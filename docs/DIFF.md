# Diff Viewer with Lineage Integration

## Problem

The current diff panel in the TUI (`d` key) fetches unified diff text from the hashd-server REST API and can render it with `git-delta` when the client has delta installed. Without delta, it falls back to plain unified diff text.

The TUI must not run git or hashd subprocesses to access repository data or mutate workflow state. Local render subprocesses are different: delta is a terminal formatter over REST-fetched text, not a git operation. That client-side formatter carve-out is allowed; data/action subprocesses remain forbidden and must stay behind REST.

The goal is to evolve the diff experience across four incremental steps, from "prettier output" to "select a line and trace it back to the requirement that produced it." The realistic target is Step 2.5. Steps beyond that are documented for future direction.

---

## Optional Client Dependency: delta

Enhanced rendering is built on [delta](https://github.com/dandavison/delta) (git-delta), a Rust-based diff renderer that provides:

- **Syntax-aware highlighting**: Understands the language of the changed file (Python, Go, JS, etc.), not just the diff format.
- **Word-level diff**: Highlights exactly which characters changed within a modified line.
- **Function context in hunk headers**: Shows which function a change is inside.
- **Line numbers**: Configurable side-by-side or inline.
- **Width control**: `--width=N` for precise terminal/panel width formatting.
- **Side-by-side mode**: `--side-by-side` for two-column comparison when terminal width allows.

### Why not a Python library?

- **pygments**: Excellent syntax highlighting but no diff awareness. Cannot highlight a diff with the underlying language's syntax simultaneously.
- **difflib** (stdlib): Generates diffs but renders them as plain text. No syntax highlighting, no word-level change detection.
- **rich.syntax**: Beautiful syntax highlighting for single files via pygments, but has no diff mode.
- None of these can produce word-level change highlighting within a diff. Delta is the only tool that does this well in the terminal.

### Installation

Delta is an optional client-side dependency for the TUI diff panel.

| Platform | Install command |
|----------|----------------|
| Arch Linux | `pacman -S git-delta` |
| macOS | `brew install git-delta` |
| Ubuntu/Debian (24.04+) | `apt install git-delta` |
| Older Ubuntu/Debian | Download `.deb` from GitHub releases |
| Any (Rust) | `cargo install git-delta` |

If delta is not found on the client PATH, the diff panel still renders the REST-fetched unified diff. Delta only adds syntax highlighting, word-level markers, and side-by-side mode.

### Configuration

hashd controls delta's output via explicit flags, not the user's `~/.config/delta/` or `.gitconfig` settings. This ensures consistent rendering across machines. Key flags used:

| Flag | Purpose |
|------|---------|
| `--paging=never` | No pager -- output captured for the TUI panel |
| `--width=N` | Match the TUI panel width or terminal width |
| `--no-gitconfig` | Ignore user's delta theme to ensure consistent display |
| `--side-by-side` | When explicitly requested and width permits |

---

## Step 1: Delta Rendering

### Goal

Replace the manual Rich coloring in the diff panel with delta-rendered output. Same diff, much better presentation.

### What changes

**`detail_git.py`**: The current `get_diff_content()` function fetches raw unified diff text via REST. When delta is installed, it pipes that text through delta. When delta is missing or fails, it renders the unified diff directly. The function accepts a `width` parameter so delta can format to fit the panel.

**ANSI to Rich conversion**: Delta outputs ANSI escape sequences (24-bit color). Textual's `Static` widget renders Rich markup, not raw ANSI. The bridge is `rich.text.Text.from_ansi()`, which converts ANSI escape sequences into a Rich `Text` object that `Static` can render directly.

**`detail.py`**: The `_update_diff_panel()` method currently calls `get_diff_content()` and passes the result as a markup string. It needs to:
1. Determine the actual rendered width of the diff panel (`self.query_one("#panel-diff").size.width`).
2. Subtract a margin for the scrollbar and padding.
3. Pass that width to the delta rendering function.
4. Set the `Static` widget's content to the resulting `Text` object.

On terminal resize, Textual fires a `Resize` event. If the diff panel is active, re-render with the new width.

**`README.md`**: Document delta as an optional TUI diff enhancement.

### Acceptance criteria

- `d` key in TUI shows delta-rendered diff with syntax highlighting, word-level change markers, and line numbers.
- Diff wraps correctly within the panel with no horizontal overflow.
- Terminal resize re-renders at the correct width.
- Missing delta binary falls back to unified diff rendering with an optional install hint, not a crash.

### Risks

- `Text.from_ansi()` handling of delta's 24-bit ANSI output needs testing. Rich supports it, but edge cases are possible with delta's box-drawing characters and line-number decorations.
- Delta's `--width` controls line wrapping. Need to determine the right margin to subtract for Textual's scrollbar and padding (likely 2-4 characters).

---

## Step 2: File Tree Navigation

### Goal

When viewing a diff, show a navigable file list with per-file +/- line counts. Selecting a file scrolls the diff to that file's section. The left column becomes context-aware, showing different content depending on the active panel.

### Left column context switching

The left column currently always shows the status box (top) and microcommit list (bottom). With this change, the bottom half becomes context-aware:

| Active panel | Left column bottom half shows |
|---|---|
| review | Microcommit list (current behavior) |
| log | Microcommit list (current behavior) |
| timeline | Microcommit list (current behavior) |
| diff | File tree with +/- stats |

When the user presses `d` to enter the diff panel, the left column replaces the microcommit list with the file tree. When the user switches to any other panel (`v`, `l`, `L`, `t`), the microcommit list returns.

### File tree widget

A list of files changed in the diff, each showing the filename and insertion/deletion counts. Data comes from the server's diff REST endpoint, backed by numstat data, and returns entries like `42  8  handlers/job.go` (additions, deletions, filename).

Display format per item:

```
handlers/job.go                  +42 -8
internal/db/queries.go           +12 -3
cmd/server/main.go                +5 -0
```

Green for the `+N`, red for the `-N`. Files are listed in the order they appear in the REST diff.

The list is flat, not a directory tree. Workstream diffs typically touch 5-20 files. A directory tree adds complexity without significant benefit at this scale. If diffs routinely grow larger, revisit this.

### Scroll anchoring

When the user selects a file in the file tree and presses Enter (or clicks), the diff panel scrolls to that file's section. This requires knowing where each file's diff starts within the rendered output.

Approach: Parse the raw REST-fetched unified diff text before piping through delta to identify file boundary positions (lines starting with `diff --git`). Map those to line offsets in the rendered output. When a file is selected, scroll the `VerticalScroll` container to the corresponding offset.

### Per-commit diff (smart `d` behavior)

The `d` key gains context awareness based on the currently highlighted microcommit:

| Context | `d` shows |
|---|---|
| No commit highlighted, or "all" | Full workstream diff (base_sha..HEAD) |
| Specific commit highlighted | That microcommit's diff only |

When viewing a per-commit diff, the file tree shows only the files in that commit. A header at the top of the diff panel shows which commit is being viewed (e.g., `COMMIT-JOB_DRAFT_SAVE-003`) or `All changes (base..HEAD)` for the full view.

To get a per-commit diff: each microcommit corresponds to one git commit. The commit SHA is known from the commits table. The TUI asks the server for that commit's diff.

### TUI diff scopes

| Usage | Behavior |
|-------|----------|
| `d` on a highlighted microcommit | Diff for one microcommit only |
| Highlight a file in the diff file list | Single file from the workstream or commit diff |
| `s` | Side-by-side mode (delta `--side-by-side`, when installed) |

### TUI keybinding additions (diff panel active)

| Key | Action | Notes |
|---|---|---|
| `s` | Toggle side-by-side / unified | Only shown when diff panel is active and git-delta is installed. |

### Acceptance criteria

- Left column switches to file tree when diff panel is active, switches back when leaving.
- File tree shows all changed files with green +N and red -N counts.
- Selecting a file scrolls the diff to that file's section.
- Highlighting a microcommit then pressing `d` shows that commit's diff.
- Pressing `d` with no commit highlighted shows the full workstream diff.
- A header in the diff panel indicates what is being viewed.
- `s` toggles side-by-side mode when git-delta is installed.

### Design decisions

- **Flat file list vs directory tree**: Flat. Revisit if workstream diffs regularly exceed 30 files.
- **Side-by-side minimum width**: 80 characters. Below that, unified mode is forced with a notification.
- **File tree replaces vs overlays microcommit list**: Replaces. The two lists serve different purposes and showing both would crowd the already-limited left column.

---

## Step 2.5: Line Selection and Lineage Lookup

### Goal

Select a line or range of lines in a file and query hashd's lineage data to answer: who wrote this, which story produced it, what prompt generated it, what review approved it, and what human decisions shaped it.

This is where hashd's unique value becomes visible. Anyone can render a diff. Tracing a line of code back through the full chain -- requirement to story to prompt to agent to review to approval -- is what no other tool does.

### Prerequisite: Lineage query API (DONE)

LINEAGE.md Phase 3 landed in PR #85. The full CLI and data layer already exist:

- **`hashd lineage <file> [--line N] [--lines N-M]`** -- file blame -> commit -> story chain
- **`hashd lineage <sha>`** -- commit -> story/reviews/human decisions
- **`hashd lineage STORY-XXXX`** -- story -> all commits/reviews/decisions
- Output formats: `--format table` (default), `json`, `markdown`

Key functions already implemented:
- `git_blame()` in `orchestrator/git/branch.py` -- porcelain output for machine parsing
- `get_commit_row()` in `orchestrator/lib/db.py` -- single commit lookup by SHA
- `list_commits_by_story()` / `list_commits_by_workstream()` in `db.py` -- batch queries
- `_parse_blame_shas()` in `orchestrator/commands/lineage.py` -- extracts unique SHAs from blame output
- `_lineage_file()` / `_lineage_commit()` / `_lineage_story()` -- the three query pipelines

The query pipeline (already working):

```
Selected lines in a file
  -> git blame -L start,end -- file  (porcelain format)
    -> SHA per line (deduplicated, order preserved)
      -> commits table lookup: SHA -> story_id, microcommit_id, run_id
        -> stories table: story title, source_refs (requirement text), origin
        -> reviews table: decision, confidence
        -> events table: human decisions
```

If a SHA is not found in the commits table (pre-hashd code, manual edits, or external contributions), the lineage display shows "untracked" for those lines. This is expected and not an error.

**What Step 2.5 adds**: The TUI integration. The CLI pipeline exists; this step wraps it in a lineage view widget with navigation, line selection, and a lineage detail modal.

### TUI: Lineage view

When the diff panel is active and a file is selected in the file tree, a new keybinding becomes available:

| Key | Action |
|---|---|
| `I` | Show lineage view for the selected file |

The lineage view replaces the diff content in the right panel with enriched per-line commit attribution:

- Full file content with line numbers and syntax highlighting.
- Each line annotated with its commit SHA and microcommit ID.
- Lines are grouped by commit -- consecutive lines from the same commit share a single annotation block rather than repeating the SHA on every line.
- Color coding: different commits get different muted background colors for visual grouping.

Navigation in the lineage view:

| Key | Action |
|---|---|
| Arrow up/down | Move through lines |
| Enter | Show lineage detail for the current line's commit |
| Escape | Return to diff view |

### Lineage detail display

When the user presses Enter on a line in the lineage view, a modal shows the full lineage chain for that line's commit:

```
Line 42 of handlers/job.go

Commit:       a1b2c3d -- Add job draft save handler
Story:        STORY-0023 -- Job Draft Save
Microcommit:  COMMIT-JOB_DRAFT_SAVE-003 -- Implement save endpoint
Prompt:       implement
Review:       Approved (confidence: 0.92)
Run:          run_20260311_143022
Requirement:  "Users should be able to save job drafts and resume editing later"
```

If the commit has been through multiple review cycles (rejected, then approved), the modal shows the final review decision and notes the retry count.

The modal has a keybinding to open the full story transcript (`o`), which switches to the transcript panel filtered to that run.

### CLI: `hashd lineage` (already implemented)

Landed in PR #85. The TUI lineage view reuses the same query functions from `orchestrator/commands/lineage.py` -- specifically `_parse_blame_shas()`, `get_commit_row()`, and the story/review enrichment logic. No new CLI commands needed for this step.

The TUI lineage view may need a richer return type than the CLI formatters produce. If so, extract the enrichment logic from `_lineage_file()` into a shared function that both the CLI formatter and the TUI widget can call, returning structured data rather than printing directly.

### TUI keybinding summary (when lineage view is active)

| Key | Action |
|---|---|
| `I` | Toggle lineage view on/off for the selected file |
| Up/Down | Navigate lines in lineage view |
| Enter | Show lineage detail modal for current line's commit |
| Escape | Return to diff view |

### Acceptance criteria

- Pressing `I` on a file in the file tree shows an enriched lineage view with commit annotations.
- Navigating to a line and pressing Enter shows the full lineage chain in a modal.
- The modal displays story, microcommit, review decision, prompt template, and requirement text.
- Lines not in the commits table show "untracked" gracefully.
- CLI `hashd lineage` already works (PR #85). TUI lineage view reuses the same query layer.

### Design decisions

- **Lineage view vs line selection in diff**: Lineage view. A dedicated lineage view is simpler than adding line selection to the diff panel. The diff shows what changed; lineage shows why a line exists. These are different questions with different optimal displays.
- **Lineage keybinding**: `I` for lineage. Lowercase `l` and uppercase `L` are already used by Log and Transcript.
- **Modal vs panel for lineage detail**: Modal. The lineage detail for a single line/commit is a focused lookup, not something you browse continuously. A modal overlay keeps the lineage view visible underneath for context.

---

## Step 3: Commit Browser (future)

### Goal

Browse all files in the repository, select a file, see a list of commits that touched it, select a commit, see its diff. Also the reverse: browse commits, select one, see files, select a file, see the diff.

This is the "full code archaeology" experience. Not scoped for current implementation but documented for direction.

### Navigation model

Two entry points, both reaching the same destination:

**File-first**: Browse file tree -> select file -> see commit list for that file -> select commit -> see diff for that file in that commit.

**Commit-first**: Browse commit list (all workstream commits) -> select commit -> see file list -> select file -> see diff.

Both paths end at the same view: a single file's diff in a single commit, with lineage information available via `b`.

### How it differs from Step 2

Step 2 shows files changed in the current workstream diff (base..HEAD) or in a single microcommit. Step 3 shows the full git history for any file or commit, regardless of which workstream produced it. This requires navigating across workstreams and stories, not just within the current one.

### Prerequisites

- Steps 1, 2, and 2.5 complete.
- LINEAGE.md Phase 3 queries working across workstreams.
- Performance consideration: `git log --follow` for file history can be slow on large repos. May need caching or background loading.

---

## Implementation Order

| Step | Depends on | Scope | New CLI commands | New TUI keys |
|------|-----------|-------|-----------------|-------------|
| 1 | delta installed | Small | None | None (existing `d` key, better output) |
| 2 | Step 1 | Medium | None | `s` (side-by-side toggle) |
| 2.5 | Step 2 | Medium | None (CLI `hashd lineage` already exists, PR #85) | `I` (lineage) |
| 3 | Step 2.5 | Large | Extensions to `hashd diff` and `hashd lineage` | TBD |

---

## Files Touched (estimated)

| File | Steps | Nature of change |
|------|-------|-----------------|
| `packages/hashd-tui/src/hashd_tui/watch/detail_git.py` | 1, 2 | Replace diff rendering with delta, add file stat parsing |
| `packages/hashd-tui/src/hashd_tui/watch/detail.py` | 1, 2, 2.5 | Panel width passing, left column context switching, lineage view, keybindings |
| `packages/hashd-tui/src/hashd_tui/watch/detail_display.py` | 2, 2.5 | File tree widget, lineage view widget |
| `packages/hashd-tui/src/hashd_tui/watch/base.py` | 2 | Possible new cached list widget for file tree |
| `orchestrator/commands/lineage.py` | 2.5 | Refactor enrichment logic into shared function for TUI reuse (already exists from PR #85) |
| `packages/hashd-tui/src/hashd_tui/watch/detail_lineage.py` (new) | 2.5 | TUI lineage view widget and lineage detail modal |
| `README.md` | 1 | Document delta as optional |
| `WF.md` | 1, 2, 2.5 | Document new keybindings |

---

## Relationship to LINEAGE.md

This document covers the **user-facing diff and lineage experience**. LINEAGE.md covers the **data model, query API, attestation export, and compliance story**.

LINEAGE.md Phase 3 (query commands) landed in PR #85. The `hashd lineage` CLI command, `git_blame()` function, `get_commit_row()`, `list_commits_by_story()`, and `list_commits_by_workstream()` are all implemented and tested. The diff viewer's lineage view (Step 2.5) is the first TUI consumer of this query layer.

The key integration point is the enrichment logic in `orchestrator/commands/lineage.py`. Currently it formats directly to stdout (table/json/markdown). For the TUI lineage view, we need the same enrichment as structured data. Step 2.5 will refactor the shared parts into reusable functions that both the CLI formatters and the TUI widget can call.

---

## Open Questions

1. **Delta theme**: The TUI currently passes `--dark` for stable output. If delta's default colors clash, upgrade to a custom theme (`--plus-style`, `--minus-style`, `--syntax-theme`) -- but note delta outputs ANSI, not CSS variables, so it's always an approximation.

2. ~~**Large diffs**~~: Resolved -- truncation limit set to 10,000 lines. Paginate if this becomes a real problem.

3. ~~**Side-by-side width threshold**~~: Resolved -- 80 characters effective panel width. Auto-disables on resize below threshold.

4. ~~**Lineage view performance**~~: Not a concern. Benchmarked at ~120ms for a 4k-line file with real history. 10k-line files would be ~300ms, well within the 5s git timeout.

5. ~~**Cross-worktree lineage**~~: Resolved -- lineage lines show workstream ID per SHA group. Lineage modal shows full workstream/story/review chain.
