# Figma Connector

Import and reference Figma design artifacts in hashd. Designs become first-class context that agents can read during planning, implementation, and review.

## Requirements

- Figma account with **Pro plan or higher** and a **Dev or Full seat** recommended
- Personal access token (Settings > Account > Personal access tokens)
- Starter plans, and View/Collab seats, work but are limited to 20 Tier 1 API calls/month -- see Profiles below

## Setup

```bash
# 1. Store your Figma account: a personal access token, never written to config
hashd connector login figma

# 2. Link a Figma file. The file key is the URL segment after /design/ or
#    /file/: https://figma.com/design/abc123/My-Designs -> abc123
hashd connector figma configure --set file_id=abc123

# 3. Check access with your own account
hashd connector figma check

# 4. Reference frames in stories, ACs, chat, anywhere
#    @figma:job-list -- planning and preview fetch a frame that is not cached yet
```

## Commands

| Command | What it does |
|---|---|
| `hashd connector figma configure --set file_id=<file key>` | Link a Figma file |
| `hashd connector figma configure --set profile=<name>` | Switch the API rate limit profile |
| `hashd connector figma status` | Show the settings and whether your account is stored |
| `hashd connector figma check` | Show the settings, then check Figma access with your account |

To bring a frame in, reference it as `@figma:<frame>` in a story or acceptance
criterion: planning and preview fetch a frame that is not cached yet. That fetch
fills only the request's own cache. Nothing fills or refreshes the shared
project cache (`.cache/figma`) yet, which implementation-stage `@figma:` reads,
the `figma_fetch` tool and cached listings use.

## How it works

### Referencing designs

Use `@figma:name` anywhere text goes to an agent:

```markdown
# In REQS.md
5. **Job list view** -- scrollable list with search. @figma:job-list

# In story acceptance criteria
- Job cards match layout in @figma:job-list
- Filter panel slides up per @figma:job-filter

# In hashd chat
you> @figma:job-list how should I structure the card component?

# In hashd story add-commit
$ hashd story add-commit STORY-0042 "Add filter panel per @figma:job-filter"
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

The shared project cache lives in the project directory:

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

Resolving `@figma:` references from the cache makes no API calls.

## Profiles

Figma's API rate limits vary dramatically by plan. Pick the profile that stays within your plan's budget.

### Rate limits by plan

Figma's published Tier 1 limits (read 2026-11-13):

| Plan | Tier 1 (files, nodes, images) | Notes |
|---|---|---|
| Starter, or any plan with a View/Collab seat | **up to 20 calls/month** | Barely usable for API integration |
| Pro (Dev/Full seat) | 10 calls/min | Comfortable for normal use |
| Organization (Dev/Full seat) | 15 calls/min | Aggressive staleness checks viable |
| Enterprise (Dev/Full seat) | 20 calls/min | |

`GET /files/:key/nodes` and `GET /images/:key` are both Tier 1. One frame fetch = 1-2 Tier 1 calls (node fetch + optional SVG export). The connector batches aggressively (all nodes in one call, all images in one call).

The stored-copy check (whether a story's stored copy of a frame is still
current) reads Tier 3 `GET /v1/files/:key/meta`, once per file, on every
profile, conservative included. It spends no Tier 1 budget and is not counted
in the monthly call tracking.

### Profile comparison

| Behavior | conservative | standard | aggressive |
|---|---|---|---|
| Target plan | Free/Starter | Pro Dev seat | Org Dev seat |
| SVG export on fetch | no (saves 1 API call) | yes | yes |
| Raw JSON cache | yes | yes | yes |
| Text summary | yes (from cached JSON) | yes | yes |
| Staleness check | never | never (nothing refreshes the shared cache yet) | on every resolve pre-implementation |
| API call tracking | warns at 13 of 20 monthly | warns at threshold | warns at threshold |

### Switching profiles

```bash
# Show the current settings, profile included
hashd connector figma status

# Switch to a different profile
hashd connector figma configure --set profile=standard
```

## Configuration

In `config.yaml`:

```yaml
figma:
  file_id: "abc123def456"       # Figma file key (extracted from URL)
  file_name: "HBC Designs"      # display name
  profile: standard              # conservative | standard | aggressive
  plan: pro                      # detected: starter | pro | org | enterprise
  seat: dev                      # detected: view | collab | dev | full
```

The token is never stored in config: every person signs in with their own
account -- `hashd connector login figma` (there is no site to give; every
Figma account is for `figma.com`). Reads, previews and checks use your
account. An agent's `figma_browse` and `figma_fetch` tools run on the server
with the account of whoever owns the work, in every mode. See
docs/CONNECTORS.md.

## Health checks

`hashd doctor` Figma section validates:

- Your Figma account's token is set and non-empty
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
- `GET /v1/files/:key/meta` (Tier 3) for the file's `last_touched_at`: recorded as a frame's version when it is fetched, and read again by the stored-copy check on every profile. It needs the token's `file_metadata:read` scope and spends no Tier 1 budget

The REST API returns raw style data (RGBA, font properties, auto-layout params), not CSS. The `.txt` summary extracts human-readable values. For exact CSS, agents read the `.json` source and construct styles from the raw properties.

Auth is via `X-Figma-Token` header with a personal access token. OAuth is not supported.

## Architecture

See Building Connectors for the connector contract and docs/CONNECTORS.md for the full system specification.
