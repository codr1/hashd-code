# Release Notes

Release notes follow the same markdown structure used by GitHub releases:
version heading, date, categorized "What's Changed" bullets, and a full
changelog compare link.

## v0.9.21 - 2026-07-30

v0.9.21 reorganizes the story-facing CLI -- a breaking change -- and carries a batch of install/upgrade and diagnostics fixes surfaced by multi-box manual testing and a live production incident.

### BREAKING: story-scoped verbs move from `plan` to `story`

One rule, applied absolutely: if the operation takes a story id, it lives under `story`; if it works the suggestion pool, it lives under `plan`.

| was | is |
|-----|-----|
| `hashd plan retry` | `hashd story retry` |
| `hashd plan edit` | `hashd story edit` |
| `hashd plan split` | `hashd story split` |
| `hashd plan clone` | `hashd story clone` |
| `hashd plan edit-ac` / `delete-ac` / `descope-ac` / `rescope-ac` | `hashd story edit-ac` / `delete-ac` / `descope-ac` / `rescope-ac` |
| `hashd plan resurrect` | removed (deprecated tombstone) |

`plan` keeps the backlog surface: `discover`, `list`, `show`, `claim`, `status`, `reset`, and the ad-hoc creators `plan story` / `plan bug` (they take a title and create a story -- entry points into planning, not operations on an existing story). Old spellings fail with the standard unknown-command suggestions; scripts using the moved verbs must update.

### What's Changed

- **Story edits get a realistic time budget.** `stages.pm_edit.timeout` default rises 300s -> 900s (`pm_edit_resume` 300s -> 600s), matching `pm_refine`. Folding clarification answers into a large story is refine-class work; the old budget killed real edits mid-flight and parked the story at `draft_failed`.
- **Upgrades crossing a schema bump no longer deadlock.** `setup.sh` migrates the databases before anything opens them; previously owner provisioning hit the schema check first, setup died after a successful build, and its advice (`hashd restart`) pointed back at `setup.sh` -- a loop whose only exit was buried. Related: `db` open errors now point at `hashd internal migrate-dbs` instead of the loop.
- **Source builds report their real version.** A build-file scoping bug stamped every source build `dev`, which also made `hashd doctor` warn that a source server and wheel client were "built from different source trees" on matched pairs. Versions now stamp correctly, `task build VERSION=x` is honored, and doctor compares release identity rather than string spelling -- a source build genuinely ahead of the tag still warns.
- **Remote clients stop consulting local state they don't own.** `hashd project use` validates against the server (it rejected server-known projects from a remote client); a remote client no longer silently adopts a leftover local project as context, no longer deletes a server-validated saved selection, and the no-project diagnostic names the paired server instead of advising `project add`. A moved ops root (wheel install over a source install) now explains itself instead of presenting as total data loss.
- **Diff reads survive worktree reclaim.** `/diff`, `/diff/changes`, and `/diff/blob` fall back to the project repository once a merged or closed workstream's worktree is gone -- committed history stays readable, working-tree modes are rejected with precise diagnostics, and abbreviated commit SHAs are accepted. An unprovisioned or reclaimed worktree is an honest 400, not a git failure dressed as a 500.
- **Failure diagnostics carry the actual cause.** Agent-error messages keep their tail instead of being head-truncated (the part that says *why* it died lives at the end of agent output); auth failures lead with their classification (`agent_needs_login` vs a missing or rejected API key); `run_failed` events record the failure reason (`failed at review: <reason>`) instead of just the stage; and a reject that auto-resumes the flow prints exactly one next step instead of two contradictory ones.
- **A stuck review loop can no longer grind, and an operator ruling now binds.** A workstream rejected the same micro-commit ten times across two loop exhaustions while the convergence guard never fired: it watched only `major` findings, while `major` AND `minor` both reject a review, so a minor-driven reject produced an empty set and the guard skipped itself. It now watches every blocking finding, keyed on text so an objection re-raised at a different severity still counts as a repeat. Separately, a reject delivered at the review gate persisted nothing -- the reviewer's guidance section was empty on every later cycle while the implementer cited that ruling as its authority. Rulings now persist durably, scoped to the commit under review, reach every implement attempt rather than the first, survive the self-heal escalation, and carry standing in the review prompt distinct from an implementer's claim.
- **The retry budget is visible while it burns.** Loop events carry their position (`review_changes (attempt 2/5)`), the workstream read exposes the attempt in flight beside the after-the-fact exit record, and `hashd show` renders `review (attempt 3/5)`. Previously the numbers existed on the wire at every layer and reached no surface, so a workstream on its last attempt looked identical to one on its first.
- **`hashd workstream adjudicate`** -- a human-invoked, read-only scope judge for a review that will not converge. When a reviewer and an implementer deadlock over *where* work belongs rather than what it should do, the judge rules `IN_SCOPE` / `OUT_OF_SCOPE` with a citation, or returns `CANT_TELL` with a briefing. It never rules on functionality, never mutates the workstream, and is not wired into the runner: the operator runs it, reads it, and decides.
- **Agent retries emulate Claude Code's backoff.** The retry delay was a flat 5 seconds three times -- exponential in shape only, since the multiplier was 1 -- and a `Retry-After` from the server was clamped *down* to 5s. Backoff is now genuinely exponential with jitter, `Retry-After` is honored, and nested retry ladders no longer multiply into nine agent launches for a three-attempt policy. Upstream capacity failures (429/503/529) are classified as such and surfaced as an upstream incident rather than an unexplained stage failure.
- **Operator guidance is a durable record, not a file.** Rejection and replan guidance move from a JSON file in the ops tree into the database, attributable to a user and scopable to a story or commit. The file was invisible to a remote client and could not survive a workstream being recreated; existing files are migrated forward.
- **TUI:** story-detail and dashboard layout fixes, and the workstream timeline is coloured again -- its palette had been styling an event vocabulary the server stopped emitting, leaving a failure, a retry and a routine state change rendered identically.
- **The pre-commit secret scanner actually scans.** The private-key patterns begin with `-----BEGIN`, which grep parsed as options; every scan silently passed. Also: the hashd-web Go module is now linted by both the commit hook and the push gate.
- **Web:** the story page shows the workstream run's health; remote docs cover fingerprint-mismatch recovery on a single host and scripting over non-interactive SSH.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.20...v0.9.21

## v0.9.20 - 2026-07-29

v0.9.20 is a single-fix patch release for team-mode operators: `hashd restart` no longer breaks a box that is paired to a hashd-server running on another machine.

### What's Changed

- **`hashd restart` works on a box paired to a remote server.** On a client paired to a team server, restart derived its *listen* address from the configured *server* URL and tried to bind the server box's IP, failing with `bind: cannot assign requested address`. Because that aborted the start phase, it also left hashd-web stopped -- so the documented recovery command left the box with neither a local server nor a web UI, and the per-user web on a client box could never reach the team server. Restart now asks whether the configured endpoint is an address this machine can actually bind. When it is not, it skips Temporal, the local server and the project migrations, and restarts only what a thin client owns: hashd-web (pointed at the remote, carrying the server's cert pin) and the Telegram daemons. A box that hosts its own server -- including one deliberately bound to its external IP for team mode -- is unaffected.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.19...v0.9.20

