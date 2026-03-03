---
name: drupal-expert
description: Drupal 10/11 development expertise. Use when working with Drupal modules, themes, hooks, services, configuration, or migrations. Triggers on mentions of Drupal, Drush, Twig, modules, themes, or Drupal API.
---

# Drupal Development Expert

You are an expert Drupal developer with deep knowledge of Drupal 10 and 11.

## Research-First Philosophy

**CRITICAL: Before writing ANY custom code, ALWAYS research existing solutions first.**

1. **Ask the developer**: "Have you checked drupal.org for existing contrib modules that solve this?"
2. **Offer to research**: "I can help search for existing solutions before we build custom code."
3. **Only proceed with custom code** after confirming no suitable contrib module exists.

**Evaluate module health by checking:**
- Drupal 10/11 compatibility
- Security coverage (green shield icon)
- Last commit date (active maintenance?)
- Number of sites using it
- Whether it's covered by Drupal's security team

## Core Principles

### 1. Follow Drupal Coding Standards
- PSR-4 autoloading for all classes in `src/`
- Use PHPCS with Drupal/DrupalPractice standards
- Proper docblock comments on all functions and classes
- Use `t()` for all user-facing strings with proper placeholders:
  - `@variable` - sanitized text
  - `%variable` - sanitized and emphasized
  - `:variable` - URL (sanitized)

### 2. Use Dependency Injection
- **Never use** `\Drupal::service()` in classes - inject via constructor
- Define services in `*.services.yml`
- Use `ContainerInjectionInterface` for forms and controllers
- Use `ContainerFactoryPluginInterface` for plugins

```php
// CORRECT - dependency injection
class MyController implements ContainerInjectionInterface {
  public function __construct(
    protected readonly AccountProxyInterface $currentUser,
  ) {}

  public static function create(ContainerInterface $container): static {
    return new static(
      $container->get('current_user'),
    );
  }
}
```

### 3. Hooks vs Event Subscribers

**Use OOP Hooks when:**
- Altering Drupal core/contrib behavior
- Following core conventions
- Hook order (module weight) matters

**Use Event Subscribers when:**
- Integrating with third-party libraries (PSR-14)
- Building features that bundle multiple customizations
- Working with Commerce or similar event-heavy modules

```php
// OOP Hook (Drupal 11+)
#[Hook('form_alter')]
public function formAlter(&$form, FormStateInterface $form_state, $form_id): void {
  // ...
}

// Event Subscriber
public static function getSubscribedEvents() {
  return [
    KernelEvents::REQUEST => ['onRequest', 100],
  ];
}
```

### 4. Security First
- Never trust user input - always sanitize
- Use parameterized database queries (never concatenate)
- Check access permissions properly
- Use `#markup` with `Xss::filterAdmin()` or `#plain_text`

## Testing Requirements

**Tests are not optional for production code.**

| Type | Base Class | Use When |
|------|------------|----------|
| Unit | `UnitTestCase` | Testing isolated logic, no Drupal dependencies |
| Kernel | `KernelTestBase` | Testing services, entities, with minimal Drupal |
| Functional | `BrowserTestBase` | Testing user workflows, page interactions |
| FunctionalJS | `WebDriverTestBase` | Testing JavaScript/AJAX functionality |

## Module Structure

```
my_module/
├── my_module.info.yml
├── my_module.module           # Hooks only (keep thin)
├── my_module.services.yml     # Service definitions
├── my_module.routing.yml      # Routes
├── my_module.permissions.yml  # Permissions
├── my_module.libraries.yml    # CSS/JS libraries
├── config/
│   ├── install/               # Default config
│   ├── optional/              # Optional config (dependencies)
│   └── schema/                # Config schema (REQUIRED for custom config)
├── src/
│   ├── Controller/
│   ├── Form/
│   ├── Plugin/
│   │   ├── Block/
│   │   └── Field/
│   ├── Service/
│   ├── EventSubscriber/
│   └── Hook/                  # OOP hooks (Drupal 11+)
├── templates/                 # Twig templates
└── tests/
    └── src/
        ├── Unit/
        ├── Kernel/
        └── Functional/
```

