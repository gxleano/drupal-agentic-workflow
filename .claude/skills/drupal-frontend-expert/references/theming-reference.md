# Drupal Theming Reference

Complete reference for Drupal 10/11 theme development: structure, Twig, preprocessing, libraries, breakpoints, and best practices.

## Theme Directory Structure

```
mytheme/
├── mytheme.info.yml           # Theme metadata (required)
├── mytheme.libraries.yml      # CSS/JS library definitions
├── mytheme.theme               # Preprocess functions
├── mytheme.breakpoints.yml    # Responsive breakpoints
├── logo.svg                    # Theme logo
├── screenshot.png              # Theme screenshot for admin
├── css/
│   ├── base.css               # Reset, typography, global styles
│   ├── layout.css             # Grid, page layout
│   └── components/            # Component styles (BEM)
│       ├── header.css
│       ├── card.css
│       └── footer.css
├── js/
│   ├── behaviors.js           # Drupal.behaviors entry point
│   └── components/            # Component scripts
│       └── accordion.js
├── images/                    # Theme images (icons, backgrounds)
├── templates/                 # Twig template overrides
│   ├── layout/
│   │   ├── html.html.twig
│   │   └── page.html.twig
│   ├── content/
│   │   ├── node.html.twig
│   │   └── node--article--teaser.html.twig
│   ├── block/
│   │   └── block.html.twig
│   ├── field/
│   │   └── field.html.twig
│   ├── navigation/
│   │   └── menu.html.twig
│   └── misc/
│       └── status-messages.html.twig
└── components/                # SDC components (Drupal 10.3+)
    ├── button/
    └── card/
```

## Theme Info File (`*.info.yml`)

```yaml
name: My Theme
type: theme
description: 'Custom theme for the project.'
core_version_requirement: ^10 || ^11
php: 8.3
base theme: false

# Regions available for block placement
regions:
  header: Header
  primary_menu: 'Primary menu'
  secondary_menu: 'Secondary menu'
  hero: Hero
  breadcrumb: Breadcrumb
  highlighted: Highlighted
  help: Help
  content: Content
  sidebar_first: 'Sidebar first'
  sidebar_second: 'Sidebar second'
  footer: Footer

# Global libraries (loaded on every page)
libraries:
  - mytheme/global

# Override libraries from other themes/modules
libraries-override:
  claro/global-styling: false
  core/normalize: mytheme/normalize

# Extend libraries from other themes/modules
libraries-extend:
  core/drupal.dialog:
    - mytheme/dialog-overrides
```

### Base Theme Options

```yaml
# No base theme — start from scratch
base theme: false

# Extend a core theme
base theme: olivero

# Extend a contrib theme
base theme: bootstrap5
```

## Twig Syntax

### Variables

```twig
{# Print a variable (auto-escaped) #}
{{ variable }}

{# Print with default #}
{{ variable|default('N/A') }}

{# Access object properties #}
{{ node.label }}
{{ node.id }}
{{ node.bundle }}

{# Access array keys #}
{{ content.field_name }}
{{ attributes.class }}

{# Check if variable is set and not empty #}
{% if variable is not empty %}
  {{ variable }}
{% endif %}
```

### Tags

```twig
{# Conditionals #}
{% if node.bundle == 'article' %}
  <span class="badge">Article</span>
{% elseif node.bundle == 'page' %}
  <span class="badge">Page</span>
{% else %}
  <span class="badge">Other</span>
{% endif %}

{# Loops #}
{% for item in items %}
  <li class="{{ cycle(['odd', 'even'], loop.index0) }}">
    {{ item.content }}
  </li>
{% endfor %}

{# Set variables #}
{% set classes = ['node', 'node--' ~ node.bundle, 'node--' ~ view_mode] %}

{# Blocks (template inheritance) #}
{% block content %}
  {{ parent() }}
  <div>Additional content</div>
{% endblock %}
```

### Drupal-Specific Filters

