$ErrorActionPreference = "Stop"
$Headers = @{ Authorization = "Bearer orion-proxy-key"; "Content-Type" = "application/json" }

Write-Host "Testing models..."
Invoke-RestMethod -Uri "http://localhost:3800/v1/models" -Headers $Headers -TimeoutSec 10 | ConvertTo-Json -Depth 5

Write-Host "Testing token count..."
$anthropicBody = @{
  model = "qwen/3.7-max"
  max_tokens = 20
  messages = @(@{ role = "user"; content = "responda: CONECTADO" })
} | ConvertTo-Json -Depth 5
Invoke-RestMethod -Method Post -Uri "http://localhost:3800/v1/messages/count_tokens" -Headers $Headers -Body $anthropicBody -TimeoutSec 10 | ConvertTo-Json -Depth 5

Write-Host "Testing chat completion..."
$body = @{
  model = "qwen/3.7-max"
  max_tokens = 40
  messages = @(@{ role = "user"; content = "responda exatamente: CONECTADO" })
} | ConvertTo-Json -Depth 5
Invoke-RestMethod -Method Post -Uri "http://localhost:3800/v1/chat/completions" -Headers $Headers -Body $body -TimeoutSec 180 | ConvertTo-Json -Depth 10
