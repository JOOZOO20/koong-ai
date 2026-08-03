#!/usr/bin/env bash
# guard-state.sh — PreToolUse(Write|Edit) hook.
# Blocks agent file-writes to (1) the koong state dir & loop-log (evidence
# forgery) and (2) harness files themselves (gate disablement). Humans edit
# harness files directly; agents may not.
set -uo pipefail

INPUT=$(cat)

command -v jq >/dev/null 2>&1 || exit 0
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -n "$FILE" ] || exit 0

block() {
  printf 'KOONG GUARD BLOCKED: %s\n' "$1" >&2
  exit 2
}

case "$FILE" in
  *".claude/koong/state/"*|*".koong/loop-log.jsonl")
    block "state/loop-log는 koong 훅과 스크립트만 기록합니다. 직접 쓰기는 증거 위조로 간주됩니다." ;;
  *".claude/koong/scripts/"*|*".claude/settings.json"|*".claude/agents/koong-"*|*".claude/skills/koong"*)
    block "하네스 파일은 에이전트가 수정할 수 없습니다(게이트 무력화 방지). 변경이 필요하면 사용자에게 직접 수정을 요청하세요. 에이전트 model 변경은 'bash .claude/koong/scripts/set-model.sh <model>'을 사용하세요." ;;
esac

exit 0