| Filter | Purpose | Example |
|--------|---------|---------|
| `\|t` | Translate string | `{{ 'Hello'|t }}` |
| `\|escape` | HTML escape (default, usually unnecessary) | `{{ var|escape }}` |
| `\|raw` | Skip auto-escaping (**dangerous with user data**) | `{{ trusted_markup|raw }}` |
| `\|without()` | Render array without specific children | `{{ content|without('field_image') }}` |
| `\|clean_class` | Sanitize for CSS class name | `{{ type|clean_class }}` |
| `\|clean_id` | Sanitize for HTML ID | `{{ id|clean_id }}` |
| `\|safe_join()` | Join array with separator (safe) | `{{ items|safe_join(', ') }}` |
| `\|render` | Force render a render array | `{{ content.field_name|render }}` |
| `\|striptags` | Remove HTML tags | `{{ body|striptags }}` |
| `\|format_date()` | Format date | `{{ node.created.value|format_date('medium') }}` |

### Drupal-Specific Functions

```twig
{# Attach a library #}
{{ attach_library('mytheme/my-component') }}

{# Translation #}
{{ 'Submit'|t }}
{% trans %}Hello {{ name }}{% endtrans %}
{% trans %}
  Singular item
{% plural count %}
  {{ count }} items
{% endtrans %}

{# URL generation #}
{{ path('entity.node.canonical', {'node': node.id}) }}
{{ url('entity.node.canonical', {'node': node.id}) }}

{# Link generation #}
{{ link('Click here', url('entity.node.canonical', {'node': node.id})) }}

{# File URL #}
{{ file_url(node.field_image.entity.fileuri) }}

{# Active theme path #}
{{ active_theme_path() }}

{# Render a block #}
{{ drupal_block('system_branding_block') }}
```

### Attributes Object

Drupal's `Attribute` object provides chainable methods:

```twig
{# Add classes #}
<div{{ attributes.addClass('my-class', 'another-class') }}>

{# Remove a class #}
<div{{ attributes.removeClass('unwanted') }}>

{# Set an attribute #}
<div{{ attributes.setAttribute('data-id', node.id) }}>

{# Remove an attribute #}
<div{{ attributes.removeAttribute('role') }}>

{# Check if class exists #}
{% if attributes.hasClass('active') %}

{# Print all attributes #}
<div{{ attributes }}>

{# Create new attributes #}
{% set custom_attrs = create_attribute() %}
{% set custom_attrs = custom_attrs.addClass('custom').setAttribute('role', 'banner') %}
<div{{ custom_attrs }}>
```

## Preprocessing Functions

### Pattern

```php
// mytheme.theme

/**
 * Implements hook_preprocess_HOOK() for node templates.
 */
function mytheme_preprocess_node(array &$variables): void {
  $node = $variables['node'];

  // Add custom variable
  $variables['is_featured'] = $node->hasField('field_featured')
    && $node->get('field_featured')->value;

  // Add CSS class conditionally
  if ($variables['is_featured']) {
    $variables['attributes']['class'][] = 'node--featured';
  }

  // Add reading time estimate
  if ($node->hasField('body') && !$node->get('body')->isEmpty()) {
    $word_count = str_word_count(strip_tags($node->get('body')->value));
    $variables['reading_time'] = (int) ceil($word_count / 200);
  }
}
```

### Common Preprocess Hooks

| Hook | Template | Variables |
|------|----------|-----------|
| `preprocess_html` | `html.html.twig` | `page`, `head_title`, `html_attributes` |
| `preprocess_page` | `page.html.twig` | `page` (regions), `node` (if node page) |
| `preprocess_node` | `node.html.twig` | `node`, `content`, `label`, `view_mode` |
| `preprocess_block` | `block.html.twig` | `content`, `plugin_id`, `label` |
| `preprocess_field` | `field.html.twig` | `items`, `field_name`, `field_type` |
| `preprocess_region` | `region.html.twig` | `content`, `region` |
| `preprocess_views_view` | `views-view.html.twig` | `rows`, `header`, `footer`, `pager` |

### When to Preprocess vs Use Twig Logic

