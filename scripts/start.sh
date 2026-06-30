#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT/logs"
mkdir -p "$LOG_DIR"

(cd "$ROOT/proxies/qwenproxy" && PORT=3802 API_KEY=orion-proxy-key nohup npm run start > "$LOG_DIR/qwenproxy.log" 2>&1 & echo $! > "$LOG_DIR/qwenproxy.pid")
sleep 3
(cd "$ROOT/hub" && PORT=3800 HOST=127.0.0.1 HUB_API_KEY=orion-proxy-key QWENPROXY_URL=http://localhost:3802 QWENPROXY_KEY=orion-proxy-key nohup npm run start > "$LOG_DIR/hub.log" 2>&1 & echo $! > "$LOG_DIR/hub.pid")

echo "Started qwenproxy on :3802 and hub on :3800"
echo "Logs: $LOG_DIR"
