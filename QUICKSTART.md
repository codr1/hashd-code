# Quickstart

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/codr1/hashd-code/main/install.sh | bash
```

The installer provides a Python 3.11+ runtime (bootstrapping [uv](https://github.com/astral-sh/uv) when your system has none, so PEP-668 "externally-managed-environment" boxes like fresh Arch and Homebrew Python just work), puts `hashd` on your PATH, fetches SHA-verified forge CLIs, and starts the local hashd services. It finishes by running `hashd doctor`.

> **Working on hashd itself?** This page is the user install. Building from
> source is a contributor path that needs access to the hashd source repository;
> its `DEVELOPMENT.md` covers the Go/Task/sqlc toolchain and `setup.sh`.
> (No link here on purpose: QUICKSTART ships in the public hashd-code release,
> while the source repo is private, so a relative link would 404 for readers.)

### Requirements

#### System Tools

The only OS-level prerequisite is **git**. Python is handled by the installer.

| Tool | Required | Purpose |
|------|----------|---------|
| git | yes | Version control, worktrees |
| [gh (GitHub CLI)](https://cli.github.com/) | for GitHub | PR workflow, repo operations; auto-installed by `install.sh`, link is the manual fallback |
| [bkt (Bitbucket CLI)](https://github.com/avivsinai/bitbucket-cli) | for Bitbucket | PR workflow, repo operations; auto-installed by `install.sh`, link is the manual fallback |
| [glab (GitLab CLI)](https://gitlab.com/gitlab-org/cli) | for GitLab | PR workflow, repo operations; auto-installed by `install.sh`, link is the manual fallback |
| [tea (Gitea CLI)](https://about.gitea.com/products/tea/) | for Gitea | PR workflow, repo operations; auto-installed by `install.sh`, link is the manual fallback |
| [delta](https://github.com/dandavison/delta) | bundled | TUI side-by-side, syntax-highlighted, word-level diffs; auto-installed by `install.sh` |

> **Node.js** is the prerequisite for the AI agent CLIs (they are npm
> packages), not for hashd itself. Install it alongside your agent --
> see [AI Coding Agents](#ai-coding-agents) below.

> **git-delta** and **gitleaks** do NOT need to be installed by
> hand. The curl installer above (wheel users) and `setup.sh`
> (source checkouts) both fetch pinned binaries into
> `~/.hashd/tools/bin/`. If a tool install fails (e.g. offline),
> `hashd` will retry on first use.

**Install git by platform:**

```bash
# --- Arch Linux ---
sudo pacman -S git

# --- macOS (Homebrew) ---
brew install git

# --- Debian/Ubuntu 24.04+ ---
sudo apt install git
```

The installer fetches pinned prebuilt forge CLIs for GitHub, GitLab,
Bitbucket, and Gitea. After install, authenticate the forge(s) you use:

```bash
gh auth login                         # GitHub
glab auth login                       # GitLab
bkt auth login --kind cloud --web     # Bitbucket OAuth
# Bitbucket API-token alternative:
bkt auth login --kind cloud --web-token
tea login add --name work --url https://git.example.com --token $TOKEN  # Gitea
```

#### AI Coding Agents

Hashd uses AI agents for planning, implementation, and review. Claude is the default agent for every stage; any other supported agent can be swapped in per stage. You only need Claude to get started.

The agent CLIs are npm packages, so they need **Node.js 20+** -- the agent's prerequisite, not hashd's. Install Node for your OS first:

```bash
# --- macOS (Homebrew) ---
brew install node

# --- Linux (any distro): nvm, no root ---
#   https://github.com/nvm-sh/nvm
#   nvm install 20 && nvm use 20
# Debian/Ubuntu alternative: NodeSource 20.x
#   curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - && sudo apt install nodejs
# Arch: sudo pacman -S nodejs npm
```

Then install an agent:

```bash
# Claude Code >= 2.1.220 (required - the default agent for every stage)
npm i -g @anthropic-ai/claude-code