## v0.9.19 - 2026-07-28

v0.9.19 is a reliability and internals release. A batch of fixes surfaced by the multi-user petshop soak hardens the runner, merge, and human-gate paths, and stage-timeout handling is consolidated into a single authority so operator timeout overrides -- including for the PM and discovery workflows -- take effect consistently.

### What's Changed

- **Stage-timeout handling consolidated.** The five separate resolvers for a stage's effective timeout collapse into one authority, and the single-shot PM/discovery workflows (planning, discovery, add-commit, detect, describe, edit) now derive their activity timeouts from project config -- so raising a stage timeout past the old hardcoded value takes effect instead of being silently capped.
- **Soak-surfaced reliability fixes.** Stage sub-processes are reaped by process group, a killed worker is caught via restart 401-liveness, the read-only review/judge stages retry infra blips (Tier A), `already_done` is handled for the plain-format claude agent, and abandoning a story releases its claimed suggestion.
- **Human gate and story-run gating.** Review-loop exhaustion parks at the human gate instead of failing the run, the park reason is surfaced on the operator surfaces, and the web/TUI story-run offer is gated on `runtime_status` and run-eligible workstream stages.
- **`project remove` cleans up its artifacts.** Removing a project now hard-deletes its orphaned workstream and run log trees, so the filesystem parallels the database removal instead of stranding unreferenced trees.
- **Side-by-side diffs.** New server `/diff/changes` and `/diff/blob` endpoints back side-by-side diff views.
- **Model and agent version bumps.** The Codex default model moves to gpt-5.6-sol (GPT-5.6 flagship), and the documented agent minimums update to Claude Code 2.1.220 and Codex CLI 0.145.0.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.18...v0.9.19

## v0.9.18 - 2026-07-27

The hashd CLI becomes a pure REST client. The server now owns all project state
-- repositories, config, prompts, and every AI agent run -- so the CLI never
touches SQLite, Temporal, or the filesystem directly, and every command works
identically whether the server is local or a remote team host.

### What's Changed

- **The server owns each project's repo.** `hashd project add` registers a
  project's repository at a canonical server-side path (a symlink for a local
  add, a clone for a remote one), and every agent run and git operation resolves
  through it. `hashd project remove` unlinks the server's own link but preserves
  a pre-existing clone or ingested repo -- it never deletes your working tree.
- **AI agent runs moved server-side.** describe/tech suggestion, the multi-repo
  project-add describe map-reduce, and `hashd project repo edit --suggest` now
  run as server-orchestrated Temporal workflows; the CLI dispatches and awaits
  the result over the event stream instead of invoking an agent itself -- so they
  work unchanged in team mode.
- **Prompts, doctor, cost, and completions are server-backed.** `hashd prompts`
  reads and edits prompts through the server, `hashd doctor` runs its checks
  server-side, `hashd cost` accepts a git ref the server resolves, and
  project-name tab completion lists projects over REST -- the last client-side
  ops-directory reads are gone.
- **Unified abandon/close teardown.** Abandoning or closing a story or workstream
  now cascades cleanup through one server-side path, fixing an orphaned-worktree
  case for in-flight stories.
- **Team-mode and petshop-soak reliability fixes.** A batch of fixes surfaced by
  the multi-user petshop soak, including team-mode edge cases in planning and
  merge.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.17...v0.9.18

## v0.9.17 - 2026-07-24

hashd gets a web UI. Install hashd and it's there -- after `hashd restart` it's
served at http://localhost:8099/ui, started and supervised alongside the server
with no separate process to run. Server-side-rendered views of your projects,
plans, stories, and workstreams with the same operator actions as the CLI,
curl-drivable end to end and keyboard-accessible.

### What's Changed

- **A web UI, shipped and auto-launched.** hashd-web ships inside the hashd
  install (binary and source) and comes up with `hashd restart` / `hashd start`,
  health-checked and reaped like every other hashd service -- you never launch or
  manage a separate binary. It prints its URL on start.
- **Dashboard, plan, stories, and workstreams in the browser.** Server-side-
  rendered pages mirroring the TUI/CLI: suggestions plus REQS/SPEC editing on the
  plan page, the stories and workstreams lists and their detail pages, with the
  human-gate verbs (approve / reject / run / merge) wired in.
- **Single-user and team, both supported.** Solo mode needs no login; team mode
  adds per-user sign-in with a session cookie, and the live event stream is fanned
  out per user.
- **Accessible and curl-drivable.** WAI-ARIA tabs, menus, and fields with keyboard
  operation, and every page and action is reachable by curl via structural hooks
  (no reliance on JavaScript) -- the same surface the operator smoke and the
  petshop soak drive.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.16...v0.9.17

## v0.9.16 - 2026-07-23

Three reliability fixes from the v0.9.15 petshop soak: a crashed story now
surfaces an actionable error, a killed server no longer leaves an agent running
loose, and add-commit tells you how to build the commit it queued.

### What's Changed

- **A crashed story now shows an actionable error, not a blank "crashed".** When
  planning or an edit fails a story into `draft_failed` (for example a git push
  to an unreachable remote), the reason -- including the retry command -- now
  appears in `hashd show STORY-x`. Previously it read `FAILED (crashed)` with no
  error, while the real diagnostic sat only in a stage-log file.
- **A killed server no longer leaves an agent running unsupervised.** Agent
  subprocesses now die with the server (`Pdeathsig`, held reliable across the
  fork), and a startup sweep SIGKILLs any agent orphaned by a hard crash before
  resuming work -- so a resumed run can't race a leftover agent over the same
  worktree.
- **`add-commit` points you at the next step.** The confirmation now says to run
  `hashd run <ws>` to build the queued commit, instead of looking like a stuck
  workstream (add-commit plans the commit; you run to implement it).

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.15...v0.9.16

## v0.9.15 - 2026-07-23

A soak-reliability patch: a leaked subprocess can no longer wedge a run, a story
being edited can no longer be approved out from under the edit, and a bare-box
install fails fast when git is missing.

### What's Changed

- **A leaked test or agent subprocess can no longer wedge a run.** Every runner,
  agent, hook, forge, and network-git command now bounds how long it waits on
  its output pipe after the deadline (`cmd.WaitDelay`). A project test command
  that leaves a background listener holding the pipe -- or an agent that spawns a
  surviving MCP or credential-helper child -- returns within seconds of the
  timeout instead of blocking the substage until the housekeeping sweep reaps it.
- **Approving a story mid-edit is rejected, not silently reverted.** Answering
  clarifications dispatches an edit; approving while that edit is still in flight
  now fails fast with an actionable diagnostic instead of "succeeding" and then
  being undone when the edit lands the story back at draft.
- **`install.sh` fails fast when git is missing.** git is a system prerequisite
  hashd shells out to (and never bundles); on a bare box the installer now stops
  up front with the OS-correct install command instead of running to completion
  and surfacing the gap only at first `doctor`.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.14...v0.9.15

## v0.9.14 - 2026-07-22

Remote project add lands: you can bring a project onto a hashd server you don't
share a filesystem with, pull it back down, and promote a no-remote project to a
real git remote. Plus a round of Temporal soak-reliability fixes and the Sonnet
5 model default.

### What's Changed

