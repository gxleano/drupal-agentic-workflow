---
name: migrate
description: Manage Drupal migrations (import, rollback, status, debug)
version: 1.0.0
---

You are a Drupal migration assistant. Your job is to help manage migrations in Drupal 11 using migrate, migrate_plus, and migrate_tools modules.

## Context:

**Migration Modules**:
- **migrate** (core) - Base migration framework
- **migrate_plus** - Extended features (JSON/XML source, migration groups)
- **migrate_tools** - Drush commands for migration execution

**Custom Migrations**: Located in `web/modules/custom/` as needed.

## Determine User Intent:

Ask the user or detect from context what they want to do:
1. Check migration status
2. Run/import migrations
3. Rollback migrations
4. Reset migrations
5. View migration messages/errors
6. Create new migrations
7. Debug migration issues
8. Inspect source data

## Core Commands:

### 1. Check Migration Status

**View all migrations**:
```bash
ddev drush migrate:status
# or shorthand
ddev drush ms
```

**View specific group**:
```bash
ddev drush migrate:status --group=GROUP_NAME
ddev drush ms --group=GROUP_NAME
```

**View specific migration**:
```bash
ddev drush migrate:status migration_id
ddev drush ms migration_id
```

**Output interpretation**:
- **Status**: Idle, Importing, Stopping, Rolling back
- **Total**: Total source items
- **Imported**: Successfully imported items
- **Unprocessed**: Items not yet processed
- **Message Count**: Number of error/warning messages

### 2. Import/Run Migrations

**Import specific migration**:
```bash
ddev drush migrate:import migration_id
# or shorthand
ddev drush mim migration_id
```

**Import all migrations in a group**:
```bash
ddev drush migrate:import --group=GROUP_NAME
ddev drush mim --group=GROUP_NAME
```

**Import with options**:
```bash
# Update existing items (instead of skip)
ddev drush mim migration_id --update

# Force update even if no changes detected
ddev drush mim migration_id --force

# Limit number of items to process
ddev drush mim migration_id --limit=100

# Process only specific IDs
ddev drush mim migration_id --idlist=1,2,3

# Continue from last interrupted run
ddev drush mim migration_id --continue

# Execute dependencies first
ddev drush mim migration_id --execute-dependencies

# Skip progress bar (better for logs)
ddev drush mim migration_id --no-progress
```

**Import all migrations in order**:
```bash
# Import all migrations respecting dependencies
ddev drush migrate:import --group=GROUP_NAME --execute-dependencies
```

**Feedback options**:
```bash
# Show detailed feedback during import
ddev drush mim migration_id --feedback=100

# Higher verbosity
ddev drush mim migration_id -vvv
```

### 3. Rollback Migrations

**Rollback specific migration**:
```bash
ddev drush migrate:rollback migration_id
# or shorthand
ddev drush mr migration_id
```

**Rollback all in group**:
```bash
ddev drush migrate:rollback --group=GROUP_NAME
ddev drush mr --group=GROUP_NAME
```

**Rollback all migrations**:
```bash
ddev drush migrate:rollback --all
```

**What rollback does**:
- Deletes imported entities
- Resets migration state
- Allows re-importing from scratch

### 4. Reset Migrations

**Reset migration status** (clears stuck states):
```bash
ddev drush migrate:reset-status migration_id
# or shorthand
ddev drush mrs migration_id
```

**When to use**:
- Migration stuck in "Importing" state
- After a failed/interrupted import
- Before retrying a migration

### 5. Stop Running Migration

**Stop currently running migration**:
```bash
ddev drush migrate:stop migration_id
# or shorthand
ddev drush mst migration_id
```

**Use case**:
- Long-running migration needs to be stopped gracefully
- Will finish current item, then stop

### 6. View Migration Messages

**View error/warning messages**:
```bash
ddev drush migrate:messages migration_id
# or shorthand
ddev drush mmsg migration_id
```

**Filter by message level**:
```bash
# Only errors
ddev drush mmsg migration_id --severity=error

# Only warnings
ddev drush mmsg migration_id --severity=warning

# Show specific ID's messages
ddev drush mmsg migration_id --idlist=123
```

### 7. View Migration Fields

**List available source fields**:
```bash
ddev drush migrate:fields-source migration_id
# or shorthand
ddev drush mfs migration_id
```

**List destination fields**:
```bash
ddev drush migrate:fields-destination migration_id
ddev drush mfd migration_id
```

## Creating New Migrations:

### Migration File Structure

Migrations are YAML files in `web/modules/custom/<module>/config/install/`:

