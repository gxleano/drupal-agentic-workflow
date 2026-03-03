---
name: debug
description: Diagnose and fix common Drupal code-level issues (hooks, services, cache, entities, routes, permissions)
version: 1.0.0
---

You are a Drupal 11 code-level debugging assistant. You help diagnose why custom code isn't working — hooks not firing, services not found, cache not invalidating, entities not loading, routes returning 403/404, etc.

**This skill complements the `ddev` skill.** Use `ddev` for environment issues (containers, ports, PHP errors). Use this skill for *Drupal code logic* issues.

## Determine the Problem Category

Ask the user or detect from context:

| Category | Symptoms |
|----------|----------|
| **Hook not firing** | alter/presave/insert hook has no effect |
| **Service not found** | `ServiceNotFoundException`, class not found |
| **Cache not invalidating** | Stale content after save, changes not visible |
| **Entity query issues** | Empty results, access denied, wrong data |
| **Route/controller 404** | Page not found for custom route |
| **Permission/access 403** | Access denied unexpectedly |
| **Plugin not discovered** | Block/widget/formatter not appearing |
| **Config issues** | Missing config, schema mismatch, import fails |
| **AJAX/form issues** | Form rebuild fails, AJAX callback errors |
| **Event subscriber not firing** | Subscriber registered but never called |

---

## 1. Hook Not Firing

### OOP Hooks (src/Hook/)

**Checklist:**

```bash
# 1. Is the module enabled?
ddev drush pm:list --type=module --status=enabled | grep MODULE_NAME

# 2. Is the hook class registered in services.yml?
ddev exec grep -r "Hook\\" web/modules/custom/MODULE_NAME/MODULE_NAME.services.yml

# 3. Is autowire enabled for the hook class?
# Verify: either explicit service entry with autowire:true
# OR _defaults autowire with resource: src/ scanning

# 4. Is src/Hook/ excluded from autowiring?
# Check services.yml exclude list — src/Hook/ should NOT be excluded

# 5. Clear cache (hook discovery is cached)
ddev drush cr

# 6. Verify class is autoloaded
ddev exec drush php:eval "var_dump(class_exists('Drupal\\MODULE_NAME\\Hook\\CLASSNAME'));"
```

**Common causes:**
- `src/Hook/` listed in `exclude:` in services.yml — **remove it from excludes**
- Missing `autowire: true` on the service definition
- Wrong namespace — must match `Drupal\{module}\Hook\{ClassName}`
- Module not enabled
- Cache not cleared after adding hook class

### Procedural Hooks (.module)

```bash
# 1. Verify the hook function exists and has correct name
ddev exec grep -n "function MODULE_NAME_hook_name" web/modules/custom/MODULE_NAME/MODULE_NAME.module

# 2. Check for typos in hook name
# hook_form_alter, NOT hook_form_alters

# 3. Check module weight (maybe another module overrides)
ddev exec drush php:eval "print_r(\Drupal::moduleHandler()->getModuleList());"
```

### form_alter Hooks

```bash
# 1. Verify the form ID you're targeting
# Add temporary debug to see the actual form_id:
ddev exec drush php:eval "
  // Enable Devel if available for form ID inspection
  var_dump(\Drupal::hasService('devel.dumper'));
"

# 2. Check if you're using form_alter vs form_FORM_ID_alter
# hook_form_alter fires for ALL forms
# hook_form_user_login_form_alter fires only for that form
```

---

## 2. Service Not Found

```bash
# 1. Check if the service ID exists in the container
ddev exec drush php:eval "var_dump(\Drupal::hasService('MODULE_NAME.service_name'));"

# 2. List all services from the module
ddev exec drush php:eval "
  \$container = \Drupal::getContainer();
  \$ids = \$container->getServiceIds();
  foreach (\$ids as \$id) {
    if (str_contains(\$id, 'MODULE_NAME')) { echo \$id . PHP_EOL; }
  }
"

# 3. Check services.yml syntax
ddev exec php -r "var_dump(yaml_parse_file('/var/www/html/web/modules/custom/MODULE_NAME/MODULE_NAME.services.yml'));"

# 4. Regenerate autoloader
ddev composer dump-autoload

# 5. Clear all caches
ddev drush cr
```

**Common causes:**
- Typo in service ID (services.yml vs code reference)
- services.yml syntax error (indentation, missing colon)
- Class doesn't exist at the namespace path
- Module not enabled
- Missing `use` statement for the interface
- Argument references non-existent service (e.g. `@logger.channel.MODULE_NAME` without defining the channel)

---

## 3. Cache Not Invalidating

### Render Cache

