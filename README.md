# koong-agent

> **한국어로 말하면 백엔드가 나옵니다.**
> A Claude Code-native autonomous backend development harness — harness engineering + loop engineering.

`/koong 회원가입이랑 로그인 만들어줘` — that's the whole workflow. koong interviews you in plain Korean (no jargon, max 4 questions, sensible defaults), confirms a mini-spec, then autonomously explores, implements, tests, security-audits, commits, and opens the PR. Backend experience not required; the output is production-grade anyway.

---

## Why this exists

AI coding agents write plausible code fast — and quietly skip the things that separate a demo from production: ownership checks on every endpoint, idempotency on payment paths, tests that actually exercise behavior, commits that happen only after review. Prompting "please be careful" doesn't fix this. **Enforcement does.**

koong is a *harness*: hooks physically block `git commit`, `git push`, and `gh pr create` until a verify + 4-way review loop reports zero findings against the current diff hash. Change one line after review? The hash changes, the approval dies, the loop reruns. That's the whole trick — the model can't skip the loop, because the loop isn't a suggestion.

## What you get

| | |
|---|---|
| 🔁 **Commit loop** | Before every commit: verifier + code-reviewer + scope-auditor + convention-auditor + security-auditor run **in parallel**, findings get fixed, loop repeats until `FINDINGS: 0` (max 3 iterations, then escalate — never silently ship). |
| 🔀 **PR loop** | Before every push/PR: the same fan-out on the *cumulative branch diff*, plus scripted secret scan and dependency audit. |
| 🔒 **Security doctrine** | Rule-ID system (SEC-*) covering IDOR, authz coverage, mass assignment, JWT pitfalls, payment integrity, SSRF, migrations. Security BLOCKER/MAJOR findings are **never** auto-relaxed — fix it or get an explicit human waiver. |
| ✂️ **Scope discipline** | A dedicated auditor deletes what you didn't ask for. No speculative features, no premature abstractions, no drive-by refactors (the Karpathy rule, enforced). |
| 🌐 **4 stacks** | Java/Spring · Python/FastAPI · Node/Next.js · Go. Stack auto-detected; only that profile loads. Clean code *in that language's idiom* — Go reads like Go, not translated Java. |
| 🤖 **Plan-aware models** | Detects your Claude plan (`Max→opus`, `Pro→sonnet`) and sets all 7 subagents accordingly. |
| 🚀 **Autonomous git** | Commits always; issues + PRs automatically for significant work (auth/payments/security/migrations). Conventional Commits with Korean bodies, Korean PR templates. |
| 🐣 **Beginner mode** | Jargon-free interviews ("출입증(토큰)"), plain-Korean progress lines, destructive-command hard blocks, "this may cost money" warnings, mock-first paid integrations, run-it-yourself ending reports with copy-paste curl examples. |

## Install

```bash
cd your-project        # empty directory is fine too
npx koong-agent init
```

Then in Claude Code:

```
/koong-init                      # once: plan → models, stack → verify commands, mode
/koong 쇼핑몰 백엔드 만들어줘        # everything else
```

No Node? `curl -fsSL https://raw.githubusercontent.com/JOOZOO20/koong-agent/main/install.sh | bash`

Check your environment anytime: `npx koong-agent doctor` · Upgrade: `npx koong-agent update` (preserves your config, model settings, and hand-edited files).

## How the harness works

```
 user: "/koong 지갑 기능 만들어줘"
   │
   ├─ interview (≤4 plain-Korean questions, defaults marked 추천)
   ├─ mini-spec: 만드는 것 / 이건 안 만들어요(non-goals = scope contract) → confirm once
   │
   ▼  autonomous from here
 explore ×4 (parallel) → implement → test-writer ×N (parallel)
   │
   ▼  /koong-commit  ──────────────────────────────┐
 fan-out ×5 (parallel): verifier ┐                 │
   code-reviewer · scope-auditor ├─ findings? ──fix┘ (max 3, fresh agents each round)
   convention · security-auditor ┘
   │ FINDINGS: 0
   ▼
 mark (diff-hash) → git commit   ← PreToolUse hook blocks commit without valid marks
   │  ...repeat per task unit...
   ▼  /koong-pr
 cumulative-diff fan-out + secret scan + dep audit → push → gh pr create (Korean template)
```

**File map** (installed into your project):

```
CLAUDE.md                     orchestration brain (routing, iron rules, parallelism mandate)
.claude/
├── settings.json             hooks + pre-approved permissions (this is what makes it autonomous)
├── agents/koong-*.md         7 subagents
├── skills/koong*/SKILL.md    /koong /koong-new /koong-init /koong-commit /koong-pr /koong-issue
└── koong/scripts/*.sh        gate-git · diff-hash · mark · detect-plan · detect-stack · guards
docs/koong/
├── core-principles.md        scope discipline · clean code · clean architecture · production baseline
├── security.md               the SEC-* doctrine
├── git-policy.md             autonomous git rules · Korean commit/PR/issue formats
├── testing.md                FIRST · Given-When-Then · the Iron Rule
└── profiles/                 java-spring · python · node-nextjs · go
```

## 한국어 요약

**koong-agent는 Claude Code 위에서 백엔드 개발을 자율 수행하는 하네스입니다.**

1. **설치**: `npx koong-agent init` → Claude Code에서 `/koong-init` 한 번.
2. **사용**: `/koong 만들고 싶은 것`을 한국어로. 백엔드를 몰라도 됩니다 — 전문용어 없는 질문 몇 개(추천값 제공)에 답하면 끝.
3. **품질**: 모든 커밋 전에 검증 + 4종 리뷰(정확성·범위·컨벤션·보안)가 병렬로 돌고, 지적이 0이 될 때까지 수정 루프를 반복합니다. **이 루프는 훅이 물리적으로 강제**합니다 — 건너뛸 수 없습니다.
4. **보안**: 소유권 검증, 결제 멱등성, JWT 함정, 시크릿 스캔, 의존성 감사까지. 보안 BLOCKER/MAJOR는 절대 완화되지 않습니다.
5. **git**: 커밋·이슈·PR·푸시 모두 자동. 인증/결제/보안 같은 중요한 작업은 이슈부터 만들고 PR로 마무리합니다.

## License

MIT