- **Remote project add (`hashd project add` against a remote server).** Land a
  repo on the server three ways -- `--clone <https-url>` (server-side clone with
  an encrypted per-user forge token), `--bundle` (upload a local repo), or
  `--create` (start empty) -- plus `hashd project download` to pull a
  server-owned repo back, and `hashd project set-remote` to promote a no-remote
  project onto a real git remote. Every server-side git network op is
  SSRF-guarded (public-host-only, DNS-rebind- and redirect-proof), and forge
  tokens are encrypted at rest (AES-256-GCM).
- **Encrypted forge token store.** Per-user forge tokens are sealed at rest and
  resolved CLI-first for single-user / token-based for teams, via `hashd forge`.
- **Soak-reliability fixes.** A hung git or test subprocess during merge can no
  longer stall a substage past its timeout; a crashed run no longer pins
  `runtime_status` at `running` (the stale-invocation reaper is now actually
  scheduled); merge no longer strands WIP markers when an annotation block is
  empty; and the `loop_triggered` transcript line now names its real trigger.
- **Agent auth failures are classified, not retried.** An agent that fails
  authentication surfaces an actionable diagnostic instead of being retried as a
  transient error.
- **Sonnet 5 for review stages.** The review / adjudicate / concern-triage
  stages default to `claude-sonnet-5`.
- **Login robustness.** Shell-completion sourcing is guarded so a missing binary
  can't break `hashd` login; the forge-aware `merge_mode` default no longer omits
  the mode for multi-repo doctor.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.13...v0.9.14

## v0.9.13 - 2026-07-20

Soak-hardening on top of the Temporal engine: a batch of fixes for issues the
v0.9.12 petshop soak surfaced -- broken operator-recovery paths, silent async
failures, and lingering one-off HTTP clients -- plus the ZMQ retirement and
per-project artifact edit locks.

### What's Changed

- **Runner-wedge recovery.** `hashd close --force` no longer returns 422, `hashd
  skip` works on real (heading-format) plans instead of 409ing every time, `hashd
  skip -m` records a durable reason, and `replan -> run` regenerates the plan
  instead of dead-ending at preflight.
- **Workstream/story lifecycle fixes.** `hashd run` on a concerns-flagged
  workstream points at `hashd reject` instead of dead-ending at the merge gate;
  closing a workstream now releases its linked story instead of stranding it at
  `implementing`; and WIP-marker cleanup on abandon no longer strands markers
  under concurrent REQS writes.
- **Team-mode TLS + telemetry.** The teardown-hook and grep-redirect calls now go
  through the standard fingerprint-pinned, authenticated client instead of bare
  HTTP clients that failed strict TLS against the LAN certificate in team mode.
- **Async operation surfacing.** Add-commit declines and other async operation
  outcomes now surface on the story detail and workstream list via a reusable
  `operation_result` event, and the agent-driven `plan split` render bug is fixed.
- **ZMQ retired.** The ZMQ forwarder is replaced by an in-process event broker;
  hashd-server is the sole publisher and bridges directly to SSE.
- **Per-project REQS/SPEC edit locks.** Editing REQS or SPEC takes a Temporal,
  event-driven FIFO lock so concurrent writers (planning, story-edit, docs, the
  TUI editor) don't clobber each other, with a read-only SPEC viewer in the TUI
  artifacts menu.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.12...v0.9.13

## v0.9.12 - 2026-07-17

The Temporal release. Prefect is gone: hashd's entire execution engine -- the
workstream runner, planning, merge, discovery -- is reimplemented as Temporal
workflows and activities, and with execution off Python, the orchestration layer
is demolished. Work now survives Ctrl-C and full-stack restarts by construction.
Alongside the engine swap: per-user story and workstream ownership, and a round
of install and diagnostic hardening.

### What's Changed

