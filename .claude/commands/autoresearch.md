---
name: autoresearch
description: Autonomous Goal-directed Iteration. Modify, verify, keep/discard, repeat. Apply to ANY task with a measurable metric.
argument-hint: "[Goal: <text>] [Scope: <glob>] [Metric: <text>] [Verify: <cmd>] [Guard: <cmd>] [--iterations N]"
---

EXECUTE IMMEDIATELY -- do not deliberate, do not ask clarifying questions before reading the protocol.

## Argument Parsing (do this FIRST, before reading any files)

Extract these from $ARGUMENTS -- the user may provide extensive context alongside config. Ignore prose and extract ONLY structured fields:

- `Goal:` -- text after "Goal:" keyword
- `Scope:` or `--scope <glob>` -- file globs after "Scope:" keyword
- `Metric:` -- text after "Metric:" keyword
- `Verify:` -- shell command after "Verify:" keyword
- `Guard:` -- shell command after "Guard:" keyword (optional)
- `Guard-Direction:` -- "higher is better" or "lower is better" (optional, for metric-valued guard)
- `Guard-Threshold:` -- max allowed regression as % (optional, for metric-valued guard)
- `Iterations:` or `--iterations` -- integer N for bounded mode
- `Completion-Promise:` -- semantic exit condition text (optional)
- `Evaluator:` -- on/off (default: on)
- `Agents:` -- default/full (default: default)

## Execution

1. Read the autonomous loop protocol: `.claude/skills/autoresearch/references/autonomous-loop-protocol.md`
2. Read the results logging format: `.claude/skills/autoresearch/references/results-logging.md`
3. If Goal, Scope, Metric, and Verify are all extracted -- proceed directly to loop setup
4. If any critical field is missing -- use `AskUserQuestion` with batched questions as defined in SKILL.md "Interactive Setup" section
5. **Initialize the loop state** by running:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT:-claude-plugin}/scripts/setup-loop.sh" \
     --goal "<goal>" \
     --scope "<scope>" \
     --verify "<verify>" \
     --direction "<direction>" \
     ${guard:+--guard "<guard>"} \
     ${guard_direction:+--guard-direction "<guard_direction>"} \
     ${guard_threshold:+--guard-threshold "<guard_threshold>"} \
     ${iterations:+--max-iterations "<iterations>"} \
     ${completion_promise:+--completion-promise "<completion_promise>"} \
     --evaluator "<evaluator>" \
     --agents "<agents>"
   ```
   If setup-loop.sh is not available (plugin not installed via marketplace), skip this step and proceed with prompt-driven loop.
6. Execute the autonomous loop: Modify -> Verify -> Keep/Discard -> Repeat
7. The stop hook handles iteration counting and loop continuation. Do NOT maintain a separate iteration counter.

IMPORTANT: Start executing immediately. Stream all output live -- never run in background. The stop hook prevents premature exit, but you should still follow the full protocol each iteration.
