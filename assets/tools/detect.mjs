#!/usr/bin/env node
// Zero-dep stack detector. Run from a project root:
//   node .claude/tools/detect.mjs           # writes .claude/stack.json
//   node .claude/tools/detect.mjs --print   # also prints to stdout
//   node .claude/tools/detect.mjs --gaps    # also writes .claude/gaps.md
//
// Detects: PHP/Drupal backend, JS/TS/Twig frontend, build tooling, QA configs,
// infra (DDEV/Docker/CI), then maps detected capabilities to skills available
// in ~/.claude (user-global + plugin-provided + project-local) and reports gaps.

import {
  readFileSync,
  existsSync,
  readdirSync,
  statSync,
  writeFileSync,
  mkdirSync,
} from 'node:fs';
import { join, dirname, basename } from 'node:path';
import { homedir } from 'node:os';
import { execSync } from 'node:child_process';

const ROOT = process.cwd();
const args = new Set(process.argv.slice(2));

// ---------- helpers ----------
const readJson = (p) => {
  try {
    return JSON.parse(readFileSync(p, 'utf8'));
  } catch {
    return null;
  }
};
const readText = (p) => {
  try {
    return readFileSync(p, 'utf8');
  } catch {
    return null;
  }
};
const exists = (p) => existsSync(p);

function findFirst(rel) {
  for (const r of rel) if (exists(join(ROOT, r))) return r;
  return null;
}

