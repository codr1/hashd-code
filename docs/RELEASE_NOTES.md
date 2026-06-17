# Release Notes

Release notes follow the same markdown structure used by GitHub releases:
version heading, date, categorized "What's Changed" bullets, and a full
changelog compare link.

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
