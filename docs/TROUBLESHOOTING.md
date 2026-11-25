# Troubleshooting

## Installer migration failures

A restart Diagnostic tagged `restart.migration_failed` stops the published
installer without its second restart. Source setup also exits unsuccessfully
at its restart phase. Neither invocation reports installation success. The
original migration Diagnostic below the tag retains the affected projects,
explanation, facts, causes, and repair suggestions. The tag identifies the
migration failure regardless of whether any services are available; it does
not by itself promise recovery, backup, or restoration.

For a protected full or server-component restart, automatic recovery keeps the
lifecycle lock, confirms the server and Temporal process groups stopped, restores
only this attempt's archive without replacement migrations, then starts the
retained previous build at the recovered operations root. An unconfirmed stop
prevents publication and either build's startup; failed restoration starts
neither build. The diagnostic names the exact archive, retained carrier, recovered
root and any stop, restore or startup failure paths. Excluded repository clones
and local-runner checkouts survive recovery and any prior root relocation.

Read the recovered-server startup-release report separately: work may be released,
still held, or unknown if readiness cannot be read. Successful recovery still
leaves the upgrade unsuccessful. A confirmed released recovery makes its archive
eligible for configured retention (including removal with keep=0); failed or
unconfirmed recovery keeps it protected. `--skip-backup` leaves
manual recovery only; no older archive is searched for.

Health does not confirm startup release. If release is held or unknown, keep the
exact archive and retained-build directory named in the report, even with
`upgrade.backup.keep=0`. A standing hold refuses mutating requests and keeps held
work paused. An unknown release means requests may already be accepted and work
may already have resumed; do not assume the installation is quiescent. Resolve
the reported readiness reason; if credentials prevent reading release, re-join the host as directed by
the startup report before starting again. Do not retry the failed migration merely
to clear a hold. A later successful attempt does not release an older protected
archive. Backup retention or cleanup errors supplement the migration and recovery
reports; resolve every reported path without discarding those recovery artifacts.

Follow the migration's repair suggestions before retrying. For a packaged
installation, rerun the original installer invocation directly. For a source
installation, rerun setup from the source checkout:

```bash
./setup.sh
```

The installer supplies the retained previous-build handoff required by the
replacement build's restart; a plain restart from a new shell lacks that handoff.
Unrelated convergence failures still get the
published installer's one retry; restart-hold and destructive-upgrade refusals
still require the action named in their Diagnostic before retrying.

The packaged installer preserves the previous local build before uv/pipx
replaces its wheels or external tools are refreshed. Source setup preserves it
before syncing dependencies, refreshing tools, generating code, or rebuilding. If preparation or
restart fails, it prints `Previous runnable build retained at:` followed by a directory
under `~/.local/state/hashd/retained/build.*`. That directory contains
`build-identity` and `handoff.sh`, independently of the checkout and temporary
installer files. A preservation refusal includes the complete
`install.preserve_previous` Diagnostic and stops before replacement.

Protected local full and server-component restarts require that previous runnable
build before auto-rebuild, shutdown or migration. Restart validates the installer
handoff against the installation's operations root and executable fingerprint;
source setup preserves it before replacement. Direct source restarts without that
pre-replacement handoff refuse; copying binaries after a manual build cannot
recover the overwritten build. Restore the previous installation before rerunning
setup if no handoff exists. Auto-rebuild requires a retained build and archive for
existing local source installations even when the executing CLI sees no pending migrations.
A `restart.recovery_build` refusal stops before rebuilding or stopping services.
Restore the named executable, resource, interpreter or infrastructure prerequisite
from the existing installation, correct any filesystem error, then rerun the installer.
A newly built replacement alone is insufficient. `--skip-backup` deliberately bypasses
this prerequisite as well as archive creation, leaving automatic restoration unavailable.

Recovery records its selected carrier beside the installation receipt in
`hashd-install-recovery`. The next source or packaged installer preserves that
carrier, even though the installed launcher still points at the failed candidate.
A completed installation clears the selection; a failed attempt keeps it.
Even confirmed, released recovery is a failed installation: restart may release
archive protection, but preserves the installer-owned retained build and its
handoff. Direct restarts consume that same installer handoff and do not own its
cleanup. A healthy replacement with unresolved startup or workflow release returns
`restart.release_unconfirmed`: both installers stop unsuccessfully and preserve
the retained build; the packaged installer does not retry that outcome.

Keep that directory while recovery remains unresolved. A later explicit
packaged install or `./setup.sh` creates its own retained build; successful
installation removes only that attempt's payload. Temporary wheel-directory
cleanup leaves retained builds in place. Fresh installations and remote clients
need no prior local build.

If automatic recovery did not start the previous build, first resolve the
reported stop or restoration failure. After explicitly restoring the selected
archive and confirming the database
is suitable for the previous build, use the exact retained location printed by
the installer to start it manually. In a subshell, the handoff selects its runtime,
tools, interpreter, and recorded operations root:

```bash
retained="$HOME/.local/state/hashd/retained/build.ABC123" # use the printed location
(
    source "$retained/handoff.sh"
    "$retained/bin/hashd" start
)
```

The source and packaged installer harnesses exercise this handoff and
manual-start command, including a later explicit upgrade attempt. Preserving
the build alone does not restore the database; protected restart recovery performs
that restoration before automatically starting it.

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

When a story that is not the fix reaches the merge gate and its only failures
are tests its baseline recorded as failing before it, the gate parks at
`merge_test_failed` naming them, with no FIX and no recovery question, and
offers go-anyway: `hashd run <ws_id> --run-anyway` (TUI `!`, Web "Go
anyway") accepts them for the revision the gate tested. The acceptance is
recorded (who, when, which tests) and stated in the PR body, and the next gate
at that revision passes on those failures. Any other failure, a test outside
the baseline, or a new revision blocks again, and go-anyway is asked again.
Test identity comes only from the repo's build adapter (`build.adapters`): a
fresh, complete report the merge-gate command writes, as the test command
does. Console output is never read for it, so a repo without an adapter (Go
and pytest today) is not offered go-anyway at the gate, and neither is a
build failure or a report that may be missing a failure. An adapter whose
report cannot prove every part of the build compiled (Maven) needs a build
that passed on the same content: the post-rebase build, or one the gate runs
for the purpose, which counts only if it changes no file the suite tested --
not even one the side-effect policy puts back afterwards.

The adapter's report says nothing about another step of the same command
(`jest; eslint`), so go-anyway is your decision on the evidence: the park and
the Go anyway confirmation name the tests and show the command's exit status
and the end of its raw output. Check that output for any other failure before
you accept.

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

Close is one of three kinds, and each decides what happens to the story's
requirement in REQS:

- `hashd close <story> [--reason "..."]` abandons the story; its requirement
  returns to REQS as open work, and an optional reason is recorded as the
  story's closure.
- `hashd close <story> --no-changes --reason "..."` closes it as no changes
  needed; the requirement is met and its REQS sections are burned.
- `hashd close <story> --ref <ref> --reason "..."` closes it as
  `closed_by_person`, for work done outside hashd. The server verifies the
  ref first (`#<number>` or the URL of a merged or closed PR, a commit SHA on
  the target branch, or an implemented story) and refuses one it cannot
  confirm. The requirement is met and burned, and the branch is always kept.

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
