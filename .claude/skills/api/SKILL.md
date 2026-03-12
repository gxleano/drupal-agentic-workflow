---
name: api
description: REST, JSON:API, and GraphQL development for decoupled and headless Drupal
version: 1.0.0
---

# API Development — Drupal 11

## Activation

Activate when:
- Working with JSON:API, REST resources, or GraphQL
- Building decoupled / headless Drupal backends
- Configuring API authentication (OAuth, JWT)
- Implementing custom API endpoints
- Troubleshooting API response caching or CORS

## JSON:API (Core)

Drupal core's JSON:API module follows the JSON:API spec (jsonapi.org). Zero custom code needed for standard CRUD.

### Enable

```bash
ddev drush en jsonapi -y
```

### Endpoints

| Operation | Method | URL |
|-----------|--------|-----|
| List | GET | `/jsonapi/node/article` |
| Single | GET | `/jsonapi/node/article/{uuid}` |
| Create | POST | `/jsonapi/node/article` |
| Update | PATCH | `/jsonapi/node/article/{uuid}` |
| Delete | DELETE | `/jsonapi/node/article/{uuid}` |
| Related | GET | `/jsonapi/node/article/{uuid}/field_tags` |
| Relationship | GET | `/jsonapi/node/article/{uuid}/relationships/field_tags` |

### Filtering

```
# Exact match
/jsonapi/node/article?filter[status]=1

# Condition groups
/jsonapi/node/article?filter[title-filter][condition][path]=title&filter[title-filter][condition][operator]=CONTAINS&filter[title-filter][condition][value]=Drupal

# Shorthand
/jsonapi/node/article?filter[field_tags.name]=news

# Multiple conditions (AND)
/jsonapi/node/article?filter[status]=1&filter[promote]=1

# OR group
/jsonapi/node/article?filter[or-group][group][conjunction]=OR&filter[a][condition][path]=title&filter[a][condition][value]=Foo&filter[a][condition][memberOf]=or-group&filter[b][condition][path]=title&filter[b][condition][value]=Bar&filter[b][condition][memberOf]=or-group
```

### Includes (Relationships)

```
# Include referenced entities
/jsonapi/node/article?include=field_tags,uid

# Nested includes
/jsonapi/node/article?include=field_tags,field_image.field_media_image

# Sparse fieldsets (reduce payload)
/jsonapi/node/article?fields[node--article]=title,body,field_tags&fields[taxonomy_term--tags]=name
```

### Pagination & Sorting

```
# Pagination
/jsonapi/node/article?page[limit]=10&page[offset]=20

# Sorting
/jsonapi/node/article?sort=created           # ASC
/jsonapi/node/article?sort=-created          # DESC
/jsonapi/node/article?sort=sticky,-created   # Multi-sort
```

### Creating Resources

```json
POST /jsonapi/node/article
Content-Type: application/vnd.api+json
Authorization: Bearer <token>

{
  "data": {
    "type": "node--article",
    "attributes": {
      "title": "New Article",
      "body": {
        "value": "<p>Content</p>",
        "format": "basic_html"
      }
    },
    "relationships": {
      "field_tags": {
        "data": [
          { "type": "taxonomy_term--tags", "id": "uuid-here" }
        ]
      }
    }
  }
}
```

### File Uploads via JSON:API

```
POST /jsonapi/node/article/{uuid}/field_image
Content-Type: application/octet-stream
Content-Disposition: file; filename="photo.jpg"
Authorization: Bearer <token>

<binary file data>
```

### JSON:API Extras (Contrib)

```bash
ddev composer require drupal/jsonapi_extras
ddev drush en jsonapi_extras -y
```

Provides: resource type renaming, field aliasing, disabling resources, custom field enhancers.

## REST Resources

### Core REST Module

```bash
ddev drush en rest serialization -y
```

Configure at `/admin/config/services/rest` or via config YAML.

### Custom REST Resource Plugin

