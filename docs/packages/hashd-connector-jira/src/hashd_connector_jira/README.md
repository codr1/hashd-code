# Jira Connector

Resolves Jira issue references into prompt/chat context. It supports Jira Cloud
and Jira Server/Data Center API reads. It does not create hashd stories, create
Jira issues, or run a background sync daemon.

Through the connector host's `sync_apply` write bridge it can add a note or a
pull-request link, as a comment, to an issue hashd already has attached --
nothing else. See [Outbound notes](#outbound-notes).

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

### Parked: outward description composition

Composing a Jira description from a story -- body, acceptance criteria as a
`- [ ] ` checklist under an `Acceptance criteria:` heading, and a
`hashd story: <id>` provenance line -- is designed but deliberately **not
shipped**, because nothing can call it. `SyncBackend.create_issue` takes only
`(title, body, issue_type)`: no `checklist`, no `story_id`. A renderer with no
caller is dead code that reads as a feature, so the design is recorded here
instead of sitting unused in the package.

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
  `description ~ "<story id>"`, so until the story id reaches the description
  that dedup cannot match an issue hashd itself created. That gap exists today
  and closes with the same protocol change.

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
