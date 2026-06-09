# Code Tools Operator Reference

Hashd bundles `codebase-memory-mcp` and exposes its code-intelligence tools through `wf code`.
Hashd owns workstream activation, project naming, telemetry, and cleanup; cbm owns indexing and query execution.

Commands resolve the cbm project from `--workstream`, the current worktree, the current workstream context, or `--project` as a direct cbm project override.

## Commands

All cbm passthrough commands accept JSON arguments:

```bash
wf code <tool> --args '<json>' --workstream <id>
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
wf code --workstream my-workstream search-graph --args '{"name_pattern":"Handler"}'
```

Trace inbound references:

```bash
wf code --workstream my-workstream trace-path --args '{"function_name":"Handler","direction":"inbound","depth":2}'
```

Fetch a snippet:

```bash
wf code --workstream my-workstream get-code-snippet --args '{"qualified_name":"Handler"}'
```

Run a Cypher query:

```bash
wf code --workstream my-workstream query-graph --args '{"query":"MATCH (n) RETURN n LIMIT 20"}'
```

Render architecture context:

```bash
wf code --workstream my-workstream get-architecture
```

List cbm projects:

```bash
wf code list-projects
```

Show code-tool telemetry:

```bash
wf code stats my-workstream
wf code stats --project hbc --by tool
```

## Lifecycle

When a workstream activates, hashd computes its cbm project name from the worktree path, records it on the workstream row, and asks cbm to index the repository. Terminal workstream transitions call cbm project deletion best-effort, and the housekeeping janitor reaps orphaned cbm projects.

`wf code stats` reads hashd telemetry from `code_tool_calls`; it is not a cbm passthrough command.
