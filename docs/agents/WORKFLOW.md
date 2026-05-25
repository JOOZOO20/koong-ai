# WORKFLOW.md

> **This document is the single source of truth for git / commit / PR / branch / issue conventions.**
> Designed to work unchanged when copied into any project.
> Coding conventions → `BACKEND_CONVENTIONS.md` | Test conventions → `TESTING.md`
> Project-specific branch policies (e.g., long-lived integration branches, multi-agent ownership) belong in project-specific documents.

---

## 1. Branch Policy (General Patterns)

This section presents two common patterns. Check the project-specific document to see which pattern your project uses (or if it uses a different one).

### 1.1 Pattern A — Simple Trunk-Based (Recommended for small projects)

> production branch:        main
> feature branch base:      main
> feature PR target:        main

- All features branch from `main` and PR back into `main`.
- Small, frequent merges. Requires strong CI.

### 1.2 Pattern B — Long-Lived Integration Branch (Recommended for large changes / parallel work)

> production branch:        main
> integration branch:       <integration-branch-name>   ← all work accumulates here
> feature branch base:      <integration-branch-name>
> feature PR target:        <integration-branch-name>
> final release PR:         <integration-branch-name> → main

- Used for large refactors or concurrent parallel work.
- Fully validate on the integration branch before a single release PR to main.
- The integration branch name and its lifetime are defined in the project-specific document.

### 1.3 Branch Naming

Scope is the domain package name or affected area. Examples:
- `feature/order-create-api`
- `feature/auth-social-login`
- `fix/payment-rounding-error`
- `refactor/notification-template-extraction`

### 1.4 Worktree Branching

When working with **git worktrees**, identify the correct base branch before creating a feature branch:

- **If the project has only a main production branch**: branch directly from `main` using the standard naming pattern above.
- **If the project maintains a long-lived integration branch**: branch from that integration branch instead, not directly from `main`.

The guiding principle: always branch from the most recent common ancestor of all active work in progress. This ensures your feature merges into the right intermediate checkpoint and does not bypass any integration step the project has set up.

### 1.5 Absolute Rules

- Force push to the production branch (`main`) is forbidden.
- Cross-merging between feature branches is forbidden. When a dependency is needed, merge into integration/main first, then re-branch.

---

## 2. Development Workflow

Plan → implement → test → self-review → commit and open PR. Follow this order for any feature, bug fix, or refactor.

### Phase 1. Plan Before You Branch

Before creating a branch, clarify:
- Work scope (which domain, which feature, which user scenario)
- Affected packages / migration numbers / cross-domain dependencies
- API signatures (URI, method, key request/response fields)
- Expected PR size (LOC, file count — based on §5 PR scope guide)

Then create a branch from the correct base (§1.4).

### Phase 2. Implementation

- Write production code following `BACKEND_CONVENTIONS.md`.
- Respect domain boundaries (in parallel-work projects: no changes outside your ownership scope).
- Add migration files if needed, OpenAPI annotations, and file header comments (`BACKEND_CONVENTIONS.md` §17).
- Run `./gradlew spotlessApply` when done. Treat formatting as part of writing code.

### Phase 3. Testing & Validation (Autonomous Loop)

Follow the autonomous test workflow in `TESTING.md` §0:
- The agent seamlessly transitions to writing unit tests and integration/E2E tests without pausing.
- Run the tests. If any test fails, autonomously analyze the root cause and modify the production code or test code to fix it.
- Repeat this self-healing loop until all tests pass perfectly.

Run the full validation suite command when all tests are passing:

> ./gradlew spotlessApply compileJava test jacocoTestReport

If any step fails, return to Phase 2 and fix the production code autonomously.

### Phase 4. Self-Review

Re-read your own diff and verify each item:

1. **Auth / Authz** — SecurityFilterChain classification explicit; correct principal type; authorization checks where needed
2. **SQL Injection** — JPA parameter binding everywhere; no string-concatenated SQL
3. **Sensitive Data Exposure** — No passwords/tokens/PII/payment info in logs, responses, or external notifications; masking applied
4. **Exception Handling** — No `try-catch` in controllers; new exceptions mapped in global handler
5. **N+1** — 1:N queries use `@EntityGraph` or `JOIN FETCH`; no lazy field access in loops
6. **Transactions** — Boundary in Service; read methods `readOnly = true`; cross-domain ops use outbox
7. **Migrations** — Correct number range; soft delete + partial index + TIMESTAMPTZ + FK index pattern; no modifications to existing migrations

All 7 ✅ → proceed to commit and PR.

### Phase 5. Commit & PR

> git status              # review what changed
> git diff --stat         # confirm scope
> git add <files>
> git commit              # follow §3 Conventional Commits format
> git push

Re-verify PR size against §5 before pushing. If over the upper bound, split first (§5.4).

---

## 3. Commit Messages — Detailed Conventional Commits

### 3.1 Format & Strict Detail Rule

Follows the standard Conventional Commits spec, but **with a strict language and detail rule:**
- `<type>` and `<scope>` **MUST be in English lowercase.**
- `<description>` and `<body>` **MUST follow the user's instruction language (e.g., Korean).**
- The `<body>` **MUST be highly detailed and structured.** Do not write a single vague line. You must clearly explain the context, the solution, and the exact changes.

