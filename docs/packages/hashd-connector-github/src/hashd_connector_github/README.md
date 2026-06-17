# GitHub Connector

Resolves GitHub issue references into prompt/chat context. It does not create
hashd stories, create GitHub issues, or run a background sync daemon.

## Setup

```bash
wf project config set github.repo owner/repo
wf github setup
```

`wf github setup` validates GitHub access and creates the optional `hashd:*`
labels used by older projects. Issue resolution uses the GitHub CLI auth context.

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

`wf doctor` validates:

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

## Architecture

See [Building Connectors](../README.md) for the connector contract and
[docs/CONNECTORS.md](../../../docs/CONNECTORS.md) for the full system
specification.
