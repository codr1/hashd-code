# Troubleshooting

## Baseline Test Failures

### What it means

When you create a workstream (`hashd run STORY-xxxx`), hashd runs the project's
test suite against the fresh worktree (a clean checkout of main). If tests
fail, the workstream stays in `provisioning` with `baseline_failures`
populated (and `runtime_status` reports `provisioning / failed`) instead of
advancing to `active`.

This prevents agents from wasting cycles trying to "fix" pre-existing test
failures that have nothing to do with their story.

### How it looks

**CLI:**
```
ERROR: Workstream blocked -- 6 test(s) failing on main.
  - TestDashboardCandidatesReadRoutesRBAC
  - TestDashboardCandidateMutationRoutesRBAC
  ...

Main has not changed since worktree creation (47314e5).
Fix the tests on main first, or override:
  hashd run <ws_id> --run-anyway
```

**TUI:** Status panel shows `BLOCKED -- tests failing on main` in red with
the failing test names and remediation instructions. Footer shows
`[G]o  [!]Go anyway  [X]close`.

### How to fix (recommended)

Create a bug-fix story to fix the tests on main:

```bash
hashd plan bug "Fix broken tests on main"
hashd approve BUG-xxxx
hashd run BUG-xxxx --run-anyway    # This workstream IS the fix
```

The bug-fix workstream uses `--run-anyway` because it needs to run despite the
broken tests -- it's the one that will fix them. Baseline failures are stored
and excluded from the test stage so the agent isn't blamed for pre-existing
failures. The merge gate runs the full test suite without exclusions, so the
fix is verified before merging.

Once the fix merges to main, run the blocked workstream again:

```bash
hashd run <blocked_ws_id>
```

hashd detects that main has advanced, rebases the worktree, and clears the
gate automatically. No `--run-anyway` needed.

In the TUI, press `[G]o` on the blocked workstream. Same behavior -- if main
moved, the gate clears.

### How to override

If you want to proceed without fixing main (not recommended):

```bash
hashd run <ws_id> --run-anyway     # Prompts for confirmation
hashd run <ws_id> --run-anyway -y  # Skip confirmation (scripts)
```

In the TUI, press `[!]` (Go anyway) and confirm in the modal.

**Warning:** Unless this workstream fixes the broken tests, it will not
auto-recover. Baseline failures are excluded from the test stage, but the
merge gate runs the full suite. If the tests are still broken on main when
you try to merge, the merge gate will fail.

### How to check if main has broken tests

```bash
cd <repo_path>
<test_command>    # e.g., go test ./..., make test, pytest
```

### Disabling the gate

Per-project in `config.yaml`:
```yaml
workflow:
  baseline_tests: false
```

The default is `true` (enabled).

## Temporal Server Not Running

If `hashd run` fails with a connection error:

```bash
hashd restart                          # Restart all services including the Temporal sidecar
hashd restart server --reclaim-port    # Restart one component, clearing a foreign port owner
```

Restarting stops the server, which stops every activity its Temporal worker is
running. `hashd restart`, `hashd restart server` and `hashd stop` therefore put
a restart hold in force and wait -- with no limit -- until every workflow is at
a stopping point: running stages finish under their own timeouts and the next
one does not start. Progress prints the whole time (a full summary every 60
seconds without a terminal). New work is refused while the hold stands; the
refusal names the command to retry. The hold is released when the replacement
server is ready (WF.md "Restart holds").

- Ctrl-C cancels the wait: the hold is released and nothing is stopped.
- `--force` interrupts running work instead of waiting. It lists everything it
  will interrupt and asks; `--force --yes` proceeds without asking, and without
  a terminal `--force` needs `--yes`. No environment variable selects it.
