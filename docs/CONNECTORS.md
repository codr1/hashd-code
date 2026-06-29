# Connector System Specification

## Overview

Connectors extend hashd with external integrations (Figma, GitHub, Bitbucket, Jira). They're auto-discovered at startup through the `hashd.connectors` entry point group. Core never references a specific connector.

See [Building Connectors](orchestrator/connectors/README.md) for the developer guide.

---

## 1. Connector Contract

Every connector declares its capabilities via module-level attributes in `__init__.py`. All are optional.

```python
# packages/hashd-connector-my/src/hashd_connector_my/__init__.py

CONNECTOR_NAME = "my_connector"                    # unique, used as @ namespace
CONFIG_SECTION = "my_config"                       # config.yaml section

CLI_COMMANDS = {
    "mycommand": (register_fn, dispatch_fn),       # register returns parser, dispatch takes (args, ops_dir, project_config)
}

DOCTOR_CHECKS = [check_fn]                         # (project_dir) -> list[DiagnosticResult]
IS_CONFIGURED = is_configured_fn                   # (project_dir) -> bool

ARTIFACT_RESOLVER = resolver_fn                    # (project_dir, refs: list[str], fetch: bool) -> dict[str, ResolvedArtifact]
CACHE_DIR_NAME = "my_connector"                    # .cache/<this>/

TOOLS = [                                          # list of ToolSpec
    ToolSpec(name="my_browse", description="...",
             parameters={"query": "..."}, handler=fn),
]

AUTOCOMPLETE = autocomplete_fn                     # (project_dir, partial) -> list[(value, description)]
```

### Discovery

`discover_connectors()` finds connectors from one source:

1. **Entry points**: pip-installed packages declaring the `hashd.connectors` group

Import errors are logged and skipped. Namespace collisions (two connectors with the same `CONNECTOR_NAME`) are fatal -- hashd refuses to proceed.

Shipped connectors are registered in `pyproject.toml`:
```toml
[project.entry-points."hashd.connectors"]
github = "hashd_connector_github"
figma = "hashd_connector_figma"
jira = "hashd_connector_jira"
```

### Integration points

| File | What |
|---|---|
| `cli.py` | Registers CLI commands from `CLI_COMMANDS` |
| `commands/doctor.py` | Runs `DOCTOR_CHECKS` for configured connectors |
| `lib/ref_resolver.py` | Dispatches `@connector:ref` to `ARTIFACT_RESOLVER` |
| `lib/tool_dispatch.py` | Loads `TOOLS` when `@connector` detected in prompt |
| `lib/agents_config.py` | Injects MCP config for `TOOLS` into agent commands |
| `lib/chat_context.py` | Yields `AUTOCOMPLETE` completions for @ popup (server-side Python) |
| `server/api/autocomplete.go` | REST endpoint for TUI autocomplete (reads connector caches) |

---

## 2. @connector:ref Resolution

### How it works

`resolve_refs()` scans text for `@connector:ref` patterns, dispatches to the connector's `ARTIFACT_RESOLVER`, and replaces refs with file metadata. Resolution happens BEFORE any prompt reaches an agent.

There are two resolver implementations sharing the same connector-host surface:

- **Python harness** (`lib/ref_resolver.py`) -- used by the planner, tool dispatch, and the legacy Python chat path. Connector dispatch only; built-in artifacts (`@diff`, `@story`, ...) are handled separately by `lib/chat_context.py`.
- **Go server** (`server/internal/refs/`) -- used by the server-side chat generation path (`POST /chat/messages`). One entry point unfolds every `@`-reference in place so the agent never sees a raw token: built-in artifacts load **locally in Go** from the project DB / git / filesystem, and connector references dispatch through the same connector host via `server/internal/connectors`. This is the Go-canonical home as the Python chat path is retired.

Both call the identical connector-host verbs (`capabilities`, `resolve_artifacts`), so connectors plug into either resolver unchanged.

### Reference types

| Pattern | What happens |
|---|---|
| `@figma:job-list` | Resolves to cached file references (JSON, SVG, TXT) |
| `@github:42` | Resolves to cached/fetched GitHub issue details |
| `@jira:PROJ-123` | Resolves to cached/fetched Jira issue details |
| `@jira:123` | Resolves using default project key from config |
| `@jira:OTHER:456` | Resolves to `OTHER-456` (cross-project) |
| `@figma` (bare) | Resolves to tool listing + cached artifacts manifest |
| `@diff`, `@story`, etc. | Built-in refs -- not routed to connectors |

