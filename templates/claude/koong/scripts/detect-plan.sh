#!/usr/bin/env bash
# detect-plan.sh — detect the user's Claude subscription plan from ~/.claude.json.
# stdout: "max" | "pro" | "unknown"
set -euo pipefail

CLAUDE_JSON="${HOME}/.claude.json"

if [ ! -f "$CLAUDE_JSON" ] || ! command -v jq >/dev/null 2>&1; then
  echo "unknown"
  exit 0
fi

ORG_TYPE=$(jq -r '.oauthAccount.organizationType // empty' "$CLAUDE_JSON" 2>/dev/null || true)

case "$ORG_TYPE" in
  claude_max*) echo "max" ;;
  claude_pro*) echo "pro" ;;
  *) echo "unknown" ;;
esac
