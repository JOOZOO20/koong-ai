#!/usr/bin/env bash
# risk.sh — deterministic risk-tier classification of the current change set.
# The gate runs this itself at commit time, so the orchestrator cannot
# under-declare a tier. No LLM judgment involved.
#
# Usage: risk.sh [base-ref]     (no arg = working diff vs HEAD; base-ref = PR mode)
# Output (stdout, key=value lines):
#   TIER=0|1|2|3
#   AGENTS=comma,separated,agent,names
#   VERIFY=fast|full
#   REASONS=...
set -uo pipefail

DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$DIR"

BASE="${1:-}"

if [ -n "$BASE" ]; then
  NUMSTAT=$(git diff "$BASE"...HEAD --numstat 2>/dev/null || true)
  FILES=$(git diff "$BASE"...HEAD --name-status 2>/dev/null || true)
  CONTENT=$(git diff "$BASE"...HEAD --unified=0 2>/dev/null | grep '^+' || true)
else
  NUMSTAT=$( { git diff HEAD --numstat 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null | awk '{print "0\t0\t"$0}'; } )
  FILES=$( { git diff HEAD --name-status 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null | awk '{print "A\t"$0}'; } )
  CONTENT=$( { git diff HEAD --unified=0 2>/dev/null | grep '^+'; git ls-files --others --exclude-standard -z 2>/dev/null | xargs -0 cat 2>/dev/null; } || true )
fi

PATHS=$(printf '%s\n' "$FILES" | awk '{print $2}')
N_FILES=$(printf '%s\n' "$PATHS" | grep -c . || true)
INSERTIONS=$(printf '%s\n' "$NUMSTAT" | awk '{ if ($1 ~ /^[0-9]+$/) s += $1 } END { print s+0 }')

TIER=2
REASONS=""
add_reason() { REASONS="${REASONS:+$REASONS; }$1"; }

# ── docs-only → T0 ───────────────────────────────────────────────────────────
if [ "$N_FILES" -gt 0 ] && ! printf '%s\n' "$PATHS" | grep -qvE '\.(md|txt|rst|adoc)$|^LICENSE|^NOTICE|^\.gitignore$'; then
  TIER=0; add_reason "docs-only"
else
  HIGH_RISK='auth|login|jwt|token|password|passwd|payment|billing|charge|refund|wallet|balance|migration|security|cors|crypto|secret|permission|role|admin'

  # harness tampering = always max review
  if printf '%s\n' "$PATHS" | grep -qE '^\.claude/|^CLAUDE\.md$|^\.koong/'; then
    TIER=3; add_reason "harness-files-touched"
  elif printf '%s\n' "$PATHS" | grep -qiE "$HIGH_RISK" || printf '%s' "$CONTENT" | grep -qiE "$HIGH_RISK"; then
    TIER=3; add_reason "high-risk-signal"
  elif printf '%s\n' "$FILES" | grep -E '^D' | awk '{print $2}' | grep -qiE '(test|spec)'; then
    TIER=3; add_reason "test-deletion"
  elif [ "$INSERTIONS" -gt 400 ] || [ "$N_FILES" -gt 15 ]; then
    TIER=3; add_reason "large-change(${INSERTIONS}L/${N_FILES}f)"
  elif printf '%s\n' "$PATHS" | grep -qiE '(controller|router|handler|routes|middleware)|(^|/)api/'; then
    TIER=2; add_reason "transport-layer"
  elif [ "$INSERTIONS" -le 60 ] && [ "$N_FILES" -le 3 ]; then
    TIER=1; add_reason "small-low-risk(${INSERTIONS}L/${N_FILES}f)"
  else
    TIER=2; add_reason "default(${INSERTIONS}L/${N_FILES}f)"
  fi
fi

# PR mode never goes below full fan-out
if [ -n "$BASE" ]; then
  TIER=3; add_reason "pr-level"
fi

case "$TIER" in
  0) AGENTS="koong-verifier"; VERIFY="fast" ;;
  1) AGENTS="koong-verifier,koong-code-reviewer"; VERIFY="fast" ;;
  2) AGENTS="koong-verifier,koong-code-reviewer,koong-security-auditor,koong-scope-auditor"; VERIFY="full" ;;
  3) AGENTS="koong-verifier,koong-code-reviewer,koong-security-auditor,koong-scope-auditor,koong-convention-auditor"; VERIFY="full" ;;
esac

echo "TIER=$TIER"
echo "AGENTS=$AGENTS"
echo "VERIFY=$VERIFY"
echo "REASONS=$REASONS"
