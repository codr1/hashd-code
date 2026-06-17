# Python Migration

Updated: 2026-05-27 against `dev` at `e820ba16`.

This document replaces the old footprint and Python/Go parity audits. It tracks
the core Python surface that still participates in hashd orchestration, the
places where Go is now authoritative, and the deliberate divergences that should
not be "fixed back" to older Python behavior.

## Scope

This audit is about the core Python-shrink direction under `orchestrator/`.
Generated Python is counted separately and not investigated as migration work.

Explicitly out of scope:

| Package | Files | LOC | Notes |
| --- | ---: | ---: | --- |
| `packages/hashd-tui/` | 39 | 18,596 | TUI surface, tracked separately. |
| `packages/hashd-bot-telegram/` | 20 | 12,073 | Telegram bot surface, tracked separately. |
| Connector framework | 20 | 3,984 | `orchestrator/connectors/`, `orchestrator/connector_host*.py`, and connector packages. |

The connector subtotal is 4 files / 914 LOC in `orchestrator/` plus 16 files /
3,070 LOC across `packages/hashd-connector-{figma,github,jira}/`.

## Current Footprint

Fresh structural count, excluding `orchestrator/_generated/`, `__pycache__/`,
and the connector framework:

| Directory | Files | LOC |
| --- | ---: | ---: |
| `orchestrator/` root files | 5 | 1,006 |
| `orchestrator/agents/` | 2 | 555 |
| `orchestrator/commands/` | 4 | 406 |
| `orchestrator/entry/` | 4 | 163 |
| `orchestrator/git/` | 7 | 542 |
| `orchestrator/lib/` | 86 | 24,158 |
| `orchestrator/migrations/` | 12 | 1,568 |
| `orchestrator/pm/` | 12 | 5,343 |
| `orchestrator/runner/` | 22 | 6,006 |
| `orchestrator/services/` | 1 | 1 |
| `orchestrator/stages/` | 3 | 419 |
| `orchestrator/workflow/` | 38 | 12,379 |
| **Core handwritten subtotal** | **196** | **52,546** |

Generated sidebar:

| Directory | Files | LOC | Notes |
| --- | ---: | ---: | --- |
| `orchestrator/_generated/` | 15 | 3,361 | OpenAPI, DB, and dispatch client output. Regenerate, do not hand-edit. |

Largest in-scope Python files:

| File | LOC | Role |
| --- | ---: | --- |
| `orchestrator/pm/agent_utils.py` | 1,938 | Agent invocation bridge, Python agent schemas, Go review wrapper. |
| `orchestrator/lib/config.py` | 1,838 | Project config compatibility and test/build gate policy. |
| `orchestrator/lib/server_client.py` | 1,674 | REST client boundary into the Go server. |
| `orchestrator/workflow/deployable_flow.py` | 1,147 | Prefect run entry and lifecycle orchestration. |
| `orchestrator/runner/impl/stages/implementation.py` | 1,051 | Python implementation stage wrapper. |
| `orchestrator/workflow/planning_flow.py` | 1,027 | Story planning flow and annotation application. |
| `orchestrator/workflow/merge_gate.py` | 965 | Merge gate checks and local git/forge side effects. |
| `orchestrator/pm/stories.py` | 956 | Story helper layer. |
| `orchestrator/workflow/engine.py` | 946 | Main implement/test/review loop. |
| `orchestrator/lib/prefect_server.py` | 932 | Prefect service/process integration. |
| `orchestrator/lib/agents_config.py` | 858 | Agent config resolution. |
| `orchestrator/pm/planner.py` | 819 | Planner prompt/result handling. |
| `orchestrator/lib/repo_host.py` | 791 | Forge abstraction. |
| `orchestrator/runner/impl/prompt_context.py` | 787 | Python prompt-context assembly still used outside Go review. |
| `orchestrator/runner/locking.py` | 728 | Runner lock and metadata writes. |
| `orchestrator/workflow/merge/__init__.py` | 705 | Merge flow coordinator. |

## Where Go Is The Source Of Truth

