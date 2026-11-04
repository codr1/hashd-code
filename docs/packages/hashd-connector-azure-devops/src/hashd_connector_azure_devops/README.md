# Azure Boards references

Read work items from **Azure DevOps Services** using `@azure:123` in reference-enabled planning inputs, or choose Azure Boards in the shared reference picker. On-premises Server/TFS, arbitrary API hosts and typed page URLs are not supported. There are no connector commands or synchronization jobs. Remote writes include outbound notes and lifecycle state moves, described below.

Hashd's **forge sign-in** requests this audited Entra delegated permission set:

```text
499b84ac-1321-427f-aa17-267ca6975798/vso.code_write
```

Code write covers forge PR comments and inherits Code read (`vso.code`).
Boards operations, including the connector's PR-relation lookup, use the
separately supplied connector credential with the permissions listed below. OIDC
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

Forge sign-in **does not acquire or refresh this Boards connector's separately
supplied credential**. Connector accounts and credential delivery remain
separate. The external token supplier must arrange its own grant, acquisition
and renewal; update the connector account or the configuration/environment
credential below when replacing its token. A forge login cannot renew it.
See the endpoint and permission audit.

### Boards operation permissions and credential replacement

| Boards operation | Required resource-prefixed permission | Retained grant satisfying it |
| --- | --- | --- |
| Item/reference reads; fields, types, states and team settings; saved-query definition/execution; WIQL, batch and search POSTs; story-stamp lookup | `499b84ac-1321-427f-aa17-267ca6975798/vso.work` | `499b84ac-1321-427f-aa17-267ca6975798/vso.work_write` inherits Work read |
| Work-item creation/updates, comments, PR relations and lifecycle state changes | `499b84ac-1321-427f-aa17-267ca6975798/vso.work_write` | Work write directly |
| Azure Repos PR lookup before adding an artifact relation | `499b84ac-1321-427f-aa17-267ca6975798/vso.code` | `499b84ac-1321-427f-aa17-267ca6975798/vso.code_write` inherits Code read |

An explicit Bearer `insufficient_scope` response names the failed operation's
permission, the retained write grant and its read inheritance. Have a tenant
administrator configure that grant in the supplying app's Azure DevOps delegated
permissions and grant administrator consent. Then obtain a replacement token from
the external supplier and store it for the selected connector destination:

```sh
hashd connector login azure --destination https://dev.azure.com/your-organization
```

Choose the Entra access-token credential and retry the failed operation manually.
This updates the connector account; `hashd forge login` uses a separate account
and cannot renew it. In a configuration/environment credential route, replace
that route's effective `azure.access_token` or `AZURE_DEVOPS_ACCESS_TOKEN` instead;
clear a displaced environment override when the configured value should win.
`hashd connector azure status` shows the destination, and
`hashd connector azure configure` corrects it. PATs retain their existing Basic
credential and Work Items/Code permission guidance. A plain 403 leaves
project/item authorization and token permissions uncertain; expiry and
connectivity failures keep their own diagnoses. Rejection bodies and challenges
may echo a credential and are not copied into diagnostics.

Set the declared `azure` section using existing project configuration editors:

```yaml
azure:
  organization_url: https://dev.azure.com/your-organization
  project: Your Project
  access_token: externally-supplied-entra-access-token
```

Use **either** `access_token` (Bearer) **or** `pat` (Basic), never both. `AZURE_DEVOPS_ORGANIZATION_URL`, `AZURE_DEVOPS_PROJECT`, `AZURE_DEVOPS_ACCESS_TOKEN` and `AZURE_DEVOPS_PAT` override their nonempty configured counterparts. A variable that displaces a value the config did set is logged by name at load and named in a 401/403 read failure, so a shadowed organization or credential does not report as an expired token; values are never logged. Clear the other effective credential mode when switching. Credentials need work-item **read** access; where OAuth/PAT scopes apply, `vso.work` is sufficient for reading. Outbound notes additionally need **write** access (`vso.work_write`, Work Items Read & write); with a read-only credential reads keep working and each note is refused with a write-access message. Linking an Azure Repos pull request also needs **Code (Read)** (`vso.code`), to read the pull request's repository and project ids; an explicit delegated-scope rejection names Code read and its inherited write grant, while other failures retain their own diagnosis. Microsoft recommends Entra for new integrations; PAT remains a compatibility option. Hashd does not acquire or refresh tokens, parse their claims, or implement a managed OAuth/identity lifecycle. Expired or refused credentials produce a read failure without fallback to another credential.

