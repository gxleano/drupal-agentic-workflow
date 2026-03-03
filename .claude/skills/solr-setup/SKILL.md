---
name: solr-setup
description: Setup and troubleshoot local Solr search for DDEV environment
version: 1.0.0
---

You are a Solr search setup assistant for Drupal 11 on DDEV.

## Determine What the User Needs

1. **Install** — Add Solr to the DDEV environment
2. **Configure** — Connect Drupal Search API to Solr
3. **Troubleshoot** — Fix connection or indexing issues
4. **Manage** — Reindex, clear index, check status

## Installation

### 1. Add DDEV Solr Add-on

```bash
ddev add-on get ddev/ddev-solr
ddev restart
```

Solr UI will be available at: `https://{DDEV_SITE_URL}:8983`

### 2. Install Drupal Modules

```bash
ddev composer require drupal/search_api drupal/search_api_solr
ddev drush pm:enable search_api search_api_solr -y
ddev drush cr
```

### 3. Configure Solr Server

Create a Search API server at `/admin/config/search/search-api/add-server`:

| Setting | Value |
|---------|-------|
| Backend | Solr |
| Solr Connector | Standard |
| HTTP Protocol | http |
| Solr host | solr |
| Solr port | 8983 |
| Solr path | / |
| Solr core | drupal |

### 4. Upload Config Files

```bash
# Generate Solr config from Drupal
ddev drush search-api-solr:get-server-config SEARCH_API_SERVER_ID /tmp/solr-config.zip

# Extract to Solr configset directory
ddev exec bash -c "cd /var/solr/data/drupal/conf && unzip -o /tmp/solr-config.zip"

# Restart Solr to load new config
ddev restart
```

### 5. Create Search Index

Create a Search API index at `/admin/config/search/search-api/add-index`:
- Select content types to index
- Add fields for indexing
- Configure processors (HTML filter, tokenizer, stemmer)

### 6. Index Content

```bash
ddev drush search-api:index
ddev drush search-api:status
```

## Troubleshooting

### Connection Refused

```bash
# Check Solr is running
ddev describe | grep solr
ddev exec curl -s http://solr:8983/solr/admin/cores?action=STATUS

# Restart if needed
ddev restart
```

### Core Not Found

```bash
# List available cores
ddev exec curl -s http://solr:8983/solr/admin/cores?action=STATUS | python3 -m json.tool

# Create core manually
ddev exec solr create_core -c drupal
```

### Indexing Issues

```bash
# Check index status
ddev drush search-api:status

# Clear and reindex
ddev drush search-api:clear INDEX_ID
ddev drush search-api:index INDEX_ID

# Check for errors
ddev drush watchdog:show --type=search_api --count=20
```

### Schema Mismatch After Drupal Update

```bash
# Regenerate and re-upload config
ddev drush search-api-solr:get-server-config SERVER_ID /tmp/solr-config.zip
ddev exec bash -c "cd /var/solr/data/drupal/conf && unzip -o /tmp/solr-config.zip"
ddev restart
ddev drush search-api:rebuild-tracker
ddev drush search-api:index
```

## Quick Reference

```bash
# Status
ddev drush search-api:status                    # All indexes
ddev drush search-api:server-list               # All servers

# Indexing
ddev drush search-api:index                     # Index all
ddev drush search-api:index INDEX_ID --limit=100  # Limited
ddev drush search-api:clear INDEX_ID            # Clear index

# Maintenance
ddev drush search-api:rebuild-tracker           # Fix tracking table
ddev drush search-api:reset-tracker             # Reset all tracking

# Solr direct
ddev exec curl -s "http://solr:8983/solr/drupal/select?q=*:*&rows=0"  # Count docs
ddev exec curl -s "http://solr:8983/solr/drupal/admin/luke"             # Schema info
```

## Related Skills

- **ddev** — Environment management and service debugging
- **drupal-expert** — Drupal module installation and configuration patterns
