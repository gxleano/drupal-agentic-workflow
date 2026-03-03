# JavaScript Behaviors Guide

Comprehensive reference for Drupal.behaviors, the `once()` API, and modern JavaScript patterns in Drupal 10/11.

## Why Drupal Behaviors?

Drupal doesn't load pages like a traditional website. Content can arrive via:
- **BigPipe**: Streams content in chunks after initial page load
- **Ajax**: Form rebuilds, Views infinite scroll, exposed filter updates
- **Turbo/pjax**: Partial page replacements
- **Layout Builder**: Dynamic block placement

Standard `DOMContentLoaded` or `$(document).ready()` only fires once. **Drupal behaviors fire every time new content appears**, making them the correct pattern for all JavaScript initialization.

## Drupal.behaviors Pattern

### Basic Structure

```javascript
(function (Drupal, once) {
  'use strict';

  Drupal.behaviors.myBehaviorName = {
    attach(context, settings) {
      // Called when new content is added to the DOM.
      // context = the DOM element that was just added (or document on page load).
      // settings = drupalSettings object.
    },
    detach(context, settings, trigger) {
      // Called when content is removed from the DOM.
      // trigger = 'unload' (page leave), 'move' (moved in DOM), 'serialize' (form serialize).
    },
  };
})(Drupal, once);
```

### Lifecycle

1. **Page load**: `attach(document, drupalSettings)` called for all behaviors
2. **Ajax response**: `attach(newElement, drupalSettings)` called with the new DOM element
3. **BigPipe placeholder replaced**: `attach(replacedElement, drupalSettings)`
4. **Form submit/Ajax before**: `detach(formElement, drupalSettings, 'serialize')`
5. **Content removed**: `detach(removedElement, drupalSettings, 'unload')`
6. **Content moved**: `detach(element, drupalSettings, 'move')` then `attach(element, drupalSettings)`

### Context Parameter

```javascript
Drupal.behaviors.myFeature = {
  attach(context) {
    // context is the new DOM subtree — query within it, not the whole document.

    // CORRECT — queries within context
    const elements = context.querySelectorAll('.my-element');

    // WRONG — queries the entire document (wastes time, may re-initialize)
    const elements = document.querySelectorAll('.my-element');
  },
};
```

## once() API

The `once()` function ensures an element is initialized exactly once, even if `attach()` is called multiple times.

### Basic Usage

```javascript
(function (Drupal, once) {
  'use strict';

  Drupal.behaviors.accordion = {
    attach(context) {
      // once('id', 'selector', context) returns only elements not yet processed.
      once('accordion', '.accordion', context).forEach((element) => {
        const header = element.querySelector('.accordion__header');
        const content = element.querySelector('.accordion__content');

        header.addEventListener('click', () => {
          content.hidden = !content.hidden;
          header.setAttribute('aria-expanded', String(!content.hidden));
        });
      });
    },
  };
})(Drupal, once);
```

### once() Returns

`once(id, selector, context)` returns an array of DOM elements that:
- Match the selector within context
- Have NOT been processed with this `id` before

### Removing once() Tracking

```javascript
// Remove tracking so element can be re-initialized
once.remove('accordion', '.accordion', context);
```

### Checking once() Status

```javascript
// Check if element has been processed
const processed = once.find('accordion', '.accordion');
// Returns elements that HAVE been processed with 'accordion'
```

## jQuery-Free Patterns

Drupal 10/11 encourages jQuery-free JavaScript. Here are modern equivalents:

### DOM Selection

```javascript
// jQuery: $('.my-class')
const elements = context.querySelectorAll('.my-class');

// jQuery: $('#my-id')
const element = context.querySelector('#my-id');

// jQuery: $(this).closest('.parent')
const parent = element.closest('.parent');

// jQuery: $(this).find('.child')
const children = element.querySelectorAll('.child');

// jQuery: $(this).siblings('.sibling')
const siblings = [...element.parentNode.children].filter(
  (child) => child !== element && child.matches('.sibling'),
);
```

### DOM Manipulation

