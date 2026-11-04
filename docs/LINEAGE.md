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

Each blamed line gets one of four answers from `GET /commits/{sha}`: an own row prints its message and story; a proven line is marked as reached through a transformation and lists every origin with its message and story (`origins may be missing` when its origins are incomplete); an evidence-only line prints `unproven`; and an unrecorded line stays `(untracked)` in the table and `no` in markdown, which also covers forge-side squash or rebase merges hashd never recorded. Only the lookup's own not-recorded answer (`lineage.commit.not_recorded`) reads as untracked; any other failed commit read fails the command. An own row's or an origin's recorded story that answers 404 is a failed story link with the server's diagnostic, never "no story", and a repository that could not be read prints its diagnostic beside that record. `--format json` rows carry the `resolution`, the own row's `repository` and `story_link`, and the `origins`, each with its own `story_link` (`server/internal/cli/lineage_file.go`).

The server blames at the repo's default branch, what landed, never the checkout's working tree (`GET /lineage/blame`). In a multi-repo project the target names its repo, `hashd lineage <repo>:<path>[:N[-M]]` (the `repo` query parameter on the endpoint), and each blamed SHA is looked up in that repo; a bare path there is refused with the repos whose default branch holds it. A single-repo project keeps the bare path. A squash completion collapses a story's micro-commits into one landed commit, so a squashed line's attribution degrades from the micro-commit that wrote it to its story.

Without `--line`/`--lines`: `git log --follow <file>` for all commits touching the file.

#### `hashd lineage <sha>`

Full chain for a single commit.

```
$ hashd lineage a1b2c3d

Commit: a1b2c3d4e5
------------------
  SHA:         a1b2c3d4e5f6a7b8c9d0a1b2c3d4e5f6a7b8c9d0
  Repository:  (root)
  Revision:    a1b2c3d4e5f6a7b8c9d0a1b2c3d4e5f6a7b8c9d0
  Message:     COMMIT-AUTH-003: Implement JWT token validation
  Created:     2026-03-09T10:21:40Z

Links:
  Workstream: STORY-0012
  Story: STORY-0012
  Run: run_2026-03-09T10:05:13
  Microcommit: COMMIT-AUTH-003
  Reviews: recorded
  Human decisions: recorded
  Agent calls: recorded
  Git object: recorded

Story (as it reads now): STORY-0012 - JWT Authentication
  Source refs (discovery): REQS.md#auth-jwt

Intent in force:
  State: recorded
  Micro-commit entry in force: COMMIT-AUTH-003 - Implement JWT token validation
  ...

Reviews (1):
  [1]  implement  approve  confidence=0.94  2026-03-09 10:20
      Change hash: chg1:sha256:3f9a0c6e1d2b4a5f8e7c9b0a1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e

Human decisions (1):
  2026-03-09 10:30  approved
```

A link that was not recorded or could not be read keeps its line and says
which; a failed one is followed by its error and cause:

```
Links:
  Workstream: not applicable (recorded as intentionally absent)
  Story: failed (could not be read; the error below says why)
    error: The story STORY-0012 of commit a1b2c3d4e5f6a7b8c9d0a1b2c3d4e5f6a7b8c9d0 could not be read
      --> lineage.commit.story

      caused by: database is locked
  Run: not recorded (never recorded for this commit)
```

Table and markdown follow the read's `resolution`. An `own_row` read prints the commit's own record. A `proven` or `unproven` read names the requested SHA and its resolution, and never prints an origin's fields under that Commit header: `proven` says attribution came through a recorded transformation, and `unproven` that only the evidence names it, so no attribution is shown. Every read then prints its recorded transformations whole: the steps back (with the origins-incomplete notice), each origin with its review coverage, its step path (transformation, disposition, the `replayed_resolved` and origins-incomplete notices, and a generated result's recorded attribution, which no origin's reviews cover) and then its own attribution as an own row prints it, its location and links included, so an origin whose git object is gone shows a failed `Git object` link, the steps forward ("Became", `dropped` included), and the evidence. The reviews of the own row and of every origin are numbered from 1 in one index space, in that order, each review once by its ID, as a story read numbers its chains' reviews, so `--details=N` expands the review numbered N wherever it appears and is validated against every review shown. `--format json` prints the response as served, except that the own row's `reviews` and each origin's `attribution.reviews` hold those numbered entries (`server/internal/cli/lineage_commit.go`).

Served by `GET /commits/{sha}/lineage` (`server/internal/api/lineage_endpoints.go`, `lineage_intent.go`). `{sha}` is a recorded SHA or a prefix of 7 or more hex characters, optionally narrowed by the `repo` query parameter to the records of that repository (`commits.repository`, else the repository of the commit intent the record names, as `location` reports it; for one SHA, a record naming the repo in `commits.repository` is preferred over one naming it through its intent). A record written before repositories were recorded names none; its repository is unknown rather than another. For each SHA, the record naming the requested repo answers, and an unnamed one answers only when that SHA has no such record, so one commit recorded before and after repositories were is one commit, and a blamed line keeps its older lineage. A record naming another repo never answers. With no `repo`, a SHA whose records all name one repository is read in that repository the same way, so a direct and an intent-backed record of one commit are one commit. Ambiguity is between distinct commits or repositories: a prefix two of them share is refused. A prefix two recorded commits share is refused (409, `lineage.commit.ambiguous_prefix`) naming each with its resolved repository (or why it has none: never recorded, or its intent missing; an intent that cannot be read fails the read with its cause), and one commit recorded in several repositories is refused (409, `commits.sha.ambiguous`) until the repo is named; neither is ever picked. A SHA hashd did not record answers 404 (`lineage.commit.not_recorded`). `GET /commits/{sha}` resolves the same way, through the same lookup and walker, and serves the commit read (`types.LineageCommitRead`): the resolved `sha`, its `resolution`, its own row's fields and its recorded `location` at the top level only for `own_row`, as the read served them before it followed transformations, `origins_incomplete`, `steps` (every recorded step back, with a generated result's recorded attribution, so a result with no link or no surviving origin row is still served), `origins`, `results` and `evidence`, the lineage read's own, origins with their attribution included (an origin's row is never served as the requested SHA's). An unrecorded SHA keeps the 404 (`lineage.commit.not_recorded`), and a failed read is a 500 Diagnostic. The batched `GET /commits?sha=` read is unchanged.

A SHA with no commits row of its own is followed through the recorded Git transformations (`commit_transformations` and its origin, result, link and evidence tables; `followTransformations` in `server/internal/api/lineage_transformations.go`), reading only the project DB, never git, so an origin whose objects are gone still resolves. When no record matches a prefix, the prefix (lowercased, as every recorded SHA is) resolves against the project's recorded transformation results, and one that matches several is refused with the same 409 (`lineage.commit.ambiguous_prefix`), naming every candidate. The read names the full SHA it resolved to in `sha`, and its `resolution` is one of:

- `own_row`: the SHA has its own commits row. Only this resolution serves the own-row fields below (`commit`, `location`, `story`, `intent`, `microcommit`, `reviews`, `human_decisions`, `agent_calls`, `links`, `present_day`).
- `proven`: a recorded transformation names it: a proven link, a recorded result, or a recorded origin disposition. Its attribution is each origin's, served on that origin, never in the own-row fields.
- `unproven`: only investigative evidence names it. Evidence is never read as a link, so no attribution is served.
- unrecorded: nothing in the project DB names it. The read answers 404 (`lineage.commit.not_recorded`), as it did before it followed transformations.

