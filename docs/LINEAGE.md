# Code Lineage

## Problem

When AI agents write code, the traditional `git blame` answer -- "who changed this line and when" -- is insufficient. The real question becomes: **what requirement motivated this line, what prompt produced it, what model generated it, what review approved it, and what human decisions shaped it?**

Every line of AI-generated code in a hashd-managed project should be traceable back through the full chain:

```
line of code
  -> git commit (SHA)
    -> microcommit (COMMIT-FOO-001)
      -> run (implement/test/review cycle)
        -> prompt (template + variables + rendered text)
          -> agent invocation (model, tokens, duration)
            -> workstream (branch, worktree)
              -> story (STORY-XXXX, acceptance criteria)
                -> PRD requirement (REQS.md section)
                  -> human decisions (approvals, rejections, clarifications)
```

This is not theoretical. Enterprises adopting AI code generation face concrete pressure:

- **EU AI Act (Article 50, effective August 2026)**: Providers of AI systems generating synthetic content must mark outputs in a machine-readable format as AI-generated. The first draft Code of Practice (December 2025) explicitly calls out AI-generated software code as requiring special treatment. The technical approach for code is still being defined (second draft expected mid-March 2026), but the obligation is coming.
- **EU AI Act (Article 12)**: High-risk AI systems must maintain logs sufficient to trace operation back to inputs. Code generation for safety-critical systems qualifies.
- **SOC 2 / ISO 27001**: Audit trails must demonstrate who authorized what change and why.
- **CISA SBOM 2025**: Updated minimum elements now require "generation context" -- how a component was produced, not just what it is. Directly relevant to AI-generated code.
- **License compliance**: AI-generated code may reproduce copyrighted snippets. Provenance proves the generation context.
- **Liability**: When AI-generated code causes a production incident, the organization needs to reconstruct the decision chain -- not just the diff.

## Landscape

### Entire.io (primary competitor)

Founded by former GitHub CEO Thomas Dohmke. $60M seed at $300M valuation (Feb 2026). Building a three-layer platform:

1. **Checkpoints CLI** (shipped, open source): Git hooks that capture AI agent sessions alongside commits. Stores session transcripts on a dedicated `entire/checkpoints/v1` branch. Adds an `Entire-Checkpoint: <12-char-hex>` trailer to commit messages. Supports Claude Code, Gemini CLI, OpenCode, Cursor.

2. **Web dashboard** (shipped): Browse checkpoints per repo/branch. Session cards show duration, conversation steps, tool invocations, token count, and human-vs-AI attribution percentage. Line-level attribution showing which agent wrote which lines. Side-by-side diffs with checkpoint-level change attribution.

3. **Git-compatible database** (roadmap): A new storage layer that unifies code, intent, constraints, and reasoning in a single version-controlled system. A "semantic reasoning layer" for multi-agent coordination via a "context graph."

**What Entire captures per checkpoint:**
- Complete agent transcript (prompts + responses)
- Files modified with diffs
- Timestamps and duration
- Agent identity (which tool, which model)
- Token consumption
- Optional AI-generated summaries (intent, outcome, learnings, friction, open items)
- Nested sub-agent sessions (parent-child hierarchy)

**What Entire does NOT capture:**
- Requirements/story linkage (no concept of stories or requirements)
- Review decisions (no built-in code review)
- Human approval/rejection history
- Confidence scoring
- Microcommit planning or breakdown context
- Clarification history
- Cross-workstream conflict awareness

**Key architectural decision:** Entire stores session data on a separate git branch (`entire/checkpoints/v1`), not in the main history. Read-only GitHub App integration -- never writes to repos.

### Atomic Software

AI-native version control startup building a Git alternative. Stores AI provenance as first-class change records rather than bolt-on metadata. Addresses the "hourglass effect" where AI collapses code writing to near-instant but validation becomes the bottleneck. Early stage, less public detail than Entire.

### Archipelo

Code Provenance Engine + DevSPM (Developer Security Posture Management) platform. Tracks all actors, artifacts, metadata, and events across the SDLC. AI Code Monitor detects AI-generated code. Partnership with Checkmarx for AppSec integration. Different positioning from Entire -- focused on security posture and compliance rather than developer experience.

### git-ai (open standard)

The most technically complete open standard for line-level AI attribution in source code. MIT-licensed Git extension that stores attribution data in Git Notes (`refs/notes/ai`).

