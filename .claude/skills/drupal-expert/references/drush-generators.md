# Drush Code Generators Reference

**Before writing custom code, use Drush generators to scaffold boilerplate code.**

Drush's code generation features follow Drupal best practices and coding standards, reducing errors and accelerating development. Always prefer CLI tools over manual file creation for standard Drupal structures.

## Content Types and Fields

**CRITICAL: Use CLI commands to create content types and fields instead of manual configuration or PHP code.**

### Create Content Types

```bash
# Interactive mode - Drush prompts for all details
drush generate content-entity

# Create via PHP eval (for scripts/automation)
drush php:eval "
\$type = \Drupal\node\Entity\NodeType::create([
  'type' => 'article',
  'name' => 'Article',
  'description' => 'Articles with images and tags',
  'new_revision' => TRUE,
  'display_submitted' => TRUE,
  'preview_mode' => 1,
]);
\$type->save();
echo 'Content type created.';
"
```

### Create Fields

```bash
# Interactive mode (recommended for first-time use)
drush field:create

# Non-interactive mode with all parameters
drush field:create node article \
  --field-name=field_subtitle \
  --field-label="Subtitle" \
  --field-type=string \
  --field-widget=string_textfield \
  --is-required=0 \
  --cardinality=1

# Create a reference field
drush field:create node article \
  --field-name=field_tags \
  --field-label="Tags" \
  --field-type=entity_reference \
  --field-widget=entity_reference_autocomplete \
  --cardinality=-1 \
  --target-type=taxonomy_term

# Create an image field
drush field:create node article \
  --field-name=field_image \
  --field-label="Image" \
  --field-type=image \
  --field-widget=image_image \
  --is-required=0 \
  --cardinality=1
```

**Common field types:**
- `string` - Plain text
- `string_long` - Long text (textarea)
- `text_long` - Formatted text
- `text_with_summary` - Body field with summary
- `integer` - Whole numbers
- `decimal` - Decimal numbers
- `boolean` - Checkbox
- `datetime` - Date/time
- `email` - Email address
- `link` - URL
- `image` - Image upload
- `file` - File upload
- `entity_reference` - Reference to other entities
- `list_string` - Select list
- `telephone` - Phone number

**Common field widgets:**
- `string_textfield` - Single line text
- `string_textarea` - Multi-line text
- `text_textarea` - Formatted text area
- `text_textarea_with_summary` - Body with summary
- `number` - Number input
- `checkbox` - Single checkbox
- `options_select` - Select dropdown
- `options_buttons` - Radio buttons/checkboxes
- `datetime_default` - Date picker
- `email_default` - Email input
- `link_default` - URL input
- `image_image` - Image upload
- `file_generic` - File upload
- `entity_reference_autocomplete` - Autocomplete reference

### Manage Fields

```bash
# List all fields on a content type
drush field:info node article

# List available field types
drush field:types

# List available field widgets
drush field:widgets

# List available field formatters
drush field:formatters

# Delete a field
drush field:delete node.article.field_subtitle
```

## Generate Module Scaffolding

```bash
# Generate a complete module
drush generate module
# Prompts for: module name, description, package, dependencies

# Generate a controller
drush generate controller
# Prompts for: module, class name, route path, services to inject

# Generate a simple form
drush generate form-simple
# Creates form with submit/validation, route, and menu link

# Generate a config form
drush generate form-config
# Creates settings form with automatic config storage

# Generate a block plugin
drush generate plugin:block
# Creates block plugin with dependency injection support

# Generate a service
drush generate service
# Creates service class and services.yml entry

# Generate a hook implementation
drush generate hook
# Creates hook in .module file or OOP hook class (D11)

# Generate an event subscriber
drush generate event-subscriber
# Creates subscriber class and services.yml entry
```

## Generate Entity Types

```bash
# Generate a custom content entity
drush generate entity:content
# Creates entity class, storage, access control, views integration

# Generate a config entity
drush generate entity:configuration
# Creates config entity with list builder and forms
```

## Generate Common Patterns

```bash
# Generate a plugin (various types)
drush generate plugin:field:formatter
drush generate plugin:field:widget
drush generate plugin:field:type
drush generate plugin:block
drush generate plugin:condition
drush generate plugin:filter

# Generate a Drush command
drush generate drush:command-file

# Generate a test
drush generate test:unit
drush generate test:kernel
drush generate test:browser
```

## Create Test Content

**Use Devel Generate for test data instead of manual entry:**

```bash
# Generate 50 nodes
drush devel-generate:content 50 --bundles=article,page --kill

# Generate taxonomy terms
drush devel-generate:terms 100 tags --kill

# Generate users
drush devel-generate:users 20

# Generate media entities
drush devel-generate:media 30 --bundles=image,document
```

