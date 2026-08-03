#!/usr/bin/env bash
# gate-git.sh — PreToolUse(Bash) hook. THE koong enforcement gate.
#
# Enforces:
#   1. git commit only with identity-verified evidence from every agent the
#      risk tier requires (tier is RECOMPUTED here — cannot be under-declared),
#      hash-matched to the current diff, verdicts clean, security waiver logic.
#   2. git push / gh pr create only with pr-scope evidence keyed to HEAD,
#      clean tree, and only to the 'origin' remote (exfil prevention).
#   3. `mark.sh evidence <agent>` callable ONLY by that agent itself
#      (hook input agent_type must match — the main agent cannot forge evidence).
#   4. State dir + harness files writable only through sanctioned scripts.
#   5. Universal blocks (force-push, amend, public repo) and beginner rails.
set -uo pipefail

DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SCRIPTS="$DIR/.claude/koong/scripts"
STATE="$DIR/.claude/koong/state"
EVIDENCE="$STATE/evidence"
CONFIG="$DIR/.claude/koong/config.json"
WAIVERS="$DIR/.koong/security-waivers.md"
LOOPLOG="$DIR/.koong/loop-log.jsonl"

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  echo "koong gate: jq가 설치되어 있지 않아 게이트를 건너뜁니다. 'brew install jq' 후 npx koong-agent doctor 를 실행하세요." >&2
  exit 0
fi

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[ -n "$CMD" ] || exit 0
AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty')

block() {
  printf 'KOONG GATE BLOCKED: %s\n' "$1" >&2
  exit 2
}

MODE="beginner"; MANUAL="false"
if [ -f "$CONFIG" ]; then
  MODE=$(jq -r '.mode // "beginner"' "$CONFIG" 2>/dev/null || echo "beginner")
  MANUAL=$(jq -r '.allow_manual_marks // false' "$CONFIG" 2>/dev/null || echo "false")
fi

# ── evidence identity verification ──────────────────────────────────────────
# `mark.sh evidence <name>` may only be run by the agent whose name it records.
if printf '%s' "$CMD" | grep -qE 'mark\.sh[[:space:]]+evidence\b'; then
  CLAIMED=$(printf '%s' "$CMD" | sed -n 's/.*mark\.sh[[:space:]]\{1,\}evidence[[:space:]]\{1,\}\([a-z-]*\).*/\1/p')
  if [ "$MANUAL" != "true" ]; then
    [ -n "$AGENT_TYPE" ] || block "증거(evidence)는 리뷰 서브에이전트 본인만 기록할 수 있습니다. 메인 에이전트의 증거 기록은 위조로 간주되어 차단됩니다. 해당 에이전트를 실제로 실행하세요."
    [ "$AGENT_TYPE" = "$CLAIMED" ] || block "신원 불일치: 현재 에이전트($AGENT_TYPE)가 '$CLAIMED'의 증거를 기록하려 했습니다. 자기 자신의 증거만 기록할 수 있습니다."
  fi
  exit 0
fi

# ── legacy manual marks ──────────────────────────────────────────────────────
if printf '%s' "$CMD" | grep -qE 'mark\.sh[[:space:]]+(verify|review|pr-verify|pr-review)\b'; then
  [ "$MANUAL" = "true" ] || block "수동 마킹은 비활성화되어 있습니다(allow_manual_marks=false). 각 리뷰 에이전트가 스스로 'mark.sh evidence'를 실행하는 것이 정상 경로입니다."
  exit 0
fi

# ── state & harness write protection ────────────────────────────────────────
# Only sanctioned koong scripts may touch state/; harness files are human-only.
if printf '%s' "$CMD" | grep -qE '\.claude/koong/state|\.koong/loop-log' && \
   ! printf '%s' "$CMD" | grep -qE 'koong/scripts/(mark|clear-marks|diff-hash|risk|gate-git|session-start|stop-guard)\.sh'; then
  block "state 디렉터리와 loop-log는 koong 훅/스크립트만 기록할 수 있습니다. 직접 쓰기는 증거 위조로 간주됩니다."
fi
if printf '%s' "$CMD" | grep -qE '(>|>>|tee[[:space:]]|sed[[:space:]]+-i|mv[[:space:]]|cp[[:space:]]|rm[[:space:]]|chmod[[:space:]])[^|]*\.claude/(koong/scripts|settings\.json|agents/koong-|skills/koong)'; then
  block "하네스 파일(.claude/koong/scripts, settings.json, koong 에이전트/스킬 정의)은 에이전트가 수정할 수 없습니다. 변경이 필요하면 사용자에게 직접 수정을 요청하세요. (model 변경은 set-model.sh 사용)"
fi

# ── universal hard blocks ────────────────────────────────────────────────────
case "$CMD" in
  *"git push"*--force*|*"git push"*"-f "*|*"git push -f"*)
    block "force push는 금지되어 있습니다." ;;
  *"git commit"*--amend*)
    block "commit --amend는 금지되어 있습니다. 새 커밋을 만드세요." ;;
  *"gh repo create"*--public*)
    block "저장소는 항상 --private로 생성합니다. 공개 저장소는 사용자가 명시적으로 요청한 경우 사용자에게 직접 실행을 안내하세요." ;;
