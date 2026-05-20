#!/usr/bin/env node
// Zero-dep project-fact scanner. Reads Drupal config + custom module YAMLs and
// builds .claude/project-map.md — a structural overview the agent can grep
// instead of probing the codebase.
//
// Usage:
//   node .claude/tools/project-map.mjs           # writes .claude/project-map.md
//   node .claude/tools/project-map.mjs --print   # also prints to stdout
//
// Extracts (via regex; no Drush required):
//   - Content types and their fields
//   - User roles and permission grants
//   - Routes per custom module
//   - Services per custom module
//   - Config splits

import {
  readFileSync,
  readdirSync,
  writeFileSync,
  existsSync,
  mkdirSync,
} from 'node:fs';
import { join, basename } from 'node:path';

const ROOT = process.cwd();
const args = new Set(process.argv.slice(2));

const SKIP = new Set([
  'node_modules',
  'vendor',
  '.git',
  'dist',
  'build',
  'core',
]);

function readText(p) {
  try {
    return readFileSync(p, 'utf8');
  } catch {
    return null;
  }
}
function readJson(p) {
  try {
    return JSON.parse(readFileSync(p, 'utf8'));
  } catch {
    return null;
  }
}
const unquote = (s) => (s ? s.trim().replace(/^['"]|['"]$/g, '') : s);

function walk(dir, pattern, out = []) {
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const e of entries) {
    if (SKIP.has(e.name)) continue;
    const full = join(dir, e.name);
    if (e.isDirectory()) walk(full, pattern, out);
    else if (pattern.test(e.name)) out.push(full);
  }
  return out;
}

// ---------- locate paths ----------
const stack = readJson(join(ROOT, '.claude', 'stack.json'));
const customCodePaths = [
  stack?.backend?.custom_modules_path,
  'web/modules/custom',
  'docroot/modules/custom',
  'docroot/profiles/vitalaire/modules',
  'modules/custom',
]
  .filter(Boolean)
  .filter((p) => existsSync(join(ROOT, p)));

const configPaths = [
  'config/sync',
  'config/default',
  'config/dev',
  'config/test',
  'config/prod',
].filter((p) => existsSync(join(ROOT, p)));

// ---------- extractors (regex, no YAML parser dep) ----------

// Content types: node.type.<id>.yml has `type: <id>` and `name: <label>`.
function extractContentTypes() {
  const types = [];
  for (const cp of configPaths) {
    const files = walk(join(ROOT, cp), /^node\.type\.[^.]+\.yml$/);
    for (const f of files) {
      const text = readText(f) || '';
      const id = text.match(/^type:\s*(.+)$/m)?.[1]?.trim();
      const label = unquote(text.match(/^name:\s*(.+)$/m)?.[1]);
      const description =
        unquote(text.match(/^description:\s*(.+)$/m)?.[1]) || '';
      if (id && !types.find((t) => t.id === id)) {
        types.push({ id, label: label || id, description, source: cp });
      }
    }
  }
  return types.sort((a, b) => a.id.localeCompare(b.id));
}

// Fields per bundle: field.field.<entity>.<bundle>.<field>.yml
function extractFields() {
  const fields = {};
  for (const cp of configPaths) {
    const files = walk(
      join(ROOT, cp),
      /^field\.field\.[^.]+\.[^.]+\.[^.]+\.yml$/,
    );
    for (const f of files) {
      const parts = basename(f, '.yml').split('.');
      if (parts.length !== 5) continue;
      const [, , entity, bundle, fieldName] = parts;
      const text = readText(f) || '';
      const fieldType = text.match(/^field_type:\s*(.+)$/m)?.[1]?.trim() || '?';
      const required = /^required:\s*true/m.test(text);
      const key = `${entity}.${bundle}`;
      (fields[key] ||= []).push({ name: fieldName, type: fieldType, required });
    }
  }
  for (const k of Object.keys(fields))
    fields[k].sort((a, b) => a.name.localeCompare(b.name));
  return fields;
}

// Roles + permissions: user.role.<id>.yml has `id:`, `label:`, and `permissions:` list.
function extractRoles() {
  const roles = [];
  for (const cp of configPaths) {
    const files = walk(join(ROOT, cp), /^user\.role\.[^.]+\.yml$/);
    for (const f of files) {
      const text = readText(f) || '';
      const id = text.match(/^id:\s*(.+)$/m)?.[1]?.trim();
      const label = unquote(text.match(/^label:\s*(.+)$/m)?.[1]);
      if (!id || roles.find((r) => r.id === id)) continue;
      // permissions: - 'perm one' \n  - 'perm two'
      const permBlock = text.split(/^permissions:\s*$/m)[1] || '';
      const perms = [
        ...permBlock.matchAll(/^\s+-\s*['"]?([^'"\n]+)['"]?\s*$/gm),
      ]
        .map((m) => m[1].trim())
        .filter(Boolean);
      roles.push({
        id,
        label: label || id,
        permission_count: perms.length,
        permissions: perms,
      });
    }
  }
  return roles.sort((a, b) => a.id.localeCompare(b.id));
}

// Routes: per custom module's *.routing.yml — top-level keys are route names.
function extractRoutes() {
  const routes = [];
  for (const cp of customCodePaths) {
    const files = walk(join(ROOT, cp), /\.routing\.yml$/);
    for (const f of files) {
      const text = readText(f) || '';
      const module = basename(f, '.routing.yml');
      // Top-level keys at column 0 (Drupal route names allow dots and underscores).
      const routeNames = [
        ...text.matchAll(/^([a-zA-Z_][a-zA-Z0-9_.]*):\s*$/gm),
      ].map((m) => m[1]);
      for (const name of routeNames) {
        // Try to find the path: line under this route.
        const reBlock = new RegExp(
          `^${name.replace(/\./g, '\\.')}:\\s*$([\\s\\S]*?)(?=^[a-zA-Z_][\\w.]*:\\s*$|\\Z)`,
          'm',
        );
        const block = text.match(reBlock)?.[1] || '';
        const path = block
          .match(/^\s+path:\s*['"]?([^'"\n]+)['"]?/m)?.[1]
          ?.trim();
        const controller = block
          .match(/^\s+_controller:\s*['"]?([^'"\n]+)['"]?/m)?.[1]
          ?.trim();
        const form = block
          .match(/^\s+_form:\s*['"]?([^'"\n]+)['"]?/m)?.[1]
          ?.trim();
        routes.push({
          module,
          name,
          path: path || '?',
          controller: controller || form || '?',
        });
      }
    }
  }
  return routes.sort(
    (a, b) => a.module.localeCompare(b.module) || a.name.localeCompare(b.name),
  );
}

// Services: per custom module's *.services.yml — keys under `services:`.
function extractServices() {
  const services = [];
  for (const cp of customCodePaths) {
    const files = walk(join(ROOT, cp), /\.services\.yml$/);
    for (const f of files) {
      const text = readText(f) || '';
      const module = basename(f, '.services.yml');
      // Two-space indented keys under `services:`.
      const servicesBlock = text.split(/^services:\s*$/m)[1] || '';
      const ids = [
        ...servicesBlock.matchAll(/^  ([a-zA-Z_][a-zA-Z0-9_.]*):\s*$/gm),
      ].map((m) => m[1]);
      for (const id of ids) {
        const reBlock = new RegExp(
          `^  ${id.replace(/\./g, '\\.')}:\\s*$([\\s\\S]*?)(?=^  [a-zA-Z_][\\w.]*:|\\Z)`,
          'm',
        );
        const block = servicesBlock.match(reBlock)?.[1] || '';
        const cls = block
          .match(/^\s+class:\s*['"]?([^'"\n]+)['"]?/m)?.[1]
          ?.trim();
        services.push({ module, id, class: cls || '?' });
      }
    }
  }
  return services.sort(
    (a, b) => a.module.localeCompare(b.module) || a.id.localeCompare(b.id),
  );
}

// Config splits: config_split.config_split.<id>.yml
function extractConfigSplits() {
  const splits = [];
  for (const cp of configPaths) {
    const files = walk(
      join(ROOT, cp),
      /^config_split\.config_split\.[^.]+\.yml$/,
    );
    for (const f of files) {
      const text = readText(f) || '';
      const id = text.match(/^id:\s*(.+)$/m)?.[1]?.trim();
      const label = unquote(text.match(/^label:\s*(.+)$/m)?.[1]);
      const folder = unquote(text.match(/^folder:\s*(.+)$/m)?.[1]);
      const status = text.match(/^status:\s*(true|false)$/m)?.[1] === 'true';
      if (id && !splits.find((s) => s.id === id && s.source === cp)) {
        splits.push({
          id,
          label: label || id,
          folder: folder || '?',
          status,
          source: cp,
        });
      }
    }
  }
  return splits.sort((a, b) => a.id.localeCompare(b.id));
}

// ---------- render ----------
const contentTypes = extractContentTypes();
const fieldsByBundle = extractFields();
const roles = extractRoles();
const routes = extractRoutes();
const services = extractServices();
const splits = extractConfigSplits();

const lines = [];
lines.push(`# Project map — ${stack?.project?.name || basename(ROOT)}`);
lines.push('');
lines.push(
  '> Auto-generated by drupal-agentic-workflow. Re-run `setup.sh` to refresh.',
);
lines.push(
  '> Source: YAML config + custom module declarations (no Drush required).',
);
lines.push('');

// Content model
lines.push('## Content types');
lines.push('');
if (contentTypes.length === 0) {
  lines.push('_None found in scanned config paths._');
} else {
  lines.push('| Type | Label | Fields | Description |');
  lines.push('|------|-------|--------|-------------|');
  for (const t of contentTypes) {
    const fcount = (fieldsByBundle[`node.${t.id}`] || []).length;
    lines.push(
      `| \`${t.id}\` | ${t.label} | ${fcount} | ${t.description || '—'} |`,
    );
  }
  // Field details per type (collapsed under details for terseness).
  lines.push('');
  lines.push('### Fields per content type');
  for (const t of contentTypes) {
    const flist = fieldsByBundle[`node.${t.id}`] || [];
    if (flist.length === 0) continue;
    lines.push('');
    lines.push(`**\`${t.id}\`** (${flist.length} fields)`);
    lines.push('');
    for (const f of flist) {
      lines.push(
        `- \`${f.name}\` — ${f.type}${f.required ? ' *(required)*' : ''}`,
      );
    }
  }
}
lines.push('');

// Roles
lines.push('## Roles & permissions');
lines.push('');
if (roles.length === 0) {
  lines.push('_No user.role.*.yml found._');
} else {
  lines.push('| Role | Label | Permissions granted |');
  lines.push('|------|-------|---------------------|');
  for (const r of roles) {
    lines.push(`| \`${r.id}\` | ${r.label} | ${r.permission_count} |`);
  }
}
lines.push('');

// Routes
lines.push('## Routes (custom modules)');
lines.push('');
if (routes.length === 0) {
  lines.push('_No routing.yml files found in custom modules._');
} else {
  lines.push('| Module | Route | Path | Handler |');
  lines.push('|--------|-------|------|---------|');
  for (const r of routes.slice(0, 200)) {
    lines.push(
      `| \`${r.module}\` | \`${r.name}\` | \`${r.path}\` | \`${r.controller}\` |`,
    );
  }
  if (routes.length > 200)
    lines.push(`\n_(${routes.length - 200} more routes truncated)_`);
}
lines.push('');

// Services
lines.push('## Services (custom modules)');
lines.push('');
if (services.length === 0) {
  lines.push('_No services.yml entries found._');
} else {
  lines.push('| Module | Service ID | Class |');
  lines.push('|--------|------------|-------|');
  for (const s of services.slice(0, 200)) {
    lines.push(`| \`${s.module}\` | \`${s.id}\` | \`${s.class}\` |`);
  }
  if (services.length > 200)
    lines.push(`\n_(${services.length - 200} more services truncated)_`);
}
lines.push('');

// Config splits
lines.push('## Config splits');
lines.push('');
if (splits.length === 0) {
  lines.push('_None found — single-config-directory setup._');
} else {
  lines.push('| Split | Label | Folder | Status | Source |');
  lines.push('|-------|-------|--------|--------|--------|');
  for (const s of splits) {
    lines.push(
      `| \`${s.id}\` | ${s.label} | \`${s.folder}\` | ${s.status ? 'active' : 'inactive'} | ${s.source} |`,
    );
  }
}
lines.push('');

const out = lines.join('\n');
mkdirSync(join(ROOT, '.claude'), { recursive: true });
writeFileSync(join(ROOT, '.claude', 'project-map.md'), out);

if (args.has('--print')) {
  console.log(out);
} else {
  console.log(
    `Wrote .claude/project-map.md (${contentTypes.length} types, ${roles.length} roles, ${routes.length} routes, ${services.length} services, ${splits.length} splits)`,
  );
}
