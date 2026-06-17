# E2E Test Plan

## Purpose

The durable test guidance for hashd. Two complementary tracks:

- **Track A — Fresh-install validation:** does a brand-new install on a brand-new system reach a working state? Single-repo, single-platform-per-pass.
- **Track B — Workflow validation:** does the full lifecycle (discovery → planning → run → review → merge) actually work end-to-end on representative project shapes, including multi-repo? This is where ongoing testing surfaces real blockers.

Read top-to-bottom for fresh-install validation. Skip to Track B when validating workflow against the current state of `dev`.

## Living document

This file is the canonical guidance both the coordinating session and Agent T follow. When a phase passes cleanly, mark it. When a phase finds a bug, file an `F-NNN` finding (see Findings Ledger at the bottom) and stop the phase. When a finding closes, retest the phase that surfaced it.

If a brief is dispatched to a non-T agent that touches surface area covered by a phase here, that brief should explicitly reference the phase number it's addressing or invalidating.

---

## Track A — Fresh-install validation

Validate the full hashd lifecycle on fresh systems (1 Mac, 1 Linux). Every CLI command, every workflow path, every error condition.

### Test Project: todo-app

A minimal Go HTTP to-do API. Small enough for AI to implement in minutes, complex enough to exercise all workflow stages.

#### REQS.md

```markdown
# todo-app Requirements

A full-stack to-do application: Go REST API backend + React frontend. Two directories at the repo root: `server/` and `web/`.

## Backend (server/)

Go HTTP API using the standard library. Single binary, no frameworks.

1. **CRUD endpoints**: Create, read, update, delete to-do items via REST.
   - POST /api/todos — create item (title required, optional description)
   - GET /api/todos — list all items (supports ?status=pending|done filter)
   - GET /api/todos/:id — get single item
   - PUT /api/todos/:id — update item (title, description, status)
   - DELETE /api/todos/:id — delete item

2. **Persistence**: SQLite database via modernc.org/sqlite. Items survive restart.
   - Schema: id (integer PK), title (text), description (text), status (text), created_at, updated_at

3. **Status workflow**: Items start as "pending". Can be marked "done". Can be reopened to "pending".

4. **Input validation**: Title required and non-empty. Status must be "pending" or "done". Return 400 with JSON error on bad input.

5. **CORS**: Allow requests from localhost:5173 (Vite dev server).

6. **Static serving**: Serve `web/dist/` at `/` for production. API routes take precedence.

7. **Tests**: Table-driven tests for every endpoint. Use httptest, no external test dependencies. `go test ./...` must pass.

## Frontend (web/)

React + TypeScript via Vite. Minimal UI — no component library, just plain HTML + CSS.

1. **Todo list view**: Shows all todos. Each item displays title, description (if any), and status badge (pending/done).

2. **Add todo**: Text input + button at the top. Submits POST, appends to list without page reload.

3. **Toggle status**: Click a todo item to toggle pending ↔ done. Calls PUT, updates in place.

4. **Delete**: X button on each item. Calls DELETE, removes from list.

5. **Filter**: Three buttons — All / Pending / Done. Filters the displayed list (client-side filter, not API query).

6. **Tests**: Vitest + React Testing Library. Test that adding, toggling, and deleting update the UI. `npm test` must pass.
```

### Single-repo / monorepo note

todo-app is a **two-directory single-git-repo** project (server/ + web/). This exercises the common monorepo pattern. True multi-repo (separate git repos under one hashd project, mode=multi) is covered in Track B.

---

### Phase 0: Install

Run on both Mac and Linux. Each phase notes which machine.

| # | Machine | Command | Pass criteria |
|---|---------|---------|---------------|
| 0.1 | Linux | `curl -fsSL https://raw.githubusercontent.com/codr1/hashd-code/main/install.sh \| bash` | Installs without error |
| 0.2 | Mac | Same | Installs without error |
| 0.3 | Both | `wf version` | Shows wf version, python version, server status |
| 0.4 | Both | `wf doctor` | Reports no project (expected), all tools checked |

---

