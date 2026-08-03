---
name: koong-issue
description: Creates a GitHub issue per the koong git-policy decision table (auth/payments/security/migrations/new-domain work gets an issue BEFORE implementation). Returns the issue number for Closes #N linking.
---

# /koong-issue — 이슈 생성

## When (git-policy.md §4)

- Auth/authz, payments, security-sensitive, data-loss-risk migration work → **always, before implementation starts**.
- New domain / large feature (≥ ~300 production LOC or ≥ 3 commits expected) → yes.
- Regular features/bugfixes/chores → no issue. Don't over-create; if in doubt for small work, skip.

## How

1. Check `gh auth status` — not authed → tell the user issue automation needs `gh auth login`, continue without an issue.
2. Title: `type: 한국어 요약` (lowercase type, no scope parens, no agent mentions). e.g. `feat: 카카오페이 결제 게이트웨이 연동`
3. Body — feature:
   ```
   ## Context
   <이 기능이 왜 필요한지, 어떤 문제를 해결하는지>

   ## Requirements
   - [ ] <상세 기능 1>
   - [ ] <상세 기능 2>
   ```
   Body — bug:
   ```
   ## Description
   <기대 동작 vs 실제 동작>

   ## Steps to Reproduce
   1. <재현 절차>
   ```
4. `gh issue create --title "..." --body "..."` → capture the issue number, report it, and carry it to the eventual PR's `Closes #N`.
5. Beginner mode: one-line explanation — "📋 할 일을 깃허브에 기록해둘게요 (이슈 #N)".