# Codex CLI >= 0.145.0 (optional - swap in per stage if you want it)
npm i -g @openai/codex
```

Each agent needs either **OAuth login** or an **API key**. If both are configured, the agent CLI's own precedence rules apply. Hashd verifies authentication by asking the CLI for its status and preserves API-key env vars unless you explicitly force OAuth mode:

```bash
# Option A: OAuth (interactive login, no API key needed)
claude auth login
codex login

# Option B: API keys (add to your shell profile)
export ANTHROPIC_API_KEY="sk-ant-..."    # for Claude Code
export OPENAI_API_KEY="sk-..."           # for Codex CLI
```

Claude already handles every stage out of the box. To use a different agent:

```bash
# Scan installed agents and apply a default for all stages:
hashd agents --suggest

# Or use Codex for everything:
hashd config stages-use codex

# Or split roles per project:
hashd project config set planner claude
hashd project config set coder codex
```

Run `hashd agents` to see all seven supported agents and their install status. See [docs/AGENT_MANAGEMENT.md](docs/AGENT_MANAGEMENT.md) for agent switching, auth configuration, and per-project overrides.

Hashd bundles cbm for symbol-aware code inspection. See [docs/CODE_TOOLS.md](docs/CODE_TOOLS.md) for the `hashd code` command reference and troubleshooting.
For source checkouts, `setup.sh` fetches the pinned `codebase-memory-mcp`
binary and smoke-checks it with `codebase-memory-mcp --version`; setup
fails immediately if the binary cannot be fetched or executed.

#### Optional Tools

```bash
# Desktop notifications (Linux only, freedesktop-compliant)
# Arch: sudo pacman -S libnotify
# Debian/Ubuntu: sudo apt install libnotify-bin
```

### Verify Setup

```bash
hashd doctor
```

This checks all required tools, API connectivity, and configuration.

## Project Setup

```bash
# Register an existing local repo with the wizard
hashd project add /path/to/your/repo

# Agent / script flow: investigate first, then execute from stored defaults
hashd project add /path/to/your/repo --no-interview --suggest
hashd project add /path/to/your/repo --no-interview

# Or clone and register in one step (works with any git host)
hashd project add /path/to/repo --clone https://github.com/user/repo
hashd project add /path/to/repo --clone https://gitlab.com/user/repo
hashd project add /path/to/repo --clone https://bitbucket.org/team/repo

# Multi-repo/container onboarding controls
hashd project add /path/to/platform --primary backend --active frontend
hashd project add /path/to/platform --all-active --repo-skip-test docs --repo-skip-build docs

# The investigate pass prints canonical settings output such as:
#   Running project add with the following settings:
#     --name demo
#     --description "Demo trading platform"  # AI-inferred
#     --primary backend
#     --active frontend
#     --git-name "Alice"
#     --git-email "alice@example.com"
#
# It also stores those defaults in the project-add cache. The second
# command reuses them, applies any explicit flag overrides, prints the
# same canonical settings block again, and then executes project add.
#
# The wizard path still:
# - Auto-detects forge from git remote (GitHub, Bitbucket, GitLab, Gitea)
# - Auto-detects build systems (Makefile, package.json, Taskfile, etc.)
# - Prefills description, tech preferences, and repo settings from
#   stored defaults or fresh AI investigation when requested
# - Sets the new project as the current project on success
```

### Projects with Code Generation

If your project uses code generation (sqlc, templ, protobuf, OpenAPI, etc.), wire generation as a dependency in your build system so it runs before tests:

```yaml
# Taskfile example
tasks:
  generate:
    cmds:
      - sqlc generate
      - templ generate
  test:
    deps: [generate]
    cmds:
      - go test ./...
