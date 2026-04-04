---
name: cancel
description: Stop the active autoresearch loop.
---

Check if an autoresearch loop is currently active by reading `.claude/autoresearch-loop.local.md`.

If the file does NOT exist, tell the user: "No active autoresearch loop found."

If the file exists:
1. Extract the `iteration` and `goal` fields from the YAML frontmatter
2. Remove the file: `rm .claude/autoresearch-loop.local.md`
3. Report: "Cancelled autoresearch loop at iteration {iteration}. Goal was: {goal}"
