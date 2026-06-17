# Build-System Auto-Detection

Status: SHIPPED. Historical design record; implementation is the source of truth.
Shipped across: PRs #312, #314, #316, #328, #336, #337, #339.
Scope: `server/internal/config/detect.go`, `server/internal/config/detect_test.go`, a new `detect` stage in `orchestrator/`, a `--suggest` flag on `wf project add` / `wf project interview`, and warnings when `test_cmd` is empty.
Owner: TBD

## Summary

When a user runs `wf project add <path>` (or `wf project interview`), hashd inspects the repo and populates sensible defaults for `test_cmd` and `build_cmd`. Those defaults prefill the interactive interview, land in `config.yaml`, and drive the merge gate. Today the cascade covers Go, Python (pyproject/setup.py), Node, Rust, Java (Maven + Gradle), Taskfile, and Makefile. This document defines the target coverage and the phased rollout:

- **Phase 1** — Heuristic expansion: ten new ecosystems (.NET, Bun, Deno, Python-pip, Python-uv sharpening, PHP, Ruby, CMake, Dart/Flutter, Swift, Elixir, Scala, Zig, Haskell) and a `DetectedSystem` naming sweep. **SHIPPED in PR #312.**
- **Phase 2a** — Merge-gate warning when `test_cmd` is empty. Currently merge passes silently with zero tests run. Real bug. **SHIPPED in PR #314.**
- **Phase 2b** — UI warnings (CLI interview, TUI, Telegram). **SHIPPED in PR #339.**
- **Phase 3a** — AI-assisted detection, Python orchestrator side. **SHIPPED in PR #316.**
- **Phase 3b** — AI-assisted detection, CLI/REST/streaming wiring. `--suggest` flag on `wf project add` / `wf project interview`; sync with TTY-driven watching; parallel-dispatch-with-review-in-order for multi-repo; SSE subscription; stream-json parsing for per-file-read events. **SHIPPED across PRs #328, #336, and #337.**

The goal is **broad coverage with zero coupling**: detection is a suggestion layer, never a choice. The user can type any command in the interview, or leave it blank, and the orchestrator runs exactly what was configured.

## Principles

1. **Detection is a suggestion, not a decision.** `promptDefault` in `server/internal/cli/project.go` shows the detected value as the default-in-brackets. Enter accepts, anything else overrides. Empty is allowed. The orchestrator never consults `DetectedSystem` at runtime; it only consults `test_cmd` / `build_cmd`.
2. **First match wins.** The cascade is a flat if-return chain. Order is chosen so that the most specific manifest for a given ecosystem is checked before any manifest it can coexist with.
3. **Ecosystem names, not manifest filenames.** `DetectedSystem` is a display string. Humans read `Detected: java-gradle`, not `Detected: build.gradle.kts`. Qualifiers are hyphenated (`java-gradle`, `python-uv`, `haskell-stack`).
4. **No arbitrary caps.** No "first 5 files," no "first 100 lines," no cost estimation. Detection is a non-hot path; correctness matters more than cycles. The only numeric limits are runaway guards at extreme values (see **Limits and Caps**).
5. **No schema changes, no new dependencies for phase 1.** Heuristic detection is stdlib-only (`os`, `filepath`, `strings`, `encoding/json`). Phase 3 adds a new `detect` stage but reuses the existing `agent_calls` token-tracking table and the existing stage framework.
6. **Sub-repo detection inherits for free.** `detectSubRepoBuildSystem` delegates to `detectBuildSystem` via a temp `DetectionResult`; every new heuristic branch automatically works for multi-repo projects.
7. **Install is not build.** `build_cmd` means "produce a build artifact before running tests," not "install dependencies." `composer install`, `bundle install`, `npm install` are out of scope for `build_cmd`.
8. **Never estimate cost in dollars.** Token usage is tracked in the existing `agent_calls` table. Dollar theater is forbidden.

## Current state (origin/dev)

