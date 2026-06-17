# RAG: Project Knowledge Base

A vector-indexed knowledge base enabling semantic search across all project artifacts -- requirements, stories, specifications, clarifications, reviews, plans, conversations, implementation history, and timelines.

---

## Why RAG

The pair programmer chat has persistent conversation history, but no memory of what happened *outside* the chat -- what the reviews said, what clarifications were resolved, what the requirements evolved into, what the implementation logs contain. The agent answers questions from what's in its context window, which is a tiny slice of the project's full history.

RAG turns the entire project history into a searchable knowledge base. The agent can retrieve relevant context on demand, ask for more depth when a chunk looks promising, and synthesize answers from across the full lifecycle.

---

## Current Chat Architecture

RAG builds on top of the existing pair programmer chat system. This section summarizes the architecture that RAG extends.

### Vision

An AI pair programmer called in on-demand during any stage of the workflow. Unlike ephemeral clarification modals, this provides **persistent conversation context** tied to each story -- your buddy who knows the full history.

### Screen Integration

Chat is available from these screens with appropriate context:

| Screen | Context Level | Auto-Injected | Available via @ |
|--------|--------------|---------------|-----------------|
| DashboardScreen | Project | project info | @stories, @workstreams |
| DetailScreen | Workstream/Story | workstream, stage, story | @diff, @log, @review, @timeline, @clq |
| StoryDetailScreen | Story | story, criteria, questions | @transcript, @workstream (if linked) |
| PlanScreen | Project/Suggestion | project, selected suggestion | @reqs, @suggestion |

### @ Syntax for Context Injection

Type `@` in chat input to see available artifacts:

| Artifact | Description |
|----------|-------------|
| `@diff` | Current git diff |
| `@log` | Latest stage log |
| `@review` | Review feedback |
| `@timeline` | Story/workstream timeline |
| `@story` | Story details + criteria |
| `@file:path` | Specific file from worktree |
| `@clq` | Clarification history |
| `@reqs` | REQS.md content |
| `@spec` | SPEC.md content |
| `@commits` | Recent commit history |
| `@stories` | List of project stories |
| `@workstreams` | List of active workstreams |
| `@STORY-xxxx` | Cross-story reference |

`@file:path` is project-scoped. References must resolve inside the project
directory. Planning does not load file contents into prompts; it only preserves
the reference so agents can read reachable project files on demand. Paths
outside the project produce a planning-time warning and should be moved into
the project tree.

Visual feedback: header shows loaded context badges (`[story] [diff] [log]`), inline expansion shows `[diff loaded - 127 lines]`, already-loaded artifacts show `[already in context]`.

### Conversation Persistence

SQLite `chat_messages` table in `projects/{project}/hashd.db`:
- Columns: `id`, `project`, `story_id`, `role`, `content`, `context_type`, `created_at`
- `story_id IS NULL` for project-level chat, otherwise the story ID
- Ordered by `id ASC` (append-only)

### Agent Configuration