```bash
# 1. Check that render array has #cache metadata
# Missing #cache = Drupal uses default (permanent cache, no tags)

# 2. Verify cache tags are being set correctly
# After saving an entity, check if the right tags are invalidated:
ddev exec drush php:eval "
  \$tags = ['node:123', 'node_list'];
  \Drupal::service('cache_tags.invalidator')->invalidateTags(\$tags);
  echo 'Tags invalidated: ' . implode(', ', \$tags);
"

# 3. Disable render cache temporarily for debugging
# In settings.local.php:
# $settings['cache']['bins']['render'] = 'cache.backend.null';
# $settings['cache']['bins']['page'] = 'cache.backend.null';
# $settings['cache']['bins']['dynamic_page_cache'] = 'cache.backend.null';

# 4. Clear specific cache bin
ddev drush cache:clear render
ddev drush cache:clear dynamic_page_cache
ddev drush cache:clear page
```

**Checklist for render arrays:**
```php
// Every render array MUST have:
$build['#cache'] = [
  'tags' => ['node:' . $node->id(), 'node_list'],  // WHAT invalidates it
  'contexts' => ['user.permissions', 'url.path'],    // WHAT varies it
  'max-age' => Cache::PERMANENT,                     // HOW LONG to cache
];
```

**Common causes:**
- Missing `#cache` tags — Drupal doesn't know when to invalidate
- Missing `#cache` contexts — same cached version shown to all users
- Using `max-age: 0` everywhere (kills performance)
- Not invalidating tags after programmatic entity updates
- BigPipe/Dynamic Page Cache serving stale responses

### Config Cache

```bash
# Config changes not taking effect
ddev drush cr                          # Always first
ddev drush config:status               # Check for overrides
ddev drush config:get MODULE.settings  # Verify actual values
```

---

## 4. Entity Query Issues

```bash
# 1. Debug the query
ddev exec drush php:eval "
  \$query = \Drupal::entityTypeManager()
    ->getStorage('node')
    ->getQuery()
    ->accessCheck(TRUE)
    ->condition('type', 'article')
    ->condition('status', 1)
    ->range(0, 5);
  \$ids = \$query->execute();
  var_dump(\$ids);
"

# 2. Check accessCheck impact — compare with/without
ddev exec drush php:eval "
  // With access check (respects permissions)
  \$with = \Drupal::entityTypeManager()->getStorage('node')->getQuery()
    ->accessCheck(TRUE)->condition('type', 'article')->count()->execute();

  // Without access check (all entities, regardless of perms)
  \$without = \Drupal::entityTypeManager()->getStorage('node')->getQuery()
    ->accessCheck(FALSE)->condition('type', 'article')->count()->execute();

  echo \"With access: \$with, Without access: \$without\";
"

# 3. Check if entities exist at all
ddev exec drush php:eval "
  \$storage = \Drupal::entityTypeManager()->getStorage('node');
  \$count = \$storage->getQuery()->accessCheck(FALSE)->count()->execute();
  echo \"Total nodes: \$count\";
"
```

**Common causes:**
- Missing `->accessCheck(TRUE)` — **required in Drupal 11**, throws deprecation/error
- Running as anonymous user without permission
- Wrong condition field name (use `field_name` not `field_name.value` for simple fields)
- Entity type doesn't exist or isn't installed
- Status condition missing (unpublished content filtered out)

---

## 5. Route/Controller 404

```bash
# 1. Check if route exists
ddev exec drush eval "var_dump(\Drupal::service('router.route_provider')->getRouteByName('MODULE.route_name'));"

# 2. List all routes from module
ddev exec drush eval "
  \$routes = \Drupal::service('router.route_provider')->getAllRoutes();
  foreach (\$routes as \$name => \$route) {
    if (str_contains(\$name, 'MODULE_NAME')) {
      echo \$name . ' => ' . \$route->getPath() . PHP_EOL;
    }
  }
"

# 3. Rebuild router
ddev drush cr

# 4. Check routing.yml syntax
ddev exec php -r "var_dump(yaml_parse_file('/var/www/html/web/modules/custom/MODULE_NAME/MODULE_NAME.routing.yml'));"
```

**Common causes:**
- Routing YAML indentation error
- Controller class not found (wrong namespace)
- Missing `_controller` or `_form` in defaults
- Route path conflicts with another module
- Module not enabled

---

## 6. Permission/Access 403

```bash
# 1. Check user permissions
ddev exec drush php:eval "
  \$account = \Drupal::currentUser();
  echo 'User: ' . \$account->getAccountName() . PHP_EOL;
  echo 'Roles: ' . implode(', ', \$account->getRoles()) . PHP_EOL;
  echo 'Has permission: ' . var_export(\$account->hasPermission('PERMISSION_NAME'), true);
"

# 2. Check the route's access requirements
ddev exec drush eval "
  \$route = \Drupal::service('router.route_provider')->getRouteByName('MODULE.route_name');
  print_r(\$route->getRequirements());
"

# 3. Check if permission is defined
ddev exec grep -r "PERMISSION_NAME" web/modules/custom/MODULE_NAME/*.permissions.yml
```