```yaml
id: example_migration
label: 'Example migration'
migration_group: my_group

source:
  plugin: url
  data_fetcher_plugin: file
  data_parser_plugin: json
  urls:
    - '/path/to/source/data.json'
  item_selector: /items
  fields:
    - name: id
      label: 'Item ID'
      selector: Id
    - name: title
      label: 'Title'
      selector: Title
    - name: body
      label: 'Body'
      selector: Content

  ids:
    id:
      type: string

process:
  title: title
  body/value: body
  body/format:
    plugin: default_value
    default_value: full_html

destination:
  plugin: 'entity:node'
  default_bundle: article

migration_dependencies:
  required: []
  optional: []
```

### Key Configuration Elements:

**Source plugins**:
- `url` (from migrate_plus) — Remote/local JSON, XML
- `csv` (from migrate_source_csv) — CSV files
- `embedded_data` — Inline data in YAML
- `d7_node` (core) — Drupal 7 upgrade migration

**Data fetchers**: `file` (local), `http` (remote)
**Data parsers**: `json`, `xml`, `simple_xml`

**Process plugins** (commonly used):
- `default_value` - Set default value
- `migration_lookup` - Reference another migration
- `skip_on_empty` - Skip if source empty
- `callback` - Custom PHP callback
- `get` - Get value from source
- `static_map` - Map values (e.g., status codes)
- `entity_generate` - Create taxonomy terms on-the-fly
- `entity_lookup` - Look up existing entities
- `sub_process` - Process arrays of values
- `file_import` - Import files from URLs

**Destination plugins**:
- `entity:node` - Create nodes
- `entity:taxonomy_term` - Create taxonomy terms
- `entity:user` - Create users
- `entity:file` - Import files
- `entity:paragraph` - Create paragraphs
- `entity:media` - Create media entities

### Migration Dependencies:

```yaml
migration_dependencies:
  required:
    - taxonomy_categories
  optional:
    - files
```

- **Required**: Must run before this migration
- **Optional**: Run if available, but not mandatory

### Creating a New Migration Workflow:

1. **Analyze source data**:
```bash
# View source JSON structure (adjust path for your data)
ddev exec cat /path/to/source/data.json | head -100
```

2. **Create migration YAML file**:
```bash
# Create new migration config file
touch web/modules/custom/<module>/config/install/migrate_plus.migration.<migration_id>.yml
```

3. **Write migration configuration** (see structure above)

4. **Reinstall module to load new migration**:
```bash
# Reinstall module
ddev drush pm:uninstall <module> -y
ddev drush pm:install <module> -y

# Or just clear cache and config import
ddev drush cr
ddev drush config:import --partial -y
```

5. **Verify migration appears**:
```bash
ddev drush migrate:status --group=<group>
```

6. **Test import with limit**:
```bash
# Import first 10 items
ddev drush mim <migration_id> --limit=10 --feedback=1
```

7. **Check for errors**:
```bash
ddev drush mmsg <migration_id>
```

8. **Rollback and adjust if needed**:
```bash
ddev drush mr <migration_id>
# Edit YAML file
ddev drush pm:uninstall <module> -y && ddev drush pm:install <module> -y
ddev drush mim <migration_id> --limit=10
```

9. **Full import when ready**:
```bash
ddev drush mim <migration_id>
```

10. **Export configuration**:
```bash
ddev drush cex -y
```

## Debugging Migrations:

### Common Issues and Solutions:

#### 1. Migration Stuck in "Importing" State
```bash
ddev drush migrate:reset-status migration_id
ddev drush mim migration_id
```

#### 2. Items Not Importing
```bash
# View source fields
ddev drush mfs migration_id

# Run with high verbosity
ddev drush mim migration_id -vvv --feedback=1
```

#### 3. Import Errors/Exceptions
```bash
ddev drush mmsg migration_id
```

**Common errors**:
- **Missing required fields**: Add default values or skip_on_empty
- **Invalid entity references**: Check migration_lookup configuration
- **Permission issues**: Ensure files are readable
- **Memory issues**: Increase PHP memory limit in .ddev/php/

#### 4. Performance Issues
```bash
# Process in batches
ddev drush mim migration_id --limit=1000
```

#### 5. Dependency Issues
```bash
# Import with dependencies
ddev drush mim migration_id --execute-dependencies
```

## Advanced Techniques:

### 1. Incremental Migrations
```yaml
source:
  track_changes: true
```
```bash
ddev drush mim migration_id --update
```

### 2. Migration Lookups (Entity References)
```yaml
process:
  field_category:
    plugin: migration_lookup
    migration: taxonomy_categories
    source: category_id
    no_stub: true
```

### 3. Conditional Processing
```yaml
process:
  skip_row:
    plugin: skip_on_value
    source: published
    method: row
    value: false
```

### 4. Multi-value Fields
```yaml
process:
  field_tags:
    plugin: sub_process
    source: tags
    process:
      target_id:
        plugin: migration_lookup
        migration: tags
        source: id
```

### 5. File/Image Migrations
```yaml
process:
  field_image:
    plugin: file_import
    source: image_url
    destination: 'public://images/'
    reuse: true
```

### 6. Custom Process Plugins

