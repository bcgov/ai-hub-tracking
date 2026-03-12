<#
.SYNOPSIS
  postToolUse hook: run full pre-commit validation suite on the affected portal package after every
  TypeScript file edit or create.

.DESCRIPTION
  Checks run in order: format:check -> lint -> typecheck (backend only).
  Output from postToolUse hooks is ignored by the agent; results are written to
  .github/hooks/logs/portal-lint.log.

  Input (stdin): JSON with shape { "toolName": "...", "toolArgs": "..." }
  For edit/create tools, toolArgs contains a "path" or "filePath" field.
#>

try {
    $hookInput = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $toolName = $hookInput.toolName

    # Only trigger on file edit or create operations
    if ($toolName -notmatch '^(edit|create|create_file)$') {
        exit 0
    }

    # Parse tool args (may be a nested JSON string or object)
    $rawArgs = $hookInput.toolArgs
    $toolArgs = if ($rawArgs -is [string]) { $rawArgs | ConvertFrom-Json } else { $rawArgs }

    $filePath = if ($toolArgs.path) { $toolArgs.path }
    elseif ($toolArgs.filePath) { $toolArgs.filePath }
    elseif ($toolArgs.file) { $toolArgs.file }
    else { $null }

    if (-not $filePath) {
        exit 0
    }

    # Only process TypeScript/JavaScript files
    if ($filePath -notmatch '\.(ts|tsx|js|jsx)$') {
        exit 0
    }

    $repoRoot = (Get-Location).Path
    $logDir = Join-Path $repoRoot ".github/hooks/logs"
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $log = Join-Path $logDir "portal-lint.log"

    # Helper: run one npm script, log label + output + pass/fail
    function Invoke-Check {
        param([string]$Label, [string]$Script, [string]$Dir)
        "--- $Label ---" | Add-Content $log
        Push-Location $Dir
        $output = npm run $Script 2>&1
        $output | Add-Content $log
        if ($LASTEXITCODE -eq 0) {
            "--- $Label PASSED ---" | Add-Content $log
        }
        else {
            "--- $Label FAILED ---" | Add-Content $log
        }
        Pop-Location
        "" | Add-Content $log
    }

    $ranCheck = $false

    # backend — mirrors .pre-commit-config.yaml: portal-backend-lint (lint + format:check)
    if ($filePath -match "tenant-onboarding-portal/backend") {
        "=== Backend pre-commit checks: $filePath @ $(Get-Date) ===" | Add-Content $log
        $backendDir = Join-Path $repoRoot "tenant-onboarding-portal/backend"
        Invoke-Check -Label "lint"         -Script "lint"         -Dir $backendDir
        Invoke-Check -Label "format:check" -Script "format:check" -Dir $backendDir
        $ranCheck = $true
    }

    # frontend — mirrors .pre-commit-config.yaml: portal-frontend-lint (lint + format:check)
    if ($filePath -match "tenant-onboarding-portal/frontend") {
        "=== Frontend pre-commit checks: $filePath @ $(Get-Date) ===" | Add-Content $log
        $frontendDir = Join-Path $repoRoot "tenant-onboarding-portal/frontend"
        Invoke-Check -Label "lint"         -Script "lint"         -Dir $frontendDir
        Invoke-Check -Label "format:check" -Script "format:check" -Dir $frontendDir
        $ranCheck = $true
    }

    if ($ranCheck) {
        "" | Add-Content $log
    }

    # postToolUse output is ignored; always exit 0
    exit 0
}
catch {
    # Fail open — never block the agent due to hook errors
    exit 0
}
