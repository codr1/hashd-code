# Release Notes

Release notes follow the same markdown structure used by GitHub releases:
version heading, date, categorized "What's Changed" bullets, and a full
changelog compare link.

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
