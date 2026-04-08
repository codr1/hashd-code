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
| Node.js 18+ | yes | Required by Claude Code and Codex CLI |
| git | yes | Version control, worktrees |
| [gh (GitHub CLI)](https://cli.github.com/) | for GitHub | PR workflow, repo operations |
| [bkt (Bitbucket CLI)](https://bitbucket.org/) | for Bitbucket | PR workflow, repo operations |
| [glab (GitLab CLI)](https://gitlab.com/gitlab-org/cli) | for GitLab | PR workflow, repo operations |
| [delta](https://github.com/dandavison/delta) | yes | Syntax-highlighted diffs |

**Install by platform:**

```bash
# --- Arch Linux ---
sudo pacman -S git github-cli git-delta nodejs npm python

# --- macOS (Homebrew) ---
brew install git gh git-delta node python@3.11

# --- Debian/Ubuntu 24.04+ ---
sudo apt install git gh git-delta nodejs npm python3
# Older Ubuntu: delta is not in apt, install from GitHub releases:
#   https://github.com/dandavison/delta/releases

# --- Others ---
# gh: https://cli.github.com/
# delta: https://github.com/dandavison/delta#installation
```

After installing gh, authenticate:

```bash
gh auth login
```

#### AI Coding Agents

Hashd uses AI agents for planning, implementation, and review. The default setup uses Claude for planning/review and Codex for implementation:

```bash
# Claude Code >= 2.1 (planning, review, breakdown)
npm i -g @anthropic-ai/claude-code

# Codex CLI >= 0.98 (implementation)
npm i -g @openai/codex
```

Both require API keys:

```bash
# Anthropic (for Claude Code)
export ANTHROPIC_API_KEY="sk-ant-..."

# OpenAI (for Codex CLI)
export OPENAI_API_KEY="sk-..."
```

Add these to your shell profile (`~/.bashrc`, `~/.zshrc`, etc.) so they persist.

Run `wf agents` to see all six supported agents and their install status. See [AGENT_MANAGEMENT.md](AGENT_MANAGEMENT.md) for switching agents and per-project overrides.

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
# Register an existing local repo
wf project add /path/to/your/repo

# Or clone and register in one step (works with any git host)
wf project add /path/to/repo --clone https://github.com/user/repo
wf project add /path/to/repo --clone https://gitlab.com/user/repo
wf project add /path/to/repo --clone https://bitbucket.org/team/repo

# This will:
# - Auto-detect forge from git remote (GitHub, Bitbucket, GitLab)
# - Auto-detect build system (Makefile, package.json, Taskfile, etc.)
# - Ask for project description, tech preferences
# - Configure test/build commands
# - Set it as the current project
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

# Create story from suggestion #1
wf plan new 1

# Or quick mode (skip REQS.md)
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
wf reject <workstream-id> -f "feedback"
wf clarify list

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
# Bash
wf --completion bash >> ~/.bashrc

# Zsh
wf --completion zsh >> ~/.zshrc

# Fish
wf --completion fish > ~/.config/fish/completions/wf.fish
```

## Multi-Project Setup

```bash
# Register another project
wf project add /path/to/another/repo

# List projects (* = current)
wf project list

# Switch projects
wf project use <project-name>

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
| Create story | `wf plan new 1` | Plan screen (`p`), press `1-9` |
| Quick story | `wf plan story "title"` | Plan screen (`p`), press `s` |
| Quick bug | `wf plan bug "title"` | Plan screen (`p`), press `b` |
| Approve story | `wf approve STORY-xxx` | Story Detail, press `A` |
| Run implementation | `wf run STORY-xxx` | Workstream Detail, press `G` |
| View progress | `wf show <ws>` | Select workstream `1-9` |
| Approve work | `wf approve <ws>` | Workstream Detail, press `a` |
| Reject work | `wf reject <ws> -f "..."` | Workstream Detail, press `r` |
| Merge | `wf merge <ws>` | Workstream Detail, press `m` |
| Chat with AI | `wf chat` | Any screen, press `C` |
| Search | `wf search "query"` | Dashboard, press `/` |
| Diagnose issues | `wf doctor` | -- |

## Further Reading

- **[WF.md](WF.md)** -- Full command reference and lifecycle docs
- **[AGENT_MANAGEMENT.md](AGENT_MANAGEMENT.md)** -- Agent switching, auth, per-project overrides
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** -- Common issues and fixes
- **[CONNECTORS.md](CONNECTORS.md)** -- External integrations (GitHub Issues, Figma)

