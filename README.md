# Drupal Agentic Workflow for Claude Code

> Turn Claude Code into a Drupal-native development partner with 16 AI-powered skills, automated code quality hooks, and security scanning.

## Why Use This?

| Without | With |
|---------|------|
| Claude generates code with coding standard violations | phpcbf auto-fixes violations before you see them |
| Manual phpcs/phpstan runs after every change | Post-generation hook lints every file automatically |
| No protection against destructive commands | Pre-bash guard blocks `git reset --hard`, `rm -rf`, etc. |
| Generic AI responses about Drupal | 16 specialized skills with Drupal 10/11 expertise |
| Security issues caught in code review | Security patterns scanned on every file save |

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

## Prerequisites

- **Claude Code CLI** installed and authenticated
- **DDEV** local development environment
- **Drupal 10.3+ or 11** project using `drupal/recommended-project`
- **PHP 8.3+** and **Composer 2**
- **jq** — required by hooks for JSON parsing (`brew install jq` / `apt-get install jq`)
- **Node.js 18+** — optional, for Prettier/ESLint/Stylelint (gracefully skipped if absent)

## Quick Setup

### 1. Clone This Repository

```bash
git clone <repo-url> ~/drupal-agentic-workflow
```

Keep it somewhere permanent — you'll reference it for each project.

### 2. Initialize Claude Code in Your Project

```bash
cd /path/to/your/drupal-project
claude /init
```

This generates a `CLAUDE.md` with auto-detected project info.

### 3. Run Setup

```bash
~/drupal-agentic-workflow/bin/setup.sh .
```

This single command:
- Checks for code quality tools (`drupal/coder`, `phpstan`) and offers to install them
- Copies all 16 skills and hooks into `.claude/`
- Appends Drupal coding rules to your existing `CLAUDE.md`
- Installs `.prettierrc.json` and `phpstan.neon`
- Generates `AI_CONTEXT.md` templates for custom modules missing one

The script is fully idempotent — safe to run multiple times. It never overwrites files you've customized.

Options:
```
~/drupal-agentic-workflow/bin/setup.sh --dry-run .       # Preview without changes
~/drupal-agentic-workflow/bin/setup.sh --force .         # Skip Drupal detection
~/drupal-agentic-workflow/bin/setup.sh --skip-tools .    # Skip code quality tools check
~/drupal-agentic-workflow/bin/setup.sh --help            # Show help
```

### 4. Fill In Project Details

In your `CLAUDE.md`, complete:
- **Custom Modules** — list each module with `AI_CONTEXT.md` link
- **Contributed Modules** — list installed contrib
- Any project-specific conventions

### 5. Verify Setup

```bash
# Check that hooks are registered
cat .claude/settings.json | jq '.hooks'

# Check that skills are available (start Claude Code)
claude
# Then type: /drupal-expert
```

## What's Included

### Skills (16)

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

### 6. Create AI_CONTEXT.md for Each Module

For each custom module, create an `AI_CONTEXT.md` at the module root. Ask Claude: *"Create an AI_CONTEXT.md for {module_name}"*

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

```
your-drupal-project/
├── .claude/
│   ├── settings.json                  # Hook and skill configuration
│   ├── hooks/
│   │   ├── README.md                  # Hook documentation
│   │   ├── pre-bash-guard.sh         # Blocks destructive Bash commands
│   │   ├── post-generation-lint.sh    # phpcbf + phpcs + prettier + eslint + security scan
│   │   └── prompt-context.sh          # Git status injection (opt-in)
│   └── skills/
│       ├── code-review/               # Architectural code reviews
│       ├── config-management/         # Config export/import, Config Split, Recipes
│       ├── ddev/                      # DDEV environment management
│       ├── debug/                     # Code-level troubleshooting
│       ├── drush/                     # Drush CLI reference + deprecated commands
│       ├── drupal-expert/             # Drupal knowledge base + references
│       ├── drupal-frontend-expert/    # Twig, SDC, theming + references
│       ├── drupal-security/           # Proactive security + checklist
│       ├── drupal-site-builder-expert/# Views, content types, config + references
│       ├── generate-tests/            # PHPUnit test generation + references
│       ├── migrate/                   # Migration management
│       ├── performance/               # Caching, queries, BigPipe, profiling
│       ├── refactor/                  # Code smell detection and refactoring
│       ├── scaffold/                  # Module/component generation
│       ├── solr-setup/                # DDEV Solr configuration
│       └── update-module/             # Safe contrib module updates
├── .prettierrc.json                   # Prettier config (JS/CSS/Twig/YAML/JSON)
├── phpstan.neon                       # PHPStan config (generated by setup)
├── CLAUDE.md                          # Generated per project (not from this repo)
└── ...
```

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with `bin/setup.sh --dry-run` on a sample Drupal project
5. Submit a pull request

When adding new skills, follow the existing pattern: create a directory under `.claude/skills/` with a `SKILL.md` containing frontmatter (name, description) and comprehensive guidance.
