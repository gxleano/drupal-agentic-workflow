# Drupal 11 Rules for CLAUDE.md

> These rules are automatically appended to your project's `CLAUDE.md` by `setup.sh`.
> Replace placeholder values marked with `{...}` with your project details.

---

## Critical Code Rules (Always Follow)

### PHP / Drupal 11
- `declare(strict_types=1)` on all new PHP files
- `protected readonly` constructor property promotion for injected services
- PHP attributes (`#[Block]`, `#[Hook]`) instead of docblock annotations
- `match` instead of `switch` for simple conditionals
- `static` instead of `self` in `create()` methods and factories
- Fully type all parameters, properties, and return types
- 2-space indentation, `\Exception` not `use Exception`, `@todo` not `TODO:`

### Dependency Injection
- Constructor injection with interfaces (`EntityTypeManagerInterface`, not `EntityTypeManager`)
- Never `\Drupal::` in service classes — inject via constructor
- `AutowireTrait` for plugins when all services are standard container services
- Fall back to explicit `create()` only when runtime logic decides dependencies

### Plugins
- `#[Block(...)]` attribute, not `@Block(...)` annotation
- `final class` unless extension is explicitly intended
- Fully typed constructor params: `string $plugin_id`, `array $plugin_definition`

### Hooks
- `#[Hook]` attribute classes in `src/Hook/` for all new hooks
- Only `hook_theme()`, `hook_preprocess_*()`, `hook_install()`, `hook_update_N()` stay in `.module`
- Group related hooks by domain (`FormHooks`, `EntityHooks`)
- Inject services via constructor, never `\Drupal::` in hook classes

### Documentation
- No redundant docblocks — if the type says it, don't repeat it
- Document array structures (`@param array{key: type}`), side effects, and `@throws`
- `{@inheritdoc}` for overridden methods

### Caching
- All render arrays must include `#cache` metadata (tags, contexts, max-age)
- Use `Cache::mergeTags()` / `Cache::mergeContexts()` to combine
- Entity cache tags via `$entity->getCacheTags()`

### Security
- `->accessCheck(TRUE)` on all entity queries (or `FALSE` with justification)
- Sanitize user input: `$this->t()`, `Xss::filter()`, `Html::escape()`
- In JS: `Drupal.checkPlain()` for any user-controlled data inserted into DOM

## Code Quality

Enforced at two levels:
1. **Post-generation hook** (`.claude/hooks/`) — on every file Write/Edit:
   - **Prettier** — Formats JS/TS, CSS/SCSS, Twig, YAML, JSON before linting (optional, skipped if not installed)
   - **phpcs** — Drupal + DrupalPractice coding standards (via ddev)
   - **eslint** — JavaScript/TypeScript linting
   - **stylelint** — CSS/SCSS linting
   - **security scan** — `eval()`, `shell_exec()`, `$_GET`, `unserialize()`, `extract()` (local grep, instant)
   - **performance scan** — `\Drupal::` in `src/`, missing `accessCheck()` on entity queries (local grep, instant)
2. **Manual** — run checks explicitly when needed

**IMPORTANT**: When generating or modifying PHP code for custom modules, Claude Code must:

1. **Generate the code** following Drupal coding standards
2. **Immediately run phpcbf** to auto-fix violations:
   ```bash
   ddev exec phpcbf --standard=Drupal,DrupalPractice --extensions=php,module,inc,install,test,profile,theme web/modules/custom/{module_name}
   ```
3. **Verify with phpcs** to ensure no remaining violations:
   ```bash
   ddev exec phpcs --standard=Drupal,DrupalPractice --extensions=php,module,inc,install,test,profile,theme web/modules/custom/{module_name}
   ```
4. **Optional: Run PHPStan** for static analysis (when requested or for critical code):
   ```bash
   ddev exec phpstan analyze web/modules/custom/{module_name}
   ```

## Custom Modules

Located in `web/modules/custom/`. Each module has an `AI_CONTEXT.md` file — **read it first** before exploring module code. It provides architecture, class map, data flow, and key decisions that save significant time vs. reading all source files.

<!-- List your custom modules here. Example format:
- **my_module**: Brief description — [AI_CONTEXT.md](web/modules/custom/my_module/AI_CONTEXT.md)
-->

## Installed Contributed Modules/Themes

<!-- List your installed contrib modules/themes here. Example format:
- **drupal/gin** ^5.0: Modern admin theme
- **drupal/token** ^1.17: Token support
- **cweagans/composer-patches** ^1.7: Composer patching
-->

## Frontend / Theming

### Twig Templates
- Auto-escaped by default — never use `|raw` with user-controlled data
- Use `{{ attach_library('theme/library-name') }}` for CSS/JS
- Use `{% trans %}` for translatable strings
- Template naming: `node--{type}--{viewmode}.html.twig`
- Use `{{ dump() }}` for debugging (with Twig debug enabled)

### Single Directory Components (SDC)
- Available in Drupal 10.1+, stable in 10.3+
- Components live in `components/{name}/` with `*.component.yml` schema
- Use `/drupal-frontend-expert` for SDC guidance

### CSS/JS Libraries
- Define in `*.libraries.yml`, attach via `{{ attach_library() }}`
- Use `Drupal.behaviors` with `once()` for JS initialization
- jQuery-free patterns preferred for new code

### Prettier Formatting
- `.prettierrc.json` handles JS/TS, CSS/SCSS, Twig, YAML, JSON (not PHP)
- Runs automatically in the post-generation hook when installed
- Install: `npm install --save-dev prettier`
- For Twig: `npm install --save-dev prettier-plugin-twig-melody`

## Security

Proactive security is enforced during development via the `drupal-security` skill:

- **Never** use `|raw` in Twig with user-controlled variables
- **Never** concatenate user input into SQL queries — use the query builder
- **Always** use `->accessCheck(TRUE)` on entity queries
- **Always** add access requirements to routes (`_permission` or `_access`)
- **Prefer** `#plain_text` over `#markup` for user-controlled output
- **Use** environment variables for secrets, never hardcode credentials
- **Use** Form API for all forms (automatic CSRF protection)

Use `/drupal-security` for detailed guidance on specific security patterns.

## JavaScript

ESLint configuration in `web/core/.eslintrc.json`:
- Airbnb base + Prettier
- ECMAScript 2020
- Drupal globals (Drupal, drupalSettings, jQuery)

## NEVER Commit

- `web/sites/default/settings.local.php`
- `.ddev/.env` or any secret values
- `vendor/` directory
