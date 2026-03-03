# Single Directory Components (SDC) Guide

Comprehensive reference for building Single Directory Components in Drupal 10/11.

## What Are SDCs?

Single Directory Components (SDC) is a Drupal core feature (experimental in 10.1, stable in 10.3) that bundles a component's template, CSS, JS, and metadata in one directory. This enables a component-based architecture similar to modern frontend frameworks.

**Benefits:**
- Self-contained components (template + styles + JS + schema in one folder)
- Automatic library generation (no manual `*.libraries.yml` entries)
- Prop validation via JSON Schema
- Named slots for content injection
- Reusable across themes and modules

## Directory Structure

Components live in a `components/` directory inside your theme or module:

```
mytheme/
├── components/
│   ├── button/
│   │   ├── button.component.yml    # Schema (required)
│   │   ├── button.html.twig        # Template (required)
│   │   ├── button.css              # Styles (optional, auto-loaded)
│   │   └── button.js               # JavaScript (optional, auto-loaded)
│   ├── card/
│   │   ├── card.component.yml
│   │   ├── card.html.twig
│   │   └── card.css
│   └── hero/
│       ├── hero.component.yml
│       ├── hero.html.twig
│       ├── hero.css
│       └── hero.js
```

**Naming rules:**
- Directory name = component machine name
- Files must use the same name as the directory
- Template: `{name}.html.twig`
- Schema: `{name}.component.yml`

## Component Schema (`*.component.yml`)

The schema file defines metadata, props, and slots using JSON Schema:

```yaml
name: Button
status: stable
description: A reusable button component.

props:
  type: object
  required:
    - label
  properties:
    label:
      type: string
      title: Button label
      description: The text displayed on the button.
    url:
      type: string
      title: Button URL
      description: Optional link URL. Renders as <a> if provided, <button> otherwise.
    variant:
      type: string
      title: Button variant
      enum:
        - primary
        - secondary
        - outline
      default: primary
    size:
      type: string
      title: Button size
      enum:
        - small
        - medium
        - large
      default: medium
    disabled:
      type: boolean
      title: Disabled state
      default: false

slots:
  icon:
    title: Icon slot
    description: Optional icon displayed before the label.
```

### Status Values

| Status | Meaning |
|--------|---------|
| `stable` | Production-ready, API won't change |
| `experimental` | May change, use with caution |
| `deprecated` | Will be removed, migrate away |
| `obsolete` | Do not use |

### Prop Types

| Type | JSON Schema | Example |
|------|-------------|---------|
| String | `type: string` | Labels, URLs, CSS classes |
| Integer | `type: integer` | Counts, indices |
| Number | `type: number` | Decimals, percentages |
| Boolean | `type: boolean` | Flags, toggles |
| Array | `type: array` | Lists of items |
| Object | `type: object` | Nested structured data |
| Enum | `type: string` + `enum: [...]` | Predefined options |

### Required Props

```yaml
props:
  type: object
  required:
    - title
    - url
  properties:
    title:
      type: string
    url:
      type: string
    description:
      type: string  # Optional — not in required list
```

### Default Values

```yaml
props:
  type: object
  properties:
    variant:
      type: string
      default: primary
    columns:
      type: integer
      default: 3
```

## Slots

Slots allow passing arbitrary Twig content into component regions.

### Default Slot

```yaml
# card.component.yml
slots:
  content:
    title: Card content
```

```twig
{# card.html.twig #}
<div class="card">
  <div class="card__content">
    {% block content %}
      {# Default content if slot is empty #}
      <p>No content provided.</p>
    {% endblock %}
  </div>
</div>
```

### Multiple Named Slots

```yaml
# layout.component.yml
slots:
  header:
    title: Header content
  main:
    title: Main content
  sidebar:
    title: Sidebar content
  footer:
    title: Footer content
```

```twig
{# layout.html.twig #}
<div class="layout">
  <header class="layout__header">{% block header %}{% endblock %}</header>
  <main class="layout__main">{% block main %}{% endblock %}</main>
  <aside class="layout__sidebar">{% block sidebar %}{% endblock %}</aside>
  <footer class="layout__footer">{% block footer %}{% endblock %}</footer>
</div>
```

## Using SDCs in Twig

### Basic Include with Props

```twig
{% include 'mytheme:button' with {
  label: 'Click me',
  url: '/contact',
  variant: 'primary',
} %}
```

### With Slots

```twig
{% embed 'mytheme:card' with { title: 'My Card' } %}
  {% block content %}
    <p>This is the card content.</p>
    <a href="/read-more">Read more</a>
  {% endblock %}
{% endembed %}
```

### In Render Arrays (PHP)

```php
$build['button'] = [
  '#type' => 'component',
  '#component' => 'mytheme:button',
  '#props' => [
    'label' => $this->t('Submit'),
    'variant' => 'primary',
  ],
  '#slots' => [
    'icon' => [
      '#markup' => '<svg>...</svg>',
    ],
  ],
];
```

### Component Namespacing

Components are namespaced by their provider (theme or module):

