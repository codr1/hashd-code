# Code Tools Operator Reference

Hashd bundles `codebase-memory-mcp` and exposes its code-intelligence tools through `hashd code`.
Hashd owns workstream activation, project naming, telemetry, and cleanup; cbm owns indexing and query execution.

Commands resolve the cbm project from `--workstream`, the current worktree, the current workstream context, or `--project` as a direct cbm project override.

## Commands

All cbm passthrough commands accept JSON arguments:

```bash
hashd code <tool> --args '<json>' --workstream <id>
```

Available tools:

```text
search-graph
trace-path
query-graph
get-code-snippet
get-architecture
get-graph-schema
search-code
detect-changes
list-projects
index-status
manage-adr
ingest-traces
```

Hashd-managed tools are intentionally not exposed:

```text
index_repository
delete_project
```

## Examples

Search graph nodes:

```bash
hashd code --workstream my-workstream search-graph --args '{"name_pattern":"Handler"}'
```

Trace inbound references:

```bash
hashd code --workstream my-workstream trace-path --args '{"function_name":"Handler","direction":"inbound","depth":2}'
```

Fetch a snippet:

```bash
hashd code --workstream my-workstream get-code-snippet --args '{"qualified_name":"Handler"}'
```

Run a Cypher query:

```bash
hashd code --workstream my-workstream query-graph --args '{"query":"MATCH (n) RETURN n LIMIT 20"}'
```

Render architecture context:

```bash
hashd code --workstream my-workstream get-architecture
```

List cbm projects:

```bash
hashd code list-projects
```

Show code-tool telemetry:

```bash
hashd code stats my-workstream
hashd code stats --project hbc --by tool
```

## Lifecycle

When a workstream activates, hashd computes its cbm project name from the worktree path, records it on the workstream row, and asks cbm to index the repository. Terminal workstream transitions call cbm project deletion best-effort, and the housekeeping janitor reaps orphaned cbm projects.

Each hashd project keeps its indexes in its own folder, `<ops>/cbm/<project>`, served by a cbm process of its own; the stage MCP shim and the server both point cbm there (`CBM_CACHE_DIR`), and a stage under ops-dir isolation is granted that one folder. The process that launches an agent hands the shim, in the code server's own MCP `env`, the cbm binary it resolved itself (`HASHD_CBM_BIN`, when that is an executable by absolute path): the shim runs in whatever environment the agent gives its MCP servers, and Codex, for one, passes them neither `HASHD_ROOT` nor hashd's other install locations. The janitor reconciles each project's folder against that project's live workstreams. A direct `/code/<tool>` call names a cbm project, and the server serves it from the folder of the hashd project whose workstream owns it. Migration M023 moved the indexes of the shared layout (files directly under `<ops>/cbm`) into the folder of the project whose workstream claims each one; the server does not start until it has run.

`hashd code stats` reads hashd telemetry from `code_tool_calls`; it is not a cbm passthrough command. Its rows come from two writers:
- **The stage MCP shim** records each code tool call it serves (kind `code`) through `POST /workstreams/{id}/code-tool-calls`, authenticated with the run's token. A post the server refuses is logged once in the shim's log, with the server's Diagnostic.
  - The agent forwards the token to its MCP servers by name, never as a value in its config, in the way it declares (`mcp_env_forwarding`):
    - codex: the server's `env_vars` list;
    - claude and qwen: their MCP servers inherit their environment;
    - gemini: a `"$HASHD_TOKEN"` reference it expands.
  - kimi, copilot and opencode declare none: their forwarding is not proven.
- **Each agent attempt** records the search and read tools its own stdout shows (kinds `grep`, `read`, `glob`). An agent that declares `tool_calls` in its registry entry (codex) is read as it declares:
  - a finished shell command counts once per search or read program it runs;
  - a finished MCP call counts as kind `mcp`, tool `<server>/<tool>`, except a call to the `code` server when the agent also declares `mcp_env_forwarding`: the shim records that call itself, so it is counted once.