## Non-Interactive Mode for Automation and AI Agents

**CRITICAL: Drush generators are interactive by default. Use these techniques to bypass prompts.**

### Method 1: `--answers` with JSON (Recommended)

```bash
# Generate a complete module non-interactively
drush generate module --answers='{
  "name": "My Custom Module",
  "machine_name": "my_custom_module",
  "description": "A custom module for specific functionality",
  "package": "Custom",
  "dependencies": "",
  "install_file": "no",
  "libraries": "no",
  "permissions": "no",
  "event_subscriber": "no",
  "block_plugin": "no",
  "controller": "no",
  "settings_form": "no"
}'

# Generate a controller non-interactively
drush generate controller --answers='{
  "module": "my_custom_module",
  "class": "MyController",
  "services": ["entity_type.manager", "current_user"]
}'

# Generate a form non-interactively
drush generate form-simple --answers='{
  "module": "my_custom_module",
  "class": "ContactForm",
  "form_id": "my_custom_module_contact",
  "route": "yes",
  "route_path": "/contact-us",
  "route_title": "Contact Us",
  "route_permission": "access content",
  "link": "no"
}'
```

### Method 2: Sequential `--answer` Flags

```bash
drush generate controller --answer="my_module" --answer="PageController" --answer=""
drush gen controller -a my_module -a PageController -a ""
```

### Method 3: Discover Required Answers

```bash
drush generate module -vvv --dry-run
```

### Method 4: Auto-Accept Defaults

```bash
drush generate module -y
drush generate module --answer="My Module" -y
```

### Complete Non-Interactive Examples

```bash
# Block plugin
drush generate plugin:block --answers='{
  "module": "my_custom_module",
  "plugin_id": "my_custom_block",
  "admin_label": "My Custom Block",
  "category": "Custom",
  "class": "MyCustomBlock",
  "services": ["entity_type.manager"],
  "configurable": "no",
  "access": "no"
}'

# Service
drush generate service --answers='{
  "module": "my_custom_module",
  "service_name": "my_custom_module.helper",
  "class": "HelperService",
  "services": ["database", "logger.factory"]
}'

# Event subscriber
drush generate event-subscriber --answers='{
  "module": "my_custom_module",
  "class": "MyEventSubscriber",
  "event": "kernel.request"
}'

# Drush command
drush generate drush:command-file --answers='{
  "module": "my_custom_module",
  "class": "MyCommands",
  "services": ["entity_type.manager"]
}'
```

### Common Answer Keys Reference

| Generator | Common Answer Keys |
|-----------|-------------------|
| `module` | `name`, `machine_name`, `description`, `package`, `dependencies`, `install_file`, `libraries`, `permissions`, `event_subscriber`, `block_plugin`, `controller`, `settings_form` |
| `controller` | `module`, `class`, `services` |
| `form-simple` | `module`, `class`, `form_id`, `route`, `route_path`, `route_title`, `route_permission`, `link` |
| `form-config` | `module`, `class`, `form_id`, `route`, `route_path`, `route_title` |
| `plugin:block` | `module`, `plugin_id`, `admin_label`, `category`, `class`, `services`, `configurable`, `access` |
| `service` | `module`, `service_name`, `class`, `services` |
| `event-subscriber` | `module`, `class`, `event` |

### Troubleshooting

**"Missing required answer" error:**
```bash
drush generate module -vvv --answers='{"name": "Test"}'
```

**JSON parsing errors:**
```bash
# Use single quotes outside, double inside
drush generate module --answers='{"name": "Test Module"}'  # Correct
```

**Interactive prompt still appears:**
```bash
drush generate module -vvv --dry-run 2>&1 | grep -E "^\s*\?"
```

## Avoiding Common Mistakes

**DON'T manually create:**
- Content type config files (`node.type.*.yml`)
- Field config files (`field.field.*.yml`, `field.storage.*.yml`)
- View mode config (`core.entity_view_display.*.yml`)
- Form mode config (`core.entity_form_display.*.yml`)

**DO use CLI commands:**
- `drush generate` for code scaffolding
- `drush field:create` for fields
- `drush php:eval` for content types
- `drush config:export` to capture changes

## Integration with DDEV

```bash
ddev drush generate module
ddev drush field:create node article
ddev exec drush generate controller
```

## Sources

- [Drush Code Generators](https://drupalize.me/tutorial/develop-drupal-modules-faster-drush-code-generators)
- [Drush Generate Command](https://www.drush.org/13.x/commands/generate/)
- [Drush field:create](https://www.drush.org/13.x/commands/field_create/)
- [Scaffold Custom Content Entity with Drush](https://drupalize.me/tutorial/scaffold-custom-content-entity-type-drush-generators)
- [Drupal Code Generator (DCG)](https://github.com/Chi-teck/drupal-code-generator)