Use this exact format for the commit message:

> <type>(<scope>): <description in user's language> [(#issue)]
> 
> - 이전 상황/문제점: <What was the previous state or problem?>
> - 해결 방법: <How did you approach or solve it?>
> - 진행 사항:
>   - <Detail 1>
>   - <Detail 2>
> 
> <optional footer>

### 3.2 type (English, lowercase)

| type | Meaning |
|---|---|
| `feat` | New feature |
| `fix` | Bug fix |
| `refactor` | Code restructuring without behavior change |
| `perf` | Performance improvement |
| `test` | Test code added/modified |
| `docs` | Documentation only (no code impact) |
| `chore` | Build, dependencies, config, etc. |
| `style` | Formatting, semicolons, etc. |
| `build` | Build system changes (Gradle, Docker, etc.) |
| `ci` | CI pipeline changes (GitHub Actions, etc.) |

### 3.3 scope (English, lowercase) — include when domain-specific, omit when cross-cutting

Include scope when the change is clearly tied to one domain:
- `feat(auth): 소셜 로그인 연동 기능 추가`
- `fix(order): 재고가 0 미만으로 떨어지는 동시성 버그 수정`
- `refactor(notification): 알림 템플릿 렌더링 로직 분리`

---

## 4. Issue Rules

### 4.1 When to Create an Issue (Keep It Minimal)

AI-assisted development moves fast. **Avoid over-creating issues** — they add overhead without value if every small task gets one. Use issues only when the benefit of tracking outweighs the cost.

### 4.2 Issue Title

Use a consistent prefix to align perfectly with Conventional Commits (`type(scope): description`). 
**Title description must also be in the user's instruction language (e.g., Korean).**

| Prefix | Use when |
| :--- | :--- |
| `feat(scope):` or `feat:` | A new feature needs to be tracked and built |
| `fix(scope):` or `fix:` | A bug needs to be tracked and fixed |
| `refactor(scope):` or `refactor:` | Code restructuring / design improvement is needed |

Examples:
* `feat(payment): 카카오페이 결제 게이트웨이 연동`
* `fix(navigation): 모바일 뷰포트에서 네비게이션 바 깨짐 현상 수정`

---

## 5. PR Scope Guide (Core)

### 5.1 PR Unit Definition
**1 PR = 1 "feature slice"** = the minimum unit that a user, operator, or scheduler can "use" or "operate."

### 5.2 Size Criteria

| Metric | Lower bound | Recommended range | Upper bound |
|---|---|---|---|
| Production LOC (excl. test) | 300 | **600–1,500** | 2,500 |
| Changed file count | 5 | **10–30** | 50 |
| Migration file count | 0 | 1–3 | 5 |

### 5.3 PR Completeness Checklist
1. ☐ **Migration** (when schema changes)
2. ☐ **Entity + Repository**
3. ☐ **Service + Business Logic**
4. ☐ **Controller + Request/Response DTOs**
5. ☐ **OpenAPI annotations** (`@Tag`, `@Operation`)
6. ☐ **Service unit tests**
7. ☐ (if applicable) **Repository `@DataJpaTest`** or **controller smoke test**
8. ☐ **Build/test passing**: `./gradlew spotlessApply test jacocoTestReport`

---

## 6. PR Body Template (Detailed & Structured)

The PR body MUST be highly detailed and structured in the user's instruction language (e.g., Korean), following this exact format:

> ## PR 요약 (Summary)
> - <전체적인 작업 목적 및 핵심 요약 1>
> - <전체적인 작업 목적 및 핵심 요약 2>
> 
> ## 진행한 사항 (Changes)
> - <상세 작업 내역 1>
> - <상세 작업 내역 2>
> - <상세 작업 내역 3>
> 
> ## 검증 (Test Evidence)
> - `./gradlew test` 성공
> - `./gradlew jacocoTestReport` 성공
> - `./gradlew jacocoTestCoverageVerification` 결과 (Coverage: XX%)
> 
> ## 영향 범위 (Boundary & Impact)
> - <어느 패키지/도메인까지 수정되었는지 설명>
> - <다른 에이전트의 공유 컨트랙트 등 수정 금지 영역 준수 여부>
> 
> ## Linked Issues
> Closes #123
> 
> ## Checklist
> - [x] BACKEND_CONVENTIONS.md compliant
> - [x] TESTING.md §0 automation workflow complete
> - [x] Within own ownership scope (for parallel-work projects)
> - [x] OpenAPI annotations added
> - [x] ./gradlew spotlessApply
> - [x] ./gradlew test
> - [x] ./gradlew jacocoTestReport

---

## 7. Integration Branch Verification (For Pattern B Projects)

In projects using the integration branch pattern (§1.2), run the following periodically on the integration branch to catch cross-domain regressions:

> ./gradlew spotlessApply
> ./gradlew compileJava
> ./gradlew test
> ./gradlew jacocoTestReport
> ./gradlew jacocoTestCoverageVerification

Before the `integration branch → main` release PR:
- Sync with latest `main` and resolve conflicts
- Verify no API path changes, or confirm compatibility policy
- Validate migration order (Flyway `validate-on-migrate`)
- Confirm production env vars are in sync
- CI passing
- Verify deployment status and health check after merge