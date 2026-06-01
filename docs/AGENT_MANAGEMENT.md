# Agent Management

## Agent-driven Project Add

For scripted onboarding, agents should treat `wf project add` as a two-step flow:

```bash
wf project add /path/to/repo --no-interview --suggest
wf project add /path/to/repo --no-interview
```

The first command runs investigation only. It prints the canonical settings block, stores those proposed settings in the project-add cache, and exits without modifying project state.

The second command reuses the stored defaults, applies any explicit flag overrides, prints the same canonical settings block again, and then executes project add.

Use explicit flags on the second command when the proposal needs correction, for example:

```bash
wf project add /path/to/repo --no-interview \
  --description "Payments API" \
  --git-name "Alice" \
  --git-email "alice@example.com"
```

Interactive operators can still use:

```bash
wf project add /path/to/repo --suggest
```

That runs the same investigation, stores the defaults, and then opens the wizard with AI-prefilled values.

## Switching Agents

### See what's installed

```bash
wf agents
```

Shows all 7 registered agents (Claude, Codex, Gemini, OpenCode, Kimi, Qwen, Copilot), their install status, supported shapes, and current stage assignments.

### Per-stage assignment

Each of the 18 workflow stages has a "shape" describing the kind of invocation it needs. Any agent can be assigned to any stage whose shape it supports.

```bash
# Assign gemini to the breakdown stage
wf project config set stage.breakdown gemini

# Assign claude to review
wf project config set stage.review claude
```

Validation prevents incompatible assignments (e.g., an agent without `review_resume` cannot serve the review resume stage).

Assignments are validated against the agent registry before they are saved.

Agents with `available` status (not yet verified with hashd) require `--force`:

```bash
wf project config set stage.breakdown gemini --force
```

### Bulk assignment by role

```bash
# Set all non-implement stages (16 stages) to gemini
wf project config set planner gemini --force

# Set implement + implement_resume (2 stages) to claude
wf project config set coder claude
```

If an agent does not support the required stage shapes, the assignment is rejected.

### Stage reference

| Phase | Stage | Default Agent | Shape |
|-------|-------|---------------|-------|
| Planning | detect | claude | json |
| Planning | pm_discovery | claude | print |
| Planning | pm_refine | claude | print |
| Planning | pm_edit | claude | print |
| Planning | pm_route | claude | print |
| Planning | pm_annotate | claude | edit |
| Planning | pm_describe | claude | print |
| Implementation | breakdown | claude | review |
| Implementation | implement | codex | implement |
| Implementation | implement_resume | codex | implement_resume |
| Review | concern_triage | claude | print |
| Review | review | claude | review |
| Review | review_resume | claude | review_resume |
| Review | fix_generation | claude | json |
| Review | plan_add | claude | json |
| Completion | final_review | claude | review |
| Completion | pm_spec | claude | json |
| Completion | pm_docs | claude | edit |

### Agent shape support

Which agents can serve which stage shapes (`wf agents` shows this live):

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
wf project config reset stage.review
```

Reset all stage assignments:

```bash
# Reset all stage overrides at once
wf project config reset --all
```

Use `wf project config diff` before resetting to inspect which project overrides will be cleared. `wf project config show <key>` shows the effective value and Default/System/Project stack for one setting.

Nuclear option -- reset all behavioral overrides (stage assignments, autonomy mode, etc.) back to defaults:

```bash
wf doctor --reset-to-defaults
```

This preserves identity and build settings (name, repo_path, test_cmd, etc.) but strips stage_agents and other behavioral overrides.

### Direct config editing

All stage overrides can also be set by editing `config.yaml` directly. See `../config.sample.yaml` in the repo root for all available settings with commented-out examples, including common recipes like using Claude for implementation or switching models.

---

## Authentication

Most CLI coding agents support both OAuth (interactive login) and API key authentication. When both are configured, agents differ on which takes precedence -- leading to silent auth failures or unexpected billing. Hashd verifies auth by delegating to each agent CLI's own status command and only strips API-key env vars when the project explicitly forces OAuth mode.

### Auth mode

Set with `wf project config set auth-mode <mode>`:

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
| **Qwen** | Mutually exclusive | Nothing to strip | `qwen auth status` |
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

### Diagnostics

Preflight verifies assigned agents before a workstream runs. Agents with `verify_auth` use the CLI-owned status command, so new provider auth modes are recognized without hashd parsing credential files. If the command exits non-zero, hashd surfaces a Diagnostic naming the agent, command, and stderr/stdout excerpt.

### Common scenarios

**"I only have an API key (no OAuth)"**

It just works. `auto` mode keeps the API key in the environment.

**"I use OAuth but also have an API key in my shell"**

`auto` mode keeps the API key and lets the CLI decide. If you want OAuth to win for agents where keys override OAuth (Claude, Gemini), set:

```bash
wf project config set auth-mode oauth
```

**"I want to switch from OAuth to API key"**

```bash
wf project config set auth-mode api-key
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

All LLM prompts live in `prompts/*.md` as templates. They use `{variable}` placeholders for dynamic content and `{{ }}` for literal braces. HTML comments (`<!-- ... -->`) are stripped before sending to the LLM.

Prompts are loaded and rendered by `orchestrator/lib/prompts.py`:

```python
from orchestrator.lib.prompts import render_prompt
prompt = render_prompt('review_contextual', commit_title='Add auth', diff='...')
```

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
| `review_retry.md` | review (resume) | Shorter prompt for re-reviews |
| `review_history.md` | review | Previous review cycles section |
| `review_format_retry.md` | review (resume) | JSON format correction prompt |
| `final_review.md` | final_review | Holistic branch review before merge |

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
| `breakdown.md` | breakdown | Break story into 2-5 micro-commits |
| `fix_generation.md` | fix_generation | Generate FIX commits for merge gate failures |
| `conflict_resolution.md` | merge (resolve) | Resolve git rebase conflicts |
| `directives_edit.md` | directives | AI-assisted editing of directives files |
| `pair_programmer.md` | chat | System prompt for pair programmer chat |

### Viewing and managing prompts

```bash
# List all prompts grouped by pipeline phase
wf prompts list

# Show a prompt template (with metadata header)
wf prompts show implement

# Show the built-in default even if a project override exists
wf prompts show implement --default
```

### Per-project prompt overrides

Projects can shadow any default prompt template. Overrides are stored in the ops dir under `projects/<name>/prompts/<template>.md` -- not in the repo, since prompts are operational config.

Override resolution: project `prompts/<name>.md` > built-in `prompts/<name>.md`.

Overrides are by **prompt template name**, not stage name. Some stages compose multiple templates (e.g., implement uses 6), so overriding at the template level gives fine-grained control.

```bash
# Create an override (copies default, opens $EDITOR)
wf prompts edit breakdown

# See what changed
wf prompts diff breakdown

# Restore the default
wf prompts reset breakdown

# Reset all overrides at once
wf prompts reset --all
```
