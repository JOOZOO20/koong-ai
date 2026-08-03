#!/usr/bin/env bash
# mark.sh — loop-state markers validated by gate-git.sh.
#
# Usage:
#   mark.sh evidence <agent-name> <commit|pr> "<final output block>"
#       Records the agent's verdict as evidence. ONLY the agent itself may call
#       this — gate-git.sh verifies the caller's agent_type from the hook input.
#       For koong-security-auditor, SEC_BM / SEC_RULES are computed HERE by
#       deterministic parsing (not self-reported).
#   mark.sh bootstrap                # one-time pass for the scaffold commit
#   mark.sh money-ok                 # user explicitly approved a may-cost-money command
#   mark.sh loop-start NAME | loop-iter N | loop-end
#
# Legacy manual marks (verify/review/pr-verify/pr-review) exist ONLY as a
# debugging escape hatch and require config.json: "allow_manual_marks": true.
set -euo pipefail

DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SCRIPTS="$DIR/.claude/koong/scripts"
STATE="$DIR/.claude/koong/state"
CONFIG="$DIR/.claude/koong/config.json"
LOOPLOG="$DIR/.koong/loop-log.jsonl"
mkdir -p "$STATE/evidence"

cmd="${1:?usage: mark.sh evidence|bootstrap|money-ok|loop-start|loop-iter|loop-end}"

manual_allowed() {
  command -v jq >/dev/null 2>&1 && [ -f "$CONFIG" ] && \
    [ "$(jq -r '.allow_manual_marks // false' "$CONFIG" 2>/dev/null)" = "true" ]
}

case "$cmd" in
  evidence)
    agent="${2:?agent name}"
    scope="${3:?commit|pr}"
    verdict="${4:-}"
    case "$agent" in
      koong-verifier|koong-code-reviewer|koong-scope-auditor|koong-convention-auditor|koong-security-auditor) ;;
      *) echo "mark.sh: unknown agent '$agent'" >&2; exit 1 ;;
    esac
    case "$scope" in commit|pr) ;; *) echo "mark.sh: scope must be commit|pr" >&2; exit 1 ;; esac

    if [ "$scope" = "pr" ]; then
      KEY=$(git -C "$DIR" rev-parse HEAD)
    else
      KEY=$(bash "$SCRIPTS/diff-hash.sh")
    fi

    FILE="$STATE/evidence/$agent.$scope.ok"
    {
      echo "$KEY"
      printf '%s\n' "$verdict"
    } > "$FILE"

    # deterministic severity parse (counts come from the text, not self-report)
    N_B=$(printf '%s\n' "$verdict" | grep -c '^\[BLOCKER\]' || true)
    N_M=$(printf '%s\n' "$verdict" | grep -c '^\[MAJOR\]' || true)
    N_N=$(printf '%s\n' "$verdict" | grep -c '^\[MINOR\]' || true)
    if [ "$agent" = "koong-security-auditor" ]; then
      RULES=$(printf '%s\n' "$verdict" | grep -E '^\[(BLOCKER|MAJOR)\]' | grep -oE 'SEC-[A-Z0-9]+' | sort -u | tr '\n' ' ' | sed 's/ $//')
      {
        echo "SEC_BM=$((N_B + N_M))"
        echo "SEC_RULES=$RULES"
      } >> "$FILE"
    fi

    # telemetry line (loop-log is protected from direct agent writes; this
    # script is the only sanctioned writer besides the gate)
    mkdir -p "$DIR/.koong"
    printf '{"ts":"%s","type":"evidence","agent":"%s","scope":"%s","blocker":%s,"major":%s,"minor":%s,"key":"%s"}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$agent" "$scope" "$N_B" "$N_M" "$N_N" "$(printf '%s' "$KEY" | cut -c1-8)" >> "$LOOPLOG"
    ;;
  bootstrap)
    echo "1" > "$STATE/bootstrap.ok"
    ;;
  money-ok)
    echo "1" > "$STATE/money.ok"
    ;;
  loop-start)
    printf '{"loop":"%s","iteration":1,"status":"in_progress"}\n' "${2:?loop name}" > "$STATE/loop.json"
    rm -f "$STATE/stop-blocks"
    ;;
  loop-iter)
    name=$(sed -n 's/.*"loop":"\([^"]*\)".*/\1/p' "$STATE/loop.json" 2>/dev/null || echo "commit")
    printf '{"loop":"%s","iteration":%s,"status":"in_progress"}\n' "$name" "${2:?iteration}" > "$STATE/loop.json"
    ;;
  loop-end)
    rm -f "$STATE/loop.json" "$STATE/stop-blocks"
    ;;
  verify|review|pr-verify|pr-review)
    # legacy escape hatch — debugging / non-Claude-Code environments only
    manual_allowed || { echo "mark.sh: manual marks are disabled (config allow_manual_marks=false). 정상 경로는 리뷰 에이전트 본인이 실행하는 'mark.sh evidence' 입니다." >&2; exit 1; }
    case "$cmd" in
      verify)    bash "$SCRIPTS/diff-hash.sh" > "$STATE/evidence/koong-verifier.commit.ok"; printf 'VERDICT: PASS\nVERIFY_MODE=full\n' >> "$STATE/evidence/koong-verifier.commit.ok" ;;
      review)    for a in koong-code-reviewer koong-scope-auditor koong-convention-auditor koong-security-auditor; do
                   { bash "$SCRIPTS/diff-hash.sh"; echo "FINDINGS: 0"; [ "$a" = "koong-security-auditor" ] && printf 'SEC_BM=0\nSEC_RULES=\n'; } > "$STATE/evidence/$a.commit.ok"
                 done ;;
      pr-verify) { git -C "$DIR" rev-parse HEAD; printf 'VERDICT: PASS\nVERIFY_MODE=full\n'; } > "$STATE/evidence/koong-verifier.pr.ok" ;;
      pr-review) for a in koong-code-reviewer koong-scope-auditor koong-convention-auditor koong-security-auditor; do
                   { git -C "$DIR" rev-parse HEAD; echo "FINDINGS: 0"; [ "$a" = "koong-security-auditor" ] && printf 'SEC_BM=0\nSEC_RULES=\n'; } > "$STATE/evidence/$a.pr.ok"
                 done ;;
    esac
    ;;
  *)
    echo "mark.sh: unknown subcommand '$cmd'" >&2
    exit 1
    ;;
esac
