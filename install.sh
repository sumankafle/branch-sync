#!/usr/bin/env bash
# Installs branch-sync into a repo LOCALLY (never committed): files are added to .git/info/exclude.
# Usage: ./install.sh [path/to/repo]      (default: current directory)
#        ./install.sh --user              (install the agent for the current user)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-.}"

if [[ "$TARGET" == "--user" ]]; then
  USER_PROMPTS="${VSCODE_USER_PROMPTS_FOLDER:-${HOME}/.config/Code/User/prompts}"
  mkdir -p "$USER_PROMPTS"
  cp "$HERE/branch-sync.agent.md" "$USER_PROMPTS/branch-sync.agent.md"
  echo "Installed user agent: $USER_PROMPTS/branch-sync.agent.md"
  echo "Reload VS Code, then select branch-sync from the Copilot agent dropdown."
  exit 0
fi

TOP="$(git -C "$TARGET" rev-parse --show-toplevel)" || { echo "Not a git repo: $TARGET"; exit 1; }

mkdir -p "$TOP/.branch-sync" "$TOP/.github/agents"
cp "$HERE/sync-branch.sh"        "$TOP/.branch-sync/sync-branch.sh"
cp "$HERE/branch-sync.agent.md"  "$TOP/.github/agents/branch-sync.agent.md"
chmod +x "$TOP/.branch-sync/sync-branch.sh"

EXCL="$(cd "$TOP" && realpath "$(git rev-parse --git-path info/exclude)")"
mkdir -p "$(dirname "$EXCL")"; touch "$EXCL"
for p in "/.branch-sync/" "/.github/agents/branch-sync.agent.md"; do
  grep -qxF "$p" "$EXCL" || echo "$p" >> "$EXCL"
done

echo "Installed into: $TOP"
echo "Local-only ignore file: $EXCL"
echo "Check:  cd $TOP && git status   (nothing new should be listed)"
echo "Reload VS Code, then select branch-sync from the Copilot agent dropdown."