```php
declare(strict_types=1);

namespace Drupal\my_module\Plugin\rest\resource;

use Drupal\Core\StringTranslation\TranslatableMarkup;
use Drupal\rest\Attribute\RestResource;
use Drupal\rest\Plugin\ResourceBase;
use Drupal\rest\ResourceResponse;
use Drupal\Core\Entity\EntityTypeManagerInterface;
use Drupal\Core\Cache\CacheableMetadata;
use Drupal\Core\Session\AccountProxyInterface;
use Psr\Log\LoggerInterface;
use Symfony\Component\DependencyInjection\ContainerInterface;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

#[RestResource(
  id: 'my_module_stats',
  label: new TranslatableMarkup('Module Statistics'),
  uri_paths: [
    'canonical' => '/api/v1/stats/{entity_type}',
  ]
)]
final class StatsResource extends ResourceBase {

  public function __construct(
    array $configuration,
    string $plugin_id,
    mixed $plugin_definition,
    array $serializer_formats,
    LoggerInterface $logger,
    protected readonly EntityTypeManagerInterface $entityTypeManager,
    protected readonly AccountProxyInterface $currentUser,
  ) {
    parent::__construct($configuration, $plugin_id, $plugin_definition, $serializer_formats, $logger);
  }

  public static function create(
    ContainerInterface $container,
    array $configuration,
    $plugin_id,
    $plugin_definition,
  ): static {
    return new static(
      $configuration,
      $plugin_id,
      $plugin_definition,
      $container->getParameter('serializer.formats'),
      $container->get('logger.factory')->get('rest'),
      $container->get('entity_type.manager'),
      $container->get('current_user'),
    );
  }

  public function get(string $entity_type): ResourceResponse {
    if (!$this->currentUser->hasPermission('access content')) {
      throw new AccessDeniedHttpException();
    }

    $storage = $this->entityTypeManager->getStorage($entity_type);
    $count = $storage->getQuery()
      ->accessCheck(TRUE)
      ->count()
      ->execute();

    $data = [
      'entity_type' => $entity_type,
      'count' => (int) $count,
      'timestamp' => time(),
    ];

    $response = new ResourceResponse($data);

    // Add cache metadata
    $cache = new CacheableMetadata();
    $cache->addCacheTags([$entity_type . '_list']);
    $cache->addCacheContexts(['user.permissions']);
    $cache->setCacheMaxAge(300);
    $response->addCacheableDependency($cache);

    return $response;
  }

}
```

### REST Config (rest.resource.my_module_stats.yml)

```yaml
langcode: en
status: true
dependencies:
  module:
    - my_module
    - serialization
id: my_module_stats
plugin_id: my_module_stats
granularity: resource
configuration:
  methods:
    - GET
  formats:
    - json
  authentication:
    - cookie
    - oauth2
```

## Authentication

### Decision Tree

| Method | Use Case | Module |
|--------|----------|--------|
| Cookie | Same-domain SPA, traditional frontend | Core |
| OAuth 2.0 | Third-party apps, mobile, server-to-server | `simple_oauth` |
| Basic Auth | Development / testing only | Core (`basic_auth`) |
| API Key | Simple machine-to-machine | `key_auth` |

### OAuth 2.0 Setup (simple_oauth)

```bash
ddev composer require drupal/simple_oauth
ddev drush en simple_oauth -y

# Generate keys
ddev drush simple-oauth:generate-keys ../keys
```

```php
// Request token
// POST /oauth/token
// Content-Type: application/x-www-form-urlencoded
//
// grant_type=password&client_id=CLIENT_ID&client_secret=SECRET&username=user&password=pass
// grant_type=client_credentials&client_id=CLIENT_ID&client_secret=SECRET
// grant_type=authorization_code&code=AUTH_CODE&client_id=CLIENT_ID&redirect_uri=URI
```

### Using Tokens

```
GET /jsonapi/node/article
Authorization: Bearer eyJ0eXAiOiJKV1Qi...
```

## CORS Configuration

In `services.yml` (or `sites/default/services.yml`):

```yaml
parameters:
  cors.config:
    enabled: true
    allowedHeaders:
      - content-type
      - authorization
      - x-csrf-token
    allowedMethods:
      - GET
      - POST
      - PATCH
      - DELETE
      - OPTIONS
    allowedOrigins:
      # Specific origins (recommended for production)
      - 'https://frontend.example.com'
      # Development — allow DDEV sites
      - 'https://*.ddev.site'
    exposedHeaders: false
    maxAge: 3600
    supportsCredentials: true
```

**Never use `allowedOrigins: ['*']` with `supportsCredentials: true`** — browsers reject this.

## Response Caching

### Cache Tags on API Responses

JSON:API automatically adds cache tags. For custom REST resources:

```php
public function get(): ResourceResponse {
  $data = $this->buildResponseData();
  $response = new ResourceResponse($data);

  $cache = new CacheableMetadata();
  $cache->addCacheTags(['node_list', 'config:my_module.settings']);
  $cache->addCacheContexts(['user.permissions', 'url.query_args']);
  $cache->setCacheMaxAge(600); // 10 minutes
  $response->addCacheableDependency($cache);

  return $response;
}
```

### Conditional Requests

