'use strict';
// init.js — npx koong-agent init: copy the payload into the current project.

const fs = require('node:fs');
const path = require('node:path');
const {
  TEMPLATES, walkCopy, walkFiles, chmodScripts, sha256File, sha256Normalized, templateVersion, log,
} = require('./util');
const { mergeClaudeMd, mergeSettings } = require('./merge');

function run(cwd) {
  const version = templateVersion();
  log(`koong-agent v${version} 설치를 시작합니다...`);

  // 1. .claude/ payload (templates/claude → .claude). Don't clobber settings.json blindly.
  const claudeSrc = path.join(TEMPLATES, 'claude');
  const claudeDest = path.join(cwd, '.claude');
  const targetSettings = path.join(claudeDest, 'settings.json');
  const incomingSettings = JSON.parse(
    fs.readFileSync(path.join(claudeSrc, 'settings.json'), 'utf8')
  );

  let settingsMode = 'copied';
  let existingSettings = null;
  if (fs.existsSync(targetSettings)) {
    existingSettings = JSON.parse(fs.readFileSync(targetSettings, 'utf8'));
    settingsMode = 'merged';
  }

  walkCopy(claudeSrc, claudeDest);

  if (existingSettings) {
    const merged = mergeSettings(existingSettings, incomingSettings);
    fs.writeFileSync(targetSettings, JSON.stringify(merged, null, 2) + '\n');
  }

  chmodScripts(path.join(claudeDest, 'koong', 'scripts'));
  fs.mkdirSync(path.join(claudeDest, 'koong', 'state'), { recursive: true });

  // 2. docs/koong
  walkCopy(path.join(TEMPLATES, 'docs'), path.join(cwd, 'docs'));

  // 3. CLAUDE.md — copy, or import-append when the project already has one.
  const payloadClaudeMd = fs.readFileSync(path.join(TEMPLATES, 'CLAUDE.md'), 'utf8');
  const targetClaudeMd = path.join(cwd, 'CLAUDE.md');
  let claudeMdMode;
  if (fs.existsSync(targetClaudeMd)) {
    claudeMdMode = mergeClaudeMd(
      targetClaudeMd,
      payloadClaudeMd,
      path.join(cwd, 'docs', 'koong', 'KOONG.md')
    );
  } else {
    fs.writeFileSync(targetClaudeMd, payloadClaudeMd);
    claudeMdMode = 'copied';
  }

  // 4. .gitignore: ensure state dir + .env are ignored
  const gitignorePath = path.join(cwd, '.gitignore');
  const needed = ['.claude/koong/state/', '.env'];
  let gi = fs.existsSync(gitignorePath) ? fs.readFileSync(gitignorePath, 'utf8') : '';
  const missing = needed.filter((line) => !gi.split(/\r?\n/).some((l) => l.trim() === line));
  if (missing.length) {
    fs.writeFileSync(
      gitignorePath,
      gi.replace(/\s*$/, gi ? '\n' : '') + '# koong\n' + missing.join('\n') + '\n'
    );
  }

  // 5. Install manifest (update.js depends on it)
  // Agent files use a normalized hash (model: line excluded) so /koong-init's
  // model rewrite doesn't count as a user modification at update time.
  const manifest = { version, files: {} };
  for (const rel of walkFiles(claudeSrc)) {
    const dest = path.join(claudeDest, rel);
    if (!fs.existsSync(dest)) continue;
    const key = `.claude/${rel}`;
    manifest.files[key] = key.startsWith('.claude/agents/')
      ? sha256Normalized(dest)
      : sha256File(dest);
  }
  for (const rel of walkFiles(path.join(TEMPLATES, 'docs'))) {
    const dest = path.join(cwd, 'docs', rel);
    if (fs.existsSync(dest)) manifest.files[`docs/${rel}`] = sha256File(dest);
  }
  fs.writeFileSync(
    path.join(claudeDest, 'koong', 'manifest.json'),
    JSON.stringify(manifest, null, 2) + '\n'
  );

  log('');
  log(`✅ koong-agent v${version} 설치 완료! (CLAUDE.md: ${claudeMdMode}, settings.json: ${settingsMode})`);
  log('');
  log('다음 단계:');
  log('  1. claude          ← Claude Code 실행');
  log('  2. /koong-init     ← 프로젝트에 맞게 자동 설정 (딱 한 번)');
  log('  3. /koong 만들고 싶은 것을 한국어로 적으세요');
  log('');
  log('문제가 있으면: npx koong-agent doctor');
}

module.exports = { run };