Every resolution serves the transformation fields, `[]` when there are none:

- `steps`: every recorded step that produced the SHA, or a SHA on the way back to its origins, in walk order. A step gives its `transformation_id`, `repository` (the configured repository name, or `(root)`, never a filesystem path), `operation`, `outcome`, `origin_sha` (absent for a result recorded with no link), `result_sha` (absent for an origin recorded with no link: dropped, or merged_in), and the origin's `disposition`, with `origin_entry`, the origin's position from 0 among its transformation's recorded origins (absent for a step naming no origin, or when the recording order could not be read), and `result_entry`, the result's position from 0 among its transformation's recorded results (absent for a step naming no result, or when the recording order could not be read), so `transformation_id`, `origin_entry`, then `result_entry` is the step's recorded order. A `replayed_unchanged` disposition means hashd replayed the commit with no conflict-resolution changes; it does not claim the patch identity or content is unchanged. `content_differs_from_reviewed` is set on a `replayed_resolved` step: the result's content differs from what the origin's reviews judged. `origins_incomplete` says the result's recorded origin list is incomplete. `generated` is set on a generated result (`generated_intent_id`): that intent's recorded attribution, read from `commit_intents` -- `intent_id`, `workstream_id`, `story_id`, `microcommit_id` and `run_id` each with its `*_not_applicable` flag (a value, deliberately absent, or neither: unknown), `operation` and `actor_kind`. No origin's reviews cover generated content. An intent the result names that cannot be read, or is not recorded (`lineage.commit.generated_intent`), leaves `generated` absent on that step and is served as a failed element in `failed_evidence`; an origin whose generated-result records cannot be read has no `generated` and is never `covered` (`unestablished` unless an established route step makes it `not_covered`). Every step, in `steps`, `results` and each origin's `path`, carries `evidence_class`: `content_movement`, evidence of how content moved, never attribution, which is each origin's. Its `location` is built from the transformation record alone, never by searching repositories: the transformation's recorded `repository` (`repository_state` `recorded`) and, as `revision`, the step's result SHA, else its origin SHA; a transformation with no recorded repository reads `not_recorded` with a `lineage.commit.repository` diagnostic.
- `origins_incomplete`: a step in `steps` records an incomplete origin list, so origins may be missing.
- `origins`: each commit with its own commits row that the SHA came from, in recording order (the earliest recorded step reaching it, whatever its depth), in the repository of the transformation that reached it (a row in another repository never answers), with `path` -- the route the walk first reached it by, in order from the step whose result is the SHA to the step whose origin is the origin; every step of every other route is in `steps`, and paths are never enumerated, so a split and recombined history costs its recorded steps, not its path count -- and `attribution`: its commits row, location, story, intent, micro-commit entry, reviews, human decisions, agent calls, links and present_day, as the own-row fields read for an own row, so an origin whose git object is gone reads as a `failed` `object` link. `generated` is set when the origin is itself a generated result with a row of its own: each intent a recorded result names for it, as a step's `generated` reads. `review_coverage` says whether its reviews judged the SHA's content: `covered` when every step established on a route from it replays it unchanged into results with complete origins; `not_covered` when the origin is generated, or an established route step is `replayed_resolved`, `combined`, generated or origins-incomplete, so its reviews judged other content; `unestablished` when only steps whose place on a route could not be settled would change it. A step is on a route when a route visits no commit twice through it; deciding that exactly is the directed two-disjoint-paths problem, so the read settles what it can in polynomial time and reports the rest as unestablished, never as a match or a mismatch.
- `results`: every recorded step from the SHA, or a SHA it became, forward, in recording order (transformation, then origin entry) across the whole walk, each with the origin's disposition, `dropped` included.
- `evidence`: the investigative evidence rows naming the SHA on either side: `transformation_id`, `repository`, `operation`, `outcome`, `origin_sha`, `result_sha`, `kind` and the kind's recorded facts in `detail`. Each row is content-movement evidence, such as a patch-identity match: `evidence_class` is `content_movement` and `location` names the transformation's recorded repository with the row's `result_sha` as the revision, as for a step. A kind this server does not know is served as recorded, never filtered. Never a link, and never attribution.

Each walk visits a commit (a SHA in a repository) at most once, so a cycle ends it, and nothing is capped. Own-row fields:

