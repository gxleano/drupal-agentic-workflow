# Drupal 10.3 — version-specific guidance

> Version deltas only. Generic Drupal best practices live in the existing skills and `CLAUDE-TEMPLATE.md`.

## Required APIs

- Symfony 6.4 LTS APIs are available; prefer constructor property promotion and typed properties in services.
- `#[FormElement]` and `#[RenderElement]` attribute plugin discovery is supported alongside legacy annotations.
- Use `\Drupal\Core\Hook\Attribute\Hook` for OOP hooks where convenient (introduced in 10.3; not yet preferred).
- `EntityTypeInterface::getKey('revision_translation_affected')` and revision metadata keys are stable — rely on them instead of hand-rolled checks.
- CKEditor 5 is the only editor; new text formats must target the `ckeditor5` plugin.

## Deprecated patterns to avoid

- `\Drupal\Core\Render\Element\FormElement` annotation-only plugins — migrate to `#[FormElement]` attributes when touching them.
- `hook_help()` returning raw strings — return render arrays or `MarkupInterface`.
- Direct use of `db_query()` shims and the legacy `\Drupal::database()->query()` with unbounded `{}` interpolation for table names; prefer the Connection schema API.
- `\Drupal\Core\Entity\EntityType::getLowercaseLabel()` — use `getSingularLabel()` / `getPluralLabel()`.
- Calling `\Drupal::service('renderer')->render()` outside a render context — wrap in `executeInRenderContext()`.

## OOP hook policy

- `#[Hook]` attribute is **available but optional** in 10.3.
- New code MAY use procedural `mymodule_entity_presave()` style; converting is not required.
- If you do convert, keep one hook class per module under `src/Hook/` and register via service autowiring (no manual `services.yml` entry needed when autoconfigure is enabled).
- Mixing OOP and procedural hooks in the same module is allowed.

## Plugin attribute policy

- Attribute-based discovery is **preferred for new plugins** where the manager supports it (Block, FieldType, FieldWidget, FieldFormatter, FormElement, RenderElement, Condition, Action, QueueWorker, Mail, Tour, ImageEffect, Search, Migrate*).
- Annotations remain fully supported — do **not** mass-convert existing plugins.
- When both attribute and annotation are present on the same class, attribute wins; remove the annotation to avoid drift.

## Test base classes

- `BrowserTestBase` (functional), `WebDriverTestBase` (JS), `KernelTestBase` (kernel), `UnitTestCase` (unit) — all PHPUnit 9/10 compatible.
- Use `Drupal\Tests\Traits\Core\CronRunTrait` for cron-driven assertions.
- `ExistingSiteBase` (drupal/drupal-test-traits) is supported but not part of core.
- Functional JS tests require ChromeDriver 119+ for compatibility with the bundled Mink driver.

## Minimum PHP

- **PHP 8.1.0** (PHP 8.3 recommended).
- `readonly` properties and enums are safe to use in custom code.
- First-class callable syntax (`$obj->method(...)`) is supported.
