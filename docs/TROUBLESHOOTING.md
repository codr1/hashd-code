# Troubleshooting

## Baseline Test Failures

### What it means

When you create a workstream (`wf run STORY-xxxx`), hashd runs the project's
test suite against the fresh worktree (a clean checkout of main). If tests
fail, the workstream is created in `baseline_failed` state instead of `active`.

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
  wf run <ws_id> --run-anyway
```

**TUI:** Status panel shows `BLOCKED -- tests failing on main` in red with
the failing test names and remediation instructions. Footer shows
`[G]o  [!]Go anyway  [X]close`.

### How to fix (recommended)

Create a bug-fix story to fix the tests on main:

```bash
wf plan bug "Fix broken tests on main"
wf approve BUG-xxxx
wf run BUG-xxxx --run-anyway    # This workstream IS the fix
```

The bug-fix workstream uses `--run-anyway` because it needs to run despite the
broken tests -- it's the one that will fix them. Baseline failures are stored
and excluded from the test stage so the agent isn't blamed for pre-existing
failures. The merge gate runs the full test suite without exclusions, so the
fix is verified before merging.

Once the fix merges to main, run the blocked workstream again:

```bash
wf run <blocked_ws_id>
```

hashd detects that main has advanced, rebases the worktree, and clears the
gate automatically. No `--run-anyway` needed.

In the TUI, press `[G]o` on the blocked workstream. Same behavior -- if main
moved, the gate clears.

### How to override

If you want to proceed without fixing main (not recommended):

```bash
wf run <ws_id> --run-anyway     # Prompts for confirmation
wf run <ws_id> --run-anyway -y  # Skip confirmation (scripts)
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

## Prefect Server Not Running

If `wf run` fails with a connection error:

```bash
wf restart          # Restart all services including Prefect
```

## Stale Flows

If a workstream shows as "running" but nothing is happening:

```bash
wf show <ws_id>     # Check status and last run
wf reset <ws_id>    # Reset to active state, cancel stale flows
```

## Worktree Cleanup

If git complains about existing worktrees or branches:

```bash
wf close <ws_id> --force    # Remove worktree, branch, and DB record
```

Never `cd` into a worktree directory before removing it. Always run cleanup
from outside the worktree path.

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

New workstreams branching off main will hit `baseline_failed`.

### How to fix with wf

Create a targeted bug story and let the agent fix it:

```bash
# 1. Create a bug with specific fix instructions
wf plan bug "Fix broken main: remove duplicate migration" \
  -f "Delete migrations/073_users_google_id.sql -- it is an exact duplicate of 072_users_google_id.sql. The column already exists from 072. Only delete 073, do not touch 072. Do not create any new migrations."

# 2. The workstream will hit baseline_failed (because main is broken).
#    Override it -- the agent's job is to fix the broken tests.
wf run <ws_id> --run-anyway

# 3. The agent deletes the duplicate, tests pass, merge gate passes.
#    Merge when ready:
wf merge <ws_id>
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

## Missing AI Tools

If `wf run` reports missing binaries:

```bash
wf doctor           # Check all tool versions and configuration
wf agents           # Show configured agents and their status
```

See README.md for installation instructions.
