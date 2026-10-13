# Azure Boards references

Read work items from **Azure DevOps Services** using `@azure:123` in reference-enabled planning inputs, or choose Azure Boards in the shared reference picker. On-premises Server/TFS, arbitrary API hosts and typed page URLs are not supported. There are no connector commands or synchronization jobs. The only remote writes are light outbound notes, described below.

Set the declared `azure` section using existing project configuration editors:

```yaml
azure:
  organization_url: https://dev.azure.com/your-organization
  project: Your Project
  access_token: externally-supplied-entra-access-token
```

Use **either** `access_token` (Bearer) **or** `pat` (Basic), never both. `AZURE_DEVOPS_ORGANIZATION_URL`, `AZURE_DEVOPS_PROJECT`, `AZURE_DEVOPS_ACCESS_TOKEN` and `AZURE_DEVOPS_PAT` override their nonempty configured counterparts. A variable that displaces a value the config did set is logged by name at load and named in a 401/403 read failure, so a shadowed organization or credential does not report as an expired token; values are never logged. Clear the other effective credential mode when switching. Credentials need work-item **read** access; where OAuth/PAT scopes apply, `vso.work` is sufficient for reading. Outbound notes additionally need **write** access (`vso.work_write`, Work Items Read & write); with a read-only credential reads keep working and each note is refused with a write-access message. Microsoft recommends Entra for new integrations; PAT remains a compatibility option. Hashd does not acquire or refresh tokens, parse their claims, or implement a managed OAuth/identity lifecycle. Expired or refused credentials produce a read failure without fallback to another credential.

Configured values remain readable through the existing authorized configuration APIs. The ordinary configuration editor does not prefill arbitrary stored values; this is **not** a masked credential-store guarantee. No changes to config access permissions are implied.

Search is scoped to the configured organization/project and requires explicit nonempty search text. Optional state, assignee and work-item-type filters use exact native Azure values. Native paging is explicit; indexing, trimming and inaccessible-result notices remain visible. Search results can lag the current work item: Preview and Submit resolve the selected resource again, and the normal planning capture pins the bytes actually used by that execution. Direct numeric references do not depend on the search index.

Explicit numeric references are **organization-scoped**: an authorized connector caller can request any work item readable by the configured credential in that organization, including another project. `azure.project` restricts search; it is not a project-isolation policy for direct reads. Azure credential permissions and Hashd's existing caller/project authorization remain the access boundaries. Returned organization/item/revision identity is verified before caching or capture; a different organization is refused.

The artifact is the complete returned current work-item JSON (`$expand=all`), including custom fields and relation metadata. It is readable in full preview and supplied to the planner, with its producer digest verified by the shared capture boundary. Related files, comment pages and prior revisions are **not** fetched; their links do not claim full target delivery. The verified organization URL, returned item ID and revision identify the resource. Organization renames are not transparent identity migrations.

Credentials go only to the configured organization's fixed `dev.azure.com` work-item (including, for `hashd doctor` and state moves, the work-item types) and `almsearch.dev.azure.com` search API paths. Redirects are not followed. Cached reads preserve producer-recorded evidence; failed refreshes do not silently use an old successful response. Browse/preview/cancel never creates a story or link; typed and picked sources share the existing nonexclusive attachment path.

Provider HTTP calls use the shared 130-second API failsafe for each network phase, not a total elapsed-time guarantee. Managed calls also inherit caller cancellation and the 130-second bound on the whole connector host process; the per-phase provider bound does not extend that enclosing bound, so a slow multi-phase call can end at the host bound first. Standalone provider calls retain the network-phase bound.

Outbound notes are one of the connector's two writes: a comment, or a comment carrying a pull-request link (`Linked PR: <url>`), on a work item already attached through this connector. A note changes no state, field or relation. A note is posted under the project the work item reports for itself, because attachment identity is organization-scoped as above; the organization is also the destination checked before every write, so repointing `azure.organization_url` refuses notes for items attached from the old one. Notes use the comments API's markdown format, and that API is still a preview version (`7.1-preview.4`) on Microsoft's reference, unlike the reads.

