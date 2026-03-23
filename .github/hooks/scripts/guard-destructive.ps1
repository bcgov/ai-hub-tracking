# guard-destructive.ps1
# preToolUse hook — denies dangerous commands that could destroy infrastructure,
# force-push history, or perform hard-resets without explicit user confirmation.

try {
    $hookInput = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $toolName = $hookInput.toolName

    # Only inspect bash tool invocations
    if ($toolName -ne 'bash') { exit 0 }

    $toolArgs = $hookInput.toolArgs | ConvertFrom-Json
    $command = $toolArgs.command

    if (-not $command) { exit 0 }

    # -- Force push ---------------------------------------------------------------
    if ($command -match 'git push.*(--force|-f)\b') {
        @{ permissionDecision = 'deny'; permissionDecisionReason = 'git force-push requires explicit user confirmation' } |
        ConvertTo-Json -Compress
        exit 0
    }

    # -- Hard reset ---------------------------------------------------------------
    if ($command -match 'git reset --hard') {
        @{ permissionDecision = 'deny'; permissionDecisionReason = 'git reset --hard requires explicit user confirmation' } |
        ConvertTo-Json -Compress
        exit 0
    }

    # -- rm -rf targeting critical top-level directories --------------------------
    if ($command -match 'rm\s+-rf\s+.*(infra-ai-hub|initial-setup|sensitive|ssl_certs|jobs|\.github)') {
        @{ permissionDecision = 'deny'; permissionDecisionReason = 'Recursive deletion of infrastructure or sensitive directories requires explicit user confirmation' } |
        ConvertTo-Json -Compress
        exit 0
    }

    # -- Terraform destroy --------------------------------------------------------
    if ($command -match 'terraform\s+destroy') {
        @{ permissionDecision = 'deny'; permissionDecisionReason = 'terraform destroy requires explicit user confirmation' } |
        ConvertTo-Json -Compress
        exit 0
    }

    # Allow all other commands
    exit 0

}
catch {
    # Never block on script error — fail open
    exit 0
}
