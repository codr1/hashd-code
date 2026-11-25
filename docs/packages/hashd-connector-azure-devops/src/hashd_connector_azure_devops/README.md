# Azure Boards references

Read work items from **Azure DevOps Services** using `@azure:123` in reference-enabled planning inputs, or choose Azure Boards in the shared reference picker. On-premises Server/TFS, arbitrary API hosts and typed page URLs are not supported. There are no connector commands or synchronization jobs. Remote writes include outbound notes and lifecycle state moves, described below.

Hashd's **forge sign-in** requests this audited Entra delegated permission set:

```text
499b84ac-1321-427f-aa17-267ca6975798/vso.code_write
```

Code write covers forge PR comments and inherits Code read (`vso.code`).
Boards operations, including the connector's PR-relation lookup, acquire their
own resource with Work write (`vso.work_write`) and Code read (`vso.code`)
when you select **Use my Entra sign-in**. Add both delegated permissions to
the same app registration and grant administrator consent when required. OIDC
`openid`, `profile` and `offline_access` remain for forge identity and renewal.

For forge setup, an administrator registers an Entra public client with
`http://localhost` under Mobile and desktop applications and enables public
client flows for device code. Under API permissions > Azure DevOps > Delegated
permissions, configure the Code write form above, replacing the old broad permission.
A tenant administrator selects Grant admin consent for the updated permissions
when tenant policy requires it. A Hashd server administrator sets:

```sh
hashd config set sso.entra.client_id <application-id>
hashd config set sso.entra.tenant <tenant-id, domain or organizations>
```

Existing forge users run one of these alternatives after that update:

```sh
hashd forge login --host dev.azure.com --scope <organisation>
hashd forge login --host dev.azure.com --scope <organisation> --device-code
```

Old broad access tokens cannot satisfy the new request. Missing consent enters
interactive sign-in once; successful consent restores held-account reuse, cached
acquisition and silent renewal without an unconditional consent prompt.

The renewable Boards method uses your sign-in bound to the selected organization.
Hashd acquires and renews a Boards token on use and delivers it as `access_token`;
it does not reuse the repository token. A removed or unusable sign-in refuses the
operation without falling back to PAT, project or environment credentials.
Explicitly pasted credentials remain static and must be replaced by their supplier.
See the endpoint and permission audit.

### Boards operation permissions and credential replacement

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

Point the connector at your organization and project, then store your own Azure DevOps account for the organization:

```bash
hashd connector azure configure --set organization_url=https://dev.azure.com/your-organization
hashd connector azure configure --set "project=Your Project"
# Your account. Search, preview, planning, notes, state moves, tracker stories
# and `check` use it; solo chat references do not use it yet.
hashd connector login azure --destination https://dev.azure.com/your-organization \
    --method "Use my Entra sign-in"
```

Choose renewable access above, or sign in with an externally supplied Entra access token (`--method "Entra access token"`, sent as Bearer) **or** a personal access token (`--method "Personal access token"`, sent as Basic). Signing in again replaces the stored account. `AZURE_DEVOPS_ORGANIZATION_URL` and `AZURE_DEVOPS_PROJECT` on the server override their nonempty configured counterparts. A variable that displaces a value the config did set is logged by name at load and named in a 401/403 read failure, so a shadowed organization or project does not report as an expired token; values are never logged. Credentials need work-item **read** access; where OAuth/PAT scopes apply, `vso.work` is sufficient for reading. Outbound notes additionally need **write** access (`vso.work_write`, Work Items Read & write); with a read-only credential reads keep working and each note is refused with a write-access message. Linking an Azure Repos pull request also needs **Code (Read)** (`vso.code`), to read the pull request's repository and project ids; an explicit delegated-scope rejection names Code read and its inherited write grant, while other failures retain their own diagnosis. Microsoft recommends Entra for new integrations; PAT remains a compatibility option. Hashd renews tokens only for the renewable method; pasted tokens remain externally managed. Expired or refused credentials produce a read failure without fallback to another credential.

