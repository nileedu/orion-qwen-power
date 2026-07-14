$ErrorActionPreference = "Stop"
$Headers = @{ Authorization = "Bearer orion-proxy-key"; "Content-Type" = "application/json" }

Write-Host "Testing models..."
$models = Invoke-RestMethod -Uri "http://127.0.0.1:3800/v1/models" -Headers $Headers -TimeoutSec 10
if (-not ($models.data.id -contains "qwen/3.7-max")) {
  throw "Default model qwen/3.7-max is missing from /v1/models."
}
Write-Host "OK      $($models.data.Count) model(s), default model available"

Write-Host "Testing token count..."
$anthropicBody = @{
  model = "qwen/3.7-max"
  max_tokens = 40
  messages = @(@{ role = "user"; content = "responda exatamente: CONECTADO" })
} | ConvertTo-Json -Depth 5
$tokens = Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:3800/v1/messages/count_tokens" `
  -Headers $Headers -Body $anthropicBody -TimeoutSec 10
if ($tokens.input_tokens -lt 1) { throw "Token count returned an invalid value." }
Write-Host "OK      token count $($tokens.input_tokens)"

Write-Host "Testing OpenAI chat completion..."
$openAi = Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:3800/v1/chat/completions" `
  -Headers $Headers -Body $anthropicBody -TimeoutSec 180
$openAiText = [string]$openAi.choices[0].message.content
if ($openAiText.Trim() -ne "CONECTADO") {
  throw "OpenAI chat returned unexpected content: $openAiText"
}
Write-Host "OK      OpenAI chat -> $openAiText ($($openAi.model))"

Write-Host "Testing Anthropic messages adapter..."
$anthropicHeaders = @{
  "x-api-key" = "orion-proxy-key"
  "anthropic-version" = "2023-06-01"
  "content-type" = "application/json"
}
$anthropic = Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:3800/v1/messages" `
  -Headers $anthropicHeaders -Body $anthropicBody -TimeoutSec 180
$anthropicText = [string](($anthropic.content | Where-Object { $_.type -eq "text" } | Select-Object -First 1).text)
if ($anthropicText.Trim() -ne "CONECTADO") {
  throw "Anthropic adapter returned unexpected content: $anthropicText"
}
Write-Host "OK      Anthropic messages -> $anthropicText ($($anthropic.model))"
Write-Host "ALL TESTS PASSED"
