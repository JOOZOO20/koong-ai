# koong Git Policy (git-policy.md)

> **Single source of truth for autonomous git behavior: branches, commits, issues, PRs, and when to do what.**
> The commit/PR loops themselves live in the `/koong-commit` and `/koong-pr` skills; this document defines the formats and decision rules they follow.

---

## §1 Autonomy Declaration

- The agent commits, creates issues, opens PRs, and pushes **without asking for human approval**. The only gate is the hook-enforced verify+review loop (`gate-git.sh`) — if the markers are valid, act.
- In `beginner` mode, every git/gh action is preceded by one plain-Korean explanation line (e.g., "💾 지금까지 만든 코드를 저장할게요 — git commit").
- **Forbidden regardless of mode**:
  - Force-push to `main` (or any push with `--force*`) — hook-blocked.
  - Amending pushed commits — hook-blocked.
  - Committing meta-documents (plans, agent notes, todo lists). Only real project artifacts: source, tests, migrations, project docs.
  - `gh repo create --public` without an explicit user sentence asking for public. Default is always `--private`.

---

## §2 Branch Policy

### 2.1 Patterns

**Pattern A — Trunk-based (default for small projects)**: all features branch from `main`, PR back into `main`.

**Pattern B — Long-lived integration branch (large parallel work)**: features branch from and PR into the integration branch; a single release PR goes `integration → main` after full validation.

### 2.2 Branch Naming (Strict)

Prefixes: `feature/` `fix/` `hotfix/` `refactor/` `docs/` `chore/`

- **No redundant context**: never include project names, version numbers, or agent identifiers.
- **Broad scope**: a branch accumulates multiple granular commits for one domain-level PR, so name it after the **broad feature or domain**, not a micro-task.

| | |
|---|---|
| ❌ `feature/v2-auth-login` | version token |
| ❌ `feature/wallet-balance-api` | too granular |
| ✅ `feature/auth` | broad domain |
| ✅ `feature/wallet` | holds balance + charge + deduction commits |
| ✅ `hotfix/payment-rounding-error` | hotfixes may be specific |

Never work directly on `main` or the integration branch. Cross-merging between feature branches is forbidden — merge into the base first, then re-branch.

---

## §3 Commit Messages — Conventional Commits (Korean body)

### 3.1 Format

- **English**: commit type, branch names, code identifiers.
- **Korean**: the summary description and the entire body.
- **NO scope parentheses**: `type: 설명` only. ❌ `feat(wallet): ...` ✅ `feat: ...`
- No agent identifiers. Describe *what*, not *who*.

```
<type>: <한국어 요약 설명> [(#issue)]

- 이전 상황/문제점: <어떤 기능적 문제, 비효율, 구조적 한계가 있었는지 한국어로 상세 기술>
- 해결 방법: <어떤 논리/아키텍처로 해결했는지 한국어로 기술>
- 진행 사항:
  - <클래스/모듈/마이그레이션 단위 작업 내역 1 (식별자는 영어, 설명은 한국어)>
  - <작업 내역 2>
```

Example:

```
fix: 소셜 로그인 연동 시 이메일 중복 가입 자동 병합 차단 및 검증 추가

- 이전 상황/문제점: 소셜 로그인 연동 시 기존 로컬 계정과 동일한 이메일을 사용할 경우, 별도의 사용자 동의 없이
  자동으로 계정이 병합되어 보안 취약점 및 사용자 혼선이 발생하는 문제가 있었음.
- 해결 방법: 소셜 가입 및 로그인 전 가입 정보의 이메일 존재 여부를 우선 검증하고, 동일 이메일 감지 시
  명시적인 연동을 강제하도록 검증 레이어를 보강함.
- 진행 사항:
  - SocialLoginService: 가입 이메일 검증 로직 추가 및 자동 병합 코드 제거
  - UserCredentialsRepository: 가입 방식별 이메일 중복 조회 쿼리 추가
  - ErrorCode: 중복 가입 충돌 에러 코드(AUTH_DUPLICATE_EMAIL) 추가
```

