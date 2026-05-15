# Quickstart

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/codr1/hashd-code/main/install.sh | bash
```

The installer handles Python virtual environment setup and puts `wf` on your PATH.

### Requirements

#### System Tools

| Tool | Required | Purpose |
|------|----------|---------|
| Python 3.11+ | yes | Runtime |
| Node.js 20+ | yes | Required by npm-installed agent CLIs |
| git | yes | Version control, worktrees |
| [gh (GitHub CLI)](https://cli.github.com/) | for GitHub | PR workflow, repo operations |
| [bkt (Bitbucket CLI)](https://bitbucket.org/) | for Bitbucket | PR workflow, repo operations |
| [glab (GitLab CLI)](https://gitlab.com/gitlab-org/cli) | for GitLab | PR workflow, repo operations |
| [delta](https://github.com/dandavison/delta) | yes | Syntax-highlighted diffs |

> **gitleaks** is used for secrets scanning at project setup but
> does NOT need to be installed by hand. The curl installer above
> (wheel users) and `setup.sh` (source checkouts) both fetch a
> pinned gitleaks binary into `~/.hashd/tools/bin/`. If a tool
> install fails (e.g. offline), `wf` will retry on first use.

**Install by platform:**

```bash
# --- Arch Linux ---
sudo pacman -S git github-cli git-delta nodejs npm python

# --- macOS (Homebrew) ---
brew install git gh git-delta node python@3.11

# --- Debian/Ubuntu 24.04+ ---
sudo apt install git gh git-delta python3
# Install Node.js 20+ explicitly. Preferred: nvm
#   https://github.com/nvm-sh/nvm
#   nvm install 20
#   nvm use 20
# Alternative: NodeSource 20.x repo
#   curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
#   sudo apt install nodejs
# Older Ubuntu: delta is not in apt, install from GitHub releases:
#   https://github.com/dandavison/delta/releases

# --- Others ---
# gh: https://cli.github.com/
# delta: https://github.com/dandavison/delta#installation
```

After installing the appropriate forge CLI, authenticate:

```bash
gh auth login      # GitHub
glab auth login    # GitLab
bkt auth login     # Bitbucket
```

#### AI Coding Agents

Hashd uses AI agents for planning, implementation, and review. The default setup uses Claude for planning/review and Codex for implementation. You only need one agent to get started - Claude can handle all stages if you prefer a single-agent setup.

```bash
# Claude Code >= 2.1.137 (planning, review, breakdown - and optionally implementation)
npm i -g @anthropic-ai/claude-code

# Codex CLI >= 0.130.0 (implementation - optional if using Claude for everything)
npm i -g @openai/codex
```

Each agent needs either **OAuth login** or an **API key**. If both are configured, hashd prefers OAuth:

```bash
# Option A: OAuth (interactive login, no API key needed)
claude auth login
codex login

# Option B: API keys (add to your shell profile)
export ANTHROPIC_API_KEY="sk-ant-..."    # for Claude Code
export OPENAI_API_KEY="sk-..."           # for Codex CLI
```

To use Claude for all stages (no Codex needed):

```bash
wf project config set coder claude
```

Run `wf agents` to see all seven supported agents and their install status. See [docs/AGENT_MANAGEMENT.md](AGENT_MANAGEMENT.md) for agent switching, auth configuration, and per-project overrides.

#### Optional Tools

```bash
# Desktop notifications (Linux only, freedesktop-compliant)
# Arch: sudo pacman -S libnotify
# Debian/Ubuntu: sudo apt install libnotify-bin
```

### Verify Setup

```bash
wf doctor
```

This checks all required tools, API connectivity, and configuration.

## Project Setup

```bash
# Register an existing local repo with the wizard
wf project add /path/to/your/repo

# Agent / script flow: investigate first, then execute from stored defaults
wf project add /path/to/your/repo --no-interview --suggest
wf project add /path/to/your/repo --no-interview

