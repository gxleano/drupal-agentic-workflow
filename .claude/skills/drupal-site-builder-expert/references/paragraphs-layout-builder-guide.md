# Paragraphs vs Layout Builder Guide

A practical comparison of Drupal's two main layout/content composition systems.

## Paragraphs

### What It Is

Paragraphs is a contrib module that treats content sections as separate entities (paragraph types) referenced from a host entity. Editors build pages by adding, reordering, and configuring paragraph items.

### Setup

```bash
ddev composer require drupal/paragraphs
ddev drush en paragraphs -y
```

### Creating Paragraph Types

Paragraph types are like mini content types. Common types:

| Type | Fields | Purpose |
|------|--------|---------|
| Text | Body (formatted) | Rich text section |
| Image + Text | Image (media ref), Body, Layout (select: left/right) | Image with text |
| Gallery | Images (media ref, multiple) | Image gallery grid |
| Accordion | Title (text), Body (formatted) | Expandable section |
| CTA | Heading, Body, Link, Background (color select) | Call to action banner |
| Card Grid | Cards (nested paragraph ref) | Grid of card items |
| Video | Video (media ref), Caption | Embedded video |
| Quote | Quote text, Attribution | Blockquote |

```bash
# Create paragraph type structure at:
# admin/structure/paragraphs_type/add
```

### Adding to Content Types

1. Add an **Entity Reference Revisions** field to your content type
2. Target type: Paragraph
3. Allow unlimited values
4. Select which paragraph types are available
5. Configure widget: Classic, Modal (with `paragraphs_features`), or Experimental

```bash
# Recommended companion modules
ddev composer require drupal/paragraphs_features
ddev drush en paragraphs_features -y
```

### Widget Options

| Widget | UX | Best for |
|--------|-----|---------|
| Classic | Inline forms, expand/collapse | Simple sites, few paragraph types |
| Modal (paragraphs_features) | Dialog picker with previews | Many paragraph types, better UX |
| Experimental | Improved drag-and-drop | Sites needing better reordering |

### Theming Paragraphs

Templates follow the pattern:

```
paragraph--TYPE.html.twig
paragraph--TYPE--VIEWMODE.html.twig
paragraph.html.twig
```

Example:

```twig
{# paragraph--image-text.html.twig #}
{% set layout = content.field_layout[0]['#markup']|default('left') %}

<section{{ attributes.addClass('image-text', 'image-text--' ~ layout) }}>
  <div class="image-text__media">
    {{ content.field_image }}
  </div>
  <div class="image-text__content">
    {{ content.field_body }}
  </div>
</section>
```

### Nesting Paragraphs

Paragraphs can reference other paragraphs for nested structures:

```
Landing Page (node)
  └── field_content (paragraphs)
      ├── Hero paragraph
      ├── Card Grid paragraph
      │   └── field_cards (paragraphs)
      │       ├── Card paragraph
      │       ├── Card paragraph
      │       └── Card paragraph
      └── CTA paragraph
```

**Warning:** Deep nesting (3+ levels) creates editorial complexity. Keep to 2 levels maximum.

### Paragraphs Pros

- **Content portability** — Paragraph data is structured, exportable, and API-friendly
- **Editorial flexibility** — Editors can compose any page layout from building blocks
- **Decoupled/API ready** — JSON:API/GraphQL can serialize paragraph data cleanly
- **Clear content model** — Each paragraph type has a defined schema
- **Reusable patterns** — Same paragraph types across content types
- **Revision support** — Full revision history for each paragraph

### Paragraphs Cons

- **Complex content model** — Many entity references, harder to query
- **Migration complexity** — Migrating paragraph content requires careful planning
- **Performance** — Loading many nested paragraph entities adds queries
- **No visual editing** — Editors work in forms, not WYSIWYG layout
- **Contrib dependency** — Not in core

---

## Layout Builder

### What It Is

Layout Builder is a core module (Drupal 8.5+) that provides drag-and-drop page layout editing. It works at the display mode level, adding sections with configurable layouts and blocks.

### Setup

```bash
ddev drush en layout_builder layout_discovery -y
```

Enable per content type:
1. Go to **Admin > Structure > Content types > [Type] > Manage display**
2. Check "Use Layout Builder"
3. Optionally check "Allow each content entity to have its layout customized"

### Sections and Layouts

Pages are composed of **sections**, each with a **layout**:

| Layout | Columns | Use case |
|--------|---------|----------|
| One column | 1 | Full-width content |
| Two column | 2 (equal, 33/67, 67/33) | Sidebar layouts |
| Three column | 3 (equal, 25/50/25) | Complex layouts |
| Custom | Any | Via custom layout plugins |

