---
name: entity
description: Custom content and config entity types with bundles, handlers, queries, and views integration
version: 1.0.0
---

# Custom Entity Types — Drupal 11

## Activation

Activate when:
- Creating custom content or config entity types
- Working with entity handlers (access, list builder, form, storage)
- Entity queries, base fields, computed fields
- Entity reference, revisions, translations
- Views integration for custom entities

## Decision Tree: Content vs Config Entity

| Factor | Content Entity | Config Entity |
|--------|---------------|---------------|
| Stored in | `{entity_type}` DB table | `config` table / YAML |
| Exportable | Not by default (use default_content) | Yes — `drush cex` |
| Revisionable | Yes | No |
| Translatable | Yes | Yes (config translation) |
| Has fields | Yes (bundles, Field UI) | Yes (limited, annotation-based) |
| User-created | Yes (like nodes, users) | Yes (like views, image styles) |
| Examples | Node, Media, User, Comment | View, ImageStyle, Vocabulary, Role |
| **Use when** | User content, runtime data | Site configuration, admin-managed |

## Content Entity with Bundles

### Entity Class

```php
declare(strict_types=1);

namespace Drupal\my_module\Entity;

use Drupal\Core\Entity\Attribute\ContentEntityType;
use Drupal\Core\Entity\ContentEntityBase;
use Drupal\Core\Entity\EntityChangedTrait;
use Drupal\Core\Entity\EntityTypeInterface;
use Drupal\Core\Field\BaseFieldDefinition;
use Drupal\Core\StringTranslation\TranslatableMarkup;
use Drupal\my_module\Entity\Handler\ProjectAccessControlHandler;
use Drupal\my_module\Entity\Handler\ProjectListBuilder;
use Drupal\my_module\Form\ProjectForm;
use Drupal\my_module\Form\ProjectDeleteForm;
use Drupal\user\EntityOwnerTrait;

#[ContentEntityType(
  id: 'project',
  label: new TranslatableMarkup('Project'),
  label_collection: new TranslatableMarkup('Projects'),
  label_singular: new TranslatableMarkup('project'),
  label_plural: new TranslatableMarkup('projects'),
  bundle_label: new TranslatableMarkup('Project type'),
  bundle_entity_type: 'project_type',
  handlers: [
    'access' => ProjectAccessControlHandler::class,
    'list_builder' => ProjectListBuilder::class,
    'form' => [
      'default' => ProjectForm::class,
      'add' => ProjectForm::class,
      'edit' => ProjectForm::class,
      'delete' => ProjectDeleteForm::class,
    ],
    'route_provider' => [
      'html' => \Drupal\Core\Entity\Routing\AdminHtmlRouteProvider::class,
    ],
    'views_data' => \Drupal\views\EntityViewsData::class,
  ],
  base_table: 'project',
  data_table: 'project_field_data',
  revision_table: 'project_revision',
  revision_data_table: 'project_field_revision',
  translatable: TRUE,
  revisionable: TRUE,
  admin_permission: 'administer projects',
  entity_keys: [
    'id' => 'id',
    'revision' => 'revision_id',
    'bundle' => 'type',
    'label' => 'title',
    'uuid' => 'uuid',
    'langcode' => 'langcode',
    'owner' => 'uid',
    'published' => 'status',
  ],
  revision_metadata_keys: [
    'revision_user' => 'revision_uid',
    'revision_created' => 'revision_timestamp',
    'revision_log_message' => 'revision_log',
  ],
  links: [
    'canonical' => '/project/{project}',
    'add-page' => '/project/add',
    'add-form' => '/project/add/{project_type}',
    'edit-form' => '/project/{project}/edit',
    'delete-form' => '/project/{project}/delete',
    'collection' => '/admin/content/projects',
    'version-history' => '/project/{project}/revisions',
  ],
  field_ui_base_route: 'entity.project_type.edit_form',
)]
final class Project extends ContentEntityBase {

  use EntityChangedTrait;
  use EntityOwnerTrait;

  public function getTitle(): string {
    return (string) $this->get('title')->value;
  }

  public function isPublished(): bool {
    return (bool) $this->get('status')->value;
  }

  public static function baseFieldDefinitions(EntityTypeInterface $entity_type): array {
    $fields = parent::baseFieldDefinitions($entity_type);
    $fields += static::ownerBaseFieldDefinitions($entity_type);

    $fields['title'] = BaseFieldDefinition::create('string')
      ->setLabel(new TranslatableMarkup('Title'))
      ->setRequired(TRUE)
      ->setTranslatable(TRUE)
      ->setRevisionable(TRUE)
      ->setSetting('max_length', 255)
      ->setDisplayOptions('form', [
        'type' => 'string_textfield',
        'weight' => -10,
      ])
      ->setDisplayOptions('view', [
        'label' => 'hidden',
        'type' => 'string',
        'weight' => -10,
      ])
      ->setDisplayConfigurable('form', TRUE)
      ->setDisplayConfigurable('view', TRUE);

    $fields['status'] = BaseFieldDefinition::create('boolean')
      ->setLabel(new TranslatableMarkup('Published'))
      ->setDefaultValue(TRUE)
      ->setRevisionable(TRUE)
      ->setDisplayOptions('form', [
        'type' => 'boolean_checkbox',
        'weight' => 100,
      ])
      ->setDisplayConfigurable('form', TRUE);

    $fields['description'] = BaseFieldDefinition::create('text_long')
      ->setLabel(new TranslatableMarkup('Description'))
      ->setTranslatable(TRUE)
      ->setRevisionable(TRUE)
      ->setDisplayOptions('form', [
        'type' => 'text_textarea',
        'weight' => 0,
      ])
      ->setDisplayOptions('view', [
        'type' => 'text_default',
        'weight' => 0,
      ])
      ->setDisplayConfigurable('form', TRUE)
      ->setDisplayConfigurable('view', TRUE);

    $fields['created'] = BaseFieldDefinition::create('created')
      ->setLabel(new TranslatableMarkup('Created'))
      ->setTranslatable(TRUE)
      ->setRevisionable(TRUE);

    $fields['changed'] = BaseFieldDefinition::create('changed')
      ->setLabel(new TranslatableMarkup('Changed'))
      ->setTranslatable(TRUE)
      ->setRevisionable(TRUE);

    // Configure owner field display
    $fields['uid']
      ->setLabel(new TranslatableMarkup('Author'))
      ->setRevisionable(TRUE)
      ->setDisplayOptions('form', [
        'type' => 'entity_reference_autocomplete',
        'weight' => 90,
      ])
      ->setDisplayConfigurable('form', TRUE)
      ->setDisplayConfigurable('view', TRUE);

    return $fields;
  }

}
```

