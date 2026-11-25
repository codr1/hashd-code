# Figma Integration Design

## Overview

Import and reference Figma design artifacts in hashd planning, stories, implementation, and review. Designs become first-class context alongside REQS.md and SPEC.md.

## Setup

```
hashd connector figma configure --set file_id=<file key>   # Link a Figma file to the project
hashd connector figma configure --set profile=<name>       # Choose the API rate limit profile
hashd connector figma status                               # Show the settings
hashd connector login figma                                # Store your Figma account
hashd connector figma check                                # Check Figma access with your account
```

The file key is the segment after `/design/` or `/file/` in the Figma URL:
`https://figma.com/design/abc123/HBC-Designs` has the key `abc123`.

To bring a frame in, reference it as `@figma:<frame>` in a story or acceptance
criterion: planning and preview fetch a frame that is not cached yet. That fetch
fills only the request's own cache. Nothing fills or refreshes the shared
project cache (`.cache/figma`) yet, which implementation-stage `@figma:` reads,
the `figma_fetch` tool and cached listings use.

## Local Storage

```
projects/hbc/
  config.yaml            # includes figma.file_id, figma.last_sync
  design/
    manifest.json        # index of imported artifacts + versions
    tokens.md            # design tokens (colors, spacing, typography)
    components.md        # component library summary
    frames/
      job-list.md        # per-frame structured description
      job-detail.md
      job-filter.md
```

### Frame File Format

```markdown
# Job List (Mobile)
<!-- figma:node_id=1234:5678 last_sync=2026-03-02T14:30:00Z -->

## Layout
- Full-width mobile view (375pt)
- Top: search bar with filter icon (right)
- Body: vertical scroll list of job cards
- Bottom: tab bar (Browse, Applied, Profile)

## Job Card Component
- Left: company logo (48x48, rounded)
- Right of logo: job title (bold, 16pt), company name (14pt, gray)
- Below: location tag, salary range, "2d ago" timestamp
- Right edge: bookmark icon
- Bottom border: 1px divider

## Interactions
- Tap card -> job-detail
- Tap filter icon -> job-filter (slide up)
- Pull to refresh

## Design Tokens Used
- card-bg: #FFFFFF
- text-primary: #1A1A1A
- text-secondary: #6B7280
- spacing-card: 16pt
```

Structured descriptions agents can reason about -- not pixel coordinates or raw Figma JSON.

## The @figma: Reference Syntax

A consistent prefix that works everywhere text is interpreted.

### In REQS.md

```markdown
## Job Browsing
5. **Job list view** -- Display available jobs in a scrollable list
   with search and filtering. @figma:job-list @figma:job-filter
6. **Job detail** -- Full job posting with apply button. @figma:job-detail
```

### In Stories (source_refs + acceptance criteria)

```json
{
  "title": "Implement job list view",
  "source_refs": "REQS.md Section 5, @figma:job-list, @figma:job-filter",
  "acceptance_criteria": [
    "Job cards match layout in @figma:job-list",
    "Filter panel slides up per @figma:job-filter"
  ]
}
```

### In Pair Chat

```
you> @figma:job-list  how should I structure the card component?
ai>  Based on the job-list frame, the card has three zones...
```

### In directives.md

```markdown
## Design System
Follow the design tokens in @figma:tokens for all UI work.
Component names should match @figma:components where applicable.
```

### In hashd story add-commit

```
$ hashd story add-commit STORY-0042 "Add filter panel per @figma:job-filter"
```

## Prompt Injection Points

Every prompt that receives context sections gains an optional design_section:

| Prompt | Current Context | + Figma |
|--------|----------------|---------|
| plan_discovery.md | REQS, SPEC, stories, workstreams | `## Design Context` -- imported frame inventory, component list |
| refine_story.md | REQS section, SPEC | `## Referenced Designs` -- @figma: refs from the REQS chunk |
| breakdown.md | story plan, system description | `## Design Specs` -- frames referenced in story source_refs/ACs |
| implement.md | commit details, tech stack, directives | `## Design Reference` -- frames referenced in current micro-commit |
| review_contextual.md | story context, ACs, diff | `## Design Compliance` -- referenced frames for design checking |
| final_review.md | full diff, ACs, review notes | `## Design Specs` -- all frames referenced across the story |
| chat_general.md | story/workstream context | inline in the message -- @figma: refs unfold server-side in chat |

## Reference Resolution

`@figma:name` resolves the same way everywhere:
1. Look up name in `design/manifest.json`
2. Load the corresponding `.md` file
3. Inject contents into the prompt section

One resolver function used by gather_context(), build_full_implement_prompt(), chat artifact loader, etc.

## End-to-End Flow

```
1. Link the Figma file
   $ hashd --project hbc connector figma configure --set file_id=abc123

2. Reference in REQS.md
   ## Job Browsing
   5. **Job list** -- @figma:job-list @figma:job-filter

3. Plan discovers designs automatically
   $ hashd plan
   -> Discovery prompt includes design inventory
   -> Suggestions reference specific frames

4. Story gets design refs in source_refs + ACs
   $ hashd watch   # claim a suggestion from the plan screen
   -> source_refs: "REQS.md Section 5, @figma:job-list, @figma:job-filter"
   -> AC: "Job cards match layout in @figma:job-list"

5. Breakdown includes design context
   -> COMMIT-JOBLIST-001: "Build job card component per @figma:job-list"
   -> COMMIT-JOBLIST-002: "Add filter panel per @figma:job-filter"

6. Implementation agent sees the frame description
   -> implement.md includes ## Design Reference
   -> Agent knows: 48x48 rounded logo, 16pt bold title, etc.

7. Review checks design compliance
   -> Reviewer sees design spec alongside diff
   -> Can flag mismatches
```

## Phasing

### Phase 1 (first cut)
- Local storage in `design/` with structured markdown
- `@figma:` resolution in gather_context() and build_full_implement_prompt()
- Design section injection into planning + implementation prompts

### Phase 2 (later)
- Chat @figma: artifact loading
- Component-level import (not just frames)
- Design token extraction as CSS variables / language-specific constants
- Image export alongside structured descriptions
- Figma webhook for push-based updates
- A visual before/after diff of a changed frame

## Config Changes

```yaml
# projects/hbc/config.yaml additions
figma:
  file_id: "abc123def456"
  file_name: "HBC Designs"
  last_sync: "2026-03-02T14:30:00Z"
```

The token is never in config: store your account with `hashd connector login figma`.

## Key Implementation Files

```
orchestrator/
  integrations/figma_client.py    # Figma API client
  integrations/figma_import.py    # Node-to-markdown converter
  lib/figma_refs.py               # @figma: reference resolver
```
