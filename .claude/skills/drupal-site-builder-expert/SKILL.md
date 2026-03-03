---
name: drupal-site-builder-expert
description: Drupal site building expertise. Use when working with content types, Views, Layout Builder, Paragraphs, taxonomy, menus, configuration management, or content workflows.
version: 1.0.0
---

# Drupal Site Builder Expert

You are an expert Drupal site builder with deep knowledge of content architecture, Views, layout systems, and configuration management for Drupal 10/11.

## Research-First Philosophy

**Before building custom solutions, always check for existing options:**

1. **Contrib modules** — Search drupal.org for modules that solve the problem
2. **Recipes** (Drupal 10.3+) — Check if a Drupal Recipe handles the use case
3. **Core features** — Drupal core has grown significantly; verify it's not already built in
4. **Only build custom** after confirming no suitable solution exists

## Content Architecture

### Content Types

Content types define the structure of your content. Plan them carefully — changing later is harder than getting it right.

**Principles:**
- One content type per distinct editorial concept (Article, Event, Product — not "Page with type field")
- Use fields for structured data, body field for free-form content
- Keep content types focused; use entity references for relationships
- Plan display modes (teaser, full, card) upfront

```bash
# Create content type via Drush
ddev drush generate content-type

# List existing content types
ddev drush entity:list --type=node_type
```

### Field Types

| Field | When to use |
|-------|------------|
| Text (plain) | Titles, short labels, machine values |
| Text (formatted) | Body text, descriptions with HTML |
| Entity reference | Link to other entities (nodes, terms, users, media) |
| Media reference | Images, videos, documents (use Media, not File/Image directly) |
| Paragraphs | Flexible content blocks (requires `paragraphs` module) |
| Link | URLs (internal or external) |
| Date/Date range | Events, scheduling |
| Boolean | Toggle/checkbox |
| List (text/integer) | Select lists, radio buttons |
| Email/Telephone | Contact information |

### Display Modes

- **View modes**: Control how content appears (full, teaser, card, search_result)
- **Form modes**: Control form layout for editors (default, simplified)

```bash
# Create custom view mode
ddev drush generate entity-view-mode

# List view modes
ddev drush entity:list --type=entity_view_mode
```

## Views

Views is the query builder for Drupal — use it for any list, feed, or filtered display.

### Display Types

| Display | Purpose |
|---------|---------|
| Page | Standalone page with URL |
| Block | Embeddable block for regions/Layout Builder |
| Attachment | Attached before/after another display |
| Feed | RSS/Atom feed |
| REST Export | JSON/XML API endpoint |
| Entity Reference | Powers autocomplete/select for reference fields |

### Quick Patterns

**Recent articles page:**
- Content type: Article
- Sort: Created date (desc)
- Pager: Full pager, 10 items
- Filter: Published (yes), Content type (Article)
- Format: Unformatted list of teasers

**Related content block:**
- Contextual filter: Content type (from URL node)
- Exclude current node
- Sort: Random
- Limit: 3 items

**Taxonomy term listing:**
- Relationship: Taxonomy term (via field_tags)
- Contextual filter: Term ID (from URL)
- Sort: Created date (desc)

Refer to `references/views-guide.md` for detailed Views configuration.

## Layout Systems

### When to Use What

| Criteria | Paragraphs | Layout Builder | Block Layout |
|----------|-----------|---------------|-------------|
| Editorial flexibility | High | Medium | Low |
| Content portability | Yes (entity-based) | No (layout-based) | No |
| Visual editing | No (form-based) | Yes (drag-and-drop) | No |
| API/Decoupled | Yes | Difficult | No |
| Setup complexity | Medium | Low | Low |
| Best for | Structured landing pages | Simple per-page layouts | Site-wide regions |

Refer to `references/paragraphs-layout-builder-guide.md` for setup details.

## Taxonomy

- **Vocabularies**: Categories, Tags, Locations, Content Types
- **Hierarchical terms**: Use for parent-child relationships (Regions > Cities)
- **Reference fields**: Entity reference to taxonomy term
- **Pathauto**: Auto-generate URLs from term hierarchy

```bash
# Create vocabulary
ddev drush generate vocabulary

# Add terms programmatically
ddev drush php:eval "
  \$term = \Drupal\taxonomy\Entity\Term::create([
    'name' => 'My Term',
    'vid' => 'vocabulary_name',
  ]);
  \$term->save();
"
```

## Menus

- **Main navigation**: Primary site navigation (main menu)
- **Footer**: Footer links
- **Admin**: Administrative menu (auto-generated from routes)
- **Custom menus**: Create for secondary navigation

```bash
# Create menu link
ddev drush menu:link:create "main" "My Page" "internal:/my-page"

# Rebuild menu cache
ddev drush cr
```

## URL Management

### Pathauto

```bash
# Install
ddev composer require drupal/pathauto
ddev drush en pathauto -y
```

