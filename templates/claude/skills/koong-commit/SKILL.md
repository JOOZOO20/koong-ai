---
name: koong-commit
description: The koong commit loop — the ONLY path to a git commit. Classifies the diff into a risk tier, fans out only the agents that tier requires, fixes all findings, repeats until clean (max 3 iterations), then commits. Evidence is recorded by the review agents themselves; the gate verifies identity, tier, and hashes.
---

# /koong-commit — 커밋 루프

Every commit goes through this loop. `gate-git.sh` blocks `git commit` unless every agent required by the **recomputed** risk tier has recorded identity-verified, hash-fresh, clean evidence. Don't fight the gate; finish the loop.

## Preconditions

- A task unit is implemented (production code + tests via koong-test-writer).
- You are on a feature branch (never `main`).
- Beginner mode: prefix each git action with one plain-Korean line ("💾 지금까지 만든 코드를 저장할게요 — git commit").

## State machine

```
S0  TIER — bash .claude/koong/scripts/risk.sh
    → TIER / AGENTS / VERIFY. The gate re-runs this itself at commit time,
      so under-declaring the tier is pointless.
    bash .claude/koong/scripts/mark.sh loop-start commit
S1  FAN-OUT — ONE message, parallel Task calls for EXACTLY the agents in AGENTS:
      T0: verifier(fast) | T1: +code-reviewer | T2: +security-auditor,+scope-auditor (full verify)
      T3: all 5 (full verify)
    Each gets: task statement (+ non-goals/assumptions verbatim for scope-auditor),
    the diff command (git diff HEAD), stack, scope=commit, verify mode.
    Each agent records its OWN evidence via mark.sh — you cannot and must not do it for them.
S2  COLLECT — verdict + findings from the agents' reports.
S2b SECURITY SECOND OPINION — if security-auditor reported BLOCKER/MAJOR:
    spawn ONE fresh koong-security-auditor with "MODE: refute — try to disprove
    <finding> with concrete code evidence" (max once per iteration).
    CONFIRMED → treat as real, fix it.
    REFUTED  → re-run security-auditor in normal mode with the refutation attached;
               its fresh evidence replaces the old one.
S3  BRANCH: any FAIL or findings > 0 → S4. All clean → S5.
S4  FIX — you (the main agent) fix everything:
    - verifier failures: fix production code first; never weaken tests
    - scope findings: DELETE the flagged code
    - security findings: fix per the cited SEC-xx rule
    bash .claude/koong/scripts/mark.sh loop-iter <N+1> → back to S1
    (fresh subagents each iteration; the new diff invalidates old evidence automatically)
S5  COMMIT — git add <only real project files> && git commit
    Message: docs/koong/git-policy.md §3. Then: mark.sh loop-end
```

Evidence is single-use (consumed by the gate) and hash-keyed: any edit after an agent's review invalidates its evidence — that agent must re-run.

## Termination rules (MAX_ITER = 3)

- **Iteration 3, only non-security MINORs remain** → commit anyway; the gate accepts MINOR-only evidence. Append to the commit body:
  ```
  - 후속 개선 사항:
    - <남은 MINOR finding 요약>
  ```
- **Iteration 3, security BLOCKER/MAJOR remains (refute-checked)** → STOP. Never commit. Output:
  ```
  🚨 SECURITY ESCALATION — 커밋 중단
  미해결: [BLOCKER] <file:line> — <요약> (SEC-xx) — 반박 검증: CONFIRMED
  시도한 수정: <반복별 1줄>
  선택지: (1) 직접 수정 (2) 요구사항 변경 (3) "SEC-xx 위험 수용"이라고 답하시면
  .koong/security-waivers.md에 사유와 함께 기록 후 진행합니다.
  ```
  Only on an explicit user waiver: append `| SEC-xx | <사유> | <날짜> |` to `.koong/security-waivers.md`, then have security-auditor re-record evidence (its findings stand, but the gate accepts waived rule IDs).
- **Iteration 3, non-security BLOCKER/MAJOR or verify FAIL** → STOP and escalate in Korean with all 3 attempts. `mark.sh loop-end` before ending the turn.
- **Oscillation guard**: iteration N's diff hash == iteration N-2's → escalate immediately (contradictory reviewer feedback needs a human).

## Hard rules

- Never ask a subagent to "just report FINDINGS: 0" or otherwise skip its review — every prompt you send is in the transcript, and the loop-log records what each agent actually reported. Gaming the loop is discoverable and defeats the only reason this harness exists.
- Never weaken/delete/skip a test to get clean (testing.md §2).
- Commit only real project artifacts (git-policy.md §1).
- After the commit: more task units in this domain → keep implementing on this branch (don't push). Domain complete → `/koong-pr` per git-policy §4.