**Use preprocess for:**
- Complex PHP logic (date calculations, entity loading)
- Data that requires service injection
- Computed values from multiple fields

**Use Twig for:**
- Simple conditionals (`{% if variable %}`)
- CSS class composition
- Template structure and layout
- String formatting

## Template Suggestions

### Naming Convention

Templates are discovered in this order (most specific first):

**Node templates:**
```
node--{type}--{viewmode}.html.twig
node--{type}.html.twig
node--{nid}.html.twig
node.html.twig
```

**Page templates:**
```
page--node--{nid}.html.twig
page--node--{type}.html.twig
page--node.html.twig
page--front.html.twig
page.html.twig
```

**Block templates:**
```
block--{module}--{delta}.html.twig
block--{module}.html.twig
block--{region}.html.twig
block.html.twig
```

**Field templates:**
```
field--{name}--{type}--{bundle}.html.twig
field--{name}--{bundle}.html.twig
field--{name}.html.twig
field--{type}.html.twig
field.html.twig
```

### Custom Template Suggestions

```php
/**
 * Implements hook_theme_suggestions_HOOK_alter() for node.
 */
function mytheme_theme_suggestions_node_alter(array &$suggestions, array $variables): void {
  $node = $variables['elements']['#node'];
  $view_mode = $variables['elements']['#view_mode'];

  // Add suggestion based on a field value
  if ($node->hasField('field_layout') && !$node->get('field_layout')->isEmpty()) {
    $layout = $node->get('field_layout')->value;
    $suggestions[] = 'node__' . $node->bundle() . '__' . $layout;
  }
}
```

### Debugging Template Suggestions

Enable Twig debug in `settings.local.php`:

```php
$settings['twig_debug'] = TRUE;
$settings['cache']['bins']['render'] = 'cache.backend.null';
$settings['cache']['bins']['page'] = 'cache.backend.null';
$settings['cache']['bins']['dynamic_page_cache'] = 'cache.backend.null';
```

This outputs HTML comments showing:
```html
<!-- THEME DEBUG -->
<!-- THEME HOOK: 'node' -->
<!-- FILE NAME SUGGESTIONS:
   * node--article--full.html.twig
   * node--article.html.twig
   * node--1.html.twig
   x node.html.twig
-->
<!-- BEGIN OUTPUT from 'themes/custom/mytheme/templates/content/node.html.twig' -->
```

## CSS/JS Library Definitions

### Full Library Example

```yaml
# mytheme.libraries.yml

# Global library (loaded on every page via info.yml)
global:
  css:
    base:
      css/base.css: { weight: -10 }
    layout:
      css/layout.css: {}
    component:
      css/components/header.css: {}
      css/components/footer.css: {}
  js:
    js/behaviors.js: {}
  dependencies:
    - core/drupal
    - core/once

# Component-specific library
accordion:
  css:
    component:
      css/components/accordion.css: {}
  js:
    js/components/accordion.js: {}
  dependencies:
    - core/drupal
    - core/once
    - mytheme/global

# External library (CDN)
fontawesome:
  css:
    theme:
      https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css:
        type: external
        minified: true
  js:
    https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/js/all.min.js:
      type: external
      minified: true
      attributes:
        defer: true
```

### CSS Categories and Weight

| Category | Weight | Purpose |
|----------|--------|---------|
| `base` | -200 | Reset, normalize, typography |
| `layout` | -100 | Grid, page structure |
| `component` | 0 | UI components (default) |
| `state` | 100 | Active, disabled, hover states |
| `theme` | 200 | Colors, fonts, decoration |

### JS Options

```yaml
my-script:
  js:
    js/my-script.js:
      weight: -10                # Load order (lower = earlier)
      minified: false            # Is it pre-minified?
      preprocess: true           # Allow aggregation
      attributes:
        defer: true              # Defer loading
        async: true              # Async loading
    js/footer-script.js:
      header: false              # Load in footer (default: header)
```

### Conditional Loading

