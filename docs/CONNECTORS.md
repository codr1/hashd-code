# Connector System Specification

## Overview

Connectors extend hashd with external integrations (Figma, GitHub, Bitbucket, Jira). They're auto-discovered at startup through the `hashd.connectors` entry point group. Core never references a specific connector.

See [Building Connectors](packages/hashd-client/src/hashd_client/README.md) for the developer guide.

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

EVENT_HANDLER = handler_factory                    # (project_dir) -> object with handle(event) -> None
EVENT_TYPES = ("workstream_ready_to_merge",)       # the connector event types it takes

CONFIG_FIELDS = (                                  # project settings `hashd connector <name>` shows and writes
    ConfigField(key="url", label="Site URL", type="string", sensitive=False, required=True, destination=True,
                description="Your site's address."),
)

DISPLAY_NAME = "My Connector"                      # shown instead of the name
ICON_LIGHT = "icon-light.svg"                      # SVG files in this package: for light and dark backgrounds
ICON_DARK = "icon-dark.svg"
ABOUT = "ABOUT.md"                                 # markdown file in this package: the About page
LOGIN_METHODS = (                                  # how a person signs in to the destination
    LoginMethod(label="API token", description="...", help_url="https://...",
                fields=(CredentialField(key="api_token", label="API token", secret=True),)),
)
ACCOUNT_DESTINATION = site_of                      # (typed text) -> the destination an account is stored for
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

### Configuration

Web **Settings → Connectors** lists every installed connector from
`GET /connectors/overview`, with its declared name, icons, About and the
server's one-word state. Each connector's page edits its declared settings
(`PUT /connectors/config`), stores your own account from its `LOGIN_METHODS`
for the destination the server resolved (`PUT /connectors/accounts`), shows
what it does, and runs its checks as you (`GET /connectors/check`). Nothing in
the Web module names a connector.

Under **Advanced** on that page, and in the TUI **Project Configuration**, one
explicit setting key can be written under the connector's `CONFIG_SECTION`
for keys it does not declare. They do not load or prefill stored values. Save
writes a project override; an explicitly confirmed empty save writes a blank;
Reset removes only the named override. YAML configuration and connector
environment-variable credentials remain supported.

Connector `CONFIG_SECTION` declarations also enable `config set/get/reset` for
free-form dotted settings at system and project scope. For example,
`hashd project config set jira.url https://company.atlassian.net` writes a project
override. This declares a namespace, not field names or types: a typo such as
`jira.ur` is accepted, and the connector's loader/doctor owns field validation.
Existing credential support is unchanged, including Jira YAML values and
environment overrides; Figma stores its token environment-variable name.

The existing project config batch API deep-merges partial connector objects, so
changing Figma's profile retains its file ID and other settings. Dotted-key reads
and resets use the same declarations. Schema-based completion/diff/reset-all do
not enumerate free-form connector leaves; address a known leaf or section
explicitly. Host discovery failures are reported instead of claiming a key is
unknown. Ordinary schema settings do not require a connector-host lookup.

### Declared settings: `hashd connector <name> configure|status|check`

A connector declares the project settings that say **where** it points in
`CONFIG_FIELDS`. The declaration is the allowlist: these commands show and write
only declared fields, never another key in the section, and a field states
`sensitive=False` explicitly -- a secret cannot be declared, because credentials
are personal accounts, never project settings. Each field is typed (`string`,
or `enum` with its `choices`). `required` means no operation works without it;
a field only some operations need lists them in `needed_for` (`references` --
resolving `@connector:ref`; `picker` -- searching or browsing for one; `notes`,
`events`, `checks`), so an optional mode stays configurable and each operation
says why it is unavailable: a ClickUp task or Azure work item referenced by id
resolves without the List or project the picker needs. `destination` marks the field personal
accounts are stored for. A string field may carry a `pattern` the whole value
must match. Python (`re.fullmatch`) and Go (anchored) both apply it, so keep
it to anchored ASCII literals and character classes such as `^[0-9]+$`, and add
it to `tests/fixtures/connectors/pattern_samples.json`, which holds both sides
to the same answers. Values are read as the connectors' loaders read them:
trimmed, a blank one is absent, and a present `null` is invalid. A present
value that fails its pattern, its choices or its type is reported invalid,
never shown, and never replaced by an inherited one, and it blocks every
operation, since the loaders validate the whole section first; an absent
optional one blocks only what needs it. The host and the server both refuse a declaration that
breaks these rules. Nested settings (`lifecycle`, `events`, notes) are not
declared and stay on `hashd project config set`.