**Tracker stories (#2918).** `hashd story link STORY-x` with no id finds the work item tagged `hashd:<project>:<STORY-x>` in `project` (WIQL `[System.Tags] CONTAINS`), else creates one of type `work_item_type` (required for this, no default): `System.Title` is the story's title, `System.Description` (HTML, every value escaped) holds the problem, the acceptance criteria and a line naming the hashd story, a link to it unless `link_back: "false"` or hashd's `web.public_url` is localhost, and `System.Tags` is the stamp. Two or more tagged work items are refused, each named; link one by its id. Creating needs **write** access, as notes do.

Your account is encrypted at rest, scoped to you and never shown again; the settings stay readable through the existing authorized configuration APIs.

Search is scoped to the configured organization/project (or the projects `azure.intake.sources` names, below), except a native query (below). Optional state, assignee and work-item-type filters use exact native Azure values; assignee `me` is `[System.AssignedTo] = @Me`, which Azure resolves for the account the search is read with, and it lists through WIQL even beside search text. Native paging is explicit; indexing, trimming and inaccessible-result notices remain visible.

### Intake: the board the team uses

The picker declares filters that scope a listing to one team's board. Values of one filter are alternatives (any may match), except `tags_all`; different filters all apply.

| Filter | WIQL |
|---|---|
| `area_path` | `[System.AreaPath] UNDER '<path>'` |
| `area_path_exact` | `[System.AreaPath] = '<path>'` |
| `iteration_path` | `[System.IterationPath] UNDER '<path>'` |
| `iteration: current` | `[System.IterationPath] = @CurrentIteration('[<project>]\<team>')`; needs `team`, because Azure resolves the current iteration per team |
| `tags_all` / `tags_any` | `[System.Tags] CONTAINS '<tag>'` per tag, AND / OR; a tag with spaces or quotes is matched as written, and `;` (the tag separator) is refused |
| `changed_since` | `[System.ChangedDate] >= 'YYYY-MM-DD'` |
| `team` | the team's area paths, read from `_apis/work/teamsettings/teamfieldvalues`, each with its children when the team includes them; a team whose board is scoped by another field is refused |
| `saved_query` | a stored query, by id or path, run as stored; no other filter or search text with it |
| `source` | one of `azure.intake.sources` |

Search text alone uses the search service, as above. Search text with any of the board filters, or with sources configured, joins the WIQL listing as `CONTAINS WORDS` on title and description, with the same id-ordered paging, so a page is never a search page with most results filtered away.

A saved query must be a flat query: a tree or one-hop query returns links, and is refused with its name. It cannot take the paging clause, so each page runs it again and pages over its result sorted by id; the cursor is bound to that result, and a changed result asks for a new listing. A result of 20,000 items (Azure's WIQL result limit, from Microsoft's reference) may already be cut, so it is refused naming the limit rather than listed short.

A search can instead be one native query (`NATIVE_QUERY`, "WIQL query or saved query id"): the whole search, never combined with filters or search text, and `azure.intake.sources` do not apply to it. A saved query's id runs that stored query as the `saved_query` filter does, in `azure.project`. Anything else is WIQL, posted as typed to the bound project's WIQL endpoint, so `@project` means `project`; no project clause is added, so it lists what it returns from any project of the organization. A query Azure refuses (HTTP 400) is reported with Azure's own reason, withheld only when the response carries the credential. It must return a flat list, and like a saved query each page runs it again and pages over its result sorted by id. A result of 20,000 items may already be cut: it is listed, and every page reports it incomplete.

A watch of a person's own work (`WATCH_DEFAULT`) opens on `assignee: me` in every open state category, and on `iteration: current` only when `azure.intake` sets a team for Azure to resolve it with: the picker's default `team`, which the watch then also searches with, or a `team` on every source. Without one the iteration is left out. The picker's defaults are unchanged.

`azure.intake` sets the picker's defaults: shown filled in and editable. Without it the picker opens on every open state category, as before; a malformed `azure.intake` makes the picker unavailable with the reason.

```yaml
azure:
  intake:
    area_path: ["Factory\\Team A"]
    tags_all: [factory]
    changed_since: 2026-09-01     # optional
    # or: saved_query: 0f6c...    # alone: a stored query takes no other filter
```

Several projects of the configured organization can be listed together. `project` stays the bound project (doctor's, and the saved query's); each source's own filters always apply to it, and the picker's filters narrow every source. Each source needs its own name and project: a listed item is labelled by the project it reports.

```yaml
azure:
  intake:
    sources:
      - {name: factory, project: Factory, area_path: ["Factory\\Team A"], tags_all: [factory]}
      - {name: payments, project: Payments, area_path: ["Payments\\Intake"]}
```

Several sources are one organization-level WIQL query OR-ing each (project AND its filters), keyset-paged by id, and every listed item must be in one of the projects. Each item names its source. A source the account cannot read is left out, and the page says which and why; when no source can be read, the listing fails. A saved query runs in `azure.project` and is not combined with sources. Writes are unchanged: notes and state moves act in the project the item reports for itself. One organization per Hashd project: accounts and the attachment destination are stored per organization.

The WIQL above, the team settings endpoint and the stored-query endpoints (`_apis/wit/queries/{id}`, `_apis/wit/wiql/{id}`) follow Microsoft's reference; they have not been run against a live organization from this repository. Search results can lag the current work item: Preview and Submit resolve the selected resource again, and the normal planning capture pins the bytes actually used by that execution. Direct numeric references do not depend on the search index.

Explicit numeric references are **organization-scoped**: an authorized connector caller can request any work item readable by the configured credential in that organization, including another project. `azure.project` restricts search; it is not a project-isolation policy for direct reads. Azure credential permissions and Hashd's existing caller/project authorization remain the access boundaries. Returned organization/item/revision identity is verified before caching or capture; a different organization is refused.

The artifact is the complete returned current work-item JSON (`$expand=all`), including custom fields and relation metadata. It is readable in full preview and supplied to the planner, with its producer digest verified by the shared capture boundary. Related files, comment pages and prior revisions are **not** fetched; their links do not claim full target delivery. The verified organization URL, returned item ID and revision identify the resource. Organization renames are not transparent identity migrations.

Beside the JSON, each read writes a Markdown projection of the work item (title, type, state, tags, area and iteration paths, parent and child links, and the configured fields converted from HTML by `hashd_client.html_markdown`), and returns the same projection typed. The Markdown file, each field under its role (description, acceptance criteria, repro steps), is what the planner reads as the imported item's input; the planner still writes the story's problem and criteria. Images stay links and are never fetched. The fields read are configurable, because processes rename them; the defaults are Microsoft's:

```yaml
azure:
  fields:
    acceptance_criteria: Microsoft.VSTS.Common.AcceptanceCriteria
    description: System.Description
    repro_steps: Microsoft.VSTS.TCM.ReproSteps
    extra: [Custom.Rationale]   # projected for display only
    target_repo: Custom.PrimaryWorkRepository   # optional: the repository the change belongs in
  types:
    bug: [Bug]                  # work item types projected as a bug story
```

Each fetch reads every configured field's definition (`_apis/wit/fields/{name}`). Azure leaves an empty field out of a work item response, so a configured field the item lacks is read as empty only because the organization defines it; a name the organization does not define fails the read naming the setting, rather than reading as "no acceptance criteria". `hashd doctor` checks every configured field the same way. The definition also gives the field's declared type: only an HTML field is converted to Markdown, and any other text field, such as a plain-text one, is kept as written, angle brackets and entities included. A cache-only read re-projects the cached JSON without asking, with the types its fetch recorded, and writes the Markdown projection when it is missing; a cache written before the types were recorded serves its JSON alone until the next fetch. `target_repo`, when set, names a text field whose value is returned as the projection's `target_repo_hint`, trimmed and otherwise as the item holds it; the server takes it as the story's target only when it is exactly the name of a primary or active repo, and otherwise a story with no target stops for a person to correct the field or register the repo, rather than being routed (docs/ARCHITECTURE.md).

Credentials go only to the configured organization's fixed `dev.azure.com` work-item (including, for `hashd doctor`, state moves and state-category listing, the work-item types and work-item type states, and for a `team` filter its team settings, and for projection and `hashd doctor`, the field definitions) and `almsearch.dev.azure.com` search API paths. Redirects are not followed. Cached reads preserve producer-recorded evidence; failed refreshes do not silently use an old successful response. Browse/preview/cancel never creates a story or link; typed and picked sources share the existing nonexclusive attachment path.

Provider HTTP calls use the shared 130-second API failsafe for each network phase, not a total elapsed-time guarantee. Managed calls also inherit caller cancellation and the 130-second bound on the whole connector host process; the per-phase provider bound does not extend that enclosing bound, so a slow multi-phase call can end at the host bound first. Standalone provider calls retain the network-phase bound.

Outbound notes are one of the connector's two writes, on a work item already attached through this connector: a comment, or a pull-request link. A pull-request link is a relation on the work item plus the comment `Linked PR: <url>`. For an Azure Repos pull request in the configured organization (`dev.azure.com/{org}/{project}/_git/{repo}/pullrequest/{id}`, or the `{org}.visualstudio.com` form), the relation is the `ArtifactLink` Azure writes itself (`vstfs:///Git/PullRequestId/{projectId}%2F{repositoryId}%2F{id}`, named "Pull Request"), so the item's Development section shows it and a "linked work item" branch policy accepts it; the ids come from the Git API's pull-request read. Any other URL, including an Azure pull request in another organization, is a `Hyperlink` relation. The work item is read with its relations first: the same URL already there is not written again. The relation is a JSON Patch tested against the revision read, so an item changed since is refused, not overwritten, and nothing retries; a refused link posts no comment. A note changes no state or field. A note is posted under the project the work item reports for itself, because attachment identity is organization-scoped as above; the organization is also the destination checked before every write, so repointing `azure.organization_url` refuses notes for items attached from the old one. Notes use the comments API's markdown format, and that API is still a preview version (`7.1-preview.4`) on Microsoft's reference, unlike the reads.

The server delivers a Hashd connector event only for the types a project subscribes the connector to (`azure.events.subscribe`). State moves on the attached work item have these defaults, with no `azure.lifecycle` configuration required:

| Event | Default state category |
| --- | --- |
| `requirements_approved` | `InProgress` |
| `workstream_pr_link` | `InProgress` |
| `workstream_ready_to_merge` | `Resolved` |
| `workstream_merged` | `Resolved` |
| `story_implemented` | `Completed` |
| `story_abandoned` | `Removed` |
| `workstream_changes_requested` | None: an unmapped subscribed event is refused; set `{category: InProgress}` or `{to, from}` |

An explicit `azure.lifecycle.<event>` entry replaces that event's default, and leaves every other event's default as it is. `workstream_started` and `workstream_changes_requested` still require an explicit entry. `story_closed_by_person` has no default: unmapped, the delivery succeeds and the work item is left untouched, until `azure.lifecycle.story_closed_by_person` maps it. An entry takes one of two forms, never both:

- **Explicit target states**, `{to: [state names], from: [state names]}`: a nonempty list of nonblank state names, in order of preference. The target is the first name the item's type has in the item's own project, matched exactly (case included). An item already in that state is left alone without a write. When none is available the move is refused and recorded on the story, naming the work item, its current state, every configured target and the type's states, and saying no move was attempted; there is no fallback to a category. An explicit rule is the operator's decision, so it skips the same-category shortcut, the event-specific category restriction and the `attachment_shared` gate below, and can move forward within one category: it leaves alone a state the map sets for a later milestone. The order is `requirements_approved` < `workstream_started` < `workstream_ready_to_merge` < `workstream_pr_link` < `workstream_merged` < `story_implemented` = `story_abandoned` = `story_closed_by_person`. A state no milestone sets is not a later milestone; before writing, the manual-move guard below checks it. It still moves only forward across categories (`Proposed` < `InProgress` < `Resolved` < `Completed`, with `Removed` reachable from any unfinished category): a target in an earlier category than the item's current state leaves the item alone without a write. `workstream_changes_requested` is the one exception: its rule moves the item to the first available target, back as well as forward, from a `Proposed` state or a state the map sets for any milestone (or any unfinished state allowed by `from`). Like every rule, it never touches an item in `Completed` or `Removed`. An optional `from: [state names]` restricts the rule to items whose current state, as read for that delivery, is one of those names, matched exactly; `[]` allows none. When set, `from` overrides the manual-move guard below; when absent, that guard decides. Nothing earlier is remembered: each delivery decides from its own read. For unfinished items, this source precondition is checked before target selection and the milestone check. Any other current state, even at a later milestone, is refused and recorded on the story, naming the work item, its current state and every configured source, and saying no move was attempted, so a card someone moved by hand is left where it is.
- **A category move**, `{category, states}`: the rules below decide whether and where the item moves.

An entry may also carry a `types` mapping keyed by exact `System.WorkItemType` name (case included), either alone or alongside a shared rule in either form. Each per-type value takes the same `{to, from}` or `{category, states}` form and validation. For an item's type, the connector selects its matching per-type rule, else the entry's shared rule, else the event's default (or, for an event without a default, the same unmapped behaviour: `story_closed_by_person` succeeds without a write, and any other unmapped event is refused). The within-category milestone map is read per type through the same lookup. `hashd doctor` checks per-type `types` mappings against `azure.project` (reading each mapped type's states once), reporting missing types, missing states in `to`/`from`/`states`, `states` entries outside their rule's category, and `to` states outside the event's allowed categories; `from` is checked for existence only, and shared event-level state names are not checked against a type.

