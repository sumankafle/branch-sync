# Using branch-sync with VS Code

`branch-sync` is a GitHub Copilot custom agent for safely syncing a GitLab feature
branch with its target branch. Copilot runs locally in VS Code; the repository may
remain hosted on GitLab.

## Install on any laptop

Requirements: Git 2.31+, VS Code, GitHub Copilot Chat with Agent mode, and Bash.

```bash
git clone https://github.com/sumankafle/branch-sync.git
cd branch-sync
./install.sh --user
```

Reload VS Code with **Developer: Reload Window**, open Copilot Chat, choose **Agent**
mode, and select **branch-sync**. The user installation makes the agent available in
every workspace for that VS Code user. On Windows, run the commands from Git Bash or WSL.

### Keep the tool in `/opt`

The tool can live outside all GitLab repositories, including `/opt`. Only the initial
clone needs administrator permission; run the installer as your normal user:

```bash
sudo git clone https://github.com/sumankafle/branch-sync.git /opt/branch-sync
sudo chown -R "$USER:$USER" /opt/branch-sync
cd /opt/branch-sync
./install.sh --user
```

To update it later:

```bash
cd /opt/branch-sync
git pull --ff-only
./install.sh --user
```

Install the helper into a project from `/opt` with:

```bash
/opt/branch-sync/install.sh /path/to/your/gitlab-project
```

Do not run `install.sh --user` with `sudo`; otherwise the agent may be installed for
root instead of your VS Code user.

To install it in one project instead:

```bash
./install.sh /path/to/your/gitlab-project
```

This creates `.branch-sync/sync-branch.sh` and
`.github/agents/branch-sync.agent.md`, and hides them through `.git/info/exclude`.

## Prepare a GitLab project

```bash
cd /path/to/your/gitlab-project
git remote -v
git remote set-head origin -a
git status
```

The checked-out branch is the **source branch**. The branch detected by `origin/HEAD`
is the **target branch**, normally `main` or `master`. Work on a feature branch, not
the target branch, and commit or stash changes before syncing.

## Daily use

1. Open the GitLab project in VS Code.
2. Select **Agent > branch-sync** in Copilot Chat.
3. Ask: `Check and sync my current branch with the latest target branch.`
4. Review the source/target report and confirm before a rebase or squash.
5. Review and approve every proposed conflict resolution.
6. Run the project tests and inspect the final diff.
7. Push only after review:

```bash
.branch-sync/sync-branch.sh push
```

## Safety rules

- The agent never pushes by itself.
- Push uses `--force-with-lease`, never plain `--force`.
- The helper fetches the latest target before rebasing and verifies the source is based on it.
- A backup branch is created before rebasing or squashing.
- Dirty worktrees and detached HEAD states are rejected.
- The agent asks before editing conflicted files.
- Reused `rerere` resolutions are not staged automatically.
- Files inside submodules are never edited.
- Restore is destructive and requires explicit opt-in.

Review before pushing:

```bash
git status
git diff origin/main...HEAD
```

Replace `origin/main` with `origin/master` when appropriate.

## Useful commands

```bash
.branch-sync/sync-branch.sh check
.branch-sync/sync-branch.sh rebase
.branch-sync/sync-branch.sh continue
.branch-sync/sync-branch.sh abort
```

Restore only after reviewing the backup:

```bash
BRANCH_SYNC_ALLOW_RESET=1 .branch-sync/sync-branch.sh restore backup/<name>
```

Update the agent on a laptop:

```bash
cd /path/to/branch-sync
git pull --ff-only
./install.sh --user
```

Uninstall:

```bash
./uninstall.sh --user
# or, for one project:
./uninstall.sh /path/to/your/gitlab-project
```

If the agent does not appear, confirm the installed file exists, reload VS Code, and
update GitHub Copilot Chat. If push is rejected after a rebase, stop and inspect the
remote; never replace `--force-with-lease` with plain `--force`.