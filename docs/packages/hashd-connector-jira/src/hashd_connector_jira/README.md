# Jira Connector

Resolves Jira issue references into prompt/chat context. It supports Jira Cloud
and Jira Server/Data Center API reads. It does not create hashd stories, create
Jira issues, or run a background sync daemon.

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
