$ErrorActionPreference = "Stop"

Write-Host "Starting Orion Qwen Power..."
& "$PSScriptRoot\start.ps1"

Write-Host "Repairing Claude Code configuration..."
& "$PSScriptRoot\configure-claude.ps1" -ClearConflictingUserEnvironment

Write-Host "Installing or refreshing automatic recovery..."
& "$PSScriptRoot\install-autostart.ps1"

Write-Host "Running end-to-end tests..."
& "$PSScriptRoot\test.ps1"

Write-Host "REPAIR COMPLETED"