```

Then enter `task test` when prompted during project setup.

## Option A: CLI Workflow

```bash
# Create requirements file in your repo (optional but recommended).
# Before registration, edit <your-repo>/REQS.md directly.
# After registration, use the server-backed artifact editor:
hashd project reqs edit

# Inspect the configured requirements artifact
hashd project reqs show

# Discover stories from REQS.md
hashd plan

# View suggestions
hashd plan list

# Quick mode (skip REQS.md)
hashd plan story "add user authentication"

# Review and approve story
hashd show STORY-0001
hashd approve STORY-0001

# Start implementation
hashd run STORY-0001

# Monitor progress
hashd show <workstream-id>
hashd log <workstream-id>

# Handle gates as needed
hashd approve <workstream-id>
hashd reject <workstream-id> -f "feedback"
hashd answer list

# Complete
hashd merge <workstream-id>
```

## Option B: TUI Workflow (hashd watch)

`hashd watch` is a viewer: it connects to running hashd services and never
starts or restarts them. The installer brings the local stack up for you; if
the services are ever down (say, after a reboot), `hashd watch` tells you
exactly what is down and the fix is one command:

```bash
hashd restart        # brings up all local hashd services
```

```bash
# Launch TUI
hashd watch

# Dashboard (home screen):
#   1-9           - Select workstream (opens detail view)
#   a-i           - Select story (opens story detail)
#   p             - Open plan screen
#   m             - Change autonomy mode
#   /             - Command palette
#   ?             - Help (context-aware)
#   q             - Quit

# Workstream Detail:
#   G             - Run workstream
#   a             - Approve (human review gate)
#   r             - Reject with feedback
#   R             - Reset workstream
#   d             - View diff
#   l             - View log
#   v             - View review
#   t             - View timeline
#   P             - Create PR/MR
#   m             - Merge
#   C             - Open chat
#   Esc           - Back to dashboard

# Story Detail:
#   A             - Approve story (draft -> accepted)
#   E             - AI edit story
#   G             - Create workstream and run
#   C             - Close/abandon story
#   Esc           - Back to dashboard

# Plan Screen:
#   d             - Discover stories from REQS.md
#   1-9           - Create story from suggestion
#   s             - New story
#   b             - New bug
#   Esc           - Back to dashboard
```

## Autonomy Modes

Hashd supports three autonomy modes, configurable per-project:

| Mode | Behavior |
|------|----------|
| **supervised** | Human approves at each gate |
| **gatekeeper** (default) | Auto-continue if AI confidence >= 90%, human approves at merge |
| **autonomous** | Auto-continue commits + auto-merge if thresholds met |

Set during project setup or change anytime:

```bash
hashd project config set autonomy gatekeeper
hashd project config show autonomy
hashd project config diff
```

Override per-run: `hashd run --supervised`, `hashd run --gatekeeper`, or `hashd run --autonomous`

## Telegram Bot

Manage your full workflow from mobile:

```bash
# 1. Create a bot via @BotFather on Telegram, copy the token
hashd telegram bot <YOUR_TOKEN>

# 2. Get your user ID from @userinfobot, then authorize
hashd telegram allow <YOUR_USER_ID>
hashd telegram chat-id <YOUR_USER_ID>

# 3. Start the bot
hashd telegram start
```

The bot also auto-starts when you run `hashd run`. Send `/` for the button menu.

## Shell Completion

```bash
# Bash (managed automatically by setup.sh and dist/install.sh)
source <(hashd completion bash)

# Zsh (managed automatically by setup.sh for source installs)
autoload -Uz compinit && compinit
source <(hashd completion zsh)

# Fish
hashd completion fish > ~/.config/fish/completions/hashd.fish
```

## Multi-Project Setup

```bash
# Register another project
hashd project add /path/to/another/repo

# List projects (* = current)
hashd project list

# Show, switch, or clear the current project
hashd project use
hashd project use <project-name>
hashd project use --clear

# Or use --project flag
hashd plan list --project <project-name>

