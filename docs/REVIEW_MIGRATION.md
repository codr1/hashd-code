# Review Migration

Updated: 2026-05-27 against `dev` at `e820ba16`.

This document replaces the old review migration plan and audit. It is the
single source for the current state of the review-stage Python to Go migration.

The TUI, Telegram bot, and connector framework are explicitly out of scope for
this migration document. They consume review state through normal product
surfaces, but their own package migrations are tracked separately.

## Goal

Move the review stage's durable behavior out of Python and into typed Go code:
context loading, prompt rendering, agent invocation, parsing, deterministic
verification, retry policy, persistence, events, and diagnostics. Python should
only remain where it is still the orchestration boundary or a separate product
surface.

## What's Migrated

Per-microcommit stage review is Go-owned in the current production path.

| Area | Current implementation |
| --- | --- |
| Prefect entry | `orchestrator/workflow/tasks.py::task_review` calls `_task_review_go`, not a Python `stage_review` implementation. It maps Go envelopes into `StageError`, `StageInterrupted`, `StageReviewChangesRequested`, or `StageSoftRetry`. |
| Internal command | `server/internal/cli/internal_stage_review.go` exposes hidden `wf internal stage-review`, which reads `StageParams` JSON and returns a JSON envelope. |
| Stage contract | `server/internal/stages/review/params.go` and `result.go` define typed input/output. `StageResult` intentionally omits the legacy `documentation` field from persisted review shape. |
| Context load | `server/internal/stages/review/loader.go` loads workstream, story, microcommit, plan/test/build context, implement notes, review history, project config, and prior concerns. |
| Prompt rendering | `server/internal/stages/review/prompt.go` renders `prompts/review_contextual.md` and verifier retry prompts on the live path. Format-retry prompt support still exists for compatibility/test coverage but is not on the default `runRetryWrappedReview` path. |
| Agent invocation | `server/internal/stages/review/invoke.go` runs through Go `agents.RunStageWithOptions`, including agent command/env resolution, transcript roots, timeouts, token usage, and `agent_calls` output. |
| Parse/schema handling | `server/internal/stages/review/parse.go` extracts JSON, unwraps known agent envelopes, accepts current string/object finding shapes, and rejects malformed/missing review output with Diagnostics. |
| Semantic retry | `server/internal/stages/review/retry.go` owns transient retry, API-rejection classification, soft retry, low-confidence verdict normalization, and verifier redraft loops. |
| Deterministic verifier | `server/internal/stages/review/verifier.go` enforces grounded blockers/required changes, grounded concerns, confidence reasons, identity hygiene, and bounded redrafts. The current bound is `verifierRedraftMaxAttempts = 2`. |
| Persistence/events | `server/internal/stages/review/persist.go` writes `stage_review` rows, stores concern provenance, and records review prompt/response, verifier, retry, and summary transcript events. Format-retry event helpers remain for the compatibility path noted below. |
| Tests | The Go review package now covers parameter validation, context loading, prompt rendering, parsing, retry, verifier behavior, persistence, observability, and internal CLI envelopes. |

The old Python stage implementation (`orchestrator/runner/impl/stages/review.py`)
is gone. The remaining Python review-stage surface is an envelope bridge in
`orchestrator/pm/agent_utils.py` plus the Prefect task wrapper.

## What's Still Python

| Area | Current implementation | Migration meaning |
| --- | --- | --- |
| Prefect run loop | `orchestrator/workflow/engine.py` and `deployable_flow.py` still decide when to enter review and what to do with review outcomes. | This is runner/orchestration migration work, not review-stage business logic. |
| Review bridge | `orchestrator/pm/agent_utils.py` defines `GoReviewStageEnvelope`, `GoReviewStageResult`, timeout Diagnostics, and `run_review_stage_via_go`. | Removable only after the Python runner no longer shells to `wf internal stage-review`. |
| Final branch review | `orchestrator/workflow/review.py::run_final_review` still owns final-review git context, prompt assembly, semantic retries, DB save, transcript event, per-commit concern pooling, and verdict mapping. It invokes Go `wf internal agent-run`, but the stage itself is Python-owned. | This is the highest-leverage remaining review migration target. |
| Final-review prompt context | `orchestrator/runner/impl/prompt_context.py` still contains final-review and review-history formatting used by Python final review. | Port or delete after final review moves. |
| Display/approval consumers | Go CLI review/show/lineage surfaces and package UIs read persisted review data. | Consumer surfaces are not stage migration blockers; TUI and Bot are explicitly out of scope here. |

