# branch-sync: keep your GitLab MR branch up to date (local only)

Checks whether your branch is behind `main`/`master`, rebases it safely (backup first),
and lets a GitHub Copilot agent resolve the conflicts while keeping both sides.
Works with many submodules. **Nothing is ever committed**: files are hidden via `.git/info/exclude`.

## What's in this folder

| File | Purpose |
|---|---|
| `sync-branch.sh` | The safe Git helper (check / rebase / continue / restore / squash / push) |
| `branch-sync.agent.md` | The Copilot custom agent (instructions for resolving conflicts) |
| `install.sh` | Copies both into a repo and git-ignores them locally |
| `uninstall.sh` | Removes everything again |

## Setup

1. **Requirements**: git 2.31+, VS Code with GitHub Copilot Chat (agent mode). Check: `git --version`.
2. **Unzip/copy this folder** anywhere outside your repo, e.g. `~/tools/branch-sync`.
3. **Install for your user** (recommended when this is your personal workflow):
  ```bash
  cd ~/tools/branch-sync
  ./install.sh --user
  ```
  This copies the agent to VS Code's user prompts folder, so it is available in every workspace.
  Set `VSCODE_USER_PROMPTS_FOLDER` first if your VS Code user data lives somewhere else.
4. **Or install into one repo** (useful for a project-specific copy):
   ```bash
   cd ~/tools/branch-sync
   ./install.sh /path/to/your/repo
   ```
   This creates `.branch-sync/sync-branch.sh` and `.github/agents/branch-sync.agent.md`
   in the repo and adds both to `.git/info/exclude`.
5. **Verify it's invisible to Git** (repo install only):
   ```bash
   cd /path/to/your/repo && git status      # must show nothing new
   ```
6. **Reload VS Code** (`Developer: Reload Window`). Open Copilot Chat, switch to **Agent** mode,
   and select **branch-sync** in the agent dropdown. If it's missing, check that
   `.github/agents/branch-sync.agent.md` or the user prompts file exists and that your
   Copilot extension is up to date.

## Daily use

**Before opening or updating a MR:**

1. Commit your work (or stash it). The worktree must be clean.
2. In Copilot Chat (branch-sync agent): **"Sync my branch with main."**
3. The agent will:
   1. run `check` (behind/ahead, files changed on both sides, submodule pointer changes)
   2. offer to `squash` your commits first if you have many (resolve conflicts once, not per commit)
   3. run `rebase` (creates `backup/<branch>-<timestamp>` first)
   4. resolve conflicts file by file, `git add`, `continue`
   5. verify nothing was lost, run your tests, and give a report
4. **Review** the result: `git diff origin/main...HEAD` and the agent's report.
5. **Push yourself only after review:** `.branch-sync/sync-branch.sh push` uses
  `--force-with-lease`, never plain `--force`. The lease prevents overwriting newer remote
  work that you have not fetched.
   GitLab updates the MR and re-runs the pipeline.

**Without Copilot** you can use the script directly:
```bash
.branch-sync/sync-branch.sh check
.branch-sync/sync-branch.sh rebase        # exit code 2 = conflicts, fix them, then:
git add <files> && .branch-sync/sync-branch.sh continue
.branch-sync/sync-branch.sh push
```

## Safety net

| Situation | Command |
|---|---|
| Mid-rebase, want out | `.branch-sync/sync-branch.sh abort` |
| Rebase finished but result looks wrong | `BRANCH_SYNC_ALLOW_RESET=1 .branch-sync/sync-branch.sh restore backup/<name>` after review |
| List backups | `git branch --list 'backup/*'` |
| Clean up old backups | `git branch -D backup/<name>` |

After each rebase the script prints a **lost-work check**: every file you changed that now has
*no* diff against the target is flagged with `!!`. Investigate those before pushing.

## Submodule notes

- Submodule conflicts are **pointer** conflicts (which commit the submodule should point to).
  Default rule: keep the target's pointer unless *you* intentionally bumped that submodule.
- After the rebase the script runs `git submodule update --init --recursive`.
- If `git status` shows ` M some-submodule` right after switching branches, run
  `git submodule update --init --recursive` (or set `git config submodule.recurse true`).
  The script refuses to start on a dirty worktree.
- Make sure the submodule commits your branch points to are **pushed** to their own GitLab repos.

## GitLab notes

- The script works with any remote named `origin` (override: `REMOTE=upstream ...`).
  It detects `main` or `master` from `origin/HEAD`; if that is missing, run
  `git remote set-head origin -a`.
- GitLab's "Rebase" button on the MR only works when there are no conflicts; this tool is for
  the conflict case. If the MR is set to "fast-forward merge", you must rebase before merging.
- The tool never uses plain `--force`; it uses `--force-with-lease` only for the current source branch.
- `git rerere` is enabled (repo-local), so if you rebase the same branch again, previously
  resolved conflicts are replayed automatically.

## Uninstall

```bash
./uninstall.sh /path/to/your/repo
```

For a user install, run:

```bash
./uninstall.sh --user
```

## Limits (be honest with yourself)

- The agent resolves *textual* conflicts. It can't guarantee the merged code is *correct*:
  always build and test, and read the diff before pushing.
- For big semantic conflicts (renamed/moved functions on both sides) it will ask you.
- Tested end to end on a sample repo with a submodule, a conflict and a submodule bump;
  try it first on a throwaway branch in your real repo.
