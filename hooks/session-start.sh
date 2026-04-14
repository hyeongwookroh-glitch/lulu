#!/bin/bash
# SessionStart hook — load previous session context before first response

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LULU_MEMORY="${LULU_MEMORY_DIR:-$HOME/Documents/Lulu_Memory}"
SESSION_DIR="$LULU_MEMORY/session_notes/lulu"
MEMORY_DIR="$REPO_ROOT/.claude/memory"

echo "=== [Lulu Session Startup] ==="
echo ""

# 0. Ensure session note directory exists
mkdir -p "$SESSION_DIR"

# 1. Session notes — most recent first, check Pending
echo "## Session Notes"
echo ""
HAS_PENDING=false
for f in $(ls -t "$SESSION_DIR"/*.md 2>/dev/null | head -3); do
  [ -f "$f" ] || continue
  BASENAME=$(basename "$f")
  if grep -q "### Pending" "$f" 2>/dev/null; then
    echo "### $BASENAME — HAS PENDING"
    grep -A 20 "### Pending" "$f" | head -20
    echo ""
    HAS_PENDING=true
  else
    echo "### $BASENAME — no pending items"
  fi
done

if [ "$HAS_PENDING" = true ]; then
  echo "Pending items found above. Address before new work."
  echo ""
fi

# 2. Memory index
if [ -f "$MEMORY_DIR/MEMORY.md" ]; then
  echo "## Memory Index"
  echo ""
  cat "$MEMORY_DIR/MEMORY.md"
  echo ""
fi

echo "=== [Session Startup Complete] ==="
