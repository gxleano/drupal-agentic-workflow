# AI-Assisted Drupal Development Patterns

Methodologies for effective AI-assisted Drupal development, based on patterns from the Drupal community's AI tooling.

## The Context-First Approach

**CRITICAL: Always gather context before generating code.**

### Step 1: Find Similar Files

```bash
find modules/custom -name "*.services.yml" -exec grep -l "entity_type.manager" {} \;
find modules/custom -name "*Form.php" -type f
find modules/custom -path "*/Controller/*.php" -type f
find modules/custom -path "*/Plugin/Block/*.php" -type f
```

### Step 2: Understand Project Patterns

1. **Naming patterns** — Service naming, class naming, file organization
2. **Dependency patterns** — Common injections, logging, entity loading
3. **Configuration patterns** — Where config is stored, settings forms, schemas

### Step 3: Provide Context in Requests

```markdown
**Bad request:**
"Create a service that processes nodes"

**Good request:**
"Create a service that processes article nodes.

Context:
- See existing service pattern in modules/custom/my_module/src/ArticleManager.php
- Inject entity_type.manager and logger.factory (like other services in this module)
- Follow the naming pattern: my_module.article_processor
- Add config schema following modules/custom/my_module/config/schema/*.yml pattern"
```

## Structured Prompting for Drupal Tasks

**Use hierarchical prompts for complex generation tasks.**

### Prompt Template

```markdown
## Task
[One sentence describing what you want to create]

## Module Context
- Module name: my_custom_module
- Module path: modules/custom/my_custom_module
- Drupal version: 11
- PHP version: 8.3+

## Requirements
- [Specific requirement 1]
- [Specific requirement 2]

## Code Standards
- Use constructor property promotion
- Use PHP 8 attributes for plugins
- Inject all dependencies (no \Drupal::service())

## Similar Files (for reference)
- [Path to similar implementation]

## Expected Output
- [File 1]: [Description]
- [File 2]: [Description]
```

### Example: Creating a Block Plugin

```markdown
## Task
Create a block that displays recent articles with a configurable limit.

## Module Context
- Module name: my_articles
- Drupal version: 11
- PHP version: 8.3+

## Requirements
- Display recent article nodes (type: article)
- Configurable number of items (default: 5)
- Cache per page with article list tag

## Code Standards
- Use #[Block] attribute (not annotation)
- Inject entity_type.manager and date.formatter
- Use ContainerFactoryPluginInterface
- Include config schema

## Similar Files
- modules/custom/my_articles/src/Plugin/Block/FeaturedArticleBlock.php

## Expected Output
- src/Plugin/Block/RecentArticlesBlock.php
- config/schema/my_articles.schema.yml (update)
```

## The Inside-Out Approach

Based on the Drupal AI CodeGenerator pattern, breaking complex tasks into deterministic steps.

### Phase 1: Task Classification

| Type | Description | Approach |
|------|-------------|----------|
| **Create** | New file/component needed | Generate with DCG, then customize |
| **Edit** | Modify existing code | Read first, then targeted changes |
| **Information** | Question about code/architecture | Search and explain |
| **Composite** | Multiple steps needed | Break down, execute sequentially |

### Phase 2: Solvability Check

Before generating, verify:
- Required dependencies available?
- Target directory exists and is writable?
- No conflicting files/classes?
- All referenced services/classes exist?
- Compatible with Drupal version?

### Phase 3: Scaffolding First

**Use DCG to scaffold, then customize:**

```bash
drush generate plugin:block --answers='{
  "module": "my_module",
  "plugin_id": "recent_articles",
  "admin_label": "Recent Articles",
  "class": "RecentArticlesBlock"
}'
# Then customize the generated file
```

### Phase 4: Auto-Generate Tests

```bash
drush generate test:kernel --answers='{
  "module": "my_module",
  "class": "RecentArticlesBlockTest"
}'
```

## Iterative Development Workflow

**Expect 80% completion from AI-generated code.** Plan for refinement.

```
1. GATHER CONTEXT    → Find similar files, understand patterns
2. GENERATE (~80%)   → Scaffold with DCG, generate business logic
3. REVIEW & REFINE   → Security, DI compliance, config schema, PHPCS
4. TEST              → Generated tests + edge cases + manual smoke
5. ITERATE           → Fix failures, address feedback
```

### Common Refinement Tasks

| Issue | Solution |
|-------|----------|
| PHPCS errors | Run `phpcbf` for auto-fix |
| Missing DI | Add to constructor, update `create()` |
| No cache metadata | Add `#cache` with tags, contexts, max-age |
| Missing access check | Add permission check or access handler |
| No config schema | Create schema matching config structure |
| Hardcoded strings | Wrap in `$this->t()` with placeholders |

## Prompt Patterns for Common Tasks

### Content Type with Fields

```markdown
Create a content type for [purpose].
- Machine name: [machine_name]
- Label: [Human Label]
- Publishing options: published by default, create new revision

Fields:
1. [field_name] ([field_type]): [description] - [required/optional]

After creation, export config with: drush cex -y
```

### Custom Service

```markdown
Create a service for [purpose].
- Name: [module].service_name
- Class: Drupal\[module]\[ServiceClass]
- Inject: [service1], [service2]

Methods:
- methodName(params): return_type - [description]

Include: Interface, services.yml entry, PHPDoc
```

### Event Subscriber

```markdown
Create an event subscriber for [purpose].
- Class: Drupal\[module]\EventSubscriber\[ClassName]
- Event: [event.name]
- Priority: [0-100]

Behavior:
- [Describe what should happen when event fires]

Include: services.yml entry with tags, proper type hints
```

## Debugging AI-Generated Code

```bash
php -l modules/custom/my_module/src/MyClass.php                              # Syntax check
drush cr                                                                      # Clear caches
drush devel:services | grep my_module                                        # Check container
grep -n "^use" modules/custom/my_module/src/MyClass.php                      # Use statements
drush php:eval "class_exists('Drupal\my_module\MyClass') ? print 'Found' : print 'Not found';"
drush ws --severity=error --count=20                                         # Check logs
```

## Sources

- [Building a Drupal Module Using AI - Jacob Rockowitz](https://www.jrockowitz.com/blog/building-a-drupal-model-using-al)
- [AI Generation Module](https://www.drupal.org/project/ai_generation)
- [AI Module](https://www.drupal.org/project/ai)
- [CodeGenerator Agent Pattern](https://git.drupalcode.org/-/snippets/261)