- `commit`: the commits row.
- `location`: where the commit is anchored, read only from its record and with no worktree: `repository`, `repository_state` and `revision` (the commit SHA). The repository is `commits.repository`, else the `repository` of the `commit_intents` row named by `commits.intent_id`, else none: `repository_state` is then `not_recorded`, with a `lineage.commit.repository` diagnostic saying the repository was never recorded for this commit, even when a configured repository holds the SHA. The read never searches the configured repositories for the SHA. A named intent that is missing or cannot be read makes `repository_state` `failed` with its cause. Every link in `links` carries the same `location`. Intent versions keep their own `git_repo`/`git_ref`/`git_path`.
- `story`: present-day context, the story row as it reads now rather than as it read when the commit ran, and so listed in `present_day`. It is omitted when the recorded story cannot be read, and `links.story` then says why: a missing row is never served as "no story". What the execution was handed is `intent`.
- `intent`: what the commit's execution was handed when it ran. `state` is `recorded` (every listed capture was read), `unknown` (capture evidence is unavailable: the commit has no `run_id` or `microcommit_id`, no capture names its workstream, run and micro-commit -- work that predates capture, including runs in flight across the upgrade -- or a listed capture was lost) or `failed` (a stored record could not be read). `recorded` is not proof that every invocation was captured: legacy or absent evidence leaves no row, and reads as unknown only where the read can see it is missing. `captures` are the captures of that execution in recorded order, selected by the commit's own run; `planning_captures` are the planning captures they name through `planning_capture_id`. A planning or edit call that resumed a validation-retry session is sent only its retry feedback, so its capture records no story intent, only its saved prompt, with `criteria_empty_reason` saying so; when its output is applied that capture is the one named, not the capture of the fresh call that started the session, and the intent's diagnostic says the planning inputs in force are unknown to this read. Each capture gives its stage, invocation, `captured_at`, planning state, `criteria_empty_reason`, `handed` (the problem, criterion and descoped criterion versions with their `criterion_id`, plan, micro-commit entry, and requirement inputs with their bytes, source and Git repo/ref/path or `no_revision_reason`, each at its link position), `scope` (the criteria identifiers or reason and their versions, exactly as recorded) and `rulings` (each bundle's refs: the row id, the `sha256` the capture recorded, and the referenced clarification, guidance, saved prompt, attachment capture or event row as it reads now). The saved prompt is the record of exactly what the agent received. A saved prompt ref carries its whole stored content, and it and an attachment capture's manifest are checked against the recorded digest over those stored bytes: `verification` is `verified`, or `mismatch`. A clarification, guidance or event ref has `verification` `not_verifiable`: its digest covers the text as the stage rendered it into the prompt (for workstream clarifications that share one human answer, the batch heading, that row's own question and the shared answer), so the row shown is the current source record, not proof of the wording handed.

  An implement capture (`implement` or `implement_fix`: fresh, the fresh fallback, a review-retry session resume or a crash resume) also records who wrote a workstream CLQ answer when its run was dispatched by the general question path of `POST /workstreams/{id}/answer`, and only while that run carries the answer as its feedback: its first cycle. It lists the rows the answer named that the call's Operator Clarifications section rendered, in the answer's order, under `rulings` bundle `workstream_clarifications`. It records the operator's answer, byte for byte as composed at answer time, as one `handed` requirement input with source `operator_instruction`, for the answer as a whole and never split across questions or criteria. The answer is recorded only when every named row is rendered showing exactly those bytes as its answer, or, when the answer named no rows, when the human-guidance section carries them verbatim. The server's framing and question labels are never recorded: the implement agent is not sent them. These read as unknown authorship: a shown answer that differs from what the operator typed (an option number shown as its option text, or an answer replaced after it was given), whose rows are still listed; answered rows rendered again after the run cleared that feedback, in later cycles or runs; runs dispatched before this evidence existed; feedback from any other producer; and review and final-review captures. Guidance the cycle appends to the feedback is never attributed by this evidence.

  A linked version, planning capture or referenced row that no longer exists, a saved prompt whose content cannot be read, and a digest mismatch each mark that item `failed` with a `lineage.intent` diagnostic and fail the intent. A capture that could not be written when its invocation ran is kept as a lost capture (`intent_captures.lost_reason`, written by `intentcapture.RecordLost` beside its `system_error`, with no links): it is listed with state `lost`, its invocation's identity and the reason in its diagnostic, and makes the intent `unknown`; the captures written beside it are still served. When the lost capture cannot be written either, the `system_error` says so. The intent's own diagnostic lists every failed or lost item, the captures whose planning state is `unknown` (their story's applied planner output had no capture evidence), the planning captures that resumed a session, and, when captures exist but the micro-commit entry is omitted, why. Burn events are not listed.
- `microcommit`: the entry the latest implement capture of the commit's run was handed. A resumed session's capture is handed no entry and leaves the entry of a fresh attempt captured earlier in the same run in force. The entry is omitted, with the reason in the intent diagnostic, when the latest implement capture handed one is preceded by a lost implement capture or one with a handed item that could not be read (no earlier entry stands in for either), when the run has no implement capture (its implement work may predate capture), and when every implement capture in the run resumed a session: a capture does not record which session a resume continued, so an entry captured in an earlier run is never selected. Omitted when no capture names the execution.
- `reviews`, `human_decisions`, `agent_calls`: the micro-commit's reviews, `human_input` events and agent calls. A commit recording no micro-commit (a merge or fixup commit records it `not_applicable`) has none of them, never its workstream's reviews of other micro-commits.
- `links`: the outcome of each link of the chain (`workstream`, `story`, `run`, `microcommit`, `reviews`, `human_decisions`, `agent_calls`, `object`), each a `state` of `recorded`, `not_applicable` (recorded as intentionally absent), `not_recorded` (never recorded) or `failed` (the recorded link could not be read), with the recorded `id` on an id link and a `diagnostic` on a failed one. The id links read only the commit record: a set id is `recorded`, a set `*_not_applicable` flag is `not_applicable`, and anything else, including every record written before that attribution existed, is `not_recorded`; nothing is backfilled from the workstream, plan or story as they read now. The `story` link is `failed` when the recorded story row is missing (`lineage.commit.story`, saying so) or cannot be read (with its cause). A record list is `recorded` when rows were read and `not_recorded` when none were; when the commit record lacks an id it is selected by (`workstream` for reviews, `workstream` and `microcommit` for human decisions, `run` and `microcommit` for agent calls) it passes on that link's state, `not_applicable` when any such link is. A query that fails marks its list `failed` with its cause (`lineage.commit.reviews`, `lineage.commit.human_decisions`, `lineage.commit.agent_calls`) beside an empty list. The `object` link says whether the commit's git object is present in its recorded repository, checked with `git --no-lazy-fetch cat-file --batch-check` in that repository's checkout, so a partial clone never fetches a missing object from its promisor remote (`repo_path` for `(root)`, the `project_repos` path otherwise), never a workstream worktree or branch: `recorded` when it is present, as it stays for a commit merged to the default branch after its feature branch is deleted and pruned; `failed` (`lineage.commit.object`) when git reports the object missing or not a commit, and, titled as an object that could not be checked rather than a missing one, with its cause when git fails, the project config cannot be read or the checkout cannot be resolved, beside a recorded `repository_state`. It passes on a `repository_state` of `not_recorded` or `failed`. A missing object is never reported as not recorded.
- `present_day`: the top-level fields of the response that read current rows rather than what was recorded for the commit's execution: `["story"]`.

A failed story or record-list read is reported on its link, on an own row or an origin's attribution, and the rest of the chain is still served; it never reads as an omitted story or an empty list. For an `own_row` SHA, a failed content-movement read -- the walk back, the walk forward, the read of their recording order, or the evidence read -- is served in `failed_evidence` beside the row's attribution, and the rest of the read is still served. For any served SHA, `own_row` or `proven` alike, so is a failed evidence read once a walk has proven it, a failed read of the origins the walk reached, of a generated result's intent, of an origin's generated-result records, or of an evidence row's detail: each element has `evidence_class` `content_movement`, `state` `failed`, a `lineage.commit.movement_evidence` `diagnostic` naming the read with its cause, and a `location` naming the repository the read was asked for (`repo`, `(root)` for a single-repo file read) with the SHA as the revision, or `not_recorded` with a `lineage.commit.movement_evidence.repository` diagnostic when the read named none; no repository is searched for. A failed read of a recorded commit -- an origin's repository or generated-result records, a generated result's intent, or an evidence row's detail -- is anchored at that commit instead, in its transformation's recorded repository. The file read gives an origin, or each generated intent of a result, whose attribution read failed a chain whose story, micro-commit, intent and human-decision links are `failed` with that diagnostic, its object still checked, never an unattributed chain. `steps`, `origins`, `results` and `evidence` then hold only what was read (a failed recording-order read still serves every step, origin and result the walks read, in walk order and without `origin_entry` or `result_entry`; a failed read of an origin's repository leaves that origin out and the walk does not pass it), never standing in for no evidence. `failed_evidence` is `[]` when every read succeeded. The file read serves it on each commit's embedded lineage and still builds the own row's chain. A failed commit lookup, a failed transformation read of a SHA with no own row (its resolution depends on that read), or a captured-intent read that fails outright, fails the request with its cause; it never reads as an unrecorded SHA.

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
    [1]  implement  approve  confidence=0.94  mc=COMMIT-AUTH-003  2026-03-09 10:20
        Change hash: chg1:sha256:3f9a0c6e1d2b4a5f8e7c9b0a1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e
    [2]  implement  approve  confidence=0.91  mc=COMMIT-AUTH-005  2026-03-09 11:05
        Change hash: not computed: resolve changed tree: git exited 128
    [3]  implement  approve  confidence=0.88  mc=COMMIT-AUTH-005  2026-03-09 11:40
        Change hash: not recorded (reviewed before change hashes were recorded)

  Human decisions (1):
    approved (2026-03-09T10:15:00Z)