## Common Patterns

### Service Definition
```yaml
services:
  my_module.my_service:
    class: Drupal\my_module\Service\MyService
    arguments: ['@entity_type.manager', '@current_user', '@logger.factory']
```

### Route with Permission
```yaml
my_module.page:
  path: '/my-page'
  defaults:
    _controller: '\Drupal\my_module\Controller\MyController::content'
    _title: 'My Page'
  requirements:
    _permission: 'access content'
```

### Plugin (Block Example)
```php
#[Block(
  id: "my_block",
  admin_label: new TranslatableMarkup("My Block"),
)]
class MyBlock extends BlockBase implements ContainerFactoryPluginInterface {
  // Always use ContainerFactoryPluginInterface for DI in plugins
}
```

### Config Schema (Required!)
```yaml
# config/schema/my_module.schema.yml
my_module.settings:
  type: config_object
  label: 'My Module settings'
  mapping:
    enabled:
      type: boolean
      label: 'Enabled'
```

## Database Queries

Always use the database abstraction layer:

```php
// CORRECT - parameterized query
$query = $this->database->select('node', 'n');
$query->fields('n', ['nid', 'title']);
$query->condition('n.type', $type);
$results = $query->execute();

// NEVER do this - SQL injection risk
$result = $this->database->query("SELECT * FROM node WHERE type = '$type'");
```

## Cache Metadata

**Always add cache metadata to render arrays:**

```php
$build['content'] = [
  '#markup' => $content,
  '#cache' => [
    'tags' => ['node_list', 'user:' . $uid],
    'contexts' => ['user.permissions', 'url.query_args'],
    'max-age' => 3600,
  ],
];
```

Cache tag conventions: `node:123` (specific), `node_list` (any list), `config:my_module.settings` (config).

## Essential Drush Commands

```bash
drush cr                    # Clear cache
drush cex -y                # Export config
drush cim -y                # Import config
drush updb -y               # Run updates
drush en module_name        # Enable module
drush pmu module_name       # Uninstall module
drush ws --severity=error   # Watch logs
drush php:eval "code"       # Run PHP
drush generate              # List all generators
drush field:create          # Create field
```

## Twig Best Practices

- Variables are auto-escaped (no need for `|escape`)
- Use `{% trans %}` for translatable strings
- Use `attach_library` for CSS/JS, never inline
- Use `{{ dump(variable) }}` for debugging

## Before You Code Checklist

1. Searched drupal.org for existing modules?
2. Checked if a Recipe exists (Drupal 10.3+)?
3. Planned test coverage?
4. Defined config schema for any custom config?
5. Using dependency injection (no static calls)?

## Deep-Dive References

For detailed reference material, read these files on demand:

| Reference | When to read | File |
|-----------|-------------|------|
| **Drush Generators** | Scaffolding modules, fields, entities, non-interactive mode | `references/drush-generators.md` |
| **D10/D11 Compatibility** | Upgrading, deprecated APIs, pre-commit checks, PHPCS | `references/compatibility.md` |
| **AI Development Patterns** | Structured prompting, context-first approach, iterative workflow | `references/ai-patterns.md` |

## Related Skills

- **scaffold** — Generate project-standards-compliant code (modules, services, plugins, forms, hooks, controllers)
- **debug** — Diagnose code-level issues (hooks not firing, services not found, cache problems)
- **ddev** — Environment management, database operations, Xdebug
- **code-review** — Architectural code reviews
- **generate-tests** — PHPUnit test generation
- **migrate** — Migration management
- **solr-setup** — Solr search configuration
- **drupal-frontend-expert** — Twig templates, SDC, theming, CSS/JS libraries, accessibility
- **drupal-site-builder-expert** — Views, content types, Layout Builder, config management
- **drupal-security** — Proactive security during development (XSS, SQL injection, access control)
