# RAG Reality Check

An honest assessment of RAG.md against the current state of the project, the competitive landscape, and where context improvements would have the most impact.

---

## Phase 0 is gold. Ship it tomorrow.

Getting `system_description` into the 13 prompts that currently operate blind is the single highest-ROI item on the entire RAG document. Every agent immediately knows what the project is. Zero new dependencies. A few hours of work. This alone will visibly improve breakdown, review, and planning quality.

---

## The RAG plan is overengineered for the problem it solves

RAG.md is solving: *"the pair programmer chat doesn't know what happened outside the chat."*

But the pair programmer chat is a **human convenience tool**. It's not on the critical path of the automated pipeline. The agents that actually do work -- breakdown, implement, review, fix generation -- get their context from the orchestrator's prompt assembly, not from RAG. Building a vector search pipeline to help the human ask better questions in chat is real value, but it's not the force multiplier.

The plan calls for:
- 24 implementation tasks across 4 phases
- A new OpenAI API dependency (just for embeddings, when everything else is Claude + Codex)
- Incremental indexing hooks invasively wired into 4 subsystems (chat_session, stories, stages, plan)
- An embedding pipeline, vector DB, two-stage retrieval, context window management

All for ~2,500 chunks. At that scale, **SQLite FTS5 (full-text search) would get you 80% of the value with zero new dependencies and zero API cost.** FTS5 is built into SQLite. Keyword search over project artifacts -- stories, reviews, clarifications, chat history -- works fine when the corpus is small and the vocabulary is domain-specific.

The honest math: ~34k LOC, 6 dependencies, and a small team. Adding an embedding pipeline that touches 4 subsystems is a maintenance surface area expansion you'll feel every time you refactor anything.

---

## The @ syntax already solves most of this

The existing chat system provides 14 artifact types the user can inject on demand:

```
@diff @log @review @story @timeline @clq @reqs @spec
@commits @stories @workstreams @STORY-xxxx @BUG-xxxx @file:path
```

`@file:path` is scoped to files inside the project directory. Planning preserves
the reference as metadata and warns on outside-project paths instead of loading
file contents into the prompt.

The "missing memory" problem is really "the user doesn't always know which artifact to pull." RAG's answer is semantic search. A simpler answer: **surface what's available more aggressively.** When the user opens chat on a workstream, show a one-line summary of what happened since their last chat. That's a query against the existing JSONL files, not a vector search.

---

## The instinct is better than the spec

The right sequence: *start with requirements and transcripts, leave agents to grep/glob, slowly add tree-sitter maps.*

RAG.md jumps to embeddings before proving that keyword search over artifacts isn't enough. And it focuses on the chat pair programmer when the bigger lever is the **pipeline agents**.

---

## Where the real context gap hurts

The agents that would benefit most from better context aren't the pair programmer -- they're:

1. **Breakdown agent** -- decomposes stories into micro-commits. Needs to understand existing code structure to make realistic commit plans. Currently gets the story + ACs but no codebase map.

2. **Review agent** -- reviews implementation. Gets the diff but limited broader context about *why* things are the way they are (past review decisions, related stories, architectural choices).

3. **Fix generation agent** -- generates fix commits after test failures or review rejections. Needs to understand what was already tried (oscillation detection hints at this problem).

These agents would benefit more from a **compact codebase structural summary** (tree-sitter maps) and **relevant prior decisions** (past reviews, resolved clarifications) injected into their prompts. That's not RAG -- that's better prompt assembly.

---

## Recommended sequence

### 1. ~~Ship Phase 0 now~~ (Done)
`system_description` wired into all 9 top-level reasoning prompts and 10 call sites. Continuation prompts and sub-section templates intentionally skipped (agent already has context). Only remaining item: validate non-empty description during `wf project interview`.

### 2. Add FTS5 search over artifacts instead of vector search
Same schema minus the embedding columns. `wf search "authentication flow"` returns matching chunks from stories, reviews, clarifications, chat history. New dependencies: zero. Cost: zero. Covers 80% of the "project memory" use case.

### 3. Improve prompt assembly for pipeline agents
When the review agent runs, include the 2-3 most recent review decisions and any resolved clarifications for this workstream. When breakdown runs, include a summary of the codebase structure (even just a file tree with line counts is better than nothing). This is deterministic context injection, not retrieval.

### 4. Tree-sitter structural maps when ready
Start with one language (whatever the main project uses). Generate a compact summary: module -> classes -> public methods with signatures. Feed it to breakdown and review agents. This is Aider's insight without Aider's 108-dependency burden -- no need to support 100 languages because you control which projects run through hashd.

### 5. Vector embeddings if and when FTS5 proves insufficient
You'll know because users will search for concepts ("that time we decided to use JWT instead of sessions") and get nothing back from keyword search. That's when embeddings earn their keep.

---

## Context: competitive landscape

### How others handle codebase context

| Tool | Strategy | Dependencies | What it indexes |
|------|----------|-------------|-----------------|
| **Aider** | Tree-sitter + PageRank repo map | 108 deps, no vector DB | Code structure only (AST) |
| **Goose** | MCP extensions, agentic exploration | Variable via extensions | Nothing pre-indexed |
| **Claude Code** | Agentic grep/glob | None | Nothing pre-indexed |
| **Cursor** | Cloud RAG, tree-sitter AST chunking | Turbopuffer (cloud) | Full codebase |
| **Continue.dev** | Local RAG, LanceDB | LanceDB, embeddings | Code + docs |

Aider's repo map uses 4-6% of the context window vs 54-70% for agent-based search. But Aider invested ~20k LOC and 108 dependencies to support 100+ languages. The sweet spot for hashd is a single-language tree-sitter map fed to the agents that need structural awareness (breakdown, review), not a universal code indexer.

### Key insight from Aider

Code has *explicit structure* (imports, call graphs, class hierarchies) that is more reliable for determining relevance than semantic similarity of text embeddings. For project artifacts (stories, reviews, conversations), the opposite is true -- semantic search adds value because the vocabulary is less structured. This argues for:
- **Structural analysis** (tree-sitter) for code context
- **Text search** (FTS5, then embeddings if needed) for project artifacts
- **Not** mixing them into one system prematurely

---

## The bottom line

RAG.md is a well-researched design doc that solves a researched problem rather than a felt problem. The pair programmer chat isn't where users are blocked today -- getting reliable, high-quality automated implementation cycles is. Every hour spent on embedding infrastructure is an hour not spent on making the core loop tighter: better breakdowns, better reviews, fewer oscillation loops, smarter fix generation.

The tree-sitter instinct is the right one. A structural map of the codebase fed to the breakdown agent would directly reduce the "Codex implements something unrealistic and wastes a cycle" failure mode. That's on the critical path. RAG for chat is not.
