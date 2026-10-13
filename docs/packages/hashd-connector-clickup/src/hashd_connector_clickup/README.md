# ClickUp task references

Read ClickUp tasks through the ClickUp API v2 using `@clickup:86a4xte6z` in reference-enabled planning inputs, or choose ClickUp in the shared reference picker to browse one configured List. References use **native task IDs** only; Custom Task IDs, task URLs and free-text search are not supported. There are no connector commands or synchronization jobs. There are two remote writes, both on a task already attached to a story and both refused unless `clickup.workspace_id` still names the Workspace the task was attached from: hashd's outbound story note (a comment, or a pull-request link carried as a comment), and an opt-in status move for subscribed events (below). A note whose request may have reached ClickUp before failing is reported as possibly posted, never as absent.

Set the declared `clickup` section using existing project configuration editors:

```yaml
clickup:
  workspace_id: "9012345"
  list_id: "901234567"
  api_token: pk_your_personal_token
```

Use **either** `api_token` (a personal token, which begins with `pk_` and is sent as `Authorization: pk_...`) **or** `access_token` (an externally supplied OAuth access token, sent as `Authorization: Bearer ...`), never both. `CLICKUP_WORKSPACE_ID`, `CLICKUP_LIST_ID`, `CLICKUP_API_TOKEN` and `CLICKUP_ACCESS_TOKEN` override their nonempty configured counterparts. Clear the other effective credential mode when switching. Hashd does not run the OAuth flow, acquire or refresh tokens, or inspect token contents; a refused credential produces a read failure without fallback to another credential.

Configured values remain readable through the existing authorized configuration APIs. The ordinary configuration editor does not prefill arbitrary stored values; this is **not** a masked credential-store guarantee. No changes to config access permissions are implied.

`workspace_id` is required for every read: the returned task's `team_id` must equal it, so a token that can see several Workspaces cannot supply a task from another one. Explicit task references are **Workspace-scoped**: an authorized connector caller can request any task in that Workspace readable by the configured token, including tasks in other Lists. ClickUp token permissions and Hashd's existing caller/project authorization remain the access boundaries.

`list_id` enables the picker. It browses that List with ClickUp's native Get Tasks paging (100 tasks per page, `last_page` required on every page; page numbers can shift if the List changes between pages) and refuses results whose home List or Workspace differ. Tasks whose home List is elsewhere, subtasks and closed tasks follow ClickUp's native defaults and are not listed; name an exact status to include tasks in that status, including closed ones. Optional filters use native values: exact status name, ClickUp numeric user ID for assignee, exact tag name, and an updated-since date (`YYYY-MM-DD`, UTC midnight inclusive). Each filter takes one value. Text in the picker is an exact native task ID lookup within the Workspace and cannot be combined with filters. Listed tasks can change before selection: Preview and Submit resolve the selected task again, and the normal planning capture pins the bytes actually used by that execution.

The artifact is the complete returned task JSON from Get Task with `include_markdown_description=true` and `include_subtasks=true`, including custom fields, checklists, dependencies, linked tasks and attachment metadata. It is readable in full preview and supplied to the planner, with its producer digest verified by the shared capture boundary. Comment pages, attachment files and attached Docs are **not** fetched; their links do not claim target delivery. The verified Workspace ID and task ID identify the resource and `date_updated` is recorded as its version. The task link is shown only when ClickUp returns an `https://app.clickup.com` URL.

Credentials go only to the fixed `https://api.clickup.com/api/v2` task, List and List-task paths, and, for `hashd doctor`, the authorized-Workspaces path (`GET /team`). Redirects are not followed. Rate-limit refusals (HTTP 429) are reported as such. Cached reads preserve producer-recorded evidence; failed refreshes do not silently use an old successful response. Browse/preview/cancel never creates a story or link; typed and picked sources share the existing nonexclusive attachment path.

Provider HTTP calls use the shared 130-second API failsafe for each network phase, not a total elapsed-time guarantee. Managed calls also inherit caller cancellation and the connector host deadline, currently 30 seconds; the provider setting does not extend that enclosing deadline. Standalone provider calls retain the network-phase bound.