When the commit loop ends at iteration 3 with only non-security MINOR findings remaining, append them to the body:

```
- 후속 개선 사항:
  - <남은 MINOR finding 요약>
```

### 3.2 Types

| type | Meaning |
|---|---|
| `feat` | New feature |
| `fix` | Bug fix |
| `hotfix` | Urgent production fix |
| `refactor` | Restructuring without behavior change |
| `perf` | Performance improvement |
| `test` | Test code only |
| `docs` | Documentation only |
| `chore` | Build, deps, config |

---

## §4 Issue / PR / Commit Decision Table

| Work | Issue | Branch | PR | Push |
|---|---|---|---|---|
| Auth/authz, payments, security-sensitive, data-loss-risk migration | ✅ create **first** | ✅ | ✅ | at PR |
| New domain / large feature (≥ ~300 production LOC or ≥ 3 commits) | ✅ | ✅ | ✅ | at PR |
| Regular feature/bugfix in an existing domain | ❌ | ✅ | ✅ | at PR |
| Small fix / refactor / docs / chore (1 commit, no behavior risk) | ❌ | ✅ | bundle into the domain PR when the domain work wraps | at PR |

- **Commits happen always** — every completed task unit goes through `/koong-commit`. The table only decides issue/PR ceremony.
- Issues are created via `/koong-issue` **before implementation starts** for the first row, and any time tracking adds value. Avoid over-creating issues for micro-tasks.

---

## §5 Issue Format

Title: `type: 한국어 요약` (lowercase type, no scope parens). Examples: `feat: 카카오페이 결제 게이트웨이 연동`, `fix: 모바일 뷰포트에서 네비게이션 바 깨짐 현상 수정`

**Feature issue body**
```
## Context
이 기능이 왜 필요한가요? 어떤 문제를 해결하나요?

## Requirements
- [ ] 구현해야 할 상세 기능 1
- [ ] 구현해야 할 상세 기능 2
```

**Bug issue body**
```
## Description
기대했던 동작과 실제 동작의 차이는 무엇인가요?

## Steps to Reproduce
1. ...
2. ...
```

---

## §6 PR Rules

### 6.1 Scope

**1 PR = 1 domain-level feature.** Not one PR per API. A PR groups the cohesive commits of one broad feature (`feat: 지갑 기능 구현` containing balance, charge, deduction commits).

- Upper bound: production LOC > 2,500 or files > 50 → **split** (by CRUD, read/write, or sub-feature) and state the split reason.
- There is **no lower bound**. Never add unrequested features to make a PR bigger — that violates scope discipline (core-principles.md §1).

### 6.2 PR Body Template (Korean)

Title: broad scope — `type: 넓은 한국어 기능 설명` (e.g., `feat: 지갑 기능 구현`).

```
## PR 요약
- <전체 작업 목적 및 핵심 요약>

## 진행한 사항
- <도메인/레이어별 변경 사항 및 구현 로직 (커밋 내용 통합 요약)>

## 검증
- <koong-verifier 증거: 실행한 verify 명령과 결과, 테스트 개수/커버리지, 실제 구동 확인 내역>
- <PR 레벨 스크립트 게이트 결과: 시크릿 스캔, 의존성 감사>

## 영향 범위
- <영향받는 패키지/도메인>

## Linked Issues
Closes #<N>

## Checklist
- [ ] core-principles.md / 스택 프로파일 준수
- [ ] /koong-commit 루프 전 커밋 통과 (FINDINGS: 0)
- [ ] /koong-pr 루프 통과 (누적 diff 검증)
- [ ] security.md 위반 없음 (waiver 있으면 명시)
```

The 검증 section is filled from actual koong-verifier output — never hand-written claims.

### 6.3 Integration-Branch Projects (Pattern B)

Before the `integration → main` release PR: sync with latest `main`, resolve conflicts, CI green, run the full verify suite on the integration branch.
