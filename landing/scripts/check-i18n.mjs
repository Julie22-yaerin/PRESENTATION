#!/usr/bin/env node
/* Fails loudly when a data-i18n key in index.html has no English string, or when
 * an English string is no longer used anywhere. Run it after editing copy:
 *
 *   node landing/scripts/check-i18n.mjs
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

import { en } from '../lib/dictionary.en.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (relative) => readFileSync(path.join(root, relative), 'utf8');

const html = read('index.html');

const used = new Set();
for (const match of html.matchAll(/data-i18n(?:-alt|-aria)?="([^"]+)"/g)) {
  used.add(match[1]);
}

// Keys the JS looks up by name instead of through an attribute.
const jsSources = ['app.js', 'lib/i18n.js', 'lib/downloads.js', 'lib/dictionary.vi.js'].map(read).join('\n');
for (const match of jsSources.matchAll(/'((?:gen|meta)\.[a-zA-Z0-9.]+)'/g)) {
  used.add(match[1]);
}

// Download labels come from the config file.
const config = JSON.parse(read('download-config.json'));
for (const channel of config.channels) {
  used.add(channel.labelKey);
}

const missing = [...used].filter((key) => !(key in en));
const unused = Object.keys(en).filter((key) => !used.has(key));

if (missing.length > 0) {
  console.error(`Missing English strings (${missing.length}):`);
  for (const key of missing) {
    console.error(`  - ${key}`);
  }
}
if (unused.length > 0) {
  console.error(`English strings nobody uses (${unused.length}):`);
  for (const key of unused) {
    console.error(`  - ${key}`);
  }
}
if (missing.length > 0 || unused.length > 0) {
  process.exit(1);
}

console.log(`i18n OK — ${used.size} keys, all present in lib/dictionary.en.js`);