### Phase 1: Local Repo (from scratch)

Test `wf project add --local` — creates a git repo and registers it.

| # | Command | Pass criteria |
|---|---------|---------------|
| 1.1 | `mkdir ~/test-todo && wf project add ~/test-todo --local --yes` | Creates dir, git init, detects no build system, registers project |
| 1.2 | `wf project show` | Shows project with repo_path, no test/build commands |
| 1.3 | `wf doctor` | Green (except no test_cmd — expected) |
| 1.4 | `wf project remove test-todo --yes` | Removes project dir, clears DB, confirms deletion |
| 1.5 | `wf project list` | Empty — project gone |
| 1.6 | Verify `~/.hashd/projects/test-todo/` is gone | No leftover files |

---

### Phase 2: GitHub Repo (from scratch)

Test `wf project add --create` — creates a remote repo on GitHub.

| # | Command | Pass criteria |
|---|---------|---------------|
| 2.1 | `wf project add ~/todo-app --create --host github --name todo-app-test` | Creates GitHub repo, clones, registers |
| 2.2 | `wf project show` | Shows project with github forge, merge_mode=pr |
| 2.3 | `wf doctor` | All green including forge auth |
| 2.4 | Copy REQS.md (from above) into the repo, commit, push | Repo has requirements |
| 2.5 | `wf project describe --suggest` | Agent explores repo, prints a description, and saves it to project config by default |
| 2.6 | `wf project describe --suggest --no-save` | Prints a new description suggestion without changing saved project config |
| 2.7 | `wf project tech --suggest` | Agent suggests a tech stack and saves it to project config by default |
| 2.8 | Change or remove `REQS.md`, then run `wf project describe` | CLI prints the saved description plus a stale-warning telling the user to refresh |

After Phase 6, clean up: `gh repo delete todo-app-test --yes`

---

### Phase 3: Planning

| # | Command | Pass criteria |
|---|---------|---------------|
| 3.1 | `wf plan discover` | Agent reads REQS.md, discovers 3-5 stories |
| 3.2 | `wf plan list` | Stories visible with titles and status=available |
| 3.3 | Pick a story (CRUD endpoints): `wf plan story STORY-XXXX` | Refines with acceptance criteria |
| 3.4 | `wf show STORY-XXXX` | Shows story with ACs |
| 3.5 | `wf plan edit STORY-XXXX` | Edits story (e.g., add AC for error codes) |

---

### Phase 4: Single Workstream — Happy Path

Run one story through the full lifecycle.

| # | Command | Pass criteria |
|---|---------|---------------|
| 4.1 | `wf run STORY-XXXX` | Preflight passes. Provisions workstream. Breakdown generates micro-commits. |
| 4.2 | `wf show WS-ID` | Status=active, plan shows commits |
| 4.3 | `wf watch WS-ID` | TUI shows progress. Stages run: implement → test → review. |
| 4.4 | Wait for completion or human gate | Workstream reaches ready_to_merge or awaiting_review |
| 4.5 | `wf review WS-ID` | Shows structured review with `verdict`, `confidence`, and severity-tagged `findings` |
| 4.5a | `wf review WS-ID --json` (or inspect the review record) | Output has `verdict ∈ {approve, reject}`, `confidence ∈ [0.0, 1.0]`, `findings` array with each entry `{text, severity}`, severities in `{major, minor, nit, suggestion}` |
| 4.6 | `wf diff WS-ID` | Shows branch diff with actual code changes |
| 4.7 | `wf log WS-ID` | Timeline shows all events |
| 4.8 | `wf approve WS-ID` | Transitions to ready_to_merge |
| 4.9 | `wf merge WS-ID` | Merges to main. Archives. Worktree cleaned up. |
| 4.10 | `cd server && go test ./...` on main | Backend tests pass |
| 4.10b | `cd web && npm test` on main | Frontend tests pass |
| 4.11 | `wf list` | Workstream shows status=archived |

---

### Phase 5: Error Paths

Start a second story for these tests.