| Ecosystem | Trigger file(s) | `test_cmd` | `build_cmd` | `DetectedSystem` |
|---|---|---|---|---|
| Go | `go.mod` | `go test ./...` | `go build ./...` | `go.mod` |
| Python (pyproject) | `pyproject.toml` | `uv run pytest` if `pytest` in file else `uv run python -m pytest` | - | `pyproject.toml` |
| Python (setuptools) | `setup.py` | `python -m pytest` | - | `setup.py` |
| Node | `package.json` | `npm test` if `scripts.test` | `npm run build` if `scripts.build` | `package.json` |
| Rust | `Cargo.toml` | `cargo test` | `cargo build` | `Cargo.toml` |
| Java (Maven) | `pom.xml` | `mvn test` | `mvn package` | `pom.xml` |
| Java (Gradle) | `build.gradle`, `build.gradle.kts` | `./gradlew test` | `./gradlew build` | `build.gradle` or `build.gradle.kts` |
| Taskfile | `Taskfile.yml`, `Taskfile.yaml`, `taskfile.yml` | `task test` if `test:` target | `task build` if `build:` target | `Taskfile.yml` (etc.) |
| Makefile | `Makefile` | `make test` if `test:` target | `make build` if `build:` target | `Makefile` |

`DetectedSystem` naming is inconsistent (mix of manifest filenames and ecosystem names). The phase 1 sweep replaces all values with the ecosystem-name convention.

## Phase 1 — Heuristic expansion

Added in a single PR. Ten new branches plus a sharpening to the existing pyproject branch plus a naming sweep.

### Top-20 ecosystem gaps (Tier 1)

| Ecosystem | Trigger(s) | `test_cmd` | `build_cmd` |
|---|---|---|---|
| Python-uv sharpening | `pyproject.toml` AND `uv.lock` | `uv run pytest` (unconditional) | - |
| Bun | `bun.lockb` | `bun test` | `bun run build` if `package.json` has `scripts.build` else empty |
| Deno | `deno.json`, `deno.jsonc`, `deno.lock` | `deno test` | - |
| .NET | `global.json`, `Directory.Build.props`, any `*.sln`, `*.csproj`, `*.fsproj`, `*.vbproj` | `dotnet test` | `dotnet build` |
| Python-pip | `requirements.txt` (no pyproject, no setup.py) | `python -m pytest` | - |
| PHP | `composer.json` | `composer test` if `scripts.test` else `./vendor/bin/phpunit` if `phpunit.xml{,.dist}` else empty | - |
| Ruby | `Gemfile` | `bundle exec rake test` if Rakefile defines a `test` task, else `bundle exec rspec` if `spec/` dir, else `bundle exec rake` if Rakefile, else empty | - |
| CMake | `CMakeLists.txt` | `ctest --test-dir build` | `cmake -B build && cmake --build build` |
| Dart / Flutter | `pubspec.yaml` | `flutter test` if file references Flutter SDK, else `dart test` | - |
| Swift | `Package.swift` | `swift test` | `swift build` |

Notes:

- `.NET` accepts `.fsproj` and `.vbproj` alongside `.csproj`. All three use the same `dotnet` CLI; excluding F# and VB would be less generic for no benefit.
- CMake `build_cmd` chains configure + build (`cmake -B build && cmake --build build`). `cmake -B build` is idempotent. This matches what a real CMake user runs from a fresh clone and aligns with hashd's `build_cmd` → `test_cmd` sequencing (the README "Build and Test Execution" section). Alternative shapes (chain-in-test_cmd, defer to phase 3 AI investigation) rejected: placement here loses fewer signals.
- Dart vs Flutter disambiguation: `pubspec.yaml` with `flutter:` or `sdk: flutter` means Flutter; otherwise plain Dart. Empty `build_cmd` in both cases — Flutter's build target depends on platform (`apk`, `ios`, `web`, etc.) and is user-specific.
- Ruby prefers `rspec` over Minitest's `rake test` when both signals exist and a `spec/` directory is present. If neither applies, `bundle exec rake` runs the default Rake task (often `test`), and the user can override.

### JVM adjacencies and functional-language coverage (Tier 2)

Same pattern, cheap additions for ecosystems just outside the StackOverflow top 20 but with universally-agreed build manifests.

| Ecosystem | Trigger(s) | `test_cmd` | `build_cmd` |
|---|---|---|---|
| Scala | `build.sbt` | `sbt test` | `sbt compile` |
| Elixir | `mix.exs` | `mix test` | `mix compile` |
| Haskell (Stack) | `stack.yaml` | `stack test` | `stack build` |
| Haskell (Cabal) | `*.cabal` | `cabal test` | `cabal build` |
| Zig | `build.zig` | `zig build test` | `zig build` |

### DetectedSystem naming convention

Sweep the full cascade to ecosystem names. Lowercase, hyphenated qualifiers. No manifest filenames.

