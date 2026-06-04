// Tests for assets/tools/conventions.mjs — the convention-detection scanner.
// Zero-dependency: uses Node's built-in test runner (`node --test`).
//
// Strategy: build a throwaway fixture project on disk, run the real tool with
// cwd set to it (the tool reads ROOT = process.cwd()), and assert the emitted
// conventions.md reflects the patterns we planted.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import {
  mkdtempSync,
  mkdirSync,
  writeFileSync,
  rmSync,
  readFileSync,
  existsSync,
} from 'node:fs';
import { join, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const TOOL = join(HERE, '..', 'assets', 'tools', 'conventions.mjs');

/** Create a fixture Drupal-ish project with two custom-module PHP files. */
function makeFixture() {
  const root = mkdtempSync(join(tmpdir(), 'daw-conv-'));
  const mod = join(root, 'web', 'modules', 'custom', 'demo', 'src');
  // OOP hook classes live under src/Hook/ by Drupal convention; the scanner
  // only counts #[Hook] attributes there.
  const hookDir = join(mod, 'Hook');
  mkdirSync(hookDir, { recursive: true });

  // File 1: strict_types + an OOP #[Hook] method (under src/Hook/).
  writeFileSync(
    join(hookDir, 'Hooks.php'),
    `<?php

declare(strict_types=1);

namespace Drupal\\demo\\Hook;

use Drupal\\Core\\Hook\\Attribute\\Hook;

final class Hooks {
  #[Hook('entity_presave')]
  public function entityPresave(): void {}
}
`,
  );

  // File 2: NO strict_types + a \Drupal:: service-locator anti-pattern.
  writeFileSync(
    join(mod, 'Service.php'),
    `<?php

namespace Drupal\\demo;

class Service {
  public function go() {
    return \\Drupal::service('entity_type.manager');
  }
}
`,
  );
  return root;
}

function run(root) {
  const stdout = execFileSync('node', [TOOL, '--print'], {
    cwd: root,
    encoding: 'utf8',
  });
  return stdout;
}

test('emits PHP conventions and writes conventions.md', () => {
  const root = makeFixture();
  try {
    const out = run(root);
    assert.match(
      out,
      /## PHP conventions/,
      'should report a PHP conventions section',
    );
    assert.ok(
      existsSync(join(root, '.claude', 'conventions.md')),
      'should write .claude/conventions.md',
    );
    const file = readFileSync(join(root, '.claude', 'conventions.md'), 'utf8');
    // --print uses console.log, which appends one trailing newline vs the file.
    assert.equal(
      out.trimEnd(),
      file.trimEnd(),
      'file content should match --print output',
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('counts strict_types adoption as 1 of 2 files', () => {
  const root = makeFixture();
  try {
    const out = run(root);
    // Table row: | `declare(strict_types=1)` | 1/2 (50%) | … |
    assert.match(
      out,
      /strict_types=1\)`\s*\|\s*1\/2/,
      `expected 1/2 strict_types adoption, got:\n${out}`,
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('detects the OOP #[Hook] method', () => {
  const root = makeFixture();
  try {
    const out = run(root);
    assert.match(
      out,
      /#\[Hook\]`:\s*1/,
      `expected one #[Hook] method detected, got:\n${out}`,
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('flags the \\Drupal:: anti-pattern', () => {
  const root = makeFixture();
  try {
    const out = run(root);
    assert.match(
      out,
      /Anti-patterns detected/,
      'should have an anti-patterns section',
    );
    assert.match(
      out,
      /\\Drupal::/,
      'should flag the \\Drupal:: service locator usage',
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
