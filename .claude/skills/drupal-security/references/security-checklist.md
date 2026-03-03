# Drupal Security Checklist

Comprehensive security reference mapping OWASP Top 10 to Drupal-specific mitigations, with code examples and review procedures.

## OWASP Top 10 — Drupal Mitigations

### 1. Injection (A03:2021)

**SQL Injection:**

```php
// UNSAFE
$result = $db->query("SELECT * FROM {users_field_data} WHERE name = '" . $name . "'");

// SAFE — parameterized query
$result = $db->query('SELECT * FROM {users_field_data} WHERE name = :name', [':name' => $name]);

// SAFE — query builder
$query = $db->select('users_field_data', 'u')
  ->fields('u', ['uid', 'name'])
  ->condition('u.name', $name);
```

**LDAP Injection:** Use Drupal's LDAP module with proper escaping.

**Command Injection:**

```php
// UNSAFE
exec('convert ' . $filename . ' output.png');

// SAFE — use Symfony Process
use Symfony\Component\Process\Process;
$process = new Process(['convert', $filename, 'output.png']);
$process->run();
```

### 2. Broken Authentication (A07:2021)

**Drupal mitigations:**
- Core password hashing (bcrypt-based `PhpassHashedPassword`)
- Flood control for login attempts (`user.flood_control` service)
- Session management with automatic regeneration on login
- Two-factor authentication via contrib (`tfa` module)

```php
// Check flood control before login
$flood = \Drupal::service('user.flood_control');
if (!$flood->isAllowed('user.failed_login_ip', 50)) {
  throw new AccessDeniedHttpException('Too many login attempts.');
}
```

**Recommendations:**
- Enable `flood_control` settings in `settings.php`
- Use strong password policies (`password_policy` module)
- Implement TFA for admin accounts
- Set appropriate session lifetimes

### 3. Sensitive Data Exposure (A02:2021)

**Drupal mitigations:**

```php
// settings.php — force HTTPS
$settings['reverse_proxy'] = TRUE;
// Redirect HTTP to HTTPS at web server level

// Private file system for sensitive uploads
$settings['file_private_path'] = '/path/outside/webroot/private';

// Hash salt from environment
$settings['hash_salt'] = getenv('DRUPAL_HASH_SALT');

// Database credentials from environment
$databases['default']['default'] = [
  'database' => getenv('DB_NAME'),
  'username' => getenv('DB_USER'),
  'password' => getenv('DB_PASS'),
  'host' => getenv('DB_HOST'),
  'driver' => 'mysql',
];
```

**Recommendations:**
- HTTPS everywhere (enforce at web server)
- Private file system for non-public files
- Environment variables for all secrets
- Remove `CHANGELOG.txt`, `web.config`, `README.md` from production
- Disable verbose error reporting in production

### 4. XML External Entities (A05:2021)

**Drupal mitigations:**
- PHP 8 disables external entity loading by default
- Drupal's XML handling uses safe defaults
- Verify: `libxml_disable_entity_loader(true)` for PHP < 8.0

### 5. Broken Access Control (A01:2021)

```php
// UNSAFE — no access check on entity query
$nodes = $storage->getQuery()->execute();

// SAFE — access check enforced
$nodes = $storage->getQuery()
  ->accessCheck(TRUE)
  ->condition('type', 'article')
  ->execute();

// UNSAFE — route without permissions
// my_module.routing.yml
my_module.admin:
  path: '/admin/secret'
  defaults:
    _controller: '\Drupal\my_module\Controller\AdminController'
  # Missing requirements!

// SAFE — route with permissions
my_module.admin:
  path: '/admin/secret'
  defaults:
    _controller: '\Drupal\my_module\Controller\AdminController'
  requirements:
    _permission: 'administer site configuration'
```

**Recommendations:**
- Review all custom routes for access requirements
- Use `accessCheck(TRUE)` on all entity queries
- Implement `EntityAccessControlHandler` for custom entities
- Test access as anonymous, authenticated, and admin users
- Use role-based permissions, not user ID checks

