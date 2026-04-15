#!/bin/bash
# PostToolUseFailure hook — track consecutive tool errors, warn on diminishing returns

AGENT_NAME="lulu"
ERROR_FILE="/tmp/${AGENT_NAME}_consecutive_errors"

COUNT=$(($(cat "$ERROR_FILE" 2>/dev/null || echo 0) + 1))
echo "$COUNT" > "$ERROR_FILE"

if [ "$COUNT" -ge 3 ]; then
  echo ""
  echo "⚠️ ${COUNT} consecutive tool errors. You may be repeating the same approach."
  echo "Try a different method or re-analyze the problem."
  echo ""
fi