**Tracker stories (#2918).** `hashd story link STORY-x` with no id finds the work item tagged `hashd:<project>:<STORY-x>` in `project` (WIQL `[System.Tags] CONTAINS`), else creates one of type `work_item_type` (required for this, no default): `System.Title` is the story's title, `System.Description` (HTML, every value escaped) holds the problem, the acceptance criteria and a line naming the hashd story, a link to it unless `link_back: "false"` or hashd's `web.public_url` is localhost, and `System.Tags` is the stamp. Two or more tagged work items are refused, each named; link one by its id. Creating needs **write** access, as notes do.

Configured values remain readable through the existing authorized configuration APIs. The ordinary configuration editor does not prefill arbitrary stored values; this is **not** a masked credential-store guarantee. No changes to config access permissions are implied.

Search is scoped to the configured organization/project (or the projects `azure.intake.sources` names, below). Optional state, assignee and work-item-type filters use exact native Azure values. Native paging is explicit; indexing, trimming and inaccessible-result notices remain visible.

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

Each fetch reads every configured field's definition (`_apis/wit/fields/{name}`). Azure leaves an empty field out of a work item response, so a configured field the item lacks is read as empty only because the organization defines it; a name the organization does not define fails the read naming the setting, rather than reading as "no acceptance criteria". `hashd doctor` checks every configured field the same way. The definition also gives the field's declared type: only an HTML field is converted to Markdown, and any other text field, such as a plain-text one, is kept as written, angle brackets and entities included. A cache-only read re-projects the cached JSON without asking, with the types its fetch recorded, and writes the Markdown projection when it is missing; a cache written before the types were recorded serves its JSON alone until the next fetch. `target_repo`, when set, names a text field whose value is returned as the projection's `target_repo_hint`, trimmed and otherwise as the item holds it; the server takes it as the story's target only when it is exactly the name of a primary or active repo, and otherwise routes the story as usual with the name as a hint (docs/ARCHITECTURE.md).

Credentials go only to the configured organization's fixed `dev.azure.com` work-item (including, for `hashd doctor`, state moves and state-category listing, the work-item types, and for a `team` filter its team settings, and for projection and `hashd doctor`, the field definitions) and `almsearch.dev.azure.com` search API paths. Redirects are not followed. Cached reads preserve producer-recorded evidence; failed refreshes do not silently use an old successful response. Browse/preview/cancel never creates a story or link; typed and picked sources share the existing nonexclusive attachment path.

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

An explicit `azure.lifecycle.<event>` entry replaces that event's default. `workstream_started` still requires an explicit entry. For example:

```yaml
azure:
  events:
    subscribe: [workstream_pr_link, workstream_ready_to_merge]
  lifecycle:
    workstream_pr_link: {category: InProgress}
    workstream_ready_to_merge: {category: Resolved, states: [Code Review, Resolved]}
```

- **Workstream milestones are not story progress.** `workstream_started`, `workstream_pr_link`, `workstream_ready_to_merge` and `workstream_merged` each say that the story's workstream reached that point; `requirements_approved` says the story's requirements were approved. None says the story is finished: a story owns one workstream, but only the story's own transition finishes it. Map them conservatively, to `InProgress` or `Resolved`.
- **The story's own terminal events** say what the story became, and each may make exactly one move: `story_implemented` to `Completed` (`{category: Completed}`) and `story_abandoned` to `Removed` (`{category: Removed}`). Any other category for them is refused. A process with no Removed state leaves the item alone successfully for the default abandonment move; an explicitly configured abandonment move is refused and records why.
- **A terminal move leaves a shared item alone.** Before moving to Completed or Removed, the connector reads the event's `attachment_shared` fact: `"true"` (another story in this project, still in progress, is attached to the same item) leaves the item as it is; `"false"` goes ahead; absent or any other value is refused and recorded, because unknown is not "unshared". The fact is a snapshot taken at delivery from this project's own records: a story in another project attached to the same item is not seen, and neither is one attached or moved after the read.
- **A move names a state category**, one of Microsoft's categories, never a state's display name. Default state names differ by process, anyone with process-edit permission can add more, and a state named "Resolved" belongs to the In Progress category for some CMMI types. The target state is the item's type's only state in that category; when the type has several, `states` lists the choices in order of preference, and the first the type has is used. Several states without a choice refuse even a default, naming `azure.lifecycle.<event>.states` as the remedy. A missing category leaves the item alone successfully only for a default; a configured move with no available target is refused and recorded on the story.
- **An item in `Completed` or `Removed` is never touched**, by any event: nothing here reopens or re-closes a work item, and nothing creates one.
- **Moves only go forward.** Events are unordered and delivered once, so an item whose state is already in the target category, or a later one (`Proposed` < `InProgress` < `Resolved` < `Completed`), is left alone: a late event never moves an item back. `Removed` is off that path: an item not yet in `Completed` or `Removed` can be abandoned from any category. A current state whose category is not one of those is refused, never assumed.
- **Every move is tested against the revision it was decided on** (a JSON Patch `test` on `/rev`). If anyone changed the item since it was read, Azure refuses the update; the refusal is reported with that revision and the move is not retried against a fresh read.
- A subscribed `workstream_started` without a mapping, a mapping for an event this connector does not take, or a malformed mapping is refused and recorded on the story; nothing is changed. Explicit entries retain the category and state validation above.

Lifecycle refusals use `HashdError(Diagnostic(...))` with source `azure.lifecycle`; existing provider diagnostics retain their source, permission metadata and recovery guidance. The host returns the structured diagnostic, and its title carries the reason and an actionable next step on one line for compact event records, including every available state choice or the complete failure evidence without truncation (line breaks are escaped). Expected configuration, attachment identity, transport and response-decoding failures are reported at the lifecycle call site. A rejected read means no move was attempted. A failed update is **unconfirmed**, reports the revision tested and is never retried: inspect the item's current state and revision in Azure before moving it manually. Credential selection, environment overrides and the transport's credential-echo protection still apply; refusals do not include a rejected HTTP response body.

A move reads the item and its type's states from the project the item reports for itself, then updates it (`_apis/wit/workitems/{id}`, api-version 7.1, `application/json-patch+json`), which needs Work Items (Read & write). It acts with the account Hashd supplied for the delivery, through the same credential loading as every other call here. The request shapes follow Microsoft's reference; they have not been run against a live organization from this repository.

`hashd doctor` reports the `azure` configuration as the connector loads it, then one authenticated read of the project's work-item types (`_apis/wit/workitemtypes`, api-version 7.1), which needs the same Work Items read scope as references and search. The request shape follows Microsoft's reference; it has not been run against a live organization from this repository.

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
cleanup and sweep. Run from this package:

```sh
hashd test -- uv run --project . --group dev pytest tests/live/test_live_boards.py
```

Commit the scrubbed recorded cassettes and `tests/live/report.json` together.
Record granted permissions and service results without tokens. The added
cassettes currently say `recorded: false`: they are offline contract fixtures,
not live evidence. No restricted Entra token or sandbox was supplied for
COMMIT-ENTRA_MIN_SCOPES-005, so live permission enforcement remains unverified.