### Blocks in Layout Builder

Place these block types in sections:

- **Content fields** — Render individual fields from the entity
- **Inline blocks** — One-off content blocks (not reusable)
- **Reusable blocks** — Shared blocks across pages
- **Views blocks** — Embed Views displays
- **Custom block types** — Structured content blocks

### Default vs Per-Entity Layouts

| Feature | Default layout | Per-entity override |
|---------|---------------|-------------------|
| Scope | All entities of this type | Single entity |
| Editing | Admin > Manage display | Entity edit page |
| Consistency | Enforced across all entities | Unique per entity |
| Use case | Standard layout for articles | Custom landing pages |

### Layout Builder Restrictions

```bash
ddev composer require drupal/layout_builder_restrictions
ddev drush en layout_builder_restrictions -y
```

Control which blocks and layouts are available per content type — prevents editors from adding inappropriate blocks.

### Custom Layout Plugins

```php
// src/Plugin/Layout/TwoColumnCustom.php
#[Layout(
  id: 'two_column_custom',
  label: new TranslatableMarkup('Two Column Custom'),
  category: new TranslatableMarkup('Custom Layouts'),
  template: 'templates/layout/two-column-custom',
  regions: [
    'main' => ['label' => new TranslatableMarkup('Main')],
    'sidebar' => ['label' => new TranslatableMarkup('Sidebar')],
  ],
)]
final class TwoColumnCustom extends LayoutDefault {
}
```

### Layout Builder Pros

- **Visual editing** — Drag-and-drop interface, WYSIWYG-like
- **Core module** — No contrib dependency, well-maintained
- **Simple setup** — Enable and configure, no field creation
- **Block reuse** — Leverage existing blocks
- **Per-page overrides** — Allow unique layouts per entity

### Layout Builder Cons

- **Not API-friendly** — Layout data is stored as section/component arrays, hard to serialize for decoupled
- **Performance** — Complex layouts with many blocks can be slow
- **Less portable** — Layout is tied to the rendering system
- **Block discovery issues** — All available blocks shown unless restricted
- **Revision complexity** — Layout overrides create large revision data

---

## Comparison Table

| Criteria | Paragraphs | Layout Builder |
|----------|-----------|---------------|
| **Core/Contrib** | Contrib | Core |
| **Editorial UX** | Form-based (structured) | Visual drag-and-drop |
| **Content portability** | Excellent (entity-based) | Poor (rendering-based) |
| **API/Decoupled** | Excellent | Difficult |
| **Visual editing** | No (use form widgets) | Yes |
| **Content model clarity** | Excellent (typed paragraphs) | Moderate (blocks) |
| **Performance** | Moderate (many entities) | Moderate (many blocks) |
| **Migration** | Complex but structured | Very complex |
| **Setup effort** | Medium (types + fields) | Low (enable + configure) |
| **Nesting** | Yes (2 levels recommended) | Limited (sections only) |
| **Revisions** | Per-paragraph revisions | Per-layout revisions |
| **Reusability** | Paragraph types across nodes | Reusable blocks |

## Decision Guide

### Use Paragraphs When:

- Building a **decoupled/headless** site (JSON:API, GraphQL)
- Editors need **structured, repeatable** content patterns
- Content needs to be **migrated** or **exported** cleanly
- You need **deep nesting** (grids of cards, tabbed sections)
- The project has many **content types sharing** the same building blocks
- **Content is the product** (publishing, editorial-heavy sites)

### Use Layout Builder When:

- Editors want **visual, drag-and-drop** page building
- The site is **traditional Drupal** (not decoupled)
- You need **simple per-page layout overrides** (marketing pages)
- The project uses **existing blocks** that need flexible placement
- **Quick setup** is important and content model is simple
- Editors are non-technical and need **WYSIWYG layout**

### Use Both When:

- Paragraphs for **structured content** (article body sections)
- Layout Builder for **page-level layout** (placing blocks, fields, Views)
- Keep responsibilities clear: Paragraphs = content composition, Layout Builder = page layout

---

## Block Layout (Legacy)

The traditional Block Layout system (`/admin/structure/block`) places blocks in theme regions. It still works and is appropriate for:

- **Site-wide elements**: Header, footer, sidebar blocks
- **Simple sites**: Where per-page layout isn't needed
- **Theme regions**: Navigation, branding, copyright

For most new projects, prefer Layout Builder for per-page layouts and Block Layout for site-wide structural elements.