**Key design properties:**
- Line-level granularity: maps file + line ranges to session hashes
- Session hash = SHA-256 of `{tool}:{conversation_id}`, first 16 hex chars
- Metadata per session: agent_id (tool, model), human_author, full message transcript, additions/deletions/accepted/overridden line counts
- Survives rebase, squash, cherry-pick, merge, amend
- Transcript storage: local, cloud, or self-hosted (privacy control)
- Supports: Cursor, Claude Code, Codex, Copilot, Gemini CLI, OpenCode, Continue, Droid, Junie, Rovo Dev

**What git-ai does NOT do:** No requirements linkage, no review decisions, no human approval chain, no pipeline orchestration. Purely an attribution layer.

**Relevance to hashd:** The git-ai schema (v3.0.0) is a good reference for line-level attribution if we ever need it. However, hashd's microcommit model provides a natural attribution boundary -- every line in a microcommit is agent-generated by definition. git-ai solves a harder problem (mixed human/AI edits in a single commit) that hashd's architecture avoids.

### Threatrix (AICertify)

Different angle: detects AI-generated code snippets after the fact for license compliance. 99% accuracy claim across 420 languages. Generates SBOMs (CycloneDX, SPDX). IDE plugin for real-time alerts. Complementary to lineage -- they detect provenance gaps; we prevent them.

### Standards and frameworks

