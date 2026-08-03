#!/usr/bin/env bash
# stop-guard.sh — Stop hook. Blocks stopping mid-loop (verify/review not finished,
# dirty tree) so the agent completes the commit instead of abandoning it.
# Allows the stop after 2 consecutive blocks to avoid trapping the session.
set -uo pipefail

DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE="$DIR/.claude/koong/state"

INPUT=$(cat)

# never fight the hook system's own re-invocation
if command -v jq >/dev/null 2>&1; then
  ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)
  [ "$ACTIVE" = "true" ] && exit 0
fi

[ -f "$STATE/loop.json" ] || exit 0

DIRTY=$(git -C "$DIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [ "$DIRTY" = "0" ]; then
  # nothing uncommitted: stale loop state, clean it up and allow stop
  rm -f "$STATE/loop.json" "$STATE/stop-blocks"
  exit 0
fi

BLOCKS=0
[ -f "$STATE/stop-blocks" ] && BLOCKS=$(cat "$STATE/stop-blocks" 2>/dev/null || echo 0)

if [ "$BLOCKS" -ge 2 ]; then
  rm -f "$STATE/stop-blocks"
  exit 0
fi

echo $((BLOCKS + 1)) > "$STATE/stop-blocks"

LOOP=$(sed -n 's/.*"loop":"\([^"]*\)".*/\1/p' "$STATE/loop.json" 2>/dev/null || echo "commit")
ITER=$(sed -n 's/.*"iteration":\([0-9]*\).*/\1/p' "$STATE/loop.json" 2>/dev/null || echo "?")

REASON="koong ${LOOP} 루프가 미완료 상태입니다 (iteration ${ITER}, 미커밋 변경 ${DIRTY}개). verify+review를 끝내고 커밋까지 완료하세요. 3회 초과 실패로 에스컬레이션하는 경우라면 현재 상태와 시도 내역을 한국어로 보고한 뒤 mark.sh loop-end 로 루프를 정리하고 종료하세요."

if command -v jq >/dev/null 2>&1; then
  jq -cn --arg r "$REASON" '{decision:"block",reason:$r}'
else
  printf '{"decision":"block","reason":"%s"}\n' "$(printf '%s' "$REASON" | sed 's/"/\\"/g')"
fi
