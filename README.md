# Drupal Agentic Workflow for Claude Code

> Turn Claude Code into a Drupal-native development partner: specialized skills, auto-generated project context, code quality hooks, and security scanning.

## Why Use This?

| Without | With |
|---------|------|
| Claude generates code with coding standard violations | phpcbf auto-fixes violations before you see them |
| Manual phpcs/phpstan runs after every change | Post-generation hook lints every file automatically |
| No protection against destructive commands | Pre-bash guard blocks `git reset --hard`, `rm -rf`, etc. |
| Generic AI responses about Drupal | Specialized skills with Drupal 10/11 expertise |
| Security issues caught in code review | Security patterns scanned on every file save |
| Agent invents idioms instead of matching codebase | `.claude/conventions.md` reports actual adoption (hooks, DI, `match`/`switch`) |
| Agent guesses content types / routes / services | `.claude/project-map.md` lists them from YAML config |
| Agent hallucinates service IDs / field / route names | `.claude/site-api.json` is the running site's ground truth — grep it before writing |
| Agent re-litigates decisions you've already made | `.claude/decisions/` ADR scaffolds capture the *why* once |
| Agent invents API URLs / credentials | `.claude/external-systems.md` documents where they live |

### What Happens When You Write Code

```
Claude writes/edits a file
  │
  ├─ PreToolUse: pre-bash-guard.sh
  │   └─ Blocks destructive Bash commands (git reset --hard, rm -rf, etc.)
  │
  └─ PostToolUse: post-generation-lint.sh
      ├─ Is PHP? → phpcbf auto-fix → phpcs → security-perf-scan
      ├─ Is JS/TS? → prettier → eslint
      ├─ Is CSS/SCSS? → prettier → stylelint
      ├─ Is Twig/YAML/JSON? → prettier
      └─ Exit 2 if errors → Claude sees feedback and auto-corrects
```

### What Happens When You Run Setup

```
bin/setup.sh /path/to/project
  │
  ├─ Phase 0-6 : Validate Drupal project, install tools, copy skills/hooks,
  │              merge CLAUDE.md, install .prettierrc, scan custom modules
  │              for AI_CONTEXT.md
  │
  ├─ Phase 7   : detect.mjs        → .claude/stack.json + gaps.md
  │              (PHP/Drupal/JS versions, integrations, capability gaps)
  │
  ├─ Phase 7b  : detect.mjs        → .claude/skills-recommended.md
  │              (which installed skills cover which capability)
  │
  ├─ Phase 7c  : conventions.mjs   → .claude/conventions.md
  │              (adoption stats for hook style, DI, match/switch, ...)
  │
  ├─ Phase 7d  : copies scaffolds  → .claude/glossary.md, external-systems.md,
  │              test-fixtures.md, decisions/ (idempotent, user-owned)
  │
  ├─ Phase 7e  : project-map.mjs   → .claude/project-map.md
  │              (content types, fields, roles, routes, services, splits)
  │
  ├─ Phase 7f  : renders           → .claude/drupal-version-guide.md
  │              (per-version Drupal guide picked from
  │              assets/knowledge/drupal/<version>/ based on stack.json)
  │
  ├─ Phase 7g  : vendors           → .claude/reference/examples/
  │              (clones the matching Examples module branch — see
  │              examples_branch_for_major() in bin/setup.sh — for
  │              offline-friendly reference code)
  │
  ├─ Phase 7h  : patches           → .gitignore (managed block)
  │              (inserts/updates the `# >>> drupal-agentic-workflow >>>`
  │              … `# <<< drupal-agentic-workflow <<<` block; lines
  │              outside the markers are never touched; may print a
  │              `git rm --cached` notice for already-tracked
  │              AI_CONTEXT.md files)
  │
  ├─ Phase 7i  : site-api.sh (Drush)→ .claude/site-api.json
  │              (introspects the RUNNING site for ground-truth service IDs,
  │              entity/bundle/field machine names, routes, permissions and
  │              modules; needs a bootable site via ddev/vendor/global drush;
  │              falls back to project-map.md when the site is down)
  │
  ├─ Phase 8   : Summary (installed / up-to-date / skipped counts)
  │
  └─ Phase 9   : Offer to launch `claude` for the 4 manual next-step tasks;
                 all prompts persisted to .claude/followups.md
