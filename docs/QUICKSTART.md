# Quickstart

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/codr1/hashd-code/main/install.sh | bash
```

### Requirements

- **Python 3.11+**
- **Node.js 18+** (required by Claude Code and Codex CLI)
- **git** (and **gh**/**bkt**/**glab** if using PR workflow with GitHub/Bitbucket/GitLab)
- **Claude Code** (`npm i -g @anthropic-ai/claude-code`) - planning, review, breakdown
- **Codex CLI** (`npm i -g @openai/codex`) - implementation

For development setup (working on hashd source), see [DEVELOPMENT.md](DEVELOPMENT.md).

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
# - Detect build system (Makefile, package.json, etc.)
# - Ask for project description, tech preferences
# - Configure test/build commands
# - Set it as the current project
```

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

## Quick Reference

| Task | CLI | TUI |
|------|-----|-----|
| Discover stories | `wf plan` | Plan screen (`p`), press `d` |
| Create story | `wf plan new 1` | Plan screen (`p`), press `1-9` |
| Approve story | `wf approve STORY-xxx` | Story Detail, press `A` |
| Run implementation | `wf run STORY-xxx` | Workstream Detail, press `G` |
| View progress | `wf show <ws>` | Select workstream `1-9` |
| Approve work | `wf approve <ws>` | Workstream Detail, press `a` |
| Reject work | `wf reject <ws> -f "..."` | Workstream Detail, press `r` |
| Merge | `wf merge <ws>` | Workstream Detail, press `m` |
