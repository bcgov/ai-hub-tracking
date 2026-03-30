#!/usr/bin/env pwsh
# =============================================================================
# bastion-proxy.ps1 — SOCKS5 proxy via Azure Bastion
# =============================================================================
#
# Creates a SOCKS5 proxy on your local machine by tunnelling through Azure
# Bastion to the jumpbox VM.  All traffic routed through the proxy is resolved
# and forwarded by the jumpbox, giving access to private PaaS endpoints
# without a VPN.
#
# PREREQUISITES
#   Azure CLI:         https://learn.microsoft.com/cli/azure/install-azure-cli
#   bastion extension: az extension add --name bastion
#   ssh extension:     az extension add --name ssh   (AAD auth only)
#   Standard SKU Azure Bastion with native tunnelling enabled
#   "Virtual Machine Administrator Login" RBAC role on the VM (AAD auth)
#
# IMPORTANT — BROWSER AUTHENTICATION
#   When the device code URL appears, open it in an Incognito / Private Browsing
#   window. If you use a regular browser tab, the browser may silently sign in
#   with a cached personal Microsoft account and authenticate as the wrong user.
#
#   Chrome/Edge: Ctrl+Shift+N  |  Firefox: Ctrl+Shift+P
#
# USAGE
#   .\scripts\bastion-proxy.ps1 -ResourceGroup <rg> -BastionName <name> -VmName <vm>
#
# EXAMPLES
#   # Entra ID (AAD) auth — recommended:
#   .\scripts\bastion-proxy.ps1 -ResourceGroup ai-hub-tools -BastionName ai-hub-bastion -VmName ai-hub-jumpbox
#
#   # SSH key auth — break-glass fallback:
#   .\scripts\bastion-proxy.ps1 -ResourceGroup ai-hub-tools -BastionName ai-hub-bastion -VmName ai-hub-jumpbox `
#     -AuthType ssh-key -Username <admin_username> -SshKey ..\sensitive\jumpbox_ssh_key.pem
#
# =============================================================================

[CmdletBinding()]
param(
    [Alias('g')]
    [Parameter(Mandatory)]
    [string]$ResourceGroup,

    [Alias('b')]
    [Parameter(Mandatory)]
    [string]$BastionName,

    [Alias('v')]
    [Parameter(Mandatory)]
    [string]$VmName,

    [Alias('p')]
    [int]$Port = 8228,

    [ValidateSet('AAD', 'ssh-key')]
    [string]$AuthType = 'AAD',

    [string]$SshKey = '',

    [string]$Username = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Constants ─────────────────────────────────────────────────────────────────

$SUBSCRIPTION_ID = 'eb733692-257d-40c8-bd7b-372e689f3b7f'
$LOGIN_TIMEOUT = 300   # max seconds to wait for device code login

# ── Helpers ───────────────────────────────────────────────────────────────────

function Write-Info { param([string]$Msg) Write-Host "[INFO]  $Msg" -ForegroundColor Cyan }
function Write-Ok { param([string]$Msg) Write-Host "[ OK ]  $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "[WARN]  $Msg" -ForegroundColor Yellow }
function Write-Err { param([string]$Msg) Write-Host "[ERROR] $Msg" -ForegroundColor Red }

# ── Validate ssh-key arguments ────────────────────────────────────────────────

if ($AuthType -eq 'ssh-key') {
    if (-not $SshKey) { Write-Err '-SshKey is required for -AuthType ssh-key'; exit 1 }
    if (-not $Username) { Write-Err '-Username is required for -AuthType ssh-key'; exit 1 }
    if (-not (Test-Path $SshKey)) { Write-Err "SSH key file not found: $SshKey"; exit 1 }
}

# ── Port utilities ────────────────────────────────────────────────────────────

function Test-PortInUse {
    param([int]$TestPort)
    $listening = netstat -ano 2>$null | Select-String "TCP\s+[0-9.:]+:${TestPort}\s+[0-9.:]+\s+LISTENING"
    return [bool]$listening
}

function Find-FreePort {
    param([int]$StartPort)
    $limit = $StartPort + 50
    for ($p = $StartPort; $p -le $limit; $p++) {
        if (-not (Test-PortInUse $p)) { return $p }
    }
    Write-Err "No free port found in range $StartPort–$limit"
    exit 1
}

# ── Prerequisite checks ───────────────────────────────────────────────────────

Write-Info 'Checking prerequisites...'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Err 'Azure CLI (az) is not installed.'
    Write-Err 'Install: https://learn.microsoft.com/cli/azure/install-azure-cli'
    exit 1
}

$null = az extension show --name bastion 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Info "Installing Azure CLI 'bastion' extension..."
    az extension add --name bastion --yes 2>&1 | Out-Null
}

if ($AuthType -eq 'AAD') {
    $null = az extension show --name ssh 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Installing Azure CLI 'ssh' extension..."
        az extension add --name ssh --yes 2>&1 | Out-Null
    }
}

Write-Ok 'Prerequisites satisfied'

