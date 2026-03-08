# Common Drupal Patterns Reference

Load this file on demand when you need code examples for common Drupal patterns.

## Service Definition

```yaml
services:
  my_module.my_service:
    class: Drupal\my_module\Service\MyService
    arguments: ['@entity_type.manager', '@current_user', '@logger.factory']
```

## Route with Permission

```yaml
my_module.page:
  path: '/my-page'
  defaults:
    _controller: '\Drupal\my_module\Controller\MyController::content'
    _title: 'My Page'
  requirements:
    _permission: 'access content'
```

## Plugin (Block Example)

```php
#[Block(
  id: "my_block",
  admin_label: new TranslatableMarkup("My Block"),
)]
class MyBlock extends BlockBase implements ContainerFactoryPluginInterface {
  // Always use ContainerFactoryPluginInterface for DI in plugins
}
```

## Config Schema (Required!)

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

## Dependency Injection in Controllers

```php
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

## OOP Hook (Drupal 11+)

```php
#[Hook('form_alter')]
public function formAlter(&$form, FormStateInterface $form_state, $form_id): void {
  // ...
}
```

## Event Subscriber

```php
public static function getSubscribedEvents() {
  return [
    KernelEvents::REQUEST => ['onRequest', 100],
  ];
}
```

## Entity Query with Access Check

```php
$query = $this->entityTypeManager->getStorage('node')->getQuery()
  ->accessCheck(TRUE)
  ->condition('type', 'article')
  ->condition('status', 1)
  ->sort('created', 'DESC')
  ->range(0, 50);
$nids = $query->execute();
$nodes = $this->entityTypeManager->getStorage('node')->loadMultiple($nids);
```

## Form with Dependency Injection

```php
class MyForm extends FormBase {
  public function __construct(
    protected readonly EntityTypeManagerInterface $entityTypeManager,
  ) {}

  public static function create(ContainerInterface $container): static {
    return new static(
      $container->get('entity_type.manager'),
    );
  }

  public function getFormId(): string {
    return 'my_module_my_form';
  }

  public function buildForm(array $form, FormStateInterface $form_state): array {
    $form['name'] = [
      '#type' => 'textfield',
      '#title' => $this->t('Name'),
      '#required' => TRUE,
    ];
    $form['actions']['submit'] = [
      '#type' => 'submit',
      '#value' => $this->t('Submit'),
    ];
    return $form;
  }

  public function submitForm(array &$form, FormStateInterface $form_state): void {
    $this->messenger()->addStatus($this->t('Saved.'));
  }
}
```

## Custom Plugin Type

```php
// Annotation-free plugin (Drupal 11+)
#[FieldFormatter(
  id: 'my_formatter',
  label: new TranslatableMarkup('My Formatter'),
  field_types: ['text'],
)]
class MyFormatter extends FormatterBase {
  // ...
}
```

## Queue Worker

```php
#[QueueWorker(
  id: 'my_module_process',
  title: new TranslatableMarkup('Process items'),
  cron: ['time' => 60],
)]
class ProcessQueueWorker extends QueueWorkerBase implements ContainerFactoryPluginInterface {
  public function processItem($data): void {
    // Process queue item
  }
}
```
