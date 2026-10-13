# Agent Management

## Agent-driven Project Add

For scripted onboarding, agents should treat `hashd project add` as a two-step flow:

```bash
hashd project add /path/to/repo --no-interview --suggest
hashd project add /path/to/repo --no-interview
```

The first command runs investigation only. It prints the canonical settings block, stores those proposed settings in the project-add cache, and exits without modifying project state.

The second command reuses the stored defaults, applies any explicit flag overrides, prints the same canonical settings block again, and then executes project add.

Use explicit flags on the second command when the proposal needs correction, for example:

```bash
hashd project add /path/to/repo --no-interview \
  --description "Payments API" \
  --git-name "Alice" \
  --git-email "alice@example.com"
```

Interactive operators can still use:

```bash
hashd project add /path/to/repo --suggest
```

That runs the same investigation, stores the defaults, and then opens the wizard with AI-prefilled values.

## Switching Agents

### See what's installed

```bash
hashd agents
```

Shows all 7 registered agents (Claude, Codex, Gemini, OpenCode, Kimi, Qwen, Copilot): whether each binary is installed, where it was found, and the health of any credential registered with the server. It does not list stages -- `hashd project config get stage_agents` shows the effective per-stage assignments.

### Per-stage assignment

Each workflow stage has a "shape" describing the invocation it needs. Assign an
agent that supports that shape; `*_resume` stages inherit their base stage's agent.
`hashd project config get stage_agents` (or `show stage_agents`) lists the agent each stage launches and the entry that chose it; `config list` shows only the raw entries, which role entries make an incomplete answer.

```bash
# Assign gemini to the breakdown stage
hashd project config set stage.breakdown gemini

# Assign claude to review
hashd project config set stage.review claude
```

Resume stages are not separately configurable. A `*_resume` stage continues a session its base stage opened, and that session id is specific to the agent that minted it, so `review_resume` always runs on whatever `review` runs on. It has no agent key of its own at any layer: the agent comes from the base stage's ladder alone, role entries included -- project `stage_agents.review` > project `stage_agents.reviewer` > system `stage_agents.review` > system `stage_agents.reviewer` > the stage's `default_agent`. `adjudicate` and `scope_adjudicate` add two rungs before their default, project then system `stage_agents.reviewer`, so they fall back to the reviewers' agent when nothing names theirs. A matched entry whose agent is unknown or has no shape for the stage leaves the stage on its default rather than falling to a lower rung. The full ladder is in [WF.md, Stage-agent roles](../WF.md#stage-agent-roles). Assigning a base stage therefore carries its resume with it, and a write to a resume stage's agent key is refused.

A `stage_agents.<x>_resume` entry left in an existing config file loads without error and is ignored: nothing rewrites the file, and there is no migration for it. Reset still accepts those keys on purpose, so clear a leftover with `hashd project config reset stage_agents.<x>_resume`, or `hashd config reset stage_agents.<x>_resume` for a system-level one. The refusal a write returns names that same command.

Validation prevents incompatible assignments: an agent must support the shape of every stage it is assigned, including the resume shape its base stage implies.

### The web Settings > Agents panel

The panel lists every stage the server declares, grouped under its phase, with the agent in force on each and whether this project pinned it. A stage nobody has configured is a row like any other: it shows what it inherits and its picker writes `stage_agents.<stage>` when used. Rendering the page writes nothing -- showing a stage the agent it inherits is a statement about today, not an instruction to freeze it at that value.

Choosing an agent on a PHASE is an explicit instruction about that phase's whole subtree, so it writes one key per configurable stage in the phase: the ones running a default, the ones inheriting, and the ones already set to something else. Sibling phases are untouched, and a `*_resume` row is never written -- it follows its base stage, which is in the same phase. The phase picker's inherit row is the reverse verb: it removes this project's pins across the phase and touches nothing that has none. Each stage is its own config write, so a phase the server refuses partway reports which stages moved and which did not.

The panel makes two reads and needs both: `/config/show` for `stage_agents`, which alone says which entries this project owns, and `/stage-agents` for the roster. If either fails the panel reports the stages as unknown and draws no list, rather than presenting the half it got as the whole; a phase write refuses before touching anything, because assigning off a fragment would cover the stages some layer happened to name and report the phase assigned.

`GET /projects/{name}/stage-agents` is the read behind the "runs on" column. It reports, per declared stage, the agent that will actually launch, where it came from (`agent_key`, the `stage_agents` key that chose it -- the stage's own key, the base stage's on a resume row, or a role key such as `stage_agents.reviewer` when a role entry chose it; empty when the stage runs its default -- and `agent_layer`, `project`, `system` or `default`), which role chose it (`agent_role`, present only when a role entry did), whether an adjudicator stage is borrowing the reviewer role's agent because nothing chose one for it (`reviewer_fallback`), and the default the stage falls back to. All of it comes from `agents.EffectiveStageAgents`, the layered resolver that reads the system and project layers separately -- the same resolver `buildStageCommand` and dispatch preflight use. The merged config cannot answer this: a hand-edited `stages.<name>.default_agent` is inert, and an assignment whose agent has no shape for the stage leaves the stage on its default (`stages-use` accepts exactly that, with a warning). Where the configured agent and the resolved one disagree, the panel keeps showing the setting in the picker -- it is the key that control writes, and the one to remove -- and states the agent that actually runs beside it.

Assignments are validated against the agent registry before they are saved.

Agents with `available` status (not yet verified with hashd) require `--force`:

```bash
hashd project config set stage.breakdown gemini --force
```

### Bulk assignment by role

Every configurable stage belongs to exactly one role, and a resume stage follows its base stage's role:

| role | stages |
|---|---|
| `planner` | `breakdown`, `browser_classify`, `chat`, `concern_triage`, `detect`, `plan_add`, `plan_split`, `pm_annotate`, `pm_describe`, `pm_discovery`, `pm_docs`, `pm_edit`, `pm_refine`, `pm_route`, `pm_spec`, `tech_tree` |
| `coder` | `fix_from_review`, `fix_generation`, `implement` |
| `reviewer` | `final_review`, `review` |
| `reviewer_adjudicator` | `adjudicate`, `scope_adjudicate` |

```bash
# Set the planner role's stages to gemini
hashd project config set planner gemini --force

# Set the coder role's stages to claude (implement_resume follows implement)
hashd project config set coder claude
```

A role write stores one `stage_agents.<role>` entry; an existing stage pin keeps outranking it, and the write warns about each entry that does. With no `adjudicate`, `scope_adjudicate` or `reviewer_adjudicator` entry in either layer, the adjudication stages fall back to the `reviewer` agent, so a `reviewer` write must also suit them.

A `stage_agents.<name>` or `stage.<name>` write naming neither a stage nor a role is refused with a "Did you mean" for the nearest stage and the nearest role, plus the valid names of both: `set stage_agents.reviewerr codex` suggests `review` (a stage) or `reviewer` (a role). An unknown agent name is refused with the nearest agent suggested. If the agent does not support every stage shape the key covers -- for a `reviewer` write, the adjudication stages falling back to it included -- the assignment is rejected. `hashd doctor` reports a `stage_agents` entry already in project or system config that names neither a stage nor a role, with the same suggestion.

### Stage reference

