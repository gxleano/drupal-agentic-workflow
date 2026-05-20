#!/usr/bin/env node
// Zero-dep convention scanner. Reads .claude/stack.json (for custom_modules_path),
// scans PHP + a bit of CSS/JS under custom code, and writes .claude/conventions.md
// summarising which idioms this codebase actually uses.
//
// Usage:
//   node .claude/tools/conventions.mjs            # writes .claude/conventions.md
//   node .claude/tools/conventions.mjs --print    # also prints summary to stdout

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

// ---------- locate code paths ----------
function readStack() {
  try {
    return JSON.parse(
      readFileSync(join(ROOT, '.claude', 'stack.json'), 'utf8'),
    );
  } catch {
    return null;
  }
}

const stack = readStack();
const customCodePaths = [
  stack?.backend?.custom_modules_path,
  'web/modules/custom',
  'docroot/modules/custom',
  'docroot/profiles/vitalaire/modules',
  'modules/custom',
]
  .filter(Boolean)
  .filter((p) => existsSync(join(ROOT, p)));

if (customCodePaths.length === 0) {
  console.error('No custom code paths found — nothing to scan.');
  process.exit(0);
}

// ---------- file walker ----------
const SKIP = new Set([
  'node_modules',
  'vendor',
  '.git',
  'dist',
  'build',
  'tests',
]);
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

const phpFiles = customCodePaths.flatMap((p) =>
  walk(join(ROOT, p), /\.(php|module|install|theme)$/),
);
const cssFiles = customCodePaths.flatMap((p) =>
  walk(join(ROOT, p), /\.(css|scss)$/),
);
const jsFiles = customCodePaths.flatMap((p) => walk(join(ROOT, p), /\.js$/));
const componentYml = customCodePaths.flatMap((p) =>
  walk(join(ROOT, p), /\.component\.yml$/),
);
const moduleFiles = phpFiles.filter((f) => /\.module$/.test(f));
const installedHookAttrFiles = phpFiles.filter((f) => f.includes('/src/Hook/'));

// ---------- counters ----------
const c = {
  php_total: phpFiles.length,
  with_strict_types: 0,
  with_namespace: 0,
  module_hook_functions: 0,
  attr_hook_classes: 0,
  attr_hook_methods: 0,
  match_uses: 0,
  switch_uses: 0,
  static_create: 0,
  self_create: 0,
  ctor_promotion: 0,
  readonly_props: 0,
  classic_property_decl: 0,
  drupal_static_calls: 0,
  drupal_static_in_services: 0,
  autowire_trait: 0,
  final_class: 0,
  block_attribute: 0,
  block_annotation: 0,
  entity_query_no_accesscheck: 0,
  drupal_behaviors: 0,
  drupal_behaviors_files: new Set(),
};