## Known Intentional Divergences

| Divergence | Current decision |
| --- | --- |
| No `documentation` in stage review persistence | `StageResult` documents this as intentional to preserve the current persisted Python shape. Do not restore it for parity. |
| No first-class `review_completed` event | The durable surfaces are `reviews` rows plus transcript/stage/loop/human-gate events such as `review_summary`. Do not add a synthetic completion event without a new event-contract brief. |
| Stage review and final review are not the same migration unit | Per-microcommit stage review is Go-owned; final branch review is still Python-owned. Treat final review as a follow-up target rather than claiming the review arc is completely gone from Python. |
| Transcript actor labels retain compatibility names | Go stage-review summary tests still expect actor `claude`, and Python final review records actor `CLAUDE`. If selected-agent actor labeling is desired, handle it as a compatibility-changing follow-up. |
| Verifier replaces hallucination-specific parsing | The live Go path uses deterministic grounding and bounded redrafts rather than restoring old ad hoc hallucination handling. |

## Resolved From The Old Plan/Audit

| Old item | Current resolution |
| --- | --- |
| Build a Go scaffold for review | Complete. `server/internal/stages/review` is the live stage package. |
| Keep the old Python stage behind a toggle | Superseded. The Python `stage_review` implementation has been removed. |
| Port context loading | Complete in `loader.go`. |
| Port prompt rendering | Complete in `prompt.go` against `review_contextual`. |
| Port agent invocation/auth/env | Complete through Go agent runner integration. |
| Port parse/schema behavior | Complete in `parse.go` and result types. |
| Port retry behavior | Complete for the live path through semantic retry, transient classification, verifier redrafts, and soft retry. |
| Port persistence/events | Complete for `stage_review` rows and stage-review transcript events. |
| Add deterministic bounded verifier | Complete in `verifier.go`; bounded redrafts are part of the live path. |
| Resolve session-id shape | `StageResult` carries `session_id`; agent invocation fills it from Go transcript/agent output metadata when available. |
| Remove Python stage file | Complete. No `orchestrator/runner/impl/stages/review.py` remains. |

Dropped from the old documents:

| Old content | Reason |
| --- | --- |
| Phase-by-phase PR checklist | Historical; the PR sequence has landed or been superseded. |
| File/line references to deleted Python review stage | Stale after the Go stage became live. |
| Claims that Python shells directly to the review agent for stage review | Stale. Python shells to `wf internal stage-review`; Go owns the agent invocation. |
| Open questions about whether context/prompt/retry/persist should move | Resolved by the current Go implementation. |

## Next Steps

1. **Port final branch review to Go.**
   - Move `orchestrator/workflow/review.py::run_final_review` behind a Go stage or sibling review package path.
   - Reuse existing Go review primitives where they fit: prompt rendering, agent invocation, parsing, verifier, retry classification, persistence, and transcript events.
   - Keep final-review-specific semantics explicit: whole-branch git context, per-commit concern pool, final verdict mapping, and merge-blocking behavior.

2. **Delete the Python review bridge after the runner no longer needs it.**
   - `GoReviewStageEnvelope`, `GoReviewStageResult`, and `run_review_stage_via_go` exist because the Python Prefect task shells to the Go internal command.
   - Once the runner lifecycle is Go-owned or calls a server endpoint instead, this bridge should disappear.

3. **Audit review retry leftovers in Go.**
   - `runFormatRetry` is currently exercised by tests but is not on the default `runRetryWrappedReview` path.
   - `isRetryableReviewFailure`, `isSessionResumeFailure`, and `finalReviewFailure` are compatibility-shaped helpers that should be checked before deletion.
   - This is cleanup, not a blocker for final-review porting.

4. **Decide whether actor labels should track selected agents.**
   - Current persisted transcript actor labels preserve `claude`/`CLAUDE` compatibility.
   - Changing them is observable and should be handled separately from migration cleanup.
