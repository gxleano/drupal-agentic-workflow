# Testing Context

This file documents your project's test infrastructure, existing coverage, and known gaps.
Fill in the sections below after running your test suite.

## Test Infrastructure

- **PHPUnit config**: `web/core/phpunit.xml.dist`
- **Run all tests**: `ddev exec vendor/bin/phpunit -c web/core web/modules/custom/`
- **Run module tests**: `ddev exec vendor/bin/phpunit -c web/core web/modules/custom/{module_name}`
- **Run by type**: `ddev exec vendor/bin/phpunit -c web/core --testsuite=unit`

## Custom Module Test Coverage

<!-- Add a section for each custom module. Example:

### my_module

**Existing tests:**
- `tests/src/Unit/Services/MyServiceTest.php` — 5 tests, covers MyService
- `tests/src/Kernel/Form/MyFormTest.php` — 3 tests, covers form validation

**Test base classes:**
- None custom (uses standard Drupal base classes)

**Known gaps:**
- No functional tests for admin pages
- MyOtherService has no test coverage
- Plugin classes untested

-->

## Shared Test Utilities

<!-- Document any shared traits, base classes, or helpers.

Example:
- `tests/src/Traits/MyTestTrait.php` — Provides helper methods for creating test entities

-->

## Test Environment Notes

<!-- Document any special setup needed for tests.

Example:
- Tests require `node` and `taxonomy` modules enabled
- Kernel tests need `installEntitySchema('my_entity')`
- API tests mock HTTP client via `GuzzleMiddleware`

-->
