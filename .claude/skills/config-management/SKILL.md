---
name: config-management
description: Drupal configuration management expertise. Use when working with config export/import, Config Split, config overrides, config schema, or Recipes.
---

# Drupal Configuration Management Expert

You are an expert in Drupal's configuration management system.

## Core Concepts

Drupal stores configuration as YAML files in the database. The config sync workflow:

```
Database (active) ←→ drush cex/cim ←→ File system (sync directory)
                                           ↕
                                        Git repository
```

## Config Export/Import

### Export Configuration

```bash
# Export all active config to sync directory
ddev drush cex -y

# Review what changed
git diff config/sync/

# Export specific config type
ddev drush config:export --diff
```

### Import Configuration

```bash
# Import config from sync directory to database
ddev drush cim -y

# Preview changes before importing
ddev drush cim --preview=diff

# Partial import (single file)
ddev drush config:import --partial --source=/path/to/config -y
```

### Common Workflow

```bash
# Developer workflow: pull changes, import config, clear cache
git pull
ddev composer install
ddev drush cim -y
ddev drush updb -y
ddev drush cr
```

## Config Split

Config Split allows environment-specific configuration (e.g., devel module enabled only on dev).

### Setup

```bash
ddev composer require drupal/config_split
ddev drush en config_split -y
```

### Configuration

Define splits at `/admin/config/development/configuration/config-split`:

| Split | Purpose | Example |
|-------|---------|---------|
| `dev` | Development tools | devel, webprofiler, dblog |
| `stage` | Staging overrides | Stage file proxy, search index config |
| `prod` | Production hardening | Syslog, config_readonly, aggregation |

### Split Types

- **Complete split**: Config entirely managed by the split (e.g., devel.settings)
- **Conditional split**: Config exists in default sync but values differ per environment

### settings.php Configuration

```php
// In settings.php or settings.local.php
// Activate the appropriate split per environment

// Development
$config['config_split.config_split.dev']['status'] = TRUE;
$config['config_split.config_split.prod']['status'] = FALSE;

// Production
$config['config_split.config_split.dev']['status'] = FALSE;
$config['config_split.config_split.prod']['status'] = TRUE;
```

### Export with Splits

```bash
# Export respects active splits
ddev drush cex -y

# Verify split directory has the right files
ls config/split/dev/
```

## Config Overrides

Override config values without changing the stored config.

### settings.php Overrides

```php
// Override system site name
$config['system.site']['name'] = 'My Dev Site';

// Override mail system for dev
$config['system.mail']['interface']['default'] = 'test_mail_collector';

// Disable CSS/JS aggregation on dev
$config['system.performance']['css']['preprocess'] = FALSE;
$config['system.performance']['js']['preprocess'] = FALSE;
```

### Module-based Overrides

```php
// In a custom module: implement config override service
// my_module.services.yml
services:
  my_module.config_override:
    class: Drupal\my_module\ConfigOverride
    tags:
      - { name: config.factory.override }
```

### Override Priority

1. settings.php overrides (highest)
2. Module overrides (via `config.factory.override` service)
3. Config Split
4. Active configuration in database (lowest)

**Important**: Overrides are NOT exported. They only affect runtime behavior.

## Config Ignore

Prevent specific config from being imported (useful for environment-specific content).

```bash
ddev composer require drupal/config_ignore
ddev drush en config_ignore -y
```

### Common Ignore Patterns

Configure at `/admin/config/development/configuration/ignore`:

```
# Ignore system site info (different per environment)
system.site

# Ignore specific keys
system.site:name
system.site:mail

# Ignore all views displays (content-managed)
views.view.* ~views.view.important_view

# Ignore webform submissions config
webform.webform.*
```

## Config Schema

**Every custom config MUST have a schema.** Without schema, config validation and translation break.

### Schema Location

```
my_module/config/schema/my_module.schema.yml
```

### Schema Examples

```yaml
# Simple settings
my_module.settings:
  type: config_object
  label: 'My Module settings'
  mapping:
    enabled:
      type: boolean
      label: 'Enable feature'
    api_key:
      type: string
      label: 'API Key'
    max_items:
      type: integer
      label: 'Maximum items'
    allowed_types:
      type: sequence
      label: 'Allowed content types'
      sequence:
        type: string
        label: 'Content type'

# Config entity
my_module.type.*:
  type: config_entity
  label: 'My Type'
  mapping:
    id:
      type: string
      label: 'Machine name'
    label:
      type: label
      label: 'Label'
    description:
      type: text
      label: 'Description'
    settings:
      type: mapping
      label: 'Settings'
      mapping:
        weight:
          type: integer
          label: 'Weight'
```

### Validate Schema

```bash
# Check for schema errors
ddev drush config:inspect my_module.settings
```

## Config Readonly (Production)

Prevent config changes on production:

```bash
ddev composer require drupal/config_readonly
ddev drush en config_readonly -y
```

```php
// settings.php — enable on production
if (getenv('ENVIRONMENT') === 'production') {
  $settings['config_readonly'] = TRUE;
}

// Allow specific forms to still save
$settings['config_readonly_whitelist_patterns'] = [
  'system.site',
];
```

## Recipes (Drupal 10.3+)

Recipes are composable config packages that apply configuration once (not synced).

### Using Recipes

```bash
# Apply a core recipe
ddev exec php core/scripts/drupal recipe core/recipes/standard

# Apply a contrib recipe
ddev exec php core/scripts/drupal recipe recipes/my_recipe
```

### Recipe Structure

```
my_recipe/
├── recipe.yml          # Recipe definition
├── config/
│   └── *.yml           # Config to apply
└── content/            # Optional default content
```

### recipe.yml

```yaml
name: 'My Recipe'
description: 'Sets up a blog with standard fields'
type: 'Content type'
recipes:
  - core/recipes/tags_taxonomy
config:
  import:
    node: '*'
  actions:
    node.type.article:
      ensure_exists:
        label: 'Blog Post'
```

## Handling Config Conflicts

### During Import

```bash
# See what would change
ddev drush cim --preview=diff

# If conflicts, review and resolve
ddev drush cex -y  # Re-export to see current state
git diff config/    # Compare
```

### Common Conflict Patterns

1. **UUID mismatch**: Config exists with different UUID — delete and reimport
2. **Missing dependency**: Config references module not enabled — enable module first
3. **Schema change**: Module update changed config schema — run `drush updb` first

### Resolution Strategy

```bash
# 1. Run database updates first
ddev drush updb -y

# 2. Try import
ddev drush cim -y

# 3. If partial failure, export to see delta
ddev drush cex -y
git diff config/

# 4. Resolve manually and re-import
ddev drush cim -y
```

## Best Practices

1. **Always export after changes**: `ddev drush cex -y` after any admin UI changes
2. **Review diffs before committing**: `git diff config/` to verify expected changes
3. **Schema is mandatory**: Every custom config needs a schema file
4. **Never edit sync files manually** unless you know exactly what you're doing
5. **Use Config Split** for environment-specific modules (devel, stage_file_proxy)
6. **Use Config Ignore** for content-managed config (webforms, menus with content)
7. **Deploy order**: `composer install` → `drush updb` → `drush cim` → `drush cr`

## Related Skills

- **drupal-expert** — General Drupal development patterns
- **drupal-site-builder-expert** — Content types, Views, Layout Builder configuration
- **update-module** — Module updates and config changes
- **ddev** — Environment management