```javascript
// jQuery: $(el).addClass('active')
element.classList.add('active');

// jQuery: $(el).toggleClass('active')
element.classList.toggle('active');

// jQuery: $(el).hasClass('active')
element.classList.contains('active');

// jQuery: $(el).attr('data-id')
element.getAttribute('data-id');
// Or for data attributes:
element.dataset.id;

// jQuery: $(el).hide() / $(el).show()
element.hidden = true;
element.hidden = false;

// jQuery: $(el).html('<p>text</p>')
element.innerHTML = '<p>text</p>';

// jQuery: $(el).text('safe text')
element.textContent = 'safe text';

// jQuery: $(el).append(child)
element.appendChild(child);

// jQuery: $(el).remove()
element.remove();
```

### Events

```javascript
// jQuery: $(el).on('click', handler)
element.addEventListener('click', handler);

// jQuery: $(el).off('click', handler)
element.removeEventListener('click', handler);

// jQuery: $(document).on('click', '.dynamic', handler) — event delegation
document.addEventListener('click', (event) => {
  const target = event.target.closest('.dynamic');
  if (target) {
    handler(event, target);
  }
});

// jQuery: $(el).trigger('change')
element.dispatchEvent(new Event('change'));
```

### AJAX

```javascript
// jQuery: $.ajax() / $.get() / $.post()
// Modern: fetch()
const response = await fetch('/api/data', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'X-Requested-With': 'XMLHttpRequest',
  },
  body: JSON.stringify({ key: 'value' }),
});
const data = await response.json();
```

### Animation

```javascript
// jQuery: $(el).fadeIn()
element.animate(
  [{ opacity: 0 }, { opacity: 1 }],
  { duration: 300, fill: 'forwards' },
);

// jQuery: $(el).slideDown()
// Use CSS transitions instead:
element.style.maxHeight = element.scrollHeight + 'px';
// With CSS: .element { transition: max-height 0.3s ease; overflow: hidden; }
```

## drupalSettings

Pass data from PHP to JavaScript.

### PHP Side

```php
// In a render array
$build['#attached']['drupalSettings']['myModule'] = [
  'apiEndpoint' => '/api/v1/items',
  'maxItems' => 10,
  'currentUser' => [
    'id' => $this->currentUser->id(),
    'name' => $this->currentUser->getAccountName(),
  ],
];

// In a preprocess function
function mytheme_preprocess_page(&$variables): void {
  $variables['#attached']['drupalSettings']['myTheme'] = [
    'breakpoint' => 768,
  ];
}
```

### JavaScript Side

```javascript
Drupal.behaviors.myFeature = {
  attach(context, settings) {
    // Access via settings parameter
    const endpoint = settings.myModule?.apiEndpoint;
    const maxItems = settings.myModule?.maxItems;

    // Or via global drupalSettings
    const breakpoint = drupalSettings.myTheme?.breakpoint;

    // Always use optional chaining — settings may not be set
  },
};
```

## Ajax Integration

Behaviors automatically re-fire when Drupal Ajax updates the DOM.

### Ajax Form Example

```php
// PHP — form with Ajax
$form['search'] = [
  '#type' => 'textfield',
  '#title' => $this->t('Search'),
  '#ajax' => [
    'callback' => '::ajaxCallback',
    'wrapper' => 'results-wrapper',
    'event' => 'keyup',
    'progress' => ['type' => 'throbber'],
  ],
];

$form['results'] = [
  '#type' => 'container',
  '#attributes' => ['id' => 'results-wrapper'],
  '#markup' => '',
];
```

```javascript
// JS — behavior re-fires when #results-wrapper is replaced
Drupal.behaviors.searchResults = {
  attach(context) {
    once('search-results', '#results-wrapper', context).forEach((wrapper) => {
      // Initialize result interactions (click handlers, etc.)
      // This fires after every Ajax response that updates the wrapper.
    });
  },
};
```

### Custom Ajax Commands

```javascript
// Define a custom Ajax command
Drupal.AjaxCommands.prototype.myCustomCommand = function (ajax, response) {
  const element = document.querySelector(response.selector);
  if (element) {
    element.textContent = response.data;
    // Re-attach behaviors to the updated element
    Drupal.attachBehaviors(element);
  }
};
```

## BigPipe Compatibility

BigPipe streams page content in chunks. Behaviors must handle:
- Initial page load (partial content)
- BigPipe placeholder replacements (more content arrives)

