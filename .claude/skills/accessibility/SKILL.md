---
name: accessibility
description: WCAG 2.2 compliance, keyboard navigation, ARIA patterns, and automated a11y testing for Drupal
version: 1.0.0
---

# Accessibility (a11y) — Drupal Development

## Activation

Activate when:
- Working on Twig templates, frontend components, or theme development
- User mentions accessibility, a11y, WCAG, ARIA, screen reader, keyboard navigation
- Creating forms, interactive elements, modals, or dynamic content
- Reviewing frontend code for compliance

## WCAG 2.2 Quick Reference

| Level | Target | Criteria Count | Typical Requirement |
|-------|--------|---------------|---------------------|
| A | Minimum | 30 | Legal baseline in most jurisdictions |
| AA | Standard | 24 additional | **Target this** — industry standard, most regulations |
| AAA | Enhanced | 28 additional | Rarely required site-wide, useful for specific content |

### Core Principles (POUR)

1. **Perceivable** — content available to all senses (alt text, captions, contrast)
2. **Operable** — navigable by keyboard, enough time, no seizure triggers
3. **Understandable** — readable, predictable, input assistance
4. **Robust** — compatible with assistive technologies

## Semantic HTML in Drupal Twig

### Heading Hierarchy

```twig
{# CORRECT: proper heading hierarchy #}
<article{{ attributes }}>
  <h2{{ title_attributes }}>{{ label }}</h2>
  <div{{ content_attributes }}>
    <h3>Section Title</h3>
    <p>{{ content.field_body }}</p>
  </div>
</article>

{# WRONG: skipping heading levels #}
<div>
  <h1>Title</h1>
  <h4>Subsection</h4> {# Skipped h2 and h3! #}
</div>
```

### Landmarks

```twig
{# page.html.twig with proper landmarks #}
<header role="banner">
  {{ page.header }}
</header>

<nav role="navigation" aria-label="{{ 'Main navigation'|t }}">
  {{ page.primary_menu }}
</nav>

<main role="main" id="main-content">
  <a id="main-content-anchor" tabindex="-1"></a>
  {{ page.content }}
</main>

<aside role="complementary" aria-label="{{ 'Sidebar'|t }}">
  {{ page.sidebar }}
</aside>

<footer role="contentinfo">
  {{ page.footer }}
</footer>
```

### Accessible Navigation

```twig
{# menu.html.twig — accessible menu with current page indication #}
{% import _self as menus %}

{{ menus.menu_links(items, attributes, 0) }}

{% macro menu_links(items, attributes, menu_level) %}
  {% import _self as menus %}
  {% if items %}
    <ul{{ attributes.addClass(menu_level == 0 ? 'menu' : 'menu--child') }} role="list">
      {% for item in items %}
        {% set item_classes = [
          'menu__item',
          item.in_active_trail ? 'menu__item--active-trail',
          item.below ? 'menu__item--expanded',
        ] %}
        <li{{ item.attributes.addClass(item_classes) }}>
          <a href="{{ item.url }}"
            {{ item.in_active_trail ? 'aria-current="page"' }}
            {{ item.below ? 'aria-expanded="false" aria-haspopup="true"' }}>
            {{ item.title }}
          </a>
          {% if item.below %}
            {{ menus.menu_links(item.below, attributes.removeClass(attributes.class), menu_level + 1) }}
          {% endif %}
        </li>
      {% endfor %}
    </ul>
  {% endif %}
{% endmacro %}
```

## ARIA Patterns

### Rule: Use ARIA as Last Resort

1. Use native HTML first (`<button>`, `<nav>`, `<dialog>`)
2. Don't change native semantics (`<h2 role="tab">` — wrong)
3. All interactive ARIA controls must be keyboard operable
4. Don't use `role="presentation"` or `aria-hidden="true"` on focusable elements
5. All interactive elements must have accessible names

### Common ARIA Patterns in Drupal