```

The story's captured intent history is served on `GET /stories/{id}?include=intent` (`readStoryIntent` in `server/internal/api/lineage_intent.go`), which `hashd lineage <STORY-XXXX>` requests. Without `include=intent` the detail read runs none of the history queries and omits all four fields, meaning not requested; the `GET /stories` list carries none of it. When requested, a list with no records is served as `[]`. Fields:

- `intent_versions`: every `intent_versions` row recorded for the story, in the order they were first recorded (version id order: a version's id is allocated with the capture that first recorded it, so removing that capture, as a workstream removal does, leaves the order unchanged): `kind`, `criterion_id`, the exact bytes (`content`, or `content_base64` when they are not UTF-8) with `content_sha256`, `source`, and Git repo/ref/path or `no_revision_reason`. An edited criterion is a separate version under the same `criterion_id`. Each version lists `captures`, the captures that used it in recorded order: capture id, stage, invocation, workstream, run, micro-commit, `captured_at` and `role` (`handed`, or `scope` for a micro-commit's criteria line). A lost capture links no version, so it is listed under none. The commit read lists a lost capture only when its workstream, run and micro-commit are the commit's; a lost capture of a stage recorded without them (planning, edit, plan split, breakdown) is served by no read.
- `intent_state`: `recorded` when the story has versions, `unknown` when it has none: its stages ran before capture existed or have not run, every capture recorded for it linked no version, or its captures were lost. `recorded` is not proof that every invocation was captured, and a lost capture does not change it.
- `requirement_consumption`: consumption evidence, never intent: the story's `requirement_burned` events, newest first, each with its event id, `created_at` and `payload`. They are written after the requirement text is removed from REQS and are never listed as a version or a requirement input.
- `merge_comparisons`: content-movement evidence, never attribution: the change-hash comparison each of the story's `merge_landed` events recorded, in recorded order (`created_at`, then event id, ascending), uncapped, each read through `mergeflow.DecodeMergeLanding`. An element carries `evidence_class` `content_movement`, `state`, `event_id`, `workstream_id`, `created_at`, `merge_sha`, `merge_mode`, `target_branch`, `compared_review_id`, `reviewed_change_hash` and `landed_change_hash` as recorded (`hash`, or `not_computed` with its reason), and `outcome`, the recorded `changehash` outcome (`match`, `differ`, `no_reviewed_hash`, `landed_not_computed`); nothing is recomputed or re-compared. A `match` proves each file gained and lost the same lines in the same order, not that the patch identity is unchanged, and never links commits. `state` is `recorded`; `not_recorded` for a landing written before landings recorded a comparison, which is neither a match nor a difference and carries a `lineage.story.merge_comparison` diagnostic; or `failed`, with that diagnostic and its cause, for a row whose payload does not decode or, as one element with no event id, when the landing rows cannot be listed. A failed element never fails the story read: the intent fields and every other element are still served, deliberately unlike the snapshot's landed merge, which fails its read. `location` is always `repository_state` `not_recorded` with a `lineage.story.merge_comparison.repository` diagnostic, since a landing record names no repository, and the recorded `merge_sha` as the `revision` (empty when the leg held none); no repository is searched for.

Apart from `merge_comparisons`, a failed history lookup fails the `include=intent` read with its cause; it never reads as an omitted field or empty history, and it cannot fail the default read, which does not run it.

#### Output formats

`--format table` (default): human-readable tables as shown above.
`--format json`: machine-readable, suitable for piping to `jq` or feeding to other tools.
`--format markdown`: for pasting into PRs, docs, or reports.

`--details` and `--details=N` expand reviews on `hashd lineage <sha>` and `hashd lineage <STORY-XXXX>`, the way `hashd show --details` expands standing records: `--details` expands every review, `--details=N` only the review numbered N, and the rest stay compact. An expanded review adds `record`: its stored record whole, as recorded JSON when it parses and as the stored string otherwise, so its diff identity, change hash, verdict, confidence threshold, provenance, session id, every finding and the recorded diagnostic evidence are shown uncut. Table prints it as indented JSON beneath the review's change hash, markdown fences it, and JSON carries it on the same numbered entry, so the flag selects the same reviews in every format. The CLI selects over the reviews the read already serves; no REST parameter is involved. The value is parsed and refused as `hashd show` refuses it (`show.errors.details`): `0`, a number past the last review, a non-number, and any N on a read with no reviews (`--details` alone is fine there), before anything is printed. A file target refuses the flag (`lineage.details.target`): file lineage lists no reviews.

Table and markdown print every captured-intent text whole. `hashd lineage <sha>` prints the commit's Repository and Revision from `location` (or the repository state and its diagnostic when none was recorded or it could not be read), then a "Links" section with each link's outcome: a recorded id link shows its id, `not_applicable` reads "not applicable (recorded as intentionally absent)", `not_recorded` reads "not recorded (never recorded for this commit)", and a `failed` link reads as failed followed by its whole diagnostic and cause, never as an empty value. The current story row is printed under "Story (as it reads now)", apart from the recorded "Intent in force". It adds an "Intent in force" section: the intent's state (`recorded`, `unknown: no capture for this execution`, or `unknown`/`failed` followed by the served diagnostic, including its cause), the micro-commit entry the server resolved as in force (or `unknown` when it omitted it, with the reason in that diagnostic), then each capture's stage, invocation, handed versions (criterion ids with their text, plan, micro-commit entry, requirement inputs with source and Git repo/ref/path or no-revision reason), scope ids or reason, and ruling bundles by ref id, each with the clarification, guidance or event it names, whole, under "Source record (as it reads now, not as captured)": the server serves those rows as they read now, so the recorded evidence is the reference's id and digest. Any failed or lost item's diagnostic is shown in full. `hashd lineage <STORY-XXXX>` adds "Intent versions" (the state, then every version with its text and the captures that used it) and "Requirement consumption". Each review, in table, markdown and JSON, is numbered from 1 in listing order with its type, decision, confidence, micro-commit, time and the change hash its record stores: the hash whole in the form it names (`chg1:sha256:<hex>`), "not computed: <reason>" with the recorded reason, "not recorded (reviewed before change hashes were recorded)" for a record without one, or "unreadable" with the stored value and why it does not parse; JSON carries it as `change_hash` with its `state` (`recorded`, `not_computed`, `not_recorded`, `unreadable`). JSON prints the commit lineage response as served, every field kept except `reviews`, which holds those numbered entries, and the story's `intent_state`, `intent_versions` and `requirement_consumption`. Story lineage reads each of its commits' recorded chain (`GET /commits/{sha}/lineage`, in the repository the listed record is located in) and shows, under each commit, its links and its intent in force with the ruling bundles its execution was supplied; its human decisions are those chains' `human_decisions`, read through each commit's recorded workstream and micro-commit, together with the story's own `human_input` records: its events (`GET /stories/{id}/events`) and the human gate's approvals and rejections, which it records as transcripts (`GET /stories/{id}/transcripts`). They keep the decisions of a story with no commits or of a micro-commit that produced none and survive the story losing its current workstream; each is listed once, in order of its recorded instant; JSON keeps each whole, tagged with the `record` table it was read from, with its `data` payload and execution ids as recorded, while table and markdown show its content truncated to 60 characters and the feedback the payload records, such as an approval's conditions, whole. The current workstream's `human_input` events that none of those name (an event recorded with only a workstream id) are listed apart as present-day workstream context (`workstream_human_decisions`, "Workstream context (as it reads now)"). A listed record the lineage read cannot address (its repository not recorded or unreadable, and another record of the SHA answers) fails the command (`lineage.story.commit_record`) rather than show another record's chain. A direct and an intent-backed record of one commit in one repository are one commit to the lookup, which answers with the direct record. When both record the same execution (workstream, run, micro-commit and intentionally-absent flags, which the chain is read from), both stay listed, each read through that answer as its own record (its `created_at`, message and `prev_hash`, which the record hash covers, kept), and story export attests each distinct hash-chain entry with its own provenance, an identical one once; a pair recording different executions is refused (`lineage.story.commit_record`), since the read cannot name the intent-backed record and its chain would be another execution's. Its reviews are its commits' chains' reviews and its current workstream's, each listed once and numbered in one index space. JSON adds each chain as served under `commit_lineage`, every field kept except `reviews`, which holds that chain's reviews as their story-wide numbered entries, expanded as `--details` selects, and `sha`, `resolution` and `origins`: origins are other commits' attribution, which `hashd lineage <sha>` shows. Its content-movement evidence (`steps`, `results`, `evidence`, `origins_incomplete`, `failed_evidence`) is kept as served, and the story read's `merge_comparisons` are added whole. Table and markdown show each commit's steps, results, evidence and failed evidence reads under it as commit lineage renders them, then a "Merge change-hash comparisons: content-movement evidence, not attribution" section listing every comparison with its state, recorded hashes (a hash not computed with its reason), outcome, any diagnostic and its location; a `match` says each file gained and lost the same lines in the same order, never that the reviewed and landed changes are one commit, patch or author. Story lineage fails, with the cause, when a commit's chain or its current workstream's reviews cannot be fetched; `hashd lineage <STORY-XXXX>` prints its title, status and source refs as present-day context ("as it reads now"), apart from the recorded "Intent versions", and lists every commit recorded for the story (`GET /commits?story_id=`, never blame) with its recorded repository beside its SHA, the repository a follow-up `hashd lineage <sha>` resolves in. That repository is the commit's `location`, which `GET /commits` and `GET /commits/{sha}` serve beside each record, resolved the way commit lineage resolves it (the record's repository, else its commit intent's), so a record attributed only through its intent is never shown as having no repository. File lineage lists a blamed commit as untracked only when the commit lookup answers that hashd never recorded it (`lineage.commit.not_recorded`); any other failure of that lookup, a 404 for an unknown project or repository included, fails the command with its cause (`lineage.file.commit_fetch`). Each tracked row carries the commit's recorded `repository` and a `story_link` with the same four outcomes as commit lineage's links; a recorded story whose read answers HTTP 404, whatever its source, is a `failed` story link, rendered as a retrieval failure with the served diagnostic whole, never as no story, and any other failure to fetch the story fails the command.

### Phase 4: Attestation export (DONE)

**Goal:** Export lineage in standard formats for compliance.

`hashd lineage export <sha> --format slsa`:
- in-toto Statement with SLSA v1.0 provenance predicate
- `buildType`: `https://hashd.ai/provenance/v1`
- `externalParameters`: story_id, microcommit_id (both from the commit record)
- `internalParameters`: run_id, and `links`: one entry per link of the commit's recorded chain, keyed by its name on the read (`workstream`, `story`, `run`, `microcommit`, `reviews`, `human_decisions`, `agent_calls`, `object`), holding its `state` and, when it has one, its recorded `id`; and `content_movement` (below)
- `builder.id`: `https://hashd.ai/builder/v1`
- `metadata.invocationId`: run_id

