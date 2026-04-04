#!/bin/bash

# Autoresearch Loop Setup Script
# Creates the state file that activates the stop hook.
# Called by the /autoresearch command after config extraction.

set -euo pipefail

# Parse arguments
GOAL=""
SCOPE=""
VERIFY=""
GUARD=""
DIRECTION="higher is better"
MAX_ITERATIONS=0
COMPLETION_PROMISE="null"
EVALUATOR="on"
AGENTS="default"
GUARD_DIRECTION=""
GUARD_THRESHOLD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --goal) GOAL="$2"; shift 2 ;;
    --scope) SCOPE="$2"; shift 2 ;;
    --verify) VERIFY="$2"; shift 2 ;;
    --guard) GUARD="$2"; shift 2 ;;
    --direction) DIRECTION="$2"; shift 2 ;;
    --max-iterations) MAX_ITERATIONS="$2"; shift 2 ;;
    --completion-promise) COMPLETION_PROMISE="$2"; shift 2 ;;
    --evaluator) EVALUATOR="$2"; shift 2 ;;
    --agents) AGENTS="$2"; shift 2 ;;
    --guard-direction) GUARD_DIRECTION="$2"; shift 2 ;;
    --guard-threshold) GUARD_THRESHOLD="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$GOAL" ]]; then
  echo "Error: --goal is required" >&2
  exit 1
fi

if [[ -z "$VERIFY" ]]; then
  echo "Error: --verify is required" >&2
  exit 1
fi

# Run config validation if available
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/validate-config.sh" ]]; then
  bash "$SCRIPT_DIR/validate-config.sh" \
    --verify "$VERIFY" \
    --direction "$DIRECTION" \
    ${GUARD:+--guard "$GUARD"} \
    ${GUARD_DIRECTION:+--guard-direction "$GUARD_DIRECTION"} \
    ${SCOPE:+--scope "$SCOPE"}
fi

# Prepare YAML-safe values
quote_yaml() {
  local val="$1"
  if [[ -z "$val" ]] || [[ "$val" == "null" ]]; then
    echo "null"
  else
    echo "\"$val\""
  fi
}

CURRENT_HEAD=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
mkdir -p .claude

# Quote completion promise for YAML
if [[ -n "$COMPLETION_PROMISE" ]] && [[ "$COMPLETION_PROMISE" != "null" ]]; then
  CP_YAML="\"$COMPLETION_PROMISE\""
else
  CP_YAML="null"
fi

cat > .claude/autoresearch-loop.local.md <<STATEEOF
---
active: true
iteration: 1
session_id: ${CLAUDE_CODE_SESSION_ID:-}
max_iterations: $MAX_ITERATIONS
goal: $(quote_yaml "$GOAL")
scope: $(quote_yaml "$SCOPE")
verify: $(quote_yaml "$VERIFY")
guard: $(quote_yaml "$GUARD")
direction: $(quote_yaml "$DIRECTION")
guard_direction: $(quote_yaml "$GUARD_DIRECTION")
guard_threshold: $(quote_yaml "$GUARD_THRESHOLD")
completion_promise: $CP_YAML
evaluator: $EVALUATOR
agents: $AGENTS
previous_outcome: null
commit_before: $CURRENT_HEAD
verified: false
guard_checked: false
research_done: false
started_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
---

You are in an ACTIVE autoresearch loop. Continue iterating.

## Config
Goal: $GOAL
Scope: $SCOPE
Verify: $VERIFY
$(if [[ -n "$GUARD" ]] && [[ "$GUARD" != "null" ]]; then echo "Guard: $GUARD"; fi)
Direction: $DIRECTION
$(if [[ "$EVALUATOR" == "on" ]]; then echo "Evaluator: on"; fi)
$(if [[ "$AGENTS" == "full" ]]; then echo "Agents: full"; fi)
$(if [[ -n "$COMPLETION_PROMISE" ]] && [[ "$COMPLETION_PROMISE" != "null" ]]; then echo "Completion-Promise: $COMPLETION_PROMISE"; fi)

## Instructions

1. Read the autonomous loop protocol: \`.claude/skills/autoresearch/references/autonomous-loop-protocol.md\`
2. Read the results logging format: \`.claude/skills/autoresearch/references/results-logging.md\`
3. Read the current results log: \`autoresearch-results.tsv\` (if it exists)
4. Execute from Phase 1 (Review) through Phase 8 (Repeat).

## Critical Rules (always apply, even if protocol file is unavailable)

1. ONE atomic change per iteration. If you need "and" to describe it, split it.
2. Commit BEFORE verify. This enables clean rollback.
3. Git is memory. Run \`git log --oneline -20\` and \`git diff HEAD~1\` every iteration.
4. Verification must be mechanical. Run the Verify command, extract a number. No subjective judgment.
5. Never modify guard/test files. Adapt your implementation to pass them.

## State File Updates (required for flow-check compliance)

After running verify: update \`verified: true\` in \`.claude/autoresearch-loop.local.md\` frontmatter.
After checking guard: update \`guard_checked: true\` in frontmatter.
After deciding outcome: update \`previous_outcome: <keep|discard|crash|no-op|...>\` in frontmatter.
If you performed research/investigation: update \`research_done: true\` in frontmatter.
STATEEOF

# Output activation message
cat <<EOF
Autoresearch loop activated.

  Iteration: 1
  Max iterations: $(if [[ $MAX_ITERATIONS -gt 0 ]]; then echo "$MAX_ITERATIONS"; else echo "unlimited"; fi)
  Evaluator: $EVALUATOR
  $(if [[ "$AGENTS" == "full" ]]; then echo "Agents: full (Coordinator/Dev/Evaluator/Research)"; fi)
  $(if [[ -n "$COMPLETION_PROMISE" ]] && [[ "$COMPLETION_PROMISE" != "null" ]]; then echo "Completion promise: $COMPLETION_PROMISE"; else echo "Completion promise: none"; fi)

The stop hook is now active. The loop will continue until max iterations
or completion promise is met.

To cancel: /autoresearch:cancel
To monitor: grep '^iteration:' .claude/autoresearch-loop.local.md
EOF