| # | Test | Command | Pass criteria |
|---|------|---------|---------------|
| 5.1 | Reject and retry | `wf reject WS-ID -f "the tests don't cover edge cases"` | FIX commit added to plan, workstream re-activates. Next review's rendered prompt includes a `claimed_fixes_section` populated from the prior implementer's `changes` list (verifies the claim-validation flow). Verify by inspecting the next review stage result/log payload for `rendered_prompt` and searching for `claimed_fixes_section`; record the log path or DB query used. |
| 5.2 | Wait for retry | `wf watch WS-ID` | Agent addresses feedback, re-implements |
| 5.3 | Skip a commit | `wf skip WS-ID` | Current micro-commit marked done, moves to next |
| 5.4 | Reset workstream | `wf reset WS-ID` | Plan cleared, worktree recreated |
| 5.5 | Close workstream | `wf close WS-ID` | Status=closed, worktree removed |
| 5.6 | Reopen workstream | `wf open WS-ID` | Status=active |
| 5.7 | Preflight: wrong branch | `cd worktree && git checkout main`, then `wf run WS-ID` | Preflight error: "Worktree on wrong branch" with fix hint |
| 5.8 | Preflight: missing agent | Temporarily rename claude binary, `wf run STORY-YYYY` | Preflight error: "Claude Code is not installed" with install hint |
| 5.9 | Workstream feedback | `wf workstream feedback WS-ID "focus on error handling"` | Guidance recorded |
| 5.10 | FIX cycle uses dedicated prompt | After `final_review` rejects, observe the next implementer invocation | Stage uses `implement_fix.md` (not `implement.md`); rendered prompt includes `fix_requirements_section` framed as established acceptance criteria; implementer's diff is either net-subtractive (`total_removed > total_added`) or minimal (`total_added <= 10` and `total_changed <= 20`) |

---

### Phase 6: Parallel Workstreams

Run two stories simultaneously.

| # | Command | Pass criteria |
|---|---------|---------------|
| 6.1 | `wf run STORY-A` (SQLite persistence) | Provisions WS-A |
| 6.2 | `wf run STORY-B` (input validation) | Provisions WS-B |
| 6.3 | `wf list` | Both show status=active |
| 6.4 | `wf watch` (no ID — dashboard) | Both visible with live status |
| 6.5 | Both reach ready_to_merge | Approve both |
| 6.6 | `wf merge WS-A` then `wf merge WS-B` | First merges immediately. Second waits for concurrency lock, then merges. No conflicts (different files). |
| 6.7 | `cd server && go test ./...` + `cd web && npm test` | All tests pass after both merges |

---

### Phase 7: Existing Repo (re-attach)

Test removing and re-adding an existing project. Verifies clean removal and re-registration.

| # | Command | Pass criteria |
|---|---------|---------------|
| 7.1 | `wf project remove todo-app-test --yes` | Project removed. DB gone. Config gone. |
| 7.2 | Verify: `ls ~/.hashd/projects/todo-app-test/` | Directory does not exist |
| 7.3 | Verify: repo still exists on disk at ~/todo-app with code | Code untouched — only hashd metadata removed |
| 7.4 | `wf project add ~/todo-app` | Re-registers. Detects Go. Detects existing tests. Detects git remote. |
| 7.5 | `wf doctor` | All green |
| 7.6 | `wf plan list` | Empty — old stories not carried over (fresh DB) |

---

### Phase 8: Ad-Hoc Story

After re-attaching, create a story manually (not from discovery).

| # | Command | Pass criteria |
|---|---------|---------------|
| 8.1 | `wf plan story "Add /todos/:id/toggle endpoint"` | Creates story directly |
| 8.2 | `wf plan story STORY-YYYY` | Refines: AC = toggle pending↔done, return updated item, 404 on missing |
| 8.3 | `wf run STORY-YYYY` | Full lifecycle: preflight → breakdown → implement → test → review |
| 8.4 | `wf approve WS-ID` / `wf merge WS-ID` | Merges the toggle endpoint |
| 8.5 | `cd server && go test ./...` + `cd web && npm test` | All tests pass including new toggle tests |
| 8.6 | Manual curl test: `curl -X POST localhost:8080/api/todos/1/toggle` | Returns toggled item |
| 8.7 | Open browser to localhost:8080, click a todo | Toggle works in the UI |