esac

# ── beginner-mode safety rails ───────────────────────────────────────────────
if [ "$MODE" = "beginner" ]; then
  case "$CMD" in
    *"git reset --hard"*|*"rm -rf"*|*"prisma migrate reset"*|*"flyway clean"*|*"flywayClean"*|*"DROP TABLE"*|*"DROP DATABASE"*|*"drop table"*|*"drop database"*)
      block "초보자 보호: 데이터를 파괴할 수 있는 명령입니다. 꼭 필요하다면 사용자에게 이유를 설명하고 직접 실행을 안내하세요." ;;
  esac
  if printf '%s' "$CMD" | grep -qE '(curl|wget)[^|;&]*\|[[:space:]]*(sudo[[:space:]]+)?(ba)?sh'; then
    block "초보자 보호: 인터넷에서 받은 스크립트를 바로 실행하는 패턴(curl | bash)은 차단됩니다. 필요하면 사용자에게 내용 확인 후 직접 실행을 안내하세요."
  fi
  case "$CMD" in
    *"terraform apply"*|*"aws "*deploy*|*"gcloud "*deploy*|*"fly deploy"*|*"vercel --prod"*|*"vercel deploy --prod"*|*"railway up"*)
      if [ ! -f "$STATE/money.ok" ]; then
        block "💸 이 작업은 돈이 들 수 있습니다. 사용자에게 예상 비용을 설명하고 명시적 동의를 받은 뒤 'bash $SCRIPTS/mark.sh money-ok'를 실행하고 다시 시도하세요."
      fi
      rm -f "$STATE/money.ok"
      ;;
  esac
fi

# ── evidence validation helpers ──────────────────────────────────────────────
check_evidence() { # check_evidence <agent> <scope> <key> <tier>
  local agent="$1" scope="$2" key="$3" tier="$4"
  local file="$EVIDENCE/$agent.$scope.ok"
  [ -f "$file" ] || { echo "MISSING:$agent"; return; }
  [ "$(head -n1 "$file")" = "$key" ] || { echo "STALE:$agent"; return; }
  case "$agent" in
    koong-verifier)
      grep -q '^VERDICT: PASS' "$file" || { echo "FAILED:$agent"; return; }
      if [ "$tier" -ge 2 ] && ! grep -q 'VERIFY_MODE=full' "$file"; then
        echo "FASTONLY:$agent"; return
      fi
      ;;
    koong-security-auditor)
      grep -q '^FINDINGS: 0$' "$file" && { echo "OK"; return; }
      local bm rules r
      bm=$(grep '^SEC_BM=' "$file" | cut -d= -f2 || echo 1)
      if [ "${bm:-1}" != "0" ]; then
        rules=$(grep '^SEC_RULES=' "$file" | cut -d= -f2- || echo "")
        [ -n "$rules" ] || { echo "SECBM:$agent"; return; }
        for r in $rules; do
          grep -q "$r" "$WAIVERS" 2>/dev/null || { echo "NOWAIVER:$r"; return; }
        done
      fi
      # BM==0 but findings>0 → only MINORs remain: acceptable at iteration cap
      ;;
    *)
      # reviewers: FINDINGS: 0, or only-MINOR remainder (iteration-3 relaxation)
      if ! grep -q '^FINDINGS: 0$' "$file"; then
        grep -qE '^\[(BLOCKER|MAJOR)\]' "$file" && { echo "FINDINGS:$agent"; return; }
      fi
      ;;
  esac
  echo "OK"
}

explain() { # explain <status-token>
  case "$1" in
    MISSING:*)  echo "${1#MISSING:} 증거가 없습니다 — 해당 에이전트를 실행하세요" ;;
    STALE:*)    echo "${1#STALE:} 증거가 현재 diff와 불일치합니다(리뷰 후 코드 변경됨) — 루프를 다시 도세요" ;;
    FAILED:*)   echo "verifier가 PASS를 보고하지 않았습니다" ;;
    FASTONLY:*) echo "T2+ 티어는 최종 verify가 full 모드여야 합니다 (VERIFY_MODE=full)" ;;
    FINDINGS:*) echo "${1#FINDINGS:}에 미해결 BLOCKER/MAJOR finding이 있습니다" ;;
    SECBM:*)    echo "보안 BLOCKER/MAJOR가 미해결입니다 — 수정하거나 사용자의 명시적 waiver가 필요합니다" ;;
    NOWAIVER:*) echo "보안 규칙 ${1#NOWAIVER:} 위반이 미해결이며 waiver가 없습니다. 수정하거나, 사용자가 '${1#NOWAIVER:} 위험 수용'을 명시한 경우에만 .koong/security-waivers.md 기록 후 진행하세요" ;;
  esac
}

