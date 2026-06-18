# Building Connectors

Connectors are hashd's plugin system for external integrations.
`orchestrator/connectors/` is the core framework: discovery, shared contracts,
and cache helpers. Connector implementations live in installable packages and
are auto-discovered through the `hashd.connectors` entry point group.

## Core references vs connectors

The core reference library (`orchestrator/lib/ref_resolver.py`) owns
project-internal reference mechanics such as parsing `@file:` references,
formatting metadata blocks, and validating whether a file path is inside the
project tree. Connectors are for optional external systems such as Figma, Jira,
and GitHub: they may have auth, network calls, cache staleness, and rate limits.

Connectors consume the core reference helpers; they are not peers of the built-in
`@file:` contract. Keep project-internal reference behavior in the core library
so the eventual Go migration has one clear target.

## How discovery works

`discover_connectors()` loads packages declaring the `hashd.connectors` entry
point group. Each entry point resolves to a connector module whose module-level
attributes are inspected.

Import errors are logged and skipped. A broken connector cannot crash hashd.

## Module contract

Declare any combination of these attributes in your connector's `__init__.py`. All are optional.

```python
# packages/hashd-connector-my/src/hashd_connector_my/__init__.py

CONNECTOR_NAME = "my_connector"          # unique name (defaults to module name)
CONFIG_SECTION = "my_config"             # config.yaml section this connector owns

CLI_COMMANDS = {
    "mycommand": (register_fn, dispatch_fn),
}

DOCTOR_CHECKS = [check_health_fn]       # list of health check functions
IS_CONFIGURED = is_configured_fn         # (project_dir) -> bool
ARTIFACT_RESOLVER = resolver_fn          # (project_dir, refs, fetch) -> dict[str, ResolvedArtifact]
CACHE_DIR_NAME = "my_connector"          # .cache/<this>/

TOOLS = [                                # list of ToolSpec
    ToolSpec(name="my_browse", description="...",
             parameters={"query": "..."}, handler=fn),
]
```

### CLI_COMMANDS

Each entry maps a command name to a `(register_fn, dispatch_fn)` tuple:

- `register_fn(subparsers)` -- adds an argparse subparser, returns the parser object. Does **not** set `func`.
- `dispatch_fn(args, ops_dir, project_config) -> int` -- handles command dispatch. Receives project config from cli.py's wrapper, so no circular imports.

### DOCTOR_CHECKS

List of `check_fn(project_dir) -> list[DiagnosticResult]` functions. Only called when `IS_CONFIGURED` returns True. Results are printed in the `wf doctor` Connectors section.

### IS_CONFIGURED

`(project_dir) -> bool`. Gates doctor checks and artifact loading. Should check both that the config section exists **and** that required backend credentials are present.

### ARTIFACT_RESOLVER

`(project_dir, refs: list[str], fetch: bool) -> dict[str, ResolvedArtifact]`. Batch interface -- receives all `@connector:ref` refs at once, returns a dict mapping each ref to its result. The connector decides how to batch API calls internally. Returns `ResolvedArtifact` with file references (not content) or error. Never raises.

### CACHE_DIR_NAME

String used by `get_connector_cache_dir()`. Cache lives at `projects/<project>/.cache/<cache_dir_name>/`.

### TOOLS

List of `ToolSpec` objects. Tools are loaded lazily when `@connector` is detected in a prompt. The model can call them via MCP (in agent stages) or prompt-based dispatch (in `wf chat`).

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

## Integration points

Core interacts with connectors only through `discover_connectors()`. The five hook sites:

| File | What it does |
|---|---|
| `cli.py` | Registers CLI commands from `CLI_COMMANDS` |
| `commands/doctor.py` | Runs `DOCTOR_CHECKS` for configured connectors |
| `lib/ref_resolver.py` | Dispatches `@connector:ref` to `ARTIFACT_RESOLVER` |
| `commands/chat.py`, `pm/planner.py`, `runner/impl/prompt_context.py` | Call `resolve_refs()` before agent invocation |

## Base types

`orchestrator/connectors/_base.py` provides shared types:

- `ToolSpec` -- tool exposed to agents (name, description, handler, stage scoping)
- `ResolvedArtifact` -- result of artifact resolution (file refs, source, error)
- `ArtifactRef` -- reference to a cached file (path, format, size, description)
- `RefError` -- failed resolution (ref, connector, error message)
- `SyncBackend` -- Protocol for sync backends (fetch, create, update, close, etc.)
- `IssueData` -- backend-agnostic issue representation
- `RemoteState` -- current state of an external issue
- `DiagnosticResult` -- health check result (name, passed, message)

These are optional. A connector that only adds CLI commands or artifacts doesn't need them.

## File structure

Bundled connectors use this structure:

```
packages/hashd-connector-my/
  pyproject.toml
  src/hashd_connector_my/
    __init__.py      # Module contract declarations
    config.py        # Config struct, load/save, is_configured
    backend.py       # External API wrapper
    engine.py        # Reference parsing and transforms
    commands.py      # CLI handlers + register/dispatch
```

`pyproject.toml` registers the connector:

```toml
[project.entry-points."hashd.connectors"]
my = "hashd_connector_my"
```

## Non-Python connectors

The discovery system is Python-only (same model as Neovim's Lua-based plugin discovery). A Rust/Go connector works via a thin Python shim that handles discovery and delegates to the binary via subprocess or IPC. See CONNECTORS.md for details.

## Full specification

See docs/CONNECTORS.md for the complete system specification including resolution protocol, MCP server, tool dispatch, and future plans.
