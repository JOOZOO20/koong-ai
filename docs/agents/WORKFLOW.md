# WORKFLOW.md

> **This document is the single source of truth for git / commit / PR / branch / issue conventions.**
> Designed to work unchanged when copied into any project.
> Coding conventions → `BACKEND_CONVENTIONS.md` | Test conventions → `TESTING.md`
> Project-specific branch policies (e.g., long-lived integration branches, multi-agent ownership) belong in project-specific documents.

---

## 1. Branch Policy (General Patterns)

This section presents two common patterns. Check the project-specific document to see which pattern your project uses (or if it uses a different one).

### 1.1 Pattern A — Simple Trunk-Based (Recommended for small projects)

```
production branch:        main
feature branch base:      main
feature PR target:        main
```

- All features branch from `main` and PR back into `main`.
- Small, frequent merges. Requires strong CI.

### 1.2 Pattern B — Long-Lived Integration Branch (Recommended for large changes / parallel work)

```
production branch:        main
integration branch:       <integration-branch-name>   ← all work accumulates here
feature branch base:      <integration-branch-name>
feature PR target:        <integration-branch-name>
final release PR:         <integration-branch-name> → main
```

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
- Run `./gradlew spotlessApply when done. Treat formatting as part of writing code.`

### Phase 3. Testing & Validation

Follow the multi-agent test workflow in `TESTING.md` §0:
- Main Agent completes production code, then pauses and prompts user to invoke Test Agent via `/fork`
- Test Agent writes unit tests and integration/E2E tests
- Main Agent resumes, runs tests, fixes production code if needed

Run the full validation suite command when all tests are passing:
```bash
./gradlew spotlessApply compileJava test jacocoTestReport
```

If any step fails, return to Phase 2 and fix the production code.

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

```bash
git status              # review what changed
git diff --stat         # confirm scope
git add <files>
git commit              # follow §3 Conventional Commits format
git push
```

Re-verify PR size against §5 before pushing. If over the upper bound, split first (§5.4).

---

## 3. Commit Messages — Conventional Commits

### 3.1 Format

Follows the standard Conventional Commits spec without modifications.

```
<type>(<scope>): <description> [(#issue)]

<body — multiple lines, what and why>

<optional footer>
```

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
- `feat(auth): add social login`
- `fix(order): guard against negative stock`
- `refactor(notification): extract template rendering`

**Omit scope** when the change is cross-cutting, infrastructure-wide, or not tied to a specific domain:
- `refactor: restructure global error handler`
- `chore: upgrade Spring Boot to 3.5.x`
- `docs: update API onboarding guide`

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
| `docs:` | Documentation, markdown guides, or API docs to write |
| `chore:` | Dependency updates, build config, housekeeping |

Examples:
* `feat(payment): kakao pay gateway integration`
* `fix(navigation): bar breaks on mobile viewport`
* `refactor(notification): make post-order delivery async`

### 4.3 Labels (Recommended)
Labels let you filter issues without bloating titles. Suggested label categories:
- **Type**: `feature`, `bug`, `refactor`, `documentation`, `chore`
- **Priority**: `P1` (critical), `P2` (high), `P3` (normal), `P4` (low)

### 4.4 Issue Body Templates

#### Feature Issue
```markdown
## Context
Why does this feature need to exist? What problem does it solve?

## Requirements
- [ ] Specific thing to implement
- [ ] Another specific thing

## References
- Design mockup / Figma link
```

#### Bug Issue
```markdown
## Description
What is the bug? What was expected vs. what actually happens?

## Steps to Reproduce
1. Go to ...
2. Click ...

## Screenshots / Logs
(Attach error screenshot or relevant log snippet)
```

### 4.5 Linking Issues to PRs
In the PR body: `Closes #123` or `Fixes #123`. Use `Refs #45` when the PR is related but does not fully resolve it.

---

## 5. PR Scope Guide (Core)

### 5.1 PR Unit Definition
**1 PR = 1 "feature slice"** = the minimum unit that a user, operator, or scheduler can "use" or "operate."

Good PR titles:
- ✅ `feat(order): implement order creation with stock reservation`
- ✅ `feat(payment): implement Stripe gateway adapter`
- ✅ `refactor: restructure global error handler`

### 5.2 Size Criteria

| Metric | Lower bound | Recommended range | Upper bound |
|---|---|---|---|
| Production LOC (excl. test) | 300 | **600–1,500** | 2,500 |
| Changed file count | 5 | **10–30** | 50 |
| Migration file count | 0 | 1–3 | 5 |
| Test LOC | (no limit) | 50–100% of production | (no limit) |

### 5.3 PR Completeness Checklist
1. ☐ **Migration** (when schema changes)
2. ☐ **Entity + Repository**
3. ☐ **Service + Business Logic**
4. ☐ **Controller + Request/Response DTOs**
5. ☐ **OpenAPI annotations** (`@Tag`, `@Operation`)
6. ☐ **Service unit tests**
7. ☐ (if applicable) **Repository `@DataJpaTest`** or **controller smoke test**
8. ☐ **Build/test passing**: `./gradlew spotlessApply test jacocoTestReport`

### 5.4 Size Violation Rules
- **Above upper bound → split**: Split into CRUD, Read/Write, or Sub-feature boundaries, and provide a "Split Reason".
- **Below lower bound → absorb**: Include the next sub-feature from the same domain.

---

## 6. PR Body Template

```markdown
## Summary
<1–3 sentences. What was done and why.>

## Changes
- <Key changes by domain/layer>

## API Changes (if any)
- `POST /orders` (new)

## Migrations
- `V42__create_order_table.sql`

## Test Evidence
- `./gradlew test`: ✅ N tests passing
- `./gradlew jacocoTestCoverageVerification`: ✅ passing

## Size
- LOC (production, excl. test): ~1,100
- Changed files: 18

## Boundary Check
- Changed packages: `com.example.order`
- No external domain changes ✅

## Linked Issues
Closes #123

## Checklist
- [x] BACKEND_CONVENTIONS.md compliant
- [x] TESTING.md §0 automation workflow complete
- [x] Within own ownership scope (for parallel-work projects)
- [x] OpenAPI annotations added
- [x] ./gradlew spotlessApply
- [x] ./gradlew test
- [x] ./gradlew jacocoTestReport
```

---

## 7. Integration Branch Verification (For Pattern B Projects)

In projects using the integration branch pattern (§1.2), run the following periodically on the integration branch to catch cross-domain regressions:

```bash
./gradlew spotlessApply
./gradlew compileJava
./gradlew test
./gradlew jacocoTestReport
./gradlew jacocoTestCoverageVerification
```

Before the `integration branch → main` release PR:
- Sync with latest `main` and resolve conflicts
- Verify no API path changes, or confirm compatibility policy
- Validate migration order (Flyway `validate-on-migrate`)
- Confirm production env vars are in sync
- CI passing
- Verify deployment status and health check after merge
```