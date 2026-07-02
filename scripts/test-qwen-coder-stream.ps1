# test-qwen-coder-stream.ps1
# Testa qwen/3-coder-plus-no-thinking com (1) um prompt MEDIO de auditoria (para
# tentar produzir uma resposta longa, >2000 chars, onde a janela de scan de
# getIncrementalDelta pode falhar) e (2) o caminho D: streaming SSE via hub.
# Repete o prompt medio 3x para checar intermitencia.

$ErrorActionPreference = "Continue"
$HUB = "http://127.0.0.1:3800"
$BACKEND = "http://127.0.0.1:3802"
$KEY = "orion-proxy-key"
$MODEL = "qwen/3-coder-plus-no-thinking"
$BACKEND_MODEL = "qwen3-coder-plus-no-thinking"
$OUTDIR = "C:\Users\Nilo\Documents\orion-qwen-power\tests\fixtures\qwen-coder-response-cases"
New-Item -ItemType Directory -Force -Path $OUTDIR | Out-Null

$auditPrompt = @"
Audite este script Python curto e liste, em formato de lista numerada detalhada
(pelo menos 15 itens, um por linha, cada item com 1-2 frases de explicacao),
todos os problemas potenciais de estilo, performance, seguranca e legibilidade
que voce encontrar, mesmo que pequenos. Seja exaustivo e detalhado em cada item,
nao resuma.

def process(data, u=None, cfg={}, *args, **kwargs):
    r = []
    for i in range(len(data)):
        x = data[i]
        if x != None:
            if type(x) == str:
                x = x.strip()
            try:
                y = eval(x) if isinstance(x, str) else x
            except:
                y = 0
            r.append(y)
    f = open("output.txt", "a")
    for item in r:
        f.write(str(item) + "\n")
    return r
"@

Write-Output "=== Prompt medio de auditoria (nao-streaming), 3 repeticoes, caminho B (hub) ==="
for ($i = 1; $i -le 3; $i++) {
  $body = @{ model = $MODEL; messages = @(@{role = "user"; content = $auditPrompt}); temperature = 0.1; stream = $false }
  $bodyJson = $body | ConvertTo-Json -Depth 10 -Compress
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    $resp = Invoke-WebRequest -Uri "$HUB/v1/chat/completions" -Method Post -Headers @{Authorization = "Bearer $KEY"} `
      -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyJson)) `
      -TimeoutSec 120 -ErrorAction Stop
    $sw.Stop()
    $raw = $resp.Content
    $raw | Out-File -FilePath "$OUTDIR\audit-medio-repeticao$i`__B-hub-nonstream.json" -Encoding utf8
    $parsed = $raw | ConvertFrom-Json
    $content = $parsed.choices[0].message.content
    $reasoning = $parsed.choices[0].message.reasoning_content
    $finishReason = $parsed.choices[0].finish_reason
    $tokens = $parsed.usage.completion_tokens
    Write-Output "Repeticao $i : status=$($resp.StatusCode) elapsed=$($sw.ElapsedMilliseconds)ms completion_tokens=$tokens content_length=$($content.Length) finish_reason=$finishReason reasoning_present=$([bool]$reasoning)"
    Write-Output "  content_preview: $($content.Substring(0, [Math]::Min(150, $content.Length)))"
    Write-Output "  content_tail: $($content.Substring([Math]::Max(0,$content.Length-150)))"
  } catch {
    $sw.Stop()
    Write-Output "Repeticao $i : ERRO - $($_.Exception.Message)"
    if ($_.Exception.Response) {
      try {
        $stream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $errBody = $reader.ReadToEnd()
        $errBody | Out-File -FilePath "$OUTDIR\audit-medio-repeticao$i`__B-hub-nonstream-ERROR.json" -Encoding utf8
        Write-Output "  error body: $($errBody.Substring(0, [Math]::Min(300, $errBody.Length)))"
      } catch {}
    }
  }
}

Write-Output ""
Write-Output "=== Caminho A: mesmo prompt medio, backend bruto (porta 3802) ==="
$bodyA = @{ model = $BACKEND_MODEL; messages = @(@{role = "user"; content = $auditPrompt}); temperature = 0.1; stream = $false }
$bodyAJson = $bodyA | ConvertTo-Json -Depth 10 -Compress
try {
  $respA = Invoke-WebRequest -Uri "$BACKEND/v1/chat/completions" -Method Post -Headers @{Authorization = "Bearer $KEY"} `
    -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyAJson)) `
    -TimeoutSec 120 -ErrorAction Stop
  $respA.Content | Out-File -FilePath "$OUTDIR\audit-medio__A-backend-bruto.json" -Encoding utf8
  $parsedA = $respA.Content | ConvertFrom-Json
  $contentA = $parsedA.choices[0].message.content
  Write-Output "status=$($respA.StatusCode) completion_tokens=$($parsedA.usage.completion_tokens) content_length=$($contentA.Length) finish_reason=$($parsedA.choices[0].finish_reason)"
  Write-Output "  content_preview: $($contentA.Substring(0, [Math]::Min(150, $contentA.Length)))"
} catch {
  Write-Output "ERRO caminho A: $($_.Exception.Message)"
}

Write-Output ""
Write-Output "=== Caminho D: streaming SSE via hub, prompt medio ==="
$bodyD = @{ model = $MODEL; messages = @(@{role = "user"; content = $auditPrompt}); temperature = 0.1; stream = $true }
$bodyDJson = $bodyD | ConvertTo-Json -Depth 10 -Compress
try {
  $req = [System.Net.HttpWebRequest]::Create("$HUB/v1/chat/completions")
  $req.Method = "POST"
  $req.ContentType = "application/json; charset=utf-8"
  $req.Headers.Add("Authorization", "Bearer $KEY")
  $req.Timeout = 120000
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($bodyDJson)
  $req.ContentLength = $bytes.Length
  $reqStream = $req.GetRequestStream()
  $reqStream.Write($bytes, 0, $bytes.Length)
  $reqStream.Close()
  $resp = $req.GetResponse()
  $respStream = $resp.GetResponseStream()
  $reader = New-Object System.IO.StreamReader($respStream)
  $allChunks = @()
  $accumulatedContent = ""
  $chunkCount = 0
  while (-not $reader.EndOfStream) {
    $line = $reader.ReadLine()
    if ($line -and $line.StartsWith("data: ")) {
      $chunkCount++
      $dataStr = $line.Substring(6)
      $allChunks += $dataStr
      if ($dataStr -ne "[DONE]") {
        try {
          $chunkObj = $dataStr | ConvertFrom-Json
          $deltaContent = $chunkObj.choices[0].delta.content
          if ($deltaContent) { $accumulatedContent += $deltaContent }
        } catch {}
      }
    }
  }
  $reader.Close()
  $allChunks -join "`n" | Out-File -FilePath "$OUTDIR\audit-medio__D-hub-streaming-RAW.txt" -Encoding utf8
  Write-Output "chunks recebidos: $chunkCount | content_length acumulado: $($accumulatedContent.Length)"
  Write-Output "  content_preview: $($accumulatedContent.Substring(0, [Math]::Min(150, $accumulatedContent.Length)))"
  Write-Output "  content_tail: $($accumulatedContent.Substring([Math]::Max(0,$accumulatedContent.Length-150)))"
  $accumulatedContent | Out-File -FilePath "$OUTDIR\audit-medio__D-hub-streaming-CONTENT.txt" -Encoding utf8
} catch {
  Write-Output "ERRO caminho D: $($_.Exception.Message)"
}