- **Temporal replaces Prefect as the execution engine.** The runner is rebuilt
  as Temporal workflows + activities and cut over incrementally -- activities and
  the inner/outer cycle (#1254 onward), reads, wiring, and engine-gating flipped
  behind it (#1266, #1268), native retry and the tier-B heartbeat model, then the
  engine flipped Temporal-only (#1282). Pinned to temporal-server 1.31.2 (#1287),
  with a workflow janitor + retention sweep (#1288), a schema-compatibility guard
  (#1290), and the payload/transport ceilings raised to the real limit (#1286).
  Work survives disconnect and restart because the sidecar persists it.

- **The Python orchestrator is demolished.** With Temporal owning execution, the
  Prefect/Python orchestration layer is deleted (#1284); the connector host and
  chat surface move to Go, and path validation goes Go-native (#1283). No PR
  increases net Python.

- **Per-user story and workstream ownership.** Stories and workstreams carry an
  owner; a guard stops one user acting on another's work, assignment is explicit,
  and the owner shows through the CLI and the watch TUI (#1277, #1278, #1280).

- **Source install works end to end.** A from-scratch source install was broken
  by ordering (tools installed after the step that needed them) and a dead
  first-install path; both fixed, plus the forge CLIs (gh/glab/bkt/tea) are now
  vendored by the shared installer so source installs get them too (#1291, #1292).

- **add-commit and first-run onboarding.** add-commit no longer strands or drops
  work (a refused commit is surfaced, not appended; one added at ready_to_merge
  returns the workstream to active), clarification answers are attributed
  honestly, `project add` reminds you to set a setup hook, and a missing agent
  warns instead of failing the install (#1293).

- **`hashd show` renders the detail it already had.** Provisioning diagnostics,
  pending clarifications, and error detail now show in the plain view instead of
  only in `--json`; a merged workstream stops flagging its removed worktree
  (#1294).

- **Reliability and fixes.** AI merge-conflict resolution legs (#1281),
  tech-tree resume fallback (#1276), petshop-validation fixes (#1279),
  release-surface cleanup (#1285), and a bot-view prompt-lint pass (#1289).

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.11...v0.9.12

## v0.9.11 - 2026-07-09

The plumbing release. The Go server becomes the single writer of record for
workstream state; the CLI, TUI, bot, and connectors move onto a shared
hashd-client SDK with the watch TUI as a pure viewer; migrations run through a
Go runner; and Telegram gains self-service per-user pairing. Mostly invisible
from the outside, but it is the foundation the team-server story stands on.

### What's Changed

- **One writer of record: the Go server owns every state mutation.** Commit
  hash-chains and run records (#1225), then clarifications, story transcripts,
  and workstream-id allocation (#1226), then the clarification / plan-split /
  run-transcript writes (#1227) all move behind the server -- no process other
  than the server writes the database. The events schema is synced and a
  generate-drift gate plus clarification-flip events close the residue (#1228,
  #1229), and the dead Python review parser is deleted. This shuts the last
  split-brain window where a Python helper and the server could both touch the
  same rows.

- **A shared `hashd-client` SDK; the watch TUI is a pure viewer.** The client
  logic is extracted into a reusable SDK (#1234); the TUI (#1235) and the
  Telegram bot plus connectors (#1236) cut over to it, and every transitional
  shim is deleted. The TUI now renders server state and dispatches through the
  SDK with no authority of its own, so local and remote mode share one client
  path.

- **Migrations run through a Go runner.** Schema and runtime migrations move to
  a Go migration runner with M000-M017 frozen as the baseline, and the old
  Python migration framework is deleted (#1237). Migrations apply the same way
  whether the trigger is a database open or a restart.

- **Telegram: self-service per-user pairing.** A user pairs their own Telegram
  account to the server and receives a per-user scoped token minted at
  provisioning, with a two-sided bind -- no operator hand-holding, and every
  action is attributed to the user who took it (#1232).

- **Client/server hardening.** A wire-contract handshake refuses a connection
  when the client and server disagree on the event contract (with a Diagnostic
  that points at the upgrade command), `hashd doctor` checks the contract before
  the version, the request header carries the build version, and agent
  retry-budget caps are pinned in lockstep with the retry logic (#1230).

- **Reliability and infra.** Fixed three live bugs -- a housekeeping cancel
  path, worker liveness, and the remote agent check (#1222). The ZMQ event-bus
  forwarder is reimplemented in Go with structured subprocess diagnostics
  (#1224). `hashd` now runs the tool copy it installed or fails loudly instead
  of silently falling back to `PATH` (#1233). The two cross-language
  review-prompt seams are pinned against drift (#1223).

- Internal: tombstone phrasing swept out of the user-facing docs (#1231).

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.10...v0.9.11

## v0.9.10 - 2026-07-06

Remote and team-server mode, made real. Driving a hashd-server from another
machine over TLS worked in pieces but fell apart at the one step that matters --
restarting the server -- and was undocumented. This release fixes the restart
path, adds a one-command way to onboard a teammate, and ships the manual that
explains how to run hashd for more than one person.

### What's Changed

- **`hashd restart` supervises an off-loopback TLS server instead of killing
  it.** When the server listens on a LAN address it serves HTTPS with a
  self-signed certificate and requires a bearer token on every request --
  including the health probe the restart supervisor uses. The supervisor sent a
  tokenless plain-HTTP probe, read the connection failure as "server dead," and
  tore the server down on every restart. It now probes with the resolved token
  over TLS, pinning the server's persisted certificate fingerprint, and the
  probe never writes TLS material. This was the last thing standing between
  "remote mode works" and "remote mode works after a restart." (#1218)

- **`hashd admin user add` mints a per-user access token.** Adding a user now
  returns a single token that carries both the bearer secret and the server's
  certificate fingerprint, so a teammate pairs with one
  `hashd server set <url> --token <token>` -- no separate certificate step and
  no second command. The token is attributed to that user even in solo mode.
  Full autocomplete and `--help`; the `admin` command group stays hidden. (#1218)

- **Remote and team-server mode are documented.** New `docs/REMOTE.md` covers
  the trust model (self-signed cert + fingerprint-in-token pinning, off-loopback
  fails closed), making a server reachable, provisioning users, pairing a
  client, the optional password-login path, and troubleshooting. README and
  QUICKSTART gain real onboarding sections for all three shapes -- solo-local, a
  shared server, and the unmanaged solo-shared-repo layout -- and the E2E plan's
  remote phase is now an executable mirror of that manual. (#1219)

- Internal: the release tooling's run-finder tolerates a local clock running
  ahead of GitHub (a WSL2 cut no longer dies waiting for a dispatched run it
  cannot see), and a comment records why the automatic TLS certificate is reused
  across listen-host changes rather than regenerated -- regenerating would change
  the pinned fingerprint and break every already-paired client. (#1220)

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.9...v0.9.10

## v0.9.9 - 2026-07-05

The butter release: a day of hunting operator-experience bugs end to end.
Quitting the watch TUI is instant instead of a 6-second stall, restarts no
longer leak event-bus daemons, upgrades stop re-running first-install
ceremony, and an operator-level smoke suite now drives hashd the way a
human does so this class of bug gets caught before it ships.

### What's Changed

- **Quitting `hashd watch` is instant.** Every quit (and project switch)
  stalled ~6.3 seconds: the event subscriber's stop path closed the SSE
  response to interrupt a blocked read, but closing a file descriptor does
  not wake a thread parked in recv() -- only a socket shutdown does. stop()
  now shuts the raw socket down first. Measured through the real TUI:
  6.35s before, 0.33s after. (#1215)

- **`hashd restart` no longer leaks event-bus daemons.** Every restart
  stacked a fresh ZMQ forwarder pair on top of the old one (the pid file
  named a process whose group id did not exist, so the stop silently killed
  nothing), and a superseded pair's eventual exit deleted the live pair's
  socket files -- silently killing real-time updates for the TUI, Telegram,
  and web. Stops now resolve the real process group, cleanup only removes
  files it still owns, and a sweep converges boxes that already accumulated
  strays back to exactly one forwarder on the next restart. (#1207)

- **Upgrades stop re-running first-install ceremony.** `setup.sh` now
  detects a working install and: never rewrites your per-stage agent
  assignments (previously it re-applied the default to all stages on every
  upgrade), no longer hard-fails on missing golangci-lint (a lint tool is
  needed to contribute, not to run hashd), and closes with an upgrade
  summary instead of "register your project" onboarding copy. (#1208)

- **Schema-gate errors say what they looked at.** "schema checkpoint behind
  source" now names the exact ops root, checkpoint file, and both versions,
  plus a HASHD_OPS_ROOT hint -- so a stale leftover install can no longer
  produce an undebuggable refusal. (#1210)

- **Operator-level smoke suite, wired into every release.** A hermetic
  harness boots a fully isolated hashd instance and drives it the way an
  operator does: `hashd watch` under a real pty (paints, owns the terminal
  foreground, quits clean), restart lifecycle (the forwarder-leak detector
  is a hard gate), an event-bus roundtrip, and a no-TTY contract table.
  Runs via `task smoke` locally, and every release candidate must now pass
  it -- plus a Tier 3 upgrade gate that installs the previous release,
  populates it with state, upgrades to the candidate, and asserts the
  server comes back healthy with the owner and data intact.
  (#1209, #1214, #1216, #1217)

- Internal: release tooling fails a cut with missing release notes in
  seconds instead of after the full CI pipeline, and stops compiling
  toolchain binaries just to record their version strings (~2.5 minutes
  saved per release). Code generators write atomically so parallel build
  chains can no longer truncate a generated artifact. Release builds
  actually reuse their Go module and C-compile caches across cuts (the
  Go cache restore was silently failing; the ccache directory died with
  the runner). Test-suite hygiene: TUI tests no longer leak a fake server
  URL across tests (the suite dropped from 112s to under 4s) and the api
  dispatch tests no longer sleep through production retry backoffs
  (70s to 38s cold). (#1206, #1212)

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.8...v0.9.9

## v0.9.8 - 2026-07-05

Fixes the two ways a working install could go dark: `hashd watch` freezing on
a blank screen at launch, and upgrades stranding a solo server that then
refused to start.

### What's Changed

- **`hashd watch` no longer freezes at launch.** Since v0.9.0 the CLI started
  the Python TUI in its own background process group (for clean Ctrl-C
  group-kill), but never handed it the terminal foreground -- and a TUI in a
  background group suspends itself waiting for an `fg` that never comes. The
  operator saw a frozen blank screen before the first paint, in local and
  remote mode alike. The launcher now starts the TUI's process group as the
  terminal foreground group and takes the terminal back when it exits; Ctrl-C
  reaches the TUI directly. Scripted / non-tty invocations are unchanged.
  (#1205)

- **Upgrades can no longer strand a solo server without an owner.** A
  solo-mode server that starts with no active user now self-heals by
  provisioning the implicit owner (derived from git config, the same way the
  installers do) instead of failing closed. A leftover non-active row for the
  same email is promoted, not collided with. Manual source upgrades
  (git pull + rebuild + restart) get a speed bump: a bare `hashd restart`
  that is really an upgrade asks for `--yes` so it isn't mistaken for a
  routine restart, and the installers hard-fail if owner provisioning fails
  instead of leaving a dead server behind. Team mode still fails closed on
  missing identity. (#1204)

- **One event surface for the watch TUI.** The TUI now consumes the server's
  SSE stream in local mode too, instead of opening its own ZMQ socket --
  local and remote share one code path, and the footer indicator now says
  "server disconnected" honestly. Remote mode also gains a client/server
  version banner: when the connecting CLI's build differs from the server's,
  the status line flags it in red (banner only, never blocks). (#1203)

- **Autonomous runs no longer park on final-review concerns.** In autonomous
  mode a final-review `CONCERNS` verdict now feeds a bounded self-heal loop
  (matching how the per-commit qa-gate already auto-continues) instead of
  stopping the unattended run at the first concern. Gatekeeper and supervised
  behavior are unchanged. (#1201)

- **Quieter doctor and install output.** Dropped the per-tool "dev-only;
  skipped in packaged install" noise, the raw schema version number in
  `hashd status` (only a mismatch is actionable), and other non-actionable
  chatter. (#1202)

- Internal: dead Python swept out (net -322 lines). (#1200)

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.7...v0.9.8

## v0.9.7 - 2026-07-02

Fixes the fresh-macOS binary install: `hashd`/`wf` now land on the zsh PATH,
completions work, and the bundled secret scanner no longer trips a timeout on
first run.

### What's Changed

- **Fresh macOS installs work end to end.** The binary installer wired PATH and
  shell completions only into `~/.bashrc`, which macOS Terminal (zsh) never
  sources -- so `hashd`/`wf` read as command-not-found and `hashd <TAB>`
  completion did nothing. The installer now writes the managed PATH + completion
  blocks to `~/.zshrc` too (on macOS, or when the login shell is zsh), including
  the entry-points directory. Linux and bash behavior is unchanged.

- **gitleaks no longer times out on first run.** The bundled secret scanner is now
  warmed once at install time -- paying macOS's one-time Gatekeeper cost up front
  -- and ad-hoc-signed with its quarantine attribute cleared, so `hashd doctor`'s
  dependency check passes on the first run instead of being killed by the probe
  timeout. That per-check timeout is also raised to 1s as a backstop.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.6...v0.9.7

## v0.9.6 - 2026-07-02

Makes provisioning fail loud when a fresh worktree can't run its toolchain, and
surfaces auth and mode in the watch dashboard.

### What's Changed

- **Baseline gate fails loud on a missing toolchain.** When a fresh worktree can't
  launch its configured test/build runner -- exit 126/127 or an exec launch error,
  e.g. a local-toolchain project whose dependencies aren't reachable from the
  worktree -- provisioning now stops at `provisioning / failed` with an actionable
  diagnostic (make the runner resolvable from a fresh worktree, or configure a
  `hooks.setup` install) instead of silently passing and surfacing the failure
  cryptically a few commits later. A legitimate greenfield non-zero exit (no tests
  yet) still passes.

- **Watch dashboard shows auth and mode.** The `hashd watch` dashboard header now
  surfaces the server's authentication surface and deployment mode.

- **Docs use the canonical `hashd` command.** QUICKSTART and the product docs now
  reference `hashd` throughout instead of the legacy `wf` alias (the alias still
  works).

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.5...v0.9.6

## v0.9.5 - 2026-07-01

Attributes work to the user who did it (team mode), and lets the implementer resolve
non-regression test conflicts it previously stalled on.

### What's Changed

- **Work is attributed to the acting user.** Stories, workstreams, suggestions, and
  clarification answers now record which user created or acted on them, backed by
  `user_id` columns on the core work items; existing unowned items are backfilled to
  the host owner. In team mode this makes "who did what" queryable. Solo mode is
  unaffected.

- **Legitimate test conflicts no longer stall the implementer.** When a failing test
  is judged a non-regression -- your change is fine, but the failure comes from a
  superseded test or an environmental/setup/harness issue -- the implementer is now
  explicitly authorized to fix that root cause, even in a file outside the current
  commit, while keeping the fix tightly scoped. Previously it documented the fix but
  wouldn't make it, and the commit looped to exhaustion.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.4...v0.9.5

## v0.9.4 - 2026-07-01

Adds multi-user / team-server identity, and finishes the local-only merge story so AI
conflict resolution works without a remote.

### What's Changed

- **Multi-user identity and team-server mode.** hashd now supports real users. A host
  provisions accounts (users table + host-local provisioning); a new user completes setup
  with a self-service password (replacing the shared setup key); and `hashd login` exchanges
  that password for a user-scoped bearer token. Deployment modes make it explicit: **solo**
  stays the default -- one implicit user, no auth ceremony, exactly like today -- while
  **team** enforces per-user identity on every request. Existing single-user setups are
  unaffected.

- **AI conflict resolution works on local-only repos.** `hashd merge --ai-resolve` assumed a
  git remote and aborted immediately (without ever running the resolver) on a project with
  no `origin`. It now rebases against the local base and resolves locally, matching the
  local-merge support added in 0.9.3.

- **Reviewers see the implementer's scope reasoning.** The per-commit reviewer can now read
  the implementer's optional `reason` (why work was deferred -- e.g. "tests belong to a
  later commit") and is told to verify it against this commit's scope rather than guess, so
  it stops docking confidence on deferrals it had to infer.

- **Completed requirements are captured verbatim at merge.** When a story merges and its
  requirement block is removed from REQS.md, hashd now records a durable `requirement_burned`
  event holding the exact original wording, the consuming story, the completion timestamp,
  and (when REQS.md is git-tracked) the source commit -- so the full history of completed
  requirements is queryable instead of being discarded on burn-down.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.3...v0.9.4

## v0.9.3 - 2026-06-30

A follow-up to 0.9.2 that restores local-only merges and makes a declined breakdown
recoverable.

### What's Changed

- **Local-only merges work again.** A project with no git remote couldn't merge -- the
  pre-merge rebase/test safety gate added in 0.9.2 unconditionally fetched `origin` and
  aborted when there wasn't one. It now sources the latest base locally when no remote is
  configured, so the same rebase-onto-latest-then-retest gate runs for local and remote
  projects alike.

- **A declined breakdown is now a recoverable operator decision, not a dead end.** When the
  breakdown step declines to break a story down, it blocks with the agent's reason and a
  proceed/hold choice -- `hashd answer <ws> proceed` to build it anyway, or `hold` to fix
  the story first -- instead of failing with an opaque "no JSON" error. The step is also
  clearer that REQS work-in-progress markers are internal bookkeeping (not a "not ready"
  signal) and that a plan carrying more detail than REQS is expected.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.2...v0.9.3

## v0.9.2 - 2026-06-30

A follow-up to 0.9.1 that fixes a review-loop stall on stories that span more than
one micro-commit.

### What's Changed

- **Micro-commit reviews no longer stall on deferred work.** The per-commit reviewer
  scored its confidence against the *whole story's* acceptance criteria, so an early
  micro-commit that legitimately leaves some criteria to later commits (for example,
  validation handled in its own commit) couldn't reach the confidence bar and looped
  through implement/review until it exhausted its attempts. The micro-commit reviewers now
  score against the commit's own scope -- story acceptance criteria are shown for context,
  and criteria a commit isn't responsible for no longer lower its confidence or raise
  findings. The whole-branch final review still verifies every acceptance criterion before
  merge.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.1...v0.9.2

## v0.9.1 - 2026-06-30

A focused follow-up to 0.9.0 that unblocks autonomous end-to-end runs on a clean
install, brings live streaming to Codex chat, and repairs several agents' headless
commands.

### What's Changed

- **Breakdown no longer refuses ready stories.** A persona line shipped in 0.9.0 told
  the breakdown stage to "refuse to break down a story that isn't ready" -- and on a
  requirements-anchored project it read hashd's *own* internal WIP markers (which claim a
  region of REQS for an active story) as a human "not ready" signal and refused,
  dead-ending the run before any code was written. That directive is reverted so breakdown
  proceeds normally; a readiness check with proper, surfaced refusal handling will return
  in a later release.

- **Merge gate finds the bundled gitleaks.** The mandatory secret-scan merge gate searched
  for `gitleaks` on `PATH` only, so a fresh install -- where the installer places gitleaks
  in hashd's own tools directory rather than on `PATH` -- failed every merge with "install
  gitleaks" even though it was already present. The gate now resolves bundled tools the same
  tools-dir-first way the rest of hashd does (honoring `$HASHD_TOOLS_DIR`, falling back to
  `PATH`).

- **Codex chat reaches parity with Claude.** The in-TUI thinking-partner chat now streams
  Codex replies token-by-token over the app-server transport, and Codex gains the read-only
  hashd MCP tool to query project state over that same transport -- bringing it to
  co-primary parity with Claude for chat.

- **Agent fixes across the fleet.** Gemini's headless invocation is fixed and live-verified
  so it runs non-interactively again; OpenCode's non-chat shapes no longer emit broken
  flags; and `_resume` stages now inherit their original base agent (covered by a live Codex
  regression test), so a resumed stage runs on the same agent it started on.

- **Internal robustness and cleanup.** hashd resolves which Python interpreter its
  subprocesses use through a single shared resolver, fixing divergence for non-default
  virtualenvs, and a batch of orphaned Python modules plus dead, uncalled functions was
  removed (a net reduction of roughly nine hundred lines).

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.0...v0.9.1

## v0.9.0 - 2026-06-29

A major release on three fronts: hashd now runs as a real **client/server** (CLI and
TUI on one machine, the server on another, over the internet, securely); the in-TUI
**AI thinking-partner chat** moved onto the server with live streaming that survives
disconnects; and the tool itself is now **`hashd`** (`wf` lives on as an alias). Plus
durable PR reviews and uniform agent permissions.

### What's Changed

- **Run hashd remotely, securely.** Point the CLI and TUI at a server on another box with
  `hashd server set https://host:1337 --token <token>` -- set it once and every command and
  the TUI follow. Same-machine use is unchanged: loopback stays fully transparent, with no
  auth or setup. The server auto-generates its own TLS certificate and `hashd auth create`
  mints a single pairing token that carries the certificate's fingerprint, so the client
  trusts it by pinning -- no CA files, no OS trust-store edits. Off-loopback is fail-closed:
  the server refuses to bind to a public address without TLS, and every remote request needs
  a valid bearer token. Manage tokens with `hashd auth {create,list,delete}`.

- **The CLI is now `hashd`.** The command renamed from `wf` to `hashd`; `wf` and `ha` remain
  permanent aliases, so existing muscle memory and scripts keep working. Pure rename, no
  behavior change.

- **AI chat / thinking-partner, now server-side and first-class.** The in-TUI chat runs on
  the Go server and streams the reply live, token by token, over SSE -- and generation is
  detached server-side, so you can drop the connection and reconnect, replay, or resume
  mid-turn (built for remote/SSH use). It auto-injects the right context for the scope (a
  story chat loads that story's diff, commits, review, clarifications, and timeline; a
  project chat loads its stories and workstreams) and resolves `@`-references server-side --
  `@diff`, `@file`, `@story`, `@commits`, `@review`, `@reqs`, `@spec`, `@timeline`, and
  connectors `@github` / `@jira` / `@figma`. The agent can propose story edits for you to
  confirm and apply, and has a read-only hashd MCP tool to query project state. In the answer
  box, `Ctrl+G` opens a clarification assistant that drafts an answer (refining your current
  draft if you've started one) for you to edit and submit -- nothing is ever sent on your
  behalf. Works across all seven agents (Claude, Codex, Gemini, Qwen, Copilot, OpenCode,
  Kimi) with per-agent live streaming and session reuse on resume.

- **Durable PR reviews.** Rejecting a PR no longer closes it and opens a fresh one -- the
  same PR gains a FIX commit and is reused, preserving review threads, resolutions, and bot
  incremental reviews across cycles. hashd reads forge review threads (GitHub, GitLab,
  Bitbucket, Gitea) with their resolution state, keeps a durable finding ledger, and feeds
  only still-open findings forward; it never marks a finding resolved itself -- the reviewer
  does. Late final-review concerns are now posted as PR comments.

- **Uniform agent permissions.** Each stage's tool-permission intent (read-only vs. write,
  shell access) is declared once and rendered to each agent's own flags, instead of being
  hand-maintained per agent -- fixing drift such as a review-resume that wasn't actually
  read-only. Agents without a native read-only mode (OpenCode, Kimi) are explicitly flagged
  as best-effort.

- **A thinner, server-owned core (the foundation for remote).** The Telegram bot and TUI are
  now database-clean -- clients reach the server over REST and SSE, never the database
  directly. Crash/health recovery is native in the Go server (the redundant Python monitor
  is gone), housekeeping sweeps and project-config reads moved server-side, forge PR/MR
  operations run through the server, and project Telegram config is served over REST.

- **Installer and tooling.** The installer shows per-wheel download progress and retries
  transient fetch failures (no more silent hangs or a single CDN blip aborting the install),
  and vendors the forge CLIs (`gh`, `glab`, `bkt`, `tea`) into hashd's own tools directory;
  its version parser no longer misreads `tea`'s build-metadata line, fixing aborted installs.
  A REQS.md viewer/editor opens with `R` from the TUI dashboard. Hyphenated project names are
  valid end to end, and `project add` preserves the build commands it detects.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.8.7...v0.9.0

## v0.8.7 - 2026-06-19

### What's Changed

- New `wf project` views surface a project's REQS and SPEC artifacts directly,
  so you can read the requirements and spec a project is working against without
  leaving the CLI.
- `wf` is far more responsive to interruption: it now exits promptly on Ctrl-C
  and SIGTERM instead of hanging, renders friendly, actionable diagnostics for
  bad arguments instead of a bare usage dump, and its shell completion works even
  on machines without the `bash-completion` package installed.
- `wf restart` is now a careful neighbor: it only stops processes hashd itself
  launched, and when a foreign process is holding a hashd port it tells you which
  one instead of killing it.
- `wf watch` no longer goes down with the server -- a dead or half-dead server
  surfaces as an error state in the TUI instead of crashing it.
- Hardened the boundary between the clients (`wf`, TUI, Telegram bot) and the
  server -- groundwork for running the server on a separate, eventually
  multi-tenant, host. The CLI now routes every call through a single cancellable
  HTTP path that reports clearly when a remote server is unreachable, and the
  Telegram bot gained the same CI-enforced "no direct database access" guard the
  TUI already enforced.
- Fresh installs now deliver `gitleaks` and `git-delta` and converge on an honest
  `wf doctor` that reports what is actually installed and authenticated. `wf
  project add` runs and classifies your configured test and build commands at
  setup time -- catching a broken toolchain before the first story instead of
  hours in -- and adds a Gitea on-ramp.
- Project discovery now runs on Sonnet instead of Opus: faster and cheaper for a
  step that does not need the larger model.
- Internal hardening: pinned every GitHub Action in the dev and back-merge
  workflows to commit SHAs (matching the release workflow) to close a
  supply-chain gap, removed dead Python now that the work moved to Go (the
  `prompt_registry` and the `timeline` mirror, ~760 lines, both superseded by
  Go-canonical paths), and made the pubsub tests self-heal stale runtime
  directories.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.8.6...v0.8.7

## v0.8.6 - 2026-06-18

### What's Changed

- Onboarding now works on a bare machine in one command. `curl … | install.sh`
  bootstraps a Python 3.11+ runtime via `uv` when none is present, so a fresh Arch
  or macOS box no longer dead-ends on a missing Python or a PEP-668 pipx wall. The
  installer output is quieter and clearer, errors carry the one OS-correct fix, and
  it finishes by running `wf doctor` and pointing you at your first project.
- Fixed installs that died with "No wheel found": wheels are now fetched from
  direct release CDN URLs instead of the unauthenticated GitHub API, which a fresh
  box (no `gh` yet) could exhaust at 60 requests/hour.
- Drew an honest dependency boundary: hashd needs `git` and an AI agent CLI; Python
  is handled by `uv`, and Node is documented as the agent CLI's prerequisite, not
  hashd's. The README now leads with the install command, and `wf doctor` guides you
  through installing and authenticating an agent.
- Trimmed the published docs to a curated, customer-facing set (internal design and
  planning papers no longer ship), moved QUICKSTART and the workflow reference to the
  front page, and hid the internal `wf upgrade` command (it runs data migrations,
  not a self-update) from the CLI surface.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.8.5...v0.8.6

## v0.8.5 - 2026-06-17

### What's Changed

- Fixed an install/startup crash for returning users. hashd shares the global
  `~/.prefect` database, so a machine whose `~/.prefect` was stamped by a newer
  Prefect (including hashd's own earlier install) crash-looped under the pinned
  older Prefect -- surfaced only as an opaque "health check timed out". Bumped the
  Prefect pin to 3.6.29, the newest pre-3.7 release, whose schema reads and
  forward-upgrades those databases; the FastAPI/Starlette web stack stays frozen
  at the proven-booting versions.
- `wf restart` and Prefect auto-start now surface the real server-start failure
  (tailed from the Prefect log) instead of a bare timeout, and point at the
  `PREFECT_HOME` workaround when the database was written by a newer Prefect.
- The TUI diff view now works out of the box: `git-delta` (pinned 0.19.2,
  SHA-verified) is auto-installed by both source setup and packaged installs and
  resolved from `~/.hashd/tools/bin`, so it is no longer a manual package-manager
  prerequisite.
- Release/vendor tooling: the bundled codebase-memory-mcp bump is now manual-only
  (dropped the weekly auto-bump) and mirror-aware (DeusData canonical, codr1
  mirror), with a release-time staleness nudge in the cut script.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.8.4...v0.8.5

## v0.8.4 - 2026-06-17

### What's Changed

- Closed the commit gate's biggest hole: a red micro-commit can no longer land.
  Exhausted test/build failures terminate instead of falling through to commit,
  the qa and human-review gates verify the test outcome and fail closed, and a
  failure caused by an earlier commit self-heals with reframed guidance instead
  of grinding.
- Reworked test-conflict escalation onto a single breakdown engine: the Tier-2
  architect/replanner became a partial breakdown, the oscillation guard now
  fires correctly and detects the same concern recurring across runs (not just
  within one run), and red-test conflicts are adjudicated against the
  requirement.
- `wf reject` now folds the review gate's own findings into the next attempt by
  default -- with provenance and recurring-concern framing -- so iterating no
  longer means re-typing what the reviewer already said. Reset/replan/reject were
  unified onto one engine and their feedback moved to a consistent `-f` flag.
- Lifted model and reasoning-effort out of agent command strings into
  declarative `model`/`effort` config, added per-stage agent retries with honest
  timeout reporting, attributed the harness-reported model, and gave the
  implementer the story's business goal as orientation.
- Added planning observability and recovery: see what is blocking planning,
  auto-heal orphaned planning state, and a `/plan/reconcile` endpoint with
  `wf plan reset`.
- Fixed cloned stories failing to load by declaring clone metadata fields and
  making the story loader tolerant of unknown server-written `data` keys, so
  future server-side fields can't crash it. Story `depends_on` is now validated
  at accept time.
- Reworked onboarding around the system rather than the command list, made
  Claude the universal default with `wf agents --suggest` and gatekeeper
  autonomy, and improved `wf project add`/describe with docs-first prompts and
  multi-repo role framing.
- Hardened fresh installs across platforms: pinned the Prefect/FastAPI/Starlette
  trio to a tested set (a fresh resolve was landing on a broken Starlette 1.x),
  dropped the installer's `awk` dependency for minimal Fedora, and moved the
  bundled codebase-memory-mcp binary onto a hashd-controlled fork.
- Smaller fixes: derive Prefect task timeouts from config, find the venv Python
  on dev-rig installs, a Telegram retry command for draft-failed stories,
  flow-status discovery by tag, and an in-place elapsed/cap timer for long AI
  steps.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.8.3...v0.8.4

## v0.8.3 - 2026-06-10

### What's Changed

- Fixed macOS release tooling by using `python3` in cbm lock parsing and bump
  automation.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.8.2...v0.8.3

## v0.8.2 - 2026-06-10

### What's Changed

- Fixed Apple Silicon cbm startup by forcing ad-hoc signing onto a fresh inode.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.8.1...v0.8.2

## v0.8.1 - 2026-06-09

### What's Changed

- Fixed planning retry recovery for suggestion-derived stories whose suggestion
  was already self-owned or done.
- Improved macOS cbm packaging by ad-hoc signing the bundled cbm binary.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.8.0...v0.8.1

## v0.8.0 - 2026-06-09

### What's Changed

- Replaced the native code-index backend with cbm-backed `wf code` and MCP code
  tools, including telemetry, prompt routing, and grep-redirect experiments.
- Made cbm lifecycle safer across workstreams: fixed list-project parsing,
  cross-project reconciliation, restart preservation, and telemetry writes.
- Added server-derived current errors and transitional dispatch status so
  summary surfaces show current operator state instead of stale history.
- Hardened startup and runtime recovery by cancelling orphan Prefect flows and
  sweeping stale active invocations before resume reconcilers run.
- Moved more TUI actions to REST, removed local-path consumers from screens,
  surfaced workstream clarifications, and gated actions from server-provided
  availability.
- Fixed repeated Rich markup failures in TUI status/log panels by escaping
  untrusted content at the formatter boundary.
- Restored optional client-side git-delta diff rendering for side-by-side,
  syntax-highlighted, word-level diffs.
- Improved project onboarding with narrated `wf project add`, editable detected
  git identity, and nested .NET solution detection.
- Added automatic merge-gate recovery for regenerated rebase conflicts and
  framed/contaminated fix-generation parser hardening.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.7.11...v0.8.0

## v0.7.11 - 2026-06-01

### What's Changed

- Unwrapped agent response text consistently before downstream parsing.
- Fixed workstream feedback project routing.
- Warned on planner file references outside the project.
- Made merge failures recoverable.
- Removed orphaned implement history prompt content.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.7.10...v0.7.11

## v0.7.10 - 2026-06-01

### What's Changed

- Added story split breakdown flow and plan-split wheel packaging.
- Flattened reviewer verdict schema and fixed review verdict consumers.
- Added review session resume, review observability CLI surfaces, acknowledged
  concern lifecycle, and final review history context.
- Fixed stale conflict-resolution state surfaces, TUI Rich bracket escaping,
  review feedback selection, TUI review schema display, and approval resume.
- Improved prompt composition documentation and fix-cycle prompt coverage.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.7.9...v0.7.10

## v0.7.9 - 2026-05-28

### What's Changed

- Added tech tree planner backend and TUI plan rendering.
- Made story-run claims transactional.
- Allowed ad-hoc planning without REQS anchors and extended the policy to edit
  flow.
- Checked auto-resolved rebase builds before continuing.
- Rendered auto-skipped implementation stages as success in `wf show`.
- Added final review deletion-reversal evidence and artifact-edit deterrents.
- Consolidated blocked suggestion rendering and moved tech-tree toggle hints to
  the footer.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.7.8...v0.7.9

## v0.7.8 - 2026-05-28

### What's Changed

- Self-healed accepted stories at implementation finalize.
- Sharpened plan discovery prompt behavior.
- Locked tech tree architecture and terminology.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.7.7...v0.7.8

## v0.7.7 - 2026-05-28

### What's Changed

- Added merge-gate secret scanning with gitleaks.
- Added JSON output for `wf show` and `wf list`.
- Added bounded review verification and richer review schema diagnostics.
- Ported final branch review to Go and consolidated FSM contracts in Go.
- Added wait flags for merge and answer workflows.
- Surfaced workstream blocked reasons and review fields in display surfaces.
- Improved OAuth/auth detection for Claude, Kimi, and Qwen.
- Hardened release wheel source retention with KEEP_FILES drift checks and
  globbed Prefect parameter schemas.
- Improved WSL filesystem diagnostics and chmod tolerance.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.7.6...v0.7.7

## v0.7.6 - 2026-05-26

### What's Changed

- Kept `deployment_refresh.py` as source in wheels so restart/doctor
  subprocess module execution works after install.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.7.5...v0.7.6

## v0.7.5 - 2026-05-26

### What's Changed

- Switched consumers to server-provided available actions and added FSM guard
  coverage for PR, merge, and replan flows.
- Preserved final review feedback and reshaped concern lifecycle handling.
- Improved final-review context by injecting authoritative stage results and
  test-stage evidence.
- Guarded terminal states from accidental rewrites.
- Forbade workflow-owned artifact edits and bounded implementation summaries.
- Escaped review/TUI markup and added fallback rendering for malformed Rich
  markup.
- Fixed `wf open`, `wf show` gate display, fuzzy 404 suggestions, stale merge
  toasts, timeout blocked-event duplication, and release workflow secret
  handling.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.7.4...v0.7.5

## v0.7.4 - 2026-05-22

### What's Changed

- Moved TUI and Telegram bot into separate installable subpackages and restored
  connector entry-point packages.
- Added connector host boundary and connector package discovery.
- Added transcript table storage, run-dir blobs, UTC event timestamps, and
  Go-routed ledger events.
- Fixed multi-repo worktree rooting and cross-repo provisioning defects.
- Improved release safety with DOA install gates, wheel smoke scripts,
  release-merge-before-tag behavior, ccache for wheel builds, and Python module
  execution checks.
- Added project-add single-repo flags, merge-gate/test command sync, and Go
  build environment setup in source installs.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.7.3...v0.7.4

## v0.7.3 - 2026-05-21

### What's Changed

- Redesigned release process around candidate CI, fresh checkout gates, pinned
  actions, and automated main-to-dev back-merges.
- Added `wf version` and `wf flow status`.
- Moved prompt transport to stdin and hardened prompt retry tests.
- Fixed wheel contract data packaging and first-run install/doctor UX.
- Added editing timeout recovery and edit-flow cleanup.
- Handled ZMQ forwarder restarts in `wf watch`.
- Hardened Prefect startup, work pool setup, and fresh-install restart gates.
- Added real install DOA gates and tzdata handling for packaged installs.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.7.2...v0.7.3

## v0.7.2 - 2026-05-20

### What's Changed

- Completed the review-stage migration to Go, including retry layers,
  cancellation handling, persistence, and deletion of the Python review path.
- Cut over detect parsing and execution through Go.
- Consolidated suggestion lifecycle writes through Go.
- Added release prepare/execute commands and offline OpenAPI regeneration.
- Added Gitea forge support.
- Fixed wheel `python -m` entrypoint source retention, install/doctor first-run
  UX, planning log-dir validation, and task build failure checks.
- Aligned GitHub and Jira connectors with the reference connector contract.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.7.1...v0.7.2

## v0.7.1 - 2026-05-18

### What's Changed

- Added system-wide stage-use defaults.
- Extracted and restored shared chat engine behavior while honoring repo skip
  gates.
- Backported release wheel smoke tests and synced OpenAPI output with the live
  server runtime.
- Dropped a stale wheel smoke requirement for `migrations/runner.py`.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.7.0...v0.7.1

## v0.7.0 - 2026-05-15

### What's Changed

- Added derived workstream runtime status and documented the canonical
  workstream state model.
- Added implementing, merging, and provisioning substages with timeout
  failsafes.
- Began the Go agent-runner migration for PM, route, concern triage, review,
  and related agent stages.
- Added structured diagnostics, parser drift contracts, and richer operator
  help for failure cases.
- Improved planning, REQS, and suggestion flows with drift handling, blocked
  suggestion display, queued planning cancellation, and planning retry reasons.
- Added remote-watch data-source seams, SSE/ZMQ coverage, TUI reconnection, and
  clarification action visibility.
- Hardened restart, Prefect, git-lock, runner shutdown, and auto-resume paths.
- Improved project setup and detection with build-system registry, test/merge
  command handling, project-add suggestions, and half-initialized project
  recovery.
- Fixed release/wheel packaging for migrations, Pydantic models, docs flow
  deployment, and fresh-checkout safety.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.5.10...v0.7.0
