'use strict';
// stats.js — npx koong-agent stats: summarize .koong/loop-log.jsonl.
// The commit lines are written by the gate hook itself (not by any agent),
// so these numbers are tamper-resistant evidence of what the harness caught.

const fs = require('node:fs');
const path = require('node:path');
const { log } = require('./util');

function run(cwd) {
  const logPath = path.join(cwd, '.koong', 'loop-log.jsonl');
  if (!fs.existsSync(logPath)) {
    log('아직 기록이 없어요 (.koong/loop-log.jsonl 없음). /koong 으로 작업을 시작하면 자동으로 쌓입니다.');
    return;
  }

  const lines = fs.readFileSync(logPath, 'utf8').split('\n').filter(Boolean);
  const entries = [];
  for (const line of lines) {
    try { entries.push(JSON.parse(line)); } catch { /* skip corrupt lines */ }
  }

  const commits = entries.filter((e) => e.type === 'commit');
  const evidence = entries.filter((e) => e.type === 'evidence');

  const bySeverity = { blocker: 0, major: 0, minor: 0 };
  const byAgent = {};
  let securityBlockers = 0;
  for (const e of evidence) {
    bySeverity.blocker += e.blocker || 0;
    bySeverity.major += e.major || 0;
    bySeverity.minor += e.minor || 0;
    const total = (e.blocker || 0) + (e.major || 0) + (e.minor || 0);
    if (total > 0) byAgent[e.agent] = (byAgent[e.agent] || 0) + total;
    if (e.agent === 'koong-security-auditor') securityBlockers += e.blocker || 0;
  }

  const tierDist = {};
  let iterSum = 0;
  for (const c of commits) {
    tierDist[`T${c.tier}`] = (tierDist[`T${c.tier}`] || 0) + 1;
    iterSum += c.iterations || 1;
  }
  const avgIter = commits.length ? (iterSum / commits.length).toFixed(1) : '0';

  const totalFindings = bySeverity.blocker + bySeverity.major + bySeverity.minor;

  log('koong stats — 하네스가 잡아낸 것들');
  log('');
  log(`  게이트 통과 커밋:        ${commits.length}개`);
  log(`  루프가 잡은 finding:     ${totalFindings}개 (BLOCKER ${bySeverity.blocker} / MAJOR ${bySeverity.major} / MINOR ${bySeverity.minor})`);
  log(`  차단된 보안 BLOCKER:     ${securityBlockers}개`);
  log(`  평균 루프 반복:          ${avgIter}회`);
  const tiers = Object.keys(tierDist).sort().map((t) => `${t}:${tierDist[t]}`).join('  ');
  log(`  티어 분포:               ${tiers || '-'}`);
  if (Object.keys(byAgent).length) {
    log('');
    log('  에이전트별 적발:');
    for (const [agent, n] of Object.entries(byAgent).sort((a, b) => b[1] - a[1])) {
      log(`    ${agent.replace('koong-', '').padEnd(20)} ${n}개`);
    }
  }
  log('');
  log('  * commit 라인은 게이트 훅이 직접 기록합니다 — 에이전트가 조작할 수 없는 수치입니다.');
}

module.exports = { run };
