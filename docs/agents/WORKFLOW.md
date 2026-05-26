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

### 1.3 Branch Naming Conventions (Strict)

Always use standard prefixes based on the work type:
- `feature/` : New features or functionalities
- `fix/` : Bug fixes for non-critical issues
- `hotfix/` : Urgent fixes for production
- `refactor/` : Code restructuring without behavior change
- `docs/` : Documentation updates
- `chore/` : Build tasks, config, dependency updates

**🚨 Strict Naming Rule:**
Branch names MUST only describe the *purpose* or *domain* of the work. 
**DO NOT include project names, version numbers, agent identifiers, or any other redundant context in the branch name.**

- ❌ `feature/dailyme-v2-agent2-record-dailycall` (Bad: includes project name, version, and agent info)
- ❌ `hotfix/v2-agent3-fix-payment` (Bad: includes version and agent info)
- ❌ `feature/agentA-auth-login` (Bad: includes agent info)
- ✅ `feature/record-dailycall` (Good: domain and purpose only)
- ✅ `hotfix/payment-rounding-error` (Good)

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

Plan → branch → implement → test → self-review → commit and open PR. Follow this order strictly.

### Phase 1. Plan & Branch Before You Work

Before writing any code, you MUST:
1. Clarify the work scope (which domain, which feature).
2. Propose API signatures (URI, method, key request/response fields).
3. **Create and switch to a new branch** following the §1.3 naming convention (e.g., `git checkout -b feature/your-feature-name`). **Do not work directly on `main` or the integration branch.**

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

## 3. Commit Messages — Conventional Commits

### 3.1 Format & Strict Language/Detail Rule

Follows the standard Conventional Commits spec, but **enforces a strict high-quality structure and language separation**:

**🚨 Language Separation Rule:**
- **Code & Syntax:** The commit type (`feat`, `fix`, `hotfix`), scope, branch names, and exact code elements (variable names, class names) **MUST be in English**.
- **Prose & Explanation:** The overall description and the detailed body (context, problems, solutions) **MUST be entirely in Korean.**

> <type>(<scope>): <한국어 요약 설명> [(#issue)]
> 
> - 이전 상황/문제점: <이전에 어떤 기능적 문제, 비효율성, 구조적 한계 또는 제약이 있었는지 한국어로 상세 기술>
> - 해결 방법: <문제를 해결하기 위해 어떤 논리나 아키텍처적 구조를 설계하여 해결했는지 한국어로 기술>
> - 진행 사항:
>   - <영향을 받은 구체적인 클래스/메서드/마이그레이션 파일 작업 내역 1 (클래스명은 영어, 설명은 한국어)>
>   - <영향을 받은 구체적인 클래스/메서드/마이그레이션 파일 작업 내역 2>

#### Best Practice Example:
> fix(auth): 소셜 로그인 연동 시 이메일 중복 가입 자동 병합 차단 및 검증 추가
> 
> - 이전 상황/문제점: 소셜 로그인 연동 시 기존 로컬 계정과 동일한 이메일을 사용할 경우, 별도의 사용자 동의 없이 자동으로 계정이 병합되어 보안 취약점 및 사용자 혼선이 발생하는 문제가 있었음.
> - 해결 방법: 소셜 가입 및 로그인 로직 진입 시 가입 정보의 이메일 존재 여부를 우선 검증하고, 동일 이메일 감지 시 프로세스를 중단한 뒤 명시적인 계정 연동 API 호출을 강제하도록 검증 레이어를 보강함.
> - 진행 사항:
>   - SocialLoginService: 가입 이메일 검증 로직 추가 및 자동 병합 코드 제거
>   - UserCredentialsRepository: 가입 방식별 이메일 중복 조회 쿼리 메서드 추가
>   - ErrorCode: 이메일 중복 가입 충돌 에러 코드(AUTH_DUPLICATE_EMAIL_MERGE_BLOCKED) 추가

### 3.2 type (English, lowercase)

| type | Meaning |
|---|---|
| `feat` | New feature |
| `fix` | Bug fix |
| `hotfix` | Urgent production fix |
| `refactor` | Code restructuring without behavior change |
| `perf` | Performance improvement |
| `test` | Test code added/modified |
| `docs` | Documentation only (no code impact) |
| `chore` | Build, dependencies, config, etc. |

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

Use a consistent lowercase prefix to align perfectly with Conventional Commits (`type(scope): description`). This makes issues, branches, and commits seamlessly traceable.

Format: `type(scope): brief summary` or `type: brief summary` (all lowercase)

| Prefix | Use when |
| :--- | :--- |
| `feat(scope):` or `feat:` | A new feature needs to be tracked and built |
| `fix(scope):` or `fix:` | A bug needs to be tracked and fixed |
| `refactor(scope):` or `refactor:` | Code restructuring / design improvement is needed |

Examples:
* `feat(payment): 카카오페이 결제 게이트웨이 연동`
* `fix(navigation): 모바일 뷰포트에서 네비게이션 바 깨짐 현상 수정`

### 4.3 Issue Body Templates

#### Feature Issue
> ## Context
> 이 기능이 왜 필요한가요? 어떤 문제를 해결하나요?
> 
> ## Requirements
> - [ ] 구현해야 할 상세 기능 1
> - [ ] 구현해야 할 상세 기능 2

#### Bug Issue
> ## Description
> 기대했던 동작과 실제 동작의 차이는 무엇인가요?
> 
> ## Steps to Reproduce
> 1. 특정 페이지로 이동
> 2. 특정 버튼 클릭

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
| Test LOC | (no limit) | 50–100% of production | (no limit) |

### 5.3 Size Violation Rules
- **Above upper bound → split**: Split into CRUD, Read/Write, or Sub-feature boundaries, and provide a "Split Reason".
- **Below lower bound → absorb**: Include the next sub-feature from the same domain.

---

## 6. PR Body Template (Detailed & Structured in Korean)

**🚨 Language Separation Rule:**
Just like commit messages, the PR format uses English for structural elements (code, branches, class names), but **all explanations and prose MUST be strictly in Korean.**

> ## PR 요약
> - <전체적인 작업 목적 및 핵심 요약 1>
> - <전체적인 작업 목적 및 핵심 요약 2>
> 
> ## 진행한 사항
> - <도메인/레이어별 구체적인 변경 사항 및 구현 로직 기술 1>
> - <도메인/레이어별 구체적인 변경 사항 및 구현 로직 기술 2>
> 
> ## 검증
> - `./gradlew test` 성공 여부 및 통과한 테스트 개수 기술
> - `./gradlew jacocoTestReport` 성공 및 최종 커버리지 결과 기술 (예: Coverage 84%)
> 
> ## 영향 범위
> - <이번 커밋으로 인해 영향을 받는 패키지 및 도메인 범위 기술>
> - <공유 컨트랙트 수정 금지 수칙 준수 여부 명시>
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
- CI passing
- Verify deployment status and health check after merge