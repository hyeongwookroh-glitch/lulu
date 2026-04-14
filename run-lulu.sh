#!/bin/bash
# Lulu — Claude Code session start script (auto-restart wrapper)
cd "$(dirname "$0")"

while true; do
  claude \
    --model opus \
    --effort max \
    --dangerously-skip-permissions \
    --strict-mcp-config --mcp-config .mcp-lulu.json \
    --dangerously-load-development-channels server:lulu
  EXIT_CODE=$?
  echo "[$(date)] Lulu exited (code: $EXIT_CODE), restarting in 3s..."
  sleep 3
done
