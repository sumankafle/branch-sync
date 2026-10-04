#!/usr/bin/env bash
# Safely bring a GitLab merge-request branch up to date with main/master.
#
# This script is intentionally conservative:
# - it refuses to work with uncommitted changes;
# - it creates a backup branch before rewriting local history;
# - it never force-pushes;
# - it never edits files inside submodules.
#
# Usage:
#   sync-branch.sh check
#   sync-branch.sh rebase
#   sync-branch.sh continue
#   sync-branch.sh abort
#   sync-branch.sh restore <backup-branch>
#   sync-branch.sh squash "commit message"
#   sync-branch.sh push
set -euo pipefail

REMOTE="${REMOTE:-origin}"
die() {
  echo "ERROR: $*" >&2
  exit 1
}

STATE_FILE="$(git rev-parse --git-path branch-sync-state 2>/dev/null || true)"

default_branch() {
  local branch_name=""

  branch_name=$(git symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null | sed "s#^$REMOTE/##") || true
  if [[ -z "$branch_name" ]]; then
    for candidate in main master; do
      if git show-ref --verify --quiet "refs/remotes/$REMOTE/$candidate"; then
        branch_name="$candidate"
        break
      fi
    done
  fi

  [[ -n "$branch_name" ]] || die "Cannot detect default branch (no main/master on $REMOTE)"
  echo "$branch_name"
}

current_branch() {
  git symbolic-ref --quiet --short HEAD || die "Detached HEAD - checkout a branch first"
}

is_clean() {
  [[ -z "$(git status --porcelain)" ]]
}

submodule_paths() {
  git ls-files --stage | awk '$1 == "160000" { print $4 }'
}

fetch_all() {
  # Fetch before every comparison so the decision uses current remote refs.
  git fetch "$REMOTE" --prune --quiet
  git submodule sync --recursive --quiet
}