`hashd lineage export <sha> --format in-toto`:
- in-toto Statement with custom hashd predicate (`https://hashd.ai/provenance/v1`)
- Full commit row (its recorded story id)
- `reviews`: the same numbered entries as `hashd lineage <sha> --format json` (number, id, type, decision, confidence, micro-commit, time, and `change_hash` with its `state`), compact by default
- Human decisions, agent calls (model/tokens/duration)
- `links`: each link's `state` and recorded `id`, as in the SLSA `internalParameters`, so `not_applicable` and `not_recorded` stay distinct
- `chain` section with `prev_hash` and `record_hash` for verifiability
- `content_movement`: the same section as the SLSA `internalParameters` carries (below)

`hashd lineage export STORY-XXXX --format slsa`:
- Exports array of attestations for all commits in the story, each read in the repository its record is located in

`--details` and `--details=N` expand in-toto reviews as they do on the lineage read: an expanded entry adds `record`, the review's stored record whole and as recorded. A story export numbers its reviews from 1 across all its attestations, each review once by its ID (a chain attested once is numbered once, and a review that commits of one micro-commit share keeps one number in every attestation that carries it), so `--details=N` expands the review numbered N wherever it appears. The value is refused as `hashd show` refuses it (`show.errors.details`) before anything prints. `--details` with `--format slsa` is refused before any fetch (`lineage.export.details_format`): SLSA provenance carries no reviews, and its output is unchanged.

Both formats carry a `content_movement` section per attested commit, with `classification: content_movement`: evidence of how the commit's content moved, never attribution. It holds the commit lineage read's `origins_incomplete`, `steps`, `results` and `evidence` (each element with its transformation id, repository, operation, outcome, origin and result SHAs, a step's `origin_entry` and `result_entry` as served, disposition or evidence kind and detail, and its location's repository and revision), and `merge_comparisons`: every change-hash comparison the merge_landed rows of the commit's recorded story recorded (`GET /stories/{id}?include=intent`; a commit whose story link is not recorded carries none, and a story export reads the story once for all its attestations), each with its `state`, event, merge SHA, recorded hashes or not-computed reasons and outcome. `steps` are listed in recorded order (`transformation_id`, `origin_entry`, then `result_entry`; a step naming no origin leads its transformation), every other element in served order, none capped. No element's location state or diagnostic is attested, and nothing in the section enters the subject, the commit, `chain` (`record_hash`), `links` or `hashd lineage verify`.

Export refuses (`lineage.export.failed_link`) a commit whose chain has a `failed` link, whose read has a `failed_evidence` element, or whose story read has a `failed` merge comparison, with each diagnostic whole, rather than attest a failed read as content never recorded; `not_recorded` and `not_applicable` links, and `not_recorded` comparisons, export as what the record holds.

A commit export attests only a commit's own record: a SHA whose lineage read resolves `proven` or `unproven` is refused with the same not-recorded Diagnostic (`lineage.commit.not_recorded`) as a SHA hashd never recorded.

The export attests only recorded content, compact and expanded, so it reproduces byte-for-byte across story edits and across a backup restored to another location. Any top-level section the commit lineage read names in `present_day` (today the `story` row: its title, `source_refs` and `origin`) is never attested; the recorded story id stands for it. No link `location` or `diagnostic` is attested, and nothing is derived from the server host's filesystem.

### Phase 5: Tamper evidence -- hash chain (DONE)

**Goal:** Make lineage records verifiable via hash chain.

- Each commit record includes `prev_hash`: SHA-256 of the previous record's canonical JSON
- Canonical form: sorted keys, compact separators, all commit fields
- First commit for a project has `prev_hash = None` (genesis)
- `hashd lineage verify` walks the chain, reports total/verified/breaks, and reports coverage (git object retrievable, attribution complete, every gap) as a separate result
- Exit code 0 if chain valid, 1 if broken; only the chain decides it, never coverage

Future options (deferred):
- **Sigstore integration:** Keyless signing of attestation exports
- **Transparency log:** Append-only log of lineage events, Rekor-style

