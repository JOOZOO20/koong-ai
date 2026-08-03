'use strict';
// merge.js — CLAUDE.md import-line append + settings.json deep merge.

const fs = require('node:fs');

const IMPORT_LINE = '@docs/koong/KOONG.md';
const IMPORT_BLOCK = `\n# koong-agent\n${IMPORT_LINE}\n`;

// If the target project already has its own CLAUDE.md, we don't clobber it:
// the koong payload goes to docs/koong/KOONG.md and we append an import line (idempotent).
function mergeClaudeMd(existingPath, payloadContent, koongMdPath) {
  fs.mkdirSync(require('node:path').dirname(koongMdPath), { recursive: true });
  fs.writeFileSync(koongMdPath, payloadContent);
  const existing = fs.readFileSync(existingPath, 'utf8');
  if (existing.includes(IMPORT_LINE)) return 'already-imported';
  fs.writeFileSync(existingPath, existing.replace(/\s*$/, '\n') + IMPORT_BLOCK);
  return 'import-appended';
}

// settings.json deep merge: permissions arrays = set union, hooks arrays = concat
// deduped by (matcher + command), everything else: existing user keys win.
function mergeSettings(existing, incoming) {
  const out = JSON.parse(JSON.stringify(existing));

  out.permissions = out.permissions || {};
  for (const key of ['allow', 'deny']) {
    const a = (existing.permissions && existing.permissions[key]) || [];
    const b = (incoming.permissions && incoming.permissions[key]) || [];
    out.permissions[key] = [...new Set([...a, ...b])];
  }

  out.hooks = out.hooks || {};
  const hookKey = (m) =>
    `${m.matcher || ''}::${(m.hooks || []).map((h) => h.command || '').join('|')}`;
  for (const event of Object.keys(incoming.hooks || {})) {
    const a = (existing.hooks && existing.hooks[event]) || [];
    const b = incoming.hooks[event] || [];
    const seen = new Set(a.map(hookKey));
    out.hooks[event] = [...a, ...b.filter((m) => !seen.has(hookKey(m)))];
  }

  for (const key of Object.keys(incoming)) {
    if (key === 'permissions' || key === 'hooks') continue;
    if (!(key in out)) out[key] = incoming[key];
  }
  return out;
}

module.exports = { mergeClaudeMd, mergeSettings, IMPORT_LINE };