- `configure --set KEY=VALUE --unset KEY` (`PUT /connectors/config`) validates the
  whole request against the declaration, then writes it in one rewrite of the
  project's `config.yaml` under the project lock. `--unset` removes this
  project's value; a value inherited from system configuration still applies.
  With no flags it lists the settings.
- `status` (`GET /connectors/status`) reads only local facts: the declarations
  (asked with no project directory, so no connector code runs against the
  project), the configuration files, and whether **you** have a personal
  credential for the destination. It reports the destination, your personal
  authentication, and per operation whether its settings are set and you have a
  credential -- not a remote health claim.
- `check` (`GET /connectors/check`) checks the settings, then runs the
  connector's own `DOCTOR_CHECKS` with **your** personal credential. It never
  uses project, environment or host credentials, in solo or team mode: without
  a personal credential the authenticated check is refused, and a connector with
  no personal accounts gets none. The credential is bound to its destination:
  the request names the destination it was chosen for, and the connector host
  refuses before any check runs unless the connector, loading its
  configuration there (environment overrides included), still points there:
  its `ACCOUNT_DESTINATION` of its `REMOTE_SCOPE` is the account's destination
  (for GitHub, the issues repository's host). The doctor checks reached here
  only read; GitHub's reads the credential and the repository on the
  repository's own host (`gh api --hostname`), never `gh auth status`, which
  tests every account on every host.

| Connector | Personal credential | Destination |
|---|---|---|
| GitHub issues | your account for the issues repository's host (`hashd connector login github`): an Issues token, or your forge login if you choose it; never the code repository's remote | `github.repo` |
| Jira | your account (`hashd connector login jira`) | `jira.url` |
| Azure Boards | your account (`hashd connector login azure`) | `azure.organization_url` |
| ClickUp | your account (`hashd connector login clickup`) | `clickup.workspace_id` |
| Confluence | your account (`hashd connector login confluence`): Atlassian email and API token; it declares no checks | `confluence.url` |
| Figma | none yet: no authenticated check runs | -- |

Note the order: `hashd connector status jira` lists your Jira accounts;
`hashd connector jira status` reports the project's Jira connector.

**Team-mode reads.** In team mode the connectors above with a personal
credential (GitHub issues, Jira, Azure Boards, ClickUp, Confluence) are read the same way
a check is: with **your** credential for the project's destination, pinned to
it, and never with the project's `config.yaml` credentials, the server's
environment or its `gh` login. This covers reference search
(`GET /connectors/search`), preview, the story-source availability a picker and
an import read (`GET /connectors/capabilities`), and the connector checks in
`hashd doctor`. Without a usable credential of your own the read is refused and
says how to connect one (`hashd connector login ...`); nobody else's account
is used instead. Under
your credential, the credential fields in `config.yaml` are not read at all, so
a malformed one there cannot affect it. Solo mode reads as before.

Search and preview use a cache private to that one request, under the project's
`.private-reads/`: nothing is read from or written to a cache other users
share, a returned file is read only from that request's cache (a regular file,
of its stated size and SHA-256), and the cache is removed when the request ends.
A cached listing (`@jira:issues`, `@github:issues`) and a cache-only read are
refused, since a shared cache holds what other users fetched. A server that
stops mid-request can leave that request's directory behind; nothing removes it
yet. The directory's file modes separate nothing between Hashd users, who share
the server's OS account: the boundary is that no shared read path reaches it.

**Chat references are unavailable** in team mode for these connectors:
`@jira:KEY`, `@github:N`, `@azure:N`, `@clickup:ID` and `@confluence:ID` in a
chat message are
refused, in every turn and when the conversation is rebuilt, and not read with
anyone's credential. What such a read returns is a file the agent reads on later
turns, and nothing yet keeps it with the conversation. Before this change chat
read them with the project's or the server's credentials; that stopped
deliberately. A bare `@jira` still lists the connector's tools. Preview an item,
or paste what the conversation needs.

