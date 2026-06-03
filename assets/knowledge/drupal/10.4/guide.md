# Drupal 10.4 — version-specific guidance

> Version deltas only. Generic Drupal best practices live in the existing skills and `CLAUDE-TEMPLATE.md`.
>
> **Note:** 10.4 is a standard (non-LTS) minor release. **10.3 is the LTS** that receives extended security support. Treat 10.4 as a stepping stone to 11.x.

## Required APIs

- Same Symfony 6.4 baseline as 10.3 — no major API additions.
- All 10.3 attribute plugin managers remain; no new plugin discovery types in 10.4.
- `#[Hook]` attribute remains available; still optional for module code.
- Continue to target CKEditor 5 plugin definitions for any text-format work.
- Workspaces and Workflows APIs receive minor signature stabilisation — re-run `phpstan` after upgrading from 10.3.

## Deprecated patterns to avoid

- Same deprecation set as 10.3 — nothing new is *removed* in 10.4 (security-focused release).
- Any code still using annotation-only plugins for managers that now ship attribute support should be flagged for 11.x migration but does not need to be touched for 10.4.
- Avoid introducing new procedural hooks if a clean `#[Hook]` conversion is already on your roadmap for 11.x.
- Do not rely on behaviour scheduled for removal in 11.x (jQuery UI dialog, CKEditor 4 upgrade path, Stable 9 theme) — treat as already deprecated.

## OOP hook policy

- Identical to 10.3: `#[Hook]` is **optional**.
- Do not refactor working procedural hooks solely for the 10.4 upgrade.
- If you are dual-targeting 10.4 and 11.x, prefer `#[Hook]` for new hooks to minimise the 11.x diff.

## Plugin attribute policy

- Identical policy to 10.3.
- No additional plugin types gained attribute discovery in 10.4.
- Keep using annotations for plugins on managers that have not yet adopted attributes.

## Test base classes

- Same set as 10.3 (`BrowserTestBase`, `WebDriverTestBase`, `KernelTestBase`, `UnitTestCase`).
- PHPUnit 10 is the supported runner; PHPUnit 9 still works but is on the way out.
- Verify any custom `Drupal\Tests\...\Traits` against the 10.4 trait set — a few were marked internal.

## Minimum PHP

- **PHP 8.1.0** (PHP 8.3 recommended).
- Identical runtime requirements to 10.3.
- No PHP-version-driven syntax changes between 10.3 and 10.4.