### Bundle Entity (Config Entity)

```php
declare(strict_types=1);

namespace Drupal\my_module\Entity;

use Drupal\Core\Config\Entity\ConfigEntityBundleBase;
use Drupal\Core\Entity\Attribute\ConfigEntityType;
use Drupal\Core\StringTranslation\TranslatableMarkup;

#[ConfigEntityType(
  id: 'project_type',
  label: new TranslatableMarkup('Project type'),
  label_collection: new TranslatableMarkup('Project types'),
  handlers: [
    'list_builder' => \Drupal\my_module\Entity\Handler\ProjectTypeListBuilder::class,
    'form' => [
      'add' => \Drupal\my_module\Form\ProjectTypeForm::class,
      'edit' => \Drupal\my_module\Form\ProjectTypeForm::class,
      'delete' => \Drupal\Core\Entity\EntityDeleteForm::class,
    ],
    'route_provider' => [
      'html' => \Drupal\Core\Entity\Routing\AdminHtmlRouteProvider::class,
    ],
  ],
  config_prefix: 'project_type',
  bundle_of: 'project',
  admin_permission: 'administer projects',
  entity_keys: [
    'id' => 'id',
    'label' => 'label',
    'uuid' => 'uuid',
  ],
  config_export: ['id', 'label', 'description'],
  links: [
    'add-form' => '/admin/structure/project-types/add',
    'edit-form' => '/admin/structure/project-types/{project_type}',
    'delete-form' => '/admin/structure/project-types/{project_type}/delete',
    'collection' => '/admin/structure/project-types',
  ],
)]
final class ProjectType extends ConfigEntityBundleBase {

  protected string $id;
  protected string $label;
  protected string $description = '';

  public function getDescription(): string {
    return $this->description;
  }

}
```

### Config Schema (config/schema/my_module.schema.yml)

```yaml
my_module.project_type.*:
  type: config_entity
  label: 'Project type'
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
```

## Entity Handlers

### Access Control Handler

```php
declare(strict_types=1);

namespace Drupal\my_module\Entity\Handler;

use Drupal\Core\Access\AccessResult;
use Drupal\Core\Access\AccessResultInterface;
use Drupal\Core\Entity\EntityAccessControlHandler;
use Drupal\Core\Entity\EntityInterface;
use Drupal\Core\Session\AccountInterface;

final class ProjectAccessControlHandler extends EntityAccessControlHandler {

  protected function checkAccess(
    EntityInterface $entity,
    string $operation,
    AccountInterface $account,
  ): AccessResultInterface {
    return match ($operation) {
      'view' => AccessResult::allowedIfHasPermission($account, 'view projects')
        ->orIf(
          AccessResult::allowedIfHasPermission($account, 'view own projects')
            ->andIf(AccessResult::allowedIf($entity->getOwnerId() === (int) $account->id()))
        )
        ->addCacheableDependency($entity),
      'update' => AccessResult::allowedIfHasPermission($account, 'edit projects')
        ->orIf(
          AccessResult::allowedIfHasPermission($account, 'edit own projects')
            ->andIf(AccessResult::allowedIf($entity->getOwnerId() === (int) $account->id()))
        )
        ->addCacheableDependency($entity),
      'delete' => AccessResult::allowedIfHasPermission($account, 'delete projects')
        ->addCacheableDependency($entity),
      default => AccessResult::neutral(),
    };
  }

  protected function checkCreateAccess(
    AccountInterface $account,
    array $context,
    ?string $entity_bundle = NULL,
  ): AccessResultInterface {
    return AccessResult::allowedIfHasPermission($account, 'create projects');
  }

}
```

