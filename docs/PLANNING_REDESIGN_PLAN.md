# Planning + Question Lifecycle Redesign Plan

**Status:** Implementation plan. Burn after implementation lands.

## Architecture (already in WF.md)

Two question lifecycles, one storage table.

**Story-planning:** bundle UX. Planner emits all open questions at once. Operator answers as bundle. Edit-flow auto-dispatches for story redraft only; this is separate from workstream-runtime, which remains manual resume via `wf run <ws>`. Old answered CLQs preserved as historical context for next planner run.

**Workstream-runtime:** per-question UX with multi-emit support. Implement-stage agent can emit 1+ CLQs in one turn. Operator answers each individually. When the blocking CLQs are answered, the workstream becomes resumable and the operator manually continues it with `wf run <ws>`.

Discriminator: `clarifications.story_id` set vs `clarifications.workstream_id` set.

## Planning flow redesign (F-059/F-060)

**Single AI call** for planning. Planner output:
```json
{
  "story": { ... },
  "reqs_annotations": [
    {"start_anchor": "unique phrase from REQS", "end_anchor": "unique phrase from REQS"},
    ...
  ],
  "open_questions": ["question 1", "question 2"],
  "error": null  // or refusal message
}
```

**Anchor format:** phrases from REQS that each appear exactly once in the file.
Prompt guidance still asks for longer phrases when natural boundaries support
them, but validation enforces uniqueness rather than word count.

