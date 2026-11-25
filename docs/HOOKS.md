# Workspace Hooks

Workspace hooks are project-configured shell commands that run automatically at
workstream lifecycle points. They're the place for per-project setup you can't
express in `config.yaml` -- installing dependencies inside the worktree,
provisioning ephemeral services, copying secrets, tearing down containers.

## Quick Start

Add a `hooks:` block to your project's `config.yaml`:

```yaml
hooks:
  setup: "npm install"
  teardown: "docker-compose -p hashd-${HASHD_WORKSTREAM_ID} down"
  timeout_seconds: 600    # default: 300
```

That's it. Setup runs when a workstream is provisioned; teardown runs when it's
removed. Both are optional -- omit either key to skip it.

## Lifecycle

### `setup`

| When | After worktree creation, before baseline tests |
|------|------------------------------------------------|
| Where | Runs in the worktree (`cwd = ws.worktree`) |
| On success | Provisioning continues to baseline tests |
| On failure | Workstream stays at `provisioning` with `provision_error` populated; `runtime_status` reports `provisioning / failed` (retryable) |
| On timeout | Killed; workstream stays at `provisioning` with `provision_error` set to the timeout reason |

Called from `orchestrator/workflow/provisioning.py` (Step C3). Recovery: fix
the hook or increase the timeout, then re-run the workstream -- provisioning
is idempotent and resumes from the failed step.

### `teardown`

| When | Before worktree removal (close, merge archive, `workstream remove`) |
|------|---------------------------------------------------------------------|
| Where | Runs in the worktree (`cwd = ws.worktree`) |
| On success | Worktree is removed |
| On failure | Logged as a warning; worktree removal proceeds anyway |
| On timeout | Killed; worktree removal proceeds |

**Teardown never blocks cleanup.** If it fails, the worktree is still removed
and the workstream is still archived -- we log the diagnostic for you to
investigate but won't leave orphaned workstreams just because a container
didn't shut down cleanly.

Called from:
- `server/internal/cli/close.go` (`hashd close`)
- `server/internal/cli/workstream.go` (`hashd workstream remove`)
- `orchestrator/workflow/merge/archive.py` (post-merge archive)

## HASHD_* Environment Variables

A hook runs repository code, so it does not inherit the server's
environment. It receives the allowlisted environment a project command
receives (`server/internal/childenv`): the base names (`PATH`, `HOME`,
locale, `TERM`, `TZ`, `TMPDIR`, `USER`, `LOGNAME`, `SHELL`, the proxy and CA
variables), then the project environment, then these context variables last.

The project environment is the project's entries, with the target repo's
over them by name, resolved right before the hook starts, so a changed entry
or a replaced secret is the next hook's (docs/AGENT_MANAGEMENT.md,
**The project environment**, says how entries are set). Every entry type
reaches a hook:

- a **value** entry as written;
- a **secret** entry's secret, or with `as_file` the path of a read-only file
  holding it, written for this one hook outside the worktree and removed once
  it ends;
- a **credential** entry's value: the work owner's own credential for its
  forge credential key;
- a **host** entry's variable, read from the environment of the machine that
  runs the hook (the server, or the runner the workstream is placed on): an
  exact name, or every variable a `PREFIX_*` pattern matches. A variable
  that machine lacks is not set.

Every secret and credential value is replaced by `[REDACTED]` in the hook's
output. A project environment that cannot be had -- an owner with no
credential for a credential entry's key, a secret that does not open -- stops
the hook before it starts; its failure names the entry and what to do.

The context variables:

| Variable | Description | Always set? |
|----------|-------------|-------------|
| `HASHD_PROJECT_NAME` | Project name (matches `name:` in config.yaml) | Yes |
| `HASHD_WORKSTREAM_ID` | Workstream identifier (e.g., `ws_abc123`) | Yes |
| `HASHD_WORKTREE_PATH` | Absolute path to the git worktree | Yes |
| `HASHD_BASE_BRANCH` | Default branch (from `default_branch`, e.g., `main`) | Yes |
| `HASHD_STORY_ID` | Story ID (e.g., `STORY-0042`) | Only if workstream is linked to a story |

Reference them in your hook command with normal shell syntax:
`${HASHD_WORKSTREAM_ID}`, `"$HASHD_STORY_ID"`, etc.

