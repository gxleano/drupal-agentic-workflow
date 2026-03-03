# Code Review Checklist

Quick-reference checklist for reviewing Drupal code in this project.

---

## Module Structure

- [ ] `.info.yml` has correct `core_version_requirement: ^11`
- [ ] `.info.yml` has correct package
- [ ] Services defined in `.services.yml` with interface arguments
- [ ] Logger channel registered if logging is used
- [ ] Custom cache bins registered if caching is used
- [ ] Routes defined in `.routing.yml` with proper permissions
- [ ] Menu links defined if admin pages exist
- [ ] Directory structure follows convention (`src/Services/`, `src/Plugin/`, etc.)

## PHP 8.3 Compliance

- [ ] Constructor property promotion used (no separate property + assignment)
- [ ] All properties have type declarations
- [ ] All method parameters have type declarations
- [ ] All methods have return type declarations
- [ ] `match()` used instead of simple `switch` statements
- [ ] Named arguments used for boolean parameters and multi-param calls
- [ ] Nullable types use `?Type` syntax
- [ ] Union types used where appropriate (`string|int`)
- [ ] `readonly` used for immutable properties

## SOLID Principles

### Single Responsibility (SRP)
- [ ] Class name clearly describes its one responsibility
- [ ] Class has fewer than 7 public methods
- [ ] No "Manager", "Handler", "Utility" god classes
- [ ] Business logic in services, not in hooks/controllers/forms
- [ ] Each method does one thing

### Open/Closed (OCP)
- [ ] No long if/elseif/switch chains based on type
- [ ] Protected methods used for extension points
- [ ] Plugin system used where behavior varies by type
- [ ] Alter hooks provided for extensibility
- [ ] Event dispatching for significant actions

### Liskov Substitution (LSP)
- [ ] Subclasses don't throw "Not implemented" exceptions
- [ ] Overridden methods maintain parent's contract
- [ ] Return types match or narrow parent types
- [ ] No precondition strengthening in subclasses

### Interface Segregation (ISP)
- [ ] Interfaces have 1-4 focused methods
- [ ] No implementations with unused methods
- [ ] Separate interfaces for separate concerns
- [ ] Clients depend only on methods they use

### Dependency Inversion (DIP)
- [ ] Constructor injection for all dependencies
- [ ] Dependencies typed as interfaces, not concrete classes
- [ ] No `\Drupal::` in service classes
- [ ] No `new ServiceClass()` for Drupal services
- [ ] Services registered in container, not instantiated manually

## Error Handling

- [ ] External API calls wrapped in try-catch
- [ ] Specific exceptions caught before generic `\Exception`
- [ ] All caught exceptions logged with context
- [ ] Safe defaults returned on failure (empty array, NULL, FALSE)
- [ ] No empty catch blocks (swallowed exceptions)
- [ ] Form validation uses `setErrorByName()` with field name
- [ ] User-facing errors use `$this->t()` for translation
- [ ] Log messages include relevant context (`@id`, `@message`, `@type`)

## Caching

- [ ] All render arrays include `#cache` metadata
- [ ] Cache tags match entities that affect output
- [ ] Cache contexts match what varies the output
- [ ] `max-age` set appropriately (not 0 unless necessary)
- [ ] `Cache::mergeTags()` / `Cache::mergeContexts()` used for combining
- [ ] Entity cache tags included (`$entity->getCacheTags()`)
- [ ] List cache tags used for listing pages (`node_list`, `taxonomy_term_list`)
- [ ] Custom cache bins for expensive computations
- [ ] Cache keys are deterministic (sorted arrays, consistent hashing)

## Security

- [ ] Entity queries use `->accessCheck(TRUE)` or `->accessCheck(FALSE)` with justification
- [ ] User input sanitized: `$this->t()`, `Xss::filter()`, `Html::escape()`
- [ ] No raw SQL queries (use Entity Query or Database API)
- [ ] Route permissions defined in `.routing.yml`
- [ ] CSRF protection on state-changing operations
- [ ] File uploads validated (extension, size, MIME type)
- [ ] No hardcoded credentials or API keys
- [ ] Admin forms use `ConfigFormBase` with proper permissions

## PHPDoc Quality

- [ ] All classes have summary + description
- [ ] All public methods have PHPDoc
- [ ] `@param` blocks document type, name, and purpose
- [ ] Array parameters document their keys and types
- [ ] `@return` documents type and structure (for arrays)
- [ ] `@throws` documents thrown exceptions
- [ ] `@see` references related classes/docs
- [ ] `{@inheritdoc}` used for overridden methods
- [ ] No redundant docs (don't restate what code shows)

## Drupal Patterns

- [ ] Render arrays used (not raw HTML strings)
- [ ] Entity API for CRUD (not direct DB queries)
- [ ] Configuration API for persistent settings
- [ ] State API for transient values only
- [ ] Translation API (`$this->t()`, `new TranslatableMarkup()`)
- [ ] Messenger service for user notifications
- [ ] Queue API for deferred/heavy processing
- [ ] Batch API for user-facing bulk operations
- [ ] Event system for cross-module communication

## Coding Standards (PHPCS)

- [ ] 2-space indentation (not tabs, not 4 spaces)
- [ ] `\Exception` (not `use Exception;`)
- [ ] `@todo` format (not `TODO:`)
- [ ] Lines under 80 chars (120 max)
- [ ] Proper spacing around operators
- [ ] Opening brace on same line for classes/methods
- [ ] `elseif` (not `else if`)
- [ ] Trailing comma in multi-line arrays and parameter lists
- [ ] No trailing whitespace
- [ ] Single blank line between methods

## Testing

- [ ] Unit tests for services with business logic
- [ ] Kernel tests for entity/database interactions
- [ ] Functional tests for forms and workflows
- [ ] Test methods named descriptively (`testProcessWithEmptyInput`)
- [ ] `@group` annotation matches module name
- [ ] `@covers` annotation on unit tests
- [ ] Mocks for external dependencies
- [ ] Edge cases covered (empty, null, invalid input)
- [ ] Error paths tested
- [ ] Assertions are specific and meaningful

## Performance

- [ ] No N+1 query patterns (use `loadMultiple()`, not `load()` in loops)
- [ ] Database queries limited (`->range()` on listings)
- [ ] Heavy computations cached
- [ ] Views used for listings (not custom queries when avoidable)
- [ ] Lazy loading for expensive dependencies
- [ ] No unnecessary entity loads
- [ ] Batch processing for large data sets

---

## Severity Quick Reference

| Finding | Severity |
|---------|----------|
| Missing access check on query | Critical |
| XSS vulnerability | Critical |
| SQL injection risk | Critical |
| `\Drupal::` in service class | Major |
| Missing error handling on API call | Major |
| Missing cache metadata on render array | Major |
| God class (too many responsibilities) | Major |
| Fat interface (too many methods) | Major |
| Business logic in hook | Major |
| Missing PHPDoc on public method | Minor |
| `switch` instead of `match` | Minor |
| Line length > 80 chars | Minor |
| TODO instead of @todo | Minor |
| Missing test for edge case | Suggestion |
| Opportunity for better abstraction | Suggestion |