**Pre-apply validation phase:**
1. Schema check (annotation count)
2. Anchor uniqueness (each appears exactly once in REQS)
3. Anchor ordering (end appears after start)
4. Inter-annotation overlap detection
5. Existing-WIP overlap (no overlap with OTHER stories' markers)

**Retry loop:** up to 3x with feedback to planner on transient validation failures. Operator-visible: "drafting — retry 2/3" status display. Per-attempt logs preserved.

**Refusal handling:** planner can refuse to draft (e.g., overlap with existing other-story WIP that can't be worked around). Story → draft_failed with refusal message. No retries on refusal.

**WIP marker handling on redraft:** disk REQS is canonical. Planner sees REQS as-is with all current markers. Prompt instructs:

> "WIP markers tagged `<!-- BEGIN WIP: STORY-XXXX -->` matching this story's ID are YOUR previous decisions. Confirm them, change them, or remove them in your new output. Markers with OTHER story IDs cannot be overlapped."

**Apply phase (deterministic, after validation passes):**
```
current_marked = parse_wip_regions(disk_reqs, story_id=this_story_id)
new_set = planner_output.reqs_annotations

to_unmark = current_marked - new_set
to_mark = new_set - current_marked

new_reqs_content = disk_reqs
for region in to_unmark:
    new_reqs_content = remove_markers(new_reqs_content, region, this_story_id)
for region in to_mark:
    new_reqs_content = add_markers(new_reqs_content, region, this_story_id)

write(new_reqs_content)
git_add + git_commit + git_push
```

Idempotent. If planner emits the same set as currently marked, both diffs are empty, no-op.

**Ordering:** REQS write (file + git) FIRST, then story DB commit. If REQS write fails, story never committed (clean rollback). If DB commit fails (rare), orphan REQS markers — recoverable via git revert.

**Multi-repo:** primary REQS only. Annotation always against project-root REQS.md.

**Failure modes (all hard-fail with Diagnostic, story → draft_failed):**

| Condition | Source tag |
|---|---|
| Planner refusal | `stage.planning.refusal` |
| Schema invalid output | `stage.planning.annotate.schema` |
| Anchor uniqueness failure | `stage.planning.annotate.uniqueness` |
| Anchor not found | `stage.planning.annotate.not_found` |
| Anchor sequence violation | `stage.planning.annotate.sequence` |
| Inter-annotation overlap | `stage.planning.annotate.self_overlap` |
| Other-story WIP overlap | `stage.planning.annotate.cross_overlap` |
| REQS missing for non-ad-hoc | `stage.planning.reqs_missing` |
| Apply phase failure | `stage.planning.apply` |

**Ad-hoc stories:** annotations optional (empty array OK). Non-ad-hoc stories: annotations required (validation enforces).

## Question lifecycle implementation

**Storage:** unified `clarifications` table. Discriminator on row: `story_id` set (story-planning) vs `workstream_id` set (workstream-runtime).

**Story-planning operational behavior:**

- TUI 'a' key on story_detail: reads pending CLQs filtered by `story_id` set + `workstream_id` null + `status=pending`. Presents as bundled modal: "Q1: ..., Q2: ..., Q3: ...".
- Operator submits bundled answer string.
- Server endpoint flips ALL pending story-CLQs to `answered` with the same bundled answer text.
- Server dispatches edit-flow with the bundle as feedback (existing edit-flow path).
- Edit-flow's planner re-runs. Old answered CLQs visible as historical context. Planner may emit new questions.
- New questions → new CLQ rows (replace operationally).

**Workstream-runtime operational behavior:**

- Implement-stage agent protocol widened: `clarifications_needed: [{...}, {...}]` (list, not single).
- Runner loops to create N CLQ rows on `StageBlocked`.
- TUI 'c' key on workstream_detail: reads pending CLQs filtered by `workstream_id` set + `status=pending`. Per-question modal.
- Operator answers each CLQ individually via the per-CLQ answer endpoint.
- Each answer flips that CLQ's status independently.
- **No automatic resume.** Operator must manually run `wf run <ws>` to resume the workstream. Implement-stage prompt context picks up all answered workstream CLQs (filtered by `workstream_id`) on the next run.

**Light versioning (story-planning only):**

- New `clq_round` int column on `stories` table. Increments on each redraft.
- CLQs created in round N tagged with the story's clq_round at creation time (or just inferred — if all CLQs for a story were created during round N, they're round-N CLQs).
- Answer submission body includes `clq_round`. Server checks against current. Mismatch → 409 "your answer is from round N; story is now in round N+1; refresh."
- TUI / CLI fetch the round when displaying CLQs and echo it on submit.

**Answer endpoint locking (story-planning):**

- POST `/clarifications/{id}/answer`: if story is in `drafting` status, return 409 "story is currently re-drafting; wait for completion." No answer recorded.

## Pre-Go behaviors that MUST be preserved

The current Python implementation (which has been load-bearing through hundreds of stories) does several things the redesign must keep. Verified by reading `orchestrator/workflow/planning_flow.py`, `orchestrator/pm/reqs_annotate.py`, `orchestrator/workflow/edit_flow.py`.

**Distributed workflow safety:**
- **Pre-annotate `git pull --rebase`** on the REQS repo before any annotation work. Reduces conflict risk when other operators have updated REQS in parallel.
- **Idempotency check** after apply (`git status --porcelain reqs_file`). If REQS didn't actually change, skip the commit.
- **Push retry with conflict detection** (`_sync_main_and_push`). Retries on remote conflicts via rebase + push. Detects OVERLAP_CONFLICT_MARKER at push time (someone else committed an overlapping marker between our planner read and our push) → triggers retry-with-feedback (not the existing retroactive-delete).

**Suggestion lifecycle:**
- `transition_suggestion(... CLAIMED ...)` on planning entry — atomic claim. Prevents two flows refining the same suggestion.
- `revert_suggestion(...)` on every failure path. Preserves work for retry.
- `transition_suggestion(... DONE ...)` after story successfully drafted.

**Story FSM transitions:**
- `queued → drafting` on planning slot acquisition
- `drafting → draft` on success (after apply succeeds)
- `* → draft_failed` on any failure path
- Safety-net finally block: if story still in `queued` or `drafting` after flow exit, force-transition to `draft_failed`. Prevents stuck stories.

**Logging and observability (per `docs/ARCHITECTURE.md` "Logging And Transcripts"):**
- Per-attempt log file: `<run_dir>/stages/planning_attempt_N.log` for each AI call (initial + retries). Streaming via D's #466 codex hygiene work — already wired.
- Per-attempt transcript record: each retry records to story transcript with attempt number, failure reason, feedback given to planner. Replayable decisions.
- Apply-phase audit log: record what regions were marked/unmarked in the diff. Operator can debug planner's decisions.
- `planning_retry` notification event with attempt count → ZMQ → TUI shows "drafting — retry 2/3".
- All existing notification events preserved: `notify_planning_complete`, `notify_planning_failed`, `notify_suggestion_reverted`.
- All `log_system_error(...)` calls preserved with `service=SERVICE_WORKFLOW`, `stage="planning"`, story/project metadata.
- Final operator-visible failure message (Diagnostic) includes a path to all attempt logs for easy drilldown.

**Edit-flow gets the same treatment:**
- Edit-flow (`orchestrator/workflow/edit_flow.py`) shares the planning shape and is the primary redraft path. It must use the same single-AI-call structure, validation phase, retry loop, atomic apply, and lifecycle preservation as planning_flow.
- **Edit-flow currently doesn't promote new open_questions to CLQs** (planning_flow does post-#467). The redesign closes this gap on the edit path — F-055's reach extends to edit_flow.

## Implementation work breakdown

| PR | Scope | Sequencing |
|---|---|---|
| **A. Planning redesign (F-059/F-060)** | Single AI call, anchor-based annotations, validation phase, retry loop, atomic apply, diff-reconcile WIP markers, refusal handling | Independent. Can dispatch first. |
| **B. Implement protocol multi-emit** | Widen `clarification_needed` → `clarifications_needed: [...]`; runner loops to create N CLQs. **No auto-resume** — operator manually runs `wf run` after answering. | Independent. Can dispatch in parallel with A. |
| **C. Story-planning bundle path through CLQ table + light versioning + implement story-CLQ load** | TUI 'a' reads from CLQs filtered by story_id; `wf answer STORY-X` flips all pending story-CLQs + dispatches edit-flow; M015 schema adds `clq_round` to stories; answer endpoint enforces round + drafting-status lock; **implement-stage prompt context loads story-scoped CLQs (via workstream's linked story_id), not just workstream-scoped — closes the orphan-answer gap where story open questions were silently dropped from implementation context.** | Depends on A landing for planner-side schema. |
| **D. WIP cleanup on close (F-061)** | Remove a story's WIP markers from REQS when story transitions to merged/closed/abandoned. Same diff-reconcile machinery as A. | Lowest priority. Independent. |
| **E. CLI help text alignment** | Legacy clarification-command Long text says workstream-runtime; `wf answer` Long text frames the bundle/per-question split. Any operator-facing wording change to commands, subcommands, flags, or related public API naming needs explicit product/operator sign-off before it is finalized. | Tiny. Fold into A or B. |

## Dispatch sequence

**Slot 1 (immediate):** PR A — planning redesign. Foundational. Largest scope. Best agent: D (server-side + multi-repo context from #449/#451/#457/#466) or A (just shipped #471 capabilities work).

**Slot 2 (parallel):** PR B — implement protocol multi-emit + manual resume after answers. Different code surface. Best agent: B (just delivered #475 workflow-control regressions, has the implement-side context).

**Slot 3 (after A lands):** PR C — bundle-via-CLQs + versioning. Reshape of in-flight F-055 work. Best agent: whoever owns that PR currently.

**Slot 4 (lowest priority):** PR D — WIP cleanup on close. Whoever's free.

**Slot 5 (fold in):** PR E — CLI help text. Tiny additive.

## T unblock path (parallel to redesign)

T is parked at clarifications gate on STORY-0003. T is blocked on **operator providing answers**, not on the redesign work.

The actually-working today path (per CR review of the doc):

1. Operator answers via `wf answer STORY-0003 "Q1: ..., Q2: ..., Q3: ..."` — bundle answer, single submission.
2. This dispatches the edit-flow with the answers as feedback.
3. Edit-flow's planner re-runs, refines the story with answers as context, story moves to `draft` (refined).
4. Operator approves the refined story (`wf approve STORY-0003`) and dispatches the workstream (`wf run STORY-0003`).
5. Implement-stage runs against the refined story content.

**Why NOT the legacy per-CLQ answer command per question:** today's implement-stage prompt context only loads CLQs filtered by `workstream_id`, not by story_id. Story-scoped CLQ answers are silently dropped from the implement context. The `wf answer STORY-X` bundle path goes through edit-flow which refines the story content with the answer as feedback — that's how the answer reaches the implement-stage agent (indirectly, via the refined story).

PR C closes this gap on both surfaces: per-CLQ answer flips also flow through to edit-flow (so the legacy per-CLQ command becomes operationally equivalent to the bundle path), AND implement-stage prompt loads story-scoped CLQs directly.

## Open decisions

1. **Implement protocol breaking change.** New protocol is `clarifications_needed: [...]` (list). Backward compatibility for one release? Or hard cut? Recommendation: hard cut — prompts are versioned with the codebase.

2. **Manual-resume clarity.** Workstream does not auto-continue when the last blocking CLQ is answered. The operator explicitly resumes it with `wf run <ws>`. Surface that clearly in operator-facing events/help so answered CLQs do not look like a dead-end.

3. **Story-CLQ versioning rollout.** New `clq_round` int — schema migration M015. Bundle into PR C (same surface).

4. **F-040 / F-054 / F-055 reconciliation.** F-040 promote-to-CLQ work was correct direction (single table). F-054 backfill was correct. F-055 in-flight needs scope reshape per PR C above. No revert needed.

## What's already documented

- WF.md Phase 1 "Questions and Answers" section: lifecycles, storage, operational distinction
- WF.md "Question & Answer Commands" section: command surface

## Burn this doc

Once PRs A through E land, delete this file. Architecture lives in WF.md; CLI surface in --help text; this doc is the implementation plan and has no long-term value.