State moves are the other write, and are off unless a project configures them. The server delivers a Hashd connector event only for the types a project subscribes the connector to (`azure.events.subscribe`). For each subscribed type, `azure.lifecycle` says what to do to the attached work item:

```yaml
azure:
  events:
    subscribe: [workstream_pr_link, workstream_ready_to_merge]
  lifecycle:
    workstream_pr_link: {category: InProgress}
    workstream_ready_to_merge: {category: Resolved, states: [Code Review, Resolved]}
```

- **Workstream milestones are not story progress.** `workstream_pr_link`, `workstream_ready_to_merge` and `workstream_merged` each say that the story's workstream reached that point; `requirements_approved` says the story's requirements were approved. None says the story is finished: a story owns one workstream, but only the story's own transition finishes it. Map them conservatively, to `InProgress` or `Resolved`.
- **The story's own terminal events** say what the story became, and each may make exactly one move: `story_implemented` to `Completed` (`{category: Completed}`) and `story_abandoned` to `Removed` (`{category: Removed}`). Any other category for them is refused. Microsoft allows one Completed state per work item type; a process with no Removed state (Basic, and CMMI by default) refuses the abandonment and records why.
- **A terminal move leaves a shared item alone.** Before moving to Completed or Removed, the connector reads the event's `attachment_shared` fact: `"true"` (another story in this project, still in progress, is attached to the same item) leaves the item as it is; `"false"` goes ahead; absent or any other value is refused and recorded, because unknown is not "unshared". The fact is a snapshot taken at delivery from this project's own records: a story in another project attached to the same item is not seen, and neither is one attached or moved after the read.
- **A move names a state category**, one of Microsoft's categories, never a state's display name. Default state names differ by process, anyone with process-edit permission can add more, and a state named "Resolved" belongs to the In Progress category for some CMMI types. The target state is the item's type's only state in that category; when the type has several, `states` lists the choices in order of preference, and the first the type has is used. With none, or several and no choice, the event is refused and the refusal is recorded on the story.
- **An item in `Completed` or `Removed` is never touched**, by any event: nothing here reopens or re-closes a work item, and nothing creates one.
- **Moves only go forward.** Events are unordered and delivered once, so an item whose state is already in the target category, or a later one (`Proposed` < `InProgress` < `Resolved` < `Completed`), is left alone: a late event never moves an item back. `Removed` is off that path: an item not yet in `Completed` or `Removed` can be abandoned from any category. A current state whose category is not one of those is refused, never assumed.
- **Every move is tested against the revision it was decided on** (a JSON Patch `test` on `/rev`). If anyone changed the item since it was read, Azure refuses the update; the refusal is reported with that revision and the move is not retried against a fresh read.
- An event the project subscribes to without a mapping, a mapping for an event this connector does not take, or a malformed one is refused and recorded on the story; nothing is changed.

A move reads the item and its type's states from the project the item reports for itself, then updates it (`_apis/wit/workitems/{id}`, api-version 7.1, `application/json-patch+json`), which needs Work Items (Read & write). It acts with the account Hashd supplied for the delivery, through the same credential loading as every other call here. The request shapes follow Microsoft's reference; they have not been run against a live organization from this repository.

`hashd doctor` reports the `azure` configuration as the connector loads it, then one authenticated read of the project's work-item types (`_apis/wit/workitemtypes`, api-version 7.1), which needs the same Work Items read scope as references and search. The request shape follows Microsoft's reference; it has not been run against a live organization from this repository.

Provider contracts: [Microsoft authentication guidance](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/authentication-guidance?view=azure-devops), [work-item read API](https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/work-items/get-work-item?view=azure-devops-rest-7.1), [work-item search API](https://learn.microsoft.com/en-us/rest/api/azure/devops/search/work-item-search-results/fetch-work-item-search-results?view=azure-devops-rest-7.1), [work-item comments API](https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/comments/add-work-item-comment?view=azure-devops-rest-7.1), [work-item update API](https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/work-items/update?view=azure-devops-rest-7.1), [work-item type states API](https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/work-item-type-states/list?view=azure-devops-rest-7.1), [workflow state categories](https://learn.microsoft.com/en-us/azure/devops/boards/work-items/workflow-and-state-categories?view=azure-devops).