### ARTIFACT_RESOLVER contract

Batch interface -- receives all refs for the connector at once:

```python
def resolver(project_dir: Path, refs: list[str], fetch: bool) -> dict[str, ResolvedArtifact]:
```

- `refs=[""]` for bare `@connector`
- `fetch=True`: check staleness, fetch on cache miss (interactive contexts)
- `fetch=False`: cache only, error if missing (batch stages)
- Returns `ResolvedArtifact` with file references (path, format, size, description) or error
- Never raises -- errors in the `ResolvedArtifact.error` field

### Resolution output

Specific refs get file metadata:
```
@figma:job-list resolved to:
  Source: Figma: Job List (375x812pt)
  Figma source JSON: .cache/figma/frames/job-list.json (48KB)
  SVG visual export: .cache/figma/frames/job-list.svg (14KB)
  Structural text summary: .cache/figma/frames/job-list.txt (2KB)
```

Bare refs get tool listing + cached data:
```
@figma capabilities:
  Available tools:
    figma_browse(query) -- Browse Figma file pages and frames
    figma_fetch(name) -- Fetch a specific Figma frame's cached file paths
  Cached data:
    Figma artifact listing: .cache/figma/listing.txt (245B)
```

### Error handling

Resolution failure triggers a human gate:
- Interactive: retry/continue/abort prompt. Continue allows optional user context.
- Non-interactive (`--yes`): continues with missing-artifact note injected.
- Prefect flows: transition to blocked state.

### Deduplication

Same ref appearing multiple times: first occurrence gets full metadata, subsequent get `(see @connector:ref above)`.

### Substitution safety

`apply_substitutions()` uses context-aware regex:
- Bare `@mock` won't match inside `@mock:test` (colon in negative lookahead)
- `@figma:job` won't match inside `@figma:job-list` (word/hyphen boundary)

---

## 3. Connector-Provided Tools

### ToolSpec

```python
@dataclass(frozen=True)
class ToolSpec:
    name: str                  # globally unique, model-facing
    description: str           # one-line for prompt
    parameters: dict[str, str] # param_name -> description
    handler: Callable          # (project_dir, args: dict) -> str
    include_stages: list[str]  # empty = all stages
    exclude_stages: list[str]  # empty = no exclusions
```

### Two delivery paths

**Prompt-based dispatch** (for `hashd chat` one-shot mode):
- Tools described in a prompt section appended by `format_tools_section()`
- Model signals tool calls via `tool_call` fenced blocks
- Harness parses, dispatches to handler, injects result, re-invokes
- Max 10 iterations per turn, human continuation at limit

**MCP server** (for agent stages -- implement, review):
- `mcp_server.py` wraps connector tools via FastMCP
- `mcp_config.py` generates per-agent config (7 agents supported)
- Auto-injected into agent commands via `get_stage_command()`
- Agents call tools natively -- no prompt-based dispatch needed

### Tool loading

Lazy -- only when `@connector` is detected in the prompt:
- `@figma:job-list` or bare `@figma` -> load Figma tools
- No `@figma` in prompt -> no Figma tools

### Error handling

Tool failures injected as result text (not raised). Model is instructed to stop if the error is critical. Errors surfaced to human at next opportunity. Results truncated at 100KB.

---

## 4. Per-Project Artifact Cache

Each connector gets a cache directory:

```
projects/hbc/.cache/<connector_name>/
```

The connector owns its cache layout. Core doesn't read it directly -- the `ARTIFACT_RESOLVER` manages the cache.

### Cache lifecycle

- **Populate**: `hashd <connector> import` or fetch-on-miss
- **Refresh**: `hashd <connector> sync` or staleness check (profile-dependent)
- **Read**: `ARTIFACT_RESOLVER` reads from cache, returns file references
- **Inspect**: files are plain text/JSON/SVG, human-readable

### Cache strategy

Connectors declare `CACHE_STRATEGY` to control workstream behavior:

- `"live"` (default): always reads from the shared project cache. Used by GitHub and Jira (cheap API calls, data changes frequently).
- `"snapshot"`: cache is frozen into the workstream ops dir at provisioning time. Implementation reads from the snapshot, zero API calls. Used by Figma on conservative/standard profiles (6 API calls/month on free tier).
- Callable `(project_dir) -> str`: dynamic strategy. Figma uses this to go live on aggressive (enterprise) profiles.

Snapshot is copied by `snapshot_connector_caches()` during `provision_workstream()`. The resolver reads from the workstream snapshot via `contextvars` without changing the `ARTIFACT_RESOLVER` interface.

---

## 5. MCP Server

`orchestrator/mcp_server.py` -- FastMCP stdio server that exposes connector tools to AI agents.

### How it works

1. Orchestrator writes MCP config before agent invocation (format varies per agent)
2. Agent starts the hashd MCP server as a stdio subprocess
3. Server discovers configured connectors, registers their tools with typed signatures
4. Agent calls tools natively during execution
5. Server logs timing for every tool call and startup

### Supported agents

| Agent | Config mechanism |
|---|---|
| Claude Code | `--mcp-config` flag with JSON file |
| Codex | `.codex/config.toml` in worktree |
| Gemini CLI | `.gemini/settings.json` in worktree |
| OpenCode | `.opencode.json` in worktree |
| Kimi Code | `--mcp-config-file` flag with JSON file |
| Qwen Code | `.qwen/settings.json` in worktree |

File-based configs are excluded from git via `.git/info/exclude`.

---

## 6. Shipped Connectors

### GitHub

GitHub issue reference resolver. Use `@github:42` in stories, acceptance
criteria, or chat to embed issue context. The connector reads issue details on
demand and caches them; it does not create stories, create issues, or run a sync
daemon.

See [packages/hashd-connector-github/src/hashd_connector_github/README.md](packages/hashd-connector-github/src/hashd_connector_github/README.md).

### Figma

Design context integration. Import frames, reference in stories/ACs/chat, browse via tools.

See [packages/hashd-connector-figma/src/hashd_connector_figma/README.md](packages/hashd-connector-figma/src/hashd_connector_figma/README.md).

### Jira

Jira issue reference resolver for Jira Cloud (REST API v3) and Server/Data
Center (REST API v2). Use `@jira:PROJ-123`, `@jira:123`, or
`@jira:OTHER:456` in stories, acceptance criteria, or chat to embed issue
context. The connector reads issue details on demand and caches them; it does
not create stories, create issues, or run a sync daemon.

See [packages/hashd-connector-jira/src/hashd_connector_jira/README.md](packages/hashd-connector-jira/src/hashd_connector_jira/README.md).

---

## 7. Future Connectors

### Linear, Shortcut, Azure DevOps
Same connector contract, different API clients.

---

## 8. Non-Python Connectors

Discovery is Python-only (Neovim model). A Rust/Go connector works via a thin Python shim that delegates to a binary via subprocess or IPC. If we accumulate enough non-Python connectors, add a standardized wire protocol (msgspec-RPC, JSON over stdin/stdout) so shims become generic.

---

## 9. Building a Connector

Step-by-step guide to building a new connector. Uses a hypothetical "Linear" connector as the example.

### Step 1: Create the directory

```
packages/hashd-connector-linear/src/hashd_connector_linear/
    __init__.py
```

### Step 2: Declare the contract

```python
# packages/hashd-connector-linear/src/hashd_connector_linear/__init__.py

CONNECTOR_NAME = "linear"          # unique -- becomes @linear:ref namespace
CONFIG_SECTION = "linear"          # config.yaml section
CACHE_DIR_NAME = "linear"          # .cache/linear/
```

That's the minimum. hashd discovers it, `hashd doctor` shows it, `@linear` is reserved. Everything else is optional.

### Step 3: Add configuration

```python
# packages/hashd-connector-linear/src/hashd_connector_linear/config.py

import msgspec
from orchestrator.lib.project_loader import load_project_yaml

class LinearConfig(msgspec.Struct):
    api_key: str = ""
    team_id: str = ""

def load_linear_config(project_dir):
    raw = load_project_yaml(project_dir)
    section = raw.get("linear", {})
    return msgspec.convert(section, LinearConfig)

def is_configured(project_dir):
    try:
        config = load_linear_config(project_dir)
        return bool(config.api_key and config.team_id)
    except Exception:
        return False
```

