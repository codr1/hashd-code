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
| `implement_oscillation_check.md` | implement | Oscillation detection for FIX-004+ commits |

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