Not yet covered (#1856):
- Chat references to the connectors above: keeping what they return with
  the conversation, and answering later turns and rebuilds from it.
- Figma, which has no personal accounts, is still read with the project's or
  the server's credentials; so are references fetched during planning, and the
  Figma tools an agent's MCP server runs.
- Connector caches written before this change, and by solo mode, are not purged;
  planning and implementation still read the shared caches.
- Autocomplete (`GET /connectors/autocomplete`) still offers the issue keys in
  the project's shared Jira cache to every signed-in user, with or without an
  account. That is separate from the cached listings above: `@jira:issues` and
  `@github:issues` are refused under your own account, but the keys autocomplete
  enumerates are not. Reads made with your own account do not add to that cache.
- `GET /projects/{name}/config/raw` returns the project's `config.yaml` as
  written, including any connector credential in it, to every signed-in user.

### Presentation: name, icons, About, sign-in

Every client shows a connector from what it declares, the same way for every
connector, so no client and no part of core names one. The host loads and
checks these at discovery and serves them in `capabilities`, with no project:

- `DISPLAY_NAME`: a short name ("Jira"). Without it, the connector's name.
- A `ConfigField`'s `label`: what a person reads ("Site URL", "Default
  project"); the key is what `config.yaml` holds, and clients show it only
  where raw keys belong (Advanced). Without one, the host derives it from the
  key ("project_key" -> "Project key", "file_id" -> "File ID"). Write the
  `description` for the person filling the field in.
- `ICON_LIGHT` / `ICON_DARK`: SVG files in the connector's own package, drawn
  on light and on dark backgrounds; either alone serves both. Clients draw them
  as images, never inline, so an icon cannot run script. A plain file name only.
- `ABOUT`: a markdown file in the package. Say what the connector does, what a
  person needs, and what it reads and writes. Clients render it without raw HTML.
- `LOGIN_METHODS`: the ways a person signs in to the destination. Each method's
  fields are one complete credential set, stored and handed to the connector
  under exactly those keys, so a connector's `CREDENTIAL_MODES` should be
  derived from it (the bundled ones are). Every method has at least one
  `secret` field; a secret is never shown back and never has an example. A
  field's `pattern` is a full-match regular expression a value must satisfy
  (ClickUp's personal token starts with `pk_`), checked before the account is
  stored; say it in words in the field's `description`. Both languages apply
  it, so the `CONFIG_FIELDS` pattern rules hold here too: keep to the shared
  subset and add it to `pattern_samples.json`. A `help_url` must be
  https. A method with `forge_login` offers the person's forge login for the
  destination host instead of a credential of its own: it has one secret
  field, which is filled from the forge token when the connector is used, and
  it is offered only to someone with a forge login stored there; nothing of it
  is stored with the account. Its `ACCOUNT_DESTINATION` must answer a forge
  host. Because any connector can declare one, Hashd describes that method
  itself -- naming the connector and the host, and that the token can also
  push code and merge pull requests -- instead of showing the connector's own
  description. Declaring `LOGIN_METHODS` is what gives a connector personal accounts:
  the server's account store, its CLI (`hashd connector login`) and the Web
  page all read them, and none names a connector.
- `ACCOUNT_DESTINATION`: required with `LOGIN_METHODS`, along with a
  `CONFIG_FIELDS` field marked `destination`. A function from what a person
  typed (a site URL, a workspace ID) to the destination their account is stored
  for. Applied to what `REMOTE_SCOPE` reports, it must give the same answer:
  that is how an account is found for every project at that destination, and
  what the host checks before a personal credential is used. For most
  connectors the two are the same string; one account may also cover many
  scopes (GitHub: the host, for every repository on it). Raise
  `ValueError` with a message written for the person on anything that is not a
  destination. It must be pure -- no network, no project -- because the server
  asks it whenever it resolves a destination (`account_destinations`, one host
  call for every connector asked about) and keeps the answers briefly.

- `NOTES_MARKDOWN`: `True` when the comments its `SYNC_BACKEND` posts render
  Markdown, so what Hashd adds to a note (an attribution) is escaped as
  Markdown there.

A stored account reaches the connector as the caller credential source:
`HASHD_CONNECTOR_CREDENTIAL_SOURCE=caller` and `HASHD_CONNECTOR_CREDENTIALS`, a
JSON object of credential field to value. A connector whose config loader uses
`hashd_client.connector_env.resolve_connector_env` gets exactly that set and no
credential from `config.yaml` or the environment; it needs no variable names of
its own for it. One whose tool reads its own credential (GitHub runs `gh`)
calls `connector_env.caller_credentials` and hands the tool exactly that set,
and never lets it fall back to a login on the machine. The server scrubs each
handed-over value from the host's output.

Files are capped at 16 KiB, and must ship in the package
(`[tool.setuptools.package-data]`). An unusable declaration is logged and left
out rather than shown half-working. The package name and version come from the
distribution that provides the entry point.

### Integration points

| File | What |
|---|---|
| `cli.py` | Registers CLI commands from `CLI_COMMANDS` |
| `commands/doctor.py` | Runs `DOCTOR_CHECKS` for configured connectors |
| `lib/ref_resolver.py` | Dispatches `@connector:ref` to `ARTIFACT_RESOLVER` |
| `lib/agents_config.py` | Injects MCP config for `TOOLS` into agent commands |
| `server/api/autocomplete.go` | REST endpoint for TUI autocomplete (reads connector caches) |

---

### Connector events (opt-in)

A connector can act on committed Hashd facts about a story it is attached to.
It declares `EVENT_HANDLER` and `EVENT_TYPES`. A project then subscribes the
connector by name, in the connector's own section:

```yaml
jira:
  events:
    subscribe: [requirements_approved, workstream_ready_to_merge]
```

Nothing is sent until a project subscribes. Subscribing to events does not
change notes: a milestone subscribed as an event is also still documented as a
note, unless notes are switched off.

**Types.** These are the note milestones: `requirements_approved`,
`story_edited`, `clarification_answered`, `workstream_ready_to_merge`,
`workstream_merged` and `workstream_pr_link`. Two more types are events only,
never notes:
- `story_implemented`: the story reached implemented. This happens
  automatically once every workstream it owns has finished, or when an
  operator marks it implemented.
- `story_abandoned`: the story was closed, cancelled, or abandoned.

Both are terminal, so each happens at most once per story. Unlike the
workstream milestones, they speak for the whole story. An unknown name is
ignored with a warning. A type the connector's `EVENT_TYPES` does not declare is refused at
delivery, and the refusal is recorded on the story.

**The event.** The host verb is `deliver_event`. Each event carries:
- `type`, `occurrence` and `occurred_at` (when it was published, just after
  the commit);
- the story, the workstream, and the attached item (`external_id`,
  `connection_id`);
- `facts`: the title, and the link where there is one. `story_implemented`
  and `story_abandoned` also carry `attachment_shared`: `"true"` when another
  story in this project, not yet implemented or abandoned, is attached to the
  same remote item (same connector, `connection_id` and `external_id`), and
  `"false"` when none is. It is absent when it could not be read; treat that
  as unknown, never as `"false"`. It is read at delivery from this project's
  own records, so a story in another project attached to the same item is not
  seen. It does not guarantee anything once read: an attachment or transition
  after the read is not reflected. What to do with it is the connector's
  decision;
- `actor`: who caused it;
- `credential`: whose account the connector acts with.

**Actor and credential are separate.**
- `actor` is a Hashd user (`kind: user` with `user_id`) or `kind: system`.
  It is never a guess. A user is the authenticated Hashd account that
  requested the action. It is not an independently verified person: a client
  that sends one shared account's token is reported as that account.
- A workstream reaching ready to merge is caused by the system, and acted on
  with the workstream owner's account (`credential.kind: owner`).
- A merge or a PR link that Hashd performed (`hashd merge`, `hashd pr create`)
  is caused by the account that requested it. It is acted on with the
  workstream owner's account, as for ready to merge.
- A story milestone is caused by the signed-in account, and acted on with
  that account. That includes an operator marking a story implemented or
  abandoning it.
- A story Hashd found implemented, once every workstream finished, is
  attributed to the **story's owner** (`kind: user` with the owner's id) and
  acted on with the owner's account (`credential.kind: owner`). This records
  who is responsible for the story. It does not claim the owner performed any
  merge; each merge keeps its own attribution above. A story with no owner is
  withheld.
- When nobody can be named as the cause, the event is withheld and the note
  still goes out. That covers:
  - a request with no authenticated account, including solo-mode loopback
    requests;
  - a merge or PR link from an execution started before the requester was
    recorded;
  - a merge Hashd only found done: a PR merged on the forge by somebody
    else, or a merge finished by hand after conflicts. This holds even when
    a `hashd merge` was waiting for it.

**Credentials.** `credential` names the account Hashd supplied to the
connector host for this delivery. It is the same account a note would use: in
team mode, the person's own connected account and never a fallback account; in
solo mode, the server's own login (`credential.kind: server`).

`credential` is not a guarantee of the remote identity a handler acts with.
Hashd hands the account only to the connector's own credential loading, so a
handler must build its client through that credential-aware loader, the same
way its write backend does. A handler that reads another token, file or
environment variable acts as whoever that belongs to, and Hashd cannot see or
prevent it.

**Delivery.**
- Checked with the same gates as outbound notes: a connector that is
  configured, declares that it modifies external systems, and still points at
  the attachment's destination.
- Each occurrence starts once and is delivered once to each subscribed
  attachment. It is never retried.
- Events are unordered: two facts about one story can arrive in either
  order, so a handler that changes state should be safe to apply in either
  order.
- A delivery that fails is recorded on the story. It is recorded as
  "not sent" when it was refused before the connector was reached, and as
  "not confirmed" when the connector may have acted.
- Hashd does not record what a connector did with an event.

## 2. @connector:ref Resolution

### How it works

`resolve_refs()` scans text for `@connector:ref` patterns, dispatches to the connector's `ARTIFACT_RESOLVER`, and replaces refs with file metadata. Resolution happens BEFORE any prompt reaches an agent.

There are two resolver implementations sharing the same connector-host surface:

- **Python harness** (`lib/ref_resolver.py`) -- used by the planner and runner prompt assembly. Connector dispatch only; built-in artifact names in `BUILTIN_REFS` are skipped and resolve elsewhere.
- **Go server** (`server/internal/refs/`) -- used by the chat generation path (`POST /chat/messages`, serving both `hashd chat` and the TUI). One entry point unfolds every `@`-reference in place so the agent never sees a raw token: built-in artifacts load **locally in Go** from the project DB / git / filesystem, and connector references dispatch through the same connector host via `server/internal/connectors`. This is the Go-canonical home for server-side chat `@`-reference resolution.

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

`packages/hashd-client/src/hashd_client/mcp_server.py` -- FastMCP stdio server that exposes connector tools to AI agents.

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
| OpenCode | `OPENCODE_CONFIG_CONTENT` environment overlay (`mcp` key) |
| Kimi Code | `--mcp-config-file` flag with JSON file |
| Qwen Code | `.qwen/settings.json` in worktree |

File-based configs are excluded from git via `.git/info/exclude`.

---

## 6. Shipped Connectors

### Outbound story notes in team mode

In team mode, hashd posts a story note on a tracker **only with the connected
account of the person the note speaks for**. That is the signed-in user whose
action caused it (an approval, an edit, an answer), or the workstream's owner
for a workstream milestone (ready to merge, merged, PR link), whoever clicked.
It never uses the server's own `gh` login or environment, or the project's
connector credentials, for a note. Solo mode is unchanged. Commits, pushes and
PRs are unchanged.

- **GitHub issues, Jira, Azure Boards, ClickUp, and any connector declaring
  `LOGIN_METHODS`:** each user can connect a personal account for one
  destination on the connector's Web page, or with
  `hashd connector login <connector> --destination <site, Workspace ID or
  organization> [--method NAME] [--field KEY=VALUE]...`, and check or remove it
  with `hashd connector status` / `logout`. `--method` picks one of the
  connector's sign-in methods (asked on a terminal when it has several);
  fields that are not secret go in `--field` or are asked; the secret is read
  hidden or from stdin. It is stored encrypted and never shown again. A note on an item at that destination
  is posted with that account. The server hands it only to the connector for
  that one write, and the connector ignores every other credential in the
  project's config or the server's environment. With no account connected for
  the destination, the note is withheld unless the project chose a fallback
  account (below).
- **GitHub issues** signs in for a host (`github.com`, or an Enterprise host)
  and the account covers every repository there. Two ways: an **Issues token**
  (a fine-grained token with Issues: Read and write, the safer choice, since it
  can do nothing else), or **Use my forge login**, offered only once you have
  stored one for that host (`hashd forge login`, Settings > Forge). The forge
  login is not copied: the account reads it when it is used, so rotating it
  carries through and removing it leaves the account unusable rather than
  falling back to anything else. It can do far more than issues need.

  ```
  hashd connector login github --destination github.com --method "Issues token"
  hashd connector login github --destination github.com --method "Use my forge login"
  ```

**Change from earlier versions: GitHub issues.** GitHub issues used to read
and post with your forge login automatically. It now has an account of its
own, like the other trackers: until you sign in to it (with an Issues token or,
by choice, your forge login), team-mode GitHub reads are refused, notes are
withheld, and `hashd connector github check` is refused in either mode. Solo
mode's reads and notes are unchanged. Its fallback accounts (below) now use `destinations` (hosts or
repository URLs, each standing for its host), not `repositories`, so one
approves every repository on a host.

