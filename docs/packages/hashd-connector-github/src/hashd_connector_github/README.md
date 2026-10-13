# GitHub Connector

Resolves GitHub issue references into prompt/chat context. It does not create
hashd stories, create GitHub issues, or run a background sync daemon.

## Setup

```bash
hashd project config set github.repo owner/repo
hashd github setup
```

`hashd github setup` validates GitHub access and creates the optional `hashd:*`
labels used by older projects. Issue resolution uses the GitHub CLI auth context,
except where Hashd hands the connector a person's own GitHub account (team mode,
and `hashd connector github check`): then every `gh` call uses exactly that
token and never the machine's login. A person signs in with
`hashd connector login github --destination github.com`, with an Issues token
or, by choice, their forge login.

## Usage

Reference GitHub issues in story text, acceptance criteria, and chat:

| Ref | Resolves to |
|---|---|
| `@github:42` | GitHub issue #42 details, fetched on demand and cached |
| `@github` or `@github:issues` | Cached GitHub artifact manifest |

Specific issue refs fetch through GitHub on interactive resolution and then read
from `.cache/github_sync/` in cache-only contexts.

## Configuration

In project `config.yaml`:

```yaml
github:
  repo: owner/repo
```

If `github.repo` is omitted, the connector attempts to infer the repository from
the GitHub CLI in the configured project repo.

## Health Checks

`hashd doctor` validates:

- `gh` CLI is installed and authenticated
- repository is accessible
- optional `hashd:*` labels exist

## Backend

The backend uses the GitHub CLI for issue reads and setup checks:

| Method | What |
|---|---|
| `fetch_issue(id)` | `gh issue view N --json ...` |
| `setup()` | `gh label create "hashd:*" ...` |
| `doctor()` | Check auth, repo access, labels |

## Outbound notes

The connector host writes hashd's outbound story notes through
`outbound.NoteBackend`: a comment, or a pull-request link carried as a comment,
on an issue already attached to a story. Nothing else is reachable from it --
no close, reopen or label change. A note is refused unless the repository this
connector resolves to (`REMOTE_SCOPE`, `https://<host>/<owner>/<repo>`) is still
the one the issue was attached from, and `gh --repo` is pinned to that same
host-qualified repository. A `gh` timeout is reported as possibly posted.

## Lifecycle labels (opt-in connector events)

A project can have a label added to an attached issue when a Hashd lifecycle
event happens. Both halves are the project's choice, and nothing happens
without both:

```yaml
github:
  events:
    subscribe: [workstream_ready_to_merge, workstream_merged]  # Hashd's switch
  lifecycle:
    labels:                                                    # this connector's mapping
      workstream_ready_to_merge: "hashd: ready"
      workstream_merged: "hashd: merged"
```

The events this connector takes are `requirements_approved`,
`workstream_ready_to_merge`, `workstream_pr_link` and `workstream_merged`, and
the story's own terminal events `story_implemented` and `story_abandoned`
(below).

**Labels are milestone markers, not a status field.** Each one says that this
event happened at least once for the story, for its workstream. They are only
ever added:
- Old markers stay. An issue can carry both "ready" and "merged" labels. A
  story owns one workstream, but a later attempt can replace it and events
  arrive in any order, so a "ready" after a "merged" is new work.
- No label is removed, replaced or ranked. The labels are not kept in step
  with any current state.

Other rules:
- **A closed issue is not edited.** The event succeeds without touching it.
  The check is a read before the write, so an issue closed in between can
  still get the label. Nothing ever reopens it.
- **A subscribed event with no label mapped is refused**, with the key to set.
  The refusal is recorded on the story. So is a `lifecycle` or `labels` value
  that is not a mapping.
- **Each mapping is exactly one label.** `gh --add-label` splits its value on
  commas and parses double quotes, so a label containing either is refused
  rather than turned into something else.
- **A label that does not exist in the repository is gh's refusal.** Nothing
  creates it, and `hashd github setup`'s labels are unchanged.
- **A `gh` timeout is reported as possibly applied.**

The label is added through the same host-pinned `gh --repo` and credential
path as the notes.

## Closing on the story's own terminal events (opt-in)

The workstream and approval events above never close an issue: an issue is
attached to a story, and a workstream merging is not the story being done. The
story's own terminal events can, when the project lists them:

```yaml
github:
  events:
    subscribe: [story_implemented, story_abandoned]
  lifecycle:
    close: [story_implemented, story_abandoned]
    labels:
      story_implemented: "hashd: done"   # optional, added before the close
```

- **The reasons are fixed:** `story_implemented` closes the issue as
  *completed*, `story_abandoned` as *not planned*. `close` is a list of those
  two names only; anything else (a bare string, a mapping, another event) is
  refused.
- **Order:** the issue is read first, and an issue observed closed is left
  alone. Then the label, if one is mapped for the event, then the close. A
  failure stops what comes after it, and a close that fails after the label
  was added says the label was added.
- **A shared issue is left alone.** Every write for a terminal event, label
  and close, first reads the event's `attachment_shared` fact. `"true"`
  (another story in this project, still in progress, is attached to the same
  issue) leaves the issue as it is. `"false"` goes ahead. Absent or any other
  value is refused and recorded, because unknown is not "unshared". The fact is
  a snapshot taken at delivery from this project's own records: a story in
  another project attached to the same issue is not seen, and neither is one
  attached or moved after the read.
- **Not atomic.** This connector reads the issue, then `gh` reads it again and
  closes it. An issue observed closed at either read is left alone (`gh`
  reports "already closed" and succeeds), but a close landing between `gh`'s
  read and its close can have its reason overwritten. Nothing ever reopens an
  issue.
- A terminal event with neither a label nor a close configured is refused. A
  `gh` timeout on the close is reported as possibly closed. Nothing is retried.

## Architecture

See Building Connectors for the connector contract and
docs/CONNECTORS.md for the full system
specification.
