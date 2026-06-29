# Provenance and audit

This is hashd's sharpest differentiator: a complete, queryable, exportable, and
tamper-evident record of *why every line of merged code exists*. Generation-only
spec tools stop at producing code; hashd records the full decision chain that
produced it and lets you audit it after the fact.

This page is the operator-facing overview. For the full design — schema, query
internals, the standards landscape, and the competitive analysis — see
**[docs/LINEAGE.md](LINEAGE.md)**. For the concepts in context, see
[how-hashd-works.md](how-hashd-works.md); for terms, see [glossary.md](glossary.md).

## Why this matters

`git blame` answers "who changed this line and when." For AI-generated code, that
isn't enough. The real questions are: *what requirement motivated this line, what
prompt produced it, what model generated it, what review approved it, and what
human decisions shaped it?*

hashd answers all of them because it **owns the whole pipeline**. A tool that hooks
the commit event captures the agent session but lacks the upstream context (why was
the agent invoked?) and the downstream context (what did the reviewer conclude? did
a human approve?). hashd doesn't infer the chain — it *defines* it as work flows
through the governed loop.

This is the foundation of hashd's enterprise framing. The "enterprise-grade" claim
rides entirely on auditability, traceability, and governance — not on multi-user
features (hashd is single-operator today). What makes AI-generated code shippable
in a regulated or high-assurance setting is exactly this: requirements
traceability, an immutable record of who authorized what and why, and a verifiable
provenance export.

## The chain

Every merged line traces back through:

```text
line of code -> git commit -> micro-commit -> run -> prompt + agent call
  -> workstream -> story -> requirement -> reviews + human decisions
```

Each link is a real, recorded relationship in SQLite, not a heuristic:

| Link | Where it's recorded |
|------|---------------------|
| Requirement -> Story | story's frozen source-requirement text + origin |
| Story -> Workstream | `workstreams.story_id` |
| Workstream -> plan/breakdown | `workstreams.plan` (the micro-commit list) |
| plan -> prompt | `events` (prompt template + rendered text) |
| prompt -> agent call | `agent_calls` + `events` (model, tokens, duration) |
| agent call -> commit | `commits.sha` -> `commits.run_id` |
| commit -> review | `reviews` (decision, confidence, blockers) |
| review -> human decision | `events` (approval/rejection + reason) |
| clarification history | `clarifications` (question + answer) |
| cross-commit patterns | final review spans all commits |

## Querying lineage: `hashd lineage`

`hashd lineage <target>` walks the chain in either direction. The target type is
auto-detected:

- `STORY-NNN` / `BUG-NNN` -> everything produced by that story;
- 7-40 hex chars -> the full chain for that commit;
- anything else -> a file path.

```bash
hashd lineage STORY-0012                 # all commits, reviews, decisions for a story
hashd lineage a1b2c3d                     # full chain for one commit
hashd lineage src/auth/jwt.go             # all commits touching a file
hashd lineage src/auth/jwt.go --lines 42-58   # lineage for specific lines (git blame)
```

A commit query reads like a lab notebook entry — the story it served, the
requirement it fulfilled, the run and prompt that produced it, the review verdict
and confidence, and the human decision:

```text
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

Output formats: `--format table` (default), `--format json` (for `jq` / tooling),
`--format markdown` (for pasting into PRs or reports). In the TUI, the **Lineage
view** (`I` in diff mode) traces a selected line interactively.

## Exporting attestations: `hashd lineage export`

For supply-chain compliance, export the chain as a standard, machine-readable
attestation:

```bash
hashd lineage export <sha> --format slsa      # in-toto Statement, SLSA v1.0 provenance predicate
hashd lineage export <sha> --format in-toto   # in-toto Statement, hashd predicate
hashd lineage export STORY-0012 --format slsa # array of attestations, one per commit
```

- **SLSA** export emits an in-toto Statement carrying a SLSA v1.0 provenance
  predicate (`buildType: https://hashd.ai/provenance/v1`), with the story,
  micro-commit, requirement, and origin as external parameters and the run id as
  the invocation id.
- **in-toto** export carries the full hashd predicate
  (`https://hashd.ai/provenance/v1`): the commit row, story summary, review
  decisions and confidence, human decisions, and agent calls (model, tokens,
  duration) — plus a `chain` section with `prev_hash` and `record_hash` for
  verifiability.

## Tamper evidence: `hashd lineage verify`

Commit records are linked into a hash chain: each record stores a `prev_hash` —
the SHA-256 of the previous record's canonical JSON (sorted keys, compact
separators). The first commit for a project is the genesis record with no
predecessor.

```bash
hashd lineage verify   # exit 0 if the chain is intact, 1 if broken
```

`verify` walks the chain and reports total / verified / breaks. It tolerates legacy
pre-hash-chain segments and fails when a link is missing, duplicated, cyclic, or
mismatched — i.e. when a record was altered or removed after the fact.

## The durable event log underneath it all

Lineage is possible because hashd already records everything as it happens. Every
state change is **dual-written**: pushed over ZMQ for live consumers and persisted
to the SQLite **events table** as the durable record. The events table is the spine
of the audit trail — it captures every prompt, response, stage start/end, and human
decision, tagged with project, story, workstream, run, micro-commit, stage, and
actor. Agent calls (`agent_calls`), review decisions (`reviews`), and run lifecycle
(`runs`) round out the structured record. Because all of this is captured by the
pipeline rather than reconstructed afterward, the chain is complete by construction.

See [how-hashd-works.md](how-hashd-works.md#the-dual-write-event-log) for the
dual-write contract and [glossary.md](glossary.md) for the entity definitions.

## What's not (yet) here

Per **PRD.md** "Deferred or not shipped": cryptographic *signing* of
attestation exports (Sigstore/Cosign) and a Rekor-style transparency log are not
shipped. The hash chain provides tamper *evidence*; keyless signing is a future
option. The export formats (SLSA, in-toto) and the verifiable hash chain are
shipped today.