### List Builder

```php
declare(strict_types=1);

namespace Drupal\my_module\Entity\Handler;

use Drupal\Core\Entity\EntityInterface;
use Drupal\Core\Entity\EntityListBuilder;

final class ProjectListBuilder extends EntityListBuilder {

  public function buildHeader(): array {
    return [
      'title' => $this->t('Title'),
      'type' => $this->t('Type'),
      'status' => $this->t('Status'),
      'author' => $this->t('Author'),
      'changed' => $this->t('Updated'),
    ] + parent::buildHeader();
  }

  public function buildRow(EntityInterface $entity): array {
    /** @var \Drupal\my_module\Entity\Project $entity */
    return [
      'title' => $entity->toLink(),
      'type' => $entity->bundle(),
      'status' => $entity->isPublished() ? $this->t('Published') : $this->t('Unpublished'),
      'author' => $entity->getOwner()?->toLink() ?? $this->t('Anonymous'),
      'changed' => \Drupal::service('date.formatter')->format($entity->getChangedTime(), 'short'),
    ] + parent::buildRow($entity);
  }

}
```

## Entity Queries

```php
declare(strict_types=1);

namespace Drupal\my_module\Service;

use Drupal\Core\Entity\EntityTypeManagerInterface;
use Drupal\my_module\Entity\Project;

final class ProjectRepository {

  public function __construct(
    protected readonly EntityTypeManagerInterface $entityTypeManager,
  ) {}

  /** @return \Drupal\my_module\Entity\Project[] */
  public function findPublished(int $limit = 10): array {
    $ids = $this->entityTypeManager->getStorage('project')
      ->getQuery()
      ->accessCheck(TRUE)
      ->condition('status', 1)
      ->sort('created', 'DESC')
      ->range(0, $limit)
      ->execute();

    return $ids ? $this->entityTypeManager->getStorage('project')->loadMultiple($ids) : [];
  }

  /** @return \Drupal\my_module\Entity\Project[] */
  public function findByType(string $type): array {
    $ids = $this->entityTypeManager->getStorage('project')
      ->getQuery()
      ->accessCheck(TRUE)
      ->condition('type', $type)
      ->condition('status', 1)
      ->execute();

    return $ids ? $this->entityTypeManager->getStorage('project')->loadMultiple($ids) : [];
  }

  public function countByOwner(int $uid): int {
    return (int) $this->entityTypeManager->getStorage('project')
      ->getQuery()
      ->accessCheck(FALSE) // Internal count — no access check needed
      ->condition('uid', $uid)
      ->count()
      ->execute();
  }

  /** Aggregate query example */
  public function getTypeCounts(): array {
    return $this->entityTypeManager->getStorage('project')
      ->getAggregateQuery()
      ->accessCheck(TRUE)
      ->groupBy('type')
      ->aggregate('id', 'COUNT')
      ->execute();
  }

}
```

## Entity Events and Hooks

### OOP Hook Class

```php
declare(strict_types=1);

namespace Drupal\my_module\Hook;

use Drupal\Core\Entity\EntityInterface;
use Drupal\Core\Hook\Attribute\Hook;
use Drupal\my_module\Entity\Project;
use Drupal\my_module\Service\NotificationService;

final class ProjectEntityHooks {

  public function __construct(
    protected readonly NotificationService $notificationService,
  ) {}

  #[Hook('entity_presave')]
  public function onProjectPresave(EntityInterface $entity): void {
    if (!$entity instanceof Project) {
      return;
    }

    // Auto-set title format if empty
    if ($entity->isNew() && empty($entity->getTitle())) {
      $entity->set('title', 'Project ' . date('Y-m-d H:i:s'));
    }
  }

  #[Hook('entity_insert')]
  public function onProjectInsert(EntityInterface $entity): void {
    if (!$entity instanceof Project) {
      return;
    }

    $this->notificationService->notifyNewProject($entity);
  }

  #[Hook('entity_update')]
  public function onProjectUpdate(EntityInterface $entity): void {
    if (!$entity instanceof Project) {
      return;
    }

    // Check if status changed to published
    if ($entity->isPublished() && !$entity->original->isPublished()) {
      $this->notificationService->notifyPublished($entity);
    }
  }

}
```

