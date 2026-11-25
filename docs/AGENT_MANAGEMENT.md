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

Shows every declared agent: whether each binary is installed, where it was found, and the health of any credential registered with the server. It does not list stages -- `hashd project config get stage_agents` shows the effective per-stage assignments.

Owners and administrators can disable an agent server-wide with
`hashd config set agents.<name>.enabled false`, and re-enable it with `true`.
Every declared agent is enabled by default, including in solo mode. Project
settings cannot override this property. `hashd agents` reports disabled agents;
`hashd agents --suggest` considers only agents the server enables. Assignments
are preserved and running stages continue. Selecting a disabled agent, resetting
to a disabled inherited assignment, or starting the next stage on it is refused
with the setting to change. The same decision applies to local and remote runners.


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

Resume stages are not separately configurable. A `*_resume` stage continues a session its base stage opened, and that session id is specific to the agent that minted it, so `review_resume` always runs on whatever `review` runs on. It has no agent key of its own at any layer: the agent comes from the base stage's ladder alone, role entries included -- project `stage_agents.review` > project `stage_agents.reviewer` > system `stage_agents.review` > system `stage_agents.reviewer` > the stage's `default_agent`. `adjudicate` and `scope_adjudicate` add two rungs before their default, project then system `stage_agents.reviewer`, so they fall back to the reviewers' agent when nothing names theirs. A matched entry whose agent is unknown leaves the stage on its default rather than falling to a lower rung; one whose agent has no shape for the stage keeps the stage on that agent, and its launch is refused with a Diagnostic naming the stage, the agent and the missing shape (no other agent runs in its place). The full ladder is in [WF.md, Stage-agent roles](../WF.md#stage-agent-roles). Assigning a base stage therefore carries its resume with it, and a write to a resume stage's agent key is refused.

A `stage_agents.<x>_resume` entry left in an existing config file loads without error and is ignored: nothing rewrites the file, and there is no migration for it. Reset still accepts those keys on purpose, so clear a leftover with `hashd project config reset stage_agents.<x>_resume`, or `hashd config reset stage_agents.<x>_resume` for a system-level one. The refusal a write returns names that same command.

Validation prevents incompatible assignments: an agent must support the shape of every stage it is assigned, including the resume shape its base stage implies.

### The web Settings > Agents panel

Settings > Agents has **Agent properties** and **Stages**. Agent properties shows one Enabled/Disabled toggle per declared agent; owners and administrators can change it. The TUI offers the same properties and opens the existing stage configuration editor from Stages. Disabled assignments remain visible, with the setting to change before the next stage.

The Web Stages section keeps the grid with one table per role. The default groups are `planner`, `coder`, `reviewer` and `reviewer_adjudicator`, in that order; any other role the server reports gets a table after them, and stages no role covers are listed last in a table with no role row. Each role table opens with the role's own row, then lists the stages the server places in that role (the `stage_role` field of `GET /projects/{name}/stage-agents`). Every row has agent, model and effort cells. Rendering the panel writes nothing; each cell is edited in place.

A scope control above the grid chooses where writes go: **this project** (the project layer) or **every project on this server** (the system layer, which every project inherits unless it sets its own entry). The grid always shows this project's effective table. The chosen scope decides which layer every cell's set and reset writes, which layer's entry decides whether a cell offers a reset, and the layer the roster card's "Use for every stage" writes. Where the entry in force for a cell is not the chosen scope's own entry for it (the key or layer `/stage-agents` reports differs, or for a role cell the layer holding the entry differs), the cell names the winning entry by its key and layer, for example "in force: stage_agents.implement · project" at system scope: a system write does not change what that project runs while the project entry stands.

The server owns authorization. A system-scope write goes to `PUT /config`, `POST /config/reset` or `PUT /config/stages-use` with your credentials, the same endpoints `hashd config set`, `hashd config reset` and `hashd config stages-use` use, and the server allows it only for a central config administrator (`requireCentralConfigAdministrator`). The panel adds no check of its own and offers the system scope to everyone; a refused system write, for example by a non-administrator in team mode, shows its Diagnostic at the cell like any other refusal.

A stage cell shows the effective value and what supplied it, exactly as the server reports them: the stage's own entry, a role entry (naming the role), the reviewer fallback, `stages.<stage>.model`, or the default. A value from project or system configuration is followed by the config layer (`project` or `system`) that holds it; a value supplied by the default has `default` provenance and no config layer. A cell the server flags `not_applicable` reads "not applicable", because the launched command has no slot for that value and it is not sent to the agent. A `*_resume` row names the base stage it follows and shows its own row's values.

A role row shows the `stage_agents.<role>`, `stage_models.<role>` and `stage_effort.<role>` entries and the layer that holds each one: the project's entry if it has one, otherwise the system layer's. A role with no entry reads "none set". `reviewer_adjudicator` with no agent entry reads "follows reviewer".

Each role cell and each stage cell (except on a `*_resume` row) edits one entry at the chosen scope's layer: `stage_agents.<key>`, `stage_models.<key>` or `stage_effort.<key>`, where the key is the stage or role. The agent cell is a select of every agent `GET /agents` lists, in three labelled groups: **verified** (installed, registry status `active`), **not verified** (installed, status `available`) and **not installed** (whatever the status), which are listed but cannot be chosen. A stored entry naming an agent that is not installed still shows as the cell's value. Saving an agent that is not verified first opens a confirmation dialog; **save anyway** sends the write with `force`, the same flag `--force` sets on the CLI, and **cancel** (or Escape) sends nothing and puts the cell back to the value last read. The groups and the dialog only shape the choice: the server decides whether a write needs `force`, and a refusal still shows at the cell. The roster card's "Use for every stage" sends no `force` (`PUT /config/stages-use` takes none). For an agent that is not verified it first opens a confirmation dialog; **use anyway** sends the write, and **cancel** (or Escape) sends nothing. The model cell is a text field. The effort cell is a select of the `effort_levels` `GET /agents` publishes for the agent the row shows; a role row with no agent entry, or an agent that publishes none, gets a text field and the server validates the value. Every value control saves with its own **save** button, a select included, so you can pin the value a cell already shows (an inherited agent or effort level, or a system role entry copied into the project). A blank model field is submitted as a set request, not turned into a reset; the server refuses a blank model or effort and the panel shows that refusal, so nothing blank is stored and the key keeps its entry. At project scope the write goes through `PUT /projects/{name}/config`, the endpoint `hashd project config set` uses, and at system scope through `PUT /config`, with your credentials. **reset** removes the entry through `POST /projects/{name}/config/reset` or `POST /config/reset`, and appears only where the chosen scope's layer holds that entry. A role's agent reset is not single-entry: the server's reset of `stage_agents.<role>` also removes that layer's `stage_agents.<stage>` entries for the role's stages, so the cell names those entries beside its reset. A not-applicable cell has no value control, but keeps its reset when the entry exists.

Writes run one at a time: while one is in flight, every control in the panel is disabled. If a write gets no response, the panel says it could not be confirmed and the cell goes back to the value last read; the write may still have landed, so reload the section to see what is stored.

After every write or reset the panel reads the grid again and redraws it, so a role write shows on every stage under the role. When the server refuses a write, its whole Diagnostic (title, detail, explanation, facts and every help line) appears at the cell that sent it, and the cell keeps the value the new read reports. Every warning on an accepted write is shown whole at that cell too. These include a role write's more specific entries that still hold covered stages, an agent write's model and effort entries that stay in force (and whether each is not applicable or names a level the agent does not accept), and the covered stages a model or effort entry will not apply to. Each warning names its key, its layer and the reset command. The roster card's "Use for every stage" shows its warnings whole under the card in the same way.

The panel resolves nothing itself. It makes four reads and needs all of them: `/stage-agents` for the stage rows, and `/config/show` for `stage_agents`, `stage_models` and `stage_effort` for the role rows. If any of them fails, the panel reports the stages as unknown and draws no grid, so a partial answer is never shown as the whole one. The roster cards below the grid still list each agent and its install state, and each card's "Use for every stage" runs `PUT /projects/{name}/config/stages-use`, or `PUT /config/stages-use` at system scope.

`GET /projects/{name}/stage-agents` is the read behind the grid's stage rows. It reports, per declared stage, the agent that will actually launch, where it came from (`agent_key`, the `stage_agents` key that chose it -- the stage's own key, the base stage's on a resume row, or a role key such as `stage_agents.reviewer` when a role entry chose it; empty when the stage runs its default -- and `agent_layer`, `project`, `system` or `default`), which role chose it (`agent_role`, present only when a role entry did), whether an adjudicator stage is borrowing the reviewer role's agent because nothing chose one for it (`reviewer_fallback`), and the default the stage falls back to. All of it comes from `agents.EffectiveStageAgents`, the layered resolver that reads the system and project layers separately -- the same resolver `buildStageCommand` and the run preflight use. The merged config cannot answer this: a hand-edited `stages.<name>.default_agent` is inert, and an assignment whose agent has no shape for the stage is reported on that agent and refused at launch (`stages-use` still accepts it, with a warning naming the gap).

Assignments are validated against the agent registry before they are saved.

Agents with `available` status (not yet verified with hashd) require `--force`:

```bash
hashd project config set stage.breakdown gemini --force
```

### Bulk assignment by role

Every configurable stage belongs to exactly one role, and a resume stage follows its base stage's role:

| role | stages |
|---|---|
| `planner` | `breakdown`, `browser_classify`, `chat`, `concern_triage`, `detect`, `failing_tests`, `plan_add`, `plan_split`, `pm_annotate`, `pm_describe`, `pm_discovery`, `pm_docs`, `pm_edit`, `pm_refine`, `pm_route`, `pm_spec`, `tech_tree` |
| `coder` | `fix_generation`, `implement` |
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

These settings apply wherever the stage launches its default agent, also when
a `stage_agents` entry chose that same agent. A stage moved to another agent
instead uses that agent's registry model default. Model IDs are strings: `null` is a literal ID, not a reset. An
explicitly empty model omits the model flag; reset removes the override. The
Web Agents grid's model column edits `stage_models`, not
`stages.<stage>.model`: the grid shows a legacy `stages.<stage>.model` entry as
the provenance of the model in force, but writes and resets only
`stage_models`.

`stage_models` and `stage_effort` set a stage's model and reasoning effort on
either path. They are keyed by stage or role and resolve on the `stage_agents`
ladder; a resume stage follows its base stage's key:

```yaml
stage_agents:
  reviewer: codex
stage_models:
  reviewer: {agent: codex, model: gpt-6.1-sol}  # written by `set stage_models.reviewer gpt-6.1-sol`
stage_effort:
  reviewer: high
```

A model string belongs to the agent it was set for. The write records the
agent the key's stages launch beside the model, and the entry applies only
where the stage launches that agent: move the stage to another agent and it
runs that agent's default model, never the other agent's string. A
plain-string entry (hand-written, or older than this rule) names no agent and
applies only on the stage's default agent, like `stages.<stage>.model`. Model
strings are free strings passed as written; claude takes an alias (`opus`,
`sonnet`, `haiku`) or a full ID. An agent that refuses one fails the attempt
as an API rejection, not retried, with its own error and the
`config set stage_models.<stage> <model>` command that fixes it.

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
  `model_template` / `effort_template` (every shape of an agent that declares
  one carries its placeholder)
- for `stage_models`, the key's stages launch different agents, so no one
  agent would own the model (`model_agents_differ`): set it per stage
- an effort is not one of the effective agent's accepted levels:

| Agent | Accepted `stage_effort` levels |
|---|---|
| claude | `low`, `medium`, `high`, `xhigh`, `max` |
| codex | `low`, `medium`, `high`, `xhigh` |
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
With no entry, effort is the stage's declared effort where it launches its
default agent, else the launching agent's registry `effort` (claude's `high`).

A value is sent only where the launched command has a slot: the command carries
`{model}` / `{effort}` and the agent declares `model_template` /
`effort_template`. Every shape of an agent that declares a template carries its
placeholder, so a stage reassigned to claude, codex or opencode gets its model
(and claude's or codex's effort); gemini, kimi, qwen and copilot declare no
templates. A value with no slot sends nothing and is reported as not
applicable.

### Direct config editing

All stage overrides can also be set by editing `config.yaml` directly. See `../config.sample.yaml` in the repo root for all available settings with commented-out examples, including common recipes like using Claude for implementation or switching models.

---

### ACP agents

`agy` is Google's Antigravity CLI, which serves ACP itself (`agy acp`). Install
it yourself on each runner (`curl -fsSL https://antigravity.google/cli/install.sh | bash`,
into `~/.local/bin`); hashd checks the declared minimum version (1.5.1) and
never installs or updates it. The CLI takes its profile as `--gemini-dir`, which
the declaration fills from the run's `GEMINI_HOME`. It is listed as
`available`, so selecting it uses the existing force rule. Inspect-only shell
shapes remain unavailable; the native transport cannot enforce them.

The CLI reports an upstream API failure as an ordinary reply and records it in
the session's own log. hashd reads that log (read-only, only the steps the
prompt added) and fails the attempt with the provider's status. Only a spent
quota -- the provider's `QUOTA_EXHAUSTED`, or the runtime's `refusal` stop -- is
an account usage limit. A plain rate limit (429)
or an outage (5xx) is retried like any harness's, after the retry delay the
provider recorded; an error the log does not render as the provider's is not
retried. When the
runtime does not advertise `_meta.antigravity.systemPrompt.append`, the stage's
instructions lead the prompt instead (docs/ARCHITECTURE.md, **Agent harnesses**).

Use Fleet or `hashd agents login agy` for personal Google sign-in, or register a
Gemini API key through the existing credential form. The CLI's ACP sign-in
refuses a machine with no display, so both run its own `agy acp --login`: open
the link Fleet shows in any browser, sign in, and submit the code Google's page
shows in Fleet's **Code** field (or paste it at the terminal). On a desktop the
CLI's browser sign-in runs as before. Native login files stay in that owner's
runner profile. Cloud/Enterprise's additional license
picker still needs qualification; push and proxy sign-in are not declared.

Fleet's bounded login observation reads the native session's model catalogue
without sending a prompt. These are advertised choices, not verified model
entitlements. Displayed thinking levels belong to the displayed model; the
native runtime validates a selected model and effort before each stage prompt,
including resumes. Instructions are delivered explicitly from the checkout.
Native daemons keep their disabled default and delegation, workflow and scheduler
tools are excluded. Stages use the same process-group cleanup as other agents.

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

On a team server, agents run on the server but the work belongs to individual users -- so runs act as the **story owner**, using a credential that user registered:

```bash
hashd agents login <agent>     # register your credential with the server
hashd agents logout <agent>    # remove it, and sign the agent out on this machine
hashd agents logout <agent> --runner <id-or-name>   # sign the agent out on that runner only
hashd agents                   # shows your registered credentials and their health
```

The two logout forms have distinct effects:

- `hashd agents logout <agent>` removes your registered credential for the agent from the server, then runs the agent's own sign-out (its declared `logout_args`) in your hashd login folder on the machine you run it on. The server's result line also says that runs already going may keep a copy they were given until they end, and that removal stops no run.
- `hashd agents logout <agent> --runner <id-or-name>` is Fleet's Sign out on that runner. It sends one `DELETE /agents/{agent}/login?runner_id=<id-or-name>`; the server resolves the runner (an unknown or ambiguous name is refused with the server's Diagnostic) and the runner runs the agent's own sign-out in your hashd login folder there. The command then follows that attempt through `GET /agents/{agent}/login?runner_id=...`, printing its progress and the agent's output, and succeeds only when the attempt ends with the agent confirming it is signed out; a failed sign-out exits non-zero with the runner's Diagnostic, as does one it cannot confirm. It never removes or changes a registered credential: when one remains that runs still receive, the result says so and names `hashd agents logout <agent>`. It needs no terminal.
- Removing a registered credential in TUI or Web Settings also runs the agent's own sign-out in the login folder that row names as "Your sign-in on <machine>": your hashd login folder on the server machine, through Fleet's Sign out on the server's local runner. Settings reports the two outcomes separately: the server's removal result line, then the sign-out's outcome.