const phpServicesDirs = [/\/src\/(Service|Services|Plugin)\//];

for (const file of phpFiles) {
  let text;
  try {
    text = readFileSync(file, 'utf8');
  } catch {
    continue;
  }

  if (
    /^<\?php\s*[\s\S]{0,200}declare\s*\(\s*strict_types\s*=\s*1\s*\)/m.test(
      text,
    )
  )
    c.with_strict_types++;
  if (/^namespace\s+\S+;/m.test(text)) c.with_namespace++;

  // hooks
  if (/\.module$/.test(file)) {
    const fnName = basename(file, '.module');
    const matches = text.match(
      new RegExp(`function\\s+${fnName}_[a-z_]+\\s*\\(`, 'g'),
    );
    if (matches) c.module_hook_functions += matches.length;
  }
  if (file.includes('/src/Hook/')) {
    if (/#\[Hook\(/m.test(text)) c.attr_hook_classes++;
    const methodHooks = text.match(/#\[Hook\(/g);
    if (methodHooks) c.attr_hook_methods += methodHooks.length;
  }

  // language features
  c.match_uses += (text.match(/\bmatch\s*\(/g) || []).length;
  c.switch_uses += (text.match(/\bswitch\s*\(/g) || []).length;
  c.static_create += (text.match(/return\s+static::/g) || []).length;
  c.self_create += (text.match(/return\s+self::/g) || []).length;

  // DI patterns — look only inside constructors
  const ctorBlocks =
    text.match(/public\s+function\s+__construct\s*\([\s\S]*?\)\s*\{/g) || [];
  for (const ctor of ctorBlocks) {
    if (
      /(protected|private|public)\s+(readonly\s+)?[A-Za-z_\\]+\s+\$/.test(ctor)
    )
      c.ctor_promotion++;
  }
  c.readonly_props += (
    text.match(/\b(protected|private|public)\s+readonly\s+/g) || []
  ).length;
  c.classic_property_decl += (
    text.match(
      /^\s*(protected|private)\s+[A-Za-z_\\][A-Za-z0-9_\\]*\s+\$[a-zA-Z_]/gm,
    ) || []
  ).length;

  // \Drupal:: in services / plugins (anti-pattern)
  const drupalCalls = (text.match(/\\Drupal::/g) || []).length;
  c.drupal_static_calls += drupalCalls;
  if (phpServicesDirs.some((re) => re.test(file)) && drupalCalls > 0)
    c.drupal_static_in_services += drupalCalls;

  if (/use\s+AutowireTrait;/.test(text)) c.autowire_trait++;
  if (/^final\s+class\s/m.test(text)) c.final_class++;

  // plugin attribute vs annotation
  if (/#\[Block\(/.test(text)) c.block_attribute++;
  if (/@Block\(/.test(text)) c.block_annotation++;

  // entity query without accessCheck
  for (const m of text.matchAll(
    /->getStorage\(['"]\w+['"]\)\s*->getQuery\([^)]*\)([\s\S]{0,300}?)->execute\(\)/g,
  )) {
    if (!/accessCheck\s*\(/.test(m[1])) c.entity_query_no_accesscheck++;
  }
}

for (const file of jsFiles) {
  let text;
  try {
    text = readFileSync(file, 'utf8');
  } catch {
    continue;
  }
  const m = text.match(/Drupal\.behaviors\.[A-Za-z_]+/g);
  if (m) {
    c.drupal_behaviors += m.length;
    c.drupal_behaviors_files.add(file);
  }
}

// BEM-ish: look for double-underscore or double-dash class selectors
let bemHits = 0,
  totalCssClasses = 0;
for (const file of cssFiles) {
  let text;
  try {
    text = readFileSync(file, 'utf8');
  } catch {
    continue;
  }
  const classes = text.match(/\.[a-zA-Z][\w-]*/g) || [];
  totalCssClasses += classes.length;
  bemHits += classes.filter((cls) => /__|--/.test(cls)).length;
}
const bemRatio = totalCssClasses > 0 ? bemHits / totalCssClasses : 0;

// ---------- helpers ----------
const pct = (num, denom) => (denom > 0 ? Math.round((num / denom) * 100) : 0);
const verdict = (ratio, threshold = 0.7) =>
  ratio >= threshold
    ? '**dominant**'
    : ratio >= 0.3
      ? 'mixed'
      : ratio > 0
        ? 'sparse'
        : 'absent';

const hookStyle =
  c.module_hook_functions + c.attr_hook_methods > 0
    ? c.attr_hook_methods >= c.module_hook_functions
      ? 'attributes'
      : '.module functions'
    : 'no hooks found';

const lines = [];
lines.push(`# Code conventions — ${stack?.project?.name || basename(ROOT)}`);
lines.push('');
lines.push(
  '> Generated by drupal-agentic-workflow. Re-run `setup.sh` to refresh.',
);
lines.push(
  `> Scanned ${c.php_total} PHP file(s), ${jsFiles.length} JS, ${cssFiles.length} CSS/SCSS across ${customCodePaths.length} custom path(s).`,
);
lines.push('');
lines.push('## PHP conventions');
lines.push('');
lines.push('| Convention | Adoption | Verdict |');
lines.push('|---|---|---|');
lines.push(
  `| \`declare(strict_types=1)\` | ${c.with_strict_types}/${c.php_total} (${pct(c.with_strict_types, c.php_total)}%) | ${verdict(c.with_strict_types / Math.max(c.php_total, 1))} |`,
);
lines.push(
  `| Hook style | \`.module\`: ${c.module_hook_functions}, \`#[Hook]\`: ${c.attr_hook_methods} | dominant: **${hookStyle}** |`,
);
lines.push(
  `| Constructor property promotion | ${c.ctor_promotion} ctor(s) | ${c.ctor_promotion > 0 ? 'in use' : 'absent'} |`,
);
lines.push(
  `| \`readonly\` properties | ${c.readonly_props} occurrence(s) | ${verdict(c.readonly_props / Math.max(c.ctor_promotion, 1))} |`,
);
lines.push(
  `| Classic property declarations (non-promoted) | ${c.classic_property_decl} | — |`,
);
lines.push(
  `| \`match\` vs \`switch\` | ${c.match_uses} match / ${c.switch_uses} switch | dominant: **${c.match_uses > c.switch_uses ? 'match' : 'switch'}** |`,
);
lines.push(
  `| Factory return style | \`static::\`: ${c.static_create}, \`self::\`: ${c.self_create} | dominant: **${c.static_create >= c.self_create ? 'static' : 'self'}** |`,
);
lines.push(
  `| \`AutowireTrait\` adoption | ${c.autowire_trait} class(es) | ${c.autowire_trait > 0 ? 'in use' : 'absent'} |`,
);
lines.push(
  `| \`final class\` declarations | ${c.final_class} | ${verdict(c.final_class / Math.max(c.php_total, 1), 0.2)} |`,
);
lines.push(
  `| Plugin discovery | \`#[Block]\`: ${c.block_attribute}, \`@Block\`: ${c.block_annotation} | dominant: **${c.block_attribute >= c.block_annotation ? 'attributes' : 'annotations'}** |`,
);
lines.push('');
lines.push('## Anti-patterns detected');
lines.push('');
lines.push('| Pattern | Count | Note |');
lines.push('|---|---|---|');
lines.push(
  `| \`\\\\Drupal::\` static calls (anywhere) | ${c.drupal_static_calls} | should be DI in service classes |`,
);
lines.push(
  `| \`\\\\Drupal::\` inside Service/Plugin classes | ${c.drupal_static_in_services} | **avoid — use constructor injection** |`,
);
lines.push(
  `| Entity queries missing \`->accessCheck()\` | ${c.entity_query_no_accesscheck} | always declare access intent |`,
);
lines.push('');
lines.push('## Frontend conventions');
lines.push('');
lines.push('| Convention | Adoption |');
lines.push('|---|---|');
lines.push(`| SDC components (\`*.component.yml\`) | ${componentYml.length} |`);
lines.push(
  `| \`Drupal.behaviors.*\` | ${c.drupal_behaviors} use(s) in ${c.drupal_behaviors_files.size} file(s) |`,
);
lines.push(
  `| BEM-ish class selectors (\`__\` or \`--\`) | ${bemHits}/${totalCssClasses} (${pct(bemHits, totalCssClasses)}%) — ${verdict(bemRatio, 0.4)} |`,
);
lines.push('');
lines.push('## Guidance for code generation');
lines.push('');

// Synthesise guidance based on counts
const guidance = [];
if (pct(c.with_strict_types, c.php_total) < 70 && c.php_total > 0) {
  guidance.push(
    `- Only ${pct(c.with_strict_types, c.php_total)}% of PHP files declare \`strict_types\`. **Add \`declare(strict_types=1);\` on every new file** to push adoption up.`,
  );
}
if (hookStyle === '.module functions' && c.php_total > 0) {
  guidance.push(
    `- Hooks currently live in \`.module\` files. New hooks should match this style unless migrating; do not mix attribute hooks for the same module without converting all of them.`,
  );
} else if (hookStyle === 'attributes') {
  guidance.push(
    `- Hooks use \`#[Hook]\` attribute classes under \`src/Hook/\`. Continue this pattern — do not add hooks to \`.module\` files.`,
  );
}
if (c.drupal_static_in_services > 0) {
  guidance.push(
    `- ${c.drupal_static_in_services} \`\\Drupal::\` call(s) detected inside service/plugin classes. **Never add new ones** — inject via constructor instead.`,
  );
}
if (c.ctor_promotion > 0 && c.classic_property_decl > c.ctor_promotion) {
  guidance.push(
    `- Constructor promotion is in use (${c.ctor_promotion} ctors) but ${c.classic_property_decl} classic declarations remain. **Use promotion + \`readonly\` for new services.**`,
  );
}
if (c.entity_query_no_accesscheck > 0) {
  guidance.push(
    `- ${c.entity_query_no_accesscheck} entity query(ies) missing \`->accessCheck()\` — always declare \`accessCheck(TRUE|FALSE)\` explicitly.`,
  );
}
if (c.match_uses < c.switch_uses && c.switch_uses > 0) {
  guidance.push(
    `- \`switch\` outnumbers \`match\` (${c.switch_uses} vs ${c.match_uses}). For simple value mapping, prefer \`match\` in new code.`,
  );
}
if (c.block_annotation > c.block_attribute && c.block_annotation > 0) {
  guidance.push(
    `- ${c.block_annotation} plugin(s) still use \`@Block\` annotations. New plugins should use \`#[Block]\` attributes.`,
  );
}
if (componentYml.length === 0 && cssFiles.length > 0) {
  guidance.push(
    `- No SDC components detected. If introducing new frontend components, consider SDC (\`*.component.yml\`) for forward compatibility.`,
  );
}
if (guidance.length === 0) {
  guidance.push(
    '- No major adoption gaps detected. Match existing patterns when adding code.',
  );
}
lines.push(...guidance);
lines.push('');

const out = lines.join('\n');
mkdirSync(join(ROOT, '.claude'), { recursive: true });
writeFileSync(join(ROOT, '.claude', 'conventions.md'), out);

if (args.has('--print')) {
  console.log(out);
} else {
  console.log(
    `Wrote .claude/conventions.md (${c.php_total} PHP, ${jsFiles.length} JS, ${cssFiles.length} CSS scanned)`,
  );
}
