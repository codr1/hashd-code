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

Shows all 7 registered agents (Claude, Codex, Gemini, OpenCode, Kimi, Qwen, Copilot), their install status, supported shapes, and current stage assignments.

### Per-stage assignment

Each of the 18 workflow stages has a "shape" describing the kind of invocation it needs. Any agent can be assigned to any stage whose shape it supports.

```bash
# Assign gemini to the breakdown stage
hashd project config set stage.breakdown gemini

# Assign claude to review
hashd project config set stage.review claude
```

Validation prevents incompatible assignments (e.g., an agent without `review_resume` cannot serve the review resume stage).

Assignments are validated against the agent registry before they are saved.

Agents with `available` status (not yet verified with hashd) require `--force`:

```bash
hashd project config set stage.breakdown gemini --force
```

### Bulk assignment by role

```bash
# Set all non-implement stages (16 stages) to gemini
hashd project config set planner gemini --force

# Set implement + implement_resume (2 stages) to claude
hashd project config set coder claude
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
| Implementation | implement | claude | implement |
| Implementation | implement_resume | claude | implement_resume |
| Review | concern_triage | claude | print |
| Review | review | claude | review |
| Review | review_resume | claude | review_resume |
| Review | fix_generation | claude | json |
| Review | plan_add | claude | json |
| Completion | final_review | claude | review |
| Completion | pm_spec | claude | json |
| Completion | pm_docs | claude | edit |

### Agent shape support

Which agents can serve which stage shapes (`hashd agents` shows this live):

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
# Reset all stage overrides at once
hashd project config reset --all
```

Use `hashd project config diff` before resetting to inspect which project overrides will be cleared. `hashd project config show <key>` shows the effective value and Default/System/Project stack for one setting.

Nuclear option -- reset all behavioral overrides (stage assignments, autonomy mode, etc.) back to defaults:

```bash
hashd doctor --reset-to-defaults
```

This preserves identity and build settings (name, repo_path, test_cmd, etc.) but strips stage_agents and other behavioral overrides.

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
| **OpenCode** | Not supported | OpenCode is a multi-provider harness with its own auth store, and Anthropic prohibits Claude subscription OAuth in third-party tools |

Behavior at run time (registered-credential-wins):

- A registered credential is always injected for your runs, in both deployment modes, and overrides the server host's own environment.
- Single-user mode with nothing registered keeps today's behavior: the host's own agent auth.
- Team-server runs on an owned workstream **refuse to dispatch** when the owner has no live credential for the run's agents. The refusal names the exact command to fix it.
- When a run proves a credential dead (expired, revoked, or a token-rotation conflict), the server records it: the next dispatch fails instantly with the recovery steps instead of burning another run. Re-registering clears the state.

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

Overrides are by **prompt template name**, not stage name. Some stages compose multiple templates (e.g., implement uses 6), so overriding at the template level gives fine-grained control.

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
