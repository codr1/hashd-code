> Status: HISTORICAL. Phase 1 shipped; Phases 2-5 are superseded by
> ../../../DAS_PLAN.md.
>
> Non-goals folded into ../../../PRD.md.
> Research compendium preserved here for reference.
>
> Active tracking: see ../../../DAS_PLAN.md for the current state of context
> delivery, tree-sitter integration, code graph access, search, and related work.

# MVP.md -- Context Graph: From Research to Roadmap

## Business Goal

Make HASHD's agents faster, cheaper, and more accurate by giving them the right context at the right time. Every wasted exploration cycle is a wasted dollar. Every hallucinated file path is a failed run. Every review that misses a spec violation is a human intervention.

**The measurable wins we're after:**

1. **Fewer wasted cycles.** Breakdown agent proposes realistic commit plans on the first try because it knows the codebase structure.
2. **Grounded reviews.** Review agent checks implementation against acceptance criteria, not just code quality in a vacuum.
3. **Cheaper runs.** Agents spend 4-6% of context window on orientation, not 54-70%.
4. **Cross-artifact memory.** "What did we decide about auth?" returns an answer from clarifications, reviews, and chat history -- for both humans and agents.

---

## What the Research Actually Says

Before building anything, here are the findings that should constrain our design. Some of these challenge assumptions we've been making.

### More context hurts -- even with perfect retrieval

Du et al. (EMNLP 2025 Findings): Even when all relevant information is present and identifiable, performance degrades 13.9-85% as input length increases. This persists even when irrelevant tokens are replaced with whitespace. The degradation is in the attention mechanism itself, not retrieval noise.

**Implication:** Stuffing the context window is actively harmful. Every token we inject must earn its place. The Context Graph must be a compression, not an expansion.

### Signatures are nearly as good as full code

Zhang et al. (AAAI 2025, HCP): Pruning function bodies in non-current files does NOT significantly reduce accuracy. Signatures + structure are enough. 4 layers of import dependencies sufficient for most scenarios.

**Implication:** The structural map should be signatures and relationships, not code. This validates Aider's approach (compact map, not full files).

### Similar code snippets hurt (-15%)

Gu et al. (ICSE 2026, AllianceCoder): In-context code (local imports, current file) and API information help. Similar code snippets from elsewhere in the repo actively degrade results by up to 15%.

**Implication:** Do NOT retrieve "similar" functions as examples. Retrieve structural information (what exists, what depends on what) and API contracts. This is the opposite of what naive RAG would do.

### Hybrid retrieval wins, but 80% of the time retrieval doesn't help at all

RepoFormer (ICML 2024): 80% of the time, retrieval does not improve code generation. Knowing when NOT to retrieve is as important as retrieval quality. Citation-grounded study (Dec 2025): Hybrid BM25 + dense + graph achieves 92% citation accuracy vs 74-78% for either alone.

**Implication:** FTS5 is fine for the 20% of cases where search helps. Embeddings can wait. But the biggest lever is deterministic injection of known-relevant context, not search.

### Deterministic AST graphs crush LLM-extracted graphs

Chinthareddy (Jan 2026): Deterministic AST-derived knowledge base (tree-sitter) vs LLM-extracted knowledge graph: 95.6% vs 84.4% correctness, 40-71x faster, 20-46x cheaper, 90-99% vs 63-71% corpus coverage.

**Implication:** Build the code graph deterministically with tree-sitter. Do not use LLMs to infer code structure. LLMs are for reasoning about the structure, not discovering it.

### BM25 dominates for code-to-code; embeddings win for NL-to-code

Galimzyanov (NeurIPS 2025): BM25 with word splitting outperforms dense retrievers by ~10 percentage points on code-to-code retrieval. Dense embeddings win for natural language to code by ~15 points NDCG. BM25 is 200x faster.

**Implication:** FTS5 (which is BM25-family) is the right first step for code search. Embeddings earn their keep when humans ask conceptual questions ("how did we handle auth?"), not when agents look up specific functions.

### Interface design matters as much as model capability

SWE-agent (Princeton, NeurIPS 2024): 100-line mini-SWE-agent matches the full SWE-agent on SWE-bench. Purpose-built tool interfaces for LLMs matter more than elaborate RAG pipelines.

**Implication:** How we present context to agents (prompt structure, tool design) is as important as what context we provide. Don't over-engineer retrieval and under-engineer prompt assembly.

---

## What We Have Today (Agent Context Audit)

| Agent | Context Quality | Key Gaps |
|-------|----------------|----------|
| **implement** | Good | Has codebase dir structure, directives, review history, human feedback. Missing: clarifications, test expectations |
| **review** | Medium | Has story context, diff, tech prefs. Missing: acceptance criteria as checklist, clarifications, test results |
| **breakdown** | Low | Has story + system description. Must explore codebase from scratch every time |
| **fix_generation** | Low | Has truncated error output (4000 chars), plan. Missing: previous fix attempts, review feedback |
| **final_review** | Low | Has diff + commit log. Missing: per-commit review decisions, story acceptance criteria, test results |
| **plan_discovery** | Medium | Has REQS, SPEC, active stories/workstreams. Must explore codebase from scratch |

The biggest gaps are NOT search problems. They are prompt assembly problems -- we have the data, we just don't pass it to the agents.

---

## Competitive Landscape

### Tier 1: Cursor

**What they do:** Tree-sitter AST chunking, proprietary embedding model, Turbopuffer vector DB (100B+ vectors, 10M+ namespaces), Merkle tree change detection, hybrid retrieval (vector + ripgrep).

**What they DON'T do:** No structural code graph. No call graph, no dependency tracking. Semantic search alone -- they rely on the agent to discover cross-file relationships via tool calls.

**Their biggest strength:** Custom-trained Composer model with RL-trained self-summarization. The model manages its own context window, not the infrastructure.

**Their biggest weakness at scale:** Degrades above ~5,000 files. No cross-file structural understanding. Vector search returns "most similar" not "most relevant."

**What we learn:** AST chunking is table stakes. But Cursor's lack of a structural graph is their acknowledged gap -- and it's exactly what Aider fills with PageRank. We can do both.

### Tier 2: Aider

**What they do:** Tree-sitter for definition + reference extraction, NetworkX dependency graph, personalized PageRank ranking with empirical weight multipliers (50x for chat-file references, 10x for mentioned identifiers, 0.1x for private/common symbols). 1024 token budget. No embeddings.

**Key results:** 70.3% correct file identification on SWE Bench Lite -- with just the static repo map, no RAG, no tools, no search. The structural graph alone outperforms tool-based exploration.

**Key insight from Paul Gauthier:** "Every model gets confused above ~25-30k tokens." The repo map is a compression of the codebase optimized for LLM comprehension -- precision over recall.

**What we learn:** The graph + PageRank approach is proven. The weight multipliers are empirical gold (took iteration to discover). The 1024-token budget constraint is surprisingly effective. We should start here, not with search.

### Tier 2: Traycer

