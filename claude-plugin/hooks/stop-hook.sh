#!/bin/bash

# Autoresearch Loop Stop Hook
# Prevents session exit when an autoresearch loop is active.
# Re-injects the continuation prompt to keep the loop running.
#
# Adapted from ralph-loop's stop-hook.sh with autoresearch-specific
# additions: flow-check integration, previous_outcome tracking,
# completion promise support, and config re-injection.

set -euo pipefail

HOOK_INPUT=$(cat)

STATE_FILE=".claude/autoresearch-loop.local.md"

if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

# Parse YAML frontmatter (between --- delimiters)
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")

extract_field() {
  local field="$1"
  echo "$FRONTMATTER" | grep "^${field}:" | sed "s/^${field}: *//" | sed 's/^"\(.*\)"$/\1/'
}

ITERATION=$(extract_field "iteration")
MAX_ITERATIONS=$(extract_field "max_iterations")
COMPLETION_PROMISE=$(extract_field "completion_promise")
PREVIOUS_OUTCOME=$(extract_field "previous_outcome")

# Session isolation: only block the session that started the loop
STATE_SESSION=$(extract_field "session_id" || true)
HOOK_SESSION=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""')
if [[ -n "$STATE_SESSION" ]] && [[ "$STATE_SESSION" != "$HOOK_SESSION" ]]; then
  exit 0
fi

# Validate numeric fields
if [[ ! "$ITERATION" =~ ^[0-9]+$ ]]; then
  echo "Warning: autoresearch state file corrupted (iteration='$ITERATION'). Removing state and allowing exit." >&2
  rm "$STATE_FILE"
  exit 0
fi

if [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "Warning: autoresearch state file corrupted (max_iterations='$MAX_ITERATIONS'). Removing state and allowing exit." >&2
  rm "$STATE_FILE"
  exit 0
fi

# Check max iterations (0 = unlimited)
if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
  echo "Autoresearch: max iterations ($MAX_ITERATIONS) reached." >&2
  rm "$STATE_FILE"
  exit 0
fi

# Get transcript path
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path')

if [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  echo "Warning: autoresearch transcript not found at $TRANSCRIPT_PATH. Removing state and allowing exit." >&2
  rm "$STATE_FILE"
  exit 0
fi

# Extract last assistant text block from transcript (JSONL)
if ! grep -q '"role":"assistant"' "$TRANSCRIPT_PATH"; then
  echo "Warning: no assistant messages in transcript. Removing state and allowing exit." >&2
  rm "$STATE_FILE"
  exit 0
fi

LAST_LINES=$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" | tail -n 100)
if [[ -z "$LAST_LINES" ]]; then
  echo "Warning: failed to extract assistant messages. Removing state and allowing exit." >&2
  rm "$STATE_FILE"
  exit 0
fi

set +e
LAST_OUTPUT=$(echo "$LAST_LINES" | jq -rs '
  map(.message.content[]? | select(.type == "text") | .text) | last // ""
' 2>&1)
JQ_EXIT=$?
set -e

if [[ $JQ_EXIT -ne 0 ]]; then
  echo "Warning: failed to parse transcript JSON. Removing state and allowing exit." >&2
  rm "$STATE_FILE"
  exit 0
fi

# Check completion promise
if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  PROMISE_TEXT=$(echo "$LAST_OUTPUT" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")

  if [[ -n "$PROMISE_TEXT" ]] && [[ "$PROMISE_TEXT" = "$COMPLETION_PROMISE" ]]; then
    echo "Autoresearch: completion promise met." >&2
    rm "$STATE_FILE"
    exit 0
  fi
fi

# Run flow-check if available and iteration > 0
FLOW_WARNINGS=""
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ $ITERATION -gt 0 ]] && [[ -f "$HOOK_DIR/flow-check.sh" ]]; then
  set +e
  FLOW_WARNINGS=$(bash "$HOOK_DIR/flow-check.sh" "$STATE_FILE" 2>&1)
  set -e
fi

# Continue loop: increment iteration, update previous_outcome, reset flags
NEXT_ITERATION=$((ITERATION + 1))
CURRENT_HEAD=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

TEMP_FILE="${STATE_FILE}.tmp.$$"
sed \
  -e "s/^iteration: .*/iteration: $NEXT_ITERATION/" \
  -e "s/^commit_before: .*/commit_before: $CURRENT_HEAD/" \
  -e "s/^verified: .*/verified: false/" \
  -e "s/^guard_checked: .*/guard_checked: false/" \
  -e "s/^research_done: .*/research_done: false/" \
  "$STATE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$STATE_FILE"

# Extract prompt body (everything after closing ---)
PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$STATE_FILE")

if [[ -z "$PROMPT_TEXT" ]]; then
  echo "Warning: autoresearch state file has no prompt body. Removing state and allowing exit." >&2
  rm "$STATE_FILE"
  exit 0
fi

# Build system message
SYSTEM_MSG="Autoresearch iteration $NEXT_ITERATION"
if [[ $MAX_ITERATIONS -gt 0 ]]; then
  SYSTEM_MSG="$SYSTEM_MSG / $MAX_ITERATIONS"
fi
if [[ -n "$PREVIOUS_OUTCOME" ]] && [[ "$PREVIOUS_OUTCOME" != "null" ]]; then
  SYSTEM_MSG="$SYSTEM_MSG | Previous: $PREVIOUS_OUTCOME"
fi
if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  SYSTEM_MSG="$SYSTEM_MSG | To stop: output <promise>$COMPLETION_PROMISE</promise> (ONLY when TRUE)"
fi
if [[ -n "$FLOW_WARNINGS" ]]; then
  SYSTEM_MSG="$SYSTEM_MSG | Flow-check warnings: $FLOW_WARNINGS"
fi

jq -n \
  --arg prompt "$PROMPT_TEXT" \
  --arg msg "$SYSTEM_MSG" \
  '{
    "decision": "block",
    "reason": $prompt,
    "systemMessage": $msg
  }'

exit 0
