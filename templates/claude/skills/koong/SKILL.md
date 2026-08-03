---
name: koong
description: The single entry point for backend development — user states a feature in plain Korean ("회원가입이랑 로그인 만들어줘"), koong interviews (jargon-free, max 4 questions), confirms a mini-spec, then autonomously explores → implements → tests → commit-loops → issue/PR. Route every backend feature/bugfix/change request through this skill.
---

# /koong — 백엔드 개발 오케스트레이터

The user says what they want in Korean. You deliver a production-grade backend change: clean code, clean architecture, tests, security, committed and PR'd — autonomously.

## Phase 0 — Preflight (silent)

1. `.claude/koong/config.json` missing → run `/koong-init` first.
2. No source code in the repo (no src/, app/, cmd/, or only the koong payload) → hand off to `/koong-new` with the user's original sentence; it returns here.
3. Read config: `mode`, `stack`, `verify_cmds`. Load `docs/koong/core-principles.md`, `docs/koong/git-policy.md`, and `docs/koong/profiles/<stack>.md` (only that profile).
4. Launch ONE koong-explorer for a quick inventory: what already exists relevant to this request (feeds the interview skip rules).

## Phase 1 — Interview (beginner mode)

**Rules:**
- **R1**: ask only decision-changing questions — different answers must produce different code. Everything else: silent defaults.
- **R2**: max 4 questions, ONE message, numbered, each option marked `(추천)`. Preamble: "몇 가지만 여쭤볼게요. 잘 모르겠으면 '추천대로'라고 하시면 추천값으로 진행해요."
- **R3**: zero jargon. Never say JWT/OAuth/REST/CRUD/토큰/세션/DB를 그대로 — plain words with the technical term in parentheses at most ("출입증(토큰)").
- **R4**: skip anything already answered by (a) the request text, (b) existing code from Phase 0, (c) config. Auth already implemented → never ask about login.
- **R5**: pick the ≤4 highest-impact slots for THIS request from the bank; dropped slots take their defaults.

**Question bank (silent tech mapping):**

| Slot | Question | Mapping |
|---|---|---|
| 사용자 | "이 서비스는 누가 쓰나요? ① 나 혼자/내부용 (추천) ② 일반 사람들이 가입해서 씀" | ① minimal auth, no rate limit ② full user domain + rate limiting + hardened validation |
| 로그인 | "로그인은 어떻게 할까요? ① 이메일+비밀번호 (추천) ② 카카오/구글로 시작 ③ 로그인 없음" | ① local accounts + JWT access/refresh + bcrypt ② OAuth2 + JWT ③ no auth layer |
| 저장 정보 | "어떤 정보를 저장하나요? 생각나는 대로 적어주세요 (예: 상품, 주문, 리뷰). 잘 모르면 제가 알아서 정할게요 (추천)" | free text → domain entities/relations; silence → infer from request |
| 외부 연동 | "결제나 문자/이메일 발송 같은 외부 서비스가 필요한가요? ① 아니요 (추천) ② 결제 ③ 이메일/알림" | ② payments as a **mock module** + "실결제는 PG 계약 필요" doc ③ console/log stub + config placeholder. Never sign the user up for anything. |
| 배포 | "인터넷에 올려서 쓸 계획인가요? ① 일단 내 컴퓨터에서만 (추천) ② 올리고 싶음" | ② Dockerfile + deploy guide doc (no actual deploy — money rail) |

**Expert skip rule**: `mode=expert` OR delegation signals in the request ("그냥", "알아서", "질문 없이", "니가 정해") → skip the interview, print an **assumptions block** once, and proceed immediately:
```
가정하고 진행합니다: <auth 방식> / 도메인: <...> / 외부연동 없음 / 로컬 실행 기준
비범위: <2개 이상>
(다르면 언제든 말씀해주세요 — 즉시 반영합니다)
```
The assumptions replace the mini-spec confirmation; they still bind the scope-auditor. If zero slots are genuinely undecided, don't interview even in beginner mode.

## Phase 2 — Mini-spec + ONE confirmation (beginner mode)

```
📋 이렇게 만들게요

만드는 것
- <기능 1: 비개발자가 이해할 수 있는 한 줄>
- <기능 2>

이건 안 만들어요 (이번 범위 밖)      ← 최소 2개, 반드시
- <non-goal 1>
- <non-goal 2>

나중에 원하시면 추가할 수 있어요: 위 항목 전부 가능해요.

이대로 진행할까요? (네 / 바꾸고 싶은 부분 말씀해주세요)
```

The non-goals list is the **scope-auditor's contract** — pass it verbatim into every loop fan-out. After "네": no more questions until the ending report. Complete the run.

## Phase 3 — Autonomous pipeline

Follow the git-policy §4 decision table from the start: significant work (auth/payments/security/migration/new domain) → `/koong-issue` FIRST, then branch.

1. **Branch**: `git checkout -b feature/<broad-domain>` (git-policy §2).
2. **Explore**: up to 4 koong-explorer in parallel, ONE message (structure/conventions, similar-feature reference, security config, test layout). Never explore serially.
3. **Implement**: production code only, per the stack profile + core-principles. Exactly the spec — the scope-auditor will delete anything extra.
4. **Test**: koong-test-writer ×N in parallel (one per domain/module touched).
5. **Commit**: `/koong-commit` (the full loop — verify + 4 reviewers, fix until zero findings).
6. Repeat 3–5 per task unit until the spec is complete. Stay on the branch; don't push between units.
7. **PR**: `/koong-pr` when the domain feature is complete (per decision table).

**Progress lines** (beginner mode): one plain-Korean line per stage — "🔍 기존 코드 구조를 파악하는 중...", "🛠️ 회원가입 기능을 만드는 중...", "🧪 자동 테스트를 만들고 돌려보는 중...", "🔒 보안 점검 중...", "💾 코드를 저장했어요 (commit)". Expert mode: normal concise reporting.

## Phase 4 — Ending report

Beginner template:
```
✅ 완성됐어요!

## 무엇을 만들었나요
- <기능 요약> (파일 N개, 테스트 N개 전부 통과 ✔)

## 내 컴퓨터에서 실행해보기
터미널에 아래를 순서대로 붙여넣으세요:
    <stack의 실행 명령: ./gradlew bootRun | uv run fastapi dev app/main.py | npm run dev | go run ./cmd/server>
서버가 켜지면 <문서/헬스 URL> 를 열어보세요. 끄려면 Ctrl+C.

## 만들어진 기능 목록
| 기능 | 주소 | 방식 | 설명 |
|---|---|---|---|
| <회원가입> | </api/auth/signup> | POST | <이메일·비밀번호로 가입> |

## 직접 해보기 (복사해서 붙여넣으세요)
    curl -X POST http://localhost:<port>/... -H "Content-Type: application/json" -d '{...}'

## 저장 기록
- 브랜치 <branch>에 커밋 N개, PR: <URL> (이슈 #N 연결)

## 다음에 해보면 좋은 것
1. <다음 기능> → "/koong <한 문장>"

⚠️ 주의: .env 파일에는 비밀 정보가 들어있어요. 절대 다른 사람에게 보내거나 인터넷에 올리지 마세요.
⚠️ 아직 실제로 동작하지 않는 것: <mock 목록 — 예: 결제는 모의 결제 모듈이에요. 실결제는 PG 계약 필요.>
```
Expert mode: same facts, terse form, no hand-holding lines.
