#!/usr/bin/env bash
# Removes branch-sync from a repo. Usage: ./uninstall.sh [path/to/repo]
#                          or: ./uninstall.sh --user
set -euo pipefail

if [[ "${1:-}" == "--user" ]]; then
	USER_PROMPTS="${VSCODE_USER_PROMPTS_FOLDER:-${HOME}/.config/Code/User/prompts}"
	rm -f "$USER_PROMPTS/branch-sync.agent.md"
	echo "Removed user agent: $USER_PROMPTS/branch-sync.agent.md"
	exit 0
fi

TOP="$(git -C "${1:-.}" rev-parse --show-toplevel)"
rm -rf "$TOP/.branch-sync" "$TOP/.github/agents/branch-sync.agent.md"
rmdir "$TOP/.github/agents" "$TOP/.github" 2>/dev/null || true
EXCL="$(cd "$TOP" && realpath "$(git rev-parse --git-path info/exclude)")"
sed -i.bak -e '\#^/\.branch-sync/$#d' -e '\#^/\.github/agents/branch-sync\.agent\.md$#d' "$EXCL" && rm -f "$EXCL.bak"
echo "Removed from $TOP (backup/* branches were kept)."
