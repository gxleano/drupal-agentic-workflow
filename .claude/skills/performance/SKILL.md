---
name: performance
description: Drupal performance optimization expertise. Use when working on caching, database queries, asset optimization, lazy loading, BigPipe, or profiling.
---

# Drupal Performance Optimization Expert

You are an expert in Drupal performance optimization across all layers.

## Cache Layers

Drupal has multiple cache layers. Optimize from outermost to innermost:

```
Browser Cache
  └─ CDN / Reverse Proxy (Varnish)
      └─ Page Cache (anonymous users)
          └─ Dynamic Page Cache (authenticated users)
              └─ Render Cache (blocks, entities, views)
                  └─ Internal Cache (config, discovery, etc.)
```

### Page Cache (Anonymous)

For anonymous users, entire pages are cached. Configure at `/admin/config/development/performance`:

```php
// settings.php — max-age for page cache
$config['system.performance']['cache']['page']['max_age'] = 86400; // 24 hours
```

**When it works**: Anonymous users, no session, no personalization.
**When it breaks**: Any per-user content, CSRF tokens, form tokens.

### Dynamic Page Cache (Authenticated)

Caches render arrays for authenticated users using cache contexts to vary output.

**Key cache contexts**:
- `user` — per user
- `user.permissions` — per permission set (most efficient for auth users)
- `user.roles` — per role combination
- `url.query_args` — varies by query string
- `url.path` — varies by path
- `session` — per session
- `languages` — per language

### Render Cache

All render arrays MUST include cache metadata:

```php
$build = [
  '#markup' => $content,
  '#cache' => [
    'tags' => ['node:123', 'node_list'],
    'contexts' => ['user.permissions'],
    'max-age' => 3600,
  ],
];
```

**Cache tag conventions**:
- Entity: `node:123`, `user:456`, `taxonomy_term:789`
- Entity list: `node_list`, `user_list`
- Config: `config:my_module.settings`
- Custom: `my_module:custom_tag`

**Invalidation**:
```php
// Invalidate specific tags
\Drupal\Core\Cache\Cache::invalidateTags(['node:123']);

// Entity saves auto-invalidate their tags
$node->save(); // Invalidates node:{nid} and node_list
```

## BigPipe and Lazy Builders

BigPipe sends the page shell immediately and streams personalized content later.

### Lazy Builders

Use lazy builders for personalized or uncacheable content in an otherwise cacheable page:

```php
$build['user_greeting'] = [
  '#lazy_builder' => [
    'my_module.greeting_builder:build',
    [$uid],
  ],
  '#create_placeholder' => TRUE,
];
```

```php
// Service class
class GreetingBuilder {
  public function build(int $uid): array {
    return [
      '#markup' => $this->t('Hello, @name', ['@name' => $user->getDisplayName()]),
      '#cache' => [
        'contexts' => ['user'],
        'tags' => ['user:' . $uid],
      ],
    ];
  }
}
```

Register as a service with `#[AutowireLocator]` or in `*.services.yml`.

### When to Use Lazy Builders

- User-specific content on an otherwise anonymous-cacheable page
- Expensive calculations that shouldn't block initial render
- Content that changes frequently (live counters, notifications)

## Database Query Optimization

### Avoid N+1 Queries

```php
// BAD: N+1 — loads each entity individually
foreach ($nids as $nid) {
  $node = $this->entityTypeManager->getStorage('node')->load($nid);
}

// GOOD: Single query, bulk load
$nodes = $this->entityTypeManager->getStorage('node')->loadMultiple($nids);
```

### Entity Query Best Practices

```php
$query = $this->entityTypeManager->getStorage('node')->getQuery()
  ->accessCheck(TRUE)
  ->condition('type', 'article')
  ->condition('status', 1)
  ->range(0, 50)  // Always limit results
  ->sort('created', 'DESC');
$nids = $query->execute();

// Bulk load results
$nodes = $this->entityTypeManager->getStorage('node')->loadMultiple($nids);
```

### Database Select Optimization

```php
// Use specific fields instead of loading full entities
$query = $this->database->select('node_field_data', 'n');
$query->fields('n', ['nid', 'title']);  // Only needed columns
$query->condition('n.type', 'article');
$query->range(0, 50);
$query->addTag('node_access');  // Respect access control
$results = $query->execute();
```

