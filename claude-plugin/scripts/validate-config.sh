#!/bin/bash

# Autoresearch Config Validation Script
# Validates config before creating the loop state file.
# Called by setup-loop.sh. Exits non-zero on validation failure.

set -euo pipefail

VERIFY=""
GUARD=""
DIRECTION=""
GUARD_DIRECTION=""
SCOPE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify) VERIFY="$2"; shift 2 ;;
    --guard) GUARD="$2"; shift 2 ;;
    --direction) DIRECTION="$2"; shift 2 ;;
    --guard-direction) GUARD_DIRECTION="$2"; shift 2 ;;
    --scope) SCOPE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

ERRORS=0

# Check git repo exists
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "Validation error: not a git repository. Run 'git init' first." >&2
  ERRORS=$((ERRORS + 1))
fi

# Check not detached HEAD
if ! git symbolic-ref HEAD >/dev/null 2>&1; then
  echo "Validation warning: detached HEAD. Consider checking out a branch." >&2
fi

# Check working tree is clean
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  echo "Validation error: working tree has uncommitted changes. Commit or stash first." >&2
  ERRORS=$((ERRORS + 1))
fi

# Validate direction
if [[ -n "$DIRECTION" ]]; then
  case "$DIRECTION" in
    "higher is better"|"lower is better") ;;
    *)
      echo "Validation error: direction must be 'higher is better' or 'lower is better', got: '$DIRECTION'" >&2
      ERRORS=$((ERRORS + 1))
      ;;
  esac
fi

# Validate guard direction (if provided)
if [[ -n "$GUARD_DIRECTION" ]]; then
  case "$GUARD_DIRECTION" in
    "higher is better"|"lower is better") ;;
    *)
      echo "Validation error: guard-direction must be 'higher is better' or 'lower is better', got: '$GUARD_DIRECTION'" >&2
      ERRORS=$((ERRORS + 1))
      ;;
  esac
fi

# Validate scope resolves to files (if provided)
if [[ -n "$SCOPE" ]]; then
  IFS=',' read -ra SCOPE_PARTS <<< "$SCOPE"
  TOTAL_FILES=0
  for glob in "${SCOPE_PARTS[@]}"; do
    glob=$(echo "$glob" | xargs)
    COUNT=$(find . -path "./$glob" 2>/dev/null | head -1 | wc -l || echo 0)
    TOTAL_FILES=$((TOTAL_FILES + COUNT))
  done
  if [[ $TOTAL_FILES -eq 0 ]]; then
    echo "Validation warning: scope '$SCOPE' matched no files. The glob may be wrong." >&2
  fi
fi

# Dry-run verify command
if [[ -n "$VERIFY" ]]; then
  set +e
  VERIFY_OUTPUT=$(eval "$VERIFY" 2>&1)
  VERIFY_EXIT=$?
  set -e

  if [[ $VERIFY_EXIT -ne 0 ]]; then
    echo "Validation error: verify command failed (exit $VERIFY_EXIT)." >&2
    echo "  Command: $VERIFY" >&2
    echo "  Output (last 5 lines):" >&2
    echo "$VERIFY_OUTPUT" | tail -5 | sed 's/^/    /' >&2
    ERRORS=$((ERRORS + 1))
  else
    LAST_NUMBER=$(echo "$VERIFY_OUTPUT" | grep -oE '[-]?[0-9]+\.?[0-9]*' | tail -1 || echo "")
    if [[ -z "$LAST_NUMBER" ]]; then
      echo "Validation error: verify command produced no numeric output." >&2
      echo "  Command: $VERIFY" >&2
      echo "  Output (last 5 lines):" >&2
      echo "$VERIFY_OUTPUT" | tail -5 | sed 's/^/    /' >&2
      echo "  The verify command must output at least one number for metric extraction." >&2
      ERRORS=$((ERRORS + 1))
    else
      echo "Validation: verify command OK (metric: $LAST_NUMBER)" >&2
    fi
  fi
fi

# Dry-run guard command (if provided)
if [[ -n "$GUARD" ]]; then
  set +e
  GUARD_OUTPUT=$(eval "$GUARD" 2>&1)
  GUARD_EXIT=$?
  set -e

  if [[ $GUARD_EXIT -ne 0 ]]; then
    echo "Validation error: guard command failed (exit $GUARD_EXIT)." >&2
    echo "  Command: $GUARD" >&2
    echo "  Output (last 5 lines):" >&2
    echo "$GUARD_OUTPUT" | tail -5 | sed 's/^/    /' >&2
    ERRORS=$((ERRORS + 1))
  else
    if [[ -n "$GUARD_DIRECTION" ]]; then
      GUARD_NUMBER=$(echo "$GUARD_OUTPUT" | grep -oE '[-]?[0-9]+\.?[0-9]*' | tail -1 || echo "")
      if [[ -z "$GUARD_NUMBER" ]]; then
        echo "Validation error: guard command produced no numeric output (metric-valued mode requires a number)." >&2
        ERRORS=$((ERRORS + 1))
      else
        echo "Validation: guard command OK (metric: $GUARD_NUMBER)" >&2
      fi
    else
      echo "Validation: guard command OK (pass/fail mode)" >&2
    fi
  fi
fi

if [[ $ERRORS -gt 0 ]]; then
  echo "" >&2
  echo "Config validation failed with $ERRORS error(s). Fix the issues above before starting the loop." >&2
  exit 1
fi

exit 0