| Standard | Relevance |
|----------|-----------|
| **SLSA v1.0** | Build provenance levels. L1: provenance exists. L2: hosted build + signed provenance. L3: hardened builds. Defines `buildDefinition`, `runDetails`, `externalParameters`. hashd already meets L1 concepts (provenance exists in events table), could formalize to L2. SLSA answers "was this binary built from this source?" -- it does NOT answer "was this source written by AI?" We need provenance going *backward* from code to agent/prompt. |
| **in-toto** | Attestation framework. Statement + Predicate model. SLSA provenance is an in-toto predicate type. Fixed envelope format with pluggable predicates -- we can define a `https://hashd.ai/provenance/v1` predicate type for AI code lineage without inventing a new envelope. |
| **Sigstore / Cosign** | Keyless signing via OIDC identity (GitHub/Google). Fulcio for ephemeral certificates, Rekor for transparency log. Could sign lineage attestations without key management. Gitsign enables keyless commit signing. Open proposal (sigstore/gitsign#105) for AI provenance predicate type. |
| **C2PA** | Content provenance standard (images, video, audio). C2PA v2.3 spec has no source code media type or code-specific assertions. Source files have no standard metadata container (unlike JUMBF in images). The EU draft Code of Practice acknowledges code needs special treatment but offers no solution yet. Monitor but do not adopt. |
| **CycloneDX ML-BOM** | CycloneDX v1.5+ includes ML-BOM for documenting model identity, training datasets, methodology. Could document which models generated code. OWASP AIBOM project doing gap analysis. CycloneDX is now Ecma International ECMA-424 (Dec 2025). |
| **SBOM (CISA 2025)** | Updated minimum elements add component hash, license, tool name, and **generation context**. The "generation context" field is where AI provenance metadata belongs. |
| **EU AI Act** | Article 50 (effective August 2026): machine-readable marking of AI-generated content required. Article 12: logging for high-risk systems. First draft Code of Practice (Dec 2025) explicitly flags AI-generated code as needing technical solutions. No standard exists yet -- first mover advantage. |

## hashd advantage

hashd has a structural advantage over Entire and every other system in this space: **we control the entire pipeline, not just the capture layer.**

Entire hooks into the commit event and records what happened in the agent session. They capture the transcript but lack upstream context (why was the agent invoked?) and downstream context (what did the reviewer think? did a human approve it?).

hashd orchestrates the full lifecycle. We don't need to infer the chain -- we *define* it:

| Lineage link | Entire | hashd |
|--------------|--------|-------|
| Requirement -> Story | N/A | `stories.source` -> REQS.md section |
| Story -> Workstream | N/A | `workstreams.story_id` |
| Workstream -> Plan/Breakdown | N/A | `workstreams.plan` (microcommit list) |
| Plan -> Prompt | N/A | `events` table (prompt template + rendered text) |
| Prompt -> Agent call | Transcript capture | `agent_calls` + `events` (model, tokens, duration) |
| Agent call -> Commit | Checkpoint trailer | `commits.sha` -> `commits.run_id` |
| Commit -> Review | N/A | `reviews` (decision, confidence, blockers) |
| Review -> Human decision | N/A | `events` (human_input, approval/rejection + reason) |
| Clarification history | N/A | `clarifications` (CLQ-xxx, question + answer) |
| Cross-commit patterns | N/A | Final review spans all commits |

Entire is a **telescope** -- it shows you what happened in a session. hashd is the **laboratory notebook** -- it records the hypothesis, the experiment, the results, the peer review, and the PI's sign-off.

## Current state

### What exists

The `commits` table schema is defined (`db.py:49-58`):

```sql
CREATE TABLE IF NOT EXISTS commits (
    sha TEXT PRIMARY KEY,
    project TEXT NOT NULL,
    workstream_id TEXT NOT NULL,
    story_id TEXT,
    microcommit_id TEXT,
    run_id TEXT,
    message TEXT,
    created_at TEXT NOT NULL
);
```

Indexes exist for project, workstream, and story lookups.

Supporting infrastructure that already records lineage data:

| Component | Location | What it captures |
|-----------|----------|-----------------|
| `events` table | `db.py:142` | Every prompt, response, stage start/end, human decision. Tagged with project, story_id, workstream_id, run_id, microcommit_id, stage, actor; `microcommit_id` is set only by writers that name one -- `stage_changed` start/stop and `agent_retry` rows from the shared agent launcher carry the launch's microcommit ID when one was supplied and NULL otherwise, and `agent_killed` rows carry none. |
| `agent_calls` table | `db.py:30` | Per-invocation: agent, stage, model, elapsed_seconds, input/output tokens. Tagged with run_id, workstream_id, story_id, microcommit_id. |
| `reviews` table | `db.py:178` | Review decisions: type, decision, confidence, blocker_count. Tagged with run_id, workstream_id, story_id, microcommit_id. |
| `runs` table | `db.py` | Run lifecycle: started_at, ended_at, stages, failed_stage, commit_sha. |
| `stories` table | `db.py:63` | Story content, acceptance criteria, status, source_suggestion_id. |
| `Transcript` | `stages/transcript.py:29` | Run-level audit: prompt text, response text, stage markers, human input. |
| `StoryTranscript` | `lib/story_transcript.py` | Story-level events rendered to markdown. |
| `commits` table | `db.py:49` | Every runner commit: SHA, project, workstream, story, microcommit, run, message. Populated by `save_commit()`. |
| Commit messages | `stages.py` | Format: `COMMIT-FOO-001: description` |
| `render_prompt()` | `lib/prompts.py:112` | Renders templates with variable interpolation. Template name tracked in `events.data` metadata. |

### What is done

1. **Commits table populated (Phase 1).** `save_commit()` in `db.py`, called from `stage_commit()` in `stages.py`. Every runner-created commit now gets a row.

2. **Prompt template name captured (Phase 1).** `prompt_template` recorded in `events.data` metadata via `record_agent_call()`. Tracks `breakdown`, `implement`, `implement_retry`, `review`, `review_retry`, and `review_format_retry`.

3. **Requirement text captured in stories (Phase 2).** `source_refs` field repurposed to hold closely paraphrased requirement text from REQS.md. `origin` field added to tag how each story was created (`"discovery"`, `"manual"`, `"bug"`).

4. **Lineage query commands (Phase 3).** `hashd lineage` command with auto-detection of target type (file, SHA, story/bug ID). Three query paths: file blame -> commit lookup -> story enrichment; commit -> story + reviews + human decisions; story -> all commits + reviews + decisions. Output formats: `--format table|json|markdown`. Human rejection of final reviews recorded as queryable `human_input` events.

### What is missing

1. **No export format.** No way to export lineage as SLSA provenance, in-toto attestation, or any standard format.

2. **No signing.** Lineage records are stored in SQLite but not cryptographically signed or tamper-evident.

## Design

### Phase 1: Wire up the commits table + prompt template tracking -- DONE

**Goal:** Every git commit made by the runner gets a row in `commits`. Prompt template names recorded in events.

**Implemented:**

- `save_commit()` in `db.py` (follows `save_run()` pattern: `project_dir` first, keyword-only params, `INSERT OR IGNORE`, returns `bool`).
- Called from `stage_commit()` in `stages.py` after transcript record, before dirty-files check. All values from `RunContext`.
- `prompt_template` optional parameter added to `Transcript.record_agent_call()`. Flows through `**kwargs` into `events.data` JSON as `{"metadata":{"prompt_template":"implement"}}`.
- Five call sites tagged: `breakdown`, `implement`/`implement_retry` (tracked via `prompt_name` variable), `review`/`review_retry` (same pattern), `review_format_retry`.

**Verification queries:**

```sql
-- Commits table
SELECT sha, workstream_id, microcommit_id, message FROM commits ORDER BY created_at DESC LIMIT 5;

-- Prompt template tracking
SELECT event_type, json_extract(data, '$.metadata.prompt_template') as tpl
FROM events WHERE json_extract(data, '$.metadata.prompt_template') IS NOT NULL
ORDER BY id DESC LIMIT 10;
```

### Phase 2: Requirement-to-story linkage -- DONE

**Goal:** Each story records the requirement text it fulfills, readable standalone without REQS.md.

**Implemented:** Repurposed the existing `source_refs` field on stories. Updated the `refine_story.md` and `edit_story.md` prompts to instruct Claude to closely paraphrase the original REQS.md text rather than cite section numbers. No schema change needed -- `source_refs` already exists.

- `source_refs`: prompts updated (`refine_story.md`, `edit_story.md`) to paraphrase requirement text instead of citing section numbers. Display labels renamed to "Source Requirements".
- `origin` field added to Story model: `"discovery"` (from REQS.md via `hashd plan`), `"manual"` (`hashd plan story`), `"bug"` (`hashd plan bug`), `""` (legacy). Set automatically in `create_drafting_placeholder()`.

**Design rationale:** REQS.md is a living document -- lines get deleted as stories consume them. Section references become meaningless. Paraphrasing the requirement text creates a frozen, readable record. The `reqs_refs` field on suggestions (discovery phase) still uses section references, which is fine since REQS.md exists at discovery time.

**Verbatim capture at burn-down (`requirement_burned` event):** `source_refs` is the story's *reading* of the requirement (a paraphrase), not the original wording. When a story's WIP block is removed from REQS.md -- by the merge archive, the WIP sweep backstop, or the planning-apply reconcile -- the server records a durable `requirement_burned` event in the `events` table holding the **verbatim** requirement text, the configured `reqs_path`, the consuming `story_id` and the completion timestamp. The text is the record. A Git source locator (`reqs_git_ref` commit id, `reqs_git_repo` repository root, `reqs_git_path` repository-relative path) is attached only when reading that path at that commit in that repository, through the same WIP extraction, gave exactly the recorded text when the event was written; only the current HEAD of the repository that owns REQS is checked. A missing locator means the source could not be proven at record time (for example, the deletion was already committed), not necessarily that REQS was untracked. hashd does not retain or recover the pre-burn REQS source, so `git show <reqs_git_ref>:<reqs_git_path>` in `reqs_git_repo` works only while that commit is still reachable there. This closes the gap between the paraphrase and the exact original, and makes "completed requirements, by story, in chronological order" a query over those events. Recorded server-side in `server/internal/reqs/requirement_burned.go` (`reqs.RecordRequirementBurned`).

### Phase 3: Lineage query commands -- DONE

**Goal:** Walk the chain in either direction from any point.

**Implemented:**

- `cmd_lineage()` in `commands/lineage.py` with auto-detect: `STORY-`/`BUG-` prefix -> story, 7-40 hex chars -> SHA (with file-exists fallback for ambiguous names), otherwise -> file path.
- Three query functions in `db.py`: `get_commit_row()`, `list_commits_by_story()`, `list_commits_by_workstream()`.
- `git_blame()` helper in `git/branch.py` using `--porcelain` format for machine parsing.
- Commit-level human decisions scoped by `microcommit_id` (not entire workstream).
- Story-level queries show all human decisions for the workstream (correct -- they all relate to the story).
- Human rejection of final reviews now recorded as `human_input` events in the events table (previously only in story transcript), matching the in-pipeline `record_human_input()` format. Added in `approve.py:_reject_post_completion()`.
- Output formats: `--format table` (default), `--format json`, `--format markdown`.

#### `hashd lineage <file> [--line N] [--lines N-M]`

Trace a file (or specific lines) back to the stories and decisions that produced it.

```
$ hashd lineage src/auth/jwt.go --lines 42-58

Lines 42-58 of src/auth/jwt.go

  SHA       Micro-commit     Story       Review   Origin
  a1b2c3d   COMMIT-AUTH-003  STORY-0012  0.94     discovery
  e4f5g6h   COMMIT-AUTH-005  STORY-0012  0.91     discovery

STORY-0012: JWT Authentication
  Requirement: Users must authenticate via JWT with 30-minute session expiry
  Origin: discovery (from REQS.md)
```

Implementation: `git blame -L N,M <file>` to get SHAs, look up each in `commits`, join to stories/reviews.

Without `--line`/`--lines`: `git log --follow <file>` for all commits touching the file.

#### `hashd lineage <sha>`

Full chain for a single commit.

```
$ hashd lineage a1b2c3d

Commit a1b2c3d: COMMIT-AUTH-003: Implement JWT token validation
  Workstream: auth_jwt
  Story:      STORY-0012 - JWT Authentication (discovery)
  Requirement: Users must authenticate via JWT with 30-minute session expiry
  Run:        run_2026-03-09T10:05:13
  Prompt:     implement (template: implement)
  Review:     pass (confidence: 0.94, 0 blockers)
  Human:      approved
```

Served by `GET /commits/{sha}/lineage` (`server/internal/api/lineage_endpoints.go`, `lineage_intent.go`). Fields:

- `commit`: the commits row.
- `story`: the story row as it reads now, omitted when the story no longer exists.
- `intent`: what the commit's execution was handed when it ran. `state` is `recorded` (every listed capture was read), `unknown` (capture evidence is unavailable: the commit has no `run_id` or `microcommit_id`, no capture names its workstream, run and micro-commit -- work that predates capture, including runs in flight across the upgrade -- or a listed capture was lost) or `failed` (a stored record could not be read). `recorded` is not proof that every invocation was captured: legacy or absent evidence leaves no row, and reads as unknown only where the read can see it is missing. `captures` are the captures of that execution in recorded order, selected by the commit's own run; `planning_captures` are the planning captures they name through `planning_capture_id`. A planning or edit call that resumed a validation-retry session is sent only its retry feedback, so its capture records no story intent, only its saved prompt, with `criteria_empty_reason` saying so; when its output is applied that capture is the one named, not the capture of the fresh call that started the session, and the intent's diagnostic says the planning inputs in force are unknown to this read. Each capture gives its stage, invocation, `captured_at`, planning state, `criteria_empty_reason`, `handed` (the problem, criterion and descoped criterion versions with their `criterion_id`, plan, micro-commit entry, and requirement inputs with their bytes, source and Git repo/ref/path or `no_revision_reason`, each at its link position), `scope` (the criteria identifiers or reason and their versions, exactly as recorded) and `rulings` (each bundle's refs: the row id, the `sha256` the capture recorded, and the referenced clarification, guidance, saved prompt, attachment capture or event row as it reads now). The saved prompt is the record of exactly what the agent received. A saved prompt ref carries its whole stored content, and it and an attachment capture's manifest are checked against the recorded digest over those stored bytes: `verification` is `verified`, or `mismatch`. A clarification, guidance or event ref has `verification` `not_verifiable`: its digest covers the text as the stage rendered it into the prompt (for workstream clarifications that share one human answer, the batch heading, that row's own question and the shared answer), so the row shown is the current source record, not proof of the wording handed.

  An implement capture (`implement` or `implement_fix`: fresh, the fresh fallback, a review-retry session resume or a crash resume) also records who wrote a workstream CLQ answer when its run was dispatched by the general question path of `POST /workstreams/{id}/answer`, and only while that run carries the answer as its feedback: its first cycle. It lists the rows the answer named that the call's Operator Clarifications section rendered, in the answer's order, under `rulings` bundle `workstream_clarifications`. It records the operator's answer, byte for byte as composed at answer time, as one `handed` requirement input with source `operator_instruction`, for the answer as a whole and never split across questions or criteria. The answer is recorded only when every named row is rendered showing exactly those bytes as its answer, or, when the answer named no rows, when the human-guidance section carries them verbatim. The server's framing and question labels are never recorded: the implement agent is not sent them. These read as unknown authorship: a shown answer that differs from what the operator typed (an option number shown as its option text, or an answer replaced after it was given), whose rows are still listed; answered rows rendered again after the run cleared that feedback, in later cycles or runs; runs dispatched before this evidence existed; feedback from any other producer; and review and final-review captures. Guidance the cycle appends to the feedback is never attributed by this evidence.

  A linked version, planning capture or referenced row that no longer exists, a saved prompt whose content cannot be read, and a digest mismatch each mark that item `failed` with a `lineage.intent` diagnostic and fail the intent. A capture that could not be written when its invocation ran is kept as a lost capture (`intent_captures.lost_reason`, written by `intentcapture.RecordLost` beside its `system_error`, with no links): it is listed with state `lost`, its invocation's identity and the reason in its diagnostic, and makes the intent `unknown`; the captures written beside it are still served. When the lost capture cannot be written either, the `system_error` says so. The intent's own diagnostic lists every failed or lost item, the captures whose planning state is `unknown` (their story's applied planner output had no capture evidence), the planning captures that resumed a session, and, when captures exist but the micro-commit entry is omitted, why. Burn events are not listed.
- `microcommit`: the entry the latest implement capture of the commit's run was handed. A resumed session's capture is handed no entry and leaves the entry of a fresh attempt captured earlier in the same run in force. The entry is omitted, with the reason in the intent diagnostic, when the latest implement capture handed one is preceded by a lost implement capture or one with a handed item that could not be read (no earlier entry stands in for either), when the run has no implement capture (its implement work may predate capture), and when every implement capture in the run resumed a session: a capture does not record which session a resume continued, so an entry captured in an earlier run is never selected. Omitted when no capture names the execution.
- `reviews`, `human_decisions`, `agent_calls`: the micro-commit's reviews, `human_input` events and agent calls.

A failed database lookup fails the request with its cause; it never reads as an omitted story or an empty list.

#### `hashd lineage <STORY-XXXX>`

Everything produced by a story.

```
$ hashd lineage STORY-0012

STORY-0012: JWT Authentication
  Origin:      discovery
  Requirement: Users must authenticate via JWT with 30-minute session expiry
  Workstream:  auth_jwt
  Status:      implemented

  Commits (3):
    a1b2c3d  COMMIT-AUTH-003  implement  review: 0.94
    e4f5g6h  COMMIT-AUTH-005  implement  review: 0.91
    f7g8h9i  COMMIT-AUTH-005  implement_retry  review: 0.88

  Files touched (7):
    src/auth/jwt.go, src/auth/middleware.go, src/auth/jwt_test.go, ...

  Reviews (3):
    COMMIT-AUTH-003: pass (0.94), COMMIT-AUTH-005: pass (0.91, 0.88)

  Human decisions (1):
    approved (2026-03-09T10:15:00Z)
```

The story's captured intent history is served on `GET /stories/{id}?include=intent` (`readStoryIntent` in `server/internal/api/lineage_intent.go`), which `hashd lineage <STORY-XXXX>` requests. Without `include=intent` the detail read runs none of the history queries and omits all three fields, meaning not requested; the `GET /stories` list carries none of it. When requested, a list with no records is served as `[]`. Fields:

- `intent_versions`: every `intent_versions` row recorded for the story, in the order they were first recorded (version id order: a version's id is allocated with the capture that first recorded it, so removing that capture, as a workstream removal does, leaves the order unchanged): `kind`, `criterion_id`, the exact bytes (`content`, or `content_base64` when they are not UTF-8) with `content_sha256`, `source`, and Git repo/ref/path or `no_revision_reason`. An edited criterion is a separate version under the same `criterion_id`. Each version lists `captures`, the captures that used it in recorded order: capture id, stage, invocation, workstream, run, micro-commit, `captured_at` and `role` (`handed`, or `scope` for a micro-commit's criteria line). A lost capture links no version, so it is listed under none. The commit read lists a lost capture only when its workstream, run and micro-commit are the commit's; a lost capture of a stage recorded without them (planning, edit, plan split, breakdown) is served by no read.
- `intent_state`: `recorded` when the story has versions, `unknown` when it has none: its stages ran before capture existed or have not run, every capture recorded for it linked no version, or its captures were lost. `recorded` is not proof that every invocation was captured, and a lost capture does not change it.
- `requirement_consumption`: consumption evidence, never intent: the story's `requirement_burned` events, newest first, each with its event id, `created_at` and `payload`. They are written after the requirement text is removed from REQS and are never listed as a version or a requirement input.

A failed history lookup fails the `include=intent` read with its cause; it never reads as an omitted field or empty history, and it cannot fail the default read, which does not run it.

#### Output formats

`--format table` (default): human-readable tables as shown above.
`--format json`: machine-readable, suitable for piping to `jq` or feeding to other tools.
`--format markdown`: for pasting into PRs, docs, or reports.

Table and markdown print every captured-intent text whole. `hashd lineage <sha>` adds an "Intent in force" section: the intent's state (`recorded`, `unknown: no capture for this execution`, or `unknown`/`failed` followed by the served diagnostic, including its cause), the micro-commit entry the server resolved as in force (or `unknown` when it omitted it, with the reason in that diagnostic), then each capture's stage, invocation, handed versions (criterion ids with their text, plan, micro-commit entry, requirement inputs with source and Git repo/ref/path or no-revision reason), scope ids or reason, and ruling bundles by ref id. Any failed or lost item's diagnostic is shown in full. `hashd lineage <STORY-XXXX>` adds "Intent versions" (the state, then every version with its text and the captures that used it) and "Requirement consumption". JSON prints the commit's `intent` as served, and the story's `intent_state`, `intent_versions` and `requirement_consumption`. Story lineage fails, with the cause, when its workstream's reviews or `human_input` events cannot be fetched; file lineage fails when a commit's story cannot be fetched, and shows no story only when the story no longer exists.

### Phase 4: Attestation export (DONE)

**Goal:** Export lineage in standard formats for compliance.

`hashd lineage export <sha> --format slsa`:
- in-toto Statement with SLSA v1.0 provenance predicate
- `buildType`: `https://hashd.ai/provenance/v1`
- `externalParameters`: story_id, microcommit_id, requirement (source_refs), origin
- `internalParameters`: run_id
- `builder.id`: `https://hashd.ai/builder/v1`
- `metadata.invocationId`: run_id

`hashd lineage export <sha> --format in-toto`:
- in-toto Statement with custom hashd predicate (`https://hashd.ai/provenance/v1`)
- Full commit row, story summary, reviews (type/decision/confidence)
- Human decisions, agent calls (model/tokens/duration)
- `chain` section with `prev_hash` and `record_hash` for verifiability

`hashd lineage export STORY-XXXX --format slsa`:
- Exports array of attestations for all commits in the story

### Phase 5: Tamper evidence -- hash chain (DONE)

**Goal:** Make lineage records verifiable via hash chain.

- Each commit record includes `prev_hash`: SHA-256 of the previous record's canonical JSON
- Canonical form: sorted keys, compact separators, all commit fields
- First commit for a project has `prev_hash = None` (genesis)
- `hashd lineage verify` walks the chain, reports total/verified/breaks
- Exit code 0 if chain valid, 1 if broken

Future options (deferred):
- **Sigstore integration:** Keyless signing of attestation exports
- **Transparency log:** Append-only log of lineage events, Rekor-style

## Schema additions

### commits table (existing, populated by Phase 1)

Schema defined in `db.py` (`_SCHEMA`, `commits` table). Populated by `save_commit()` called from `stage_commit()`.
Includes `prev_hash TEXT` for hash chain (Phase 5).

**Retention on removal:** deleting a workstream row (`hashd workstream remove`, `hashd archive delete`, or a story run replacing a closed or merged row under the story's workstream ID) keeps lineage only for successful work: a `merged` workstream whose story is `implemented` (or that has no story). That removal keeps the workstream's `commits` rows, its `intent_captures` and `intent_capture_links`, exactly the `clarifications`, `workstream_guidance` and `transcripts` rows a kept capture link names (a `transcripts` link is the saved prompt an agent invocation was sent), and the `events` rows any capture link names, including a link from another workstream's capture; those events stay out of search, and one kept only for another workstream's link is deleted when that workstream's removal deletes the link; its other events, other transcripts, runs, reviews, agent calls, chat, search entries, PR review findings, merge-gate repairs and code tool calls are still deleted. Any other removal (closed, abandoned, or unfinished work -- `remove` first returns an `implementing` story to `accepted`) is destructive: the commits, the workstream's intent captures and links, and the story's intent versions that no remaining link references are deleted with it, so `GET /commits/{sha}/lineage` answers 404. Deleting a story (only one the same request just created: a planning placeholder whose dispatch failed, or a clone whose suggestion relink failed) deletes its intent captures, links, versions and planning applications. Kept lineage reserves its workstream ID, whether the merged row is still live or already deleted: planning (`reqs.GenerateWorkstreamID`) and story run treat the ID as taken, so another story that would use it claims the next free numbered variant (`<id>_1`, ...) with its own branch, worktree and run, and the response reports that ID. The reserved ID's row, branch and kept records are left alone, so story run only replaces rows whose deletion keeps nothing, a later workstream never reads kept records as its own, and removing it cannot delete them. Enforced by the `workstreams_ad` trigger in `server/contracts/schema.sql`, the `WorkstreamIDReserved` query, and `reqs.DeleteStoryWithIndexTx`.

### stories fields (repurposed/added by Phase 2)

- `source_refs` TEXT: paraphrased requirement text, frozen at refinement time.
- `origin` TEXT: `"discovery"`, `"manual"`, `"bug"`, or `""` (legacy). Stored in story `data` JSON.

### events.data addition (done, Phase 1)

No schema change needed -- `data` is a TEXT column storing JSON. `prompt_template` stored in metadata:

```json
{
  "direction": "in",
  "metadata": { "prompt_template": "implement_retry" }
}
```

## Queries the system must support

These are the questions lineage answers:

1. **"Why does this line of code exist?"**
   `git blame <file>` -> SHA -> `commits` -> story_id -> story -> requirement_refs -> REQS.md

2. **"What prompt produced this commit?"**
   SHA -> `commits.run_id` -> `events` WHERE run_id AND event_type LIKE '%_prompt' -> prompt text + template name

3. **"What did the reviewer say about this code?"**
   SHA -> `commits.microcommit_id` -> `reviews` WHERE microcommit_id -> decision, confidence, concerns

4. **"Did a human approve this?"**
   SHA -> `commits.run_id` -> `events` WHERE event_type = 'human_input' -> approval/rejection + reason

5. **"What model generated this?"**
   SHA -> `commits.run_id` + `commits.microcommit_id` -> `agent_calls` -> model, tokens, duration

6. **"Show me everything related to this story."**
   story_id -> `commits` + `events` + `reviews` + `agent_calls` + `clarifications`

7. **"Which requirements are implemented?"**
   `stories` WHERE requirement_refs IS NOT NULL -> group by requirement_ref -> coverage report

8. **"What changed between these two reviews?"**
   microcommit_id range -> commits + diffs + review decisions -> timeline

## Comparison with Entire.io

| Capability | Entire.io | hashd (after Phase 3) |
|-----------|-----------|----------------------|
| Agent transcript capture | Yes (checkpoint branch) | Yes (events table) |
| Line-level AI attribution | Yes (% human vs AI) | Yes (all lines are agent-generated per microcommit, human edits tracked via separate commits) |
| Commit-to-session link | Yes (trailer) | Yes (commits.run_id) |
| Requirement traceability | No | Yes (story -> requirement_refs -> REQS.md) |
| Review decision history | No | Yes (reviews table, confidence scores) |
| Human approval chain | No | Yes (events: human_input records) |
| Clarification history | No | Yes (clarifications table) |
| Confidence scoring | No | Yes (review confidence 0-100) |
| Cross-workstream awareness | No | Yes (conflict detection, planning) |
| Prompt template tracking | No | Yes (prompt_template in events.data) |
| Multi-agent hierarchy | Yes (nested sessions) | Yes (breakdown -> implement -> review stages) |
| Rewind to checkpoint | Yes (`entire rewind`) | Partial (`git checkout` + run history) |
| Standard export (SLSA) | No | Planned (Phase 4) |
| Tamper evidence | No | Planned (Phase 5) |
| Web dashboard | Yes | Planned (TUI + web) |
| Token cost tracking | Yes (per session) | Yes (agent_calls: input/output tokens) |

## Non-goals

- **Replacing git blame.** Git is the source of truth for "what changed." Lineage answers "why it changed."
- **Real-time line attribution.** Entire shows % human vs AI per line in a web UI. hashd's model is different -- microcommits are atomic agent outputs. Every line in a microcommit was agent-generated by definition. Human edits are separate commits.
- **C2PA metadata.** The standard is designed for media content (images, video). Applying it to source code files is premature. Monitor industry adoption.
- **Building a new VCS.** Entire's roadmap includes a "git-compatible database." We use git as-is and store lineage metadata in SQLite alongside it. This is simpler, more portable, and doesn't require developers to change their tools.
