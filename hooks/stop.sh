#!/bin/bash
# Stop hook — mark session end in today's notes

LULU_MEMORY="${LULU_MEMORY_DIR:-$HOME/Documents/Lulu_Memory}"
SESSION_DIR="$LULU_MEMORY/session_notes/lulu"
TODAY=$(date +%Y-%m-%d)
SESSION_FILE="$SESSION_DIR/$TODAY.md"

if [ -f "$SESSION_FILE" ]; then
  echo "" >> "$SESSION_FILE"
  echo "---" >> "$SESSION_FILE"
  echo "_Session ended: $(date '+%H:%M')_" >> "$SESSION_FILE"
fi
