#!/usr/bin/env bash
# set-model.sh — the ONLY sanctioned way to change koong agent models.
# Replaces exactly the `model:` frontmatter line in all koong agent files.
# Exists so /koong-init can set plan-based models while Write/Edit access to
# agent definitions stays fully blocked for agents.
#
# Usage: set-model.sh <opus|sonnet|haiku|inherit>
set -euo pipefail

MODEL="${1:?usage: set-model.sh <opus|sonnet|haiku|inherit>}"
case "$MODEL" in
  opus|sonnet|haiku|inherit) ;;
  *) echo "set-model.sh: invalid model '$MODEL' (opus|sonnet|haiku|inherit)" >&2; exit 1 ;;
esac

DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CONFIG="$DIR/.claude/koong/config.json"

changed=0
for f in "$DIR"/.claude/agents/koong-*.md; do
  [ -f "$f" ] || continue
  tmp="$f.tmp.$$"
  sed "s/^model:.*$/model: $MODEL/" "$f" > "$tmp" && mv "$tmp" "$f"
  changed=$((changed + 1))
done

# keep config.json in sync when present
if [ -f "$CONFIG" ] && command -v jq >/dev/null 2>&1; then
  tmp="$CONFIG.tmp.$$"
  jq --arg m "$MODEL" '.agent_model = $m' "$CONFIG" > "$tmp" && mv "$tmp" "$CONFIG"
fi

echo "koong: ${changed}개 에이전트의 model을 '$MODEL'로 설정했습니다."