- `--yes` (`-y`) alone never forces: it answers the command's other prompts.
- If the restart hold cannot be put in force (the local server does not
  answer, or the configured URL is another machine's), the command stops
  nothing and exits non-zero at once, naming the same command and the `--force`
  form.
- Against a hashd-server older than v0.9.25-998-g077bf39c4, the version that introduced the restart hold, the command holds nothing: it prints one line saying running work is not held, then stops as older releases did.
- If hashd-server itself cannot be stopped, the command releases the hold it
  put in force and exits non-zero: the server is still running, and nothing is
  coming to release a hold left behind.
- `--reclaim-port` authorizes killing an unrecognized process that still holds
  the hashd-server port as the server starts. Without a terminal, that kill is
  refused unless this flag is given; `--yes` does not authorize it. It applies
  to `hashd restart` and `hashd restart server` -- the restarts that start the
  server -- and not to `hashd stop`.
- `--in-place-upgrade` says a restart of a source checkout after a version
  change is deliberate, skipping the installer's owner provisioning, tool
  refresh and doctor. `hashd restart` only: a component restart refuses it, and
  `hashd stop` does not take it. `./setup.sh` is the supported upgrade path and
  passes it for you.

The board names each item's stage and the substage beside it -- what a live
agent is running, or the last substage the item recorded when no agent is
attached -- but never which agent that is, because the record of a running
invocation carries no agent name. The background housekeeping sweep is
off the board too: it belongs to no project to be listed under, and it repeats
every few minutes and redoes whatever a restart interrupts. What a stop
genuinely could not read -- a project whose database would not open, one the
check ran out of budget before reaching -- is listed under "Not checked" on
that stop, and is never the same thing as nothing running.

## Stale Flows

Inspect the current stage, diagnostics, and available actions before changing
a workstream that appears stuck:

```bash
hashd show <ws_id> --details
hashd watch <ws_id>
```

- **Failed implementation:** fix the reported cause, then use `hashd run <ws_id>`
  when run is available. This continues the existing plan.
- **`awaiting_human_review`:** use `hashd approve <ws_id>` or
  `hashd reject <ws_id> -f "guidance"`, not `run`. Read the gate reason first:
  approving a review gate accepts the current diff; approving an agent-stop
  gate retries implementation without committing it.
- **Still running:** silence alone does not establish failure. Inspect the
  active stage; do not reset merely to clear the status.

`hashd reset <ws_id>` is a deliberate implementation restart: it resets the
worktree to baseline, discards committed micro-commit code and uncommitted
edits, unmarks the retained plan, removes FIX commits, and clears reviews.
It is not a harmless retry. See [reset / replan / reject](../WF.md#plan-regeneration-reset--replan--reject).

## Worktree Cleanup

Inspect the owning workstream with `hashd show <ws_id>` before removing its
worktree. Close only when you intend to abandon that work:

```bash
hashd close <ws_id> --keep-branch
```

Close asks for confirmation, removes the worktree, and discards uncommitted
changes. `--keep-branch` retains committed work for `hashd open <ws_id>`;
without it, close also deletes the local branch. The database record is kept.
Use `-y` only to confirm those consequences without a prompt.

Check the response for cleanup warnings: a closed record does not guarantee
the worktree was removed. Run cleanup from outside the worktree path.

## Broken Main (Post-Merge Test Failures)

### What it means

After merging a story, the post-merge test suite fails on main. This typically
happens when two features developed in parallel create conflicting artifacts --
most commonly duplicate migration files with the same content but different
version numbers.

### How it looks

```
WARNING: Post-merge tests FAILED on main!
  Main branch may need fixes before merging other workstreams.
  Test output (last 20 lines):
    migrations/073_users_google_id.sql:1:1: column "google_id" already exists
    task: Failed to run task "test": exit status 1
```

New workstreams branching off main will sit at `provisioning / failed` (with `baseline_failures` populated).

### How to fix with hashd

Create a targeted bug story and let the agent fix it:

```bash
# 1. Create a bug with specific fix instructions
hashd plan bug "Fix broken main: remove duplicate migration" \
  -f "Delete migrations/073_users_google_id.sql -- it is an exact duplicate of 072_users_google_id.sql. The column already exists from 072. Only delete 073, do not touch 072. Do not create any new migrations."

# 2. The workstream will sit at provisioning / failed (because main is broken).
#    Override the baseline gate -- the agent's job is to fix the broken tests.
hashd run <ws_id> --run-anyway

# 3. The agent deletes the duplicate, tests pass, merge gate passes.
#    Merge when ready:
hashd merge <ws_id>
```

This pattern works for any "main is broken" situation: create a bug story
describing exactly what to fix, run-anyway to bypass the baseline gate, and
let the agent fix it through the normal review cycle.

### Prevention

The pre-merge validation pipeline (runs inside the merge lock) catches most of
these issues before they land on main:
- Migration renumbering resolves version number conflicts
- Migration dedup detects content-identical files from parallel branches
- Full test suite runs on the rebased branch before merge

---

## REQS/SPEC Edit Rejected

### What it means

`hashd project reqs edit` and `hashd project spec edit` are server-backed artifact
edits. The CLI opens the document in `$EDITOR`, but hashd-server owns the write,
commit, and push. The server rejects edits when it cannot safely commit exactly
the intended document change.

### Common causes

| Error | Meaning | Fix |
|-------|---------|-----|
| `REQS edit touches active WIP sections` | The edit changed bytes between `BEGIN WIP` and `END WIP` markers owned by an active story | Re-run `hashd project reqs edit` and move your change outside the WIP block, or wait for the story to merge/close |
| `repo has uncommitted changes` | The server repo is dirty, so hashd cannot commit only the artifact edit | Commit, stash, or discard those changes on the server-side repo, then retry |
| `document changed since it was opened` | The artifact changed after the editor opened | Re-run the edit command so you start from the latest file |
| `path must not be a symlink` | The configured artifact path is a symlink | Replace it with a regular tracked Markdown file, or update `reqs_path` / `spec_path` |
| `file not found` | The configured artifact path does not exist | Create and commit the file, or update the path with `hashd project config set reqs_path <path>` or `hashd project config set spec_path <path>` |

### Safe inspection

Use the read-only commands before editing:

```bash
hashd project reqs show
hashd project spec show
```

These commands read through hashd-server, so they work from a remote CLI client
that does not have the repo mounted locally.

---

## Missing AI Tools

If `hashd run` reports missing binaries:

```bash
hashd doctor           # Check all tool versions and configuration
hashd agents           # Show configured agents and their status
```

See README.md for installation instructions.

---

## Workspace Hook Failures

See [Workspace Hooks](HOOKS.md) for configuration and environment variables.

### Setup hook timed out

The workstream stays at `provisioning` with `runtime_status: failed` and a
`provision_error` diagnostic:

```
Hook exceeded timeout of 300s and was killed.
  Command: npm ci
  Last output:
    ...
  Fix: increase hooks.timeout_seconds in config.yaml, or simplify the hook.
```

**How to fix:**

1. Increase the timeout in your project's `config.yaml`:
   ```yaml
   hooks:
     timeout_seconds: 900
   ```
2. Retry provisioning. The setup hook runs again, so it must tolerate partial
   work from the previous attempt:
   ```bash
   hashd run <ws_id>
   ```

Alternatively, simplify the hook or pre-warm its dependencies.

### Setup hook failed (non-zero exit)

```
Hook failed: exit status 1
  Command: cp ../.env .env
  Output:
    cp: cannot stat '../.env': No such file or directory
```

**How to fix:** read the output tail to find the root cause. Typical issues:

- **Path assumptions.** Hooks run in the worktree (`$HASHD_WORKTREE_PATH`),
  not the project root. Use absolute paths or paths rooted at the worktree.
- **Missing tool on PATH.** Hooks inherit the parent's environment, so the
  tool must be on the PATH that started the hashd server. Try
  `which <tool>` from the same shell that runs `hashd`.
- **Partial success.** If a multi-step hook fails halfway, add
  `set -euo pipefail` at the top so later steps don't run on garbage state.

After fixing the underlying issue, re-run `hashd run <ws_id>`.

### Teardown hook failed

Teardown-hook failures are logged and do not block worktree removal. Removal
can fail separately; check the operation's response before assuming it succeeded.

Clean up any resources the failed hook left behind. Make teardown tolerate
already-removed resources without suppressing other errors.

### Testing a hook before deploying

Run the command the same way the server will, with the HASHD_* vars set:

```bash
cd /path/to/your/worktree
HASHD_PROJECT_NAME=myproject \
HASHD_WORKSTREAM_ID=ws_test \
HASHD_WORKTREE_PATH=$PWD \
HASHD_BASE_BRANCH=main \
bash -c 'YOUR HOOK COMMAND HERE'
```

Add `-x` (`bash -x -c ...`) to trace each expanded command.
