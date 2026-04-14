#!/bin/bash
# PostCompact hook — re-inject critical context after context compaction

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LULU_MEMORY="${LULU_MEMORY_DIR:-$HOME/Documents/Lulu_Memory}"
SESSION_DIR="$LULU_MEMORY/session_notes/lulu"
MEMORY_DIR="$REPO_ROOT/.claude/memory"

echo "=== [Lulu PostCompact Recovery] ==="
echo ""

# 1. Core persona
echo "## Core Persona"
echo ""
cat "$REPO_ROOT/CLAUDE.md"
echo ""

# 2. Checkpoint FIRST (working state)
for cp in "$LULU_MEMORY/checkpoint.md" "$MEMORY_DIR/checkpoint.md"; do
  if [ -f "$cp" ]; then
    echo "## Checkpoint (recovered — act on this IMMEDIATELY)"
    echo ""
    cat "$cp"
    echo ""
    rm "$cp"
    break
  fi
done

# 3. Session notes (today)
TODAY=$(date +%Y-%m-%d)
if [ -f "$SESSION_DIR/$TODAY.md" ]; then
  echo "## Session Notes ($TODAY)"
  echo ""
  cat "$SESSION_DIR/$TODAY.md"
  echo ""
fi

# 4. Memory index
if [ -f "$MEMORY_DIR/MEMORY.md" ]; then
  echo "## Memory Index"
  echo ""
  cat "$MEMORY_DIR/MEMORY.md"
  echo ""
fi

echo "=== [PostCompact Recovery Complete] ==="