```yaml
azure:
  events:
    subscribe: [requirements_approved, workstream_started, workstream_pr_link, workstream_ready_to_merge, workstream_changes_requested]
  lifecycle:
    workstream_pr_link: {category: InProgress}
    # Per-type rules keyed by exact System.WorkItemType name, optionally beside a shared rule.
    workstream_started:
      to: [Active]
      types:
        Bug: {to: [Doing]}
    # Doing -> Code review, both InProgress states: a move no category rule makes.
    workstream_ready_to_merge: {to: [Code review], from: [Doing]}
    # Back to Doing when a review requests changes, only from Code review: a card moved elsewhere is left alone.
    workstream_changes_requested: {to: [Doing], from: [Code review]}
```

Moves set the work item's `System.State`, not a board column. A board column is shown for a state; a column with no state of its own (a split column's Doing/Done halves, or several columns mapped to one state) cannot be targeted and stays unmapped.

The rest of this section describes category moves, except where it says every move.

- **Workstream milestones are not story progress.** `workstream_started`, `workstream_pr_link`, `workstream_ready_to_merge` and `workstream_merged` each say that the story's workstream reached that point; `requirements_approved` says the story's requirements were approved. None says the story is finished: a story owns one workstream, but only the story's own transition finishes it. Map them conservatively, to `InProgress` or `Resolved`. `workstream_changes_requested` says a review of the workstream's pull request requested changes, sending the work back: its category is `InProgress` only, and any other, `Resolved` included, is refused.
- **The story's own terminal events** say what the story became, and each may make exactly one move: `story_implemented` and `story_closed_by_person` to `Completed` (`{category: Completed}`) and `story_abandoned` to `Removed` (`{category: Removed}`). Any other category for them is refused. A process with no Removed state leaves the item alone successfully for the default abandonment move; an explicitly configured abandonment move is refused and records why.
- **A terminal move leaves a shared item alone.** Before moving to Completed or Removed, the connector reads the event's `attachment_shared` fact: `"true"` (another story in this project, still in progress, is attached to the same item) leaves the item as it is; `"false"` goes ahead; absent or any other value is refused and recorded, because unknown is not "unshared". The fact is a snapshot taken at delivery from this project's own records: a story in another project attached to the same item is not seen, and neither is one attached or moved after the read.
- **A move names a state category**, one of Microsoft's categories, never a state's display name. Default state names differ by process, anyone with process-edit permission can add more, and a state named "Resolved" belongs to the In Progress category for some CMMI types. The target state is the item's type's only state in that category; when the type has several, `states` lists the choices in order of preference, and the first the type has is used. Several states without a choice refuse even a default, naming `azure.lifecycle.<event>.states` as the remedy. A missing category leaves the item alone successfully only for a default; a configured move with no available target is refused and recorded on the story.
- **An item in `Completed` or `Removed` is never touched**, by any event or rule, explicit or by category, whatever its `from`: nothing here reopens or re-closes a work item, and nothing creates one.
- **Moves only go forward**, except `workstream_changes_requested`'s. Events are unordered and delivered once, so a category move leaves an item whose state is already in the target category, or a later one (`Proposed` < `InProgress` < `Resolved` < `Completed`), alone, and an explicit move leaves an item whose target is in an earlier category alone. Within one category, an explicit move also leaves alone a state the map sets for a later milestone, in this order: `requirements_approved` < `workstream_started` < `workstream_ready_to_merge` < `workstream_pr_link` < `workstream_merged` < `story_implemented` = `story_abandoned` = `story_closed_by_person`. This is Hashd's workflow order: ready to merge precedes PR create (WF.md, Phase 4). The map uses configured moves or their defaults, selecting from the item's already-read type states; an unavailable or refused selection sets no state. Each milestone's `from` restriction does not affect that type-level selection, and a state shared by milestones counts for the latest one in the forward-only check. A state no milestone sets is not a later milestone; before writing, the manual-move guard below checks it. The delivery's own `from` precondition must pass before the later-milestone check can leave the item alone successfully without a write or a refusal record. `workstream_changes_requested` is the one exception whose move may go back: `{category: InProgress}` moves a `Resolved` item (when mapped) to its `InProgress` state, and an item already in the chosen state is left alone without a write. `Removed` is off that path: an item not yet in `Completed` or `Removed` can be abandoned from any allowed source state. A current state whose category is not one of those is refused, never assumed.
- **Stateless manual-move guard (every move, explicit or by category).** Right before writing -- after every successful no-op and earlier refusal -- the connector checks that the item's current state is one Hashd could have put it in: a state in the item's type's `Proposed` category, or a state the map sets for this type for an earlier milestone (by the order above), or for any milestone in the case of `workstream_changes_requested`. An explicit `{to, from}` rule's `from` list overrides this check. Any other current state is treated as a person's move: the card is left alone with no write, and the delivery is refused with a diagnostic naming the work item, its current state, every allowed source state, and the next steps (moving the card back or adding the state to `from` alongside an explicit `to` list). Because nothing is stored between events, a person's move to a state the map sets for an earlier milestone cannot be detected and may still be moved.
- **Every move, explicit or by category, is tested against the revision it was decided on** (a JSON Patch `test` on `/rev`). If anyone changed the item since it was read, Azure refuses the update; the refusal is reported with that revision and the move is not retried against a fresh read.
- A subscribed `workstream_started` or `workstream_changes_requested` without a mapping, a mapping for an event this connector does not take, or a malformed mapping (including an empty, non-list or blank `to`, a non-list or blank `from`, `from` without `to`, or `to`/`from` mixed with `category`/`states`) is refused and recorded on the story before any Azure request; nothing is changed. Category entries retain the category and state validation above.

