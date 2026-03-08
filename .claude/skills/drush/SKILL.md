---
name: drush
description: Use when working with Drush CLI for Drupal site management - running cache rebuilds, config imports/exports, database queries, PHP evaluation, module management, user operations, or troubleshooting Drush commands that no longer exist
---

# Drush CLI Reference

Command-line interface for Drupal site management. Drush runs in the Drupal bootstrap context, giving full access to the Drupal API.

Based on [factorial-io/skills/drush](https://github.com/factorial-io/skills) (MIT licensed).

## Command Structure

**All commands follow: `drush <command> [arguments] [--options]`**

Most commands have short aliases. Use `drush list` to see all available commands, `drush <command> --help` for details.

**In DDEV:** Prefix with `ddev` (e.g., `ddev drush cr`).

## Quick Reference

| Task | Command | Alias |
|------|---------|-------|
| Cache rebuild | `drush cache:rebuild` | `drush cr` |
| Config export | `drush config:export` | `drush cex` |
| Config import | `drush config:import` | `drush cim` |
| Config get | `drush config:get <name>` | `drush cget <name>` |
| Config set | `drush config:set <name> <key> <value>` | `drush cset <name> <key> <value>` |
| Database update | `drush updatedb` | `drush updb` |
| Module install | `drush pm:install <module>` | `drush en <module>` |
| Module uninstall | `drush pm:uninstall <module>` | `drush pmu <module>` |
| List modules | `drush pm:list` | `drush pml` |
| User login link | `drush user:login` | `drush uli` |
| User info | `drush user:information <name>` | |
| Watchdog logs | `drush watchdog:show` | `drush ws` |
| Status overview | `drush status` | `drush st` |
| Run cron | `drush cron` | |
| State get | `drush state:get <key>` | `drush sget <key>` |
| State set | `drush state:set <key> <value>` | `drush sset <key> <value>` |
| Deploy (updb+cim+cr) | `drush deploy` | |
| Code generation | `drush generate` | `drush gen` |
| Site requirements | `drush core:requirements` | `drush rq` |
| Watchdog tail | `drush watchdog:tail` | `drush wt` |
| Queue list | `drush queue:list` | |
| Queue run | `drush queue:run <name>` | |
| Security check | `drush pm:security` | |

## Running PHP Code

Drush can evaluate arbitrary PHP within full Drupal bootstrap context.

### Inline PHP with eval

```bash
# Simple expression
ddev drush php:eval "echo \Drupal::VERSION;"

# Load and inspect an entity
ddev drush php:eval "\$node = \Drupal\node\Entity\Node::load(1); echo \$node->getTitle();"

# Query entities
ddev drush php:eval "\$ids = \Drupal::entityTypeManager()->getStorage('node')->getQuery()->accessCheck(FALSE)->condition('type', 'article')->range(0, 5)->execute(); print_r(\$ids);"

# Access a service
ddev drush php:eval "echo \Drupal::service('extension.list.module')->getPath('node');"

# Get current user
ddev drush php:eval "echo \Drupal::currentUser()->getAccountName();"
```

**Shell escaping:** Use single quotes around the PHP string in fish/zsh to avoid `$` expansion, or escape `\$` in double quotes.

### Interactive PHP shell

```bash
# Opens interactive REPL with Drupal bootstrapped
ddev drush php:cli
```

### Running PHP scripts

```bash
# Execute a PHP file with full Drupal bootstrap
ddev drush php:script path/to/script.php

# Pass arguments (available as $extra in the script)
ddev drush php:script path/to/script.php -- arg1 arg2
```

## SQL Operations

### Direct SQL queries

```bash
# Run a SQL query directly
ddev drush sql:query "SELECT nid, title FROM node_field_data LIMIT 10"

# Count content by type
ddev drush sql:query "SELECT type, COUNT(*) as count FROM node_field_data GROUP BY type"

# Check a specific table
ddev drush sql:query "DESCRIBE users_field_data"
```

### Database shell and dumps

```bash
# Open interactive database client
ddev drush sql:cli

# Create database dump
ddev drush sql:dump > dump.sql
ddev drush sql:dump --gzip --result-file=/tmp/dump.sql

# Import SQL file
ddev drush sql:cli < dump.sql

# Show database connection info
ddev drush sql:conf

# Sanitize user data (emails, passwords) for safe copies
ddev drush sql:sanitize
```

## Configuration Management

### Get configuration

```bash
# Get entire config object (YAML output)
ddev drush cget system.site

# Get a specific key
ddev drush cget system.site name
ddev drush cget system.site page.front

# Show pending config changes
ddev drush config:status
```

### Set and edit configuration

```bash
# Set a single value
ddev drush cset system.site name "My Site"

# Set nested value
ddev drush cset system.site page.front "/node"

# Edit full config object in editor
ddev drush config:edit system.site

# Delete a config object
ddev drush config:delete <config-name>
```

### Export/import workflow

```bash
# Export active config to sync directory
ddev drush cex -y

# Import config from sync directory
ddev drush cim -y

# Import partial (does not delete active-only config)
ddev drush cim --partial

# Import from non-default directory
ddev drush cim --source=/path/to/config
```

## Module Management

```bash
# List all modules with status
ddev drush pml
ddev drush pml --status=enabled
ddev drush pml --type=module --status="not installed"

# Install module(s)
ddev drush en module_name
ddev drush en module_one module_two

# Uninstall module(s)
ddev drush pmu module_name

# Check if module is enabled
ddev drush pml --filter=module_name
```

## User Management

```bash
# Generate one-time login link
ddev drush uli
ddev drush uli --uid=1
ddev drush uli admin

# Create user
ddev drush user:create username --mail="user@example.com" --password="pass"

# Add/remove role
ddev drush user:role:add editor admin
ddev drush user:role:remove editor admin

# Block/unblock user
ddev drush user:block username
ddev drush user:unblock username

# Reset password
ddev drush user:password admin "newpassword"
```

## Roles and Permissions

```bash
# List all roles
ddev drush role:list

# Get permissions for a specific role
ddev drush cget user.role.editor

# List all available permissions
ddev drush php:eval 'echo implode("\n", array_keys(\Drupal::service("user.permissions")->getPermissions()));'

# Search for specific permissions
ddev drush php:eval 'echo implode("\n", array_keys(\Drupal::service("user.permissions")->getPermissions()));' | grep administer

# Grant/remove permissions
ddev drush role:perm:add anonymous 'access content'
ddev drush role:perm:add editor 'access content,administer nodes'
ddev drush role:perm:remove anonymous 'access content'

# Create/delete a role
ddev drush role:create editor Editor
ddev drush role:delete editor
```

## Code Generation

Scaffolding via `drush generate` (powered by drupal-code-generator):

```bash
# Interactive: pick a generator from the list
ddev drush generate

# Generate a specific component
ddev drush generate module
ddev drush generate controller
ddev drush generate form:config
ddev drush generate plugin:block
ddev drush generate entity:content
ddev drush generate hook

# Preview without writing files
ddev drush generate controller --dry-run

# Pre-fill answers to skip prompts
ddev drush generate controller --answer=Example --answer=example
```

Common generators: `module`, `controller`, `field`, `hook`, `form:simple`, `form:config`, `form:confirm`, `plugin:block`, `plugin:action`, `entity:content`, `entity:configuration`, `service-provider`, `drush:command`.

## Useful Options

| Option | Description |
|--------|-------------|
| `--format=json` | JSON output (useful for scripting/parsing) |
| `--format=yaml` | YAML output |
| `-y` | Auto-confirm prompts |
| `-v` / `--debug` | Verbose / debug output |
| `--uri=http://example.com` | Set base URI |

## Deprecated and Removed Commands

Commands that **NO LONGER EXIST** in modern Drush (12+). **Never suggest these:**

| Removed Command | What to Use Instead |
|-----------------|---------------------|
| `drush entity-updates` / `drush entup` | `drush updatedb` — entity schema updates are handled by update hooks |
| `drush pm-download` / `drush dl` | `composer require drupal/<module>` |
| `drush pm-update` / `drush up` | `composer update` then `drush updb` |
| `drush pm-enable` (old syntax) | `drush pm:install` / `drush en` |
| `drush pm-disable` / `drush dis` | `drush pm:uninstall` / `drush pmu` (no "disable" concept) |
| `drush features-*` | Use config management (`drush cex`/`drush cim`) |
| `drush registry-rebuild` / `drush rr` | `drush cr` |
| `drush variable-get/set` | `drush sget`/`drush sset` (State) or `drush cget`/`drush cset` (Config) |

**Rule:** If a command uses a hyphen (e.g., `entity-updates`), it is likely old syntax. Modern Drush uses colons (e.g., `cache:rebuild`).

## Common Mistakes

| Wrong | Right | Why |
|-------|-------|-----|
| `drush entity-updates` | `drush updb` | `entity-updates` removed in Drush 11+ |
| `drush dl module` | `composer require drupal/module` | Package management via Composer |
| `drush up` | `composer update && drush updb` | Updates via Composer, then DB updates |
| `drush dis module` | `drush pmu module` | No disable concept; uninstall instead |
| `drush variable-get x` | `drush sget x` or `drush cget x` | Variables removed; use State or Config |
| `drush cim` before `drush updb` | `drush updb && drush cim` or `drush deploy` | Update hooks may add schemas needed by config |
| Missing `-y` in scripts | Add `-y` flag | Commands prompt for confirmation and hang without it |
| Missing `accessCheck(FALSE)` in `php:eval` queries | Always add `->accessCheck(FALSE)` | Required since Drupal 9.2 |

## Related Skills

- **ddev** — DDEV environment management (wraps drush commands with `ddev` prefix)
- **drupal-expert** — Drupal development patterns and coding standards
- **config-management** — Detailed config export/import, Config Split, Recipes
- **scaffold** — Module/component generation with project standards
- **debug** — Troubleshoot issues using drush and watchdog logs
