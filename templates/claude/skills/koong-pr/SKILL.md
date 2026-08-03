---
name: koong-pr
description: The koong PR loop — the ONLY path to git push and gh pr create. Verifies the cumulative branch diff (full suite + secret scan + dependency audit + 4 reviewers), then pushes and opens the PR with the Korean template. Use when a domain-level feature is complete.
---

# /koong-pr — PR 루프

`gate-git.sh` blocks `git push` / `gh pr create` without HEAD-keyed pr markers and blocks them entirely on a dirty tree. Complete this loop instead of fighting the gate.

## P0 — Preconditions

- Working tree is clean (every change committed via `/koong-commit`). Dirty → finish `/koong-commit` first.
- Confirm a PR is warranted per `docs/koong/git-policy.md §4` decision table. Small chore-level work → keep accumulating on the branch instead.
- Determine the base branch (main, or the integration branch for Pattern B projects).
- Beginner mode: explain each action in one plain-Korean line.

## P1 — Issue

Significant work (auth/payments/security/migrations/new domain) with no linked issue yet → run `/koong-issue` now; remember the number for `Closes #N`.

## P2 — Fan-out on the CUMULATIVE branch diff

`bash .claude/koong/scripts/mark.sh loop-start pr`, then ONE message, 5 parallel Task calls, diff command = `git diff <base>...HEAD` (PR level is always all 5 agents + full verify — no tier reduction):

- koong-verifier (scope: **pr**, VERIFY_MODE=full) — full suite + coverage + boot-and-exercise + **secret scan + dependency audit scripts** (output to `.claude/koong/state/audit/`)
- koong-code-reviewer / koong-scope-auditor / koong-convention-auditor / koong-security-auditor (scope: pr)

Each agent records its own evidence (`mark.sh evidence <name> pr ...`) — keyed to HEAD, identity-verified by the gate. The cumulative diff catches cross-commit issues the per-commit loops couldn't see. Security BLOCKER/MAJOR → same refute-mode second opinion as /koong-commit S2b.

## P3 — Findings loop (MAX_PR_ITER = 2)

Findings > 0 or FAIL → fix. **Fixes require commits, so each fix round goes through `/koong-commit`** (its own full loop), then re-enter P2. After 2 PR-level iterations with unresolved BLOCKER/MAJOR → same escalation rules as `/koong-commit` (security never waivable except by explicit user waiver; report attempts in Korean; `mark.sh loop-end`).

Non-security MINOR-only remainder after 2 iterations → proceed, list them in the PR body under `## 후속 개선 사항`.

## P4 — Evidence check

All 5 agents recorded clean pr-scope evidence themselves in P2/P3 — there is nothing for you to mark. HEAD-keyed: any new commit invalidates the evidence → re-run P2.

## P5 — Push

`git push -u origin <branch>` (no remote → in beginner mode ask once: "코드를 깃허브에 올려둘까요? 무료이고 비공개예요" → `gh repo create <name> --private --source=. --push`; never `--public`).

## P6 — Create PR

`gh pr create` with:
- Title: broad scope — `type: 넓은 한국어 기능 설명` (e.g., `feat: 지갑 기능 구현`)
- Body: git-policy.md §6.2 template. The `## 검증` section is filled from the actual koong-verifier EVIDENCE/AUDIT output — never hand-written claims. Include `Closes #N`.

`bash .claude/koong/scripts/mark.sh loop-end`, then report the PR URL. Beginner mode: explain what a PR is in one line ("변경 내용을 한눈에 검토할 수 있는 페이지예요").
