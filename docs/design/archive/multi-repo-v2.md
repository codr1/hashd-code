# Multi-Repo Project Model v2

Status: SHIPPED. Historical design record; implementation is the source of truth.
Production code: server/internal/db/schema.sql (project_repos table),
server/internal/config/config.go (mode: multi), multi-repo interview flow,
REQS precedence resolution.
Owner: hashd
Supersedes: the de-facto v1 implemented across
`server/internal/config/detect.go::scanSubRepos`,
`server/internal/cli/project.go::newProjectAddCmd` (the multi-repo block at
~line 525), and `orchestrator/pm/repo_router.py`.

This document specifies the v2 data model, bootstrap flow, CLI surface,
server endpoints, ZMQ events, AI investigation, REQS precedence, planner
integration, and tab-completion story for hashd's multi-repo projects.
It is the spec another agent will implement from. It does not include
code.

---

## 1. Goals and Non-Goals

### 1.1 Goals

1. **Curation, not auto-inclusion.** Detection stays heuristic ("find every
   immediate subdir with `.git`"), but detection produces a *candidate list*,
   not a *membership list*. Membership is declared by the user through
   explicit status assignment. This fixes the 64-repo case (64 detected
   sub-repos, user cares about 3) and the hypothetical 120-repo case.

2. **Four-value repo status.** A repo in a multi-repo project is always in
   exactly one of `primary`, `active`, `reference`, `ignore`. The status
   field controls routing, REQS defaults, review context, and prompt
   construction.

3. **Scale linearly with intent, not with repo count.** Adding three
   in-scope repos to a 120-repo workspace must cost ~3 interview steps,
   not ~120. AI investigation runs lazily, per-repo, as the user adds it.

4. **DB-first, not file-first.** Repo-level state (status, test_cmd,
   descriptions, soft-deleted entries, etc.) lives in SQLite, mutated
   through server endpoints, with ZMQ events emitted on every change.
   hashd is becoming a team server with multiple concurrent UIs — a
   hand-editable YAML file is the wrong source of truth for that.

5. **Explicit multi-repo declaration.** `config.yaml` carries a `mode: multi`
   marker when the project is multi-repo. The marker is the single,
   explicit statement of intent. No inference, no surprises.

6. **Restore the UX that PR #293 regressed.** The 13 regressions catalogued
   in `.claude/multi-repo-golden-run.md` are not all fixable here. PR #311
   (`worktree-project-add-fixes`) is landing 4 P1 items independently:
   interactive init menu, "initialize git?" prompt, `reqs_path` precedence
   prompt, and sub-repo git identity propagation. Multi-repo v2 picks up
   what's left on the multi-repo path: **has-commits warning** and
   **duplicate-name rejection**. Rich build-system feedback and the
   remaining P2/P3 items are tracked separately.

7. **Soft-delete, not hard-delete.** Removing a repo from the project sets
   `status: ignore` and preserves its full row. Re-adding the same path
   pre-fills answers from the preserved row. `prune` only removes entries
   whose on-disk path no longer exists.

8. **Reference-status repos are real planning context.** A repo marked
   `reference` is read by planning and review, surfaced to stage prompts as
   read-only context, and never selected as a story target. Today's
   planner has no concept of "read but don't modify" — this is the biggest
   semantic addition in v2.

9. **Single-repo config shape is untouched.** No `mode:`, no `repos:`
   pollution for single-repo users. Adding multi-repo support must not
   visibly change anything for single-repo projects.

### 1.2 Non-Goals

- **No cross-repo atomic stories.** One story = one repo, always. Work
  spanning two repos becomes two linked stories with a merge gate.
- **No AI-driven repo *discovery*.** Detection stays mechanical. AI is
  used only to pre-fill per-repo *answers*, never to decide which repos
  exist.
- **No automatic garbage collection of soft-deleted entries.** `ignore`
  is forever. `prune` only cleans up when the on-disk path has vanished.
- **No cap on active count. No cap on reference count.** Educate, don't
  enforce.
- **No TUI / fat-form interview.** The interview stays linear and
  prompt-by-prompt. Tab completion is the only affordance we add.
- **No `repos:` list in `config.yaml`.** Repo state lives in SQLite,
  full stop. YAML carries only project-level fields plus `mode: multi`.
- **No hand-editable repo config.** To change a repo's settings, use
  `wf project repo edit` or `wf project repo set`. Do not reach into the
  database directly.
- **No legacy-config migration.** User confirmed on 2026-04-22 that no
  multi-repo projects exist in production. The v2 shape is the only
  shape — legacy `repos: [...]` YAML lists are not read, parsed, or
  migrated. Any such config fails load with a clear error.
- **No reference-repo worktree mounting.** Reference repos are read by
  the planner from their original on-disk paths. They do not appear
  inside the workstream worktree.

---

## 2. Background

### 2.1 What v1 is

Today, when you run `wf project add /path/to/parent`:

1. Go detects every immediate subdir with a valid Git marker (`.git`
   dir or `gitdir:` file; `scanSubRepos`, skipping
   `node_modules`, `vendor`, `.venv`, etc.).
2. If ≥2 sub-repos were found, the CLI asks **one** y/n: "Set up as
   multi-repo project?"
3. If yes, loop over **every** detected sub-repo and ask 6 prompts: name,
   description, default branch, test_cmd, build_cmd, merge_gate,
   merge_mode.
4. Write a flat `repos: [...]` list into `config.yaml`. No `status` field.
   No primary concept. No selection.
5. At planning time, `orchestrator/pm/repo_router.py::route_story_to_repo`
   calls an LLM with a manifest built from every entry in `repos[]` and
   asks it to pick one.

### 2.2 What's broken

1. **No curation.** bigco has 64 git subdirs, user cares about 3. Current
   interview gives one all-or-nothing y/n.
2. **No primary concept.** PR #311 landed `resolveReqsPath` with root +
   sub-repo precedence detection — REQS no longer has to live at the
   root. But without a primary status, the "which sub-repo anchors the
   project" question still has no answer: the detection picks by
   filesystem presence, not by user intent. Multi-repo v2's primary
   status is the missing anchor.
3. **No "read but don't modify" status.**
4. **Interview ordering is backward.** The single/multi question is asked
   *last*, after all project-level prompts.
5. **13 parity regressions from PR #293.** Of these, four touch the
   multi-repo path and must land with this redesign: sub-repo git identity
   propagation, has-commits warning, duplicate-name rejection,
   `reqs_path` prompt.
6. **No status mutation CLI.** Changes require hand-editing `config.yaml`.
7. **Planner is status-blind.** `repo_router.py` iterates `config.repos`
   with zero filter.
8. **YAML as source of truth doesn't work for a multi-user server.**
   hashd is becoming a team server. Concurrent writes from CLI, TUI, and
   bot converge on the same `config.yaml`, with no atomic transitions, no
   CAS, no event emission, no history. The current architecture doc
   (`docs/ARCHITECTURE.md`) already mandates SQLite + ZMQ for entity state; repo
   status is an entity state and should follow the same pattern.

### 2.3 What we lost from Python

The pre-Go Python code — deleted in PR #293 under the "full parity" claim
— had UX patterns worth recovering. Read directly from `git show
59a24bf^:orchestrator/commands/interview.py::run_multi_repo_interview`:

1. ~~**Per-sub-repo git identity propagation.**~~ **Restored by PR #311**
   via `propagateGitIdentity`. Project-root identity now propagates to
   each sub-repo, respecting per-sub-repo overrides.
2. **Has-commits warning loop.** Python warned when a sub-repo had no
   commits yet. Go is silent. *Multi-repo v2 scope.*
3. **Duplicate-name rejection loop.** Go accepts duplicates and fails at
   server-side validation. *Multi-repo v2 scope.*
4. **Rich detection feedback.** Python printed both the manifest type
   and the extracted commands. Go prints one line. Handled by
   build-system-detection Phase 1 naming sweep + Phase 2b UI warnings —
   not a multi-repo v2 item.
5. ~~**`reqs_path` prompt.**~~ **Restored by PR #311** via
   `resolveReqsPath` with root + sub-repo precedence detection.
   Multi-repo v2 extends this to filter by status (§7).
6. **Defaults from existing config on re-interview.** Go has no
   re-interview command. Covered by `wf project repo edit` (§4.3)
   for individual repos; a full re-interview command is out of scope.

### 2.4 What the research said

| Tool | Multi-repo model | Relevance |
|---|---|---|
| Factory.ai | One repo per session | Nobody else treats primary+reference as a first-class concept for AI coding. |
| Superset (superset.sh) | Workspace dir with `.superset.yaml` declaring members | Explicit declaration, no auto-detection. |
| worca-cc | Git submodules or pinned manifest | Good reminder that a parent control repo and child repos can coexist; hashd treats that as a multi-repo variant, not a monorepo. |
| Bazel workspaces | `WORKSPACE` enumerates external deps | Explicit, build-graph-aware. Overkill. |
| Cargo workspaces | `[workspace] members = [...]` | Clearest analog: explicit member list, no auto-discovery. |
| Lerna / Nx / Turborepo | `packages/*` glob | Assumes homogeneous layout. |
| google `repo` / `gclient` | Manifest XML/Python | Explicit, heavyweight. |

**Finding: explicit declaration via config, not auto-detection, is the
pattern across successful multi-repo tools. Nobody we found does
AI-native primary+reference scoping.** We are building something new.

### 2.5 Positioning: meta-repo-inspired, team-server-architected

The emerging community pattern for AI multi-repo context is the
**meta-repo** (also "spine pattern" or "root AGENTS.md"): a
coordinator directory contains the sub-repos as siblings and carries
a checked-in `AGENTS.md` that gives the model a map and behavioral
rules. The model reads the map first, then navigates into sub-repos
on demand using its normal file-read tools. No pre-loading, no
budget caps, just: *here's what exists, here's how to behave, use
your tools*.

hashd adopts that **prompt-layer behavior pattern** (see §8.2) but
diverges on architecture:

- The map lives in the hashd server (SQLite + ZMQ), not in an
  `AGENTS.md` file in a git repo. This matters because hashd is
  heading toward a team server with concurrent UIs — a checked-in
  text file cannot survive concurrent mutation from CLI, TUI, and
  bot. We treat the map as mutable state, same pattern described in
  `docs/ARCHITECTURE.md`
  already mandates for workstream and story state.
- **Primary** is an anchor concept the meta-repo pattern doesn't
  have. Worth revisiting as the model evolves; for now it gives
  REQS and the router something to fall back on.
- **Reference** is a first-class status with router-level
  enforcement (§8.1, §8.4), not a convention humans maintain.

### 2.6 Supported topology model

Short-term support is intentionally narrow:

- **Single repo** is the default. This includes monorepos for now; hashd
  does not yet model path-level components inside one repo.
- **Multi-repo** means multiple independent child repos under one
  project root.
- **Superproject** is a multi-repo variant where the project root is
  itself a Git repo with `.gitmodules`.
- **Container directory** is a non-repo directory containing child repos.
  `wf project add` may initialize a local-only control repo at the root
  before continuing through the normal multi-repo interview.

This document refers to the "map" throughout — that is deliberate,
and aligns with where the industry term appears to be settling.
Public user-facing documentation should use the same vocabulary.

**Forward-looking (out of scope for v2):** when hashd becomes a
multi-user server, different users working on the same project may
need *different maps* — user A treating repo X as active while user
B treats it as reference, or the same directory shell participating
in two different projects with different primary/active/reference
splits. The `project_repos` table as spec'd is per-project, not
per-user-per-project. Flagged in §11 as a forward concern so the
implementing agent builds structures that can grow into it rather
than corner us.

---

## 3. Data Model

### 3.1 Status enum

| Status | Multiplicity | Routable | In model context | Purpose |
|---|---|---|---|---|
| `primary` | **Exactly one** | Yes | Yes | Anchor for REQS default, displayed first, fallback target for routing. |
| `active` | 0..N | Yes | Yes | Eligible for modifications. A story can be routed here. |
| `reference` | 0..N | **No** | Yes (read-only) | Planning/review reads code, docs, SPECs here. Routing must never select it. |
| `ignore` | 0..N | No | No | Soft-deleted with config preserved. Re-activation pre-fills answers from the preserved row. |

**Invariants:**

- Multi-repo projects have exactly one `primary`. Zero primary is an
  error. Two primaries is an error.
- Single-repo projects have no `project_repos` rows.
- Status transitions are always confirmation-prompted unless `--yes`.

**Why four values, not three or five:**

- Three (primary/active/ignore) loses the read-only-context case.
- Five would split `ignore` into "never configured" and "soft-deleted".
  We fold those into one — never-configured repos simply have no row;
  soft-deleted repos have a row with `status: ignore`. The CLI handles
  re-activation by looking up the soft-deleted row and pre-filling.

### 3.2 `mode:` field in `config.yaml`

```yaml
mode: multi    # explicit, required for multi-repo projects
# absent == single
```

- `mode: multi` is the **sole, explicit** statement that a project is
  multi-repo.
- Absent `mode:` (or `mode: single`, which is accepted but not written)
  means single-repo.
- `mode: multi` means "look in the DB for repos." It is the
  file-system-visible contract.
- No other values accepted. Unknown values fail config load.

### 3.3 `config.yaml` shape

**Single-repo (unchanged, no `mode:` field written):**

```yaml
name: myproject
repo_path: /home/user/dev/myproject
default_branch: main
reqs_path: REQS.md
description: "short description"
tech:
  preferred: ""
  acceptable: ""
  avoid: ""
test_cmd: "go test ./..."
build_cmd: "go build ./..."
merge_gate_test_cmd: "go test ./..."
merge_mode: pr
autonomy: gatekeeper
```

**Multi-repo (same shape plus `mode: multi`, no `repos:` anywhere):**

```yaml
name: bigco
repo_path: /home/vess/dev/bigco
mode: multi
default_branch: main
reqs_path: bigco-risk-service/REQS.md
description: "BigCo platform. See sub-repo SPECS."
tech:
  preferred: "go, python, react"
  acceptable: "typescript, rust"
  avoid: "java"
autonomy: gatekeeper
suggest_default: true
```

Project-level `test_cmd` / `build_cmd` / `merge_mode` are omitted in
multi-repo configs — they don't apply to the project root. Per-repo
values live in the DB.

The multi-repo project's `repo_path` is still the parent directory. The
primary repo's *path* is stored in the DB, relative to `repo_path`.

### 3.4 SPEC.md and REQS.md update routing

| Operation | Target repo | Notes |
|---|---|---|
| REQS.md WIP cleanup post-merge | Primary | Where REQS lives — root or sub-repo. |
| SPEC.md update post-merge | Active | Where the story's changes were committed. |

Rationale:

- SPEC lives next to the code it describes. Operators reading a repo find
  code + its SPEC together.
- REQS lives at primary; it's the requirement source-of-truth, often
  referenced from multiple repos.
- Cross-repo case (primary != active): both files update independently in
  their respective repos. No cross-repo SPEC writes.
- Reference and ignored repos: never written.

Bootstrap:

- If active repo has no SPEC.md yet, the merge flow creates one with a
  project header.
- The update prompt handles both "SPEC exists, edit it" and "SPEC missing,
  create it" cases.

### 3.5 SQLite schema: `project_repos` table

This table lives in the existing per-project SQLite database alongside
workstreams, stories, events, etc. One row per configured repo.

```sql
CREATE TABLE project_repos (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,
  name                  TEXT NOT NULL,
  path                  TEXT NOT NULL,           -- relative to project repo_path
  status                TEXT NOT NULL CHECK (status IN ('primary','active','reference','ignore')),
  description           TEXT NOT NULL DEFAULT '',
  default_branch        TEXT NOT NULL DEFAULT 'main',
  test_cmd              TEXT NOT NULL DEFAULT '',
  build_cmd             TEXT NOT NULL DEFAULT '',
  merge_gate_test_cmd   TEXT NOT NULL DEFAULT '',
  merge_mode            TEXT NOT NULL DEFAULT 'pr' CHECK (merge_mode IN ('pr','local')),
  ignored_at            TEXT,                    -- ISO-8601 UTC, set on transition to ignore
  ignored_reason        TEXT,                    -- optional free-text
  created_at            TEXT NOT NULL,           -- ISO-8601 UTC
  updated_at            TEXT NOT NULL,           -- ISO-8601 UTC
  updated_by            TEXT,                    -- "cli", "tui", "bot", etc.
  UNIQUE(name)
);

-- Enforce "exactly one primary" at the DB level with a partial unique index.
CREATE UNIQUE INDEX idx_project_repos_one_primary
  ON project_repos(status) WHERE status = 'primary';
```

**Notes:**

- Only one `primary` per project; the partial unique index enforces this
  at the storage layer as a safety net. Application-layer CAS is still
  the primary mechanism.
- No `project_id` column — each project has its own SQLite file, so
  project identity is implicit in the file path.
- `path` is canonical relative form `./<name>`. Absolute paths rejected.
- For `status: reference`, `test_cmd` / `build_cmd` / `merge_gate_test_cmd`
  / `merge_mode` are unused by the planner/runner. They default to empty
  strings and are only populated if the user later promotes to `active`
  (see §4.3).

### 3.6 Validation rules

Enforced at load time / mutation time. The rules here are strict;
crash-recovery semantics live in §4.1 and invoke `wf project add`
explicitly rather than being special-cased at load.

1. `config.yaml` with `mode: multi` must have at least one row in
   `project_repos`. Zero rows on load → error "project marked
   multi-repo but has no configured repos; restore the database or
   re-run `wf project add`". This rule is strict — the loader never
   silently swallows the inconsistency.
2. `config.yaml` without `mode: multi` must have zero rows in
   `project_repos`. Rows present without the marker → error "found
   repo rows but config.yaml does not declare `mode: multi`;
   invariant violated". The supported recovery path is the
   write-ordering snapshot from §4.1: when
   `.project-create-recovery.yaml` exists, `wf project add` may
   complete the write even if `config.yaml` is missing or malformed.
   Without that snapshot, rows present without the marker remain a
   conflict that requires operator cleanup.
   Snapshot-only leftovers with zero repo rows are stale temp state
   and may be discarded; repo rows without either `mode: multi` or a
   recovery snapshot remain an operator-visible error.
3. Exactly one row has `status: primary`. Zero or multiple is an
   error; the partial unique index catches multiple at write time.
4. `name` is unique within the project (enforced by `UNIQUE(name)`).
5. `path` resolves under `repo_path` (no `..` escape, no absolute
   paths outside project root).
6. `reqs_path` in `config.yaml` resolves to a readable file at load
   time, OR the loader emits a non-fatal warning. Not fail-closed —
   user may have stale config while editing REQS.
7. Every row's `status` is one of the four valid values (CHECK
   constraint).