---

### Phase 9: Remote CLI (stretch)

Server on Linux, CLI on Mac.

| # | Machine | Command | Pass criteria |
|---|---------|---------|---------------|
| 9.1 | Linux | `hashd-server --ops-dir ~/.hashd --addr :1337` | Server starts, listening |
| 9.2 | Mac | `export HASHD_SERVER_URL=http://<linux-ip>:1337` | Env set |
| 9.3 | Mac | `wf list` | Shows workstreams from Linux server |
| 9.4 | Mac | `wf show WS-ID` | Shows details from remote |
| 9.5 | Mac | `wf plan story "Add pagination"` | Creates story on remote server |
| 9.6 | Mac | `wf watch` | TUI connects, shows dashboard |
| 9.7 | Mac | `wf approve WS-ID` | Mutation goes through to remote |

---

### Phase 10: Hooks

| # | Command | Pass criteria |
|---|---------|---------------|
| 10.1 | `wf project config set hooks.setup "go mod tidy"` | Config saved |
| 10.2 | `wf run STORY-ZZZZ` | After worktree creation, `go mod tidy` runs in worktree |
| 10.3 | `wf project config set hooks.teardown "echo cleanup"` | Config saved |
| 10.4 | `wf close WS-ID` | Teardown hook runs, "cleanup" in output |
| 10.5 | `wf project config set hooks.setup "sleep 999"` | Config saved |
| 10.6 | `wf project config set hooks.timeout_seconds 2` | Config saved |
| 10.7 | `wf run STORY-ZZZZ` | Setup hook times out. Error message includes "hooks.timeout_seconds" fix hint. Workstream stays at `provisioning` with `provision_error` populated; `wf show` reports `provisioning / failed`. |

---

### Phase 11: Project Config Commands

| # | Command | Pass criteria |
|---|---------|---------------|
| 11.1 | `wf project config list` | Shows all config values; TTY output highlights project overrides and includes a diff footer when overrides exist |
| 11.2 | `wf project config get test_cmd` | Shows configured test command |
| 11.2a | `wf project config diff` | Shows only project overrides with inherited baseline and override values |
| 11.2b | `wf project config show test_cmd` | Shows effective value, source, Default/System/Project stack, and description when available |
| 11.3 | `wf project config set description "A test to-do API"` | Updates description |
| 11.4 | `wf project config get description` | Returns "A test to-do API" |
| 11.5 | `wf project config reset description` | Resets to default (empty) |
| 11.6 | `wf project config get description` | Returns "(not set)" or empty |
| 11.7 | `wf project config reset --all` | Clears project overrides while preserving project identity |
| 11.7 | `wf project interview` | Re-runs setup, current values as defaults |

---

### Phase 12: Reviewer Schema Behavior

Assertions against the reviewer verdicts produced during Phases 4-8. Most checks sample the natural verdicts the reviewer produces during the lifecycle phases above. Tests marked "controlled" require the operator to create a deliberate throwaway condition so the reviewer sees the target behavior; do not merge controlled-bug or controlled-false-claim changes into the project baseline.

