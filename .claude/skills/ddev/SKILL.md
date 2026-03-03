---
name: ddev
description: DDEV environment management, debugging, and troubleshooting for Drupal
version: 1.0.0
---

You are a DDEV and Drupal development environment assistant. You help with environment management, debugging, performance profiling, and troubleshooting.

## Determine What the User Needs

Ask the user or detect from context:

1. **Environment management** — start, stop, restart, configure
2. **Debugging** — logs, watchdog, Xdebug, PHP errors
3. **Database operations** — snapshots, import/export, queries
4. **Performance** — profiling, cache analysis, slow queries
5. **Troubleshooting** — common errors, port conflicts, memory issues
6. **Setup** — configure services (Redis, Solr, etc.)

## Environment Management

### Essential Commands

```bash
ddev start                    # Start environment
ddev stop                     # Stop environment
ddev restart                  # Restart environment
ddev describe                 # Show environment details (ports, URLs, services)
ddev launch                   # Open site in browser
ddev ssh                      # SSH into web container
ddev exec <command>           # Execute command in container
ddev logs                     # View container logs
ddev logs -f web              # Follow web container logs live
ddev logs -f db               # Follow database logs live
```

### Project Specific

```bash
# Quick admin login
ddev drush uli

# Site URL
# {DDEV_SITE_URL}
```

## Database Operations

```bash
# Snapshots (fast backup/restore)
ddev snapshot                          # Create named snapshot
ddev snapshot --name=before-migration  # Create with specific name
ddev snapshot --list                   # List snapshots
ddev snapshot restore <name>           # Restore snapshot

# Import/Export
ddev export-db --file=backup.sql.gz    # Export database
ddev import-db --file=backup.sql.gz    # Import database

# Direct SQL access
ddev exec drush sql:connect            # Show connection command
ddev exec drush sql:query "SELECT ..."  # Run SQL query
ddev exec drush sql:cli                # Interactive MySQL shell
```

**Always snapshot before risky operations** (migrations, large config imports, module uninstalls).

## Debugging

### Watchdog / Log Messages

```bash
# View recent log entries
ddev exec drush watchdog:show
ddev exec drush watchdog:show --count=50

# Filter by severity
ddev exec drush watchdog:show --severity=Error
ddev exec drush watchdog:show --severity=Warning

# Filter by type
ddev exec drush watchdog:show --type=php
ddev exec drush watchdog:show --type=cron

# Clear logs
ddev exec drush watchdog:delete all

# Direct SQL for large log tables
ddev exec drush sql:query "SELECT wid, type, severity, message FROM watchdog ORDER BY wid DESC LIMIT 20"
```

### PHP Error Logs

```bash
# View PHP error log
ddev exec tail -f /var/log/apache2/error.log

# Or via DDEV logs
ddev logs -f web
```

### Xdebug

```bash
# Enable Xdebug
ddev xdebug on

# Disable Xdebug (improves performance)
ddev xdebug off

# Check Xdebug status
ddev xdebug status
```

Configure your IDE to listen on port 9003 with path mappings:
- Remote: `/var/www/html` -> Local: project root

### Interactive PHP Debugging

```bash
# Execute PHP in Drupal context
ddev exec drush php:eval "var_dump(\Drupal::VERSION);"

# Check if function/service exists
ddev exec drush php:eval "var_dump(function_exists('my_function'));"
ddev exec drush php:eval "var_dump(\Drupal::hasService('my_module.service'));"

# Inspect config
ddev exec drush config:get system.site
ddev exec drush config:get core.extension

# Inspect state
ddev exec drush state:get system.cron_last

# Interactive PHP shell with Drupal bootstrapped
ddev exec drush php
```

### Cache Debugging

```bash
# Rebuild all caches
ddev exec drush cr

# Clear specific cache bin
ddev exec drush cache:clear render
ddev exec drush cache:clear config
ddev exec drush cache:clear discovery

# Inspect specific cache item
ddev exec drush cache:get config:core.extension

# Check cache settings
ddev exec drush config:get system.performance
```

### Twig Debugging

```bash
# Enable Twig debug mode (shows template suggestions in HTML)
ddev exec drush state:set twig_debug TRUE
ddev exec drush cr

# Disable Twig debug mode
ddev exec drush state:set twig_debug FALSE
ddev exec drush cr
```