---

## 4. UX

### 4.1 Interview flow — mode-first

Current flow asks "multi?" last. Reverse it: ask after detection, branch
immediately.

```
$ wf project add /home/vess/dev/bigco

Detecting project at /home/vess/dev/bigco...

  Found 64 git repositories under this directory.
  (Only the ones you add below will be part of this project.)

Is this a multi-repo project? (y/n) [y]: y

  Multi-repo projects have one PRIMARY repo (the anchor — where
  REQS.md lives by default) plus any number of ACTIVE repos
  (eligible for modifications) and REFERENCE repos (read-only
  context for the model). Everything else is ignored.

  You will configure them one at a time. You can always add, remove,
  or re-status repos later with `wf project repo ...`.

Project name [bigco]: bigco
Description (what it does, who it's for): BigCo platform.
Tech stack — Preferred (use by default): go, python, react
Tech stack — Acceptable (okay when needed): typescript
Tech stack — Avoid (don't introduce): java

Run AI investigation for each repo as you add it? (y/n) [y]: y
  (When you add a repo, an agent will read its README, manifests,
  and recent commits to suggest description, test_cmd, build_cmd, etc.
  You review and accept/edit each answer. Costs ~1-3 cents per repo.)

--- Primary repo ---
  Which repo is the primary? (This is where REQS.md will live by
  default, and will be the fallback target if a story's repo is
  ambiguous.)

  Filter (leave blank for full list): bigco
  Matching sub-repos:
    [1] bigco-risk-service
    [2] bigco-position-service
    [3] bigco-reporting-legacy
    [4] back to full list (64)
  Pick [1]: 1

  Running AI investigation on bigco-risk-service...
  [AI output shown below, §6.3]
  Accept all? (y/n/edit) [y]: y

  Git identity for this sub-repo: not configured.
  Copy project-level identity (Alice <alice@example.com>)? [y]: y
  Set.

--- Active repos ---
  Active repos are eligible to host workstreams. You can add as many
  as you want, blank answer when done.

  Unregistered sub-repos (63):
    [1] bigco-position-service
    [2] bigco-reporting-legacy
    [3] bigco-docs
    [f] filter by substring
    [d] done
  Pick: 1
  Add bigco-position-service as active? [y]: y

  [AI investigation, review, git identity propagation — same as primary]

  Continue adding active repos?
    [1] bigco-reporting-legacy
    [2] bigco-docs
    [f] filter by substring
    [d] done
  Pick: d

--- Reference repos ---
  Reference repos are read by the model when planning and reviewing
  code, but NEVER selected as the target of a story. Use them for
  docs, SPECs, shared libraries you depend on, design notes, or
  anything you want the model to be aware of without ever modifying.

  Unregistered sub-repos (62):
    [1] bigco-reporting-legacy
    [2] bigco-docs
    [f] filter by substring
    [d] done
  Pick: 2
  Add bigco-docs as reference? [y]: y

  [AI investigation; test/build prompts skipped for reference repos]

  Continue adding reference repos?
    [1] bigco-reporting-legacy
    [f] filter by substring
    [d] done
  Pick: d

--- REQS.md location ---
  Looking for REQS.md...
    Not at project root.
    Found at bigco-risk-service/REQS.md (primary).
  Use bigco-risk-service/REQS.md as the REQS path? (y/n) [y]: y

--- Summary ---
  Project:   bigco
  Primary:   bigco-risk-service
  Active:    bigco-position-service
  Reference: bigco-docs
  REQS:      bigco-risk-service/REQS.md
  Ignored:   62 other detected repos (preserved on disk, not registered)

  Write config and register project? (y/n) [y]: y

Seeded 3 repos into the database.
Wrote /home/vess/dev/hashd-ops/projects/bigco/config.yaml
Next: wf --project bigco plan
```