**What they do:** "Artifact Engine" (AST + LLM scout agents + ripgrep), plan-anchored verification (GPT-5.1 diffs implementation against spec), multi-model routing (Sonnet for planning, GPT for verification, Grok-fast for context gathering).

**Reality check:** 33K VSCode installs, zero Reddit presence, 12 open GitHub issues including database locking and ripgrep timeouts. The Artifact Engine is mostly LLM-inferred, not deep static analysis.

**What we learn:** Plan-anchored verification (checking implementation against spec) is a genuine insight we should adopt. Their multi-model routing validates "right model for the right job." But their technology is more marketing than substance -- we can match it with deterministic approaches.

### Tier 3: Academic + Research Tools

**Greptile:** Graph-based codebase context + agentic search. 82% bug catch rate. v3 uses aggressive caching -- 3x more context tokens but 75% lower inference costs.

**Factory AI:** HyperCode (multi-resolution code representation) + ByteRank (proprietary retrieval). Custom-trained embeddings. 200% QoQ growth. $10B+ trajectory.

**Augment Code:** Custom embedding models + dependency graph + commit history analysis. 400K+ files, sub-200ms latency. "Context architecture matters as much as model choice."

**Sourcegraph Cody:** Abandoned pure embeddings for enterprise. Moved to BM25 + Semantic Graph (SCIP symbol index). Pivoting to Amp (agentic workflows).

**What we learn:** The industry is converging on hybrid (BM25 + graph + optional embeddings). Pure embeddings are being abandoned at scale. Purpose-built retrieval beats generic approaches.

### Tier 3: Orchestrators (BMAD, Gas Town)

**BMAD:** Process framework, not technology. Context through "epic sharding" -- hyper-detailed story files that embed full context. No indexing, no AST, no graphs.

**Gas Town (Steve Yegge):** 20-30 parallel Claude Code instances, git worktrees, external state via "Beads" (git-backed issue tracker). No indexing. Philosophy: throw agents at the work, manage state externally.

**What we learn:** BMAD validates front-loading context into planning artifacts (we already do this with stories + ACs). Gas Town validates external state management (we already do this with SQLite + ZMQ). Neither does code understanding -- that's our opportunity.

---

## Open Questions Requiring Research

These are assumptions we're making that need validation before or during implementation.

### Q1: What's our optimal token budget for the structural map?

Aider defaults to 1024 tokens. Paul Gauthier says models degrade above 25-30k total. But our agents already consume significant context (story, directives, review history, diff). How much budget remains for a structural map?

**Research needed:** Measure current prompt sizes for each agent (breakdown, review, implement). Calculate remaining budget. Test with varying map sizes to find the sweet spot.

### Q2: Does PageRank generalize to our use case?

Aider's PageRank works for interactive coding (user says "edit function X", map shows related functions). Our use case is automated pipeline agents -- breakdown agent needs to see the full codebase structure to plan commits, not a query-focused slice.

