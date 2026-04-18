---
name: cancel
description: Use when user types /autoresearch:cancel or asks to stop/abort the active autoresearch loop. Removes the state file and allows session exit.
---

Check if an autoresearch loop is currently active by reading `.claude/autoresearch-loop.local.md`.

If the file does NOT exist, tell the user: "No active autoresearch loop found."

If the file exists:
1. Extract the `iteration` and `goal` fields from the YAML frontmatter
2. Remove the file: `rm .claude/autoresearch-loop.local.md`
3. Report: "Cancelled autoresearch loop at iteration {iteration}. Goal was: {goal}"
