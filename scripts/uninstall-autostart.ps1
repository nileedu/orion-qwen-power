$ErrorActionPreference = "Stop"
$TaskName = "Orion Qwen Power Watchdog"

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
  Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
  Write-Host "Autostart removed: $TaskName"
} else {
  Write-Host "Autostart was not installed."
}
