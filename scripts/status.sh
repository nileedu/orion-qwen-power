#!/usr/bin/env bash
set +e
check() {
  name="$1"
  url="$2"
  if curl -fsS --max-time 5 "$url" >/dev/null; then
    echo "OK      $name $url"
  else
    echo "FAILED  $name $url"
  fi
}
check hub http://localhost:3800/health
check qwenproxy http://localhost:3802/health
curl -fsS --max-time 5 http://localhost:3800/v1/models -H "Authorization: Bearer orion-proxy-key"
