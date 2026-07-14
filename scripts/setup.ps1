param(
  [switch]$InstallBrowsers
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

function Require-Command($Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "$Name not found. Install it first and re-run this script."
  }
}

Require-Command node
Require-Command npm

$nodeMajor = [int]((node --version).TrimStart("v").Split(".")[0])
if ($nodeMajor -lt 20) {
  throw "Node.js 20+ is required. Current: $(node --version)"
}

Push-Location "$Root\hub"
npm install
Pop-Location

Push-Location "$Root\proxies\qwenproxy"
npm install
if ($InstallBrowsers) {
  npx playwright install chromium
}
Pop-Location

if (-not (Test-Path "$Root\hub\.env")) {
  Copy-Item "$Root\hub\.env.example" "$Root\hub\.env"
}
if (-not (Test-Path "$Root\proxies\qwenproxy\.env")) {
  Copy-Item "$Root\proxies\qwenproxy\.env.example" "$Root\proxies\qwenproxy\.env"
  (Get-Content "$Root\proxies\qwenproxy\.env") `
    -replace '^PORT=.*$', 'PORT=3802' `
    -replace '^API_KEY=.*$', 'API_KEY=orion-proxy-key' |
    Set-Content "$Root\proxies\qwenproxy\.env"
}

Write-Host "Setup complete."
Write-Host "Next:"
Write-Host "  1. Run: .\scripts\login-qwen.ps1"
Write-Host "  2. Run: .\scripts\start.ps1"
Write-Host "  3. Run: .\scripts\configure-claude.ps1"
Write-Host "  4. Run: .\scripts\install-autostart.ps1"
Write-Host "  5. Run: .\scripts\test.ps1"
