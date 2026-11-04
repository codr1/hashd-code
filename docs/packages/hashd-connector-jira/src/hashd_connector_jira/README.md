# Jira Connector

Resolves Jira issue references into prompt/chat context. It supports Jira Cloud
and Jira Server/Data Center API reads. It does not create hashd stories or run
a background sync daemon.

Through the connector host's `sync_apply` write bridge it can add a note or a
pull-request link, as a comment, to an issue hashd already has attached; see
[Outbound notes](#outbound-notes). Opt-in, it moves an attached issue's status
when the project subscribes to an event and maps it in `jira.lifecycle`; see
[Lifecycle moves](#lifecycle-moves). Through `create_story` it finds or creates
the issue for a hashd story; see [Tracker stories](#tracker-stories). Those are
its only writes: it never closes an issue other than by a lifecycle move, and
never reopens one.

## Setup

### Jira Cloud

1. Go to https://id.atlassian.com/manage-profile/security/api-tokens
2. Create an API token
3. Configure hashd:

```bash
hashd project config set jira.url https://your-company.atlassian.net
hashd project config set jira.project_key PROJ
hashd project config set jira.email you@company.com
hashd project config set jira.api_token <your-api-token>
hashd jira setup
```

### Jira Server/Data Center

```bash
hashd project config set jira.url https://jira.company.local
hashd project config set jira.project_key PROJ
hashd project config set jira.pat <your-personal-access-token>
hashd jira setup
```

### Issue creation settings

Creating a Jira issue for a hashd story uses these settings:

| Setting | Meaning |
|---|---|
| `jira.project_key` | Project the issue is created in. Optional for references and searches, needed to create issues. |
| `jira.issue_type` | Issue type a hashd story is created as (for example `Story`), when no issue carries its label. Needed to create issues; there is no default. |
| `jira.link_back` | `true` or `false`: whether a created issue links to the story's page in hashd's Web UI. Unset is `true`. |

```bash
hashd project config set jira.issue_type Story
hashd project config set jira.link_back false
```

## Environment Variables

Secrets can be set via env vars instead of config:

| Variable | Overrides |
|---|---|
| `JIRA_URL` | `jira.url` |
| `JIRA_EMAIL` | `jira.email` |
| `JIRA_API_TOKEN` | `jira.api_token` |
| `JIRA_PAT` | `jira.pat` |
| `JIRA_PROJECT_KEY` | `jira.project_key` |

A nonempty variable wins over `config.yaml`, so the connector host can supply
credentials without writing them to disk. When one displaces a value that
`config.yaml` did set, that is logged by name at load, marked in
`hashd jira status`, and named in a 401/403 from Jira -- an ambient `JIRA_EMAIL`
shadowing the configured account reports as an override, not as a bad token.
Variable names only are ever logged; values never are.

## Usage

Reference Jira issues in story text, acceptance criteria, and chat:

| Ref | Resolves to |
|---|---|
| `@jira:PROJ-123` | Specific issue by full key |
| `@jira:123` | Specific issue using `jira.project_key` |
| `@jira:OTHER:456` | Specific issue from another project |
| `@jira` or `@jira:issues` | Cached Jira artifact manifest |

Specific issue refs fetch through Jira on interactive resolution and then read
from `.cache/jira_sync/` in cache-only contexts.

Newly fetched issue artifacts include readable nested description text followed
by the source JSON response in the same cached Markdown file. This retains
formatting metadata and unrendered nodes without another Jira request. It does
not download referenced attachments or additional comment pages, and the live
cache is not an immutable planning-attempt snapshot. Older cached artifacts
remain readable and gain the source section when fetched again.

## Tracker stories

`hashd story link <STORY>` with no ref finds the issue labelled
`hashd:<project>:<STORY>` in `jira.project_key` and links it. When no issue
carries the label it creates one as `jira.issue_type`, labelled with it, and
links that; the label is the duplicate guard, because Jira has no idempotent
create. The created issue is the fixed view: the story's title as its summary,
and a description of the problem, the acceptance criteria and a line naming the
hashd story -- ADF on Cloud, escaped wiki markup on Server/Data Center, so
every character reads as the text it is. `jira.link_back` controls whether
that line links to the story's page in hashd's Web UI.

Refused, with nothing created:

- two or more issues in the project carry the label: each is named, and the
  right one is linked by its key (`hashd story link <STORY> PROJ-123`);
- `jira.issue_type` is unset and no issue carries the label;
- the story has no title, or its text contains the configured Jira credential.

On Cloud the label lookup goes through `/rest/api/3/search/jql`, which
Atlassian documents as eventually consistent: an issue created seconds ago can
be missing from its results. Jira's `reconcileIssues` closes that only for
issue ids the caller already holds, and a rerun does not hold the id of the
issue an earlier, failed link created. So a rerun of `hashd story link` within
that window, after a create whose link failed, can create a second labelled
issue; the next link then refuses the pair, naming both.

The lookup and the create use the story owner's own Jira account, as every
team-mode write does. A rejection from Jira, such as a description over the
site's field limit, fails with Jira's own message; nothing is cut to fit or
retried. Outbound notes then reach the created issue like any other linked one.
The code is `stories.JiraStories`, declared as `CREATE_STORY`.

## Lifecycle moves

The connector's `EVENT_HANDLER` moves an attached issue to the status the
project names for an event. It is off unless the project subscribes the
connector to the event in `jira.events.subscribe` and maps a move for it in
`jira.lifecycle`: `to` is the status to move to, `from` every status the event
may move the issue out of.

```yaml
jira:
  events:
    subscribe: [workstream_started, workstream_pr_link, story_implemented, story_abandoned]
  lifecycle:
    workstream_started: {to: "In Progress", from: ["To Do"]}
    workstream_pr_link: {to: "In Review", from: ["To Do", "In Progress"]}
    story_implemented: {to: "Done", from: ["In Progress", "In Review"]}
    story_abandoned: {to: "Done", from: ["To Do", "In Progress", "In Review"]}
```

- **Names, not categories.** Jira's three status categories cannot choose a
  target ("In Progress" and "In Review" share one), so the operator names each
  status. Names compare ignoring case. The move is the first transition, in
  Jira's order, whose destination status is named `to`; a transition's own
  name is never matched.
- **Explicit `from`.** An issue moves only out of a status its `from` lists,
  and not when it is already at `to`; otherwise it is left as is, so a late,
  repeated or out-of-order event changes nothing. "Never backwards" is a
  property of the mapping, not of a ranking.
- **Done statuses are untouched.** An issue in Jira's done category is left
  alone whatever the event: nothing reopens an issue or moves it between two
  done statuses.
- **Only terminal events reach done.** `story_implemented` and
  `story_abandoned` must map to a status in the done category, and every other
  event to one outside it; a workstream milestone never finishes an issue.
- **`attachment_shared`.** A terminal event moves the issue only when the event
  says no other unfinished story is attached to it (`"false"`). `"true"` leaves
  it as is; a missing or other value is refused with nothing changed.
- **Reported, not retried.** A subscribed event with no mapping, a `to` the
  issue's workflow cannot reach from where it is (the error lists every
  transition it offers), and a transition Jira refuses (a condition, a
  validator, a required screen field, with Jira's own message) are reported on
  the story. A transport failure says whether the move can have reached Jira.
  Nothing is retried or reconciled.
- **Read and transition are two requests.** The issue's status and the
  transitions it offers are read together, then the transition is sent, so a
  change made in between, by a person or by another event, is not seen.

## Cloud vs Server/DC Differences

| Aspect | Cloud | Server/DC |
|---|---|---|
| API version | v3 | v2 |
| Auth | email + API token (Basic) | PAT (Bearer) |
| Rich text | ADF | Wiki/plain text |
| Search endpoint | `POST /rest/api/3/search/jql` | `POST /rest/api/2/search` |

## Troubleshooting

**"Jira API 401: ..."** -- Auth failed. Check email, API token, or PAT.

**"Jira API 404: get project ..."** -- Project key doesn't exist or user lacks
access.

**ADF rendering issues** -- Cloud v3 uses ADF for descriptions. hashd reads by
extracting plain text; complex formatting may be simplified.

## Status resolution and field mapping

`status.py` translates hashd's six outbound states into this site's workflow.
A Jira workflow is not a fixed set of statuses -- admins create and rename them
per project -- so the target is resolved at push time against `statusCategory`
(Jira's three-key abstraction over every custom workflow) and the `/transitions`
endpoint. Category is the floor: three hashd states share `indeterminate`, so a
destination whose NAME looks like the state is preferred among the transitions
already leading into the required category. Names refine, never decide, so a
site that renamed or translated its statuses lands somewhere correct but
imprecise rather than somewhere wrong.

Two no-match outcomes, deliberately different. Already in the required category
with nothing more precise on offer: no transition, no error -- that is the
ceiling of what the site's workflow can express and it is reached on every
tick. Required category unreachable: raise, because hashd asked for a state
this ticket cannot hold and leaving it where it is on every tick is a mirror
that has silently stopped mirroring.

`mapping.py` holds the field shapes the adapter uses today: `extract_checklist`
on the read path and `jira_issue_type` on the create path.

### Parked: description composition on `create_issue`

Tracker stories compose a description from a story and stamp the issue with a
label ([Tracker stories](#tracker-stories), `stories.py`). The same
composition on this backend's `SyncBackend.create_issue` path is designed but
deliberately **not shipped** -- body, acceptance criteria as a `- [ ] `
checklist under an `Acceptance criteria:` heading, and a `hashd story: <id>`
provenance line -- because nothing can call it there: `create_issue` takes
only `(title, body, issue_type)`, no `checklist`, no `story_id`.

Three things it has to get right when it is built, each learned the hard way:

- **Criteria go out and never come back.** They are positional strings with no
  identity in hashd, so nothing on a Jira issue could be matched back to
  criterion #2 after somebody inserted a new #1. Inbound criteria would need an
  identity migration first.
- **Markdown checkbox lines, not a Jira taskList node.** Cloud's document
  format has one and it renders better, but this connector's own reader
  (`_adf_to_text`) understands paragraphs and hard breaks, so a taskList comes
  back as an empty description and the checklist becomes invisible to the
  intake picker. A mirror hashd cannot read back is worse than one rendered as
  text. Server/DC takes the same lines verbatim.
- **The provenance line is load-bearing.** `search_issues` dedups with
  `description ~ "<story id>"`. An issue created through `story link` carries
  the story id in its link-back line, so that dedup can match it; one created
  through `create_issue` does not, and cannot be matched until the story id
  reaches its description. That gap closes with the same protocol change.

Prerequisite: `checklist` and `story_id` on the shared `SyncBackend.create_issue`
-- a cross-connector contract change owned outside this package.

### Closing an issue

`close_issue` reads `reason` the way the GitHub backend does: `not_planned`
targets hashd's `cancelled` state, so the ticket lands on an abandoning status
("Won't Do") rather than a completing one. It transitions first and comments
second, because only the transition is idempotent -- an unreachable state
raises, and commenting first would leave a closing comment on an issue that is
still open, once per retry.

### Verification

`tests/fake_jira.py` is a Jira at the HTTP boundary, not a monkeypatch of the
backend's own methods, which would test the test. `test_backend_http.py`
builds `JiraSyncBackend` from a project directory pointing at it and drives
the real `httpx` client onto a real port, so a wrong URL, method, JSON body
shape or missing auth header fails there the way it would against a real
site. `test_backend_writes.py` beside it uses an in-memory stub client to
cover resolution branches cheaply -- including the ones a fake site cannot
easily be put into.

No live Jira is contacted and no credentials are used.

The outbound notes below are also driven through the **connector host**'s
`sync_apply` against the same fake, so the connector's own `SYNC_BACKEND`,
`MODIFIES_EXTERNAL` and `REMOTE_SCOPE` declarations are what is exercised.

### Outbound notes

`SYNC_BACKEND` is `outbound.JiraOutboundNotes`, which owns exactly the two
writes the bridge documents: `comment` and `link_pr`, both posted as comments.
It is deliberately not `JiraSyncBackend`, so create, transition, close and
reopen are not reachable through the bridge.

- **Identity.** An attachment records the issue's numeric Jira `id`, and the
  bridge passes it as `external_id`. It is used as Jira's REST paths accept
  it; a key or project-local number is refused rather than resolved, because
  `JiraSyncBackend` would read `10042` as `PROJ-10042`, another issue.
- **Destination.** `REMOTE_SCOPE` is the configured site in exactly the form
  `reference_identity` records as `connection_id`, so the bridge refuses a
  write after `jira.url` (or `JIRA_URL`) is repointed.
- **Outcome.** A Jira rejection raises `JiraApiError` with Jira's own message.
  A transport failure raised before the request left says the note was not
  sent; any other may have reached Jira and says so, since a comment is not
  idempotent and a retry could duplicate it.

### Open integration questions

- **`update_status` argument vocabulary.** The shared protocol names it
  `label_or_transition`; GitHub reads it as a label, this adapter reads it as a
  hashd state. No caller exists yet to settle it, so both a hashd state and a
  bare Jira category key are accepted, and they resolve by DIFFERENT rules: a
  state gets name preference inside its category, while a bare category takes
  the first transition into it, which is what this adapter did before. A
  category carries no state, so there is no vocabulary to prefer a name for.
- **`reopen_issue`.** The protocol declares it and this adapter implements it,
  unchanged. Whether hashd should ever reopen a ticket a human closed is an
  integration policy question and is not settled here.
