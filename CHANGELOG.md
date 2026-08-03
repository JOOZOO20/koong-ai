# Changelog

All notable changes to koong-agent are documented here (newest first).

## [2.0.0] — 2026-07-05

Complete rebuild: from a markdown directive package to a Claude Code-native autonomous backend harness.

### Added
- **Hook-enforced loops**: PreToolUse gate physically blocks `git commit` / `git push` / `gh pr create` without fresh diff-hash-keyed verify+review markers. Editing after review auto-invalidates approval.
- **7 subagents** (explorer, test-writer, verifier, code-reviewer, scope-auditor, convention-auditor, security-auditor) — models auto-set by Claude plan (Max→opus, Pro→sonnet) via `/koong-init`.
- **6 skills**: `/koong` (jargon-free interview → mini-spec → autonomous pipeline), `/koong-new` (zero-to-scaffold bootstrap), `/koong-init`, `/koong-commit` (5-agent fan-out loop, max 3 iterations), `/koong-pr` (cumulative-diff loop + secret scan + dependency audit), `/koong-issue`.
- **Security doctrine** (`docs/koong/security.md`): rule-ID system (SEC-N/A/I/D/S/E/P/M/O), 10 absolute rules, beginner traps top-15, per-stack implementation table. Security BLOCKER/MAJOR findings are never auto-relaxed — explicit human waiver only.
- **Language profiles**: java-spring, python, node-nextjs, go — auto-selected by stack detection.
- **Beginner mode**: jargon-free questions with recommended defaults, plain-Korean progress lines, destructive-command hard blocks, money-cost warnings, mock-first paid integrations.
- **npm distribution**: `npx koong-agent init | doctor | update` (zero runtime dependencies).

### Removed
- Human-approval requirement for git add/commit/push (replaced by the hook gate).
- `/fork`-based manual test-agent phases; agent-number/todo.md choreography.
- PR size lower bound and the "absorb more features" rule (conflicted with scope discipline).

## [1.0.0]

Initial markdown directive package (AGENTS.md / CLAUDE.md / BACKEND_CONVENTIONS.md / TESTING.md / WORKFLOW.md).
