'use strict';
// update.js — npx koong-agent update: refresh templates while preserving
// config.json, the user's root CLAUDE.md, agent model frontmatter, and
// user-modified files (written as <file>.new instead of overwritten).

const fs = require('node:fs');
const path = require('node:path');
const readline = require('node:readline');
const {
  TEMPLATES, walkFiles, chmodScripts, sha256File, sha256Normalized, templateVersion, log,
} = require('./util');

function readManifest(cwd) {
  const p = path.join(cwd, '.claude', 'koong', 'manifest.json');
  if (!fs.existsSync(p)) return null;
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return null; }
}

function changelogBetween(fromV, toV) {
  const p = path.join(__dirname, '..', 'CHANGELOG.md');
  if (!fs.existsSync(p)) return '';
  const text = fs.readFileSync(p, 'utf8');
  const sections = text.split(/^## /m).slice(1);
  const picked = [];
  for (const s of sections) {
    const ver = (s.match(/\[?([0-9]+\.[0-9]+\.[0-9]+)/) || [])[1];
    if (!ver) continue;
    if (ver === fromV) break; // sections are newest-first
    picked.push('## ' + s.trim());
    if (ver === toV) continue;
  }
  return picked.join('\n\n');
}

async function confirm(question) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const answer = await new Promise((res) => rl.question(question, res));
  rl.close();
  return /^(y|yes|네|ㅇ)?$/i.test(answer.trim());
}

async function run(cwd) {
  const manifest = readManifest(cwd);
  if (!manifest) {
    log('설치 기록(manifest)이 없어요. 먼저 npx koong-agent init 을 실행하세요.');
    process.exitCode = 1;
    return;
  }
  const fromV = manifest.version;
  const toV = templateVersion();
  if (fromV === toV) {
    log(`이미 최신 버전(v${toV})입니다.`);
    return;
  }

  log(`koong-agent v${fromV} → v${toV} 업데이트`);
  const cl = changelogBetween(fromV, toV);
  if (cl) log('\n' + cl + '\n');
  if (!(await confirm('계속할까요? [Y/n] '))) { log('취소했습니다.'); return; }

  const conflicts = [];
  const newManifest = { version: toV, files: {} };

  const groups = [
    { src: path.join(TEMPLATES, 'claude'), destRoot: path.join(cwd, '.claude'), prefix: '.claude/' },
    { src: path.join(TEMPLATES, 'docs'), destRoot: path.join(cwd, 'docs'), prefix: 'docs/' },
  ];

  for (const { src, destRoot, prefix } of groups) {
    for (const rel of walkFiles(src)) {
      const srcFile = path.join(src, rel);
      const destFile = path.join(destRoot, rel);
      const key = prefix + rel.replace(/\\/g, '/');
      const isAgent = key.startsWith('.claude/agents/');
      const shippedHash = manifest.files[key];

      // Agent files: manifest stores the NORMALIZED hash (model: line excluded),
      // so /koong-init's model rewrite never reads as a user modification.
      let userModified = false;
      let preservedModel = null;
      if (fs.existsSync(destFile) && shippedHash) {
        if (isAgent) {
          const m = fs.readFileSync(destFile, 'utf8').match(/^model:\s*(.*)$/m);
          preservedModel = m ? m[1].trim() : null;
          userModified = sha256Normalized(destFile) !== shippedHash;
        } else {
          userModified = sha256File(destFile) !== shippedHash;
        }
      }

      if (userModified) {
        fs.writeFileSync(destFile + '.new', fs.readFileSync(srcFile));
        conflicts.push(key);
        newManifest.files[key] = shippedHash; // keep old baseline for next time
        continue;
      }

      fs.mkdirSync(path.dirname(destFile), { recursive: true });
      fs.copyFileSync(srcFile, destFile);
      if (isAgent && preservedModel && preservedModel !== 'inherit') {
        const content = fs.readFileSync(destFile, 'utf8')
          .replace(/^model:\s*.*$/m, `model: ${preservedModel}`);
        fs.writeFileSync(destFile, content);
      }
      newManifest.files[key] = isAgent ? sha256Normalized(destFile) : sha256File(destFile);
    }
  }

  chmodScripts(path.join(cwd, '.claude', 'koong', 'scripts'));
  fs.writeFileSync(
    path.join(cwd, '.claude', 'koong', 'manifest.json'),
    JSON.stringify(newManifest, null, 2) + '\n'
  );

  log(`\n✅ v${toV} 업데이트 완료.`);
  log('보존됨: .claude/koong/config.json, 프로젝트 CLAUDE.md, 에이전트 model 설정');
  if (conflicts.length) {
    log('\n⚠️ 직접 수정하신 파일은 덮어쓰지 않았어요. 새 버전을 <파일>.new 로 두었으니 비교해서 반영하세요:');
    for (const c of conflicts) log(`  - ${c} (→ ${c}.new)`);
  }
}

module.exports = { run };