# Or clone and register in one step (works with any git host)
wf project add /path/to/repo --clone https://github.com/user/repo
wf project add /path/to/repo --clone https://gitlab.com/user/repo
wf project add /path/to/repo --clone https://bitbucket.org/team/repo

# Multi-repo/container onboarding controls
wf project add /path/to/platform --primary backend --active frontend
wf project add /path/to/platform --all-active --repo-skip-test docs --repo-skip-build docs

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
# - Auto-detects forge from git remote (GitHub, Bitbucket, GitLab)
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
# Create requirements file in your repo (optional but recommended)
# Edit <your-repo>/REQS.md with your requirements

# Discover stories from REQS.md
wf plan

# View suggestions
wf plan list

# Quick mode (skip REQS.md)
wf plan story "add user authentication"

# Review and approve story
wf show STORY-0001
wf approve STORY-0001

# Start implementation
wf run STORY-0001

# Monitor progress
wf show <workstream-id>
wf log <workstream-id>

# Handle gates as needed
wf approve <workstream-id>
wf reject <workstream-id> "feedback"
wf answer list

# Complete
wf merge <workstream-id>
```

## Option B: TUI Workflow (wf watch)

```bash
# Launch TUI
wf watch

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
wf project config set autonomy gatekeeper
```

Override per-run: `wf run --supervised`, `wf run --gatekeeper`, or `wf run --autonomous`

## Telegram Bot

Manage your full workflow from mobile:

```bash
# 1. Create a bot via @BotFather on Telegram, copy the token
wf telegram bot <YOUR_TOKEN>

# 2. Get your user ID from @userinfobot, then authorize
wf telegram allow <YOUR_USER_ID>
wf telegram chat-id <YOUR_USER_ID>

# 3. Start the bot
wf telegram start
```

The bot also auto-starts when you run `wf run` or `wf watch`. Send `/` for the button menu.

## Shell Completion

```bash
# Bash (managed automatically by setup.sh and dist/install.sh)
source <(wf completion bash)

# Zsh
wf completion zsh >> ~/.zshrc

# Fish
wf completion fish > ~/.config/fish/completions/wf.fish
```

## Multi-Project Setup

```bash
# Register another project
wf project add /path/to/another/repo

# List projects (* = current)
wf project list

# Show, switch, or clear the current project
wf project use
wf project use <project-name>
wf project use --clear

# Or use --project flag
wf plan list --project <project-name>
```

## Updating

```bash
# Re-run the installer to get the latest version
curl -fsSL https://raw.githubusercontent.com/codr1/hashd-code/main/install.sh | bash
```

## Quick Reference

| Task | CLI | TUI |
|------|-----|-----|
| Discover stories | `wf plan` | Plan screen (`p`), press `d` |
| Create story | `wf plan story "title"` | Plan screen (`p`), press `1-9` |
| Quick story | `wf plan story "title"` | Plan screen (`p`), press `s` |
| Quick bug | `wf plan bug "title"` | Plan screen (`p`), press `b` |
| Approve story | `wf approve STORY-xxx` | Story Detail, press `A` |
| Run implementation | `wf run STORY-xxx` | Workstream Detail, press `G` |
| View progress | `wf show <ws>` | Select workstream `1-9` |
| Approve work | `wf approve <ws>` | Workstream Detail, press `a` |
| Reject work | `wf reject <ws> "..."` | Workstream Detail, press `r` |
| Merge | `wf merge <ws>` | Workstream Detail, press `m` |
| Chat with AI | `wf chat` | Any screen, press `C` |
| Search | `wf search "query"` | Dashboard, press `/` |
| Diagnose issues | `wf doctor` | -- |

## Further Reading

- **[WF.md](WF.md)** -- Full command reference and lifecycle docs
- **[docs/AGENT_MANAGEMENT.md](AGENT_MANAGEMENT.md)** -- Agent switching, auth, per-project overrides
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** -- Common issues and fixes
- **[CONNECTORS.md](CONNECTORS.md)** -- External integrations (GitHub Issues, Figma)