| # | Test | Pass criteria |
|---|------|---------------|
| 12.1 | Reviewer surfaces real bugs (controlled or natural) | A known bug is a reproducible defect that breaks an acceptance criterion, misses server-side input validation, or fails a unit/integration test. Either introduce a labeled throwaway `intentional-bug` commit before Phase 4, or confirm the defect occurs naturally during Phases 4-8. Before review, record the reproduction command/scenario and expected failure output. Reviewer finds it; severity is `major`; `verdict` is `reject` |
| 12.2 | Reviewer approves clean work | A commit that meets AC and passes tests gets `verdict=approve` with empty findings or only low-severity findings |
| 12.3 | Nits and suggestions never force reject | A commit whose findings are entirely `nit` and `suggestion` returns `verdict=approve` regardless of count |
| 12.4 | Severity distribution | Across at least 10 reviews sampled from Phases 4-8, findings spread across severities. Not all `major`, not all `nit`. If >=80% of findings across the sampled set belong to one severity category, file a finding. |
| 12.5 | Anti-anchoring on retry | When a retry addresses a flagged finding, the next reviewer does NOT re-flag the addressed item. The implementer's `changes` list claim is reflected in the diff and survives validation. |
| 12.6 | False-claim detection (controlled or natural) | Prefer a natural false claim if one occurs. Otherwise construct the scenario in a throwaway workstream by editing the implementer's captured `changes` entry to claim a fix while leaving the diff unchanged. The next reviewer flags the false claim as a finding; the finding cites both the claimed `changes` entry and the missing diff evidence. |
| 12.7 | Per-commit concerns pool consumption | First `final_review` on a workstream sees populated `per_commit_concerns`. Second `final_review` (after a FIX cycle) sees empty `per_commit_concerns`. `concerns_pool_consumed_at` is set after the first run. Verify internal state with `sqlite3 ~/.hashd/projects/<project>/hashd.db "SELECT concerns_pool_consumed_at FROM workstreams WHERE id='<WS-ID>';"`, then inspect the two final-review rendered prompts/log payloads for `per_commit_concerns` present on the first run and empty on the second. |
| 12.8 | Acknowledged-concerns suppression | After the operator marks a concern as acknowledged, the per-commit reviewer does NOT flag it on subsequent cycles, and the implementer does NOT modify the related code |
| 12.9 | AC framing consistency | On a FIX cycle, the implementer prompt contains `fix_requirements_section` framed as "established acceptance criteria"; `acknowledged_concerns_section` uses the same posture; `descoped_section` continues to read as negative AC |

---

## Track B — Workflow validation (multi-repo + Pattern 6)

Single-repo Track A covers the install and command-surface validation. Track B exercises the full workflow on a representative multi-repo project (`mode=multi`, multiple routable repos in `project_repos`) to catch the cross-language contract drift class that surfaces specifically when target_repo, dispatch payloads, and FSM transitions all interact.

### When to run Track B

- After any PR landing on `dev` that touches the dispatch surface (`server/internal/api/mutations_dispatch.go`, `mutations_plan.go`, `mutations_pr.go`, `run.go`, `approve.go`).
- After any PR landing schema migrations (anything that bumps `SCHEMA_VERSION` in `orchestrator/lib/db/core.py`).
- After any PR landing on the discovery / planning / breakdown stages.
- Whenever the Findings Ledger gates a phase as BLOCKED — re-run from the unblocked step forward.

### Project shape for Track B

A real multi-repo project: one operator-curated `project` with at least 3 routable repos in `project_repos` (mode=multi). This project is **not provided by hashd** — Track B is designed to be run against an operator's own representative project. Do not commit a multi-repo fixture to this repo.

### What "Pattern 6 territory" means

Pattern 6 is the AI-output protocol class — places where the system parses structured output from an AI agent and trips on shape drift. Reaching Pattern 6 territory means a workstream has reached the **implement stage** specifically (not preflight, not provisioning, not breakdown), where the AI is asked to produce code-shaped output that the runner parses. Track B is considered "successful" only when at least one workstream reaches the implement stage and the AI-output parser fires (whether it succeeds or surfaces a finding).

### Track B phases

#### B.0: Project preflight

| # | Command | Pass criteria |
|---|---------|---------------|
| B.0.1 | `wf restart --yes; echo EXIT=$?` | Restart completes, exit 0, schema bumped if pending migration. Both binaries refreshed (CLI + server). |
| B.0.2 | `wf --project <project> project show` | Shows mode=multi, lists all repos in inventory, primary marked |
| B.0.3 | `sqlite3 .../hashd.db "PRAGMA table_info(project_repos);"` | Schema includes target_repo-relevant columns; no missing migration |
| B.0.4 | `wf doctor` | Green |

#### B.1: Discovery → suggestion

