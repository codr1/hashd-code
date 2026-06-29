# HASHD - Human-Agent Synchronized Handoff Development

(حشد = Arabic for "crowd")

**The disciplined, auditable software factory for spec-driven development.** Every change goes spec -> story -> implement -> review -> merge through governed gates, with a full audit trail of why every line of merged code exists.

## Install

One paste on a fresh box -- no Python setup required:

```bash
curl -fsSL https://raw.githubusercontent.com/codr1/hashd-code/main/install.sh | bash
```

The installer provides a Python 3.11+ runtime (via [uv](https://github.com/astral-sh/uv) when your system has none), installs the `hashd` CLI and server, fetches SHA-verified forge CLIs (gh, glab, bkt, tea), then runs `hashd doctor` to confirm the setup. `wf` remains a permanent alias for the same CLI, and installs also include the short `ha` alias.

**System requirements:** `git`, and one authenticated AI coding agent CLI ([Claude Code](https://docs.claude.com/en/docs/claude-code) by default). The agent CLIs are npm packages, so installing one needs Node.js -- `hashd doctor` prints the exact commands for your OS. See [QUICKSTART.md](QUICKSTART.md#ai-coding-agents) for the agent on-ramp.

## What hashd is

Hashd is an orchestration system for AI coding agents. It plans the work, runs agents in isolated worktrees, grounds them in verified code structure, gates each change through review, and records the full lineage of every commit.

**10x developer throughput. 10x fewer tokens spent on exploration. 15%+ accuracy improvement from grounded context.**

AI coding agents are powerful but unaccountable. They generate code without explaining why, re-discover the codebase on every run, and make decisions you can't trace later. Hashd adds the structure that makes AI-generated code trustworthy enough to ship -- and fast enough to change how much you ship in a day.

Spec-driven development is an established category. Generation-only spec tools stop at *producing* code from a spec; hashd governs the whole path to a **merged, attested commit** -- the implement/test/review loop, the human-approval gates between steps, and a verifiable provenance chain that records every one of them.

## How it works

Work flows through four entities, each backed by a validated state machine:

```text
Requirement -> Suggestion -> Story (+ acceptance criteria) -> Workstream -> micro-commits -> merged commit
```

- A **Suggestion** is a candidate piece of work discovered from your requirements (`REQS.md`).
- Claiming it creates a **Story**: a feature or bug with acceptance criteria -- the source of truth for *what* the change should do.
- Running an accepted Story creates a **Workstream**: one git branch in one isolated worktree, holding a plan of **micro-commits** (the smallest planned units of work).
- Each micro-commit runs the **governed loop** -- `implement -> test -> review -> human approval -> commit` -- where every arrow is a **gate**. When all micro-commits land, the branch gets a holistic final review and a merge gate (tests, conflict check, secrets scan), then merges.
- Whether a gate stops for a human is set by the project's **autonomy mode** (supervised / gatekeeper / autonomous). All modes still block to a human on failures.
- Every state change is **dual-written**: pushed live over ZMQ and recorded durably in SQLite. That durable log is the spine of the **audit trail** -- `hashd lineage` reconstructs why any line of code exists, all the way back to the requirement and the human who approved it.

## Philosophy

The bottleneck in shipping AI-written code is not typing speed -- it is **trust**: knowing a change does what was asked, that it was reviewed, that a human signed off where it mattered, and that you can reconstruct the decision chain later. Hashd is a *process and provenance* layer over raw agents. It does not make the agent faster; it makes the agent's output **accountable** -- governed by gates, recorded as it happens, and auditable after the fact. That is the half generation-only tools lack.

## Documentation

Start here to learn the system, then dive into the reference docs:

- **[docs/how-hashd-works.md](docs/how-hashd-works.md)** - the mental model: entities, the governed gates, the event log, and the provenance chain, as concepts.
- **[docs/walkthrough.md](docs/walkthrough.md)** - one feature start-to-finish, from spec to a merged commit with a full audit trail.
- **[docs/glossary.md](docs/glossary.md)** - canonical definitions: Suggestion, Story, Workstream, micro-commit, stage vs runtime_status vs runner_stage, gates, lineage.
- **[docs/navigation.md](docs/navigation.md)** - the `hashd watch` TUI: Dashboard, Story Detail, Workstream Detail, and when to use each.
- **[docs/provenance.md](docs/provenance.md)** - the audit/lineage story: `hashd lineage`, SLSA/in-toto export, hash-chain verify, the durable event log.
- [QUICKSTART.md](QUICKSTART.md) - installation, first project setup, basic workflows.
- [docs/AGENT_MANAGEMENT.md](docs/AGENT_MANAGEMENT.md) - agent switching, auth configuration, prompt overrides.
- [docs/CODE_TOOLS.md](docs/CODE_TOOLS.md) - code intelligence operator commands and troubleshooting.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) - client/server boundaries, state, events, and diagnostics.
- [WF.md](WF.md) - the canonical lifecycle documentation, state machines, and command reference.
- [RELEASE_NOTES.md](docs/RELEASE_NOTES.md) - version-by-version release notes.

## What hashd does

**Plans the work.** Stories, suggestions, and workstreams are first-class entities with state machines. A story flows from drafting through review to acceptance; a workstream loops through breakdown, implement, test, review, and human gate for each micro-commit. You always know what stage a piece of work is in and what comes next.

**Grounds the agents.** Agents query a pre-computed Context Graph instead of re-discovering the codebase on every run. AST structure, dependency edges, and project knowledge are extracted once and made available to every agent in every workstream. Published research on systems like Aider shows tool-based exploration consumes 54-70% of the context window for orientation alone; pre-computed structural maps reduce this to 4-6%. That's a 10-15x reduction in tokens spent discovering what static analysis already knows -- and a corresponding reduction in cost, latency, hallucinated file paths, and first-pass review failures.

**Records the lineage.** Every commit traces through its workstream, its story, its reviews, its clarifications, and the human decisions that gated it. `hashd lineage <file|sha|STORY-xxx>` reconstructs the chain. `hashd lineage export --format slsa|in-toto` produces machine-readable provenance for supply-chain compliance. `hashd lineage verify` validates the hash chain integrity. AI-generated code becomes auditable.

```
file -> git log -> commit message (COMMIT-XX-NNN)
  -> workstream -> STORY_ID -> story
    -> transcript, reviews, clarifications, human decisions
```


**Runs in parallel, safely.** Multiple workstreams execute against the same project concurrently. Each gets its own git worktree and per-workstream lock. `hashd conflicts` warns when workstreams touch overlapping files. The FSM serializes per-workstream operations so concurrent runs don't corrupt shared state. With grounded agents and parallel execution working together, hashd users routinely ship 10x more debugged code per day than they would driving an agent by hand.

**Works with any agent.** Use Claude Code, Codex, Copilot, Gemini, OpenCode, Kimi, or Qwen -- any combination, any stage. Stages declare their required invocation shape; any agent that supports the shape can fill the slot. You're not locked to one vendor.

**Spans multiple repositories.** A single project can include a backend repo, a frontend repo, and an infra repo. Planning happens at the project level; execution happens in the right repo automatically.

**Multiple interfaces.** A TUI (`hashd watch`) for real-time monitoring with status-adaptive keybindings, a CLI for power users and scripting, and a Telegram bot for mobile workflow management.

**Keeps you in the loop where it matters.** Three autonomy modes -- supervised, gatekeeper, and autonomous -- with confidence-threshold gating. A clarification queue holds work until you answer agent questions. Structured approve and reject flows.

## What's coming

**Team server.** A multi-user team server is in active development. It will let engineering teams coordinate humans and agent fleets on the same project -- shared workstream registry, multi-user gates, attestations exported per merge.

**Web dashboard.** A browser-based interface for monitoring and controlling workstreams.

**Desktop app.** A native Electron client for users who prefer a windowed UI over the terminal.

## Context Graph: Three Layers

The Context Graph that grounds the agents (above) is built in three layers:

**Layer 1: Structural analysis.** AST parsing extracts a deterministic map of the codebase -- modules, classes, functions, and their signatures -- with zero LLM calls. Every symbol is verified to exist; every relationship is a real reference, not a retrieval approximation. This is *grounding* in the formal sense: constraining generation with verified facts.

**Layer 2: Dependency edges.** Import graphs, call sites, and type references promote the structural tree into a full graph. When an agent needs to modify a function, the graph answers "what depends on this?" in constant time rather than O(n) tool-call rounds.

**Layer 3: Project knowledge.** Full-text search over project artifacts -- stories, review decisions, clarifications, conversation history -- connects code nodes to the business decisions that motivated them. The graph becomes heterogeneous: code structure and project intent in a single queryable system.



## Shell Completion

Install shell completion for your shell:

```bash
# Bash (managed automatically by setup.sh and dist/install.sh)
source <(hashd completion bash)

# Zsh (managed automatically by setup.sh for source installs)
autoload -Uz compinit && compinit
source <(hashd completion zsh)

# Fish
hashd completion fish > ~/.config/fish/completions/hashd.fish
```

Examples:
```bash
hashd r<TAB>                    # -> hashd run
hashd run o<TAB>                # -> hashd run open_play_rules
hashd run STORY-<TAB>           # -> hashd run STORY-0001
hashd show <TAB>                # Shows both stories and workstreams
```

## Parallel Workstreams

Hashd supports running multiple workstreams simultaneously. Each workstream gets its own git worktree and lock file, allowing true parallel development:

```bash
# Terminal 1
hashd run feature_auth --loop

# Terminal 2 (at the same time)
hashd run feature_api --loop

# Terminal 3
hashd run bugfix_123 --loop
```

A warning is shown when more than 3 workstreams are running concurrently (to avoid API rate limits).

## Desktop Notifications

Hashd sends desktop notifications when workstreams need attention:

| Event | Urgency | When |
|-------|---------|------|
| Ready for review | normal | Human approval needed |
| Blocked | critical | Clarification needed or other blocker |
| Complete | low | All micro-commits done |
| Failed | critical | Stage failure |

Works with any freedesktop-compliant notification daemon (mako, dunst, GNOME, KDE).

Requires `notify-send` to be installed:
```bash
# Debian/Ubuntu
sudo apt install libnotify-bin

# Arch
sudo pacman -S libnotify
```

## Workstream Context

Set a current workstream to avoid typing it repeatedly:

```bash
hashd use my_feature        # Set current workstream
hashd run --loop            # Operates on my_feature
hashd approve               # Still my_feature
hashd show                  # Still my_feature

hashd use                   # Show current workstream
hashd use --clear           # Clear current workstream
```

When a workstream context is set, you can still override it explicitly:

```bash
hashd use my_feature
hashd show other_feature  # Operates on other_feature, context unchanged
```

## Pair Programming Chat

`hashd chat` opens an AI pair programmer with persistent conversation history. Use `@` syntax to inject context:

```bash
hashd chat                    # Auto-detect context from current directory
hashd chat STORY-0001         # Explicit story context
hashd chat my-workstream      # Explicit workstream context
hashd chat --history          # View past conversation as markdown
```

**Available @ artifacts:**

| Artifact | Description |
|----------|-------------|
| `@diff` | Current git diff |
| `@log` | Latest stage log |
| `@review` | Review feedback |
| `@story` | Story details + criteria |
| `@timeline` | Story/workstream timeline |
| `@file:path` | Specific file content |
| `@clq` | Clarification history |
| `@reqs` | REQS.md content |
| `@spec` | SPEC.md content |
| `@commits` | Commit history |
| `@stories` | List of project stories |
| `@workstreams` | List of active workstreams |
| `@STORY-xxxx` | Cross-reference another story |
| `@BUG-xxxx` | Cross-reference a bug |

For full artifact inspection or manual edits, use the server-backed project
artifact commands: `hashd project reqs` / `hashd project reqs edit` and
`hashd project spec` / `hashd project spec edit`. The `@reqs` and `@spec` references
are prompt/chat context shortcuts.

`@file:path` is project-scoped. The path must resolve inside the project
directory. Planning treats file references as metadata only and never loads file
contents into prompts; agents read reachable project files on demand. A
planning-time warning is emitted when REQS or a story description references an
outside-project path so the operator can move the file into the project tree.

In TUI mode, press `C` from any screen to open chat. Type `@` to see autocomplete.

**Actionable chat:** When chatting in a story context, the AI can propose edits to story artifacts (acceptance criteria, title, problem statement, non-goals) and run safe read-only `hashd` commands. Each proposed action appears in a confirmation bar -- press `y` to apply or `n` to skip. Actions are logged to the story transcript.

## Directives

Directives are curated rules that guide AI implementation. They exist at three levels:

```
~/.config/hashd/directives.md        # Global user preferences
{repo}/directives.md              # Project rules
workstreams/{id}/directives.md    # Workstream-specific (rare)
```

**Why `directives.md` not `AGENTS.md`?** We want hashd to control when directives are passed to agents, not have agents auto-read them. This ensures agents only see these rules when we explicitly include them in prompts.

### Example directives.md

```markdown
# Project Directives

- No backward compatibility. We have zero users.
- Use sync.Once pattern for handler initialization
- Follow existing templ component patterns in internal/templates
- HTMX handlers should set HX-Trigger for related component updates
```

### Commands

```bash
hashd directives                       # View global directives
hashd directives all                   # View all (global + project)
hashd directives all -w <ws>           # View all including workstream
hashd directives project               # View project only
hashd directives workstream <ws>       # View workstream's only

hashd directives edit                  # Edit global in $EDITOR
hashd directives edit project          # Edit project in $EDITOR
hashd directives edit workstream <ws>  # Edit workstream's in $EDITOR

hashd directives ai-edit               # AI-assisted edit of global
hashd directives ai-edit project       # AI-assisted edit of project
hashd directives ai-edit workstream <ws>  # AI-assisted edit of workstream's
```

Directives are automatically included in implementation prompts.

## Commands

### Core Commands

| Command | Description |
|---------|-------------|
| `hashd plan` | Plan stories from REQS.md (saves suggestions) |
| `hashd plan list` | View current suggestions |
| `hashd plan story "title"` | Quick feature story (skips REQS discovery) |
| `hashd plan bug "title"` | Quick bug fix (skips REQS discovery, conditional SPEC update) |
| `hashd plan clone STORY-xxx` | Clone a locked story to edit |
| `hashd plan edit STORY-xxx` | Edit existing story (if unlocked) |
| `hashd plan reset` | Reclaim suggestions stranded by a dead flow or deleted story (unblocks discovery) |
| `hashd run [id]` | Run workstream or create from story |
| `hashd list` | List all stories and workstreams |
| `hashd show <id>` | Show story or workstream details |
| `hashd approve <id>` | Accept story or approve workstream gate |
| `hashd pr create [id]` | Create PR/MR on forge (for external review) |
| `hashd pr feedback <ws>` | View PR/MR review comments |
| `hashd merge [id] [--confirm\|-y] [--pr] [--no-push] [--fix] [--ai-resolve]` | Merge to main (`--pr`: via forge PR instead of direct merge) |
| `hashd close <id>` | Close story or workstream (abandon) |
| `hashd watch [id]` | Interactive TUI (dashboard, or detail for workstream/STORY-xxxx) |

### Watch UI Keybindings

The `hashd watch` TUI adapts keybindings to workstream status:

| Status | Key Actions |
|--------|-------------|
| `awaiting_human_review` | `[a]` approve, `[r]` reject, `[R]` reset |
| `complete` | `[P]` create PR, `[m]` merge, `[e]` edit microcommit |
| `pr_open` / `pr_approved` | `[r]` reject (pre-fills PR feedback), `[o]` open PR, `[a]` merge |

In PR states, `[r]` opens a modal pre-filled with forge feedback for editing.

**Diff mode** (`[d]` to enter): `[s]` side-by-side, `[I]` lineage, `[h]` hunk selection, `[space]` select hunk, `[f]` fullscreen, `Enter` lineage detail (in lineage).

### Telegram Bot

The Telegram bot covers the full workflow from mobile. Send `/` for the button menu or type commands directly:

| Category | Commands |
|----------|----------|
| **Inspect** | `/status`, `/list`, `/show <id>`, `/log <id>` |
| **Execute** | `/run <id>`, `/review <id>` |
| **Gate** | `/approve <id>`, `/reject <id> [feedback]` |
| **Lifecycle** | `/merge <id>`, `/close <id>`, `/pr <id>` |
| **Plan** | `/plan`, `/story <title>`, `/bug <title>`, `/answer [id]` |
| **Utility** | `/search <query>`, `/use [id|clear]`, `/project [name]` |

**Setup:**

1. Create a bot via [@BotFather](https://t.me/BotFather) (`/newbot`), copy the token:
   ```bash
   hashd telegram bot <YOUR_TOKEN>
   ```
2. Get your user ID from [@userinfobot](https://t.me/userinfobot), then allow it and set as chat target:
   ```bash
   hashd telegram allow <YOUR_USER_ID>
   hashd telegram chat-id <YOUR_USER_ID>
   ```
3. Start the bot:
   ```bash
   hashd telegram start
   ```

The bot also auto-starts when you run `hashd run` or `hashd watch`.

### Supporting Commands

| Command | Description |
|---------|-------------|
| `hashd use [id]` | Set/show current workstream context |
| `hashd run [id] --loop` | Run until blocked or complete |
| `hashd run [id] --yes` | Skip confirmation prompts |
| `hashd run [id] --verbose` | Show implement/review exchange |
| `hashd log [id]` | Show workstream timeline |
| `hashd review [id]` | Show latest saved final review |
| `hashd lineage <target>` | Trace code lineage (file, SHA, or STORY/BUG ID) |
| `hashd lineage export <sha\|STORY-xxxx\|BUG-xxxx> --format slsa\|in-toto` | Export attestation JSON for a tracked commit or story |
| `hashd lineage verify` | Validate commit hash chain integrity |
| `hashd reject [id] -f "..."` | Reject with feedback (context-aware) |
| `hashd reject [id] --reset` | Discard changes, start fresh (human gate only) |
| `hashd diff [id]` | Show workstream diff |
| `hashd skip [id]` | Mark commit as done without changes |
| `hashd reset [id]` | Keep the plan, reset the worktree to baseline, redo the implementation |
| `hashd replan [id] [-f "..."]` | Regenerate the plan from a clean base |
| `hashd refresh [id]` | Refresh touched files |
| `hashd conflicts [id]` | Check for file conflicts |
| `hashd archive work` | List archived workstreams |
| `hashd archive stories` | List archived stories |
| `hashd open <id> [--force]` | Resurrect archived workstream |
| `hashd answer list` | List entities with pending clarifications |
| `hashd answer show <entity>` | Show pending questions for a story or workstream |
| `hashd answer <entity> "<text>"` | Bundle-answer pending clarifications and dispatch the next agent run |
| `hashd directives` | View/edit project directives |
| `hashd workstream add-commit <ws> "title"` | Add AI-generated micro-commit to plan |
| `hashd workstream edit-commit <ws> <id>` | Edit a micro-commit's title/description |
| `hashd workstream feedback <ws> "text"` | Add feedback to workstream |
| `hashd workstream remove <ws>` | Remove orphaned workstream |
| `hashd plan retry STORY-xxx` | Retry failed planning run |
| `hashd plan resurrect STORY-xxx` | Resurrect abandoned story |

### Project Commands

| Command | Description |
|---------|-------------|
| `hashd project add <path>` | Register a new project (wizard by default; investigate-then-execute also supported) |
| `hashd project add <path> --no-interview` | Register a new project without prompts, using stored defaults or explicit overrides |
| `hashd project list` | List registered projects |
| `hashd project use [name] [--clear]` | Set/show/clear current project context |
| `hashd project show` | Show current project configuration |
| `hashd project interview` | Reconfigure project (build/test commands, merge mode, autonomy) |
| `hashd project remove <name> -y` | Remove a project without confirmation prompt |
| `hashd project config list` | List effective project config, highlighting project overrides in TTY output |
| `hashd project config diff` | Show project overrides against inherited system/default config |
| `hashd project config show <key>` | Show effective value, source, override stack, and schema description |
| `hashd project config get <key>` | Print one effective config value |
| `hashd project config set <key> <value>` | Set config value |
| `hashd project config reset <key>` | Remove one project override |
| `hashd project config reset --all` | Remove all project overrides while preserving project identity |
| `hashd project describe` | Show current project description |
| `hashd project describe --suggest` | AI-generate and save a description suggestion |
| `hashd project tech` | Show current project tech stack |
| `hashd project tech --suggest` | AI-analyze and save a tech stack suggestion |
| `hashd project reqs [show]` | Show configured REQS artifact content through hashd-server |
| `hashd project reqs edit` | Edit configured REQS in `$EDITOR`; WIP sections are protected |
| `hashd project spec [show]` | Show configured SPEC artifact content through hashd-server |
| `hashd project spec edit` | Edit configured SPEC in `$EDITOR` through the server-side commit flow |
| `hashd project repo list [--json]` | List repos registered under the current project |
| `hashd project repo show <name> [--json]` | Show one registered repo |
| `hashd project repo add <path> --status <status>` | Add a repo to the current project |
| `hashd project repo set-status <name> <status>` | Reclassify a repo as primary, active, reference, or ignore |
| `hashd project repo set-path <name> <new-path>` | Update a repo's relative path within the project |
| `hashd project repo edit <name> ...` | Update per-repo commands and metadata |
| `hashd project repo remove <name>` | Soft-delete a repo entry (status=`ignore`) |
| `hashd project repo prune` | Hard-delete ignored repos whose paths no longer exist |

`hashd project describe --suggest` and `hashd project tech --suggest` persist the AI result to
`config.yaml` by default. Use `--no-save` for a dry run, or `-y` to skip the interactive
save prompt. `hashd project show`, `hashd project describe`, `hashd project tech`, and
`hashd project list` warn when saved AI-generated metadata may be stale relative to the
current `reqs_path` or fallback source files.

`hashd project reqs` and `hashd project spec` read the configured artifacts through
hashd-server, so remote CLI clients do not need local filesystem access to the
repository. Their `edit` subcommands open the current artifact in `$EDITOR`, send
the replacement back with a compare-and-swap head SHA, and let the server commit
and push exactly that artifact change. The server rejects stale edits, dirty
repos, symlink artifact paths, and any REQS edit that changes text between
`BEGIN WIP` and `END WIP` markers owned by active stories.

### Observability Commands

| Command | Description |
|---------|-------------|
| `hashd system-log` | View system event log |
| `hashd prompts list` | List prompt templates |
| `hashd prompts show <name>` | Show prompt content |
| `hashd prompts edit <name>` | Edit prompt override |
| `hashd agents` | Show installed AI agents and stage assignments |
| `hashd doctor` | Validate setup and diagnose issues |
| `hashd restart [component] [-y]` | Restart infrastructure (Prefect, ZMQ, messengers) |
| `hashd search <query> [--kind kind] [-n limit]` | Full-text search across stories, events, reviews, chat (default limit: 20) |

### Smart ID Routing

Commands automatically route based on ID prefix:
- `STORY-xxx` - Routes to story commands (e.g., `hashd show STORY-0001`)
- `lowercase_id` - Routes to workstream commands (e.g., `hashd show my_feature`)

Commands marked with `[id]` use the current workstream context if no ID is provided.

When reopening archived workstreams, `hashd open` analyzes staleness by comparing file changes on the branch against the default branch. It prints commits-behind, overlapping files, default-branch line churn, and a low/moderate/high/critical severity score. High and critical reopens require interactive confirmation, or `--force` for non-interactive use.

## Lifecycle

Stories flow: `drafting` -> `draft` -> `accepted` -> `implementing` -> `implemented` (also: `draft_failed`, `editing`, `abandoned`)

Workstreams loop: `breakdown` -> `implement` -> `test` -> `review` -> `human_review` -> `commit` (repeat for each micro-commit)

See **[WF.md](WF.md)** for detailed lifecycle documentation.

## Context-Aware Reject

The `hashd reject` command adapts its behavior based on workstream state:

### During Human Review Gate

When status is `awaiting_human_review` (mid-micro-commit):

```bash
hashd reject my_feature -f "Fix the null check"    # Iterate with feedback
hashd reject my_feature --reset                    # Discard, start fresh
```

This writes a rejection file and continues the run loop.

### After All Commits Complete

When all micro-commits are done (pre-merge):

```bash
hashd reject my_feature -f "address review concerns"  # Any non-empty feedback; server appends review concerns automatically
hashd reject my_feature -f "also fix the tests"       # Add explicit guidance alongside the auto-included review concerns
```

This:
1. Parses the final review for concerns (## Concerns section)
2. Generates a fix micro-commit (COMMIT-*-FIX-001)
3. Appends it to the plan
4. Sets status back to `active`

### After PR Created

When a PR exists:

```bash
hashd pr feedback my_feature                        # View PR comments
hashd reject my_feature -f "Fix the null check"     # Create fix commit
```

For PR states (`pr_open`, `pr_approved`):
- feedback text is **required** (via `-f`/`--feedback`, no auto-fetch)
- Use `hashd pr feedback` to view comments first
- In `hashd watch`, the `[r]` modal pre-fills with PR feedback for editing

## Workflow Execution

Hashd uses [Prefect](https://www.prefect.io/) for workflow orchestration. The Prefect server and worker are started automatically when needed:

```bash
# Run a workstream (Prefect starts automatically)
hashd run my_feature  # Submits to Prefect, returns immediately

# Monitor progress
hashd watch my_feature  # Interactive TUI
hashd show my_feature   # Status snapshot
```

The `hashd run` command submits work to the Prefect worker and returns immediately. Use `hashd watch` or `hashd show` to monitor execution.

### Automatic Retries

Prefect automatically retries transient failures:

| Stage | Retries | Delay | Handles |
|-------|---------|-------|---------|
| implement | 2 | 10s | Agent timeouts, API errors |
| test | 2 | 5s | Subprocess timeouts |
| review | 1 | 30s | Claude rate limits |
| qa_gate | 1 | 5s | Validation errors |
| update_state | 2 | 5s | Git push failures |

## Requirements

See **[QUICKSTART.md](QUICKSTART.md)** for full installation instructions including platform-specific commands.

- **Git** - the only OS-level prerequisite. (Python 3.11+ is handled by the installer; it bootstraps a runtime via [uv](https://github.com/astral-sh/uv) when your system has none.)
- **At least one AI coding agent** - Claude Code by default (see [Agent Configuration](#agent-configuration)). Agent CLIs are npm packages, so installing one needs **Node.js 20+**; that is the agent's prerequisite, not hashd's. `hashd doctor` prints the exact OS-correct install commands.
- A forge CLI for your host: [gh](https://cli.github.com/) (GitHub), [glab](https://gitlab.com/gitlab-org/cli) (GitLab), [bkt](https://github.com/avivsinai/bitbucket-cli) (Bitbucket), or [tea](https://about.gitea.com/products/tea/) (Gitea). The curl installer auto-installs pinned prebuilt versions; links are manual fallbacks.
- [delta (git-delta)](https://github.com/dandavison/delta) - bundled TUI side-by-side, syntax-highlighted, word-level diff renderer (auto-installed by the installer / `setup.sh`)
- [gitleaks](https://github.com/gitleaks/gitleaks) - secrets scanning at project setup (auto-installed by the installer / `setup.sh`)
- [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) - bundled code intelligence backend (auto-fetched by the installer / `setup.sh`; setup fails if the pinned binary cannot be fetched or executed)
- A project with tests (Makefile, package.json, Taskfile, etc.)

Authenticate the forge you use:

```bash
gh auth login                         # GitHub
glab auth login                       # GitLab
bkt auth login --kind cloud --web     # Bitbucket OAuth
bkt auth login --kind cloud --web-token # Bitbucket API-token alternative
tea login add --name work --url https://git.example.com --token $TOKEN  # Gitea
```

Minimum agent/tool versions verified for this release:

| Tool | Minimum | Notes |
|------|---------|-------|
| Claude Code | 2.1.154 | required - the default agent for every stage |
| Codex CLI | 0.130.0 | optional - swap in per stage if you want it |
| uv | 0.11+ | |
| Go | 1.26+ | |

Run `hashd doctor` to check your setup.


## Configuration

All project configuration lives in a single `config.yaml` per project. Generated by `hashd project add` or `hashd project interview`. You can also edit it manually. See `config.sample.yaml` for all available settings with documentation.

### config.yaml

```yaml
# --- Project Identity ---
name: "myproject"
repo_path: "/path/to/repo"
default_branch: "main"
reqs_path: "REQS.md"
spec_path: "SPEC.md"

# --- Build & Test ---
test_cmd: "make test"            # impl-phase tests; falls through to merge_gate_test_cmd if empty
build_cmd: ""
merge_gate_test_cmd: "make test" # merge-time tests; the visible failure surface
test_timeout: 300
merge_mode: "local"              # "local" or "pr"
forge: ""                        # auto-detected from remote; "github", "bitbucket", "gitlab", "gitea"

# --- Autonomy ---
autonomy: "gatekeeper"          # "supervised", "gatekeeper", or "autonomous"

# --- Optional Overrides ---
# workflow:
#   max_review_attempts: 5
# stages:
#   implement:
#     timeout: 2400
```

Run `hashd doctor --show-defaults` to see all available settings and their default values.
Run `hashd doctor --reset-to-defaults` to strip behavioral overrides and restore defaults while preserving identity and build settings.

Use `hashd config ...` for system-wide overrides and `hashd project config ...` for project overrides. `list` shows the effective config and marks overridden values on TTYs, `diff` shows only overrides with their baseline values, and `show <key>` prints the effective value plus its Default/System/Project provenance. `reset --all` clears all overrides at the invoked scope. Shell completion includes config verbs and schema-backed key names.

### Test Command Configuration

Each project (or each repo, in multi-repo mode) has two test command fields:

- `test_cmd` — runs during implementation, after each commit. Provides per-commit feedback so agents catch regressions early.
- `merge_gate_test_cmd` — runs at merge time, before changes land. Final validation.

For most projects, set them to the same command. The CLI defaults `test_cmd` to **fall through to `merge_gate_test_cmd`** when unset, so configuring just the merge gate is sufficient for "run the same tests at both gates" semantics. `hashd project show` renders this as `Test command: (falls through to merge gate test)` so the implication is visible.

Set `test_cmd` explicitly only when you want a faster subset for per-commit feedback (e.g. `test_cmd: "pytest -m fast"` and `merge_gate_test_cmd: "pytest"` for fast-vs-full split).

Set `tests_skipped: true` to acknowledge that no test command is configured. This affects merge-gate enforcement (the gate proceeds with an encouragement event rather than hard-failing). Note: today this flag does **not** suppress the impl-phase test stage — that path is gated only by the effective command being empty. If you want no impl-phase tests, leave both fields empty; the impl-phase will skip silently.

Configure with:

```bash
hashd project repo edit <repo-name> --test-cmd "..." --merge-gate-test-cmd "..."
```

### Workspace Hooks

Setup and teardown commands run automatically during workstream lifecycle:

```yaml
hooks:
  setup: "npm install && cp ../.env .env"
  teardown: "docker-compose -p hashd-${HASHD_WORKSTREAM_ID} down"
  timeout_seconds: 600               # default: 300 (5 min)
```

- **setup** runs in the worktree after creation, before baseline tests. Failure records `provision_error` and keeps the workstream at `provisioning`; `runtime_status` reports `provisioning / failed`. Retry by re-dispatching with `hashd run` (the next provisioning attempt clears `provision_error` on success).
- **teardown** runs in the worktree before removal (close, merge, workstream remove). Failure is logged but doesn't block cleanup.
- **timeout_seconds** applies to both hooks. Hooks killed after the timeout get an actionable diagnostic pointing at the config key.

Hook subprocesses inherit the full parent environment plus these HASHD_* context variables:

| Variable | Description |
|----------|-------------|
| `HASHD_PROJECT_NAME` | Project name |
| `HASHD_WORKSTREAM_ID` | Workstream identifier |
| `HASHD_STORY_ID` | Story ID (e.g., STORY-0042) |
| `HASHD_WORKTREE_PATH` | Path to git worktree |
| `HASHD_BASE_BRANCH` | Default branch (e.g., main) |

See **[docs/HOOKS.md](docs/HOOKS.md)** for the full reference -- lifecycle details, more examples, the REST call flow, and troubleshooting recipes are in **[docs/TROUBLESHOOTING.md#workspace-hook-failures](docs/TROUBLESHOOTING.md#workspace-hook-failures)**.

### Multi-Repo Projects

hashd supports projects that span multiple git repositories (e.g., a Go backend + React frontend in separate repos). The principle: **project-level planning, repo-level execution**.

**Supported shapes:**
- Single repo: one Git repo, including monorepos for now.
- Multi-repo container: a non-repo directory containing child Git repos; `hashd project add` can initialize a local-only control repo at the container root.
- Superproject: a parent Git repo with submodules; treated as a multi-repo variant.

**Directory layout:**

```
platform/              # project root (git repo, may be local-only)
  REQS.md              # requirements live here
  backend/             # sub-repo (its own git history + remote)
    SPEC.md
    go.mod
  frontend/            # sub-repo (its own git history + remote)
    SPEC.md
    package.json
```

**Setup:** `hashd project add /path/to/platform` detects whether the path is a single repo, a multi-repo container, or a superproject and then prompts for the right setup flow. For agent-driven onboarding, the canonical pattern is `hashd project add /path --no-interview --suggest` followed by `hashd project add /path --no-interview`; see [QUICKSTART.md](QUICKSTART.md) for the full two-flag walkthrough. Use `--primary <repo>` to pin the primary sub-repo, `--active <repo>` (repeatable) or `--all-active` to mark non-primary repos active, `--repo-skip-test <repo>` to explicitly acknowledge a repo with no test command, and `--repo-skip-build <repo>` to explicitly acknowledge a repo with no build command. For container bootstrap, root-level files are committed into the local control repo by default; root-level directories require an explicit `--commit-root-dirs` in non-interactive mode. Each registered repo gets its own test command, build command, merge mode, default branch, and status.

**Config:** project-level settings live in `config.yaml`; per-repo state for multi-repo projects lives in SQLite `project_repos`, not in a `repos:` block in YAML.

**Repo management after setup:** use `hashd project repo list`, `hashd project repo show <name>`, `hashd project repo add <path> --status <status>`, `hashd project repo set-status <name> <status>`, `hashd project repo edit <name> ...`, `hashd project repo set-path <name> <new-path>`, `hashd project repo remove <name>`, and `hashd project repo prune`.

**How it works:**
- During planning, stories are automatically routed to the correct repo based on content
- Each workstream targets one repo -- worktrees, branches, and merges happen in that repo
- REQS.md stays at the project root; SPEC.md is per-repo
- Inspect or edit the configured REQS and SPEC paths with `hashd project reqs` and
  `hashd project spec`; the server applies those paths and commits successful
  manual edits
- `hashd run`, `hashd merge`, `hashd watch` all work the same -- they resolve the target repo automatically

### Build and Test Execution

When you run `hashd project add` or `hashd project interview`, the CLI detects your build system (Makefile, Taskfile, package.json, etc.) and prompts you to confirm or customize the commands:

```
Detected: Taskfile
  Test command: task test
  Build command: task build

Test command [task test]:
Build command (optional, press Enter to skip) [task build]:
Merge gate test command [task test]:
```

The orchestrator runs exactly what you configure:

1. **BUILD_CMD** (if set) - runs before tests
2. **TEST_CMD** - runs the test suite

#### Projects with Code Generation

If your project uses code generation (sqlc, templ, protobuf, OpenAPI, etc.), your build and test commands must trigger generation first. Wire generation as a dependency in your build system:

**Taskfile:**
```yaml
tasks:
  generate:
    cmds:
      - sqlc generate
      - templ generate

  build:
    deps: [generate]
    cmds:
      - go build ./...

  test:
    deps: [generate]
    cmds:
      - go test ./...
```
Then enter `task build` and `task test` when prompted.

**Makefile:**
```makefile
.PHONY: generate build test

generate:
	sqlc generate
	templ generate

build: generate
	go build ./...

test: generate
	go test ./...
```
Then enter `make build` and `make test` when prompted.

**npm (package.json):**
```json
{
  "scripts": {
    "generate": "openapi-generator generate -i spec.yaml -o src/api",
    "prebuild": "npm run generate",
    "build": "tsc",
    "pretest": "npm run generate",
    "test": "jest"
  }
}
```
Then enter `npm run build` and `npm test` when prompted.

The key is ensuring generated code exists before compilation, whether it's a fresh worktree or an existing checkout.

### Autonomy Modes

Autonomy is configured per-project via `hashd project interview` or directly in `config.yaml`:

| Mode | Behavior |
|------|----------|
| **supervised** | Human approves at each gate |
| **gatekeeper** (default) | Auto-continue if AI confidence >= 90%, human approves at merge |
| **autonomous** | Auto-continue commits + auto-merge if thresholds met |

Override per-run: `hashd run --supervised`, `hashd run --gatekeeper`, or `hashd run --autonomous`

```yaml
# In config.yaml
autonomy: "gatekeeper"
modes:
  gatekeeper:
    commit_threshold: 0.85   # Override default 0.90
```

## Merge Behavior

### Automatic Conflict Resolution

When using the PR workflow (`hashd merge --pr` or `merge_mode: pr`), PRs may become conflicting if main moves ahead. The merge command handles this automatically:

1. Fetches latest main
2. Attempts rebase of the PR branch
3. Force-pushes rebased branch (using `--force-with-lease`)
4. Re-checks PR status

If rebase fails due to merge conflicts, blocks for human resolution with instructions.

### Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Force push loses work | `--force-with-lease` prevents overwriting if branch changed |
| Infinite rebase loop | Max 3 attempts before blocking for human |
| Forge API timing | 2s delay after push; worst case run `hashd merge` again |
| Review bypass | Checks for `REVIEW_REQUIRED` status from forge |

### Review Requirements

The merge respects the forge's configured review requirements:

- **APPROVED** - Merge proceeds
- **PENDING/None** - Merge proceeds (assumes no review required)
- **CHANGES_REQUESTED** - Blocks; use `hashd reject` to generate fix commit from PR feedback
- **REVIEW_REQUIRED** - Blocks until required reviews complete

### Check Requirements

- **success** - Merge proceeds
- **pending** - Merge proceeds (for slow bots like CodeRabbit)
- **failure** - Blocks until checks pass

<!-- TODO: Reassess pending check behavior. Currently allows merge with pending checks
     to avoid blocking on slow bots (CodeRabbit). Consider:
     - Configurable list of ignorable checks
     - Timeout-based promotion of pending to success
     - Separate "required" vs "optional" check categories
-->

## Agent Configuration

Hashd supports seven CLI coding agents. Any agent can be assigned to any workflow stage, as long as it supports the stage's required invocation shape.

### Supported Agents

| Agent | Binary | Status | Shapes | Install | Auth |
|-------|--------|--------|--------|---------|------|
| **Claude Code** | `claude` | active | print, json, edit, review, review_resume, implement, implement_resume | `npm i -g @anthropic-ai/claude-code` | Anthropic API key |
| **Codex** | `codex` | active | print, json, edit, review, review_resume, implement, implement_resume | `npm i -g @openai/codex` | OpenAI API key |
| **GitHub Copilot** | `copilot` | available | print, json, edit, review, review_resume, implement, implement_resume | `npm i -g @github/copilot` | GitHub Copilot subscription |
| **Gemini CLI** | `gemini` | available | print, json, edit, review, review_resume, implement, implement_resume | `npm i -g @google/gemini-cli` | Google account (free) |
| **OpenCode** | `opencode` | available | print, json, review, review_resume, implement, implement_resume | `go install github.com/opencode-ai/opencode@latest` | Depends on model |
| **Kimi Code** | `kimi` | available | print, json, edit, review, review_resume, implement, implement_resume | `uv tool install kimi-cli` | Moonshot (~$19/mo) |
| **Qwen Code** | `qwen` | available | print, json, edit, review, review_resume, implement, implement_resume | `npm i -g @qwen-code/qwen-code` | Qwen OAuth (free) |

**Status:** `active` = tested and verified. `available` = config defined, not yet verified (assign with `--force`).

### Quick Setup

By default, **Claude** handles every stage -- planning, implementation, and review. Any supported agent can be swapped in per stage.

```bash
hashd agents                                # See installed agents and stage assignments
hashd agents --suggest                      # Scan agents and apply a default for all stages
hashd config stages-use codex               # Use one agent for every stage system-wide
hashd project config set coder codex        # Use Codex for implementation (this project)
hashd project config set planner gemini     # All non-implement stages
hashd project config set stage.review gemini  # Single stage override
```

### Stage Reference

| Phase | Stage | Default Agent | Shape |
|-------|-------|---------------|-------|
| Planning | `detect` | claude | json |
| Planning | `pm_discovery` | claude | print |
| Planning | `pm_refine` | claude | print |
| Planning | `pm_edit` | claude | print |
| Planning | `pm_route` | claude | print |
| Planning | `pm_annotate` | claude | edit |
| Planning | `pm_describe` | claude | print |
| Implementation | `breakdown` | claude | review |
| Implementation | `implement` | claude | implement |
| Implementation | `implement_resume` | claude | implement_resume |
| Review | `concern_triage` | claude | print |
| Review | `review` | claude | review |
| Review | `review_resume` | claude | review_resume |
| Review | `fix_generation` | claude | json |
| Review | `plan_add` | claude | json |
| Completion | `final_review` | claude | review |
| Completion | `pm_spec` | claude | json |
| Completion | `pm_docs` | claude | edit |

### Template Variables

Command templates support these variables:

| Variable | Description | Used In |
|----------|-------------|---------|
| `{prompt}` | The prompt text | All stages |
| `{worktree}` | Path to git worktree | `implement`, `implement_resume` |
| `{session_id}` | Session UUID for resuming | `review_resume`, `implement_resume` |

If `{prompt}` is in the command template, it's passed as a CLI argument. Otherwise, the prompt is passed via stdin (useful for multi-line prompts).

### Missing Tool Detection

If a required tool isn't installed, hashd will fail early with a clear error:

```
ERROR: Required tool 'codex' is not installed.

Stages that need it: implement, implement_resume

To fix this, either:
  1. Install codex: npm i -g @openai/codex
  2. Add stage overrides to config.yaml in your project directory:
     ...
```

See **[docs/AGENT_MANAGEMENT.md](docs/AGENT_MANAGEMENT.md)** for agent switching, prompt management, and per-project overrides.

## Local-Only Mode

Hashd works without a git remote configured. When no `origin` remote exists:

- Rebase checks are skipped (no fetch/rebase against remote main)
- Conflict detection against remote is skipped
- PR features are unavailable
- Workstreams complete locally after tests pass

This is useful for:
- Local experimentation before pushing
- Air-gapped development environments
- Learning hashd without setting up a remote

To enable full features later:
```bash
git remote add origin <url>
```

## Connectors

Connectors are hashd's plugin system for external integrations. They're auto-discovered at startup from packages that register the `hashd.connectors` entry point group. Install or remove a connector package and core keeps working without hard references.


### Included connectors

| Connector | What it does | Docs |
|---|---|---|
| **GitHub Sync** | Sync stories with GitHub Issues -- pull, push, auto-sync via labels | [docs](docs/CONNECTORS.md#github-sync) |
| **Jira Sync** | Sync stories with Jira issues -- pull, push, status tracking | [docs](docs/CONNECTORS.md#jira) |
| **Figma** | Import and reference Figma designs -- `@figma:frame` in stories, ACs, chat | [docs](docs/CONNECTORS.md#figma) |

### Third-party connectors

None yet. If you build a connector for Linear, Shortcut, or another tool, open a PR or publish it as a pip package with an `hashd.connectors` entry point.

## Troubleshooting

See **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** for common issues:
baseline test failures, stale flows, worktree cleanup, and missing tools.

## License

BSL 1.1 (Business Source License)

See [LICENSE](LICENSE.md) for details.