The [stage-to-shape registry](../server/internal/agents/runner.go) (`stageShapeMap`)
defines each stage's required invocation shape.
[defaults.yaml](../server/internal/config/defaults.yaml) defines default agents
and their commands. `hashd project config list` shows effective configuration;
`hashd agents` shows installed binaries and credential health.
See [WF.md](../WF.md) for workflow roles and transitions, and
[README: Directives](../README.md#stage-scope) for directive stage groups.

### Agent shape support

Which agents can serve which stage shapes, as declared by `agents.<name>.shapes` in the built-in defaults:

| Agent | print | json | edit | review | review_resume | implement | implement_resume |
|-------|-------|------|------|--------|---------------|-----------|-----------------|
| claude | x | x | x | x | x | x | x |
| codex | x | x | x | x | x | x | x |
| gemini | x | x | x | x | x | x | x |
| opencode | x | x | -- | x | x | x | x |
| kimi | x | x | x | x | x | x | x |
| qwen | x | x | x | x | x | x | x |
| copilot | x | x | x | x | x | x | x |

### Restoring defaults

Reset a single stage assignment:

```bash
# Reset review back to default agent
hashd project config reset stage.review
```

Reset all stage assignments:

```bash
# Reset stage assignments only; preserve other project settings
hashd project config reset planner
hashd project config reset coder
hashd project config reset reviewer
hashd project config reset reviewer_adjudicator
```

Use `hashd project config diff` before resetting to inspect which project overrides will be cleared. `hashd project config show <key>` shows the effective value and Default/System/Project stack for one setting.

Nuclear option -- reset all behavioral overrides (stage assignments, autonomy mode, etc.) back to defaults:

```bash
hashd doctor --reset-to-defaults
```

This preserves identity and build settings (name, repo_path, test_cmd, etc.) but strips stage_agents and other behavioral overrides.

### Per-stage models

The CLI/API and TUI Project Configuration editor expose `stages.<stage>.model`
for stages that declare a model. System settings are inherited by projects;
project settings override them. Resume-stage models are independent of their
base stage's model (unlike agent assignments).

```bash
hashd config set stages.review.model claude-sonnet-5
hashd project config set stages.review.model claude-opus-5
hashd project config reset stages.review.model  # inherit the system value again
```

These settings apply on the default-agent path only. An explicit agent
assignment, even to the default agent, instead uses that agent's registry model
default. Model IDs are strings: `null` is a literal ID, not a reset. An
explicitly empty model omits the model flag; reset removes the override. The
Web Agents panel edits agent assignments; it does not currently provide model
controls.

`stage_models` and `stage_effort` set a stage's model and reasoning effort on
either path. They are keyed by stage or role and resolve on the `stage_agents`
ladder; a resume stage follows its base stage's key:

```yaml
stage_agents:
  reviewer: codex
stage_models:
  reviewer: gpt-6.1-sol
stage_effort:
  reviewer: high
```

Set, read and reset an entry at system or project scope, by stage or role:

```bash
hashd config set stage_models.reviewer gpt-6.1-sol
hashd config set stage_effort.reviewer high
hashd project config set stage_models.review gpt-6.1-sol
hashd project config get stage_models.review
hashd project config reset stage_models.review  # clears exactly this entry
```

A write is refused for an unknown stage or role, for a resume stage (set its
base stage instead), and for an empty value. Model IDs are stored as strings.
A write is in force at the next stage launch, without a restart, and
`hashd config get stage_agents` shows each stage's effective model and effort.

A write is also checked against the agents it would configure, before anything
is stored. It covers the stage and its resume stage for a stage key, the role's
stages and their resume stages for a role key, and `adjudicate` and
`scope_adjudicate` too for a `reviewer` key. Each covered stage is resolved as
the runner resolves it, on the layers as the write would leave them: a project
write against system and project config, a system write against system config
alone. Where the written entry applies under the rung rule below, the write is
refused when:

- the stage's launched command has no slot for the value: its agent declares no
  `model_template` / `effort_template`, or the command lacks `{model}` /
  `{effort}`, as on a stage `stage_agents` moved to claude
- an effort is not one of the effective agent's accepted levels:

| Agent | Accepted `stage_effort` levels |
|---|---|
| claude | `low`, `medium`, `high`, `xhigh`, `max` |
| codex | `low`, `medium`, `high` |
| others | none: no effort slot |

A covered stage where the entry does not apply is not checked; the write is
stored with a warning naming the stage and the `stage_agents` entry and layer
that chose its agent. Model names are never checked against a provider.

An entry applies only at or above the rung of the `stage_agents` entry that
chose the stage's agent; a stage on its default agent takes any rung. A stage
pinned by its own entry ignores its role's entry, an agent chosen by a project
role entry ignores system entries, and an adjudicator takes the `reviewer`
entries only when its agent came through the reviewer fallback or it is on its
default agent. Where a `stage_models` entry applies it outranks
`stages.<stage>.model`; the two coexist because `stages.<stage>.model` names a
model for the stage's own command and does not follow it onto another agent.
With no entry, effort is the stage's declared effort on the default agent and
the agent's registry `effort` after a reassignment.

A value is sent only where the launched command has a slot: the command carries
`{model}` / `{effort}` and the agent declares `model_template` /
`effort_template`. Claude's shapes carry neither placeholder, so a stage
reassigned to claude sends no model or effort; gemini, kimi, qwen and copilot
declare no templates. A value with no slot sends nothing and is reported as not
applicable.

### Direct config editing

All stage overrides can also be set by editing `config.yaml` directly. See `../config.sample.yaml` in the repo root for all available settings with commented-out examples, including common recipes like using Claude for implementation or switching models.

---

## Authentication

Most CLI coding agents support both OAuth (interactive login) and API key authentication. When both are configured, agents differ on which takes precedence -- leading to silent auth failures or unexpected billing. Hashd verifies auth by delegating to each agent CLI's own status command and only strips API-key env vars when the project explicitly forces OAuth mode.

### Auth mode

Set with `hashd project config set auth-mode <mode>`:

| Mode | Behavior |
|------|----------|
| **auto** (default) | Preserve API keys; verify auth through the agent CLI's status command |
| **oauth** | Strip API keys for agents where key overrides OAuth |
| **api-key** | Preserve API keys |

Most users should leave this at `auto`. It avoids guessing from private credential files and lets the agent CLI choose the active auth mode. Use `oauth` only when you deliberately want hashd to remove API-key env vars before invoking agents where keys override OAuth.

### Per-agent auth behavior

Each agent handles the OAuth/API-key conflict differently:

| Agent | Key overrides OAuth? | What hashd does | verify_auth command |
|-------|---------------------|-----------------|---------------------|
| **Claude** | Yes (`ANTHROPIC_API_KEY` wins) | Keeps key in `auto`; strips key in `oauth` | `claude auth status` |
| **Gemini** | Yes (`GEMINI_API_KEY` wins) | Keeps key in `auto`; strips key in `oauth` | Not declared; no verified non-interactive status command |
| **Codex** | No (OAuth wins) | Nothing to strip | `codex login status` |
| **Kimi** | No (OAuth wins) | Nothing to strip | Not declared; no verified non-interactive status command |
| **Qwen** | Mutually exclusive | Nothing to strip | Not declared; `qwen auth status` always exits 0 since qwen-code v0.15.11 |
| **OpenCode** | Provider-specific | Nothing to strip | Not declared; no single status command covers every provider |
| **Copilot** | N/A (token hierarchy) | Nothing to strip | `gh auth status` |

### Login and logout commands

| Agent | Login | Logout |
|-------|-------|--------|
| Claude | `claude` (opens browser) | N/A |
| Codex | `codex login` | `codex logout` |
| Gemini | Interactive `/auth` in TUI | Interactive `/auth signout` in TUI |
| Kimi | `kimi login` | `kimi logout` |
| Qwen | `qwen auth` | `qwen auth` (select different method) |
| OpenCode | N/A (set env vars) | N/A |
| Copilot | `copilot login` | `copilot logout` |

### Per-user credentials (team servers)

On a team server, agents run on the server but the work belongs to individual users -- so runs act as the **workstream owner**, using a credential that user registered:

```bash
hashd agents login <agent>     # register your credential with the server
hashd agents logout <agent>    # remove it
hashd agents                   # shows your registered credentials and their health
```

Login harvests the credential from your own machine where the agent has a sanctioned artifact, and prompts for a paste otherwise. Secrets are read hidden on a TTY or piped on stdin -- never passed as flags. The server validates the credential shape at registration (a wrong paste fails immediately with the fix named), stores it encrypted at rest, and never returns it.

The TUI has the same surface: press `s` on the dashboard for Settings -- view credential health, register or replace a credential (paste into a masked field, or Lift to pull it from this machine's env vars / agent credential files / the gh CLI), remove one, and change the autonomy mode.

| Agent | What you register | Subscription supported? |
|-------|-------------------|------------------------|
| **Claude** | `claude setup-token` output (or an API key with `--method api-key`) | Yes; tokens last about a year |
| **Codex** | Your `~/.codex/auth.json` (run `codex login` first), or `--method api-key` | Yes. After uploading, run `codex login` again locally -- the server's copy becomes the live one, and sharing one login between laptop and server breaks both |
| **Gemini** | Your `~/.gemini/oauth_creds.json`, or `--method api-key`. Workspace accounts add `--project <id>` | Yes; agent runs burn quota fast, so expect a paid tier |
| **Copilot** | `gh auth token` output (harvested automatically), or a fine-grained PAT with the "Copilot Requests" permission | Yes; classic `ghp_` tokens are rejected -- the Copilot CLI silently ignores them |
| **Qwen** | An API key plus `--base-url` (Coding Plan or any OpenAI-compatible endpoint) | Key-based only; the free OAuth tier was discontinued upstream |
| **Kimi** | A Moonshot platform API key plus `--model` | Key-based only today |
| **OpenCode** | A provider API key plus `--model <provider>/<model>` -- OpenCode is multi-provider, so the model's provider half is what the key authenticates against | Key-based only; subscription logins route through OpenCode's own auth store, and Anthropic prohibits Claude subscription OAuth in third-party tools |

Behavior at run time (registered-credential-wins):

- A registered credential is always injected for your runs, in both deployment modes, and overrides the server host's own environment.
- Single-user mode with nothing registered keeps today's behavior: the host's own agent auth.
- Team-server runs on an owned workstream **refuse to dispatch** when the owner has no live credential for the run's agents. The refusal names the exact command to fix it.
- When a run proves a credential dead (expired, revoked, or a token-rotation conflict), the server records it: the next dispatch fails instantly with the recovery steps instead of burning another run. Re-registering clears the state.

An OpenCode credential is injected differently from the others, and the difference is worth knowing when reading a run: the server hands OpenCode a complete one-provider auth store on `OPENCODE_AUTH_CONTENT` and pins the model on `OPENCODE_CONFIG_CONTENT`. Verified against OpenCode 1.18.31: the injected store **replaces** the host's `~/.local/share/opencode/auth.json` for that process (and is never written back to disk), and it **outranks a provider key in the ambient environment** -- with the host's own `OPENAI_API_KEY` exported and a different key injected, the request that reached the provider carried the injected one. The model pin is load-bearing rather than cosmetic: OpenCode also picks providers up from environment variables the host exports, so an unpinned model could select one of those instead of the registered credential. Nothing is materialized on disk, so OpenCode is the one registered agent with no per-user agent home.

**Known gap: OpenCode config files can override or redirect the registered key (unresolved).** Tested against OpenCode 1.18.31, offline, with dummy keys only. The injected auth store does **not** outrank OpenCode's *config files*. The server's pin covers only the model, so a `provider` section in any config source OpenCode loads still applies. Per OpenCode 1.18.31's source, those sources are:
- the project's `opencode.json` / `opencode.jsonc`, looked up from the run's directory to the worktree root, and those in its `.opencode/` directories;
- the server host's global config directory (`~/.config/opencode/`: `config.json`, `opencode.json`, `opencode.jsonc`);
- a file named by `OPENCODE_CONFIG`.

The project `opencode.json` and the host's global `opencode.json` were tested. The other sources are merged the same way in OpenCode's source, but were not separately tested.

In OpenCode 1.18.31:
- **A config `apiKey` replaces the registered key.** A `provider.<provider>.options.apiKey` in any of them is sent instead of the user's registered key. With it in the host's global config, a team-server run on an owned workstream acts as the host's key, not the owner's.
- **A config URL redirects the registered key.** A `provider.<provider>.options.baseURL`, or a per-model `models.<model>.provider.api`, in any of them sends the user's registered key to that URL. Anyone who can commit `opencode.json` to the project repository can therefore redirect a registered key to an endpoint they choose.

Hashd does not currently prevent or detect either case: no config isolation, and no pre-launch check. Until that changes, treat OpenCode registered keys as exposed to whoever controls any of those config sources. Review all of them for `provider` settings before registering an OpenCode key on a shared server, and keep reviewing them: every run reads them afresh, so a change made after registration, such as a commit to the repository, applies to the next run. Other OpenCode versions were not tested.

A startup verification has been proposed: confirm which credential and endpoint OpenCode actually resolved, and refuse the run when they are wrong. **It is not implemented.** For it to be sound, the effective key source *and* destination must be inspected deterministically, through a supported mechanism, before any provider request. Asking the model which key it used is not verification, and probing a live request could itself send the key to the redirected endpoint. OpenCode 1.18.31 has no supported command that reports the effective key source and destination together:
- `opencode debug config` prints merged config values, secrets included;
- `opencode providers list` shows only the auth store and environment variables.

The server never installs, pins, or updates agent binaries -- installing agents on the server is the operator's job, and a dispatch whose agent is missing is refused with the install command.

### Diagnostics

Preflight verifies assigned agents before a workstream runs. Agents with `verify_auth` use the CLI-owned status command, so new provider auth modes are recognized without hashd parsing credential files. If the command exits non-zero, hashd surfaces a Diagnostic naming the agent, command, and stderr/stdout excerpt.

### Common scenarios

**"I only have an API key (no OAuth)"**

It just works. `auto` mode keeps the API key in the environment.

**"I use OAuth but also have an API key in my shell"**

`auto` mode keeps the API key and lets the CLI decide. If you want OAuth to win for agents where keys override OAuth (Claude, Gemini), set:

```bash
hashd project config set auth-mode oauth
```

**"I want to switch from OAuth to API key"**

```bash
hashd project config set auth-mode api-key
```

This is equivalent to `auto` for current env handling, but documents the operator intent that API keys should stay in the agent environment.

**"Codex/Kimi ignores my API key"**

These agents prefer OAuth when both are present. Hashd can't change this via environment manipulation. You need to clear the OAuth session:

```bash
# For Codex
codex logout

# For Kimi
kimi logout
```

**"Claude auth fails after I changed nothing"**

Your OAuth token may have expired. If preflight reports the agent is not authenticated, run the agent's status command directly; for agents with `verify_auth`, hashd uses that same command. Re-authenticate:

```bash
claude
```

This opens the browser login flow and refreshes the token.

### Environment variables

Hashd always strips `CLAUDECODE` from the subprocess environment for all agents. This prevents nested Claude Code session interference when spawning agents from within a Claude Code terminal.

Hashd sets `IS_SANDBOX=1` in every agent subprocess environment. The variable is scoped to the spawned agent process; it is not exported into operator shells or written to global toolchain configuration. Agents should treat their current working directory as ephemeral, avoid reaching outside the assigned worktree unless the operator supplied an explicit path, and avoid mutating global toolchain state.

The following API key env vars are stripped only when `auth_mode` is `oauth`:

| Env var | Stripped when | Agent |
|---------|-------------|-------|
| `ANTHROPIC_API_KEY` | mode is `oauth` | Claude |
| `GEMINI_API_KEY` | mode is `oauth` | Gemini |
| `GOOGLE_API_KEY` | mode is `oauth` | Gemini |

---

## Prompt Management

### How prompts work

All LLM prompts live in `prompts/*.md` as templates. They use `{{ variable }}` placeholders for dynamic content; see [Composing prompts](#composing-prompts) for conditionals, includes and literal braces. HTML comments (`<!-- ... -->`) are stripped before sending to the LLM.

Prompts are loaded and rendered by `server/internal/prompts`:

```go
prompt, err := prompts.Render(promptsDir, overridesDir, "implement", vars)
```

### Composing prompts

Strongly prefer `include_<role>_<concern>.md` for reusable sections, or
`include_<concern>.md` when role-independent. This is a naming convention, not
a requirement: existing names remain valid. Share repeated instructions and
response contracts; keep each task's scope and authority in its main template.
Keep code and testing guidance in separate sections.

Keep prompt instructions in Markdown; Go selects sections and supplies data.
Retry verdicts select `include_implement_feedback_*.md` through the same loader
and override rules; FIX generation selects `include_fix_generation_repair_ruling.md`
only when it carries out a repair ruling, so its prompt without one is unchanged.
A `fix_generation` override without `{{ repair_ruling_section }}` refuses a ruling
instead of dropping it. A FIX whose merge-gate binding stored its ruling gives
its implementer and reviewer `include_repair_ruling_evidence.md`: the ruling,
the failed command, the tested revision and the complete stored output. It
rides the implementer's `{{ fix_requirements_section }}` and the reviewer's
`{{ repair_ruling_section }}` (contextual and closed-list reviews), and an override
without that placeholder refuses the FIX the same way. Both ruling sections
include `include_repair_ruling.md`, so the FIX generator, implementer and
reviewer read the same verdict directions. Findings and rulings are passed in
full, not clipped to a size budget. Scope and severity filters select relevant records; they are not
length limits. Do not inject raw agent/tool transcripts in place of terminal
summaries or repeat a FIX description as its own reviewer feedback.

Final review, FIX, and test/review adjudication share `prompts.InlineDiff`:
include the whole patch below 1,000 lines, otherwise omit it entirely. Keep the
exact Git comparison and complete changed-file inventory either way. Shared
reading guidance lives in `include_branch_diff.md`; each main prompt owns scope.

Prompts are Gonja (Jinja2) templates. `{{ name }}` inserts a variable; a
variable the template uses but the caller does not supply fails the render
instead of rendering empty. `{% if name %}...{% else %}...{% endif %}` selects
a section; an empty string is false. A template includes another file
directly:

```markdown
<!-- Composition: shared response contract; task-specific scope stays here.
     Shared-section naming is strongly encouraged, not required. -->
{% include "include_implement_output.md" %}
{% include "/path/to/prompts/team_rules.md" %}
```

Relative paths resolve from the containing template's directory, including
nested includes. Within the shipped/project prompt directories, matching
project files take precedence and missing overrides fall back to shipped files.
Absolute paths select the exact file on the **server**, without override lookup.
All files must be within the configured shipped or project prompt directories.
Traversal outside those directories is rejected. Relative symlinks confined to
their prompt directory work; absolute or escaping symlinks are rejected.
User-created files need no registration or shipped counterpart to be included.

An include path must be a string literal. Included files are rendered in
place with the parent's variables; an include in a false `{% if %}` branch is
never read. Whitespace, including the newline after a block tag, is preserved.
Single braces, as in JSON examples, are literal text. Write a literal `{{`,
`{%` or `{#` as a string expression (`{{ "{{" }}`) or inside
`{% raw %}...{% endraw %}`. HTML comments are stripped from each file as it is
read, so they neither render nor trigger includes; the top-level template also
loses its leading whitespace. Variable values are inserted verbatim and never
parsed as template syntax. No shell expansion or commands are supported.

Missing/unreadable files, malformed includes, and circular references fail
with the include chain. Expansion is bounded to 64 files deep and 8 MiB of
source text per load, counting repeated includes. File reads use Go's
directory-confined `os.Root` API to enforce the include boundary.

Document composition and required variables in the main template's HTML
comment. Adding or rearranging includes needs only Markdown edits. Raw
show/edit/diff/reset operations do not expand includes. Shipped includes retain
their defaults and use the existing named override/reset mechanism; resetting
a parent alone does not reset overrides of its shared files.
The prompt list omits conventionally named `include_*` files; named show, edit,
diff, and reset still accept shipped includes. Other include names remain valid
for composition, without special catalog treatment.

### Code and testing guidance

Each role has separate `include_<role>_code_reuse.md` and
`include_<role>_testing.md` files. Main templates retain task scope, execution
limits, and output contracts; shared guidance does not expand their authority.

| Role | Main templates using both includes (`.md`) |
|------|-------------------------------------------|
| `implement` | `implement`, `implement_fix`, `implement_retry`, `implement_resume_crash`, `conflict_resolution` |
| `review` | `review_contextual`, `review_round_resume`, `review_closed_list`, `final_review` |
| `planner` | `plan_discovery`, `refine_story`, `edit_story`, `plan_split`, `tech_tree`, `concern_triage` |
| `breakdown` | `breakdown`, `plan_add`, `fix_generation`, `fix_from_review` |

The four review templates also share `include_review_scope.md`: judge requested
behavior, regressions, and unnecessary additions without expanding the task.
The closed-list template retains its narrower carried-findings/new-breakage
limit; shared guidance never reopens it.

The three per-commit review templates also share
`include_review_accepted_deviations.md`: optional explanations of justified
departures from the commit description, passed to final review as context,
not findings or changes to ACs. Format repair preserves them when present.

Partial breakdown uses `breakdown`; warm/cold final-review task generation uses
`fix_from_review`. Format-only retries (`review_repair`, `planner_retry_resume`,
`review_adjudicate_reauthor`) retain the existing assessment/task, not a new
engineering rubric; a resumed `pm_refine` retry also carries the story size
guidance at the current setting. Judges, operator-ruling translation, project descriptions,
routing, chat, and SPEC updates keep their specialized prompts. Keep this map
current when adding an entry point; do not copy the guidance into directives.

### Prompt-to-stage mapping

#### Implementation pipeline

| Prompt | Used by | Purpose |
|--------|---------|---------|
| `implement.md` | implement | Main implementation prompt for micro-commits |
| `implement_retry.md` | implement (resume) | Shorter prompt for session resume after review rejection |
| `implement_review_context.md` | implement | Previous review output context |
| `directives_section.md` | agent prompts | Shared operator directives section |
| `concern_triage.md` | concern_triage | Triage pending review concerns against next micro-commit |

#### Review pipeline

| Prompt | Used by | Purpose |
|--------|---------|---------|
| `review_contextual.md` | review | Context-aware review with tool access |
| `review_round_resume.md` | review (resume) | Re-review round in the resumed reviewer session |
| `review_repair.md` | review + final_review (resume) | Redraft of an unusable review response (schema/verifier) |
| `review_closed_list.md` | review (judged retry) | Closed-list grading after the review-conflict judge's CARRY |
| `review_history.md` | final_review | Previous review cycles section |
| `final_review.md` | final_review | Holistic branch review before merge |
| `final_review_delta.md` | final_review (after a FIX) | Delta round: checks the FIX commits answer the last verdict's findings |
| `browser_classify.md` | browser_classify | Boolean browser relevance check before story planning, implementation, per-commit or final review |

Story planning, implementation, per-commit and final review can use an installed [Playwright CLI](https://github.com/microsoft/playwright-cli)
and its matching Chromium on the agent host. Hashd does not install them during
an agent invocation. CLI detection precedes the `browser_classify` call (Haiku by default,
configured through the existing stage settings). The classifier receives the
whole story and human guidance and returns `{"browser": true}` or `{"browser": false}`.
The first successful decision is saved in the story's existing data as
`browser_classification`, including `false`, and reused across planning, implementation,
reviews, runs and restarts. No lifecycle state or human decision is added.
Failed classification and missing tools do not save a negative result. Cloned
stories start unclassified; legacy workstreams without a story classify per
invocation. Prompt-only rendering makes no call.

Story planning (`pm_refine`) offers access with “A browser is available if useful
for planning.” It adds no browsing checklist or required evidence. Classification
uses the incoming story/request; its existing planning execution claim guards the
saved decision. Setup fits within the current activity budget, reserving the
planner's timeout and browser close allowance; insufficient budget skips access.
Each attempt owns its browser and temporary captures, including native resume
and cold fallback. Retries retire previous sessions. Breakdown and story editing
do not acquire browsers through this path.
The prompt requires JSON only; the parser also accepts one complete JSON object
inside fences or surrounding prose. Missing/non-Boolean fields, extra keys,
multiple objects and partial JSON produce a warning rather than a guessed decision.

The source and wheel installers download a private Node runtime, locked
Playwright CLI and matching Chromium into the managed tools directory; browser
payloads are not in the wheels or project dependencies. Remote-only client
installs skip this download. Installation launches Chromium, clicks a local
test page and captures a screenshot before publishing the executable. A failed
upgrade retains the previous runtime. No administrator commands run implicitly:
missing Linux shared libraries appear in the installation error, and browser
validation stays unavailable until the operator fixes them and reruns installation.
Browser OS support follows Playwright (currently macOS 14+ and supported
Debian/Ubuntu releases), without raising Hashd's own minimum requirements.

The server and `hashd doctor` resolve the managed executable, independent of
shell PATH. The agent receives its resolved absolute command, so an installer
upgrade cannot switch versions mid-session. Doctor checks the CLI version;
installation and actual session startup check that Chromium can launch. Old
runtime directories remain available for in-flight sessions; they are not
deleted during upgrades. Dependencies refresh before minor/major release
candidates are tested; patch releases retain their tested dependency set unless
a security or bug fix requires an update.

Only a positive classification and successful private browser launch enable
`include_review_browser.md`. This adds a best-effort behavioral/visual check,
including available design guides and existing precedent. Agents try documented
development or test-harness commands, first establishing safe cleanup, and stop
only the services they started—never shared services or processes by name/port.
They do not improvise infrastructure or repair the environment. Unavailable browser/app access produces
a separate `browser_warning`, not a finding or verdict change. Observed defects
use normal findings within the review's existing scope. Fresh, resumed and
closed-list per-commit reviews share the same include; the closed list still
bounds what may be raised. Review judges are unchanged.

Implementers use `include_implement_browser.md`, sharing the same session/startup
instructions with reviewers. Fresh implementation, FIX, review-retry and
crash-resume prompts receive the current session and ask the agent to exercise
the changed UI, inspect screenshots, fix in-scope visual/behavioral defects and
check again. Native resume and its fresh fallback share one browser; a later
activity gets a new one. A negative classification loads no browser guidance.
Missing tools, classifier failures and launch failures leave a warning in the
implementation transcript and append-only run log without blocking work. The implementer
reports checks or skipped validation in its existing notes; no result field is
added. These captures are temporary under `browser/implement-*`: completion,
failure or cancellation closes the session, preserves its lifecycle log and
removes scratch. The implement timeout plus 30 seconds bounds an orphaned
browser's idle lifetime. The implement activity additionally reserves the
configured classifier budget and bounded browser startup/cleanup time, preserving
the implementer's own timeout and reporting buffer. Optional setup skips or
stops early if an older recorded activity budget or a later config change leaves
insufficient time. Selected story-image attachments remain final-review-only.

Each review round owns one headless, in-memory browser session across its
redrafts and any cold fallback. Resuming the reviewer in a later round opens a
new browser; it never reuses the previous round's session or warning. Browser
warnings survive schema/verifier redrafts and are stored separately from
findings in the review record. Hashd closes that session on completion, error,
or cancellation; the CLI's idle timeout (the review or final-review timeout
plus 30 seconds; resumed attempts inherit their base stage's timeout) bounds
leftovers after a host-process crash. Per-commit artifacts remain under the run's
`browser/review-*` directory.

Final review additionally receives the short screenshot-attachment skill in
`include_final_review_images.md`. The reviewer explicitly selects a PNG and
caption through `hashd internal review-attach-image`; selecting none is valid.
The template checks that its optional attachment command is defined, so an
older server reading the updated template skips this skill until upgraded.
The supplied Unix socket belongs to that invocation, is inside a private
directory, and closes when the review ends. The helper cannot choose a story or
permanent destination and does not open the database. It submits the filename
to the owning server, which reads only a regular file within that review's
scratch directory, validates the PNG, and copies it into
`<project-ops>/artifacts/stories/<story>/reviews/<browser-session>/images/`.
Server-generated filenames and content digests identify the immutable captures.
Selections exceeding 32 MiB or 32 million pixels fail explicitly, without
truncation. This is confined attachment handling, not a filesystem sandbox for
an agent with shell access.

Each successful attachment immediately creates a `final_review_image` story
transcript record carrying the run, session and reviewed diff identity; selected
images therefore survive reviewer failure or cancellation. A completed final
review references those same transcript IDs in its `attachments` data. No
agent-output schema field or original/annotated pair is required. Unselected
captures are scratch: after closing the browser, Hashd preserves its lifecycle
log beside the scratch directory and removes that directory. A hard host crash
can leave scratch behind for existing run-directory cleanup; this adds no
background filesystem sweeper.

`GET /stories/{id}/review-images/{image_id}?project=...` serves the selected PNG
through ordinary API authentication, checking its story membership and digest.
Web shows images in the story transcript and final-review panel and forwards
`/ui/stories/{project}/{id}/review-images/{image_id}` through the user's existing
browser session. URLs contain no credentials; image responses use `nosniff`
and private, non-storing cache policy. Selected files belong to project artifact
storage, outside worktrees and run scratch. They are retained like other captured
story artifacts; this change adds no automatic selected-image deletion policy.
TUI Kitty/Sixel rendering and clickable fallback are tracked separately in
[GitHub #1956](https://github.com/codr1/hashd/issues/1956).

#### Planning pipeline

| Prompt | Used by | Purpose |
|--------|---------|---------|
| `plan_discovery.md` | pm_discovery | Discover next chunks to build from REQS |
| `refine_story.md` | pm_refine | Refine chunk into story with acceptance criteria |
| `edit_story.md` | pm_edit | Edit existing story based on feedback |
| `project_describe.md` | pm_describe | Generate project description from repo contents |
| `plan_add.md` | plan_add | Generate a single micro-commit from instruction |

#### Other

| Prompt | Used by | Purpose |
|--------|---------|---------|
| `breakdown.md` | breakdown / partial breakdown | Break a story or its unfinished tail into cohesive micro-commits |
| `fix_generation.md` | fix_generation | Generate FIX commits for merge gate failures |
| `include_fix_generation_repair_ruling.md` | fix_generation (with a repair ruling) | The ruling, requirements and failed verification, passed whole; one FIX or a decline |
| `include_repair_ruling.md` | fix_generation + implement + review (a repair ruling) | The ruling and what each verdict directs, shared by every ruling section |
| `include_repair_ruling_evidence.md` | implement + review (a FIX with a stored ruling) | The ruling the FIX carries out and its failure evidence, passed whole |
| `conflict_resolution.md` | merge (resolve) | Resolve git rebase conflicts |
| `chat_general.md` | chat | System prompt for chat (CLI `hashd chat` and the TUI chat panel) |

### Viewing and managing prompts

```bash
# List all prompts grouped by pipeline phase
hashd prompts list

# Show a prompt template (with metadata header)
hashd prompts show implement

# Show the built-in default even if a project override exists
hashd prompts show implement --default
```

### Per-project prompt overrides

Projects can shadow any default prompt template. Overrides are stored in the ops dir under `projects/<name>/prompts/<template>.md` -- not in the repo, since prompts are operational config.

Override resolution: project `prompts/<name>.md` > built-in `prompts/<name>.md`.

Overrides are by **prompt template name**, not stage name. Stages compose multiple templates, so overriding at the template level gives fine-grained control, including shared sections.

The server owns the override files; the CLI reads and writes them over the REST
API, so these commands work the same in single-user and team/remote mode.

```bash
# Edit an override in $EDITOR (starts from the current override, or the default)
hashd prompts edit breakdown

# Set an override non-interactively (for scripts / CI)
hashd prompts edit breakdown --file new_breakdown.md
cat new_breakdown.md | hashd prompts edit breakdown --file -

# See what changed
hashd prompts diff breakdown

# Restore the default
hashd prompts reset breakdown

# Reset all overrides at once
hashd prompts reset --all
```

### OpenCode distribution and configuration

Hashd targets the active [OpenCode](https://opencode.ai/docs/cli/) TypeScript CLI
(`npm install -g opencode-ai`), verified against v1.18.31. The archived Go
`github.com/opencode-ai/opencode` v0.0.55 is incompatible. Hashd reports binaries
found on PATH; presence alone does not verify this CLI contract. Check
`opencode --version` and `opencode run --help` before assigning it to stages.
Hashd does not install or upgrade agent binaries.

All supported OpenCode stage shapes send the prompt on stdin and use
`run --format json`, including free-form implement/print stages. Response text
comes from `text` events' `part.text`; top-level `sessionID` is retained for
explicit `--session` resume. Historical wrapped response transcripts remain
readable.

Hashd injects native `mcp` local-server entries through the per-process
`OPENCODE_CONFIG_CONTENT` overlay. It preserves inherited JSON/JSONC settings
and unrelated MCP entries, replacing only the Hashd-injected server names.
Project/global config files (including `opencode.jsonc`), auth stores and
`OPENCODE_CONFIG` remain untouched and OpenCode loads them normally, including
any `provider` settings in them, which can override or redirect a registered
OpenCode key (see the known gap under agent credentials above). Invalid
inline config refuses launch rather than discarding settings. The internal
Hashd token stays in the child environment, never the MCP config payload.
Older Hashd launches could write an incompatible `mcpServers` object to
`opencode.json`. Review and migrate those obsolete entries to OpenCode's native
`mcp` schema without discarding authored settings; this correction does not
delete or rewrite existing files.
This does not change the existing best-effort read-only permission declaration,
server-side credential exclusion, or stage-specific background/subagent policy.

## Agent Tool Permissions

Agent permissions are declared by stage shape, not by individual agent command
templates. The source of truth is
`server/internal/config/defaults.yaml:shape_capabilities`, mirrored into
`packages/hashd-client/src/hashd_client/defaults.yaml` by `task -d server generate:defaults`; both
copies must stay in sync. The runners translate that shape intent into each
agent's CLI flags when assembling the command.

### Shape Capabilities

| Shape | Writes? | Bash | Intent |
|---|---:|---|---|
| `print` | no | none | Read context and produce free-form text for planning and discovery. |
| `json` | no | none | Read context and produce structured output. |
| `edit` | yes | none | Edit a bounded artifact such as REQS annotations or docs. |
| `review` | no | inspect | Inspect the tree and run read-oriented shell commands such as `git diff`, `git status`, `git log`, `go list`, or `task --list`; do not modify files. |
| `review_resume` | no | inspect | Same as `review`, continuing a prior review session. |
| `implement` | yes | full | Implement code in an isolated worktree and run the project build/test tooling. |
| `implement_resume` | yes | full | Same as `implement`, continuing a prior implementation session. |

`bash: inspect` means shell access is allowed for inspection because many CLIs
do not expose a read-only shell. The stage still has `writes: false`; the agent
must not edit files, and downstream gates validate the result.

### Stage Shapes

The Go map `server/internal/agents/runner.go:stageShapeMap`, Python mirror
`packages/hashd-client/src/hashd_client/agents_check.py:STAGE_SHAPE`, and fixture
`tests/fixtures/agents/stage_shape.json` define which shape each stage uses.
Those three stay in lockstep through the existing stage-shape contract tests.

Default stage commands in `defaults.yaml:stages` and per-agent templates for
stage-backed shapes in `defaults.yaml:agents.*.shapes` are structural templates
only: binary, model/output format, resume session, worktree, and stdin
placeholders. Permission flags are derived from the shape capabilities at
command assembly time. The `chat` and `chat_resume` templates are the remaining
interactive exceptions: they intentionally carry explicit tool restrictions
because they are not stage-backed agent-run shapes.

### Per-Agent Enforcement

| Agent | Derived enforcement |
|---|---|
| Claude Code | Every shape denies the `Agent` tool that starts subagents and the tools through which the stage agent starts or resumes work outside its turn: `Monitor`, `RemoteTrigger`, `ScheduleWakeup`, `SendMessage` and `Workflow`, and its launch settings refuse messages other Claude Code sessions send into it (see "Background work"). `writes:false` also denies write tools; `bash:none` also denies shell and other side-effect tools. `writes:true` uses edit or full-permission mode based on `bash`. |
| Codex | `writes:false` sets Codex's read-only sandbox through a config override that works for both start and resume; `writes:true` uses workspace-write or full implementation modes. Every launch, including chat over app-server, also turns off subagents and goal continuation through `-c features.multi_agent=false`, `-c agents.enabled=false` and `-c features.goals=false` (see "Background work"). |
| Gemini | `writes:false` maps to plan approval mode; write-capable shapes use auto-edit or yolo based on `bash`. Every launch also loads hashd's shipped `agent_policies/gemini.toml`, whose one rule denies `invoke_agent`, the tool that starts subagents, through `--admin-policy`, a flag Gemini CLI added in 0.35.0, so a launch on an older Gemini CLI is expected to fail; user settings and admin or system policy can still outrank or drop the file, and no flag or variable turns off background shell processes or Auto Memory, so none is pinned for them (see "Background work"). |
| Qwen | `writes:false` maps to plan approval mode; write-capable shapes use auto-edit or yolo based on `bash`. Every launch also excludes the `agent`, `monitor` and `send_message` tools through `--exclude-tools` and sets `QWEN_CODE_DISABLE_WORKFLOWS=1` and `QWEN_CODE_DISABLE_CRON=1`; no flag or variable turns off background shell commands, so none is pinned for them (see "Background work"). |
| Copilot | `writes:false` excludes write, and also excludes shell for `bash:none`; implementation uses yolo. Every launch, including yolo, also excludes the `task` and `write_agent` tools in the same `--excluded-tools` list; no flag or variable turns off async or detached shell commands, so none is pinned for them (see "Background work"). |
| OpenCode | No native read-only knob is declared. `writes:false` is best-effort and unsafe for read-only-critical stages until the agent has an enforceable mode. Every launch also sets `OPENCODE_PERMISSION` with `task` denied, keeping any other rules the variable already holds, so no subagent starts, and `OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=false`, which still refuses background subagents where an agent's own configured permission allows `task` again; no flag or variable stops a shell command from backgrounding itself, so none is pinned for it (see "Background work"). |
| Kimi | Kimi Code 2.x; `writes:false` remains best-effort and unsafe for read-only-critical stages. New sessions bind `agent_policies/kimi.md`, denying `Agent` and `AgentSwarm` while preserving the base prompt. Resume restores that binding without `--agent-file`. No retired Ralph flag is sent. Background shell work remains unrestricted (see "Background work"). |

This is deliberately honest: the permission intent is uniform, but enforcement
depends on what the selected agent can express. Agents without a read-only knob
must not be treated as equivalent to enforced read-only agents.

#### Background work

Every Claude launch pins two Claude Code opt-outs twice each: the agent process environment carries `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` and `CLAUDE_CODE_DISABLE_CRON=1`, and the launch's single inline `--settings` value carries the same entries in its `env`. The launcher sets them after credential injection. No other agent receives any of these pins. Claude Code documents the background-task opt-out as disabling `run_in_background` on Bash and subagent tools, auto-backgrounding and Ctrl+B, and the scheduled-task opt-out as making the `/loop` skill and cron tools unavailable and stopping already-scheduled tasks from firing, including tasks a resumed session restores ([environment variables](https://code.claude.com/docs/en/env-vars), [scheduled tasks](https://code.claude.com/docs/en/scheduled-tasks#disable-scheduled-tasks)). On 2.1.266 it removes `CronCreate`, `CronDelete`, `CronList` and the `/loop` skill, and leaves `ScheduleWakeup` offered, so every shape also denies `ScheduleWakeup` through `--disallowedTools` (Per-Agent Enforcement above).

The same `--settings` value also carries `crossSessionInbound: "refuse"` on every Claude launch, so a stage session drops messages the operator's other Claude Code sessions send into it. Claude Code documents that a `claude -p` session binds an inbox socket like an interactive one, that a message arriving while the receiving session is idle starts a new turn with it, and that with no `crossSessionInbound` value a receiver that prompts for permissions takes every message except one from a sender that bypasses prompts, while a receiver that bypasses prompts still takes messages from a sender that also bypasses them ([cross-session messaging](https://code.claude.com/docs/en/cross-session-messaging#control-inbound-messages)). Without the key, every stage shape would take messages: the `edit` shape's `acceptEdits` counts as prompting and would take them from the operator's ordinary sessions, and the other shapes bypass prompts and would take them from bypassing sessions. It reads managed settings first, then the `--settings` flag, then user settings, applies the first value found, and applies a project or local value only when it is stricter ([settings reference](https://code.claude.com/docs/en/settings-reference#crosssessioninbound)). Denying `SendMessage` stops only the stage agent's own sends; this setting is the inbound control. Sessions hashd does not launch, including the operator's own, keep their messaging.

A managed (policy) settings source that sets either variable to another value or `crossSessionInbound` to another value, or otherwise outranks the invocation settings as Claude Code documents, defeats the launch's value for it on that host, and hashd cannot observe it. hashd does not override, narrow or probe managed settings, change which settings sources Claude loads, or refuse to launch. The Claude enforcement claim is limited to what the cited documentation and the isolated live check below establish.

The opt-in live check `TestLiveClaudeBackground` (`server/internal/agents/live_claude_background_test.go`) launches the real claude binary through `RunStageWithOptions` in a temp directory with no project, at the harness default tool timeout. The host's Claude Code login, user settings and account MCP connectors still load (leg (2) below moves the user configuration directory), so its results hold for the host it ran on. It last ran on Claude Code 2.1.266. Each row records what that run observed. A result is unavailable (the tool is not offered), refused (the harness answered the call with an error), foreground completion (the work finished inside the call), started or moved to background (the call returned while its work kept running), or not moved (the harness stopped the command at its timeout). Completion after final result is judged from the stream (a frame after the first `type:"result"` frame, or a turn the harness started itself) and from a marker file the work writes as its last step, watched for the work's own duration after the run returned. The launcher runs the agent in its own process group and SIGKILLs that group when the agent exits, so the marker watch sees only work that left the group: a "no" for work inside the group comes from that reap, not from the work not having run. The check fails on any background start or later completion, on `Agent` (listed as `Task` in the tool list) or `Workflow` offered on any shape, on `Monitor`, `CronCreate`, `ScheduleWakeup`, `RemoteTrigger`, `SendMessage` or the `/loop` skill offered on any shape, and on a case with no attempt or not exercised, which produce no row. Case (e) asks the stage agent to try `Monitor`, `CronCreate` and `ScheduleWakeup` with local work that writes its marker; it never asks for `RemoteTrigger` (routines on the operator's claude.ai account) or `SendMessage` (the operator's other sessions), and judges both from the offered tool list alone. Case (f) names the stage session with a unique `--name`, added at the test's subprocess seam because the launcher passes none, and once the stage agent's foreground Bash call starts, a test-owned `claude -p` sender restricted to `--tools SendMessage` and bypassing permission prompts sends one message to that name alone; it never lists or messages any other session. The message's last line is a random token that appears nowhere in the stage's prompt or argv. The check looks for it in three places: the stage session's stored transcript (the one file named for the session id under the Claude Code configuration directory's `projects` directory), which records a delivered message whether or not the stage agent mentions it; the stage's stream; and the stage agent's text, which is asked to quote the last line of any message that reached it without acting on it. A control leg first removes `crossSessionInbound` from the launch settings and must find the token in its transcript, so the run shows that signal records a delivery without depending on the stage agent; the leg with the launch settings fails if the token appears in any of the three, and fails as not exercised when the control's transcript showed none or its own transcript cannot be read. The sender's `SendMessage` answered `{"success":true,...}` in both legs, so the result is judged on the receiving side.

| Case | Shape | Result | Completion after final result |
|---|---|---|---|
| (a) Bash command past the harness default tool timeout | implement | not moved | no |
| (b) Explicitly backgrounded Bash call | implement | refused | no |
| (c) Background subagent through `Agent` (anthropics/claude-code#34916) | implement | foreground completion (recorded while the implement shape still offered `Agent`; not run since the launch denies it) | no |
| (c) Background subagent through `Workflow` | implement | unavailable | no |
| (c) Background subagent through `Workflow` | edit | unavailable | no |
| (d) Subagent tools `Agent` and `Workflow` on a read-only shape | review | unavailable | no |
| (e) `Monitor`, `CronCreate`, `ScheduleWakeup`, `RemoteTrigger`, `SendMessage` and the `/loop` skill | implement | unavailable (a tool search for `Monitor`, `CronCreate` and `ScheduleWakeup` found none; no call made) | no |
| (e) `Monitor`, `CronCreate`, `ScheduleWakeup`, `RemoteTrigger`, `SendMessage` and the `/loop` skill | edit | unavailable (a tool search for `Monitor`, `CronCreate` and `ScheduleWakeup` found none; no call made) | no |
| (e) `Monitor`, `CronCreate`, `ScheduleWakeup`, `RemoteTrigger`, `SendMessage` and the `/loop` skill | review | unavailable (a tool search for `Monitor`, `CronCreate` and `ScheduleWakeup` found none; no call made) | no |
| (f) Message from another Claude Code session, control: launch settings with `crossSessionInbound` removed | implement | delivered (token in the stage session transcript, the stream and the stage agent's text) | no |
| (f) Message from another Claude Code session, launch settings | implement | refused (token in none of the transcript, the stream or the stage agent's text) | no |

Rows (a) and (b) run on a write-capable shape where Bash stays offered: they record what the opt-out does to each background path. The `Agent` row was recorded while write-capable shapes still offered `Agent`, and records the opt-out running a background subagent request in the foreground. Every shape now denies `Agent`, and the check, which now fails when `Agent` is offered on the implement shape, has not run since. The opt-out does not stop `Workflow`: before the launch denied it, a write-capable run returned "Workflow launched in background", the stage agent replied, and when the workflow completed claude ran a further turn whose reply was the run's last `type:"result"` frame. The `Workflow` rows and row (d) therefore record the launch's `--disallowedTools` denial, not background suppression.

The (e) rows likewise record the launch's denials and the scheduled-task pin, not suppression by the background-task opt-out. Before either was in place, isolated `claude -p` probes on 2.1.266 with the background-task pins and the implement shape's permission flags observed: `Monitor` answered "Monitor started" with a `task_started` frame marked `is_backgrounded`, the stage agent replied, and when the watched command finished claude ran two further turns after the first `type:"result"` frame, and the command's marker file was written; `ScheduleWakeup` answered that the harness would re-invoke the agent when the wakeup fired, and the agent ended its turn with an empty result without making the call the prompt asked for next; a `CronCreate` one-shot job that came due during a foreground Bash call did not fire before the process exited; `SendMessage` to a subagent the run had just started resumed it with a `task_started` frame marked `is_backgrounded`, and that call returned only after the subagent finished. Claude Code documents that `SendMessage` to a completed subagent resumes it in the background ([resume subagents](https://code.claude.com/docs/en/sub-agents#resume-subagents)) and, with cross-session messaging on, starts a turn in the receiving session when it is idle ([message delivery](https://code.claude.com/docs/en/cross-session-messaging#message-delivery)); that it restores `CronCreate` tasks on `--resume` ([scheduled tasks](https://code.claude.com/docs/en/scheduled-tasks#limitations)), which hashd's resume shapes use; and that `RemoteTrigger` creates and runs routines on claude.ai ([tools reference](https://code.claude.com/docs/en/tools-reference)). None of these probes called `RemoteTrigger` or messaged a session other than case (f)'s test-owned receivers. `TaskOutput`, `TaskStop` and `ListAgents` read, wait on or stop existing work, or list agents, and stay offered on every shape.

Not examined: the bundled `/batch` skill, which Claude Code documents as spawning one background subagent per unit in an isolated git worktree, and the bundled `/deep-research` workflow ([commands](https://code.claude.com/docs/en/commands)). The `Skill` tool that invokes skills stays offered on write-capable and `bash: inspect` shapes. Whether the background-task pin and the `Workflow` denial close these commands has not been probed, and no check covers them.

The same check's conflicting-settings legs keep every launcher pin, put `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=0` and `CLAUDE_CODE_DISABLE_CRON=0` in one source each, echo both variables from the session's shell, read whether `CronCreate` is offered and make an explicitly backgrounded Bash call on the implement shape. Leg (1) sets the inherited process environment. Leg (2) writes user settings in a temp directory selected with `CLAUDE_CONFIG_DIR`, which Claude Code documents as the configuration directory for settings and credentials ([environment variables](https://code.claude.com/docs/en/env-vars), [credential management](https://code.claude.com/docs/en/authentication#credential-management)). Legs (3) and (4) write `.claude/settings.json` and `.claude/settings.local.json` in the leg's temp working directory. Legs (2) to (4) set `HASHD_LIVE_UNRELATED=present` beside the `0` entries, unset in the process environment, so its arrival in the session shell shows the file was loaded and its other `env` entries survived the launch's settings value. The test never opens the operator's user settings, a project's settings or a managed-settings path; a leg it cannot isolate with the authentication available to the test process is not run. A leg fails when anything but `1` reaches the session shell for either variable, the call starts or `CronCreate` is offered (pins hold `unenforced`), and when its unrelated variable does not arrive: the run cannot tell an unloaded file from replaced `env` entries, so that leg is not exercised and produces no row. Last run on Claude Code 2.1.266:

| Leg | Conflicting source | Background Bash started | Background-task opt-out in session shell | Scheduled-task opt-out in session shell | `CronCreate` offered | Unrelated variable reached session | Pins hold |
|---|---|---|---|---|---|---|---|
| (1) | Inherited process environment `0` | no | `1` | `1` | no | n/a | yes |
| (2) | User settings `env` `0` under `CLAUDE_CONFIG_DIR` | not run: no authentication outside Claude Code's config directory (`claude auth status` exits 1 under the isolated directory) | not run | not run | not run | not run | not run |
| (3) | Project `.claude/settings.json` `env` `0` | no | `1` | `1` | no | yes | yes |
| (4) | Local `.claude/settings.local.json` `env` `0` | no | `1` | `1` | no | yes | yes |

Every Codex launch pins three config overrides: `-c features.multi_agent=false`, `-c agents.enabled=false` and `-c features.goals=false` (`codexStageOwnedArgs` in `server/internal/agents/runner.go`). On the exec route the launcher adds them after credential and MCP injection, at the permission flags' position before the trailing stdin sentinel, which `exec` and `exec resume` both accept. No shape carries these keys, so each appears once. That reaches every exec shape (`print`, `print_resume`, `json`, `edit`, `review`, `review_resume`, `implement`, `implement_resume`, `detect`), `stage_agents` reassignments and `hashd internal agent-run`. On the app-server route `codexAppServerArgs` adds them after the fixed sandbox and approval flags and before the MCP flags, which reaches `chat` and `chat_resume`. OpenAI documents `features.multi_agent` as enabling the multi-agent tools (`spawn_agent`, `send_input`, `resume_agent`, `wait_agent`, `close_agent`), `agents.enabled` as enabling or disabling multi-agent tools, and `features.goals` as enabling persisted goals and automatic continuation ([config reference](https://developers.openai.com/codex/config-reference), [subagents](https://developers.openai.com/codex/agent-configuration/subagents)); both subagent keys are pinned because the docs do not say which wins when user config sets the other. `-c` overrides rank above project `.codex/config.toml`, profiles and user `config.toml` ([config basics](https://developers.openai.com/codex/config-basic)), and `exec resume` and `app-server` take `-c` ([CLI reference](https://developers.openai.com/codex/cli/reference)). All pages retrieved 2026-09-14.

No override is pinned for three Codex paths that can outlive a turn, because none is documented to turn them off: background terminals, which app-server lists and stops through `thread/backgroundTerminals/*` ([app-server](https://developers.openai.com/codex/app-server)) and which `features.unified_exec`, documented only as selecting the PTY-backed exec tool, is not claimed to control; async command hooks (`hooks.<Event>[].hooks[].async`), whose only documented off switch, `features.hooks`, turns off every lifecycle hook; and `codex cloud exec`, which a stage agent with shell access and the owner's Codex login can run. Client-created goals (`thread/goal/set`) and the client methods `command/exec`, `process/spawn` and `thread/shellCommand` start work only when the client calls them, and hashd never does.

A managed `requirements.toml` can defeat the pins: OpenAI documents its `[features]` table as requiring a runtime feature to stay enabled or disabled, names `features.multi_agent`, and documents that a conflicting value from `config.toml`, a profile or a CLI override falls back to a compatible one ([managed configuration](https://developers.openai.com/codex/enterprise/managed-configuration), [config reference](https://developers.openai.com/codex/config-reference)). hashd cannot observe such a pin, and does not read, override or probe managed config or requirements.

The opt-in live check `TestLiveCodexBackground` (`server/internal/agents/live_codex_background_test.go`, `HASHD_LIVE_CODEX=1`) launches the real codex binary through `RunStageWithOptions`, which swaps in app-server for chat, in a temp git repo with a temp project config naming codex in `stage_agents`. The host's Codex login and user config (including its MCP servers) still load, so results hold for the host it ran on. Each route's turn asks for a short foreground command, a command left running in a background terminal, a subagent started through a spawn tool, and a persisted goal. Every command ends by printing a nonce the test wrote to a file outside the repo, which appears in no prompt or argv, so the agent can report it only by running the command. The background work is a `sh -c` command whose `$0` is a random token, which sleeps and writes a marker file before printing its nonce. After the run returns, the check looks for the process with `pgrep -f` and for the marker, waits out the work's 45-second duration, then looks again. Tool calls come from the route's own session rollout, the files named for its thread id under `CODEX_HOME`, where Codex documents it keeps local state and session rollout files ([advanced config](https://developers.openai.com/codex/config-file/config-advanced), [non-interactive mode](https://developers.openai.com/codex/non-interactive-mode)); `codex exec --json` does not list these calls. A background-terminal start is a tool call carrying its probe's token whose recorded output names a running session (a `session_id` and no `exit_code`), a subagent start is a `spawn_agent` call, a code-mode script calling one whose recorded output reports the script completed, or recorded subagent activity, a goal is a goal tool call whose recorded output carries the created goal, or a code-mode script calling one whose recorded output carries the created goal or reports the script completed, and a `task_started` after the route's first `task_complete` is a turn Codex started itself. On exec routes the check also counts JSONL events after the first `turn.completed`. A result is unavailable (the agent had no such tool), no attempt (it reported nothing for it), refused (the tool or sandbox rejected it), foreground completion (the marker or nonce was there when the call returned), background start (the call returned while the work kept running: the rollout records the start, or the work was seen after the turn), or not exercised (no result could be established, including a claim no marker, nonce or recorded call backs). Unavailable and refused rest on the agent's report together with no process, marker, nonce or recorded call, so for the subagent and goal they count only when control leg (0) recorded that capability's call on the host; otherwise the row is not exercised. Control leg (0) runs the implement route against leg (1)'s conflicting project config with the three overrides removed at the test's subprocess seam, and a recorded subagent start or created goal shows the capability offered unpinned. It runs only there: the app-server argv has no seam to remove the overrides, so it does not show the capabilities offered unpinned on the review or chat shapes, their sandbox or the app-server transport, and those routes' subagent and goal rows rest on this one control plus their own agent report and rollout. The check fails on a subagent or goal start, including a recorded call whose work finished inside the turn, on work seen after the turn, on events after the first `turn.completed` or a turn Codex started itself, on a foreground command whose nonce did not arrive, and on a route result that is not exercised or has no attempt. A background-terminal start is recorded, not failed, because no documented override turns background terminals off. Last run on codex-cli 0.153.4, which passed:

| Route | Shape | Capability | Result | Work after turn end |
|---|---|---|---|---|
| exec | review | short foreground command | foreground completion | no |
| exec | review | background terminal | background start | no |
| exec | review | subagent | unavailable | no |
| exec | review | goal continuation | unavailable | no |
| exec | review_resume | short foreground command | foreground completion | no |
| exec | review_resume | background terminal | background start | no |
| exec | review_resume | subagent | unavailable | no |
| exec | review_resume | goal continuation | unavailable | no |
| exec | implement | short foreground command | foreground completion | no |
| exec | implement | background terminal | background start | no |
| exec | implement | subagent | unavailable | no |
| exec | implement | goal continuation | unavailable | no |
| exec | implement_resume | short foreground command | foreground completion | no |
| exec | implement_resume | background terminal | background start | no |
| exec | implement_resume | subagent | unavailable | no |
| exec | implement_resume | goal continuation | unavailable | no |
| app-server | chat | short foreground command | foreground completion | no |
| app-server | chat | background terminal | background start | no |
| app-server | chat | subagent | unavailable | no |
| app-server | chat | goal continuation | unavailable | no |
| app-server | chat_resume | short foreground command | foreground completion | no |
| app-server | chat_resume | background terminal | background start | no |
| app-server | chat_resume | subagent | unavailable | no |
| app-server | chat_resume | goal continuation | unavailable | no |
| control (0): leg (1)'s conflicting project config with the three overrides removed at the test's subprocess seam; its canary reached the agent | implement | subagent | background start (the rollout records a `spawn_agent` call and subagent activity) | no |
| control (0) | implement | goal continuation | background start (the rollout records a `create_goal` call that completed) | yes: the rollout records one turn Codex started after the stage's result |
| conflicting config (1): project `.codex/config.toml` turning `features.multi_agent`, `features.goals` and `agents.enabled` back on, temp repo trusted through a `projects.<path>.trust_level` override at the test's subprocess seam; its `developer_instructions` canary reached the agent | implement | subagent | unavailable | no |
| conflicting config (1) | implement | goal continuation | unavailable | no |
| conflicting config (2): user `config.toml` under an isolated `CODEX_HOME` | implement | subagent, goal continuation | not run: `codex login status` exits 1 under the isolated `CODEX_HOME`, and the operator's credentials are never copied | not run |
| any | any | `codex cloud exec` | not run: the check never submits a remote task | not run |
| any | any | async command hooks | not run: hooks come from operator hook config, which the check never writes | not run |

Every route's rollout records the background command's tool call. In this run no background-terminal process was alive when the run returned and no marker appeared. An earlier run on the same version, with the same probes, found the `chat` route's background-terminal process still alive when the run returned; it was gone by the end of the 60-second wait, and its marker could not be written under the read-only sandbox. That run failed on it, so a `chat` background terminal has outlived its turn on this host. The runs do not show what ends these processes: codex itself on exit, the exec launcher's SIGKILL of the agent's process group when codex exits, or the app-server transport's kill of codex when the turn returns. No pinned override controls the background terminal. Control leg (0) shows that on this host, with the overrides removed, the stage agent starts a subagent and creates a goal, and Codex starts a further turn after the stage's result; with them in place, leg (1) and every route record neither call. In the earlier run, the pinned leg (1) agent searched its own tool list for spawn and goal tools, and the rollout records an empty result. A code-mode script that calls the goal tool can print nothing, so its recorded output need not carry the created goal; the check counts such a script once its output reports it completed.

Every Gemini CLI launch pins one control: `geminiStageOwnedArgs` in `server/internal/agents/runner.go` adds `--admin-policy <install root>/agent_policies/gemini.toml` after the permission flags (`--skip-trust` and `--approval-mode plan|auto_edit|yolo` from `geminiPermFlags`) at the end of argv, after credential and MCP injection, which fresh and `--resume` launches both accept. Gemini CLI added `--admin-policy` in 0.35.0 (2026-03-24): its argument parser (`packages/cli/src/config/config.ts`) is strict, and at [v0.34.0](https://github.com/google-gemini/gemini-cli/blob/v0.34.0/packages/cli/src/config/config.ts) it defines `--policy` but not `--admin-policy`, which [v0.35.0](https://github.com/google-gemini/gemini-cli/blob/v0.35.0/packages/cli/src/config/config.ts) adds. hashd declares no minimum Gemini CLI version and does not check the installed one, so a launch on a release older than 0.35.0 is expected to fail on the unknown flag. `agent_policies/gemini.toml` is an authored file in the hashd source that the core wheel ships next to `agent_policies/kimi.md` and that the launcher reads from `$HASHD_ROOT` the same way; with `HASHD_ROOT` unset, no file there, or a path holding a comma (Gemini CLI splits the flag's value on commas, so such a path would load no policy), the stage fails with a diagnostic before gemini starts. The file holds one rule: `toolName = "invoke_agent"`, `decision = "deny"`, `priority = 999`. The worktree `.gemini/settings.json` MCP file, the permission flags and the credential environment do not change. That reaches every shape (`print`, `print_resume`, `json`, `edit`, `review`, `review_resume`, `implement`, `implement_resume`, `chat`, `chat_resume`, `detect`), `stage_agents` reassignments and `hashd internal agent-run`. Gemini CLI 0.49.0 documents these ways a stage agent can start work that runs on after its call returns:

- Background shell processes. `run_shell_command` takes `is_background`, and a command run in the background with `&` "will return immediately and the process will continue to run in the background" ([shell tool](https://github.com/google-gemini/gemini-cli/blob/v0.49.0/docs/tools/shell.md)); `tools.shell.backgroundCompletionBehavior: "inject"` returns a finished background command's output to the agent ([configuration](https://github.com/google-gemini/gemini-cli/blob/v0.49.0/docs/reference/configuration.md)). The documented controls are settings keys (`tools.core`, the deprecated `tools.exclude`) and policy engine rules loaded from TOML files (`~/.gemini/policies`, `--policy`, `--admin-policy`) ([policy engine](https://github.com/google-gemini/gemini-cli/blob/v0.49.0/docs/reference/policy-engine.md)). hashd writes neither, does not deny `run_shell_command` (which would also remove foreground shell use), and does not treat a rule matching command text as a control for `&`.
- Subagents. A subagent reports back when it finishes ([subagents](https://github.com/google-gemini/gemini-cli/blob/v0.49.0/docs/core/subagents.md)), and the docs name the `experimental.enableAgents` setting, per-agent `agents.overrides` and policy rules as the ways to turn subagents off. The subagents page describes each subagent as a tool of its own name; in the installed 0.49.0 bundle every subagent call instead runs through one tool, `invoke_agent` (`AGENT_TOOL_NAME`), which takes `agent_name` and `prompt`, the system prompt tells the model to invoke subagents through it, and the policy check receives that call name. Pinned: `--admin-policy` naming the shipped file, whose rule denies `invoke_agent`; the policy engine docs say a call a matching deny rule blocks is not executed and the tool is excluded from the model's memory ([policy engine](https://github.com/google-gemini/gemini-cli/blob/v0.49.0/docs/reference/policy-engine.md)). This also removes subagents that finish inside the turn. `--admin-policy` and `--policy` both take files or directories; in the installed bundle `--admin-policy` paths are added at the admin tier after the system policies directory, while `--policy` paths replace the user policies directory (`~/.gemini/policies`), which is why hashd uses `--admin-policy`. The installed bundle numbers the admin tier 5 (the policy engine page says base 4) and adds a rule's priority divided by 1000, so the rule's 999, the largest priority the schema accepts, gives it 5.999, the highest a rule can have. Loaded through that bundle's own policy loader, the file produced one admin-tier rule at 5.999 and no errors, and the bundle's policy engine returned deny for an `invoke_agent` call and allow for other tools in yolo mode; no gemini run has exercised it. Remote (A2A) agents ([remote subagents](https://github.com/google-gemini/gemini-cli/blob/v0.49.0/docs/core/remote-agents.md)) are a separate surface, and the rule is not claimed to cover them.
- Auto Memory, "a background extraction agent" that starts at session boot. It is off by default and turned on by `experimental.autoMemory` in user or project settings ([auto memory](https://github.com/google-gemini/gemini-cli/blob/v0.49.0/docs/cli/auto-memory.md)); no flag or environment variable controls it, so off by default is not off on every host. The docs do not say whether it keeps running after a headless turn ends.
- Hooks run synchronously, with Gemini CLI waiting for them, except `PreCompress`, which is "fired asynchronously" ([hooks](https://github.com/google-gemini/gemini-cli/blob/v0.49.0/docs/hooks/index.md), [hooks reference](https://github.com/google-gemini/gemini-cli/blob/v0.49.0/docs/hooks/reference.md)). Hooks, and extensions that bundle hooks, subagents and MCP servers, come from operator configuration; the only extension flag, `-e none`, turns off every extension, and hashd passes it nowhere.

Gemini CLI applies command-line arguments over environment variables, those over the system settings file, and that over project, user and system-default settings ([configuration layers](https://github.com/google-gemini/gemini-cli/blob/v0.49.0/docs/reference/configuration.md#configuration-layers)); admin-tier policy outranks user and extension policy, and upstream documents that supplemental admin policies are ignored when any `.toml` policy file is found in the standard system location (`/etc/gemini-cli/policies`, `/Library/Application Support/GeminiCli/policies`, `C:\ProgramData\gemini-cli\policies`) ([policy engine](https://github.com/google-gemini/gemini-cli/blob/v0.49.0/docs/reference/policy-engine.md)). The additive ordering above is what the installed bundle shows; that ignore branch was not verified there. The shipped file therefore covers ordinary, default Gemini CLI use: a system policy file on the host drops it, and the operator's own settings and any admin or system policy remain theirs and can outrank it or turn subagents back on, which hashd cannot observe and does not claim to contain. hashd does not read, write, override or probe Gemini settings (`experimental.enableAgents`, `agents.overrides` among them), `~/.gemini/policies`, workspace policies, admin or system policy, or the credential home. All pages retrieved 2026-09-14 at the v0.49.0 tag of google-gemini/gemini-cli, the installed version, and checked against [geminicli.com](https://geminicli.com/docs/reference/configuration) ([shell tool](https://geminicli.com/docs/tools/shell), [subagents](https://geminicli.com/docs/core/subagents)).

The opt-in live check `TestLiveGeminiBackground` (`server/internal/agents/live_gemini_background_test.go`, `HASHD_LIVE_GEMINI=1`) launches the real gemini binary through `RunStageWithOptions` in one temp git repo with a temp project config naming gemini in `stage_agents`, with `HASHD_ROOT` at the source checkout, so `--admin-policy` names the `agent_policies/gemini.toml` the wheel ships. Routes: review, review_resume, implement, implement_resume, chat and chat_resume. The implement shape prints plain text with no session id, so implement_resume resumes the latest session an earlier route in the same repo produced. Each turn asks for a short foreground command, a shell command started with `is_background` and left running, and a command delegated to a subagent. Every command ends by printing a nonce the test wrote to a file outside the repo; the background and subagent work is a `sh -c` command whose `$0` is a random token, which sleeps and writes a marker file. After the run returns, the check looks for the process with `pgrep -f` and for the marker, waits out the work's duration, then looks again. On the chat routes a stream-json `tool_use` frame whose `parameters` carry a probe's token records the call through its `tool_name`, one that also sets `is_background` records a background start, and frames after the first `result` frame are work after the stage's result; the review routes' json envelope and the implement routes' plain text list no tool calls, so their results rest on the process, marker, nonce and the agent's report. Results use the same six values as the Codex check. It fails when a route cannot run, when a resume route has nothing to resume, when the foreground command's nonce does not reach an implement route, on a subagent probe that ran, in the background or the foreground, and on a capability with no attempt or not exercised; a background shell start, work after the turn and frames after the result are recorded, not failed, because no documented invocation-level control turns them off. On the chat routes a subagent probe counts against the policy only when the stream records it running through `invoke_agent`: one recorded only through `run_shell_command` or another tool is not exercised. The review and implement routes record no calls, so a subagent probe that ran there fails with a note that the output does not show which tool ran it. On the chat routes the reply arrives as assistant message frames, so the check rebuilds the agent text from them before reading the report lines. It writes no settings, hooks or extensions and no policy beyond the shipped file the launcher passes; the launcher writes the chat routes' MCP settings file into the temp repo's `.gemini/settings.json`, which Gemini CLI loads as project settings, with its hashd MCP server command pointed at a path that does not exist. It never reads Gemini CLI's session files and never contacts a remote agent; authentication and the host's user, system and admin settings and policy still load. Once opted in, a missing gemini binary or a missing `pgrep` fails it, and a host with no gemini authentication fails the first route, with gemini's own error in the logged stderr.

The check has not produced a result, and it has not run since the launch added `--admin-policy`: this host still has no gemini authentication (`GEMINI_API_KEY` unset), so live proof of the policy is unavailable. It last ran on Gemini CLI 0.49.0, before the policy file, and stopped at the first route: gemini exited 41 with "Please set an Auth method in your `~/.gemini/settings.json` or specify one of the following environment variables before running: GEMINI_API_KEY, GOOGLE_GENAI_USE_VERTEXAI, GOOGLE_GENAI_USE_GCA", which the launcher classified as `transient`, not as an agent authentication failure. No row below is a live result, and nothing here shows how Gemini CLI 0.49.0 behaves:

| Route | Shape | Capability | Result | Work after turn end |
|---|---|---|---|---|
| review | review | short foreground command, background shell process, subagent | not run: gemini exited 41, no auth method configured on the host | not run |
| review_resume | review_resume | short foreground command, background shell process, subagent | not run: the review route did not run | not run |
| implement | implement | short foreground command, background shell process, subagent | not run: the check stopped at the review route | not run |
| implement_resume | implement_resume | short foreground command, background shell process, subagent | not run: the check stopped at the review route | not run |
| chat | chat | short foreground command, background shell process, subagent | not run: the check stopped at the review route | not run |
| chat_resume | chat_resume | short foreground command, background shell process, subagent | not run: the check stopped at the review route | not run |
| any | any | Auto Memory | not run: turned on only through a settings key the check never writes, and it mines sessions idle for at least three hours | not run |
| any | any | remote (A2A) subagent | not run: the check never contacts a remote agent | not run |
| any | any | hooks and extensions | not run: they come from operator configuration, which the check never writes | not run |
| any | any | `tools.shell.backgroundCompletionBehavior` inject | not run: a settings key the check never writes | not run |
| any | any | subagent with the shipped `--admin-policy` file | not run: no gemini authentication on the host (`GEMINI_API_KEY` unset); verified offline only, as above | not run |
| user settings or admin or system policy that outrank or drop the shipped policy file | any | subagent | not run: the check writes no Gemini settings or policy and never reads the host's; a documented limitation | not run |

Every Qwen Code launch pins three controls (`qwenStageOwnedArgs` and `qwenLaunchEnvPins` in `server/internal/agents/runner.go`): `--exclude-tools agent,monitor,send_message`, and `QWEN_CODE_DISABLE_WORKFLOWS=1` and `QWEN_CODE_DISABLE_CRON=1` in the agent process environment. The launcher adds them after credential and MCP injection; the flag goes after the permission flags at the end of argv, which fresh and `--resume` launches both accept. That reaches every shape (`print`, `print_resume`, `json`, `edit`, `review`, `review_resume`, `implement`, `implement_resume`, `chat`, `chat_resume`, `detect`), `stage_agents` reassignments and `hashd internal agent-run`. The worktree `.qwen/settings.json` MCP file, the permission flags and the credential environment are unchanged. Qwen Code 0.23.4 documents these ways a stage agent can start work that runs on after its call returns:

- Subagents. The `agent` tool runs a top-level subagent in the background by default and delivers its result in a later turn, a fork always runs detached, and a one-shot headless run waits for a fork to finish ([sub-agents](https://github.com/QwenLM/qwen-code/blob/v0.23.4/docs/users/features/sub-agents.md), [agent tool](https://github.com/QwenLM/qwen-code/blob/v0.23.4/docs/developers/tools/task.md), [headless forks](https://github.com/QwenLM/qwen-code/blob/v0.23.4/docs/design/2026-07-21-headless-fork-subagents.md)). The Claude Code and Codex executors run through the same tool. Pinned: `--exclude-tools agent`, which the headless docs name for bounding subagent work ([headless](https://github.com/QwenLM/qwen-code/blob/v0.23.4/docs/users/features/headless.md)).
- Monitors. `monitor` runs a command in the background and streams its output back as task notifications while the agent continues, and a notification in the one-shot headless queue is submitted as a new model turn ([monitor tool](https://github.com/QwenLM/qwen-code/blob/v0.23.4/docs/developers/tools/monitor.md), [monitor cancellation](https://github.com/QwenLM/qwen-code/blob/v0.23.4/docs/design/monitor-cancel-notification.md)). Pinned: `--exclude-tools monitor`.
- Continuing a background agent and messaging other agents. `send_message` queues work for a running agent, resumes a paused one or continues a completed one, including agents a resumed session restores, and addresses Agent Team teammates and, with cross-session messaging on, other Qwen Code sessions ([sub-agents](https://github.com/QwenLM/qwen-code/blob/v0.23.4/docs/users/features/sub-agents.md#background-agent-continuation), [commands](https://github.com/QwenLM/qwen-code/blob/v0.23.4/docs/users/features/commands.md#6-messaging-another-running-session)). Pinned: `--exclude-tools send_message`.
- Workflows, a script that orchestrates subagents in parallel. Off by default and enabled only from user or system settings or `QWEN_CODE_ENABLE_WORKFLOWS=1`; `QWEN_CODE_DISABLE_WORKFLOWS=1` forces it off, and disable wins ([settings](https://github.com/QwenLM/qwen-code/blob/v0.23.4/docs/users/configuration/settings.md#tools)). Pinned.
- Scheduled tasks. The cron tools, on by default, queue prompts that fire between turns while the process runs; `QWEN_CODE_DISABLE_CRON=1` disables them ([scheduled tasks](https://github.com/QwenLM/qwen-code/blob/v0.23.4/docs/users/features/scheduled-tasks.md), [settings](https://github.com/QwenLM/qwen-code/blob/v0.23.4/docs/users/configuration/settings.md#experimental)). Pinned.

`--exclude-tools` uses the same deny mechanism as `permissions.deny`, which outranks allow and ask rules from every scope and removes a built-in tool from the registry ([structured output](https://github.com/QwenLM/qwen-code/blob/v0.23.4/docs/users/features/structured-output.md#permission-gating), [settings](https://github.com/QwenLM/qwen-code/blob/v0.23.4/docs/users/configuration/settings.md#permissions)). Qwen Code applies command-line arguments over environment variables, those over the system settings file, and that over project, user and system-default settings, and a settings `env` entry is applied only when the process environment leaves the variable unset ([configuration layers](https://github.com/QwenLM/qwen-code/blob/v0.23.4/docs/users/configuration/settings.md#configuration-layers), [authentication](https://github.com/QwenLM/qwen-code/blob/v0.23.4/docs/users/configuration/auth.md)). The exclusion names the tools as the headless and tool pages name them; the settings page's alias table still maps `Agent` to `task`, and whether `agent` matches on an installed 0.23.4 is for the live check to show. No admin policy is documented, but a system settings file, `--safe-mode`/`QWEN_CODE_SAFE_MODE` in the host environment or other host configuration may still defeat these controls, and hashd cannot observe that. hashd does not read, write, override or probe Qwen Code's user, project or system settings.

No flag or variable is pinned for these paths, and they stay open:

- Background shell commands. `run_shell_command` with `is_background` or a trailing `&` returns immediately while the process keeps running ([shell tool](https://github.com/QwenLM/qwen-code/blob/v0.23.4/docs/developers/tools/shell.md)), and background shell completions share the notification queue that starts later turns ([sub-agents](https://github.com/QwenLM/qwen-code/blob/v0.23.4/docs/users/features/sub-agents.md#notification-queue)). The only controls are permission rules matching command text or excluding `run_shell_command`, which would also remove foreground shell use; hashd uses neither.
- Auto-memory extraction, auto-dream and auto-skill review, which run in the background after a session, on by default, and are turned off only through `memory.*` user or project settings ([memory](https://github.com/QwenLM/qwen-code/blob/v0.23.4/docs/users/features/memory.md), [settings](https://github.com/QwenLM/qwen-code/blob/v0.23.4/docs/users/configuration/settings.md#memory)). `--safe-mode` also drops MCP servers, context files, hooks and permission rules, so hashd does not pass it. The docs do not say whether they keep running after a headless run exits.
- Async command hooks (`"async": true`) from operator configuration, whose results are injected in the next turn; Qwen Code reclaims a still-running async hook on POSIX exit except for event types documented as fire-and-forget ([hooks](https://github.com/QwenLM/qwen-code/blob/v0.23.4/docs/users/features/hooks.md#async-hooks)).
- Agent Team, off by default and enabled by `experimental.agentTeam` or `QWEN_CODE_ENABLE_AGENT_TEAM=1`, with no variable that turns it off ([multi-agent coordination](https://github.com/QwenLM/qwen-code/blob/v0.23.4/docs/users/features/multi-agent-coordination.md)). With `agent` and `send_message` excluded, whether its remaining team tools can start a teammate is not documented.

Inbound cross-session messages do not reach a stage: a one-shot `qwen -p` run never registers in the session registry ([commands](https://github.com/QwenLM/qwen-code/blob/v0.23.4/docs/users/features/commands.md#qwen-sessions-ps)). Goals do not start from a stage agent: headless runs do not offer `propose_goal`, and only a prompt that is entirely a `/goal` command starts Goal work ([goals](https://github.com/QwenLM/qwen-code/blob/v0.23.4/docs/users/features/goals.md), [headless](https://github.com/QwenLM/qwen-code/blob/v0.23.4/docs/users/features/headless.md#run-a-persistent-goal)). All pages retrieved 2026-09-15 at the v0.23.4 tag of QwenLM/qwen-code, the `latest` `@qwen-code/qwen-code` release on npm that day, and checked against the [official docs site](https://qwenlm.github.io/qwen-code-docs/en/users/features/headless/).

The opt-in live check `TestLiveQwenBackground` (`server/internal/agents/live_qwen_background_test.go`, `HASHD_LIVE_QWEN=1`) launches the real qwen binary through `RunStageWithOptions` in one temp git repo with a temp project config naming qwen in `stage_agents`. Routes: chat, chat_resume, review, review_resume, implement and implement_resume; a resume route whose fresh route printed no session id resumes the latest session an earlier route in the same repo produced. Each turn asks for a short foreground command that also echoes both pinned variables, a shell command started with `is_background`, a subagent through `agent`, a `monitor`, a workflow, and a one-time `cron_create` task, and asks whether `send_message` is offered without calling it. The work is a `sh -c` command whose `$0` is a random token, which sleeps and writes a marker file before printing a nonce the test wrote outside the repo. After the run returns, the check looks for the process with `pgrep -f` and for the marker, waits 150 seconds, then looks again. The chat routes print stream-json messages one per line and the review routes print one JSON array of the same messages; on both the check decodes the messages for recorded tool calls, a system message's tool list, the report lines in the first result message, the session id a resume route continues, and messages after the first result. The implement routes print plain text, so their results rest on the process, marker, nonce and the agent's report. Results use the same six values as the Codex check. It fails when a route cannot run, when the foreground command's nonce does not reach an implement route, when anything but `1` reaches the session shell for a pinned variable, on a subagent, monitor, workflow or scheduled-task start, on an excluded tool offered, and on a capability with no attempt or not exercised; a background shell start and later frames are recorded, not failed. Two legs run on the implement shape with a settings file that sets both variables to `0` in `env`, turns `experimental.cron` on, allows `agent`, `monitor` and `send_message`, and sets `HASHD_LIVE_QWEN_UNRELATED=present`, which must reach the session shell to show the file loaded: (1) as the temp repo's project `.qwen/settings.json`, (2) as user settings under a temp `QWEN_HOME`, which needs no copied credentials because the check requires environment-visible authentication, and which also turns `tools.workflowsEnabled` on. Qwen Code ignores that key in project settings, so leg (1) does not set workflows against their pin and only leg (2) does; a leg (2) launch that cannot run there is logged as not run. It writes no other settings and never reads Qwen Code's credential or session files or messages another session. Once opted in, a missing qwen binary, no `DASHSCOPE_API_KEY` (or `OPENAI_API_KEY` with `OPENAI_BASE_URL`), a missing `pgrep`, or a `qwen --version` other than 0.23.4 fails it.

Documented release: Qwen Code 0.23.4. Installed version: not installed. Opted in on this host, the check stops at its first precondition ("qwen is not on PATH"). No row below is a live result, and none shows the controls enforced:

| Route | Shape | Capability | Result | Work after turn end |
|---|---|---|---|---|
| chat | chat | short foreground command, pinned variables, background shell command, subagent, monitor, workflow, scheduled task, `send_message` offered | not run: qwen not installed; setup authorization pending | not run |
| chat_resume | chat_resume | same as chat | not run: qwen not installed; setup authorization pending | not run |
| review | review | same as chat | not run: qwen not installed; setup authorization pending | not run |
| review_resume | review_resume | same as chat | not run: qwen not installed; setup authorization pending | not run |
| implement | implement | same as chat | not run: qwen not installed; setup authorization pending | not run |
| implement_resume | implement_resume | same as chat | not run: qwen not installed; setup authorization pending | not run |
| conflicting settings (1): project `.qwen/settings.json` | implement | same as chat, plus the unrelated variable | not run: qwen not installed; setup authorization pending | not run |
| conflicting settings (2): user `settings.json` under a temp `QWEN_HOME` | implement | same as chat, plus the unrelated variable | not run: qwen not installed; setup authorization pending | not run |
| any | any | auto-memory, auto-dream and auto-skill review | not run: harness-started, turned off only through `memory.*` settings keys the check never writes | not run |
| any | any | async hooks | not run: hooks come from operator configuration, which the check never writes | not run |
| any | any | Agent Team teammates | not run: off unless a setting or `QWEN_CODE_ENABLE_AGENT_TEAM` enables them, and the check sets neither | not run |
| any | any | messages to or from other Qwen Code sessions | not run: the check never discovers or messages another session | not run |

Every GitHub Copilot CLI launch excludes two tools: `copilotPermFlags` in `server/internal/agents/runner.go` joins `task` and `write_agent` (`copilotStageOwnedTools`) into the launch's one `--excluded-tools` value, after the shape's own `write` and `shell` entries, as a comma-separated list; the implement shapes carry `--yolo --excluded-tools task,write_agent`. The permission flags sit at the end of argv. The prompt goes over stdin, not `-p`. The `--additional-mcp-config` file and the credential environment do not change. Copilot CLI's tool availability values name no `write` or `shell` tool (those are `--allow-tool`/`--deny-tool` permission kinds; its file and shell tools are `create`, `edit`, `apply_patch`, `bash` and `powershell`), so the docs do not show that those two entries remove any tool; they stay as they were pending a decision on the read-only shapes. The `--excluded-tools` value reaches every shape (`print`, `print_resume`, `json`, `edit`, `review`, `review_resume`, `implement`, `implement_resume`, `chat`, `chat_resume`, `detect`), `stage_agents` reassignments and `hashd internal agent-run`. Copilot CLI 1.0.83 documents these ways a stage agent can start work that runs on after its call returns:

- Subagents. `task` runs subagents, `read_agent` checks a background agent's status ([tool availability values](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference#tool-availability-values)), a finished background subagent raises an `agent_completed` notification ([hooks reference](https://docs.github.com/en/copilot/reference/hooks-reference#notification-hook)), `task` takes `mode: "background"` (1.0.35 in the [changelog](https://github.com/github/copilot-cli/blob/v1.0.83/changelog.md)), and a `-p` run waits up to `COPILOT_TASK_WAIT_TIMEOUT_SECONDS` (default 600) for pending background agents and shell commands before it exits; the docs do not say whether a piped prompt run, which hashd launches, waits the same way ([environment variables](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference#environment-variables)). Pinned: `--excluded-tools task`. This also removes subagents that finish inside the turn, and every built-in or custom agent dispatched through `task`.
- Continuing a background agent. `write_agent` sends a message to a running agent, and a background agent that finishes a turn waits idle for one (`agent_idle`) ([tool availability values](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference#tool-availability-values), [hooks reference](https://docs.github.com/en/copilot/reference/hooks-reference#notification-hook)). Pinned: `--excluded-tools write_agent`.

Copilot CLI documents `--excluded-tools` as "These tools will not be available to the model", with several tools given as a comma-separated list ([command-line options](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference#command-line-options)); a tool outside the available set cannot be used even when `--allow-tool` names it, and `--available-tools`, which hashd does not pass, would make it ignore `--excluded-tools` ([allowing and denying tool use](https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/allowing-tools)). It applies command-line flags last, over environment variables, local, repository and user settings and MDM managed settings ([configuration file settings](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference#configuration-file-settings)); `permissions-config.json` does not support tool filtering, and no user, repository or managed settings key listed there makes an excluded tool available. Managed `permissions.disableBypassPermissionsMode` suppresses `--allow-all-tools` and `--yolo`, which acts on the shapes' permissions, not the exclusion. Server-managed settings and organization or enterprise policy apply per account, and hashd cannot observe them: the docs name none that restores an excluded tool, so the claim is limited to the cited documentation and the live check below. hashd does not read, write, override or probe Copilot CLI's user, repository or managed settings.

No flag or variable is pinned for these paths, and they stay open:

- Async and detached shell commands. Copilot CLI raises `shell_completed` when "a background (async) shell command finishes" and `shell_detached_completed` when "a detached shell session completes" ([hooks reference](https://docs.github.com/en/copilot/reference/hooks-reference#notification-hook)), and a detached command is a process "that outlives the tool call" ([command safety analysis](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference#command-safety-analysis)). Both run through the shell tool (`bash` or `powershell`), which also runs foreground commands, and no flag or variable turns off either mode; hashd excludes neither and does not set `COPILOT_TASK_WAIT_TIMEOUT_SECONDS`.
- Sidekick agents, which "run automatically in the background and publish context into the session inbox" on events such as `user.message`, defined by a `sidekick:` block in an agent file from a project's `.github/agents/` or `.claude/agents/`, the user's agents directory or a plugin ([sidekick agents](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference#sidekick-agents), [custom agent locations](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference#custom-agent-locations)). No flag or variable turns them off, and whether excluding `task` stops them is not documented.
- MCP Tasks: in experimental mode, MCP tools with `taskSupport: "required"` run as non-blocking background agents (1.0.41 in the [changelog](https://github.com/github/copilot-cli/blob/v1.0.83/changelog.md)). The only off switch is `--no-experimental`, which turns off every experimental feature, including the per-session sandbox flags, so hashd does not pass it.
- Notification hooks from operator configuration, which fire asynchronously and never block the session ([hooks reference](https://docs.github.com/en/copilot/reference/hooks-reference#notification-hook)).
- Delegation to Copilot cloud agent. `/delegate` and the `&` prompt prefix push a task to Copilot cloud agent, which works in the background on GitHub ([delegating tasks](https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/delegate-tasks-to-cca)). No tool the docs list starts it and no flag turns it off, and a stage agent with shell access and the owner's GitHub token can still reach GitHub itself.
- Remote control, which injects prompts submitted from GitHub.com or GitHub Mobile into the running session. The remote-control pages say a session is steerable only from the local machine by default, that `--remote`, `/remote on` or a user setting turns remote control on, and that a seat from an organization also needs its "View and control" policy ([remote control](https://docs.github.com/en/copilot/concepts/agents/copilot-cli/about-remote-control), [steering remotely](https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/steer-remotely)); the settings reference lists a `remote` setting, default `"on"`, that controls session syncing and remote access ([user settings](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference#user-settings-copilotsettingsjson)). The docs say remote control is available only to interactive sessions and name `--prompt` runs as excluded; they do not say whether a piped prompt run, which hashd launches, is excluded. `--no-remote` is documented as disabling remote access for a session ([command-line options](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference#command-line-options)), and the `remote` setting it overrides also controls session syncing, so hashd does not pass it; whether to pin it is an open decision.

Scheduled prompts (`/every`, `/after`) are experimental slash commands documented as available only inside an interactive session ([scheduling prompts](https://docs.github.com/en/copilot/how-tos/copilot-cli/automate-copilot-cli/schedule-prompts)); no tool the docs list creates one, and the docs do not say whether a piped prompt run counts as an interactive session. All docs.github.com pages retrieved 2026-09-15, when 1.0.83 was the `latest` `@github/copilot` release on npm; the pages carry no version. The changelog is read at the v1.0.83 tag of github/copilot-cli.

The opt-in live check `TestLiveCopilotBackground` (`server/internal/agents/live_copilot_background_test.go`, `HASHD_LIVE_COPILOT=1`) launches the real copilot binary through `RunStageWithOptions` in one temp git repo with a temp project config naming copilot in `stage_agents`, with `COPILOT_HOME` and `COPILOT_CACHE_HOME` in temp directories and `COPILOT_AUTO_UPDATE=false`. Routes: review, review_resume, implement, implement_resume, chat and chat_resume. Each turn asks for a short foreground command, a shell command in async mode and one detached, both left running, a subagent through `task` in background mode, whether `write_agent` is offered without calling it, and a last foreground command that prints a nonce and the time. Every command ends by printing a nonce the test wrote outside the repo; the probe work is a `sh -c` command whose `$0` is a random token, which sleeps 60 seconds and writes a marker file. After the run returns, the check looks for the process with `pgrep -f` and for the marker, waits 90 seconds, then looks again. A marker written after the last command's time is work that finished after the turn, whether or not the run waited for it: the docs document that wait for `-p` runs only. Copilot CLI documents no JSONL event schema, so the check decodes none, and reads each report line from its first match in the agent text. Results use the same six values as the Codex check. It fails when a route cannot run, when the foreground command's nonce does not reach an implement route, on a subagent that ran or `write_agent` offered, and on a capability with no attempt or not exercised; an async or detached shell start is recorded, not failed. The implement shape prints plain text with no session id, so unless it prints one the check logs implement_resume as not exercised and fails, and does not borrow another route's session. Once opted in, a missing copilot binary, no `COPILOT_GITHUB_TOKEN`, `GH_TOKEN` or `GITHUB_TOKEN`, a missing `pgrep`, or a `copilot --version` other than 1.0.83 fails it.

Documented release: Copilot CLI 1.0.83. Installed version: not installed. Opted in on this host, the check stops at its first precondition ("copilot is not on PATH"). No row below is a live result, and none shows the exclusion enforced:

| Route | Shape | Capability | Result | Work after turn end |
|---|---|---|---|---|
| review | review | short foreground command, async shell command, detached shell command, subagent, `write_agent` offered | not run: copilot not installed; setup authorization pending | not run |
| review_resume | review_resume | same as review | not run: copilot not installed; setup authorization pending | not run |
| implement | implement | same as review | not run: copilot not installed; setup authorization pending | not run |
| implement_resume | implement_resume | same as review | not run: copilot not installed; setup authorization pending | not run |
| chat | chat | same as review | not run: copilot not installed; setup authorization pending | not run |
| chat_resume | chat_resume | same as review | not run: copilot not installed; setup authorization pending | not run |
| conflicting config | any | any | not run: Copilot CLI documents no setting that makes a tool `--excluded-tools` removed available again | not run |
| any | any | delegation to Copilot cloud agent (`/delegate`, `&`) | not exercised: remote | not run |
| any | any | sidekick agents | not run: they come from operator agent configuration, which the check never writes | not run |
| any | any | MCP Tasks background agents | not run: needs experimental mode and an operator MCP server, neither of which the check sets up | not run |
| any | any | notification hooks | not run: hooks come from operator configuration, which the check never writes | not run |
| any | any | scheduled prompts (`/every`, `/after`) | not run: documented as slash commands inside an interactive session; the docs do not say whether a piped prompt run counts as one | not run |
| any | any | remote control | not exercised: remote; the docs name `--prompt` runs as excluded, not piped prompt runs, and `--no-remote` is not pinned | not run |

### Kimi Code 2.x Launch Contract

The registry targets **Kimi Code 2.x**, not the retired Python `kimi-cli`.
Issue #1855's command-shape fix landed in #1858; #1857 covers the remaining
launch defects. The current implementation was checked against the published
2.1.1 executable and [upstream source at a940f2ff](https://github.com/MoonshotAI/kimi-code/tree/a940f2ff049ed57abce68c59526de7a6628a4112).

- Kimi ignores piped stdin. Its ten shapes use `-p {prompt}`. The runner
  substitutes the prompt **after** splitting the template, as one literal argv
  element; there is no shell expansion and nothing is truncated. This exception
  is Kimi-only. Unlike stdin, argv is visible to local process inspection and
  subject to OS argument-size limits; an oversized prompt fails the launch.
- Fresh sessions use `--agent-file <HASHD_ROOT>/agent_policies/kimi.md`. The
  Markdown frontmatter denies both `Agent` and `AgentSwarm`, sets `subagents: []`,
  and the body embeds `${base_prompt}` to retain the normal system instructions.
  Other tools, including foreground shell execution, remain available.
- Kimi persists the agent binding at session creation. A resume uses
  `--session <id>` without `--agent-file`, which 2.x rejects in combination.
  Before that launch, `verifyKimiResumePolicy` replays the session's main-agent
  journal (`<KIMI_CODE_HOME>/sessions/<workspace>/<id>/agents/main/wire.jsonl`,
  protocol 1.5) the way Kimi restores it: every line in order up to the first
  corrupted one (where Kimi's own read stops), records Kimi would skip or reject
  by schema skipped, `profile.bind` replacing and `config.update` amending the
  policy. The resume runs only when the result still denies `Agent` and
  `AgentSwarm` with `subagents: []`, whoever created the session; an
  unprotected session (one created outside hashd or before this policy without
  those restrictions), a journal it cannot find or read, or another journal
  version is refused with a diagnostic and nothing launches. Restrictions are
  never retrofitted; start a new hashd session instead.
- `--max-ralph-iterations` belongs to the retired CLI and is not sent. No claim
  is made that this fixes background shell execution, hooks or all autonomous
  continuation features. No native read-only enforcement has been added.
- Registered API keys use an isolated `KIMI_CODE_HOME/config.toml` with
  `api_key_env = "KIMI_API_KEY"`, not an empty `api_key` or legacy
  `KIMI_SHARE_DIR`. The secret stays in the injected environment. Auto-update is
  disabled for that injected process with `KIMI_CODE_NO_AUTO_UPDATE=1`.
- `verify_auth` remains absent: listing providers on an empty home exits zero
  and is not evidence of authentication. Registry status remains `available`.

`TestRunStageWithOptionsPinsKimiStageOwnedArgs` covers every shape with and
without MCP injection; the credential test pins the isolated home and key
binding. The opt-in `TestKimiCodeLocalProvider` uses a real 2.x executable with a
local fake API and disposable home. It verifies literal prompt delivery,
registered-key configuration, fresh/resumed plain and stream-JSON output,
session IDs, ordinary tools retained and both delegation tools absent, and that
a session the executable created without the policy is refused on resume before
reaching the provider. `TestReadKimiResumePolicy` covers the journal replay rules
and `TestRunStageRefusesUnverifiedKimiResumeBeforeLaunch` the runner's refusal.
The opt-in check makes no paid model calls. Run it with `HASHD_TEST_KIMI_BINARY=/path/to/kimi`.

### Historical Kimi 1.x Audit (Not The Current Launch Contract)

The following records the superseded 1.50.0 investigation and its unexecuted
background-work probes. Its flags, YAML policy and home paths are historical,
not instructions for Kimi Code 2.x. `TestLiveKimiBackground` is also a legacy
1.50.0 probe, not validation of the current launcher; the local-provider test
above is the 2.x launch check. Retaining this audit does not claim its controls
or background-work guarantees were verified.

Every Kimi Code CLI (`kimi-cli`) launch pins two controls: `kimiStageOwnedArgs` in `server/internal/agents/runner.go` puts `--agent-file <install root>/agent_policies/kimi.yaml` and `--max-ralph-iterations 0` right after the binary, after credential and MCP injection. Every kimi shape ends in `-p` with the prompt on stdin, so the flags go before the shape's own arguments, which fresh and `--resume` launches both accept. `agent_policies/kimi.yaml` is an authored file in the hashd source that the core wheel ships under `hashd_data` next to `prompts/`, `templates/` and `schemas/`; the launcher reads it from `$HASHD_ROOT`, the install root the `hashd` and `hashd-server` bootstrap sets for a source checkout and a packaged install alike. It is `version: 1` with `extend: default` and `exclude_tools: ["kimi_cli.tools.agent:Agent"]`, so the built-in default agent's prompt and every other tool stay as they are. With `HASHD_ROOT` unset, or no file there, the stage fails with a diagnostic before kimi starts rather than launching with subagents available. The `--mcp-config-file` temp file, the credential environment and `KIMI_SHARE_DIR` `config.toml`, and the empty permission flags behind the best-effort read-only status do not change. That reaches every shape (`print`, `print_resume`, `json`, `edit`, `review`, `review_resume`, `implement`, `implement_resume`, `chat`, `chat_resume`, `detect`), `stage_agents` reassignments and `hashd internal agent-run`. kimi-cli 1.50.0 documents these ways a stage agent's run can go on after its turn:

- Ralph Loop, which feeds the same prompt again as further iterations after each user message until the agent outputs `<choice>STOP</choice>` or the limit is reached; `0` disables it, `-1` is unlimited, and the default is `0` ([`kimi` command](https://github.com/MoonshotAI/kimi-cli/blob/1.50.0/docs/en/reference/kimi-command.md#loop-control), [config files](https://github.com/MoonshotAI/kimi-cli/blob/1.50.0/docs/en/configuration/config-files.md#loop_control)). kimi-cli applies command-line flags over its config file, and only environment variables outrank flags; no variable is documented for this setting ([config overrides](https://github.com/MoonshotAI/kimi-cli/blob/1.50.0/docs/en/configuration/overrides.md#priority), [environment variables](https://github.com/MoonshotAI/kimi-cli/blob/1.50.0/docs/en/configuration/env-vars.md)). Pinned: `--max-ralph-iterations 0`. kimi-cli added the flag in 0.73 (2026-01-09, in the [changelog](https://github.com/MoonshotAI/kimi-cli/blob/1.50.0/docs/en/release-notes/changelog.md)). hashd declares no minimum kimi-cli version and does not check the installed one, so a launch on a release older than 0.73 is expected to fail on the unknown flag.
- Subagents. `Agent` starts or resumes a subagent in the foreground or, with `run_in_background=true`, in the background, for up to `background.agent_task_timeout_s` (default 900 seconds); a one-shot `--print` run waits for background agents and lets the model process their results; and subagent instances persist with the session, so a resumed session can continue one through `resume` ([agents and subagents](https://github.com/MoonshotAI/kimi-cli/blob/1.50.0/docs/en/customization/agents.md#agent), [config files](https://github.com/MoonshotAI/kimi-cli/blob/1.50.0/docs/en/configuration/config-files.md#background), [sessions](https://github.com/MoonshotAI/kimi-cli/blob/1.50.0/docs/en/guides/sessions.md#session-state-persistence)). An agent file loaded with `--agent-file` can `extend` the built-in `default` agent and list tools in `exclude_tools`, and `Agent` is `kimi_cli.tools.agent:Agent` ([custom agent files](https://github.com/MoonshotAI/kimi-cli/blob/1.50.0/docs/en/customization/agents.md#custom-agent-files)). Pinned: `--agent-file` naming the shipped policy file. This also removes subagents that finish inside the turn. The config file reference lists no key that adds back a tool an agent file excludes. The system prompt is frozen when a session is created and subagent instances are restored on resume ([data locations](https://github.com/MoonshotAI/kimi-cli/blob/1.50.0/docs/en/configuration/data-locations.md#contextjsonl)); the docs do not say whether a resumed session takes its tool list from the agent file it is resumed with. Resume launches carry the same file, and the live check below resumes only sessions created with it, which cannot tell a tool list frozen at creation from one read again on resume. Resuming a session created without the policy, such as an implement or review session started before hashd shipped it, is an open, unverified limitation: that session may still offer `Agent`.

No flag or variable is pinned for this path, and it stays open:

- Background Shell commands. `Shell` with `run_in_background=true` returns a task ID at once while the command keeps running, and its completion is sent to the agent, starting a new turn when the agent is idle ([agents and subagents](https://github.com/MoonshotAI/kimi-cli/blob/1.50.0/docs/en/customization/agents.md#shell), [background tasks](https://github.com/MoonshotAI/kimi-cli/blob/1.50.0/docs/en/guides/interaction.md#background-tasks)). A one-shot `--print` run waits for running background tasks before it exits and lets the model process their results, up to `background.print_wait_ceiling_s` (default 3600 seconds), then kills them; `background.keep_alive_on_exit = true` keeps background tasks running after the CLI exits ([config files](https://github.com/MoonshotAI/kimi-cli/blob/1.50.0/docs/en/configuration/config-files.md#background), 1.37.0 in the [changelog](https://github.com/MoonshotAI/kimi-cli/blob/1.50.0/docs/en/release-notes/changelog.md)). The only controls are `[background]` config keys, and `Shell` also runs foreground commands, so hashd excludes nothing and writes no config.

Hooks from the config file run with a timeout (default 30 seconds) and fail open, are not documented as asynchronous, and a `Stop` hook can keep the turn going once ([hooks](https://github.com/MoonshotAI/kimi-cli/blob/1.50.0/docs/en/customization/hooks.md)); hashd leaves operator hooks as they are. `SendDMail` is offered only by the `okabe` agent, and hashd passes no `--agent`. Flow skills run several turns, but the docs name only the `/flow:<name>` command as a way to start one ([skills](https://github.com/MoonshotAI/kimi-cli/blob/1.50.0/docs/en/customization/skills.md#flow-skills)). The docs describe no scheduled or deferred tasks, no messages into a print-mode session from another session, and no managed or organization policy. The documented priority puts the flags over `config.toml` under `KIMI_SHARE_DIR` or `~/.kimi`; the docs do not say whether anything else on a host can change that, and hashd cannot observe it. hashd does not read, write, override or probe kimi-cli's user configuration. All pages retrieved 2026-09-15 at the 1.50.0 tag of MoonshotAI/kimi-cli, the latest `kimi-cli` release on PyPI that day, and checked against the [official docs site](https://moonshotai.github.io/kimi-cli/). The 1.50.0 README and docs index say kimi-cli is being wound down in favour of a separate Kimi Code product; none of that product's documentation is used here.

The opt-in live check `TestLiveKimiBackground` (`server/internal/agents/live_kimi_background_test.go`, `HASHD_LIVE_KIMI=1`) launches the real kimi binary through `RunStageWithOptions` in one temp git repo with a temp project config naming kimi in `stage_agents`, with `KIMI_CLI_NO_AUTO_UPDATE=1` and `KIMI_SHARE_DIR` in a temp directory holding a disposable `config.toml` in the shape `server/internal/credinject/plan.go` materializes: an empty `api_key` (the key rides `KIMI_API_KEY`) and the model named by `HASHD_LIVE_KIMI_MODEL`, and with `HASHD_ROOT` at the source checkout, so `--agent-file` names the `agent_policies/kimi.yaml` the wheel ships. Routes: review, review_resume, implement, implement_resume, chat and chat_resume; each resume takes the session id from kimi's stderr resume hint. kimi-cli documents that `--resume` with an id it does not find creates a new session, so a resume route counts only when the resumed turn reports the nonce its fresh route's foreground command read from a file the check deletes before resuming; otherwise the route is not exercised and its probes are not reported as resume results. A fresh route whose foreground command's nonce did not come back leaves its resume route not exercised without launching it. Each turn asks for a short foreground command, a `Shell` command with `run_in_background`, a subagent through `Agent` with `run_in_background`, and a last foreground command that prints a nonce and the time. Every command ends by printing a nonce the test wrote outside the repo; the probe work is a `sh -c` command whose `$0` is a random token, which sleeps 60 seconds and writes a marker file. After the run returns, the check looks for the process with `pgrep -f` and for the marker, waits 90 seconds, then looks again; a marker written after the last command's time is work that finished after the turn, whether or not the run waited for it. The review and chat routes print stream-json messages, which the check decodes for tool calls carrying a probe's token and `run_in_background`, and for messages after the one carrying the last command's line; the implement routes print plain text, so their results rest on the process, marker, nonce and the agent's report. Results use the same six values as the Codex check. It fails when a route cannot run, when the foreground command's nonce does not reach an implement route, when a fresh route prints no session id for its resume route or a resume route does not show it continued that session, on a subagent that ran in the background or the foreground on any route, fresh or resumed, and on a capability with no attempt or not exercised; a background shell start is recorded, not failed. On the stream-json routes a subagent probe counts against the policy only when the output records it running through `Agent`: one recorded only through `Shell` or another tool is not exercised. The plain-text implement routes record no calls, so a subagent probe that ran there fails with a note that the output does not show which tool ran it. One leg writes a temp `config.toml` that also sets `loop_control.max_ralph_iterations = 2` and a `SessionStart` hook appending to a file, and runs one prompt, a foreground command that appends a line to a counter file plus a reply line carrying its nonce, twice, each with its own temp `KIMI_SHARE_DIR` and repo and both printing stream-json: once as a baseline that invokes kimi directly without the flag, and once as the review stage through the launcher. An iteration can end without running the command again, so it counts as a second counter line or a decoded message after the first reply carrying the nonce. The leg reports the flag holding only when the baseline iterated and the launcher's run did not, fails on an iteration in the launcher's run, and is not exercised when either run shows no hook run or no message stream, the command never ran, or the baseline did not iterate either. kimi-cli documents `-p` as taking the prompt text and stdin input as a pipe into `kimi --print`; every kimi shape ends in a bare `-p` with the prompt on stdin, so whether that launch parses at all is for the live check to show. It never reads the real share directory, kimi-cli's credential files or skills directories, and never runs `kimi login`. Once opted in, a missing kimi binary, no `KIMI_API_KEY`, no `HASHD_LIVE_KIMI_MODEL`, a missing `pgrep`, or a `kimi --version` other than 1.50.0 fails it.

Documented release: kimi-cli 1.50.0. Installed version: not installed. Opted in on this host, the check stops at its first precondition ("kimi is not on PATH"). No row below is a live result, and none shows either pinned control enforced, including on resume:

| Route | Shape | Capability | Result | Work after turn end |
|---|---|---|---|---|
| review | review | short foreground command, background shell command, background subagent | not run: kimi not installed; setup authorization pending | not run |
| review_resume | review_resume | same as review | not run: kimi not installed; setup authorization pending | not run |
| implement | implement | same as review | not run: kimi not installed; setup authorization pending | not run |
| implement_resume | implement_resume | same as review | not run: kimi not installed; setup authorization pending | not run |
| chat | chat | same as review | not run: kimi not installed; setup authorization pending | not run |
| chat_resume | chat_resume | same as review | not run: kimi not installed; setup authorization pending | not run |
| conflicting config: `loop_control.max_ralph_iterations = 2` with a `SessionStart` hook in the temp `config.toml`, against a baseline run without the flag | review | Ralph Loop iterations | not run: kimi not installed; setup authorization pending | not run |
| review_resume, implement_resume, chat_resume | resume shapes | subagents in a session created without the policy file and resumed with it | not run: the check creates every session with the policy file; open, unverified limitation | not run |
| any | any | background tasks kept alive after exit (`background.keep_alive_on_exit`) | not run: a config key the check never sets | not run |
| any | any | hooks from operator configuration | not run: the check writes only its own temp config | not run |
| any | any | `SendDMail` | not run: only the `okabe` agent offers it, and hashd passes no `--agent` | not run |
| any | any | flow skills | not run: started by a `/flow:` command, which no stage prompt is | not run |

hashd's `opencode` registry entry targets OpenCode 1.18.31 ([anomalyco/opencode](https://github.com/anomalyco/opencode), npm `opencode-ai`, the latest release on 2026-09-16): every shape runs `opencode run --format json`: `run` reads the prompt from piped stdin, `--format json` prints one event per line carrying a top-level `sessionID`, and `--session` continues a session and exits with "Session not found" for an id it does not have ([`run` command](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/cli/cmd/run.ts), [CLI](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/web/src/content/docs/cli.mdx#run)). MCP servers reach it through the per-process `OPENCODE_CONFIG_CONTENT` inline config in OpenCode's `mcp` shape (`type: "local"`, `command` as one array, `environment`), merged into the inherited value so its other settings stay as they are ("OpenCode distribution and configuration" above), since OpenCode ignores config keys it does not define ([MCP servers](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/web/src/content/docs/mcp-servers.mdx), [config parsing](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/config/parse.ts)).

Every opencode launch pins two environment variables: `opencodeStageOwnedEnv` in `server/internal/agents/runner.go` sets them after credential and MCP injection, so argv and the stdin prompt stay as the shape builds them. That reaches every shape (`print`, `print_resume`, `json`, `review`, `review_resume`, `implement`, `implement_resume`, `chat`, `chat_resume`, `detect`), `stage_agents` reassignments and `hashd internal agent-run`. The permission flags stay empty and read-only stays best-effort. OpenCode 1.18.31 has these ways a stage agent's run can go on after its turn:

- Subagents. The `task` tool starts a subagent in a child session, in the foreground by default; with `background: true` it returns at once and later sends the subagent's result into the parent session as a new prompt, and a running foreground task can also be promoted to a background job; the source read here does not show what promotes one ([`task` tool](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/tool/task.ts), [agents](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/web/src/content/docs/agents.mdx#task-permissions)). Pinned: `OPENCODE_PERMISSION`, the documented inline permission config ([environment variables](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/web/src/content/docs/cli.mdx#environment-variables)), with `"task":"deny"` as its last key. An inherited value keeps every other key in its order and as written, since the last matching rule wins ([permissions](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/web/src/content/docs/permissions.mdx#granular-rules-object-syntax)); a value OpenCode cannot parse, which it skips, is replaced, and so is valid JSON that is not an object: OpenCode deep-merges the parsed variable without the config schema's normalization of a single action such as `"allow"` to `{"*":"allow"}`, so a string spreads into index keys that name no permission and holds no rule to keep ([config loading](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/config/config.ts)). A denied `task` call is rejected and the tool description lists no subagent, so this also removes subagents that finish inside the turn. Also pinned: `OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=false`, the documented background-subagent switch. OpenCode reads it only from the process environment, and an explicit value outranks the `OPENCODE_EXPERIMENTAL` umbrella; while it is false the `task` tool rejects a background call before it checks the permission ([runtime flags](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/effect/runtime-flags.ts)).

Config can defeat the `task` denial, and hashd cannot observe it. OpenCode merges `OPENCODE_PERMISSION` into the permission object after every config source, managed config files and macOS managed preferences included ([config loading](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/config/config.ts)), but an agent's own `permission`, from `agent` in any config file or an agent Markdown file, is applied after it for that agent, and the docs say agent rules take precedence ([agent permissions](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/agent/agent.ts), [permissions](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/web/src/content/docs/permissions.mdx#agents)). A config file that already sets `task` keeps that key's place in the merged object, so a wildcard rule it lists after `task` also re-allows it. Where config allows `task` again, foreground subagents run; background ones stay refused by the variable, which no config key sets. The docs also let a user invoke any subagent with an `@` mention even when `task` is denied; `opencode run` sends the stdin prompt as one text part, not a mention.

No flag or variable is pinned for this path, and it stays open:

- Shell commands that background themselves. The `bash` tool has no background mode: it starts the command in its own process group and waits for that shell to exit, killing it only on timeout or abort ([`bash` tool](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/tool/shell.ts)). A command that backgrounds a child with `&`, `nohup` or `setsid` returns while the child keeps running, and `opencode run` stops reading the session's events once the session first goes idle, so it does not wait for the child. No flag or variable turns this off, and `bash` also runs foreground commands, so hashd denies nothing.

Plugins, loaded from config files or `.opencode/plugins/`, run code inside the opencode process on its events ([config](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/web/src/content/docs/config.mdx#plugins)); hashd leaves operator plugins as they are and does not pass `--pure`, which drops every external plugin. Without `--attach`, `opencode run` talks to its server in-process rather than through a listening port, so no other client can prompt the stage session. The CLI, tool, agent and config documentation describe no scheduled or deferred tasks. hashd does not read, write, override or probe OpenCode's user, project or managed configuration beyond the `OPENCODE_CONFIG_CONTENT` value it builds from the inherited one to add its MCP servers. Source and documentation retrieved 2026-09-16 at the v1.18.31 tag of anomalyco/opencode, the latest release on GitHub and npm (`opencode-ai`) that day.

The opt-in live check `TestLiveOpencodeBackground` (`server/internal/agents/live_opencode_background_test.go`, `HASHD_LIVE_OPENCODE=1`) launches the real opencode binary through `RunStageWithOptions` in one temp git repo with a temp project config naming opencode in `stage_agents`, with `HOME` and the four XDG base directories pointing at temp directories, so OpenCode's global config, auth store, sessions and caches are disposable; a temp global `opencode.json` names the model from `HASHD_LIVE_OPENCODE_MODEL` and disables sharing and autoupdate, and the provider key rides the variable `HASHD_LIVE_OPENCODE_KEY_ENV` names. Routes: review, review_resume, implement, implement_resume, chat and chat_resume; each resume takes the session id `extractSessionID` finds in its fresh route's output. Each turn asks for a short foreground command, a `bash` command that backgrounds its work with `nohup ... &`, a foreground subagent through `task`, a background subagent through `task`, and a last foreground command that prints a nonce and the time. The probes and markers, the 90-second wait and the six result values are the same as the Kimi check, except that the nonce files sit in the repo: OpenCode's `bash` tool asks for `external_directory` permission before `cat` names a path outside it, and `opencode run` rejects every ask. There OpenCode's `read`, `grep` and `glob` tools can read them without an ask, so a nonce the agent reports shows the file was read, not that the command ran. On every route the check decodes `tool_use` events for calls carrying a probe's token, their `background` input and a failed state's error, and counts `step_start` events after the text carrying the end line. It fails when a route cannot run, when the foreground command's nonce does not reach an implement route, when a fresh route prints no session id for its resume route, on a subagent that ran, in the background or the foreground, on any route, and on a capability with no attempt or not exercised; a background shell start is recorded, not failed. One leg writes a temp project `opencode.json` giving the build agent its own permission allowing `task` and an unrelated `instructions` file holding a canary, and runs the review stage once: the leg is not exercised when the canary does not come back, records a foreground subagent that runs as the limitation above, and fails on any subagent work that starts in the background. Managed config on the host fails the check instead of being bypassed. Once opted in, a missing opencode binary, no `HASHD_LIVE_OPENCODE_KEY_ENV` or an empty variable under that name, no `HASHD_LIVE_OPENCODE_MODEL`, a missing `pgrep`, or an `opencode --version` other than 1.18.31 fails it.

Documented release: OpenCode 1.18.31. Installed version: not installed. Opted in on this host, the check stops at its first precondition ("opencode is not on PATH"). No row below is a live result, and none shows either pinned variable enforced:

| Route | Shape | Capability | Result | Work after turn end |
|---|---|---|---|---|
| review | review | short foreground command, self-backgrounded shell command, foreground subagent, background subagent | not run: opencode not installed; setup authorization pending | not run |
| review_resume | review_resume | same as review | not run: opencode not installed; setup authorization pending | not run |
| implement | implement | same as review | not run: opencode not installed; setup authorization pending | not run |
| implement_resume | implement_resume | same as review | not run: opencode not installed; setup authorization pending | not run |
| chat | chat | same as review | not run: opencode not installed; setup authorization pending | not run |
| chat_resume | chat_resume | same as review | not run: opencode not installed; setup authorization pending | not run |
| conflicting config: `agent.build.permission.task: "allow"` with an `instructions` canary in the temp project `opencode.json` | review | foreground subagent, background subagent | not run: opencode not installed; setup authorization pending | not run |
| review_resume, implement_resume, chat_resume | resume shapes | subagents in a session created without the pinned variables | not run: every session the check resumes is created by the launcher | not run |
| any | any | plugins and hooks from operator configuration | not run: the check writes only its own temp config | not run |

### Internal Wrapper Coverage

`hashd internal agent-run` supports the stages that use the generic agent-run
bridge: `adjudicate`, `concern_triage`, `final_review`, `fix_generation`,
`freeform` (alias for `final_review`), `implement`, `implement_resume`,
`plan_add`, `pm_annotate`, `pm_breakdown` (alias for `breakdown`),
`pm_describe`, `pm_discovery`, `pm_docs`, `pm_edit`, `pm_refine`, `pm_route`,
`pm_spec`, `review`, and `review_resume`.

Dedicated internal wrappers handle `detect`, `tech_tree`, `plan_split`, and the
review-stage scaffold where the stage needs extra loaded context or special
parsing before or after the agent call.

---

## Agent Contract

What a CLI must implement to be a hashd agent, and how hashd invokes it for
fresh and resumed work. The registry (`server/internal/config/defaults.yaml
agents:`) declares each agent's conformance; `agents.RunStageWithOptions`
assembles every invocation from the stage's shape template plus the
capability-derived permission flags (see Agent Tool Permissions above).

### Required capabilities

| # | Capability | Registry surface | Why |
|---|---|---|---|
| C1 | Non-interactive prompt intake on **stdin** | `{prompt}` is a stdin sentinel, never argv; agents with no bare-stdin mode declare `prompt_stdin_sentinel` (codex `-`) or `prompt_value_flags` (`-p`/`--prompt`) | Prompts exceed argv limits and must not leak into `ps` |
| C2 | Machine-parseable output for structured stages | shape templates carry the agent's JSON/stream flags (`--output-format json`, `--json`, ...) | Verdicts, results, and session ids are parsed, never scraped |
| C3 | **Session identity**: emit a session id in machine-readable output | per-agent extractor in `server/internal/agents/session_id.go` (codex JSONL events, gemini/qwen `session_id` keys, opencode `sessionID`, copilot `session.start`, kimi stderr hint) | Resume is impossible without capturing the id |
| C4 | **Session resume**: an invocation that continues the same conversation from that id | `_resume` shape templates with `{session_id}` (claude/gemini/kimi/qwen/copilot `--resume`, codex `exec resume` / app-server `thread/resume`, opencode `--session`) | Dirty-tree continuity on retry, and the token payoff: a resumed turn sends only the new instruction instead of re-sending the full prompt |
| C5 | Distinguishable missing-session errors | `sessionResumePatterns` in `server/internal/agents/classifier.go` (`session_not_found` classification) | A dead session must fall back to a fresh run, not retry-loop |
| C6 | Permission flags mappable to `shape_capabilities` | per-agent flag translators in `runner.go` (`--dangerously-skip-permissions`, `sandbox_mode=...`, `--approval-mode ...`); agents without a read-only mode are best-effort and documented as such | Shape intent (writes/bash) is enforced per agent |
| C7 | Auth verification verb | `verify_auth` (`claude auth status`, `codex login status`, ...); omit rather than guess when the CLI has no reliable verb | Preflight without inspecting private credential files |

An agent missing C3/C4 still works for every one-shot stage; it simply never
takes a `_resume` path (each retry re-sends the full prompt). An agent missing
C6's read-only mode may only be trusted with write-shaped stages.

#### C2 detail: message attribution

C2 asks for machine-parseable output. A **review verdict** asks for more than
that: the round's answer must be attributable to a turn, not just present
somewhere in stdout. A shape that emits only a terminal envelope collapses the
whole run into one string, so anything landing after the reviewer's answer --
an injected task notification, a stray follow-up turn -- becomes
indistinguishable from the answer itself.

When a shape emits a message stream, `agents.AssistantMessages` reads the
round's messages out of it and the verdict is taken from the newest message
that carries a review object. What that requires of a stream:

- Each of the agent's own messages is a distinguishable frame, in order
  (claude stream-json `type:"assistant"`, codex `item.completed` with
  `item.type:"agent_message"`, kimi `role:"assistant"`).
- Frames that are **not** the agent speaking are labelled as such and are
  excluded: user turns, tool results, and nested Task-subagent frames (claude
  marks these with a non-null `parent_tool_use_id` -- a subagent's output is a
  tool's output wearing an assistant frame).
- Message text declares itself text. Attribution counts a content block only
  when it says it is text, so a tool argument can never be read as something
  the agent said. This rule is stricter than the one the response unwrap
  applies (`contentText` counts any block carrying a text key), and the two
  disagreeing is the third degrade below.

Newest wins at both levels: the newest message is searched first, and within a
message the last object is tried first, so an agent that quotes an earlier
verdict and then gives its own has its own recorded. Inside that newest message
position is the only signal there is, so its trailing UNTERMINATED object is
tried ahead of its complete ones -- a run cut off mid-object was writing its
answer, and a complete object before it is as likely to be a quote. A complete
object outranks a repaired one only ACROSS messages: a message that ends
unterminated with another message after it was split rather than truncated, and
joining the messages -- which stays inside the agent's own text -- recovers the
split object whole. There is no fallback to scanning raw stdout.

Degrading to the terminal-envelope path -- the pre-attribution behaviour -- is
never an error, and WHEN it happens is a tier the stage names. The tiers are
`agents.EnvelopeTier` (`server/internal/agents/messages.go`), which is the
whole of the messages-versus-envelope decision: `PayloadScopes` /
`SelectAgentPayload` answer it once, and a stage names its tier rather than
deciding again.

Two cases are every stage's, because there is no attribution to lose in them:

- Stdout carries no message stream (a single terminal envelope, or plain text).
- The stdout shape is one `AssistantMessages` does not model.

Above those the stages differ, and each difference is a ruling rather than a
preference:

| Tier | Additionally reads the envelope when | Whose |
|---|---|---|
| `EnvelopeWhenNoStream` | never -- a recognized stream answers for itself, including when it carries nothing the caller accepts | the implementer's status payload (operator ruling CLQ-171) |
| `EnvelopeWhenNoMessageText` | a recognized stream yields no message text at all AND the runner's unwrap resolved an answer anyway | the review verdict |
| `EnvelopeWhenNothingSelected` | the agent's own messages carry nothing the caller accepts | the adjudication judges |

The middle row is a disagreement between two readers of the same stdout, so it
means the shape is modelled wrong rather than the agent being silent -- the
likeliest cause being content blocks labelled loosely enough that the strict
text rule above drops what the unwrap's permissive rule keeps. Reporting no
answer there would burn every semantic retry on a round the agent did answer.
Review stops there deliberately: once ANY message text has been read the stream
is attributable, and reaching past it would let whatever landed in the envelope
after the reviewer's answer supply the verdict. The bottom row goes further
only because a judge is not asked again -- it gets one shot, so a verdict it did
give outranks the fail-closed park. The top row stops short because the
operator ruled that the implementer's own turns decide its status.

No tier reads RAW stdout. The envelope is the runner's RESOLVED response, and
only when it resolved something: `UnwrapResponseText` returns stdout verbatim
when it cannot unwrap, and counting that as an answer would put the caller back
on the brace walk this exists to replace.

Which shapes stream is a `defaults.yaml` question, not a parser one, and it is
answered at two layers: a default install runs `stages.<name>.command`, while a
stage reassigned via `stage_agents` runs the named agent's SHAPE, resolved
through `stageShapeMap` (`server/internal/agents/runner.go`). Both layers for
the claude agent:

| Stage | Default (`stages.<name>.command`) | Shape it maps to | Reassigned to claude |
|---|---|---|---|
| `review` / `review_resume` | stream-json | `review` / `review_resume` | stream-json |
| `final_review` | `--output-format json` | `review` | stream-json |
| `adjudicate` | `--output-format json` | `review` | stream-json |
| `breakdown` | `--output-format json` | `review` | stream-json |

So attribution is live on the shipped default agent for `review` and
`review_resume`, and live for `final_review`, `adjudicate` and `breakdown` only
when `stage_agents.<stage>: claude` puts them on the shape rather than their own
command. Final-review output repairs use the `review_resume` invocation shape
of the configured final reviewer, retaining its agent/model/timeout policy.
For claude this streams either way. It is live for the codex (`--json` JSONL) and kimi
(stream-json) review shapes on every one of those stages.

The same selection reads every structured payload a stage takes as an agent's
answer -- the review verdict, the implementer's terminal status payload
(`ParseImplementStatus`), and the adjudication judges' verdicts
(`parseVerdict`) -- so the ordering above is stated once and holds for all
three, and they differ only in the tier each names. Which of them takes the
message path at all is the same `defaults.yaml` question, answered by the table
above: `implement` streams (stream-json) under the shipped claude agent, so
attribution is live there; `adjudicate` keeps the single-envelope shape on the
default agent, and streams when reassigned to claude or run on the codex and
kimi shapes.

### Invocation placeholders

| Placeholder | Meaning | Guard |
|---|---|---|
| `{prompt}` | stdin sentinel (legacy spelling; prompt always rides stdin) | rewritten at assembly |
| `{session_id}` | the resume id | command fails fast if the template needs it and the value is empty |
| `{worktree}` | implement cwd flag (codex `-C {worktree}`) | |
| `{model}` / `{effort}` | rendered through the agent's `model_template` / `effort_template` | dropped when the agent declares no template |

An agent that declares `effort_template` must also declare `effort_levels`, the
values its effort flag accepts (claude `low`..`max`, codex `low`/`medium`/`high`);
an agent with no `effort_template` declares none. `TestLoadRegistryEffortLevels`
enforces the pairing.

### Fresh vs resumed invocations by stage

Reference shapes shown for the default agent (claude); every agent substitutes
its own template for the same shape. "Resume trigger" is who decides to take
the `_resume` path.

Each fresh/resume pair reads one `stages.<base>.timeout` setting, including
defaults and overrides. Resume stages have no separate timeout setting or alias;
deadline diagnostics name the base setting. Outer activity floors/margins remain.

| Stage | Fresh invocation (claude) | Resumed invocation (claude) | Resume trigger | Session store |
|---|---|---|---|---|
| implement | `claude --output-format stream-json --verbose -p` (stdin: full commit prompt + branch diff; session captured before work) | `claude --resume {session_id} --output-format stream-json --verbose -p` (stdin: retry feedback or crash reorientation) | saved session + retry feedback or crash retry; same rule for FIX (`runflow/implementdriver.go`) | `workstreams.codex_session_id` (durable) |
| review | `claude --output-format stream-json --verbose -p` (the verdict is read out of the reviewer's own assistant messages, so the round's turns have to reach stdout) | `claude --resume {session_id} --output-format stream-json --verbose -p` (stdin: retry/redraft delta) | in-package semantic-retry and format-redraft loops (`stages/review/retry.go`) | in-process (same stage run) |
| final_review | `claude --output-format json -p` | configured final reviewer's `review_resume` shape (stdin: repair delta) | shared output-repair loop; final-review policy retained | in-process (same stage run) |
| fix_from_review | `claude --print` (stdin: concerns -> FIX instruction) | via `fix_from_review_resume` | explicit stage invocation only; not dispatched by final review | optional session handoff |
| tech_tree | dedicated wrapper, print shape | `tech_tree_resume` | discovery flow hands its session forward in-flow | in-flow (dies with the flow) |
| chat | stream-json + tool allowlist | `chat_resume` | server: `chat_sessions` row exists | `chat_sessions.agent_session_id` (durable) |
| pm_refine / pm_edit | `claude --print --output-format json` (stdin: SPEC+REQS+story) | `claude --resume {session_id} --print --output-format json` (stdin: retry feedback only, plus the current story size section; pm_refine also adds its browser section) | validation retries in the planner loop resume the rejected attempt's session; agent failures rerun fresh | loop state (session threads through the workflow) |
| pm_discovery | `claude --print` (stdin: SPEC+REQS+backlog) | none (session feeds tech_tree only) | -- | in-flow |
| pm_docs | edit shape (stdin: SPEC section + full diff) | none today | -- | none |
| detect / plan_split / breakdown / adjudicate / concern_triage / fix_generation / plan_add / pm_route / pm_describe | one-shot shapes | none (fresh rerun is the contract) | -- | none |

### Resume decision ladder

Every `_resume` path degrades safely; a resume is an optimization, never a
correctness dependency:

```text
retry needed
   |
   v
saved session id? --no--> fresh invocation (full prompt)
   |yes
   v
_resume invocation (--resume {session_id}, delta prompt)
   |
   +-- success -----------------> continue
   +-- session_not_found -------> ONE fresh fallback (full prompt)
   +-- api_rejection ----------> park (no retry)
   +-- context_exhausted ------> clear saved session, park/fresh per stage
   +-- auth family / usage_limit -> park (a fresh session hits the same wall)
```

`session_not_found` is a first-class classification: the runner tags it only
on resume attempts, it is never retried as transient, and each caller falls
back cold exactly once (implement, fix_from_review, tech_tree, review, chat
all implement this convention).

### Agent retry ladder & backoff

One ladder owns transient retries: `runStageAttempts` in
`server/internal/agents/retry.go`, inside a single `RunStageWithOptions`
call. Stage-level loops (the review semantic retry) retry only semantic
failures -- schema mismatch, format redrafts -- and treat a transient or
upstream exhaustion from the inner ladder as terminal for the stage, so the
two ladders never multiply.

The backoff mirrors the Anthropic SDK transport that Claude Code ships:
delays of `min(0.5 * 2^n, 8)` seconds scaled by a one-sided random factor in
`[0.75, 1.0)` (jitter only ever shortens the wait), default budget 8
attempts. A server-supplied `Retry-After` (`retry-after-ms` wins over
`retry-after`, seconds-float or HTTP-date) is honored verbatim upward,
clamped only by a 300s sanity cap -- the one deliberate deviation from the
reference, so a broken header cannot wedge a stage until its StartToClose. An
`x-should-retry` marker overrides classification in both directions. A
deadline guard stops the ladder when the remaining activity deadline cannot
fit the wait plus another attempt. Overrides: `stages.<name>.retries` per
stage, `HASHD_AGENT_RETRY_MAX_ATTEMPTS` / `_BASE_SECONDS` / `_MAX_SECONDS`
globally.

Two consecutive agent-stage timeouts stop the ladder, even with attempts
remaining. A different failure resets the streak. This limits automatic
spending; it does not establish that another attempt cannot succeed. The
failure retains the deadline's bound, setting and help, plus attempts run.

A transient agent-binary spawn failure triggers bounded retries of the start
within the same attempt, without consuming an agent retry or
review round. The first process never started: the respawn uses the same
command, prompt, environment, worktree and session ID; no completed agent work
is replayed. An unresolved binary retains its original failure. Recovery is
recorded as an entity-linked `agent_retry` event classified `binary_unavailable`,
with the agent name, probe count and elapsed probe time. Probe time is included
in `LadderElapsedSeconds`, not the successful spawn's `ElapsedSeconds`.
The **Deadline inventory** defines the probe bounds.

The upstream-capacity family (HTTP 429/503/529, `overloaded_error`,
`rate_limit_error`) classifies as `upstream_overloaded` -- retryable on the
same ladder, but carrying the parsed HTTP status and Retry-After so failure
surfaces say "the upstream API is having an incident, not your code" with
real numbers. Each retry wait is announced as an `agent_retry` event (durable
row + bus frame) with attempt/budget/status/wait. `stage_changed` start/stop
and `agent_retry` rows written for a launch through the shared agent launcher
(`agents.RunStageWithOptions`) carry that launch's microcommit ID in
`events.microcommit_id` and in the live frame when one was supplied, and NULL
(no frame field) otherwise; `agent_killed` rows carry none. Every subprocess
attempt streams to its own log file (`<stage>.log`, `<stage>.attempt2.log`, ...), and
an upstream exhaustion fails the run with `failure_kind:
"upstream_overloaded"` on the run row, the `run_failed` event, and
`current_errors` -- which the CLI Diagnostic, TUI status panel, and web story
page all render as a distinct calm treatment.

A 429 whose extracted error message names the ACCOUNT's session/usage limit
is carved out of the capacity family as `usage_limit`: non-retryable within
the run (the limit outlasts any backoff the ladder can afford), carrying the
parsed reset time in `classification_message`. The claude structured error
envelope (`is_error` or `terminal_reason: "api_error"` plus
`api_error_status`) routes by status before any prose matching; a structured
401 lands the agent-auth family (`agent_needs_login` /
`agent_invalid_api_key` -- non-retryable but resumable after re-auth, and
the login signal outranks key-shaped tags like `authentication_error`).
Both park with their `failure_kind` riding the same run-row / `run_failed` /
`current_errors` channel as the capacity family, and the implement driver
and review stage render them as the account's condition ("account hit its
usage limit; resets <time>", with `hashd agents` credential-status help) --
never as upstream capacity.

### Chat context

Story refinement and editing (including validation resumes), and `plan_split`,
receive the same project-bound `hashd-read` tools as chat to discover related
stories and read their full problem statements and acceptance criteria. Their
existing connector tools remain available. Other pipeline stages do not gain
this MCP server. Read tools do not mutate stories or expand the stage's output
contract: refinement returns existing-story dependencies; split proposals still
use sibling titles (and the parent for an ordinary split).

Split planning uses the resolved target repository, references the configured
SPEC, and loads global/project directives with the `edit_flow` filter used by
refinement and editing. Normal workflow splits honor project prompt overrides.
The split sees the source brief and non-goals; Arc-child planning, editing and
splitting also receive the Arc's exclusions as constraints, without copying
them into each child's stored non-goals or assigning it the whole feature.

Fresh chat loads current story/AC/workstream and microcommit orientation.
Execution history is retrieved deliberately through `hashd-read` record indexes
and full event/transcript reads; explicit operator references remain available.
Fresh general/clarification-assist and resumed chat turns share shipped chat
instructions that temporarily prohibit spawning foreground or background
subagents. This prompt rule does not change pipeline agent permissions,
session lifetimes, or operator confirmation of proposed actions.

Help Draft captures the invoking answer box and starts one ordinary assist turn
in its matching session. Origin and captured questions/options/context/draft are
labeled message content, not session identity or a separate workflow. Captured
context remains literal through its durable server-computed prefix boundary;
references in the operator task/draft retain normal resolution. Automatic
drafting waits for confirmed prior completion; it does not add server session
locking or change the manual composer. The operator still decides whether to
use and submit the proposed answer.

### Session persistence rules

- A session id that must survive process death is persisted **durably** and
  read back by whatever re-enters the stage (`workstreams.codex_session_id`,
  `chat_sessions`). In-process handoffs (discovery -> tech_tree) die with the
  run by design.
- Saved sessions are cleared when their context is spent: micro-commit done
  (commit stage), `context_exhausted`, operator reset, chat clear.
- Claude's sessionful shapes (print/edit/implement) emit stream-json so the
  session id rides the FIRST event; the runner's OnSessionID hook persists it
  durably before the agent does any work, on both engine paths. The agent-run
  envelope carries session ids for every agent.

---

## Directives

Directives are curated standing rules that guide AI agents. They exist at three levels:

```
~/.config/hashd/directives.md        # Global user preferences
{repo}/directives.md              # Project rules
workstreams/{id}/directives.md    # Workstream-specific (rare)
```

**Why `directives.md` not `AGENTS.md`?** We want hashd to control when directives are passed to agents, not have agents auto-read them. Using `directives.md` ensures agents only see these rules when we explicitly include them in prompts.

**Key principle:** Directives are documentation, not runtime state. They persist and are version-controlled.

### Example directives.md

```markdown
# Project Directives

<!--
Directives guide AI agents during implementation.
hashd passes this file to agents - they don't auto-read it.
-->

- Use sync.Once pattern for handler initialization
- Follow existing templ component patterns in internal/templates
- HTMX handlers should set HX-Trigger for related component updates
```

### Commands

```bash
# Viewing
hashd directives                       # View global
hashd directives all                   # View all (global + project + workstream)
hashd directives project               # View project only
hashd directives workstream <ws>       # View workstream's only

# Manual editing
hashd directives edit                  # Edit global
hashd directives edit project          # Edit project
hashd directives edit workstream <ws>  # Edit workstream's

# AI-assisted editing
hashd directives ai-edit               # AI edit global
hashd directives ai-edit project       # AI edit project
hashd directives ai-edit workstream <ws>  # AI edit workstream's
```

### Two write paths, and what each one guards

A workstream's directives column has two writers, and they are not the same
operation under two names:

| Path | Semantics | Precondition |
|---|---|---|
| `POST /workstreams/{id}/feedback` (`hashd workstream feedback`, the guidance modals, the Telegram bot) | APPENDS one entry after a blank line; earlier entries stay (see the note below) | whatever state preconditions that verb carries (see WF.md's busy-guard table) |
| `PUT /directives/workstream` (`hashd directives edit workstream`) | REPLACES the whole document | compare-and-swap on `base_etag`; no state gate |

The feedback route **appends** (#1756). It needs no `base_etag`, because it
never replaces what it did not read: its UPDATE is a compare-and-swap against
the text it read, so a write landing in between is kept and the append re-reads
and lands after it. After three contended attempts it refuses with 409 and
appends nothing. The response carries the full saved text, and the CLI, TUI and
Web show it. An empty or whitespace-only entry is refused and changes
nothing.

**The gate on the guidance verb governs that verb, not this column.** The
editor is the AUTHORING surface: the operator has the whole document in front
of them, so replacing it is the intended act rather than an accident, and
refusing it at a human park would stop an operator correcting directives at
exactly the moment a park is asking them for guidance. That the same bytes can
be reached through the editor when the guidance verb is withheld is a decision,
not a hole in the gate.

What the editor does owe is that a replace cannot destroy a revision its author
never saw. `GET /directives` returns an `etag` on the workstream section, the
editor sends it back as `base_etag`, and a save whose token no longer matches
the stored directives is refused with 409
`workstream.directives.cas_mismatch` naming both revisions. Guidance
accumulates (#1756), so a blind replace can discard several people's
entries rather than one; the token is what makes that a refusal instead of a
silent win. A
refused save keeps the operator's text -- the CLI retains the edited buffer and
names the file -- and is never retried automatically, because resending the
same body under a freshly read token is the last-write-wins the token exists to
stop.

`base_etag` is **semantically mandatory**: every write without one is refused,
with 400 `workstream.directives.cas_missing`. It is deliberately not marked
`required` in the OpenAPI schema, and that is the only reason — a schema-
required field that is absent is rejected by the framework before the handler
runs, as `validation failed: expected required property base_etag to be
present`, which tells an operator whose older `hashd` is talking to a newer
server nothing about what to do. Letting the request reach the handler means
both an omitted and an empty token get the diagnostic that names the `GET` to
read and the field to send back. There is no fallback path: the schema permits
omission, the server does not.

The file-backed global and project levels carry no token: they have no `etag`
and their concurrent saves remain last-write-wins.

### Usage

Directives are automatically included in all agent-driven stages that produce or judge work:

- implementation
- merge-conflict resolution
- per-commit review and review retry
- final review
- fix generation
- add-commit planning
- planning discovery
- story refine/edit
- breakdown
- concern triage

Use `hashd directives all` to view all directives at once.

### Stage-Scoped Directive Blocks

Directives can include optional stage markers when a rule should only reach a subset of agents. Unwrapped content still renders in every stage.

```markdown
<!--
This file is hashd's directives.md -- operator-authored standing guidance.

Sections wrapped in `<!-- STAGE: name1, name2 -->` / `<!-- END STAGE -->`
only render in those agent stages. Unwrapped sections render in every stage.

Valid stage names: planning, implement, fix_generation, review, final_review,
edit_flow.
-->

# Standing directives

Use msgspec for new data types.

<!-- STAGE: review, final_review -->
Be strict on test coverage for new public code paths.
<!-- END STAGE -->

<!-- STAGE: planning -->
Prefer one-commit-per-AC granularity.
<!-- END STAGE -->
```

Valid stage names are `planning`, `implement`, `fix_generation`, `review`, `final_review`, and `edit_flow`. The merge-conflict resolver uses `implement`; breakdown uses `planning`; concern triage uses `review`. Matching blocks render without the marker comments. Non-matching blocks are stripped. Malformed blocks fail open with a warning, so the content renders to every stage rather than silently disappearing. Nested stage blocks are not supported.

---

## Agent-stop classification

The exhausted-ladder route to an [agent-stop gate](../WF.md#agent-stop-landing-a-stop-that-is-not-a-question)
has two qualifications because the classifier's default arm catches more
than the agent's own answer. First,
the ladder has to be exhausted, which means both rungs spent inside the
one run: the session resume, then the fresh fallback. A first
full-prompt attempt keeps the `failed` outcome — not because a resume
rung is waiting for it (there is none: the resume needs a saved session
for the micro-commit plus a review history or a crash retry, and a
run starts with an empty history unless operator feedback seeded it) but
because that attempt has spent nothing: the run ends failed and
re-dispatching it is a cure the operator already has. That bounds where
this landing is live, which is worth recording: an unusable-output stop
reaches the gate from the attempts *after* the first — a retry inside
this cycle's implement/test/review loop, a cycle carrying operator
feedback, or a crash retry — and ends `failed` on the first attempt of a
micro-commit, including a FIX. FIX retries use the same resume ladder.
Second, the failure has to actually be the agent's answer, which is a
**positive** test and not "everything the named families left over".
That arm is the classifier's catch-all, so three things have to hold and
each excludes a different way of arriving there:

- **The classifier recognized nothing.** Most transient results are
  faults this system did recognize — a reset or refused connection, a
  name-resolution failure, a bare 5xx, claude's `connection_error`,
  codex's `server_error` — and they carry the *same* classification kind
  as the catch-all. Those are the network failing, and a network fault
  is the shape most likely to survive both rungs and arrive looking
  exhausted, so the kind alone cannot be the test.

  "Recognized" spans **both** of the classifier's tables, and that is
  load-bearing rather than incidental. The retry side
  (`classifyRetryableAPIError`, over the per-agent retryable patterns)
  has always named faults the classification side could not, and every
  token one side knew and the other did not went to the catch-all and
  read as the agent's own answer. The classification side now consults
  those same per-agent tables rather than keeping a second list beside
  them, so the two cannot disagree about what a table contains, and
  `TestClassificationAgreesWithTheRetryTables` pins the shapes.
  Past both, there is nothing left in the system to consult, and text
  neither one matches does read as the agent's answer — widening that
  is the classifier's job, not its callers'.

  Reading the tables costs a known **narrowing**, recorded rather than
  discovered later: they are matched against the whole transcript
  (stderr and stdout), so an implementer that merely *quotes* one of
  their tokens — `connection_error`, `network_error`, codex's broad
  `api[_\s-]?error` — and then gives up is recognized, and its stop ends
  `failed` at `implementing` instead of parking. This repo's own
  classifier source contains those tokens. The direction is the safe
  one (it fails to park rather than parking a fault whose cure is a
  re-run), which is why it is a **coverage gap in the landing**, not a
  hazard; the cure is the same one `TestBareIsErrorIsNotRecognition`
  applies to `is_error` — recognition off a structured field rather
  than off free text — and it is follow-up work in the classifier.
- **There was an ordinary agent exit to read.** The runner reports no
  result at all when it refuses before launch (an unconfigured agent
  command, a project config that will not load, a team-mode credential
  the injector declines), and returns a full result *alongside* an
  invocation error for everything that produced no exit code — a missing
  or non-executable binary, a spawn failure, an interrupt, a kill at
  `stages.implement.timeout`, a stream read error. That second shape
  reads like a real run in every field, so the error is the only thing
  that says otherwise.
- **The agent wrote something.** A process killed with nothing written
  still comes back carrying a classification message, so only stdout and
  stderr count as the agent having said anything.

A kill at `stages.implement.timeout` is excluded twice over — by the
clause above and by its own descriptor, which names the bound this
system enforced rather than anything the agent did.

## Activity cancellation and retry boundaries

Transient agent failures (API timeouts, rate limits) are retried automatically in two layers (git pushes are NOT blanket-retried: the archive push retries once behind a pull --rebase, while the one-shot commit leg stays MaximumAttempts:1):

1. **Within an attempt** — the Go agent runner retries a classified-`transient` agent failure internally.
2. **Across attempts** — each long agent stage activity carries a `RetryPolicy` (`agentActivityOptions`: `InitialInterval 5s`, `BackoffCoefficient 2.0`, `MaximumInterval 60s`) plus a 120s `HeartbeatTimeout`. It retries ONLY infrastructure failures (worker death detected via a missed heartbeat, DB faults). An agent *outcome* is returned as data with a nil error and never retries — the outcome/error split is the guard, so a review verdict of "changes required" is data, not a retryable error. Tier A stages whose whole-body re-run is crash-safe (implement, adjudicate, concern_triage, test, probe, detect, provision, final_review, and review -- its agent-outcome errors carry the typed non-retryable `review_outcome` marker so only infra shapes retry) use `MaximumAttempts>1`; stages that persist a plan or transition mid-body (breakdown, partial_breakdown) and the one-shot commit leg keep the heartbeat but stay `MaximumAttempts:1`. On a Tier-A retry the implement driver resumes the agent's session (crash-resume); other stages re-run fresh. **Cancellation is a different layer from an agent outcome.** When the activity context is cancelled -- worker shutdown, heartbeat-timeout invalidation, a persistence brownout -- the runner kills the agent subprocess off `ctx.Done` and the killed attempt classifies `interrupted` (the holistic judges surface the same kill as an `Unavailable` / error verdict). That is the box blinking *before* the agent finished, not the agent's answer. So a **single boundary helper, `propagateCancel`, wraps the return of every agent-stage activity** (implement, test, review, final_review, adjudicate, concern_triage, breakdown, partial_breakdown, the committed-breakage probe, provision, detect, scope_adjudicate): when the context is cancelled it discards whatever the driver returned -- a nil-error `interrupted` / `Unavailable` / `Verdict:"error"` / `"Build failed"` outcome, or a wrapped context error -- and returns the bare `ctx.Err()`. This is one authority rather than a guard per stage, so no stage -- present or future -- can silently masquerade a cancellation as an outcome. Temporal then splits the two cancellation kinds by cause: an infrastructure-driven cancel (worker death / heartbeat-timeout / brownout, a non-server cause) is retryable, but only stages with `MaximumAttempts>1` re-run while their retry budget remains (implement resumes its session; the judge runs again). The one-shot `partial_breakdown` (`MaximumAttempts:1`) instead routes its interrupted attempt through `failStage` to `StatusFailed`, preserving work for explicit retry; a **server-requested cancel (operator stop) carries a `CanceledError` cause, so the SDK reports it terminal-canceled and the workflow's cancellation path handles it -- no retry**. Returning the bare `ctx.Err()` -- not a wrapped or typed error -- is what lets the SDK's `cancelAllowed` check make that split. The fail-closed path is **not** weakened -- it is reached truthfully. A judge that *ran* and could not settle (its agent was rejected, exhausted context, or self-exited, with the context still alive) still renders `could not run (<reason>)` and routes to a human; deadline exhaustion instead closes the run `failed` with an operator note naming the in-flight stage and micro-commit and pointing at `hashd run` -- the abandoned attempt surfaced, not left as a stale pre-kill reading. The discriminator everywhere is `ctx.Err()`: non-nil means the box blinked (propagate -- Temporal retries an infra cancel, terminates a server-requested one); nil means the agent produced the outcome (fail-closed, no retry).

These retries happen transparently within a single micro-commit cycle. The business-logic retry loops (implement/test/review = 5, merge-conflict = 3, PR-rebase = 3) are workflow-level, independent of activity retries.