```

## Prerequisites

- **Claude Code CLI** installed and authenticated
- **DDEV** local development environment
- **Drupal 10.3+ or 11** project using `drupal/recommended-project`
- **PHP 8.3+** and **Composer 2**
- **jq** — required by hooks for JSON parsing (`brew install jq` / `apt-get install jq`)
- **Node.js 18+** — optional, for Prettier/ESLint/Stylelint (gracefully skipped if absent)

## Quick Setup

### 1. Install

**Recommended — as a Composer dev dependency** (per-project, versioned, updatable):

```bash
# In your Drupal project root. Until it's on Packagist, add the VCS repo first:
composer config repositories.daw vcs https://github.com/gxleano/drupal-agentic-workflow
composer require --dev gxleano/drupal-agentic-workflow:dev-main
```

This installs the `daw` CLI at `vendor/bin/daw`. To keep context fresh as your
dependencies change, add it to your `composer.json` so it re-runs after every
`composer update`:

```json
{
  "scripts": {
    "post-update-cmd": ["@php -r \"passthru('vendor/bin/daw update');\""]
  }
}
```

**Alternative — clone once, reference everywhere** (one install serves many projects):

```bash
git clone <repo-url> ~/drupal-agentic-workflow
```

### 2. Initialize Claude Code in Your Project

```bash
cd /path/to/your/drupal-project
claude /init
```

This generates a `CLAUDE.md` with auto-detected project info.

### 3. Run Setup

```bash
vendor/bin/daw install            # if installed via Composer
# or, if cloned:
~/drupal-agentic-workflow/bin/setup.sh .
```

Use `vendor/bin/daw update` for a non-interactive refresh (re-copies skills/hooks,
refreshes the `CLAUDE.md`/`AGENTS.md` managed blocks, and regenerates detected
context) without re-prompting and while preserving your customized files.

This single command:
- Checks for code quality tools (`drupal/coder`, `phpstan`) and offers to install them
- Copies the bundled skills and hooks into `.claude/`
- Appends Drupal coding rules to your existing `CLAUDE.md` (managed block — refreshed on re-run, your customizations outside the markers are preserved)
- Writes an `AGENTS.md` with the same agent-agnostic rules for non-Claude agents (Cursor, Codex, Gemini CLI, Copilot, …) — rendered from the same template, so no drift
- Installs `.prettierrc.json` and `phpstan.neon`
- Optionally analyzes custom modules and generates `AI_CONTEXT.md` with real module info (hooks, routes, services, etc.)
- Auto-populates the Custom Modules section in `CLAUDE.md` with discovered modules
- **Generates the project-context files** that agents read: `stack.json`, `skills-recommended.md`, `conventions.md`, `project-map.md`, `gaps.md`
- **Scaffolds knowledge files** the team fills in over time: `glossary.md`, `external-systems.md`, `test-fixtures.md`, `decisions/`
- **Offers to launch `claude`** at the end for the 4 manual follow-up tasks (filling project details, contrib module list, etc.)

The script is fully idempotent — safe to run multiple times. It never overwrites files you've customized.

Options:
```
~/drupal-agentic-workflow/bin/setup.sh --dry-run .          # Preview without changes
~/drupal-agentic-workflow/bin/setup.sh --force .            # Skip Drupal detection
~/drupal-agentic-workflow/bin/setup.sh --skip-tools .       # Skip code quality tools check
~/drupal-agentic-workflow/bin/setup.sh --skip-ai-context .  # Skip AI_CONTEXT.md generation prompt
~/drupal-agentic-workflow/bin/setup.sh --skip-detect .      # Skip stack detection / convention scan / project map
~/drupal-agentic-workflow/bin/setup.sh --skip-followups .   # Skip the "open claude for X" prompts at the end
~/drupal-agentic-workflow/bin/setup.sh --help               # Show help
```

### 4. Fill In Project Details

Phase 9 of `setup.sh` automatically offers to launch `claude` for each of these tasks. If you skipped them (`--skip-followups`, ran in CI, or chose `N` at the prompt), the prompts are saved to `.claude/followups.md` — open the file and run `claude "<paste prompt>"` for any task whenever you're ready.

The 4 follow-ups:
- **Fill in CLAUDE.md project details** — agent uses `stack.json`, `project-map.md`, `conventions.md` to draft project overview and architecture notes.
- **Verify Custom Modules descriptions** — agent cross-references each module's `AI_CONTEXT.md` and the project map to tighten the auto-populated descriptions.
- **List installed contrib modules** — agent reads `composer.json`, groups packages by category, fills the Contributed Modules section.
- **Review AI_CONTEXT.md per module** — agent appends a "Domain notes" section to each capturing business logic + gotchas (keeping the auto-generated tables intact).

You can also hand-edit the team-owned knowledge files at any time:
- `.claude/glossary.md` — domain terms
- `.claude/external-systems.md` — API URLs, credential locations, integration notes
- `.claude/test-fixtures.md` — demo users, sandbox cards, seed content
- `.claude/decisions/NNNN-*.md` — architecture decision records (copy `0001-template.md`)

### 5. Verify Setup

```bash
# Check that hooks are registered
cat .claude/settings.json | jq '.hooks'