# ── git commit gate ──────────────────────────────────────────────────────────
if printf '%s' "$CMD" | grep -qE '(^|[;&|[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+commit\b'; then

  if [ -f "$STATE/bootstrap.ok" ]; then
    rm -f "$STATE/bootstrap.ok"
    exit 0
  fi

  # deterministic secret scan on staged diff
  if git -C "$DIR" diff --cached -U0 2>/dev/null | grep -qEi \
    '(api[_-]?key|secret|passwd|password|token|private[_-]?key)[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9+/_-]{16,}|AKIA[0-9A-Z]{16}|-----BEGIN (RSA|EC|OPENSSH) PRIVATE KEY|eyJhbGciOi'; then
    block "스테이징된 변경에 시크릿으로 보이는 문자열이 있습니다 (SEC-N3/SEC-S2). 환경변수로 분리하고, 실제 키였다면 로테이션하세요."
  fi
  if git -C "$DIR" diff --cached --name-only 2>/dev/null | grep -qE '(^|/)\.env(\..*)?$'; then
    block ".env 파일은 커밋할 수 없습니다 (SEC-S2). .gitignore에 추가하고 .env.example만 커밋하세요."
  fi

  # recompute the tier ourselves — the orchestrator's claim is not trusted
  RISK=$(bash "$SCRIPTS/risk.sh")
  TIER=$(printf '%s\n' "$RISK" | sed -n 's/^TIER=//p')
  AGENTS=$(printf '%s\n' "$RISK" | sed -n 's/^AGENTS=//p' | tr ',' ' ')
  HASH=$(bash "$SCRIPTS/diff-hash.sh" 2>/dev/null || echo "NOHASH")

  PROBLEMS=""
  for agent in $AGENTS; do
    STATUS=$(check_evidence "$agent" commit "$HASH" "$TIER")
    [ "$STATUS" = "OK" ] || PROBLEMS="${PROBLEMS}  - $(explain "$STATUS")\n"
  done
  if [ -n "$PROBLEMS" ]; then
    block "커밋 요건 미충족 (리스크 티어 T$TIER — 필수: $(echo "$AGENTS" | tr ' ' ',')):\n$(printf '%b' "$PROBLEMS")/koong-commit 루프를 완료하세요. 티어는 게이트가 diff에서 직접 재계산하므로 낮춰 신고할 수 없습니다."
  fi

  # tamper-proof telemetry: the gate itself records the passing commit
  ITER=$(sed -n 's/.*"iteration":\([0-9]*\).*/\1/p' "$STATE/loop.json" 2>/dev/null || echo 1)
  mkdir -p "$DIR/.koong"
  printf '{"ts":"%s","type":"commit","tier":%s,"iterations":%s,"agents":"%s","hash":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TIER" "${ITER:-1}" "$(echo "$AGENTS" | tr ' ' ',')" "$(printf '%s' "$HASH" | cut -c1-8)" >> "$LOOPLOG"

  # evidence is single-use
  rm -f "$EVIDENCE"/*.commit.ok
  exit 0
fi

# ── git push / gh pr create gate ─────────────────────────────────────────────
IS_PUSH=false
printf '%s' "$CMD" | grep -qE '(^|[;&|[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push\b' && IS_PUSH=true

if [ "$IS_PUSH" = "true" ] || printf '%s' "$CMD" | grep -qE '(^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+create\b'; then

  if [ "$IS_PUSH" = "true" ]; then
    # exfil prevention: push only to origin (or implicit default remote)
    REMOTE=$(printf '%s' "$CMD" | sed -n 's/.*git\([[:space:]]\{1,\}-C[[:space:]]\{1,\}[^[:space:]]\{1,\}\)\{0,1\}[[:space:]]\{1,\}push[[:space:]]\{1,\}\(-u[[:space:]]\{1,\}\)\{0,1\}\([^-][^[:space:]]*\).*/\3/p')
    if [ -n "$REMOTE" ] && [ "$REMOTE" != "origin" ]; then
      block "push는 origin 원격으로만 허용됩니다 ('$REMOTE' 차단 — 코드 유출 방지). 다른 원격이 정말 필요하면 사용자에게 직접 실행을 안내하세요."
    fi
  fi

  if [ -n "$(git -C "$DIR" status --porcelain 2>/dev/null)" ]; then
    block "워킹트리에 커밋되지 않은 변경이 있습니다. 모든 변경을 /koong-commit으로 커밋한 뒤 push/PR 하세요."
  fi

  HEAD_SHA=$(git -C "$DIR" rev-parse HEAD 2>/dev/null || echo "NOHEAD")
  PROBLEMS=""
  for agent in koong-verifier koong-code-reviewer koong-scope-auditor koong-convention-auditor koong-security-auditor; do
    STATUS=$(check_evidence "$agent" pr "$HEAD_SHA" 3)
    [ "$STATUS" = "OK" ] || PROBLEMS="${PROBLEMS}  - $(explain "$STATUS")\n"
  done
  if [ -n "$PROBLEMS" ]; then
    block "PR 요건 미충족 (PR 레벨은 항상 5종 전체 + full verify):\n$(printf '%b' "$PROBLEMS")/koong-pr 루프를 완료하세요."
  fi
  exit 0
fi

exit 0