### Index Custom Tables

```php
// In hook_schema() or hook_update_N()
$schema['my_table'] = [
  'fields' => [...],
  'indexes' => [
    'status_created' => ['status', 'created'],
  ],
];
```

## Views Optimization

### Views Caching

Always configure cache on Views:

| Cache Type | Use When |
|------------|----------|
| Tag-based | Content changes unpredictably (default, recommended) |
| Time-based | Content changes on a schedule |
| None | Never (except during development) |

### Views Performance Tips

1. **Limit fields**: Only select fields you display
2. **Use pager**: Never load unbounded results
3. **Disable SQL rewrite**: Only if access checking is handled elsewhere
4. **Use rendered entity**: More cacheable than field-by-field rendering
5. **Avoid Views PHP**: Use custom plugins instead

### Views Query Optimization

```php
// Custom Views field plugin with optimized query
public function query() {
  // Add only needed joins
  $this->ensureMyTable();
  $this->field_alias = $this->query->addField($this->tableAlias, $this->realField);
}
```

## Redis / Memcache Integration

### Redis with DDEV

```bash
ddev get ddev/ddev-redis
ddev restart
```

```php
// settings.php
$settings['redis.connection']['host'] = 'redis';
$settings['redis.connection']['port'] = 6379;
$settings['cache']['default'] = 'cache.backend.redis';

// Don't cache these bins in Redis
$settings['cache']['bins']['form'] = 'cache.backend.database';
$settings['cache']['bins']['bootstrap'] = 'cache.backend.chainedfast';
$settings['cache']['bins']['discovery'] = 'cache.backend.chainedfast';
```

### Monitor Redis

```bash
ddev redis-cli monitor  # Watch all commands
ddev redis-cli info memory  # Memory usage
ddev redis-cli dbsize  # Number of keys
```

## Asset Optimization

### CSS/JS Aggregation

```php
// settings.php — enable on production
$config['system.performance']['css']['preprocess'] = TRUE;
$config['system.performance']['js']['preprocess'] = TRUE;
```

### Library Optimization

```yaml
# my_module.libraries.yml — attach only what's needed
my_library:
  css:
    theme:
      css/my-styles.css: { minified: true }
  js:
    js/my-script.js: { minified: true }
  dependencies:
    - core/drupal
    # Don't depend on jQuery unless required
```

```php
// Attach library only where needed, not globally
$build['#attached']['library'][] = 'my_module/my_library';
```

## Profiling

### Webprofiler (Development)

```bash
ddev composer require drupal/webprofiler
ddev drush en webprofiler -y
```

Provides toolbar with:
- Database queries (count, time, duplicates)
- Cache hits/misses
- Events dispatched
- Memory usage
- Timeline

### Xdebug Profiling

```bash
# Enable Xdebug in DDEV
ddev xdebug on

# Generate cachegrind profiles
ddev exec php -d xdebug.mode=profile -d xdebug.output_dir=/tmp vendor/bin/drush cr
```

Analyze with KCachegrind, QCachegrind, or Webgrind.

### Quick Performance Checks

```bash
# Check cache hit ratio
ddev drush cr && time ddev drush cr  # Second run should be fast

# Count database queries on a page
ddev drush ws --severity=Notice | grep -c "query"

# Check for large config objects
ddev drush config:list | wc -l
```

## Performance Checklist

Before deploying, verify:

- [ ] Page cache enabled with appropriate max-age
- [ ] CSS/JS aggregation enabled
- [ ] Views have caching configured (not "None")
- [ ] No N+1 query patterns (use `loadMultiple()`)
- [ ] Entity queries have `accessCheck()` and `range()`
- [ ] Render arrays include `#cache` metadata
- [ ] Lazy builders used for personalized content on cached pages
- [ ] No `\Drupal::` calls in hot paths (use DI)
- [ ] Database queries use indexes for WHERE/ORDER BY columns
- [ ] Libraries attached only where needed (not globally)

## Related Skills

- **drupal-expert** — General Drupal development patterns
- **debug** — Troubleshoot performance issues at code level
- **ddev** — Environment configuration, Redis/Memcache setup