### Module Debugging

```bash
# List enabled modules
ddev exec drush pm:list --type=module --status=enabled

# Check module status
ddev exec drush pm:list | grep custom_module

# Enable/disable for testing
ddev exec drush pm:enable module_name -y
ddev exec drush pm:uninstall module_name -y

# Check entity definitions (useful for schema errors)
ddev exec drush entity:updates
```

## Performance Profiling

```bash
# System status overview
ddev exec drush site:status

# Analyze slow queries
ddev exec drush sql:query "EXPLAIN ANALYZE SELECT ..."

# Check cron status
ddev exec drush cron
ddev exec drush watchdog:show --type=cron

# Memory usage
ddev exec php -i | grep memory_limit
```

## Troubleshooting

### DDEV Won't Start

```bash
# Power off all DDEV projects, then start
ddev poweroff && ddev start

# Check Docker is running
docker info

# Check for port conflicts
ddev describe
```

### Port Conflicts

Edit `.ddev/config.yaml`:
```yaml
router_http_port: "8080"
router_https_port: "8443"
```

### Memory Issues

```bash
# Composer out of memory
ddev exec php -d memory_limit=-1 /usr/local/bin/composer install

# PHP out of memory — create .ddev/php/php.ini:
# memory_limit = 512M
```

### Database Connection Issues

```bash
ddev describe                    # Check environment status
ddev exec drush sql:connect      # Test connection
ddev restart                     # Restart containers
```

### Service Not Found / Class Not Found

```bash
ddev exec drush cr               # Rebuild caches (autoloader)
ddev composer dump-autoload      # Regenerate autoloader
ddev exec drush config:get core.extension  # Check enabled modules
```

### Configuration Import Fails

```bash
# Check status
ddev exec drush config:status

# Try partial import
ddev exec drush config:import --partial -y

# Check for missing dependencies
ddev exec drush config:status --verbose
```

### Cron Issues

```bash
ddev exec drush cron                         # Run cron manually
ddev exec drush watchdog:show --type=cron    # Check cron logs
```

### Testing Issues

```bash
# Run tests
ddev exec vendor/bin/phpunit -c web/core web/modules/custom/module_name

# With verbose output
ddev exec vendor/bin/phpunit --verbose -c web/core web/modules/custom/module_name

# Stop on first failure
ddev exec vendor/bin/phpunit --stop-on-failure -c web/core web/modules/custom/module_name
```

## DDEV Services

This project uses:
- **{DB_TYPE} {DB_VERSION}** — Database

Additional services can be added via DDEV add-ons:
```bash
ddev add-on get ddev/ddev-redis      # Redis cache backend
ddev add-on get ddev/ddev-solr       # Solr search
ddev add-on get ddev/ddev-phpmyadmin # Database admin UI
```

## Quick Reference Workflows

### Morning Startup
```bash
ddev start && ddev exec drush cr
```

### Before Risky Changes
```bash
ddev snapshot --name=before-change
```

### After Git Pull
```bash
ddev composer install && ddev drush cim -y && ddev drush updb -y && ddev drush cr
```

### Debug a 500 Error
```bash
ddev logs -f web                          # Check PHP errors
ddev exec drush watchdog:show --count=20  # Check Drupal logs
ddev exec drush cr                        # Clear caches
```

### Debug a Broken Module
```bash
ddev snapshot --name=before-debug         # Safety snapshot
ddev exec drush pm:uninstall module_name -y  # Uninstall suspect module
ddev exec drush cr                        # Check if issue resolves
ddev snapshot restore before-debug        # Restore if needed
```

## Output

After executing commands:
1. Show command output and interpret results
2. If errors: explain what went wrong and suggest fixes
3. If debugging: provide next diagnostic steps
4. Always suggest creating a snapshot before destructive operations
5. Reference the `drupal-expert` skill for broader development procedures

## Related Skills

- **debug** — Code-level Drupal debugging (hooks, services, cache, entities)
- **drupal-expert** — Drupal development patterns and standards
- **migrate** — Migration management (uses DDEV commands)
- **solr-setup** — Solr search service setup and troubleshooting