**Change from earlier versions.** Team projects whose notes were posted with
the server's `gh` login or a project token now withhold those notes until the
user connects a GitHub account. For Jira, Azure Boards and ClickUp they are
withheld until the user connects an account for that destination. A note is also withheld when nobody is
identified: a request with no signed-in user, a workstream with no owner, or a
note queued before an upgrade. A withheld note is recorded on the story as
**not sent**, with the reason. The action that caused it still succeeds.

**Fallback accounts are temporarily suspended.** A project's choice of a
fallback account, described below, is currently never honoured, for GitHub,
Jira, Azure Boards and ClickUp alike. Each such note is recorded on the story as
**not sent**, with the reason "Fallback accounts temporarily suspended". A
person's own connected account is used exactly as before, and solo mode is
unaffected. The central definitions and the project choices are kept as they
are, and no configuration change is needed. They take effect again when
fallback accounts are restored. The rest of this section describes how they
work then.

**Fallback accounts (optional, off by default).** A team project can choose
an approved account to post a connector's notes for a person who has **not
connected** an account of their own for the destination, under that
connector's own section (`github`, `jira`, `azure`, `clickup`).

**Defining an account (server administrators).** Only a server administrator
defines fallback accounts, in the central config. This is the file
`hashd config set` writes, and it needs an owner or admin in team mode.
- `destinations`: where the account may post, as the connector names its
  account destinations -- sites, organizations, Workspace IDs, or GitHub hosts
  (a repository URL stands for its host).
