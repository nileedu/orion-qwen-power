#!/usr/bin/env bash
set +e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for f in "$ROOT/logs/hub.pid" "$ROOT/logs/qwenproxy.pid"; do
  [ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null && rm -f "$f"
done
echo "Stopped known Orion Qwen processes."