## Configuration

```yaml
hooks:
  setup: ""               # shell command; empty/omitted = no-op
  teardown: ""            # shell command; empty/omitted = no-op
  timeout_seconds: 300    # applies to BOTH hooks; default 300 (5 min)
```

All three fields are optional. Defaults live in `orchestrator/lib/defaults.yaml`
and are merged into your project config by the standard loader.

## Examples

### Node dependencies

```yaml
hooks:
  setup: "npm ci"
```

### Python project with uv

```yaml
hooks:
  setup: "uv sync --frozen"
```

### Ephemeral docker-compose stack per workstream

```yaml
hooks:
  setup: "docker-compose -p hashd-${HASHD_WORKSTREAM_ID} up -d db redis"
  teardown: "docker-compose -p hashd-${HASHD_WORKSTREAM_ID} down -v"
  timeout_seconds: 900
```

The `-p` (project name) flag isolates each workstream's containers so parallel
workstreams don't clobber each other.

### Copy secrets from outside the repo

```yaml
hooks:
  setup: "cp ~/.config/myproject/.env .env"
```

### Story-aware setup

```yaml
hooks:
  setup: |
    if [ -n "$HASHD_STORY_ID" ]; then
      echo "Provisioning for $HASHD_STORY_ID"
    fi
    make deps
```

### Multi-step hook with explicit failure

```yaml
hooks:
  setup: |
    set -euo pipefail
    npm ci
    cp ../shared/.env .env
    npx prisma generate
```

`set -euo pipefail` is recommended for anything beyond a single command so a
failing step aborts the hook cleanly.

## Testing Hooks Locally

Before dropping a hook into `config.yaml`, run it the same way the server will:

```bash
cd /path/to/your/worktree
HASHD_PROJECT_NAME=myproject \
HASHD_WORKSTREAM_ID=ws_test \
HASHD_WORKTREE_PATH=$PWD \
HASHD_BASE_BRANCH=main \
bash -c 'YOUR HOOK COMMAND HERE'
```

To debug a failing hook, run it with `bash -x`:

```bash
bash -x -c 'npm ci && cp ../.env .env'
```

## Diagnostics

### Timeout

```
Hook exceeded timeout of 300s and was killed.
  Command: npm ci
  Last output:
    added 847 packages, audited 1203 packages in 4m 58s
    ...
  Fix: increase hooks.timeout_seconds in config.yaml, or simplify the hook.
```

**Action:** bump `hooks.timeout_seconds` in your config, or speed up the hook
(prefer `npm ci` over `npm install`, use a cache, etc.).

### Hook failure (non-zero exit)

```
Hook failed: exit status 1
  Command: npm ci
  Output:
    npm ERR! code ENOENT
    npm ERR! syscall open
    npm ERR! path /path/to/worktree/package.json
    npm ERR! errno -2
    ...
```

**Action:** read the output tail to find the root cause. Common issues:
- Missing file in the worktree (fresh checkouts don't have untracked files)
- Path assumptions (always use `$HASHD_WORKTREE_PATH` or relative paths)
- Missing tool (the hook inherits the parent's PATH -- confirm the tool is on it)
- Missing variable (a toolchain variable such as `JAVA_HOME` is not inherited
  unless the project environment has a host entry for it; `hashd doctor` lists
  what a hook receives and what it does not)

## Call Flow

The hooks run only at their lifecycle points, inside the stages of the
runner that holds the story's checkout (the server's local runner or a
remote one); no endpoint runs one on request.

```
setup     provisioning's environment build    server/internal/runflow/environment.go
teardown  the merge archive's checkout removal server/internal/mergeflow/archive.go
teardown  close / remove / archive delete      server/internal/runnerconnect/teardown_worktree_stage_body.go
          (the teardown_worktree stage)
                 |
                 v
     server/internal/hooks (RunContext), with the project
     environment the server answers for the stage's assignment
                 |
                 v
     bash -c "<hook>" in the story's checkout
     with HASHD_* env vars injected
```

## See Also

- `README.md` -- short Workspace Hooks section with the headline example
- `docs/TROUBLESHOOTING.md#workspace-hook-failures` -- recovery recipes
- `config.sample.yaml` -- annotated config template
- `server/internal/hooks/hooks.go` -- Go implementation