- The credential is one complete set of the connector's own sign-in fields. A
  field that only identifies the account (Jira's `email`) is written as a
  value. Every secret is written only as `<field>_env`, naming the server's
  environment variable that holds it: `token_env`, `api_token_env`, `pat_env`
  or `access_token_env`. A secret written as a value is refused, and neither
  file ever holds one.

```yaml
jira:
  outbound_notes:
    fallback_accounts:
      hashd-automation:
        label: Hashd automation                 # the name the note gives for who posted it
        destinations: [https://example.atlassian.net]
        email: hashd-bot@example.com
        api_token_env: HASHD_NOTES_JIRA_TOKEN   # or pat_env, for Server/DC
github:
  outbound_notes:
    fallback_accounts:
      hashd-automation:
        label: Hashd automation
        destinations: [github.com]
        token_env: HASHD_NOTES_GITHUB_TOKEN
```

**Choosing one (a project).** A project opts in by name in its own config, for
example `jira.outbound_notes.fallback: hashd-automation`. A project cannot
define an account itself, name a different environment variable, or send an
account's credential anywhere else.

The rules:
- The person's own connected account is always used first.
- The fallback posts only when that person has no account for the destination,
  and only to a listed destination.
- It is never used when the person's account cannot be read (a chosen forge
  login that is gone included) or the tracker rejects it, when nobody is
  identified, when the choice or definition is incomplete, or when the
  variable is unset. Each of these records the note as not sent, or not
  confirmed, with the reason.