```javascript
Drupal.behaviors.lazyComponent = {
  attach(context) {
    // This fires for:
    // 1. Initial page load (context = document)
    // 2. Each BigPipe placeholder replacement (context = replaced element)
    // 3. Each Ajax response (context = updated element)

    once('lazy-component', '[data-lazy-component]', context).forEach((el) => {
      // Safe: only initializes elements not yet processed.
      initComponent(el);
    });
  },
};
```

## Event Delegation

For elements that may be added/removed dynamically:

```javascript
Drupal.behaviors.dynamicList = {
  attach(context) {
    once('dynamic-list', '.item-list', context).forEach((list) => {
      // Event delegation — handles clicks on items added later
      list.addEventListener('click', (event) => {
        const item = event.target.closest('.item-list__item');
        if (item) {
          item.classList.toggle('item-list__item--selected');
        }
      });
    });
  },
};
```

## Common Patterns

### Toggle

```javascript
Drupal.behaviors.toggle = {
  attach(context) {
    once('toggle', '[data-toggle-target]', context).forEach((trigger) => {
      const targetId = trigger.dataset.toggleTarget;
      const target = document.getElementById(targetId);
      if (!target) return;

      trigger.addEventListener('click', () => {
        const isExpanded = trigger.getAttribute('aria-expanded') === 'true';
        trigger.setAttribute('aria-expanded', String(!isExpanded));
        target.hidden = isExpanded;
      });
    });
  },
};
```

### Lazy Load (Intersection Observer)

```javascript
Drupal.behaviors.lazyLoad = {
  attach(context) {
    once('lazy-load', '[data-lazy-src]', context).forEach((img) => {
      const observer = new IntersectionObserver(
        (entries) => {
          entries.forEach((entry) => {
            if (entry.isIntersecting) {
              img.src = img.dataset.lazySrc;
              observer.unobserve(img);
            }
          });
        },
        { rootMargin: '200px' },
      );
      observer.observe(img);
    });
  },
};
```

### Debounced Input

```javascript
Drupal.behaviors.searchInput = {
  attach(context) {
    once('search-input', '.search-input', context).forEach((input) => {
      let timeout;
      input.addEventListener('input', () => {
        clearTimeout(timeout);
        timeout = setTimeout(() => {
          performSearch(input.value);
        }, 300);
      });
    });
  },
};
```

## Debugging Behaviors

### List Registered Behaviors

```javascript
// In browser console:
console.log(Object.keys(Drupal.behaviors));
```

### Manually Trigger Behaviors

```javascript
// Re-attach behaviors to an element
Drupal.attachBehaviors(document.querySelector('#my-element'));

// Detach behaviors from an element
Drupal.detachBehaviors(document.querySelector('#my-element'));
```

### Debug once() State

```javascript
// Check which elements have been processed
const processed = once.find('my-behavior');
console.log('Processed elements:', processed);
```

## Library Definition

```yaml
# mytheme.libraries.yml
my-component:
  js:
    js/my-component.js: {}
  dependencies:
    - core/drupal        # Required: provides Drupal object
    - core/once          # Required: provides once()
    - core/drupal.ajax   # Optional: if using Ajax commands
```

**Common dependencies:**

| Library | Provides |
|---------|----------|
| `core/drupal` | `Drupal` object, `Drupal.behaviors`, `Drupal.t()`, `Drupal.checkPlain()` |
| `core/once` | `once()` API |
| `core/drupal.ajax` | Ajax framework, `Drupal.Ajax`, `Drupal.AjaxCommands` |
| `core/drupalSettings` | `drupalSettings` global |
| `core/drupal.dialog` | Dialog API |
| `core/drupal.dialog.ajax` | Ajax dialog commands |

## Performance Tips

1. **Always use `once()`** — prevents duplicate initialization
2. **Query within `context`** — don't search the whole document
3. **Use event delegation** — one listener on parent vs many on children
4. **Debounce/throttle** — for scroll, resize, input events
5. **Use `requestAnimationFrame()`** — for visual updates
6. **Lazy initialize** — use Intersection Observer for below-fold content
7. **Clean up in `detach()`** — remove timers, observers, event listeners when content is removed