Wire it up:
```python
# __init__.py (add)
from hashd_connector_linear.config import is_configured
IS_CONFIGURED = is_configured
```

### Step 4: Add doctor checks

```python
# __init__.py (add)
def _check_health(project_dir):
    from orchestrator.connectors._base import DiagnosticResult
    from hashd_connector_linear.config import load_linear_config

    config = load_linear_config(project_dir)
    results = []

    if not config.api_key:
        results.append(DiagnosticResult("Linear config", False,
            "linear.api_key is empty\n"
            "      set it:  hashd project config set linear.api_key <key>"))
        return results

    # ... API health checks ...
    results.append(DiagnosticResult("Linear auth", True, "authenticated"))
    return results

DOCTOR_CHECKS = [_check_health]
```

### Step 5: Add artifact resolution

```python
# __init__.py (add)
def _resolve(project_dir, refs, fetch):
    from orchestrator.connectors._base import ResolvedArtifact, ArtifactRef
    from orchestrator.connectors import get_connector_cache_dir

    cache_dir = get_connector_cache_dir(project_dir, "linear")
    cache_dir.mkdir(parents=True, exist_ok=True)
    results = {}

    for ref in dict.fromkeys(refs):
        # ... fetch/cache issue, build ResolvedArtifact ...
        pass

    return results

ARTIFACT_RESOLVER = _resolve
```

Now `@linear:LIN-42` resolves in prompts, chat, stories, ACs.

### Step 6: Add CLI commands (optional)

```python
# packages/hashd-connector-linear/src/hashd_connector_linear/commands.py

def register_linear_subcommands(subparsers):
    p = subparsers.add_parser("linear", help="Linear integration")
    # ... add subcommands ...
    return p

def cmd_linear_dispatch(args, ops_dir, project_config):
    # ... dispatch subcommands ...
    return 0
```

```python
# __init__.py (add)
from hashd_connector_linear.commands import register_linear_subcommands, cmd_linear_dispatch
CLI_COMMANDS = {"linear": (register_linear_subcommands, cmd_linear_dispatch)}
```

### Step 7: Add tools (optional)

```python
from orchestrator.connectors._base import ToolSpec

TOOLS = [
    ToolSpec(
        name="linear_search",
        description="Search Linear issues by text",
        parameters={"query": "Search text"},
        handler=_handle_search,
    ),
]
```

Tools are exposed to agents via MCP (agent stages) and prompt-based dispatch (`hashd chat`).

### Step 8: Add autocomplete (optional)

```python
def _autocomplete(project_dir, partial):
    return [("issues", "Issue listing")]  # extend with cached data

AUTOCOMPLETE = _autocomplete
```

The `AUTOCOMPLETE` function is called server-side by Python (Prefect flows, MCP server). The TUI gets autocomplete via a separate REST endpoint (`GET /connectors/autocomplete`) that reads the connector's cache directory on the server. Your `AUTOCOMPLETE` function still works — the REST endpoint provides an equivalent for remote clients.

### Step 9: Register as entry point

All connectors are discovered via the `hashd.connectors` entry point group. Register an entry point for your connector package, including workspace-local packages:

```toml
# your-package/pyproject.toml
[project.entry-points."hashd.connectors"]
linear = "your_package.linear"
```

### Step 10: Add cache strategy (optional)

```python
CACHE_STRATEGY = "snapshot"  # or "live" (default), or callable
```

### What you get for free

Without writing any integration code in core:
- `hashd doctor` validates your config and runs your health checks
- `@linear:ref` resolves in every prompt surface
- Your tools appear in MCP and chat
- Autocomplete works in TUI and CLI
- Cache snapshots work at provisioning time (if strategy="snapshot")
- Your connector is removable: delete the directory, everything else keeps working

---

## 10. Open Questions

1. **Inbound changes.** Resolved: no automatic inbound sync. Operators reference external artifacts on demand with `@connector:ref`.
2. **Safety flags.** `modifies_code` / `modifies_external` for gating autonomous execution. Deferred until connectors have write tools.
3. **TOOLS_ALWAYS_LOAD.** Provision for tools that load on every invocation regardless of `@` refs (e.g., a linter). No use case yet.
4. **Plugin architecture.** Rename "connector" to "plugin"? Event handlers vs daemons? Lifecycle hooks? Third-party sandboxing? Revisit when community connectors emerge.