- The note ends with "Posted by <label> on behalf of <person>, who has not
  connected their own account to Hashd". Where the connector's comments render
  Markdown (its `NOTES_MARKDOWN`: GitHub, Azure Boards) the name is escaped as
  Markdown; elsewhere it is printed plain, and characters Jira's wiki markup
  would act on are left out. Ordinary punctuation is kept.

### GitHub

GitHub issue reference resolver. Use `@github:42` in stories, acceptance
criteria, or chat to embed issue context. The connector reads issue details on
demand and caches them; it does not create stories, create issues, or run a sync
daemon. Its remote writes are hashd's outbound story notes -- a comment or a
pull-request link on an issue already attached to a story -- and, only for the
lifecycle events a project subscribes it to and maps to a label, an added label
on that issue (connector events, above), and, only for a story's own
`story_implemented` or `story_abandoned` event that the project lists in
`github.lifecycle.close`, a close with a fixed reason, never while another
story in this project still in progress shares the issue. All are refused
unless the configured repository is still the one the issue was attached from.
It never reopens an issue or removes a label.

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

### Confluence

Read-only Cloud page artifacts via `@confluence:123456` on the configured site.
Typed full URLs are unsupported by current shared input parsing. Bundled but
unconfigured; use the existing project configuration editors.
Raw JSON/storage and a readable projection retain current content and report
conversion limitations. See the [provider guide](packages/hashd-connector-confluence/src/hashd_connector_confluence/README.md)
for token routes, tenant-verification limits and configuration. No connector CLI.
In team mode each person reads Confluence with their own account for the site
(`hashd connector login confluence --destination https://SITE.atlassian.net`,
or its Web page): their Atlassian email and an API token.

