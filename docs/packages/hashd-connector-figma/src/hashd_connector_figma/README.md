# Figma Connector

Import and reference Figma design artifacts in hashd. Designs become first-class context that agents can read during planning, implementation, and review.

## Requirements

- Figma account with **Pro plan or higher** and a **Dev or Full seat** recommended
- Personal access token (Settings > Account > Personal access tokens)
- Free/Starter plans work but are limited to 6 API calls/month -- see Profiles below

## Setup

```bash
# 1. Set your Figma token (never stored in config, only the env var name)
export FIGMA_TOKEN="figd_your_token_here"

# 2. Connect a Figma file
wf figma connect https://figma.com/file/abc123/My-Designs

# 3. Browse what's available
wf figma list
wf figma list --page "Job Browsing"

# 4. Import frames you need
wf figma import job-list job-detail job-filter

# 5. Reference in stories, ACs, chat, anywhere
#    @figma:job-list resolves to cached file references
```

## Commands

| Command | What it does |
|---|---|
| `wf figma` | Show status or setup instructions |
| `wf figma connect <url>` | Link Figma file, validate token, detect plan, recommend profile |
| `wf figma list [--page NAME]` | Browse pages and frames in the linked file |
| `wf figma import <name> [...]` | Fetch frames from Figma API, cache locally |
| `wf figma show <name>` | Display a cached artifact |
| `wf figma status` | Show cache status and staleness (API check depends on profile) |
| `wf figma sync` | Refresh all cached artifacts from Figma |
| `wf figma profile [name]` | Show or switch API rate limit profile |

## How it works

### Referencing designs

Use `@figma:name` anywhere text goes to an agent:

```markdown
# In REQS.md
5. **Job list view** -- scrollable list with search. @figma:job-list

# In story acceptance criteria
- Job cards match layout in @figma:job-list
- Filter panel slides up per @figma:job-filter

# In wf chat
you> @figma:job-list how should I structure the card component?

# In wf workstream add-commit
$ wf workstream add-commit my_ws "Add filter panel per @figma:job-filter"
```

### What the agent sees

`@figma:job-list` does NOT inline file contents into the prompt. It resolves to file references with metadata:

```
@figma:job-list resolved to:
  Figma source: .cache/figma/frames/job-list.json (48KB)
  SVG export:   .cache/figma/frames/job-list.svg (14KB)
  Summary:      .cache/figma/frames/job-list.txt (2KB)
  Dimensions:   375x812pt
  Last synced:  2026-03-21T08:30:00Z
```

The agent decides what to read based on its task:
- **Planning**: reads the `.txt` summary for orientation
- **Implementation**: reads `.svg` for layout + `.json` for exact styles/CSS values
- **Review**: reads `.svg` to check visual compliance

### Cache

Imported artifacts are cached locally in the project directory:

```
projects/hbc/.cache/figma/
    manifest.json                  # index of all cached artifacts
    frames/
        job-list.json              # raw Figma API response (node tree, exact styles)
        job-list.svg               # visual export (SVG from Figma image API)
        job-list.txt               # structural summary (text content, hierarchy)
```

Three files per frame:
- **`.json`** -- raw Figma API response. Source of truth. Contains exact CSS-extractable values, auto-layout constraints, component variants, colors as RGBA. Agents read this when they need precise styles.
- **`.svg`** -- visual export from Figma's image export endpoint. Lightweight, modern models handle SVG natively.
- **`.txt`** -- structural summary generated locally from the JSON. Text content, hierarchy, dimensions. Quick orientation without reading the full node tree.

The cache is fully local after import. No API calls to resolve `@figma:` references from cache.

## Profiles

Figma's API rate limits vary dramatically by plan. The connector detects your plan at setup and recommends a profile that stays within your budget.

### Rate limits by plan

| Plan | Tier 1 (files, images) | Notes |
|---|---|---|
| Free / Starter | **6 calls/month** | Barely usable for API integration |
| Pro (Dev/Full seat) | 15 calls/min | Comfortable for normal use |
| Org (Dev/Full seat) | 20 calls/min | Aggressive staleness checks viable |

`GET /files/:key/nodes` and `GET /images/:key` are both Tier 1. One frame import = 1-2 Tier 1 calls (node fetch + optional SVG export). The connector batches aggressively (all nodes in one call, all images in one call).

### Profile comparison

| Behavior | conservative | standard | aggressive |
|---|---|---|---|
| Target plan | Free/Starter | Pro Dev seat | Org Dev seat |
| SVG export on import | no (saves 1 API call) | yes | yes |
| Raw JSON cache | yes | yes | yes |
| Text summary | yes (from cached JSON) | yes | yes |
| Staleness check | never (manual sync only) | on `wf figma status/sync` | on every resolve pre-implementation |
| API call tracking | warns at 4 of 6 monthly | warns at threshold | warns at threshold |

### Switching profiles

```bash
# Show current profile and plan
wf figma profile

# Switch to a different profile
wf figma profile standard

# Re-detect plan (e.g., after upgrading)
wf figma connect https://figma.com/file/abc123/My-Designs
```

### Plan detection

`wf figma connect` detects your plan through:
1. The MCP server's `whoami` tool (if available) -- returns plan and seat type directly
2. API response headers on rate limit (429) -- returns `X-Figma-Plan-Tier` and `X-Figma-Rate-Limit-Type`
3. If neither is available, defaults to `conservative` and asks you to set the profile manually

## Configuration

In `config.yaml`:

```yaml
figma:
  file_id: "abc123def456"       # Figma file key (extracted from URL)
  file_name: "HBC Designs"      # display name (set at connect time)
  token_env: FIGMA_TOKEN         # env var holding the personal access token
  profile: standard              # conservative | standard | aggressive
  plan: pro                      # detected: starter | pro | org | enterprise
  seat: dev                      # detected: view | collab | dev | full
```

The token is never stored in config. Only the env var name. Set the actual token in your shell environment.

## Health checks

`wf doctor` Figma section validates:

- Token env var set and non-empty
- Figma API reachable with the token
- Configured file accessible
- Cache integrity (manifest matches files on disk)
- Plan/seat info (if detected)
- API call budget (tracked locally)

## Figma API notes

The connector uses the Figma REST API v1:
- `GET /v1/files/:key/nodes?ids=...` for node trees (batched, one call for multiple frames)
- `GET /v1/images/:key?ids=...&format=svg` for SVG exports (batched, one call for multiple frames)
- `GET /v1/files/:key` for file metadata (lastModified check on standard/aggressive profiles)

The REST API returns raw style data (RGBA, font properties, auto-layout params), not CSS. The `.txt` summary extracts human-readable values. For exact CSS, agents read the `.json` source and construct styles from the raw properties.

Auth is via `X-Figma-Token` header with a personal access token. OAuth is not supported (would be needed for MCP server integration in a future phase).

## Architecture

See [Building Connectors](../README.md) for the connector contract and [docs/CONNECTORS.md](../../../docs/CONNECTORS.md) for the full system specification.
