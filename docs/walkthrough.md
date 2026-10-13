# Walkthrough: one feature, start to finish

This is a single narrative that takes one feature from a requirement all the way
to a merged, audited commit. It introduces each concept the first time it appears.
If you want the *why* behind the steps, read [how-hashd-works.md](how-hashd-works.md)
first; for installation and setup, see [../QUICKSTART.md](../QUICKSTART.md); for
command examples, see [Command Reference](#command-reference); for authoritative
states and guards, see [WF.md](../WF.md).

We'll add a "log out" button to an example web app. Assume hashd is installed and
the project is registered (`hashd project add /path/to/repo`).

## 1. Point at a spec

hashd is **spec-driven**: the intended starting point is a requirements document,
normally `REQS.md` in your repo, that describes *what* you want in plain language.
You don't have to use it — you can create work directly (step 2b) — but starting
from a spec is what makes the rest of the chain traceable back to an intent.

If the project is already registered, edit the configured requirements artifact
through hashd-server:

```bash
hashd project reqs set --file updated-reqs.md
```

Before registration, create or edit `REQS.md` directly in the repo. Add a line:

```markdown
## Authentication
- Logged-in users need a visible way to log out from any page.
```

You can inspect the current configured requirements with:

```bash
hashd project reqs show
```

## 2a. Generate a Story (the spec-driven path)

Run discovery. hashd reads `REQS.md` and proposes **Suggestions** — candidate
pieces of work safe to start against the current `main`:

```bash
hashd plan          # discovery; proposes suggestions
hashd plan list     # view them, numbered
```

Claim the one you want. Claiming turns a Suggestion into a **Story** — a feature
(or bug) with a problem statement and **acceptance criteria** (the testable
conditions for "done"):

```bash
hashd plan claim 1  # or claim it from the TUI plan screen
```

## 2b. Or create a Story directly (skip discovery)

If you don't want to go through `REQS.md`, create the Story straight away:

```bash
hashd plan story "add a log out button"
# for a bug:  hashd plan bug "logout link 404s on mobile"
```

Either path lands you at the same place: a drafted Story.

## 3. Review and accept the Story

A Story is the **source of truth** for what the change should do, so it's worth a
look before you commit agents to it:

```bash
hashd show STORY-0001     # read the problem statement and acceptance criteria
```

If the acceptance criteria need work, reshape them — edit, delete, descope, or
rescope individual criteria (`hashd story edit-ac` / `delete-ac` / `descope-ac` /
`rescope-ac`), or hand the whole story to the AI editor
(`hashd story edit STORY-0001 -f "also handle the mobile nav"`). When it reads
right, accept it:

```bash
hashd approve STORY-0001  # draft -> accepted
```

Accepting unlocks the Story to be run.

## 4. Run the governed loop

Running an accepted Story creates a **Workstream** — one git branch in one
isolated worktree — and starts the implement/test/review loop:

```bash
hashd run STORY-0001 --loop   # --loop runs until it blocks or completes
```

hashd first breaks the Story into a **plan**: an ordered list of **micro-commits**,
the smallest planned units of work (e.g. "add the logout endpoint", "add the
button component", "wire the click handler"). Each micro-commit runs the same
governed loop, and each arrow is a **gate**:

```text
implement  ->  test  ->  review  ->  human gate  ->  commit
(agent       (tests    (AI         (approve /      (record the
 writes       must      reviewer    reject /        commit + its
 code)        pass)     approves)   reset)          lineage)
```

- The **test gate**: configured tests must pass, or the loop goes back to implement.
- The **review gate**: an AI reviewer reads the diff and either approves or requests
  changes (back to implement). The cycle is bounded — capped retries before it
  escalates to you.
- The **human review gate**: when a micro-commit is clean, whether it stops for you
  depends on the project's **autonomy mode**. In `gatekeeper` (the default), a
  confident clean commit auto-continues and you approve only at merge; in
  `supervised`, you approve every commit. Failures always stop for a human.

Watch it run:

```bash
hashd watch STORY-0001    # live TUI, or:
hashd show <workstream>   # status snapshot
```

## 5. Hit an approval gate

When the loop pauses for you, the Workstream's `runtime_status` reads `blocked` (or
`changes_required`) and its stage is `awaiting_human_review`. Look at the diff and
decide:

```bash
hashd diff <workstream>                      # see the change
hashd approve <workstream>                   # looks good, continue
hashd reject <workstream> -f "rename the handler to logout()"   # iterate with feedback
hashd reset  <workstream>                    # keep the plan, redo from a clean baseline
hashd replan <workstream> -f "split the endpoint out"  # the plan itself is wrong; regenerate it
```

(`reset` keeps the plan and redoes the implementation from baseline; `replan`
regenerates the plan from a clean base. They differ only in keep-vs-regenerate
the plan — see **[WF.md > Plan regeneration](../WF.md)**.)

If an agent needs information to proceed it raises a **clarification** and the
Workstream blocks. Answer it and the run continues:

```bash
hashd answer list
hashd answer <workstream> "use the existing session-cookie clear path"
```

## 6. Final review and merge

When every micro-commit is done, two branch-level gates run before anything lands:

- **Final review** — a holistic review of the *whole branch diff*. It either marks
  the branch `ready_to_merge`, flags `final_review_with_concerns` (mergeable, but
  worth a human read), or — if you reject — generates a FIX micro-commit you then
  `hashd run` to address.
- **Merge gate** — runs the merge-gate test command, checks for conflicts against
  fresh `main`, and runs a `gitleaks` secrets scan. A secret finding blocks the merge.

Then merge:

```bash
hashd merge <workstream> --wait        # direct merge to main (default)
# or, for external review on a forge:
hashd pr create <workstream>          # open the PR for external review
hashd merge <workstream> --pr --wait  # merge that PR after review
```

In PR mode you can pull review comments (`hashd pr feedback`) and reject to generate
a FIX commit on the same PR. Code merge precedes documentation finalization:
hashd updates `SPEC.md`, burns the implemented `REQS.md` WIP sections, preserves
deferred requirements and archives the Workstream.
Inspect the final project documents with `hashd project spec show` and
`hashd project reqs show`; use the matching `set` commands or the TUI document
editor for manual corrections.

## 7. View the audit trail

The change is now in `main` — and every step that produced it was recorded. This
is the payoff of the governed path: a full, queryable **lineage** chain.

```bash
hashd lineage <workstream-or-sha-or-STORY-0001>
```

Trace a specific file or line back to the Story and decisions that produced it:

```bash
hashd lineage src/auth/logout.go --lines 12-30
```

Export a machine-readable attestation for compliance, or verify the tamper-evident
hash chain:

```bash
hashd lineage export <sha> --format slsa     # SLSA v1.0 provenance
hashd lineage export <sha> --format in-toto  # in-toto statement, hashd predicate
hashd lineage verify                         # validate the commit hash chain
```

For the full provenance story — what's captured, the standards it maps to, and why
it's the differentiator — see [provenance.md](provenance.md) and
**[docs/LINEAGE.md](LINEAGE.md)**.

## Recap

```text
REQS.md  ->  Suggestion  ->  Story (+ ACs)  ->  Workstream  ->  micro-commits
   ->  implement/test/review/approve loop  ->  final review  ->  merge gate
   ->  merged commit  ->  hashd lineage (full audit trail)
```

Every arrow is a validated transition that was logged. That is the whole point:
not just code generated from a spec, but a governed path to a merged, attested
commit.

## Command Reference

### Core Commands

| Command | Description |
|---------|-------------|
| `hashd plan` | Discover from REQS.md, save suggestions |
| `hashd plan list` | View current suggestions |
| `hashd plan story "title" [-f ctx]` | Quick feature (skips REQS discovery) |
| `hashd plan bug "title" [-f ctx]` | Quick bug fix (conditional SPEC update) |
| `hashd story edit STORY-xxx [-f "feedback"]` | Edit existing story |
| `hashd story clone STORY-xxx` | Clone a locked story |
| `hashd story retry STORY-xxx` | Retry failed planning run |
| `hashd plan reset` | Reclaim claimed suggestions whose story is gone (dead flow / out-of-band delete) so discovery is unblocked, and release pending stories stranded behind dependencies that are all implemented |
| `hashd story descope-ac STORY-xxx N` | Move acceptance criterion N to descoped list |
| `hashd story rescope-ac STORY-xxx N` | Move descoped criterion N back to acceptance criteria |
| `hashd story split STORY-xxx [--feedback ".."]` | Request an agent breakdown proposal for a large story |
| `hashd story split STORY-xxx 3,5,7 -t "title" [-y]` | Split criteria into one new draft sibling story |
| `hashd run [id] [--once\|--loop] [--gatekeeper\|--supervised\|--autonomous] [-f ".."] [-y]` | Dispatch the workstream run workflow (-f: guidance, -y: skip prompts) |
| `hashd list [--mine]` | List stories and workstreams (`--mine`: only your own in team mode; solo mode lists everything) |
| `hashd show <id>` | Show story or workstream details |
| `hashd approve <id>` | Accept story or approve gate |
| `hashd reject [id] [-f "feedback"] [--reset] [--include-forge \| --findings-file FILE]` | Reject a gate and fold review findings into the next FIX commit. `-f` is optional additive operator guidance and takes precedence over folded findings. Use `@directive <text>` in feedback to add durable constraints (e.g. `hashd reject ws-1 -f "fix X @directive do not modify RBAC"`) |
| `hashd assign <id> [user]` | Assign a story/workstream to a user by handle (default: yourself); ownership is open -- anyone can (re)assign |
| `hashd unassign <id>` | Clear the owner of a story/workstream |
| `hashd admin user rename <email> <name>` | Rename a user's unique display-name handle (team-server; the solo owner defaults from `git config user.name`) |
| `hashd pr create [id]` | Create PR/MR for specified workstream |
| `hashd pr feedback [id]` | View PR/MR review comments |
| `hashd review findings ID [--include-forge]` | Export editable findings without dispatching; accepts a workstream or linked story ID |
| `hashd merge [id] [--confirm\|-y] [--pr] [--no-push] [--fix] [--ai-resolve]` | Merge to main and archive (`--confirm`/`-y` required in supervised/gatekeeper mode, `--pr` forces PR workflow) |
| `hashd close [id] [--force] [--keep-branch] [--no-changes] [-r ".."]` | Abandon workstream (-r reason required with --no-changes) |
| `hashd skip [id] [commit] [-m ".."]` | Mark commit as done without changes |
| `hashd reset [id]` | Keep the plan, reset the worktree to baseline, redo the implementation |
| `hashd replan [id] [-f ".."]` | Regenerate the plan from a clean base (resets the worktree to baseline, clears the plan; `-f`: why the plan is wrong) |

Workstream run, approve and reject requests must use the server's configured
operations root. These actions refuse a different `ops_dir` before changing
work or sending a workflow decision: Temporal activities use the worker's root,
and project/workstream workflow IDs do not distinguish roots. Equivalent paths
(including symlinks) are accepted. Connect to the server serving the intended
root to operate on its workstreams.

### Supporting Commands

| Command | Description |
|---------|-------------|
| `hashd use [id] [--clear]` | Set/show/clear current workstream |
| `hashd watch [id]` | Interactive TUI - monitor execution progress |
| `hashd review [id]` | Show the current review (pending micro-commit/FIX, or the current final verdict) |
| `hashd diff [id] [--scope story\|current] [--commit SHA\|micro-commit id] [--staged] [--uncommitted] [--stat] [--file path]` | Show workstream diff; the whole story when no range is named |
| `hashd log [id] [--since ISO] [-n limit] [-r]` | Show workstream timeline |
| `hashd docs [id]` | Update SPEC.md from workstream |
| `hashd refresh [id]` | Refresh touched files |
| `hashd conflicts [id]` | Check file conflicts |
| `hashd test [--] <command...>` | Run a test command in the current worktree and record its verdict |

### Archive Commands

| Command | Description |
|---------|-------------|
| `hashd archive work` | List archived workstreams |
| `hashd archive stories` | List archived stories |
| `hashd archive delete <id> --confirm` | Permanently delete the workstream and its records; a merged workstream whose story is implemented, or that has no story, keeps its lineage |
| `hashd open <id> [--force]` | Resurrect archived workstream |

### Directives Commands

| Command | Description |
|---------|-------------|
| `hashd directives` | View global directives |
| `hashd directives all` | View all (global + project + workstream) |
| `hashd directives project` | View project only |
| `hashd directives workstream <ws>` | View workstream's only |
| `hashd directives edit` | Edit global in $EDITOR |
| `hashd directives edit project` | Edit project in $EDITOR |
| `hashd directives edit workstream <ws>` | Edit workstream's in $EDITOR |
| `hashd directives ai-edit` | AI-assisted edit of global |
| `hashd directives ai-edit project` | AI-assisted edit of project |
| `hashd directives ai-edit workstream <ws>` | AI-assisted edit of workstream's |

### Project Commands

| Command | Description |
|---------|-------------|
| `hashd project add <path> [--no-interview] [--primary name] [--active name ...\|--all-active] [--repo-skip-test name] [--repo-skip-build name] [--commit-root-dirs]` | Register a new project |
| `hashd project list` | List registered projects |
| `hashd project use [name] [--clear]` | Set, show, or clear the current project |
| `hashd project show [name]` | Show project configuration (defaults to the current project) |
| `hashd project interview` | Update project configuration interactively |
| `hashd project remove <name> [-y]` | Remove a project |
| `hashd project config list` | List effective project config and mark overrides in TTY output |
| `hashd project config diff` | Show project overrides against inherited system/default config |
| `hashd project config show <key>` | Show effective value, source, override stack, and description |
| `hashd project config get <key>` | Get config value |
| `hashd project config set <key> <value>` | Set config value |
| `hashd project config reset <key>` | Remove one project override |
| `hashd project config reset --all` | Remove all project overrides |
| `hashd project describe` | Show current project description |
| `hashd project describe --suggest` | AI-generate a description suggestion |
| `hashd project reqs [show]` | Show configured REQS artifact content through hashd-server |
| `hashd project reqs set [--file F]` | Overwrite REQS from a file or stdin, atomically under the edit lock; active-story WIP sections are protected |
| `hashd project reqs {lock,refresh,unlock}` | Hold / renew / release the REQS edit lock across a multi-step script (identity-keyed, 10-min lease) |
| `hashd project spec [show]` | Show configured SPEC artifact content through hashd-server |
| `hashd project spec set [--file F]` | Overwrite SPEC from a file or stdin, atomically under the edit lock |
| `hashd project spec {lock,refresh,unlock}` | Hold / renew / release the SPEC edit lock across a multi-step script |

### System Config Commands

| Command | Description |
|---------|-------------|
| `hashd config list` | List effective system config and mark system overrides in TTY output |
| `hashd config diff` | Show system overrides against compiled defaults |
| `hashd config show <key>` | Show effective value, source, override stack, and description |
| `hashd config get <key>` | Get system config value |
| `hashd config set <key> <value>` | Set system config value |
| `hashd config reset <key>` | Remove one system override |
| `hashd config reset --all` | Remove all system overrides |

### Auth Commands

| Command | Description |
|---------|-------------|
| `hashd auth create --description <name>` | Create a bearer token for off-loopback clients; plaintext is shown once |
| `hashd auth list` | List token metadata without exposing secrets |
| `hashd auth delete <id>` | Revoke one bearer token |

### Workstream Commands

| Command | Description |
|---------|-------------|
| `hashd workstream remove <id>` | Remove orphaned workstream |

Workstream removal confirms its workflows have stopped before deleting records.
If shutdown cannot be confirmed, an agent is still flushing its final records,
or the project-wide docs workflow is running, removal fails and retains the
records for retry. It does not cancel another workstream’s docs update.
Deletion removes its reviews, guidance, events, transcripts, runs, usage,
commit records, clarifications, and workstream conversations in the same database
transaction as its row. Story records and other workstreams remain. Removing a
merged workstream whose story is implemented, or that has no story, keeps its
lineage (commits, intent captures and the records they name) and reserves its
workstream ID, so a later story that would take the ID gets the next numbered
variant (`<id>_1`, ...).
Closing or retrying a workstream retains its records; only deletion removes
them.

### Observability Commands

| Command | Description |
|---------|-------------|
| `hashd chat [id]` | Pair programmer chat with AI |
| `hashd agents` | Show installed AI agents and stage assignments |
| `hashd doctor` | Validate setup and diagnose issues |
| `hashd restart [component] [-y] [--auto-rebuild]` | Restart infrastructure (server, Temporal sidecar, event forwarder, messengers); `--in-place-upgrade` takes no component, `--reclaim-port` takes none or `server` |
| `hashd lineage <target> [--line N] [--lines N-M] [--format table\|json\|markdown]` | Trace code lineage (auto-detects file/SHA/STORY/BUG) |
| `hashd lineage export <sha\|STORY-xxxx\|BUG-xxxx> [--format slsa\|in-toto]` | Export attestation (SLSA v1.0 or in-toto) for SHA or story |
| `hashd lineage verify` | Validate hash chain integrity for project commits |
| `hashd system-log` | View system event log |
| `hashd prompts list` | List prompt templates |
| `hashd prompts show <name>` | Show prompt content |
| `hashd prompts edit <name>` | Edit prompt override |
| `hashd prompts reset <name>` | Reset prompt to default |
| `hashd prompts diff <name>` | Show diff from default |
| `hashd completion [bash\|zsh\|fish]` | Generate shell completion |

---

### Manual Artifact Inspection and Edits

Operators can inspect the current configured documents without shelling into the
project repository:

```bash
hashd project reqs       # same as hashd project reqs show
hashd project spec       # same as hashd project spec show
```

Manual edits go through the same server-side ownership boundary. The CLI is batch
only -- there is no interactive `$EDITOR` session holding a lock open (that is the
TUI editor's job). Overwrite in one shot from a file or stdin:

```bash
hashd project reqs set --file new-reqs.md
hashd project spec set < new-spec.md
```

`set` fetches the current `head_sha`, then the server acquires the document's edit
lock, writes, commits, pushes, and releases -- atomically, mutually exclusive with
planning and other editors. To fence the document across several manual steps,
hold the lock explicitly (identity-keyed, 10-minute lease, renew before it lapses):

```bash
hashd project reqs lock       # hold it
hashd project reqs set --file draft.md
hashd project reqs refresh    # extend the lease if the work runs long
hashd project reqs unlock     # release
```

A `set` records the document `head_sha` it read for the CAS check. The server
rejects:

- stale edits where the artifact changed after the editor opened
- dirty repos, because manual artifact edits must commit exactly one document change
- checkouts on another branch or detached HEAD, because manual edits must land on the configured default branch that document readers use
- symlink artifact paths
- REQS edits that change bytes between `BEGIN WIP` and `END WIP` markers

Treat REQS WIP sections as owned by active stories. Edit outside them or wait for
the story to merge/close and clean up its markers.

## Adjust story scope

Descoping moves a criterion out of active acceptance criteria and excludes it
from implementation. Rescoping brings it back:

```bash
hashd story descope-ac STORY-0054 5
hashd story rescope-ac STORY-0054 1
hashd show STORY-0054
```

Ask the planner to propose a split, then answer its proposal before it applies:

```bash
hashd story split STORY-0054
hashd story split STORY-0054 --feedback "split out recurring events"
hashd answer STORY-0054 "yes"
# Or request a revision:
hashd answer STORY-0054 "yes, but keep account setup in the parent"
```

To extract selected criteria directly into a draft sibling:

```bash
hashd story split STORY-0054 3,5,7 -t "Referral Reward Configuration"
# Add -y to skip confirmation.
```

Pair programmer chat can propose these actions too; the operator confirms them.
For example, its action blocks can carry:

```text
~~~action
{"op": "descope_criterion", "index": 4}
~~~

~~~action
{"op": "split_story", "criteria": [3, 5, 7], "title": "Referral Reward Config"}
~~~
```

See the [scope lifecycle](../WF.md#story-scope-management) and
[TUI controls](watch.md#story-scope-operations).

## Work as an Arc

An Arc is one feature spread over several connected stories. The Arc itself
holds the feature's problem and criteria and is never implemented; its
children are ordinary stories that are planned, run and merged as usual,
each knowing its Arc and its siblings. Arcs are flat: a child is never an Arc.

1. **Request an Arc proposal.** For a draft or accepted story that is in no Arc and has never had a workstream: `hashd story arc STORY-0054`, `M` on the TUI story detail, or **plan as arc** in the Web story menu. The story stays as it is while the planner proposes its children; `hashd show STORY-0054` shows the operation's phase. When planning judges a story several stories' worth, the story shows 'Arc proposed' with the planner's reasoning; nothing starts until the proposal is requested, and autonomous mode requests it itself.
2. **Review the proposal.** At 'Arc draft' the proposal opens in the TUI and Web Arc proposal workspaces: approve it, discard it, or revise it with guidance; every version stays in the history with a comparison. A factual question from the planner is answered in the workspace and planning resumes; the answer approves nothing. Approval converts the story to an Arc and creates its children; autonomous mode approves a ready proposal itself. Editing the story's requirements while a proposal is ready makes that proposal stale: refresh it, or discard it and keep the edits. An Arc that already has children is not split again: add one with `hashd plan story "..." --arc STORY-0054`.
3. **Let the children run.** Accepted children are planned at once in
   gatekeeper and autonomous modes, and wait as drafts for you in supervised
   mode. A child that depends on an unfinished sibling waits in `pending` and is
   replanned when it lands. Set or change prerequisites with
   `hashd story depends-on` (or `k` in the TUI, the chips on the Web), or when
   creating a story (`hashd plan story|bug --depends-on ...`, or the create
   dialogs). The Arc's page lists its children with "n of m implemented"; a
   child shows "part of <arc> · n of m". A closed (abandoned) child leaves the
   Arc and is not counted.
4. **Complete the Arc.** When at least one child remains (not closed), every
   remaining child is implemented, and every prerequisite of the Arc itself is
   a known story that is done (implemented) or closed (abandoned), complete it:
   `hashd story complete-arc STORY-0054`, `K` in the TUI, or **complete arc**
   in the Web story menu. An id that names no story, a blank entry or an
   unreadable list is not done or closed and holds the Arc back. If every child
   was closed, close the Arc (`hashd close`) instead of completing it. An Arc is
   approved only under the same prerequisite rule, and it is never parked for
   planning.

Two Arc questions are still open with the operator (#2025): whether a story may
depend on an Arc (today the server allows it, and completing the Arc releases
such stories), and whether an accepted story gets a notice when a prerequisite
lands.

See [Arcs in the workflow](../WF.md#story-scope-management),
[dependency editing](../SPEC.md#story-dependency-editing) and
[TUI controls](watch.md).