Login harvests the credential from your own machine where the agent has a sanctioned artifact, and prompts for a paste otherwise. Secrets are read hidden on a TTY or piped on stdin -- never passed as flags. The server validates the credential shape at registration (a wrong paste fails immediately with the fix named), stores it encrypted at rest, and never returns it.

The TUI has the same surface: press `s` on the dashboard for Settings -- view credential health, register or replace a credential (paste into a masked field, or Lift to pull it from this machine's env vars / agent credential files / the gh CLI), remove one (which also runs the agent's own sign-out in your hashd login folder on the server machine, the row's "Your sign-in on <machine>", and reports the removal and the sign-out as two outcomes), and change the autonomy mode.

| Agent | What you register | Subscription supported? |
|-------|-------------------|------------------------|
| **Claude** | An Anthropic API key with `--method api-key`, or a push sign-in (`hashd agents login claude --push`) | Yes: Claude's own sign-in on each runner (`hashd agents login claude`, hashd never sees the token), or pushed from the server (below) |
| **Codex** | A push sign-in (`hashd agents login codex --push`), your `~/.codex/auth.json` (run `codex login` first), or `--method api-key` | Yes, as push (below). An uploaded `auth.json` is refreshed by the server from then on: run `codex login` again locally, since sharing one login between laptop and server breaks both |
| **Gemini** | Your `~/.gemini/oauth_creds.json`, or `--method api-key`. Workspace accounts add `--options google_cloud_project=<id>` | Yes; agent runs burn quota fast, so expect a paid tier |
| **Copilot** | `gh auth token` output (harvested automatically), or a fine-grained PAT with the "Copilot Requests" permission | Yes; classic `ghp_` tokens are rejected -- the Copilot CLI silently ignores them |
| **Qwen** | An API key plus `--base-url` (Coding Plan or any OpenAI-compatible endpoint) | Key-based only; the free OAuth tier was discontinued upstream |
| **Kimi** | A Moonshot platform API key plus `--model` | Key-based only today |
| **OpenCode** | A provider API key plus `--model <provider>/<model>` -- OpenCode is multi-provider, so the model's provider half is what the key authenticates against | Key-based only; subscription logins route through OpenCode's own auth store, and Anthropic prohibits Claude subscription OAuth in third-party tools |

Behavior at run time (registered-credential-wins):

- A registered credential is always injected for your runs, in both deployment modes, and overrides the server host's own environment.
- Run `hashd agents login claude` or `hashd agents login codex` on each runner machine. Sign-in writes directly into that runner's per-owner agent home, the same home its launch probe reads. A paired runner uses its saved connection identity; on the server machine, the local runner uses the same layout. Existing login files are not copied or used as a fallback: sign in again on each machine. A registered API key still takes precedence, and signing in on the server machine replaces it; a sign-in the server keeps (push or proxy) is never removed by it, and its sign-in mode decides which sign-in runs use (below).
- `hashd agents login claude --push` or `hashd agents login codex --push` signs the agent in once for every runner. The agent's own sign-in (browser, or its headless sign-in as below) runs in a fresh temporary folder on the machine you run it on, and its login file (claude's `.credentials.json`, codex's `auth.json`) is registered with the server as your subscription credential, stored encrypted. It is a registered credential, so it outranks a runner's own sign-in on every runner. Only the server refreshes it: before a launch whose deadline the access token would not outlast, the server runs the agent's own refresh (claude's stream-JSON initialize, codex's app-server `account/read`) on its copy and stores the result; the server needs the agent installed for that. A run gets only the access token -- claude in `CLAUDE_CODE_OAUTH_TOKEN`, codex an `auth.json` holding no refresh token -- never the refresh token, and writes nothing back. Claude refreshes only inside its own expiry window, so a still-valid token can be handed to a stage that outlasts it: the stage then fails as an ordinary agent error. The sign-in is always fresh, never a copy of an existing login: two refreshers on one refresh token leave one signed out. An agent that keeps its login outside a file (a system keychain) cannot be pushed from that machine. Codex `auth.json` registrations made before push are push registrations, with no change to what is stored.
- `hashd agents login claude --proxy` is the same sign-in, kept and refreshed on the server the same way, but its runs never hold the access token (#2893 step 4). A run gets a placeholder key and the address of a forwarder on its own host (claude: `ANTHROPIC_AUTH_TOKEN` and `ANTHROPIC_BASE_URL`, pointing at `127.0.0.1`); the forwarder admits only that placeholder and only the paths the agent declares (`proxy.paths` in `defaults.yaml`), and sends each request over the runner's paired connection to the server, which puts the access token on it and sends it to the provider. What the provider answers, a usage limit included, comes back unchanged. The placeholder is worthless anywhere else and ends with the run; the server refuses the request once the run's attempt ends. A sign-in the server cannot keep current answers the run with an authentication error naming `hashd agents login claude --proxy`. There is no fallback to push or to another credential. Only agents that declare `proxy:` take it; codex stays on push, since its ChatGPT sign-in keeps a token codex reads itself.
- Each agent with a sign-in the server can keep (claude, codex) has a sign-in mode (#2893 step 5), stored on that sign-in (`delivery` in its non-secret settings): `manual` (runs use your own sign-in on each machine that runs them; the server sign-in stays kept, unused, and never leaves the server), `push`, or `proxy` (claude). With no mode set it is `auto`: push when the server keeps a sign-in for you, manual when it does not, shown as `auto — using push now` or `auto — using manual now`. `hashd agents mode <agent>` shows it and `hashd agents mode <agent> <auto|manual|push|proxy>` sets it; without a server sign-in there is nothing to set, and push or proxy is refused naming `hashd agents login <agent> --push`. `hashd agents login <agent> --push`, `--proxy` and `--manual` sign in and set the mode in one act (`--manual` signs in on this machine). Plain `hashd agents login <agent>` never changes the mode; when it is push or proxy, it ends naming `hashd agents mode <agent> manual` and `--manual`. `hashd agents`, the Web Agent logins row and the TUI settings modal (`m`) name the two sign-ins by where they are ("Server sign-in: kept / none", "Your sign-in on <machine>: signed in / not signed in"), show the mode and set it among the modes the server offers (`GET /agents/credentials` `modes`, `PUT /agents/{agent}/mode`). An API-key registration has no mode.
- Where a browser likely cannot reach the agent's localhost sign-in callback -- an SSH session (`SSH_CONNECTION`/`SSH_TTY`), WSL, a terminal multiplexer (`HERDR_ENV`, `TMUX`, `STY`, `ZELLIJ`), a container, or Linux with no `DISPLAY`/`WAYLAND_DISPLAY` -- `hashd agents login` says so and runs the agent's declared `headless_sign_in` instead: codex's device code (`codex login --device-auth`: a link and a one-time code for a browser on any device), claude's paste-the-code sign-in (`claude auth login` prints a link whose page shows a code to paste back). An agent declaring none gets its browser sign-in, with the reason it may not finish. A device-code sign-in the account refuses is reported and, on a terminal, the browser sign-in starts in its place, saying why; with no terminal the refusal (`agents.login.headless_refused`) is the result, and no browser sign-in is left waiting. The sign-in still lands in the same per-owner agent home.
- Claude, codex, OpenCode, Copilot, Qwen, Kimi and Gemini runs never use the server host's own login or configuration, in either mode. Every run starts from a home of its own under the runner's `runnerlayout.AgentHomesRoot(ops, serverID, runnerID)`, set as `HOME` (claude also gets `CLAUDE_CONFIG_DIR` inside it; OpenCode gets `XDG_CONFIG_HOME`, `XDG_DATA_HOME` and `XDG_STATE_HOME` inside it, and an empty `OPENCODE_CONFIG` / `OPENCODE_CONFIG_DIR`; Copilot gets an empty `GH_CONFIG_DIR` and `XDG_CONFIG_HOME`, so neither its config nor its gh login fallback points back at the host; Qwen gets an empty `QWEN_RUNTIME_DIR`, `QWEN_CODE_TRUSTED_FOLDERS_PATH`, `QWEN_CODE_MCP_APPROVALS_PATH`, `QWEN_CODE_HOOK_APPROVALS_PATH` and `QWEN_CODE_MEMORY_BASE_DIR`, so its state and config files all fall under `QWEN_HOME`; Kimi reads its config and state only from `KIMI_CODE_HOME`; Gemini gets an empty `GEMINI_CLI_TRUSTED_FOLDERS_PATH`, so its config and state all fall under `GEMINI_CLI_HOME`, and an empty `GOOGLE_GENAI_USE_GCA`, `GOOGLE_GENAI_USE_VERTEXAI`, `CLOUD_SHELL`, `GEMINI_CLI_USE_COMPUTE_ADC` and `GOOGLE_APPLICATION_CREDENTIALS`, so no auth selector or credential file admitted from the server turns a `GEMINI_API_KEY` run into the host's Google login), holding only a `.gitconfig` with the project's `git_name`/`git_email` and `safe.directory` for the worktree. The home is removed after its sessions are saved. Startup salvages abandoned Claude sessions before sweeping run homes; a failed save retains the source for recovery. So the host user's plugins, skills, settings, hooks, MCP servers, `~/.gitconfig` and `gh` login never reach a stage. A claude resume finds its session because hashd keeps each run's session files (only those) for the owner and copies the one being resumed into the next run's home. OpenCode keeps every session in one database, which hashd keeps in the owner's agent home (`OPENCODE_DB`); only that database, with its SQLite WAL files, is kept there between runs. `XDG_CACHE_HOME` is left to follow the run's `HOME`, as for the other agents: every tool reads it, so the caches tools build in it (go, uv, pip) go with the run, and OpenCode fetches its model list again on each run. A project that wants its runs to share the server's cache admits `XDG_CACHE_HOME` through a host entry of its environment. On those runs Copilot's `COPILOT_HOME` is the owner's agent home, and only its `session-state/` (what `copilot --resume <id>` reads) is kept there between runs. Qwen's `QWEN_HOME` is the owner's agent home the same way, and only each project's `projects/<cwd>/chats/` (whose `<id>.jsonl` is what `qwen --resume <id>` reads) is kept there between runs; the project memory and metadata beside it are not. Kimi's `KIMI_CODE_HOME` is the owner's agent home too, and only its `sessions/` (whose `<workdir>/<id>/` is what `kimi --session <id>` reads) is kept there between runs; the `config.toml` each run's credential writes goes with the rest. Gemini's `GEMINI_CLI_HOME` is the owner's agent home as well; Gemini nests its state in `.gemini/`, and only each project's `.gemini/tmp/<project>/chats/` (what `gemini --resume <id>` reads) and the `.project_root` beside it (which checkout the project folder belongs to) are kept there between runs. The `.gemini/settings.json` and `.gemini/oauth_creds.json` each run's credential writes go with the rest.
- With nothing registered, a claude, codex, Copilot or Gemini run proceeds only when a credential variable survives the project's auth-mode filtering and `agents.<name>.env` precedence (claude: `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN` or `CLAUDE_CODE_OAUTH_TOKEN`; codex: `CODEX_API_KEY`; Copilot: `COPILOT_GITHUB_TOKEN`; Gemini: `GEMINI_API_KEY`). Otherwise the stage is refused with `hashd agents login <agent>`, in single-user mode too. An OpenCode run always needs a registered credential: its provider keys have no single variable name. So does a Qwen run: `DASHSCOPE_API_KEY` alone selects no auth type (Qwen Code 0.27.0 refuses "No auth type is selected" from a home with no settings), so it does not count. Nor does a Kimi run's `KIMI_API_KEY`: it binds no model (Kimi Code 2.5.2 refuses "No model configured" from a home with no `config.toml`), so a Kimi run needs a registered credential too. Gemini's `GOOGLE_API_KEY` does not count either: alone it selects no auth type (Gemini CLI 0.49.0 asks for an auth method from a home with no settings). Project-level work such as detect uses the registered credential of the person who asked for it, the server owner on a single-user server.
- Package caches and toolchains that live in the server user's home (`~/go`, `~/.cache`, `~/.npm`, `~/.cargo`, `~/.rustup`) are not reachable from a claude, codex, OpenCode, Copilot, Qwen, Kimi or Gemini run's home. Export `GOMODCACHE`, `GOCACHE`, `npm_config_cache`, `CARGO_HOME` or `RUSTUP_HOME` in the server's environment to share them.
- When hashd injects MCP servers for Claude, it passes `--mcp-config` without `--strict-mcp-config`, so Claude's own MCP discovery stays on; only the `browser_classify` launch keeps an empty strict config (`--mcp-config {"mcpServers":{}} --strict-mcp-config`), and launches with no injected servers pass no MCP flags. The isolated run home removes host-user MCP configuration. When `mcp.project_servers` is on, hashd injects the servers the repository's root `.mcp.json` defines at the story's pinned base commit: an absent file, a file with no servers, or a launch with no pinned source injects none, while a refused read (malformed or non-regular file, missing pinned commit, or unreadable repository) refuses the launch before the agent starts with no fallback to the working tree, lane, or branch tip. Servers the harness discovers on its own come from the working tree and its other sources, not the pinned base, and the harness's own precedence decides a shared name.
- Every agent attempt's transcript meta records the MCP configuration hashd delivered as `mcp_delivery`: `project_servers` and its config layer (`project_servers_source`), `project_source_outcome` (`disabled`, `absent`, `no_servers`, `servers`, or `no_pinned_source`, with `repository` and full `commit` when a pinned read ran), and every delivered server in `servers` (`name`, `origin` as `project` or `hashd`, `transport` as `stdio` or the definition's declared type, and for `stdio` servers `command` and sorted `env_keys`). It records env variable names only — never env values, header values, args, or harness-substituted values — and launches refused for MCP reasons record no attempt. `agent_profile` remains the agent's own report of what it loaded or connected.
- Every claude run records what the agent itself reported loading: plugins, skills, MCP servers, slash commands, subagents and the settings files in its config directory. The record goes on the run's transcript as `agent_profile`. `hashd doctor` lists, per stage agent, the most recent run's record with that run's stage, id and time, or "not reported yet" before any run has made one. Doctor starts no agent. A field the agent version does not report reads "not reported by this agent version", never "none".
- Every run acts for a person. A launch that names nobody (no acting user, and no workstream or story to read an owner from) is refused before it starts, with a Diagnostic that names the launch (`ownership.launch_without_owner`); a launch of unassigned work is refused naming `hashd assign` (`ownership.unassigned`). Project-level stages that a user asks for act for that user: discovery and its tech tree, project description and build detection have no story or workstream to read an owner from, so their agent acts for the requesting user (`RunStageOptions.ActingOwner`) and runs from a run home on that user's credential like any owned run. Only then can the stage fence hold the launch to what its shape allows; a launch left on the host's own profile is not contained by shape, and an agent with an OS sandbox of its own (codex) cannot run commands there.
- The run home keeps the host's configuration out of a run, not the repository's. Gemini, Copilot, Qwen and Kimi still read their config files committed in the worktree (for example `.gemini/settings.json` or `.qwen/settings.json`), and hashd does not yet check those for a setting that would send the run's credential somewhere else, the way Claude's credential guard checks Claude's project settings (`server/internal/agents/claude_settings.go`; [Project settings and the run's credential](#project-settings-and-the-runs-credential)). That check is follow-up work, held the same way as OpenCode's (#1775).
- Team-server runs on an owned workstream **refuse to dispatch** when the owner has no live credential for the run's agents. The refusal names the exact command to fix it.
- When a run proves a credential dead (expired, revoked, or a token-rotation conflict), the server records it: the next dispatch fails instantly with the recovery steps instead of burning another run. Re-registering clears the state.

An OpenCode credential is injected differently from the others, and the difference is worth knowing when reading a run: the server hands OpenCode a complete one-provider auth store on `OPENCODE_AUTH_CONTENT` and pins the model on `OPENCODE_CONFIG_CONTENT`. Verified against OpenCode 1.18.31: the injected store **replaces** the host's `~/.local/share/opencode/auth.json` for that process (and is never written back to disk), and it **outranks a provider key in the ambient environment** -- with the host's own `OPENAI_API_KEY` exported and a different key injected, the request that reached the provider carried the injected one. The model pin is load-bearing rather than cosmetic: OpenCode also picks providers up from environment variables the host exports, so an unpinned model could select one of those instead of the registered credential. No credential file is materialized on disk.

**Known gap: a project's OpenCode config files can override or redirect the registered key (unresolved).** Since #2203 the server host's global config directory and an `OPENCODE_CONFIG` file in the server's environment are no longer read by a stage run (per-run config home, verified against OpenCode 1.18.35). The project's own `opencode.json` / `.opencode/` in the worktree is still read, and the rest of this section still applies to it; it is revisited with #2228. Tested against OpenCode 1.18.31, offline, with dummy keys only. The injected auth store does **not** outrank OpenCode's *config files*. The server's pin covers only the model, so a `provider` section in any config source OpenCode loads still applies. Per OpenCode 1.18.31's source, those sources are:
- the project's `opencode.json` / `opencode.jsonc`, looked up from the run's directory to the worktree root, and those in its `.opencode/` directories;
- the server host's global config directory (`~/.config/opencode/`: `config.json`, `opencode.json`, `opencode.jsonc`);
- a file named by `OPENCODE_CONFIG`.

The project `opencode.json` and the host's global `opencode.json` were tested. The other sources are merged the same way in OpenCode's source, but were not separately tested.

In OpenCode 1.18.31:
- **A config `apiKey` replaces the registered key.** A `provider.<provider>.options.apiKey` in any of them is sent instead of the user's registered key. With it in the host's global config, a team-server run on an owned workstream acts as the host's key, not the owner's.
- **A config URL redirects the registered key.** A `provider.<provider>.options.baseURL`, or a per-model `models.<model>.provider.api`, in any of them sends the user's registered key to that URL. Anyone who can commit `opencode.json` to the project repository can therefore redirect a registered key to an endpoint they choose.

For the project's own config, hashd does not currently prevent or detect either case: no pre-launch check. Until that changes, treat OpenCode registered keys as exposed to whoever controls any of those config sources. Review all of them for `provider` settings before registering an OpenCode key on a shared server, and keep reviewing them: every run reads them afresh, so a change made after registration, such as a commit to the repository, applies to the next run. Other OpenCode versions were not tested.

A startup verification has been proposed: confirm which credential and endpoint OpenCode actually resolved, and refuse the run when they are wrong. **It is not implemented.** For it to be sound, the effective key source *and* destination must be inspected deterministically, through a supported mechanism, before any provider request. Asking the model which key it used is not verification, and probing a live request could itself send the key to the redirected endpoint. OpenCode 1.18.31 has no supported command that reports the effective key source and destination together:
- `opencode debug config` prints merged config values, secrets included;
- `opencode providers list` shows only the auth store and environment variables.

The server never installs, pins, or updates agent binaries -- installing agents on the server is the operator's job, and a dispatch whose agent is missing is refused with the install command.

### Shared project and server API keys

Use `--scope project|server` on the same three commands to select a shared
registration. Omitting `--scope` keeps the personal behavior above. Only a server
owner or admin may list, set, replace or remove shared credentials. Only API keys
can be shared; subscription sign-ins, credential files and harvested tokens belong
to a person.

```bash
hashd project use my-project
hashd agents --scope project --project my-project
printf '%s' "$ANTHROPIC_API_KEY" | hashd agents login claude --scope project --method api-key
hashd agents logout claude --scope project --project my-project
hashd agents --scope server
```

`hashd agents --scope ...` lists the agent, scope (project name or server), method,
health, who set the key and when, without returning any secret. Scoped login only
stores the shared key and prints the project it was registered for; it never runs
an agent sign-in. It refuses `--push`, `--proxy`, `--manual` and any resolved method
other than API key before reading a secret. Supply `--method api-key` for agents
whose default method is a subscription. The key is still read hidden on a TTY or
from stdin, never from a flag, and cleartext remote servers are refused before
the key is read.

For project scope, `hashd agents`, `hashd agents login` and `hashd agents logout`
select the hashd project from `--project`, then the saved current project
(`hashd project use <name>`), then `HASHD_PROJECT`, then the only configured local
project. Agent-specific settings go in `--options key=value` on `hashd agents login`,
repeated for more (Gemini's Google Cloud project is
`--options google_cloud_project=<id>`). A remote client does not use its local project
list as a fallback. Project scope is refused when no hashd project resolves;
server scope needs no project selection.

Storing a shared key does not activate it. `agents.credential_source` defaults to
`owner`, preserving personal registrations, runner sign-ins and existing personal
credential selection. The Web and TUI show it as **Agents run on**, naming the
values `owner` **User's account**, `project` **Project key** and `server`
**Team key** (solo offers Team key only when a project already stores it).
Everyone with access to the project sees it; a server owner or admin selects
shared delivery per project there or from the CLI:

```bash
hashd project config set agents.credential_source project --project my-project
# Or use the server-wide key for runs of this project:
hashd project config set agents.credential_source server --project my-project
# Restore personal credential selection:
hashd project config set agents.credential_source owner --project my-project
```

`project` uses only that hashd project's shared key; `server` uses only the server
registration. A missing, removed or dead key refuses the run, with no fallback to
personal credentials, harness logins or environment keys. Shared keys stay on the
server and are delivered only through the agent's API-key proxy: the agent receives
a local forwarder address and placeholder credential. Agents without a declared
API-key proxy form are refused, naming their affected stage assignments; choose
an agent with that form or restore `owner` source.

Scoped logout sends only the selected shared registration's DELETE and prints
the server's message. It leaves personal registrations and personal and runner
sign-ins intact. `--scope` and `--runner` cannot be combined.

The REST selector uses query parameters on the existing credential routes:

| Operation | Project scope | Server scope |
|-----------|---------------|--------------|
| List | `GET /agents/credentials?scope=project&project=<name>` | `GET /agents/credentials?scope=server` |
| Register | `PUT /agents/{agent}/credentials?scope=project&project=<name>` | `PUT /agents/{agent}/credentials?scope=server` |
| Remove | `DELETE /agents/{agent}/credentials?scope=project&project=<name>` | `DELETE /agents/{agent}/credentials?scope=server` |
| Test | `POST /agents/{agent}/credentials/test?scope=project&project=<name>` | `POST /agents/{agent}/credentials/test?scope=server` |

**Testing a shared key.** An agent's API-key proxy may declare `key_check`: a
no-cost authenticated GET (claude and codex list their models). Registering a
shared key runs it at once, and Test runs it again; neither makes a model call.
It goes through the key's own `base_url` when set, with the proxy's
authentication header. The provider's answer is recorded on that registration:
a success verifies it (`ok`), a 401 or 403 (401 only for Bedrock) marks it
`revoked` so runs refuse it early, and any other answer records nothing and reports `unknown`. An agent
with no `key_check` has no Test.

**In the Web.** Settings > Server > **Team keys** (server administrators on a
team server only) lists each agent that can take a shared key, whether its
server-scope key works, who set it and its `base_url`, with Add key or Replace
(stored and tested at once), Test and Remove. `GET /agents` marks those agents
`shared_key`, and `key_check` where a key can be tested.

**Whether the project's key works.** `GET /projects/{name}/agents/key-status`
tells anyone who can open the project, for the key its `agents.credential_source`
selects, whether each shared-key agent's key is `working`, `broken`,
`not_tested` or `not_set`, and nothing else about it. Under `owner` it lists no
keys.

Omit `scope` for personal credentials. Server scope takes no `project` parameter.
The PUT body uses `method: "api_key"`, `secret` and optional `config`; the server
also refuses non-API-key shared registrations and enforces owner/admin access.

#### Custom upstream (`base_url`)

A shared API key for an agent that declares an API-key proxy (`claude`, `codex`)
accepts an optional `--base-url` (stored as `config.base_url`) to forward
proxied requests to a custom gateway instead of the agent's default upstream:

```bash
printf '%s' "$OPENAI_API_KEY" | hashd agents login codex --scope server --method api-key --base-url http://192.168.1.10:8317/v1
```

Only agents that declare an API-key proxy (`claude`, `codex`) take `base_url`
here, and only on shared project or server API keys; personal registrations of
those agents refuse `base_url`.
`GET /agents` publishes it in each agent's `credential_config` with
`shared_only`, so the Web and TUI personal forms leave it out.

The URL must use `http` or `https` with a host and no userinfo, query, or
fragment. Plain `http` is accepted for any host so LAN gateways work; using
`http` sends the API key in cleartext between the hashd server and that
endpoint.

The `base_url` path is prefixed to each forwarded request path, and a trailing
`base_path` declared by the agent (`codex`'s `/v1`) is trimmed before prefixing
so it appears once:

- `codex` with `http://192.168.1.10:8317/v1`: `/v1/responses` forwards to `http://192.168.1.10:8317/v1/responses`
- `codex` with `http://192.168.1.10:8317/openai`: `/v1/responses` forwards to `http://192.168.1.10:8317/openai/v1/responses`
- `claude` with `http://192.168.1.10:8317/anthropic`: `/v1/messages` forwards to `http://192.168.1.10:8317/anthropic/v1/messages`

Replacing the shared key replaces its `config` as a whole, including `base_url`:
re-registering without `--base-url` clears it and returns requests to the
agent's default upstream.

#### Amazon Bedrock (`provider=bedrock`)

A shared claude API key can be an Amazon Bedrock API key instead of an
Anthropic one. Set `provider=bedrock` and the key's AWS `region` in `--options`:

```bash
printf '%s' "$BEDROCK_API_KEY" | hashd agents login claude --scope server --method api-key \
  --options provider=bedrock --options region=us-east-1
```

Optional `opus_model`, `sonnet_model` and `haiku_model` pin the Bedrock model
or inference profile id each Claude model name runs (Claude Code's
`ANTHROPIC_DEFAULT_*_MODEL`); without them Claude Code picks its own Bedrock
defaults for the region. An ARN is refused: the proxy admits one model id per
request path. `base_url` does not apply to a Bedrock key, and Bedrock settings
do not apply without `provider=bedrock`. Bedrock is shared keys only.

A run under a Bedrock key gets `CLAUDE_CODE_USE_BEDROCK=1`, `AWS_REGION`, its
forwarder as `ANTHROPIC_BEDROCK_BASE_URL` and the forwarder's placeholder as
`AWS_BEARER_TOKEN_BEDROCK`, which Claude Code sends as `Authorization: Bearer`.
The server replaces it with the Bedrock key and forwards only
`POST /model/<id>/invoke` and `/model/<id>/invoke-with-response-stream` to
`https://bedrock-runtime.<region>.amazonaws.com`. Test lists the region's
inference profiles on `https://bedrock.<region>.amazonaws.com` (no model
call); only a 401 marks the key broken, because AWS answers 403 for a
missing permission as well as a refused key.

**With an IAM role instead of an API key.** Set `role_arn` (and the role's
`external_id`, when its trust policy requires one). Nothing is pasted, and
login reads no key:

```bash
hashd agents login claude --scope server --method api-key \
  --options provider=bedrock --options region=eu-west-1 \
  --options role_arn=arn:aws:iam::123456789012:role/hashd-bedrock
```

The server assumes that role with its own AWS identity, found through the AWS
SDK's default credential chain: environment variables, a shared profile, an
EKS service-account token or Pod Identity, ECS, or the EC2 instance profile.
It calls `sts:AssumeRole` with session name `hashd` (and the external ID),
keeps the session until five minutes before it expires, and signs each
forwarded request with it (SigV4, service `bedrock`). The session never
leaves the server; the run sees the same placeholder as with an API key. A
role the server cannot assume refuses the run's request with a Diagnostic
naming the role. Test assumes the role and signs the inference-profile list:
AWS refusing the role (`AccessDenied`) marks the key broken; the role also
needs `bedrock:ListInferenceProfiles` for Test to say working.

The role's trust policy must allow the server's identity to call
`sts:AssumeRole`; its permissions need `bedrock:InvokeModel` and
`bedrock:InvokeModelWithResponseStream` on the models it runs. Until agent
runs are contained (#2202), an agent on an EC2 host can read the instance's
own role from the metadata service, so give that identity nothing but
`sts:AssumeRole` into the Bedrock role.

The request shapes were taken from Claude Code 2.1.322 against a local stand-in
endpoint; no live AWS account was used, for the API key or the role. The Web Team keys form offers the
provider as a choice and shows only that provider's settings.

Because a proxied run receives a loopback forwarder URL rather than the native
provider endpoint, its cost is recorded with the provider unresolved
(`custom_endpoint_provider_unresolved`) and no native-price figure. A Bedrock
key's run is the exception: it is priced at Bedrock's rates for the key's
region, from AWS's public price list or LiteLLM's (docs/design/cost-capture.md).

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

No child hashd starts in a worktree inherits the server's environment. Its
environment is allowlisted by `server/internal/childenv`, the one builder
for every such process: agent stages, every project command (build, test,
fast check, merge gate and the provisioning baseline) and workspace hooks.
A name reaches a child only when one of these layers admits it, later layers
winning:

1. **Base**: `PATH`, `HOME`, `LANG`, `LANGUAGE`, `LC_*`, `TERM`, `TZ`,
   `TMPDIR`, `USER`, `LOGNAME`, `SHELL`, the proxy variables (`HTTP_PROXY`,
   `HTTPS_PROXY`, `NO_PROXY` and their lower-case forms), the CA variables
   (`SSL_CERT_FILE`, `SSL_CERT_DIR`, `NODE_EXTRA_CA_CERTS`,
   `REQUESTS_CA_BUNDLE`), and hashd's install locations (`HASHD_ROOT`,
   `HASHD_PACKAGE_BIN_DIR`, `HASHD_TOOLS_DIR`, `HASHD_CBM_BIN`). A run that
   starts from a hashd-owned profile gets that profile's `HOME` instead of
   the server's.
2. **The project environment** (below): the one layer a project sets, the
   same for an agent, a project command and a hook.
3. **The agent's credential variables** (agents only): the `credential_env`
   its registry entry in `defaults.yaml` declares (claude:
   `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`;
   gemini: `GEMINI_API_KEY`, `GOOGLE_API_KEY`, `GOOGLE_CLOUD_PROJECT`; and so
   on). A run carrying a registered credential inherits none of them, from
   this layer or from the project environment: the injected credential sets
   its own.
4. **`agents.<name>.env`** (agents only): values the operator declares in
   system config, withheld from a run carrying a registered credential.
5. **Prepared credential/profile** (agents only): hashd-owned credential
   values and profile paths override configured values, including on solo
   env-credential runs.
6. **The child's own context**, last: an agent's run variables
   (`HASHD_STAGE`, `HASHD_AGENT_ROLE`, `HASHD_PROJECT`, `HASHD_RUN_ID`,
   `HASHD_WORKSTREAM_ID`, `HASHD_SERVER_URL`, `HASHD_SERVER_CA_CERT`,
   `HASHD_TOKEN` and `IS_SANDBOX=1`), a test command's handoff variables, a
   hook's `HASHD_*` context.

Some names are never admissible, from any layer but an injected credential:
`HASHD_SECRET_KEY`, `HASHD_OPS_ROOT`, `AWS_SECRET_ACCESS_KEY`,
`AWS_SESSION_TOKEN`, `AZURE_CLIENT_SECRET`, `AZURE_FEDERATED_TOKEN_FILE`, and the forge token names the server's forge calls use (`GH_TOKEN`, `GITHUB_TOKEN`, `GH_ENTERPRISE_TOKEN`, `GITHUB_ENTERPRISE_TOKEN`, `GITLAB_TOKEN`, `GITLAB_ACCESS_TOKEN`, `OAUTH_TOKEN`, `CI_JOB_TOKEN`, `BKT_TOKEN`, listed once in `server/internal/forge/forgecred`).
An entry of the project environment under one of these names is refused when
it is written.

#### The project environment

A project has one environment: named entries, each setting one variable for
every child hashd starts for the project. An entry belongs to the project or
to one of its repos; a repo's entry overrides the project's entry of the same
name, whatever either's type, for that repo's work. There is no system-wide
scope: every project holds its own entries, and a project added later starts
with none.

An entry has a type, which says where its value comes from:

| Type | The variable receives |
|---|---|
| `value` | The value as written. Plain configuration: not for passwords or tokens. |
| `secret` | A value stored sealed in the project's database and never shown again. With `as_file`, the variable receives the path of a read-only file holding it instead. |
| `credential` | The forge credential of the person who owns the work, for the forge credential key the entry names (`<host>`, or `<host>/<organisation>` where one host serves many, as `hashd forge status` lists it). Only the key is stored. |
| `host` | The value of a variable in the environment of the machine that runs the child. The entry names that variable, or reads the one of its own name; a name ending in `*` (`MAVEN_*`) passes every variable it matches. |

**A host entry comes from each runner's own environment.** A stage that runs
on a runner reads the variable from that runner's process environment; a
child the server starts itself reads the server's. hashd neither copies a
host variable from one machine to another nor checks that a runner has it: a
variable the machine lacks is simply not set for the child. Set it where the
runner's service is configured.

Entries are read and written over the server's routes `GET /projects/<project>/env` and `PUT` / `DELETE
/projects/<project>/env/<NAME>` (`?repo=<name>` for a repo's entry), and
through three surfaces that list, set and remove entries: `hashd project env`,
TUI Settings (the "Project environment" row) and Web Settings (the
Environment section). A caller the server offers no write actions sees the
table read-only. With `hashd project env`:

```sh
# list: the project's own entries and every repo's; --repo <name> lists what that repo's work receives
hashd project env list
# set or replace; a secret is read from a hidden prompt, piped stdin or --from-file
printf '%s' "$NPM_TOKEN" | hashd project env set NPM_TOKEN --secret
hashd project env set SIGNING_KEY --secret --from-file signing.key --as-file
hashd project env set MAVEN_ARGS -- -B    # -- so a value starting with - is not read as a flag
hashd project env set FEED_TOKEN --credential <host>/<organisation> --repo api
hashd project env set JAVA_HOME --host
hashd project env remove NPM_TOKEN
```

Every project member may list the environment; only an owner or admin may
set or remove an entry. A listing shows each entry's name, type, scope and
version, a value entry's value, a credential entry's key and the variable a
host entry reads. It never shows a secret's value, and it shows a host entry
as read from the runner, never a value read from one. A value or a secret
holds at most 64 KiB; a secret delivered as a variable holds no NUL byte
(deliver it as a file). A name hashd sets (`HASHD_*`), a never-admissible
name, and for a secret or a credential a name every child inherits from the
base set, are refused when the entry is written. Setting an entry again
replaces it at a new version: that is how a secret is rotated, and the next
launch receives the new value. Each set and remove leaves a
`project_env_set` / `project_env_removed` row on the project timeline naming
the entry, its scope, type and version and who acted, never a value.

Right before a child launches, the server resolves the environment for the
work it runs for: the repo's entries over the project's, a secret unsealed,
and a credential as the work owner's own for its key (the workstream's
owner, so a reassignment takes effect at the next launch; the story's for
planning, which has no workstream; solo uses the solo owner): the owner's
sign-in when the key is bound to one, otherwise the owner's stored token. A
runner asks the server once per stage for its stage's environment and fills
in the host entries itself. When the owner has no usable credential, when no
owner can be determined, when the credential cannot be read or a secret does
not open, the child never starts: it stops with a Diagnostic
(`command.credentials.unavailable`, `command.credentials.owner_unknown`,
`command.credentials.unreadable`, `command.secrets.unreadable`) naming the
entry, for example "Cannot start: the work owner has no usable credential
for <host>/<organisation> (environment entry FEED_TOKEN)". The run's failure
record files the credential refusals as failure_code
`command.credential_unavailable`, `command.credential_owner_unknown` and
`command.credential_unreadable`. Nothing falls back to another person, a
service account, the host's own forge login or the server's environment,
nothing signs in automatically, and nothing retries.

An `as_file` secret is written for the one launch to a read-only (0400) file
in a directory of its own (0700), outside every worktree, and removed when
the child ends. A runner's stages use
`<runner-root>/worktrees/<server-runner-key>/runner-<runner-state-key>/workspaces/exec-secrets/run-<n>/`;
the server's own launches use `<ops>/exec-secrets/run-<n>/`. Exclude both
hierarchies from backups and monitoring. Under the stage fence the child can
read its own file and nothing else there. The server removes any file left
behind when it starts, and a run directory that cannot be removed is logged
as an ERROR naming it.

What this means for secrets, plainly:

- Agents receive the project's secrets and credentials, as project commands
  and hooks do, and so do the MCP servers an agent starts and passes its
  environment to. hashd does not scrub agent output of secret values.
- A project command's and a hook's printed output is still masked: each
  whole occurrence of a secret or credential value is replaced with
  `[REDACTED]`. This catches accidental prints only; an encoded, split or
  transformed copy is not caught.
- Any code a child runs can read the entries it received and could send them
  elsewhere. Whoever can change that code, by pushing to the branch a gate
  tests, can read them: give a project only the secrets you trust its code
  and its agents with.
- A project command that ran with a secret or a credential entry neither
  reuses nor records a test verdict. Other commands key their verdict on the
  environment's entries (name, type and version), so a pass under one
  environment never answers a run under another.

`hashd doctor --project <name>` lists, by layer, the names an agent, a
project command and a workspace hook receive, and the names in the server's
environment they do not. The project environment's names carry their
entry's type, for example `project environment: JAVA_HOME (host), NPM_TOKEN
(secret)`; no value is ever printed. A build that broke on upgrade because a
variable is no longer inherited shows here: a host entry admits it. The
server-environment check separately names the forbidden values withheld
from every child, which no entry can restore. Each credential entry, the
project's and each repo's, is listed as `FEED_TOKEN <- <host>/<organisation>:
present / missing for <owner>`, for the person running doctor: names, keys
and status only.

A command's executable (`argv[0]`) is looked up on the `PATH` a value entry
sets, and on the launching machine's own `PATH` when none does. Doctor and
the preflight stage look it up the same way: doctor reports, per repo, the
executable of each `test_cmd`, `merge_gate_test_cmd`, `fast_test_cmd` and
`build_cmd` it would run (none under `tests_skipped`, no build under
`build_skipped`), and names a missing one with its repo and the settings to
change, for example ``repo `consumer`: `mvn` not found on the declared PATH``.
It runs no command and never prints the `PATH` value.

An installation upgraded from the earlier `exec` settings had them converted
into entries once, at the upgrade; the release notes of that release say how.

`HASHD_TOKEN` is the run's own token, never the server's internal token. It
reaches only the run's project and, for a workstream run, its own
workstream; a planning run on a story reads its story's workstreams, any
related story in its project, and the events and transcripts of its own
story and its Arc siblings; a run whose stage writes nothing can read and
post telemetry only. It is revoked when the run ends, and expires on its own after the
run's longest possible duration when the server dies before revoking it
(`run_token` in WF.md's Deadline inventory). On a solo server a loopback
caller still needs no token at all until keyless loopback is retired.

The environment does not hide files: an agent runs as the server's Unix
user and can still read the ops directory by path. Closing that needs
contained execution.

`IS_SANDBOX=1` is scoped to the spawned agent process; it is not exported
into operator shells or written to global toolchain configuration. Agents
should treat their current working directory as ephemeral, avoid reaching
outside the assigned worktree unless the operator supplied an explicit path,
and avoid mutating global toolchain state.

With `auth_mode: oauth`, the credential variables an agent marks `api_key`
are withheld:

| Env var | Agent |
|---------|-------|
| `ANTHROPIC_API_KEY` | Claude |
| `GEMINI_API_KEY` | Gemini |

---

## Prompt Management

### How prompts work

All LLM prompts live in `prompts/*.md` as templates. They use `{{ variable }}` placeholders for dynamic content; see [Composing prompts](#composing-prompts) for conditionals, includes and literal braces. HTML comments (`<!-- ... -->`) are stripped before sending to the LLM.

Prompts are loaded and rendered by `server/internal/prompts`:

```go
prompt, err := prompts.Render(promptsDir, overridesDir, "implement", vars)
```

A non-empty structured commit body takes precedence over git-body fallback; the sources are never appended together. When the structured field is absent or empty, hashd preserves all non-empty bodies from implementer-created commits in that implementation attempt, in commit order. When both sources are empty, hashd adds no implementer prose or placeholder. Hashd owns the subject and lineage trailers. Forge squash-merge settings and behavior decide how source commit bodies combine in the merged commit; that is outside hashd's body-preservation contract.

The shipped agents declare the optional `commit_body` string field through
`agents.<agent>.commit_body_field`. Implementation prompts render that declaration
for ordinary, FIX, review-retry and crash-resume attempts. Put body content
requested through `hashd reject -f` or `hashd answer` in that field of the final
status object. Use JSON escapes for paragraph breaks, for example:

```json
{"status":"changes_made","files":["server/internal/example.go"],"summary":"Preserved operator guidance","changes":["Passed the requested body to the commit stage"],"commit_body":"Preserve operator-requested commit prose.\n\nValidation: the focused body handoff test passed."}
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
rides the implementer's `{{ repair_ruling_section }}` (implement and
implement_fix, directly after `implement_fix_requirements_section.md`) and the
reviewer's (contextual and closed-list reviews), and an override without that
placeholder refuses the FIX the same way. Both ruling sections
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
| `breakdown` | `breakdown`, `plan_add`, `fix_generation` |

The four review templates also share `include_review_scope.md`: judge requested
behavior, regressions, and unnecessary additions without expanding the task.
The closed-list template retains its narrower carried-findings/new-breakage
limit; shared guidance never reopens it.

The three per-commit review templates also share
`include_review_accepted_deviations.md`: optional explanations of justified
departures from the commit description, passed to final review as context,
not findings or changes to ACs. Format repair preserves them when present.

Partial breakdown uses `breakdown`. Format-only retries (`review_repair`, `planner_retry_resume`,
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
| `review_history.md` | final_review | Previous review cycles; composes guidance and attempt entries rendered in Go through `include_final_review_history_guidance.md` and `include_final_review_history_attempt.md` before bounding |
| `include_final_review_notes.md` | final_review | Selected previous-verdict checklist or per-commit human decisions from data; includes `review_verification_section.md` or `review_notes_section.md` for framing, preserving project overrides |
| `include_final_review_touched_file_contents.md` | final_review_delta | Per-file headings, submodule and binary notices, complete fenced contents and empty-list notice from files present at head; rendered in Go with project overrides before measuring the section ceiling, then placed as `touched_file_contents` in embedded mode |
| `include_final_review_touched_file_listing.md` | final_review_delta | Contents-withheld notice with the quoted worktree and every touched path's status, kind, lines, bytes or submodule commit; rendered in Go with project overrides before bounding, then placed as `touched_file_contents` in listed mode |
| `include_final_review_delta_commits.md` | final_review_delta | Full-SHA gained-commit lines, oldest first, from commit records; rendered in Go with project overrides before bounding, then placed as `delta_commits_body` |
| `include_final_review_touched_files.md` | final_review_delta | Recorded touched-path lines and deletion/submodule markers from file records; rendered in Go with project overrides before bounding, then placed as `touched_files_body` |
| `include_final_review_gate_evidence_records.md` | final_review + final_review_delta (gate_after_review) | Evidence opening sentence, subheadings and record lines, from planned commit results and the previous merge gate round; rendered in Go before bounding, with Go keeping only the bound notice and reference |
| `include_final_review_gate_evidence_section.md` | final_review + final_review_delta (gate_after_review) | Build and Test Evidence heading and bounded `build_test_evidence` body |
| `final_review.md` | final_review | Holistic branch review before merge; includes the shared evidence section under gate_after_review |
| `final_review_delta.md` | final_review (after a FIX) | Delta round: checks the FIX commits answer the last verdict's findings; includes the shared evidence section under gate_after_review |
| `failing_tests.md` | failing_tests | Name the failing tests, the runner's summary line and its count, and the failure's kind (tests, build or environment) with the output line it rests on, in a failed build or test output nothing else named (test stage, provisioning baseline, merge gate); all labelled "named by model" |
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
shell PATH. The session is bound to that resolved absolute command, so an
installer upgrade cannot switch versions mid-session.

Agents reach the session through the `hashd-browser` MCP server (`hashd
internal browser-mcp`), injected into every harness's MCP config for the
invocation that owns the session; not through their own shell. A stage whose
shell cannot start processes or write files (a read-only review, a planner with
no shell, Codex's read-only sandbox for shell-less stages) can therefore still browse. The server is
a child of the agent: outside a harness's own sandbox, inside the stage fence.
Each session's directory (`browser/<role>-<suffix>`) keeps the browser's
control files, its `config.json` and lifecycle log, and the browser saves its
captures to a `captures` child of it. That capture directory is the session's
artifacts directory: the `browser_artifacts` prompt variable and the server's
`--artifacts` name it, and it is the one directory the stage fence and, for
OpenCode, the harness's own permission layer open to the stage, read-only. The
fence opens it as a directory, so captures saved after launch are readable;
the control files beside it and other sessions stay closed. A launch whose
capture directory cannot be granted is refused before it starts
(`stage.evidence_grant`). The stage never writes there: the browser daemon
does, outside the fence, so a stage that could write there could plant a
symlink it follows. Its `browser` tool runs
one playwright-cli command in that session, from its artifacts directory, and
refuses everything that reaches past the page under test: session lifecycle,
another session, `run-code` and the debugger, commands that read or write files
the agent names, a `--filename` that is a path, and pages that are not http(s).
Codex is told to approve hashd's servers' tool calls
(`default_tools_approval_mode`) and Gemini and Qwen to trust them, since a
headless stage has no one to answer a confirmation.

A project can declare the app a browser check looks at:

```yaml
browser:
  app_cmd: sh -c 'cd web && exec go run ./e2e/harness -addr 127.0.0.1:{port}'
  app_url: http://127.0.0.1:{port}/ui   # default http://127.0.0.1:{port}/
```

With `browser.app_cmd` set, planning and both reviews have Hashd start the app
from the checkout under the stage fence, with the project's `exec`
environment, on a free local port (`{port}`, also `HASHD_APP_PORT`); wait
until `app_url` answers; give the agent that address; and stop the app's
process group when the session closes. The wait has no timeout of its own: it
uses only the time the activity has beside the agent's own timeout (or that
timeout, outside a workflow). An app that exits, or does not answer in that
time, skips browser validation with a warning naming the app log beside the
session's lifecycle log. Implementers still start their own app, since they
change the code it runs. Without the key, agents try the documented commands
as before, which only works where their shell can. Doctor checks the CLI version;
installation and actual session startup check that Chromium can launch. Old
runtime directories remain available for in-flight sessions; they are not
deleted during upgrades. Dependencies refresh before minor/major release
candidates are tested; patch releases retain their tested dependency set unless
a security or bug fix requires an update.

Only a positive classification and successful private browser launch enable
`include_review_browser.md`. This adds a best-effort behavioral/visual check,
including available design guides and existing precedent. When Hashd started
the app (`browser.app_cmd`) the reviewer uses its address; otherwise agents try
documented development or test-harness commands, first establishing safe
cleanup, and stop only the services they started—never shared services or
processes by name/port.
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

Final review additionally receives the short screenshot-attachment skill, part
of `final_review.md`. The reviewer explicitly selects a PNG and
caption through the `hashd-browser` server's `attach_image` tool (the same
receiver `hashd internal review-attach-image` posts to); selecting none is valid.
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
| `plan_discovery_resume.md` | pm_discovery_resume | Finish interrupted discovery in its existing session |
| `refine_story.md` | pm_refine | Refine chunk into story with acceptance criteria |
| `edit_story.md` | pm_edit | Edit existing story based on feedback |
| `sequence_story.md` | pm_refine_resume, pm_edit_resume | Sequencing turn after a draft or an edit: which open filed stories the story should wait for, each with a one-line reason |
| `project_describe.md` | pm_describe | Generate project description from repo contents |
| `directives_edit.md` | pm_edit | Propose a revision of one directives level (global, project, workstream) from the operator's instruction |
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

The server owns the override files. The `hashd prompts` commands read and write them over the REST API and send only the project and the prompt name: the reads (`GET /prompts`, `GET /prompts/{name}`) take `project` rather than filesystem paths, so the commands need no local `HASHD_ROOT` or ops root and work the same against a local or a remote server.

Overrides can also be listed, viewed, edited, diffed and reset from Web Settings > Prompts, which uses the same REST routes and writes the same override files.

Overrides can also be listed, viewed, edited, diffed and reset from the TUI Settings modal's Prompts row, which uses the same REST routes and writes the same override files.

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

What a stage is given to read outside its checkout -- its delivered inputs
(the directories under `<TranscriptRoot>/inputs/` holding copies of its
selected files), the directory holding its project environment's as-file
entries, and its browser session's capture directory, each of which the stage
fence opens read-only -- reaches OpenCode's own permission layer, which would otherwise refuse them:
OpenCode asks `external_directory` before a tool reads or writes outside the
worktree, and `opencode run` rejects every ask. Verified against OpenCode
1.19.5 with a local scripted model, each launch that delivers inputs writes an
`opencode.json` holding only a reference `hashd-input-<dir name>` for every
such directory into a directory of the launch's own, removed after the
launch, and points `OPENCODE_CONFIG_DIR` at it. OpenCode then puts `<dir>/*`
among the `external_directory` allows of every agent's defaults, whichever
agent the config makes the default. A reference alone grants no tool
permission ([References](https://opencode.ai/docs/references/)), and hashd
writes no permission rule: the defaults come before every rule a config sets,
so a configured `external_directory` or `read` denial still refuses the inputs,
and no rule is added, replaced, reordered or re-advertised. hashd never writes a
rule above the operator's and does not check their config before launch; a read
such a denial refuses is left to be reported as a harness refusal. OpenCode reads
references only from config files (never `OPENCODE_CONFIG_CONTENT` or an
`OPENCODE_CONFIG` file); its reference loader reads `OPENCODE_CONFIG_DIR` in
the global directory's place whenever the variable is set, even empty, as the
run home's declaration sets it, and its config loader reads that directory's
`opencode.json` after the project's root config, which moves no other setting
because the file holds nothing else. An inherited `OPENCODE_CONFIG_DIR` naming
a directory refuses the launch rather than being replaced. OpenCode applies
references only inside a git project, as a stage's checkout is; elsewhere the
inputs stay refused. The copies are read-only files. With the fence off, that
prevents only writes by the `edit`, `write` and `patch` tools and plain shell
writes; the agent's own user can still `chmod` or delete a copy, and the stage
fence is what prevents that.

## Ops-dir isolation

The ops dir (`~/.hashd` by default) holds `secret.key`, the system and project databases, every workstream's worktree and every run's transcripts. A stage runs repository code and agent tool calls as the server's own user, so without isolation any of them can open those files by path.

`stage_isolation.ops_dir: true` closes the ops dir to every stage child: agent processes (both spawn paths in `server/internal/agents/retry.go` and the codex app-server transport), gate commands (`mergeflow.RunBuild`, which runs the merge-gate, runner and committed-breakage test commands, and the provisioning baseline in `runflow/provision.go`) and workspace hooks (`hooks.Run`). It is a system config setting only, read from defaults and `~/.hashd/config.yaml` (`hashd config set stage_isolation.ops_dir false` turns it off); project config cannot set it. It is on by default, solo and team alike, wherever the host has a fence driver it can run, with agent launches governed by the required-fence policy below.

`stage_isolation.require_ops_fence` defaults to `true`: an agent stage whose ops-dir fence is unavailable is refused with the concrete reason; `hashd config set stage_isolation.require_ops_fence false` permits unfenced execution.

When `stage_isolation.require_ops_fence` is explicitly `false`, an unavailable fence permits agent execution and raises a standing alert naming the reason and setting.

How it works (`server/internal/opsfence`): the fence is applied by the host's driver, one per OS, chosen at build time (`driver.go`). On Linux it is Landlock (`landlock_linux.go`): the child enters a Landlock domain before it execs its command. Other platforms have no driver yet; a macOS driver (Seatbelt, `sandbox-exec` with a generated profile) is the next slice. Landlock grants by path and cannot deny anything beneath a grant, so the domain grants every entry beside each directory on the path from `/` down to the ops dir, and inside the ops dir only:

- the stage's working directory, which must be one workstream's `worktrees/<project>/<workstream>` (granted in full) or its project's managed clone `repos/<project>`, which such a stage gets read-only: hashd's own git runs in the clone unfenced (the REQS commit, worktree add and remove, local merges), and a tracked file the clone's config names, such as a `core.hooksPath` directory or an included file, would run what a stage wrote there;
- that project's managed clone read-only, except what a commit writes: the 256 loose-object fan-out directories and `objects/pack` (created by the server, so `objects/info` and its alternates file stay closed), `.git/refs`, `.git/logs` and, for a linked worktree, its own admin dir `.git/worktrees/<workstream>`. `.git/config`, `.git/hooks`, `.git/info`, `packed-refs` and other workstreams' admin dirs stay read-only.;
- an injected credential's agent home (`agent-homes/<owner>-<agent>`), for agent stages;
- read and execute on hashd's own install when it sits inside the ops dir (the server binary's directory, `HASHD_PACKAGE_BIN_DIR`, `HASHD_ROOT`, the bundled tools directory).

Every grant comes from where the server put the stage: the worktree's `.git` pointer and the admin dir's `commondir` are never read to decide one, because a stage can rewrite them. The admin dir's `gitdir` file is read only to refuse a stage whose admin dir does not name its worktree. Everything else under the ops dir, including `secret.key`, `projects/` (with the project databases), `runs/`, `cbm/` and other workstreams' worktrees, is refused with EACCES, and so is truncating a file there. `exec.Cmd` has no pre-exec hook, so the child starts as the server's own binary (`/proc/self/exe`), which enters the domain in `opsfence`'s `init` and execs the real command in place. The child keeps the server's uid and its pid, so process-group signalling, `Pdeathsig` and git ownership are unchanged.

hashd's own git follows the same fence. A stage can always rewrite what git in its worktree trusts: the worktree's `.git` file, its admin dir's `commondir` and `gitdir`, tracked hook scripts, and attributes naming filters. So with isolation on, every git command the server runs whose directory (after any `-C`) is a workstream worktree runs inside that workstream's own fence (`opsfence.WrapGit`, applied in `mergeflow.runGit` and at every other server git exec; `opsfence.GitCmd` builds one for call sites that set neither `Dir` nor `Env`). Whatever the stage planted then runs only inside the domain it already had. The repository's pre-commit and pre-push hooks keep running as the gates hashd relies on, inside that fence. Git in the managed clone itself, or in a repository outside the ops dir, runs unfenced: its config and hooks are not writable by a stage in the ops dir. The forge CLIs (gh, glab, bkt, tea run git themselves) and `gitleaks git` take the same fence by directory. Project detection (`config.DetectProject`, which runs `git status`) refuses a workstream worktree, because `config` cannot import `opsfence`. `server/internal/opsfence/gitguard_test.go` fails on any new git exec that is neither fenced nor on its allowlist, and every allowlist entry carries its reason.

When the fence cannot be had (including explicitly disabled `stage_isolation.ops_dir`), agent stages are refused unless `stage_isolation.require_ops_fence` is explicitly `false`. Configuration read errors never authorize agent fallback. Non-agent stages retain their existing unfenced fallback and notices. That happens when the host has no driver (any OS but Linux, for now), when the kernel has no Landlock ABI 3 or later (Linux 6.2+ with `landlock` in `/sys/kernel/security/lsm`; below ABI 2 renames across directories are refused, below ABI 3 truncation cannot be, and either is no fence rather than a weaker one), when the system config cannot be read, when `HASHD_OPS_ROOT` is unset, or when the fence cannot be built for that stage: the managed clone sets `extensions.worktreeConfig` (the stage's admin dir would hold config hashd's git reads), the admin dir does not name the worktree, a directory containing the ops dir cannot be listed, or a stage's working directory is inside the ops dir but outside the stage-owned subtrees (`tech_tree` runs in the project's ops directory, `projects/<name>`, and so requires the explicit agent opt-out to run unfenced). A host that cannot run the driver shows on `hashd doctor`'s `stage ops-dir isolation` row (a warning, never a failure, naming what the host lacks) and as a standing notice on every live workstream (`Stages run unfenced on this host`, kind `stage_isolation_unfenced`). An allowed unfenced fallback is logged once per reason, and doctor names the last one. Agent fallback also raises the standing alert above; refused launches raise no fallback alert. The opt-out permits fallback only when the fence is unavailable; an available fence is still used. A preparation failure a stage could have caused stays fenced, so tampering never turns the fence off for the stages after it:
- an admin dir whose `gitdir` no longer names its worktree is left out of the grants, and the fence stays (the stage's own git there fails);
- a directory on the ops dir's path that cannot be listed or resolved (a fenced stage can change its permissions, since Landlock does not govern `chmod`) refuses the stage: the refusal is the command's start error, and nothing runs;
- a child that cannot enter its domain does not run the command (exit 126).

Normal use never meets these. A command that cannot start at all (missing, not executable, a missing `#!` interpreter) is not wrapped, so its start error reads as it does unfenced; an execute-only command is fenced. `hashd doctor` names the driver while isolation is active.

Limits, and why the switch can be turned off:

- A stage cannot create a new entry directly in a directory that contains the ops dir: `$HOME` for the default `~/.hashd`. Existing entries there stay readable and writable, but a tool that creates a new file or directory directly in `$HOME`, including a temporary file it renames over an existing one, is refused. Placing the ops dir outside `$HOME` (for example `/var/lib/hashd`) avoids this.
- The domain sets `no_new_privs`, so setuid programs (`sudo`) do not gain privileges inside a stage.
- Each project's code-map indexes live in a folder of their own, `cbm/<project>`, and a stage is granted its own project's folder alone, read-write (cbm opens its indexes in WAL mode, which needs the `-wal` and `-shm` files beside them). Its code-map tools work under isolation; another project's indexes, and the `cbm/` folder that holds them all, stay closed.
- The network is not restricted. Agent environments are allowlisted by `server/internal/childenv`; see [Environment variables](#environment-variables).
- Only Linux has a driver in this slice; on other platforms agent stages require the explicit `stage_isolation.require_ops_fence: false` opt-out to run unfenced and raise a standing alert. Non-agent stages retain unfenced fallback, and doctor and the workstream notices report the unavailable fence.
- A stage can write any branch's ref and reflog in its project's managed clone, not only its own: creating a ref's lock file needs create rights on `refs/heads`, which Landlock grants for the whole directory. This is a residual integrity risk (a stage could move another workstream's branch or the default branch); it cannot run code or read the ops dir through it.
- No git under the fence can delete a ref: git takes the clone's `packed-refs.lock` to delete any ref, the pseudorefs an operation removes when it finishes included, and the fence grants no new entry in `.git` itself. Git reports `Unable to create '.../packed-refs.lock': Permission denied` and carries on. hashd's git runner logs every such report and, after a rebase, cherry-pick, revert, merge or commit it ran completes (no rebase, apply or sequencer state left; not a `--no-commit` or `--squash` merge or pick), removes that worktree's leftover `CHERRY_PICK_HEAD`, `REVERT_HEAD`, `MERGE_HEAD` and `AUTO_MERGE` files directly, out of the fence. An agent's own git has no such step: when the conflict resolver's agent completes the AI-resolve rebase itself, the resolve leg removes the `CHERRY_PICK_HEAD` and `AUTO_MERGE` it left, but only when nothing else is in progress, the tree is clean, the branch holds the commit it rebased onto, and the marker names either the rebase's last replayed commit or a commit whose patch is HEAD's (the last pick of a further rebase the agent ran itself, such as an autosquash). A marker it leaves ends the leg with a refusal that says which of these kept it. hashd deletes its own per-worktree refs (the checkpoint-reset backup) the same way, while they still name the commit it expects. A stage's own `git branch -D` or `update-ref -d` fails with that error.
- Tracked hooks still reach the clone through review: a hook a stage commits on its branch (in a tracked `core.hooksPath` directory) lands in the managed clone only when hashd merges that branch, and hashd's git in the clone then runs it unfenced. Isolation does not replace review of what is merged.
- The committed-breakage check (rerunning a failing test at committed HEAD) and the merge gate's base comparison (rerunning the failed command at the base) check the revision out in a throwaway worktree beside the workstream's own, `worktrees/<project>/.check-*`, added and removed from the project's managed clone. Under isolation that checkout is a fenced worktree like the workstream's, so the command and hashd's own git there run inside its fence, and both checks run on fenced hosts.
- Outside the ops dir isolation changes nothing: a repository the project keeps outside the ops dir, its `.git/config` and hooks included, is as writable to a stage as it is without isolation, and hashd's git there runs unfenced.

## Agent Tool Permissions

Agent permissions are declared by stage shape, not by individual agent command
templates. The source of truth is
`server/internal/config/defaults.yaml:shape_capabilities`, mirrored into
`packages/hashd-client/src/hashd_client/defaults.yaml` (generated, not committed) by
`task -d server generate:defaults`. The runners translate that shape intent into each
agent's CLI flags when assembling the command.

### Shape Capabilities

| Shape | Writes? | Bash | Intent |
|---|---:|---|---|
| `print` | no | none | Read context and produce free-form text for planning and discovery. |
| `json` | no | none | Read context and produce structured output. |
| `edit` | yes | none | Edit a bounded artifact such as REQS annotations or docs. |
| `review` | no | inspect | Inspect the tree, run shell commands, and start the app under review when the story needs a browser check; do not modify files. |
| `review_resume` | no | inspect | Same as `review`, continuing a prior review session. |
| `implement` | yes | full | Implement code in an isolated worktree and run the project build/test tooling. |
| `implement_resume` | yes | full | Same as `implement`, continuing a prior implementation session. |

`bash: inspect` means every agent gets its unrestricted shell, the way Claude's
Bash always was: a reviewer must be able to start and drive the app it checks
on any project, with no project configuration, and a read-only sandbox cannot
compile, write temporary files or open a port. The stage still has
`writes: false`: no edit tools where the agent has them, and the agent must not
modify files. That is an instruction, not an enforced sandbox; the stage fence
still closes the ops dir, and downstream gates validate the result.

### Stage Shapes

The Go map `server/internal/agents/runner.go:stageShapeMap` and Python mirror
`packages/hashd-client/src/hashd_client/agents_check.py:STAGE_SHAPE` define which shape each stage uses.
Those stay in lockstep through the existing stage-shape contract tests.

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
| Codex | `bash:none` sets Codex's read-only sandbox through a config override that works for both start and resume; `bash:inspect` (reviews) and `bash:full` (implementation) run `--dangerously-bypass-approvals-and-sandbox`; an edit-only shape uses workspace-write. Every launch, including chat over app-server, also turns off subagents and goal continuation through `-c features.multi_agent=false`, `-c agents.enabled=false` and `-c features.goals=false` (see "Background work"). |
| Gemini | `bash:none` maps to plan approval mode; `bash:inspect` (reviews) and `bash:full` use yolo; an edit-only shape uses auto-edit. Every launch also loads hashd's shipped `agent_policies/gemini.toml`, whose one rule denies `invoke_agent`, the tool that starts subagents, through `--admin-policy`, a flag Gemini CLI added in 0.35.0, so a launch on an older Gemini CLI is expected to fail; user settings and admin or system policy can still outrank or drop the file, and no flag or variable turns off background shell processes or Auto Memory, so none is pinned for them (see "Background work"). |
| Qwen | `bash:none` maps to plan approval mode; `bash:inspect` (reviews) and `bash:full` use yolo; an edit-only shape uses auto-edit. Every launch also excludes the `agent`, `monitor` and `send_message` tools through `--exclude-tools` and sets `QWEN_CODE_DISABLE_WORKFLOWS=1` and `QWEN_CODE_DISABLE_CRON=1`; no flag or variable turns off background shell commands, so none is pinned for them (see "Background work"). |
| Copilot | `writes:false` excludes write, and also excludes shell for `bash:none`; implementation uses yolo. Every launch, including yolo, also excludes the `task` and `write_agent` tools in the same `--excluded-tools` list; no flag or variable turns off async or detached shell commands, so none is pinned for them (see "Background work"). |
| OpenCode | No native read-only knob is declared. `writes:false` is best-effort and unsafe for read-only-critical stages until the agent has an enforceable mode. Every launch also sets `OPENCODE_PERMISSION` with `task` denied, keeping any other rules the variable already holds, so no subagent starts, and `OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=false`, which still refuses background subagents where an agent's own configured permission allows `task` again; no flag or variable stops a shell command from backgrounding itself, so none is pinned for it (see "Background work"). |
| Kimi | Kimi Code 2.x; `writes:false` remains best-effort and unsafe for read-only-critical stages. New sessions bind `agent_policies/kimi.md`, denying `Agent` and `AgentSwarm` while preserving the base prompt. Resume restores that binding without `--agent-file`. No retired Ralph flag is sent. Background shell work remains unrestricted (see "Background work"). |

This is deliberately honest: the permission intent is uniform, but enforcement
depends on what the selected agent can express. Agents without a read-only knob
must not be treated as equivalent to enforced read-only agents.

#### Background work

Every Claude launch pins two Claude Code opt-outs twice each: the agent process environment carries `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` and `CLAUDE_CODE_DISABLE_CRON=1`, and the launch's single inline `--settings` value carries the same entries in its `env`. The launcher sets them after credential injection. No other agent receives any of these pins. Claude Code documents the background-task opt-out as disabling `run_in_background` on Bash and subagent tools, auto-backgrounding and Ctrl+B, and the scheduled-task opt-out as making the `/loop` skill and cron tools unavailable and stopping already-scheduled tasks from firing, including tasks a resumed session restores ([environment variables](https://code.claude.com/docs/en/env-vars), [scheduled tasks](https://code.claude.com/docs/en/scheduled-tasks#disable-scheduled-tasks)). On 2.1.266 it removes `CronCreate`, `CronDelete`, `CronList` and the `/loop` skill, and leaves `ScheduleWakeup` offered, so every shape also denies `ScheduleWakeup` through `--disallowedTools` (Per-Agent Enforcement above).

The same `--settings` value also carries `crossSessionInbound: "refuse"` on every Claude launch, so a stage session drops messages the operator's other Claude Code sessions send into it. Claude Code documents that a `claude -p` session binds an inbox socket like an interactive one, that a message arriving while the receiving session is idle starts a new turn with it, and that with no `crossSessionInbound` value a receiver that prompts for permissions takes every message except one from a sender that bypasses prompts, while a receiver that bypasses prompts still takes messages from a sender that also bypasses them ([cross-session messaging](https://code.claude.com/docs/en/cross-session-messaging#control-inbound-messages)). Without the key, every stage shape would take messages: the `edit` shape's `acceptEdits` counts as prompting and would take them from the operator's ordinary sessions, and the other shapes bypass prompts and would take them from bypassing sessions. It reads managed settings first, then the `--settings` flag, then user settings, applies the first value found, and applies a project or local value only when it is stricter ([settings reference](https://code.claude.com/docs/en/settings-reference#crosssessioninbound)). Denying `SendMessage` stops only the stage agent's own sends; this setting is the inbound control. Sessions hashd does not launch, including the operator's own, keep their messaging.

A managed (policy) settings source that sets either variable to another value or `crossSessionInbound` to another value, or otherwise outranks the invocation settings as Claude Code documents, defeats the launch's value for it on that host, and hashd cannot observe it. hashd leaves managed settings untouched. The project's rules, `CLAUDE.md`, skills and settings load. hashd pins the credential and execution keys above project settings and refuses credential redirects ("Project settings and the run's credential" below). The Claude enforcement claim is limited to what the cited documentation and the isolated live check below establish.

#### Project settings and the run's credential

Claude's project settings source loads on every stage: the repository's `CLAUDE.md`, `.claude/rules/`, project skills and `.claude/settings.json` all apply. On a run that carries a registered credential, the launch's `--settings` value also carries a credential guard. That value outranks the project and local settings files and is outranked only by managed settings, which hashd never reads, overrides or probes. The key list comes from Claude Code's settings reference (settings index); results below were checked on Claude Code 2.1.302, offline, with synthetic keys and local listeners.

The guard pins:
- **Env, each to a safe value:** the endpoint `ANTHROPIC_BASE_URL` (to the run's own value, or `https://api.anthropic.com`), and each of the following the run's own environment does not set, to `""`:
  - the credential variables `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN` and `ANTHROPIC_CUSTOM_HEADERS`;
  - the provider switches `CLAUDE_CODE_USE_BEDROCK`/`_VERTEX`/`_FOUNDRY` and their base URLs;
  - the HTTP(S) proxy variables and `NODE_EXTRA_CA_CERTS`;
  - the OTLP exporter endpoints and headers.

  VERIFIED that a `--settings` env value outranks a project one, for the endpoint and `HTTPS_PROXY`. VERIFIED that `""` pins of the credential variables the run does not use leave the one it uses in place. INFERRED for the others, which follow the same per-key rule. Telemetry exporter variables do not apply from project settings anyway (settings reference, "Variables Claude Code ignores in env").
- **Command keys, to an inert command:** `statusLine`, `subagentStatusLine`, `fileSuggestion` and `otelHeadersHelper`. VERIFIED that none of them ran in a `-p` stage even unpinned. The pin keeps a repository edit from changing that (INFERRED, from the documented per-key precedence).
- **Plugins:** every plugin the repository's `enabledPlugins` names is pinned off. Repository MCP enablement is not pinned; the existing MCP injection behavior above is unchanged.
- **Permission deny rules** for `Edit` and `Write` on `./.claude/settings.json`, `./.claude/settings.local.json` and `./.mcp.json`. Claude Code reloads settings files mid-session, including `permissions`, `hooks` and `apiKeyHelper` (settings, "When edits take effect"), so a stage could otherwise change them after the pre-launch check. Edit deny rules also cover Bash redirect targets and the file commands Claude Code recognises (permissions, path rules). They do not cover every way a shell command can write a file: that residual risk is INFERRED, and containment (#2202) closes it. That deny rules hold in `bypassPermissions` mode is INFERRED: deny is evaluated first and the mode skips prompts.

Before launch, hashd reads the repository's `.claude/settings.json` and `.claude/settings.local.json`. It refuses with terminal `failure_code: agent.profile_refused`, naming the file and the key, what no pin can hold:
- `apiKeyHelper`, `awsAuthRefresh`, `awsCredentialExport` and `gcpAuthRefresh`, which produce a credential, so an inert pin would replace it with nothing;
- any `hooks`. VERIFIED that hook lists merge across layers, so an empty list in `--settings` leaves the repository's hooks running. `disableAllHooks` stops them but also stops the hooks hashd's own `--settings` carries;
- an `env` entry for a credential variable the run's own environment sets, because pinning it would put its value on the command line;
- a settings file that cannot be parsed.

The refusal's Diagnostic source is `agents.claude_project_settings_refused` (failure kind `AgentProfileRefused` once the failure catalogue exists). Runs with no registered credential (a credential from the server's environment) carry no guard: the repository's own settings stand.

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

Every Codex launch pins three config overrides: `-c features.multi_agent=false`, `-c agents.enabled=false` and `-c features.goals=false` (`codexStageOwnedArgs` in `server/internal/agents/runner.go`). On the exec route the launcher adds them after credential and MCP injection, at the permission flags' position before the trailing stdin sentinel, which `exec` and `exec resume` both accept. No shape carries these keys, so each appears once. That reaches every exec shape (`print`, `print_resume`, `json`, `edit`, `review`, `review_resume`, `implement`, `implement_resume`, `detect`) and `stage_agents` reassignments. On the app-server route `codexAppServerArgs` adds them after the fixed sandbox and approval flags and before the MCP flags, which reaches `chat` and `chat_resume`. OpenAI documents `features.multi_agent` as enabling the multi-agent tools (`spawn_agent`, `send_input`, `resume_agent`, `wait_agent`, `close_agent`), `agents.enabled` as enabling or disabling multi-agent tools, and `features.goals` as enabling persisted goals and automatic continuation ([config reference](https://developers.openai.com/codex/config-reference), [subagents](https://developers.openai.com/codex/agent-configuration/subagents)); both subagent keys are pinned because the docs do not say which wins when user config sets the other. `-c` overrides rank above project `.codex/config.toml`, profiles and user `config.toml` ([config basics](https://developers.openai.com/codex/config-basic)), and `exec resume` and `app-server` take `-c` ([CLI reference](https://developers.openai.com/codex/cli/reference)). All pages retrieved 2026-09-14.

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

Every Gemini CLI launch pins one control: `geminiStageOwnedArgs` in `server/internal/agents/runner.go` adds `--admin-policy <install root>/agent_policies/gemini.toml` after the permission flags (`--skip-trust` and `--approval-mode plan|auto_edit|yolo` from `geminiPermFlags`) at the end of argv, after credential and MCP injection, which fresh and `--resume` launches both accept. Gemini CLI added `--admin-policy` in 0.35.0 (2026-03-24): its argument parser (`packages/cli/src/config/config.ts`) is strict, and at [v0.34.0](https://github.com/google-gemini/gemini-cli/blob/v0.34.0/packages/cli/src/config/config.ts) it defines `--policy` but not `--admin-policy`, which [v0.35.0](https://github.com/google-gemini/gemini-cli/blob/v0.35.0/packages/cli/src/config/config.ts) adds. hashd declares no minimum Gemini CLI version and does not check the installed one, so a launch on a release older than 0.35.0 is expected to fail on the unknown flag. `agent_policies/gemini.toml` is an authored file in the hashd source that the core wheel ships next to `agent_policies/kimi.md` and that the launcher reads from `$HASHD_ROOT` the same way; with `HASHD_ROOT` unset, no file there, or a path holding a comma (Gemini CLI splits the flag's value on commas, so such a path would load no policy), the stage fails with a diagnostic before gemini starts. The file holds one rule: `toolName = "invoke_agent"`, `decision = "deny"`, `priority = 999`. The worktree `.gemini/settings.json` MCP file, the permission flags and the credential environment do not change. That reaches every shape (`print`, `print_resume`, `json`, `edit`, `review`, `review_resume`, `implement`, `implement_resume`, `chat`, `chat_resume`, `detect`) and `stage_agents` reassignments. Gemini CLI 0.49.0 documents these ways a stage agent can start work that runs on after its call returns:

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

Every Qwen Code launch pins three controls (`qwenStageOwnedArgs` and `qwenLaunchEnvPins` in `server/internal/agents/runner.go`): `--exclude-tools agent,monitor,send_message`, and `QWEN_CODE_DISABLE_WORKFLOWS=1` and `QWEN_CODE_DISABLE_CRON=1` in the agent process environment. The launcher adds them after credential and MCP injection; the flag goes after the permission flags at the end of argv, which fresh and `--resume` launches both accept. That reaches every shape (`print`, `print_resume`, `json`, `edit`, `review`, `review_resume`, `implement`, `implement_resume`, `chat`, `chat_resume`, `detect`) and `stage_agents` reassignments. The worktree `.qwen/settings.json` MCP file, the permission flags and the credential environment are unchanged. Qwen Code 0.23.4 documents these ways a stage agent can start work that runs on after its call returns:

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

Every GitHub Copilot CLI launch excludes two tools: `copilotPermFlags` in `server/internal/agents/runner.go` joins `task` and `write_agent` (`copilotStageOwnedTools`) into the launch's one `--excluded-tools` value, after the shape's own `write` and `shell` entries, as a comma-separated list; the implement shapes carry `--yolo --excluded-tools task,write_agent`. The permission flags sit at the end of argv. The prompt goes over stdin, not `-p`. The `--additional-mcp-config` file and the credential environment do not change. Copilot CLI's tool availability values name no `write` or `shell` tool (those are `--allow-tool`/`--deny-tool` permission kinds; its file and shell tools are `create`, `edit`, `apply_patch`, `bash` and `powershell`), so the docs do not show that those two entries remove any tool; they stay as they were pending a decision on the read-only shapes. The `--excluded-tools` value reaches every shape (`print`, `print_resume`, `json`, `edit`, `review`, `review_resume`, `implement`, `implement_resume`, `chat`, `chat_resume`, `detect`) and `stage_agents` reassignments. Copilot CLI 1.0.83 documents these ways a stage agent can start work that runs on after its call returns:

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

The opt-in live check `TestLiveCopilotBackground` (`server/internal/agents/live_copilot_background_test.go`, `HASHD_LIVE_COPILOT=1`) launches the real copilot binary through `RunStageWithOptions` in one temp git repo with a temp project config naming copilot in `stage_agents`, with `COPILOT_HOME` and `COPILOT_CACHE_HOME` in temp directories and `COPILOT_AUTO_UPDATE=false`. Routes: review, review_resume, implement, implement_resume, chat and chat_resume. Each turn asks for a short foreground command, a shell command in async mode and one detached, both left running, a subagent through `task` in background mode, whether `write_agent` is offered without calling it, and a last foreground command that prints a nonce and the time. Every command ends by printing a nonce the test wrote outside the repo; the probe work is a `sh -c` command whose `$0` is a random token, which sleeps 60 seconds and writes a marker file. After the run returns, the check looks for the process with `pgrep -f` and for the marker, waits 90 seconds, then looks again. A marker written after the last command's time is work that finished after the turn, whether or not the run waited for it: the docs document that wait for `-p` runs only. Copilot CLI documents no JSONL event schema, so the check decodes none, and reads each report line from its first match in the agent text. Results use the same six values as the Codex check. It fails when a route cannot run, when the foreground command's nonce does not reach an implement route, on a subagent that ran or `write_agent` offered, and on a capability with no attempt or not exercised; an async or detached shell start is recorded, not failed. The implement shape prints plain text with no session id, so unless it prints one the check logs implement_resume as not exercised and fails, and does not borrow another route's session. Once opted in, a missing copilot binary, no `COPILOT_GITHUB_TOKEN` (the only copilot token an agent inherits), a missing `pgrep`, or a `copilot --version` other than 1.0.83 fails it.

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
  those restrictions), a session folder whose journal it cannot find or read,
  or another journal version is refused with a diagnostic and nothing
  launches. Restrictions are never retrofitted; start a new hashd session
  instead. A session no workspace folder holds (another owner's, or one gone
  with its home) is not refused: Kimi finds sessions only there, so it fails
  `Session "<id>" not found.` itself, classified `session_not_found`, and the
  caller starts a fresh session (Kimi Code 2.5.2).
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

Every Kimi Code CLI (`kimi-cli`) launch pins two controls: `kimiStageOwnedArgs` in `server/internal/agents/runner.go` puts `--agent-file <install root>/agent_policies/kimi.yaml` and `--max-ralph-iterations 0` right after the binary, after credential and MCP injection. Every kimi shape ends in `-p` with the prompt on stdin, so the flags go before the shape's own arguments, which fresh and `--resume` launches both accept. `agent_policies/kimi.yaml` is an authored file in the hashd source that the core wheel ships under `hashd_data` next to `prompts/`, `templates/` and `schemas/`; the launcher reads it from `$HASHD_ROOT`, the install root the `hashd` and `hashd-server` bootstrap sets for a source checkout and a packaged install alike. It is `version: 1` with `extend: default` and `exclude_tools: ["kimi_cli.tools.agent:Agent"]`, so the built-in default agent's prompt and every other tool stay as they are. With `HASHD_ROOT` unset, or no file there, the stage fails with a diagnostic before kimi starts rather than launching with subagents available. The `--mcp-config-file` temp file, the credential environment and `KIMI_SHARE_DIR` `config.toml`, and the empty permission flags behind the best-effort read-only status do not change. That reaches every shape (`print`, `print_resume`, `json`, `edit`, `review`, `review_resume`, `implement`, `implement_resume`, `chat`, `chat_resume`, `detect`) and `stage_agents` reassignments. kimi-cli 1.50.0 documents these ways a stage agent's run can go on after its turn:

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

Every opencode launch pins two environment variables: the opencode adapter's `StageOwnedEnv` (`server/internal/agents/harness/opencode.go`), which `applyStageOwnedControls` in `server/internal/agents/runner.go` applies, after credential and MCP injection, so argv and the stdin prompt stay as the shape builds them. That reaches every shape (`print`, `print_resume`, `json`, `review`, `review_resume`, `implement`, `implement_resume`, `chat`, `chat_resume`, `detect`) and `stage_agents` reassignments. The permission flags stay empty and read-only stays best-effort. OpenCode 1.18.31 has these ways a stage agent's run can go on after its turn:

- Subagents. The `task` tool starts a subagent in a child session, in the foreground by default; with `background: true` it returns at once and later sends the subagent's result into the parent session as a new prompt, and a running foreground task can also be promoted to a background job; the source read here does not show what promotes one ([`task` tool](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/tool/task.ts), [agents](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/web/src/content/docs/agents.mdx#task-permissions)). Pinned: `OPENCODE_PERMISSION`, the documented inline permission config ([environment variables](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/web/src/content/docs/cli.mdx#environment-variables)), with `"task":"deny"` as its last key. An inherited value keeps every other key in its order and as written, since the last matching rule wins ([permissions](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/web/src/content/docs/permissions.mdx#granular-rules-object-syntax)); a value OpenCode cannot parse, which it skips, is replaced, and so is valid JSON that is not an object: OpenCode deep-merges the parsed variable without the config schema's normalization of a single action such as `"allow"` to `{"*":"allow"}`, so a string spreads into index keys that name no permission and holds no rule to keep ([config loading](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/config/config.ts)). A denied `task` call is rejected and the tool description lists no subagent, so this also removes subagents that finish inside the turn. Also pinned: `OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=false`, the documented background-subagent switch. OpenCode reads it only from the process environment, and an explicit value outranks the `OPENCODE_EXPERIMENTAL` umbrella; while it is false the `task` tool rejects a background call before it checks the permission ([runtime flags](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/effect/runtime-flags.ts)).

Config can defeat the `task` denial, and hashd cannot observe it. OpenCode merges `OPENCODE_PERMISSION` into the permission object after every config source, managed config files and macOS managed preferences included ([config loading](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/config/config.ts)), but an agent's own `permission`, from `agent` in any config file or an agent Markdown file, is applied after it for that agent, and the docs say agent rules take precedence ([agent permissions](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/agent/agent.ts), [permissions](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/web/src/content/docs/permissions.mdx#agents)). A config file that already sets `task` keeps that key's place in the merged object, so a wildcard rule it lists after `task` also re-allows it. Where config allows `task` again, foreground subagents run; background ones stay refused by the variable, which no config key sets. The docs also let a user invoke any subagent with an `@` mention even when `task` is denied; `opencode run` sends the stdin prompt as one text part, not a mention.

No flag or variable is pinned for this path, and it stays open:

- Shell commands that background themselves. The `bash` tool has no background mode: it starts the command in its own process group and waits for that shell to exit, killing it only on timeout or abort ([`bash` tool](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/tool/shell.ts)). A command that backgrounds a child with `&`, `nohup` or `setsid` returns while the child keeps running, and `opencode run` stops reading the session's events once the session first goes idle, so it does not wait for the child. No flag or variable turns this off, and `bash` also runs foreground commands, so hashd denies nothing.

Plugins, loaded from config files or `.opencode/plugins/`, run code inside the opencode process on its events ([config](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/web/src/content/docs/config.mdx#plugins)); hashd leaves operator plugins as they are and does not pass `--pure`, which drops every external plugin. Without `--attach`, `opencode run` talks to its server in-process rather than through a listening port, so no other client can prompt the stage session. The CLI, tool, agent and config documentation describe no scheduled or deferred tasks. hashd does not read, write, override or probe OpenCode's user, project or managed configuration beyond the `OPENCODE_CONFIG_CONTENT` value it builds from the inherited one to add its MCP servers, and the delivery `opencode.json` it writes in a directory of the launch's own. Source and documentation retrieved 2026-09-16 at the v1.18.31 tag of anomalyco/opencode, the latest release on GitHub and npm (`opencode-ai`) that day.

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

Internal wrappers handle `detect`, `tech_tree`, `plan_split`, and the
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
| C3 | **Session identity**: emit a session id in machine-readable output | per-agent extractor in `server/internal/agents/session_id.go` (codex JSONL events, gemini/qwen `session_id` keys, opencode `sessionID`, copilot's `result` event `sessionId`, kimi stderr hint; copilot and qwen declare `session_id_template`, naming the session of shapes that print no id) | Resume is impossible without capturing the id |
| C4 | **Session resume**: an invocation that continues the same conversation from that id | `_resume` shape templates with `{session_id}` (claude/gemini/kimi/qwen/copilot `--resume`, codex `exec resume` / app-server `thread/resume`, opencode `--session`) | Dirty-tree continuity on retry, and the token payoff: a resumed turn sends only the new instruction instead of re-sending the full prompt |
| C5 | Distinguishable missing-session errors | `sessionResumePatterns` in `server/internal/agents/classifier.go` (`session_not_found` classification) | A dead session must fall back to a fresh run, not retry-loop |
| C6 | Permission flags mappable to `shape_capabilities` | per-agent flag translators in `runner.go` (`--dangerously-skip-permissions`, `sandbox_mode=...`, `--approval-mode ...`); agents without a read-only mode are best-effort and documented as such; an agent whose modes run its commands in an OS sandbox of its own declares `os_sandbox_off_args` (codex), and inside the stage fence launches with that sandbox off: the fence holds a read-only shape to reading and an edit shape to its checkout, for every agent | Shape intent (writes/bash) is enforced per agent |
| C7 | Auth verification verb | `verify_auth` (`claude auth status`, `codex login status`, ...); omit rather than guess when the CLI has no reliable verb | Preflight without inspecting private credential files |
| C8 | Separable tool traffic in JSON streams | `tool_output_fields` beside `stdout_format` (codex `item.command`, `item.aggregated_output`, `item.arguments`, `item.result`; claude `message.content[type=tool_use]`, `message.content[type=tool_result]`, `tool_use_result`); a plain stream declares none | The failure classifier reads only the agent's own text: a file the agent read that quotes an error must never decide the run's failure |

An agent missing C3/C4 still works for every one-shot stage; it simply never
takes a `_resume` path (each retry re-sends the full prompt). An agent missing
C6's read-only mode may only be trusted with write-shaped stages.

#### C2 detail: final output and activity

For Claude, the terminal `type: result` frame is authoritative at every stage,
including implementation, review and adjudication. Its `result` is read exactly
as the buffered JSON envelope was. Earlier assistant frames, tool calls and tool
results are activity for watching; a verdict-shaped payload in one cannot become
a stage result. A recognized stream with no terminal result has no final answer.
The existing plain-print commands retain their completed plain output.

The runner writes Claude activity to a separate per-invocation directory beneath
`<project-ops>/agent-streams/workstreams/<id>/` (or `stories/<id>/` before a
workstream exists), using the resolved stage log name and existing `.attemptN.log`
rotation. Workstream ownership wins when both IDs are supplied. Unowned calls
keep their separate `stages/streams/` files outside story cleanup. The ordinary stage log keeps final-envelope output, stderr and exit
metadata. Transcript files keep their existing prompt, final output, stderr and
metadata layout; intermediate frames are not copied into them. Existing files
are not rewritten or deleted. Tool-call, profile and usage recording still read
the raw attempt before its output is reduced for stage consumers.

On story archive, `agent_streams.retain_full_archive` (a project setting, default
`false`) deletes these new owned activity files. Set it to `true` to keep one ZIP
per invocation instead. Cleanup includes the story's planning activity and its
workstreams; active writers are protected by the existing file lock mechanism.
Filesystem failures follow the existing archive retry path. Published ZIPs are
never replaced during replay. Lock files remain to preserve lock identity.
Existing logs, transcripts and unowned activity are never cleanup targets.

A killed stage retains the activity already written in its stream file until archive. Missing
final output and missing usage remain missing; a tool request is evidence of a
request, not proof that the tool completed. No new timer or limit is introduced.

Claude's default stage commands and explicit agent shapes both stream for review,
final_review, adjudicate and breakdown. Final-review repair rounds retain the
configured reviewer's `review_resume` shape and agent/model/timeout policy.

Other harness readers are unchanged. For harnesses whose answers are carried in
assistant messages, `agents.PayloadScopes` and `SelectAgentPayload` keep the
existing message-attribution rules: only the agent's text counts, newest acceptable
payload first, with the caller's existing envelope fallback tier. This change does
not impose Claude's result-frame protocol on Codex, Kimi or other harnesses.

### Invocation placeholders

| Placeholder | Meaning | Guard |
|---|---|---|
| `{prompt}` | stdin sentinel (legacy spelling; prompt always rides stdin) | rewritten at assembly |
| `{session_id}` | the resume id | command fails fast if the template needs it and the value is empty |
| `{worktree}` | implement cwd flag (codex `-C {worktree}`) | |
| `{model}` / `{effort}` | rendered through the agent's `model_template` / `effort_template` | dropped when the agent declares no template |

An agent that declares `effort_template` must also declare `effort_levels`, the
values its effort flag accepts (claude `low`..`max`, codex `low`/`medium`/`high`/`xhigh`);
an agent with no `effort_template` declares none.

### Fresh vs resumed invocations by stage

Reference shapes shown for the default agent (claude); every agent substitutes
its own template for the same shape. "Resume trigger" is who decides to take
the `_resume` path.

Each fresh/resume pair reads one `stages.<base>.timeout` setting, including
defaults and overrides. Resume stages have no separate timeout setting or alias;
deadline diagnostics name the base setting. Outer activity floors/margins remain.

| Stage | Fresh invocation (claude) | Resumed invocation (claude) | Resume trigger | Session store |
|---|---|---|---|---|
| implement | `claude --output-format stream-json --verbose -p` (stdin: full commit prompt + branch diff; session captured before work) | `claude --resume {session_id} --output-format stream-json --verbose -p` (stdin: retry feedback or crash reorientation) | saved session + retry feedback or crash retry; same rule for FIX (`runflow/implementdriver.go`) | `workstreams.implementer_session_id` (durable) |
| review | `claude --output-format stream-json --verbose -p` (activity streams live; the terminal result supplies the verdict) | `claude --resume {session_id} --output-format stream-json --verbose -p` (stdin: retry/redraft delta) | in-package semantic-retry and format-redraft loops (`stages/review/retry.go`) | in-process (same stage run) |
| final_review | `claude --output-format stream-json --verbose -p` | configured final reviewer's `review_resume` shape (stdin: repair delta) | shared output-repair loop; final-review policy retained | in-process (same stage run) |
| tech_tree | dedicated wrapper, print shape | `tech_tree_resume` | discovery flow hands its session forward in-flow | in-flow (dies with the flow) |
| chat | stream-json + tool allowlist | `chat_resume` | server: `chat_sessions` row exists | `chat_sessions.agent_session_id` (durable) |
| pm_refine / pm_edit | `claude --print --output-format stream-json --verbose` (stdin: SPEC+REQS+story) | `claude --resume {session_id} --print --output-format stream-json --verbose` (stdin: retry feedback or interrupted-run continuation, plus the current story size section; pm_refine also adds its browser section) | validation retries resume the rejected attempt's session; an infrastructure retry resumes the killed run's own registered ID; other agent failures without diagnostics rerun fresh | workflow loop state and durable launch record |
| pm_discovery | `claude --print --output-format stream-json --verbose` (stdin: SPEC+REQS+backlog) | `pm_discovery_resume` | operator: `hashd plan discover --resume`, only for the latest failed or killed run | durable launch record and `discovery_failed.resume_session_id` |
| pm_discovery_resume | -- (resume shape for pm_discovery) | `claude --resume {session_id} --print --output-format stream-json --verbose` (stdin: continuation prompt) | resumes the killed attempt's own chosen ID; session-not-found falls back cold once with a warning | latest discovery run's saved session |
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
   +-- context_exhausted ------> clear saved session, ONE fresh fallback (full prompt)
   +-- api_rejection ----------> park (no retry)
   +-- auth family / usage_limit -> fail (no fresh-session fallback)
```

`session_not_found` is a first-class classification: the runner tags it only
on resume attempts, it is never retried as transient, and each caller falls
back cold exactly once (implement, tech_tree, review, chat all implement this
convention). A resume that exhausts its context falls back the same way in
implement, review and the planner: the spent session is what cannot carry the
turn, so a fresh attempt is still worth one launch; only a fresh attempt that
also exhausts fails the run.

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
is classified as `usage_limit`. Hashd permits one immediate retry within the call’s attempt budget. The claude structured error
envelope (`is_error` or `terminal_reason: "api_error"` plus
`api_error_status`) routes by status before any prose matching; a structured
401 lands the agent-auth family (`agent_needs_login` /
`agent_invalid_api_key` -- non-retryable but resumable after re-auth, and
the login signal outranks key-shaped tags like `authentication_error`).
Both fail with their `failure_kind` riding the same run-row / `run_failed` /
`current_errors` channel as the capacity family, and the implement driver
and review stage report the affected account. A failed quota retry ends the run with its final error. Use `hashd agents` to inspect credentials and `hashd run` to retry manually.

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

When a per-commit review is retried after an infrastructure failure, it resumes the killed attempt's own caller-chosen session ID from durable launch records or persisted stage state for the same run, microcommit and review round. Closed-list rounds retain the judge's CARRY list. A missing session falls back cold once within the same round with a durable warning. Operator cancellation and attempts without a recorded caller-chosen ID keep their existing behavior. The whole-stage retry policy controls whether and when retries occur.

- A session id that must survive process death is persisted **durably** and
  read back by whatever re-enters the stage (`workstreams.implementer_session_id`,
  `chat_sessions`, discovery and planner launch records). The discovery ->
  tech_tree handoff is in-flow; discovery recovery reads the durable records.
- For discovery, a killed attempt's retry resumes that attempt's own chosen
  session ID through `pm_discovery_resume`. This is operator-initiated with
  `hashd plan discover --resume` and applies only to the latest failed or
  killed discovery run; it never selects an older run's session.
- For `pm_refine` and `pm_edit`, a planner rerun after an infrastructure
  failure reads the killed run's registered session ID and resumes that
  attempt's own session. Validation retries still resume the rejected
  attempt's session with feedback. In both discovery and refine/edit, a
  `session_not_found` response falls back cold once with the full prompt and
  a warning.
- Saved sessions are cleared when their context is spent: micro-commit done
  (commit stage), `context_exhausted`, operator reset, chat clear.
- An agent declaring `session_id_template` (Claude) launches each attempt
  under a session id hashd chooses. That id is in the attempt's stage log
  header and on the launch event, and the runner fires it through OnSessionID
  before the process starts, so callers persist it durably before the agent
  does any work, on both engine paths. Other agents' ids still come from
  their output: the stdout sniffer fires OnSessionID on the first id it sees,
  or the result reports it. The launcher's result (`agents.StageResult`)
  carries session ids for every agent.

---

## Directives

Directives are curated standing rules that guide AI agents. They exist at three levels:

```
~/.config/hashd/directives.md        # Global user preferences
<ops>/projects/<project>/directives.md  # Project rules, server-side in the project's ops dir
workstreams.directives                  # Workstream-specific text in the project DB
```

Project directives live only in a server-side file in the project's ops
directory (`<ops>/projects/<project>/directives.md`, beside `config.yaml` and
the `prompts` overrides dir). The server reads them from there, including for
multi-repo projects and projects without a repository root, and supplies that
text to local and remote runners. A `directives.md` in the project's repository
or a story checkout is not read at any level; it is an ordinary file hashd
ignores. Missing or blank means no project directives; an unreadable file stops
the stage with a Diagnostic. `hashd directives edit project`, `hashd directives
ai-edit project` and the Web Settings Directives panel save to the same
server-side file and never write into the repository.
The same source applies to planning and add-commit; existing stage filters still
apply. Disabling `instructions.directives` omits all three levels.

**Why `directives.md` not `AGENTS.md`?** We want hashd to control when directives are passed to agents, not have agents auto-read them. Using `directives.md` ensures agents only see these rules when we explicitly include them in prompts.

**Key principle:** Directives are curated policy and belong to hashd, not to the project's repository. Global and project directives are files on the server host; workstream directives are stored with the workstream.

### Instructions settings

Instructions come only by setting. The `instructions` group, at system or project level:

```
hashd project config set instructions.directives false     # leave the directives out of stage prompts
hashd project config set instructions.repo_files false     # agents ignore the checkout's CLAUDE.md, AGENTS.md, ...
```

`instructions.additional_files` is a list, authored as YAML in the system or project `config.yaml`:

```yaml
instructions:
  additional_files: [~/team-rules.md]   # given to every agent, on top of directives.md and the checkout's files
```

No agent reads an instruction file from a folder above its checkout, nor its own home's personal file: put a personal file you want agents to have in `instructions.additional_files`. `hashd doctor` names the files agents are not given, and why. The behaviour is in [WF.md](../WF.md#instructions).

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

# AI-assisted editing: the pm_edit agent revises the document server-side
# against your instruction (-m/--message; prompted for on a terminal), the
# proposal is shown as a diff, and only a confirmed save is written
# (-y/--yes confirms without a terminal; without one both flags are required)
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

The file-backed global and project levels carry the same token, optionally.
`GET /directives` returns an `etag` on the global and project sections,
computed over the content returned -- for global, including a legacy
`~/.config/wf/directives.md` it fell back to. `PUT /directives/global` and
`PUT /directives/project` accept it as an optional `base_etag`; a save whose
token no longer matches is refused with 409 under the level's source
(`global.directives.cas_mismatch`, `project.directives.cas_mismatch`) and
nothing is written. The project token is computed over the server-side
`<ops>/projects/<project>/directives.md`, which is where the project save
lands. Saves of the same file are serialized, so two built on the
same token cannot both land. `hashd directives edit` and `hashd directives edit
project` send the token they read and, like the workstream level, keep the
edited buffer on refusal. A save without `base_etag` is not revision-checked
and remains last-write-wins (the Web Settings Directives panel saves this way).

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
2. **Across attempts** — each long agent stage activity carries a `RetryPolicy` (`agentActivityOptions`: `InitialInterval 5s`, `BackoffCoefficient 2.0`, `MaximumInterval 60s`) plus a 120s `HeartbeatTimeout`. It retries ONLY infrastructure failures (worker death detected via a missed heartbeat, DB faults). An agent *outcome* is returned as data with a nil error and never retries — the outcome/error split is the guard, so a review verdict of "changes required" is data, not a retryable error. Tier A stages whose whole-body re-run is crash-safe (implement, adjudicate, concern_triage, test, probe, detect, provision, final_review, and review -- its agent-outcome errors carry the typed non-retryable `review_outcome` marker so only infra shapes retry) use `MaximumAttempts>1`; stages that persist a plan or transition mid-body (breakdown, partial_breakdown) and the one-shot commit leg keep the heartbeat but stay `MaximumAttempts:1`. On a Tier-A retry the implement driver resumes the agent's session (crash-resume); other stages re-run fresh. **Cancellation is a different layer from an agent outcome.** When the activity context is cancelled -- worker shutdown, heartbeat-timeout invalidation, a persistence brownout -- the runner kills the agent subprocess off `ctx.Done` and the killed attempt classifies `interrupted` (the holistic judges surface the same kill as a failed judge call / error verdict). That is the box blinking *before* the agent finished, not the agent's answer. So a **single boundary helper, `propagateCancel`, wraps the return of every agent-stage activity** (implement, test, review, final_review, adjudicate, concern_triage, breakdown, partial_breakdown, the committed-breakage probe, provision, detect, scope_adjudicate): when the context is cancelled it discards whatever the driver returned -- a nil-error `interrupted` / failed-judge-call / `Verdict:"error"` / `"Build failed"` outcome, or a wrapped context error -- and returns the bare `ctx.Err()`. This is one authority rather than a guard per stage, so no stage -- present or future -- can silently masquerade a cancellation as an outcome. Temporal then splits the two cancellation kinds by cause: an infrastructure-driven cancel (worker death / heartbeat-timeout / brownout, a non-server cause) is retryable, but only stages with `MaximumAttempts>1` re-run while their retry budget remains (implement resumes its session; the judge runs again). The one-shot `partial_breakdown` (`MaximumAttempts:1`) instead routes its interrupted attempt through `failStage` to `StatusFailed`, preserving work for explicit retry; a **server-requested cancel (operator stop) carries a `CanceledError` cause, so the SDK reports it terminal-canceled and the workflow's cancellation path handles it -- no retry**. Returning the bare `ctx.Err()` -- not a wrapped or typed error -- is what lets the SDK's `cancelAllowed` check make that split. The fail-closed path is **not** weakened -- it is reached truthfully. A judge whose agent call failed with the context still alive (its agent was rejected, exhausted context, or self-exited) ends the run `failed` as `The <judge> judge could not run: <reason>`, never a ruling; deadline exhaustion instead closes the run `failed` with an operator note naming the in-flight stage and micro-commit and pointing at `hashd run` -- the abandoned attempt surfaced, not left as a stale pre-kill reading. The discriminator everywhere is `ctx.Err()`: non-nil means the box blinked (propagate -- Temporal retries an infra cancel, terminates a server-requested one); nil means the agent produced the outcome (fail-closed, no retry).

These retries happen transparently within a single micro-commit cycle. The business-logic retry loops (implement/test/review = 5, merge-conflict = 3, PR-rebase = 3) are workflow-level, independent of activity retries.

### hashd's MCP tools and the code graph

hashd gives its agents tools as MCP servers. Each tool is declared once
(`config.MCPTool` in `server/internal/config/mcp_tools.go`), and the
declaration carries everything that belongs to the tool:

- **its server**, the MCP server a launch registers;
- **its hooks**, agent hooks that only make sense with that server;
- **its prompt sections**, the templates that tell an agent the tool is there,
  and a **prompt variable** every template can test;
- **its setting**, the project setting that turns all of it on or off.

These go into a stage together or not at all. A launch installs a server's
hooks only when it carries the server (`MCPServerDefinition.Hooks`,
`installServerHooks` in `server/internal/agents/mcp_config.go`). A prompt
renders a tool's sections only while the project has the tool on: whoever
renders a stage's prompt knows its project and passes the project's `mcp`
settings to the renderer (`prompts.RenderFor`), which renders an off tool's
sections as nothing, wherever they are rendered or included
(`toolSectionOff` in `server/internal/prompts/includes.go`). The renderer
reads no configuration itself, and refuses a tool's section when it was
given no settings. A tool added later brings its own hooks and sections by
declaring them the same way.

The one tool declared today is the **code graph** (`config.CodeGraphTool`):
the code-map index hashd builds of each checkout with codebase-memory-mcp,
and the `code` MCP server that queries it.

| Belongs to the code graph | What it is |
|---|---|
| Server | `code`: `hashd code mcp-shim`, bound to the launch checkout's code map |
| Hook | The grep redirect, for Claude Code: before `Bash`, `Grep` and `Glob` it runs `hashd internal grep-redirect-hook`, and the server serves the grep, rg and find landing pads (`--grep-hook`). `mcp.grep_hook` turns it on or off |
| Prompt sections | `code_tools_section.md` ("Code exploration") and `include_code_tools.md`, the same section under its `## Code-Analysis Tools` heading |
| Prompt variable | `code_graph`, true while the code graph is on. Templates wrap their own words about the code tools in `{% if code_graph %}`: each stage's "most useful tools" list, and steps that name an `mcp__code__` tool, which read as plain file reading otherwise |
| Setting | `mcp.code_graph`, per project, on by default |

#### `mcp.code_graph`

```bash
hashd --project <name> project config set mcp.code_graph false   # run this project's stages without the code graph
hashd --project <name> project config set mcp.code_graph true    # the default
```

It is a project setting: whether a codebase is worth mapping is one project's
call. It is not written at system scope. With it off, for that project:

- no launch gets the `code` server, and so none gets the grep redirect hook,
  whatever `mcp.grep_hook` says: the hook belongs to the server;
- no code map is built: not at provisioning, not when a checkout is activated
  or reset, not for a planning checkout, and not before a launch. The
  workstream's code-map name is still recorded, since it is only the name
  derived from the checkout's path, so nothing that reads the name fails;
- every prompt is rendered without the code-tools section, its heading, the
  per-stage tool lists and the steps that name a code tool. Every stage runs,
  with the agent's own file and search tools and hashd's other MCP servers;
- the `hashd code` query commands and their REST routes refuse (409,
  `code.code_graph.off`) with a message that names the setting and the command
  that turns it on. Nothing is indexed on demand.

The setting is read when a stage starts: when its prompt is rendered and when
its agent is launched. Nothing is migrated when it changes. Turned on, the
next launch indexes its checkout, as every launch does. Turned off, launches
stop getting the server, and an index already built is left for the usual
cleanup when its story ends.

`mcp.grep_hook` is unchanged and still on by default. It applies only while
the code graph is on.

A project's own override of a prompt (`<project>/prompts/`) is rendered by
the same rules: its `{% include "include_code_tools.md" %}` or
`{{ code_tools_section }}` goes with the tool. Words about the code tools that
an override writes itself stay unless it wraps them in `{% if code_graph %}`.

#### `mcp.project_servers`

```bash
hashd config set mcp.project_servers false                           # disable hashd's injection system-wide (for projects without an override)
hashd config reset mcp.project_servers                               # clear the system override (falls back to the enabled default)
hashd --project <name> project config set mcp.project_servers false  # override for one project
hashd --project <name> project config reset mcp.project_servers      # clear the project override (inherits system, then default)
```

`mcp.project_servers` is enabled (`true`) by default. A system-scope value
(`hashd config set|reset mcp.project_servers`) applies to every project that
does not set its own override; a project-scope override
(`hashd project config set|reset mcp.project_servers`) takes precedence for
that project. `hashd project config` (and `hashd project config show
mcp.project_servers`) displays the effective value alongside its provenance:
`(default)`, `(system)`, or `(project)`. TUI and Web controls for this setting
are tracked in STORY-0763.

The setting governs only whether hashd injects repository-declared servers
(read from the repository's root `.mcp.json` at the launch's pinned base
commit) into stage launches. The agent harness's own MCP discovery stays on
whether `mcp.project_servers` is `true` or `false`: servers the harness
discovers itself come from the working tree and its other sources, and the
harness's own precedence decides a shared name. Repository instruction files,
rules, and skills are unaffected.

Injected stdio servers are started by the harness under its ordinary child
environment — which may include the agent's sign-in and other credentials —
using the harness's own env-map syntax. hashd does not isolate those server
subprocesses, does not resolve or check references in their `env` maps, and
never writes substituted values into its configuration or launch evidence (each
attempt's `mcp_delivery` transcript metadata records sorted `env_keys` names
only). Authenticated HTTP owner sign-in for project MCP servers is tracked in
STORY-0762.

### Overview delivery pages and harness qualification

The shared code MCP shim captures one complete `get_architecture` result per
initial `overview` call. `aspects` still selects upstream content; it does not
bound delivery. The result text contains a JSON page with `snapshot`, `offset`,
`next_offset`, `has_more`, `total_content_length`, and `data`. Offsets and total
length count UTF-8 bytes of the original MCP result JSON. Concatenate `data`
in offset order to reconstruct every upstream field, including content
annotations, resources, structured content, and unknown metadata. A page may
split a JSON value, but never a UTF-8 code point. The initial `orientation` is a
supplementary preview of the architectural text, not a replacement for detail.

Continue with only `snapshot` and `offset: next_offset`, until `has_more=false`.
Snapshots are immutable, bound to the shim session and its code-map project,
and retained until session exit without eviction or continuation-count limits.
Interleave snapshots freely. Unknown snapshots, conflicting selections, and
invalid offsets fail explicitly; start a new overview after a session restart.
The existing upstream transport's 10 MiB frame limit remains a hard failure;
there is no claim that paging can recover a result the upstream cannot send.

Each delivered overview frame is at most 4096 UTF-8 bytes **including** MCP
content encoding, nested JSON escaping, paging metadata, JSON-RPC ID/envelope,
and newline. The builder measures actual serialized candidate responses.
If even one code point cannot fit, it refuses delivery explicitly using the
original request ID. If the correlated refusal also exceeds the budget, the
shim terminates the MCP session with an actionable diagnostic rather than
substituting an ID the client cannot correlate with its pending request. This
ceiling is not a prompt limit and does not use `PromptInputLimitChars`.

Harness framing and token accounting are separate from this wire limit.
Decoding the page's single text block cannot increase its UTF-8 byte count;
model-facing wrappers can add bytes/tokens. A four-characters-per-token rule
would not establish safety for escaped, non-ASCII, or adversarial text. The
following evidence inventory was checked on 2026-11-15. **All-harness
qualification is deferred**, independently of the paging implementation,
under the operator's 2026-11-15 ruling (CLQ-753). It is not a completion
condition for this delivery fix. Documented thresholds or an unchanged text
conversion alone do not measure every model-facing wrapper and token counter.
No live model boundary probes were run. This table records evidence and open
qualification work; it does not claim successful qualification of every
registration in `defaults.yaml`.

| Registration | Versioned source or documented evidence | Qualification remaining |
|---|---|---|
| `claude` | Local version `2.1.306`; [official MCP limits](https://code.claude.com/docs/en/mcp#mcp-output-limits-and-warnings) document a 25,000-token default and an independent 50,000-character persistence threshold. Both apply to Claude only. | Measure the harness wrapper and token estimate for the actual encoded boundary page; documentation is not versioned implementation evidence. |
| `codex` | Local version `0.167.1`; [MCP call handling](https://github.com/openai/codex/blob/rust-v0.167.1/codex-rs/core/src/mcp_tool_call.rs) and [serialized-result truncation](https://github.com/openai/codex/blob/rust-v0.167.1/codex-rs/utils/output-truncation/src/lib.rs) distinguish event byte limits from model/history truncation. | Trace the effective model/history budget and its framing; the event byte cap alone is insufficient. |
| `gemini` | [v0.49.0 MCP invocation and content transformation](https://github.com/google-gemini/gemini-cli/blob/v0.49.0/packages/core/src/tools/mcp-tool.ts) forwards a text block's text to the model-facing parts. | Qualify the scheduler/model wrapper and token budget; binary not installed here. |
| `agy` | Registry minimum `1.5.1`; [official ACP changelog, v1.4.0](https://antigravity.google/docs/changelog) introduces `_meta.antigravity.mcpMaxOutputBytes`. | The documented configurable limit does not establish its default or framing; a runtime boundary probe against the installed CLI is still needed. |
| `opencode` | Local version `1.19.5`; [v1.19.5 truncation](https://github.com/anomalyco/opencode/blob/v1.19.5/packages/opencode/src/tool/truncate.ts) checks both 2000 lines and 50 KiB by default. Our page text escapes internal newlines. | Qualify MCP conversion and model wrapper, including effective configuration, rather than treating the generic truncation helper as the whole path. |
| `kimi` | [1.50.0 MCP conversion](https://github.com/MoonshotAI/kimi-cli/blob/1.50.0/src/kimi_cli/soul/toolset.py) budgets content characters; [text conversion](https://github.com/MoonshotAI/kimi-cli/blob/1.50.0/packages/kosong/src/kosong/tooling/mcp.py) retains text. Local executable reports `2.5.2`, so this source does not qualify it. | Inspect the installed version's path and model-facing framing or run a version-recorded boundary probe. |
| `qwen` | [v0.23.4 MCP invocation](https://github.com/QwenLM/qwen-code/blob/v0.23.4/packages/core/src/tools/mcp-tool.ts) uses a 500,000-character per-text-part budget with no line cap. | Qualify the remaining scheduler/model wrapper and token accounting; binary not installed here. |
| `copilot` | [Official command reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference#environment-variables) documents a 20,480-byte default for `COPILOT_LARGE_OUTPUT_THRESHOLD_BYTES`. | Establish versioned implementation and framing evidence or run a version-recorded probe; binary not installed here. |

When undertaking the deferred qualification, record the harness version, unmodified
registry launch shape, effective output settings, exact tool response bytes,
and model-facing tool-result bytes and token count. Retrieve the repository-size
fixture through advertised snapshot continuations, compare concatenated data
with the captured result, and verify no file offload, truncation, or overflow at
the boundary. Include escaped controls, non-ASCII text, and a large scalar.
Record harness-added framing separately from the shim frame and demonstrate
both fit that version's applicable byte/character/token budgets. Record results
per registration without treating that future work as a gate for this paging fix.