**Write ordering (crash safety):** the server writes a temporary
recovery snapshot (`.project-create-recovery.yaml`) first, then
inserts repo rows into SQLite inside a single transaction, then writes
`config.yaml` last, and removes the snapshot only after a successful
config write. This bounds the blast radius of any mid-write crash to
exactly one supported recovery shape:

- **DB write fails, YAML untouched:** next load sees no rows and no
  `mode: multi` → treated as a fresh project. Safe. User re-runs
  `wf project add`.
- **DB write succeeds, YAML write fails:** next load sees repo rows
  plus a persisted recovery snapshot, and `wf project add` can safely
  resume whether `config.yaml` is missing or malformed.
- **Config write succeeds, snapshot cleanup fails:** next load sees
  valid `config.yaml` plus a stale recovery snapshot. The config/DB
  state is authoritative; cleanup is idempotent and the stale snapshot
  may be removed later.
- **Repo rows survive without a snapshot and without `mode: multi`:**
  this is not recoverable automatically. Surface an invariant error
  and require operator cleanup instead of guessing.

**Crash-recovery mode of `wf project add`:** when invoked and it
detects the recovery shape (DB has rows, `mode: multi` is absent, and
the recovery snapshot exists), it:

1. Reads the existing `project_repos` rows.
2. Validates that the submitted recovery payload's repo entries still
   match the persisted `project_repos` rows; any mismatch aborts the
   recovery instead of silently rewriting config around divergent DB
   state.
3. Skips the mode-first question and the per-repo prompts entirely.
4. Replays the persisted top-level project fields from the recovery
   snapshot, including `reqs_path`.
5. Writes `config.yaml` with `mode: multi`.
6. Removes the recovery snapshot.
7. Reports "Recovered multi-repo config from database" to the user.

The recovery path is idempotent — re-running it a second time is a
no-op (load succeeds normally because rule 2 is now satisfied).

**Not written to the database:** detected sub-repos the user did not
add. Their "ignore" state is implicit (no row exists). Only repos the
user explicitly soft-deletes later get a persisted `status: ignore` row.

### 4.2 Interview flow — single-repo

For a directory with no detected sub-repos, or when the user answers
"no" to the mode question, fall through to today's single-repo flow. No
`mode:`, no DB rows — just the flat `config.yaml`. With one or more
detected sub-repos, the mode-first prompt is still shown so the user
can opt into multi-repo setup.

AI-investigation y/n is offered once, at the top, for the single repo.

### 4.3 CLI surface: `wf project repo ...`

All mutations dispatch through the Go server's sync endpoints (see §5);
they never write SQLite directly from the CLI process.

```
wf project repo list [--json]
```

List all repos in the current multi-repo project. Shows `name`,
`status`, `path`, short description. `--json` for scripting.

```
wf project repo show <name> [--json]
```

Display one repo row in full. Includes `status`, `ignored_at`,
`ignored_reason`, `updated_at`, and `updated_by` when applicable.

```
wf project repo add <path> --status primary|active|reference
                           [--name <n>] [--description ...]
                           [--test-cmd ...] [--build-cmd ...]
                           [--default-branch ...]
                           [--merge-gate-test-cmd ...]
                           [--merge-mode pr|local]
```

Add a repo to the project. `--status` is required. If `--name` is
omitted, it defaults to the basename of `<path>` after path
normalization relative to `project.repo_path`. The command accepts the
same per-repo fields stored in `project_repos`.

```
wf project repo set-status <name> primary|active|reference|ignore
```

Mutate status. You simply set the stage to whatever you want it to
be. There is no explicit demote operation. Special cases:

- `set-status <X> primary`: atomic swap. The current primary is **always**
  re-tagged as `active` in the same transaction. There is no
  choice of demote target. If you want the old primary to become
  `reference` or `ignore`, run a second `set-status` command
  afterward.
  This is a deliberate design choice — one concept per command,
  no hidden side effects beyond the "exactly one primary"
  invariant.
- `set-status <X> ignore`: soft-delete path. Preserves the row and
  records the ignore metadata.
- `set-status <X> active|reference` from `ignore`: pre-fills from the
  preserved row, clears `ignored_at` and `ignored_reason`. If
  coming to `active` and `test_cmd` is empty, the server rejects the
  transition until `test_cmd` is set.
- The CLI does not expose `--expected-updated-at` for status changes.
  The server-side FSM still uses status-based CAS internally so a
  concurrent transition fails as a conflict instead of silently
  overwriting another status change.
- Setting the current `primary` to anything else is an error
  unless paired with a `set-status <other> primary` (which demotes
  automatically). Error suggests `wf project repo set-status <other>
  primary` to swap first.

```
wf project repo set-path <name> <new-relative-path>
                         [--expected-updated-at <ts>]
```

Update a repo's stored relative path. `expected_updated_at` is
auto-fetched if omitted.

```
wf project repo edit <name> [--description ...] [--test-cmd ...]
                           [--build-cmd ...] [--default-branch ...]
                           [--merge-gate-test-cmd ...]
                           [--merge-mode pr|local]
                           [--expected-updated-at <ts>]
```

Edit repo fields (description, test_cmd, build_cmd,
merge_gate_test_cmd, merge_mode, default_branch). Repo rows are not
hand-edited in YAML; edits go through this command. At least one edit
flag is required. `expected_updated_at` is auto-fetched if omitted.

```
wf project repo remove <name> [--hard]
```

Remove a repo. Default is soft: equivalent to
`wf project repo set-status <name> ignore`. `--hard` deletes the DB row
entirely, losing preserved config. `--hard` requires
`--expected-updated-at <ts>`; soft delete does not. Soft-delete uses
the same server-side status-transition CAS described above.

**Guard:** both soft and hard delete refuse when any workstream
targeting this repo is in a non-terminal state (§5.1.2). The error
enumerates the offending workstreams so the user can close or
complete them first. No `--force` escape hatch — data-integrity
invariants don't negotiate.

```
wf project repo prune
```

Walks rows with `status: ignore` and removes any whose `path` no longer
exists on disk. **Never touches rows whose path still exists.** This is
the only automatic pathway that deletes `status: ignore` rows;
manual `--hard` is the other.

