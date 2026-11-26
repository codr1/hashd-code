# Connector System Specification

## Overview

Connectors extend hashd with external integrations (Figma, GitHub, Bitbucket, Jira). They're auto-discovered at startup through the `hashd.connectors` entry point group. Core never references a specific connector.

See [Building Connectors](packages/hashd-client/src/hashd_client/README.md) for the developer guide.

---

## 1. Connector Contract

Every connector declares its capabilities via module-level attributes in `__init__.py`. All are optional except `ACCOUNT_KIND` and `LOGIN_METHODS`.

```python
# packages/hashd-connector-my/src/hashd_connector_my/__init__.py

CONNECTOR_NAME = "my_connector"                    # unique, used as @ namespace
CONFIG_SECTION = "my_config"                       # config.yaml section

DOCTOR_CHECKS = [check_fn]                         # (project_dir) -> list[DiagnosticResult]
IS_CONFIGURED = is_configured_fn                   # (project_dir) -> bool

ARTIFACT_RESOLVER = resolver_fn                    # (project_dir, refs: list[str], fetch: bool) -> dict[str, ResolvedArtifact]
CACHE_DIR_NAME = "my_connector"                    # .cache/<this>/

TOOLS = [                                          # list of ToolSpec
    ToolSpec(name="my_browse", description="...",
             parameters={"query": "..."}, handler=fn),
]

AUTOCOMPLETE = autocomplete_fn                     # (project_dir, partial) -> list[(value, description)]; only without LOGIN_METHODS

READ_VERSIONS = read_versions_fn                  # (project_dir, items: list[StoredItem]) -> dict[StoredItemKey, ItemVersion]

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
ACCOUNT_KIND = "personal"                          # who owns the account: "personal" or "project"
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
Reset removes only the named override. YAML configuration remains supported.

Connector `CONFIG_SECTION` declarations also enable `config set/get/reset` for
free-form dotted settings at system and project scope. This declares a
namespace, not field names or types: a typo such as `jira.ur` is accepted, and
the connector's loader/doctor owns field validation. A setting the connector
declares is written with `configure` (below) instead, which refuses any key the
connector does not declare: for example,
`hashd connector jira configure --set url=https://company.atlassian.net` writes a
project override. A credential is never a setting: it goes in an account, with
`hashd connector login <connector>`.

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
go in your account, never in project settings. Each field is typed (`string`,
or `enum` with its `choices`). `required` means no operation works without it;
a field only some operations need lists them in `needed_for` (`references` --
resolving `@connector:ref`; `picker` -- searching or browsing for one; `notes`,
`events`, `checks`), so an optional mode stays configurable and each operation
says why it is unavailable: a ClickUp task or Azure work item referenced by id
resolves without the List or project the picker needs. `destination` marks the field your
account is stored for. A string field may carry a `pattern` the whole value
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
  project), the configuration files, and whether **you** have an account for
  the destination. It reports the destination, your account, and per operation
  whether its settings are set and you have a credential -- not a remote health
  claim.
