# External systems

> Where integrations live, where credentials are stored, what IDs to use.
> **Never paste actual secrets here.** This file lists *where to find them* — typically `web/sites/default/settings.local.php` or `.ddev/.env` locally; environment variables in production.

## CommerceTools

- **API base URL**: <!-- e.g. https://api.europe-west1.gcp.commercetools.com -->
- **Project key**: defined in `settings.local.php` as `$config['va_commercetools.settings']['project_key']`
- **Client ID / secret**: `settings.local.php` (`...['client_id']`, `...['client_secret']`)
- **Catalog/sync direction**: products & variants pulled at runtime; no sync to Drupal DB

## HubSpot

- **Portal ID**: <!-- where it lives -->
- **Forms endpoint**: <!-- ... -->
- **Auth**: <!-- private app token in settings.local.php -->

## Payment gateways

### Ingenico
- Sandbox vs production toggle: `va_payment_ingenico.settings.environment`
- Test cards: see `.claude/test-fixtures.md`

### PayPal
- Sandbox toggle: <!-- ... -->
- Webhook URL local: <!-- via ngrok/expose -->

## Solr

- **Core name**: `drupal_content`
- **Local URL**: `http://solr:8983` (DDEV container `ddev-<project>-solr-1`)
- **Indexed types**: Article, FAQ, Media, Product variants
- **Config files** (dictionaries, not Drupal config): `config-set/`, copied into the Solr container after `bin/solr create`

## Analytics / Marketing

- **GA4 / GTM**: container ID in `va_gtm.settings.container_id`; consent-gated by `va_cookie_consent`
- **Cookie banner**: `va_cookie_consent` module + `drupal/cookies` contrib

## Hosting / Deploy

- **Acquia Cloud**: env names — dev, stage, prod
- **Branch → env**:
  - `develop` → `develop.vitalaire.oterma.factorial.io` (internal review)
  - `release` → client review
  - `main` → production
- **CI/CD**: `.gitlab-ci.yml`, `.gitlab-ci.factorial.yml`, `.gitlab-cia.yml` (Acquia)

## Local dev

- **DDEV project URL**: `https://<project>.ddev.site`
- **Mail catcher**: MailHog at `https://<project>.ddev.site:8026`
- **Apple Silicon note**: `solr:6` and `mailhog/mailhog:v1.0.0` are amd64-only — `.ddev/docker-compose.override.yaml` sets `platform: linux/amd64`

<!-- Add additional systems as integrations grow. -->