### Azure Boards

Azure DevOps Services work items use `@azure:123` or the shared reference picker.
Search stays within the configured organization/project; native state, assignee
and type filters preserve Azure values. Explicit numeric references can read any
work item accessible to the credential within that organization, including other
projects. The configured project limits search, not direct-ID access; Azure
credential permissions and existing Hashd caller/project authorization still apply.
Full returned JSON reaches preview and
the same owned planning capture as typed references. Related targets and history
are not implicitly fetched, and there are no ownership claims. The only remote
writes are outbound notes on attached items and, when a project configures them
under `azure.lifecycle`, forward-only state moves on connector events. Only a
story's own `story_implemented` or `story_abandoned` event moves an item to
Completed or Removed, and not while another story in this project still in
progress shares it (`attachment_shared`).
Use the existing project configuration editors with exactly one PAT or externally
supplied Entra access token. Ordinary authorized config readback remains unchanged,
not masked secret storage. See the [provider guide](packages/hashd-connector-azure-devops/src/hashd_connector_azure_devops/README.md).

### ClickUp

ClickUp tasks use native task IDs such as `@clickup:86a4xte6z`, or the shared
reference picker, which browses the configured List with ClickUp's native paging
and exact status, assignee, tag and updated-since filters. ClickUp has no native
task text search; picker text is an exact task ID lookup. Custom Task IDs and
URLs are not accepted. Every read verifies the returned Workspace against
`clickup.workspace_id`; explicit task IDs can name any task that token can read in
that Workspace, including other Lists. Full returned task JSON reaches preview and
the same owned planning capture as typed references. Comments, attachment files
and Docs are not fetched; there are no ownership claims. Its remote writes are
hashd's outbound story notes (a comment or a pull-request link) and, opt-in, a
status move for a subscribed event mapped per List in `clickup.lifecycle`. Both
act only on a task already attached to a story, refused unless
`clickup.workspace_id` is still the Workspace the task was attached from. Only
the story's own terminal events (`story_implemented`, `story_abandoned`) may
move a task to a closed or done status, and not while `attachment_shared` says
another unfinished story still uses it; nothing reopens a task.
Use the existing project configuration editors with exactly one personal token or
externally supplied OAuth access token. Ordinary authorized config readback remains
unchanged, not masked secret storage. See the [provider guide](packages/hashd-connector-clickup/src/hashd_connector_clickup/README.md).

## 7. Future Connectors

### Linear, Shortcut
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
    from hashd_client.connectors import DiagnosticResult
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
    from hashd_client.connectors import ResolvedArtifact, ArtifactRef
    from hashd_client.connectors import get_connector_cache_dir

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
from hashd_client.connectors import ToolSpec

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

The `AUTOCOMPLETE` function is called server-side by Python (Prefect flows, MCP server). The TUI and other remote clients get the equivalent via a separate REST endpoint (`GET /connectors/autocomplete`) that reads the connector's cache directory on the server.

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
2. **Safety flags.** `MODIFIES_EXTERNAL` now gates the connector host's `sync_apply` writes (outbound story notes). `modifies_code`, and gating autonomous execution on either flag, remain deferred.
3. **TOOLS_ALWAYS_LOAD.** Provision for tools that load on every invocation regardless of `@` refs (e.g., a linter). No use case yet.
4. **Plugin architecture.** Rename "connector" to "plugin"? Event handlers vs daemons? Lifecycle hooks? Third-party sandboxing? Revisit when community connectors emerge.