# ── Authentication ────────────────────────────────────────────────────────────

Write-Info 'Checking Azure CLI login status...'
$null = az account show 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host ''
    Write-Info 'Not logged in. Starting device code authentication...'
    Write-Host ''
    Write-Warn 'BROWSER TIP: Open the device code URL in an Incognito / Private Browsing'
    Write-Warn '             window to prevent the browser signing in as the wrong account.'
    Write-Warn '             Chrome/Edge: Ctrl+Shift+N  |  Firefox: Ctrl+Shift+P'
    Write-Host ''
    az login --use-device-code
    Write-Host ''
    Write-Info 'Waiting for login to complete...'
    $elapsed = 0
    while ($true) {
        Start-Sleep -Seconds 2
        $null = az account show 2>$null
        if ($LASTEXITCODE -eq 0) { break }
        $elapsed += 2
        if ($elapsed -ge $LOGIN_TIMEOUT) {
            Write-Err "Login timed out after ${LOGIN_TIMEOUT}s"
            exit 1
        }
    }
}
else {
    Write-Warn 'Already logged in. Azure CLI sessions expire 12h after az login.'
    Write-Warn 'Re-run this script if you encounter authentication errors.'
}

$loginEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$expireEpoch = $loginEpoch + 43200
$loginAt = Get-Date -Format 'HH:mm zzz'
$expireAt = (Get-Date).AddHours(12).ToString('HH:mm zzz')

Write-Ok 'Authenticated to Azure CLI'

# ── Subscription ──────────────────────────────────────────────────────────────

Write-Info "Switching to subscription $SUBSCRIPTION_ID..."
az account set --subscription $SUBSCRIPTION_ID 2>&1 | Out-Null
$subName = az account show --query name --output tsv
Write-Ok "Using: $subName ($SUBSCRIPTION_ID)"

# ── Resolve VM resource ID ────────────────────────────────────────────────────

Write-Info "Resolving VM '$VmName' in resource group '$ResourceGroup'..."
$vmId = az vm show --name $VmName --resource-group $ResourceGroup --query id --output tsv 2>$null
if ($LASTEXITCODE -ne 0 -or -not $vmId) {
    Write-Err "VM '$VmName' not found in resource group '$ResourceGroup'"
    exit 1
}
Write-Ok 'VM found'

# ── VM running check ──────────────────────────────────────────────────────────

$vmState = az vm get-instance-view `
    --name $VmName `
    --resource-group $ResourceGroup `
    --query "instanceView.statuses[?contains(code,'PowerState')].displayStatus | [0]" `
    --output tsv 2>$null

