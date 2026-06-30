#!/usr/bin/env bash
set -euo pipefail

echo "Testing models..."
curl -fsS http://localhost:3800/v1/models -H "Authorization: Bearer orion-proxy-key"

echo
echo "Testing token count..."
curl -fsS http://localhost:3800/v1/messages/count_tokens \
  -H "Authorization: Bearer orion-proxy-key" \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen/3.7-max","max_tokens":20,"messages":[{"role":"user","content":"responda: CONECTADO"}]}'

echo
echo "Testing chat completion..."
curl -fsS http://localhost:3800/v1/chat/completions \
  -H "Authorization: Bearer orion-proxy-key" \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen/3.7-max","max_tokens":40,"messages":[{"role":"user","content":"responda exatamente: CONECTADO"}]}'