Lifecycle refusals use `HashdError(Diagnostic(...))` with source `azure.lifecycle`; existing provider diagnostics retain their source, permission metadata and recovery guidance. The host returns the structured diagnostic, and its title carries the reason and an actionable next step on one line for compact event records, including every available state choice or the complete failure evidence without truncation (line breaks are escaped). Expected configuration, attachment identity, transport and response-decoding failures are reported at the lifecycle call site. A rejected read means no move was attempted. A failed update is **unconfirmed**, reports the revision tested and is never retried: inspect the item's current state and revision in Azure before moving it manually. Credential selection, environment overrides and the transport's credential-echo protection still apply; refusals do not include a rejected HTTP response body.

A move reads the item and its type's states from the project the item reports for itself, then updates it (`_apis/wit/workitems/{id}`, api-version 7.1, `application/json-patch+json`), which needs Work Items (Read & write). It acts with the account Hashd supplied for the delivery, through the same credential loading as every other call here. The request shapes follow Microsoft's reference; they have not been run against a live organization from this repository.

`hashd doctor` reports the `azure` configuration as the connector loads it, then one authenticated read of the project's work-item types (`_apis/wit/workitemtypes`, api-version 7.1), which needs the same Work Items read scope as references and search, checks every configured `azure.fields` definition, and checks `azure.lifecycle` per-type mappings against the configured project (`azure.project`). Mapped type names are found in that same `workitemtypes` read, and `_apis/wit/workitemtypes/{type}/states` (api-version 7.1) is read once per distinct mapped type that exists. It reports missing types, missing states in `to`/`from`/`states`, `states` lists outside their category, and `to` states outside the event's allowed categories; `from` is checked for existence only, and shared event-level state names are not checked against a type. The request shape follows Microsoft's reference; it has not been run against a live organization from this repository.

