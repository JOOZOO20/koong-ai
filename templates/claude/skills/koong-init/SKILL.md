---
name: koong-init
description: One-time koong setup for a project — detects the Claude plan and rewrites all agent models (max→opus, pro→sonnet), detects the stack and verify commands, sets beginner/expert mode, writes config.json. Run when SessionStart reports missing config or plan/stack drift.
---

# /koong-init — 1회 셋업

## 1. Plan detection → agent models

```
bash .claude/koong/scripts/detect-plan.sh   # → max | pro | unknown
```

- `max` → MODEL=`opus`, `pro` → MODEL=`sonnet`.
- `unknown` (API key user / no jq): ask ONCE — "Claude 요금제가 어떻게 되세요? (Max / Pro / API 키 사용)" — Max→opus, Pro→sonnet, API→opus. Persist the answer in config.json so this is never asked again.

Set the model for **all 7** agents with the sanctioned script (direct Write/Edit on agent files is hook-blocked):

```
bash .claude/koong/scripts/set-model.sh <opus|sonnet>
```

## 2. Stack detection → verify commands

```
bash .claude/koong/scripts/detect-stack.sh   # → java-spring | python | node-nextjs | go | unknown
```

Derive `verify_cmds` (full) AND `verify_fast_cmds` (quick mid-loop feedback) by probing what actually exists (don't assume):
- fast = the cheapest meaningful subset: java `./gradlew compileJava` + 해당 도메인 테스트, python `ruff check . && pytest <변경 경로>`, node `npx tsc --noEmit && npm test -- <관련 테스트>`, go `go build ./... && go test ./<변경 패키지>`. 도출이 어려우면 full과 동일하게.

Full commands per stack:
- **java-spring**: `./gradlew spotlessApply compileJava test jacocoTestReport` — drop tasks the build doesn't have (check `./gradlew tasks --all | grep -E 'spotless|jacoco'`); pom.xml → `./mvnw verify`.
- **python**: build from available tools: `ruff check .`, `ruff format --check .`, `mypy .`, `pytest` — include only those installed/configured (check pyproject.toml).
- **node-nextjs**: from package.json scripts: `npm run lint`, `npx tsc --noEmit` (if tsconfig), `npm test` (if test script), `npm run build`. Respect the lockfile's package manager.
- **go**: `gofmt -l .`, `go vet ./...`, `go test ./...`, `go build ./...` (+ `golangci-lint run` if `.golangci.yml` exists).
- **unknown**: tell the user to run `/koong-new` for a fresh project, or ask what the build/test commands are.

## 3. Mode

If config.json doesn't exist yet, ask once: "백엔드 개발이 처음이신가요? (네 → 쉬운 설명 모드 / 아니요 → 전문가 모드)" → `beginner` | `expert`. (Skip if `/koong-new` already set it.) User can flip anytime ("전문가 모드로 해줘" → edit config.json).

## 4. Write config

`.claude/koong/config.json`:
```json
{
  "plan": "max",
  "agent_model": "opus",
  "stack": "java-spring",
  "mode": "beginner",
  "verify_cmds": ["./gradlew spotlessApply compileJava test jacocoTestReport"],
  "verify_fast_cmds": ["./gradlew compileJava test --tests '*<domain>*'"],
  "allow_manual_marks": false
}
```
(`allow_manual_marks`는 항상 false로 생성 — 디버깅용 탈출구이며 true면 doctor가 경고한다.)

## 5. Housekeeping

- Append to `.gitignore` if missing: `.claude/koong/state/`
- `gh auth status` — not logged in → note that issue/PR automation needs `gh auth login` (don't block; commits still work).
- `jq` missing → warn: the git gate degrades without it (`brew install jq`).

## 6. Report (Korean)

Summarize: 요금제/모델, 스택, verify 명령, 모드, gh/jq 상태, and "이제 `/koong 만들고 싶은 것`을 한국어로 말씀하세요."