**Research needed:** Test personalized PageRank (Aider's approach) vs unpersonalized (global importance) vs BFS from entry points (the HCP approach) for breakdown quality.

### Q3: Single language or polyglot?

Aider supports 50+ languages with full repo map. RAG2 said "start with one language." But many projects are polyglot (Go + TypeScript, Python + JavaScript). Cross-language edges (API endpoints shared between frontend/backend) are where Traycer claims value.

**Research needed:** Audit HASHD user projects. How many are single-language? How many have meaningful cross-language dependencies? Start with the most common language and add others based on demand.

### Q4: How much do clarifications and acceptance criteria actually improve review quality?

We assume injecting ACs into the review prompt will improve plan-anchored verification. But we don't have baseline measurements.

**Research needed:** Run a before/after experiment. Take 10 past reviews where the agent missed a spec violation. Re-run with ACs injected. Measure improvement.

### Q5: Is FTS5 sufficient for project artifact search, or do we need embeddings?

RAG2 argues FTS5 covers 80% of the value. The academic research says BM25 dominates for code-to-code but embeddings win for NL-to-code.

**Research needed:** Build FTS5. Collect queries that fail (user asks conceptual question, gets no results). If failure rate is >20%, embeddings earn their keep.

### Q6: What's the right chunk size for AST-parsed code?

cAST paper targets ~4000 non-whitespace chars. Aider's token budget is 1024 tokens (~4000 chars). Continue.dev recommends whole-file chunks with Voyage Code 3 (16k token context). The HCP paper says signatures-only is nearly as good as full code.

**Research needed:** Test signatures-only (cheapest), signatures + docstrings, and full AST chunks against breakdown quality.

---

## Roadmap

### Phase 1: Deterministic Context Injection [No new infrastructure]

Fix the prompt assembly gaps. This is the highest-ROI work because it uses data we already have.

| Step | What | Agent Impact | Research Checkpoint |
|------|------|--------------|-------------------|
| ~~1a~~ | ~~Pass story acceptance criteria to review + final_review as verification checklist~~ | ~~Review catches "built wrong thing"~~ | ~~**Q4:** Measure before/after review quality~~ |
| ~~1b~~ | ~~Inject resolved clarifications into implement + review prompts~~ | ~~Agents see human decisions~~ | ~~--~~ |
| ~~1c~~ | ~~Pass previous fix descriptions to fix_generation~~ | Won't do -- fix_generation already receives full plan_content which contains all prior FIX commit descriptions inline | -- |
| ~~1d~~ | ~~Pass per-commit review concerns + human decisions to final_review~~ | ~~Final review sees cumulative context~~ | **Watch:** monitor whether review notes anchor the final reviewer instead of helping it |
| ~~1e~~ | ~~Pass test results summary to review agent~~ | ~~Reviewer knows what passed/failed~~ | ~~--~~ |

**Expected outcome:** Fewer wasted cycles from agents missing context that already exists in SQLite. Zero new dependencies.

### Phase 2: Structural Code Map [tree-sitter + graph]

Give agents a compressed, verified understanding of the codebase.

| Step | What | Agent Impact | Research Checkpoint |
|------|------|--------------|-------------------|
| 2a | tree-sitter parsing: extract definitions + references | Raw tag data | **Q3:** Start with one language or polyglot? |
| 2b | Build dependency graph (NetworkX or lightweight alternative) | Cross-file edges | **Q2:** PageRank vs BFS vs global importance |
| 2c | Generate token-budgeted structural map | Compact codebase summary | **Q1:** Optimal budget per agent |
| 2d | Inject map into breakdown + plan_discovery prompts | Agents know the codebase before exploring | **Q6:** Signatures-only vs full chunks |
| 2e | Inject map into review prompts (focused on changed files + their dependents) | Reviews catch ripple effects | -- |
| 2f | Cache maps per-file with mtime invalidation (Aider's pattern) | Fast incremental updates | -- |

**Expected outcome:** Breakdown agent proposes realistic commit plans. Review agent catches cross-file impact. Both spend fewer tokens on exploration.

**Dependencies:** `tree-sitter` + language grammar(s), `networkx` (or simpler graph lib).

**Integration note:** When Phase 2 lands, update the pair programmer chat to support structural code maps: add `@codemap` artifact type in `chat_context.py` and add `wf codemap` to the safe commands allowlist in `chat_actions.py`.

### Phase 3: Project Knowledge Search [FTS5]

Make project history searchable for both humans and agents.

| Step | What | Agent Impact | Research Checkpoint |
|------|------|--------------|-------------------|
| 3a | FTS5 virtual table on stories, reviews, events, chat_messages, clarifications | Searchable project history | -- |
| 3b | `wf search <query>` CLI command | Human productivity | -- |
| 3c | `search()` tool for pair programmer agent | Agent can find past decisions | -- |
| 3d | `search()` tool for pipeline agents (opt-in per stage) | Agents find relevant precedents | **Q5:** Track query failures, measure FTS5 sufficiency |
| 3e | `@recall:topic` artifact handler in chat | User-triggered search in chat | -- |

**Expected outcome:** "What did we decide about authentication?" returns results from across the project history. Agents can query when they need historical context.

**Dependencies:** None (FTS5 is built into SQLite).

**Integration note:** When Phase 3 lands, update the pair programmer chat: add `@search:query` artifact type in `chat_context.py`, add `wf search` to the safe commands allowlist in `chat_actions.py`, and consider adding `search()` as a tool the chat agent can call directly.

### Phase 4: Dependency Edges [tree -> graph]

Promote the structural map from a tree of definitions to a queryable graph of relationships.

| Step | What | Agent Impact | Research Checkpoint |
|------|------|--------------|-------------------|
| 4a | Extract import/require edges from AST | Cross-file dependency tracking | -- |
| 4b | Extract call-site edges (who calls whom) | Impact analysis for reviews | -- |
| 4c | Build "what depends on X?" query | Review agent checks ripple effects | -- |
| 4d | Connect code nodes to project artifact nodes | "This function was added by STORY-0042" | -- |

**Expected outcome:** Review agent can answer "what else calls this function I'm changing?" without tool-call exploration. The structural map becomes a true graph.

**Dependencies:** Completed Phase 2.

### Phase 5: Embeddings [only if FTS5 proves insufficient]

| Step | What | Research Checkpoint |
|------|------|-------------------|
| 5a | Add embedding model (OpenAI text-embedding-3-small or Voyage Code 3) | **Q5:** Only proceed if FTS5 failure rate >20% |
| 5b | Hybrid retrieval (FTS5 + vector search + reranking) | Measure improvement over FTS5 alone |
| 5c | Selective retrieval (know when NOT to search) | RepoFormer finding: 80% of retrieval doesn't help |

**Expected outcome:** Conceptual queries ("how did we handle error recovery?") return relevant results. Only built if needed.

---

## Observability: Measuring What Works

The Context Graph is only as good as our ability to measure its impact. Without observability, we inject context, assume it helps, and never know whether we're over- or under-investing. This is a parallel track that runs alongside the phases, not a separate phase.

### Design Principle: Push vs Pull

The architecture has two context delivery modes. Observability must cover both:

- **Push (Phases 1-2):** Curated context injected into every prompt -- acceptance criteria, clarifications, structural map. The agent doesn't choose to receive this. It's always there because it's always relevant.
- **Pull (Phase 3+):** Search tools the agent can call on demand -- `search()`, `grep`, `glob`, `read`. The agent decides when and whether to use these.

Push context needs token accounting (are we spending tokens wisely?). Pull context needs usage tracking (is the agent calling the tools? are the results useful?).

### Level 1: Token Accounting [Build with Phase 1]

For every agent invocation, log the prompt composition breakdown to the run transcript.

**What to capture:**

| Field | Source | Cost to Implement |
|-------|--------|-------------------|
| Total prompt tokens | LLM API response metadata (`usage.prompt_tokens`) | Free -- already returned |
| Total completion tokens | LLM API response metadata (`usage.completion_tokens`) | Free -- already returned |
| Section token counts | Count each section before prompt assembly | Low -- we build the prompt, we know the parts |
| Section list | Which optional sections were included | Low -- log what render_prompt receives |

**Section breakdown for each agent:**

```
{
  "agent": "review",
  "run_id": "...",
  "prompt_sections": {
    "system_description": 84,
    "story_context": 312,
    "acceptance_criteria": 187,
    "clarifications": 0,
    "tech_preferences": 45,
    "diff": 2840,
    "review_history": 0,
    "structural_map": 1024
  },
  "total_prompt_tokens": 4492,
  "total_completion_tokens": 1280
}
```

This goes into the existing transcript JSONL. Zero new infrastructure -- just structured logging of what we already compute.

### Level 2: Tool Call Tracking [Build with Phase 1]

Log every tool call the agent makes during execution.

**What to capture:**

| Field | Source | Why |
|-------|--------|-----|
| Tool name (grep, glob, read, search) | Agent response `tool_use` blocks | What exploration the agent needed |
| Tool call count per invocation | Count of tool_use blocks | Proxy for how much the agent explored |
| Tool result token cost | Count tokens in tool results fed back | How much exploration cost |
| Search queries (Phase 3+) | `search()` tool arguments | What the agent looked for |
| Search result count | `search()` tool response | Whether search found anything |

**The key metric:** Tool call delta. If the breakdown agent made 12 grep calls without the structural map and 4 with it, the map saved 8 exploration round-trips. This is a direct proxy for context relevance -- the agent didn't need to discover what we told it.

### Level 3: Outcome Correlation [Build post-Phase 2]

Correlate context injection with run outcomes using metrics we already track.

| Metric | What It Measures | Available In |
|--------|-----------------|--------------|
| Review pass rate (first attempt) | Did curated ACs help the reviewer catch issues? | `reviews` table |
| Fix generation oscillation count | Did previous-fix injection prevent repeated failures? | `runs` table |
| Breakdown plan acceptance rate | Did the structural map produce more realistic plans? | Human approve/reject decisions |
| Tool calls per stage | Did richer context reduce exploration? | Transcript (Level 2) |
| Total tokens per run | Did better context make runs cheaper? | Transcript (Level 1) |
| Run duration | Did less exploration make runs faster? | `runs` table |

This is observational, not causal. But over enough runs, patterns emerge: "runs where the structural map was injected used 40% fewer tool calls and had 15% higher first-pass review acceptance."

### Level 4: Context Relevance Scoring [Experimental, post-Phase 3]

Two approaches to measure whether injected context was actually used:

**4a. Attention proxy via structured self-report.** Append to agent prompts:

```
After completing your task, in your final JSON output include a
"context_usage" field rating each provided section:
- "used": directly referenced or relied upon
- "skipped": present but not needed for this task
- "partial": scanned but only partially relevant
```

This is self-reported and unreliable -- models tend to over-report usage. But consistent "skipped" signals across many runs indicate a section is not earning its token cost. The RepoFormer finding (models can predict when retrieval won't help with 85% accuracy) suggests models have some metacognitive ability here.

**4b. Search result click-through.** For `search()` tool results, track whether the agent subsequently read any of the returned source files. If search returns 5 results and the agent reads 0 of them, the search was irrelevant. If it reads 3, the search was useful. This is a concrete relevance signal that doesn't rely on self-report.

### Observability Rollout

| Phase | Observability Added | What It Enables |
|-------|-------------------|-----------------|
| Phase 1 (prompt assembly) | Token accounting + tool call tracking | Baseline: how much context do agents get today? How much do they explore? |
| Phase 2 (structural map) | Tool call delta comparison | Did the map reduce exploration? By how much? |
| Phase 3 (FTS5 search) | Search query/result logging + click-through tracking | Is search useful? What queries fail? (Gates Phase 5 decision) |
| Post Phase 3 | Outcome correlation dashboard | Which context sections correlate with better runs? |
| Experimental | Self-report scoring | Fine-grained per-section relevance signal |

The observability data feeds back into design decisions: if the structural map consistently saves 8+ tool calls per run, we invest more in map quality. If search results are rarely used, we don't build Phase 5. If acceptance criteria injection doesn't correlate with better reviews, we investigate why -- maybe the prompt structure needs work, not the content.

---

## What We're NOT Doing and Why

**NOT building a cloud-hosted embedding pipeline (RAG.md Phase 1-4).** The research says FTS5 covers the artifact search use case, and deterministic structural maps cover the code understanding use case. Embeddings are Phase 5, gated on evidence.

**NOT indexing source code as text chunks.** The research says similar code snippets hurt (-15%). We're indexing code as structure (signatures, edges) -- the graph, not the content.

**NOT supporting 100+ languages.** Aider's 108 dependencies come from universal language support. We start with the project's primary language and add on demand.

**NOT building a general-purpose code search engine.** Agents explore code dynamically with grep/glob/read. The Context Graph provides orientation (what exists, what connects to what), not content retrieval. This is Aider's insight: a map, not a search engine.

**NOT using LLMs to infer code structure.** The research is clear: deterministic AST-derived graphs are cheaper (20-46x), faster (40-71x), more complete (90-99% vs 63-71%), and more correct (95.6% vs 84.4%) than LLM-extracted graphs.

---

## References

### Academic

- Du et al., "Context Length Alone Hurts LLM Performance Despite Perfect Retrieval," EMNLP 2025 Findings. [arXiv:2510.05381](https://arxiv.org/abs/2510.05381)
- Zhang et al., "Hierarchical Context Pruning for Repository-Level Code Completion," AAAI 2025. [arXiv:2406.18294](https://arxiv.org/abs/2406.18294)
- Gu et al., "What to Retrieve for Effective Retrieval-Augmented Code Generation?" ICSE 2026. [arXiv:2503.20589](https://arxiv.org/abs/2503.20589)
- Zhang et al., "cAST: AST-Based Code Chunking," EMNLP 2025 Findings. [arXiv:2506.15655](https://arxiv.org/abs/2506.15655)
- Chinthareddy, "Reliable Graph-RAG for Codebases: DKB vs LLM-KB," Jan 2026. [arXiv:2601.08773](https://arxiv.org/abs/2601.08773)
- Galimzyanov & Kolomyttseva, "Practical Code RAG at Scale," NeurIPS 2025 DL4C. [arXiv:2510.20609](https://arxiv.org/abs/2510.20609)
- Liu et al., "Lost in the Middle," TACL 2024. [arXiv:2307.03172](https://arxiv.org/abs/2307.03172)
- Shi et al., "RepoFormer: Selective Retrieval," ICML 2024. [arXiv:2403.10059](https://arxiv.org/abs/2403.10059)
- Yang et al., "SWE-agent," NeurIPS 2024. [arXiv:2405.15793](https://arxiv.org/abs/2405.15793)
- "Citation-Grounded Code Comprehension," Dec 2025. [arXiv:2512.12117](https://arxiv.org/abs/2512.12117)
- Chroma Research, "Context Rot," 2025. [research.trychroma.com/context-rot](https://research.trychroma.com/context-rot)

### Industry / Tools

- Aider repo map: [aider.chat/2023/10/22/repomap.html](https://aider.chat/2023/10/22/repomap.html)
- Cursor + Turbopuffer: [turbopuffer.com/customers/cursor](https://turbopuffer.com/customers/cursor)
- Cursor indexing architecture: [read.engineerscodex.com/p/how-cursor-indexes-codebases-fast](https://read.engineerscodex.com/p/how-cursor-indexes-codebases-fast)
- Sourcegraph Cody context: [sourcegraph.com/blog/how-cody-understands-your-codebase](https://sourcegraph.com/blog/how-cody-understands-your-codebase)
- Augment Code context engine: [augmentcode.com/context-engine](https://www.augmentcode.com/context-engine)
- Greptile graph-based context: [greptile.com/docs/how-greptile-works/graph-based-codebase-context](https://www.greptile.com/docs/how-greptile-works/graph-based-codebase-context)
- Factory Code Droid report: [factory.ai/news/code-droid-technical-report](https://factory.ai/news/code-droid-technical-report)
- CodeRabbit + LanceDB: [lancedb.com/blog/case-study-coderabbit](https://lancedb.com/blog/case-study-coderabbit/)
- Gas Town: [github.com/steveyegge/gastown](https://github.com/steveyegge/gastown)
- BMAD: [github.com/bmad-code-org/BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD)
- Traycer docs: [docs.traycer.ai](https://docs.traycer.ai)
- Traycer multi-model blog: [traycer.ai/blog/multi-model-architecture](https://traycer.ai/blog/multi-model-architecture)
- Paul Gauthier on context limits: [simonwillison.net/2025/Jan/26/paul-gauthier](https://simonwillison.net/2025/Jan/26/paul-gauthier/)

---

## Appendix A: Research Compendium

A structured survey of the academic literature and industry findings that inform the Context Graph design. Organized by research question, with full citations, key data, and implications for HASHD.

---

### A.1 Context Window Behavior: Why Less Is More

The foundational constraint of the Context Graph is that context windows have nonlinear failure modes. Adding relevant information can degrade performance, not just adding noise.

#### A.1.1 Context Length Alone Hurts LLM Performance

Du, Hou, Vaze, & Leskovec. "Even when the Context is Perfect, LLM Judges Still Get It Wrong." Findings of EMNLP 2025, pp. 15443-15459.

Tested 5 models (Llama-3.1-8B, Mistral-v0.3-7B, GPT-4o, Claude-3.7-Sonnet, Gemini-2.0) across GSM8K, HumanEval, MMLU, and Variable Summation. Even with perfect retrieval (all relevant information present and identifiable):

| Condition | Performance Degradation |
|-----------|------------------------|
| Irrelevant context added | 13.9% - 85% |
| Irrelevant tokens replaced with whitespace | Still degrades |
| Model forced to attend only to relevant tokens | Still degrades |
| Relevant evidence placed immediately before question | Still degrades |

The degradation is in the positional encoding and attention mechanism, not in retrieval quality. Mitigation via recite-then-solve prompting recovers up to 31.2% on GSM8K.

**Citation:** [arXiv:2510.05381](https://arxiv.org/abs/2510.05381)

#### A.1.2 Lost in the Middle

Liu, Lin, Hewitt, Paranjape, Bevilacqua, Petroni, & Liang. "Lost in the Middle: How Language Models Use Long Contexts." Transactions of the ACL, 2024, vol. 12, pp. 157-173.

The foundational paper on positional bias. Performance is highest when relevant information is at the beginning or end of the context. Over 30% accuracy degradation when relevant info shifts to the middle. 13B base models show 20-point accuracy disparity between best and worst positions.

**Citation:** [arXiv:2307.03172](https://arxiv.org/abs/2307.03172) | [ACL Anthology](https://aclanthology.org/2024.tacl-1.9/)

#### A.1.3 Context Rot

Chroma Research, 2025. Tested 20 models across Anthropic, OpenAI, Google, and Alibaba families.

Focused prompts (~300 tokens) significantly outperform full prompts (~113K tokens) across ALL model families. Best models on long-context benchmarks (LongBench) still only 50-60% accurate on retrieval tasks within long contexts.

**Citation:** [research.trychroma.com/context-rot](https://research.trychroma.com/context-rot)

#### A.1.4 Implications for Context Graph Design

These three studies converge on a single design constraint: the Context Graph must be a **compression**, not an expansion. The structural map should be minimal (Aider's 1024-token default is well-calibrated). Context should be front-loaded (system prompt, story context) with dynamic content at the end. Every injected token must be justified -- unused context is actively harmful, not merely wasteful.

---

### A.2 Code Chunking: AST vs Fixed-Size

#### A.2.1 cAST: AST-Based Code Chunking

Zhang, Yin, Xu, & Neubig. "cAST: Enhancing Code Retrieval-Augmented Generation with Structural Chunking via Abstract Syntax Tree." Findings of EMNLP 2025, pp. 8106-8116. Carnegie Mellon University & Augment Code.

Recursive AST node splitting with sibling merging. Chunk sizes measured by non-whitespace character count for cross-language consistency. Target: ~4000 non-whitespace chars per chunk.

**RepoEval retrieval results (Recall@5):**

| Retriever | cAST | Fixed-size | Gain |
|-----------|------|------------|------|
| BGE | 69.8 | 67.4 | +2.4 |
| GIST | 75.0 | 70.7 | +4.3 |
| CodeSage | 83.9 | 82.1 | +1.8 |

**RepoEval generation results (Pass@1):**

| Generator + Retriever | cAST | Fixed-size | Gain |
|-----------------------|------|------------|------|
| StarCoder2-7B + CodeSage | 73.2 | 67.6 | +5.6 |
| CodeLlama + CodeSage | 72.1 | 66.5 | +5.6 |

**SWE-Bench Lite (300 problems):**

| Model | cAST | Fixed-size | Gain |
|-------|------|------------|------|
| Claude Pass@1 | 16.3 | 13.7 | +2.6 |
| Gemini Pass@8 | 35.3 | 32.3 | +3.0 |

**CrossCodeEval (Python/Java/C#/TypeScript):**
- StarCoder2 exact match: cAST 29.1 vs fixed 24.8 (+4.3 points)

Gains are consistent across retrievers, generators, and benchmarks. The mechanism is structure preservation: not splitting functions mid-body, maintaining class boundaries, retaining file/class/function metadata in each chunk.

**Citation:** [arXiv:2506.15655](https://arxiv.org/abs/2506.15655) | Code: [github.com/yilinjz/astchunk](https://github.com/yilinjz/astchunk)

#### A.2.2 Hierarchical Context Pruning (HCP)

Zhang, Guo, Xu, Zhao, Geng, Ye, & Zhang. "Hierarchical Context Pruning: Optimizing Real-World Code Completion with Repository-Level Pretrained Code LLMs." AAAI 2025.

Uses tree-sitter for dependency modeling with BFS across import graphs. Key findings:

- Without cross-file info: best model achieves only ~30% accuracy
- **4 layers of import dependencies** sufficient to cover most scenarios; diminishing returns beyond that
- **Pruning function bodies in non-current files does NOT significantly reduce accuracy** -- signatures + structure are enough
- HCP achieved higher accuracy on 5 of 6 Code LLMs vs previous methods on CrossCodeEval

This is the most directly relevant finding for our structural map design: we can send signatures and relationships without code bodies, preserving information while dramatically reducing token count.

**Citation:** [arXiv:2406.18294](https://arxiv.org/abs/2406.18294) | [AAAI 2025](https://ojs.aaai.org/index.php/AAAI/article/view/34782)

---

### A.3 Retrieval Strategies: BM25, Embeddings, and Hybrid

#### A.3.1 Practical Code RAG at Scale

Galimzyanov & Kolomyttseva. NeurIPS 2025 DL4C Workshop. Tested on Long Code Arena (code completion PL->PL and bug localization NL->PL).

The modality-driven divide:

| Task Type | Best Retriever | Margin |
|-----------|---------------|--------|
| Code-to-code (PL->PL) | BM25 + word splitting | +~10 pp exact match over dense |
| NL-to-code (NL->PL) | Dense (Voyage-Code-3) | 0.72 vs 0.57 NDCG |

Performance: BM25 with word splitter runs at 0.07s/query. Dense encoders: up to 200x slower. Optimal chunk size scales with context budget: 32-64 lines at small budgets, whole-file competitive at 16K tokens.

**Citation:** [arXiv:2510.20609](https://arxiv.org/abs/2510.20609)

#### A.3.2 Citation-Grounded Code Comprehension

December 2025. Three-way hybrid: BM25 + BGE dense + Neo4j graph expansion via import relationships.

| Retrieval Mode | Citation Accuracy |
|----------------|-------------------|
| Dense only | 78% |
| Sparse (BM25) only | 74% |
| Hybrid (alpha=0.45, beta=0.55) | **92%** |

14-18 percentage point improvement over single-mode baselines. Zero hallucinations across 30 Python repositories, 180 developer queries. Cross-file evidence discovery is the dominant factor: 62% of evaluation questions required multi-file context, and pure text similarity missed dependencies in 60% of those cases.

**Citation:** [arXiv:2512.12117](https://arxiv.org/html/2512.12117v1)

#### A.3.3 RepoFormer: Selective Retrieval

Shi, Gao, Bai, Liu, Ramamohan, Liang, & Raghunathan. ICML 2024, Amazon Science & UCLA.

**Key finding: 80% of the time, retrieval does NOT improve code generation quality.**

- RepoFormer-3B outperforms StarCoderBase-7B on most tasks
- Selective retrieval: 70% inference speedup with no performance harm
- Over 85% of abstention decisions are accurate (model correctly decides not to retrieve)

**Citation:** [arXiv:2403.10059](https://arxiv.org/abs/2403.10059) | [repoformer.github.io](https://repoformer.github.io/)

#### A.3.4 A Deep Dive into Retrieval-Augmented Generation for Code

2025. Evaluated RAG for code completion across 26 open-source LLMs (0.5B-671B parameters).

- BM25 and GTE-Qwen combination identified as optimal
- Minimal overlap between BM25 and semantic results: out of 100 test examples, 76 completely distinct retrieved samples between BM25 and UniXcoder
- For models below 7B, hybrid retrieval shows limited or negative impact; complementary benefits only emerge with larger LLMs

**Citation:** [arXiv:2507.18515](https://arxiv.org/pdf/2507.18515)

#### A.3.5 Implications for HASHD

FTS5 (BM25-family) is the right first step for artifact search. It handles code-to-code retrieval (agent looking up a function) better than dense embeddings, at 200x the speed and zero API cost. Dense embeddings earn their keep for NL-to-code queries (human asking conceptual questions) -- but only after FTS5 proves insufficient. The hybrid BM25 + graph approach (92% citation accuracy) validates our plan to combine FTS5 with the structural dependency graph.

---

### A.4 Deterministic vs LLM-Extracted Code Graphs

#### A.4.1 Reliable Graph-RAG for Codebases

Chinthareddy. January 2026. Compared three retrieval pipelines on Java codebases: vector-only, LLM-extracted knowledge graph (LLM-KB), and deterministic AST-derived knowledge base (DKB) built with tree-sitter.

**Correctness (45 questions across 3 repositories):**

| Pipeline | Correct | Partial | Incorrect |
|----------|---------|---------|-----------|
| DKB (AST-derived) | 43/45 (95.6%) | 2 | 0 |
| LLM-KB (LLM-extracted) | 38/45 (84.4%) | 5 | 2 |
| No-Graph (vector-only) | 31/45 (68.9%) | 9 | 5 |

**Indexing time (graph construction only):**

| Repository | DKB | LLM-KB | Speedup |
|------------|-----|--------|---------|
| Shopizer | 2.81s | 200.14s | 71x |
| ThingsBoard | 13.77s | 883.74s | 64x |
| OpenMRS Core | 5.60s | 222.17s | 40x |

**Cost (end-to-end, USD):**

| Repository | No-Graph | DKB | LLM-KB |
|------------|----------|-----|--------|
| Shopizer | $0.04 | $0.09 | $0.79 |
| Combined larger workload | $0.149 | $0.317 | $6.80 |

**Coverage (corpus indexing completeness):**
- DKB: 90-99% across repositories
- LLM-KB: 63-71% (files skipped: 19-35% per repo due to stochastic extraction failures)

The cost advantage grows superlinearly with repository size. LLM-KB was 46x more expensive on the larger workload vs 20x on the smaller.

**Citation:** [arXiv:2601.08773](https://arxiv.org/abs/2601.08773)

#### A.4.2 ACER: AST-Based Call Graph Generator Framework

2023. Modular framework using tree-sitter. Preprocessor parses source files, Generator implements `seek_call_sites` and `resolve` methods for call graph construction. Designed for extensibility across languages.

**Citation:** [arXiv:2308.15669](https://arxiv.org/pdf/2308.15669)

#### A.4.3 Semantic Code Graph (SCG)

Borowski et al. IEEE Access 2024. Information model where nodes are code declarations/definitions, edges represent dependencies (uses, extends, implements, overrides). Validated on 11 open-source Java/Scala projects.

User survey: SCG-based rankings considered most maintenance-critical **64% of the time** vs 25% for class collaboration networks, 10% for call graphs. SCG subsumes both -- they can be extracted from SCG.

**Citation:** [arXiv:2310.02128](https://arxiv.org/abs/2310.02128) | [github.com/VirtusLab/scg-cli](https://github.com/VirtusLab/scg-cli)

#### A.4.4 Implications for HASHD

Build the code graph deterministically with tree-sitter. Do not use LLMs to infer code structure. The data is unambiguous: deterministic AST-derived graphs are cheaper, faster, more complete, and more correct. LLMs add value when reasoning *about* the graph, not when constructing it.

---

### A.5 What to Put in Context: Quality Over Quantity

#### A.5.1 What to Retrieve for Effective Retrieval-Augmented Code Generation?

Gu, Zhao, Fan, Sun, Zhang, Peng, Lyu, & Zhang. ICSE 2026.

Tested on CoderEval and RepoExec benchmarks. Findings:

| Context Type | Effect on LLM Performance |
|-------------|--------------------------|
| In-context code (local file, imports) | Significantly positive |
| API information | Significantly positive |
| Similar code snippets | **Negative (up to -15%)** |

Proposed AllianceCoder (chain-of-thought + API retrieval) improves Pass@1 by up to 20% over existing approaches.

**Key insight:** Not all retrieval is good retrieval. Similar-looking code from other parts of the repo actively confuses models. Structural information (what APIs exist, what the local dependencies are) helps far more than example code. This directly argues against naive RAG approaches that retrieve "similar" functions as context.

**Citation:** [arXiv:2503.20589](https://arxiv.org/abs/2503.20589) | [ICSE 2026 program](https://conf.researchr.org/details/icse-2026/icse-2026-research-track/182/)

#### A.5.2 Empirical Study of Retrieval-Augmented Code Generation

ACM Transactions on Software Engineering and Methodology, 2025. Tested CodeGen, UniXcoder, CodeT5 with RAG.

RAG improves performance of pre-trained models, but noisy retrieved code can decrease performance. Quality and utilization of retrieved code are the key factors, not quantity.

**Citation:** [ACM TOSEM](https://dl.acm.org/doi/10.1145/3717061)

#### A.5.3 LLM Hallucinations in Practical Code Generation

Zhang & Wang. ISSTA 2025. Empirical study of hallucination in repository-level code generation.

Hallucinations are worse in repository-level contexts due to complex contextual dependencies absent from training data. RAG-based mitigation shows consistent effectiveness across all studied LLMs. Import graph traversal during retrieval eliminates hallucination in cross-file scenarios.

**Citation:** [arXiv:2409.20550](https://arxiv.org/abs/2409.20550) | ISSTA 2025

---

### A.6 Repository-Level Code Understanding: Benchmarks

#### A.6.1 RepoBench

Zhang, Chen, Zhang, Liu, Zan, Mao, Cheng, & Lou. ICLR 2024. Three tasks: retrieval (R), code completion (C), and pipeline (P). Python and Java, cross-file context required.

**Citation:** [arXiv:2306.03091](https://arxiv.org/abs/2306.03091) | [OpenReview](https://openreview.net/forum?id=pPjZIOuQuF)

#### A.6.2 SWE-Bench / SWE-Bench Verified

Jimenez et al. ICLR 2024. Real GitHub issues resolved by generating patches against full repositories. State-of-the-art agents achieve >70% on SWE-Bench Verified (500 human-vetted tasks).

#### A.6.3 SWE-Bench Pro

2025. Long-horizon software engineering tasks. SOTA agents score only 17.8-23.3% -- dramatically lower than SWE-Bench Verified. Performance varies by language and repository; enterprise codebases are harder.

**Citation:** [static.scale.com/uploads/SWEAP_Eval_Scale](https://static.scale.com/uploads/654197dc94d34f66c0f5184e/SWEAP_Eval_Scale%20(9).pdf)

#### A.6.4 CoIR: Code Information Retrieval Benchmark

Li et al. ACL 2025 Main. 10 datasets, 8 retrieval tasks, 7 domains, 14 programming languages, 2M evaluation documents. The comprehensive evaluation benchmark for code retrieval going forward.

**Citation:** [arXiv:2407.02883](https://arxiv.org/abs/2407.02883) | [github.com/CoIR-team/coir](https://github.com/CoIR-team/coir)

---

### A.7 Embedding Models for Code

#### A.7.1 Voyage Code 3

Voyage AI, December 2024. Proprietary. Best-in-class code embedding model at time of release.

**NDCG@10 across dimensions (Matryoshka learning):**

| Dimension | Voyage-Code-3 | OpenAI v3 Large | CodeSage Large |
|-----------|---------------|-----------------|----------------|
| 2048 | 92.12% | 75.47% | 91.59% |
| 1024 | 92.28% | 77.64% | 71.38% |
| 512 | 92.00% | 88.53% | 90.37% |
| 256 | 91.34% | 73.68% | 67.64% |

Voyage Code 3 maintains near-constant performance across dimensions. OpenAI collapses at lower dimensions. 13.8% average improvement over OpenAI text-embedding-3-large across 32 datasets.

**Citation:** [blog.voyageai.com/2024/12/04/voyage-code-3](https://blog.voyageai.com/2024/12/04/voyage-code-3/)

#### A.7.2 Nomic Embed Code

Nomic AI, 2025. Open-source (Apache 2.0), 7B parameters. Claims SOTA on CodeSearchNet vs Voyage Code 3. 81.7% on Python, 80.5% on Java (CodeSearchNet MRR@10).

#### A.7.3 CodexEmbed

Research model. Outperforms Voyage Code on CoIR benchmark by 20%.

#### A.7.4 Note on CodeSearchNet Limitations

Per Voyage AI's analysis: CodeSearchNet queries are derived verbatim from code, making the task artificially simple. CoSQA has ~51% incorrect labels. CoIR (ACL 2025) is the more rigorous successor benchmark.

**Citation:** [blog.voyageai.com/2024/12/04/code-retrieval-eval](https://blog.voyageai.com/2024/12/04/code-retrieval-eval/)

---

### A.8 The Aider Repo Map: Empirical Design Decisions

This section documents the specific design choices in Aider's repo map that are backed by iteration and empirical results, as they directly inform our Phase 2 implementation.

#### A.8.1 Architecture

Tree-sitter parses each file, extracting two tag types via language-specific `.scm` query files:
- **Definitions** (`@definition.class`, `@definition.function`): where symbols are declared
- **References** (`@reference.call`): where symbols are used

A NetworkX `MultiDiGraph` is built: nodes are files, directed edges are cross-file references via shared identifiers. Edge attributes include computed weights and the identifier name.

#### A.8.2 PageRank Weight Multipliers

These multipliers are empirical -- they emerged from iteration, not theory:

| Condition | Multiplier | Rationale |
|-----------|-----------|-----------|
| Identifier in chat-referenced files | 50x | Direct relevance to current task |
| Identifier mentioned in conversation | 10x | User expressed interest |
| Long identifier (>=8 chars, snake/kebab/camel) | 10x | Specific names are more informative |
| Private identifier (starts with `_`) | 0.1x | Internal implementation detail |
| Defined in >5 files (common/generic) | 0.1x | Low information density |
| Reference count scaling | sqrt(N) | Sublinear -- many references indicate utility but not proportionally |

The personalization vector boosts files in the current chat and files matching mentioned identifiers, each by +100/len(fnames).

#### A.8.3 Token Budget

Default: 1024 tokens. Expands to 2x when no files are in context. Binary search finds the maximum number of ranked tags fitting within 15% of the budget. Token counting uses sampling (every Nth line) for texts over 200 characters -- trading accuracy for speed.

#### A.8.4 Caching

Three-layer cache: disk-backed SQLite (per-file tags, keyed by mtime), in-memory dict (complete maps, keyed by conversation state), in-memory dict (rendered snippets, keyed by file + lines + mtime). Refresh strategies: auto (cache if build >1s), always, files-only, manual.

#### A.8.5 Key Result

70.3% correct file identification on SWE Bench Lite using only the static repo map. No RAG, no vector search, no tool-based exploration. This is the strongest evidence that structural graph analysis alone provides substantial code understanding.

**Citation:** [aider.chat/2023/10/22/repomap.html](https://aider.chat/2023/10/22/repomap.html) | [aider.chat/2024/05/22/swe-bench-lite.html](https://aider.chat/2024/05/22/swe-bench-lite.html) | [deepwiki.com/Aider-AI/aider/4.1-repository-mapping](https://deepwiki.com/Aider-AI/aider/4.1-repository-mapping)

---

### A.9 Industry Architecture Comparison

| Tool | Indexing | Retrieval | Code Graph | Scale | Key Insight |
|------|---------|-----------|------------|-------|-------------|
| **Cursor** | Tree-sitter AST + Merkle tree sync + proprietary embeddings | Hybrid: Turbopuffer vector + ripgrep lexical + reranking | None | 100B+ vectors, degrades >5K files | Custom-trained model (Composer) manages its own context via RL |
| **Aider** | Tree-sitter definitions + references | PageRank on NetworkX dependency graph | Full (definitions + call references + type refs) | 50+ languages, 1024 token budget | Static structural map outperforms tool-based exploration |
| **Sourcegraph Cody** | SCIP language-specific indexers | BM25 + Semantic Graph + targeted embeddings | Full (compiler-accurate symbol index) | Enterprise monorepos | Abandoned pure embeddings for hybrid BM25 + graph |
| **Augment Code** | Custom-trained embeddings + commit history analysis | Quantized vector search | Dependency graph | 400K+ files, sub-200ms | "Context architecture matters as much as model choice" |
| **Factory AI** | HyperCode (multi-resolution representation) | ByteRank (proprietary) | Multi-level (explicit graph + latent space) | Enterprise | Deep vertical integration: proprietary everything |
| **Greptile** | Graph-based codebase context | Agentic search + graph expansion | Dependency graph + git history | Per-PR review | 82% bug catch rate; 3x context, 75% lower cost via caching |
| **CodeRabbit** | LanceDB over PRs, issues, code deps | Semantic search + code graph analysis | Function dependencies | 50K+ daily PRs | High-volume consistency; strength is scale, not depth |
| **Traycer** | AST + LLM scout agents + ripgrep | LLM-inferred cross-layer relationships | Partial (AST for within-language, LLM for cross-layer) | VSCode extension | Marketing exceeds verified technical depth |
| **Gas Town** | None | Agent explores dynamically | None | 20-30 parallel Claude Code instances | External state (Beads) over context bloat |
| **SWE-agent** | None | Purpose-built ACI tools | None | Single-issue resolution | Interface design > indexing complexity; 100-line mini-agent matches full |
| **BMAD** | None | Context front-loaded into story artifacts | None | Process framework | Epic sharding solves context collapse through planning, not technology |

#### A.9.1 The Emerging Industry Consensus (2025-2026)

1. **Layered retrieval wins.** BM25 for lexical precision, dense embeddings for semantic understanding, graph expansion for structural dependencies. Single-mode retrieval is being abandoned.

2. **AST-aware chunking is table stakes.** Tree-sitter for parsing, split at function/class boundaries. Every serious tool does this.

3. **Context quality > context quantity.** A weaker model with great context outperforms a stronger model with poor context (Augment Code). Focused ~300-token prompts outperform ~113K-token prompts (Chroma).

4. **Pure embeddings are being abandoned at enterprise scale.** Sourcegraph moved away. Cursor supplements with lexical search. The trend is toward hybrid and graph-based approaches.

5. **The orchestration layer is the new moat.** Gas Town, BMAD, Factory, Traycer, and HASHD all compete on how you coordinate agents, not on which model you use.

6. **Simplicity is underrated.** Mini-SWE-agent (100 lines) matches full SWE-agent. Aider's no-embedding approach outperforms heavier systems on efficiency. More infrastructure does not guarantee better results.

---

### A.10 Cursor Deep Dive: Architecture and Limitations

Included separately due to Cursor's market dominance and relevance as the primary benchmark.

#### A.10.1 Indexing Pipeline

```
Local files -> Merkle tree hash -> Delta detection -> Upload changed chunks
-> Server: tree-sitter AST parse -> Chunk -> Embed (custom model)
-> Store in Turbopuffer (per-user namespace)
-> Cache embeddings by chunk hash in AWS
```

Sync runs periodically (3-10 minute intervals). Only changed files re-index via Merkle tree comparison. Source code discarded after embedding -- only vectors + obfuscated metadata persist.

#### A.10.2 Turbopuffer Scale

| Metric | Value |
|--------|-------|
| Total vectors | 100B+ |
| Active namespaces | 10M+ |
| Peak write ingestion | 1M+ docs/second (10GB/s) |
| Query latency (hot/cached) | <10ms |
| Query latency (cold/S3) | 200-500ms |
| Index reuse (teammate codebases) | Median time-to-first-query: 7.87s -> 525ms |

**Citation:** [turbopuffer.com/customers/cursor](https://turbopuffer.com/customers/cursor) | [turbopuffer.com/blog/ann-v3](https://turbopuffer.com/blog/ann-v3)

#### A.10.3 Composer Model (Custom-Trained)

Cursor 2.0 (October 2025): First in-house MoE model, trained with RL on real coding tasks using ~10 production tools. 4x faster than comparable models at ~250 tokens/second. Multi-agent mode: up to 8 parallel agents using git worktrees.

Composer 1.5 (February 2026): 20x more RL compute. Trained self-summarization for context window continuation. Adaptive thinking (minimal reasoning on easy problems, deep on hard). 47.9% on Terminal-Bench 2.0 (vs Claude Sonnet 4.5 at 41.6%).

**Citation:** [codecademy.com/article/cursor-2-0-new-ai-model-explained](https://www.codecademy.com/article/cursor-2-0-new-ai-model-explained) | [adwaitx.com/cursor-composer-1-5-agentic-coding-model](https://www.adwaitx.com/cursor-composer-1-5-agentic-coding-model/)

#### A.10.4 The Structural Graph Gap

Cursor has **no explicit dependency graph, call graph, or symbol index**. Cross-file understanding comes from semantic vector similarity (approximate) and agent tool calling (expensive). This is their biggest acknowledged architectural limitation.

Competitors that fill this gap: Aider (PageRank on AST graph), Sourcegraph (SCIP symbol index), Augment Code (dependency graph + commit history), Greptile (graph-based codebase context).

Third-party tools like Deep Graph MCP exist specifically to give Cursor structural code graph capabilities it otherwise lacks.

---

### A.11 Traycer Deep Dive: Claims vs Reality

#### A.11.1 Multi-Model Assignment

| Role | Model | Rationale |
|------|-------|-----------|
| Planning & task decomposition | Sonnet-4.5 | Efficiency in accuracy + planning speed |
| Verification, code critique, debugging | GPT-5.1 | Better at code analysis and review |
| Parallel context gathering ("scouts") | Grok-4.1-fast | Fast, cheap, parallel fan-out for file discovery |
| Summarizing large context | GPT-5.1-mini | Small model for plumbing work |

Routing is role-based and static, not dynamic. Each workflow phase has a designated model.

**Citation:** [traycer.ai/blog/multi-model-architecture](https://traycer.ai/blog/multi-model-architecture)

#### A.11.2 Artifact Engine Assessment

The "Artifact Engine" is a hybrid: AST parsing for syntactic relationships, LLM scout agents (Grok-4.1-fast) for semantic context gathering, and ripgrep for text search. The cross-layer relationship tracking (frontend -> API -> DB) is LLM-inferred, not deterministic static analysis. Per the research in A.4.1, LLM-inferred graphs are 84.4% correct vs 95.6% for deterministic AST-derived graphs.

The "92% first-pass implementation success rate" claim appears in a single third-party listing (ProductCool) with no independent verification.

#### A.11.3 User Feedback Summary

**Positive:** Good for complex multi-file tasks, significant time savings, handles large files well, token savings when paired with Claude Code.

**Negative:** 10-minute timeout on YOLO mode, artifact cooldown limits, plan editing times out, database locking with multiple VS Code instances, ripgrep process timeouts, no offline mode.

**Traction:** 33K VSCode installs, 152 GitHub stars, zero Reddit presence, no disclosed funding. Pre-Series A.

**Citation:** [marketplace.visualstudio.com/items?itemName=Traycer.traycer-vscode](https://marketplace.visualstudio.com/items?itemName=Traycer.traycer-vscode) | [github.com/traycerai/community](https://github.com/traycerai/community)

---

### A.12 Code Embedding Model Benchmarks

For reference if and when Phase 5 (embeddings) becomes necessary.

| Model | Parameters | Open Source | NDCG@10 (2048d) | Cost | Notes |
|-------|-----------|-------------|-----------------|------|-------|
| Voyage Code 3 | Unknown | No | 92.12% | $0.06/1M tok | Best proprietary; Matryoshka stable across dims |
| Nomic Embed Code | 7B | Yes (Apache 2.0) | Claims SOTA on CodeSearchNet | Free (self-hosted) | New entrant; independent benchmarks pending |
| CodexEmbed | Varies | Research | +20% over Voyage on CoIR | N/A | Not production-available |
| OpenAI text-embedding-3-small | Unknown | No | ~75% (estimated) | $0.02/1M tok | Cheapest; quality degrades at low dimensions |
| CodeSage Large V2 | 1.3B | Yes | 91.59% (2048d) | Free (self-hosted) | Strong alternative to Voyage for self-hosted |

**Caveat:** CodeSearchNet benchmarks are artificially easy (queries derived from code). CoIR (ACL 2025) is the rigorous successor. Rankings may differ on CoIR.

**Citations:** [blog.voyageai.com/2024/12/04/voyage-code-3](https://blog.voyageai.com/2024/12/04/voyage-code-3/) | [arXiv:2407.02883 (CoIR)](https://arxiv.org/abs/2407.02883)
