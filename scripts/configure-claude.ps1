param(
  [switch]$ClearConflictingUserEnvironment
)

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$fallbackModels = @(
  "qwen/3.7-max",
  "qwen/3.7-max-no-thinking",
  "qwen/3.7-plus",
  "qwen/3.7-plus-no-thinking",
  "qwen/3.6-plus",
  "qwen/coder-plus"
)

try {
  $discovered = Invoke-RestMethod -Uri "http://127.0.0.1:3800/v1/models" `
    -Headers @{ Authorization = "Bearer orion-proxy-key" } -TimeoutSec 10
  $otherModels = @($discovered.data.id | Where-Object { $_ -like "qwen/*" -and $_ -ne "qwen/3.7-max" } | Sort-Object -Unique)
  $models = @("qwen/3.7-max") + $otherModels
} catch {
  $models = $fallbackModels
  Write-Warning "Hub is offline; using the fallback model list. Run this script again after start.ps1 to discover every model."
}

function Set-JsonProperty($Object, [string]$Name, $Value) {
  if ($Object.PSObject.Properties.Name -contains $Name) {
    $Object.$Name = $Value
  } else {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
  }
}

function Update-ClaudeConfig([string]$Path, [switch]$IncludeUiSettings) {
  if (Test-Path $Path) {
    $config = Get-Content -Raw $Path | ConvertFrom-Json
    Copy-Item $Path "$Path.orion-backup-$timestamp"
  } else {
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $config = [pscustomobject]@{}
  }

  $config.PSObject.Properties.Remove("apiKeyHelper")
  if (-not ($config.PSObject.Properties.Name -contains "env")) {
    $config | Add-Member -NotePropertyName "env" -NotePropertyValue ([pscustomobject]@{})
  }

  $config.env.PSObject.Properties.Remove("ANTHROPIC_AUTH_TOKEN")
  Set-JsonProperty $config.env "ANTHROPIC_BASE_URL" "http://localhost:3800"
  Set-JsonProperty $config.env "ANTHROPIC_API_KEY" "orion-proxy-key"
  Set-JsonProperty $config.env "ANTHROPIC_MODEL" "qwen/3.7-max"
  Set-JsonProperty $config.env "CLAUDE_CODE_USE_MODEL" "qwen/3.7-max"
  Set-JsonProperty $config.env "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" "1"
  Set-JsonProperty $config.env "CLAUDE_CODE_SKIP_MODELS_CHECK" "1"

  if ($IncludeUiSettings) {
    Set-JsonProperty $config "model" "qwen/3.7-max"
    Set-JsonProperty $config "availableModels" $models
    Set-JsonProperty $config "enforceAvailableModels" $false
  }

  $config | ConvertTo-Json -Depth 100 | Set-Content -Path $Path -Encoding utf8
  Write-Host "Updated $Path"
}

Update-ClaudeConfig "$HOME\.claude\settings.json" -IncludeUiSettings
if (Test-Path "$HOME\.claude.json") {
  Update-ClaudeConfig "$HOME\.claude.json" -IncludeUiSettings
}

if ($ClearConflictingUserEnvironment) {
  [Environment]::SetEnvironmentVariable("ANTHROPIC_BASE_URL", $null, "User")
  [Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", $null, "User")
  [Environment]::SetEnvironmentVariable("ANTHROPIC_AUTH_TOKEN", $null, "User")
  Write-Host "Removed conflicting user-level Anthropic environment variables."
}

$skillSource = Join-Path (Split-Path -Parent $PSScriptRoot) "skills\configure-orion-qwen\SKILL.md"
$skillDestination = "$HOME\.claude\skills\configure-orion-qwen"
if (Test-Path $skillSource) {
  New-Item -ItemType Directory -Path $skillDestination -Force | Out-Null
  Copy-Item $skillSource (Join-Path $skillDestination "SKILL.md") -Force
  Write-Host "Installed Claude Code skill: configure-orion-qwen"
}

Remove-Item Env:ANTHROPIC_AUTH_TOKEN -ErrorAction SilentlyContinue
Write-Host "Claude Code now uses Orion Qwen through settings.json. OAuth account data was preserved."
Write-Host "Configured $($models.Count) model(s); default is qwen/3.7-max."