Claude in `--print` mode (read-only, with tools):
- Can read files, grep, explore codebase
- Cannot modify files (that's what the workflow is for)
- Configurable timeout (default 5 min for chat responses)

### System Prompt Role

Senior Software Architect / Tech Lead. Web search always enabled. Direct and concise. Proactively fetches context. Trusts file contents as authoritative.

### CLI Parity

```
wf chat                    # Auto-detect context (worktree -> workstream, else project)
wf chat STORY-0001         # Explicit story context
wf chat my-workstream      # Explicit workstream context
wf chat --new              # Start fresh
wf chat --history          # View past chat as markdown
```

---

## Industry Landscape

### How Others Do It

| Tool | Strategy | Vector DB | Chunking | Pre-indexed? |
|------|----------|-----------|----------|-------------|
| **Cursor** | Cloud RAG, tree-sitter AST | Turbopuffer | AST-based (100-500 tokens) | Yes (cloud) |
| **Continue.dev** | Local RAG, LanceDB | LanceDB | ~10-line blocks | Yes |
| **Roo Code** | tree-sitter + embeddings | Qdrant | AST (100-1000 chars) | Yes |
| **Aider** | tree-sitter repo map + PageRank | None | AST-based | Structural only |
| **OpenCode** | LSP + tool-based exploration | None | N/A | No |
| **Claude Code** | Agentic grep/glob | None | N/A | No |
| **Sourcegraph Cody** | BM25 + Semantic Graph | None (abandoned embeddings) | N/A | Yes |
| **CodeRabbit** | Full lifecycle RAG | LanceDB | Multi-artifact | Yes |

### Three Schools of Thought

1. **Agentic exploration** (Claude Code, OpenCode, Cline): No pre-indexing; the LLM uses tools to explore dynamically. Simple but token-expensive.

2. **Embedding-based RAG** (Continue, Roo Code, Cursor): Pre-index with vectors, retrieve semantically. Proven but requires infrastructure.

3. **Structural/graph-based** (Aider, Sourcegraph Cody): Build a code graph and use graph algorithms for retrieval. Best at capturing relationships.

4. **Keyword search** (SQLite FTS5, BM25): Full-text search over artifacts without embeddings. Zero new dependencies (FTS5 is built into SQLite), zero API cost, and for small corpora (~2,500 chunks of project artifacts) likely covers 80% of the semantic search use case. Sourcegraph Cody moved *toward* this (BM25) and *away* from pure embeddings. Worth considering as a first step before committing to vector infrastructure -- see [RAG2.md](RAG2.md) for full analysis.

### Key Lessons

- **Tree-sitter is ubiquitous** for code chunking. Every tool that does structural code analysis uses it.
- **Hybrid retrieval wins**: BM25 + vector search + reranking consistently outperforms either alone. BM25 is essential for code (exact identifiers, function names, error strings).
- **Single store, category metadata**: One vector store with a `content_type` field for filtering beats separate stores per artifact type.
- **Reranking is the highest-impact improvement** for RAG quality after getting basic retrieval working.
- **Content-hash dedup** is the standard pattern for incremental indexing.
- **Sourcegraph abandoned pure embeddings** for enterprise. The trend is toward hybrid approaches.
- **Memory != context window**: Large context windows help within a session, but memory enables intelligence across sessions. Memory layers cut token costs ~90%.

---

## Architecture

### Storage

One SQLite database per project: `projects/<name>/knowledge.db`

Source files (JSONL, markdown, logs) remain the source of truth. The database is a rebuildable index.

```sql
CREATE TABLE chunks (
    id INTEGER PRIMARY KEY,
    category TEXT NOT NULL,
    source_file TEXT NOT NULL,   -- relative path from ops_dir
    line_start INTEGER,
    line_end INTEGER,
    entity_id TEXT,              -- STORY-0001, ws-auth, project name
    timestamp TEXT,
    content TEXT NOT NULL,       -- chunk text (for display in results)
    content_hash TEXT NOT NULL,  -- SHA256 for dedup + staleness
    token_count INTEGER,
    embedding_model TEXT         -- track which model generated the embedding
);

CREATE VIRTUAL TABLE chunks_vec USING vec0(
    embedding float[1536]
);

CREATE INDEX idx_chunks_category ON chunks(category);
CREATE INDEX idx_chunks_entity ON chunks(entity_id);
CREATE INDEX idx_chunks_hash ON chunks(content_hash);
```

### Categories

| Category | Source Files | Chunk Unit | When Indexed |
|----------|-------------|------------|--------------|
| `requirement` | `REQS.md` | Per requirement section (markdown header) | On change |
| `story` | `STORY-xxxx.md` | Title+problem, each AC, non-goals, open questions | Create, edit |
| `specification` | `SPEC.md` | Per section (markdown header) | On change |
| `clarification` | `resolved/*.md` | Per Q+A pair | When resolved |
| `plan` | `workstreams.plan` (DB) | Per commit spec | On breakdown |
| `review` | `reviews` table, `final_review.md` | Per file/concern section | When generated |
| `implementation` | Stage logs | Per stage output (summarized if large) | On stage completion |
| `conversation` | `chat_messages` table | Per conversation turn (user + assistant pair) | On each message |
| `timeline` | `transcript.md`, `events.jsonl` | Per event/record | On append |

### Chunking Strategy

Two separate pipelines, following industry best practice:

**For structured documents** (markdown: REQS, stories, specs, reviews, plans):
- Split on markdown headers (structure-aware)
- ~400-512 tokens per chunk with ~10% overlap at boundaries
- Preserve section hierarchy in metadata

**For conversation history** (JSONL chat files):
- One chunk per conversation turn (user message + assistant response)
- Natural semantic boundary -- a question and its answer form a coherent unit
- Timestamp preserved for temporal queries

**For logs and events** (stage logs, transcripts, events):
- Per-event or per-stage-output
- Large logs (>2000 tokens): summarize before embedding, store summary as chunk, keep pointer to full log
- Events: one chunk per event entry

### Embedding Model

**Default: OpenAI `text-embedding-3-small`**
- 1536 dimensions, 8191 token context
- $0.02/1M tokens standard, $0.01/1M tokens batch API (50% off)
- 95% retrieval quality of best-in-class models at lowest cost
- Supports Matryoshka dimension reduction (can truncate to 512 dims for storage savings)

**Alternative considered**: Voyage `voyage-code-3` is 13.8% better for pure code retrieval but 3x the cost and less general for mixed code+docs content. Upgrade path if code search quality becomes a bottleneck.

**Cost estimate** for a typical project (~10K source files, ~500 tokens avg):
- Full index: ~$0.10 (standard) / ~$0.05 (batch)
- Daily incremental (10% changed): ~$0.01
- Monthly: ~$0.30

### sqlite-vec Characteristics

- **Pure C, no dependencies**, ships as a pip wheel (`pip install sqlite-vec`)
- Brute-force KNN (no ANN indexes yet -- planned for v1.0)
- **Performance sweet spot**: up to ~100K-500K vectors
- Binary quantization available (32x storage reduction, ~95% accuracy retention)

| Scale | Query Time (1536-dim, float32) |
|-------|-------------------------------|
| 10K vectors | <10ms |
| 100K vectors | ~68ms |
| 500K vectors | ~300ms (estimated) |

For our use case (project artifacts, not a full codebase index), we're comfortably in the 10K-100K range. A large project might have: ~100 stories x 5 chunks + ~50 reviews x 10 chunks + ~1000 chat turns + ~500 events = ~2500 chunks. Well within sqlite-vec's sweet spot.

---

## Agent Integration

### Two-Stage Retrieval

1. **Vector search** returns top N chunks with category, source file, line offsets, and content snippets
2. **Agent decides** if it needs more depth from any source and uses tools to fetch it

The agent is not just a consumer of RAG results -- it's an active participant that can go deeper.

### Agent Tools

The pair programmer agent gets retrieval tools alongside its existing read-only tools:

```
search(query, category=None, entity_id=None, limit=10)
    -- Filtered vector search. Returns chunks with metadata.
    -- category: filter to specific artifact type
    -- entity_id: filter to specific story/workstream

read_more(source_file, line_start, line_end)
    -- Pull more context from a source file around a chunk.
    -- Used when a chunk looks relevant but needs surrounding context.
```

### Stage Configuration

Search is a configurable stage like other stages (`stages.yaml`):

```yaml
recall:
  command: "claude -p --output-format json"
  timeout: 60
```

Overridable per-project via `agents.yaml` -- can swap Claude for Codex or Grok for the ranking/synthesis step.

### Interaction Model

Three modes, from most to least explicit:

1. **Explicit**: User types `@recall:topic` to trigger a search. Results injected as context artifact.
2. **Agent-initiated**: Agent sees the user's question, decides it needs historical context, calls `search()` tool on its own.
3. **Proactive**: On chat open, auto-inject relevant context based on current story/workstream state (extends existing auto-inject pattern).

Start with (1) and (2). Mode (3) can be added once the index is populated and we understand usage patterns.

---

## Indexing Pipeline

### Incremental Indexing (On Write)

Hook into existing write paths to index content as it's created:

```
session.add_user_message()      --> index conversation turn
session.add_assistant_message() --> index conversation turn
create_story() / update_story() --> index story chunks
stage completion                --> index review/log
clarification resolved          --> index Q+A pair
```

Each hook:
1. Chunk the new content
2. SHA256 hash each chunk
3. Check if hash already exists in DB (skip if so)
4. Call OpenAI embeddings API
5. Insert chunk + embedding

### Full Rebuild

`wf index` command: crawl all source files, chunk everything, diff against stored hashes, embed only new/changed content.

```
wf index              -- full rebuild (skips unchanged via content hash)
wf index status       -- show what's indexed, counts per category
wf index clear        -- drop and rebuild from scratch
```

### Staleness Detection

- Content hash comparison on rebuild catches modified content
- `embedding_model` column detects model version changes (triggers re-embed)
- Deleted source files: on rebuild, remove chunks whose source_file no longer exists

---

## Dependencies

```toml
[project.optional-dependencies]
rag = ["sqlite-vec>=0.1.6", "openai>=1.0"]
```

Installed via `uv sync --extra rag`. The entire RAG feature is optional -- chat works without it, just without semantic search.

### Runtime Detection

```python
def is_rag_available() -> bool:
    """Check if RAG dependencies are installed and configured."""
    try:
        import sqlite_vec
        import openai
    except ImportError:
        return False
    # Check for API key
    return bool(os.environ.get("OPENAI_API_KEY") or _load_key_from_secrets())
```

All RAG-dependent code paths check this before attempting to use the knowledge base.

---

## Setup

### setup.sh Addition

```
=== Optional: Knowledge Base (RAG) ===

Semantic search across project history (stories, reviews, conversations, etc.)
Requires: OpenAI API key for embeddings ($0.02/1M tokens)

Enable knowledge base? [y/N]: y

Checking for OPENAI_API_KEY...
  [Found in environment]          -- or --
  [Not found]
  Enter your OpenAI API key: sk-...
  Saved to secrets/openai_api_key

Installing dependencies...
  uv sync --extra rag

Verifying...
  sqlite-vec v0.1.6 ... OK
  OpenAI embeddings ... OK (text-embedding-3-small)

Knowledge base enabled.
Run 'wf index' after project setup to build the initial index.
```

### API Key Storage

- Check `OPENAI_API_KEY` environment variable first
- Fall back to `secrets/openai_api_key` file (directory already exists, gitignored)
- Never store in config files that might be committed

---

## Implementation Plan

### Phase 0: Project Context in All Prompts (Complete)

Every agent now receives `system_description` via `project_config.system_description` (falls back to `"Project: {name}"` when description is blank).

**Tasks:**

| # | Task | Status |
|---|------|--------|
| 0a | Add `{system_description}` to all top-level reasoning prompts | Done -- 9 prompts updated (`breakdown`, `fix_generation`, `final_review`, `plan_discovery`, `refine_story`, `edit_story`, `conflict_resolution`, `plan_add`, `pair_programmer`) |
| 0b | Wire `system_description` through all render_prompt call sites | Done -- 10 call sites wired (`breakdown.py`, `stages.py`, `fix_generation.py`, `merge_gate.py`, `review.py`, `merge.py`, `plan.py`, `planner.py` x3, `claude_invoke.py`) |
| 0c | Add `system_description` to `pair_programmer.md` | Done -- receives both `project_name` and `system_description` |
| 0d | Validate during `wf project interview` that description is non-empty; warn if blank | Open |

**Intentionally skipped:** `implement_retry.md`, `directives_edit.md` (utility prompt, not reasoning about the codebase), sub-section templates (`implement_review_context`, `review_history`).

#### Description Drift Detection

Project descriptions go stale. REQS.md grows, SPEC.md evolves, but the description stays frozen from `wf project interview`. We should detect this and prompt for realignment.

**When:** During `wf plan` (discovery), before generating suggestions. This is the natural checkpoint -- the user is already thinking about the project's direction.

**How:**
1. Hash REQS.md and SPEC.md content, store in `project.env` as `REQS_HASH` / `SPEC_HASH`
2. On `wf plan`, compare current hashes to stored hashes
3. If significant change detected (hash mismatch + content delta > threshold), prompt:

```
REQS.md and/or SPEC.md have changed significantly since the project
description was last reviewed.

Current description:
  "A fitness tracking API with social features and workout plans"

Want us to re-analyze and propose an updated description? [y/N]: y

Analyzing REQS.md and SPEC.md...

Proposed description:
  "A fitness tracking API with social features, workout plans,
   and real-time activity feeds with push notifications"

  [a]ccept  [e]dit  [k]eep current: _
```

**What it should NOT do:**
- Trigger during `wf run` or any automated pipeline stage -- only during interactive planning
- Trigger on every small REQS edit -- needs a meaningful change threshold (e.g., >20% content delta or new sections added)
- Block the user -- always skippable

**Tasks:**

| # | Task | Files |
|---|------|-------|
| 0e | Store REQS/SPEC content hashes in `project.env` | `orchestrator/lib/config.py` |
| 0f | Change detection logic: hash comparison + content delta threshold | `orchestrator/lib/description_drift.py` |
| 0g | Re-analysis prompt: send current description + REQS + SPEC to agent, get proposed update | `prompts/description_review.md` |
| 0h | Interactive prompt in `cmd_plan_discover()`: show old/new, accept/edit/keep | `orchestrator/commands/plan.py` |
| 0i | Update hashes after user accepts/keeps | `orchestrator/lib/description_drift.py` |

### Phase 1: Infrastructure

| # | Task | Files |
|---|------|-------|
| 1 | Add `rag` optional dependency group | `pyproject.toml` |
| 2 | RAG setup section in setup.sh | `setup.sh` |
| 3 | `KnowledgeBase` class: init DB, create tables, insert, search, delete | `orchestrator/lib/knowledge.py` |
| 4 | Embedding client: OpenAI API wrapper, batch support, error handling | `orchestrator/lib/embeddings.py` |
| 5 | `is_rag_available()` detection + API key loading | `orchestrator/lib/knowledge.py` |
| 6 | Tests for KnowledgeBase (insert, search, dedup, category filter) | `tests/test_knowledge.py` |

### Phase 2: Indexing

| # | Task | Files |
|---|------|-------|
| 7 | Chunkers: markdown section splitter, JSONL turn splitter, event splitter | `orchestrator/lib/indexer.py` |
| 8 | `wf index` CLI command (full rebuild with progress) | `orchestrator/commands/index.py`, `orchestrator/cli.py` |
| 9 | `wf index status` and `wf index clear` subcommands | `orchestrator/commands/index.py` |
| 10 | Incremental hooks: chat session write path | `orchestrator/lib/chat_session.py` |
| 11 | Incremental hooks: story create/update | `orchestrator/pm/stories.py` |
| 12 | Incremental hooks: stage completion (reviews, logs) | `orchestrator/runner/impl/stages.py` |

### Phase 3: Search Integration

| # | Task | Files |
|---|------|-------|
| 13 | Add `recall` stage to stages.yaml | `orchestrator/lib/stages.yaml` |
| 14 | `@recall:topic` artifact handler in chat context | `orchestrator/lib/chat_context.py` |
| 15 | Agent tools: `search()`, `read_more()` | `orchestrator/lib/chat_context.py` |
| 16 | Prompt template for recall/search | `prompts/recall.md` |
| 17 | Update pair programmer system prompt with tool definitions | `prompts/pair_programmer.md` |
| 18 | TUI: non-blocking search (background worker, interruptible) | `packages/hashd-tui/src/hashd_tui/watch/chat.py` |

### Phase 4: Context Window Management

These items depend on or are superseded by the RAG knowledge base.

#### Large Artifact Retrieval

Currently, large files load fully with a size warning. The original design envisioned spawning a subagent to retrieve relevant portions of large files.

RAG supersedes this: the agent's `read_more(source_file, line_start, line_end)` tool lets it selectively fetch portions of any source file. For `@file:path` artifacts specifically, instead of loading the entire file into context, the system can load a summary chunk and let the agent pull more via tools.

| # | Task | Files |
|---|------|-------|
| 19 | For `@file:path` artifacts exceeding size threshold, load a truncated preview + hint to agent that `read_more()` is available | `orchestrator/lib/chat_context.py` |

#### Context Window Summarization

Original design specified: when approaching context limits, summarize old messages but keep all @-loaded artifacts, last 10 message pairs, and a summary of earlier discussion.

With RAG, the approach changes: instead of summarizing old messages in-place, keep recent messages in context and let the agent retrieve older discussions via `search()`. This is more precise (retrieves by relevance, not recency) and cheaper (no summarization LLM call).

| # | Task | Files |
|---|------|-------|
| 20 | Token counting for chat history (track cumulative tokens in session) | `orchestrator/lib/chat_session.py` |
| 21 | When history exceeds threshold, trim old messages from API context but keep them in JSONL (they're indexed in RAG) | `orchestrator/lib/chat_session.py` |
| 22 | Add note to system prompt: "Older conversation history is available via search() tool" | `prompts/pair_programmer.md` |

#### Prompt Cache Optimization

Original design specified: structure prompts so static context (story, criteria) is at the top for Claude's cache prefix matching.

This interacts with RAG because the prompt structure changes -- RAG-retrieved chunks are dynamic and should go after static context to maximize cache hits.

| # | Task | Files |
|---|------|-------|
| 23 | Structure prompt with static prefix (system prompt, story context) then dynamic suffix (RAG results, recent messages) | `orchestrator/lib/chat_context.py`, `prompts/pair_programmer.md` |
| 24 | Measure cache hit rates before/after optimization | Manual verification |

### Future: Enhancements

- **Hybrid retrieval**: Add BM25 keyword search alongside vector search, fuse with Reciprocal Rank Fusion
- **Reranking**: Cross-encoder reranker for precision on top of initial retrieval
- **Proactive injection**: Auto-inject relevant history on chat open based on current context
- **Cross-project search**: Search across multiple projects
- **Binary quantization**: Enable for storage/speed optimization at scale
- **Dimension reduction**: Truncate to 512 dims via Matryoshka if storage becomes a concern
- **Alternative embeddings**: Support voyage-code-3 for better code retrieval, or local models for offline use
- **Semgrep as a pre-review stage**: Run `semgrep --config auto --json` on the worktree after tests pass, before Claude reviews. Semgrep is AST-based static analysis (free, open source, 30+ languages, 2,000+ security rules). It catches mechanical security issues (SQL injection, XSS, secrets in code) deterministically -- the exact class of bugs Claude is weakest at. Pass findings into the review prompt so Claude gets structured security context alongside the diff. Integration cost: one dependency (`pip install semgrep`), ~50-100 lines in stages.py. See [RAG2.md](RAG2.md) for competitive context (IBM Bob bundles Semgrep inline).

---

## Open Design Questions

1. **Large stage logs**: Summarize before embedding (extra LLM call), or just skip logs over a threshold? Logs can be thousands of lines but often contain the most valuable debugging context.

2. **Cross-story search scope**: Default to current story only, or always search project-wide? Project-wide finds more but may surface irrelevant noise from unrelated stories.

3. **Cost visibility**: Should `wf index status` show cumulative embedding costs? Or is this over-engineering for ~$0.30/month?

4. **Proactive vs explicit**: Should the agent automatically search the knowledge base when it thinks it needs context, or only when the user explicitly asks via `@recall`? Agent-initiated is more powerful but less predictable.

---

## References

### Architecture
- [How Cursor Indexes Codebases Fast](https://read.engineerscodex.com/p/how-cursor-indexes-codebases-fast) -- Merkle tree change detection, AST chunking, Turbopuffer
- [Cursor scales to 100B+ vectors with Turbopuffer](https://turbopuffer.com/customers/cursor) -- namespace-per-codebase, cold/warm tiering
- [How Cursor Works](https://blog.sshh.io/p/how-cursor-ai-ide-works) -- full architecture deep dive

### RAG Best Practices
- [AST-Based Code Chunking (cAST)](https://arxiv.org/html/2506.15655v1) -- tree-sitter chunking outperforms fixed-size by 1.8-4.3 points
- [Optimizing RAG with Hybrid Search & Reranking](https://superlinked.com/vectorhub/articles/optimizing-rag-with-hybrid-search-reranking) -- BM25 + vector + RRF + reranking pipeline
- [Breaking Up is Hard to Do: Chunking in RAG](https://stackoverflow.blog/2024/12/27/breaking-up-is-hard-to-do-chunking-in-rag-applications/) -- comprehensive chunking strategy guide

### Embedding Models
- [Voyage Code 3 Announcement](https://blog.voyageai.com/2024/12/04/voyage-code-3/) -- best-in-class code embeddings
- [6 Best Code Embedding Models Compared](https://modal.com/blog/6-best-code-embedding-models-compared) -- benchmarks across models

### Memory Systems
- [Mem0 Paper](https://arxiv.org/abs/2504.19413) -- vector + graph memory, 26% improvement over baselines
- [Letta Memory Architecture](https://docs.letta.com/guides/agents/memory/) -- tiered memory (core + archival), agent-managed

### Tools
- [sqlite-vec v0.1.0](https://alexgarcia.xyz/blog/2024/sqlite-vec-stable-release/index.html) -- performance benchmarks, limitations
- [sqlite-vec Python docs](https://alexgarcia.xyz/sqlite-vec/python.html) -- API reference
- [OpenAI Batch API](https://platform.openai.com/docs/guides/batch) -- 50% cost reduction for indexing

### Project Context
- [CodeRabbit + LanceDB](https://lancedb.com/blog/case-study-coderabbit/) -- full lifecycle RAG for code review
- [GitHub Copilot Spaces](https://github.blog/ai-and-ml/github-copilot/github-copilot-spaces-bring-the-right-context-to-every-suggestion/) -- curated context bundles
- [Continue.dev Semantic Code History Search](https://blog.continue.dev/building-a-semantic-code-history-search-with-lancedb/) -- git blame + embeddings
- [Aider Repository Map](https://aider.chat/docs/repomap.html) -- tree-sitter + PageRank, no embeddings
