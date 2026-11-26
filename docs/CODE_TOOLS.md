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

A stage launched with no workstream has no row to find an index through: planning (discovery, tech tree, refine, edit, split, routing, criterion return), project description and build detection. It gets the code map of the checkout it runs in instead, for every agent:

- The server indexes that checkout by path when the stage launches (`agents.CheckoutCodeMap`, `cbm.Projects.IndexCheckout`) and binds the stage's code server to it, with no workstream. Chat gets no code map.
- A planning checkout's index is claimed from the moment the checkout is prepared until it is removed, across the launches that run in it. The index is deleted with the checkout. A launch in the registered repository claims its index only while it runs.
- An index a claim built is deleted with its last claim. An index that stood before, a workstream's own, is refreshed and left in place.
- The janitor leaves a claimed index alone.
- The server's cbm process for the project runs only to build such an index and to delete it, and is stopped after each call: the stage's code tools query through the shim's own cbm, and an idle process that has indexed a mid-sized repository holds close to 4 GB. There is no idle timer and no setting.
- One index call runs at a time in a hashd process, across projects: a full index of a mid-sized repository peaks above 5 GB.
- If the index cannot be built, the stage runs without code tools and the server logs why.
- These stages' code tool calls are recorded in `code_tool_calls` with a fresh opaque launch ID for each shared-runner invocation, independent of reused sessions or lifecycle stage executions. The rows remain after completion, with no fabricated workstream or run.

hashd pins codebase-memory-mcp v0.12.1 (`vendor/cbm.lock`). The Linux builds are hashd's own: v0.12.1 with `vendor/cbm-hashd.patch`, built and attested on the codr1 mirror (release `v0.12.1-hashd.2`), because upstream v0.12.1 cannot start inside a stage fence and cannot be told a session's project name; the patch file says what it changes and how to rebuild. Other platforms use upstream's archives. How hashd runs it:

- **One runtime directory per process.** A cbm front end starts a daemon bound to its runtime directory. Every cbm process hashd starts, the server's and a stage shim's alike, gets a private one (`CBM_RUNTIME_DIR`, made by `cbm.NewRuntimeDir`, removed when the process ends), so no daemon is shared between a fenced stage and the server or between cache folders. cbm refuses a runtime path too long for its socket (64 characters work, 70 do not), so the directory is created directly under the temp folder, or under `/tmp` when the temp folder's path is too long; when neither can be used hashd refuses to start cbm and says to set `TMPDIR` to a short writable directory.
- **Answer format.** cbm answers its read tools as a compact text tree unless asked otherwise. Agents get that tree: the stage shim passes an agent's call on in the format the agent chose, and an agent may pass `format: "json"` itself. The server asks for `format: "json"` on every call whose answer it reads (`cbm.WithJSONFormat` in `Manager.CallTool`). `list_projects` is read page by page.
- **One output cap, 32 KB.** A cbm read tool sizes its answer by `max_output_tokens`, 4 bytes a token as its ceiling, and pages past it with its own offsets and cursors. When an agent names no budget the shim passes 8000 tokens (32,000 bytes), and the catalog shows that default; the shim never cuts a cbm answer. The `grep`, `rg` and `find` landing pads cut their output at the same 32,000 bytes. The overview keeps its own smaller pages.
- **The web UI is off.** Before each start hashd writes `ui_enabled false` to the cache folder's settings, so cbm serves no page on a local port.
- **Tools agents do not get.** The shim hides `compare_graphs` and `check_index_coverage` with the lifecycle tools; `compare_graphs` names two projects and would read another lane's code map. `get_file_outline` reaches agents as `file_outline`.
- **Indexes of another cbm version are dropped.** A cache folder records the cbm version that wrote it (`.cbm-version`). The first time the server or a runner starts cbm on a folder written by another version, it empties the folder (`cbm.DropIndexesOfAnotherVersion`); each checkout is indexed again when a stage next needs it.
- **A lane's index is named after its story.** hashd indexes a workstream's checkout with `name` set to its story's id (`cbm.StoryProjectName`: `STORY-0707`, `BUG-0717`, in cbm's own normalization of a name) and records that name in `workstreams.cbm_project_name`, which the stage's tools bind. cbm's default, the checkout path, is repeated in every symbol of the index, and a lane's path is long: one real lane index was 918 MB under its path's name and 367 MB under a short one. A story has one workstream in its hashd project, and each project's indexes are in a folder of their own; a direct `/code/<tool>` call naming a bare index that two projects hold is refused (`code.project.ambiguous`). A workstream that records no story has no name: its index is refused (`code.code_map.no_story`), never built under another name. A lane indexed before this rule is renamed at its next launch, and the janitor removes the index it leaves.
- **The stage's cbm is told that name.** cbm takes a session's project, the one its watcher refreshes as files change, from its working directory's path. For a lane the stage shim starts cbm in the checkout with `CBM_SESSION_PROJECT` set to the lane's index name (part 4 of the patch), so an agent's own edits reach the code map during the stage. Upstream's builds (macOS, Windows) ignore the variable: there a lane's index is refreshed at each agent launch only.
- **A checkout no workstream owns keeps its path's name.** A planning checkout or the registered repository is indexed under the name cbm derives from the path with symbolic links resolved, and hashd's mirror of that name (`cbm.ProjectNameFromPath`) resolves the path the same way.
- **Table answers.** Since v0.12 cbm answers searches as a column list with rows; the `hashd code` routes read that shape. A trace no longer carries a file and line per caller, so `callers` and `callees` name symbols only.

Each hashd project keeps its indexes in its own folder, `<ops>/cbm/<project>`, served by a cbm process of its own; the stage MCP shim and the server both point cbm there (`CBM_CACHE_DIR`), and a stage under ops-dir isolation is granted that one folder. The process that launches an agent hands the shim, in the code server's own MCP `env`, the cbm binary it resolved itself (`HASHD_CBM_BIN`, when that is an executable by absolute path): the shim runs in whatever environment the agent gives its MCP servers, and Codex, for one, passes them neither `HASHD_ROOT` nor hashd's other install locations. The janitor reconciles each project's folder against that project's live workstreams. A direct `/code/<tool>` call names a cbm project, and the server serves it from the folder of the hashd project whose workstream owns it. Migration M023 moved the indexes of the shared layout (files directly under `<ops>/cbm`) into the folder of the project whose workstream claims each one; the server does not start until it has run.

`hashd code stats` reads hashd telemetry from `code_tool_calls`; it is not a cbm passthrough command. Its rows come from two writers:
- **The stage MCP shim** records each code tool call it serves (kind `code`) through `POST /workstreams/{id}/code-tool-calls` for a workstream or `POST /code/tool-calls` for planning, authenticated with the launch's token. Planning launch attribution reaches the shim through the code server's MCP environment (`HASHD_LAUNCH_ID`). A post the server refuses is logged once in the shim's log, with the server's Diagnostic.
  - The agent forwards the token to its MCP servers by name, never as a value in its config, in the way it declares (`mcp_env_forwarding`):
    - codex: the server's `env_vars` list;
    - claude and qwen: their MCP servers inherit their environment.
  - kimi, copilot and opencode declare none: their forwarding is not proven.
- **Each agent attempt** records the search and read tools its own stdout shows (kinds `grep`, `read`, `glob`). An agent that declares `tool_calls` in its registry entry (codex) is read as it declares:
  - a finished shell command counts once per search or read program it runs;
  - a finished MCP call counts as kind `mcp`, tool `<server>/<tool>`, except a call to the `code` server when the agent also declares `mcp_env_forwarding`: the shim records that call itself, so it is counted once.
