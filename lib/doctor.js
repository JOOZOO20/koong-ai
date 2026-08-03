'use strict';
// doctor.js — npx koong-agent doctor: environment diagnostics with Korean fix hints.

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { execSync } = require('node:child_process');
const { templateVersion, log, ok, bad, sha256File, sha256Normalized } = require('./util');

function sh(cmd) {
  try {
    return execSync(cmd, { stdio: ['ignore', 'pipe', 'pipe'], encoding: 'utf8' }).trim();
  } catch {
    return null;
  }
}

function run(cwd) {
  let failures = 0;
  const check = (name, pass, fix) => {
    if (pass) ok(name);
    else {
      bad(`${name} → ${fix}`);
      failures++;
    }
  };

  log('koong doctor — 환경 진단');
  log('');

  const nodeMajor = parseInt(process.version.slice(1), 10);
  check(`Node ${process.version}`, nodeMajor >= 18, 'Node 18 이상이 필요해요: https://nodejs.org');

  check('git 저장소', sh('git rev-parse --is-inside-work-tree') === 'true',
    'git init 을 하거나, 새 프로젝트라면 Claude Code에서 /koong-new 를 사용하세요');
  check('git 사용자 설정', !!sh('git config user.name'),
    'git config --global user.name "이름" && git config --global user.email "이메일"');
  check('Claude Code 설치', !!sh('command -v claude'),
    'https://claude.com/claude-code 에서 설치하세요');
  check('gh CLI + 로그인', !!sh('gh auth status'),
    'gh auth login (이슈/PR 자동화에 필요해요; 커밋만 쓸 거면 없어도 됩니다)');
  check('jq 설치', !!sh('command -v jq'),
    'brew install jq (요금제 감지와 커밋 게이트에 필요해요)');

  const claudeJson = path.join(os.homedir(), '.claude.json');
  let planDetectable = false;
  if (fs.existsSync(claudeJson)) {
    try {
      const j = JSON.parse(fs.readFileSync(claudeJson, 'utf8'));
      planDetectable = !!(j.oauthAccount && j.oauthAccount.organizationType);
    } catch { /* ignore */ }
  }
  check('요금제 감지 가능', planDetectable,
    'claude 로그인이 필요해요 (API 키 사용자는 /koong-init에서 한 번 물어봅니다)');

  check('koong payload 설치됨',
    fs.existsSync(path.join(cwd, '.claude', 'skills', 'koong', 'SKILL.md')),
    'npx koong-agent init');
  check('config.json (초기화됨)',
    fs.existsSync(path.join(cwd, '.claude', 'koong', 'config.json')),
    'Claude Code에서 /koong-init 을 실행하세요');

  const stackFiles = ['build.gradle', 'build.gradle.kts', 'pom.xml', 'go.mod', 'pyproject.toml', 'requirements.txt', 'package.json'];
  check('스택 감지', stackFiles.some((f) => fs.existsSync(path.join(cwd, f))),
    '빌드 파일이 없어요. 새 프로젝트라면 /koong-new 로 생성하세요');

  const manifestPath = path.join(cwd, '.claude', 'koong', 'manifest.json');
  let manifest = null;
  if (fs.existsSync(manifestPath)) {
    try { manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8')); } catch { /* ignore */ }
  }
  check(`버전 일치 (v${templateVersion()})`, !!manifest && manifest.version === templateVersion(),
    'npx koong-agent update');

  // harness integrity: installed enforcement files vs install-time hashes.
  // Detects tampering by other tools/agents/malicious PRs (threat F-3).
  if (manifest) {
    const critical = Object.keys(manifest.files).filter(
      (k) => k.startsWith('.claude/koong/scripts/') || k === '.claude/settings.json' || k.startsWith('.claude/agents/')
    );
    const tampered = [];
    for (const key of critical) {
      const p = path.join(cwd, key);
      if (!fs.existsSync(p)) { tampered.push(`${key} (삭제됨)`); continue; }
      const hash = key.startsWith('.claude/agents/') ? sha256Normalized(p) : sha256File(p);
      if (hash !== manifest.files[key]) tampered.push(key);
    }
    check('하네스 무결성 (변조 없음)', tampered.length === 0,
      `변조/수정 감지: ${tampered.join(', ')} — 의도한 수정이 아니라면 'npx koong-agent update'로 복원하세요`);
  }

  // manual-marks escape hatch must stay off in normal operation
  const configPath = path.join(cwd, '.claude', 'koong', 'config.json');
  let manualMarks = false;
  if (fs.existsSync(configPath)) {
    try { manualMarks = JSON.parse(fs.readFileSync(configPath, 'utf8')).allow_manual_marks === true; } catch { /* ignore */ }
  }
  check('증거 시스템 활성 (allow_manual_marks=false)', !manualMarks,
    'config.json의 allow_manual_marks가 true입니다 — 수동 마킹은 게이트의 신원 검증을 우회하는 디버깅용 탈출구예요. false로 되돌리세요');

  // both PreToolUse hooks registered (Bash gate + Write/Edit guard)
  const settingsPath = path.join(cwd, '.claude', 'settings.json');
  let hooksOk = false;
  if (fs.existsSync(settingsPath)) {
    try {
      const s = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
      const pre = JSON.stringify(s.hooks && s.hooks.PreToolUse || []);
      hooksOk = pre.includes('gate-git.sh') && pre.includes('guard-state.sh');
    } catch { /* ignore */ }
  }
  check('강제 훅 등록 (gate-git + guard-state)', hooksOk, 'npx koong-agent update 로 settings.json 훅을 복구하세요');

  log('');
  log(failures === 0 ? '모든 진단 통과! /koong 을 쓸 준비가 됐어요.' : `${failures}개 항목을 해결해주세요.`);
  process.exitCode = failures;
}

module.exports = { run };
