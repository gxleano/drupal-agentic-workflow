---
name: doctor
description: Diagnostic health check for drupal-agentic-workflow setup — verifies hooks, skills, tools, and project configuration
version: 1.0.0
provides: [diagnostics]
---

# Doctor — Workflow Health Check

When the user runs `/doctor`, perform ALL of the following diagnostic checks and present results as a report.

## Output Format

Use this format for each check:
- `✓` = passing
- `✗` = failing (with fix suggestion)
- `!` = warning (non-critical)

## Checks to Perform

### 1. Hook Registration

Read `.claude/settings.json` and verify these hooks are registered:

| Hook | Event | Script |
|------|-------|--------|
| pre-bash-guard | PreToolUse (Bash) | `.claude/hooks/pre-bash-guard.sh` |
| post-generation-lint | PostToolUse (Write, Edit) | `.claude/hooks/post-generation-lint.sh` |
| prompt-context | PreToolUse (user_prompt_submit) | `.claude/hooks/prompt-context.sh` |

**Fix:** Re-run `~/drupal-agentic-workflow/bin/setup.sh .`

### 2. Hook Executability

Run `test -x` on each `.sh` file in `.claude/hooks/`:

```bash
for f in .claude/hooks/*.sh; do test -x "$f" && echo "✓ $f" || echo "✗ $f (not executable)"; done
```

**Fix:** `chmod +x .claude/hooks/*.sh`

### 3. Skills Inventory

Count and list all skills:

```bash
find .claude/skills -name "SKILL.md" -type f | sort
```

Expected: 22 skills (api, accessibility, ci-cd, code-review, config-management, ddev, debug, doctor, drupal-expert, drupal-frontend-expert, drupal-security, drupal-site-builder-expert, drush, entity, forms, generate-tests, migrate, performance, refactor, scaffold, solr-setup, update-module).

Warn if fewer than expected.

### 4. Code Quality Tools

Check `composer.json` for:

```bash
for pkg in "drupal/coder" "phpstan/phpstan" "mglaman/phpstan-drupal"; do
  grep -q "\"$pkg\"" composer.json 2>/dev/null && echo "✓ $pkg" || echo "! $pkg (missing)"
done
```

### 5. Tool Availability

Check if tools are available (try local first, then ddev):

```bash
for tool in phpcs phpcbf phpstan; do
  if command -v vendor/bin/$tool &>/dev/null || ddev exec which $tool &>/dev/null 2>&1; then
    echo "✓ $tool"
  else
    echo "✗ $tool (not found)"
  fi
done

for tool in jq prettier; do
  command -v $tool &>/dev/null && echo "✓ $tool" || echo "! $tool (not found)"
done
```

### 6. CLAUDE.md Health

Check these conditions:

| Check | How |
|-------|-----|
| File exists | `test -f CLAUDE.md` |
| Has managed markers | `grep -q 'drupal-agentic-workflow:start' CLAUDE.md` |
| Custom Modules populated | NOT just a `<!-- List your custom modules` comment |
| Contributed Modules populated | NOT just a `<!-- List your installed contrib` comment |

**Fix:** Re-run setup.sh or manually fill in the sections.

### 7. AI_CONTEXT.md Coverage

For each module in `web/modules/custom/*/`:

```bash
for dir in web/modules/custom/*/; do
  mod=$(basename "$dir")
  if [[ ! -f "$dir/AI_CONTEXT.md" ]]; then
    echo "✗ $mod — missing AI_CONTEXT.md"
  elif grep -q "TODO:" "$dir/AI_CONTEXT.md"; then
    echo "! $mod — AI_CONTEXT.md has unfilled TODO placeholders"
  else
    echo "✓ $mod"
  fi
done
```

**Fix:** Re-run setup.sh (it offers to generate these), or ask Claude to create one.

### 8. DDEV / Environment Status

```bash
if [[ -f ".ddev/config.yaml" ]]; then
  ddev status 2>/dev/null | head -5 || echo "! DDEV configured but not running"
elif [[ -f ".lando.yml" ]]; then
  echo "✓ Lando environment detected"
else
  echo "! No DDEV or Lando config found — using local environment"
fi
```

### 9. Drupal Version

```bash
ddev drush status --field=drupal-version 2>/dev/null || \
  grep '"drupal/core"' composer.lock 2>/dev/null | head -1
```

Warn if < 10.3.

### 10. PHP Version

```bash
ddev exec php -v 2>/dev/null | head -1 || php -v | head -1
```

Warn if < 8.3.

### 11. phpstan.neon

```bash
test -f phpstan.neon && echo "✓ phpstan.neon exists" || echo "✗ phpstan.neon missing"
```

**Fix:** Re-run setup.sh (it generates this).

### 12. Git Status

```bash
echo "Branch: $(git branch --show-current)"
CHANGES=$(git status --porcelain | wc -l | tr -d ' ')
if [[ "$CHANGES" -gt 0 ]]; then
  echo "! $CHANGES uncommitted change(s)"
else
  echo "✓ Working tree clean"
fi
```

## Final Report

After all checks, output a summary:

```
══════════════════════════════════
  Workflow Health Check Complete
══════════════════════════════════
  ✓ Passing : X
  ✗ Failing : X
  ! Warnings: X

  [Actionable fix suggestions for any failures]
══════════════════════════════════
```