| Trigger | Value |
|---|---|
| `go.mod` | `go` |
| `pyproject.toml` + `uv.lock` | `python-uv` |
| `pyproject.toml` | `python` |
| `setup.py` | `python-setuptools` |
| `requirements.txt` | `python-pip` |
| `bun.lockb` | `bun` |
| `deno.json` etc. | `deno` |
| `package.json` | `node` |
| `Cargo.toml` | `rust` |
| `pom.xml` | `java-maven` |
| `build.gradle{,.kts}` | `java-gradle` |
| .NET triggers | `dotnet` |
| `build.sbt` | `scala` |
| `mix.exs` | `elixir` |
| `Gemfile` | `ruby` |
| `composer.json` | `php` |
| `pubspec.yaml` (Flutter) | `flutter` |
| `pubspec.yaml` (Dart) | `dart` |
| `Package.swift` | `swift` |
| `stack.yaml` | `haskell-stack` |
| `*.cabal` | `haskell-cabal` |
| `build.zig` | `zig` |
| `CMakeLists.txt` | `cmake` |
| `Taskfile.*` | `taskfile` |
| `Makefile` | `make` |

Blast-radius check (performed 2026-04-22 against `worktree-build-detection`):

```
git grep -l "Detected:" server/ orchestrator/ prompts/ docs/ tests/
  → server/internal/cli/project.go  (only hit)

git grep -n "DetectedSystem\|detected_system" \
    -- ':!server/internal/config/detect.go' \
       ':!server/internal/config/detect_test.go'
  → server/internal/cli/project.go:506-507, 539-540  (display-only printf)
```

No consumers in prompts, docs, tests, orchestrator, or the Python side. `docs/design/archive/multi-repo-v2.md` interview prose does not quote `Detected:` strings. The sweep is purely cosmetic — safe to rename without coordinated updates elsewhere.

### Cascade ordering rules

Flat cascade. First match wins. Order matters when manifests coexist.

1. `go.mod`
2. `pyproject.toml` (with uv.lock sharpening)
3. `setup.py`
4. `requirements.txt` — after pyproject/setuptools so the modern Python manifests win
5. `bun.lockb` — **must** precede `package.json`; bun.lockb is bun-exclusive
6. `deno.json` / `.jsonc` / `.lock` — placed before `package.json`; deno.json is deno-specific
7. `package.json`
8. `Cargo.toml`
9. `pom.xml`
10. `build.gradle` / `build.gradle.kts`
11. .NET
12. `build.sbt` — JVM cluster, after Gradle (Scala projects that use Gradle get Gradle, matches upstream expectations)
13. `mix.exs`
14. `Gemfile`
15. `composer.json`
16. `pubspec.yaml`
17. `Package.swift`
18. `stack.yaml`, then `*.cabal`
19. `build.zig`
20. `CMakeLists.txt` — before `Makefile`; a CMake project often ships a convenience Makefile, but CMake is the more specific signal
21. `Taskfile.*`
22. `Makefile`

Bun-before-`package.json` is the only reorder of existing checks. All other new branches insert cleanly.

### Ordering tests

Every collision gets a test that proves the more-specific manifest wins:

- Bun vs Node (`bun.lockb` + `package.json` → bun)
- Deno vs Node (`deno.json` + `package.json` → deno)
- Python-uv vs Python-pyproject (pyproject + `uv.lock` → python-uv)
- Python-pip vs Python-pyproject (pyproject + `requirements.txt` → python)
- Python-pip vs Python-setuptools (setup.py + `requirements.txt` → python-setuptools)
- .NET vs Makefile (csproj + Makefile → dotnet)
- CMake vs Makefile (CMakeLists.txt + Makefile → cmake)

### How to add a new heuristic ecosystem

1. Pick a trigger that is unambiguous. If the trigger can coexist with an existing manifest, decide which wins and document why in the branch comment.
2. Add a branch in `detectBuildSystem` following the existing pattern: `os.Stat` for a single file, `os.ReadFile` + content sniff if the command depends on file contents, `os.ReadDir` + suffix scan if the ecosystem has per-file manifests (see `hasDotNetManifest`).
3. Set `DetectedSystem`, `TestCmd`, `BuildCmd`. Leave `BuildCmd` empty when the ecosystem has no standard build step (Deno, most script languages).
4. Add tests to `detect_test.go`:
   - Happy path: manifest present → correct detection.
   - If the branch depends on file contents, cover both branches of that conditional.
   - If ordering matters, add an ordering test that proves the new branch wins over the manifest it could collide with.
5. Confirm `detectSubRepoBuildSystem` picks up the new branch automatically (it delegates; no changes needed).

## Phase 2a — Merge-gate warning on empty `test_cmd`