| # | Command | Pass criteria |
|---|---------|---------------|
| B.1.1 | `wf plan discover` | Returns exit 0 quickly; flow dispatched |
| B.1.2 | Wait for flow to complete (~2-5 min) | Events table shows `discovery_complete`. No `discovery_failed`. |
| B.1.3 | `wf plan list` | At least one suggestion present, status=available |
| B.1.4 | Inspect suggestion data | For multi-repo project: at least one suggestion has `target_repo` populated to a routable repo name. Cross-cutting suggestions may have `target_repo=NULL`. |

#### B.2: Suggestion → story → run

| # | Command | Pass criteria |
|---|---------|---------------|
| B.2.1 | `wf watch`, then on the Plan screen select the suggested card and claim it (`c` or click `Claim`) | Creates STORY-xxxx in `drafting`, planning flow dispatched |
| B.2.2 | Wait for planning flow (~2-5 min) | Story lands in `draft`, NOT `draft_failed`. Events table shows `planning_complete`. |
| B.2.3 | `wf show STORY-xxxx` | Story has title, problem, source_refs, acceptance_criteria. `target_repo` matches the originating suggestion. |
| B.2.4 | `wf approve STORY-xxxx` | Story transitions to `accepted` |
| B.2.5 | `wf run STORY-xxxx` | Workstream provisioned with `target_repo` from story; transitions to `active`; flow dispatched |

#### B.3: Run → breakdown

| # | Command | Pass criteria |
|---|---------|---------------|
| B.3.1 | `wf show <ws_id>` | Workstream shows `target_repo` matching story. Worktree created in correct repo's path (multi-repo: not project primary). |
| B.3.2 | Wait for breakdown stage (~3-5 min) | Stage produces micro-commits in plan. |
| B.3.3 | If gatekeeper mode: workflow auto-continues to select/implement. If supervised mode: workstream transitions to `awaiting_human_review` (per F-034 contract). |
| B.3.4 | (supervised only) `wf run <ws_id>` OR `wf approve <ws_id>` | Either verb resumes; workstream transitions toward implementing |

#### B.4: Implement (Pattern 6 territory)

| # | Command | Pass criteria |
|---|---------|---------------|
| B.4.1 | Wait for first micro-commit to enter implement stage | AI invocation fires; output parsed |
| B.4.2 | Watch via `wf watch <ws_id>` | Stage progresses without parser error. If parser errors, file F-NNN with full output capture. |
| B.4.3 | Test stage runs after implement | Test cmd executes in the right repo's working tree (multi-repo: target_repo's worktree, not primary's) |
| B.4.4 | Review stage produces structured output | `wf review <ws_id>` shows the flat schema (`verdict`, `confidence`, severity-tagged `findings`) |

#### B.5: PR creation (multi-repo routing)

| # | Command | Pass criteria |
|---|---------|---------------|
| B.5.1 | `wf pr create <ws_id>` (when ready) | PR is created for the workstream and status transitions to `pr_open` |
| B.5.2 | If PR created: verify on forge | PR is on the **target_repo's remote**, not the project primary's |
| B.5.3 | `wf show <ws_id>` | `pr_url` matches the target_repo's host |
| B.5.4 | Merge — `wf merge <ws_id>` | Merges to target_repo's default branch, archives workstream |

#### B.6: Concurrent multi-repo workstreams (stretch)

| # | Command | Pass criteria |
|---|---------|---------------|
| B.6.1 | Launch two workstreams targeting different repos | Both provision into their own worktrees without contention |
| B.6.2 | Both reach implement stage in parallel | No FSM cross-contamination, no project_concurrency deadlock |
| B.6.3 | Merge both | Each PR lands in its own repo's remote |

---

## Findings Ledger

Track B is gated on findings — when one BLOCKER finding is open, T parks until it closes. Re-test the gating phase after the fix lands.

### Resolved (do not re-investigate)

F-001..F-007, F-009, F-013, F-014, F-017, F-018, F-021, F-022, F-024, F-025, F-026, F-027, F-028, F-029, F-030, F-031, F-033, F-034, F-035

### Open (priority order)

