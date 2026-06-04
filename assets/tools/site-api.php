<?php

/**
 * @file
 * Live site-API extractor for the drupal-agentic-workflow.
 *
 * Run via Drush against a bootstrapped site:
 *
 *   drush php:script .claude/tools/site-api.php
 *
 * (normally invoked through .claude/tools/site-api.sh, which resolves the
 * right Drush runner and redirects stdout to .claude/site-api.json).
 *
 * Emits a JSON index of the GROUND TRUTH of this specific site so the agent
 * can verify identifiers BEFORE generating code instead of hallucinating them:
 * valid service IDs, real entity/bundle/field machine names + types, route
 * names, permissions, and installed modules.
 *
 * SECURITY: this reads DEFINITIONS only — never config values, State, settings,
 * or secret entities. Machine names and types are not sensitive; values would
 * be. Do not add anything here that dumps config/state values.
 *
 * Defaults (see the spec): include everything (core included), mark base fields
 * rather than dropping them, operate on the default site. JSON, not Markdown,
 * because this artifact is queried (grep/jq), never read whole.
 */

declare(strict_types=1);

use Drupal\Core\Entity\ContentEntityTypeInterface;

$etm   = \Drupal::entityTypeManager();
$efm   = \Drupal::service('entity_field.manager');
$binfo = \Drupal::service('entity_type.bundle.info');
$rprov = \Drupal::service('router.route_provider');
$pperm = \Drupal::service('user.permissions');
$mlist = \Drupal::service('extension.list.module');

$out = [
  'meta' => [
    'generated_at'   => date('c'),
    'drupal_version' => \Drupal::VERSION,
    'site_uri'       => \Drupal::hasRequest()
      ? \Drupal::request()->getSchemeAndHttpHost()
      : NULL,
    'schema_version' => 1,
  ],
  // (a) Valid service IDs — the anti-hallucination list (IDs only, sorted).
  'services'     => [],
  // (b) Entity types → group, class, provider, bundle entity, fieldable flag.
  'entity_types' => [],
  // (c) Bundles + their REAL fields (the highest-value section).
  'bundles'      => [],
  // (d) Routes: name → path / methods / handler / required permission.
  'routes'       => [],
  // (e) Permissions: name → title / provider.
  'permissions'  => [],
  // (f) Installed modules + versions (what is available to reuse).
  'modules'      => [],
];

// (a) Service IDs.
$service_ids = \Drupal::getContainer()->getServiceIds();
sort($service_ids);
$out['services'] = array_values($service_ids);

// (b) Entity types.
foreach ($etm->getDefinitions() as $id => $type) {
  $out['entity_types'][$id] = [
    'group'     => $type->getGroup(),
    'class'     => $type->getClass(),
    'provider'  => $type->getProvider(),
    'bundle_of' => $type->getBundleEntityType(),
    'fieldable' => $type instanceof ContentEntityTypeInterface,
  ];
}

// (c) Bundles + fields (content entities only — config entities have no fields).
foreach ($binfo->getAllBundleInfo() as $entity_type_id => $bundles) {
  $definition = $etm->getDefinition($entity_type_id, FALSE);
  if (!$definition instanceof ContentEntityTypeInterface) {
    continue;
  }
  foreach ($bundles as $bundle_id => $info) {
    $fields = [];
    try {
      $defs = $efm->getFieldDefinitions($entity_type_id, $bundle_id);
    }
    catch (\Exception $e) {
      continue;
    }
    foreach ($defs as $name => $def) {
      $storage = $def->getFieldStorageDefinition();
      $handler = $def->getSetting('handler_settings');
      $fields[$name] = [
        'type'           => $def->getType(),
        'label'          => (string) $def->getLabel(),
        'required'       => $def->isRequired(),
        'cardinality'    => $storage->getCardinality(),
        'base'           => $storage->isBaseField(),
        'target_type'    => $def->getSetting('target_type'),
        'target_bundles' => is_array($handler) ? ($handler['target_bundles'] ?? NULL) : NULL,
      ];
    }
    $out['bundles']["$entity_type_id.$bundle_id"] = [
      'entity_type' => $entity_type_id,
      'label'       => (string) ($info['label'] ?? $bundle_id),
      'fields'      => $fields,
    ];
  }
}

// (d) Routes.
foreach ($rprov->getAllRoutes() as $name => $route) {
  $out['routes'][$name] = [
    'path'       => $route->getPath(),
    'methods'    => $route->getMethods(),
    'handler'    => $route->getDefault('_controller')
      ?? $route->getDefault('_form')
      ?? $route->getDefault('_entity_form')
      ?? $route->getDefault('_entity_view'),
    'permission' => $route->getRequirement('_permission'),
  ];
}

// (e) Permissions.
foreach ($pperm->getPermissions() as $name => $permission) {
  $out['permissions'][$name] = [
    'title'    => trim(strip_tags((string) $permission['title'])),
    'provider' => $permission['provider'] ?? NULL,
  ];
}

// (f) Installed modules.
foreach ($mlist->getAllInstalledInfo() as $name => $info) {
  $out['modules'][$name] = [
    'version' => $info['version'] ?? NULL,
    'package' => $info['package'] ?? NULL,
  ];
}

print json_encode($out, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
print "\n";