```twig
{# Accessible dropdown / disclosure #}
<div class="dropdown">
  <button
    aria-expanded="false"
    aria-controls="dropdown-menu-{{ id }}"
    type="button">
    {{ label }}
  </button>
  <ul id="dropdown-menu-{{ id }}" role="menu" hidden>
    {% for item in items %}
      <li role="menuitem">
        <a href="{{ item.url }}">{{ item.title }}</a>
      </li>
    {% endfor %}
  </ul>
</div>

{# Accessible tabs #}
<div class="tabs">
  <ul role="tablist" aria-label="{{ 'Content sections'|t }}">
    {% for tab in tabs %}
      <li role="presentation">
        <button
          role="tab"
          id="tab-{{ tab.id }}"
          aria-controls="panel-{{ tab.id }}"
          aria-selected="{{ loop.first ? 'true' : 'false' }}"
          tabindex="{{ loop.first ? '0' : '-1' }}">
          {{ tab.label }}
        </button>
      </li>
    {% endfor %}
  </ul>
  {% for tab in tabs %}
    <div
      role="tabpanel"
      id="panel-{{ tab.id }}"
      aria-labelledby="tab-{{ tab.id }}"
      {{ not loop.first ? 'hidden' }}
      tabindex="0">
      {{ tab.content }}
    </div>
  {% endfor %}
</div>

{# Live region for dynamic updates #}
<div aria-live="polite" aria-atomic="true" class="visually-hidden">
  {{ status_message }}
</div>
```

## Keyboard Navigation

### Requirements

| Element | Expected Keyboard Behavior |
|---------|---------------------------|
| Links/buttons | `Enter` to activate, visible focus indicator |
| Menus | Arrow keys to navigate, `Escape` to close |
| Tabs | Arrow keys between tabs, `Tab` to enter panel |
| Modals/dialogs | Focus trapped inside, `Escape` to close, focus returns on close |
| Carousels | Arrow keys, pause on focus, button to stop auto-play |
| Autocomplete | Arrow keys to navigate, `Enter` to select, `Escape` to dismiss |

### Focus Management in JavaScript

```javascript
(function (Drupal) {
  'use strict';

  Drupal.behaviors.accessibleModal = {
    attach(context) {
      const triggers = once('a11y-modal', '[data-modal-trigger]', context);

      triggers.forEach((trigger) => {
        trigger.addEventListener('click', (e) => {
          const modal = document.getElementById(trigger.dataset.modalTrigger);
          if (!modal) return;

          // Store trigger to return focus on close
          modal._triggerElement = trigger;

          // Show and trap focus
          modal.showModal();
          const firstFocusable = modal.querySelector(
            'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
          );
          firstFocusable?.focus();
        });
      });

      // Return focus on close
      once('a11y-modal-close', 'dialog', context).forEach((dialog) => {
        dialog.addEventListener('close', () => {
          dialog._triggerElement?.focus();
        });
      });
    },
  };
})(Drupal);
```

### Skip Link

```twig
{# Must be first focusable element in page.html.twig #}
<a href="#main-content" class="visually-hidden focusable skip-link">
  {{ 'Skip to main content'|t }}
</a>
```

```css
.skip-link {
  position: absolute;
  inset-block-start: -100%;
}
.skip-link:focus {
  position: fixed;
  inset-block-start: 0;
  inset-inline-start: 0;
  z-index: 1000;
  padding: var(--space-xs) var(--space-sm);
  background: var(--color-focus);
  color: var(--color-on-focus);
}
```

## Color and Contrast

### WCAG Contrast Ratios

| Text Type | AA Ratio | AAA Ratio |
|-----------|----------|-----------|
| Normal text (< 18pt) | 4.5:1 | 7:1 |
| Large text (≥ 18pt or 14pt bold) | 3:1 | 4.5:1 |
| UI components / graphical objects | 3:1 | — |

### CSS Patterns

