---
name: code-review
description: Perform architectural code reviews like a senior Drupal Architect
version: 2.1.0
---

## Agent Dispatcher

This skill delegates ALL work to a background agent. Do NOT perform the review inline.

### Steps

1. **Parse input**: Determine the review target and type from user arguments.
   - **Target**: module name, file paths, branch, or PR number. If just a module name (e.g. `my_module`), expand to `web/modules/custom/my_module`.
   - **Type**: `quick`, `security`, `architecture`, `full` (default), `standards`, or `test`.
   - If no target provided, ask the user.

2. **Read** the file `.claude/skills/code-review/agent-prompt.md`.

3. **Launch** a `general-purpose` agent via the Task tool:
   - `run_in_background: true`
   - `description: "Code review: <target>"`
   - `prompt`: The full contents of `agent-prompt.md` followed by:

   ```
   ---
   ## Your Review Task
   **Target**: <resolved path(s)>
   **Review type**: <type>
   **Date**: <today>
   **Review name**: <slug for report filename>
   Begin now.
   ```

4. **Tell the user** the agent is running, what it's reviewing, and where the report will be saved (`.claude/reviews/<name>.md`).

## Related Skills

- **generate-tests** — Generate tests for issues found during review
- **scaffold** — Re-scaffold components that need structural fixes
- **debug** — Investigate issues discovered during review
- **drupal-security** — Deep security analysis for vulnerabilities found during review