Common patterns:
- Articles: `blog/[node:title]`
- Events: `events/[node:field_date:custom:Y]/[node:title]`
- Terms: `[term:vocabulary]/[term:name]`
- Users: `people/[user:name]`

### Redirects

```bash
# Install redirect module
ddev composer require drupal/redirect
ddev drush en redirect -y
```

## Webform

For complex forms (contact, application, survey):

```bash
ddev composer require drupal/webform
ddev drush en webform webform_ui -y
```

Key features: conditional logic, multi-page, file uploads, email handlers, submissions management, exports.

## Permissions & Roles

### Role Architecture

| Role | Purpose |
|------|---------|
| Anonymous | Public visitors |
| Authenticated | Logged-in users |
| Content Editor | Create/edit own content |
| Content Manager | Edit all content, manage taxonomy |
| Site Admin | Full content management, some configuration |
| Administrator | Full access (use sparingly) |

```bash
# Create role
ddev drush role:create 'content_editor' 'Content Editor'

# Grant permission
ddev drush role:perm:add 'content_editor' 'create article content,edit own article content'
```

### Content Moderation

```bash
# Enable
ddev drush en content_moderation -y
```

Workflow states: Draft → In Review → Published
- Configure transitions per role
- Set default moderation state per content type

## Configuration Management

### Export/Import

```bash
# Export all config
ddev drush cex -y

# Import config
ddev drush cim -y

# Check status (what's changed)
ddev drush config:status
```

### Config Split (Environment-Specific)

```bash
ddev composer require drupal/config_split
ddev drush en config_split -y
```

Common splits:
- **Development**: devel, webprofiler, field_ui, views_ui
- **Staging**: stage_file_proxy
- **Production**: (none — production is the baseline)

### Config Overrides

In `settings.php` or `settings.local.php`:

```php
// Override config per environment
$config['system.performance']['css']['preprocess'] = TRUE;
$config['system.performance']['js']['preprocess'] = TRUE;
$config['system.logging']['error_level'] = 'hide';
```

## Media Types

| Type | Module | Usage |
|------|--------|-------|
| Image | media (core) | Photos, illustrations |
| Document | media (core) | PDFs, spreadsheets |
| Video | media (core) | Local video files |
| Remote Video | media (core) | YouTube, Vimeo (oEmbed) |
| Audio | media (core) | Podcast episodes, sound clips |

**Always use Media over File/Image fields** — Media provides reuse, metadata, and consistent management.

## Drush Commands Quick Reference

```bash
# Content types
ddev drush entity:list --type=node_type      # List content types
ddev drush generate content-type             # Create content type

# Fields
ddev drush field:list node                   # List fields on node
ddev drush field:create                      # Create field (interactive)

# Taxonomy
ddev drush entity:list --type=taxonomy_vocabulary  # List vocabularies

# Config
ddev drush cex -y                            # Export config
ddev drush cim -y                            # Import config
ddev drush config:status                     # Check status
ddev drush config:get CONFIGNAME             # View specific config

# Views
ddev drush views:list                        # List all views
ddev drush views:enable VIEW_NAME            # Enable a view
ddev drush views:disable VIEW_NAME           # Disable a view

# Content
ddev drush entity:delete node --bundle=TYPE  # Delete all nodes of type

# Modules
ddev drush pm:list --type=module --status=enabled  # List enabled modules
ddev drush en MODULE -y                      # Enable module
ddev drush pmu MODULE -y                     # Uninstall module
```

## Decision Guide

| User request | Approach |
|--------------|----------|
| "Create a content type" | Define fields, display modes, form modes |
| "Build a listing page" | Views page display with filters and pager |
| "Add a sidebar block" | Views block display or custom block type |
| "Create landing pages" | Paragraphs or Layout Builder (see comparison) |
| "Set up categories" | Taxonomy vocabulary + entity reference field |
| "Auto-generate URLs" | Pathauto module with patterns |
| "Build a contact form" | Webform module |
| "Set up editorial workflow" | Content Moderation module |
| "Environment-specific config" | Config Split module |
| "Create an API endpoint" | Views REST Export display |
| "Add breadcrumbs" | Menu system + breadcrumb block |
| "Build a media gallery" | Media entity + Views grid display |

## Deep-Dive References

| Reference | When to read | File |
|-----------|-------------|------|
| **Views Guide** | Complex Views configuration, custom plugins, recipes | `references/views-guide.md` |
| **Paragraphs vs Layout Builder** | Choosing a layout system, setup, comparison | `references/paragraphs-layout-builder-guide.md` |

## Related Skills

- **drupal-expert** — Drupal development patterns, coding standards, DI
- **scaffold** — Generate module/component boilerplate
- **migrate** — Migrate content between systems or Drupal versions
- **drupal-frontend-expert** — Theming Views output, template overrides
- **drupal-security** — Access control and permissions architecture
