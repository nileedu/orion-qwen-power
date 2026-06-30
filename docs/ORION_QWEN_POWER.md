# Orion Qwen Power

Este documento registra a direcao do Orion Qwen depois da comparacao entre:

```text
orion-proxy-stack
johngbl/QwenBridge
JHONSSBR/qwenproxy
```

## Decisao

Manter o Orion como gateway principal e incorporar as melhores ideias dos outros projetos sem copiar binarios externos.

## Base

```text
Hub: http://localhost:3800
OpenAI API: http://localhost:3800/v1
Anthropic API: http://localhost:3800
Default model: qwen/3.7-max
API key local: orion-proxy-key
```

## O Que Ja Entrou

Do Orion original:

```text
aliases limpos qwen/...
integracao Claude Code
integracao Continue
integracao OpenCode
integracao Aider
preservacao de OAuth do Claude Code
fallback centralizado
```

Do QwenBridge:

```text
descoberta dinamica de modelos Qwen via /v1/models do qwenproxy
exposicao de todos os modelos qwen* como qwen/...
endpoint Anthropic /v1/messages
endpoint Anthropic /v1/messages/count_tokens
limite de payload no hub
timeout dinamico por tamanho de payload/modelo
metricas Prometheus em /metrics
rota /v1/chat/completions/stop
rota /v1/upload proxyada para Qwen
```

Do JHONSSBR/qwenproxy:

```text
qwenproxy como backend local moderno
direct fetch/browser fallback no backend Qwen
health/watchdog/cooldown/stream handling no lane Qwen
modelo futuro de GUI propria para contas, logs, streams e diagnostico
```

## Endpoints

```text
GET  /health
GET  /metrics
GET  /v1/models
GET  /v1/health/models
POST /v1/chat/completions
POST /v1/chat/completions/stop
POST /v1/messages
POST /v1/messages/count_tokens
POST /v1/upload
```

## Modelo De Nome

O backend Qwen usa nomes como:

```text
qwen3.7-max
qwen3.7-plus
qwen3-coder-plus
```

O hub expoe nomes limpos:

```text
qwen/3.7-max
qwen/3.7-plus
qwen/coder-plus
```

OpenCode usa formato provider/model:

```text
orion/qwen/3.7-max
```

Aider usa:

```text
openai/qwen/3.7-max
```

Claude Code, Continue, Cline, Roo e Kilo usam:

```text
qwen/3.7-max
```

## Proximo Passo

Criar uma GUI propria do Orion, sem copiar executavel externo, com:

```text
status do hub
status dos backends
lista dinamica de modelos
logs
streams ativos
atalhos para Claude Code, Continue e OpenCode
configuracao segura de contas Qwen
diagnostico de OAuth/API key
```

