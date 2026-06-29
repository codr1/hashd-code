# Navigating the TUI

`hashd watch` opens hashd's terminal UI. This page is the *navigation journey* — what
each view is for and when you'd move between them. For the exhaustive,
state-by-state keybinding tables, see **[WF.md > Watch UI
Keybindings](../WF.md)**. For the terms used here, see [glossary.md](glossary.md).

The TUI is built around three views connected in a hub-and-spoke shape:

```text
              Dashboard  (the hub)
             /          \
   Story Detail        Workstream Detail
   (shape the work)    (drive the work)
```

You always return to the Dashboard with `Esc`. The TUI is ZMQ-driven: every view
updates live as state changes, so you watch progress rather than re-querying.

## Dashboard — the navigation hub

The **Dashboard** is the home screen and the entry point to everything else. It
shows the project's active Workstreams and Stories at a glance, each rendered with
its `<stage> / <runtime_status>` so you can see what is running, blocked, or
waiting on you.

From the Dashboard you:

- press `1-9` to open a **Workstream Detail** for that workstream;
- press `a-i` to open a **Story Detail** for that story;
- press `p` to open the **Plan screen** (discover suggestions, create stories/bugs);
- press `m` to change the **autonomy mode**;
- press `/` for the **command palette**, `?` for context-aware help, `C` for chat;
- press `q` to quit.

Use the Dashboard to triage: scan for anything in `blocked` or `changes_required`,
then drill into it. It is also where you switch projects (`j`).

## Story Detail — shape the work

You open **Story Detail** (`a-i` from the Dashboard) when you are working *on the
definition of a change* rather than its implementation. This is where a Story is
groomed before it becomes a Workstream, and where you intervene in a story that is
still being planned.

Use it to:

- review the problem statement and acceptance criteria, then **approve** the story
  (`A`, `draft -> accepted`) so it can be run;
- **edit** the story with AI (`E`) or reshape individual acceptance criteria —
  edit (`e`), delete (`d`), descope (`D`), rescope (`r`);
- **answer** pending clarifications the planner raised (`a`);
- **launch** the work — `G` creates a Workstream and starts the run, which is the
  hand-off point from Story Detail into Workstream Detail;
- **close** the story (`X`) if you are abandoning it.

When to be here: planning and grooming. Once you press `G`, you are in
implementation territory and the action moves to Workstream Detail.

## Workstream Detail — drive the work

You open **Workstream Detail** (`1-9` from the Dashboard) to monitor and control a
single in-flight Workstream. This is the operator cockpit for implementation,
review, and merge. Its action keys are *state-aware* — the footer offers exactly
the verbs that are legal at the current stage (backed by the FSM's guard-aware
available actions), so you are never shown an impossible action.

Use it to:

- **run** the workstream (`G`) and watch the implement/test/review loop progress;
- inspect work in flight — diff (`d`), log (`l`), review (`v`), timeline, plan;
- handle the **human review gate** when a micro-commit completes — approve (`a`),
  reject with feedback (`r`), reset (`R`, keep the plan, redo from baseline), or
  replan (`N`, regenerate the plan from a clean base);
- handle the **merge gate** at `ready_to_merge` — merge directly (`m`) or create a
  PR for external review (`P`);
- handle **merge conflicts** — AI-resolve (`i`) or reset (`R`);
- handle **PR states** — reject pre-fills forge feedback (`r`), open the PR in a
  browser (`o`), merge the PR (`a`).

When to be here: anytime a Workstream is running, blocked at a gate, or ready to
merge. This is where the governed loop is observed and steered.

## Sub-views and overlays

Two surfaces are reached from within the views above rather than from the Dashboard:

- **Diff mode** (`d` inside Workstream Detail) — toggle side-by-side (`s`),
  fullscreen (`f`), and the **Lineage view** (`I`), which traces a selected line
  back through the provenance chain. See [provenance.md](provenance.md).
- **Plan screen** (`p` from the Dashboard) — discover suggestions from `REQS.md`
  (`d`), create a story from a suggestion (`1-9`), or create a new story (`s`) or
  bug (`b`).

Project artifact inspection/editing is CLI-first: use `hashd project reqs` /
`hashd project spec` to show the configured documents and their `edit` subcommands
for guarded manual changes.

## A typical journey

1. Open `hashd watch` — land on the **Dashboard**.
2. Press `p`, run discovery, claim a suggestion into a Story.
3. Press `a-i` to open **Story Detail**; review acceptance criteria; press `A` to
   accept, then `G` to launch the Workstream.
4. The view becomes **Workstream Detail**; watch implement -> test -> review run.
5. At the human gate, press `a` to approve (or `r` / `R` / `N`).
6. At `ready_to_merge`, press `m` to merge — or `P` for a PR.
7. `Esc` back to the **Dashboard** to pick up the next piece of work.