function findAll(dirs, pattern, max = 5000) {
  const out = [];
  const skip = new Set(['node_modules', 'vendor', '.git', 'dist', 'build']);
  const walk = (d) => {
    if (out.length >= max) return;
    let entries;
    try {
      entries = readdirSync(d, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      if (skip.has(e.name)) continue;
      const full = join(d, e.name);
      if (e.isDirectory()) walk(full);
      else if (pattern.test(e.name)) out.push(full);
    }
  };
  for (const d of dirs) if (exists(join(ROOT, d))) walk(join(ROOT, d));
  return out;
}

// ---------- backend ----------
function detectBackend() {
  const composer = readJson(join(ROOT, 'composer.json'));
  const lock = readJson(join(ROOT, 'composer.lock'));
  if (!composer) return null;

  const req = composer.require || {};
  const platformPhp = composer.config?.platform?.php || null;
  const phpConstraint = req.php || null;

  const coreInLock = lock?.packages?.find((p) => p.name === 'drupal/core');

  // A project is Drupal if it requires core directly OR pulls it in
  // transitively (e.g. distribution/profile-based projects that require a
  // profile metapackage instead of drupal/core). The lock is authoritative
  // for the transitive case.
  const isDrupal = !!(
    req['drupal/core'] ||
    req['drupal/core-recommended'] ||
    req['drupal/core-composer-scaffold'] ||
    coreInLock
  );
  if (!isDrupal) {
    return {
      language: 'php',
      php_version: platformPhp || phpConstraint,
      framework: 'unknown',
    };
  }

  // Resolve a clean Drupal core version, preferring the locked version and
  // falling back to the declared constraint. Then derive a normalized major
  // (digits only) so downstream consumers don't have to re-parse constraint
  // strings like "^11.0" or "~10.3".
  const drupalCore =
    coreInLock?.version ||
    req['drupal/core-recommended'] ||
    req['drupal/core'] ||
    null;
  const drupalMajorMatch = drupalCore ? String(drupalCore).match(/\d+/) : null;
  const drupalMajor = drupalMajorMatch ? Number(drupalMajorMatch[0]) : null;

  const contribModules = Object.keys(req).filter((k) =>
    k.startsWith('drupal/'),
  ).length;

  // locate custom modules (profile-based vs standard)
  const candidatePaths = [
    'docroot/profiles/vitalaire/modules',
    'web/modules/custom',
    'docroot/modules/custom',
    'modules/custom',
  ];
  let customPath = null,
    customCount = 0,
    customModules = [];
  for (const p of candidatePaths) {
    if (!exists(join(ROOT, p))) continue;
    const infos = findAll([p], /\.info\.yml$/);
    if (infos.length) {
      customPath = p;
      customModules = infos.map((f) => basename(f, '.info.yml')).slice(0, 100);
      customCount = infos.length;
      break;
    }
  }

  // sniff integrations from contrib module names
  const integrationHints = {
    commercetools: /commercetool/i,
    hubspot: /hubspot/i,
    paypal: /paypal/i,
    ingenico: /ingenico/i,
    solr: /search_api_solr|solr/i,
    gtm: /google_tag|gtm/i,
    ai: /^drupal\/ai($|_)/i,
  };
  const detectedIntegrations = [];
  const allDeps = Object.keys(req).join(' ');
  for (const [name, re] of Object.entries(integrationHints)) {
    if (re.test(allDeps)) detectedIntegrations.push(name);
  }
  // also check custom module names
  for (const m of customModules) {
    for (const [name, re] of Object.entries(integrationHints)) {
      if (re.test(m) && !detectedIntegrations.includes(name))
        detectedIntegrations.push(name);
    }
  }

  return {
    language: 'php',
    php_version:
      platformPhp || phpConstraint || coreInLock?.require?.php || null,
    php_source: platformPhp
      ? 'composer.json:config.platform.php'
      : phpConstraint
        ? 'composer.json:require.php'
        : 'composer.lock:drupal/core',
    framework: 'drupal',
    drupal_core: drupalCore,
    drupal_major: drupalMajor,
    drupal_constraint:
      req['drupal/core-recommended'] || req['drupal/core'] || null,
    drush: req['drush/drush'] || null,
    install_profile: customPath?.includes('profiles/')
      ? customPath.split('/')[2]
      : null,
    contrib_modules: contribModules,
    custom_modules_path: customPath,
    custom_modules_count: customCount,
    custom_modules: customModules,
    integrations: detectedIntegrations,
  };
}

// ---------- frontend ----------
function detectFrontend() {
  // find theme(s) with package.json
  const themeRoots = [
    'docroot/themes/custom',
    'web/themes/custom',
    'themes/custom',
  ];
  let themeDir = null;
  for (const r of themeRoots) {
    const abs = join(ROOT, r);
    if (!exists(abs)) continue;
    for (const e of readdirSync(abs, { withFileTypes: true })) {
      if (e.isDirectory() && exists(join(abs, e.name, 'package.json'))) {
        themeDir = join(r, e.name);
        break;
      }
    }
    if (themeDir) break;
  }

  // fallback: root package.json
  const pkgPath = themeDir
    ? join(ROOT, themeDir, 'package.json')
    : join(ROOT, 'package.json');
  const pkg = exists(pkgPath) ? readJson(pkgPath) : null;

  const twigFiles = findAll(
    [
      'docroot/themes/custom',
      'web/themes/custom',
      'docroot/profiles',
      'web/modules/custom',
    ],
    /\.twig$/,
  ).length;
  const tsFiles = findAll(['docroot', 'web', 'src'], /\.(ts|tsx)$/).length;

  const deps = {
    ...(pkg?.dependencies || {}),
    ...(pkg?.devDependencies || {}),
  };
  const has = (re) => Object.keys(deps).some((k) => re.test(k));

  const langs = [];
  if (twigFiles > 0) langs.push('twig');
  if (
    Object.keys(deps).length ||
    findAll(['docroot/themes', 'web/themes'], /\.js$/, 10).length
  )
    langs.push('javascript');
  if (tsFiles > 0 || has(/^typescript$/)) langs.push('typescript');
  if (findAll(['docroot/themes', 'web/themes'], /\.scss$/, 10).length)
    langs.push('scss');

  let buildTool = null;
  if (has(/^gulp/)) buildTool = 'gulp';
  else if (has(/^vite/)) buildTool = 'vite';
  else if (has(/^webpack/)) buildTool = 'webpack';
  else if (has(/@factorial\/stack/)) buildTool = '@factorial/stack';
  else if (pkg?.scripts?.build) buildTool = 'npm-scripts';

  return {
    theme: themeDir,
    package_manager: exists(join(ROOT, themeDir || '', 'yarn.lock'))
      ? 'yarn'
      : exists(join(ROOT, themeDir || '', 'pnpm-lock.yaml'))
        ? 'pnpm'
        : exists(join(ROOT, themeDir || '', 'package-lock.json'))
          ? 'npm'
          : null,
    node: pkg?.engines?.node || null,
    build: buildTool,
    languages: langs,
    typescript: tsFiles > 0,
    twig_files: twigFiles,
    component_library: has(/@miyagi/)
      ? 'miyagi'
      : has(/storybook/)
        ? 'storybook'
        : null,
    css_framework: has(/^bootstrap$/)
      ? 'bootstrap'
      : has(/tailwindcss/)
        ? 'tailwind'
        : null,
    scripts: pkg ? Object.keys(pkg.scripts || {}) : [],
  };
}

// ---------- quality / qa tooling ----------
function detectQA() {
  return {
    phpcs: findFirst(['.phpcs.xml', 'phpcs.xml', 'phpcs.xml.dist']),
    phpstan: findFirst(['phpstan.neon', 'phpstan.neon.dist']),
    rector: findFirst(['rector.php']),
    grumphp: findFirst(['grumphp.yml', 'grumphp.yml.dist']),
    phpunit: findFirst([
      'phpunit.xml',
      'phpunit.xml.dist',
      'core/phpunit.xml.dist',
    ]),
    eslint: findFirst([
      '.eslintrc',
      '.eslintrc.js',
      '.eslintrc.json',
      'eslint.config.js',
    ]),
    prettier: findFirst(['.prettierrc', '.prettierrc.json', '.prettierrc.js']),
    stylelint: findFirst(['.stylelintrc', '.stylelintrc.json']),
    editorconfig: findFirst(['.editorconfig']),
  };
}

// ---------- infra ----------
function detectInfra() {
  return {
    ddev: exists(join(ROOT, '.ddev')),
    docker_compose: !!findFirst([
      'docker-compose.yml',
      'docker-compose.yaml',
      'compose.yaml',
    ]),
    makefile: exists(join(ROOT, 'Makefile')),
    ci: exists(join(ROOT, '.gitlab-ci.yml'))
      ? 'gitlab'
      : exists(join(ROOT, '.github/workflows'))
        ? 'github-actions'
        : exists(join(ROOT, '.circleci'))
          ? 'circleci'
          : null,
    acquia: !!findFirst(['acquia-pipelines.yml', '.gitlab-ci.factorial.yml']),
    git_branch: (() => {
      try {
        return execSync('git rev-parse --abbrev-ref HEAD', { cwd: ROOT })
          .toString()
          .trim();
      } catch {
        return null;
      }
    })(),
  };
}

// ---------- skill inventory ----------
function enumerateSkills() {
  const dirs = [
    join(homedir(), '.claude', 'skills'),
    join(homedir(), '.claude', 'plugins'),
    join(ROOT, '.claude', 'skills'),
  ];
  const found = [];
  const visit = (dir, depth = 0) => {
    if (!exists(dir) || depth > 4) return;
    for (const e of readdirSync(dir, { withFileTypes: true })) {
      const full = join(dir, e.name);
      if (e.isDirectory()) {
        // skill folder usually contains SKILL.md or skill.md
        const manifest = ['SKILL.md', 'skill.md', 'skill.yaml', 'skill.yml']
          .map((f) => join(full, f))
          .find(exists);
        if (manifest) {
          const txt = readText(manifest) || '';
          const nameMatch = txt.match(/^name:\s*(.+)$/m);
          const descMatch = txt.match(
            /^description:\s*([\s\S]+?)(?:\n[a-z_]+:|\n---)/m,
          );
          // Optional `provides:` array — either inline (`[a, b]`) or YAML list lines.
          let provides = [];
          const provInline = txt.match(/^provides:\s*\[([^\]]+)\]/m);
          if (provInline) {
            provides = provInline[1]
              .split(',')
              .map((s) => s.trim().replace(/^['"]|['"]$/g, ''))
              .filter(Boolean);
          } else {
            const provBlock = txt.match(/^provides:\s*\n((?:\s+-\s+.+\n?)+)/m);
            if (provBlock) {
              provides = [...provBlock[1].matchAll(/^\s+-\s+(.+)$/gm)].map(
                (m) => m[1].trim().replace(/^['"]|['"]$/g, ''),
              );
            }
          }
          found.push({
            name: nameMatch ? nameMatch[1].trim() : e.name,
            description: descMatch ? descMatch[1].trim().slice(0, 200) : '',
            provides,
            source:
              dir.includes(homedir()) && !dir.startsWith(ROOT)
                ? 'global'
                : 'project',
            path: full,
          });
        } else {
          visit(full, depth + 1);
        }
      }
    }
  };
  for (const d of dirs) visit(d);
  return found;
}

// ---------- capability mapping ----------
// Each capability lists detection predicates + skill name patterns that satisfy it.
const CAPABILITY_RULES = [
  {
    cap: 'drupal-backend',
    needIf: (s) => s.backend?.framework === 'drupal',
    skills: [/^drupal-expert$/],
  },
  { cap: 'drush-cli', needIf: (s) => !!s.backend?.drush, skills: [/^drush$/] },
  {
    cap: 'module-scaffolding',
    needIf: (s) => (s.backend?.custom_modules_count || 0) > 0,
    skills: [/^scaffold$/],
  },
  {
    cap: 'drupal-debug',
    needIf: (s) => s.backend?.framework === 'drupal',
    skills: [/^debug$/],
  },
  {
    cap: 'entity-api',
    needIf: (s) =>
      s.backend?.custom_modules?.some((m) => /entit(y|ies)/i.test(m)),
    skills: [/^entity$/],
  },
  {
    cap: 'config-mgmt',
    needIf: (s) => exists(join(ROOT, 'config')),
    skills: [/^config-management$/],
  },
  {
    cap: 'drupal-frontend',
    needIf: (s) => s.frontend?.languages?.includes('twig'),
    skills: [/^drupal-frontend-expert$/],
  },
  {
    cap: 'accessibility',
    needIf: (s) => (s.frontend?.twig_files || 0) > 0,
    skills: [/^accessibility$/],
  },
  {
    cap: 'rest-api',
    needIf: (s) =>
      s.backend?.custom_modules?.some((m) => /api|jsonapi|graphql/i.test(m)),
    skills: [/^api$/],
  },
  {
    cap: 'solr',
    needIf: (s) => s.backend?.integrations?.includes('solr'),
    skills: [/^solr-setup$/],
  },
  { cap: 'ddev', needIf: (s) => s.infra?.ddev, skills: [/^ddev$/] },
  {
    cap: 'code-review',
    needIf: () => true,
    skills: [/^code-review$/, /^review$/],
  },
  { cap: 'refactor', needIf: () => true, skills: [/^refactor$/, /^simplify$/] },
  {
    cap: 'security',
    needIf: (s) => s.backend?.framework === 'drupal',
    skills: [/^drupal-security$/, /^security-review$/],
  },
  {
    cap: 'performance',
    needIf: (s) => s.backend?.framework === 'drupal',
    skills: [/^performance$/],
  },
  {
    cap: 'test-generation',
    needIf: (s) => s.backend?.framework === 'drupal',
    skills: [/^generate-tests$/],
  },
  {
    cap: 'migrations',
    needIf: (s) => s.backend?.custom_modules?.some((m) => /migrat/i.test(m)),
    skills: [/^migrate$/],
  },
  {
    cap: 'drupal-ai',
    needIf: (s) => s.backend?.integrations?.includes('ai'),
    skills: [/^drupal-ai$/],
  },
  // gaps (no known skill yet)
  {
    cap: 'frontend-build-gulp',
    needIf: (s) => s.frontend?.build === 'gulp',
    skills: [],
  },
  {
    cap: 'gitlab-acquia-deploy',
    needIf: (s) => s.infra?.ci === 'gitlab' && s.infra?.acquia,
    skills: [],
  },
  {
    cap: 'commercetools',
    needIf: (s) => s.backend?.integrations?.includes('commercetools'),
    skills: [],
  },
  { cap: 'typescript', needIf: (s) => s.frontend?.typescript, skills: [] },
];

function matchCapabilities(stack, skills) {
  const results = [];
  for (const rule of CAPABILITY_RULES) {
    if (!rule.needIf(stack)) continue;
    // A skill matches a capability if it either declares the capability in
    // `provides:` (authoritative, data-driven) or its name matches the rule's
    // regex list (legacy fallback for skills without `provides:`).
    const matched = skills.filter(
      (sk) =>
        (sk.provides || []).includes(rule.cap) ||
        rule.skills.some((re) => re.test(sk.name)),
    );
    results.push({
      capability: rule.cap,
      needed: true,
      satisfied_by: matched.map((m) => ({
        name: m.name,
        description: (m.description || '')
          .split(/\.\s|\n/)[0]
          .slice(0, 140)
          .trim(),
      })),
      status: matched.length
        ? 'available'
        : rule.skills.length
          ? 'missing'
          : 'gap-no-skill-defined',
    });
  }
  return results;
}

// ---------- drift / gaps ----------
function findDrift(stack) {
  const drift = [];
  if (stack.frontend?.node && /\^?16\./.test(stack.frontend.node)) {
    drift.push('Node 16 is EOL — consider upgrading the theme to Node 20 LTS.');
  }
  if (
    stack.backend?.php_version &&
    /^8\.1/.test(stack.backend.php_version) &&
    /^10\.[3-9]|^11\./.test(stack.backend?.drupal_core || '')
  ) {
    drift.push(
      `PHP pinned to ${stack.backend.php_version} but Drupal ${stack.backend.drupal_core} recommends PHP 8.3+.`,
    );
  }
  if (stack.qa?.phpunit === null && stack.backend?.framework === 'drupal') {
    drift.push(
      'No phpunit.xml at project root — tests cannot be scaffolded without one.',
    );
  }
  if (stack.qa?.phpstan) {
    const txt = readText(join(ROOT, stack.qa.phpstan)) || '';
    const level = txt.match(/level:\s*(\d+)/)?.[1];
    if (level && Number(level) < 5)
      drift.push(`PHPStan level ${level} — consider raising toward 5+.`);
  }
  if (!stack.qa?.eslint && stack.frontend?.languages?.includes('javascript')) {
    drift.push(
      'No ESLint config detected despite JS sources — add eslint for JS linting.',
    );
  }
  return drift;
}

// ---------- main ----------
const stack = {
  generated_at: new Date().toISOString(),
  project: {
    cwd: ROOT,
    name: readJson(join(ROOT, 'composer.json'))?.name || basename(ROOT),
  },
  backend: detectBackend(),
  frontend: detectFrontend(),
  qa: detectQA(),
  infra: detectInfra(),
};

const skills = enumerateSkills();
const capabilities = matchCapabilities(stack, skills);
const drift = findDrift(stack);

stack.skills = {
  available_count: skills.length,
  capabilities,
  gaps: capabilities.filter((c) => c.status !== 'available'),
};
stack.drift = drift;

mkdirSync(join(ROOT, '.claude'), { recursive: true });
writeFileSync(
  join(ROOT, '.claude', 'stack.json'),
  JSON.stringify(stack, null, 2),
);

if (args.has('--gaps')) {
  const lines = [
    `# Stack gaps (${stack.project.name})`,
    '',
    '## Capabilities',
    ...capabilities.map(
      (c) =>
        `- **${c.capability}** — ${c.status}${c.satisfied_by.length ? ` (${c.satisfied_by.map((s) => s.name).join(', ')})` : ''}`,
    ),
    '',
    '## Drift warnings',
    ...(drift.length ? drift.map((d) => `- ${d}`) : ['- none']),
  ];
  writeFileSync(join(ROOT, '.claude', 'gaps.md'), lines.join('\n'));
}

if (args.has('--print') || args.size === 0) {
  const summary = {
    project: stack.project.name,
    backend:
      stack.backend &&
      `${stack.backend.framework} ${stack.backend.drupal_core || ''} / php ${stack.backend.php_version}`,
    frontend:
      stack.frontend?.theme &&
      `${stack.frontend.languages?.join('+')} via ${stack.frontend.build || 'n/a'} (node ${stack.frontend.node || 'n/a'})`,
    custom_modules: stack.backend?.custom_modules_count,
    integrations: stack.backend?.integrations,
    skills_available: skills.length,
    capabilities_satisfied: capabilities.filter((c) => c.status === 'available')
      .length,
    capabilities_missing: capabilities
      .filter((c) => c.status !== 'available')
      .map((c) => c.capability),
    drift,
  };
  console.log(JSON.stringify(summary, null, 2));
  console.log(`\nWrote ${join('.claude', 'stack.json')}`);
}
