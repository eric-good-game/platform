#!/usr/bin/env node
// Comprobaciones mínimas del repositorio (hito 0).
// Se ejecutan en el CI: `node scripts/check-repo.mjs`.

import { existsSync, readFileSync } from 'node:fs';

const requiredFiles = [
  'README.md',
  'CONTRIBUTING.md',
  'SECURITY.md',
  'LICENSE',
  '.gitignore',
  '.github/pull_request_template.md',
  '.github/dependabot.yml',
  'docs/README.md',
  'docs/01-vision-and-scope.md',
  'docs/07-platform-infrastructure.md',
  'docs/09-phase-1-implementation-plan.md',
];

const failures = [];

for (const file of requiredFiles) {
  if (!existsSync(file)) {
    failures.push(`falta el archivo requerido: ${file}`);
  }
}

// Invariante 4 del documento 7: ningún secreto real en Git.
const gitignore = existsSync('.gitignore') ? readFileSync('.gitignore', 'utf8') : '';
if (!/^\s*secrets\/\s*$/m.test(gitignore)) {
  failures.push('`.gitignore` debe ignorar la carpeta `secrets/` (invariante 4 del documento 7)');
}

if (failures.length > 0) {
  console.error('Comprobaciones del repositorio fallidas:');
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log('Comprobaciones del repositorio: OK');