```css
/* Use custom properties for easy theme-wide contrast management */
:root {
  --color-text: #1a1a1a;          /* 15.3:1 on white */
  --color-text-muted: #595959;    /* 7.0:1 on white */
  --color-link: #0055b8;          /* 7.1:1 on white */
  --color-link-visited: #6b3fa0;  /* 5.6:1 on white */
  --color-focus: #1a73e8;
  --focus-outline: 3px solid var(--color-focus);
  --focus-outline-offset: 2px;
}

/* Consistent focus indicators — NEVER use outline: none without replacement */
:focus-visible {
  outline: var(--focus-outline);
  outline-offset: var(--focus-outline-offset);
}

/* High contrast mode support */
@media (forced-colors: active) {
  .button {
    border: 2px solid ButtonText;
  }
}

/* Reduced motion */
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}
```

## Forms Accessibility

```twig
{# Accessible form field with error #}
<div class="form-item{{ errors ? ' form-item--error' }}">
  <label for="edit-email" class="form-item__label{{ required ? ' form-required' }}">
    {{ 'Email address'|t }}
    {% if required %}
      <span class="form-required__marker" aria-hidden="true">*</span>
    {% endif %}
  </label>

  {% if description %}
    <div id="edit-email-description" class="form-item__description">
      {{ description }}
    </div>
  {% endif %}

  <input
    type="email"
    id="edit-email"
    name="email"
    class="form-email{{ errors ? ' error' }}"
    {{ required ? 'required aria-required="true"' }}
    {{ description ? 'aria-describedby="edit-email-description"'|raw }}
    {{ errors ? 'aria-invalid="true" aria-errormessage="edit-email-error"'|raw }}
    autocomplete="email"
  />

  {% if errors %}
    <div id="edit-email-error" class="form-item__error-message" role="alert">
      {{ errors }}
    </div>
  {% endif %}
</div>
```

## Images and Media

```twig
{# Informative image — describe the content #}
<img src="{{ file_url }}" alt="{{ image_alt }}" />

{# Decorative image — empty alt, not missing #}
<img src="{{ decorative_url }}" alt="" role="presentation" />

{# Complex image — long description #}
<figure>
  <img src="{{ chart_url }}" alt="{{ 'Chart showing quarterly revenue growth'|t }}"
       aria-describedby="chart-description-{{ id }}" />
  <figcaption id="chart-description-{{ id }}">
    {{ detailed_description }}
  </figcaption>
</figure>

{# Video with captions #}
<video controls>
  <source src="{{ video_url }}" type="video/mp4" />
  <track kind="captions" src="{{ captions_url }}" srclang="en" label="{{ 'English'|t }}" default />
  <track kind="descriptions" src="{{ descriptions_url }}" srclang="en" label="{{ 'Audio descriptions'|t }}" />
</video>
```

## Dynamic Content — Drupal.announce()

```javascript
(function (Drupal) {
  'use strict';

  Drupal.behaviors.liveUpdates = {
    attach(context) {
      once('live-filter', '.views-exposed-form', context).forEach((form) => {
        form.addEventListener('change', () => {
          // After AJAX completes, announce result count
          const resultCount = document.querySelectorAll('.views-row').length;
          Drupal.announce(
            Drupal.t('@count results found', { '@count': resultCount }),
            'polite'  // 'polite' waits, 'assertive' interrupts
          );
        });
      });
    },
  };
})(Drupal);
```

### Status Messages

```twig
{# status-messages.html.twig #}
<div data-drupal-messages>
  {% for type, messages in message_list %}
    <div
      role="{{ type == 'error' ? 'alert' : 'status' }}"
      aria-label="{{ status_headings[type] }}"
      class="messages messages--{{ type }}">
      {% if status_headings[type] %}
        <h2 class="visually-hidden">{{ status_headings[type] }}</h2>
      {% endif %}
      {% if messages|length > 1 %}
        <ul class="messages__list">
          {% for message in messages %}
            <li class="messages__item">{{ message }}</li>
          {% endfor %}
        </ul>
      {% else %}
        <p class="messages__item">{{ messages|first }}</p>
      {% endif %}
    </div>
  {% endfor %}
</div>
```

## Automated Testing

### axe-core Integration