### 6. Security Misconfiguration (A05:2021)

**Production settings.php hardening:**

```php
// Disable error display
$config['system.logging']['error_level'] = 'hide';

// Enable CSS/JS aggregation
$config['system.performance']['css']['preprocess'] = TRUE;
$config['system.performance']['js']['preprocess'] = TRUE;

// Disable Twig debug
$settings['twig_debug'] = FALSE;

// Set trusted host patterns
$settings['trusted_host_patterns'] = [
  '^www\.example\.com$',
  '^example\.com$',
];

// Remove development modules
// Ensure devel, webprofiler, field_ui, views_ui are NOT enabled in production
```

**Recommendations:**
- Regular Drupal core and contrib updates
- Run `drush updatedb` after updates
- Enable Update Manager module to check for updates
- Review file permissions (directories: 755, files: 644, settings.php: 444)
- Disable unused modules
- Configure trusted host patterns

### 7. Cross-Site Scripting / XSS (A03:2021)

```php
// UNSAFE — raw user input in markup
$build['output'] = ['#markup' => $user_comment];

// SAFE — plain text (auto-escaped)
$build['output'] = ['#plain_text' => $user_comment];

// SAFE — filtered HTML
$build['output'] = ['#markup' => Xss::filter($user_comment)];

// SAFE — translation with placeholder
$build['greeting'] = ['#markup' => $this->t('Hello @name', ['@name' => $username])];
```

```twig
{# SAFE — auto-escaped #}
{{ node.title.value }}

{# UNSAFE — raw filter bypasses escaping #}
{{ user_input|raw }}

{# SAFE — explicit escaping (redundant but safe) #}
{{ user_input|escape }}
```

**Placeholder types in `t()`:**

| Placeholder | Escaping | Use for |
|-------------|----------|---------|
| `@variable` | `Html::escape()` | Plain text |
| `%variable` | `Html::escape()` + `<em>` wrap | Emphasized text |
| `:variable` | `Html::escape()` + URL check | URLs |

### 8. Insecure Deserialization (A08:2021)

```php
// UNSAFE — unserialize user data (object injection)
$data = unserialize($request->get('data'));

// SAFE — use JSON
$data = json_decode($request->get('data'), TRUE);

// SAFE — if serialization is needed, use Drupal's serialization
$serializer = \Drupal::service('serialization.phpserialize');
// Only for trusted, internal data
```

### 9. Components with Known Vulnerabilities (A06:2021)

```bash
# Check for known PHP package vulnerabilities
ddev composer audit

# Check Drupal security advisories
ddev drush pm:security

# Update everything
ddev composer update --with-dependencies
ddev drush updb -y
ddev drush cr
```

**Recommendations:**
- Run `composer audit` in CI/CD pipeline
- Subscribe to Drupal security advisories (drupal.org/security)
- Update promptly when security advisories are published
- Use `drupal/core-recommended` (locks transitive dependencies)

### 10. Insufficient Logging & Monitoring (A09:2021)

```php
// Log security events
$this->logger->warning('Failed login attempt for @user from @ip.', [
  '@user' => $username,
  '@ip' => $request->getClientIp(),
]);

$this->logger->critical('Unauthorized access attempt to @path by @user.', [
  '@path' => $request->getPathInfo(),
  '@user' => $this->currentUser->getAccountName(),
]);
```

```bash
# View recent security logs
ddev drush ws --severity=warning --count=50
ddev drush ws --type=security --count=20
```

**Recommendations:**
- Configure syslog module for production (not dblog)
- Monitor failed login attempts
- Alert on repeated access denied errors
- Log and monitor file upload activity
- Implement rate limiting on sensitive endpoints

---

## Security Review Procedure

### Manual Code Review Checklist

**For every code change, verify:**

