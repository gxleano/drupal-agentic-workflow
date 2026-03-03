---
name: scaffold
description: Generate Drupal 11 modules, services, plugins, forms, hooks, and controllers following project standards
version: 1.0.0
---

You are a Drupal 11 code scaffolding assistant. You generate standards-compliant code that follows every project convention from CLAUDE.md. This is an **inline skill** — work interactively with the user, not via background agent.

## 1. Determine What to Scaffold

Ask the user or detect from context which scaffold type they need:

| Type | What it generates |
|------|-------------------|
| `module` | New custom module from scratch |
| `service` | Service class + interface + services.yml entry |
| `plugin` | Block, Field Widget, Field Formatter, Action plugin |
| `form` | ConfigFormBase, FormBase, or ConfirmFormBase |
| `controller` | Controller with route + permissions |
| `hook` | OOP Hook class in `src/Hook/` |
| `event-subscriber` | Event subscriber + services.yml registration |
| `entity` | Content entity or config entity scaffold |

If the user says something like "scaffold a block" or "create a new service", map it to the appropriate type above.

## 2. Project Rules (Baked Into Every Template)

**Every generated file MUST follow these rules. Do NOT generate code that violates any of them.**

### PHP
- `declare(strict_types=1);` — first line after `<?php` in every file
- PHP 8.3 features: constructor property promotion, match expressions, named arguments
- `protected readonly` for all injected service properties
- `match` instead of `switch` for simple conditionals
- `static` instead of `self` in `create()` methods and factories
- Fully type all parameters, properties, and return types (no missing types)
- 2-space indentation throughout
- `\Exception` (backslash-prefixed), never `use Exception`
- `@todo` not `TODO:`

### Classes
- `final class` for plugins unless extension is explicitly intended
- `AutowireTrait` for plugins when all services are standard container services
- Fall back to explicit `create()` only when runtime logic decides dependencies
- Constructor injection with **interfaces** (`EntityTypeManagerInterface`, not `EntityTypeManager`)
- Never `\Drupal::` in service classes — always inject via constructor

### Plugins
- `#[Block(...)]` PHP attribute, never `@Block(...)` annotation
- Same for all plugin types: use PHP 8 attributes
- `new TranslatableMarkup(...)` in attributes, never `@Translation(...)`

### Hooks
- `#[Hook]` attribute classes in `src/Hook/` for all new hooks
- Only `hook_theme()`, `hook_preprocess_*()`, `hook_install()`, `hook_update_N()` stay in `.module`
- Group related hooks by domain (`FormHooks`, `EntityHooks`)
- Register hook class in services.yml with `autowire: true`

### Render Arrays & Caching
- All render arrays MUST include `#cache` metadata (tags, contexts, max-age)
- Use `Cache::mergeTags()` / `Cache::mergeContexts()` to combine
- Entity cache tags via `$entity->getCacheTags()`

### Security
- `->accessCheck(TRUE)` on all entity queries (or `FALSE` with explicit justification comment)
- `$this->t()` for user-facing strings, `Xss::filter()` / `Html::escape()` for output
- In JS: `Drupal.checkPlain()` for user-controlled data in DOM

### Documentation
- No redundant docblocks — if the type signature says it, don't repeat it
- Document array structures (`@param array{key: type}`), side effects, and `@throws`
- `{@inheritdoc}` for overridden methods

## 3. Per-Type Scaffold Procedures

---

### 3a. Module

**Ask the user:**
- Module machine name (e.g. `my_feature`)
- Human-readable name
- Description
- Any dependencies (contrib or core modules)

**Generate these files in `web/modules/custom/{module_name}/`:**

#### `{module_name}.info.yml`
```yaml
name: 'Human Name'
type: module
description: 'Module description.'
package: Custom
core_version_requirement: ^11
php: 8.3
# dependencies:
#   - drupal:node
```

