# hashd

Human-Agent Synchronized Handoff Development -- an orchestration system that coordinates AI coding agents to implement, review, and ship code autonomously.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/codr1/hashd-code/main/install.sh | sh
```

### Requirements

- Python 3.11+
- git
- [GitHub CLI](https://cli.github.com/) (`gh`)
- [Claude Code](https://claude.ai/download) (for planning, review, breakdown)
- [Codex CLI](https://github.com/openai/codex) (for implementation)
- [delta](https://github.com/dandavison/delta) (optional, for diff display)

## Quick Start

```bash
# Register your project
wf project add /path/to/your/repo

# Plan stories from requirements
wf plan

# Run the AI pipeline
wf run STORY-0001 --loop

# Monitor with the TUI
wf watch
```

## Update

```bash
curl -fsSL https://raw.githubusercontent.com/codr1/hashd-code/main/install.sh | sh
```

The installer automatically replaces the previous version.

## License

(c) Coderica Inc. All rights reserved.
