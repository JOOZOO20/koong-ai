#!/usr/bin/env node
'use strict';
// koong CLI — init | doctor | update

const cmd = process.argv[2];
const cwd = process.cwd();

const HELP = `
koong-agent — Claude Code 자율 백엔드 개발 하네스

사용법:
  npx koong-agent init      현재 프로젝트에 koong 하네스 설치
  npx koong-agent doctor    환경 진단 + 하네스 무결성 검사
  npx koong-agent stats     루프가 잡아낸 finding 통계 (loop-log 기반)
  npx koong-agent update    하네스 업데이트 (설정과 수정 파일은 보존)

설치 후: Claude Code를 열고 /koong-init → /koong <만들고 싶은 것>
`;

async function main() {
  switch (cmd) {
    case 'init':
      require('../lib/init').run(cwd);
      break;
    case 'doctor':
      require('../lib/doctor').run(cwd);
      break;
    case 'stats':
      require('../lib/stats').run(cwd);
      break;
    case 'update':
      await require('../lib/update').run(cwd);
      break;
    case undefined:
    case 'help':
    case '--help':
    case '-h':
      console.log(HELP);
      break;
    default:
      console.error(`알 수 없는 명령: ${cmd}`);
      console.log(HELP);
      process.exitCode = 1;
  }
}

main().catch((err) => {
  console.error('koong: 오류가 발생했습니다 —', err.message);
  process.exitCode = 1;
});
