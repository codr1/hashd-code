# Walkthrough: one feature, start to finish

This is a single narrative that takes one feature from a requirement all the way
to a merged, audited commit. It introduces each concept the first time it appears.
If you want the *why* behind the steps, read [how-hashd-works.md](how-hashd-works.md)
first; for installation and setup, see [../QUICKSTART.md](../QUICKSTART.md); for
every command's flags, see **[WF.md](../WF.md)**.

We'll add a "log out" button to an example web app. Assume hashd is installed and
the project is registered (`wf project add /path/to/repo`).

## 1. Point at a spec

hashd is **spec-driven**: the intended starting point is a requirements document,
normally `REQS.md` in your repo, that describes *what* you want in plain language.
You don't have to use it — you can create work directly (step 2b) — but starting
from a spec is what makes the rest of the chain traceable back to an intent.

Add a line to your `REQS.md`:

```markdown
## Authentication
- Logged-in users need a visible way to log out from any page.
```

## 2a. Generate a Story (the spec-driven path)

Run discovery. hashd reads `REQS.md` and proposes **Suggestions** — candidate
pieces of work safe to start against the current `main`:

```bash
wf plan          # discovery; proposes suggestions
wf plan list     # view them, numbered
```

Claim the one you want. Claiming turns a Suggestion into a **Story** — a feature
(or bug) with a problem statement and **acceptance criteria** (the testable
conditions for "done"):

```bash
wf plan claim 1  # or claim it from the TUI plan screen
```

## 2b. Or create a Story directly (skip discovery)

If you don't want to go through `REQS.md`, create the Story straight away:

```bash
wf plan story "add a log out button"
# for a bug:  wf plan bug "logout link 404s on mobile"
```

Either path lands you at the same place: a drafted Story.

## 3. Review and accept the Story

A Story is the **source of truth** for what the change should do, so it's worth a
look before you commit agents to it:

```bash
wf show STORY-0001     # read the problem statement and acceptance criteria
```

If the acceptance criteria need work, reshape them — edit, delete, descope, or
rescope individual criteria (`wf plan edit-ac` / `delete-ac` / `descope-ac` /
`rescope-ac`), or hand the whole story to the AI editor (`wf plan edit STORY-0001
-f "also handle the mobile nav"`). When it reads right, accept it:

```bash
wf approve STORY-0001  # draft -> accepted
```

Accepting unlocks the Story to be run.

## 4. Run the governed loop

Running an accepted Story creates a **Workstream** — one git branch in one
isolated worktree — and starts the implement/test/review loop:

```bash
wf run STORY-0001 --loop   # --loop runs until it blocks or completes
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
wf watch STORY-0001    # live TUI, or:
wf show <workstream>   # status snapshot
```

## 5. Hit an approval gate

When the loop pauses for you, the Workstream's `runtime_status` reads `blocked` (or
`changes_required`) and its stage is `awaiting_human_review`. Look at the diff and
decide:

```bash
wf diff <workstream>                      # see the change
wf approve <workstream>                   # looks good, continue
wf reject <workstream> -f "rename the handler to logout()"   # iterate with feedback
wf reset  <workstream>                    # keep the plan, redo from a clean baseline
wf replan <workstream> -f "split the endpoint out"  # the plan itself is wrong; regenerate it
```

(`reset` keeps the plan and redoes the implementation from baseline; `replan`
regenerates the plan from a clean base. They differ only in keep-vs-regenerate
the plan — see **[WF.md > Plan regeneration](../WF.md)**.)

If an agent needs information to proceed it raises a **clarification** and the
Workstream blocks. Answer it and the run continues:

```bash
wf answer list
wf answer <workstream> "use the existing session-cookie clear path"
```

## 6. Final review and merge

When every micro-commit is done, two branch-level gates run before anything lands:

- **Final review** — a holistic review of the *whole branch diff*. It either marks
  the branch `ready_to_merge`, flags `final_review_with_concerns` (mergeable, but
  worth a human read), or — if you reject — generates a FIX micro-commit you then
  `wf run` to address.
- **Merge gate** — runs the merge-gate test command, checks for conflicts against
  fresh `main`, and runs a `gitleaks` secrets scan. A secret finding blocks the merge.

Then merge:

```bash
wf merge <workstream> --wait        # direct merge to main (default)
# or, for external review on a forge:
wf merge <workstream> --pr --wait   # opens a PR; merge after CI/team review
```

In PR mode you can pull review comments (`wf pr feedback`) and reject to generate a
fix commit that produces a fresh PR. On a direct merge, hashd updates `SPEC.md`,
merges, cleans up the `REQS.md` WIP markers, and archives the Workstream.

## 7. View the audit trail

The change is now in `main` — and every step that produced it was recorded. This
is the payoff of the governed path: a full, queryable **lineage** chain.

```bash
wf lineage <workstream-or-sha-or-STORY-0001>
```

Trace a specific file or line back to the Story and decisions that produced it:

```bash
wf lineage src/auth/logout.go --lines 12-30
```

Export a machine-readable attestation for compliance, or verify the tamper-evident
hash chain:

```bash
wf lineage export <sha> --format slsa     # SLSA v1.0 provenance
wf lineage export <sha> --format in-toto  # in-toto statement, hashd predicate
wf lineage verify                         # validate the commit hash chain
```

For the full provenance story — what's captured, the standards it maps to, and why
it's the differentiator — see [provenance.md](provenance.md) and
**[docs/LINEAGE.md](LINEAGE.md)**.

## Recap

```text
REQS.md  ->  Suggestion  ->  Story (+ ACs)  ->  Workstream  ->  micro-commits
   ->  implement/test/review/approve loop  ->  final review  ->  merge gate
   ->  merged commit  ->  wf lineage (full audit trail)
```

Every arrow is a validated transition that was logged. That is the whole point:
not just code generated from a spec, but a governed path to a merged, attested
commit.
