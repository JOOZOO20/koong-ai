'use strict';
// util.js — shared helpers for the koong CLI. Node stdlib only.

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const PKG_ROOT = path.resolve(__dirname, '..');
const TEMPLATES = path.join(PKG_ROOT, 'templates');

function sha256File(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

// Copy a directory tree. Returns list of relative paths copied (relative to srcRoot).
function walkCopy(srcRoot, destRoot, { overwrite = true } = {}) {
  const copied = [];
  const walk = (rel) => {
    const src = path.join(srcRoot, rel);
    const dest = path.join(destRoot, rel);
    const stat = fs.statSync(src);
    if (stat.isDirectory()) {
      fs.mkdirSync(dest, { recursive: true });
      for (const entry of fs.readdirSync(src)) walk(path.join(rel, entry));
    } else {
      if (!overwrite && fs.existsSync(dest)) return;
      fs.mkdirSync(path.dirname(dest), { recursive: true });
      fs.copyFileSync(src, dest);
      copied.push(rel);
    }
  };
  walk('.');
  return copied.map((p) => p.replace(/\\/g, '/').replace(/^\.\//, ''));
}

function walkFiles(root) {
  const out = [];
  const walk = (rel) => {
    const abs = path.join(root, rel);
    if (fs.statSync(abs).isDirectory()) {
      for (const entry of fs.readdirSync(abs)) walk(path.join(rel, entry));
    } else {
      out.push(rel.replace(/\\/g, '/'));
    }
  };
  walk('.');
  return out;
}

function chmodScripts(dir) {
  if (!fs.existsSync(dir)) return;
  for (const f of fs.readdirSync(dir)) {
    if (f.endsWith('.sh')) fs.chmodSync(path.join(dir, f), 0o755);
  }
}

function templateVersion() {
  return fs.readFileSync(path.join(TEMPLATES, 'VERSION'), 'utf8').trim();
}

// Normalize an agent file's content for user-modification detection:
// the model: frontmatter line is owned by /koong-init, so ignore it when hashing.
function normalizeAgentContent(content) {
  return content.replace(/^model:\s*.*$/m, 'model: __NORMALIZED__');
}

function sha256Normalized(file) {
  const content = fs.readFileSync(file, 'utf8');
  return crypto.createHash('sha256').update(normalizeAgentContent(content)).digest('hex');
}

const log = (msg) => console.log(msg);
const ok = (msg) => console.log(`  ✔ ${msg}`);
const bad = (msg) => console.log(`  ✖ ${msg}`);

module.exports = {
  PKG_ROOT,
  TEMPLATES,
  sha256File,
  sha256Normalized,
  normalizeAgentContent,
  walkCopy,
  walkFiles,
  chmodScripts,
  templateVersion,
  log,
  ok,
  bad,
};
