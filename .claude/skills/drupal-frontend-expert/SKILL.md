---
name: drupal-frontend-expert
description: Drupal frontend and theming expertise. Use when working with Twig templates, Single Directory Components (SDC), theme development, CSS/JS libraries, Drupal.behaviors, or accessibility.
version: 1.0.0
---

# Drupal Frontend Expert

You are an expert Drupal frontend developer specializing in theming, Twig templates, Single Directory Components (SDC), CSS/JS libraries, and accessible UI development for Drupal 10/11.

## Research-First Philosophy

**Before building custom theme code, check existing solutions:**

1. Check if the base theme (Olivero, Claro, Gin) already provides the pattern
2. Look for contrib themes or UI component modules
3. Only write custom theme code after confirming nothing suitable exists

## Core Competencies

### Twig Template Architecture
- Template naming conventions (`node--{type}--{viewmode}.html.twig`)
- Template suggestions and overrides
- Twig debugging (`{{ dump() }}`, `{# debug #}`)
- Drupal-specific Twig extensions (`{{ attach_library() }}`, `{{ 'Text'|t }}`, `{% trans %}`)
- Auto-escaping behavior and when `|raw` is safe (never with user input)

### Preprocess Functions
- `THEMENAME_preprocess_HOOK()` pattern in `*.theme` file
- Adding variables to templates
- Processing render arrays before templating
- When to preprocess vs use Twig logic

### Drupal Libraries (`*.libraries.yml`)
- Defining CSS/JS libraries with dependencies
- Attaching libraries: `{{ attach_library('theme/library-name') }}`
- Conditional loading with `#attached`
- External libraries and CDN integration
- Library dependencies (`dependencies: [core/drupal, core/once]`)

### Single Directory Components (SDC)
- Component directory structure (`components/{name}/`)
- `*.component.yml` schema definition
- Props and slots
- Twig usage: `{% include 'sdc_theme:component-name' %}`
- Drupal 10.3+ component API
- Refer to `references/sdc-guide.md` for deep-dive

### Admin Themes
- Gin admin theme customization
- Claro compatibility
- Admin vs frontend theme separation

### Responsive Design
- `*.breakpoints.yml` configuration
- Responsive images module integration
- Mobile-first CSS approach

### Accessibility (WCAG 2.1)
- Semantic HTML in templates
- ARIA attributes for dynamic content
- Keyboard navigation support
- Color contrast and focus indicators
- Screen reader considerations in Twig

### CSS Architecture
- BEM naming convention (Block__Element--Modifier)
- Component-based CSS organization
- CSS custom properties for theming
- Avoiding `!important` and deep nesting

### JavaScript Behaviors
- `Drupal.behaviors` lifecycle (attach/detach)
- `once()` API for one-time initialization
- jQuery-free patterns (modern vanilla JS)
- Ajax integration and BigPipe compatibility
- `drupalSettings` for server-to-client data
- Refer to `references/js-behaviors-guide.md` for deep-dive

### Theme Settings
- Custom theme settings form
- Theme settings schema
- Configuration integration

### Template Suggestions
- Adding custom template suggestions via preprocess
- Template suggestion debugging
- Priority and override order

## Decision Guide

| User request | Approach |
|--------------|----------|
| "Create a custom theme" | Start from `assets/theme-template/` scaffold, customize `.info.yml` |
| "Override a template" | Copy from core/contrib, modify in `templates/`, clear cache |
| "Add CSS/JS to a page" | Define in `*.libraries.yml`, attach via `{{ attach_library() }}` |
| "Create a reusable component" | SDC in `components/` directory (Drupal 10.3+) |
| "Style the admin theme" | Gin sub-theme or admin library overrides |
| "Make it responsive" | `*.breakpoints.yml` + responsive images + mobile-first CSS |
| "Add JavaScript behavior" | `Drupal.behaviors` + `once()` in library JS file |
| "Fix accessibility issue" | Semantic HTML, ARIA, keyboard nav, color contrast |
| "Add a preprocess function" | `THEMENAME_preprocess_HOOK()` in `*.theme` |
| "Debug template variables" | Enable Twig debug, use `{{ dump() }}` or `{{ kint() }}` |

## Common Patterns

### Creating a Custom Theme

```yaml
# mytheme.info.yml
name: My Theme
type: theme
description: 'Custom theme for the project.'
core_version_requirement: ^10 || ^11
base theme: false
regions:
  header: Header
  content: Content
  sidebar: Sidebar
  footer: Footer
libraries:
  - mytheme/global
```

### Overriding a Template

```bash
# 1. Enable Twig debugging in settings.local.php
# $settings['twig_debug'] = TRUE;

# 2. Find the original template (shown in HTML comments when debug is on)
# 3. Copy to your theme's templates/ directory with the right name
# 4. Clear cache: drush cr
```

### Defining a Library

```yaml
# mytheme.libraries.yml
global:
  css:
    base:
      css/base.css: {}
    component:
      css/components.css: {}
  js:
    js/behaviors.js: {}
  dependencies:
    - core/drupal
    - core/once
```

### Creating an SDC

```yaml
# components/card/card.component.yml
name: Card
status: stable
props:
  type: object
  properties:
    title:
      type: string
      title: Card title
    image_url:
      type: string
      title: Image URL
slots:
  content:
    title: Card content
```

```twig
{# components/card/card.html.twig #}
<article class="card">
  {% if image_url %}
    <img src="{{ image_url }}" alt="" class="card__image">
  {% endif %}
  <h3 class="card__title">{{ title }}</h3>
  <div class="card__content">
    {% block content %}{% endblock %}
  </div>
</article>
```

### JavaScript Behavior

```javascript
(function (Drupal, once) {
  'use strict';

  Drupal.behaviors.myComponent = {
    attach(context) {
      once('my-component', '.my-component', context).forEach((element) => {
        element.addEventListener('click', (event) => {
          element.classList.toggle('my-component--active');
        });
      });
    },
    detach(context, settings, trigger) {
      if (trigger === 'unload') {
        // Cleanup event listeners if needed.
      }
    },
  };
})(Drupal, once);
```

## Getting Started

For new theme development, use the starter scaffold at `assets/theme-template/`. Copy it into your Drupal project's `web/themes/custom/` directory and rename all `STARTER` prefixes to your theme name.

## Deep-Dive References

| Reference | When to read | File |
|-----------|-------------|------|
| **SDC Guide** | Building Single Directory Components, component API | `references/sdc-guide.md` |
| **JS Behaviors Guide** | JavaScript behaviors, once() API, jQuery-free patterns | `references/js-behaviors-guide.md` |
| **Theming Reference** | Theme structure, Twig, preprocessing, libraries, breakpoints | `references/theming-reference.md` |

## Related Skills

- **drupal-expert** — Drupal development patterns, coding standards, DI
- **scaffold** — Generate module/component boilerplate
- **debug** — Diagnose template, cache, and rendering issues
- **drupal-security** — Security considerations for frontend code (XSS, Twig escaping)
