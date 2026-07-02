# Release Notes

Release notes follow the same markdown structure used by GitHub releases:
version heading, date, categorized "What's Changed" bullets, and a full
changelog compare link.

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