#### `{module_name}.module`
```php
<?php

declare(strict_types=1);

/**
 * @file
 * Primary module hooks for {Human Name} module.
 */
```

#### `{module_name}.services.yml`
```yaml
services:
  _defaults:
    autowire: true

  Drupal\{module_name}\:
    resource: src/
    exclude:
      - src/Plugin/
      - src/Entity/
      - src/Form/
      - src/Controller/

  logger.channel.{module_name}:
    parent: logger.channel_base
    arguments: ['{module_name}']
```

#### `AI_CONTEXT.md`
```markdown
# {Human Name} — AI Context

## Purpose
{Description}

## Architecture
- **Type**: Custom module
- **Dependencies**: {list}

## Key Files
| File | Purpose |
|------|---------|
| {module_name}.module | Hook implementations (procedural only) |
| {module_name}.services.yml | Service definitions |

## Data Flow
(To be documented as the module grows)
```

**After generation:** Enable the module:
```bash
ddev drush pm:enable {module_name} -y && ddev drush cr
```

---

### 3b. Service

**Ask the user:**
- Module name (must exist)
- Service purpose / name (e.g. `article_manager`)
- What it does (to determine injected dependencies)
- Whether an interface is needed (yes for services used by other modules, no for internal-only)

**Generate:**

#### `src/{ServiceClass}.php` (or `src/Service/{ServiceClass}.php` if module has many services)
```php
<?php

declare(strict_types=1);

namespace Drupal\{module_name};

use Drupal\Core\Entity\EntityTypeManagerInterface;
use Psr\Log\LoggerInterface;

/**
 * Manages {purpose}.
 */
final class {ServiceClass} implements {ServiceInterface} {

  public function __construct(
    protected readonly EntityTypeManagerInterface $entityTypeManager,
    protected readonly LoggerInterface $logger,
  ) {}

}
```

#### `src/{ServiceInterface}.php` (when needed)
```php
<?php

declare(strict_types=1);

namespace Drupal\{module_name};

/**
 * Interface for the {service purpose} service.
 */
interface {ServiceInterface} {

}
```

#### `{module_name}.services.yml` — add entry
```yaml
  {module_name}.{service_name}:
    class: Drupal\{module_name}\{ServiceClass}
    arguments:
      - '@entity_type.manager'
      - '@logger.channel.{module_name}'
```

If the module uses PSR-4 autowiring (`_defaults: autowire: true` with resource scanning), skip the explicit entry and just note that autowiring handles it.

---

### 3c. Plugin — Block

**Ask the user:**
- Module name
- Block ID (e.g. `recent_articles`)
- Admin label
- What the block displays
- Configurable? (if yes, what settings)

**Generate:**

#### `src/Plugin/Block/{BlockClass}.php`
```php
<?php

declare(strict_types=1);

namespace Drupal\{module_name}\Plugin\Block;

use Drupal\Core\Block\Attribute\Block;
use Drupal\Core\Block\BlockBase;
use Drupal\Core\Entity\EntityTypeManagerInterface;
use Drupal\Core\Plugin\ContainerFactoryPluginInterface;
use Drupal\Core\StringTranslation\TranslatableMarkup;
use Symfony\Component\DependencyInjection\ContainerInterface;

/**
 * Provides the {admin_label} block.
 */
#[Block(
  id: '{block_id}',
  admin_label: new TranslatableMarkup('{admin_label}'),
  category: new TranslatableMarkup('{module_human_name}'),
)]
final class {BlockClass} extends BlockBase implements ContainerFactoryPluginInterface {

  public function __construct(
    array $configuration,
    string $plugin_id,
    mixed $plugin_definition,
    protected readonly EntityTypeManagerInterface $entityTypeManager,
  ) {
    parent::__construct($configuration, $plugin_id, $plugin_definition);
  }

  /**
   * {@inheritdoc}
   */
  public static function create(
    ContainerInterface $container,
    array $configuration,
    $plugin_id,
    $plugin_definition,
  ): static {
    return new static(
      $configuration,
      $plugin_id,
      $plugin_definition,
      $container->get('entity_type.manager'),
    );
  }

  /**
   * {@inheritdoc}
   */
  public function build(): array {
    return [
      '#markup' => $this->t('Block content here.'),
      '#cache' => [
        'tags' => [],
        'contexts' => ['user.permissions'],
        'max-age' => 3600,
      ],
    ];
  }

}
```