| Python area | Current authority |
| --- | --- |
| `workflow/state_machine.py`, `workflow/entity_fsm.py` | Go FSM is authoritative. Python delegates normal story/workstream/suggestion transitions to the server. The remaining Python force path is crash-recovery plumbing, not a parallel state machine. |
| `workflow/tasks.py::task_review` | Per-microcommit review is Go-owned through `wf internal stage-review` and `server/internal/stages/review`. Python is the Prefect wrapper and envelope mapper. |
| `lib/server_client.py` and `_generated/openapi/` | Go owns API behavior and schemas. Python is a client/compatibility boundary. |
| `lib/db/*` | Generated/read helpers remain in Python for flows that have not moved. Per `docs/ARCHITECTURE.md`, new Python direct DB access is disallowed unless it is generated query output or an explicitly documented migration bridge. |
| `lib/config.py` | Compatibility layer around Go/server config behavior. Some deliberate divergences are pinned below so the Python shim does not regress server policy. |
| `workflow/review.py` | Go owns final branch review through `server/internal/stages/review/final_review.go` and the surrounding stage package. Python remains only as the Prefect-flow-compatible wrapper at `orchestrator/workflow/review.py` until the flow itself moves. |
| `workflow/merge_gate.py`, `workflow/merge/*` | Python remains authoritative for merge-side git/forge flow and gate execution. Go owns adjacent CLI/API/FSM surfaces, but not this flow. |
| `workflow/planning_flow.py`, `workflow/edit_flow.py`, `pm/*` | Python remains authoritative for planning/edit agent flows and story application details. Go owns FSM/state transitions and newer server mutations around the edges. |
| `runner/*`, `workflow/deployable_flow.py`, `workflow/engine.py` | Python remains authoritative for Prefect run lifecycle, runner-stage metadata, shutdown behavior, and orchestration order. |
| `migrations/*` | Python migration files are a historical DB migration boundary. They are not general-purpose runtime DB access. |

## Intentional Divergences Ledger

These entries were rechecked on 2026-05-27. Keep the behavior described here
unless a new migration brief explicitly supersedes it.

| Date | Divergence | Current state |
| --- | --- | --- |
| 2026-05-08 | Empty implementation `test_cmd` falls through to `merge_gate_test_cmd`. | Still current in `ProjectProfile.effective_test_cmd()`. The merge-gate command can serve as the implementation-stage test command when no separate per-commit command is configured. |
| 2026-05-07 | `test_timeout <= 0` means unbounded timeout. | Still current via timeout normalization helpers. Do not reintroduce zero-second subprocess timeouts. |
| 2026-05-06 | Project path inputs are constrained to trusted roots. | Still current. Server/API paths must not accept arbitrary filesystem roots just because older Python did. |
| 2026-05-04 | Pre-planning REQS pull failures halt before annotation. | Still current. Do not create planner annotations from stale requirement context after a pull failure. |
| 2026-04-30 | Planner `open_questions` promote into blocking clarifications. | Still current in planning/edit flows. `stories.data.open_questions` is transient planner output; the `clarifications` table is the durable gate. |
| 2026-04-30 | `wf show` active run state was restored. | Still current. Preserve active run/runner-stage visibility in display surfaces. |
| 2026-04-29 | Plan-review pause transitions to `awaiting_human_review`. | Still current. Do not fall back to the older non-blocking Python state behavior. |
| 2026-04-28 | Prefect flows fetch full project config via REST; dispatch payloads carry trigger metadata only. | Still current. Do not widen dispatch payloads back into full config snapshots. |
| 2026-04-27 | `wf log` accepts `STORY-XXXX`. | Still current. Story IDs remain valid log selectors. |
| 2026-04-27 | `wf project add --name` names the project; `--repo-name` names the remote slug. | Still current. Do not collapse the split back into Python's repo-only `--name`. |
| 2026-04-27 | `build_skipped` is informational only. | Still current. It records operator intent, but does not bypass an implemented build gate. |
| 2026-04-27 | Empty `merge_gate_test_cmd` is a hard fail unless `tests_skipped=true`. | Still current in merge pre-validation and merge gate paths. This is the opposite of the old silent Python skip. |
| 2026-04-27 | `wf review` defaults to display; `--run` stayed deferred. | Still current. Review execution is stage/runner-owned, not a public ad hoc command. |
| 2026-04-27 | Legacy clarify `ask` was dropped. | Still current. Use the current clarification workflow rather than restoring the removed verb. |
| 2026-04-27 | `wf reset --force` was dropped. | Still current. Avoid bringing back destructive reset affordances without a new design. |
| 2026-05-25 | `wf open --force` was restored. | Still current. The restored force behavior is an intentional exception. |
| 2026-04-27 | `wf run STORY-XXXX <name>` remained deferred. | Still current. Workstream naming is not restored through that positional form. |
| 2026-04-27 | `wf project config set` rejects dead keys. | Still current. Raw unknown key persistence is not parity. |
| 2026-04-27 | Former pseudo-enum values fail Huma validation. | Still current. Invalid enum-like API inputs should fail at the boundary. |

