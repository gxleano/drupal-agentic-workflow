# Drupal Agentic Workflow for Claude Code

A reusable template providing 11 AI-powered skills and a post-generation
lint/format hook for Drupal 10/11 projects with Claude Code.

## What's Included

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

Plus:
- **Post-generation hook** — Prettier formatting + phpcs/eslint/stylelint linting + security scan
- **Starter theme scaffold** — Ready-to-use theme template in `assets/theme-template/`

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
- Copies all 11 skills and the lint/format hook into `.claude/`
- Appends Drupal coding rules to your existing `CLAUDE.md`
- Installs `.prettierrc.json`
- Generates `AI_CONTEXT.md` templates for custom modules missing one

The script is fully idempotent — safe to run multiple times. It never overwrites files you've customized.

Options:
```
~/drupal-agentic-workflow/bin/setup.sh --dry-run .    # Preview without changes
~/drupal-agentic-workflow/bin/setup.sh --force .      # Skip Drupal detection
~/drupal-agentic-workflow/bin/setup.sh --help         # Show help
```

### 4. Fill In Project Details

In your `CLAUDE.md`, complete:
- **Custom Modules** — list each module with `AI_CONTEXT.md` link
- **Contributed Modules** — list installed contrib
- Any project-specific conventions

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

This creates a `CLAUDE.md` with basic project information (name, structure,
commands). Review and fill in any project-specific details it generates.

### 3. Add Drupal Rules

Open [`CLAUDE-TEMPLATE.md`](CLAUDE-TEMPLATE.md) and copy the sections into
your project's `CLAUDE.md`. These sections provide:

- **Critical Code Rules** — PHP/Drupal 11 standards, DI, plugins, hooks,
  caching, security
- **Code Quality** — Prettier + phpcs/phpcbf/phpstan workflow and post-generation hooks
- **Frontend / Theming** — Twig, SDC, libraries, Drupal.behaviors conventions
- **Security** — Proactive security patterns and pre-commit checklist
- **Custom Modules** — Template for listing your modules with AI_CONTEXT.md
  links
- **Contributed Modules** — Template for listing installed contrib

### 4. Fill In Project Details

In your `CLAUDE.md`, complete:

- **Custom Modules section** — list each module with a link to its
  `AI_CONTEXT.md`
- **Contributed Modules section** — list installed contrib modules/themes
- Any project-specific conventions or rules

### 5. Create AI_CONTEXT.md for Each Module

For each custom module, create an `AI_CONTEXT.md` at the module root:

```
web/modules/custom/your_module/AI_CONTEXT.md
```

This file should contain: architecture overview, class map, data flow,
key decisions. Ask Claude: *"Create an AI_CONTEXT.md for {module_name}"*

### 6. Update Testing Context

Edit `.claude/skills/generate-tests/references/testing-context.md` with:
- Your existing test coverage per module
- Test base classes available
- Known test gaps

### 7. Install Prettier (Optional)

For automatic formatting of JS, CSS, Twig, YAML, and JSON files:

```bash
npm install --save-dev prettier
# For Twig formatting (optional):
npm install --save-dev prettier-plugin-twig-melody
```

The post-generation hook will automatically use Prettier when available and
gracefully skip if not installed.

### 8. Configure Permissions (Optional)

Create `.claude/settings.local.json` for your permission preferences.
This file is project-local and should NOT be committed to version control.

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
```

## File Structure

```
your-drupal-project/
├── .claude/
│   ├── settings.json                  # Skill and hook configuration
│   ├── hooks/
│   │   ├── README.md                  # Hook documentation
│   │   └── post-generation-lint.sh    # Prettier + phpcs + eslint + security scan
│   └── skills/
│       ├── code-review/               # Architectural code reviews
│       ├── ddev/                      # DDEV environment management
│       ├── debug/                     # Code-level troubleshooting
│       ├── drupal-expert/             # Drupal knowledge base + references
│       ├── drupal-frontend-expert/    # Twig, SDC, theming + references
│       ├── drupal-security/           # Proactive security + checklist
│       ├── drupal-site-builder-expert/# Views, content types, config + references
│       ├── generate-tests/            # PHPUnit test generation + references
│       ├── migrate/                   # Migration management
│       ├── scaffold/                  # Module/component generation
│       └── solr-setup/                # DDEV Solr configuration
├── .prettierrc.json                   # Prettier config (JS/CSS/Twig/YAML/JSON)
├── CLAUDE.md                          # Generated per project (not from this repo)
└── ...
```

## Requirements

- Claude Code CLI installed
- DDEV local development environment
- Drupal 10 or 11 project using `drupal/recommended-project`
- PHP 8.3+
- Composer 2
- Node.js 18+ (for Prettier/eslint/stylelint — optional, gracefully skipped)
