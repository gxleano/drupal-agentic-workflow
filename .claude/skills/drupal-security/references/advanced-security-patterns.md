# Advanced Security Patterns

Extended security reference covering SSRF prevention, secure design, software integrity, cryptographic safety, dependency security, security logging, and authentication hardening. Based on OWASP Top 10 (2021) mapped to Drupal-specific mitigations.

Attribution: Patterns informed by [Ivan Grynenko's Drupal security rules](https://github.com/AvaelKross/ivangrynenko-cursorrules-drupal) (MIT licensed).

---

## SSRF Prevention (A10:2021)

Server-Side Request Forgery occurs when user input controls URLs that the server fetches.

### Anti-Patterns

```php
// UNSAFE — user input directly in URL
$response = $this->httpClient->get($request->query->get('url'));

// UNSAFE — user input in Guzzle without validation
$client = new Client(['base_uri' => $userProvidedDomain]);

// UNSAFE — file_get_contents with user-controlled URL
$content = file_get_contents($url_from_form);

// UNSAFE — PHP stream wrappers can access internal resources
$data = file_get_contents('php://filter/read=convert.base64-encode/resource=' . $user_input);
```

### Safe Patterns

```php
// SAFE — validate URL scheme and domain before fetching
use Drupal\Component\Utility\UrlHelper;

$url = $request->query->get('url');
if (!UrlHelper::isValid($url, TRUE)) {
  throw new BadRequestHttpException('Invalid URL.');
}

// Verify it's not an internal/private IP
$host = parse_url($url, PHP_URL_HOST);
$ip = gethostbyname($host);
$blockedRanges = ['10.', '172.16.', '192.168.', '127.', '169.254.', '0.'];
foreach ($blockedRanges as $range) {
  if (str_starts_with($ip, $range)) {
    throw new BadRequestHttpException('Internal URLs are not allowed.');
  }
}

// SAFE — use Drupal's HTTP client with timeout and redirect limits
$response = $this->httpClient->get($url, [
  'timeout' => 10,
  'max_redirects' => 3,
  'allow_redirects' => ['strict' => TRUE],
]);
```

### Rules

1. **Never** pass user input directly to `file_get_contents()`, `fopen()`, or HTTP clients
2. **Always** validate URLs with `UrlHelper::isValid()` and check scheme (http/https only)
3. **Block** internal IP ranges (10.x, 172.16.x, 192.168.x, 127.x, 169.254.x)
4. **Restrict** PHP stream wrappers — never allow `php://`, `data://`, `expect://` from user input
5. **Set timeouts** and redirect limits on all outbound HTTP requests
6. **Disable** XML external entity loading when parsing XML from external sources

---

## Secure Design Patterns (A04:2021)

### Permission Design

```php
// GOOD — verb + object pattern for permissions
'create article content'
'edit own article content'
'delete any article content'
'administer my_module settings'

// BAD — vague or overly broad permissions
'access my module'      // What access? View? Edit? Delete?
'do stuff'              // Meaningless
'administer everything' // Too broad
```

### Separation of Concerns

```php
// BAD — database logic in a controller
class MyController {
  public function list(): array {
    $query = $this->database->select('my_table', 'm');
    $query->fields('m');
    $query->condition('status', 1);
    // 30 lines of query building and processing...
    return ['#theme' => 'my_list', '#items' => $results];
  }
}

// GOOD — controller delegates to service
class MyController {
  public function list(): array {
    $items = $this->myService->getActiveItems();
    return ['#theme' => 'my_list', '#items' => $items];
  }
}
```

### Avoid Insecure Defaults

```yaml
# BAD — permission defaults to TRUE
my_module.settings:
  type: config_object
  mapping:
    allow_anonymous_uploads:
      type: boolean
      # Default should be FALSE (secure by default)
```

```php
// GOOD — secure defaults, opt-in for permissive settings
$config = $this->configFactory->get('my_module.settings');
$allowAnonymous = $config->get('allow_anonymous_uploads') ?? FALSE;
```

### Entity Access Handlers

```php
// Every custom entity type MUST have an access handler
/**
 * @ContentEntityType(
 *   ...
 *   handlers = {
 *     "access" = "Drupal\my_module\MyEntityAccessControlHandler",
 *   },
 * )
 */

// Access handler must check granular permissions
class MyEntityAccessControlHandler extends EntityAccessControlHandler {
  protected function checkAccess(EntityInterface $entity, $operation, AccountInterface $account): AccessResultInterface {
    return match ($operation) {
      'view' => AccessResult::allowedIfHasPermission($account, 'view my_entity'),
      'update' => AccessResult::allowedIfHasPermission($account, 'edit my_entity'),
      'delete' => AccessResult::allowedIfHasPermission($account, 'delete my_entity'),
      default => AccessResult::neutral(),
    };
  }
}
```

---

## Software & Data Integrity (A08:2021)

### Dangerous Functions — Expanded Red Flags

| Function | Risk | Safe Alternative |
|----------|------|-----------------|
| `eval()` | Arbitrary code execution | Refactor logic, use callbacks |
| `assert()` (with string) | Code execution in older PHP | Use as boolean assertion only |
| `create_function()` | Deprecated, code injection | Anonymous functions (`fn()`) |
| `preg_replace('/e')` | Code execution via regex | `preg_replace_callback()` |
| `call_user_func($user_input)` | Arbitrary function call | Whitelist allowed callbacks |
| `include`/`require` with variable | Local file inclusion | Whitelist allowed paths |
| `unserialize($user_data)` | Object injection | `json_decode()` |
| `extract($user_data)` | Variable injection | Explicit array access |
| `$$variable` | Variable variable injection | Associative array |

### Dynamic Includes

```php
// UNSAFE — user input controls which file is included
$template = $request->get('template');
include "/templates/$template.php";  // Path traversal + LFI

// SAFE — whitelist approach
$allowed = ['default', 'compact', 'detailed'];
$template = $request->get('template');
if (!in_array($template, $allowed, TRUE)) {
  $template = 'default';
}
include "/templates/$template.php";
```

### Config Import Safety

```php
// When importing config from external sources, validate first
// Never import config from untrusted sources without review
// Use config_readonly in production to prevent runtime changes
```

### Composer Integrity

```bash
# REQUIRED in CI/CD pipeline
composer audit                  # Check for known vulnerabilities
composer validate               # Validate composer.json
composer install --no-dev       # No dev dependencies in production

# Verify composer.lock is committed (deterministic builds)
git ls-files composer.lock      # Must be tracked
```

---

## Cryptographic Failures (A02:2021)

### Weak Hashing Detection

```php
// UNSAFE — weak hash algorithms
$hash = md5($password);           // Broken for passwords
$hash = sha1($data);              // Weak for integrity
$token = md5(uniqid());           // Predictable

// SAFE — use proper hashing
$hash = password_hash($password, PASSWORD_DEFAULT);  // bcrypt
$token = Crypt::randomBytesBase64(55);               // Drupal's secure random
$hash = hash('sha256', $data);                       // For data integrity (not passwords)
```

### Secure Random Generation

```php
// UNSAFE — predictable random
$token = rand();
$token = mt_rand();
$token = uniqid();

// SAFE — cryptographically secure
use Drupal\Component\Utility\Crypt;
$token = Crypt::randomBytesBase64(55);

// Or PHP native
$bytes = random_bytes(32);
$token = bin2hex($bytes);
```

### API Token Safety

```php
// API tokens MUST:
// 1. Be stored encrypted or hashed (never plaintext in DB)
// 2. Have expiration dates
// 3. Support rotation
// 4. Be revocable
// 5. Use environment variables for static tokens

// UNSAFE — plaintext token in database
$entity->set('api_token', $token)->save();

// SAFER — store hashed, verify with hash_equals
$entity->set('api_token_hash', hash('sha256', $token))->save();

// Verify:
if (hash_equals($entity->get('api_token_hash')->value, hash('sha256', $submitted_token))) {
  // Token valid
}
```

---

## Dependency Security (A06:2021)

### Deprecated Functions to Flag

These indicate outdated code that may have security implications:

```php
// Drupal deprecated functions (removed or will be removed)
drupal_set_message()    // Use \Drupal::messenger()->addMessage()
format_date()           // Use \Drupal::service('date.formatter')->format()
entity_load()           // Use EntityTypeManager::getStorage()->load()
db_query()              // Use injected database connection
db_select()             // Use injected database connection
check_plain()           // Use Html::escape()
l()                     // Use Link::fromTextAndUrl()
url()                   // Use Url::fromRoute()
file_prepare_directory() // Use FileSystemInterface::prepareDirectory()
```

### Security Advisory Package

```json
// composer.json — require this to prevent installing packages with known vulnerabilities
{
  "require": {
    "drupal/core-security-advisories": "dev-main"
  }
}
```

### Subresource Integrity

```html
<!-- When loading external scripts, use SRI -->
<script src="https://cdn.example.com/lib.js"
  integrity="sha384-HASH_HERE"
  crossorigin="anonymous"></script>
```

In Drupal libraries:
```yaml
# my_module.libraries.yml
external_lib:
  js:
    https://cdn.example.com/lib.js:
      type: external
      attributes:
        integrity: 'sha384-HASH_HERE'
        crossorigin: anonymous
```

---

## Security Logging (A09:2021)

### Events That MUST Be Logged

1. **Authentication events** — login success/failure, logout, password reset
2. **Access control decisions** — permission denied, role changes
3. **Configuration changes** — settings modifications, module enable/disable
4. **Data operations** — entity create/delete (sensitive types), bulk operations
5. **File operations** — uploads, permission changes, deletions
6. **API access** — external API calls, rate limit triggers
7. **Security events** — CSRF failures, flood control triggers, suspicious input

### Logging Patterns

```php
// LOG — authentication failure with context
$this->logger->warning('Failed login attempt for @user from @ip.', [
  '@user' => $username,
  '@ip' => $request->getClientIp(),
]);

// LOG — access denial with context
$this->logger->notice('Access denied to @path for user @uid (permission: @perm).', [
  '@path' => $request->getPathInfo(),
  '@uid' => $this->currentUser->id(),
  '@perm' => $required_permission,
]);

// LOG — configuration change
$this->logger->info('Module settings updated by @user: @changes.', [
  '@user' => $this->currentUser->getDisplayName(),
  '@changes' => implode(', ', $changed_keys),
]);
```

### Anti-Patterns

```php
// BAD — suppressed errors hide security issues
@file_get_contents($path);
error_reporting(0);

// BAD — empty catch blocks swallow evidence
try { $this->process($data); }
catch (\Exception $e) { /* silently fail */ }

// BAD — logging sensitive data
$this->logger->debug('API call with key: @key', ['@key' => $api_key]);
```

---

## Authentication Hardening (A07:2021)

### Password Policy

```bash
# Install password policy module
ddev composer require drupal/password_policy
ddev drush en password_policy -y
```

Configure at `/admin/config/security/password-policy`:
- Minimum length: 12+ characters
- Require uppercase, lowercase, digit, special character
- Password history (prevent reuse of last N passwords)
- Password expiry (for high-security sites)

### Session Management

```php
// settings.php — session hardening
ini_set('session.cookie_secure', TRUE);      // HTTPS only
ini_set('session.cookie_httponly', TRUE);     // No JS access
ini_set('session.cookie_samesite', 'Lax');   // CSRF mitigation
ini_set('session.cookie_lifetime', 0);       // Session cookie (cleared on browser close)

// For high-security: limit session duration
$config['system.performance']['session_gc_maxlifetime'] = 3600; // 1 hour
```

### Password Comparison

```php
// UNSAFE — timing attack vulnerable
if ($stored_hash === $submitted_hash) { /* ... */ }

// SAFE — constant-time comparison
if (hash_equals($stored_hash, $submitted_hash)) { /* ... */ }

// SAFE — Drupal's password service handles this correctly
$password_service = \Drupal::service('password');
$password_service->check($submitted_password, $stored_hash);
```

### Flood Control

```php
// Check flood before sensitive operations
$flood = \Drupal::service('user.flood_control');

// IP-based limit (50 attempts per hour)
if (!$flood->isAllowed('my_module.sensitive_action', 50)) {
  throw new AccessDeniedHttpException('Too many attempts. Try again later.');
}

// Register the attempt
$flood->register('my_module.sensitive_action');
```

---

## Security Configuration Hardening (A05:2021)

### Production settings.php Checklist

```php
// REQUIRED for production
$settings['trusted_host_patterns'] = [
  '^www\.example\.com$',
  '^example\.com$',
];

// Disable dangerous access flags
$settings['update_free_access'] = FALSE;
$settings['rebuild_access'] = FALSE;

// Disable error display
$config['system.logging']['error_level'] = 'hide';

// Disable Twig debug
$settings['twig_debug'] = FALSE;
$settings['twig_auto_reload'] = FALSE;
$settings['twig_cache'] = TRUE;
```

### Security Headers

Configure at web server level or via middleware:

```
X-Frame-Options: SAMEORIGIN
X-Content-Type-Options: nosniff
X-XSS-Protection: 1; mode=block
Referrer-Policy: strict-origin-when-cross-origin
Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline'
Permissions-Policy: camera=(), microphone=(), geolocation=()
Strict-Transport-Security: max-age=31536000; includeSubDomains
```

### Development Modules — Never in Production

These modules MUST NOT be enabled in production `core.extension.yml`:

- `devel` — exposes internal data
- `webprofiler` — exposes profiling data
- `field_ui` — allows field manipulation
- `views_ui` — allows view manipulation
- `dblog` — use `syslog` in production for performance

Use Config Split to manage this automatically.

### File Permission Standards

| Path | Permission | Notes |
|------|-----------|-------|
| `settings.php` | `444` (read-only) | After installation |
| `web/sites/default/` | `555` (read + execute) | Prevents writing |
| `web/sites/default/files/` | `755` | Writable for uploads |
| Private files directory | `750` | Outside webroot |