**Auto-detect for moved repos:** on any `wf` command that loads the
project, if a non-ignore row's `path` doesn't exist on disk, check
whether a different on-disk sibling has the same `name` OR the same
git remote URL as the missing row. If exactly one candidate is
found, emit a single-prompt offer ("`foo` appears to have moved
from `./foo` to `./bar`, update path? [y/n]"). Zero or multiple
candidates → no prompt, just warn.

**Dismissal persistence.** "Never retry within a session" is wrong
because every `wf` command is its own session. Instead:

- User dismissals are persisted to
  `<project_ops_dir>/skip_move_check.json` as
  `[{"repo_name": "...", "dismissed_at": "2026-04-22T10:30:00Z"}, ...]`.
- The prompt is skipped for a given repo if a dismissal with that
  `repo_name` exists and is **less than 24 hours old**. After
  24 hours the prompt re-appears (user may have changed their
  mind, or the sibling situation may have changed).
- Running `wf project repo set-path <name> <path>` explicitly clears
  the dismissal entry for that repo — the user has addressed the
  underlying case.
- `wf project repo set-status <name> ignore` also clears the dismissal
  entry — the repo is no longer subject to auto-detect at all.
- Global `--no-auto-move-detect` flag on every `wf` command
  suppresses the check entirely for scripted / CI runs. Also
  settable via project config
  (`auto_move_detect: false` under a future `ux:` block —
  deferred; flag is enough for v2).

This costs one small JSON read per `wf` load, bounded to the
project ops dir (not the repo on-disk path), so there's no risk of
the file vanishing with the moved repo.

**Known limits of auto-detect** (documented so users know when to
fall back to explicit `wf project repo set-path`):

- Rename without move (e.g., `git mv foo foo-v2` in place): the old
  name no longer matches the dir; the new dir has a different
  name. Remote-URL match still catches this if the repo has a
  remote.
- Local-only repos with no remote: only dir-name match applies.
  A same-repo-renamed-and-moved case with no remote falls through.
- Forks with diverging remote URLs: a sibling with the same code
  but a different remote URL won't match by URL. Dir-name is the
  only surviving axis.
- Ambiguous matches (two siblings both match): explicitly
  suppressed to avoid guessing; user runs `move` manually.

The auto-detect is a best-effort ergonomic affordance, not a
guarantee. When it fails, `wf project repo set-path <name>
<new-path>` is always explicit and reliable.

### 4.4 Explanatory text

**Before the primary repo prompt:**

> The **primary** repo is the anchor of this project. It is where
> `REQS.md` is expected to live by default (you can override), it is
> what the planner falls back to when a story's target is ambiguous,
> and its name appears first in all summaries. There is exactly one
> primary. You can swap it later with `wf project repo set-status <other>
> primary`.

**Before the first active-repo prompt:**

> **Active** repos are where modifications happen. A story can be
> routed to any active repo, open a workstream there, create a branch,
> and merge back via this repo's configured merge mode.
>
> Each story targets exactly ONE repo. There is no such thing as a
> cross-repo story: work that spans repos becomes N linked stories
> with a merge gate — the planner will structure it that way.
>
> There is **no cap** on the number of active repos. You can have 2,
> 20, or 200. More active repos means (a) the pre-planner has more
> candidates to choose between per story, so routing quality depends
> on keeping descriptions sharp, and (b) more test/build commands
> for you to keep current. Add the ones you actually intend to modify
> — not "everything in the directory."

**Before the first reference-repo prompt:**

> **Reference** repos are read-only context. The planner and reviewers
> will read their code, docs, and SPEC files to understand how your
> project fits together — but stories are never routed to them.
> Workstreams are never opened against them.
>
> Use `reference` when:
>   - You consume a library or service you don't control.
>   - You want the model to know about an adjacent system's API shape
>     without being allowed to modify it.
>   - Documentation, design notes, and specs live in a separate repo.
>   - You have a legacy codebase that you want the planner to
>     *understand* but never *touch*.
>
> If you're not sure whether something is active or reference, think:
> "If the planner decided to change this, would I be okay with that?"
> If no → reference.
>
> Adding reference repos has a real cost: every planning call reads
> some context from every reference repo. Keep the list focused. You
> can always add more later with `wf project repo add <path>
> --status reference`.

**Before soft-delete (`wf project repo remove` default):**

> This will **soft-delete** `<name>` — it will no longer be routed to,
> read as context, or appear in summaries. Its configuration is
> preserved so you can restore it later with `wf project repo set
> <name> active`. To delete the config entirely, re-run with `--hard`.

### 4.5 Non-interactive invocation

`--no-interview` on `wf project add` writes a complete project without
prompts using the same default interview path the interactive flow would
take. Today it supports the existing flag surface only:

- `--suggest`: run the `detect` stage on every registered repo.
- `--no-suggest`: explicit opt-out.

**Default behavior with `--no-interview`:** accept the interview's
default answers, keep AI disabled unless `--suggest` is passed, write
`config.yaml`, and seed the DB.

**Container-root bootstrap guardrail:** when `wf project add` is
bootstrapping a non-repo container root into a local control repo,
root-level files are committed by default, but root-level directories
require an explicit `--commit-root-dirs` in non-interactive mode.

---

## 5. FSM, Server Endpoints, and ZMQ Events

### 5.1 Repo status FSM

Repo status transitions go through an FSM, consistent with workstream
and story state mutations in the rest of hashd. The FSM is both
**enforcement** (guards prevent invariant violations) and
**documentation** (a single JSON file reads out all valid transitions
and their triggers).

**Why an FSM even though all states are mutually reachable:** the
transitions carry non-trivial guards and side effects. Encoding them
as data — in `orchestrator/workflow/repo_fsm.py` exporting to
`server/internal/fsm/repo_fsm.json` via the existing
`export_contracts.py` pipeline — keeps the enforcement and the spec
in one place.

**States:** `primary`, `active`, `reference`, `ignore` (same four as
§3.1).

**Triggers and transitions:**

| Trigger | Source states | Dest | Guard / side effect |
|---|---|---|---|
| `promote_to_primary` | `active`, `reference`, `ignore` | `primary` | Atomic swap: current primary → `active` in the same transaction (see 5.1.1). No choice of demote target — always `active`. |
| `set_active` | `reference`, `ignore` | `active` | Guard: `test_cmd` must be non-empty — prompt the user or error under `--yes`. Clear `ignored_at` / `ignored_reason` when coming from `ignore`. |
| `set_reference` | `active`, `ignore` | `reference` | Clear `ignored_at` / `ignored_reason` when coming from `ignore`. |
| `soft_delete` | `active`, `reference` | `ignore` | Set `ignored_at = now()`, optionally `ignored_reason`. **Guard:** reject if any workstream targeting this repo is in a non-terminal state (see §5.1.2). |

Transitions from `primary` to anything other than `primary` happen
only as the paired demotion half of `promote_to_primary`. Direct
`primary → active|reference|ignore` calls are rejected — they would
violate "exactly one primary." The FSM has no `demote_from_primary`
trigger; the client calls `set <other> primary`, and the old
primary's status change is the automatic side effect.

**Implementation pattern:** follow the existing Go
`server/internal/fsm/transition.go::TransitionWorkstream` function as
the template — CAS on status + updated_at, guard evaluation, event
emission, all in one `db.WithTx`. A new
`TransitionRepo(ctx, projectDir, name, trigger, payload)` function
handles it.

#### 5.1.1 Atomic primary swap

`promote_to_primary` always demotes the current primary to
`active`. Both rows change in one transaction:

```
BEGIN TRANSACTION;
UPDATE project_repos SET status = 'active', updated_at = :now
  WHERE status = 'primary';
UPDATE project_repos SET status = 'primary', updated_at = :now
  WHERE name = :new_primary;
COMMIT;
```

The partial unique index on `status = 'primary'` is the safety
net. If two concurrent swaps race, one transaction fails with a
constraint violation; the CLI surfaces the error and the user
retries or the UI refreshes via ZMQ.

No `demote_to` parameter exists. Users who want the old primary to
land as `reference` or `ignore` run a second `set` command after
the swap completes. One concept per command.

#### 5.1.2 Soft-delete guard: active workstreams

`soft_delete` (active|reference → ignore) must reject the transition
if any workstream targeting this repo is in a non-terminal state.
Non-terminal workstream states (per `server/internal/fsm/workstream_fsm.json`):

- `provisioning`
- `active`
- `implementing`
- `awaiting_human_review`
- `merging`
- `merge_conflicts`
- `resolving`
- `pr_open`
- `pr_approved`
- `ready_to_merge`
- `final_review_with_concerns`

Terminal states that allow soft-delete to proceed: `merged`,
`closed`, `closed_no_changes`.

The guard runs inside the FSM transition function, right before the
CAS write. Error message lists each offending workstream's ID and
status:

```
cannot soft-delete repo "bigco-position-service": 2 active
workstreams target it.
  - WS-1234 (implementing)
  - WS-1289 (pr_open)
Close or complete these workstreams first, then re-run
  wf project repo set-status bigco-position-service ignore
```

The blocker-list SELECT and the status UPDATE run inside a single
SQLite transaction. SQLite serializes writers, so a workstream INSERT
that lands before `BEGIN` is visible to the SELECT, and any INSERT
that would have landed during the transaction is delayed until after
our COMMIT (or, if concurrent, runs against the already-ignored row
and is an application-layer error the caller must handle). No TOCTOU
window is left open between the check and the update.

### 5.2 Why server endpoints

Per `docs/ARCHITECTURE.md`:

> Quick mutations (AC edits, story transitions, feedback writes) go
> through the Go server as synchronous endpoints. These don't need
> Prefect — they're fast and atomic.

Repo status changes fit the same bucket: <30s, latency-sensitive,
atomic. They belong on sync server endpoints.

Per `docs/ARCHITECTURE.md` § "Client And Server Boundary":

> No UI (TUI, Bot, CLI) may directly mutate entity state. All mutations
> dispatch through CLI commands, which handle FSM transitions, event
> emission, and error handling.

Repo state is entity state. TUI and bot dispatch via `subprocess.run`
on the CLI, same pattern as existing entity mutations. The CLI, in
turn, calls the Go server sync endpoint.

### 5.3 Endpoints

All endpoints live under `/api/projects/{name}/repos/...`. Return
JSON. Emit ZMQ events on success. All mutations dispatch through the
FSM (§5.1).

| Endpoint | Method | Body | Purpose |
|---|---|---|---|
| `/repos` | GET | — | List all repos. |
| `/repos` | POST | `{name, path, status, description, ...}` | Add a new repo. |
| `/repos/{name}` | GET | — | Show one repo. |
| `/repos/{name}` | PATCH | `{description?, test_cmd?, ...}` | Edit fields. Does not change status/name/path. |
| `/repos/{name}/status` | PUT | `{status, reason?}` | FSM transition. Atomic primary-swap per §5.1.1. No demote-target parameter. Server uses status-based CAS internally. |
| `/repos/{name}/path` | PUT | `{new_path, expected_updated_at}` | Change stored path with row-level CAS. |
| `/repos/{name}` | DELETE | `{hard: bool, expected_updated_at?}` | Remove. Default soft (FSM `soft_delete`); `expected_updated_at` required only when `hard=true`. |
| `/repos/prune` | POST | — | Remove rows whose path is gone. Single transaction. |

**Prune atomicity:** the prune endpoint:

1. Reads the set of `status='ignore'` rows.
2. Stats each row's on-disk path (filesystem call, outside the
   transaction).
3. Inside a single SQLite transaction, issues
   `DELETE FROM project_repos WHERE status='ignore' AND name IN (...)`
   for every row whose path was missing, and COMMITs.
4. Emits a single `repos_pruned` event with the full removed list.

