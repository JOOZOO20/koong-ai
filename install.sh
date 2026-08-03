#!/usr/bin/env bash
# install.sh — thin fallback installer for machines without Node.
# Primary path is: npx koong-agent init
set -euo pipefail

if command -v node >/dev/null 2>&1; then
  echo "Node가 있으니 npx로 설치합니다..."
  exec npx --yes koong-agent init
fi

echo "Node 없이 순수 bash로 설치합니다..."

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="$(pwd)"

if [ ! -d "$SRC_DIR/templates" ]; then
  TMP=$(mktemp -d)
  git clone --depth 1 https://github.com/JOOZOO20/koong-agent "$TMP/koong-agent"
  SRC_DIR="$TMP/koong-agent"
fi

TPL="$SRC_DIR/templates"

# .claude payload
mkdir -p "$DEST_DIR/.claude"
if [ -f "$DEST_DIR/.claude/settings.json" ]; then
  echo "⚠️ .claude/settings.json 이 이미 있습니다. 자동 병합은 Node 설치 후 'npx koong-agent init'으로 하거나,"
  echo "   $TPL/claude/settings.json 의 hooks/permissions 를 직접 병합하세요. (기존 파일은 유지합니다)"
  cp -R "$TPL/claude/agents" "$TPL/claude/skills" "$TPL/claude/koong" "$DEST_DIR/.claude/"
else
  cp -R "$TPL/claude/." "$DEST_DIR/.claude/"
fi
mkdir -p "$DEST_DIR/.claude/koong/state"
chmod +x "$DEST_DIR/.claude/koong/scripts/"*.sh

# docs
mkdir -p "$DEST_DIR/docs"
cp -R "$TPL/docs/koong" "$DEST_DIR/docs/"

# CLAUDE.md
if [ -f "$DEST_DIR/CLAUDE.md" ]; then
  cp "$TPL/CLAUDE.md" "$DEST_DIR/docs/koong/KOONG.md"
  if ! grep -q '@docs/koong/KOONG.md' "$DEST_DIR/CLAUDE.md"; then
    printf '\n# koong-agent\n@docs/koong/KOONG.md\n' >> "$DEST_DIR/CLAUDE.md"
  fi
else
  cp "$TPL/CLAUDE.md" "$DEST_DIR/CLAUDE.md"
fi

# .gitignore
touch "$DEST_DIR/.gitignore"
grep -qxF '.claude/koong/state/' "$DEST_DIR/.gitignore" || printf '# koong\n.claude/koong/state/\n.env\n' >> "$DEST_DIR/.gitignore"

echo ""
echo "✅ koong-agent 설치 완료!"
echo "다음 단계: Claude Code를 열고 /koong-init 실행 → /koong <만들고 싶은 것>"
