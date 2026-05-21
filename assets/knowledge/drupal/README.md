# Drupal version-aware knowledge templates

This directory holds per-Drupal-version guidance templates that the project setup script renders into `.claude/drupal-version-guide.md` so that Claude has accurate, version-specific context for the codebase it's working on.

## Directory layout

```
assets/knowledge/drupal/
├── README.md          ← this file (maintainers only)
├── 10.3/
│   └── guide.md       ← Drupal 10.3 LTS deltas
├── 10.4/
│   └── guide.md       ← Drupal 10.4 standard release deltas
└── 11.x/
    └── guide.md       ← Drupal 11.x deltas
```

Each `<version>/guide.md` is a static Markdown file with **no templating placeholders**. The setup script copies the selected file verbatim into the consuming project's `.claude/drupal-version-guide.md`.

## Required section structure

Every `guide.md` MUST use the following headings, in this order:

1. `Required APIs`
2. `Deprecated patterns to avoid`
3. `OOP hook policy`
4. `Plugin attribute policy`
5. `Test base classes`
6. `Minimum PHP`

Uniform headings let the rendered output stay predictable regardless of which version is selected — downstream tooling and humans both know exactly where to look.

## Version-specific deltas only

These templates contain **deltas, not general Drupal advice**:

- Generic Drupal coding standards, security practices, render API basics, etc. live in the project's `CLAUDE-TEMPLATE.md` and in the existing Claude skills (`drupal-expert`, `entity`, `drupal-security`, etc.).
- Each `guide.md` should describe only what differs in that version — new APIs introduced, patterns removed, minimum PHP, hook/plugin policy shifts, etc.
- Keep each section to **5–10 bullets**. If a section grows beyond that, it probably contains generic guidance that belongs in a skill instead.

## How the setup script selects a template

The setup script detects the project's Drupal core version (typically by reading `composer.lock` or `web/core/composer.json`) and maps the **major.minor** version to a directory:

| Detected version    | Template selected         |
|---------------------|---------------------------|
| `10.3.x`            | `10.3/guide.md`           |
| `10.4.x`            | `10.4/guide.md`           |
| `11.0.x` and later  | `11.x/guide.md`           |

If no matching directory exists, the setup script falls back to the highest available version less than or equal to the detected one and logs a warning.

## Adding a new version

When Drupal releases a new minor or major (e.g. `10.5`, `11.1`, `12.0`):

1. Copy the closest existing template:
   ```sh
   cp -r assets/knowledge/drupal/11.x assets/knowledge/drupal/12.x
   ```
2. Edit `guide.md` and replace its contents with **only the deltas** from the previous version. Keep the six required headings in order.
3. Update the version-selection table above with the new mapping.
4. Update the setup script's version-matching logic (see Task 3 in the plan that introduced this directory) if the new version is not covered by the existing matcher.
5. Open a PR — no other files in this repo should need changes.

## Removing a version

Drop the directory once the version is end-of-life **and** no consumer project is still on it. Update the table above. Do not retain stale guidance — out-of-date version notes are worse than none.
