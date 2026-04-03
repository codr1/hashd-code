# Agent Management

## Switching Agents

### See what's installed

```bash
wf agents
```

Shows all 6 registered agents (Claude, Codex, Gemini, OpenCode, Kimi, Qwen), their install status, supported shapes, and current stage assignments.

### Per-stage assignment

Each of the 14 workflow stages has a "shape" describing the kind of invocation it needs. Any agent can be assigned to any stage whose shape it supports.

```bash
# Assign gemini to the breakdown stage
wf project config set stage.breakdown gemini

# Assign claude to review
wf project config set stage.review claude
```

Validation prevents incompatible assignments (e.g., codex has no `print` shape, so it can't do planning stages).

Agents with `available` status (not yet verified with hashd) require `--force`:

```bash
wf project config set stage.breakdown gemini --force
```

### Bulk assignment by role

```bash
# Set all non-implement stages (12 stages) to gemini
wf project config set planner gemini --force

# Set implement + implement_resume (2 stages) to claude
wf project config set coder claude
```

Stages whose shape the agent doesn't support are skipped with a warning.

### Stage reference

| Phase | Stage | Default Agent | Shape |
|-------|-------|---------------|-------|
| Planning | pm_discovery | claude | print |
| Planning | pm_refine | claude | print |
| Planning | pm_edit | claude | print |
| Planning | pm_annotate | claude | edit |
| Planning | pm_describe | claude | print |
| Implementation | breakdown | claude | json |
| Implementation | implement | codex | implement |
| Implementation | implement_resume | codex | implement_resume |
| Review | review | claude | review |
| Review | review_resume | claude | review_resume |
| Review | fix_generation | claude | json |
| Review | plan_add | claude | json |
| Completion | final_review | claude | json |
| Completion | pm_spec | claude | json |
| Completion | pm_docs | claude | edit |

### Agent shape support

Which agents can serve which stage shapes (`wf agents` shows this live):

| Agent | print | json | edit | review | review_resume | implement | implement_resume |
|-------|-------|------|------|--------|---------------|-----------|-----------------|
| claude | x | x | x | x | x | x | -- |
| codex | -- | -- | -- | -- | -- | x | x |
| gemini | x | x | x | x | x | x | -- |
| opencode | x | x | -- | -- | -- | x | -- |
| kimi | x | x | x | -- | -- | x | -- |
| qwen | x | x | x | x | -- | x | -- |

### Restoring defaults

Reset a single stage assignment:

```bash
# Reset review back to default agent
wf project config reset stage.review
```

Reset all stage assignments:

```bash
# Reset all stage overrides at once
wf project config reset stages
```

Nuclear option -- reset all behavioral overrides (stage assignments, autonomy mode, etc.) back to defaults:

```bash
wf doctor --reset-to-defaults
```

This preserves identity and build settings (name, repo_path, test_cmd, etc.) but strips stage_agents and other behavioral overrides.

### Direct config editing

All stage overrides can also be set by editing `config.yaml` directly. See `config.sample.yaml` in the repo root for all available settings with commented-out examples, including common recipes like using Claude for implementation or switching models.

---

## Authentication

Most CLI coding agents support both OAuth (interactive login) and API key authentication. When both are configured, agents differ on which takes precedence -- leading to silent auth failures or unexpected billing. Hashd detects the auth state per agent and builds a clean subprocess environment.

### Auth mode

Set with `wf project config set auth-mode <mode>`:

| Mode | Behavior |
|------|----------|
| **auto** (default) | Detect OAuth per-agent; prefer it when available |
| **oauth** | Always strip API keys for agents where key overrides OAuth |
| **api-key** | Never strip; always use API keys |

Most users should leave this at `auto`. It does the right thing: if you have a valid OAuth session, it uses OAuth. If you only have an API key, it uses the key.

### Per-agent auth behavior

Each agent handles the OAuth/API-key conflict differently:

| Agent | Key overrides OAuth? | What hashd does | OAuth credential file |
|-------|---------------------|-----------------|----------------------|
| **Claude** | Yes (`ANTHROPIC_API_KEY` wins) | Strips key when OAuth is valid | `~/.claude/.credentials.json` |
| **Gemini** | Yes (`GEMINI_API_KEY` wins) | Strips key when OAuth is valid | `~/.gemini/oauth_creds.json` or OS keychain |
| **Codex** | No (OAuth wins) | Nothing to strip | `~/.codex/auth.json` |
| **Kimi** | No (OAuth wins) | Nothing to strip | `~/.kimi/credentials/kimi-code.json` |
| **Qwen** | Mutually exclusive | Nothing to strip | `~/.qwen/oauth_creds.json` |
| **OpenCode** | N/A (API keys only) | Nothing to strip | N/A |

### Login and logout commands

| Agent | Login | Logout |
|-------|-------|--------|
| Claude | `claude` (opens browser) | N/A |
| Codex | `codex login` | `codex logout` |
| Gemini | Interactive `/auth` in TUI | Interactive `/auth signout` in TUI |
| Kimi | `kimi login` | `kimi logout` |
| Qwen | `qwen auth` | `qwen auth` (select different method) |
| OpenCode | N/A (set env vars) | N/A |

### Diagnostics

Run `wf doctor` to see the auth state for each installed agent:

```
Agent Authentication (mode: auto):

  claude:
    [OK] OAuth: valid (expires 2026-04-29)
    [INFO] API key: ANTHROPIC_API_KEY is set -- will be ignored (OAuth preferred in auto mode)
    [INFO] To use API key instead: wf project config set auth-mode api-key

  codex:
    [OK] OAuth: ChatGPT session active
    [WARN] API key: CODEX_API_KEY is set -- Codex ignores it when OAuth is active
    [INFO] To use API key instead: codex logout
```

### Common scenarios

**"I only have an API key (no OAuth)"**

It just works. `auto` mode detects no OAuth session and keeps the API key in the environment.

**"I use OAuth but also have an API key in my shell"**

`auto` mode detects the valid OAuth session and strips the API key for agents where the key would override OAuth (Claude, Gemini). For agents where OAuth already wins (Codex, Kimi), no action is needed.

**"I want to switch from OAuth to API key"**

```bash
wf project config set auth-mode api-key
```

This tells hashd to never strip API keys, regardless of OAuth state.

**"Codex/Kimi ignores my API key"**

These agents prefer OAuth when both are present. Hashd can't change this via environment manipulation. You need to clear the OAuth session:

```bash
# For Codex
codex logout

# For Kimi
kimi logout
```

**"Claude auth fails after I changed nothing"**

Your OAuth token may have expired. Check with `wf doctor` -- it shows the expiry date. Re-authenticate:

```bash
claude
```

This opens the browser login flow and refreshes the token.

### Environment variables

Hashd always strips `CLAUDECODE` from the subprocess environment for all agents. This prevents nested Claude Code session interference when spawning agents from within a Claude Code terminal.

The following API key env vars are stripped based on auth mode and OAuth detection:

| Env var | Stripped when | Agent |
|---------|-------------|-------|
| `ANTHROPIC_API_KEY` | OAuth valid + mode is `auto` or `oauth` | Claude |
| `GEMINI_API_KEY` | OAuth valid + mode is `auto` or `oauth` | Gemini |
| `GOOGLE_API_KEY` | OAuth valid + mode is `auto` or `oauth` | Gemini |

---

## Prompt Management

### How prompts work

All LLM prompts live in `prompts/*.md` as templates. They use `{variable}` placeholders for dynamic content and `{{ }}` for literal braces. HTML comments (`<!-- ... -->`) are stripped before sending to the LLM.

Prompts are loaded and rendered by `orchestrator/lib/prompts.py`:

```python
from orchestrator.lib.prompts import render_prompt
prompt = render_prompt('review', commit_title='Add auth', diff='...')
```

### Prompt-to-stage mapping

#### Implementation pipeline

| Prompt | Used by | Purpose |
|--------|---------|---------|
| `implement.md` | implement | Main implementation prompt for micro-commits |
| `implement_retry.md` | implement (resume) | Shorter prompt for session resume after review rejection |
| `implement_history.md` | implement | Conversation history section inserted on retries |
| `implement_review_context.md` | implement | Previous review output context |
| `implement_directives.md` | implement | Project/feature directives section |
| `concern_triage.md` | concern_triage | Triage pending review concerns against next micro-commit |

#### Review pipeline

| Prompt | Used by | Purpose |
|--------|---------|---------|
| `review.md` | review | Per-commit code review (JSON output) |
| `review_contextual.md` | review | Context-aware review with tool access |
| `review_retry.md` | review (resume) | Shorter prompt for re-reviews |
| `review_history.md` | review | Previous review cycles section |
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