**When AutowireTrait is appropriate** (all dependencies are standard container services and no custom create logic is needed):

```php
use Drupal\Core\Plugin\AutowireTrait;

#[Block(
  id: '{block_id}',
  admin_label: new TranslatableMarkup('{admin_label}'),
)]
final class {BlockClass} extends BlockBase {

  use AutowireTrait;

  public function __construct(
    array $configuration,
    string $plugin_id,
    mixed $plugin_definition,
    protected readonly EntityTypeManagerInterface $entityTypeManager,
  ) {
    parent::__construct($configuration, $plugin_id, $plugin_definition);
  }

  // ... build() with #cache ...
}
```

**For configurable blocks**, also generate `defaultConfiguration()`, `blockForm()`, `blockSubmit()`, and a config schema entry.

---

### 3d. Plugin — Field Widget / Field Formatter

Follow the same pattern as Block but with:
- `#[FieldWidget(...)]` or `#[FieldFormatter(...)]` attribute
- `WidgetBase` / `FormatterBase` parent class
- `field_types` in attribute
- `formElement()` for widgets, `viewElements()` for formatters

---

### 3e. Form — Config Form

**Ask the user:**
- Module name
- Form purpose (e.g. "module settings")
- Config settings to manage (list of key/type pairs)
- Route path (e.g. `/admin/config/{module_name}`)

**Generate:**

#### `src/Form/{FormClass}.php`
```php
<?php

declare(strict_types=1);

namespace Drupal\{module_name}\Form;

use Drupal\Core\Form\ConfigFormBase;
use Drupal\Core\Form\FormStateInterface;

/**
 * Configure {module human name} settings.
 */
final class {FormClass} extends ConfigFormBase {

  private const CONFIG_NAME = '{module_name}.settings';

  /**
   * {@inheritdoc}
   */
  public function getFormId(): string {
    return '{module_name}_settings';
  }

  /**
   * {@inheritdoc}
   */
  protected function getEditableConfigNames(): array {
    return [self::CONFIG_NAME];
  }

  /**
   * {@inheritdoc}
   */
  public function buildForm(array $form, FormStateInterface $form_state): array {
    $config = $this->config(self::CONFIG_NAME);

    $form['example'] = [
      '#type' => 'textfield',
      '#title' => $this->t('Example setting'),
      '#default_value' => $config->get('example'),
    ];

    return parent::buildForm($form, $form_state);
  }

  /**
   * {@inheritdoc}
   */
  public function submitForm(array &$form, FormStateInterface $form_state): void {
    $this->config(self::CONFIG_NAME)
      ->set('example', $form_state->getValue('example'))
      ->save();

    parent::submitForm($form, $form_state);
  }

}
```

#### `{module_name}.routing.yml` — add entry
```yaml
{module_name}.settings:
  path: '/admin/config/{module_name}'
  defaults:
    _form: '\Drupal\{module_name}\Form\{FormClass}'
    _title: '{Module Name} settings'
  requirements:
    _permission: 'administer site configuration'
```

#### `config/schema/{module_name}.schema.yml`
```yaml
{module_name}.settings:
  type: config_object
  label: '{Module Name} settings'
  mapping:
    example:
      type: string
      label: 'Example setting'
```

#### `config/install/{module_name}.settings.yml`
```yaml
example: ''
```

---

### 3f. Form — Simple Form

Same as config form but extends `FormBase` instead of `ConfigFormBase`. No config schema or install config needed. Include `validateForm()` stub.