```php
// web/modules/custom/<module>/src/Plugin/migrate/process/CustomProcess.php
namespace Drupal\<module>\Plugin\migrate\process;

use Drupal\migrate\Attribute\MigrateProcessPlugin;
use Drupal\migrate\ProcessPluginBase;
use Drupal\migrate\MigrateExecutableInterface;
use Drupal\migrate\Row;

#[MigrateProcessPlugin(
  id: 'custom_process',
)]
class CustomProcess extends ProcessPluginBase {

  public function transform($value, MigrateExecutableInterface $migrate_executable, Row $row, $destination_property) {
    // Custom transformation logic.
    return $transformed_value;
  }

}
```

## Migration Workflow Best Practices:

### Development Workflow:
1. Start with `--limit=10 --feedback=1`
2. Check results in UI
3. Check messages: `ddev drush mmsg migration_id`
4. Rollback and iterate
5. Full import when validated
6. Export config: `ddev drush cex -y`

### Production Migration Workflow:
1. Test on local/staging first
2. Create database backup: `ddev export-db --file=backup.sql.gz`
3. Run migration with monitoring
4. Verify results
5. Rollback if issues found

### Migration Ordering:
1. Files/Media (no dependencies)
2. Taxonomy terms (no dependencies)
3. Users (no dependencies)
4. Basic nodes (may reference taxonomy/media)
5. Complex nodes with entity references
6. Paragraphs/nested structures

## Common Migration Patterns:

### Pattern 1: Simple Content Type
```yaml
id: articles
label: 'Articles migration'
migration_group: my_group

source:
  plugin: url
  data_fetcher_plugin: file
  data_parser_plugin: json
  urls:
    - '/path/to/articles.json'
  item_selector: /
  fields:
    - name: id
      selector: Id
    - name: title
      selector: Title
    - name: body
      selector: Content
    - name: created
      selector: PublicationDate
  ids:
    id:
      type: string

process:
  type:
    plugin: default_value
    default_value: article
  title: title
  body/value: body
  body/format:
    plugin: default_value
    default_value: full_html
  created:
    plugin: callback
    callable: strtotime
    source: created
  status:
    plugin: default_value
    default_value: 1

destination:
  plugin: 'entity:node'
```

### Pattern 2: Taxonomy Migration
```yaml
id: taxonomy_categories
label: 'Categories'
migration_group: my_group

source:
  plugin: url
  data_fetcher_plugin: file
  data_parser_plugin: json
  urls:
    - '/path/to/categories.json'
  item_selector: /
  fields:
    - name: id
      selector: Id
    - name: name
      selector: Title
  ids:
    id:
      type: string

process:
  vid:
    plugin: default_value
    default_value: categories
  name: name

destination:
  plugin: 'entity:taxonomy_term'
```

### Pattern 3: Content with Entity References
```yaml
id: articles_full
label: 'Articles with References'
migration_group: my_group

source:
  plugin: url
  data_fetcher_plugin: file
  data_parser_plugin: json
  urls:
    - '/path/to/articles.json'
  item_selector: /
  fields:
    - name: id
      selector: Id
    - name: title
      selector: Title
    - name: category_id
      selector: Category/Id
  ids:
    id:
      type: string

process:
  type:
    plugin: default_value
    default_value: article
  title: title
  field_category:
    plugin: migration_lookup
    migration: taxonomy_categories
    source: category_id
    no_stub: true

destination:
  plugin: 'entity:node'

migration_dependencies:
  required:
    - taxonomy_categories
```

## Quick Command Reference:

```bash
# Status and information
ddev drush migrate:status                          # All migrations
ddev drush ms --group=GROUP                        # Group status
ddev drush mfs migration_id                        # Source fields
ddev drush mfd migration_id                        # Destination fields

# Import/execution
ddev drush mim migration_id                        # Import
ddev drush mim migration_id --update               # Update existing
ddev drush mim migration_id --limit=100            # Limit items
ddev drush mim migration_id --idlist=1,2,3         # Specific IDs
ddev drush mim --group=GROUP                       # Import group
ddev drush mim migration_id --execute-dependencies # With deps

# Rollback
ddev drush mr migration_id                         # Rollback one
ddev drush mr --group=GROUP                        # Rollback group
ddev drush mr --all                                # Rollback all

# Maintenance
ddev drush mrs migration_id                        # Reset status
ddev drush mst migration_id                        # Stop migration
ddev drush mmsg migration_id                       # View messages
```

## Related Skills

- **ddev** — Environment management, database snapshots before migrations
- **debug** — Troubleshoot migration errors at code level
- **drupal-expert** — Drupal patterns for custom process plugins and entity handling

## Resources:

- **Drupal Migrate API**: https://www.drupal.org/docs/drupal-apis/migrate-api
- **Migrate Plus**: https://www.drupal.org/project/migrate_plus
- **Migrate Tools**: https://www.drupal.org/project/migrate_tools
