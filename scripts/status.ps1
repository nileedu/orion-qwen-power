$ErrorActionPreference = "SilentlyContinue"
$failed = $false

function Check([string]$Name, [string]$Url) {
  try {
    Invoke-RestMethod -Uri $Url -TimeoutSec 5 | Out-Null
    Write-Host "OK      $Name $Url"
  } catch {
    Write-Host "FAILED  $Name $Url"
    $script:failed = $true
  }
}

Check "hub" "http://127.0.0.1:3800/health"
Check "qwenproxy" "http://127.0.0.1:3802/health"

$task = Get-ScheduledTask -TaskName "Orion Qwen Power Watchdog" -ErrorAction SilentlyContinue
if ($task) {
  Write-Host "OK      watchdog task $($task.State)"
} else {
  Write-Host "INFO    watchdog task not installed"
}

try {
  $models = Invoke-RestMethod -Uri "http://127.0.0.1:3800/v1/models" `
    -Headers @{ Authorization = "Bearer orion-proxy-key" } -TimeoutSec 10
  Write-Host "OK      models $($models.data.Count) available"
} catch {
  Write-Host "FAILED  models $($_.Exception.Message)"
  $failed = $true
}

if ($failed) { exit 1 }