# Check that skills are available (start Claude Code)
claude
# Then type: /drupal-expert
```

## What's Included

### Skills (20)

| Skill | Type | Purpose |
|-------|------|---------|
| **drupal-expert** | Inline | Drupal development knowledge base |
| **scaffold** | Inline | Generate modules, services, plugins, forms, hooks |
| **code-review** | Agent | Architectural code reviews with reports |
| **generate-tests** | Agent | PHPUnit test generation for custom modules |
| **debug** | Inline | Drupal code-level troubleshooting |
| **ddev** | Inline | DDEV environment management |
| **migrate** | Inline | Drupal migration management |
| **solr-setup** | Inline | DDEV Solr configuration |
| **drupal-frontend-expert** | Inline | Twig, SDC, theming, CSS/JS libraries, a11y |
| **drupal-site-builder-expert** | Inline | Views, content types, Layout Builder, config mgmt |
| **drupal-security** | Inline | Proactive security during development |
| **update-module** | Inline | Safe contrib module update workflow |
| **config-management** | Inline | Config export/import, Config Split, Recipes |
| **performance** | Inline | Caching, queries, BigPipe, profiling |
| **drush** | Inline | Drush CLI reference, SQL, PHP eval, deprecated commands |
| **refactor** | Inline | Code smell detection and refactoring guidance |
| **doctor** | Inline | Diagnostic health check for workflow setup |
| **accessibility** | Inline | WCAG 2.2 compliance, ARIA patterns, a11y testing |
| **api** | Inline | REST, JSON:API, GraphQL for decoupled Drupal |
| **entity** | Inline | Custom content/config entity types with bundles |

### Hooks

| Hook | Event | Purpose |
|------|-------|---------|
| **pre-bash-guard.sh** | PreToolUse (Bash) | Blocks destructive commands |
| **post-generation-lint.sh** | PostToolUse (Write/Edit) | Auto-fix + lint + security scan |
| **prompt-context.sh** | UserPromptSubmit (opt-in) | Git status summary injection |

### Other

- **Starter theme scaffold** — Ready-to-use theme template in `assets/theme-template/`
- **CLAUDE-TEMPLATE.md** — Drupal coding standards appended to your project's CLAUDE.md
- **phpstan.neon** — Generated with Drupal-specific configuration

## Project Context Files

The biggest gap between "Claude with skills" and "Claude that produces great code in *your* codebase" is **project context**. The skills know Drupal; the context files tell the agent what *this particular project* looks like.

`setup.sh` generates the following inside your project's `.claude/` directory. Files marked **auto** are regenerated on each setup run from the current codebase state; files marked **scaffold** are templates you fill in (preserved across re-runs).

| File | Type | Generated by | What it contains | When the agent reads it |
|------|------|--------------|------------------|-------------------------|
| `stack.json` | auto | `tools/detect.mjs` | PHP version, Drupal version, frontend stack, integrations, capability resolution against installed skills | Source of truth for tooling assumptions |
| `gaps.md` | auto | `tools/detect.mjs` | Capability gaps (no installed skill covers them) + drift warnings (Node EOL, PHP/Drupal mismatch, missing phpunit.xml, etc.) | When planning new tooling / upgrades |
| `skills-recommended.md` | auto | `tools/detect.mjs` | Capability → skill mapping table with descriptions pulled from each skill's frontmatter | When picking which skill to invoke for a task |
| `conventions.md` | auto | `tools/conventions.mjs` | Adoption stats: `strict_types` %, hook style (`#[Hook]` vs `.module`), constructor promotion, `match`/`switch`, `\Drupal::` anti-patterns, plugin attribute vs annotation, SDC adoption, BEM ratio | Before writing PHP / JS / CSS — match what the codebase actually does |
| `project-map.md` | auto | `tools/project-map.mjs` | Content types + fields, user roles, routes per custom module, services per custom module, config splits — all from YAML parsing (no Drush needed) | Before touching the data model, routes, or services |
| `site-api.json` | auto | `tools/site-api.sh` (Drush) | **Ground truth of the running site**: valid service IDs, every entity type, bundle + real field machine names/types, route names, permissions, installed modules | Before injecting a service or referencing a field / route / permission — grep/`jq` it to confirm the identifier exists |
| `followups.md` | auto | `setup.sh` | The 4 next-step prompts in copy-paste form | When re-running a follow-up manually |
| `glossary.md` | scaffold | template | Domain terms, German↔English vocabulary | Before naming things in code/UI/commits |
| `external-systems.md` | scaffold | template | API URLs, credential locations, integration IDs | Before touching integrations |
| `test-fixtures.md` | scaffold | template | Demo users, sandbox cards, seed content, reset recipes | Before verifying behavior locally |
| `decisions/*.md` | scaffold | template | Architecture Decision Records (append-only) | Before proposing architectural alternatives already ruled out |

