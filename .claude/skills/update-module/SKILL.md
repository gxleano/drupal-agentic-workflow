---
name: update-module
description: Safe contrib module update workflow with pre-checks, rollback strategy, and verification. Use when updating Drupal contrib modules or themes.
---

# Drupal Module Update Assistant

You assist with safely updating Drupal contributed modules and themes.

## Pre-Update Checklist

**ALWAYS perform these steps before any update:**

1. **Create a database snapshot** (rollback safety net):
   ```bash
   ddev snapshot --name=pre-update-$(date +%Y%m%d)
   ```

2. **Check current version**:
   ```bash
   ddev composer show drupal/{module} | grep -E 'versions|descrip'
   ```

3. **Check available updates**:
   ```bash
   ddev composer outdated drupal/{module}
   ```

4. **Check release notes** on drupal.org for breaking changes:
   - Look for CHANGELOG.md in the module
   - Check if update hooks exist (`*.install` file changes)
   - Note any new dependencies

## Update Workflow

### Single Module Update

```bash
# 1. Update the module
ddev composer update drupal/{module} --with-dependencies

# 2. Run database updates
ddev drush updb -y

# 3. Clear caches
ddev drush cr

# 4. Export any config changes
ddev drush cex -y
```

### Security Update (Urgent)

Security updates should be applied immediately. Classification:

| SA Rating | Action | Timeframe |
|-----------|--------|-----------|
| Critical | Update immediately, deploy ASAP | Hours |
| Moderately Critical | Update within the day | 24 hours |
| Less Critical | Schedule for next release | 1-2 weeks |

```bash
# Check for security updates specifically
ddev drush pm:security

# Apply security update
ddev snapshot --name=pre-security-update
ddev composer update drupal/{module} --with-dependencies
ddev drush updb -y
ddev drush cr
ddev drush cex -y
```

### Bulk Update Strategy

For updating multiple modules at once:

```bash
# 1. Snapshot first
ddev snapshot --name=pre-bulk-update

# 2. Check all outdated packages
ddev composer outdated "drupal/*"

# 3. Update all Drupal packages
ddev composer update "drupal/*" --with-dependencies

# 4. Run updates and clear cache
ddev drush updb -y
ddev drush cr

# 5. Check for errors
ddev drush ws --severity=Error --count=20

# 6. Export config
ddev drush cex -y

# 7. Review config changes
git diff config/
```

## Post-Update Verification

After every update, verify:

1. **Check for errors in the log**:
   ```bash
   ddev drush ws --severity=Error --count=20
   ```

2. **Run PHPStan** for deprecation warnings:
   ```bash
   ddev exec phpstan analyze web/modules/custom/
   ```

3. **Run tests** if available:
   ```bash
   ddev exec phpunit --group={module}
   ```

4. **Review exported config changes**:
   ```bash
   git diff config/
   ```

5. **Smoke test the site**:
   ```bash
   ddev drush cr
   ddev launch
   ```

## Rollback

If anything goes wrong after an update:

```bash
# Restore database snapshot
ddev snapshot restore --latest

# Restore composer files
git checkout -- composer.json composer.lock

# Reinstall original dependencies
ddev composer install

# Clear cache
ddev drush cr
```

## Major Version Upgrades

For major version changes (e.g., 1.x to 2.x):

1. Read the upgrade guide/CHANGELOG thoroughly
2. Check if patches need updating (`composer-patches`)
3. Look for renamed services, hooks, or configuration
4. Test in a feature branch:
   ```bash
   git checkout -b update/{module}-{version}
   ddev snapshot --name=pre-major-update
   ddev composer require drupal/{module}:^{version} --with-dependencies
   ddev drush updb -y
   ddev drush cr
   ```

## Handling Update Conflicts

### Composer Conflicts

```bash
# See why a package can't update
ddev composer why-not drupal/{module} {version}

# Check dependency tree
ddev composer depends drupal/{module}
```

### Patch Conflicts

If using `cweagans/composer-patches`:
1. Check if the patch still applies after update
2. Re-roll the patch if needed
3. Remove the patch if the issue is fixed upstream

## Related Skills

- **ddev** — Environment management, snapshots
- **drupal-expert** — Drupal development patterns
- **config-management** — Config export/import workflows