Provider contracts: [Microsoft authentication guidance](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/authentication-guidance?view=azure-devops), [work-item read API](https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/work-items/get-work-item?view=azure-devops-rest-7.1), [work-item search API](https://learn.microsoft.com/en-us/rest/api/azure/devops/search/work-item-search-results/fetch-work-item-search-results?view=azure-devops-rest-7.1), [work-item comments API](https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/comments/add-work-item-comment?view=azure-devops-rest-7.1), [pull-request read API](https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-requests/get-pull-request?view=azure-devops-rest-7.1), [work-item update API](https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/work-items/update?view=azure-devops-rest-7.1), [work-item type states API](https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/work-item-type-states/list?view=azure-devops-rest-7.1), [workflow state categories](https://learn.microsoft.com/en-us/azure/devops/boards/work-items/workflow-and-state-categories?view=azure-devops).

### Narrow-grant live verification

Use the existing `tests/live/test_live_boards.py` suite and `operations.py`
registry. Supply a sandbox setup/cleanup credential through
`HASHD_LIVE_AZURE_TOKEN` or `HASHD_LIVE_AZURE_TOKEN_COMMAND`, and a separately
acquired Entra connector token restricted to the audited grants through
`HASHD_LIVE_AZURE_CONNECTOR_TOKEN` or `HASHD_LIVE_AZURE_CONNECTOR_TOKEN_COMMAND`.
The connector token is never used for harness project/process checks or cleanup;
recording scrubs and guards both credentials. Without a separate connector token,
the harness retains its historical single-token route, which is not evidence of
narrow-grant enforcement unless that token's actual grants are established.

Set `HASHD_LIVE_AZURE=1`, `HASHD_LIVE_AZURE_ORG`,
`HASHD_LIVE_AZURE_PROJECT` and `HASHD_LIVE_AZURE_PROJECT_2` as before. Also supply
`HASHD_LIVE_AZURE_SAVED_QUERY` (a flat query in the first sandbox project that
includes newly created run items) and `HASHD_LIVE_AZURE_PR_URL` (an actual Azure
Repos PR in one of those projects). The added operations execute the saved query
and batch read, create then find the same stamped story, and add/read back an
actual PR artifact relation and its comment. Created stories are tracked for
cleanup and sweep.

The area and iteration cases create run-named parent/child classification nodes
in the first sandbox project and work items inside and outside them. The setup
credential needs permission to create/delete those nodes and create/update work
items. Teardown removes the nodes after the items; `--sweep-tag` also removes
the run-named nodes after a crashed run. Listing checks complete expected ID
sets, including child versus exact-area matches and tag all/any matches with
spaces and quotes. The import case configures `azure.fields.target_repo` to
the sandbox item's `System.Description`, writes a known repository name there,
and checks that the projection preserves it. No custom process field is needed.

For the optional missing-permission case, set **`HASHD_LIVE_AZURE_NO_CODE_PAT`**
to a second PAT for the same sandbox organization, with **Work Items (Read &
write)** and **no Code scopes**. Use an identity that can otherwise read the
configured PR's repository, so the PAT scope is the deliberately missing grant;
keep the regular connector credential able to read that PR. Only
`note.azure_pr_no_code` uses this PAT, through the connector's PAT authentication
path. It must read the work item, fail the PR read with HTTP 401 or 403, name
that status and `Code (Read)` in the Diagnostic, and perform no write.
The PAT is excluded from object representations and scrubbed from recordings
and reports alongside the setup and regular connector credentials.

Without `HASHD_LIVE_AZURE_NO_CODE_PAT`, the rest of the suite runs normally.
Pytest skips this one case and `report.json` records
`WARNING: case could not run: set HASHD_LIVE_AZURE_NO_CODE_PAT ...` in its
operation result. That warning is not a passing permission check.

Run from this package:

```sh
hashd test -- uv run --project . --group dev pytest tests/live/test_live_boards.py
```

Commit the scrubbed recorded cassettes and `tests/live/report.json` together.
Record granted permissions and service results without tokens. The added
cassettes currently say `recorded: false`: they are offline contract fixtures,
not live evidence. They are replaced by recordings only after a successful
sandbox run; until then the new live cases remain unverified.