**Template differences from config form:**
- No `getEditableConfigNames()`
- No `CONFIG_NAME` constant
- Add `validateForm()` method
- Add `submitForm()` with messenger feedback:
  ```php
  $this->messenger()->addStatus($this->t('Form submitted successfully.'));
  ```

---

### 3g. Form — Confirm Form

Extends `ConfirmFormBase`. Generate `getQuestion()`, `getCancelUrl()`, `getDescription()`, and `submitForm()`.

---

### 3h. Controller

**Ask the user:**
- Module name
- Controller purpose
- Route path and title
- Permission required
- Services needed

**Generate:**

#### `src/Controller/{ControllerClass}.php`
```php
<?php

declare(strict_types=1);

namespace Drupal\{module_name}\Controller;

use Drupal\Core\Controller\ControllerBase;
use Drupal\Core\Entity\EntityTypeManagerInterface;
use Symfony\Component\DependencyInjection\ContainerInterface;

/**
 * Returns responses for {purpose} routes.
 */
final class {ControllerClass} extends ControllerBase {

  public function __construct(
    protected readonly EntityTypeManagerInterface $entityTypeManager,
  ) {}

  /**
   * {@inheritdoc}
   */
  public static function create(ContainerInterface $container): static {
    return new static(
      $container->get('entity_type.manager'),
    );
  }

  /**
   * Builds the response.
   */
  public function __invoke(): array {
    return [
      '#markup' => $this->t('Page content here.'),
      '#cache' => [
        'tags' => [],
        'contexts' => ['user.permissions'],
        'max-age' => 3600,
      ],
    ];
  }

}
```

#### `{module_name}.routing.yml` — add entry
```yaml
{module_name}.{route_name}:
  path: '/{route_path}'
  defaults:
    _controller: '\Drupal\{module_name}\Controller\{ControllerClass}'
    _title: '{Page Title}'
  requirements:
    _permission: '{permission}'
```

#### `{module_name}.permissions.yml` — add if custom permission needed
```yaml
{permission}:
  title: '{Permission Title}'
  description: '{Permission description.}'
```

---

### 3i. Hook Class

**Ask the user:**
- Module name
- Which hooks to implement
- Domain grouping (e.g. `FormHooks`, `EntityHooks`, `NodeHooks`)

**Generate:**

#### `src/Hook/{HookClass}.php`
```php
<?php

declare(strict_types=1);

namespace Drupal\{module_name}\Hook;

use Drupal\Core\Entity\EntityTypeManagerInterface;
use Drupal\Core\Form\FormStateInterface;
use Drupal\Core\Hook\Attribute\Hook;

/**
 * {Domain} hook implementations for {module_name}.
 */
final class {HookClass} {

  public function __construct(
    protected readonly EntityTypeManagerInterface $entityTypeManager,
  ) {}

  /**
   * Implements hook_form_alter().
   */
  #[Hook('form_alter')]
  public function formAlter(array &$form, FormStateInterface $form_state, string $form_id): void {
    // Implementation here.
  }

}
```

#### `{module_name}.services.yml` — register hook class
```yaml
  Drupal\{module_name}\Hook\{HookClass}:
    autowire: true
```

**Important:** If the module already uses PSR-4 autowiring with `resource: src/` and the `src/Hook/` directory is not in the `exclude` list, the hook class is auto-registered. Check and remove `src/Hook/` from excludes if present.

---

### 3j. Event Subscriber

**Ask the user:**
- Module name
- Which event(s) to subscribe to
- What the subscriber does
- Priority (default: 0)

**Generate:**

