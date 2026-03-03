# Drupal 10 to 11 Compatibility Reference

## Key Differences

| Feature | Drupal 10 | Drupal 11 |
|---------|-----------|-----------|
| PHP Version | 8.1+ | 8.3+ |
| Symfony | 6.x | 7.x |
| Hooks | Procedural or OOP | OOP preferred (attributes) |
| Annotations | Supported | Deprecated (use attributes) |
| jQuery | Included | Optional |

## Writing Compatible Code (D10.3+ and D11)

**Use PHP attributes for plugins** (works in D10.2+, required style for D11):

```php
// Modern style (D10.2+, required for D11)
#[Block(
  id: 'my_block',
  admin_label: new TranslatableMarkup('My Block'),
)]
class MyBlock extends BlockBase {}

// Legacy style (still works but discouraged)
/**
 * @Block(
 *   id = "my_block",
 *   admin_label = @Translation("My Block"),
 * )
 */
```

**Use OOP hooks** (D10.3+):

```php
// src/Hook/MyModuleHooks.php
namespace Drupal\my_module\Hook;

use Drupal\Core\Hook\Attribute\Hook;

final class MyModuleHooks {

  #[Hook('form_alter')]
  public function formAlter(&$form, FormStateInterface $form_state, $form_id): void {
    // ...
  }

  #[Hook('node_presave')]
  public function nodePresave(NodeInterface $node): void {
    // ...
  }

}
```

Register hooks class in services.yml:
```yaml
services:
  Drupal\my_module\Hook\MyModuleHooks:
    autowire: true
```

## Deprecated APIs to Avoid

```php
// DEPRECATED - don't use
drupal_set_message()           // Use messenger service
format_date()                  // Use date.formatter service
entity_load()                  // Use entity_type.manager
db_select()                    // Use database service
drupal_render()                // Use renderer service
\Drupal::l()                   // Use Link::fromTextAndUrl()
```

## Check Deprecations

```bash
./vendor/bin/drupal-check modules/custom/
./vendor/bin/phpstan analyze modules/custom/ --level=5
```

## info.yml Compatibility

```yaml
# Support both D10 and D11
core_version_requirement: ^10.3 || ^11

# D11 only
core_version_requirement: ^11
```

## Recipes (D10.3+)

Drupal Recipes provide reusable configuration packages:

```bash
php core/scripts/drupal recipe core/recipes/standard
composer require drupal/recipe_name
php core/scripts/drupal recipe recipes/contrib/recipe_name
```

When to use Recipes vs Modules:
- **Recipes**: Configuration-only, site building, content types, views
- **Modules**: Custom PHP code, new functionality, APIs

## Migration Planning (D10 to D11)

1. Run `drupal-check` for deprecations
2. Update all contrib modules to D11-compatible versions
3. Convert annotations to attributes
4. Consider moving hooks to OOP style
5. Test thoroughly in staging environment

## Pre-Commit Checks

**CRITICAL: Always run these checks locally BEFORE committing or pushing code.**

### Required: Coding Standards (PHPCS)

```bash
./vendor/bin/phpcs -p --colors modules/custom/
./vendor/bin/phpcbf modules/custom/
./vendor/bin/phpcs path/to/MyClass.php
```

**Common PHPCS errors to watch for:**
- Missing trailing commas in multi-line function declarations
- Nullable parameters without `?` type hint
- Missing docblocks
- Incorrect spacing/indentation

### DDEV Shortcut

```bash
ddev exec ./vendor/bin/phpcs -p modules/custom/
ddev exec ./vendor/bin/phpcbf modules/custom/
```

### Full Pre-Commit Checklist

```bash
# 1. Coding standards
./vendor/bin/phpcs -p modules/custom/

# 2. Static analysis
./vendor/bin/phpstan analyze modules/custom/

# 3. Deprecation checks
./vendor/bin/drupal-check modules/custom/

# 4. Run tests
./vendor/bin/phpunit modules/custom/my_module/tests/
```

### Installing PHPCS with Drupal Standards

```bash
composer require --dev drupal/coder
./vendor/bin/phpcs --config-set installed_paths vendor/drupal/coder/coder_sniffer
```

## Sources

- [Drupal 11 Readiness](https://www.drupal.org/docs/upgrading-drupal/how-to-prepare-your-drupal-7-or-8-site-for-drupal-9/deprecation-checking-and-correction-tools)
- [OOP Hooks](https://www.drupal.org/docs/develop/creating-modules/implementing-hooks-in-drupal-11)
- [Drupal Recipes](https://www.drupal.org/docs/extending-drupal/drupal-recipes)
