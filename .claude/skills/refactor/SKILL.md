---
name: refactor
description: Quick inline code review for refactoring opportunities. Identifies over-engineering, god classes, missing interfaces, fat controllers, and Drupal anti-patterns.
---

# Drupal Code Refactoring Assistant

You identify refactoring opportunities in Drupal custom code. Focus on practical improvements, not theoretical perfection.

## What to Look For

### 1. God Classes

Classes doing too much. Signs:
- More than ~300 lines
- More than 5-6 injected dependencies
- Mixed responsibilities (data access + business logic + presentation)

**Fix**: Extract responsibilities into focused services.

```php
// BEFORE: God class
class ContentManager {
  // Handles content creation, validation, notification, logging, caching...
}

// AFTER: Single responsibility
class ContentCreator { /* creates content */ }
class ContentValidator { /* validates content */ }
class ContentNotifier { /* sends notifications */ }
```

### 2. Fat Controllers

Controllers with business logic. Controllers should only:
- Accept input
- Call a service
- Return a response

```php
// BAD: Logic in controller
public function process(Request $request): Response {
  $data = $request->get('data');
  // 50 lines of business logic...
  return new JsonResponse($result);
}

// GOOD: Thin controller
public function process(Request $request): Response {
  $result = $this->processingService->process($request->get('data'));
  return new JsonResponse($result);
}
```

### 3. Fat Hooks

Hook implementations with business logic. Hooks should delegate to services:

```php
// BAD: Logic in hook class
#[Hook('node_presave')]
public function nodePresave(NodeInterface $node): void {
  // 30 lines of business logic directly in hook...
}

// GOOD: Hook delegates to service
#[Hook('node_presave')]
public function nodePresave(NodeInterface $node): void {
  $this->contentProcessor->onPresave($node);
}
```

### 4. Missing Interfaces for Services

Custom services that are injected elsewhere should have interfaces:
- Enables testing with mocks
- Documents the service contract
- Allows swapping implementations

```php
// Define interface
interface DataProcessorInterface {
  public function process(array $data): array;
}

// Implement
class DataProcessor implements DataProcessorInterface {
  public function process(array $data): array { /* ... */ }
}

// Register with interface in services.yml
services:
  my_module.data_processor:
    class: Drupal\my_module\Service\DataProcessor
```

### 5. Static Calls in Service Classes

`\Drupal::` or other static calls in `src/` classes:

```php
// BAD
class MyService {
  public function getData(): array {
    $config = \Drupal::config('my_module.settings');
    $entityTypeManager = \Drupal::entityTypeManager();
  }
}

// GOOD
class MyService {
  public function __construct(
    protected readonly ConfigFactoryInterface $configFactory,
    protected readonly EntityTypeManagerInterface $entityTypeManager,
  ) {}
}
```

### 6. Duplicate Logic

Same patterns repeated across files:
- Similar entity query patterns → extract to a repository service
- Similar form validation → extract to a validator service
- Similar render array building → extract to a builder service

### 7. Over-Engineering

Signs of unnecessary complexity:
- Abstract classes with only one implementation
- Interfaces with only one implementation and no testing need
- Event system for simple method calls
- Plugin system for 2-3 fixed variants (just use a service with match)
- Configuration for values that never change

**Rule**: If it's not needed yet, don't build it. Three similar lines are better than a premature abstraction.

### 8. Missing Error Handling at Boundaries

System boundaries (HTTP, database, file system, external APIs) need error handling:

```php
// BAD: No error handling at API boundary
$response = $this->httpClient->get($url);
$data = json_decode($response->getBody());

// GOOD: Handle failures
try {
  $response = $this->httpClient->get($url);
  $data = json_decode($response->getBody(), TRUE, 512, JSON_THROW_ON_ERROR);
}
catch (GuzzleException $e) {
  $this->logger->error('API request failed: @message', ['@message' => $e->getMessage()]);
  return [];
}
```

### 9. Drupal-Specific Anti-Patterns

| Anti-Pattern | Refactoring |
|-------------|-------------|
| `node_load()` in loops | `Node::loadMultiple($nids)` |
| Raw SQL queries | Entity query or database abstraction |
| `db_query()` (removed) | `\Drupal::database()->query()` or injected `$database` |
| `drupal_set_message()` (removed) | `\Drupal::messenger()->addMessage()` |
| `format_date()` (removed) | `$this->dateFormatter->format()` |
| `l()` / `url()` (removed) | `Url::fromRoute()`, `Link::fromTextAndUrl()` |
| `variable_get/set()` (D7) | Config API or State API |

## Refactoring Workflow

1. **Read the code** — understand what it does before changing anything
2. **Identify the smell** — what specific issue are you addressing?
3. **Check for tests** — if tests exist, they protect the refactoring
4. **Make one change at a time** — don't combine refactorings
5. **Verify behavior** — run tests, check the site manually
6. **Keep commits atomic** — one refactoring per commit

## When NOT to Refactor

- Code that works and won't be changed again
- Code blocked by an upcoming major version upgrade
- Contrib module code (patch/MR upstream instead)
- During a critical bug fix (fix first, refactor later)

## Related Skills

- **code-review** — Full architectural code review (agent-based)
- **drupal-expert** — Drupal development patterns and standards
- **generate-tests** — Generate tests before/after refactoring
- **debug** — Diagnose issues found during refactoring
