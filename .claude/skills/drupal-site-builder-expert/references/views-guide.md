# Views Configuration Guide

Comprehensive reference for building and configuring Views in Drupal 10/11.

## Architecture

Views consists of:
- **Display plugins** — How results are presented (Page, Block, Feed, REST)
- **Style plugins** — How rows are grouped (Table, Grid, List, Unformatted)
- **Row plugins** — How each item renders (Content/entity, Fields)
- **Handler plugins** — What data is included (Fields, Filters, Sorts, Relationships, Arguments)

## Display Types

### Page Display

Creates a standalone page at a URL path.

```yaml
# In views export YAML
display:
  page_1:
    display_plugin: page
    display_options:
      path: blog
      menu:
        type: normal
        title: Blog
        weight: 0
```

- Set path, title, menu link
- Configure access (permission or role)
- Use for: listing pages, archive pages, dashboards

### Block Display

Embeddable block for regions, Layout Builder, or panels.

- Appears in Block Layout and Layout Builder
- Can set items per block, override pager
- Use for: sidebar listings, featured content, related items

### Attachment Display

Attached before/after another Views display.

- Inherits contextual filters from parent
- Use for: summary headers, companion data, sub-listings

### Feed Display

RSS/Atom feed output.

- Pair with a page display at `/blog` → feed at `/blog/rss`
- Use row style: RSS fields or Content
- Use for: RSS feeds, podcast feeds

### REST Export Display

JSON or XML API output.

```yaml
display:
  rest_export_1:
    display_plugin: rest_export
    display_options:
      path: api/articles
      style:
        type: serializer
        options:
          formats:
            json: json
```

- Set serializer format (JSON, XML)
- Authentication: cookie, basic_auth, or oauth
- Use for: headless/decoupled frontends, mobile apps

### Entity Reference Display

Powers entity reference autocomplete and select widgets.

- Filters available to reference fields
- Usually hidden from public
- Use for: autocomplete fields in forms

## Filters

### Regular Filters

Hardcoded criteria that always apply:

```yaml
filters:
  status:
    value: '1'    # Published only
  type:
    value:
      article: article
```

### Exposed Filters

User-facing filters (search forms, facets):

```yaml
filters:
  title:
    exposed: true
    expose:
      label: Search
      identifier: search
      operator_id: title_op
```

**Better Exposed Filters (BEF):**
```bash
ddev composer require drupal/better_exposed_filters
ddev drush en better_exposed_filters -y
```

Converts select lists to checkboxes/radio buttons, adds reset button, AJAX auto-submit.

### Grouped Filters

Combine multiple filter values into labeled options:

| Label | Condition |
|-------|-----------|
| "Recent" | Created > 7 days ago |
| "This Month" | Created in current month |
| "Older" | Created > 30 days ago |

## Sorts

### Basic Sorts

```yaml
sorts:
  created:
    order: DESC   # Newest first
  title:
    order: ASC    # Alphabetical
```

### Exposed Sorts

Let users choose sort order (e.g., "Sort by: Date / Title / Popularity").

### Random Sort

- Use `views.sort.random` plugin
- Caveats: Cannot cache with random sort, impacts performance
- Alternative: Randomize in a block with short cache lifetime

## Relationships

Relationships join related entities into the query.

### Entity Reference

```yaml
relationships:
  field_author:
    field: field_author
    required: true   # INNER JOIN (only show nodes with author)
```

### Reverse Entity Reference

Find entities that reference the current entity:

```yaml
relationships:
  reverse__node__field_related:
    field: field_related
    entity_type: node
```

### Taxonomy Term

```yaml
relationships:
  field_tags:
    field: field_tags
    required: false  # LEFT JOIN (show even without tags)
```

## Contextual Filters (Arguments)

Dynamic filters from the URL or other context.

### From URL

Path `/blog/2024` with contextual filter on `field_year`:
- Provide default: Raw value from URL (path component 2)
- Validation: Numeric
- Action when missing: Display all / Show 404

### Default Values

| Source | Use case |
|--------|----------|
| Raw value from URL | `/taxonomy/term/{tid}` |
| Content ID from URL | Node page sidebar blocks |
| Current user ID | "My content" view |
| Fixed value | Hardcoded default |
| PHP code | Complex logic (avoid if possible) |

### Validation

- **Content type**: Validate argument is a valid node of specific type
- **Taxonomy term**: Validate argument is a valid term ID
- **Numeric**: Basic number validation
- **PHP**: Custom validation (use sparingly)

## Fields vs Rendered Entity

### Fields Mode

Select individual fields, rewrite output, custom markup:

```yaml
row:
  type: fields
fields:
  title:
    label: ''
    link_to_entity: true
  field_image:
    label: ''
  created:
    date_format: medium
```

**When to use:** Custom layouts, API endpoints, email templates, complex formatting.

### Rendered Entity Mode

Use view modes (teaser, card, full):

```yaml
row:
  type: entity:node
  options:
    view_mode: teaser
```

**When to use:** Consistent display across the site, leverages field formatters, simpler config.

## Aggregation

Enable aggregation for GROUP BY queries:

```yaml
use_aggregation: true
fields:
  type:
    group_type: group    # GROUP BY
  nid:
    group_type: count    # COUNT
  field_price:
    group_type: sum      # SUM
```

Available functions: GROUP, COUNT, COUNT DISTINCT, SUM, AVG, MIN, MAX.

**Use cases:** Content counts per type, total revenue, average ratings, most active users.

## Caching

### Tag-Based (Recommended)

```yaml
cache:
  type: tag
```

Invalidates automatically when referenced entities change. Best for most Views.

### Time-Based

```yaml
cache:
  type: time
  options:
    results_lifespan: 3600    # Query results: 1 hour
    output_lifespan: 3600     # Rendered output: 1 hour
```

Use when tag-based is insufficient or for expensive queries.

### None

```yaml
cache:
  type: none
```

**Avoid** — only for debugging or truly dynamic content (real-time dashboards).

## Views Bulk Operations (VBO)

```bash
ddev composer require drupal/views_bulk_operations
ddev drush en views_bulk_operations -y
```

Add a "Bulk operations" field to enable mass actions:
- Publish/unpublish
- Delete
- Change author
- Custom actions

## Theming Views

### Template Suggestions

```
views-view--VIEW_NAME--DISPLAY_ID.html.twig
views-view--VIEW_NAME.html.twig
views-view.html.twig

views-view-unformatted--VIEW_NAME--DISPLAY_ID.html.twig
views-view-fields--VIEW_NAME.html.twig
```

### Useful Template Variables

```twig
{# views-view.html.twig #}
{{ header }}        {# View header #}
{{ exposed }}       {# Exposed filters form #}
{{ rows }}          {# View content rows #}
{{ pager }}         {# Pager #}
{{ empty }}         {# No results message #}

{# views-view-fields.html.twig #}
{{ fields.title.content }}
{{ fields.field_image.content }}
```

### CSS Classes

Add custom CSS classes in View display settings:
- View: "CSS class" setting
- Row: "Row class" with token replacement
- Field: "Customize field HTML" wrapper classes

## Recipes

### Recent Content with Exposed Search

1. Create Page display at `/content`
2. Add fields: Title, Content type, Created date, Operations
3. Filter: Published = Yes
4. Exposed filter: Title (contains), Content type (select)
5. Sort: Created date (DESC)
6. Pager: Full pager, 25 items
7. Access: Permission "access content"

### Related Content Block

1. Create Block display
2. Content type: Article
3. Contextual filter: Content type (from URL node, exclude current)
4. Sort: Random
5. Limit: 3 items, no pager
6. Cache: Tag-based

### Taxonomy Term Archive

1. Create Page display at `/category/%`
2. Relationship: field_category (taxonomy term)
3. Contextual filter: Term ID (from URL, validate as taxonomy term)
4. Default when empty: Show 404
5. Use `{{ arguments.tid }}` for title override

### User Content Dashboard

1. Create Page display at `/my-content`
2. Contextual filter: Author UID (default: current user)
3. Exposed filters: Content type, Status
4. Fields: Title, Type, Status, Created, Edit link
5. Access: Permission "access content overview"

### Media Gallery

1. Create Page display at `/gallery`
2. Entity type: Media
3. Filter: Media type = Image, Status = Published
4. Format: Grid (3 columns)
5. Row: Rendered entity (thumbnail view mode)
6. Pager: Mini pager or Load More (with views_infinite_scroll)

## Performance Tips

1. **Always use caching** — tag-based for most Views
2. **Limit fields** — Only select fields you display
3. **Use rendered entity** when possible (simpler query)
4. **Avoid random sort** on large datasets
5. **Use contextual filters** to narrow results (vs loading everything)
6. **Aggregate carefully** — GROUP BY can be expensive
7. **Pager limits** — Don't load 1000 items per page
8. **Lazy-load blocks** — Use BigPipe for heavy View blocks

## YAML Export/Import

```bash
# Export a single view
ddev drush config:get views.view.VIEW_NAME --format=yaml > view-export.yml

# Import (via config import)
# Place in config/sync/ and run:
ddev drush cim --partial --source=/path/to/config -y
```

Views are stored as config entities at `views.view.VIEW_NAME` in the config system.