# Inspect configured project artifacts
hashd project reqs show
hashd project spec show
```

## Going Remote: Connect to a Server

Everything above sets up **local mode** -- client and server on your machine, one implicit user, no auth. If you're a solo developer on your own box, you're done; skip this section.

To drive a `hashd-server` running on another machine (a box in the closet, or a shared team server), pair a client to it with a single token. The token carries the server's TLS certificate fingerprint, so there's no separate certificate step.

```bash
# --- On the server host: make it reachable (once) ---
hashd auth create --description "server host"        # mint an owner token (copy it)
hashd server set https://<lan-ip>:1337 --token <owner-token>
hashd restart server                                 # comes up on the LAN over TLS

# --- Add a teammate (host-local, on the server host) ---
hashd admin user add alice@example.com --name "Alice"   # prints Alice's token to relay

# --- On the client machine: pair and use ---
hashd server set https://<lan-ip>:1337 --token <token>
hashd status             # shows the server, your identity, and health
hashd list -p <project>
hashd watch -p <project>

# Return to local behavior:
hashd server unset
```

Full trust model, team mode, the password-login alternative, and troubleshooting: **[docs/REMOTE.md](docs/REMOTE.md)**.

## Updating

```bash
# Re-run the installer to get the latest version
curl -fsSL https://raw.githubusercontent.com/codr1/hashd-code/main/install.sh | bash
```

## Quick Reference

| Task | CLI | TUI |
|------|-----|-----|
| Discover stories | `hashd plan` | Plan screen (`p`), press `d` |
| Create story | `hashd plan story "title"` | Plan screen (`p`), press `1-9` |
| Quick story | `hashd plan story "title"` | Plan screen (`p`), press `s` |
| Quick bug | `hashd plan bug "title"` | Plan screen (`p`), press `b` |
| Approve story | `hashd approve STORY-xxx` | Story Detail, press `A` |
| View REQS/SPEC | `hashd project reqs show`, `hashd project spec show` | - |
| Run implementation | `hashd run STORY-xxx` | Workstream Detail, press `G` |
| View progress | `hashd show <ws>` | Select workstream `1-9` |
| Approve work | `hashd approve <ws>` | Workstream Detail, press `a` |
| Reject work | `hashd reject <ws> -f "..."` | Workstream Detail, press `r` |
| Merge | `hashd merge <ws>` | Workstream Detail, press `m` |
| Chat with AI | `hashd chat` | Any screen, press `C` |
| Search | `hashd search "query"` | Dashboard, press `/` |
| Diagnose issues | `hashd doctor` | -- |

## Further Reading

Learn the system:

- **[docs/how-hashd-works.md](docs/how-hashd-works.md)** -- the mental model: entities, gates, the event log, and provenance
- **[docs/walkthrough.md](docs/walkthrough.md)** -- one feature start-to-finish, spec to merged commit
- **[docs/glossary.md](docs/glossary.md)** -- canonical term definitions
- **[docs/watch.md](docs/watch.md)** -- the `hashd watch` TUI: the three views and the keys that move between them
- **[docs/provenance.md](docs/provenance.md)** -- the audit/lineage story (`hashd lineage`, SLSA/in-toto export, hash-chain verify)

Reference:

- **[WF.md](WF.md)** -- Full command reference and lifecycle docs
- **[RELEASE_NOTES.md](docs/RELEASE_NOTES.md)** -- Version-by-version release notes
- **[docs/AGENT_MANAGEMENT.md](docs/AGENT_MANAGEMENT.md)** -- Agent switching, auth, per-project overrides
- **[docs/REMOTE.md](docs/REMOTE.md)** -- Remote and team servers: TLS trust, accounts, tokens, pairing
- **[TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** -- Common issues and fixes
- **[CONNECTORS.md](docs/CONNECTORS.md)** -- External integrations (GitHub Issues, Figma)