**Real bug, not polish.** Current behavior in `orchestrator/workflow/merge/pre_validate.py:171-174`: if `test_cmd == ""`, the merge gate returns `(True, "")` and merge passes with zero tests run. No warning, no signal.

Fix:

- When `test_cmd == ""` at merge time, emit a diagnostic in the merge result (`source: "merge.no_test_cmd"`, severity: `warning`) using the consolidated diagnostic shape (reference: PR #240).
- Record a durable event `warning_no_test_cmd` and fan it out on the project bus. TUI, Telegram, and future web UIs pick up automatically — no per-surface work needed in this phase because the SQLite event record is the source of truth and ZMQ is the realtime fanout per `docs/ARCHITECTURE.md > Event Bus And Durable Events`.
- Merge is still allowed. Warn, don't block.

Baseline tests path (`orchestrator/workflow/provisioning.py:191-195`) currently logs "No test command configured, skipping baseline gate" to Prefect. Upgrade to the same ZMQ warning event so it's visible to humans, not just Prefect logs.

Ship as a separate PR after phase 1 merges. No CLI surface changes. No new flags.

## Phase 2b — UI warnings (shipped)

Per-surface polish that attaches the `warning_no_test_cmd` signal to visible affordances:

- CLI `wf project add` / `wf project interview` end-of-interview warning when `test_cmd == ""`.
- TUI watch detail panel: warning badge on workstreams whose project has no `test_cmd`.
- Telegram `/status`: include a "no test gate" line per project.

**Status:** shipped in PR #339. The design below is retained as historical reference for the warning surfaces that landed.

**Attachment points in the interview** (per multi-repo v2 §4.1 primary/active/reference stages):

- Primary-stage repo: warn after the repo's per-prompt loop if that repo's `test_cmd` is empty.
- Active-stage repos: same — per-repo warning after the prompt loop.
- Reference repos: no warning — reference repos intentionally have no test_cmd (they're read-only context for the model, not targets of workstreams).
- Project-level end-of-interview summary: list any repos that ended with empty `test_cmd`, single summary line.

**Hook requirement:** multi-repo v2's interview needs an "after-this-stage callback" point (or equivalent). Coordinate with multi-repo v2 author to confirm the shape; if not present, add a minimal hook there.

No `--no-tests` flag. CLI surface additions need explicit user sign-off and `warn, don't block` doesn't require one.

## Phase 3 — AI-assisted detection (`--suggest`)

For build systems whose names don't match the heuristic patterns (`check`, `ci`, `verify`, `tests:unit`, `validate`, custom composer scripts, custom mix aliases, Rakefile with non-standard task names, CMake target layouts beyond `ctest`), heuristic detection returns empty or suboptimal results. Phase 3 adds a one-shot agent call — like planning — that reads the repo and proposes `test_cmd` / `build_cmd` via the same stage infrastructure.

Historical delivery:

- **Phase 3a** — Python orchestrator side. **SHIPPED in PR #316, retired by the Go cutover.** Delivered the original detect stage, prompt, and detect bus events. The Python implementation and schema file no longer exist.
- **Phase 3b.1** — backend dispatch/wire shape. **SHIPPED in PR #328.**
- **Phase 3b.2** — CLI/REST/approval UI wiring. **SHIPPED in PR #336.**
- **Phase 3b.3** — `DetectFileRead` streaming and progress rendering. **SHIPPED in PR #337.**
- **Go cutover** — parser and execution migrated to Go in PRs #713, #716, #719, and follow-up cutover. Python `detect_flow.py` now shells to `wf internal detect-stage`; the old Python `stage_detect` implementation and schema file were removed.

### Phase 3a — Stage Implementation (SHIPPED, GO-MIGRATED)

Recorded here as historical reference; authoritative source is the Go code under `server/internal/stages/detect`.

- **Stage registration.** `STAGE_SHAPE["detect"] = "json"` in `orchestrator/lib/agents_config.py`. `stages.detect` entry in `orchestrator/lib/defaults.yaml`: Claude Sonnet-class model, 10-minute (600s) timeout, `default_agent: claude`, read-only invocation (`--disallowedTools Bash,Edit,ExitPlanMode,Monitor,NotebookEdit,PowerShell,Skill,WebFetch,WebSearch,Write`). Per-project agent override via `config.yaml` `stage_agents.detect`.
- **Stage implementation.** `RunDetectStage` in `server/internal/stages/detect` is invoked by `wf internal detect-stage`; Python `detect_flow.py` is only a Prefect wrapper that shells to that internal command. Agent-level failures return `DetectResult{ok:false}` so callers fall back to heuristic values.
- **Seed context.** Primary build manifest (4 KB cap), `README.md` (2 KB cap), interesting top-level file listing. Agent is free to read anything else via its `Read` tool; these caps bound only the initial prompt.
- **Output contract.** Validated in Go by `server/internal/stages/detect/parser.go`: `test_cmd` (string|null), `build_cmd` (string|null), `build_skipped` (boolean), `detected_system` (lowercase ecosystem name), and `justification` (non-empty operator-facing rationale). Null commands are legal.
- **Bus events.** `DetectStarted(project, detect_id, repo_path)` at entry; `DetectCompleted(project, detect_id, ok, detected_system, input_tokens, output_tokens, elapsed_seconds)` at exit. `DetectFileRead` is defined but not emitted in 3a — see Phase 3b.
- **Token usage.** The Go parser lifts `input_tokens` / `output_tokens` from Claude Code's envelope, propagated to `DetectResult`, `DetectCompleted` event, and the `agent_calls` ledger on every envelope-bearing path (including validation failures — those tokens were still billed).
- **No cost estimation** ever emitted. Token counts only.

### Phase 3b — CLI + REST + streaming

**Status:** shipped across PRs #328, #336, and #337. The design below is retained as historical reference for the behavior that landed.

#### UX shape: sync with TTY-driven watching

`wf project add --suggest <path>` (and `wf project interview <name> --suggest`) is **synchronous**. The CLI dispatches the detect flow and blocks until it completes, then shows the result inline for the user to accept / edit / reject. No async default, no `--watch` flag.

- **Interactive (TTY):** CLI streams progress events (start / file-read / completed) in real time while waiting, plus an elapsed-time counter. On completion the CLI shows the four output fields + justification and prompts `[a]ccept / [e]dit per-field / [r]eject (heuristic fallback)`. Enter = accept.
- **Non-interactive (`-y` or no TTY):** CLI blocks silently, auto-applies the result when it lands. On failure (timeout, error) falls back to heuristic silently, logs a `Diagnostic` with `source: "stage.detect"`. Never fails the whole `project add` just because one repo's AI call timed out.

The `--suggest` flag is the existing precedent (`project describe --suggest`, `project tech --suggest`). Matches multi-repo v2's §6 flag vocabulary (`ai_interview_default` project-level knob can default it on).

#### Multi-repo: dispatch-as-named, review-in-named-order, cap 5

As the user types each repo name in the multi-repo-v2 interview (§4.1 primary/active/reference stages), the CLI dispatches a Prefect detect flow for that repo in the background. After all repo names are collected, the interview enters a **review phase** that walks each repo in the user's naming order. For each repo:

- If its detect already completed → show the result immediately, prompt for approval.
- If still running → stream its events (replayed from start) until `DetectCompleted`, then prompt.

This gives parallel wall-time (repos 3-N run concurrently while the user is still naming later repos) with a deterministic, predictable review ordering (no mid-typing pop-ups from unrelated repos).

**Concurrency cap 5.** `stages.detect.max_concurrent: 5` in `defaults.yaml`, overridable per-project via `config.yaml` `stages.detect.max_concurrent`. Implementation choice (Prefect global concurrency limit vs local asyncio semaphore) deferred to coding time — both are viable for cap=5.

**During dispatch phase** (user still typing names): the CLI renders **nothing** about detection. Silent background dispatch. The user is focused on naming repos; progress noise at this stage is noise. All visibility happens during the review phase.

**Multi-repo failure handling.** When review reaches repo X and X's detect failed, skip the approval prompt, print `"Detection failed for <X>: <reason>. Using heuristic."`, continue to the next repo. Never block the rest on one repo's failure.

#### Approval UX

```
--- Review aex-risk-guard-service ---

  Running AI investigation on aex-risk-guard-service...
  [detect_started]    0:03
  [detect_file_read]  0:05  Makefile
  [detect_file_read]  0:12  README.md
  [detect_completed]  1:47

  Detected system: go
  Test command:    go test ./...
  Build command:   go build ./...
  Justification:   Standard Go module with go.mod at root; test/ subdir
                   holds the package-local suite.

  [a]ccept  [e]dit per-field  [r]eject (fall back to heuristic)
  > _
```

- **Accept (`a` / Enter):** apply the AI's four fields as interview defaults for this repo, continue.
- **Edit (`e`):** prompt for `test_cmd` and `build_cmd` only (pre-filled with AI values). `detected_system` is metadata, not user-editable. `justification` is read-only explanation.
- **Reject (`r`):** discard AI values, use pre-detect heuristic values as defaults for this repo (same state as if `--suggest` weren't passed for that repo).

#### Event streaming: SSE through the server

The Go CLI subscribes to progress events via the existing server SSE endpoint (landed in PR #304). Filter shape: by `detect_id` (or by project + event type — whichever the SSE endpoint already supports). No new ZMQ client in the CLI binary; no new network pattern.

The SSE endpoint may need one extension: filtering by `detect_id` to demultiplex multi-repo runs. Confirm current filter shape before coding.

#### `DetectFileRead` source: stream-json parsing

Phase 3a did not emit `DetectFileRead` because a one-shot `subprocess.run` can't observe tool calls in-flight. Phase 3b changes the detect stage's subprocess handling to use Claude Code's `--output-format stream-json`:

- Change the invocation from `--output-format json` to `--output-format stream-json`.
- Replace `subprocess.run` with `subprocess.Popen` and a line-buffered reader.
- Parse each incoming JSON object; for tool-use events of type `read` (or equivalent in Claude Code's stream format), emit `DetectFileRead(project, detect_id, path)`.
- The terminating message carries the final result payload; feed that into the existing `_parse_agent_response` / `_validate_result` pipeline.

The change is contained to the detect stage's subprocess handling — doesn't ripple into the rest of the codebase. `DetectResult`, `DetectCompleted`, and the ledger-recording stay identical.

**Fallback position:** if stream-json parsing turns out finicky (Claude Code format changes, edge cases), Phase 3b can ship with clock-only progress (no `DetectFileRead`) and a follow-up adds stream-json when stable. Don't block Phase 3b on this piece.

#### REST contract

Extend `POST /projects/detect` with the existing `suggest: true` body field (already in scope per Phase 3a's design doc). In sync dispatch mode the endpoint:

1. Runs heuristic detection (as today).
2. If `suggest: true`, dispatches a Prefect detect flow per repo (root + sub-repos), returns immediately with a correlation object:
   ```json
   {
     "heuristic": { /* existing DetectionResult */ },
     "detect_ids": { "aex-risk-guard-service": "...", "aex-balances": "..." },
     "suggest_enabled": true
   }
   ```
3. The CLI subscribes to each `detect_id` via SSE and blocks on completion before prompting the user for approval.

No new endpoint. No change to the existing non-`suggest` response shape.

#### Timeout and cancel semantics

- **Timeout:** 10 min hard cap per repo (the `stages.detect.timeout: 600` cap from `defaults.yaml`). Not a UX knob — it's the "agent is stuck, kill it" rail. On timeout the CLI shows `"AI detection timed out after 10 min for <repo>; using heuristic defaults. Re-run with wf project interview --suggest <name> to retry."` and falls back. The interview proceeds with heuristic values.
- **Cancel (Ctrl-C during sync wait):** cancels the Prefect flow(s) for every in-flight detect in this invocation, aborts the interview, rolls back. Simple, matches user expectation. If the user wants non-blocking semantics, they use `-y`.
- **No soft-timeout messaging** ("this is taking a while..."). The streaming events already convey progress; the elapsed counter conveys time. Extra "still working" output is noise.

#### Limits

Phase 3b adds one configurable numeric cap and no others:

| Cap | Value | Configurable? |
|---|---|---|
| `stages.detect.max_concurrent` | 5 | `defaults.yaml` default, per-project override in `config.yaml` |

No `--concurrency N` CLI flag. No `--watch` / `--no-watch` flag. No `--quiet` / `--no-progress` (add when someone asks).

#### What Phase 3b does NOT include

- **Pending-suggestion queue** / async apply. The sync+review approach (user approves inline) removes the need for a post-hoc suggestion surface. If post-hoc suggestions are ever desired, that's a separate future phase.
- **Suggestion provenance tracking** (which fields came from AI vs heuristic vs user edit). Not needed with the sync-review model.
- **Multi-project parallel detect** (N projects × M repos = N×M concurrent). The cap of 5 applies per `project_add` invocation, not across projects.

## Limits and Caps

Explicit audit. Heuristic detection (phase 1) has **no arbitrary numeric caps**.

| Location | Behavior | Rationale |
|---|---|---|
| Manifest file reads (`os.ReadFile`) | No size cap | Manifests are small in practice; capping is premature |
| Directory scans (`os.ReadDir`) | Iterate all entries, early return on first match | Natural termination, not a numeric cap |
| `scanSubRepos` depth | Immediate subdirectories only | Depth cap of 1; intentional — recursive scanning is unbounded cost |
| `newGitTimeout` | 5 s per git command | Pre-existing; responsiveness guard, not a correctness cap |

Phase 3 (AI-assisted) caps:

| Cap | Value | Rationale |
|---|---|---|
| Operation timeout | 10 min (600 s) | Runaway guard. Detection is non-hot-path; giving the agent room to explore matters more than speed. |
| Prompt token ceiling | ~100k input tokens | Extreme runaway guard only. Normal operation doesn't approach this. |
| Files sent to agent | **No cap.** Agent reads any file it wants. | Correctness over cycles. |
| Max agent calls | **No cap.** | Per-stage invocation is single-shot, like planning. Multi-repo parallelism multiplies but each is independent. |
| Per-file byte cap | **No cap.** | Agent decides truncation if needed. |
| Cost estimation | **None ever.** | Prohibited. Tokens tracked as metric via `agent_calls`; dollars are user-inferable, not system-computed. |

Opt-in policy: AI-assist is off by default. User must pass `--suggest` or answer yes to the interactive prompt. Scripted `-y` flows get an advisory but don't invoke AI.

Model: Claude Sonnet-class via the `claude` agent, user-configurable per-project via `config.yaml` `stage_agents.detect` (swap to `codex`, etc.). Provider-agnostic — no Anthropic-specific code path; hashd's agent abstraction handles both.

## Non-goals

- **Auto-picking a build target for multi-target repos.** A .NET solution with 12 csproj files uses `dotnet test` / `dotnet build` at the repo root. We do not try to resolve which csproj to target. Same for Haskell multi-package stack workspaces, Cargo workspaces, Gradle multi-project builds.
- **Generating or writing manifest files.** Detection is read-only. We never create `Makefile`, `Taskfile.yml`, or any trigger file on the user's behalf.
- **Running tests to confirm they work.** Preflight already validates that the `test_cmd` binary resolves. Detection does not execute the command.
- **Deep content parsing in heuristic mode.** Where content inspection is needed (pyproject `pytest` string, package.json `scripts.test`, Rakefile `task :test`), use cheap substring or JSON checks. AST parsing belongs in phase 3's agent.
- **Shell access for the detection agent.** Read + list + glob only. Preserves a clean blast-radius boundary.
- **Dollar cost display.** Ever.

## Coordination with in-flight work

### multi-repo v2 (`docs/design/archive/multi-repo-v2.md`)

Specifies an interactive interview that consumes detection output and optionally enriches via AI investigation. Alignment points:

- `detect.go` schema stays unchanged (both designs agree).
- `scanSubRepos` stays unchanged (both designs agree).
- Phase 1 is purely additive to `detectBuildSystem` — no conflict.
- Phase 1's naming sweep invalidates any "Detected: <filename>" example strings in `multi-repo-v2.md` interview prose; doc follow-up after phase 1 ships.
- Phase 2b (UI warnings) was originally deferred until after multi-repo v2 landed because both touched the `wf project add` interview. That work later shipped in PR #339.
- Phase 3 (AI-assisted detection) and multi-repo v2's AI investigation are the same pattern at different entry points. Both should use the same stage (`detect`) and the same prompt templates where possible. Cross-author sync needed before phase 3 ships.

### PR #311 (`worktree-project-add-fixes`)

Adds to `detect.go`:

- New `ReqsExists bool` field on `SubRepoResult`, populated in `scanSubRepos` by stat-ing `REQS.md` in each sub-repo.

Rewrites `wf project add` in `server/internal/cli/project.go`:

- Interactive init menu (clone/create/local/cancel) for non-existent paths, with forge-CLI filtering.
- "Initialize git?" prompt for existing non-git directories.
- `reqs_path` precedence resolution across root + sub-repos (consumes the new `ReqsExists` field).
- Git identity propagation from project root to sub-repos.
- Subprocess timeouts and hardening on all git/forge calls.

Impact on this design:

- **Phase 1 heuristic edits** — no conflict. Different function in the same file (`detectBuildSystem` vs `scanSubRepos`).
- **Phase 1 naming sweep** — the `DetectedSystem` printf sites move inside the rewritten interview flow. The sweep is still purely cosmetic; re-confirm the printf target at rebase time.
- **Phase 2b** — PR #311 rewrote the interview surface phase 2b attached to. That dependency has since resolved; phase 2b later shipped in PR #339.
- **Phase 2a, Phase 3** — independent surfaces, no impact.

## Decisions made

1. **Phased delivery.** Historical sequence: Phase 1 in PR #312, phase 2a in PR #314, phase 3a in PR #316, phase 3b.1 in PR #328, phase 2b in PR #339, and phase 3b.2 / 3b.3 in PRs #336 / #337.
2. **`.NET` accepts F# (`.fsproj`) and VB (`.vbproj`).** Strictly more generic than csproj-only.
3. **Deno precedes `package.json`** in the cascade by the same logic as Bun.
4. **CMake `build_cmd` chains configure + build** (`cmake -B build && cmake --build build`); `test_cmd` is `ctest --test-dir build`. Aligns with hashd's build-then-test sequencing.
5. **`build_cmd` is empty for install-only or platform-specific ecosystems** (PHP, Ruby, Flutter).
6. **Haskell splits into `haskell-stack` and `haskell-cabal`** as distinct `DetectedSystem` values because `test_cmd` differs.
7. **Flag name `--suggest`** for AI-assisted detection. Matches existing precedent on `wf project describe --suggest` and `wf project tech --suggest`.
8. **REST extension, not a new endpoint.** `POST /projects/detect` gets a `suggest: true` body field.
9. **No `--no-tests` flag** for phase 2. Warn, don't block.
10. **No cost estimation** ever. Token usage only, via existing `agent_calls`.
11. **Default agent for `detect` stage: `claude` with Sonnet-class model.** User-configurable per project via `stage_agents.detect`.
12. **No arbitrary caps.** Only runaway guards: 10 min operation timeout, ~100k token ceiling.
13. **Agent tools:** read + directory listing + glob. No shell.
14. **Output contract:** JSON validated by the Go detect parser.
15. **Progress events:** tool-level granularity on the ZMQ project bus.
16. **Multi-repo parallel** for AI-assisted detection. Verified no shared mutable state.

### Phase 3b-specific decisions

17. **Sync, not async.** The CLI blocks on detect completion so the user can review/accept/edit/reject inline. No pending-suggestion queue, no post-hoc apply surface.
18. **TTY-driven watching, no `--watch` flag.** Interactive mode streams progress; non-interactive (`-y`) mode runs silent and auto-applies. No flag to toggle — `os.isatty(stderr)` is sufficient signal.
19. **Dispatch-as-named, review-in-named-order** for multi-repo. Each repo's detect fires when the user types the repo name; review phase walks repos in naming order. Parallel wall-time, deterministic review ordering.
20. **Concurrency cap 5** via `stages.detect.max_concurrent`. Default in `defaults.yaml`, per-project override in `config.yaml`. No CLI flag.
21. **Silent during dispatch phase.** The CLI renders nothing about detection while the user is still naming repos. All progress surfaces during the review phase.
22. **Approval keystrokes: `a` / `e` / `r`.** Accept / Edit per-field / Reject-to-heuristic-fallback. Enter = accept. Edit mode prompts `test_cmd` and `build_cmd` only; `detected_system` is metadata, `justification` is read-only.
23. **Ctrl-C cancels the Prefect flow(s) and aborts the interview.** Not "detach only." Simple, matches user expectation.
24. **10 min timeout per repo, fall back to heuristic silently.** Print a `wf project interview --suggest` retry tip in interactive mode. Same timeout as the stage cap.
25. **SSE through the server, not direct ZMQ in the CLI.** Reuses the existing SSE infrastructure from PR #304; no new network pattern in the CLI binary.
26. **`DetectFileRead` emitted via Claude Code's `--output-format stream-json`.** The detect stage switches from `--output-format json` + `subprocess.run` to `--output-format stream-json` + `subprocess.Popen` with line-buffered reads. Each tool-use message becomes a `DetectFileRead` event. Fallback position: clock-only progress if stream-json parsing turns out finicky.

## Open questions / future work

- Lua (rockspec), R packages (`DESCRIPTION`), PowerShell, Nim (`*.nimble`), Crystal (`shard.yml`), OCaml (`dune-project`) — trivial additions if users request.
- Reporting UI for `agent_calls` aggregates (per-project, per-workstream, per-story token usage). Schema supports it; no dashboard today.
- Multi-repo v2 prompt-template sharing — revisit when multi-repo v2's Phase 1b AI-integration lands; they consume the same `detect` stage and may want to extend the prompt seed context.
- SSE endpoint `detect_id` filter — audit the existing SSE endpoint (PR #304) to verify it filters by `detect_id` or by event type + project.
- `wf project tokens` command — shared future dep with multi-repo v2 for reporting `agent_calls` roll-ups. Neither design depends on it for current phases.