The bundled `CLAUDE-TEMPLATE.md` includes a "Project knowledge files" table that points the agent at each of these — so they're actually discovered, not forgotten.

### The Scanners

| Tool | What it scans | Output |
|------|---------------|--------|
| `detect.mjs` | `composer.json/lock`, `package.json`, `*.info.yml`, `.ddev/`, CI config | `stack.json`, `gaps.md`, `skills-recommended.md` |
| `conventions.mjs` | Every PHP/JS/CSS file under custom paths | `conventions.md` with adoption ratios + actionable guidance |
| `project-map.mjs` | Drupal config (`config/sync/`, `config/default/`, ...) + custom-module `*.routing.yml` / `*.services.yml` | `project-map.md` |

The three `.mjs` scanners are zero-dep Node CLIs (Node 18+). They run cleanly without Drush, DDEV, or a running site — just static file analysis. Re-run any directly:

```bash
node .claude/tools/detect.mjs --gaps
node .claude/tools/conventions.mjs --print
node .claude/tools/project-map.mjs --print
```

`site-api.sh` is the one generator that needs a **bootable site** — it runs `site-api.php` through Drush (resolved as `ddev drush` → `vendor/bin/drush` → global `drush`) and writes the live ground-truth index. Re-run it after `drush cim`, module install/uninstall, or field changes; check `meta.generated_at` in the JSON for staleness:

```bash
.claude/tools/site-api.sh            # writes .claude/site-api.json
.claude/tools/site-api.sh --print    # also prints to stdout
```

It reads **definitions only** — never config values, State, settings, or secret entities — so the index is safe to generate, and it's gitignored (transient, site-specific). If the site isn't bootable, it skips with a warning and `project-map.md` remains the static fallback.

### Skill `provides:` Field (Data-Driven Capability Matching)

`detect.mjs` resolves capabilities → skills via two paths:

1. **`provides:` frontmatter (authoritative)** — a skill declaring `provides: [drupal-backend, drupal-debug]` automatically satisfies those capabilities.
2. **Name regex fallback** — for legacy skills without `provides:`, a built-in regex list still matches by name.

To make a new skill discoverable for a capability, just add `provides:` to its `SKILL.md`:

```markdown
---
name: my-helper
description: ...
version: 1.0.0
provides: [drupal-backend, custom-capability]
---
```

This means third-party / community skills can plug into the capability map without anyone editing the detector.

## Usage

Once set up, use skills via slash commands in Claude Code:

```
/scaffold module my_module             # Generate a new module
/code-review my_module                 # Review a module
/generate-tests my_module              # Generate PHPUnit tests
/debug                                 # Troubleshoot an issue
/migrate                               # Manage migrations
/ddev                                  # DDEV environment help
/drupal-frontend-expert                # Theming and frontend help
/drupal-site-builder-expert            # Site building guidance
/drupal-security                       # Security review/guidance
/drush                                 # Drush CLI reference and commands
/update-module                         # Safe module update workflow
/config-management                     # Config management guidance
/performance                           # Performance optimization
/refactor                              # Code refactoring guidance
/doctor                                # Verify workflow setup health
/accessibility                         # WCAG 2.2 compliance guidance
/api                                   # REST, JSON:API, GraphQL help
/entity                                # Custom entity type guidance
```

## Manual Setup

### 1. Copy Skills and Hooks

Copy the `.claude/` directory into your Drupal project root:

```bash
cp -r .claude/ /path/to/your/drupal-project/.claude/
```

### 2. Generate CLAUDE.md

In your Drupal project root, initialize Claude Code:

```bash
claude /init
```

### 3. Add Drupal Rules

Open [`CLAUDE-TEMPLATE.md`](CLAUDE-TEMPLATE.md) and copy the sections into your project's `CLAUDE.md`.

### 4. Install Code Quality Tools

```bash
ddev composer require --dev drupal/coder phpstan/phpstan mglaman/phpstan-drupal phpstan/phpstan-deprecation-rules
```

### 5. Fill In Project Details

In your `CLAUDE.md`, complete the Custom Modules and Contributed Modules sections.

### 6. Review AI_CONTEXT.md Files

The setup script can automatically analyze your custom modules and generate `AI_CONTEXT.md` files with real information (hooks, routes, services, permissions, source structure). Review these and add any business logic context that static analysis can't capture. If you skipped this during setup, re-run the script or ask Claude: *"Create an AI_CONTEXT.md for {module_name}"*

### 7. Install Prettier (Optional)

```bash
npm install --save-dev prettier
# For Twig formatting (optional):
npm install --save-dev prettier-plugin-twig-melody
```

### 8. Configure Permissions (Optional)

Create `.claude/settings.local.json` for your permission preferences.
This file is project-local and should NOT be committed to version control.

## Customization

### Modifying Skills

Skills live in `.claude/skills/{name}/SKILL.md`. Edit the markdown to adjust behavior, add patterns, or change guidance. Skills are just context — they inject instructions when invoked.

### Adding Custom Skills

Create a new directory under `.claude/skills/` with a `SKILL.md` file:

```markdown
---
name: my-skill
description: What this skill does and when to use it
---

# My Skill

Instructions for Claude when this skill is invoked...
```

### Adding Hook Patterns

Edit `.claude/hooks/post-generation-lint.sh` to add new checks. The security/performance scan section uses simple grep patterns — add new `scan_pattern` calls for project-specific rules.

### Excluding Files from Linting

Edit the `is_lintable()` function in `post-generation-lint.sh` to add paths:

```bash
case "$FILE_PATH" in
  */vendor/*|*/node_modules/*|*/my-excluded-path/*) return 1 ;;
esac
```

### Enabling Git Context (Opt-in)

