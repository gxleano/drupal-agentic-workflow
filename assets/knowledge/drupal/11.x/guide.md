# Drupal 11.x — version-specific guidance

> Version deltas only. Generic Drupal best practices live in the existing skills and `CLAUDE-TEMPLATE.md`.

## Required APIs

- Symfony 7 baseline — verify any third-party Symfony components are 7.x compatible.
- `\Drupal\Core\Hook\Attribute\Hook` is the **preferred** way to declare hooks for new code.
- `#[FormElement]`, `#[RenderElement]`, `#[Block]`, `#[FieldType]`, `#[FieldWidget]`, `#[FieldFormatter]`, `#[Condition]`, `#[Action]`, `#[QueueWorker]` attribute plugins are the default — annotations are legacy.
- Entity API method signatures are tightened: `EntityViewBuilder::buildComponents()` and similar now have parameter type narrowing — adjust overrides to match.
- Config API: schema is enforced more strictly; partial schemas that passed on 10.x will fail validation on 11.x.

## Deprecated patterns to avoid

- **CKEditor 4** is removed entirely — there is no fallback. Migrate any remaining text formats to CKEditor 5 before upgrade.
- **jQuery UI** is largely removed (dialog/autocomplete moved to vanilla JS / `core/drupal.dialog`). Stop adding `core/jquery.ui.*` libraries.
- **Stable 9 base theme** is removed — re-base custom themes on Stark or Olivero.
- Procedural hooks remain supported but are no longer the recommended style — do not add new ones unless converting cost is prohibitive.
- `\Drupal::service()` lookups in classes that can be DI'd — 11.x's stricter container compilation surfaces these as warnings.
- PHPUnit 9-only test syntax (use PHPUnit 10 attributes for data providers and test markers).

## OOP hook policy

- **Preferred:** declare hooks as methods on a class under `src/Hook/<Module>Hooks.php` annotated with `#[Hook('entity_presave')]` (or the appropriate hook name).
- One hook class per concern is fine; one per module is also acceptable.
- The class is autowired — inject services via the constructor; no need for `create()` boilerplate when autoconfigure is on.
- Procedural hooks still work; do not block a PR over conversion of unrelated legacy hooks.
- `hook_form_FORM_ID_alter()` is fully supported via `#[Hook('form_FORM_ID_alter')]`.

## Plugin attribute policy

- New plugins **must** use attributes when the manager supports them.
- Do not introduce new annotation-based plugins in 11.x code.
- When converting an existing annotation plugin, remove the annotation in the same commit to prevent duplicate discovery.
- For plugin managers that still only support annotations (rare custom modules), document the reason inline.

## Test base classes

- `BrowserTestBase`, `WebDriverTestBase`, `KernelTestBase`, `UnitTestCase` — all on PHPUnit 10.
- PHPUnit 10 attributes (`#[DataProvider]`, `#[Group]`, `#[CoversClass]`) replace the `@dataProvider` / `@group` / `@covers` annotations.
- Mink/Selenium is replaced by the WebDriver bridge; `WebDriverTestBase` requires Chrome/Chromium 120+.
- `Drupal\TestTools\Random` is the supported source of randomness — do not call PHP `rand()` directly in tests.

## Minimum PHP

- **PHP 8.3.0**.
- Use `readonly` classes, typed class constants, and `#[\Override]` attributes where they aid clarity.
- `json_validate()` is available — prefer it over decode-and-check patterns.
