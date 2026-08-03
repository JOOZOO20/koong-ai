#!/usr/bin/env bash
# detect-stack.sh — detect the project's backend stack from build files.
# stdout: "java-spring" | "python" | "node-nextjs" | "go" | "unknown"
set -euo pipefail

DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

if [ -f "$DIR/build.gradle" ] || [ -f "$DIR/build.gradle.kts" ] || [ -f "$DIR/pom.xml" ]; then
  echo "java-spring"
elif [ -f "$DIR/go.mod" ]; then
  echo "go"
elif [ -f "$DIR/pyproject.toml" ] || [ -f "$DIR/requirements.txt" ]; then
  echo "python"
elif [ -f "$DIR/package.json" ]; then
  # any node project (Next.js or plain) uses the node-nextjs profile
  echo "node-nextjs"
else
  echo "unknown"
fi
