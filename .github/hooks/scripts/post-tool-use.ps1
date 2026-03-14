<#
.SYNOPSIS
  postToolUse hook: run full pre-commit validation suite on the affected package after every
  Python or TypeScript file edit or create.

.DESCRIPTION
  Packages covered:
    - tenant-onboarding-portal/backend  -> ESLint + Prettier
    - tenant-onboarding-portal/frontend -> ESLint + Prettier
    - jobs/apim-key-rotation            -> ruff lint + format check + pytest + docs build
    - pii-redaction-service             -> ruff lint + format check + pytest + docs build

  Checks run in order: lint -> format:check -> tests -> docs build (Python packages).
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

    # Only process TypeScript/JavaScript or Python files
    if ($filePath -notmatch '\.(ts|tsx|js|jsx|py)$') {
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

    # key-rotation function — mirrors .pre-commit-config.yaml: key-rotation-lint + key-rotation-tests + key-rotation-docs
    if ($filePath -match 'jobs/apim-key-rotation|jobs\\apim-key-rotation') {
        "=== Key Rotation pre-commit checks: $filePath @ $(Get-Date) ===" | Add-Content $log
        $keyRotDir = Join-Path $repoRoot "jobs/apim-key-rotation"

        function Invoke-UvCheck {
            param([string]$Label, [string[]]$Args, [string]$Dir)
            "--- $Label ---" | Add-Content $log
            Push-Location $Dir
            $output = uv run @Args 2>&1
            $output | Add-Content $log
            if ($LASTEXITCODE -eq 0) { "--- $Label PASSED ---" | Add-Content $log }
            else                      { "--- $Label FAILED ---" | Add-Content $log }
            Pop-Location
            "" | Add-Content $log
        }

        Invoke-UvCheck -Label "ruff check"         -Args @('ruff', 'check', '.')             -Dir $keyRotDir
        Invoke-UvCheck -Label "ruff format:check"  -Args @('ruff', 'format', '--check', '.') -Dir $keyRotDir
        Invoke-UvCheck -Label "pytest"             -Args @('pytest')                         -Dir $keyRotDir

        "--- docs build ---" | Add-Content $log
        $out = bash docs/build.sh 2>&1
        $out | Add-Content $log
        if ($LASTEXITCODE -eq 0) { "--- docs build PASSED ---" | Add-Content $log }
        else                      { "--- docs build FAILED ---" | Add-Content $log }
        "" | Add-Content $log

        $ranCheck = $true
    }

    # pii-redaction-service — mirrors .pre-commit-config.yaml: pii-redaction-lint + pii-redaction-tests + pii-redaction-docs
    if ($filePath -match 'pii-redaction-service') {
        "=== PII Redaction Service pre-commit checks: $filePath @ $(Get-Date) ===" | Add-Content $log
        $piiDir = Join-Path $repoRoot "pii-redaction-service"

        if (-not (Get-Command 'Invoke-UvCheck' -ErrorAction SilentlyContinue)) {
            function Invoke-UvCheck {
                param([string]$Label, [string[]]$Args, [string]$Dir)
                "--- $Label ---" | Add-Content $log
                Push-Location $Dir
                $output = uv run @Args 2>&1
                $output | Add-Content $log
                if ($LASTEXITCODE -eq 0) { "--- $Label PASSED ---" | Add-Content $log }
                else                      { "--- $Label FAILED ---" | Add-Content $log }
                Pop-Location
                "" | Add-Content $log
            }
        }

        Invoke-UvCheck -Label "ruff check"         -Args @('ruff', 'check', '.')             -Dir $piiDir
        Invoke-UvCheck -Label "ruff format:check"  -Args @('ruff', 'format', '--check', '.') -Dir $piiDir
        Invoke-UvCheck -Label "pytest"             -Args @('pytest')                         -Dir $piiDir

        "--- docs build ---" | Add-Content $log
        $out = bash docs/build.sh 2>&1
        $out | Add-Content $log
        if ($LASTEXITCODE -eq 0) { "--- docs build PASSED ---" | Add-Content $log }
        else                      { "--- docs build FAILED ---" | Add-Content $log }
        "" | Add-Content $log

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