Dropped from the old ledger:

| Old entry | Reason |
| --- | --- |
| `detect_*` events not registered in Go typed dispatch | Resolved. `detect_started` and `detect_completed` are registered in `server/internal/zmqpub/decode.go`, emitted by `server/internal/zmqpub/emit.go`, and covered by detect fixture tests. |

## What's Left To Migrate

Ranked by a combination of LOC impact and architectural value:

1. **Runner lifecycle and stage metadata**
   - Python modules: `orchestrator/workflow/deployable_flow.py`, `orchestrator/workflow/engine.py`, `orchestrator/runner/context.py`, `orchestrator/runner/locking.py`, and `orchestrator/runner/stages.py`.
   - Why it matters: this is where Python still writes runner stage/status metadata and controls the main orchestration loop.
   - Blocking removal: Prefect integration, cooperative shutdown, run logs, workstream locks, and direct runner metadata writes need a single Go-owned replacement or a thinner Python worker contract.
   - Go-side path: move durable runner state transitions behind server endpoints first, then shrink the Python loop to process orchestration only.

2. **Merge gate and merge flows**
   - Python modules: `orchestrator/workflow/merge_gate.py`, `orchestrator/workflow/merge/*`, and `orchestrator/workflow/merge/pre_validate.py`.
   - Why it matters: this is high-value release/merge safety code with local git, test, forge, and notification side effects.
   - Blocking removal: it mixes project config policy, git worktree operations, forge PR/merge behavior, notifications, and failure recovery.
   - Go-side path: migrate policy and status/event writes behind Go first, then port one merge mode at a time.

3. **Planning and story application**
   - Python modules: `orchestrator/pm/planner.py`, `orchestrator/pm/stories.py`, `orchestrator/workflow/planning_flow.py`, and `orchestrator/workflow/edit_flow.py`.
   - Why it matters: large footprint and still central to story creation/editing.
   - Blocking removal: agent protocols, REQS annotation, clarification creation, story mutation semantics, and operator-facing drafts are still coupled.
   - Go-side path: keep Go as the state/FSM owner, then move planner output application behind server mutations before moving agent invocation.

4. **Config/client compatibility shims**
   - Python modules: `orchestrator/lib/config.py`, `orchestrator/lib/server_client.py`, and related generated OpenAPI consumers.
   - Why it matters: large LOC, but much of it is boundary glue rather than independent business logic.
   - Blocking removal: Python flows above still need config/profile data and server calls.
   - Go-side path: delete compatibility branches as their callers move, rather than porting the shim wholesale.

5. **Final-review Prefect wrapper and Go stage bridge**
   - Python modules that remain: `orchestrator/workflow/review.py` as the 74-line Prefect-flow-compatible wrapper and the `run_review_stage_via_go` bridge plus timeout/error envelope helpers in `orchestrator/pm/agent_utils.py`.
   - Why it matters: final-review execution is already Go-owned at `server/internal/stages/review/`, so the remaining Python is glue that survives until the surrounding Prefect flow moves.
   - Blocking removal: Prefect still calls the Python wrapper, and the wrapper still shells out through `wf internal stage-review` to preserve the current flow contract.
   - Go-side state: `server/internal/stages/review/final_review.go` plus `acknowledged_concerns.go`, `context.go`, `deletion_evidence.go`, `invoke.go`, `loader.go`, `persist.go`, `prompt.go`, `retry.go`, and `verifier.go` are the live implementation.

## Vestigial Candidates

Do not delete these from this PR; they are candidates for follow-up briefs.

| Candidate | Evidence | Suggested next step |
| --- | --- | --- |
| `orchestrator/services/__init__.py` | The package is one docstring line, and no importers of `orchestrator.services` were found. | Delete after a focused import/static check. |
| Empty namespace `__init__.py` files | Several packages contain zero-byte `__init__.py` files. | Treat as packaging scaffolding, not automatic deletion targets. |
