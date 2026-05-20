---
name: generate-tests
description: Generate PHPUnit tests for Drupal custom modules using a background agent
version: 1.1.0
provides: [test-generation]
---

## Agent Dispatcher

This skill delegates ALL work to a background agent. Do NOT generate tests inline.

### Steps

1. **Parse input**: Determine the target and test type from user arguments.
   - **Target**: module name, class, or file path. If just a module name (e.g. `my_module`), expand to `web/modules/custom/my_module`.
   - **Type**: `unit`, `kernel`, `functional`, or `all` (default).
   - If no target provided, ask the user.

2. **Read** the file `.claude/skills/generate-tests/agent-prompt.md`.

3. **Launch** a `general-purpose` agent via the Task tool:
   - `run_in_background: true`
   - `description: "Generate tests: <target>"`
   - `prompt`: The full contents of `agent-prompt.md` followed by:

   ```
   ---
   ## Your Task
   **Target module**: <resolved module path>
   **Test types**: <unit|kernel|functional|all>
   **Date**: <today>
   Begin now.
   ```

4. **Tell the user** the agent is running and what module it's generating tests for.

## Related Skills

- **code-review** — Review module before generating tests for complete coverage
- **debug** — Debug failing tests
- **scaffold** — Scaffold test infrastructure for new modules
