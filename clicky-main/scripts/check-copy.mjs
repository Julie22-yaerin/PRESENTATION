#!/usr/bin/env node
import { execSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const repoRoot = path.resolve(root, '..');
const stringsFile = path.join(repoRoot, 'clicky-main/leanring-buddy/LyceumStrings.swift');
if (!existsSync(stringsFile)) {
  console.log('copy check OK — no LyceumStrings.swift yet; move copy into the centralized strings file before enforcing the rule.');
  process.exit(0);
}
const swiftFiles = execSync('git -C "' + repoRoot + '" status --short --untracked-files=all', { encoding: 'utf8' })
  .split(/\r?\n/)
  .map((line) => line.trim())
  .filter(Boolean)
  .map((line) => line.replace(/^\S+\s+/, ''))
  .filter((file) => file.endsWith('.swift'));

if (swiftFiles.length === 0) {
  console.log('copy check OK — no modified Swift files to inspect');
  process.exit(0);
}

const offenders = [];
for (const relPath of swiftFiles) {
  if (relPath.endsWith('LyceumStrings.swift')) continue;
  const abs = path.join(repoRoot, relPath);
  if (!existsSync(abs)) continue;
  const text = readFileSync(abs, 'utf8');
  const matches = [...text.matchAll(/"((?:[^"\\]|\\.)*)"/g)];
  for (const match of matches) {
    const value = match[1].replace(/\\./g, '');
    const wordCount = value.trim().split(/\s+/).filter(Boolean).length;
    if (wordCount > 3) {
      offenders.push(`${relPath}: ${value.slice(0, 80)}`);
    }
  }
}

if (offenders.length > 0) {
  console.error('copy check failed: long literal strings outside LyceumStrings.swift');
  for (const item of offenders.slice(0, 20)) console.error(`  - ${item}`);
  process.exit(1);
}

console.log(`copy check OK — ${swiftFiles.length} modified Swift file(s) inspected`);