```bash
# Install
npm install --save-dev @axe-core/cli

# Run against local site
npx axe http://my-drupal-site.ddev.site --tags wcag2a,wcag2aa,wcag22aa

# With specific rules
npx axe http://my-drupal-site.ddev.site --rules color-contrast,label,image-alt
```

### Lighthouse CI

```bash
# Install
npm install --save-dev @lhci/cli

# Run accessibility audit
npx lhci autorun --collect.url=http://my-drupal-site.ddev.site \
  --assert.assertions='categories:accessibility>=0.9'
```

### pa11y

```bash
# Install and run
npm install --save-dev pa11y
npx pa11y http://my-drupal-site.ddev.site --standard WCAG2AA

# Multiple pages
npx pa11y-ci --config .pa11yci.json
```

### PHPUnit (Drupal Functional Tests)

```php
declare(strict_types=1);

namespace Drupal\Tests\my_module\Functional;

use Drupal\Tests\BrowserTestBase;

final class AccessibilityTest extends BrowserTestBase {

  protected $defaultTheme = 'stark';

  public function testPageHasProperHeadingHierarchy(): void {
    $this->drupalGet('/node/1');
    $session = $this->assertSession();

    // Check h1 exists exactly once
    $h1_elements = $this->getSession()->getPage()->findAll('css', 'h1');
    $this->assertCount(1, $h1_elements, 'Page has exactly one h1 element');

    // Check skip link exists
    $session->elementExists('css', 'a.skip-link');

    // Check images have alt attributes
    $images = $this->getSession()->getPage()->findAll('css', 'img');
    foreach ($images as $image) {
      $this->assertTrue(
        $image->hasAttribute('alt'),
        sprintf('Image %s missing alt attribute', $image->getAttribute('src'))
      );
    }

    // Check form labels
    $inputs = $this->getSession()->getPage()->findAll('css', 'input:not([type="hidden"])');
    foreach ($inputs as $input) {
      $id = $input->getAttribute('id');
      if ($id) {
        $session->elementExists('css', "label[for=\"{$id}\"]");
      }
    }
  }

}
```

## Manual Testing Checklist

### Keyboard-Only Navigation
- [ ] Tab through entire page — all interactive elements reachable
- [ ] Focus order matches visual order
- [ ] Focus indicator visible on every focused element
- [ ] Can operate all controls (buttons, links, menus, tabs, modals)
- [ ] Can dismiss overlays/modals with Escape
- [ ] No keyboard traps (can always Tab away)

### Screen Reader (VoiceOver / NVDA)
- [ ] Page title announced on load
- [ ] Headings navigable (rotor/headings list)
- [ ] Landmarks navigable
- [ ] Form labels read correctly
- [ ] Error messages associated with fields
- [ ] Dynamic content changes announced
- [ ] Decorative images hidden, informative images described

### Visual
- [ ] Zoom to 200% — no content cut off or overlapping
- [ ] Text spacing increased — still readable (letter-spacing 0.12em, word-spacing 0.16em, line-height 1.5)
- [ ] Windows High Contrast Mode — content visible
- [ ] Color not sole indicator of meaning (errors have icons/text too)

## Common Drupal a11y Issues

| Issue | Where | Fix |
|-------|-------|-----|
| Views output missing headings | Views block/page | Add header with heading tag in views settings |
| Admin toolbar not keyboard accessible | Admin toolbar module | Use Gin theme which fixes this |
| AJAX updates not announced | Custom AJAX | Use `Drupal.announce()` after AJAX completes |
| Modal dialogs — focus not trapped | jQuery UI dialog | Use native `<dialog>` element or add focus trap JS |
| Dropdown menus — keyboard inaccessible | Custom menus | Add arrow key navigation + Escape handler |
| Status messages not role="status" | Custom templates | Use proper `role="status"` or `role="alert"` |
| Entity reference autocomplete | Core widget | Generally accessible, but test with screen reader |
| CKEditor content | WYSIWYG | Train editors on heading hierarchy, alt text, link text |
| Responsive tables | Views tables | Use `<caption>`, proper `<th scope>`, consider reflow pattern |
| Color picker fields | Custom forms | Provide text input alternative alongside visual picker |
