#!/usr/bin/env bash
# diff-hash.sh — canonical SHA-256 of the current change set.
# Hashes working-tree CONTENT of every changed/untracked file, so the hash is
# stable across `git add` (index state does not matter) but changes the moment
# any file content changes. This is what makes review approval auto-invalidate
# on post-review edits.
set -euo pipefail

DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$DIR"

SHACMD="shasum -a 256"
command -v shasum >/dev/null 2>&1 || SHACMD="sha256sum"

{
  # tracked files differing from HEAD (worktree or index) + untracked files
  { git diff HEAD --name-only 2>/dev/null || true
    git ls-files --others --exclude-standard 2>/dev/null || true
  } | sort -u | while IFS= read -r f; do
    [ -n "$f" ] || continue
    printf 'FILE:%s\n' "$f"
    if [ -f "$f" ]; then
      $SHACMD "$f"
    else
      printf 'DELETED:%s\n' "$f"
    fi
  done
} | $SHACMD | cut -d' ' -f1
