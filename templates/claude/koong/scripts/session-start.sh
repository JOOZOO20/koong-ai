#!/usr/bin/env bash
# session-start.sh — SessionStart hook. Injects project context: stack, plan,
# init status, branch state. Output is JSON with additionalContext.
set -uo pipefail

DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SCRIPTS="$DIR/.claude/koong/scripts"
CONFIG="$DIR/.claude/koong/config.json"

STACK=$(bash "$SCRIPTS/detect-stack.sh" 2>/dev/null || echo "unknown")
PLAN=$(bash "$SCRIPTS/detect-plan.sh" 2>/dev/null || echo "unknown")

CTX="[koong harness]"

if [ ! -f "$CONFIG" ]; then
  CTX="$CTX 아직 초기화되지 않았습니다 — 첫 작업 전에 /koong-init 을 실행하세요."
else
  CFG_PLAN="unknown"; CFG_STACK="unknown"; CFG_MODE="beginner"
  if command -v jq >/dev/null 2>&1; then
    CFG_PLAN=$(jq -r '.plan // "unknown"' "$CONFIG" 2>/dev/null || echo unknown)
    CFG_STACK=$(jq -r '.stack // "unknown"' "$CONFIG" 2>/dev/null || echo unknown)
    CFG_MODE=$(jq -r '.mode // "beginner"' "$CONFIG" 2>/dev/null || echo beginner)
  fi
  CTX="$CTX mode=$CFG_MODE."
  if [ "$STACK" != "unknown" ]; then
    CTX="$CTX 스택: $STACK — docs/koong/profiles/$STACK.md 프로파일만 로드하세요 (다른 프로파일 읽기 금지)."
  else
    CTX="$CTX 스택 미감지 — 새 프로젝트라면 /koong-new 를 사용하세요."
  fi
  if [ "$PLAN" != "unknown" ] && [ "$PLAN" != "$CFG_PLAN" ]; then
    CTX="$CTX ⚠️ 요금제 변경 감지(현재 $PLAN, 설정 $CFG_PLAN) — /koong-init 재실행을 권장합니다."
  fi
  if [ "$STACK" != "unknown" ] && [ "$CFG_STACK" != "unknown" ] && [ "$STACK" != "$CFG_STACK" ]; then
    CTX="$CTX ⚠️ 스택 변경 감지(감지 $STACK, 설정 $CFG_STACK) — /koong-init 재실행을 권장합니다."
  fi
fi

if git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null || echo "?")
  DIRTY=$(git -C "$DIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  CTX="$CTX 브랜치: $BRANCH, 미커밋 변경: ${DIRTY}개."
  if [ -f "$DIR/.claude/koong/state/loop.json" ]; then
    CTX="$CTX ⚠️ 미완료 koong 루프 상태가 남아있습니다 — 이어서 완료하거나 clear-marks.sh로 정리하세요."
  fi
else
  CTX="$CTX git 저장소가 아닙니다 — /koong-new 가 git init부터 처리합니다."
fi

CTX="$CTX 모든 커밋은 /koong-commit, 모든 PR은 /koong-pr 경유 필수 (훅이 차단함)."

# JSON-escape the context string via jq if available, else minimal escape
if command -v jq >/dev/null 2>&1; then
  jq -cn --arg ctx "$CTX" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
else
  ESCAPED=$(printf '%s' "$CTX" | sed 's/"/\\"/g')
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$ESCAPED"
fi