- [ ] No hardcoded credentials or API keys
- [ ] All SQL queries use parameterized methods
- [ ] All render arrays use `#plain_text` or proper sanitization
- [ ] All routes have access requirements
- [ ] All entity queries use `->accessCheck()`
- [ ] No `|raw` filter in Twig with user data
- [ ] File uploads validate extensions and MIME types
- [ ] Forms use Form API (CSRF protection)
- [ ] No dangerous functions (`eval`, `exec`, `unserialize`)
- [ ] Error messages are generic (no stack traces or DB details)
- [ ] Sensitive data uses environment variables
- [ ] Custom access handlers return `AccessResult` objects

### Automated Tools

**PHPCS with Security Sniffs:**

```bash
# Install PHPCompatibility and security sniffs
ddev composer require --dev phpcompatibility/php-compatibility

# Run security-focused checks
ddev exec phpcs --standard=Drupal,DrupalPractice \
  --extensions=php,module,inc,install,test,profile,theme \
  web/modules/custom/
```

**PHPStan Security Rules:**

```bash
# Install PHPStan with Drupal extension
ddev composer require --dev phpstan/phpstan \
  mglaman/phpstan-drupal \
  phpstan/phpstan-deprecation-rules

# Run analysis
ddev exec phpstan analyze web/modules/custom/
```

**Security Review Module:**

```bash
ddev composer require drupal/security_review
ddev drush en security_review -y
ddev drush security-review
```

Checks: file permissions, input formats, error reporting, private files, admin users, views access, field encryption.

**Composer Audit:**

```bash
# Check for known vulnerabilities in dependencies
ddev composer audit

# Integrate into CI
ddev composer audit --format=json
```

---

## Drupal Security Advisories

### Monitoring

- **Official page**: https://www.drupal.org/security
- **RSS feed**: https://www.drupal.org/security/rss.xml
- **Mailing list**: Subscribe at drupal.org security team page
- **Drush**: `ddev drush pm:security` checks installed modules

### Classification and Response

| Level | Response Time | Action |
|-------|--------------|--------|
| **Highly Critical** | Immediate (hours) | Patch/update immediately, check for exploitation |
| **Critical** | Within 24 hours | Update ASAP, review logs for exploitation |
| **Moderately Critical** | Within 1 week | Schedule update, assess exposure |
| **Less Critical** | Next maintenance window | Plan update, low urgency |
| **Not Critical** | As convenient | Update when possible |

### Response Procedure

1. **Read the advisory** — understand the vulnerability and affected versions
2. **Check exposure** — is your site affected? (version, configuration, public access)
3. **Update** — `composer update drupal/PACKAGE` or apply patch
4. **Run updates** — `drush updb -y && drush cr`
5. **Verify** — test the fix, check logs for past exploitation
6. **Document** — record the update and any findings

---

## Contrib Module Vetting

Before installing any contrib module, evaluate:

### Security Coverage

- **Green shield** on drupal.org = covered by Drupal's security team
- Modules without security coverage may have unreviewed vulnerabilities
- Check: drupal.org project page → "Security advisory coverage" field

### Maintenance Status

| Signal | Good | Bad |
|--------|------|-----|
| Last commit | < 6 months | > 2 years |
| Open issues | Actively triaged | Hundreds unaddressed |
| Release cycle | Regular releases | No releases in 1+ year |
| Maintainer activity | Responds to issues | No activity |

### Code Quality Indicators

- Has automated tests (unit, kernel, functional)
- Passes PHPCS with Drupal standards
- Uses dependency injection (not `\Drupal::` in classes)
- Has config schema for all configuration
- Proper access control on routes and entities

### Usage Statistics

- Number of reported installations (drupal.org)
- Higher usage = more eyes on security
- Very low usage (< 50 sites) = higher risk

### Security History

- Check for past security advisories for the module
- Many past advisories may indicate systemic code quality issues
- Quick response to advisories is a good sign
