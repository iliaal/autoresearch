#!/bin/bash

# Autoresearch Flow-Check Script
# Validates protocol compliance after each iteration.
# Called by stop-hook.sh. Outputs warnings to stdout (included in systemMessage).
# Does NOT block the loop -- warnings only.

set -euo pipefail

STATE_FILE="${1:-.claude/autoresearch-loop.local.md}"

if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")

extract_field() {
  echo "$FRONTMATTER" | grep "^${1}:" | sed "s/^${1}: *//" | sed 's/^"\(.*\)"$/\1/'
}

ITERATION=$(extract_field "iteration")
PREVIOUS_OUTCOME=$(extract_field "previous_outcome")
VERIFIED=$(extract_field "verified")
GUARD_CHECKED=$(extract_field "guard_checked")
GUARD=$(extract_field "guard")
RESEARCH_DONE=$(extract_field "research_done")
COMMIT_BEFORE=$(extract_field "commit_before")
SESSION_ID=$(extract_field "session_id")

WARNINGS=""

warn() {
  if [[ -n "$WARNINGS" ]]; then
    WARNINGS="$WARNINGS; $1"
  else
    WARNINGS="$1"
  fi
}

# Check 1: Results log updated
RESULTS_LOG="autoresearch-results.tsv"
if [[ -f "$RESULTS_LOG" ]]; then
  LAST_ITER=$(tail -1 "$RESULTS_LOG" | cut -f1 2>/dev/null || echo "")
  if [[ "$LAST_ITER" =~ ^[0-9]+$ ]]; then
    EXPECTED=$((ITERATION - 1))
    if [[ "$LAST_ITER" -lt "$EXPECTED" ]] && [[ $EXPECTED -gt 0 ]]; then
      warn "Results log missing entry for iteration $EXPECTED"
    fi
  fi
else
  if [[ "$ITERATION" -gt 1 ]]; then
    warn "Results log not found"
  fi
fi

# Check 2: At most 1 new commit since commit_before
if [[ -n "$COMMIT_BEFORE" ]] && [[ "$COMMIT_BEFORE" != "null" ]] && [[ "$COMMIT_BEFORE" != "unknown" ]]; then
  COMMIT_COUNT=$(git rev-list --count "${COMMIT_BEFORE}..HEAD" 2>/dev/null || echo "0")
  if [[ "$COMMIT_COUNT" -gt 2 ]]; then
    warn "Multiple commits ($COMMIT_COUNT) in one iteration (expected at most 1 experiment + 1 possible revert)"
  fi
fi

# Check 3: Outcome declared
if [[ "$PREVIOUS_OUTCOME" == "null" ]] || [[ -z "$PREVIOUS_OUTCOME" ]]; then
  if [[ "$ITERATION" -gt 1 ]]; then
    warn "No outcome declared for previous iteration"
  fi
fi

# Check 4: Verify was run
if [[ "$VERIFIED" != "true" ]]; then
  if [[ "$ITERATION" -gt 1 ]] && [[ "$PREVIOUS_OUTCOME" != "no-op" ]] && [[ "$PREVIOUS_OUTCOME" != "hook-blocked" ]]; then
    warn "Verify not run (verified flag not set)"
  fi
fi

# Check 5: Guard checked (if configured)
if [[ -n "$GUARD" ]] && [[ "$GUARD" != "null" ]]; then
  if [[ "$GUARD_CHECKED" != "true" ]]; then
    if [[ "$ITERATION" -gt 1 ]] && [[ "$PREVIOUS_OUTCOME" != "no-op" ]] && [[ "$PREVIOUS_OUTCOME" != "hook-blocked" ]] && [[ "$PREVIOUS_OUTCOME" != "discard" ]]; then
      warn "Guard not checked despite being configured"
    fi
  fi
fi

# Check 6: Research after failure (mandatory)
if [[ "$PREVIOUS_OUTCOME" == "discard" ]] || [[ "$PREVIOUS_OUTCOME" == "crash" ]]; then
  if [[ "$RESEARCH_DONE" != "true" ]]; then
    warn "MANDATORY: Research not performed after $PREVIOUS_OUTCOME. Investigate WHY the previous iteration failed before making the next change"
  fi
fi

# Check 7: No dirty working tree
DIRTY=$(git status --porcelain 2>/dev/null || echo "")
if [[ -n "$DIRTY" ]]; then
  warn "Dirty working tree at end of iteration (uncommitted or unreverted changes)"
fi

# Check 8: Session ID consistency
if [[ -n "$SESSION_ID" ]] && [[ -n "${CLAUDE_CODE_SESSION_ID:-}" ]]; then
  if [[ "$SESSION_ID" != "$CLAUDE_CODE_SESSION_ID" ]]; then
    warn "Session ID mismatch (state: $SESSION_ID, current: $CLAUDE_CODE_SESSION_ID)"
  fi
fi

if [[ -n "$WARNINGS" ]]; then
  echo "$WARNINGS"
fi

exit 0