- `check` (`GET /connectors/check`) checks the settings, then runs the
  connector's own `DOCTOR_CHECKS` with **your** account, or, for a
  `"project"` connector (`ACCOUNT_KIND`), the project's account. It never uses
  the project's `config.yaml`, environment or host credentials, in solo or
  team mode: without that account the authenticated check is refused. The
  credential is bound to its destination:
  the request names the destination it was chosen for, and the connector host
  refuses before any check runs unless the connector, loading its
  configuration there (environment overrides included), still points there:
  its `ACCOUNT_DESTINATION` of its `REMOTE_SCOPE` is the account's destination
  (for GitHub, the issues repository's host). The doctor checks reached here
  only read; GitHub's reads the credential and the repository on the
  repository's own host (`gh api --hostname`), never `gh auth status`, which
  tests every account on every host.

| Connector     | Your account                                                                                                                                                              | Destination                                  |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------- |
| GitHub issues | your account for the issues repository's host (`hashd connector login github`): an Issues token, or your forge login if you choose it; never the code repository's remote | `github.repo`                                |
| Jira          | your account (`hashd connector login jira`)                                                                                                                               | `jira.url`                                   |
| Azure Boards  | your account (`hashd connector login azure`)                                                                                                                              | `azure.organization_url`                     |
| ClickUp       | your account (`hashd connector login clickup`)                                                                                                                            | `clickup.workspace_id`                       |
| Confluence    | your account (`hashd connector login confluence`): Atlassian email and API token; it declares no checks                                                                   | `confluence.url`                             |
| Figma         | your account (`hashd connector login figma`): a personal access token                                                                                                     | none: every Figma account is for `figma.com` |

Note the order: `hashd connector status jira` lists your Jira accounts;
`hashd connector jira status` reports the project's Jira connector.

A connector that serves one place declares no destination field: its
`ACCOUNT_DESTINATION` names that place from no text, so `hashd connector login
figma` needs no `--destination`.

**Request reads.** The connectors above with your account
(GitHub issues, Jira, Azure Boards, ClickUp, Confluence, Figma) are read the same way
a check is: with **your** credential for the project's destination, pinned to
it, and never with the project's `config.yaml` credentials, the server's
environment or its `gh` login. This covers reference search
(`GET /connectors/search`), preview, artifact download, the story-source
availability a picker and an import read (`GET /connectors/capabilities`),
autocomplete, and suggestion import. Without a usable credential of your own
the read is refused and
says how to connect one (`hashd connector login ...`); nobody else's account
is used instead. Under
your credential, the credential fields in `config.yaml` are not read at all, so
a malformed one there cannot affect it. Solo mode, a team of one, reads the
same way: each of these reads takes the installation person's own account for
the project's configured destination, and is refused without one. The
connector checks in `hashd doctor` read the same way too, in solo and team
mode: a personal connector with the person's own account, and a project
connector with the project's account.

Search, preview and autocomplete (`GET /connectors/autocomplete`) use a cache
private to that one request, under the project's `.private-reads/`: nothing is
read from or written to a cache other users share, a returned file is read only
from that request's cache (a regular file, of its stated size and SHA-256), and
the cache is removed when the request ends.
Autocomplete is never answered from a shared cache: a connector that takes your own account
completes from its `SEARCH_REFERENCES` (Step 7). A cached listing (`@jira:issues`, `@github:issues`) and a cache-only read are
refused, since a shared cache holds what other users fetched. A server that
stops mid-request can leave that request's directory behind; nothing removes it
yet. The directory's file modes separate nothing between Hashd users, who share
the server's OS account: the boundary is that no shared read path reaches it.

**Planning reads as the story's owner.** In solo and team alike, the
references a planning or PM attempt or a tracker link captures for a story (its
typed `@connector:` references and attached items) from a connector that takes
your own account are read with the account of whoever owns the story at that
moment -- on a single-user server, the server owner when the story has none --
so a reassignment carries through to the next attempt, and the connector's
capabilities are answered through that owner's account too. The read uses a
cache private to the attempt, as search and preview do; what it returns is
copied into the story's captured inputs and the cache is removed. Nothing is
read with the project's config.yaml credentials, the server's environment, a
host login or another user's account instead. An unassigned story, or an
owner with no account stored for the project's configured destination, fails
the attempt once, without retrying, with the reason and how to fix it. A solo
operator who planned from project or environment credentials connects an
account of their own with `hashd connector login <connector>`.

**Implementing agents read the story's stored copies.** The latest captures of
its live linked items are verified and delivered into the run directory, with
read grants. No connector is called, and no account or shared cache is consulted.
The implement prompt stays as written: guidance, findings, answers and diffs
are not expanded, and failed-reference placeholders are never injected.

**Chat references are unavailable** in team mode for these connectors:
`@jira:KEY`, `@github:owner/repo#N`, `@azure:N`, `@clickup:ID`, `@confluence:ID` and
`@figma:NAME` in a chat message are
refused, in every turn and when the conversation is rebuilt, and not read with
anyone's credential. What such a read returns is a file the agent reads on later
turns, and nothing yet keeps it with the conversation. Before this change chat
read them with the project's or the server's credentials; that stopped
deliberately. A bare `@jira` still lists the connector's tools. Preview an item,
or paste what the conversation needs. In solo mode chat reads with the
project's configured credentials, except a connector whose sign-in has no
fields: it reads only with the solo operator's stored account, and is refused
without one. Runner-prompt references follow the same rule.

Not yet covered (#1856):

- Chat references to the connectors above: keeping what they return with
  the conversation, and answering later turns and rebuilds from it.
- Connector caches written before this change, and by solo mode, are not purged;
  implementation still unfolds references from the shared caches.

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
- `ACCOUNT_KIND`: required. Exactly one of `"personal"` (each person signs in
  with their own account) or `"project"` (the project's administrator sets one
  account the project uses). The project's administrator -- in team mode a
  user with the server's owner or admin role, in solo mode the install's
  operator -- sets or replaces that account for the selected project with
  `hashd connector login <connector> --project-account`, and removes it with
  `hashd connector logout <connector> --project-account [--destination
  <listed destination>]`. The account is set where the project's settings
  point the connector, so login takes no `--destination` and is refused, with
  how to configure the project, when the project points it nowhere. It
  follows `login`'s method, field and secret rules, piped secrets included,
  except that a forge login, a person's own, is neither offered nor accepted.
  Logout without `--destination` removes the account at the current
  destination; with one, it removes an account the project still holds at a
  destination it no longer points at. Anyone who can read the project sees the
  account in both status reports: `hashd connector status`, in a project, adds
  a "Project accounts" block after your own accounts (outside any project it
  lists only yours), and `hashd connector <name> status` prints it in place of
  the "Your account" line. Each prints `Project account: <connector>, set by
  <who> on <date>`, or that none is set and who may set it on this server, and
  each account left at a destination the project no longer points at on its own
  line naming that destination. When the project's destination cannot be
  resolved -- a setting missing, or the connector host unavailable -- it says so
  and lists every stored account only as stored, since which one is in use is
  unknown. Who set it is the server's wording: a removed
  user is marked `(removed)`, and an account set on a single-user install reads
  "the operator". `hashd connector status <name>` on a `"project"` connector
  reports this instead of a refusal, with any account of yours still
  stored there from before. The connector's Web page and the TUI Settings
  "Project accounts" section show the same record and, for someone the server
  offers it to, set, replace and remove it. Signing in to a `"project"` connector
  without `--project-account` is refused with these commands, and no account
  of yours stands in for it.
  Every read, search, autocomplete, check, tool, note and event of a `"project"` connector uses that account for the project's configured destination, pinned to it, in solo and team mode; without one it is refused with who may set it and `hashd connector login <connector> --project-account`. Chat and runner stage prompts do not read a `"project"` connector; a runner stage reference to an item the story holds a stored copy of is answered from that copy without reading the connector.
  `hashd connector <name> check`,
  `hashd connector <name> status`, `hashd doctor` and the connector overview
  use the project's account for the destination the project points at, in
  both modes; with none there, or one that cannot be opened, they say so,
  naming who may set it and `hashd connector login <name> --project-account`.
  A person's reference search, preview, download and autocomplete of a
  `"project"` connector, and the capabilities that pickers and suggestion
  import read, also use that account, in both modes, with a cache private to
  the request; with none, each is refused for that reason, and the picker and
  import show the reference action unavailable with it. Every connector also declares at least one method
  in `LOGIN_METHODS`. A connector that declares no kind, any other value, or no
  sign-in method is refused. It offers no reads, searches, autocomplete, tools,
  note or event delivery, sign-in or configure, and `hashd connector status`,
  `hashd connector <name> status`, `hashd connector <name> check`,
  `hashd doctor` and the Web connector settings show the reason and the fix,
  which is one of:
  - `it declares no ACCOUNT_KIND; declare ACCOUNT_KIND = "personal" or ACCOUNT_KIND = "project" in its package`
  - `ACCOUNT_KIND is <value>, not "personal" or "project"; declare exactly one of them in its package`
  - `it declares no LOGIN_METHODS; declare at least one sign-in method, with no fields if the connector needs no credentials`
- `LOGIN_METHODS`: the ways a person signs in to the destination. Each method's
  fields are one complete credential set, stored and handed to the connector
  under exactly those keys, so a connector's `CREDENTIAL_MODES` should be
  derived from it (the bundled ones are). A method may declare no fields: it
  is for a connector that needs no credentials, such as a public feed or a
  logger. Signing in with it asks for nothing and stores no secret, but it
  records the account, and that account is what lets the connector be used. A
  method with fields still needs at least one secret field. A secret is never
  shown back and never has an example. A
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
  itself instead of showing the connector's own description. Static forge
  tokens carry the warning that they can also push code and merge pull requests.
  With `forge_login_resource`, the method instead acquires that resource from
  the person's renewable destination binding; it never falls back to a static
  forge token. Azure Boards declares `azure_boards`, delivered as `access_token`.
  Project accounts cannot use either forge-login method. The server's account store, its CLI (`hashd connector login`)
  and the Web page all read a connector's `LOGIN_METHODS`, and none names a
  connector.
- `ACCOUNT_DESTINATION`: required, along with a
  `CONFIG_FIELDS` field marked `destination`. A function from what a person
  typed (a site URL, a workspace ID) to the destination their account is stored
  for. Applied to what `REMOTE_SCOPE` reports, it must give the same answer:
  that is how an account is found for every project at that destination, and
  what the host checks before your account is used. For most
  connectors the two are the same string; one account may also cover many
  scopes (GitHub: the host, for every repository on it). Raise
  `ValueError` with a message written for the person on anything that is not a
  destination. It must be pure -- no network, no project -- because the server
  asks it whenever it resolves a destination (`account_destinations`, one host
  call for every connector asked about) and keeps the answers briefly.

- `NOTES_MARKDOWN`: `True` when the comments its `SYNC_BACKEND` posts render
  Markdown, so what Hashd adds to a note (an attribution) is escaped as
  Markdown there.

- `NATIVE_QUERY`: the label of the connector's own query language, a
  non-empty string ("WIQL query") shown where a query is entered. A search of
  a connector that declares one may carry a single native query, which
  reaches the tracker unparsed and with no project-scope clause added: the
  query a person wrote is the whole query. A connector that declares none
  refuses one, and a native query is never combined with the declared
  filters or with search text; it pages through the same cursor as any
  search.

- `WATCH_DEFAULT`: the filter a watch of a person's own not-done work in the
  tracker opens on, written only in the connector's declared filter keys
  (`ReferenceAction.filters`). The value `me` means the reading account's
  own user. A connector whose default depends on project settings declares a
  callable of the project directory instead of a dict. The host checks it
  like `ReferenceIntake.default_filters`: a default naming an undeclared
  filter, an empty or blank value, or several values on a single-value
  filter is the connector's defect. The default then reads as not declared,
  `capabilities` reports the reason as `watch_default_problem`, and a watch of
  the connector is refused with it; its reference action, and so its picker
  and imports, are unaffected.

- `CREATE_STORY` (#2918): called with the project directory, it returns an
  object whose `find_or_create(story)` finds the tracker story carrying
  `story.stamp`, else creates it as the fixed view (`TrackerStoryContract`:
  title, problem, criteria, the line naming the hashd story and its link), and
  returns its native id and whether it created it. The host's `create_story`
  verb calls it behind the same gates as a write (`MODIFIES_EXTERNAL`,
  configured, a readable destination). Settings only creation needs declare
  `needed_for: create`.

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

| File                         | What                                                        |
| ---------------------------- | ----------------------------------------------------------- |
| `commands/doctor.py`         | Runs `DOCTOR_CHECKS` for configured connectors              |
| `lib/ref_resolver.py`        | Dispatches `@connector:ref` to `ARTIFACT_RESOLVER`          |
| `lib/agents_config.py`       | Injects MCP config for `TOOLS` into agent commands          |
| `server/api/autocomplete.go` | REST endpoint for TUI autocomplete (caller's own account)   |

---

### Connector events (opt-in)

A connector can act on committed Hashd facts about a story it is attached to.
It declares `EVENT_HANDLER` and `EVENT_TYPES`. A project then subscribes the
connector by name, in the connector's own section:

```yaml
azure:
  events:
    subscribe: [requirements_approved, workstream_ready_to_merge]
```

Nothing is sent until a project subscribes. Subscribing to events does not
change notes: a milestone subscribed as an event is also still documented as a
note, unless notes are switched off.

**Types.** These are the note milestones: `requirements_approved`,
`story_edited`, `clarification_answered`, `workstream_ready_to_merge`,
`workstream_changes_requested`, `workstream_merged` and `workstream_pr_link`.
`workstream_changes_requested` is a note as well as an event, subscribed under
`workstream_changes_requested`; it is in the default note kinds, and
`outbound_notes.events` and `outbound_notes.enabled: false` govern its note
separately from `events.subscribe`. Its note names the story and the
workstream, says the pull request's review requests changes, and includes the
PR link when one is stored. It is announced when the PR watch newly records a
changes request that it dates at the PR's current head; an undated request, an
operator reject, a failed internal review or another merge blocker announces
nothing, and announcing does not move the workstream. Each occurrence is keyed
by the recorded request (PR, head and requesting reviewers), so it is delivered
once per attachment per recorded request: a re-observation or replay delivers
nothing new, while a new head or a different reviewer set delivers again. `workstream_plan` is a note
only, never an event: the plan a workstream's breakdown wrote, its
micro-commits as stored, posted when it is made and again only when a later
breakdown, whole or partial, replaces it, marked replacing. The
`workstream_ready_to_merge` note carries the final review as recorded: its
verdict and the reviewer's summary. A note is never cut; one the tracker
refuses is a failed note on the story, whole. Four more types are events
only, never notes:

- `story_implemented`: the story reached implemented. This happens
  automatically once every workstream it owns has finished, or when an
  operator marks it implemented.
- `story_abandoned`: the story was closed, cancelled, or abandoned.
- `story_closed_by_person`: a person closed the story. Either an operator
  closed it with a reference
  (`hashd close <story> --ref <ref> --reason "..."`), because its work landed
  outside Hashd or no change was needed, or Hashd's merge archive closed it
  because a person merged its PR on the forge (`forge_merge` is `"true"`).
- `workstream_started`: the story's workstream moved into implementing for the
  first time. It is published once per workstream, and later returns to
  implementing publish nothing.

`story_implemented`, `story_abandoned` and `story_closed_by_person` are
terminal, so each happens at most once per story. Unlike the workstream
milestones, they speak for the whole story. An unknown name is
ignored with a warning. A type the connector's `EVENT_TYPES` does not declare is refused at
delivery, and the refusal is recorded on the story.

**Default tracker behavior.** Subscription is still required. The default
work-start milestone is `requirements_approved`. Existing `workstream_started`
support and its connector mappings remain available. These defaults use the
existing lifecycle settings as overrides; no new keys are needed.

| Event | Azure Boards | ClickUp | GitHub Issues | Jira |
| --- | --- | --- | --- | --- |
| `requirements_approved` | InProgress; override: `azure.lifecycle.requirements_approved`. Missing default category: successful no-op; ambiguous states require `.states`. `{to: [...]}` sets explicit target states instead, optionally restricted by `from: [...]`. | Unchanged; override: `clickup.lifecycle.<list id>.requirements_approved` (`to` / `from`). | Unchanged, no default label; override: `github.lifecycle.labels.requirements_approved`. | No inferred move; an unmapped subscribed event is refused; add `jira.lifecycle.requirements_approved` (`to` / `from`). |
| `workstream_pr_link` | InProgress; override: `azure.lifecycle.workstream_pr_link`. Missing default category: successful no-op; ambiguous states require `.states`. `{to: [...]}` sets explicit target states instead, optionally restricted by `from: [...]`. | Unchanged; override: `clickup.lifecycle.<list id>.workstream_pr_link` (`to` / `from`). | Unchanged, no default label; override: `github.lifecycle.labels.workstream_pr_link`. | No inferred move; an unmapped subscribed event is refused; add `jira.lifecycle.workstream_pr_link` (`to` / `from`). |
| `workstream_ready_to_merge` | Resolved; override: `azure.lifecycle.workstream_ready_to_merge`. Missing default category: successful no-op; ambiguous states require `.states`. `{to: [...]}` sets explicit target states instead, optionally restricted by `from: [...]`. | Unchanged; override: `clickup.lifecycle.<list id>.workstream_ready_to_merge` (`to` / `from`). | Unchanged, no default label; override: `github.lifecycle.labels.workstream_ready_to_merge`. | No inferred move; an unmapped subscribed event is refused; add `jira.lifecycle.workstream_ready_to_merge` (`to` / `from`). |
| `workstream_merged` | Resolved; override: `azure.lifecycle.workstream_merged`. Missing default category: successful no-op; ambiguous states require `.states`. `{to: [...]}` sets explicit target states instead, optionally restricted by `from: [...]`. | Unchanged; override: `clickup.lifecycle.<list id>.workstream_merged` (`to` / `from`). | Unchanged, no default label; override: `github.lifecycle.labels.workstream_merged`. | No inferred move; an unmapped subscribed event is refused; add `jira.lifecycle.workstream_merged` (`to` / `from`). |
| `workstream_changes_requested` | No default; an unmapped subscribed event is refused; set `azure.lifecycle.workstream_changes_requested` (`{category: InProgress}`, the only category allowed, or `{to: [...]}` optionally restricted by `from: [...]`). The only event whose move may go back; `Completed` and `Removed` items are never touched. | Not adopted; refused as undeclared if subscribed. | Not adopted; refused as undeclared if subscribed. | Not adopted; refused as undeclared if subscribed. |
| `story_implemented` | Completed; override: `azure.lifecycle.story_implemented`. Missing default category: successful no-op; ambiguous states require `.states`. `{to: [...]}` sets explicit target states instead, optionally restricted by `from: [...]`. | Sole closed/done status; override: `clickup.lifecycle.<list id>.story_implemented` (`to` / `from`). Zero targets: successful no-op; several targets: refusal. | Close as completed; override: `github.lifecycle.close`. Labels are optional via `github.lifecycle.labels.story_implemented`. | No inferred move; an unmapped subscribed event is refused; add `jira.lifecycle.story_implemented` (`to` / `from`). |
| `story_abandoned` | Removed; override: `azure.lifecycle.story_abandoned`. Missing default category: successful no-op; ambiguous states require `.states`. `{to: [...]}` sets explicit target states instead, optionally restricted by `from: [...]`. | Sole closed/done status, the same as implementation because ClickUp has no abandoned status type; override: `clickup.lifecycle.<list id>.story_abandoned` (`to` / `from`). Zero targets: successful no-op; several targets: refusal. | Close as not planned; override: `github.lifecycle.close`. Labels are optional via `github.lifecycle.labels.story_abandoned`. | No inferred move; an unmapped subscribed event is refused; add `jira.lifecycle.story_abandoned` (`to` / `from`). |
| `story_closed_by_person` | Unchanged: no default move, a successful no-op. Mapped by `azure.lifecycle.story_closed_by_person` (`{category: Completed}`, the only category allowed), it moves to Completed; ambiguous states require `.states`. Or `{to: [...]}` names explicit target states, optionally restricted by `from: [...]`. | Unchanged: no default move, a successful no-op. Mapped by `clickup.lifecycle.<list id>.story_closed_by_person` (`to` / `from`), it moves to that closed/done status. | Left open: no default close. Closed as completed only when `github.lifecycle.close` names it. Labels are optional via `github.lifecycle.labels.story_closed_by_person`; a label alone does not close. | No inferred move; an unmapped subscribed event is refused; add `jira.lifecycle.story_closed_by_person` (`to` / `from`) with a done-category `to`. |

An equivalent default the tracker cannot express succeeds without a write;
an explicitly configured move that cannot be made is refused. In Azure, set
`azure.lifecycle.<event>.states` to select among several states in the target
category; an unavailable category named by an override is refused. Azure also
takes `azure.lifecycle.<event>: {to: [state names]}`: the first listed state the
item's type has, by exact name, with no category fallback; none available is
refused, naming the item, its current state and every target, with no move
attempted. An optional `from: [state names]` allows the rule only from those
current states, matched exactly against the item as read for that delivery
(`[]` allows none; without `from`, any state); any other state is refused,
naming the item, its current state and every configured source, with no move
attempted, so a card moved by hand is left where it is and the refusal is
recorded. For example, `workstream_ready_to_merge: {to: [Code review], from: [Doing]}`
moves within InProgress and `workstream_changes_requested: {to: [Doing], from: [Code review]}`
moves back. Azure moves set work-item states, not board columns.

Azure moves go forward across state categories, and finished items
(`Completed` or `Removed`) are never edited or reopened by any rule; Azure
explicit `to` moves may also move within a category, but leave an item in a
state mapped to a later milestone alone successfully, without a write or refusal
record. The order is `requirements_approved` < `workstream_started` <
`workstream_ready_to_merge` < `workstream_pr_link` < `workstream_merged` <
`story_implemented` = `story_abandoned` = `story_closed_by_person`. The map uses
configured moves or their defaults to select targets for the item's type,
ignoring each milestone's `from`; a shared state counts for the latest milestone,
and a state no milestone selects is not judged. For unfinished items, the
delivery's own explicit `from` precondition is checked before target selection
and the milestone check: an excluded current state is refused and recorded,
even at a later milestone. `workstream_changes_requested` is the only exception:
its move may go back within or across categories, as `from` allows.
Azure ranks state categories for every other move; configured ClickUp moves and Jira rely on the operator's
`from` / `to` mapping to define progression. For an unmapped `story_implemented`
or `story_abandoned`, ClickUp uses the List's sole `closed`/`done` status by
default. GitHub adds
milestone labels, never
removing or ranking them. Only the story's own terminal events finish an item;
a workstream milestone never does. Before terminal writes, including GitHub
labels, `attachment_shared: "true"` leaves the item alone, `"false"` permits
the action, and an absent or invalid fact is refused. The fact is a delivery
snapshot from this project's records, with the limits described below.

GitHub supplies no default labels: they belong to the repository and must
already exist there. An absent `github.lifecycle.close` enables the
`story_implemented` and `story_abandoned` closes; `story_closed_by_person` has
no default and closes an issue, as completed, only when an explicit list names
it. An explicit list, including `[]`, is authoritative. **Compatibility:** a
subscribed `story_implemented` or `story_abandoned` with a label and no close
list now also closes; `close: []` preserves label-only behavior. A
`story_closed_by_person` label with no close list does not close. Unmapped
non-terminal events succeed without edits. Jira retains its configured
transition behavior and infers no default move.

**The event.** The host verb is `deliver_event`. Each event carries:

- `type`, `occurrence` and `occurred_at` (when it was published, just after
  the commit);
- the story, the workstream, and the attached item (`external_id`,
  `connection_id`);
- `facts`: the title, and the link where there is one. `story_closed_by_person`
  also carries its closure, whole: `reason`; `reference_form` (`pr`, `commit`
  or `story`) and `reference_value`, the reference as recorded; `forge_merge`,
  `"true"` when a person's merge on the forge closed the story and `"false"`
  otherwise; and, for a `pr` reference, the PR's page as its `link`.
  `story_implemented`, `story_abandoned` and `story_closed_by_person` also
  carry `attachment_shared`: `"true"` when another story in this project, not
  yet in a terminal state, is attached to the same remote item (same
  connector, `connection_id` and `external_id`), and `"false"` when none is.
  It is absent when it could not be read; treat that as unknown, never as
  `"false"`. It is read at delivery from this project's
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
  with the story owner's account (`credential.kind: owner`).
- A pull request's changes request (`workstream_changes_requested`) is made by
  the reviewer; the event is caused by the system, which observes that request
  and announces it, and is acted on with the story owner's account
  (`credential.kind: owner`) for a personal connector, as for ready to merge.
- A workstream starting implementation (`workstream_started`) is caused by the
  system, and acted on with the story owner's account
  (`credential.kind: owner`), as for ready to merge.
- A merge or a PR link that Hashd performed (`hashd merge`, `hashd pr create`)
  is caused by the account that requested it. It is acted on with the
  story owner's account, as for ready to merge.
- A story milestone is caused by the signed-in account, and acted on with
  that account. That includes an operator marking a story implemented,
  abandoning it, or closing it with a reference.
- A story Hashd found implemented, once every workstream finished, and a
  story Hashd's merge archive closed by person because a person merged its PR
  on the forge, are attributed to the **story's owner** (`kind: user` with the
  owner's id) and acted on with the owner's account (`credential.kind:
  owner`). This records who is responsible for the story. It does not claim
  the owner performed any merge; each merge keeps its own attribution above.
  An unassigned story's event is withheld.
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
connector host for this delivery. It is the same account a note would use: the
author's or work owner's own connected account for the attachment's
destination, and never a fallback account, in solo and team mode alike. For a
`"project"` connector it is the project's account, in both modes
(`credential.kind: project`, with no `user_id`).

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

### Stored-item change values (opt-in)

When a story is planned, Hashd stores a copy of each outside item it
references, with the item's change value at that time: the per-item value the
connector writes as `version` on the `ResourceReference` it returns (Jira's
`updated`, a Confluence page's version number). A connector that can read
that value again declares `READ_VERSIONS`, and Hashd can then check whether a
stored copy is still current and still visible to the person whose lane
depends on it.

`READ_VERSIONS(project_dir, items)` receives a list of `StoredItem`, one per
stored copy:

| Field                 | What                                                    |
| --------------------- | ------------------------------------------------------- |
| `connection_id`       | where the item lives, as its capture recorded it (a site, a workspace, a Figma file key) |
| `resource_id`         | the item's id there, as stored                          |
| `canonical_reference` | the item's `@connector:argument`, as stored             |
| `version`             | the change value recorded with the stored copy          |

It returns a dict from each item's identity, `item.key` (the pair
`(connection_id, resource_id)`), to an `ItemVersion`. Answers are never keyed
by `canonical_reference`: two stored items can share a spelling (`frontend#7`
and `backend#7`, a "Login" frame in two Figma files, one key on two Jira
sites), and each gets its own answer. On the wire the host returns each answer
with that identity, and core matches it to the stored item by connector,
`connection_id` and `resource_id`. An `ItemVersion` is exactly one of:

| `outcome`        | Meaning                                                              |
| ---------------- | -------------------------------------------------------------------- |
| `value`          | `value` is the item's current change value, in the form `version` is recorded; an optional `reason` is the connector's note on what the value covers, shown beside a change (Figma's says the file changed, not the frame) |
| `no_access`      | the tracker refused the item to the reading account                  |
| `not_checked`    | the item could not be checked; `reason` says why                     |
| `not_comparable` | the recorded `version` is not a value the item can report, so nothing can be compared |

It reads live, with the account the host was handed, and neither reads nor
writes a cache. It is checked with the gates of every read made with an
account: the destination that account was chosen for is required and must
still be where the connector points, by the connector's own
`ACCOUNT_DESTINATION` rule. Each item reaches the connector with its stored
identity unchanged: a `connection_id` is the item's identity, not an account
destination (a Figma reference's is its file key, while its account is for
figma.com). Exactly one answer comes back for every item asked about. An item the
connector omits, an empty `value`, and every item of a call that raises are
not checked, with the reason; an answer for an item that was not asked is
dropped.

**How core reads an answer.** Core compares strings and nothing else. It
parses no date and names no connector:

- a `value` equal to the recorded `version` means unchanged;
- a different non-empty `value` means changed;
- `no_access` means the reading account has no access to the item;
- `not_comparable` (a Figma capture made before change values were recorded
  holds Hashd's own sync time) is skipped: no check and no notice. It is
  never could not be checked;
- everything else is could not be checked.

The check is advisory. Whatever it finds, the lane keeps reading the stored
copy. A connector that declares no `READ_VERSIONS`, is not installed, or has a
refused declaration gets no check, and no notice, also when the read itself
finds it so: the host refuses such a read with the diagnostic source
`connector_host.versions_excluded` (`connectors.VersionsExcludedSource`),
which core reports as nothing, as it does an `account_destinations` answer
marked `excluded` (the connector is not installed or its declaration is
refused).

## 2. @connector:ref Resolution

### How it works

The Go tokenizer `refs/refparse` is canonical. Each connector declares
`REFERENCE_PATTERN`, an RE2 argument grammar exposed as `reference_pattern`
beside `has_reference_action` in the existing capabilities declaration. For
example, Jira declares issue-key/number syntax; an arbitrary `@word` is not a
connector reference. Built-ins declare their patterns in `BuiltinTypes`.

Matching begins at a word boundary. Emails, git URLs, credential URLs, package
scopes, mentions, and at-signs inside paths are plain text. `\@jira:PROJ-123`
and anything in a Markdown code span/block are also literal. `@file:./src/foo.go`
accepts repository paths and leaves sentence punctuation and Markdown closers
outside the reference.

Planning captures connector sources under the story's content owner. Chat
resolves newly submitted operator-authored text through the same tokenizer. Cold
chat replay keeps each historical user turn as written, with a notice in that
turn naming any earlier reference source that cannot be read now and its actual
Diagnostic. Historical references never refuse a rebuild; no per-turn source
snapshot is inferred. Implementation
receives linked source files separately and leaves all authored text unchanged.

### Reference types

| Pattern                 | What happens                                         |
| ----------------------- | ---------------------------------------------------- |
| `@figma:job-list`       | Resolves to cached file references (JSON, SVG, TXT)  |
| `@github:owner/repo#42` | Resolves to cached/fetched GitHub issue details; `@github:42` is shorthand for the configured repository |
| `@jira:PROJ-123`        | Resolves to cached/fetched Jira issue details        |
| `@jira:123`             | Resolves using default project key from config       |
| `@jira:OTHER:456`       | Resolves to `OTHER-456` (cross-project)              |
| `@diff`, `@story`, etc. | Built-in refs -- not routed to connectors            |

### ARTIFACT_RESOLVER contract

Batch interface -- receives all refs for the connector at once:

```python
def resolver(project_dir: Path, refs: list[str], fetch: bool) -> dict[str, ResolvedArtifact]:
```

- `fetch=True`: check staleness, fetch on cache miss (interactive contexts)
- `fetch=False`: cache only, error if missing (batch stages)
- Returns `ResolvedArtifact` with file references (path, format, size, description) or error
- Failures carry the existing `Diagnostic` in `ResolvedArtifact.diagnostic`; `error` may also retain source text. Author the reason and repair advice where the provider error is still available. Core never classifies provider prose.
- A tracker connector may also return `projection`, an `ItemProjection`: the
  item's type, state, revision, tags, display-only `attributes` in the
  tracker's own words, parent and child `links`, and `fields`, each a
  `ProjectedField` holding one field converted to Markdown (whole, with the
  SHA-256 of its bytes) under a role: `description`, `acceptance_criteria`,
  `repro_steps` or `other`. The connector maps its own facts into the neutral
  hints `story_type_hint` (`feature` or `bug`) and `target_repo_hint`. The
  contract names no tracker's concepts. Convert HTML with
  `hashd_client.html_markdown.html_to_markdown`, so every connector projects
  the same HTML to the same bytes; also write the Markdown as an `md` file in
  `files`, which is what the planner reads.

### Resolution output

Specific refs get file metadata:

```
@figma:job-list resolved to:
  Source: Figma: Job List (375x812pt)
  Figma source JSON: .cache/figma/frames/job-list.json (48KB)
  SVG visual export: .cache/figma/frames/job-list.svg (14KB)
  Structural text summary: .cache/figma/frames/job-list.txt (2KB)
```

### Error handling

An unresolved reference refuses the work before the agent starts. All failures
are listed together, each with its provider's reason and repair advice and a
backslash escape. A string-only error is preserved without an invented cause or
fix. The story's existing retry/edit commands remain available. A provider's
“missing or inaccessible” response is never restated as proof of nonexistence.

If this story already holds a verified stored copy, a failed refresh uses that
copy with a notice stating why it could not be refreshed. Another story's or
person's cache is not a fallback. Per-artifact Diagnostics survive the existing
connector-host conversion intact, including their explanation, help and evidence.

### Deduplication

Same ref appearing multiple times: first occurrence gets full metadata, subsequent get `(see @connector:ref above)`.

### Substitution safety

Substitution uses tokenizer byte spans for successful newly submitted chat references only.
Failures are refused, never replaced by inline error text. Grammar matching and
`BoundaryTail` keep adjacent identity text from matching a shorter reference.

---

## 3. Connector-Provided Tools

### ToolSpec

```python
@dataclass(frozen=True)
class ToolSpec:
    name: str                  # globally unique, model-facing
    description: str           # one line, shown to the agent
    parameters: dict[str, str] # param_name -> description; each an optional string
    handler: Callable[[ToolContext, dict[str, str]], str]

@dataclass(frozen=True)
class ToolContext:
    settings: dict[str, str]   # the connector's effective settings (declared fields, never secrets)
    account: dict[str, str]    # the work owner's stored account; empty for a sign-in method with no fields
    destination: str           # where that account is for
    cache_dir: Path            # the connector's own cache
```

A handler uses only its context: it reads no project configuration, environment
variable or other login. Core and the connector host speak tool contract
version `TOOL_CONTRACT_VERSION` (1); a call at any other version is refused,
with no compatibility path.

### Where tools run

Tools run on the server, in its connector host. An agent reaches them, wherever
it runs, through hashd's connector tool server (`hashd-tools`, `hashd code
connector-tools-mcp`), which forwards with the run's token:

- `GET /connector-tools?project=<p>` lists the tools the project's configured
  connectors declare.
- `POST /connector-tools/call?project=<p>` with `{connector, tool, arguments}`
  runs one. Only a declared tool, and only its declared parameters, are
  accepted.

The tool server holds no connector package and no connector credential, so a
runner carries neither.

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

## 5. Connector Tool Server

`server/internal/cli/connector_tools_mcp.go` -- the stdio MCP server
(`hashd-tools`) through which an agent calls connector tools.

### How it works

1. Orchestrator writes MCP config before agent invocation (format varies per agent)
2. Agent starts `hashd code connector-tools-mcp --project <p>` as a stdio subprocess
3. On `tools/list` it lists the project's tools from the server (`GET /connector-tools`)
4. On `tools/call` it forwards the call (`POST /connector-tools/call`) and returns the result, or the server's refusal as an error result

### Supported agents

| Agent       | Config mechanism                                          |
| ----------- | --------------------------------------------------------- |
| Claude Code | `--mcp-config` flag with JSON file                        |
| Codex       | `.codex/config.toml` in worktree                          |
| OpenCode    | `OPENCODE_CONFIG_CONTENT` environment overlay (`mcp` key) |
| Kimi Code   | `--mcp-config-file` flag with JSON file                   |
| Qwen Code   | `.qwen/settings.json` in worktree                         |

File-based configs are excluded from git via `.git/info/exclude`.

### Tools run as the work's owner

A connector's tools act for the person who owns the work, in every mode: the
owner the run's token recorded when the stage started (the workstream's, or the
story's when there is no workstream), so a reassignment takes effect at the
next stage.

- The server runs the tool in a connector host handed only that person's stored account for the connector's
  destination, and pinned to it: the host refuses before the tool runs if the
  connector points elsewhere. A credential value in what the tool returns is
  replaced with `[REDACTED]`.
- With no usable account (none stored, a run that names no owner, a declaration the
  host refused) the tool does not run, and the call is refused naming the
  sign-in command. Project configuration and environment credentials are never
  read instead. The stage itself is never refused for it.
- The agent never sees a connector credential: the account stays on the server.

---

## 6. Shipped Connectors

### Outbound story notes

hashd posts a story note on a tracker **only with the connected account of the
person the note speaks for**, in solo mode as in team mode. That is the
signed-in user whose action caused it (an approval, an edit, an answer), or
the linked story's owner for a workstream milestone (ready to merge, merged, PR
link), whoever clicked; a note with no recorded author on a solo server is the
installation person's own. Tracker story creation and connector events follow
the same rule for the same destination, with no fallback account for an event.
It never uses the server's own `gh` login or environment, or the project's
connector credentials, for a note. Commits, pushes and PRs are unchanged.

- **GitHub issues, Jira, Azure Boards, ClickUp, and every other connector that
  takes your own account:** each user can connect their account for one
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
by choice, your forge login), GitHub reads are refused and notes are withheld,
in solo mode as in team -- solo notes, events and tracker creation use the
author's or work owner's own account for the attachment's destination -- and
`hashd connector github check` is refused in either mode. Its fallback accounts (below) now use `destinations` (hosts or
repository URLs, each standing for its host), not `repositories`, so one
approves every repository on a host.

**Change from earlier versions.** Team projects whose notes were posted with
the server's `gh` login or a project token now withhold those notes until the
user connects a GitHub account, and a solo installation's notes, events and
tracker creations, which used the server's own login, are the author's or work
owner's own account now too -- in solo, the installation person's. For Jira,
Azure Boards and ClickUp they are withheld until the user connects an account
for that destination. A note is also withheld when nobody is identified and
nobody stands in, as only team mode allows: a request with no signed-in user,
an unassigned workstream, or a note queued before an upgrade. A withheld note is recorded on the story as
**not sent**, with the reason. The action that caused it still succeeds.

**Fallback accounts are temporarily suspended.** A project's choice of a
fallback account, described below, is currently never honoured, for GitHub,
Jira, Azure Boards and ClickUp alike. Each such note is recorded on the story as
**not sent**, with the reason "Fallback accounts temporarily suspended". A
person's own connected account is used exactly as before, and solo notes follow
the same account rule as team -- the author's or work owner's own account for
the attachment's destination -- with this fallback policy unchanged for notes
and no fallback for events. The central definitions and the project choices are kept as they
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
        label: Hashd automation # the name the note gives for who posted it
        destinations: [https://example.atlassian.net]
        email: hashd-bot@example.com
        api_token_env: HASHD_NOTES_JIRA_TOKEN # or pat_env, for Server/DC
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

GitHub issue reference resolver. Use `@github:owner/repo#42` (or `@github:42`, shorthand for the configured repository) in stories, acceptance
criteria, or chat to embed issue context. The connector reads issue details on
demand and caches them; it does not run a sync daemon. `hashd story link
STORY-x` with no reference finds or creates the story's issue: it looks in
`github.repo` for issues, open or closed (pull requests excluded), labelled
`hashd:<project>:<STORY-x>`. One is linked; two or more are refused, each
named. Otherwise the label is created if it is missing, and one issue is
created with the story's title, a body holding the problem, the acceptance
criteria and the "Created by hashd" line (a link to the story unless
`github.link_back` is `"false"` or hashd's `web.public_url` is localhost),
and the stamp label, then linked as `@github:<owner>/<repo>#<n>`. Its remote writes are that
created issue and its label, hashd's outbound story notes -- a comment or a
pull-request link on an issue already attached to a story -- and, only for the
lifecycle events a project subscribes it to, an optional mapped label on that
issue (connector events, above), and default closing on the story's own
`story_implemented` (completed) and `story_abandoned` (not planned) events,
and opt-in closing (completed) on `story_closed_by_person`, never while
another story in this project still in progress shares the issue. An explicit
`github.lifecycle.close` list overrides the defaults, including `[]` to
disable closing, and only a list naming `story_closed_by_person` closes on it.
A subscribed `story_implemented` or `story_abandoned` with a label and no
close list now also closes; `close: []` preserves label-only behavior. A
`story_closed_by_person` label with no close list does not close. There are no
default labels, and unmapped non-terminal events succeed without edits. All but
the created issue and its label are refused unless the configured repository
is still the one the issue was attached from.
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
not create hashd stories or run a sync daemon. Besides the issue
`hashd story link` creates (below), its remote writes are hashd's outbound
story notes (a comment or a pull-request link) and, opt-in, a status move for a
subscribed event mapped in `jira.lifecycle`. Notes and moves act only on an
issue already attached to a story, refused unless `jira.url` is still the site
the issue was attached from. Only the story's own terminal events
(`story_implemented`, `story_abandoned`, `story_closed_by_person`) may move an
issue to a status in Jira's done category, and not while `attachment_shared`
says another unfinished story still uses it; nothing reopens an issue. See
[Lifecycle moves](packages/hashd-connector-jira/src/hashd_connector_jira/README.md#lifecycle-moves).
`hashd story link STORY-xxx PROJ-123` links a story to an existing Jira issue,
and `hashd story link STORY-xxx` finds the issue labelled for it in
`jira.project_key` or creates one of type `jira.issue_type`; see "Tracker
stories" in [WF.md](../WF.md).

See [packages/hashd-connector-jira/src/hashd_connector_jira/README.md](packages/hashd-connector-jira/src/hashd_connector_jira/README.md).

---

### Confluence

Read-only Cloud page artifacts via `@confluence:123456` on the configured site.
Typed full URLs are unsupported by current shared input parsing. Bundled but
unconfigured; set the site with
`hashd connector confluence configure --set url=https://SITE.atlassian.net/wiki`.
Raw JSON/storage and a readable projection retain current content and report
conversion limitations. See the [provider guide](packages/hashd-connector-confluence/src/hashd_connector_confluence/README.md)
for token routes, tenant-verification limits and configuration. No connector CLI.
Each person reads Confluence with their own account for the site
(`hashd connector login confluence --destination https://SITE.atlassian.net`,
or its Web page): their Atlassian email and an API token. Solo chat references
do not use it yet.

### Azure Boards

Azure DevOps Services work items use `@azure:123` or the shared reference picker.
Search stays within the configured organization/project, or the projects
`azure.intake.sources` names in that organization; native state, assignee and
type filters preserve Azure values, and area path, iteration, tag, team,
`changed_since` and saved-query filters scope the listing to the team's board,
with `azure.intake` setting the picker's defaults. Explicit numeric references can read any
work item accessible to the credential within that organization, including other
projects. The configured project limits search, not direct-ID access; Azure
credential permissions and existing Hashd caller/project authorization still apply.
Full returned JSON reaches preview and
the same owned planning capture as typed references. Related targets and history
are not implicitly fetched, and there are no ownership claims. The only remote
writes include outbound notes on attached items and state moves on events
subscribed through `azure.events.subscribe`, forward-only across state categories
except for `workstream_changes_requested`. By default,
`requirements_approved` and `workstream_pr_link` target `InProgress`,
`workstream_ready_to_merge` and `workstream_merged` target `Resolved`,
`story_implemented` targets `Completed`, and `story_abandoned` targets `Removed`.
An explicit `azure.lifecycle.<event>` entry replaces only its own event's
default. A category entry (`{category, states}`) retains category and state
validation; an explicit-state entry (`{to: [state names]}`) moves to the first
listed state the item's type has, by exact name, bypassing the same-category
shortcut, the per-event category restriction and the sharing gate below, but
never moving back across categories (`Proposed` < `InProgress` < `Resolved` <
`Completed`, `Removed` reachable from any unfinished category) except for
`workstream_changes_requested`, and never touching a finished item; it is refused
without a category fallback when none is available, and its optional `from` list
restricts it to items currently in one of those states and refuses any other
without a write. Either form is tested
against the revision it was decided on. `workstream_started` and
`workstream_changes_requested` require an explicit entry (`workstream_changes_requested`
is the only event whose move may go back across categories, and its category form
allows `InProgress` only).
`story_closed_by_person` is terminal, may target `Completed` only, and has no
default: unmapped, it succeeds without a write.
A missing category succeeds without a write only for a default; several states
require a choice in `azure.lifecycle.<event>.states` even for a default.
Finished items are never touched by either form. For category moves, only a story's own
terminal events finish an item, and only when `attachment_shared` is `"false"`: `"true"` leaves it alone,
while an absent or unknown fact refuses the terminal move. The fact covers
other stories still in progress in this project.
`hashd story link STORY-xxx 1234` links a story to an existing Azure DevOps
story, `hashd story link STORY-xxx` finds the work item tagged for it in
`azure.project` or creates one of type `azure.work_item_type`, and
`hashd story unlink STORY-xxx` removes the link in hashd only; see "Tracker
stories" in [WF.md](../WF.md).
Set `azure.organization_url` and `azure.project` with
`hashd connector azure configure --set KEY=VALUE`. Each person signs in for the
organization with `hashd connector login azure --destination https://dev.azure.com/ORGANIZATION`,
with **Use my Entra sign-in** (renewed on use), a personal access token or an externally supplied Entra access token; solo chat
references do not use it yet. See the [provider guide](packages/hashd-connector-azure-devops/src/hashd_connector_azure_devops/README.md).

Azure Boards permission selection follows the operation, including POST reads:

| Boards operation | Required resource-prefixed permission | Retained grant satisfying it |
| --- | --- | --- |
| Item/reference reads; fields, types, states and team settings; saved-query definition/execution; WIQL, batch and search POSTs; story-stamp lookup | `499b84ac-1321-427f-aa17-267ca6975798/vso.work` | `499b84ac-1321-427f-aa17-267ca6975798/vso.work_write` inherits Work read |
| Work-item creation/updates, comments, PR relations and lifecycle state changes | `499b84ac-1321-427f-aa17-267ca6975798/vso.work_write` | Work write directly |
| Azure Repos PR lookup before adding an artifact relation | `499b84ac-1321-427f-aa17-267ca6975798/vso.code` | `499b84ac-1321-427f-aa17-267ca6975798/vso.code_write` inherits Code read |

For renewable access, configure `vso.work_write` and `vso.code` in the app's
Azure DevOps delegated permissions and have a tenant administrator grant consent
when required. Establish your organization binding, then select the Boards method:

```sh
hashd forge login --host dev.azure.com --scope your-organization --device-code
hashd connector login azure --destination https://dev.azure.com/your-organization \
    --method "Use my Entra sign-in"
hashd connector azure status
```

For missing Boards consent, repair the registration or consent as the refusal
instructs, then rerun the connector login command above. It enters the existing
browser/device-code flow requesting the Boards resource, then retries the binding.
Retry the failed operation manually. Web connector settings offers the same method
without fields when your organization has a renewable binding; its recovery
instructions lead to that CLI command. This is a personal account, unavailable
with `--project-account`.

For **Entra access token**, an explicit Bearer `insufficient_scope` refusal names
the operation's permission. Have the supplying app's administrator configure and
consent to it, obtain a replacement token, and store it with:

```sh
hashd connector login azure --destination https://dev.azure.com/your-organization \
    --method "Entra access token"
```

Retry the failed operation manually. `hashd forge login` cannot renew a pasted
token. `hashd connector azure configure` corrects the destination.
PATs retain their existing Basic
credential and Work Items/Code permission guidance. A plain 403 leaves
project/item authorization and token permissions uncertain; expiry and
connectivity failures keep their own diagnoses. Rejection bodies and challenges
may echo a credential and are not copied into diagnostics.


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
tracker task creation, hashd's outbound story notes (a comment or a pull-request link) and, opt-in, a
status move for a subscribed event. An unmapped `story_implemented` or
`story_abandoned` moves any open/custom task to its List's sole closed/done
status; no terminal status leaves it unchanged and succeeds. Several terminal
statuses refuse before writing: configure `clickup.lifecycle.<list id>.<event>`
with `to` and `from` to choose. A configured List/event move replaces the
default, resolves names ignoring case, and only moves from its named `from`
statuses to `to`. Other unmapped events succeed without a move, including
`story_closed_by_person`, which is terminal but has no default move. Notes and status moves
act only on a task already attached to a story, refused unless
`clickup.workspace_id` is still the Workspace the task was attached from. Only
the story's own terminal events (`story_implemented`, `story_abandoned`,
`story_closed_by_person`) may move a task to a closed or done status, and not
while `attachment_shared` says another unfinished story still uses it; nothing
reopens a task.
`hashd story link STORY-xxx 86a4xte6z` links a story to an existing ClickUp
task, `hashd story link STORY-xxx` finds the task tagged for it in `clickup.list_id`
or creates one in `clickup.list_id`, and `hashd story unlink STORY-xxx` removes
the link in hashd only; see "Tracker stories" in [WF.md](../WF.md).
Set `clickup.workspace_id` and `clickup.list_id` with
`hashd connector clickup configure --set KEY=VALUE`. Each person signs in for the
Workspace with `hashd connector login clickup --destination WORKSPACE_ID`, with a
personal token or an externally supplied OAuth access token; solo chat
references do not use it yet. See the [provider guide](packages/hashd-connector-clickup/src/hashd_connector_clickup/README.md).

### Stored-item change values

What each shipped connector's `READ_VERSIONS` reads to check a stored copy
(section 1, "Stored-item change values"). Each is read live with the reading
account, by the item's stored id in its stored destination; anything not
listed as no access is could not be checked.

| Connector | Value recorded and compared | No access |
| --------- | --------------------------- | --------- |
| Jira      | the issue's `updated`, exactly as Jira returns it, read by the stored issue id in the stored site | a 403, or a 404 carrying Jira's own error body. A 401, a 404 without Jira's error body (a wrong base path), no answer within the request timeout, a reply naming another issue, or an item stored in a site other than the configured one is could not be checked |
| Azure Boards | the work item's revision `System.Rev`, as a decimal string, read with a fields-limited request by the stored work item id in the stored organization | a 404 carrying Azure's own work-item error body. A 401, any 403 (including insufficient delegated scope: a 403 does not establish item access), a 404 without Azure's error body, a non-JSON answer such as a sign-in page, a reply naming another work item, or an item stored in an organization other than the configured one is could not be checked |
| ClickUp | the task's `date_updated`, exactly as ClickUp returns it, read by the stored task id, accepted only when the returned task's Workspace is the stored one | never: ClickUp documents no error code for a task that does not exist or that the account cannot access, so every refusal is could not be checked, with its reason. That includes a 429, an answer rejecting the token ("Token not found"), an answer about the token's Workspace grant ("Team not authorized", which says nothing about the person's access to the task), any answer without ClickUp's error body, a reply naming another task or another Workspace, and a task stored in a Workspace other than the configured one |
| Confluence | the page's `version.number`, as a decimal string, read without the page body by the stored page id on the stored site | a 403, or a 404 carrying Confluence's own error body (`errors` entries with its `status`, `code` and `title`). A 401, a 404 without Confluence's error body (a wrong path or token route, or another JSON error such as a gateway's), no answer within the request timeout, a reply that is not a page or names another page, a reply whose site evidence (`_links.base`) names another site or is missing from a Cloud ID-routed answer, or a page stored on a site other than the configured one is could not be checked |
| GitHub Issues | the issue's `updated_at`, exactly as GitHub returns it, read with `gh api` on the configured host from the stored reference's own repository (not the configured one) by the stored issue number. Captures made before change values were recorded have an empty `version` and are not checked until the story is captured again | a 404 carrying GitHub's own error body (`message` and `documentation_url`), or a 410 (a deleted issue). A 401, a 403 (GitHub also answers rate limits with 403), a 429, a 404 without GitHub's error body, `gh`'s sign-in-required exit (code 4), no answer within the `gh` timeout, a reply naming another issue or repository (a transferred issue), or an issue stored on a host other than the configured one is could not be checked |
| Figma | the file's `last_touched_at`, exactly as Figma returns it, read with the Tier 3 `GET /v1/files/:key/meta` from the stored frame's own file (its `connection_id`, not the configured `file_id`) on every profile, conservative included. One read per distinct file; every frame in it shares the answer, so a change says the file changed, not the frame. No Tier 1 call is made and the monthly call count is unchanged. Captures made before change values were recorded hold Hashd's own sync time (ending `+00:00`; Figma's value ends `Z`) and are not comparable: no check and no notice, and nothing stored is rewritten | a 404 carrying Figma's own error body (its `status` with `err`, or `error: true` with `message`): Figma documents it as the file not found. Every 403 is could not be checked, since Figma documents /meta's 403 as a rejected or expired token (one missing the `file_metadata:read` scope is named so). A 401, a 429, a 404 without Figma's error body (a gateway's JSON included), an unreachable API, no answer within the request timeout, a reply that is not JSON, no `last_touched_at` in the reply, or a reply whose `file.url` names another file is could not be checked, for that file only |

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
ACCOUNT_KIND = "personal"          # each person signs in with their own account
```

With its sign-in methods (`LOGIN_METHODS`, section 1), that's the minimum. hashd discovers it, `hashd doctor` shows it, `@linear` is reserved. Everything else is optional.

### Step 3: Add configuration

```python
# packages/hashd-connector-linear/src/hashd_connector_linear/config.py

import msgspec
from hashd_client.connector_env import resolve_connector_env
from orchestrator.lib.project_loader import load_project_yaml

CREDENTIAL_MODES = (frozenset({"api_key"}),)  # the fields of each LOGIN_METHODS entry

class LinearConfig(msgspec.Struct):
    api_key: str = ""  # from the account the server hands the host (section 1)
    team_id: str = ""

def load_linear_config(project_dir):
    raw = load_project_yaml(project_dir)
    section = raw.get("linear", {})
    credentials, _ = resolve_connector_env("linear", {}, section, CREDENTIAL_MODES)
    return msgspec.convert({**section, **credentials}, LinearConfig)

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
        results.append(DiagnosticResult("Linear auth", False,
            "no Linear account\n"
            "      sign in:  hashd connector login linear"))
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

### Step 6: Add tools (optional)

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

### Step 7: Add autocomplete (optional)

```python
def _autocomplete(project_dir, partial):
    return [("issues", "Issue listing")]

AUTOCOMPLETE = _autocomplete
```

`AUTOCOMPLETE` is used only by connectors that declare no `LOGIN_METHODS`. The TUI and other clients reach it through `GET /connectors/autocomplete`.

A connector that takes your own account is completed from its `SEARCH_REFERENCES` instead, read with the person's own account, and its `AUTOCOMPLETE` is never called. The first page of a search for what was typed is offered: each value is the item's `canonical_reference` after `@<connector>:`, described by its title (or its `resource_id` when it has none). A `search` action offers nothing until something is typed; a `browse` action lists with empty text. A person without an account for the project's destination is offered no completions and is told how to connect one, and a connector that takes your own account but no `SEARCH_REFERENCES` offers none.

### Step 8: Register as entry point

All connectors are discovered via the `hashd.connectors` entry point group. Register an entry point for your connector package, including workspace-local packages:

```toml
# your-package/pyproject.toml
[project.entry-points."hashd.connectors"]
linear = "your_package.linear"
```

### Step 9: Add cache strategy (optional)

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