cmd_check() {
  fetch_all
  local current_branch_name target_branch_name merge_base behind_count ahead_count
  current_branch_name=$(current_branch)
  target_branch_name=$(default_branch)
  merge_base=$(git merge-base HEAD "$REMOTE/$target_branch_name")
  read -r behind_count ahead_count < <(git rev-list --left-right --count "$REMOTE/$target_branch_name...HEAD")

  echo "Current branch: $current_branch_name"
  echo "Target branch:  $REMOTE/$target_branch_name"
  echo "Behind target:  $behind_count commits"
  echo "Ahead of target: $ahead_count commits (yours)"
  echo -n "Worktree:       "
  if is_clean; then
    echo "clean"
  else
    echo "DIRTY (commit or stash first)"
  fi

  echo; echo "== Files changed on BOTH sides (likely conflicts) =="
  comm -12 <(git diff --name-only "$merge_base" HEAD | sort) \
           <(git diff --name-only "$merge_base" "$REMOTE/$target_branch_name" | sort) || true

  local submodule_list; mapfile -t submodule_list < <(submodule_paths)
  if (( ${#submodule_list[@]} )); then
    echo; echo "== Submodule pointers changed on target since your branch point =="
    git diff --submodule=log "$merge_base" "$REMOTE/$target_branch_name" -- "${submodule_list[@]}" || true
    echo; echo "== Submodule pointers changed on YOUR branch =="
    git diff --submodule=log "$merge_base" HEAD -- "${submodule_list[@]}" || true
  fi

  echo
  if (( behind_count == 0 )); then echo "Up to date - nothing to do."
  else echo "Branch is behind. Next: sync-branch.sh rebase"; fi
}

cmd_rebase() {
  is_clean || die "Worktree not clean. Commit or stash first."
  fetch_all
  local br tgt backup old_base
  br=$(current_branch); tgt=$(default_branch)
  old_base=$(git merge-base HEAD "$REMOTE/$tgt")
  backup="backup/${br//\//-}-$(date +%Y%m%d-%H%M%S)"
  git branch "$backup" HEAD
  printf 'backup=%s\nold_base=%s\ntarget=%s\n' "$backup" "$old_base" "$tgt" > "$STATE_FILE"
  echo "Backup created: $backup  (undo: sync-branch.sh restore $backup)"

  git config rerere.enabled true      # remember conflict resolutions
  # Reuse the recorded resolution for review, but do not stage it silently.
  git config rerere.autoupdate false

  if git rebase "$REMOTE/$tgt"; then
    finish
  else
    report_conflicts
    exit 2
  fi
}

report_conflicts() {
  local conflicted_files; conflicted_files=$(git diff --name-only --diff-filter=U)
  if [[ -z "$conflicted_files" ]]; then
    echo; echo "Conflicts were auto-resolved by git rerere (reused earlier resolution)."
    echo "REVIEW the staged result (git diff --cached), then: sync-branch.sh continue"
    return 0
  fi
  echo; echo "CONFLICTED FILES:"; echo "$conflicted_files"
  local conflicted_submodules; conflicted_submodules=$(git ls-files -u | awk '$1 == "160000" { print $4 }' | sort -u)
  if [[ -n "$conflicted_submodules" ]]; then
    echo; echo "SUBMODULE POINTER CONFLICTS (pick a commit, then 'git add <path>'):"; echo "$conflicted_submodules"
  fi
  echo
  echo "NOTE: during a rebase  --ours = target branch,  --theirs = YOUR commit."
  echo "After resolving: git add <files> && sync-branch.sh continue"
}

cmd_continue() {
  if GIT_EDITOR=true git rebase --continue; then finish
  else report_conflicts; exit 2; fi
}

finish() {
  echo; echo "Rebase done. Syncing submodules to recorded commits..."
  git submodule update --init --recursive
  [[ -f "$STATE_FILE" ]] || { echo "(no state file - skipping verification)"; return 0; }
  # shellcheck disable=SC1090
  source "$STATE_FILE"
  echo; echo "== range-diff: your OLD commits (<) vs NEW commits (>)  [= same, ! changed] =="
  git range-diff "$old_base..$backup" "$REMOTE/$target..HEAD" || true
  echo; echo "== Lost-work check: files YOU changed that now have NO diff vs $REMOTE/$target =="
  local f lost=0
  while IFS= read -r f; do
    if git diff --quiet "$REMOTE/$target" HEAD -- "$f"; then echo "  !! $f"; lost=1; fi
  done < <(git diff --name-only "$old_base" "$backup")
  (( lost )) && echo "  Review the files above (expected only if upstream made the identical change)." || echo "  OK - all files you changed still differ from target."
  echo; echo "== Total diff vs backup (upstream changes show up here, your work should not) =="
  git diff --stat "$backup" HEAD | tail -5
  echo; echo "Next: build + test, then: sync-branch.sh push"
}

cmd_abort() {
  git rebase --abort
  echo "Rebase aborted, branch untouched."
}

cmd_restore() {
  local backup_branch="${1:-}"
  [[ -n "$backup_branch" ]] || die "Usage: restore <backup-branch>"
  [[ "${BRANCH_SYNC_ALLOW_RESET:-}" == "1" ]] || die "Restore uses reset --hard and is blocked by default. Review the backup, then rerun with BRANCH_SYNC_ALLOW_RESET=1."

  git rebase --abort 2>/dev/null || true
  git reset --hard "$backup_branch"
  git submodule update --init --recursive
  echo "Restored to $backup_branch"
}

cmd_squash() {
  # Fewer commits mean conflicts are resolved once instead of repeatedly.
  is_clean || die "Worktree not clean."

  local commit_message="${1:-}"
  [[ -n "$commit_message" ]] || die 'Usage: squash "commit message"'

  local target_branch_name merge_base
  target_branch_name=$(default_branch)
  fetch_all
  merge_base=$(git merge-base HEAD "$REMOTE/$target_branch_name")

  git branch "backup/squash-$(date +%Y%m%d-%H%M%S)" HEAD
  git reset --soft "$merge_base"
  git commit -m "$commit_message"
}

cmd_push() {
  is_clean || die "Worktree not clean."
  git push "$REMOTE" "$(current_branch)"
}

command="${1:-check}"
case "$command" in
  check)
    cmd_check
    ;;
  rebase)
    cmd_rebase
    ;;
  continue)
    cmd_continue
    ;;
  abort)
    cmd_abort
    ;;
  restore)
    shift
    cmd_restore "$@"
    ;;
  squash)
    shift
    cmd_squash "$@"
    ;;
  push)
    cmd_push
    ;;
  *)
    die "Unknown command. Use: check|rebase|continue|abort|restore|squash|push"
    ;;
esac