if ($vmState -ne 'VM running') {
    Write-Warn "VM is not running (current state: $($vmState ?? 'unknown'))"
    $answer = Read-Host '  Start the VM now? [y/N]'
    if ($answer.ToLower() -eq 'y') {
        Write-Info 'Starting VM...'
        az vm start --name $VmName --resource-group $ResourceGroup 2>&1 | Out-Null
        Write-Info 'Waiting for VM to reach running state...'
        az vm wait --name $VmName --resource-group $ResourceGroup `
            --custom "instanceView.statuses[?code=='PowerState/running']" 2>&1 | Out-Null
        Write-Ok 'VM is running'
    }
    else {
        Write-Err 'VM must be running to create a proxy tunnel. Exiting.'
        exit 1
    }
}

# ── Bastion health check ──────────────────────────────────────────────────────

Write-Info "Checking Bastion host '$BastionName'..."
$bastionState = az network bastion show `
    --name $BastionName `
    --resource-group $ResourceGroup `
    --query provisioningState `
    --output tsv 2>$null

if ($LASTEXITCODE -ne 0 -or -not $bastionState) {
    Write-Err "Bastion '$BastionName' not found in resource group '$ResourceGroup'"
    exit 1
}

switch ($bastionState) {
    'Succeeded' {
        Write-Ok 'Bastion is ready'
    }
    { $_ -in @('Updating', 'Creating') } {
        Write-Info "Bastion is provisioning (state: $bastionState). Waiting..."
        while ($true) {
            Start-Sleep -Seconds 15
            $bastionState = az network bastion show --name $BastionName --resource-group $ResourceGroup --query provisioningState --output tsv 2>$null
            if ($bastionState -eq 'Succeeded') { Write-Ok 'Bastion is ready'; break }
            if ($bastionState -eq 'Failed') {
                Write-Err 'Bastion provisioning failed. Check the Azure portal.'
                exit 1
            }
        }
    }
    default {
        Write-Err "Bastion is in unexpected state: '$bastionState'. Check the Azure portal."
        exit 1
    }
}

# ── Port selection ────────────────────────────────────────────────────────────

$socksPort = Find-FreePort $Port
if ($socksPort -ne $Port) {
    Write-Warn "Port $Port is in use. Using port $socksPort instead."
}

# ── Print proxy connection details ────────────────────────────────────────────

Write-Host ''
Write-Host "  SOCKS5 proxy ready on localhost:$socksPort" -ForegroundColor Green -BackgroundColor Black
Write-Host ''
Write-Host "  `$env:HTTPS_PROXY = 'socks5://localhost:$socksPort'"
Write-Host "  `$env:HTTP_PROXY  = 'socks5://localhost:$socksPort'"
Write-Host ''
Write-Host "  Or per-command:  curl --socks5-hostname localhost:$socksPort <url>"
Write-Host ''
Write-Host "  Session started : $loginAt"
Write-Host "  Session expires : $expireAt  (Entra ID 12h limit)"
Write-Host '  You will be warned 1 hour before expiry; the tunnel stops at expiry.'
Write-Host ''
Write-Host "  Connecting via Bastion (auth: $AuthType). Press Ctrl+C to stop."
Write-Host ''

# ── Build az argument array ───────────────────────────────────────────────────
#
# Arguments after '--' are passed directly to the underlying SSH client:
#   -D  SOCKS5 dynamic port forwarding on the chosen local port
#   -N  do not execute a remote command (keep connection open for forwarding)
#   -q  quiet mode (suppress banners and warnings)
#   StrictHostKeyChecking=no   Bastion already provides mutual auth
#   ServerAliveInterval/Count  keep the tunnel alive through idle periods

$sshOptsStr = "-D $socksPort -N -q -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -o ServerAliveCountMax=3"

if ($AuthType -eq 'AAD') {
    $azCmdLine = "network bastion ssh --name `"$BastionName`" --resource-group `"$ResourceGroup`" --target-resource-id `"$vmId`" --auth-type AAD -- $sshOptsStr"
}
else {
    $azCmdLine = "network bastion ssh --name `"$BastionName`" --resource-group `"$ResourceGroup`" --target-resource-id `"$vmId`" --auth-type ssh-key --username `"$Username`" --ssh-key `"$SshKey`" -- $sshOptsStr"
}

# ── Write temp batch file to avoid cmd /c quoting issues ─────────────────────
#
# Writing a .bat avoids the cmd.exe quoting edge-cases that arise when az.cmd
# (which lives in a path with spaces) is passed as an argument to /c.

$tempBat = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.bat')
"@az $azCmdLine" | Set-Content -Path $tempBat -Encoding ASCII

# ── Start az process (inherit console so output flows through) ────────────────
#
# Start-Process with -NoNewWindow and no stream redirection means the child
# inherits our stdin/stdout/stderr — az output appears in this terminal.
# -PassThru gives us the process object for the timer kill.

$proc = Start-Process -FilePath 'cmd.exe' `
    -ArgumentList "/c `"$tempBat`"" `
    -NoNewWindow -PassThru

# ── Session expiry timer (background runspace) ────────────────────────────────
#
# Runs in a separate runspace so it doesn't block WaitForExit below.
# On expiry it kills the entire process tree via taskkill /T.

$runspace = [runspacefactory]::CreateRunspace()
$runspace.Open()
$rsPs = [powershell]::Create()
$rsPs.Runspace = $runspace
$null = $rsPs.AddScript({
        param([long]$ExpireEpoch, [int]$ProcId)
        $warned = $false
        $warnEpoch = $ExpireEpoch - 3600
        while ($true) {
            Start-Sleep -Seconds 60
            $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            if ($now -ge $ExpireEpoch) {
                [Console]::Error.WriteLine('')
                [Console]::Error.WriteLine('[ERROR] Azure CLI session has expired (12h limit). Stopping proxy.')
                [Console]::Error.WriteLine('[ERROR] Re-run the script to re-authenticate.')
                $null = & taskkill /F /T /PID $ProcId 2>$null
                break
            }
            elseif ($now -ge $warnEpoch -and -not $warned) {
                $warned = $true
                [Console]::Error.WriteLine('')
                [Console]::Error.WriteLine('[WARN]  Azure CLI session expires in ~60 minutes. Restart the script soon.')
            }
        }
    }).AddParameters(@{ ExpireEpoch = $expireEpoch; ProcId = $proc.Id })
$rsHandle = $rsPs.BeginInvoke()

# ── Wait for proxy process to exit ────────────────────────────────────────────

try {
    $proc.WaitForExit()
    $exitCode = $proc.ExitCode
}
finally {
    # Stop the timer runspace
    try { $rsPs.Stop() } catch {}
    try { $rsPs.Dispose() } catch {}
    try { $runspace.Dispose() } catch {}

    # Ensure process tree is dead (idempotent if already exited)
    if (-not $proc.HasExited) {
        $null = & taskkill /F /T /PID $proc.Id 2>$null
    }
    $proc.Dispose()

    Remove-Item $tempBat -Force -ErrorAction SilentlyContinue

    Write-Host ''
    if ($null -eq $exitCode -or $exitCode -eq 0 -or $exitCode -eq 130) {
        Write-Ok 'SOCKS5 proxy stopped.'
    }
    else {
        Write-Warn "SOCKS5 proxy exited with code $exitCode."
    }
}
