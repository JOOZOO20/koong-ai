#!/usr/bin/env bash
# clear-marks.sh — remove all loop-state markers and evidence.
set -euo pipefail

DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE="$DIR/.claude/koong/state"

rm -f "$STATE"/bootstrap.ok "$STATE"/money.ok "$STATE"/loop.json "$STATE"/stop-blocks 2>/dev/null || true
rm -f "$STATE"/evidence/*.ok 2>/dev/null || true
rm -rf "$STATE"/audit 2>/dev/null || true
echo "koong: all state markers and evidence cleared."
