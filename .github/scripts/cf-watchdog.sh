#!/usr/bin/env bash
# Watchdog: automatically restarts cloudflared tunnel if it dies
while true; do
  sleep 15
  pgrep -f 'cloudflared tunnel --url http://localhost:8000' > /dev/null || \
    nohup cloudflared tunnel --url http://localhost:8000 >> cloudflared.log 2>&1 &
  pgrep -f 'cloudflared tunnel --url http://localhost:3000' > /dev/null || \
    nohup cloudflared tunnel --url http://localhost:3000 >> cloudflared-upload.log 2>&1 &
done
