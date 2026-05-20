# Test fixtures

> Demo accounts, payment test cards, seed content for local verification.
> **Never put production credentials here.** Local DDEV / sandbox only.

## Local users (DDEV)

| Role | Username | Password | UID | Notes |
|------|----------|----------|-----|-------|
| Admin | <!-- --> | <!-- --> | 1 | created by `drush si` |
| Editor | <!-- --> | <!-- --> | <!-- --> | |
| Patient | <!-- --> | <!-- --> | <!-- --> | |

Login fast: `ddev drush uli` (admin) or `ddev drush uli --uid=<n>`.

## Payment sandboxes

### Ingenico (sandbox)
- Test card success: <!-- 4111 1111 1111 1111 / any future expiry / any CVC -->
- Test card decline: <!-- ... -->

### PayPal (sandbox)
- Test buyer: <!-- email + password -->
- Test merchant: <!-- ... -->

## Seed content (after `phab -cddev copy-from`)

- Demo therapy nodes: <!-- node IDs or list -->
- Demo orders: <!-- ... -->
- Demo Infothek articles: <!-- ... -->

## Reset to clean state

```bash
ddev drush sql:drop -y
phab -cddev copy-from develop.vitalaire.oterma.factorial.io
ddev drush cr && ddev drush cim && ddev drush cr
```