```yaml
# Only load for specific pages via #attached in PHP
$build['#attached']['library'][] = 'mytheme/accordion';

# Or in Twig
{{ attach_library('mytheme/accordion') }}
```

## Responsive Breakpoints

### Configuration

```yaml
# mytheme.breakpoints.yml
mytheme.mobile:
  label: Mobile
  mediaQuery: '(min-width: 0px)'
  weight: 0
  multipliers:
    - 1x

mytheme.tablet:
  label: Tablet
  mediaQuery: '(min-width: 768px)'
  weight: 1
  multipliers:
    - 1x
    - 1.5x

mytheme.desktop:
  label: Desktop
  mediaQuery: '(min-width: 1024px)'
  weight: 2
  multipliers:
    - 1x
    - 1.5x
    - 2x

mytheme.wide:
  label: Wide
  mediaQuery: '(min-width: 1440px)'
  weight: 3
  multipliers:
    - 1x
    - 2x
```

### Responsive Images

1. Define breakpoints in `*.breakpoints.yml`
2. Create responsive image styles at `/admin/config/media/responsive-image-style`
3. Map image styles to breakpoints
4. Use responsive image formatter on image fields

## Development Workflow

### Enable Debug Mode

In `sites/default/settings.local.php`:

```php
// Twig debug (template suggestions in HTML comments)
$settings['twig_debug'] = TRUE;

// Disable render cache
$settings['cache']['bins']['render'] = 'cache.backend.null';
$settings['cache']['bins']['page'] = 'cache.backend.null';
$settings['cache']['bins']['dynamic_page_cache'] = 'cache.backend.null';

// Don't aggregate CSS/JS
$config['system.performance']['css']['preprocess'] = FALSE;
$config['system.performance']['js']['preprocess'] = FALSE;
```

### Clear Cache After Theme Changes

```bash
# After adding new templates or changing info.yml
ddev drush cr

# After changing CSS/JS (if aggregation is on)
ddev drush cr
```

### Finding Templates to Override

1. Enable Twig debug
2. Inspect the page HTML — look for `<!-- THEME DEBUG -->` comments
3. Copy the suggested template file from core/contrib to your theme's `templates/`
4. Rename using the desired suggestion pattern
5. Clear cache

## Best Practices

### BEM CSS

```css
/* Block */
.card { }

/* Element */
.card__title { }
.card__image { }
.card__content { }

/* Modifier */
.card--featured { }
.card--horizontal { }
```

### Component-Based

- One CSS file per component
- One JS behavior per component
- Template + CSS + JS in matching directories
- Use SDC for Drupal 10.3+ projects

### Accessibility

```twig
{# Semantic HTML #}
<nav aria-label="{{ 'Main navigation'|t }}">
<main role="main">
<aside role="complementary">

{# Skip link #}
<a href="#main-content" class="visually-hidden focusable skip-link">
  {{ 'Skip to main content'|t }}
</a>

{# ARIA for dynamic content #}
<button aria-expanded="false" aria-controls="panel-1">
<div id="panel-1" role="region" aria-labelledby="heading-1" hidden>

{# Screen reader text #}
<span class="visually-hidden">{{ 'Opens in a new window'|t }}</span>

{# Image alt text #}
<img src="{{ image_url }}" alt="{{ image_alt }}">
{# Empty alt for decorative images #}
<img src="{{ bg_url }}" alt="">
```

### Performance

- Use library dependencies to avoid duplicate loading
- Enable CSS/JS aggregation in production
- Lazy-load images below the fold
- Use `preload` for critical CSS
- Minimize render-blocking JS (use `defer` attribute)
- Leverage BigPipe (enabled by default in Drupal 10+)

### Security in Templates

```twig
{# SAFE — auto-escaped by default #}
{{ variable }}

{# NEVER use |raw with user-controlled data #}
{# {{ user_input|raw }}  ← XSS vulnerability! #}

{# Use |t for translated strings with placeholders #}
{{ 'Welcome, @name'|t({'@name': user_name}) }}

{# Use Drupal.checkPlain() in JS for user data #}
```
