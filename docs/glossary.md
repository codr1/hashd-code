# Glossary

The canonical vocabulary for Hashd. [WF.md](../WF.md) owns workflow rules and
state diagrams.

## Entities

### Suggestion

A discovered planning candidate that can be claimed into a story.

### Story

A feature or bug defined by a problem statement, acceptance criteria, and source
requirements. It states what the change must accomplish.

### Acceptance criteria (AC)

The bulleted, testable conditions a Story must satisfy to be considered done.
ACs are *input documentation* that grounds the implementer and reviewer — they
are not completion markers, and merge readiness is gated by FSM state and review
verdicts, not by checking off AC bullets. Operators reshape ACs with `hashd plan
{edit-ac, delete-ac, descope-ac, rescope-ac}`.

### Workstream

The execution of planned work on a dedicated branch and worktree. It holds the
micro-commit plan and execution state.

### Micro-commit

A focused unit in a workstream plan, processed by the implementation, test, and
review cycle.

### Project

A registered repository or repository group sharing Hashd configuration and planning.

### Project repo

A repository within a project, with role `primary`, `active`, `reference`, or `ignore`.

### Project artifacts

The configured project documents hashd reads and updates as work moves through the
system. The two core artifacts are REQS.md and SPEC.md. Inspect them with
`hashd project reqs` / `hashd project spec`; make guarded manual edits with
`hashd project reqs edit` / `hashd project spec edit`.

### REQS.md

The project's requirements source. Discovery reads it to create Suggestions, and
planning annotates active story scope with WIP markers. Treat text between
`BEGIN WIP` and `END WIP` markers as story-owned: `hashd project reqs edit` rejects
changes inside those sections so manual edits cannot clobber active planning
state.

### SPEC.md

The project or repo specification hashd grows after successful work. Direct merges
update SPEC.md from the story and resulting diff, then commit it with REQS cleanup.
Use `hashd project spec` to inspect the configured artifact and `hashd project spec edit`
for guarded manual corrections.

### Clarification

A durable question for human input during planning or implementation. It may be
blocking or non-blocking.

### Directive

Standing operator guidance injected into agent prompts at global, project, or
workstream scope, optionally restricted to stages.

## State model

Lifecycle position, execution condition, and substage are distinct.

### stage

The workstream's lifecycle position, currently stored as `status`.

### runtime_status

The current execution condition, derived by the server from workflow records
and liveness rather than stored independently.

### runner_stage

The current execution substage within the workstream's lifecycle stage.

## Process concepts

### Gate

A point in the lifecycle where work pauses for a verdict before it may proceed.
The governed loop has several: the **test gate** (configured tests must pass), the
**review gate** (the AI reviewer must approve, or request changes), the **human
review gate** (`awaiting_human_review`, where an operator approves/rejects/resets),
the **final-review gate** (a holistic branch review after all micro-commits land),
and the **merge gate** (merge-gate tests, conflict checks, and a secrets scan
before changes land). Whether a given gate auto-passes or stops for a human is
governed by the project's autonomy mode. See [how-hashd-works.md](how-hashd-works.md).

### Autonomy mode

The per-project setting that decides which gates stop for a human:
`supervised` (human approves every gate), `gatekeeper` (auto-continue commits when
review confidence clears a threshold, human approves merge — the default), and
`autonomous` (auto-continue commits and auto-merge when thresholds are met). All
three still block to a human on failures; the modes differ only in the merge-time
and per-commit gating.

### Dual-write event

The contract that every state change is written to two places: published to the **event bus**
for instant push to connected subscribers (TUI, Telegram, web), and logged to the
durable **SQLite events table** for catch-up by subscribers that were offline. the event bus
is ephemeral; SQLite is the durable source of truth. The events table is also the
spine of the audit trail. See [provenance.md](provenance.md).

### Attestation / lineage

**Lineage** is the chain that answers "why does this code exist?" — tracing a line
of code back through its commit, micro-commit, run, prompt, agent call,
workstream, story, requirement, reviews, and the human decisions that gated it.
`hashd lineage` walks the chain in either direction. An **attestation** is a
machine-readable export of that chain — `hashd lineage export` emits SLSA v1.0
provenance or an in-toto statement — and `hashd lineage verify` validates the
SHA-256 hash chain that links commit records. See [provenance.md](provenance.md)
and **[docs/LINEAGE.md](LINEAGE.md)**.

## Interfaces

### Dashboard

The home screen of the `hashd watch` TUI and hashd's navigation hub. It lists the
project's active Workstreams (selectable `1-9`) and Stories (selectable `a-i`),
and is the jumping-off point to the Plan screen (`p`), the autonomy-mode switch
(`m`), the command palette (`/`), and context-aware help (`?`). From the Dashboard
you drill into a Workstream Detail or Story Detail view and back. See
[watch.md](watch.md).

### Workstream Detail / Story Detail

The two drill-down views the Dashboard opens into. Workstream Detail is the
operator cockpit for a single in-flight Workstream — diff, log, review, timeline,
and the state-aware action keys (run, approve, reject, reset, replan, merge).
Story Detail is for shaping a Story before and during planning — approve, edit,
reshape acceptance criteria, and launch the Workstream. See
[watch.md](watch.md).