## Entity Validation

### Custom Constraint

```php
declare(strict_types=1);

namespace Drupal\my_module\Plugin\Validation\Constraint;

use Drupal\Core\StringTranslation\TranslatableMarkup;
use Drupal\Core\Validation\Attribute\Constraint;
use Symfony\Component\Validator\Constraint as SymfonyConstraint;

#[Constraint(
  id: 'UniqueProjectTitle',
  label: new TranslatableMarkup('Unique project title'),
)]
final class UniqueProjectTitleConstraint extends SymfonyConstraint {

  public string $message = 'A project with title %title already exists.';

}
```

```php
declare(strict_types=1);

namespace Drupal\my_module\Plugin\Validation\Constraint;

use Drupal\Core\Entity\EntityTypeManagerInterface;
use Drupal\Core\DependencyInjection\ContainerInjectionInterface;
use Symfony\Component\DependencyInjection\ContainerInterface;
use Symfony\Component\Validator\Constraint;
use Symfony\Component\Validator\ConstraintValidator;

final class UniqueProjectTitleConstraintValidator extends ConstraintValidator implements ContainerInjectionInterface {

  public function __construct(
    protected readonly EntityTypeManagerInterface $entityTypeManager,
  ) {}

  public static function create(ContainerInterface $container): static {
    return new static($container->get('entity_type.manager'));
  }

  public function validate(mixed $value, Constraint $constraint): void {
    /** @var \Drupal\my_module\Entity\Project $entity */
    $entity = $value->getEntity();

    $query = $this->entityTypeManager->getStorage('project')
      ->getQuery()
      ->accessCheck(FALSE)
      ->condition('title', $entity->getTitle());

    if (!$entity->isNew()) {
      $query->condition('id', $entity->id(), '<>');
    }

    if ($query->count()->execute() > 0) {
      $this->context->addViolation($constraint->message, [
        '%title' => $entity->getTitle(),
      ]);
    }
  }

}
```

Add constraint to entity:

```php
// In baseFieldDefinitions()
$fields['title'] = BaseFieldDefinition::create('string')
  ->setLabel(new TranslatableMarkup('Title'))
  ->addConstraint('UniqueProjectTitle');
```

Or entity-level:

```php
// In entity class
public static function baseFieldDefinitions(EntityTypeInterface $entity_type): array {
  // ...
}

// Override to add entity-level constraints
public function getConstraints(): array {
  $constraints = parent::getConstraints();
  $constraints[] = $this->typedDataManager
    ->getDefaultConstraints($this->getDataDefinition());
  return $constraints;
}
```

## Permissions (my_module.permissions.yml)

```yaml
administer projects:
  title: 'Administer projects'
  restrict access: true

create projects:
  title: 'Create projects'

view projects:
  title: 'View published projects'

view own projects:
  title: 'View own projects'

edit projects:
  title: 'Edit any project'

edit own projects:
  title: 'Edit own projects'

delete projects:
  title: 'Delete any project'
```

## Install Schema (my_module.install)

```php
declare(strict_types=1);

/**
 * @file
 * Install and update hooks for my_module.
 */

use Drupal\Core\Entity\EntityTypeInterface;

/**
 * Implements hook_install().
 */
function my_module_install(): void {
  // Create default bundle.
  \Drupal\my_module\Entity\ProjectType::create([
    'id' => 'default',
    'label' => 'Default',
    'description' => 'A default project type.',
  ])->save();
}
```

## Common Mistakes

| Mistake | Impact | Fix |
|---------|--------|-----|
| Missing `accessCheck()` on entity queries | Security: exposes data | Always call `->accessCheck(TRUE)` (or FALSE with comment) |
| Wrong entity keys in attribute | Fatal errors on install | Double-check `id`, `uuid`, `label`, `bundle`, `owner` |
| Missing `revision_metadata_keys` | Revision UI breaks | Add `revision_user`, `revision_created`, `revision_log_message` |
| No `field_ui_base_route` | Can't add fields in UI | Set to bundle type edit route |
| Forgetting `drush entity:updates` after schema change | Old schema persists | Run `ddev drush entity:updates` or `ddev drush updb` |
| Not clearing cache after entity type changes | Entity type not registered | `ddev drush cr` after any annotation/attribute change |
| Using `$entity->field_name` instead of `$entity->get('field_name')` | May work but bypasses typed data | Always use `->get()` and `->set()` |
| Missing config schema for config entities | Config export fails validation | Always create `config/schema/*.schema.yml` |
| N+1 queries loading references | Slow page loads | Use `->loadMultiple()` or `EntityQuery` with conditions |
| Hardcoding entity IDs in code | Breaks across environments | Use machine names, config, or entity queries |