#### `src/EventSubscriber/{SubscriberClass}.php`
```php
<?php

declare(strict_types=1);

namespace Drupal\{module_name}\EventSubscriber;

use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpKernel\Event\RequestEvent;
use Symfony\Component\HttpKernel\KernelEvents;

/**
 * Subscribes to {event description}.
 */
final class {SubscriberClass} implements EventSubscriberInterface {

  public function __construct(
    // Inject services here.
  ) {}

  /**
   * {@inheritdoc}
   */
  public static function getSubscribedEvents(): array {
    return [
      KernelEvents::REQUEST => ['onRequest', 0],
    ];
  }

  /**
   * Handles the request event.
   */
  public function onRequest(RequestEvent $event): void {
    // Implementation here.
  }

}
```

#### `{module_name}.services.yml` — add entry
```yaml
  Drupal\{module_name}\EventSubscriber\{SubscriberClass}:
    autowire: true
    tags:
      - { name: event_subscriber }
```

If module uses PSR-4 autowiring, the class is auto-discovered but the `event_subscriber` tag still needs explicit registration (autowiring does not auto-tag).

---

### 3k. Entity — Content Entity

**Ask the user:**
- Module name
- Entity type ID (e.g. `message`)
- Label (singular and plural)
- Whether it needs bundles
- Which base fields beyond label (e.g. description, status)
- Whether it needs admin UI (list builder, forms)

This is a complex scaffold. Use `ddev drush generate entity:content` with `--answers` JSON for the base structure, then customize the generated files to match project rules:
- Add `declare(strict_types=1)` if missing
- Convert annotations to attributes
- Add `protected readonly` to injected services
- Add `#cache` to any render arrays
- Add `->accessCheck(TRUE)` on queries

---

### 3l. Entity — Config Entity

Same approach as content entity but use `ddev drush generate entity:configuration`. Customize to match project rules after generation.

---

## 4. Post-Generation Checklist

**After generating ANY scaffold, always run:**

```bash
# 1. Auto-fix coding standards
ddev exec phpcbf --standard=Drupal,DrupalPractice --extensions=php,module,inc,install,test,profile,theme web/modules/custom/{module_name}

# 2. Verify no remaining violations
ddev exec phpcs --standard=Drupal,DrupalPractice --extensions=php,module,inc,install,test,profile,theme web/modules/custom/{module_name}
```

**Then suggest these follow-up actions:**

1. **Enable module** (if new): `ddev drush pm:enable {module_name} -y && ddev drush cr`
2. **Export config**: `ddev drush cex -y`
3. **Generate tests**: Use the `generate-tests` skill — `/generate-tests {module_name}`
4. **Update AI_CONTEXT.md**: If you created new classes or changed architecture, update the module's `AI_CONTEXT.md`
5. **Clear caches**: `ddev drush cr` (always after adding new classes/services/routes)

## 5. Decision Guide

When unsure which scaffold to use:

| User says... | Scaffold type |
|--------------|---------------|
| "new module" / "create a module" | `module` |
| "add a service" / "helper class" | `service` |
| "create a block" | `plugin` (block) |
| "settings page" / "admin form" | `form` (config) |
| "contact form" / "submission form" | `form` (simple) |
| "delete confirmation" | `form` (confirm) |
| "add a page" / "new route" | `controller` |
| "hook into" / "alter" / "implement hook_X" | `hook` |
| "listen for events" / "on kernel request" | `event-subscriber` |
| "custom entity" / "content entity" | `entity` |
| "field widget" / "field formatter" | `plugin` (field) |

## 6. Output

After scaffolding:
1. Show the user every file created/modified with a brief summary
2. Run phpcbf + phpcs and show results
3. Present the follow-up actions from section 4
4. If this is a new module, remind the user to enable it and export config

## Related Skills

- **generate-tests** — After scaffolding, suggest: `/generate-tests {module_name}`
- **code-review** — For reviewing scaffolded code: `/code-review {module_name}`
- **drupal-expert** — Drupal patterns, coding standards, drush generators reference
- **debug** — If scaffolded code doesn't work (hooks not firing, services not found)
- **drupal-frontend-expert** — Theme scaffolding, Twig templates, SDC components
- **drupal-security** — Security patterns for scaffolded code