```twig
{# From a theme called 'mytheme' #}
{% include 'mytheme:button' %}

{# From a module called 'my_module' #}
{% include 'my_module:alert' %}
```

## CSS/JS Scoping

### Automatic Library Generation

SDC automatically creates a library for each component. CSS and JS files in the component directory are auto-loaded when the component is rendered.

```
components/card/
├── card.component.yml
├── card.html.twig
├── card.css          # Auto-loaded as CSS
└── card.js           # Auto-loaded as JS
```

No need to define this in `*.libraries.yml` — it's handled automatically.

### Library Overrides

Override auto-generated library settings in the schema:

```yaml
# card.component.yml
name: Card
libraryOverrides:
  css:
    component:
      card.css:
        weight: -1
  dependencies:
    - core/drupal
    - core/once
    - mytheme/global
```

### CSS Scoping Best Practices

Use BEM or component-prefixed class names to avoid style collisions:

```css
/* card.css */
.card {
  border: 1px solid #ddd;
  border-radius: 4px;
  overflow: hidden;
}

.card__title {
  font-size: 1.25rem;
  font-weight: 700;
  padding: 1rem;
}

.card__content {
  padding: 0 1rem 1rem;
}

.card--featured {
  border-color: #0057b7;
}
```

## Nesting Components

Components can include other components:

```twig
{# hero.html.twig #}
<section class="hero">
  <div class="hero__content">
    <h1 class="hero__title">{{ title }}</h1>
    <p class="hero__description">{{ description }}</p>
    {% if cta_label and cta_url %}
      {% include 'mytheme:button' with {
        label: cta_label,
        url: cta_url,
        variant: 'primary',
        size: 'large',
      } %}
    {% endif %}
  </div>
</section>
```

## Example Components

### Alert

```yaml
# components/alert/alert.component.yml
name: Alert
status: stable
props:
  type: object
  required:
    - message
  properties:
    message:
      type: string
      title: Alert message
    type:
      type: string
      title: Alert type
      enum: [info, success, warning, error]
      default: info
    dismissible:
      type: boolean
      default: false
```

```twig
{# components/alert/alert.html.twig #}
<div class="alert alert--{{ type }}" role="alert" {% if dismissible %}data-alert-dismissible{% endif %}>
  <p class="alert__message">{{ message }}</p>
  {% if dismissible %}
    <button class="alert__close" type="button" aria-label="{{ 'Close'|t }}">×</button>
  {% endif %}
</div>
```

```css
/* components/alert/alert.css */
.alert {
  padding: 1rem;
  border-radius: 4px;
  margin-bottom: 1rem;
}
.alert--info { background: #e3f2fd; border-left: 4px solid #2196f3; }
.alert--success { background: #e8f5e9; border-left: 4px solid #4caf50; }
.alert--warning { background: #fff3e0; border-left: 4px solid #ff9800; }
.alert--error { background: #ffebee; border-left: 4px solid #f44336; }
.alert__close { float: right; border: none; background: none; cursor: pointer; font-size: 1.25rem; }
```

### Tabs

```yaml
# components/tabs/tabs.component.yml
name: Tabs
status: stable
props:
  type: object
  required:
    - items
  properties:
    items:
      type: array
      title: Tab items
      items:
        type: object
        properties:
          label:
            type: string
          id:
            type: string
          content:
            type: string
```

```twig
{# components/tabs/tabs.html.twig #}
<div class="tabs" data-tabs>
  <nav class="tabs__nav" role="tablist">
    {% for item in items %}
      <button class="tabs__tab" role="tab" aria-controls="tab-{{ item.id }}" {% if loop.first %}aria-selected="true"{% endif %}>
        {{ item.label }}
      </button>
    {% endfor %}
  </nav>
  {% for item in items %}
    <div class="tabs__panel" id="tab-{{ item.id }}" role="tabpanel" {% if not loop.first %}hidden{% endif %}>
      {{ item.content }}
    </div>
  {% endfor %}
</div>
```

## Migration from Traditional Templates

### Before (Traditional)

```yaml
# mytheme.libraries.yml
card:
  css:
    component:
      css/components/card.css: {}
  js:
    js/components/card.js: {}
  dependencies:
    - core/drupal
```

```twig
{# templates/field/field--card.html.twig #}
{{ attach_library('mytheme/card') }}
<div class="card">{{ content }}</div>
```

### After (SDC)

```
components/card/
├── card.component.yml
├── card.html.twig
├── card.css
└── card.js
```

No `*.libraries.yml` entry needed. Library is auto-generated.

## Drupal Version Notes

| Feature | 10.1 | 10.2 | 10.3+ |
|---------|------|------|-------|
| SDC core module | Experimental | Experimental | Stable |
| `#type => 'component'` | No | No | Yes |
| Component validation | Basic | Improved | Full JSON Schema |
| Library overrides | No | Partial | Yes |
| Nested components | Yes | Yes | Yes |

For Drupal 10.1-10.2, enable the experimental SDC module:
```bash
ddev drush en sdc -y
```

For Drupal 10.3+, SDC is part of the Component rendering system in core.