## Schema additions

### commits table (existing, populated by Phase 1)

Schema defined in `db.py` (`_SCHEMA`, `commits` table). Populated by `save_commit()` called from `stage_commit()`.
Includes `prev_hash TEXT` for hash chain (Phase 5).

A row also names its `repository` (the configured repository name, never a path) and its attribution: `operation`, the acting identity (`actor_kind` user or system, `actor_user_id`), the `intent_id` of the `commit_intents` row its writer recorded before committing, and per-link `*_not_applicable` flags. A NULL link with its flag clear is unknown; a set flag says the link deliberately does not apply. The same SHA in two repositories is two rows; rows with no repository (all rows written before repositories were recorded) stay unique by SHA and read their attribution as unknown. Repository and attribution sit outside the chain hash, so existing chains verify unchanged.

Writers go through `server/internal/commitrecord`. `Record` stores the intent (repository, ref, expected parents and tree, links, operation, actor, commit message, operation key, this process's instance id) before the commit and takes the intent's lock, a file under the repository's git common directory; the writer must not commit if either fails, and passes the lock's descriptor to the git that commits, so the lock stays held while that git lives even after the server dies. `Complete` marks the intent completed and appends the chain row, with the recorded message, in one transaction, recording the commit's actual tree when a hook changed it. `Supersede` records the intent of the rebased commit that is about to replace a recorded commit, naming the intent it replaces, which stays as it is until the ref holds the replacement; `Replaced` then supersedes an open predecessor. `MarkDidNotSurvive` records a rolled-back commit with no chain row. `Resolve` settles an open intent from git alone, reading only parents and trees of commits reachable from its ref, and only while holding the intent lock; a held lock leaves the intent open, even when its commit is already visible. Under the lock, an intent with a recorded replacement is settled by the replacement first: one that completes makes it `superseded`, and otherwise its own commit is looked for. One commit with exactly its ordered parents and tree completes it, several matches mark it `unresolved` with every candidate kept; no match but a commit with its parents and another tree not recorded in this repository (its own commit, if a hook rewrote the tree) also marks it `unresolved`; otherwise it is `did_not_happen`. A writer whose git refused or failed its commit settles that intent itself with `SettleHeld`, by the same rules and with the same outcomes, under the lock it already holds rather than probing for it. A replay finds its prior intent with `FindOwn` and resolves it before deciding to commit; at startup the server resolves every open intent recorded by an earlier process. `reqs.Repository` maps a checkout to its repository identity: the root repository at `repo_path` is `(root)`, a value outside the characters a repository name may use, and named repositories use their `project_repos.name`. A REQS write (`reqs.CommitReqsChangeWithOptions`) records a path-limited commit of the REQS file and leaves the intent open until its push settles. A rejected push fetches the upstream and rebases the unpublished commits onto it with the repository's own `git rebase` (`rebase.autoStash` on, `--reapply-cherry-picks`, merge commits dropped and the commits they brought replayed, commits that become empty dropped and commits empty from the start kept), so its pre-rebase and post-rewrite hooks and commit signing apply as for any rebase, and a pre-rebase hook that refuses keeps the replay from publishing. A conflict is found before the rebase starts, by replaying each commit's tree (merge-tree), and moves nothing. The rebase stops just before it picks each commit hashd recorded -- the write's own, or one a failed push left unpublished -- and the replacing intent is recorded there, with HEAD, the rebased history so far, as its parent, before git writes the rebased commit; each replacement completes with the commit that has its parents, so the record names the published SHA. Before replaying it settles every intent another writer left open on the branch, refusing while one's writer is alive, and the git that rebases inherits the locks of every intent whose outcome it decides. The REQS sync before a write fetches and fast-forwards only, never rewriting an unpublished commit. A rolled-back commit is `did_not_survive`, and a write that commits nothing records nothing. The operator SPEC edit and the gitleaks allowlist and config commits record through the same path (`reqs.DocumentCommit`): an operator operation in the repository at `repo_path` that holds the file, under its configured identity (`(root)`, or the name of a configured repository checked out there), acting for the request's user, with story, workstream, micro-commit and run recorded as not applicable; the SPEC edit's push uses the same replay. Before deciding whether there is anything to commit, these writers settle every intent left open on the file's branch, so a replay of an attempt whose commit landed unrecorded records it even when the replay commits nothing. A commit that cannot be recorded is refused and not made. The human-edit commit (`POST /workstreams/{id}/commit`) records a `human_edit_commit` intent for its path-limited commit of the batch, keyed by its retry token, with the workstream, its story (or story not applicable), the acting user, and micro-commit and run recorded as not applicable; a retry adopts the commit its intent settled to rather than reading the commit message. A record that cannot be written after the commit is noted on the workstream's transcript (a `commit_response` warning, as the commit stage notes its own) and does not fail the commit; its intent stays open for recovery. A batch no intent names whose commit would write HEAD's own tree -- committed before this record existed -- finishes its bookkeeping with no commit and no record. The post-merge documentation commit (`mergeflow` archive) records a `merge_doc_update` intent per documentation repository for its path-limited commit, keyed by the workstream and that repository's archive worktree, with the workstream, its story (or story not applicable), the system actor, and micro-commit and run recorded as not applicable; the ref is the detached archive worktree's own HEAD (`worktrees/<id>/HEAD`), and the intent completes with the commit the archive checkpoints. When the publication rebases onto a moved destination, the rebase runs in a scratch checkout and stops just before it picks the recorded commit; a superseding intent is recorded there (parent the rebased history so far, tree computed before the pick), and the finished history is checked out in the archive worktree in one step holding that intent's lock. Every git that creates, rebases in or removes the scratch checkout inherits its lock, so a replay never removes or reuses it under a git that outlived the server; a checkout that moves HEAD and then fails keeps the rebase checkpoint for the retry to adopt. The intent completes with the rebased commit, so the published SHA is the recorded one wherever the commit sits in the outgoing history, and until that step the archive worktree's HEAD still holds the commits its open intents name. The replay is pinned to a plain rebase's behaviour whatever the repository's rebase settings: no autosquashing, commits that become empty are dropped, and a todo the pause cannot be placed in refuses the rebase. A re-dispatched archive settles its own open intents before deciding to commit or rebase, and nothing staged records nothing. A record that cannot be written after git succeeded is noted on the workstream's transcript and does not fail the archive: its intent stays open, and the archive keeps the documentation worktree whose HEAD that intent names, for a replay or the next server start to resolve. The merge path's fix-up commits -- the managed-file sweep (`managed_file_sweep`), the `--fix` dirty-file commit (`dirty_file_fix`), the migration renumber and dedup (`migration_renumber`, `migration_dedup`), the post-rebase build's regeneration (`post_rebase_regeneration`), the generated-artifact regeneration at a rebased tip (`generated_artifact_regeneration`), and the merge gate's whitespace fix (`whitespace_fix`) and owned-file regeneration (`owned_file_regeneration`) -- are whole-index commits recorded through `mergeflow.FixupCommits.Commit`: an intent on the branch HEAD names, with HEAD as parent and the index's tree, keyed by the operation, workstream, repository and branch, with the workstream, its story (or story not applicable), the system actor, the run for a merge-gate commit (run not applicable elsewhere) and micro-commit not applicable. The sweep records the sweep, not an author of the swept content. Each leg settles, on entry (`FixupCommits.Settle`) and before any rebase or decision that there is nothing to commit, every intent of its workstream left open on the branch it has checked out (the publish rebase does so whether or not it may heal a conflict), so a commit an earlier attempt landed unrecorded is recorded while the branch still holds it; an intent it cannot settle, or a commit it identifies but cannot record, stops the leg before it rewrites the branch. A commit that cannot be recorded is not made and fails the leg, nothing staged records nothing, and a commit git refused is settled from git with no record. A commit git reports failed after it landed (a post-commit hook killed or timed out) is left open, because the leg may roll it back: the branch's next settle, or the startup pass, records it only if it survived. The generated-artifact regeneration at a rebased tip, which its rebase leg may discard with the rest of the rebase, is handed back to that leg undecided (`FixupCommits.CommitPending`): the leg keeps it, completing the intent with the SHA git reported (and the actual tree when a hook rewrote the index), before it verifies or publishes the branch, and discards it (`did_not_survive`, no chain row) once it has rolled the rebase back. A discard the branch still holds is left open for recovery. Settling stays for crash recovery: a leg stopped between the commit and its decision. The intent completes with the commit git reports creating, even when a post-commit hook moved HEAD past it. The local merge's own commits record through the same path, with the same links, key and settling, each intent recorded before git creates its commit. Every attempt first tries the merge with `--no-commit`. A clean trial is the merge git will make: its parents (HEAD then every `MERGE_HEAD` entry) and merged tree are recorded as a `local_merge` intent, the trial is aborted, and the real `git merge --no-ff --commit` runs holding the intent's lock, so the repository's merge strategy, merge options (`--commit` overrides only a configured `--no-commit`), prepared message and pre-merge-commit and post-merge hooks all apply. A conflicted trial goes to the conflict resolver, which runs on a detached HEAD, so a commit it makes itself never moves the branch. hashd lands no commit it recorded no intent for: when the resolver commits its merge, whatever it then reports, a soft reset returns its commits to the index -- its final index and working tree, edits staged after its last commit included, are the resolution -- and the merge is put back in progress, and hashd commits it, as it commits a resolution the resolver only staged, as `conflict_resolution_merge` (`FixupCommits.CommitMerge`); a hook that ran on the resolver's commit runs again on hashd's. A resolver commit that is not the merge, or a branch something else moved while the resolver ran, fails the merge without rewriting the branch. A writer identifies the commit it made by its exact expected parents -- the summary line git commit prints, when its commit has them, else the one commit since the first parent with them -- never by a line a hook printed. A merge it aborts records nothing, and a refused commit is `did_not_happen`. A re-dispatched merge leg settles what an earlier attempt left open before it merges, and a branch the default branch already holds is adopted, not merged again.

A git operation that rewrites, or is asked to rewrite, a branch's commits records what it did through one entry point, `commitrecord.RecordTransformation`, made while the server holds both sides. It writes one `commit_transformations` row (the operation, the configured repository identity, the workstream, story and run links, the before, onto and result tips, and the outcome) and its children in one transaction: `commit_transformation_origins` gives each commit the operation started from exactly one disposition (`replayed_unchanged`, `replayed_resolved`, `dropped`, `combined`, or `merged_in` for a commit a merge brought in with its own SHA kept); `commit_transformation_results` lists each commit it left, marking one whose origins it could not observe in full as origins-incomplete; and `commit_transformation_links` holds the origin-to-result pairings the operation observed itself in its own run, never derived afterwards by comparing commits. A result the operation generated rather than replayed names the intent its writer recorded, read from the `commits` row for that repository and SHA; with no such row it is stored origins-incomplete with no intent, never an invented attribution. Investigative evidence about a possible pairing (equal patch IDs, say) goes only to `commit_transformation_evidence`, and is never read as or turned into a link. Each link names a declared origin and result, a `combined` origin links to a result with more than one origin, and a `dropped` origin has no link. A `merged` outcome is a completed merge: it leaves a result tip other than its before tip (the merge commit), its origins are all `merged_in`, and no other outcome carries a `merged_in` origin. A `merged_in` origin kept its own identity, so it is never linked to a result; storage refuses such a link as well as the validator. An operation that rewrote nothing (`unchanged`, `refused`, `not_begun`, `conflict_aborted`, `always_aborted`, or any record whose result tip is its before tip) records its outcome with no origins, results or links. The repository must be a configured identity, `(root)` or a `project_repos` name, never a path; a refused repository value is not repeated in the failure report. A record that breaks a rule is refused whole, with no rows written; a refusal or a failed write is reported as a durable `system_error` timeline row on the workstream (and its story and run when known), whose data carries a Diagnostic sourced `commitrecord.transformation` with the operation and tips, and is logged when that row cannot be written either. Recording never fails, retries or alters the git operation, whose result and diagnostics stand. A server-run `git rebase` observes its own pairings through `commitrecord.ObserveRebase`, from git's sequencer state during that run and never by comparing patch IDs, messages or file text afterwards. Before the rebase it reads the branch tip and the replay range git computes (`rev-list --reverse <upstream>..<before>`), and it appends to the caller's rebase, after the caller's own options so that it runs after the caller's own exec steps and a caller's `--no-exec` does not clear it, an `--exec` step whose command names no path: the capture directory, created in the server's temp directory only after that directory is checked to lie outside the repository, reaches it through `HASHD_REBASE_CAPTURE`, which the caller adds to the rebase and to every git that continues or skips in it. After each pick the step removes its previous snapshot, then copies HEAD and `rebase-merge/rewritten-list` (located with `git rev-parse --git-path`) and marks the snapshot complete; it only reads the repository, never writes its config, refs or hooks, and always exits 0, and the capture is read once and deleted, never stored. A snapshot is read only when it is complete and its HEAD is the run's result, so a failed or skipped later step is never read as the whole run. Because an `--exec` with no `-i` changes git's empty-commit default from drop to keep, the observer pins `--empty=drop` when the caller set neither `-i`, `--exec` nor `--empty`. At each conflict stop the caller calls `ConflictStop`, which reads `REBASE_HEAD` and marks that origin `replayed_resolved`, before it continues. A merge that stops (`--rebase-merges`, with `MERGE_HEAD` set) is first listed against HEAD at the stop; that provisional entry is never read as a pairing, and the merge is paired with the result listed after it continues, or dropped when it is skipped. `Finish` then builds the record: an origin paired with one result is `replayed_unchanged` (or `replayed_resolved` when marked), origins paired with one shared result are `combined`, an origin in the replay range that the list does not name is `dropped`, and a result on `<onto>..<result tip>` that no origin became is a generated result, resolved by `RecordTransformation`. A replay-range commit the result still holds as it was (a pick git skipped or fast-forwarded) is neither an origin nor a result. A run that left its before tip is `unchanged`, an aborted conflict is `conflict_aborted`, and `refused`, `not_begun` and `always_aborted` pass through, all with no pairings. Where an appended `--exec` would change what the rebase does, the rebase runs exactly as the caller wrote it: a branch that already holds the commit it moves onto, unless the rebase is forced (`-f`, `--force-rebase`, `--no-ff`, read by their last value), since git may then report it up to date or skip its leading picks, and an exec changes both; a repository with a hook the rebase can run before its last exec (`pre-rebase`, `post-checkout`, `reference-transaction`, `post-index-change`, `prepare-commit-msg`, `post-commit`, `post-rewrite` (a fixup's amend runs it mid-run), `pre-merge-commit`, `post-merge`, and for `-i` also `pre-commit` and `commit-msg`, as `git hook list` reports them), since git stops a rebase whose exec step leaves the tree dirty; the apply backend (`--apply`, `--whitespace`, `-C`, or `rebase.backend=apply` as read with the rebase's own global options); and an option abbreviation or negation the observer cannot read. The one visible difference of an observed rebase is git's `Executing:` line for each step, which carries no path. When a rebase run as written rewrites the branch, when no complete snapshot accounts for every result, when a conflict stop could not be read, or when the observed pairings break the record's rules, every result the rebase left is recorded origins-incomplete, with no origins or links. `RecordTransformation` stores that record and also writes a `system_error` timeline row, sourced `commitrecord.transformation`, giving the reason the pairings were not observed; the reason is authored text that names no filesystem path, and the underlying error goes only to the server log.

The merge gate's direct rebase (`runflow/mergegate_rebase.go`) records as operation `merge_gate_rebase`, onto `origin/<default branch>` and the base SHA it resolved, linked to the workstream, its story and its run, in the repository `reqs.Repository` resolves for the worktree (an unresolvable one is passed empty, so the entry point refuses the record and reports it). It observes the workstream branch, not HEAD, so a tip read while the rebase is in progress is the branch. A rebase that completes, directly or through the auto-resolved `rebase --continue` (preceded by `ConflictStop`, so the union-resolved commit is `replayed_resolved`), records before the post-rebase verification, whose fix-up commits are their own records; one git found unnecessary is `unchanged`. Every abort exit records `conflict_aborted` after the abort, except a rebase git refused to start, which is `not_begun`; a hand-off to the regeneration-subsumption retry first records the direct rebase `conflict_aborted`, and the fallthrough abort after a retry that did not apply records nothing more. A fetch failure, an unresolved base, an unreadable snapshot or ownership mark, and a refused checkout run no rebase and record nothing. Before the gate reads the rebase output for conflicts or makes a park reason of it, `RebaseObserver.RebaseOutput` gives it back as the rebase run without the observer prints it: each observing step's progress segment and `Executing:` line go, and every other `Rebasing (n/m)` counter, which git numbers with the observing steps counted, is renumbered without them. Which steps observe is read from git's own layout, since git also counts the update-ref, label and reset commands configured `rebase.updateRefs` or `rebase.rebaseMerges` add: while the rebase is stopped, its todo after as many of its done list as git's total leaves room for (a pick git rescheduled, refusing to overwrite an untracked file, stays in both and is counted once); once it is over, output that prints every step itself. Without either (a continue's output after the run ended), counters are never renumbered on a guess; only the `Executing:` lines go.

The regeneration-subsumption retry (`runflow/mergegate_regen.go`) records each rebase it starts, every restart included, as its own operation `merge_gate_regeneration_rebase`, with the same repository, links and onto as the direct rebase. Each stop it takes with `--theirs` or union-merges is marked by `ConflictStop` before its `rebase --continue`, so those origins are `replayed_resolved`; a commit that replays without a stop is `replayed_unchanged`. A run a rollback ends (a restart for a path not yet probed, a park, an exit over an unrestored tree) records `conflict_aborted` once the rollback has returned; a retry that succeeds without a stop records its completed rebase before the post-rebase verification. A run whose replay completes is finished then, before the tip regeneration commits, and held: once the regeneration is proven and its commit kept, that commit is added as a generated result, attributed to the intent its writer recorded and never paired with an origin, and is the record's result tip; with no regeneration commit the held record is stored as it is. Either is recorded before the post-rebase verification, whose fix-up commits are their own records. A completed replay the leg rolls back because the regeneration was not proven left nothing, so it records a fresh `conflict_aborted` record at the tip the rollback left, with no pairings and no observation gap reported.

Each attempt of the local merge loop (`mergeflow.AttemptMergeWithRetry`) records its `merge --no-ff` once, as operation `merge_no_ff` (distinct from the `local_merge` and `conflict_resolution_merge` commit intents its commits record), through `FixupCommits.RecordTransformation` with the leg's links and the repository `reqs.Repository` resolves for the checkout (an unresolvable one is passed empty, so the entry point refuses the record and reports it). Its before tip is the target's HEAD when the attempt began; its onto is the branch merged and that branch's tip (`MERGE_HEAD`). A merge is not a rebase: the branch commits keep their SHAs, so a completed merge is `merged`, with each branch commit git brought in -- listed (`rev-list HEAD..MERGE_HEAD`) while the merge is in progress, after the clean `--no-commit` trial and before it is aborted, or at conflict detection (read again from the real merge when it is left in progress after a clean trial, the trial's kept otherwise), never by comparing commits afterwards -- a `merged_in` origin linked to no result, and the merge commit its one result and its result tip. Only a merge commit concluding the agent's resolution (`conflict_resolution_merge`) is a generated result, its attribution the entry point resolves from the commits row; the clean merge's commit never is. A merge commit git did not identify is reported undetermined (`commitrecord.NoteUndetermined`), never invented. Every attempt that conflicted and did not produce the merge commit records `conflict_aborted`, with no origins, results or links, after its abort ran: one left unresolved or abandoned by the resolver before the next attempt, the last attempt's abort that returns blocked, the resolver's prelaunch refusal, the deadline passing during conflict resolution, a resolution whose concluding commit git refused or that could not be recorded (it conflicted and was aborted, so it is not `refused`), and a HEAD that could not be detached for the resolver or a branch that moved while it ran. Either outcome is stored only once a cancellation-detached read shows the attempt left nothing -- no operation in progress but one it found when it began (so a merge git refused to start beside an earlier attempt's unaborted merge is `refused`, naming no onto commit from that merge), and HEAD back at its before tip -- since a failed git command proves neither (an abort git refused leaves the merge in progress, and a merge or concluding commit a hook failure reported failed may have landed); otherwise the attempt is reported undetermined. A merge git refused for a reason other than a conflict, and a clean trial whose commit could not be recorded, record `refused`, with no result tip. A re-dispatched leg that finds the branch already merged by an earlier attempt (adopted after `Settle`) records that merge once, but only a merge an earlier attempt of the workstream demonstrably made: the commit the newest completed `local_merge` or `conflict_resolution_merge` intent of the workstream on HEAD's branch resolved to, still on HEAD. A branch merged by anyone else -- one a pull brought in, say -- records nothing. The merge is identified by that intent, never by the branch's tip, which the leg's preparation may already have rebased onto the merge; its first parent is the before tip, its second the onto commit, and `rev-list <first parent>..<second parent>` its `merged_in` origins. Its generated mark comes from the operation of the intent its commits row names: generated only for `conflict_resolution_merge`. A merge commit whose commits row is missing may or may not hold the agent's content, so its result is origins-incomplete and not generated. A merge that already has a `merged` `merge_no_ff` record with it as result tip records nothing (`commitrecord.TransformationRecorded`; an aborted attempt whose result tip is the same commit is not its record); the `merge:{project}:{ws}` workflow singleton serializes the legs, so the check and the insert do not race. A lookup that fails is reported undetermined and records nothing. Recording never changes the merge's commands, retries or result.

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