The DELETE is all-or-nothing at the DB layer: partial failure rolls
back, so the DB never ends up in a half-pruned state. The stat step
is outside the transaction because filesystem calls can't be
transactional; the narrow race window ("path vanished during stat,
appeared again before DELETE") is benign — we delete the row for a
path that briefly didn't exist. `--dry-run` uses the same stat loop
without the DELETE.

**Optimistic concurrency:** row-edit, path-change, and hard-delete
mutations use `expected_updated_at` CAS in the request body. Status
transitions and soft-delete run through the FSM and use status-based CAS
internally. Representative row-level CAS update:

```sql
UPDATE project_repos
   SET <field> = :new_value, updated_at = :now, updated_by = :client
 WHERE name = :name AND updated_at = :expected_updated_at;
```

If 0 rows are affected, the server returns `409 Conflict` with the
current row in the body. For status transitions, the FSM performs the
same no-lost-update check against the current status instead of
`updated_at`. No last-write-wins; no lost updates. This is optimistic
concurrency, not a table lock — concurrent changes to different rows
proceed in parallel.

`POST /repos` (add) has no `expected_updated_at` — the row doesn't
exist yet. The `UNIQUE(name)` constraint is the safety net for
two concurrent adds of the same name; second add returns `409`.

**`updated_by` provenance:** every mutation endpoint reads the
`X-Hashd-Client` request header and writes it into `updated_by`.
Known values: `cli`, `tui`, `bot`. Absent or unknown → `unknown`.
CLI sets the header when dispatching; TUI and bot set their own.
This lets the audit trail attribute changes without requiring
authentication (pre-team-server).

### 5.4 ZMQ events

New event types, dual-written to the events table and published via
the existing ZMQ pubsub (same pattern as workstream/story events):

| Event type | Payload | Emitted when |
|---|---|---|
| `repo_added` | `{name, status, path, description}` | `POST /repos` succeeds. |
| `repo_edited` | `{name, changed_fields}` | `PATCH /repos/{name}` succeeds. |
| `repo_status_changed` | `{name, old_status, new_status, demoted?: {name, old_status, new_status}}` | `PUT /repos/{name}/status` succeeds. Includes demoted sibling info on primary-swap. |
| `repo_path_changed` | `{name, old_path, new_path}` | `PUT /repos/{name}/path` succeeds. |
| `repo_removed` | `{name, hard: bool}` | `DELETE /repos/{name}` succeeds. |
| `repos_pruned` | `{removed: [name1, name2, ...]}` | `POST /repos/prune` succeeds. Single event for the batch. |

**Wire format:** topic-prefixed msgpack, per `docs/ARCHITECTURE.md`:

```
b"bigco\x00repo_status_changed" + msgspec.msgpack.encode(event)
```

**Subscribers:** TUI project-detail screen subscribes to
`b"<project>\x00repo_"` prefix to react to all repo events. No
polling fallback. Specific TUI/bot integration deltas in §9.3.

### 5.5 Concurrent mutation summary

- **Every row-level mutation** (PATCH, PUT, DELETE) uses
  `expected_updated_at` CAS (§5.3). Two clients mutating the same
  row in parallel: one wins, the other gets `409 Conflict` and
  refreshes from the ZMQ event.
- **Primary-swap** (§5.1.1): DB transaction on two rows + partial
  unique index. If two concurrent swaps race, one transaction
  fails on the index; the CLI surfaces the error.
- **Soft-delete + concurrent promotion:** CAS catches it. The
  second mutation sees `updated_at` has changed and returns 409.
- **Prune:** inside one transaction (§5.3). Either all missing-on-
  disk rows are removed or none are. A concurrent `set <X> active`
  on a row prune was about to remove bumps `updated_at` mid-
  transaction and the prune's delete for that row becomes a
  zero-row update — row survives, prune reports it as "modified
  during prune, skipped."

---

## 6. AI Assistance During `wf project add`

**Delegation, not duplication.** An earlier draft of this section
specified a standalone "repo investigation" stage with its own
prompt and JSON schema. That collides with
`docs/design/archive/build-system-detection.md` Phase 3, which specifies a
`detect` stage (Claude Sonnet-class, user-configurable via
`stage_agents.detect`) that reads a repo and proposes `test_cmd` /
`build_cmd`. Both designs arrived at the same pattern
independently.

**Resolved:** multi-repo v2 **reuses** the `detect` stage from
build-system-detection. No new prompt, no new schema, no new agent
configuration. One stage, two callers.

### 6.1 When

- **Per-repo, lazy.** The `detect` stage runs when a repo is added
  (interview or `wf project repo add`), not batched upfront.
- **Opt-in.** Interactive: one y/n at interview start. Non-
  interactive: `--suggest` positive flag, `--no-suggest` explicit
  skip. The project-level default persists in `config.yaml` as
  `suggest_default: true|false`.
- **Flag vocabulary aligned with existing precedent.** `--suggest`
  already exists on `wf project describe` and `wf project tech`.
  Multi-repo v2 extends the same flag to `wf project add` and
  `wf project repo add`, matching build-system-detection Phase 3.
  One verb across the project-add surface.

### 6.2 What the `detect` stage provides

Per build-system-detection §"Phase 3 → Output contract," the
stage returns:

```json
{
  "test_cmd": "string or null",
  "build_cmd": "string or null",
  "detected_system": "string",
  "justification": "string"
}
```

Multi-repo v2's interview consumes all four fields directly. If
build-system-detection Phase 3 extends the schema with optional
extras later, multi-repo v2 benefits automatically.

### 6.3 Fields multi-repo v2 needs that `detect` doesn't cover

`project_repos` has a few fields the `detect` stage doesn't
produce. How each is populated:

| Field | Source |
|---|---|
| `description` | User types it in the interview. A short sentence is faster than accepting a generated one. |
| `default_branch` | Detect from git (`git rev-parse --abbrev-ref HEAD` or `git symbolic-ref refs/remotes/origin/HEAD`). No AI. |
| `merge_gate_test_cmd` | Default to `test_cmd` if unset. User can override. |
| `merge_mode` | Default to `pr`. User override. |

No expansion of the `detect` schema needed for v2. If real users
want AI-drafted descriptions later, that's a narrow future
extension of the stage — not a reason to invent a parallel stage
now.

### 6.4 Review UI

The interview shows the `detect` output alongside the extras the
interview asks for directly:

```
Investigation for bigco-risk-service (detect stage):

  Detected system: go
  Test command:    go test ./...
  Build command:   go build ./...
  Justification:   Standard Go module layout; `go.mod` at root,
                   tests under internal/.

  [a] Accept all    [e] Edit per-field    [r] Reject (manual entry)
  > a

  Description (type your own):
  > Core policy enforcement and guardrails.
  Default branch [main]:
  Merge gate [go test ./...]:
  Merge mode [pr]:
```

The `detect`-provided fields are grouped and accepted as a block;
the v2-only fields are asked per-prompt.

### 6.5 Token tracking

`detect` stage calls record into the existing `agent_calls` table
via `record_agent_call(stage="detect", ...)` per build-system-
detection §"Phase 3 → Token usage tracking." Multi-repo v2's
per-repo investigations show up in the same ledger as every other
agent call.

**No cost estimation, ever.** Both design docs agree.

At the end of a multi-repo `wf project add` with `--suggest`, a
summary line reports totals: "AI investigation: 3 repos, 12,400
input tokens, 1,850 output tokens." That text comes from a direct
aggregate query on `agent_calls` rows just written, not a pre-call
estimate.

**Shared future dependency with build-system-detection:** a
project-level token roll-up command (working name
`wf project tokens`) is referenced by both docs but does not
exist today. The data is already captured in `agent_calls`; what's
missing is the query + presentation surface. Tracked as an
explicit follow-up — first doc to reach that phase owns speccing
it. Neither doc depends on it for the current phases.

### 6.6 Reference-repo handling

When adding a reference repo, the `detect` stage **is still
invoked** if AI is on — `detected_system` is useful even for
read-only repos (it tells the planner "this is a rust project, so
type signatures live in .rs files"). But:

- `test_cmd`, `build_cmd`, `merge_gate_test_cmd`, `merge_mode`
  prompts are **skipped** in the review UI for reference repos.
  The detect stage's suggestions are recorded in the description
  for future reference (and if promoted to active later, they're
  re-surfaced).
- If the user later promotes `reference → active`, `wf project
  repo set <name> active` prompts for the test/build fields. If
  AI is on and the values are empty, it re-invokes `detect` for
  fresh output.

### 6.7 Failure modes

- `detect` stage fails / times out → fall through to heuristic
  detection only (existing `detectBuildSystem` path). One-line
  warning: "AI investigation unavailable; heuristic defaults
  applied."
- JSON parse / schema violation → same fallback. Raw response
  logged to `projects/<name>/setup.log`.
- User rejects → manual entry (the 6-prompt flow with rich
  detection output restored).

### 6.8 Dependency on build-system-detection Phase 3

Historical note: multi-repo v2 Phase 1b depended on
build-system-detection Phase 3 being in place. That dependency has
since been satisfied:

1. build-system-detection Phase 1 shipped in PR #312.
2. build-system-detection Phase 2a shipped in PR #314.
3. build-system-detection Phase 3a shipped in PR #316.
4. build-system-detection Phase 3b.1 shipped in PR #328.
5. build-system-detection Phase 2b shipped in PR #339.
6. build-system-detection Phase 3b.2 / 3b.3 shipped in PRs #336 / #337.

The sequencing rationale below remains valid as historical context:
multi-repo v2 could land its core data model and interview without AI,
and the `detect` stage integration was additive.

---

## 7. REQS Precedence

`reqs_path` in `config.yaml` is a single string, relative to
`repo_path`. The interview picks the default.

**Baseline provided by PR #311:** `resolveReqsPath` in
`server/internal/cli/project.go` detects REQS.md in the project
root plus every detected sub-repo, prompts the user to confirm a
single candidate or pick from numbered options, and auto-picks
the highest-precedence candidate (root wins) under `--yes`.
`SubRepoResult.ReqsExists` flags which sub-repos have REQS.md
without re-running filesystem stats.

Multi-repo v2 **extends** PR #311's algorithm rather than
replacing it. The extension is status-aware: only `primary` and
`active` repos participate in the search; `reference` and
`ignore` are excluded (REQS should not live in read-only or
soft-deleted repos).

### 7.1 Algorithm (post-PR-311)

On `wf project add` (after repos configured):

1. **If `--reqs-path <path>` on CLI:** use it. Validate. If missing,
   prompt.
2. **Single-repo:** look at `<repo_path>/REQS.md`. Exists → default
   `"REQS.md"`. Not → prompt, default presented is `"REQS.md"`.
3. **Multi-repo:** search in order:
   - `<repo_path>/REQS.md` (project root)
   - `<repo_path>/<primary_path>/REQS.md`
   - `<repo_path>/<primary_path>/REQUIREMENTS.md` (case-insensitive
     `reqs.md`, `requirements.md` also matched)
   - For every `active` repo: same search.
4. **Result handling:**
   - Zero matches: prompt. Default: `<primary_name>/REQS.md`.
   - One match: prompt with it as default.
   - Multiple matches: list numbered, default is primary's match (or
     root if primary doesn't have one).
5. **Reference repos NOT searched.** REQS should not live in a
   read-only repo. User can override with `--reqs-path` or prompt.

### 7.2 Examples

**BigCo:** `bigco-risk-service/REQS.md` exists; others don't.

```text
Searching for REQS.md...
  Not at project root.
  Found at bigco-risk-service/REQS.md (primary).
Use bigco-risk-service/REQS.md as REQS path? (y/n) [y]: y
```

Writes `reqs_path: bigco-risk-service/REQS.md`.

**Root:** `/path/to/project/REQS.md` exists.

```text
Searching for REQS.md...
  Found at REQS.md (project root).
Use REQS.md as REQS path? (y/n) [y]: y
```

Writes `reqs_path: REQS.md`.

**Multi-match:** both root and primary have one.

```text
Searching for REQS.md...
  Found 2 candidates:
    [1] REQS.md (project root)
    [2] bigco-risk-service/REQS.md (primary)
  Which? [2]: 2
```

**No match:** none exist.

```text
Searching for REQS.md...
  No REQS.md found.
  Default location: bigco-risk-service/REQS.md
  The planner will bootstrap it on first run.
Confirm path [bigco-risk-service/REQS.md]:
```

---

## 8. Planner Integration

### 8.1 `repo_router.py` changes

Today, `route_story_to_repo` builds a manifest from `config.repos` and
asks an LLM to pick one. In v2, the source is the DB:

1. **Load routable repos** from the `project_repos` table:
   `SELECT * FROM project_repos WHERE status IN ('primary','active')`.
2. **If only the primary exists:** skip LLM call, return primary.
3. **Otherwise:** build the manifest with status markers and call
   the router prompt. Manifest line format:
   ```
   - **{name}** [primary | active]: {description}
   ```
4. Router prompt is updated to explain that `primary` is the
   anchor/fallback.

### 8.2 The project-map prompt block

All multi-repo prompts (planning, refinement, implementation, review)
share a single `{project_map}` block that renders the full
primary+active+reference picture with behavioral rules. This is the
hashd equivalent of AGENTS.md content — a map plus rules, not
pre-loaded file contents.

**No pre-loading. No budget cap. No arbitrary ceiling.** The map
tells the model what exists and how to behave; actual file reads
happen on demand via the model's file-read tools when the work
genuinely requires them. Arbitrary content caps in prompts are
rejected as an anti-pattern — they punish legitimate deep-tracing
cases to save a few tokens on the common shallow case.

**Rendered block:**

```
## Project Repositories

Your story targets exactly one repository: {target_repo_name}
  Path: {target_repo_path}

Other repositories in this project:

  Active (read/write capable, but NOT your target for this story):
    - {name} — {path}
      {description}
    ...

  Reference (read-only, external or adjacent systems):
    - {name} — {path}
      {description}
    ...

RULES:
  1. No story may touch more than one repository. This is a hard
     invariant. Your changes go in {target_repo_name} only.
  2. You may READ files from other repos if tracing types,
     functions, callers, or specs requires it. Use your normal
     file-read tools.
  3. Do NOT modify any repo other than your target. If your work
     reveals that changes are needed elsewhere, surface that as a
     follow-up story in your output — do not make the change.
  4. Reference repos are out-of-scope by design. Read only if
     absolutely necessary to understand your target; never propose
     changes there.
```

**Which prompts include it:**

- `prompts/plan_discovery.md`: yes, rendered with `{target_repo_name}`
  set to the candidate target chosen by the router, or the primary
  during initial discovery.
- `prompts/refine_story.md`: yes, same rendering.
- `prompts/implement.md`: yes. The implementer explicitly needs
  rules (1) and (3) — we want it reading protobufs from a reference
  repo without silently editing them.
- `prompts/review_contextual.md`: yes, so the reviewer can cite
  cross-repo references and flag cross-repo changes as invariant
  violations.

Single-repo projects: the `{project_map}` block is empty (rendered
as zero characters). No vestigial "this is a single-repo project"
padding.

**Where the model reads from:** reference and other-active repos
are accessed via their original on-disk paths, which are included
verbatim in the map above. No worktree mounting. The stage agent's
cwd is its worktree, but file-read tools accept absolute paths.

### 8.3 Workstream provisioning

Unchanged for the target repo: the stage agent gets a worktree of
the target repo only.

Reference and other-active repos are **not** mounted into the
workstream worktree. They stay at their original on-disk paths.
The `{project_map}` block (§8.2) lists those paths verbatim; the
stage agent's file-read tools can reach them because cwd ≠ reach.
Modification is forbidden by prompt rule, not by filesystem
sandbox. This is the v2 position — the user has explicitly said no
to mounting. If real workflows need sandbox-level enforcement, a
Phase 4+ read-only mount can be added.

### 8.4 `resolve_repo_path` / `resolve_default_branch` changes

`ProjectConfig.resolve_repo_path(target_repo)` in Python today:

```python
if target_repo and self.is_multi_repo:
    return self.get_repo(target_repo).path
return self.repo_path
```

V2: `self.repos` is now a DB-backed property. `resolve_repo_path`
rejects non-routable targets:

```python
if target_repo and self.is_multi_repo:
    repo = self.get_repo(target_repo)  # DB query
    if repo is None:
        raise ValueError(f"Repo '{target_repo}' not found.")
    if repo.status in ("reference", "ignore"):
        raise ValueError(
            f"Repo '{target_repo}' has status '{repo.status}' — "
            f"only 'primary' or 'active' repos can be targets."
        )
    return repo.path
return self.repo_path
```

`is_multi_repo` becomes `self.config.mode == "multi"`. No DB round-trip
just to check the flag.

### 8.5 Test plan for planner changes

- `test_repo_router.py`: primary-only, reference-only (error — no
  valid targets), mixed cases.
- `test_planner_multi_repo.py`: reference manifest present in
  discovery prompt; routable manifest does not leak reference
  entries.
- `test_project_repos_crud.py`: CRUD on the table, primary-swap
  atomicity, soft-delete round-trip, prune.
- `test_repo_events.py`: every endpoint emits the right ZMQ event.

---

## 9. Completion and repo-name entry

Two distinct surfaces, handled differently:

### 9.1 Shell completion for `wf` CLI args

Cobra's `ValidArgsFunction` / `RegisterFlagCompletionFunc`. Completes
repo names in `wf project repo set-status <TAB>`, `wf project repo show
<TAB>`, `wf project repo edit <TAB>`, `wf project repo remove <TAB>`,
`wf project repo set-path <TAB>`. Completion function queries the DB for
repo names and filters by relevance (e.g., `set` excludes
already-primary candidates for the "make primary" case). **Zero new
deps**, already in the codebase.

### 9.2 Interview: numbered menus, not in-prompt tab completion

Inside interactive `wf project add` prompts, repo selection is a
**numbered menu**, not tab completion. Rationale: in-prompt tab
completion inside a running program requires a full-featured line
editor dep (`chzyer/readline` is dormant; `c-bata/go-prompt` and
`huh` are heavier). That dep cost buys a 5% UX polish and owns a
maintenance liability we will not recover from if the upstream
project stops moving.

The pattern uses `promptChoice` / `promptChoiceFrom` helpers that
already exist in `server/internal/cli/project.go` (added by PR
#311). Workflow for any sub-repo selection step (primary,
active-loop, reference-loop):

1. Show numbered list of candidate sub-repos, capped at ~10 per
   page.
2. If the full list exceeds the cap, offer a **substring filter**
   entry: user types a fragment, the list re-renders filtered.
3. User picks by number, or types `f` to re-filter, or types `d`
   to finish the loop.

See §4.1 for the rendered interview dialogue.

**For very long sub-repo lists** (the 64-repo case), the substring
filter is the first affordance offered — the full list is never
dumped in one screen. This is a real benefit over tab completion,
which would force the user to remember a name prefix.

**No new Go dependencies.** Completion source is the detected
sub-repo list from `SubRepoResult`, minus ones already registered
this session.

---

### 9.3 TUI and bot integration deltas

This section spells out what the TUI and Telegram bot need to do in
response to the new `project_repos` table and ZMQ events. Called out
so the implementing agent doesn't scope-creep into the TUI without
a plan or skip the integration entirely.

**TUI (Python, Textual):**

- Project-detail screen (`watch/project.py` — or the equivalent
  current home) adds a **Repos panel** rendering the routable +
  reference + ignored rows. Layout mirrors the `wf project repo
  list` output (§A.3).
- Subscribe to `b"{project}\x00repo_"` prefix on the existing ZMQ
  sub socket. Handler routes each event type to a panel
  re-render:
  - `repo_added`, `repo_removed`, `repo_path_changed`,
    `repos_pruned` → full panel refresh (cheap, <10 rows
    typically).
  - `repo_status_changed` → update the two affected rows (moving
    one, possibly demoting another on primary-swap).
  - `repo_edited` → update the one row's description / commands.
- Single-repo projects: the Repos panel is hidden entirely (no
  vestigial empty panel).
- No direct DB writes from the TUI. Status changes dispatched via
  `subprocess.run` on `wf project repo set-status ...` inside a
  `@work(thread=True)` method. Same pattern as existing entity
  mutations per `docs/ARCHITECTURE.md`.
- Keybindings for the panel: `s` (set status — opens status
  modal), `r` (remove — soft), `e` (edit fields).
  Non-destructive-default, destructive require confirm modal.

**Telegram bot:**

- New commands:
  - `/repos` — list all repos in the current project with status.
  - `/repo <name>` — show one repo.
- Status mutations from the bot dispatch via `run_in_executor` on
  the CLI, matching the pattern in `docs/ARCHITECTURE.md`.
- Bot subscribes to `b"{project}\x00repo_"` prefix and optionally
  notifies the chat on `repo_status_changed` when primary swaps
  (primary swap is a big deal for a multi-user project) — but
  this is opt-in via a per-chat setting, off by default, to avoid
  notification spam.

**Where these land in phasing:** the TUI and bot work ride in
Phase 1 as part of the client-side PR(s). Spec'd here so the
implementing agent has the contract; not expected to break out
into a separate later phase.

## 10. Runtime Sequence Examples

### 10.1 Primary-swap

User: `wf project repo set-status bigco-position-service primary`

1. CLI calls `PUT /api/projects/bigco/repos/bigco-position-service/status`
   with body `{"status": "primary"}`.
2. Server:
   - Begins transaction.
   - Reads current primary (`bigco-risk-service`).
   - CAS-updates the target via the FSM's status-based guard
     (`ExpectedStatus = current.Status`). Zero rows → 409 rollback.
   - Demotes the old primary: `UPDATE project_repos SET
     status='active', updated_at=:now WHERE status='primary' AND
     name!=:target`.
   - Commits.
   - Inserts event row into events table.
   - Publishes ZMQ `repo_status_changed` with demoted sibling info.
3. CLI prints confirmation. TUI receives the ZMQ event, re-renders.

### 10.2 Soft-delete and prune

Day 1: user soft-deletes `bigco-reporting-legacy`:

- `wf project repo remove bigco-reporting-legacy`.
- Server sets `status='ignore', ignored_at='2026-04-22T10:30:00Z'`.
- Row preserved. Path still exists on disk.

Day 90: user deletes `./bigco-reporting-legacy` from disk entirely.

Day 91: user runs `wf project repo prune`:

- Server walks `WHERE status='ignore'`.
- For each row, stats the path. `bigco-reporting-legacy` → gone.
- Prompts: "Will remove 1 row (path no longer exists): bigco-reporting-legacy. Confirm? [y/n]".
- On confirm, deletes the row. Emits `repos_pruned`.

### 10.3 Auto-detect move

User moves `./frontend` → `./web` on disk. Runs any `wf` command.

- Config load sees the `frontend` row has `path=./frontend`; stats
  `./frontend` → missing.
- Enumerates siblings. `./web` is a git repo.
- `./web`'s remote URL matches `frontend`'s stored remote URL (from
  initial AI investigation).
- Prompts: "`frontend` appears to have moved from `./frontend` to
  `./web`. Update path? [y/n]".
- On confirm: `PUT /repos/frontend/path` with body `{"new_path": "./web"}`.
  Emits `repo_path_changed`.

---

## 11. Open Questions

Small residual set. Most of what this section used to hold has been
decided and folded into the spec.

### 11.1 Apply-to-all defaults for uniform answers

Scratchpad idea (B) proposed project-level defaults for merge_mode,
etc. Push to v4 — the interview is already short with `detect`-stage
pre-fill. Apply-to-all adds a "project-level default" layer for
marginal savings. Confirm defer.

---

## 11.x Closed in this design

For the record — items that were open questions in earlier drafts
and are now decided:

- **Primary-swap semantics.** No demote target. Setting a new
  primary always re-tags the old primary as `active`. Users wanting
  a different outcome run a second `set` command (§4.3, §5.1.1).
- **Non-interactive status-selection flags.** Deferred. `--no-interview`
  currently means "accept the interview defaults without prompts"; it
  does not yet expose explicit `--primary` / `--active` /
  `--reference` selectors.
- **Interview repo-selection UX.** Numbered menus (using the
  existing `promptChoice` helper) with a substring-filter fallback
  for long sub-repo lists. No in-prompt tab completion, no new Go
  dependency. See §9.2.
- **Optimistic locking.** CAS on `updated_at` for every row-level
  mutation from day one (§5.3, §5.5). `409 Conflict` surfaces
  the conflict; UI refreshes via ZMQ. Not deferred to a team-
  server phase.
- **Project-root git-repo requirement.** Plan to drop it for
  `mode: multi` in Phase 2 (§13), not Phase 3 as originally
  written. Scope likely small; if it turns out larger than
  expected during implementation, push to Phase 3.
- **AI agent identity.** Delegate to the `detect` stage from
  `docs/design/archive/build-system-detection.md` Phase 3. No standalone
  investigation stage, prompt, or schema. Agent configuration
  (model, override) follows `stage_agents.detect`. See §6.

---

## 11.y Future architecture sketch (team server)

hashd is heading toward a team server where multiple users connect
from multiple UIs against one shared server. This section captures
the *business requirements* for that future, not the implementation
— so v2 doesn't corner us but doesn't over-engineer either.

### Business requirements

1. **Multi-user.** The server is a shared instance; individual
   humans are first-class identities.
2. **Projects can be user-scoped or shared.** A project may be
   "User A's view of this codebase" or "the team's view of this
   codebase." Both are legitimate.
3. **Multiple projects can point at the same on-disk directory.**
   Different users, or the same user with different workflow
   contexts, can have different maps over the same files.
4. **The map can differ per-user.** Within one project, user A
   might treat repo X as `active` (they modify it) while user B
   treats it as `reference` (they only read it). Both views are
   valid simultaneously.
5. **Permission model for mutations.** Who can change a project's
   status mapping, add/remove repos, promote primaries? Roles
   matter (owner, collaborator, viewer).
6. **Audit trail.** Every mutation is attributable to a human. The
   `updated_by` column in v2 is a weak form of this (`cli`, `tui`,
   `bot`); a team server needs a user identity.
7. **Concurrent edit resolution.** CAS (already in v2) prevents
   silent overwrites. UI affordances ("this was changed by
   Alice") layer on top.
8. **Real-time coordination.** ZMQ events (already in v2) push
   changes to every connected UI. Team members see each other's
   mutations as they happen.
9. **Isolation where it matters.** One user's soft-deletes should
   not bleed into another user's view. Hard-deletes of shared
   rows need consensus or role-gated permission.

### What v2 already does that aligns with this future

- DB-first, not file-first. YAML surviving concurrent multi-user
  mutation was never in the cards.
- FSM + CAS for every mutation. Scales to multi-user unchanged.
- ZMQ event topics already namespace by project. Adding a user
  axis later is a topic extension, not a rewrite.
- `updated_by` column is a wire already pulled. Populate it with
  a user identity string when identities exist.
- The spec is careful about "per-project" vs "per-user-per-project"
  boundaries — the schema and endpoint surface stay additive.

### What v2 deliberately does NOT do

- No user model, no auth, no permissions. This is a single-user
  local-server design today.
- No "this map is mine vs. the team's" distinction. All maps in
  v2 are shared-by-omission (one map per project).
- No presence / collaboration affordances in the UI.

### Suggested shape for the team-server phase

Not a binding commitment, just a starting-point sketch for
whoever picks up that design later:

- Add a `users` table and a nullable `user_id` column to
  `project_repos`. NULL means "shared/team view" — backward
  compatible with today's rows.
- Event topics grow to `project\x00user\x00event_type`, with
  NULL user being the "team" channel that every user
  subscribes to.
- Role/permission enforcement lives in the server, evaluated
  before FSM dispatch.
- UI shows whose view is whose, and whose mutation landed when.

Flagged here so the implementing agent for v2 leaves natural
extension points rather than baking in assumptions that would
have to be unwound.

---

## 12. Explicit Non-Goals

Restated for the implementing agent:

- No cross-repo atomic stories. One story = one repo, enforced.
- No automatic garbage collection of soft-deleted rows. `prune`
  only removes rows whose path no longer exists.
- No cap or warning on active-repo count. No cap on reference-repo
  count.
- No TUI / wizard screen for multi-repo setup. Linear prompts only.
- No AI-driven repo *discovery*.
- No submodule-management workflow beyond detection/classification.
  Superprojects are supported as a multi-repo variant, but hashd does
  not manage `git submodule add/update/sync`.
- No `repos:` list in `config.yaml`. Ever. Repo state lives in
  SQLite.
- No hand-editable repo config. `wf project repo edit` is the
  supported path.
- No legacy multi-repo config migration. User confirmed on
  2026-04-22 that no multi-repo projects exist in production.
- No reference-repo worktree mounting. Planner reads from original
  on-disk paths.
- No per-repo `autonomy` override. Autonomy is project-level.
- No per-repo `reqs_path`. One REQS per project. SPEC update routing is
  defined in §3.4.
- No change to single-repo `config.yaml` shape.

---

## 13. Implementation Phases

**External dependencies / merge order:**

- **PR #311 (`worktree-project-add-fixes`)** must merge before
  multi-repo v2 Phase 1 starts. PR #311 heavily rewrites
  `newProjectAddCmd` (+714 lines), delivers the helpers v2 uses
  (`promptChoice*From`, `promptYesNo*From`, `prepareRepoPath`,
  `ensureGitRepo`, `runWithTimeout`, `validateRepoName`), and
  lands the `resolveReqsPath` baseline that §7 extends.
  Phase 1 rebases onto PR #311, not onto the current `dev` tip
  before it.
- **build-system-detection Phase 3** must merge before multi-repo
  v2 Phase 1b starts (§6.8). Phase 1 itself has no dependency on
  it.

**Sizing note:** Phase 1 is the largest slice. If it grows past
~1000 LOC in one PR, the natural seam is server-side (schema, FSM,
endpoints, events, Python router update) vs client-side (Go CLI,
interview, TUI/bot integration). Implementing author's call on
whether to split; the design is coherent either way.

### Phase 1 — core data model, FSM, CLI, prompts

Server-side:
- SQLite schema: `project_repos` table + partial unique index
  (§3.4).
- FSM: `orchestrator/workflow/repo_fsm.py` + export to
  `server/internal/fsm/repo_fsm.json` via existing
  `export_contracts.py` pipeline (§5.1).
- Go: `TransitionRepo` paralleling `TransitionWorkstream` in
  `server/internal/fsm/transition.go`.
- Go `RepoConfig` becomes a DB-row type; YAML marshalling for
  repos removed.
- `ProjectConfig`: add `Mode` field, read/write `mode:` in YAML
  only.
- Python `lib/config.py`: parallel changes; `is_multi_repo` reads
  `mode` from YAML; `repos` / `get_repo` / `routable_repos` /
  `reference_repos` are DB queries.
- Go server endpoints: `/repos` CRUD + `/status`, `/path`,
  `/prune` (§5.3). All mutations route through the FSM.
- ZMQ event emission on every endpoint (§5.4).
- `X-Hashd-Client` header plumbing for `updated_by` (§5.3).

Client-side:
- CLI surface: `wf project repo list | show | add | edit | set-status | set-path |
  remove | prune` (§4.3). All dispatch to server endpoints.
- Interview flow: mode-first, curated, primary/active/reference
  prompts with §4.4 explanatory text. No AI integration in this
  phase (Phase 1b).
- Tab completion for `wf project repo` via Cobra (§9.1 item 1).
- TUI Repos panel + ZMQ subscription (§9.3).
- Telegram bot `/repos` and `/repo` commands (§9.3).

Planner integration (rides with server-side):
- `repo_router.py` filters routable repos from DB (§8.1).
- `resolve_repo_path` rejects non-routable targets (§8.4).
- `{project_map}` block threaded into `plan_discovery.md`,
  `refine_story.md`, `implement.md`, `review_contextual.md`
  (§8.2, Appendix A.4).

Parity-regression fixes still on multi-repo v2's plate after PR
#311 merges: **has-commits warning** (scratchpad #7) and
**duplicate-name rejection** (scratchpad #8). Sub-repo git
identity propagation (#4) and `reqs_path` prompt (#3) are
delivered by PR #311 — no action required from v2.

### Phase 1b — AI integration (after build-detection Phase 3)

Gated on `docs/design/archive/build-system-detection.md` Phase 3 landing
first — that delivers the `detect` stage this work consumes.

- Wire multi-repo interview to call the `detect` stage per repo
  (§6).
- Review UI: grouped "detect-provided" fields + per-prompt extras
  (§6.4).
- Reference-repo handling: run `detect` for `detected_system` but
  skip test/build prompts in review UI (§6.6).
- `detect` token usage rolls through existing `agent_calls` table
  — no new plumbing (§6.5).
- Failure-mode fallback: heuristic detection only on `detect`
  failure (§6.7).
- Interview sub-repo selection: numbered menus + substring filter
  using `promptChoice` from PR #311 (§9.2). No new Go dep.
  (Independent of build-detection; can land in Phase 1 if desired —
  only grouped here for cadence.)

### Phase 2 — planner test suite + cross-surface polish + git-less project root

- Planner test suite updates (§8.5).
- `{project_map}` block rendering verified across all four
  prompt surfaces.
- Auto-detect-move sidebar prompt (§4.3, §10.3) — exercised and
  tested.
- **Drop project-root git-repo requirement for `mode: multi`.**
  User has indicated this is a real limitation for workspace-style
  parents (large multi-repo projects like BigCo) and scope is likely small. Relocate any
  project-root-git-dependent state (hooks, initial commit) into
  `ops_dir/projects/<name>/`. If implementation reveals this is
  larger than expected, bump to Phase 3.

### Phase 3 — ergonomics, if needed

- `--apply-to-all` defaults for uniform answers (§11.2). Ship only
  if real users ask.
- Progressive / lazy per-repo config (scratchpad idea D).

### Phase 4+ — team-server foundation

Future phase when hashd starts supporting multiple concurrent
users. Scope described as business requirements in §11.y (future
architecture sketch), not as implementation commitments. Likely
deliverables when the time comes:

- User model + auth (server-side).
- Optional `user_id` on `project_repos` rows for per-user views.
- Role-gated mutation permissions.
- UI affordances for presence, attribution, and conflict
  resolution.

v2 deliberately stays additive so this phase is an extension, not
a rewrite.

---

## Appendix A: Example states

### A.1 Single-repo `config.yaml`

(No changes from today.)

```yaml
name: myproject
repo_path: /home/user/dev/myproject
default_branch: main
reqs_path: REQS.md
description: "A single-repo project."
tech:
  preferred: "go"
  acceptable: "python"
  avoid: ""
test_cmd: "go test ./..."
build_cmd: "go build ./..."
merge_gate_test_cmd: "go test ./..."
merge_mode: pr
autonomy: gatekeeper
```

DB: zero rows in `project_repos`.

### A.2 Multi-repo `config.yaml`

```yaml
name: bigco
repo_path: /home/vess/dev/bigco
mode: multi
default_branch: main
reqs_path: bigco-risk-service/REQS.md
description: "BigCo platform. See sub-repo SPECS."
tech:
  preferred: "go, python, react"
  acceptable: "typescript, rust"
  avoid: "java"
autonomy: gatekeeper
suggest_default: true
```

DB rows in `project_repos`:

| name | path | status | description | ignored_at |
|---|---|---|---|---|
| bigco-risk-service | ./bigco-risk-service | primary | Core policy enforcement... | — |
| bigco-position-service | ./bigco-position-service | active | Primary application workflows... | — |
| bigco-docs | ./bigco-docs | reference | Product documentation... | — |
| bigco-reporting-legacy | ./bigco-reporting-legacy | ignore | Decommissioned... | 2026-04-22T10:30:00Z |

### A.3 `wf project repo list` output

```text
NAME                           STATUS     PATH                             DESCRIPTION
bigco-risk-service         primary    ./bigco-risk-service         Core policy enforcement...
bigco-position-service   active     ./bigco-position-service   Primary application workflows...
bigco-docs                   reference  ./bigco-docs                   Product documentation...
bigco-reporting-legacy           ignore     ./bigco-reporting-legacy           Decommissioned...
```

`--json`:

```json
[
  {"name":"bigco-risk-service","status":"primary","path":"./bigco-risk-service","description":"..."},
  {"name":"bigco-position-service","status":"active","path":"./bigco-position-service","description":"..."},
  {"name":"bigco-docs","status":"reference","path":"./bigco-docs","description":"..."},
  {"name":"bigco-reporting-legacy","status":"ignore","path":"./bigco-reporting-legacy","description":"...","ignored_at":"2026-04-22T10:30:00Z"}
]
```

### A.4 Router prompt (update to `prompts/repo_router.md`)

The existing router prompt asks the model to pick a repo from a
manifest. v2 threads status markers through and explains the
primary role. Full replacement text:

```markdown
# Repo Router

You are selecting which repository in this multi-repo project will
host a story. Exactly one repository must be chosen. No story may
touch more than one repository.

## Available Repositories

{routable_manifest}

## Context

Story:
{story_title}

{story_body}

{reference_block_if_any}

## How to Decide

- The **primary** repo is the project's anchor. If the story is
  genuinely ambiguous about where it belongs, prefer the primary
  as a fallback.
- **Active** repos are peers. Pick whichever best matches the
  story's scope.
- **Reference** repos MUST NEVER be picked. They are read-only
  context, not routable targets. If your reasoning leads toward
  a reference repo, re-read the story — you may be looking at a
  linked follow-up story that belongs elsewhere.

## Output

Respond with a single JSON object:

    {"target_repo": "<name>", "reason": "<one sentence>"}

No markdown, no prose outside the JSON.
```

Where `{routable_manifest}` is rendered as:

```
- **bigco-risk-service** [primary]: Core policy enforcement and guardrails.
- **bigco-position-service** [active]: Primary application workflows and state transitions.
```

Reference and ignore rows are excluded from the routable manifest.
If reference repos exist, the router additionally receives a
`{reference_block_if_any}`:

```
## Reference Repositories (not routable; listed for context only)

- **bigco-docs**: Product documentation. Do NOT pick this.
```

The router prompt explicitly warns against picking reference repos
— belt-and-suspenders over the manifest exclusion.

### A.5 Project-map block for plan/refine/implement/review

Rendered into each of those prompts as `{project_map}` per §8.2.
Full text is reproduced there. Single-repo projects render empty.

---

## Appendix B: File-level change summary

Phase 1 touch list (assumes PR #311 has merged); approximate LOC.

- `server/internal/config/config.go` — add `Mode` to `ProjectConfig`;
  strip `Repos []RepoConfig` from YAML marshalling; `RepoConfig`
  becomes a DB row type. ~60 LOC net.
- `server/internal/config/detect.go` — no schema change; `scanSubRepos`
  unchanged. `SubRepoResult.ReqsExists` (from PR #311) consumed as-is
  by §7 extension.
- `server/internal/db/project_repos.go` (new) — CRUD + primary-swap
  transaction. ~250 LOC.
- `server/internal/db/migrations/NNN_project_repos.sql` (new) —
  `CREATE TABLE project_repos` + index. ~30 LOC.
- `server/internal/fsm/repo_fsm.json` (new, exported from Python) —
  ~1 KB of states + transitions.
- `server/internal/fsm/transition.go` — add `TransitionRepo`. ~150 LOC.
- `server/internal/api/repos.go` (new) — HTTP handlers for §5.3.
  ~300 LOC.
- `server/internal/api/events.go` — add repo event types to dispatcher.
  ~20 LOC.
- `server/internal/cli/project.go` — rewrite multi-repo block of
  `newProjectAddCmd` into mode-first curated flow. Reuses PR #311's
  `promptChoice*From`, `promptYesNo*From`, `prepareRepoPath`,
  `ensureGitRepo`, `runWithTimeout`, and `validateRepoName`. Extend
  `resolveReqsPath` to filter by repo status. ~250 LOC net
  (down from ~400 by leveraging PR #311's helpers).
- `server/internal/cli/project_repo.go` (new) — `list | add | edit |
  set | move | remove | prune | show` subcommands. ~500 LOC.
- `orchestrator/workflow/repo_fsm.py` (new) — FSM definition exported
  via `export_contracts.py`. ~100 LOC.
- `orchestrator/lib/config.py` — `RepoConfig` becomes DB-row
  dataclass; `ProjectConfig.repos` reads from DB on demand; add
  `routable_repos` / `reference_repos` helpers. ~100 LOC.
- `orchestrator/pm/repo_router.py` — filter by status; skip LLM when
  only primary exists. ~20 LOC.
- `orchestrator/pubsub.py` — register new event types. ~10 LOC.
- `prompts/repo_router.md` — update to include status markers.
- `tests/test_project_repos_crud.py` (new) — CRUD + primary-swap
  atomicity + soft-delete + prune.
- `tests/test_repo_router.py` — extend for status filtering.
- `tests/test_config.py` — extend for `mode:` field handling.
- `tests/test_repo_fsm.py` (new) — FSM transitions + guards.
- `docs/design/archive/multi-repo-v2.md` — this document.
- `README.md` § Multi-Repo Projects — rewrite to match v2 (Phase 1
  finish).
- `config.sample.yaml` — add multi-repo example with `mode: multi`
  (Phase 1 finish).