**Common causes:**
- Permission string doesn't match between routing.yml and permissions.yml
- User role doesn't have the permission
- Custom access checker returns FALSE
- `_access: 'TRUE'` missing quotes in routing.yml (must be string `'TRUE'`)

---

## 7. Plugin Not Discovered

```bash
# 1. Clear plugin cache
ddev drush cr

# 2. Check plugin manager can find it
ddev exec drush php:eval "
  // For blocks:
  \$definitions = \Drupal::service('plugin.manager.block')->getDefinitions();
  foreach (\$definitions as \$id => \$def) {
    if (str_contains(\$id, 'MODULE_NAME') || str_contains(\$id, 'my_block')) {
      echo \$id . ' => ' . \$def['class'] . PHP_EOL;
    }
  }
"

# 3. Verify class is autoloaded
ddev exec drush php:eval "var_dump(class_exists('Drupal\\MODULE\\Plugin\\Block\\MyBlock'));"

# 4. Check for PHP syntax errors
ddev exec php -l web/modules/custom/MODULE_NAME/src/Plugin/Block/MyBlock.php
```

**Common causes:**
- Wrong directory structure (must be `src/Plugin/Block/` for blocks)
- Missing or malformed `#[Block(...)]` attribute
- PHP syntax error in the class
- Namespace doesn't match file path
- Module not enabled
- `#[Block]` attribute missing `id:` parameter

---

## 8. Config Issues

```bash
# 1. Check config status
ddev drush config:status

# 2. Check specific config
ddev drush config:get MODULE_NAME.settings

# 3. Check schema validation
ddev exec drush php:eval "
  \$typed_config = \Drupal::service('config.typed');
  \$config = \Drupal::config('MODULE_NAME.settings');
  \$definition = \$typed_config->getDefinition('MODULE_NAME.settings');
  var_dump(\$definition);
"

# 4. Check for missing schema
# If you see "No schema" warnings, create config/schema/MODULE_NAME.schema.yml
```

**Common causes:**
- Config file in `config/install/` but module was already installed (reinstall module)
- Schema doesn't match config structure (extra/missing keys)
- Config overridden in settings.php (`$config['MODULE.settings']['key'] = value`)

---

## 9. AJAX/Form Issues

```bash
# 1. Check browser console for JS errors
# Open DevTools > Console, look for 400/500 responses

# 2. Check Drupal AJAX response
ddev exec drush watchdog:show --type=php --count=10

# 3. Verify callback method exists and returns correct type
# AJAX callback must return a render array or AjaxResponse
```

**Common causes:**
- AJAX callback returns wrong type (must be render array or `AjaxResponse`)
- `#ajax` wrapper ID doesn't match element in form
- Missing `'#prefix' => '<div id="wrapper-id">'` on the target element
- Form rebuild changes structure, breaking AJAX wrapper reference

---

## 10. Event Subscriber Not Firing

```bash
# 1. Check subscriber is registered
ddev exec drush php:eval "
  \$dispatcher = \Drupal::service('event_dispatcher');
  \$listeners = \$dispatcher->getListeners('kernel.request');
  foreach (\$listeners as \$listener) {
    if (is_array(\$listener)) {
      echo get_class(\$listener[0]) . '::' . \$listener[1] . PHP_EOL;
    }
  }
"

# 2. Check services.yml has event_subscriber tag
ddev exec grep -A 3 "SubscriberClass" web/modules/custom/MODULE_NAME/MODULE_NAME.services.yml
```

**Common causes:**
- Missing `tags: [{ name: event_subscriber }]` in services.yml
- `getSubscribedEvents()` returns wrong event name
- Priority too low — another subscriber stops propagation
- Autowiring does **not** auto-tag event subscribers

---

## Diagnostic Quick Reference

```bash
# Is the module enabled?
ddev drush pm:list | grep MODULE_NAME

# Is the class autoloaded?
ddev exec drush php:eval "var_dump(class_exists('Drupal\\MODULE\\ClassName'));"

# Is the service registered?
ddev exec drush php:eval "var_dump(\Drupal::hasService('module.service'));"

# What config exists?
ddev exec drush config:list | grep MODULE_NAME

# Recent errors?
ddev exec drush watchdog:show --severity=Error --count=20

# PHP syntax check?
ddev exec php -l web/modules/custom/MODULE_NAME/src/ClassName.php

# Nuclear option — clear everything
ddev drush cr && ddev composer dump-autoload
```

## Related Skills

- **ddev** — Environment-level debugging (containers, logs, Xdebug, database)
- **drupal-expert** — Drupal patterns, coding standards, DI guidance
- **scaffold** — If the issue is structural, re-scaffold the component correctly
- **drupal-frontend-expert** — Debug Twig template, theming, and rendering issues
- **drupal-security** — Investigate security-related issues