```php
use Symfony\Component\HttpFoundation\Response;

public function get(): ResourceResponse {
  $response = new ResourceResponse($data);
  $response->headers->set('ETag', md5(serialize($data)));
  $response->headers->set('Last-Modified', $lastModified->format('D, d M Y H:i:s') . ' GMT');
  $response->setPublic();
  $response->setMaxAge(300);

  return $response;
}
```

### Vary Headers

```yaml
# services.yml — vary by authorization for authenticated vs anonymous
parameters:
  http.response.debug_cacheability_headers: true  # dev only
```

## Decoupled Architecture

### Consumer Setup

```bash
ddev composer require drupal/consumers
ddev drush en consumers -y
```

Create consumers at `/admin/config/services/consumer` — each frontend app gets a consumer with scopes/roles.

### Next.js Integration Pattern

```typescript
// lib/drupal.ts — Next.js data fetching
const DRUPAL_URL = process.env.NEXT_PUBLIC_DRUPAL_URL;

export async function getArticles(page = 0) {
  const params = new URLSearchParams({
    'filter[status]': '1',
    'sort': '-created',
    'page[limit]': '10',
    'page[offset]': String(page * 10),
    'include': 'field_image,uid',
    'fields[node--article]': 'title,body,created,path,field_image,uid',
    'fields[user--user]': 'display_name',
  });

  const res = await fetch(`${DRUPAL_URL}/jsonapi/node/article?${params}`, {
    headers: { 'Accept': 'application/vnd.api+json' },
    next: { tags: ['articles'], revalidate: 60 },
  });

  if (!res.ok) throw new Error(`API error: ${res.status}`);
  return res.json();
}
```

### Preview Mode

```bash
ddev composer require drupal/next
ddev drush en next -y
```

Configure preview secret and revalidation URL in Drupal's Next.js module settings.

## Testing APIs

### Functional Test

```php
declare(strict_types=1);

namespace Drupal\Tests\my_module\Functional;

use Drupal\Tests\BrowserTestBase;
use Drupal\node\Entity\Node;
use GuzzleHttp\RequestOptions;

final class StatsResourceTest extends BrowserTestBase {

  protected static $modules = ['my_module', 'rest', 'serialization', 'node'];
  protected $defaultTheme = 'stark';

  public function testGetStats(): void {
    $this->drupalCreateContentType(['type' => 'article']);
    Node::create(['type' => 'article', 'title' => 'Test'])->save();

    $account = $this->drupalCreateUser(['access content', 'restful get my_module_stats']);
    $this->drupalLogin($account);

    $response = $this->drupalGet('/api/v1/stats/node', [
      'query' => ['_format' => 'json'],
    ]);

    $this->assertSession()->statusCodeEquals(200);
    $data = json_decode($response, TRUE);
    $this->assertEquals('node', $data['entity_type']);
    $this->assertEquals(1, $data['count']);
  }

}
```

### Kernel Test for Normalizer

```php
declare(strict_types=1);

namespace Drupal\Tests\my_module\Kernel;

use Drupal\KernelTests\KernelTestBase;
use Drupal\my_module\Normalizer\CustomNormalizer;

final class CustomNormalizerTest extends KernelTestBase {

  protected static $modules = ['my_module', 'serialization'];

  public function testNormalize(): void {
    $normalizer = $this->container->get('my_module.custom_normalizer');
    $this->assertInstanceOf(CustomNormalizer::class, $normalizer);

    $result = $normalizer->normalize($testObject);
    $this->assertArrayHasKey('expected_key', $result);
  }

}
```

## Common Mistakes

| Mistake | Impact | Fix |
|---------|--------|-----|
| Missing `accessCheck()` on entity queries in REST | Security: exposes unpublished content | Always `->accessCheck(TRUE)` |
| No cache metadata on `ResourceResponse` | Performance: responses never cached or cached incorrectly | Add `CacheableMetadata` with tags + contexts |
| N+1 queries loading related entities | Performance: slow API responses | Use JSON:API `?include=` or batch load in custom resources |
| `allowedOrigins: ['*']` in production | Security: any site can make authenticated requests | List specific allowed origins |
| Exposing sensitive fields (user email, roles) | Privacy/security: data leak | Use JSON:API Extras to disable fields or field-level access |
| Hardcoding entity UUIDs in frontend | Maintainability: breaks across environments | Use path aliases or machine names for lookups |
| Not handling pagination in frontend | UX: only first page of results shown | Always check `links.next` in JSON:API responses |
| Missing `Content-Type: application/vnd.api+json` | JSON:API rejects requests | Set proper content type on POST/PATCH |
| No rate limiting on API | Security: DoS risk | Use `flood` service or contrib module |
| Returning 500 instead of proper error codes | DX: hard to debug for consumers | Use `HttpException` subclasses (404, 403, 422) |