To inject git status into every prompt, add to `.claude/settings.local.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/prompt-context.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

## Troubleshooting

### "phpcs standard not found"

The Drupal/DrupalPractice standards require `drupal/coder`:

```bash
ddev composer require --dev drupal/coder
```

Verify phpcs can find the standards:

```bash
ddev exec phpcs -i
# Should list: Drupal, DrupalPractice
```

### "Hook not firing"

1. Check `.claude/settings.json` has the hook registered
2. Verify the hook script is executable: `chmod +x .claude/hooks/*.sh`
3. Check `jq` is installed: `which jq`
4. Test the hook manually:
   ```bash
   echo '{"tool_input":{"file_path":"test.php"}}' | .claude/hooks/post-generation-lint.sh
   ```

### "ddev exec fails"

The DDEV container must be running:

```bash
ddev start
ddev status
```

### "Skill not available"

1. Verify the skill directory exists: `ls .claude/skills/`
2. Check SKILL.md has valid frontmatter (name, description)
3. Restart Claude Code session

### "phpcbf/phpcs not found in DDEV"

```bash
ddev composer require --dev drupal/coder
ddev exec phpcs --version
ddev exec phpcbf --version
```

## File Structure

### In `~/drupal-agentic-workflow/` (this repo — your install of the workflow)

```
~/drupal-agentic-workflow/
├── bin/
│   └── setup.sh                       # Idempotent installer (9 phases)
├── CLAUDE-TEMPLATE.md                 # Managed-block content + skills index + knowledge files index
├── README.md                          # This file
├── .claude/
│   ├── settings.json                  # Hook configuration (copied to projects)
│   ├── hooks/                         # All shell hooks (copied to projects)
│   └── skills/                        # Bundled skills (copied to projects)
└── assets/
    ├── tools/
    │   ├── detect.mjs                 # Stack detection + skill capability resolver
    │   ├── conventions.mjs            # Convention adoption scanner
    │   └── project-map.mjs            # Content model / routes / services scanner
    ├── knowledge/                     # Scaffolds (idempotent — never overwrites user content)
    │   ├── glossary.md
    │   ├── external-systems.md
    │   ├── test-fixtures.md
    │   └── decisions/
    │       ├── README.md
    │       └── 0001-template.md
    ├── ci-templates/                  # CI/CD templates
    └── theme-template/                # Starter theme scaffold
```

### In your Drupal project after `setup.sh`

```
your-drupal-project/
├── .claude/
│   ├── settings.json                  # Hook + skill configuration
│   ├── hooks/                         # pre-bash-guard, post-generation-lint, etc.
│   ├── skills/                        # Bundled skills
│   ├── tools/                         # detect.mjs / conventions.mjs / project-map.mjs / site-api.{php,sh}
│   │
│   ├── stack.json                     # AUTO — detected stack + capability resolution
│   ├── gaps.md                        # AUTO — capability gaps + drift warnings
│   ├── skills-recommended.md          # AUTO — capability → skill mapping
│   ├── conventions.md                 # AUTO — code convention adoption stats
│   ├── project-map.md                 # AUTO — content model, routes, services, roles, splits
│   ├── site-api.json                  # AUTO (gitignored) — live site ground truth via Drush
│   ├── followups.md                   # AUTO — the 4 next-step prompts in copy-paste form
│   │
│   ├── glossary.md                    # SCAFFOLD — domain glossary (team fills in)
│   ├── external-systems.md            # SCAFFOLD — integrations & credential locations
│   ├── test-fixtures.md               # SCAFFOLD — demo users / sandbox cards / seed content
│   └── decisions/                     # SCAFFOLD — ADRs (append-only)
│       ├── README.md
│       └── 0001-template.md
│
├── .prettierrc.json                   # Prettier config (JS/CSS/Twig/YAML/JSON)
├── phpstan.neon                       # PHPStan config (generated)
├── CLAUDE.md                          # Managed block + project sections
└── web/modules/custom/<module>/
    └── AI_CONTEXT.md                  # AUTO — per-module context (keys files, hooks, routes, services)
```

The **AUTO** files refresh on each `setup.sh` run (so they reflect the current code). The **SCAFFOLD** files are templates — the script never overwrites your edits.

## Maintenance: Examples module branch mapping

Phase 7g vendors the [Examples for Developers](https://www.drupal.org/project/examples) project into `.claude/reference/examples/` so agents have offline-friendly reference code that matches the project's Drupal major version. The Drupal-major → Examples-branch mapping lives in the `examples_branch_for_major()` shell function inside [`bin/setup.sh`](bin/setup.sh).

Current mapping:

| Drupal major | Examples branch |
|--------------|-----------------|
| 10           | `4.0.x`         |
| 11           | `4.0.x`         |

Update this function whenever the Examples project ships a new per-major branch (for example, when a future `5.0.x` branch is published for Drupal 12). Add the new `case` arm, keep existing majors pointing at the branch they currently track, and bump the default fallback only after verifying the new branch exists on drupal.org.

For per-version Drupal guide templates (rendered by Phase 7f), see [`assets/knowledge/drupal/README.md`](assets/knowledge/drupal/README.md) — it documents the directory layout under `assets/knowledge/drupal/<version>/` and how to add or update a version-specific guide.

## Managed `.gitignore` block

Phase 7h reconciles a managed block inside your project's `.gitignore`, delimited by:

```
# >>> drupal-agentic-workflow >>>
# ... entries managed by setup.sh ...
# <<< drupal-agentic-workflow <<<
```

Rules:

- **Lines outside the markers are never touched.** Your existing `.gitignore` entries are safe — setup only reads and rewrites the region between the two marker lines.
- **User additions inside the block are preserved during reconciliation.** Setup merges the bundled defaults with any extra lines you've added inside the markers, so you can add project-specific ignores in there without losing them on re-run.
- **`git rm --cached` notice in Phase 8.** If your repo already tracks `AI_CONTEXT.md` files that the new ignore rules would otherwise cover, Phase 8 prints a one-line notice listing them along with a ready-to-paste `git rm --cached <files>` command. Setup will **never** run that command automatically — untracking files is a destructive history-affecting operation, so it is left to you.

## Live site-API index (`.claude/site-api.json`)

The most common — and most expensive — way an agent breaks Drupal code is by **hallucinating identifiers**: a service ID that was never registered, a field machine name that doesn't match the bundle, a route name that doesn't exist. Static analysis only catches these *after* the wrong code is written. Phase 7i closes that gap by giving the agent the **ground truth of the running site** to check *before* it writes.

`.claude/tools/site-api.sh` runs `.claude/tools/site-api.php` through Drush and writes `.claude/site-api.json` containing:

| Section | Source (live Drupal API) | Kills the error |
|---------|--------------------------|-----------------|
| `services` | `\Drupal::getContainer()->getServiceIds()` | inventing/typo'ing service IDs (`entity.manager`) |
| `entity_types` | `entity_type.manager` | wrong entity class / provider |
| `bundles` → `fields` | `entity_field.manager` + `entity_type.bundle.info` | wrong field machine name / type / target bundle |
| `routes` | `router.route_provider` | `Url::fromRoute()` to a non-existent route |
| `permissions` | `user.permissions` | guarding on a permission that doesn't exist |
| `modules` | `extension.list.module` | not knowing what contrib is available to reuse |

**Design notes:**

- **Runtime, not static.** Unlike the `.mjs` scanners, this reads the *compiled container* and *field manager*, so it sees UI-added fields, dynamically-registered routes, and `ServiceProvider`-registered services that YAML parsing can never find. `project-map.md` (Phase 7e, static) remains the fallback when the site isn't bootable.
- **Definitions only — never values.** The extractor reads machine names and types; it never touches config values, State, `settings.php`, or secret entities. The file is gitignored (transient and site-specific).
- **Queried, not read whole.** It's JSON so the agent greps/`jq`s for one identifier rather than loading the lot: `jq '.bundles."node.article".fields' .claude/site-api.json`.
- **Refresh on demand.** Re-run `.claude/tools/site-api.sh` after `drush cim`, module install/uninstall, or field changes. `meta.generated_at` records when it was last built.
- **Defaults.** Includes everything (core routes/services included — a missing core route name is exactly what gets hallucinated), marks base fields with `"base": true` rather than dropping them, and operates on the default site.

## Tests

The tooling itself is tested. Run the full suite (also wired as `composer test`):

```bash
bash tests/run.sh
```

Stages (each skipped gracefully if its tool is missing locally; CI runs them all):

- **`bash -n`** — syntax check of every shell script
- **`shellcheck`** (`--severity=warning`, `-x`) — static analysis of `bin/`, hooks, and tests
- **`node --test`** — unit tests for the `.mjs` generators (e.g. `conventions.mjs` against fixture projects)
- **`tests/smoke.sh`** — end-to-end `setup.sh` install into a throwaway project, asserting the `CLAUDE.md`/`AGENTS.md` managed blocks render correctly and that re-runs are idempotent

CI runs `tests/run.sh` on every push/PR via `.github/workflows/ci.yml`.

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run `bash tests/run.sh` (and `bin/setup.sh --dry-run` on a sample Drupal project)
5. Submit a pull request

When adding new skills, follow the existing pattern: create a directory under `.claude/skills/` with a `SKILL.md` containing frontmatter (name, description) and comprehensive guidance.
