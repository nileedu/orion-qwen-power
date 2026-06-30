#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_BROWSERS="${INSTALL_BROWSERS:-0}"

command -v node >/dev/null || { echo "node not found"; exit 1; }
command -v npm >/dev/null || { echo "npm not found"; exit 1; }

NODE_MAJOR="$(node --version | sed 's/^v//' | cut -d. -f1)"
if [ "$NODE_MAJOR" -lt 20 ]; then
  echo "Node.js 20+ is required. Current: $(node --version)"
  exit 1
fi

(cd "$ROOT/hub" && npm install)
(cd "$ROOT/proxies/qwenproxy" && npm install && { [ "$INSTALL_BROWSERS" = "1" ] && npx playwright install chromium || true; })

[ -f "$ROOT/hub/.env" ] || cp "$ROOT/hub/.env.example" "$ROOT/hub/.env"
if [ ! -f "$ROOT/proxies/qwenproxy/.env" ]; then
  cp "$ROOT/proxies/qwenproxy/.env.example" "$ROOT/proxies/qwenproxy/.env"
  sed -i.bak -e 's/^PORT=.*/PORT=3802/' -e 's/^API_KEY=.*/API_KEY=orion-proxy-key/' "$ROOT/proxies/qwenproxy/.env"
  rm -f "$ROOT/proxies/qwenproxy/.env.bak"
fi

echo "Setup complete."
echo "Next:"
echo "  1. ./scripts/login-qwen.sh"
echo "  2. ./scripts/start.sh"
echo "  3. ./scripts/test.sh"