`hashd doctor` reports the `clickup` configuration as the connector loads it, then whether the credential can see the configured Workspace (it must appear in `GET /team`). The request shape follows the published API reference; it has not been run against a live Workspace from this repository.

## Status moves on subscribed events (opt-in)

A project can have a Hashd event move an attached task to another status. It needs both the server-side subscription and a mapping for the task's List; with either missing, nothing moves.

```yaml
clickup:
  events:
    subscribe: [requirements_approved, workstream_pr_link]
  lifecycle:
    "901234567":                          # the ClickUp List id the task lives in
      requirements_approved:
        to: "in progress"
        from: ["to do"]
      workstream_pr_link:
        to: "in review"
        from: ["to do", "in progress"]
```

The events a move can follow are `requirements_approved`, `workstream_pr_link`, `workstream_ready_to_merge`, `workstream_merged`, and the story's own terminal events `story_implemented` and `story_abandoned`. Each is independently opt-in, and none has a default mapping. ClickUp statuses are free text defined per List, and a status's position in the List is only its display order, so nothing is derived from it: `to` is the status to move to, and `from` lists every status the event may move the task out of. Both must name exactly one status of that List. Names compare ignoring case, and a name that matches two statuses differing only by case is refused.

Just before writing, the handler reads the task and its List. It moves the task only if the task's current status is of type `open` or `custom` and is one of `from`. It then sets the status with `PUT /task/{id}`.

- **Only a story's terminal events close a task.** For `requirements_approved` and the workstream events, `to` must be of type `open` or `custom`; a `closed` or `done` target is refused. A task is shared by the story's workstreams, so a workstream milestone never means the story is finished. For `story_implemented` and `story_abandoned`, `to` must be of type `closed` or `done`. ClickUp documents `done` as a type distinct from `closed` without defining how they relate, so the operator names the exact status and nothing is ranked:

  ```yaml
  clickup:
    lifecycle:
      "901234567":
        story_implemented: {to: complete, from: [in progress, in review]}
        story_abandoned: {to: "won't do", from: [to do, in progress]}
  ```

- **A shared task is not closed.** Hashd gives each terminal event an `attachment_shared` fact, computed as it delivers the event: `"true"` when another unfinished story in the same project is attached to the same task. `"true"` leaves the task as is and reports success; `"false"` allows the move. A terminal move that would otherwise happen is refused when the fact is missing or has any other value, because a task another story still needs cannot be reopened by this handler. The fact is a snapshot of this project only: an attachment added afterwards, or another project's, is not seen.
- **Left as is, reported as success:** a List or event with no mapping, a task already at a `closed` or `done` status (even one listed in `from`, and even if the mapped names no longer match the List), a task whose current status is not in `from`, and a shared task on a terminal event. Nothing reopens a task or moves it from one terminal status to another.
- **Refused, with the reason:** malformed `lifecycle` config, a `to` or `from` name the List does not have or has twice, a `to` of the wrong kind for its event (above), and a status type other than `open`, `custom`, `closed` or `done` in `to`, in `from`, or on the task. These are unsupported rather than guessed: no type is inferred from a group's name.

Events arrive unordered, once, and are never retried. The check and the write are separate requests, and ClickUp has no conditional update, so a change made in between, by a person or another event, can be overwritten. Nothing reconciles afterwards. The move uses the credential Hashd supplied for the event, read through the same configuration loader as every other call; a write that may have reached ClickUp before failing, including a server or gateway error (HTTP 5xx), is reported as possibly applied.

Provider contracts: [authentication](https://developer.clickup.com/docs/authentication), [Get Task](https://developer.clickup.com/reference/gettask), [Get Tasks](https://developer.clickup.com/reference/gettasks), [Get List](https://developer.clickup.com/reference/getlist), [Update Task](https://developer.clickup.com/reference/updatetask), [FAQ: `order_index` is display order](https://developer.clickup.com/docs/faq), [rate limits](https://developer.clickup.com/docs/rate-limits), [API v2 OpenAPI specification](https://developer.clickup.com/openapi/clickup-api-v2-reference.json).
