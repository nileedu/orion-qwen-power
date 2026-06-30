$ErrorActionPreference = "SilentlyContinue"
function Check($Name, $Url) {
  try {
    Invoke-RestMethod -Uri $Url -TimeoutSec 5 | Out-Null
    Write-Host "OK      $Name $Url"
  } catch {
    Write-Host "FAILED  $Name $Url"
  }
}
Check "hub" "http://localhost:3800/health"
Check "qwenproxy" "http://localhost:3802/health"
try {
  Invoke-RestMethod -Uri "http://localhost:3800/v1/models" -Headers @{ Authorization = "Bearer orion-proxy-key" } -TimeoutSec 5 | ConvertTo-Json -Depth 5
} catch {
  $_.Exception.Message
}