| Finding | Severity | Gates | Status |
|---|---|---|---|
| F-036 | BLOCKER | B.2.5 onward | In flight; CLI sends extra `ops_dir` field on dispatch routes; revised brief = server-side accept `?ops_dir=` query param |
| F-019 | BUG | — | CLI strips actionable detail from server validation errors (largely closed by F-035; may have residual sites) |
| F-023 | minor | — | restart single-instance guard — closed by #455 but listed as standing follow-up if any reopen |
| F-032 | cosmetic | — | REQS-annotation step fails after planning succeeds; doesn't roll back the story |
| F-008 | unknown | — | not retested in current cycle; status uncertain |
| F-010, F-011, F-015, F-016 | unknown | — | not retested in current cycle |

### Pattern matches (recurring drift classes)

Findings that turned out to be the same architectural class have a known shape:

- **Pattern 1/2 (cross-language contract drift):** F-017, F-018, F-022, F-030, F-033, F-036. Producer side migrated; consumer side has unaligned field set or rejection rules. Fix is always at the contract layer (sql/queries, generated models, REST shape), not at call sites.
- **Pattern: Diagnostic-shape exit-code leakage:** F-025 reproduced three times across restart, hashd-server startup, run dispatch. The Diagnostic shape works; the exit-code wiring fails to propagate. Fix is wherever the propagation gap lives, with belt-and-braces `WithExitCode(1)` at the construction site.
- **Pattern: Schema-source asymmetry:** Python `core.py` schema text + Go `addColumnIfMissing` migrations. Two writers, one schema. PR #449 / #453 both navigated this. Strategic cleanup is "move schema canonical to Go-numbered migrations" — separately scoped.

---

## Filing a finding

When a phase fails:

1. **Stop the phase.** Don't try to push past the failure to "see what happens." That conflates findings.
2. **Capture state:** what command was run, what was the exact output (CLI text + relevant log files + any events table rows), what was the workstream/story state before and after.
3. **Categorize severity:**
   - BLOCKER: phase cannot continue; downstream phases gated
   - BUG: phase continues but the failure is real and fix-required
   - cosmetic: noise; doesn't affect correctness
4. **Match to a Pattern** if the shape recurs; note it.
5. **File F-NNN** with: severity, expected vs actual, reproduction, suspected fix direction (if obvious).
6. **Park.** Do not retry until coordinator dispatches a fix.

---

## Strategic direction (informs but not directly tested here)

These priorities shape what gets fixed when bugs surface, but aren't themselves test phases:

- **Go server is canonical for state.** Python-side reads should migrate to Go REST; Python-side writes are already mostly behind Go endpoints. Any new finding that surfaces a Python-side direct-DB-read footgun is a candidate for migration, not just a fix-in-place.
- **target_repo flows continuously suggestion → story → workstream.** Any phase that breaks this chain is a regression, not just a feature gap.
- **One sentinel per logical concept.** target_repo's `""` vs `None` split (workstreams vs suggestions) is queued for cleanup; if a phase trips on it, file the finding and reference the queued cleanup.
- **The Go server is the dispatch authority.** Dispatch payloads are trigger metadata; flows fetch full project config from REST. Any flow code that reconstructs ProjectConfig from dispatch payloads is the F-018 family and gets escalated.

---

## Success criteria

### Track A
All Track A phases pass on both Mac and Linux. Specifically:
- Zero install failures
- Zero preflight false positives
- Zero merge failures on clean code
- Parallel workstreams don't deadlock or corrupt
- Remote CLI round-trips all commands
- Project remove leaves no orphaned state
- Re-attach works cleanly with fresh DB
- Ad-hoc story exercises full lifecycle without discovery
- `go test ./...` passes on the todo-app after every merge

### Track B
- B.0 through B.5 pass on a representative multi-repo project
- Pattern 6 territory reached at least once (B.4 implement stage fires AI parser without protocol error)
- target_repo flows continuously through B.1 → B.5 (suggestion → story → workstream → PR remote)
- B.6 (concurrent multi-repo) is stretch — passes when prior phases stable
