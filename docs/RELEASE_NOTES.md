# Release Notes

Release notes follow the same markdown structure used by GitHub releases:
version heading, date, categorized "What's Changed" bullets, and a full
changelog compare link.

## v0.10.0 - 2026-11-25

v0.10.0 reworks replanning: a replan returns the story to planning, and the requirements revision of an implementing story is removed. It closes stories by stopping their work first, adds a lint stage, shared agent API keys (Amazon Bedrock included), repository MCP servers, runner access choices, dollar costs and price overrides, and prompt editing in Settings. hashd-server now requires HTTP/2 over TLS. It also improves remote-runner reliability, conflict recovery and test evidence, adds requirements-storage choices and backup creation, and makes story decisions and alerts clearer across the CLI, TUI and Web.

### What's Changed

- **A replan returns the story to planning; the requirements revision is gone.** `hashd replan` (full, or `--from-commit`) moves the story back to draft with its lane held. From an implementing story it clears the problem text and non-goals, so the criteria are the binding text. `-f` is now the planner's instruction for redrafting the criteria, not text for the breakdown. After `hashd approve`, the lane's next run breaks the story down again: new micro-commits are numbered past every earlier one, and the breakdown plans what the criteria still need; on a lane that already has code, that includes removing code no criterion needs. A partial replan may plan nothing; the lane then goes on to its final review. A full replan that plans nothing stops with "no changes to make", and in autonomous mode closes the story as no changes needed. A full replan starts over on the base branch's current head, not the old fork point. A replan of either form clears the lane's operator rulings and directives, and a full replan retires the lane's pending questions. Replan is also offered at an idle open or approved PR and on a finished lane (ready to merge, or final review with concerns); `hashd run` is no longer offered at an open or approved PR whose final review is current, which names `hashd merge` instead. **Removed:** the requirements edit of an implementing story. That covers `hashd approve --start-over` and `--keep-code`; `hashd story edit` on an implementing story, which is refused and names the replan; the TUI's "revise" on `E` and its `x` decline key; the Web Revise Story card, start-over and keep-and-rework approvals and decline control; and the Telegram bot's buttons for them (#3604, #3733, #3735, #3749, #3750, #3752).

- **Replan and reset close the lane's PR.** `hashd replan` and `hashd reset` close an open PR on the forge with a note and remove it from the lane before they change any code; the lane opens a new PR when it reaches the PR step again. At a PR the forge closed, `hashd show` offers replan and reset beside Rework, Close the story and Abandon (#3719, #3728).

- **Plan and code verbs, renamed and moved.** `hashd story add-commit` and `hashd story edit-commit` replace `hashd workstream add-commit` and `edit-commit`, with no alias. `hashd replan --from-commit` replaces `--from`. `hashd reset --checkpoint` is removed: `hashd reject --reset` retries the micro-commit in progress, at a review gate as before and now also on a lane stopped between attempts, keeping every landed micro-commit. `hashd reset -f "<guidance>"` adds the guidance to the lane's standing directives. When one of these verbs cannot apply, its refusal says where the lane stands and names the command that does: before the breakdown has run, at the PR, under a pause, merged or closed. The final review is told which micro-commits a person added (#3713).

- **Closing a story stops everything working on it first.** `hashd close` moves the story to a new `abandoning` state, kills every stage working on it, discards its unfinished work, and only then archives it. Where systemd user scopes are available, each agent launch runs in its own scope, so commands the agent left running are killed with it. A step that fails leaves the story abandoning, and running the close again finishes it. A rebase that cannot be undone is refused unless you confirm with `-y`, and a checkout the teardown cannot remove now fails the close instead of archiving with a warning (#3748, #3753).

- **`hashd cancel <story>` stops a story's run, merge or conflict resolution.** It asks the running work to stop; the run ends as cancelled when its running stage stops, and the checkout and branch stay as they are (#3714).

- **Lint runs as its own check before the tests.** An optional `lint_cmd` (per project, or per repo on a multi-repo project) runs before the tests in the commit cycle, at the merge gate and in the verification after a rebase. A lint failure stops the tests, goes back to the implementer with the lint output, and is reported as lint's; lint has no baseline. Set it with `hashd project config set lint_cmd`, `hashd project repo edit --lint-cmd`, `hashd project add --repo-lint-cmd`, or the Web project form; `hashd project show`, `hashd doctor` and the merge-gate settings show it, and `hashd list` shows the sub-stage a running lane is in (#3741).

- **A breakdown answer that fails its check is rejected and asked for once more.** An entry with no id or title, an id outside the lane's form, a repeated id, a number below the lane's next one, or an empty answer to a first breakdown used to be skipped or fail the run at once. Now the whole answer is rejected and the agent is asked once more, told exactly which entries were wrong; a second bad answer fails as before, naming each rejected entry. A repeated id fails with a next step to run the lane again. The merge gate's FIX generation gets the same one re-ask (#3598, #3762).

- **The merge lock holds less work.** In the approved-PR merge queue, a branch that needs no rebase reuses a recorded pass for exactly its content, and a branch that recorded clean rebases alone made current since its full pass is checked with a build instead of the full test. A merge or archive that holds the lock is admitted to its runner at once instead of waiting for a free slot. In repo mode, for a lane that merges through a pull request, SPEC and REQS are written as a commit on the lane before the full test and land with the code; archive SPEC updates elsewhere are prepared outside the lock. Every archive waits for the lock in the same arrival order as merges, with no expiry (#3603, #3663, #3703, #3708, #3716, #3752).

- **Pausing a story in the merge queue withdraws it.** Pausing a story that is waiting for the merge lock, or inside it before its forge merge starts, frees the lock for the next story; unpausing puts it at the back of the queue. A merge already started on the forge finishes (#3583).

- **Shared API keys for agents.** Administrators can register an agent API key at project or server scope with `hashd agents login <agent> --scope project|server` (listed with `hashd agents --scope`, removed with `hashd agents logout --scope`). Runs reach the provider through hashd's proxy, so the key never reaches a run. Claude and Codex support it, with an optional `--base-url` for a custom upstream. Which key a project's runs use is the **Agents run on** setting (`agents.credential_source`): User's account, Project key or Team key, shown in Web Project > Agents and TUI Settings. A shared key is tested when it is stored and from Web Settings > Server > Team keys, and every project member can see whether it works. A shared Claude key can be an Amazon Bedrock API key or an IAM role the server assumes (`--options provider=bedrock --options region=<region>`, plus `role_arn` and an optional `external_id`); the Bedrock paths have not been run against a live AWS account. `hashd agents login --options key=value` carries settings only one agent has: **Gemini's Google Cloud project moves from `--project` to `--options google_cloud_project=<id>`**. The TUI sign-in form now follows the server's list of methods and settings, and the provider account a sign-in shows is visible only to its owner (#3668, #3707, #3720, #3742, #3744, #3751, #3760).

- **Sign in and out per runner.** Fleet signs an agent out on a selected runner from Web, the TUI (`x`, beside `s` for sign-in) and `hashd agents logout <agent> --runner <runner>`. Every agent's sign-in button sits in the same place, and an agent with several methods opens a menu of them. Removing a registered credential in Settings also runs the agent's own sign-out on the server machine. Fleet shows its machines at once and fills in sign-ins right after (#3569, #3609, #3628, #3695).

- **Choose and change a runner's access.** `hashd runner add` takes `--access anyone|private`, `--project` (repeatable) or `--owner`; with none, the runner is private to you. `hashd runner access` and the TUI and Web Network settings change it later. Work already placed on the runner (queued, running or paused) keeps its placement and finishes there; only new placements follow the new access (#3590, #3756).

- **Moving a story cleans up the runner it leaves.** `hashd story runner set`, the TUI move and the Web move remove the story's checkout, branch and stage files from the runner it leaves; if that runner cannot be reached, the move still stands and warns, naming what was left and how to remove it. A move that would discard a rebase resolution only that runner holds asks for confirmation first (`-y` on the CLI) (#3711, #3758).

- **Repository MCP servers reach every agent stage.** Servers declared in the repository's `.mcp.json`, read at the story's pinned base commit, are delivered to every agent hashd configures MCP for, alongside hashd's own servers, through every retry and resume. It is on by default; turn it off with `mcp.project_servers` at system or project scope. A name clash or a definition the agent cannot carry refuses the launch, naming the server. Definitions are delivered as written, with variable references unexpanded; stdio servers run under the agent's own environment, which may include its sign-in. Each run records the MCP servers it delivered. hashd no longer passes Claude `--strict-mcp-config` when it injects servers, so Claude's own MCP discovery stays on (#3622, #3759).

- **Dollar costs everywhere, and operator prices.** `hashd cost` (and its project, story and workstream forms) prints a Cost line and a per-row COST column, and `hashd show --stats` shows the story's and each agent's cost. Administrators can set `pricing.overrides` (`hashd config set pricing.overrides '<JSON array>'`) to price calls by provider, model and optional region; overrides apply to calls captured after they are set. Bedrock calls are priced from AWS's regional price list, then LiteLLM. Reports groups "Where the time went" by role, and moves pricing gaps into a collapsed Pricing details section at the bottom of the Cost view, on Web and TUI. A story's cost and agent stats now include every call of the story, and calls are kept when a workstream row is deleted (#3694, #3698, #3701, #3705, #3721, #3745, #3747, #3757, #3764).

- **Edit prompt overrides from Settings.** Web Settings > Prompts and the TUI Settings Prompts screen list a project's prompts, mark the overridden ones, and view, edit, diff against the shipped default and reset them. `GET /prompts` takes `project` and no longer accepts `prompts_dir` or `overrides_dir` (#3673, #3684, #3704).

- **If you override prompts, compare them with the new defaults.** More of the prompts' wording moved from hashd's code into the shipped templates: the final review's sections, the build and test summaries in reviews, operator clarifications and rulings, descoped criteria and deletion-risk lines. Variables that used to carry text written by hashd now carry data the templates word, so an override written for v0.9.33 can miss sections or fail to render. `include_planner_redraft.md` is now `include_answer_redraft.md`; an override of the old name is no longer read. The final review also has a new rebase round, with its own template `final_review_rebase.md`: after an approval, a branch whose only new commits replay the approved ones is reviewed as a comparison of those commits with their replays, not as a whole new branch (#3655, #3658, #3662, #3664, #3666, #3706, #3710, #3743, #3762).

- **What agents are given.** Every supported agent can read the files hashd delivers to its stage without a permission prompt, and a read the agent refuses is reported as such. Agents are told how to read a test run's complete console through hashd. The breakdown is asked to slice commits by behaviour and to reuse existing code, and the implementer to look for helpers to reuse (#3605, #3606, #3665, #3740).

- **Failing tests are named from adapter reports and the failing-test reader.** hashd no longer parses test console output to name failures. A build adapter's report names them first; where no adapter names one, the failing-test reader does. A failed run with no named failure is never taken as a pass (#3761).

- **Usage limits end the run after one immediate retry.** An agent call that reaches its account usage limit is retried once at once; a second failure ends the run with its cause and a manual retry. The delayed retry at the quota reset time, its countdown and its reset-time estimates are removed. **On upgrade** from a build with quota retries waiting, end those workflow executions during the drain, before the worker is replaced (#3685).

- **hashd-server requires HTTP/2 over TLS, and local connections use HTTPS.** Loopback connections now use HTTPS with hashd's own certificate authority; existing installs keep their credentials, saved trust and connection records, with nothing to edit. hashd-server answers only HTTP/2 over TLS: an HTTP/1.1 client over TLS gets one refusal naming the requirement, and plaintext and unencrypted HTTP/2 are not served. **On upgrade,** a reverse proxy or load balancer in front of hashd-server must speak HTTP/2 to it (#3618, #3624, #3626).

- **Health probes.** `GET /livez` and `GET /readyz` answer without a credential; `/readyz` checks the databases, the workflow engine and the ops root, and the container's HEALTHCHECK uses it (#3746).

- **Test evidence moves out of the database.** Test inventories, console output and baseline captures are kept in files beside each project database and removed when their story finishes; large merge-gate evidence leaves event rows, and event lists stay small. Backups and upgrade snapshots include the files. **On upgrade** the migration converts existing evidence and compacts the database: allow several minutes offline on a large project database, and free disk space for the compaction (#3627, #3635, #3653, #3681).

- **A story shows its deferred work.** `hashd show`, the TUI story detail and the Web story page list the work the planner deferred from the story, with each item's id, title, summary and status, apart from the acceptance criteria and Non-Goals. An ordinary story edit keeps the list current (#3754).

- **Rescope is removed; a draft's descope returns its prose to REQS at once.** `hashd story rescope-ac`, the TUI rescope key, the Web restore control and the chat action are gone; a descoped criterion stays descoped. Descoping a criterion of a draft story returns its requirement text to REQS immediately (#3738).

- **Azure Boards lifecycle rules.** `azure.lifecycle.<event>` takes explicit `to` and `from` state lists and per-work-item-type rules (`types`). Moves only go forward, including within one state category. A card in a state the mapping does not account for, such as one a person moved by hand, is left where it is and the delivery is refused, naming the card and how to proceed. A new `workstream_changes_requested` milestone, sent when a PR review requests changes at the current head, reaches subscribed connectors, Azure Boards included. `hashd doctor` checks the configured types and states. Adopting an existing Azure Repos PR posts the parts of its description that are missing (#3599, #3619, #3647, #3650, #3672, #3699, #3700).

- **Forge reads.** GitLab and Azure DevOps "mergeability still being computed" now waits instead of stopping a merge. Gitea review threads report whether they are resolved. A lane's attention badge counts unresolved PR review threads, and the Web reject dialog preselects the PR's open findings. A plain `hashd pr push` is refused when the branch is already at the PR head, suggesting `hashd rebase` when the PR conflicts with its base. GitHub issue references take the form `@github:owner/repo#number`; existing links are converted on upgrade (#3613, #3620, #3633, #3697, #3709).

- **Merge-gate and rebase fixes.** A failed base fetch at the merge gate names the checks to make and the retry. An answered test question can resume an unfinished merge-gate FIX. A merge-gate repair shows as implementing while it runs. A retry of an unparsed provisioning baseline first brings the target branch up to date. Conflict counts are measured against the workstream's target branch, and a merged story's diff no longer includes upstream changes. A lane's conflicting documentation commit is dropped on a rebase again. A merge that landed is recorded once (#3616, #3625, #3630, #3631, #3636, #3657, #3661, #3679, #3731, #3755).

- **Runner and agent fixes.** A stage whose worktree lock is still held by a command an agent left running fails as itself instead of hanging until its deadline. Runner requests are retried only when the server says the refusal was transient, and the server's Diagnostic reaches the run when it is not. Work that completes during a restart hold continues when the hold ends. An implementer's objection to a review finding reaches the review judge. Antigravity (agy) can use tools and MCP servers and set its effort level. A protected-branch refusal of a REQS or SPEC write explains itself, and discovery stops when REQS cannot be refreshed. Config reads leave out connector secrets, and TUI Settings shows each connector's project account, which administrators can set and remove (#3591, #3596, #3597, #3610, #3611, #3614, #3615, #3623, #3632, #3648, #3659, #3675, #3732).

- **TUI.** Ctrl+J switches project; Ctrl+P is no longer bound. Every full screen's footer ends the same way, with `esc`, `q`, `/ commands` and `? help` (the dashboard has no `esc`). Workstream Detail has the graphs menu on Ctrl+G, as the dashboard does, and plain `g` no longer toggles the Gantt. The guidance action is labelled Feedback (TUI `E` and Web), and conflict resolution AI Resolve (ai-resolve in the TUI). Dashboard graphs that still fit stay shown as the terminal narrows, and Diagnostics show their related failures (#3592, #3669, #3671, #3737).

- **Web.** A PR closed on the forge is decided in one block on the story page and the Labs UI 2.0 workstream page, with Reopen and continue, Rework, Done elsewhere and Abandon; the dashboard no longer shows it. The Stories list filters on the server, keeps the filter in the address and loads long lists 100 rows at a time. The Code page loads folders as they open. The Changes tab shows whole files up to 10 MB a side and offers bigger ones as downloads. Copied code no longer carries a leading space on each line. Labs UI 2.0 gets layout fixes (#3592, #3600, #3652, #3656, #3676, #3688, #3695, #3712, #3718).

- **API changes.** `GET /stories` returns each row's owner but no longer its `available_actions`, which `GET /stories/{id}` serves; workstream and dashboard list rows leave out owner-menu actions. The workstream field `codex_session_id` is now `implementer_session_id`. `GET /workstreams/{id}/snapshot` names the current micro-commit (`selected_microcommit`), `GET /workstreams/{id}/changes?view=summary` returns the header summary, and `GET /workstreams/{id}/diff/blob/raw` streams a file version (#3670, #3682, #3693, #3702, #3712, #3715).

- **Faster pages and reads.** Many Web pages, TUI screens and server reads are faster: JSON is compressed, lists read only their candidate rows, owner menus load when opened, and the workstream page loads its change summary after the page (#3608, #3617, #3637, #3638, #3639, #3640, #3641, #3642, #3643, #3644, #3646, #3649, #3651, #3654, #3674, #3677, #3678, #3680, #3683, #3686, #3687, #3689, #3690, #3692, #3696, #3717, #3729, #3730, #3736, #3763).

- **Unassigned work does not run.** A story or workstream with no owner is shown as unassigned in the CLI, TUI and Web, and every request that would start or continue its work is refused naming `hashd assign`; closing it assigns it to the person closing. `hashd unassign` is refused on a single-user server and while the work is in flight. The server no longer assigns unowned work to the server owner at startup, and an agent launch that names no owner is refused instead of running on the host login or as the server owner.

- **A project has one environment.** Named entries set variables for every child hashd starts for a project: agent stages and the MCP servers they start, build, test and gate commands, baselines and hooks. An entry is a plain value, a sealed secret (optionally delivered as a file), the work owner's forge credential, or a variable read from the environment of the machine that runs the child; a repo's entry overrides the project's. It replaces `exec.env`, `exec.env_allow`, `exec.credentials` and project secrets, which no longer exist, together with `hashd project secret`, the repo `exec` setting (`--exec-file`) and the Settings sections Command environment and Project secrets. **On upgrade** the old settings are converted once: `exec.env_allow` names become host entries, secret bindings become secret entries named after the variable they were bound to, forge bindings become credential entries and `exec.env` values become value entries (on a name clash `exec.env` wins). The system config's `exec` block applied to every project, so its settings become entries of each existing project; a project added later starts with none. A project secret no variable was bound to is removed and a binding to a secret that was not set is left out; the upgrade output names each. A host entry is read from each runner's own environment, which hashd neither copies nor checks. Entries are listed, set and removed with `hashd project env list`, `set` and `remove` (`--repo` for a repo's entry); see docs/AGENT_MANAGEMENT.md, Environment variables.

- **Remote reads no longer take down the runner.** Abandoning a large forwarded response ends that request without crashing the runner or interrupting its other stages. Runner uploads use the server's read deadline, paired clients reuse connections, and both peers use the configured heartbeat miss count (#3268, #3272, #3273, #3279).

- **Unanswered stage offers are retried without launching a stage twice.** A runner retries a failed start acknowledgement with the same identity. The server re-sends an unanswered offer up to three times, then reports the runner and retry action. Only the workstream's first provision offer, before any stage has started, can be placed on another eligible runner; later stages stay with their owning runner (#3236, #3280).

- **Conflict resolution keeps its commit lineage.** The conflict agent can resolve, stage and continue a rebase to completion, including changes needed outside the initially conflicted files. Repository-local capture records rewritten commits even when the agent continues Git without hashd's environment. A resolution whose agent amends, squashes, rebases again or adds to the completed rebase's commits is discarded and retried, with the agent told why, instead of being published with commits hashd cannot follow. Failed attempts restore their original starting tip before retrying; interrupted resolves can recover through the existing AI Resolve action under their exact execution claim. Resolving a FIX-publication conflict resumes the unfinished FIX, including a generated commit above it (#3252, #3265, #3274, #3293, #3294).

- **Story rebase preserves uncommitted work as a WIP commit.** The work is recorded before rebasing and returned to uncommitted work on landing, replacing the previous carry mechanism (#3284).

- **Test evidence stays complete and readable.** Runners retain full test consoles while bounded display excerpts keep the tail and say how much was cut. Agent-facing references use hashd's stored-output read. Retry judges validate quotes against the full retained failing output. A command that timed out, was interrupted or has no readable result is not presented to the judge as an ordinary test failure; merge-gate deadline failures name the deadline and setting (#3123, #3172, #3175, #3213, #3218, #3241, #3242, #3263, #3271, #3286).

- **Setup-created artifacts no longer block repair.** Untracked paths proven to have been created by the workspace's setup hook are treated consistently in repair admission, dirty checks and staging. Pre-existing untracked paths and tracked edits keep their protection; an old workspace without the setup record gets no exemption. The existing build-side-effect ignore setting also applies to repair admission (#3295).

- **Choose where requirements and specs live.** `spec_mode` supports repo, local, external and none. Local mode keeps REQS and SPEC in a hashd-owned repository without a remote and completes stories when their merge lands. External and none modes use ad-hoc planning; they do not maintain REQS or SPEC, and configured `spec_paths` provide the team's own reference material (#3267, #3270, #3275, #3292).

- **Scope edits preserve the original requirement.** Approved descopes return requirements to their original REQS position. Descoped criteria appear as the story's Non-Goals. Pending stories accept edits and answers while waiting for dependencies; unresolved content questions prevent forward actions. A tracker item naming an unknown repository stops for a person instead of being routed elsewhere (#3180, #3234, #3240, #3269, #3300).

- **Backup creation, inspection and restore.** `hashd backup create` captures hashd state while hashd keeps running, and `hashd backup inspect` verifies the file against its manifest. `hashd backup restore <file>` brings a backup back onto a new host, with hashd-server stopped there. Repository clones (`repos/`) and runner checkouts are excluded: protect unpublished commits and uncommitted work separately. See the [backup guide](https://github.com/codr1/hashd-code/blob/v0.10.0/docs/BACKUP.md) for the exact contents, the restore procedure and its limits (#3289, #3320).

- **Personal accounts for planning and connector suggestions.** Planning connector reads follow the work owner's connected account in solo and team modes; autocomplete uses the requesting person's account. Missing accounts produce actionable refusals, and raw config reads withhold declared connector secrets. This does not introduce project-owned connector accounts or migrate legacy connector credentials (#3239, #3246, #3254).

- **Renewed accounts resume background forge work.** Entra renewal refusals alert the account owner, and interrupted PR observation can continue after the owner's account recovers. Azure Repos can read required PR checks and re-run a check through the existing forge path (#3040, #3146, #3257).

- **Runner access and agent homes are consistent.** Placement and runner choices enforce Anyone, These projects and Private work access. Gemini, Copilot, Qwen and Kimi use hashd-owned per-run homes alongside the existing Claude, Codex and OpenCode handling. Runner-installed tools remain available inside those homes, and planning MCP startup respects the operations fence (#3211, #3219, #3243, #3249, #3258).

- **Clearer operator decisions and history.** The Notification Center shows active alerts and retained history with dismissal. Close dialogs consistently offer the supported closure outcomes; projects can require a person to complete every PR on the forge, and a story whose PR was closed can be reopened and continued. Story approval is named Approved. Agent-call and implementation times use the viewer's local time, backed by nanosecond timestamps (#3130, #3134, #3150, #3173, #3194, #3195, #3205, #3259, #3260, #3261, #3285).

- **A quieter TUI footer.** The footer no longer shows the unread-history and active-alert pieces, and the `ctrl+y`, `f2` and `f8` keys are gone, with the dashboard's test-results line. Toasts are unchanged, and the Notification Center still opens from the command menu. The dashboard footer shows `[s]ettings` and no longer `[ctrl-g]raphs`: `ctrl+g` still works and its control stays on the status line. The command menu has a `settings` command that opens Settings from any screen.

- **A failure under stage isolation names what git stopped on.** With stage isolation on, git prints a harmless `packed-refs.lock: Permission denied` line while it works. A failed archive, rebase or merge reported that line as its cause; it now reports the error git stopped on, such as the commit a documentation rebase could not apply. The captured output is unchanged (#3256).

- **An archive whose documentation conflicts with the destination regenerates it.** When the prepared SPEC and REQS commit no longer applies because the destination changed in the same lines, the archive discards it and generates the documentation again on the current destination, then publishes that. It does not merge or resolve the two versions. If the regenerated commit conflicts too, the archive stops and names both conflicts with their files and destination commits; running the merge again generates the documentation once more (#3256).

- **A merge gate that rebased over a recorded test pass no longer fails with "Could not read the runner merge_gate result".** The gate's record carried that pass twice, each with the suite's whole per-test list; on a suite of about 14,000 tests or more it outgrew what one workflow message holds, the result was dropped, and the lane failed after four minutes. The record now names the pass and leaves the per-test list in the verdict store.

- **Each cycle carries a smaller baseline record.** The baseline test run's whole per-test list travelled through the workflow on every cycle of every lane (2.4 MB for a suite of about 16,000 tests, and growing with it toward the 4 MiB a workflow message holds). The cycle now carries the baseline without that list; the workstream's stored baseline keeps it.

- **A runner no longer slows down over old closed attempts.** Before each check-in a runner settles what its journal still holds. An attempt the server closed before it ever started is now settled even when the runner had recorded an empty cleanup for it, and settling reads only the assignment's state, never its full input. Runners carrying such attempts answered offers seconds late.

- **A busy database names the write it refused.** Every database write takes the write lock when its transaction begins. A write the database still refuses after its wait is reported as "Could not <write>: the database was busy" with nothing written, instead of a bare "database is locked".

- **A stage result too large for its workflow is refused at once, by name.** A runner stage reply over the 4 MiB a workflow message holds used to be dropped in transport: the lane sat for four minutes and then failed with "Could not read the runner ... result" marked retryable, though no retry could succeed. The read now fails immediately with the stage, the reply's size and the limit, and is not marked retryable. The recorded result is kept.

- **Archive failures retain their next steps.** Archive Diagnostics survive blocked reports, and documentation publication can recover for externally merged PRs without hiding a failed push (#3225, #3264, #3299).

- **Faster and steadier development gates.** Concurrent gate phases may use all CPUs, so Go tests can use the whole machine after shorter phases finish. Fixture reuse and race fixes reduce repeated setup and host-dependent failures. The review checker recognizes a finding withdrawn by the bot's own last reply on a resolved thread (#3282, #3290, #3296, #3297, #3301, #3302, #3303).

- **Every agent that chooses or checks technology is shown the project's tech stack.** The project's description and its Preferred, Acceptable and Avoid lists, written once in `include_project_summary.md`, now reach the FIX implementer, the project, story, workstream and clarification chats, the story planner, breakdown and add-commit, as well as the implementer and the per-commit reviewer. A project with no description is named instead, and a blank list reads "Not specified". **If you override `review_contextual.md` or `review_closed_list.md`:** their tech variables are renamed from `preferred_tech`, `acceptable_tech` and `avoided_tech` to `tech_preferred`, `tech_acceptable` and `tech_avoid`, the names the implementer's prompt uses; an override that still names the old ones fails to render, and the per-commit review fails, until it is updated.

- **The chat dock leaves the page room beside the nav.** In the Web, dragging the dock wider stops where the page would drop below its minimum width, counting the nav's width, which it used to ignore. A window too narrow for the nav, the page and the smallest dock opens the dock over the page, as expanded, where Esc closes it. When the window widens again the dock goes back beside the page at the width you chose, unless you had chosen expanded, which it keeps. In the TUI chat, Ctrl+J types a new line on every terminal, Windows Terminal included, and the hint names it. Shift+Enter does too on terminals that speak the kitty keyboard protocol (kitty, Ghostty, foot, Alacritty, iTerm2, WezTerm with it enabled); the hint names it once the terminal has reported it, since elsewhere Shift+Enter sends.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.33...v0.10.0

## v0.9.33 - 2026-11-06

v0.9.33 fixes a v0.9.32 crash in AI conflict resolution when it renumbers a migration, and brings short status labels to the TUI and the CLI.

### What's Changed

- **AI conflict resolution no longer crashes on a migration.** In v0.9.32, `hashd merge --ai-resolve` stopped with "commit operation does not belong to this merge leg" when the story's migration had to be renumbered. The resolve now renumbers it like every other merge path.

- **Status labels in the TUI and the CLI.** Stories and workstreams show short labels ("Ready To Merge", "Implementing / Idle", "Approved") from the same table the Web uses. Where a badge already names the stage, the line beside it shows only the runtime. `--json` output keeps the raw values.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.32...v0.9.33

## v0.9.32 - 2026-11-06

v0.9.32 renumbers migrations automatically when two branches both add one, adds a .NET build adapter, keeps implementers' commit messages, and tells same-named tests in different files apart.

### What's Changed

- **Migrations both branches added merge without a hand rescue.** When a story and its target both add a migration, merge preparation renumbers the story's migration as a whole (every file of it) after the target's newest and follows the rename in its references. Anything less clear-cut (a migration the merge removed, one both sides added under the same name with different content, a changed body) stops for review with a reason naming the migration. If the target moves during the merge, hashd prepares again before landing.

- **.NET build adapter.** hashd reads the TRX files `dotnet test` writes. Add `--logger trx` (VSTest) or `--report-trx` (Microsoft.Testing.Platform) to the test command configured in hashd; the project and its CI need no change (#3109).

- **Build cleanup also removes ignored files.** Paths listed under `build_side_effects.clean` (or an adapter's defaults) are removed after a command even when the repository ignores them, so old report files no longer read as stale on the next run. Files that were there before the command are left alone.

- **Implementers' commit messages are kept.** The body an implementer writes is recorded with each micro-commit and FIX commit, survives retries and checkpoint resets, and reaches the final reviewer. Commit messages are written as UTF-8 whatever `i18n.commitEncoding` says (#3097).

- **Same-named tests in different files stay apart.** A failing test is identified by its file and its name everywhere, so `TestLogin` in two files is two tests. A "go anyway" accepted on an earlier run needs accepting again after the next run.

- **Every failing test is listed.** The failure summary no longer stops at ten failing tests, ten compile errors or five build errors.

- **Recorded test results are reused.** When a commit's tests already ran and were recorded (at provisioning or an earlier merge attempt), the merge reuses that result instead of running the same tests again, and the base's standing known failures are shown with it.

- **`hashd log` shows why something stopped.** A one-line entry whose detail was empty now shows the explanation the server recorded.

- **Status labels in the new design.** With Settings > Account > Labs > New design on, the Web shows short status labels ("Ready To Merge", "Human Review") with the raw value on hover.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.31...v0.9.32

## v0.9.31 - 2026-11-06

v0.9.31 makes test failures from projects without a build adapter count everywhere, settles runner work cut off by a restart, and fixes a merge-start deadlock, a stranded-dependents bug and runner moves to a runner whose repository is behind.

### What's Changed

- **Failing tests named from your output are used everywhere.** When no build adapter reads a project's test results (Nx/jest, for example), hashd's failing-test reader names the failing tests from the output, and those names are now used exactly like mechanically parsed ones: in the failure list, the judge's input, the question you're asked, the record, baselines and go-anyway. If hashd can't mechanically verify the names (for example, several summary lines), it records "named by model; not mechanically verified" with the reason and carries on. A clarification no longer says no test was named when the output names one (#3107).

- **Closing a story by person releases what was waiting on it.** `hashd close <story> --ref` now releases pending dependent stories the same way an implemented story does, with no `hashd plan reset` needed (#3101).

- **A refused forge-merge archive recovers.** A PR merged on the forge whose archive was refused is retried automatically and, if it still can't finish, stops with a visible, actionable reason instead of being stranded (#2956).

- **Runner work cut off by a restart settles itself.** A runner records when a stage's work has finished cleaning up and reports it when it reconnects, so a story whose runner restarted can move again without manual recovery. Where the runner can't prove it, hashd says what proof is missing.

- **Moving a story to a runner whose repository is behind works.** Provisioning fetches the story's recorded base when the runner doesn't have it yet, and refuses clearly, naming the commit, branch and runner, if that commit is gone.

- **Merges no longer stall on a runner answer.** A merge start no longer waits on its own database connection while asking the runner about the branch.

- **"orphaned" is now "interrupted".** A workstream whose run stopped without a result shows as interrupted. Saved automation conditions are updated automatically on upgrade.

- **Arc proposals show a plain label in lists again.** Story lists on the CLI, TUI and Web show the plain Arc label; a pending question stays marked separately.

- **Settings > Account > Labs.** A per-browser switch page for preview features, starting with "New design".

- **Recorded instruction authorship.** Lineage records who gave each instruction, including retry feedback.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.30...v0.9.31

## v0.9.30 - 2026-11-05

v0.9.30 improves secret-scan recovery, agent controls and the decisions around closing or merging a story. It also makes automated reviews more focused and restores familiar action names and keyboard hints.

### What's Changed

- **Secret scans use the repository's rules and keep runner evidence.** The merge gate honours the scanned checkout's `.gitleaks.toml`. Findings, source context and scan-time ignore entries remain readable from the server when the checkout lives on a runner. Gitleaks `allow` and `remove` use `--workstream <story>` to update that story's `.gitleaksignore` on its assigned runner; failed or missing scans are distinct from clean scans.

- **`hashd merge` recognises PRs already merged on the forge.** It reads the PR state before preparing another merge and reconciles a person's completed merge into the story's closure and archive. A stale final review no longer strands that reconciliation, and hashd does not rebase, test or push the already-merged branch again.

- **Close dialogs offer the right ending.** TUI and Web story and workstream dialogs offer the server-permitted choices: **Abandon**, **Done outside hashd** with a reference and reason, or **No changes needed** with a reason. Each choice explains its consequences, and a refused close keeps the dialog and entered values available for correction.

- **An unmerged PR closure waits for your decision.** Closing a PR on the forge leaves its story parked as **PR closed**, with the branch intact. The CLI, TUI, Web and Telegram show the closure and its context. **Rework** continues on the same branch with your guidance; the close and abandon choices remain available where permitted.

- **Enable or disable each agent in Settings.** **Settings > Agents > Agent Properties** has a server-wide **Enabled/Disabled** control for every declared agent, available to owners and administrators. Disabled agents cannot be selected for new assignments or launched, while existing assignments stay visible and running work continues.

- **Merge conflicts can be resolved automatically.** The project setting `merge.ai_rebase` defaults to enabled. Hashd can use the configured conflict-resolution agent during merge preparation, then run the full configured verification before continuing. A failed resolution or verification stops with its evidence and recovery guidance; projects can disable automatic resolution.

- **Reviews judge the story's changes.** Per-commit and final reviews distinguish branch changes from newer work on the target branch. Upstream movement alone no longer creates findings or lowers confidence, and reviewers leave rebase and migration alignment to the merge stage while still reporting concrete defects in the branch.

- **Merge-gate recovery skips judgments it cannot act on.** When neither automatic repair nor a judge-requested re-run is available, hashd stops with the existing failure evidence instead of making another adjudicator call. If a judgment requests a repair that is not allowed, the stop preserves its reason and explains why no automatic FIX was started.

- **Familiar action names and clearer keyboard hints.** Workstream controls again say **Reject**, **Add guidance** and **Approve**, with their footer shortcuts restored. History hints show the actual `ctrl+y` binding, and other Ctrl shortcut hints use lowercase letters too.

- **Code tools install on older Linux hosts.** Linux installs now use the statically linked codebase-memory-mcp build, so Debian 12, Ubuntu 22.04 and Amazon Linux hosts no longer stop with "Code tools could not be installed". The public installer applies the same fix when it installs v0.9.29.

- **CI and timing fixes.** More reliable login-status and Arc workflow checks, plus faster disposable workflow stores, reduce flaky CI runs.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.29...v0.9.30

## v0.9.29 - 2026-11-04

v0.9.29 brings Network access and link-based pairing, whole-stage execution on runners, Azure DevOps integration, and Antigravity support. It also improves recovery when a rebase, sign-in, review or merge stops, and keeps the evidence needed to make a decision visible across the CLI, TUI and Web.

### What's Changed

- **Upgrade note: remote clients and runners must re-join.** Network access changes TLS trust. After upgrading, existing remote clients must re-join with a new link. Re-join each existing runner under its **same ID**: generate its link with `hashd runner join-link <runner>`, then run `hashd runner connect -` on that runner and supply the link. This preserves its placements. For a source checkout, set `HASHD_OPS_ROOT` explicitly when the operations root is not the checkout, and launch services with `umask 022`.

- **Network access has one set of controls.** Enable “Allow other devices to connect” in TUI or Web Settings, or use `hashd network on|off|status`. Pair devices, invite people, add or revoke runners, and configure a Public URL through the same server-provided actions. Solo stays on localhost by default. Only hashd-server opens to other devices; the managed Web service stays on loopback behind the server's HTTPS `/ui` and `/join` relay. The remote-access guide includes reverse-proxy and ALB deployment.

- **Browser-trusted HTTPS over Tailscale, when available.** For this machine's own `*.ts.net` name, Network access can use the certificate supplied by local tailscaled, with no extra hashd setting or renewal service. Status says whether it works and how to repair a refusal. Other names keep the hashd CA certificate, and an unavailable Tailscale certificate falls back to that CA. Join links prefer the Tailscale address only while its browser-trusted certificate works.

- **Runners execute complete stages where the checkout lives.** Local and remote runners use the same execution model, carrying command output, agent transcripts, test reports and failure evidence back to the server. Fleet shows placement, connection, compatibility, agent versions and sign-in status. Moving or reconnecting a runner no longer makes the server assume its checkout is local; files and diffs remain available through placement, and the REST `worktree` field is empty for runner-backed work.

- **Code-intelligence tools are installed and checked on execution hosts.** Installs and upgrades carry the pinned codebase-memory-mcp runtime. Doctor and runner admission report a missing or wrong version, and a code-backed stage refuses before agent launch if the tools are unavailable. Codex receives its MCP configuration in the correct argument position, so its stages can actually call the code tools.

- **Sign in on the machine that runs the agent.** Fleet supports owner-scoped agent sign-in on runners, with manual, push or proxy methods where the agent supports them. Claude, Codex and OpenCode use hashd-owned profiles; explicit instruction delivery keeps project guidance available without exposing unrelated host credentials. Model and effort choices use the same stage settings across agents, and lost sessions, model refusals and context failures have actionable recovery messages.

- **Antigravity is selectable through its official ACP runtime.** Install the qualified runtime, then use Fleet's manual personal-Google sign-in or register a Gemini API key. Remote browser sign-in accepts the native return URL through the existing sign-in flow. Fleet shows the runtime's model and thinking choices, which are reapplied on resume; a listed model is not a guarantee of account access. Cloud/Enterprise and push/proxy sign-in are not enabled for Antigravity in this release.

- **Azure Repos and Azure Boards are integrated.** Projects can use Azure Repos as their forge and read filtered, multiple Azure Boards sources. Native Entra sign-in stores owner credentials securely and requests narrower delegated scopes. Repository hints, work-item descriptions and story/PR links survive intake. Command credentials and named project secrets reach declared build, test and gate commands, including those on runners, without being placed in agent prompts.

- **Tracker links and lifecycle moves are more useful.** `hashd story link` can find or create the corresponding Azure Boards work item or ClickUp task. Jira supports named lifecycle transitions and open-sprint filtering. Azure Boards, ClickUp and GitHub have default lifecycle moves, with completion tied to the story reaching a terminal state.

- **Forge completion respects reviewed branches.** Projects can choose hashd completion, forge completion or supported forge auto-completion. Human reviews and approvals are evaluated against the relevant head; bot votes do not count as human approval. Reviewed branches require the appropriate acknowledgment before a rewrite, and externally completed PRs can finish their archive instead of getting stuck on an invalid transition.

- **Rebase uses the story's prepared checkout.** `hashd rebase` works on the story branch in its own checkout, retaining its setup, dependencies and code index. Uncommitted changes are carried through the rebase and restored afterwards. Recovery refs protect the original work; if accepted conflict resolution adds or drops carried paths, the outcome names them and gives a recovery command instead of refusing the rebase. Provisioning also warns about untracked paths created by setup, with the ignore fix.

- **Recovery preserves ownership and explains the next action.** Competing execution flows cannot take over the same workstream, and starts that never reached their first stage can be recovered. Workstream pause uses the same name throughout the API and interfaces. Review, test and merge stops retain their Diagnostics and supporting evidence; clarification questions carry the conclusions needed to answer them. FIX prompts also remind the implementer of defect classes found in earlier reviews of the same story.

- **Build and test evidence follows the project's tools.** Build adapters can be automatic, disabled or explicitly selected. Go, pytest and Jest reporting handles their declared output paths, including container paths. Failure readers preserve failing-test evidence, and environment failures can stop with the repair needed instead of asking an unhelpful yes/no question. Post-rebase test policy is configurable, and baseline-only failures have a distinct continuation path.

- **Planning, Arcs and lineage keep their context.** Arc children and dependencies appear together in the dashboard, planning claims survive retries, and deferred work remains a suggestion instead of disappearing. Stories can target a branch and follow team branch/commit conventions. Lineage supports cross-repository links, pinned historical reads and reproducible exports, while distinguishing integrity from attribution.

- **Decisions are readable in the TUI and Web.** Decision text and options can be read in full, large diffs have Load More, and action labels and explanations come from the server. Dashboard titles wrap, Fleet and Settings layouts are clearer, and toasts move down when a lower toast disappears. Standing alerts and routed notifications retain the story and the action needed instead of relying on transient messages.

- **Source builds and operations are more predictable.** Generated files are no longer tracked; source builds regenerate them. Agent stages use the configured filesystem fence to protect operations data, with explicit failures when the required protection is unavailable. Install, upgrade, service lifecycle and doctor checks report missing prerequisites rather than silently continuing.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.28...v0.9.29

## v0.9.28 - 2026-10-15

v0.9.28 is one day of dev since v0.9.27: the fifteen findings of the first full soak of a packaged install (solo, team and GitHub PR mode on a fresh box), each fixed and landed the same day. A fresh install gets a working TUI again, a team server comes up and restarts the way the docs describe, Codex can resume its sessions under per-user credentials, and several diagnostics say what the operator actually has to do.

### What's Changed

- **A fresh install's TUI starts.** hashd-tui bounds textual to the locked, tested version (a fresh wheel install had resolved textual 8, which removed an export the TUI imports, so `hashd watch` died at import), and the release upgrade smoke now checks the installed textual against the lock and imports the TUI's entry modules from the installed environment.

- **Team servers release the stop hold at startup.** On an HTTPS bind the server's boot-time self-dial verifies against its own certificate fingerprint and presents the internal token, so the startup release of a restart hold runs and spawned agent runs can register; `hashd start` waits for that release and reports it instead of staying silent while every client is refused.

- **A restart that moves the bind address stops the server that is running.** With the configured URL naming a new local address, `hashd restart` and `hashd stop` hold, wait and stop the server actually listening, print one line naming both addresses, and start the replacement at the configured one. The cached token is found for the same loopback server under its other spellings (localhost, 127.0.0.1, ::1) and never sent to a different loopback address.

- **Codex resumes sessions under an injected credential.** The per-user codex home keeps its session rollouts across invocations and server restarts while still removing the materialised credential, so review and implement resumes work in team mode; a genuinely lost session (`no rollout found`) is classified as a dead session and the review falls back to a cold round instead of failing the run after transient retries.

- **Remote clients read context files locally.** `plan story -f`, `plan bug -f`, story edits, rejects and workstream feedback that name a file read it on the client and send its content; a path-shaped value that names no readable file is refused before any request is sent.

- **`hashd plan` refuses unknown words and running discoveries.** `hashd plan <typo>` errors with the subcommand list and a did-you-mean instead of dispatching discovery, and `POST /plan/discover` while a discovery is already running answers a 409 naming the running discovery and its start time, with no side effects.

- **The planner splits bundled features.** A story whose description lists two or more independently deliverable features gets a split verdict however far under the size threshold it is, with one piece per feature; it stays whole only when the reason says why the features are inseparable.

- **Breakdown survives a worker death.** A breakdown activity lost to a dead worker is retried once, recovering a plan, guidance or question the lost attempt had already committed (stamped with the run id, so a run that started already parked is told apart) instead of failing the run or asking twice.

- **Planner and implementer know the configured commands.** The project's build, test and merge-gate commands reach the planner and implementer, a story that renames a configured script parks with the exact config command to run, and a missing configured script is attributed as such for npm, pnpm and Yarn (asking Yarn under Plug'n'Play), with script-neutral flags tolerated and everything unknown kept conservative.

- **Installer and doctor say what is wrong.** The installer reports a browser runtime that failed to install (missing system libraries) with the package command for the detected manager instead of silently continuing; `hashd doctor` never prints "All checks passed" under an error line, and optional dependencies warn instead of failing.

- **Codex accepts `xhigh`.** The Codex effort ladder includes `xhigh`, and an unknown `agents.<name>` key refusal points at `stage_effort` and `stage_models`.

- **`hashd pr push` brings the branch up to its base.** A plain push rebases onto the current base before publishing, as its help says; a refusal names the hashd command to run, and the behind-base retry keeps the first attempt's force-with-lease so a colleague's commit on the PR branch is refused, never overwritten.

- **Config listings render whole numbers as integers.**

- **Web design audit follow-ups.** Tooltips and popovers stay inside the viewport instead of being clipped by cards and scroll boxes, Code saved rows keep their file name beside the per-file discard control, the Code page shows one column at a time and gallery stat tiles go two-up at phone width.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.27...v0.9.28

## v0.9.27 - 2026-10-14

v0.9.27 is two days of dev since v0.9.26, cut to carry the fixes the v0.9.26 release gate itself surfaced and the gate-speed work that followed. Nothing changes in the product's shape; what changes is that upgrades from older releases restart correctly, external tools can open a hashd database again, reviews stay inside their reviewer's limits, and a landing spends minutes rather than tens of minutes in gates.

### What's Changed

- **Upgrading from a pre-hold server restarts instead of refusing.** `hashd restart`, `restart server` and `stop` read the running server's version first. A server older than the restart hold (v0.9.25 and earlier) is stopped the pre-hold way, with one printed line saying so; a modern server keeps the hold-and-wait protocol, and a refusal from it is rendered whole. The in-place upgrade from v0.9.25 is proven by the release upgrade gate.

- **System sqlite3 can open a hashd database again.** Six triggers used expression messages in `RAISE()`, which only SQLite 3.47 and later parse; Debian stable's and Ubuntu's sqlite3 reported the whole database as malformed. The messages are literals now (schema 95), and a guard refuses any future expression message.

- **A merged workstream whose archive failed stays visible.** It reads as failed on every surface, its story says so, `hashd merge` re-runs the checkpointed archive, and the janitor retries a retryable archive failure (including transport timeouts) once. Hook output is kept whole.

- **New databases load the authored schema.** A blank database is created from `schema.sql` at the release's schema version instead of replaying every migration, and upgrades are supported from the previous release onward; an older database is refused read-only with the release to step through first.

- **Reviews know the operator's rulings.** A dismissed finding is recorded with its reason (`hashd workstream acknowledge`, `hashd reject --dismiss`) and reaches every later per-commit, final and repair review round; a reviewer may re-raise it only with new evidence, tagged with the ruling's id. Rulings are shown beside the current review in `hashd show`, the TUI and the Web.

- **Delta final reviews stay inside the reviewer's input limit.** A delta round that would exceed the agent's limit lists the touched files instead of embedding them, and the record says which mode ran; a prompt still over the limit fails with a Diagnostic naming its largest sections instead of a bare agent error.

- **A clean rebase verifies with build plus the fast check.** At the landing, PR, auto-rebase and resolve sites, a conflict-free rebase runs the project build and the fast check over the branch's touched files when the full suite is already proven on the pre-rebase tree; a fast failure runs the full command, whose verdict is what is recorded and recovered. Every surface says which check ran.

- **Commit repair recognises any golangci-lint refusal.** A pre-commit refusal that is a complete golangci-lint report takes the automatic repair whatever linter it names, not only the three that were listed.

- **An adjudicated flake re-runs the merge gate once.** When the adjudicator rules a merge-gate failure a flake and there is nothing to fix, the gate re-runs itself once before parking, without spending the story's automatic FIX allowance, and a park record is complete.

- **Temporal e2e failures carry their evidence.** A cancellation, Arc, runner or housekeeping journey that exceeds its deadline dumps the workflow histories, task-queue state and sidecar metrics into the gate log before teardown. Temporary diagnostic instrumentation, tracked for removal in DAS_PLAN.

- **Gates.** Test-runtime scratch runs on tmpfs (the full gate drops from about 340 s to about 140 s on the dogfood box), gate receipts record wall and CPU per package, a clean full gate records its verdict so the same tree is not re-tested on push, builds stamp one version across all three binaries, the Go build cache is bounded, and the per-commit fast check selects direct importers only and runs Python suites only when Python changed.

- **Specification.** SPEC.md is rewritten as the present-tense specification of the product with a domain-model section derived from the authored state machines, and the post-merge documentation step edits a feature's section in place instead of appending.

- **Release workflow.** The macOS wheel job sources its tooling from a file (bash 3.2), and the manifest counts platform and pure wheels by name.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.26...v0.9.27

## v0.9.26 - 2026-10-12

v0.9.26 is two months of dev since v0.9.25: 182 stories and bugs, 462 pull requests. The headline is Arcs, a story that becomes a planned set of child stories through a reviewable proposal instead of a one-shot conversion. Under it, the engine learned to say what it is doing and why it stopped, the merge gate stopped re-testing trees it has already passed, and the test stage now runs the repository's own pre-commit hook before anything else.

### What's Changed

- **Arcs, the whole flow.** A story that is too big gets an Arc proposal: the planner drafts the child stories, asks factual questions and resumes from the answers, and the proposal waits for review in a dedicated TUI and Web workspace with revise, refresh, cancel, retry, version history and a server-computed comparison between versions. Approval is one typed, version-bound decision that converts the story and creates the children; the old make-arc conversion and its yes/no breakdown review are gone. Children render as a Planner-style tree; Arc labels on every surface come from served facts.

- **Stories have an immutable number.** A story's identity is a project-scoped number allocated durably; its type prefix is a label. Completed stories unblock their dependents through every finalization path, and a story can be assigned to a teammate from Story Detail in the TUI and Web.

- **Cancel what is still being planned.** `hashd cancel` now stops a story that is drafting or editing, discards the in-flight planner output and restores the prior state, with the Web asking first. Workstreams pause and unpause under one name in the TUI, Web and CLI, and a paused workstream reads paused everywhere.

- **The test stage runs the repository's pre-commit hook first.** Lint, formatters, secret scans and whatever else the hook enforces are discovered before the tests and the review, not at commit time; a refusal is a test failure with the hook's output as evidence. Recognized lint refusals at commit get one bounded automatic repair.

- **A tree that passed is not tested again.** A project-wide test verdict store replaces the per-workstream gate receipt: the merge gate, post-rebase verification, the per-commit test stage, the committed-breakage probe and the base comparison reuse a recorded pass for the same tree, command and tool, and every reuse is on the timeline. The gate certifies the head it ships: normalisation happens before verification, never a commit after.

- **Stage roles and per-stage models.** Planner, coder, reviewer and reviewer-adjudicator are roles in system and project config, with per-stage model and effort overrides rendered into the effective agent. A `*_resume` stage always runs its base stage's agent.

- **Every stop says why, durably.** Deadline kills name what died, which bound fired and how it derives; merge stops and merge-gate parks say what failed, never that an allowance was spent; standing faults render in full on TUI, Web and Telegram; action refusals render the full server Diagnostic; messages that name a workstream lead with its story or bug id. Both reviewers emit every finding, each tagged with what it is against and its class, and each verdict is recorded against the diff it graded.

- **Transport failures retry instead of parking.** PR create, PR push and the post-merge dev publish retry a transport-kind push failure on the cached verdict. Runs have honest boundaries: one run_started and exactly one closing outcome, including executions terminated from outside.

- **One notification system.** Server-side attention selection with project history, consistent toast lifetimes and dismissal in the TUI and Web, desktop toasts classified in one place, and an attention filter with cursor paging on the event list.

- **Reports.** Shared report contracts, usage calculations shared with `/cost`, a tokens-over-time series served by hashd-server, captured call usage and cost in relational tables with one authoritative per-call USD, numeric epoch timestamps written by production writers and queried through indexes, and lines-changed recorded at each micro-commit and at merge.

- **Web.** Dashboard with charts first, one sectioned story list and Activity as a drawer; a divided-list component so density is set once; the workstream page shows story and micro-commit LOC; connector links on Story Detail; connector issues import into Suggestions from the Plan page; a filter to my own stories and workstreams; typography on mono roles with the setting-only tests culled.

- **TUI.** Compact Braille graphs on the dashboard, scrollable lists and detail boxes, Forge review at the top of the Review panel, a live timeline that stays current, chat with a real working line and interrupt, LOC on Workstream Detail, and server text rendered as markup without corruption.

- **Operations.** `hashd stop` and `restart` check what they would kill, honor the server's graceful shutdown and confirm process exit; hashd-web drains open streams and exits cleanly on SIGTERM; `hashd doctor` keeps hashd-web's build in step with hashd-server's; the server build produces both binaries; new workstreams provision from a freshly fetched default branch; `hashd approve --force` accepts pending requirements as written; a momentarily missing agent binary is retried; GitLab forge reads work with the pinned glab.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.25...v0.9.26

## v0.9.25 - 2026-08-12

v0.9.25 makes the PR loop tell the truth about heads. Gatekeeper PR mode deliberately made publishing a keystroke -- but the surfaces never learned about the state that gate created, so finished fixes sat invisibly unpushed while the forge reviewed stale code and the reject box re-fed findings that were already addressed. One comparison -- the worktree's HEAD against the PR head hashd last pushed -- now feeds every surface in the loop. Alongside it, planners can no longer promise commit topology the pipeline itself breaks.

### What's Changed

- **The board says when the PR is behind your work.** At pr_open the workstream detail carries the head comparison and `hashd show` renders it in git's own words: `ahead of PR #440 by 1 commit -- push to publish` (behind and diverged read analogously). The run-complete notification appends the same sentence the moment a fix cycle lands push-ready, so the operator is told instead of polling (#1426).

- **The reject box never re-feeds a stale review.** When local work is ahead of the PR, forge findings are withheld entirely -- no per-finding staleness guessing, human reviews included -- and the box explains itself with a warning: the last forge review was of the old head; push to solicit the latest. Heads match: threads fold exactly as before. The threads read freshens the tracking ref first, since it already paid a forge round-trip (#1426). The TUI renders the withheld notice in the warning color, wrapped and capitalized, instead of an ambiguous empty box.

- **Merging locally past an open PR requires saying so.** The local-merge leg used to land the branch and strand the forge PR forever. It now refuses with the PR named unless acknowledged (`-y`), and after landing it closes the PR with a "merged locally as <sha>" comment -- a failed close degrades to a durable event, never a broken merge (#1426).

- **`hashd pr push --sync` recovers from a moved remote.** A lease refusal now names its remedy: --sync fetches, rebases onto the remote branch, and retries the push; conflicts abort cleanly with the files listed. The sync leg takes the structural-verb busy guard -- a rebase under a live agent is the worktree-clobber class -- re-checked immediately before the rebase, with a preempted refusal that reads as busy, never as an infrastructure error (#1426).

- **Planners stop promising what the pipeline breaks.** A story question offered "one commit or three?", the answer became a per-commit revertability criterion, and the review cycle's own appended FIX commits made it unsatisfiable -- a fix loop that could never converge. Story refinement and editing no longer ask about or encode commit counts, boundaries, or per-commit revertability (sequencing excepted); breakdown refuses such criteria before any code exists, naming the criterion for amendment. For independent revertability the honest unit is a workstream split, and the planner now says so.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.24...v0.9.25

## v0.9.24 - 2026-08-11

v0.9.24 is the release where an infrastructure brownout stops costing a workday. A live incident -- the engine's store starved for 78 seconds behind a saturated disk, two mid-flight agents killed, a fix cycle silently abandoned under a stale status -- was root-caused end to end, and every layer of the response ships here: the engine absorbs the blip, tells the operator it happened, and explains itself in plain evidence when it still has to park. Alongside it, reviewers can no longer hold a commit under the confidence line without naming a finding, planning prompts stop hauling the whole SPEC into every run, and the README finally says out loud what a team server does.

### What's Changed

- **A reviewer's doubt must have a name.** An approve carrying only nits and suggestions but graded below the commit-confidence threshold is a contradiction -- the verdict says ship, the number says do not, and nothing explains the gap. That shape used to grind soft retries into a park with nothing actionable. The reviewer contract now says it directly in all five prompt copies: nits are, by the reviewer's own classification, not reasons to hold a commit, and a systemic problem must be a named finding, not a quiet number. The verifier enforces it at authoring time against the loaded threshold (#1416), so the reviewer reconciles in-session instead of starving the loop.

- **Janitor cancels that land, and only one of each notification.** A run parked at the human gate waited in a signal that could not be cancelled, so a workstream closed while parked left a zombie the janitor "cancelled" every five minutes, forever -- 2,776 times on one live box (#1417). Parks now wait cancellably, the janitor escalates to terminate when its cancel is already pending, cleanup rows carry the run id and reason, and existing zombies self-clean on the first sweep after upgrade. The same PR ends the TUI writing every notification to the events table twice.

- **Human-gate questions carry their evidence** (#1418). Every runner escalation clarification now names the failing test and its first real error line, the micro-commit, the run id, and what each escalation tier actually concluded -- including "did not run" and "timed out unruled" as their own truthful states. A judge that never got to rule renders as "could not run (reason)", never as part of a reasoned chain.

- **Infrastructure failures reach the operator** (#1419). Engine degradation debounces into incident events (onset and recovery with duration), an agent killed by the runner emits an event naming the workstream, stage and cause, and a housekeeping action hitting the same target sweep after sweep warns instead of quietly writing row 2,730. The TUI footer shows engine state, `hashd status` lists recent incidents, and doctor joins in -- what used to die in log files is now on the surfaces you actually look at.

- **An agent killed by infrastructure is not "interrupted"** (#1422). When activity cancellation -- a heartbeat timeout, an engine brownout, a worker shutdown -- killed a live agent, the death was classified as a deliberate interruption and never retried, silently abandoning the work. One boundary helper now propagates cancellation for every agent stage: infrastructure deaths retry and resume the session, judges get to actually rule on the next attempt instead of parking a human on a question no one asked, and genuine agent self-exits still never auto-retry. A run that ends interrupted mid-attempt now says so on the workstream instead of hiding behind a stale review status.

- **Planning prompts reference the SPEC instead of swallowing it** (#1423). Edit and refine runs were rendering the entire SPEC.md into the prompt -- 671KB observed live -- on every planning cycle. Prompts now name the file and the agent reads the parts it needs; flows that mutate the SPEC make targeted edits instead of rewriting the document.

- **Planners name migrations by intent, never by ordinal** (#1421). Two parallel stories claiming the same migration number is a collision baked in at planning time. Plans now describe the migration; the implementer numbers it against the tree at hand, and a collision after a rebase is an ordinary semantic conflict the merge gate already renumbers mechanically.

- **Chat moves into the browser** (#1420): the web dashboard gains chat sessions.

- **The README says the team part out loud** (#1424). Working together on one server -- per-request attribution, workstream ownership, per-user agent credentials, team mode, the browser dashboard -- is shipped capability, and the README now leads with it: the first coding platform designed to enhance the team.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.23...v0.9.24

## v0.9.23 - 2026-08-10

v0.9.23 is the release where the review loop learns to tell a code bug from a product decision, and where a week of live multi-project driving hardened every path that had been quietly lying about state. The escalation ladder gains a judge that can rule "insufficient / contradictory requirements" and ask the operator the actual product question in plain language -- then amend the story's acceptance criteria (with the operator's approval) so the record stops contradicting the answer. Underneath it, AI conflict resolution can no longer destroy its own success, the FSM refuses structural mutations under a live worker, team servers get per-user agent credentials across all three surfaces, and clients survive restarts they used to sit out forever.

### What's Changed

- **The review judge escalates product conflicts to the human, in product language.** Five review rounds alternating between two locally-correct objections is not a code problem -- it is a story whose requirements cannot all be satisfied at once. The round-3 non-convergence judge (#1406) now recognizes that shape and rules "insufficient / contradictory requirements" (#1412): it must first attempt one honest reading that satisfies every finding -- and a resolution that lies to the end user (a silent no-op behind a success banner) is never a valid reading -- then, if none exists, it quotes the two colliding constraints, parks immediately, and asks the operator a question written scenario-first with zero code identifiers. Architectural decisions with no in-code precedent get the same treatment; everything else the judge resolves itself. When the operator answers a requirements conflict, the machine derives the minimal edits to the story's acceptance criteria, shows the exact diff as a follow-up proposal, and applies it only on confirmation (#1415) -- so a ruling becomes the record instead of a side-channel the next run re-fights.

- **AI resolve can no longer convert its own success into "merge conflicts."** The resolution loop re-ran a rebase after every agent completion, and when the workstream had legally advanced meanwhile, the redundant pass's bookkeeping transition was refused -- which the flow escalated into a forced rollback that relabeled a rebased, build-green, pushed branch with an open PR as conflicted (#1411). The loop now recognizes a finished rebase and exits once; the success path reads current state and treats already-advanced as done; and the crash rollback only rewinds the one state resolve owns, through a validated transition instead of a raw status write. Resolution leftovers are stashed before the build gate so the gate verifies the tree that ships. Alongside: resolve narrates its progress honestly (#1399), survives semantic breaks after clean rebases by escalating through the test ladder (#1400), and the merge-gate rebase closes its silent-clobber channel (#1396).

- **Structural commands refuse while a worker is live.** Replan, reset, edit-commit, add-commit, skip and resolve-oscillation could all rewrite a workstream's plan or run structure out from under an executing agent -- the worker would then commit a plan that no longer existed, or resurrect one the operator had replaced (#1408). Every structural verb now shares one busy guard: a stamped runner substage confirmed by liveness refuses the mutation with the reason, parked states accept it, and a drift test pins that every verb offered is a verb accepted. Reset out of a closed state clears the closed metadata (#1410 hardened the feedback scope the same way).

- **Team servers: agents log in per user, on every surface.** Credentials register per user and inject into agent subprocesses at run time (#1389), with health tracked on the row so a dead credential fails the next dispatch fast, pointing at re-registration. The TUI settings modal edits them (#1391), and the web Settings panel joins it (#1413) -- credential rows, login flows, per-user authorization on every endpoint, secrets never echoed. Spawned runner chains authenticate with an internal service token, killing the off-loopback 401 that silently dropped agent-invocation registrations on TLS installs (#1404, #1397).

- **Operator guidance is one-shot in fact, not just in schema.** The v45 one-shot contract claimed rulings via an UPDATE -- executed on a read-only database handle, where it failed every single time, silently re-feeding every consumed ruling to every later run (#1414). The claim now runs on its own short-lived write connection while reviewers keep their read-only doctrine. The same PR fixed `OpenReadOnly` applying its pragmas to one pooled connection out of four -- three of the four were silently writable -- and hardened the DSN against URI-breaking path characters.

- **Chat is a first-class conversation with server-executed actions** (#1394, #1403): sessions persist, actions dispatch through the same mutation surface as every other client, and the web gate answers CLQs inline (#1375).

- **Clients survive the restarts they used to sit out.** The TUI re-resolves its base URL and token on every SSE reconnect and reports stream state per failure class -- "reconnecting" for transient, actionable text for terminal -- instead of a bare "server disconnected" forever (#1409). The Temporal sidecar moves its store to WAL, ending the sqlite seizure that killed every in-flight agent box-wide (#1388). Connector-host Python resolution survives restarts (#1385).

- **The runner tells the truth about failure.** Agent failures classify from the structured envelope before any prose matching, so a 401 parks as an auth gate naming the credential instead of a generic stage death (#1393). Repeated identical build failures climb an escalation ladder to a judge instead of re-dispatching forever (#1395). A dead CAS guard on plan writes is gone (#1392), and REQS burn-down consumes requirement prose exactly once, in the right order, without fusing adjacent lines (#1402).

- **Story editing converges on one gated path** (#1384): AC edits queue behind a live run instead of racing it, and a resumed run picks up the operator's guidance in its next cycle (#1383). The commit stage no longer auto-pushes past the operator's publish gate (#1382); the TUI edits and answers stories in place (#1381).

- **Claude stages move to claude-opus-5** across all 24 agent stages, with the light stages on claude-sonnet-5.

- **Operator papercuts and display honesty**: workstream detail regressions restored (#1380), assorted operator papercuts (#1379), PR review findings fold into reject prefill including body-only findings (#1378), pre-cut operator truth fixes (#1377), and the resolve/conflict-pane pair from the 2026-08-04 incident (#1386).

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.22...v0.9.23

## v0.9.22 - 2026-07-31

v0.9.22 is an operator-truthfulness release. A parked workstream driven by hand on v0.9.21 surfaced a cluster of surfaces that reported state confidently and wrongly -- a suspended run described as busy, a finished commit's attempt shown as current, a gate reason rendered beside a live stage -- and each one is fixed at the source that produced the wrong reading rather than at the surface that displayed it. Alongside them: the web Changes tab becomes a real diff browser, operator guidance goes back to being consumed once instead of applying forever, and the ZMQ retirement finishes, taking a `hashd watch` preflight failure and a dead dependency with it.

### What's Changed

- **Operator guidance is consumed once again, not forever.** A rejection or replan instruction written by an operator rode every subsequent review prompt for the life of the workstream -- so feedback kept steering reviews long after it was addressed, and a replan instruction read as an open order long after the breakdown regenerated the plan around it. The original Python reader deleted the feedback file after reading it; the Go port read without deleting, and the later move into the database faithfully carried that drift. Guidance is now claimed by the run that picks it up (visible to every cycle of that run, absent from the next) and rows are marked rather than deleted, so the full history stays available to the scope judge. Schema v45, with a forward migration pair and a populated-database test.

- **A resumed gate no longer leaves its run row parked.** A gate signal resumes the same run, but only the workstream was transitioned back -- the run row kept `status=blocked`, its `awaiting_human_approval` reason, the review-exhaustion message and an `ended_at` from the previous day. Every surface reading that row repeated it, so a workstream four minutes into a fresh review displayed a gate reason, an exhaustion message and a stale start time beside a working loop. The row is now repaired first and unconditionally, in a single transaction with its payload, guarded so a failed or completed run is never resurrected by a late signal.

- **Parked workstreams stop reporting a suspended run as busy.** `hashd run` on a parked workstream answered "this operation is already running" and advised waiting for it to finish -- it had executed nothing for eighteen hours, and it was waiting for the operator being told to wait for it. The live attempt display also showed a finished commit's "attempt 5/5" while the runner was on the next commit's first pass, because progress was scoped by a field that is empty on a signal-resumed run and fell back to treating unattributed events as current. The commit in flight now comes from the plan, unattributed events are skipped, and the messages distinguish an open workflow from a running one.

- **The detail panel shows the timeline while work runs.** The right panel defaulted to `run.log` whenever work was active, and that file had lost roughly thirty of its narration call sites in the port -- a twenty-hour run producing four commits left eighteen lines, all of them banners. Rather than adding a third store for the same fact, active work now defaults to the timeline, which is already recorded in the events table, survives a disconnect and reaches a remote client. Idle still defaults to the review verdict. Stage-change lines also stop rendering with a dangling colon.

- **Changes tab: browse a workstream's diff, one file at a time.** A scope selector picks the whole branch or a landed micro-commit, a toolbar steps through "N of M files" with the change type, and a read-only Monaco editor renders the selected file in unified or split view. A cursor model keeps it cheap -- only the selected file's two sides are fetched, so a 200-file branch costs the same per view as a 2-file one -- and degraded states name the actual condition (a micro-commit that landed nothing, an unfetchable side, an oversized file refused before its bytes are read) instead of rendering an empty pane that reads as a deleted file.

- **`hashd watch` works on a clean local install.** The TUI preflight probed for a running ZMQ forwarder, which a post-broker box does not have, so the normal state read as a down service and the TUI refused to start with "Down: ZMQ forwarder". Only remote mode escaped it. The probe is gone, and `pyzmq` -- still a declared dependency with no importer anywhere -- is dropped from the client wheel. The forwarder reaping in `restart` stays: it drains a leftover forwarder from a pre-broker install, which is upgrade behaviour.

- **Install and client-mode fixes.** Upgrading a machine paired to a remote server no longer dies provisioning a local owner it does not need, and a schema lag now suggests the one command that fixes it instead of burying it. Installing the wheel over a source install detects the prior install's ops root and names `HASHD_OPS_ROOT` before replacing anything, rather than presenting a populated ops root elsewhere as total data loss. `PATH` is written to the login-shell profiles as well as `~/.bashrc`, so `ssh host 'hashd ...'` resolves on exactly the boxes remote mode is for. README states that the installer is the supported path and why a direct `pip install hashd` fails.

- **Smaller operator-facing fixes.** `run.log` timestamps drop to second resolution. `HASHD_WEB_ADDR` overrides the web UI's bind address, so a box still holding `:8099` from a previous local install can forward a remote box's UI elsewhere. `hashd stop` says plainly that it is always local and never reaches a paired remote server. A preview-mode prompt render no longer consumes operator guidance, which it had been spending on an inspection.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.21...v0.9.22

## v0.9.21 - 2026-07-30

v0.9.21 reorganizes the story-facing CLI -- a breaking change -- and carries a batch of install/upgrade and diagnostics fixes surfaced by multi-box manual testing and a live production incident.

### BREAKING: story-scoped verbs move from `plan` to `story`

One rule, applied absolutely: if the operation takes a story id, it lives under `story`; if it works the suggestion pool, it lives under `plan`.

| was | is |
|-----|-----|
| `hashd plan retry` | `hashd story retry` |
| `hashd plan edit` | `hashd story edit` |
| `hashd plan split` | `hashd story split` |
| `hashd plan clone` | `hashd story clone` |
| `hashd plan edit-ac` / `delete-ac` / `descope-ac` / `rescope-ac` | `hashd story edit-ac` / `delete-ac` / `descope-ac` / `rescope-ac` |
| `hashd plan resurrect` | removed (deprecated tombstone) |

`plan` keeps the backlog surface: `discover`, `list`, `show`, `claim`, `status`, `reset`, and the ad-hoc creators `plan story` / `plan bug` (they take a title and create a story -- entry points into planning, not operations on an existing story). Old spellings fail with the standard unknown-command suggestions; scripts using the moved verbs must update.

### What's Changed

- **Story edits get a realistic time budget.** `stages.pm_edit.timeout` default rises 300s -> 900s (`pm_edit_resume` 300s -> 600s), matching `pm_refine`. Folding clarification answers into a large story is refine-class work; the old budget killed real edits mid-flight and parked the story at `draft_failed`.
- **Upgrades crossing a schema bump no longer deadlock.** `setup.sh` migrates the databases before anything opens them; previously owner provisioning hit the schema check first, setup died after a successful build, and its advice (`hashd restart`) pointed back at `setup.sh` -- a loop whose only exit was buried. Related: `db` open errors now point at `hashd internal migrate-dbs` instead of the loop.
- **Source builds report their real version.** A build-file scoping bug stamped every source build `dev`, which also made `hashd doctor` warn that a source server and wheel client were "built from different source trees" on matched pairs. Versions now stamp correctly, `task build VERSION=x` is honored, and doctor compares release identity rather than string spelling -- a source build genuinely ahead of the tag still warns.
- **Remote clients stop consulting local state they don't own.** `hashd project use` validates against the server (it rejected server-known projects from a remote client); a remote client no longer silently adopts a leftover local project as context, no longer deletes a server-validated saved selection, and the no-project diagnostic names the paired server instead of advising `project add`. A moved ops root (wheel install over a source install) now explains itself instead of presenting as total data loss.
- **Diff reads survive worktree reclaim.** `/diff`, `/diff/changes`, and `/diff/blob` fall back to the project repository once a merged or closed workstream's worktree is gone -- committed history stays readable, working-tree modes are rejected with precise diagnostics, and abbreviated commit SHAs are accepted. An unprovisioned or reclaimed worktree is an honest 400, not a git failure dressed as a 500.
- **Failure diagnostics carry the actual cause.** Agent-error messages keep their tail instead of being head-truncated (the part that says *why* it died lives at the end of agent output); auth failures lead with their classification (`agent_needs_login` vs a missing or rejected API key); `run_failed` events record the failure reason (`failed at review: <reason>`) instead of just the stage; and a reject that auto-resumes the flow prints exactly one next step instead of two contradictory ones.
- **A stuck review loop can no longer grind, and an operator ruling now binds.** A workstream rejected the same micro-commit ten times across two loop exhaustions while the convergence guard never fired: it watched only `major` findings, while `major` AND `minor` both reject a review, so a minor-driven reject produced an empty set and the guard skipped itself. It now watches every blocking finding, keyed on text so an objection re-raised at a different severity still counts as a repeat. Separately, a reject delivered at the review gate persisted nothing -- the reviewer's guidance section was empty on every later cycle while the implementer cited that ruling as its authority. Rulings now persist durably, scoped to the commit under review, reach every implement attempt rather than the first, survive the self-heal escalation, and carry standing in the review prompt distinct from an implementer's claim.
- **The retry budget is visible while it burns.** Loop events carry their position (`review_changes (attempt 2/5)`), the workstream read exposes the attempt in flight beside the after-the-fact exit record, and `hashd show` renders `review (attempt 3/5)`. Previously the numbers existed on the wire at every layer and reached no surface, so a workstream on its last attempt looked identical to one on its first.
- **`hashd workstream adjudicate`** -- a human-invoked, read-only scope judge for a review that will not converge. When a reviewer and an implementer deadlock over *where* work belongs rather than what it should do, the judge rules `IN_SCOPE` / `OUT_OF_SCOPE` with a citation, or returns `CANT_TELL` with a briefing. It never rules on functionality, never mutates the workstream, and is not wired into the runner: the operator runs it, reads it, and decides.
- **Agent retries emulate Claude Code's backoff.** The retry delay was a flat 5 seconds three times -- exponential in shape only, since the multiplier was 1 -- and a `Retry-After` from the server was clamped *down* to 5s. Backoff is now genuinely exponential with jitter, `Retry-After` is honored, and nested retry ladders no longer multiply into nine agent launches for a three-attempt policy. Upstream capacity failures (429/503/529) are classified as such and surfaced as an upstream incident rather than an unexplained stage failure.
- **Operator guidance is a durable record, not a file.** Rejection and replan guidance move from a JSON file in the ops tree into the database, attributable to a user and scopable to a story or commit. The file was invisible to a remote client and could not survive a workstream being recreated; existing files are migrated forward.
- **TUI:** story-detail and dashboard layout fixes, and the workstream timeline is coloured again -- its palette had been styling an event vocabulary the server stopped emitting, leaving a failure, a retry and a routine state change rendered identically.
- **The pre-commit secret scanner actually scans.** The private-key patterns begin with `-----BEGIN`, which grep parsed as options; every scan silently passed. Also: the hashd-web Go module is now linted by both the commit hook and the push gate.
- **Web:** the story page shows the workstream run's health; remote docs cover fingerprint-mismatch recovery on a single host and scripting over non-interactive SSH.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.20...v0.9.21

## v0.9.20 - 2026-07-29

v0.9.20 is a single-fix patch release for team-mode operators: `hashd restart` no longer breaks a box that is paired to a hashd-server running on another machine.

### What's Changed

- **`hashd restart` works on a box paired to a remote server.** On a client paired to a team server, restart derived its *listen* address from the configured *server* URL and tried to bind the server box's IP, failing with `bind: cannot assign requested address`. Because that aborted the start phase, it also left hashd-web stopped -- so the documented recovery command left the box with neither a local server nor a web UI, and the per-user web on a client box could never reach the team server. Restart now asks whether the configured endpoint is an address this machine can actually bind. When it is not, it skips Temporal, the local server and the project migrations, and restarts only what a thin client owns: hashd-web (pointed at the remote, carrying the server's cert pin) and the Telegram daemons. A box that hosts its own server -- including one deliberately bound to its external IP for team mode -- is unaffected.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.19...v0.9.20

## v0.9.19 - 2026-07-28

v0.9.19 is a reliability and internals release. A batch of fixes surfaced by the multi-user petshop soak hardens the runner, merge, and human-gate paths, and stage-timeout handling is consolidated into a single authority so operator timeout overrides -- including for the PM and discovery workflows -- take effect consistently.

### What's Changed

- **Stage-timeout handling consolidated.** The five separate resolvers for a stage's effective timeout collapse into one authority, and the single-shot PM/discovery workflows (planning, discovery, add-commit, detect, describe, edit) now derive their activity timeouts from project config -- so raising a stage timeout past the old hardcoded value takes effect instead of being silently capped.
- **Soak-surfaced reliability fixes.** Stage sub-processes are reaped by process group, a killed worker is caught via restart 401-liveness, the read-only review/judge stages retry infra blips (Tier A), `already_done` is handled for the plain-format claude agent, and abandoning a story releases its claimed suggestion.
- **Human gate and story-run gating.** Review-loop exhaustion parks at the human gate instead of failing the run, the park reason is surfaced on the operator surfaces, and the web/TUI story-run offer is gated on `runtime_status` and run-eligible workstream stages.
- **`project remove` cleans up its artifacts.** Removing a project now hard-deletes its orphaned workstream and run log trees, so the filesystem parallels the database removal instead of stranding unreferenced trees.
- **Side-by-side diffs.** New server `/diff/changes` and `/diff/blob` endpoints back side-by-side diff views.
- **Model and agent version bumps.** The Codex default model moves to gpt-5.6-sol (GPT-5.6 flagship), and the documented agent minimums update to Claude Code 2.1.220 and Codex CLI 0.145.0.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.18...v0.9.19

## v0.9.18 - 2026-07-27

The hashd CLI becomes a pure REST client. The server now owns all project state
-- repositories, config, prompts, and every AI agent run -- so the CLI never
touches SQLite, Temporal, or the filesystem directly, and every command works
identically whether the server is local or a remote team host.

### What's Changed

- **The server owns each project's repo.** `hashd project add` registers a
  project's repository at a canonical server-side path (a symlink for a local
  add, a clone for a remote one), and every agent run and git operation resolves
  through it. `hashd project remove` unlinks the server's own link but preserves
  a pre-existing clone or ingested repo -- it never deletes your working tree.
- **AI agent runs moved server-side.** describe/tech suggestion, the multi-repo
  project-add describe map-reduce, and `hashd project repo edit --suggest` now
  run as server-orchestrated Temporal workflows; the CLI dispatches and awaits
  the result over the event stream instead of invoking an agent itself -- so they
  work unchanged in team mode.
- **Prompts, doctor, cost, and completions are server-backed.** `hashd prompts`
  reads and edits prompts through the server, `hashd doctor` runs its checks
  server-side, `hashd cost` accepts a git ref the server resolves, and
  project-name tab completion lists projects over REST -- the last client-side
  ops-directory reads are gone.
- **Unified abandon/close teardown.** Abandoning or closing a story or workstream
  now cascades cleanup through one server-side path, fixing an orphaned-worktree
  case for in-flight stories.
- **Team-mode and petshop-soak reliability fixes.** A batch of fixes surfaced by
  the multi-user petshop soak, including team-mode edge cases in planning and
  merge.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.17...v0.9.18

## v0.9.17 - 2026-07-24

hashd gets a web UI. Install hashd and it's there -- after `hashd restart` it's
served at http://localhost:8099/ui, started and supervised alongside the server
with no separate process to run. Server-side-rendered views of your projects,
plans, stories, and workstreams with the same operator actions as the CLI,
curl-drivable end to end and keyboard-accessible.

### What's Changed

- **A web UI, shipped and auto-launched.** hashd-web ships inside the hashd
  install (binary and source) and comes up with `hashd restart` / `hashd start`,
  health-checked and reaped like every other hashd service -- you never launch or
  manage a separate binary. It prints its URL on start.
- **Dashboard, plan, stories, and workstreams in the browser.** Server-side-
  rendered pages mirroring the TUI/CLI: suggestions plus REQS/SPEC editing on the
  plan page, the stories and workstreams lists and their detail pages, with the
  human-gate verbs (approve / reject / run / merge) wired in.
- **Single-user and team, both supported.** Solo mode needs no login; team mode
  adds per-user sign-in with a session cookie, and the live event stream is fanned
  out per user.
- **Accessible and curl-drivable.** WAI-ARIA tabs, menus, and fields with keyboard
  operation, and every page and action is reachable by curl via structural hooks
  (no reliance on JavaScript) -- the same surface the operator smoke and the
  petshop soak drive.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.16...v0.9.17

## v0.9.16 - 2026-07-23

Three reliability fixes from the v0.9.15 petshop soak: a crashed story now
surfaces an actionable error, a killed server no longer leaves an agent running
loose, and add-commit tells you how to build the commit it queued.

### What's Changed

- **A crashed story now shows an actionable error, not a blank "crashed".** When
  planning or an edit fails a story into `draft_failed` (for example a git push
  to an unreachable remote), the reason -- including the retry command -- now
  appears in `hashd show STORY-x`. Previously it read `FAILED (crashed)` with no
  error, while the real diagnostic sat only in a stage-log file.
- **A killed server no longer leaves an agent running unsupervised.** Agent
  subprocesses now die with the server (`Pdeathsig`, held reliable across the
  fork), and a startup sweep SIGKILLs any agent orphaned by a hard crash before
  resuming work -- so a resumed run can't race a leftover agent over the same
  worktree.
- **`add-commit` points you at the next step.** The confirmation now says to run
  `hashd run <ws>` to build the queued commit, instead of looking like a stuck
  workstream (add-commit plans the commit; you run to implement it).

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.15...v0.9.16

## v0.9.15 - 2026-07-23

A soak-reliability patch: a leaked subprocess can no longer wedge a run, a story
being edited can no longer be approved out from under the edit, and a bare-box
install fails fast when git is missing.

### What's Changed

- **A leaked test or agent subprocess can no longer wedge a run.** Every runner,
  agent, hook, forge, and network-git command now bounds how long it waits on
  its output pipe after the deadline (`cmd.WaitDelay`). A project test command
  that leaves a background listener holding the pipe -- or an agent that spawns a
  surviving MCP or credential-helper child -- returns within seconds of the
  timeout instead of blocking the substage until the housekeeping sweep reaps it.
- **Approving a story mid-edit is rejected, not silently reverted.** Answering
  clarifications dispatches an edit; approving while that edit is still in flight
  now fails fast with an actionable diagnostic instead of "succeeding" and then
  being undone when the edit lands the story back at draft.
- **`install.sh` fails fast when git is missing.** git is a system prerequisite
  hashd shells out to (and never bundles); on a bare box the installer now stops
  up front with the OS-correct install command instead of running to completion
  and surfacing the gap only at first `doctor`.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.14...v0.9.15

## v0.9.14 - 2026-07-22

Remote project add lands: you can bring a project onto a hashd server you don't
share a filesystem with, pull it back down, and promote a no-remote project to a
real git remote. Plus a round of Temporal soak-reliability fixes and the Sonnet
5 model default.

### What's Changed

- **Remote project add (`hashd project add` against a remote server).** Land a
  repo on the server three ways -- `--clone <https-url>` (server-side clone with
  an encrypted per-user forge token), `--bundle` (upload a local repo), or
  `--create` (start empty) -- plus `hashd project download` to pull a
  server-owned repo back, and `hashd project set-remote` to promote a no-remote
  project onto a real git remote. Every server-side git network op is
  SSRF-guarded (public-host-only, DNS-rebind- and redirect-proof), and forge
  tokens are encrypted at rest (AES-256-GCM).
- **Encrypted forge token store.** Per-user forge tokens are sealed at rest and
  resolved CLI-first for single-user / token-based for teams, via `hashd forge`.
- **Soak-reliability fixes.** A hung git or test subprocess during merge can no
  longer stall a substage past its timeout; a crashed run no longer pins
  `runtime_status` at `running` (the stale-invocation reaper is now actually
  scheduled); merge no longer strands WIP markers when an annotation block is
  empty; and the `loop_triggered` transcript line now names its real trigger.
- **Agent auth failures are classified, not retried.** An agent that fails
  authentication surfaces an actionable diagnostic instead of being retried as a
  transient error.
- **Sonnet 5 for review stages.** The review / adjudicate / concern-triage
  stages default to `claude-sonnet-5`.
- **Login robustness.** Shell-completion sourcing is guarded so a missing binary
  can't break `hashd` login; the forge-aware `merge_mode` default no longer omits
  the mode for multi-repo doctor.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.13...v0.9.14

## v0.9.13 - 2026-07-20

Soak-hardening on top of the Temporal engine: a batch of fixes for issues the
v0.9.12 petshop soak surfaced -- broken operator-recovery paths, silent async
failures, and lingering one-off HTTP clients -- plus the ZMQ retirement and
per-project artifact edit locks.

### What's Changed

- **Runner-wedge recovery.** `hashd close --force` no longer returns 422, `hashd
  skip` works on real (heading-format) plans instead of 409ing every time, `hashd
  skip -m` records a durable reason, and `replan -> run` regenerates the plan
  instead of dead-ending at preflight.
- **Workstream/story lifecycle fixes.** `hashd run` on a concerns-flagged
  workstream points at `hashd reject` instead of dead-ending at the merge gate;
  closing a workstream now releases its linked story instead of stranding it at
  `implementing`; and WIP-marker cleanup on abandon no longer strands markers
  under concurrent REQS writes.
- **Team-mode TLS + telemetry.** The teardown-hook and grep-redirect calls now go
  through the standard fingerprint-pinned, authenticated client instead of bare
  HTTP clients that failed strict TLS against the LAN certificate in team mode.
- **Async operation surfacing.** Add-commit declines and other async operation
  outcomes now surface on the story detail and workstream list via a reusable
  `operation_result` event, and the agent-driven `plan split` render bug is fixed.
- **ZMQ retired.** The ZMQ forwarder is replaced by an in-process event broker;
  hashd-server is the sole publisher and bridges directly to SSE.
- **Per-project REQS/SPEC edit locks.** Editing REQS or SPEC takes a Temporal,
  event-driven FIFO lock so concurrent writers (planning, story-edit, docs, the
  TUI editor) don't clobber each other, with a read-only SPEC viewer in the TUI
  artifacts menu.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.12...v0.9.13

## v0.9.12 - 2026-07-17

The Temporal release. Prefect is gone: hashd's entire execution engine -- the
workstream runner, planning, merge, discovery -- is reimplemented as Temporal
workflows and activities, and with execution off Python, the orchestration layer
is demolished. Work now survives Ctrl-C and full-stack restarts by construction.
Alongside the engine swap: per-user story and workstream ownership, and a round
of install and diagnostic hardening.

### What's Changed

- **Temporal replaces Prefect as the execution engine.** The runner is rebuilt
  as Temporal workflows + activities and cut over incrementally -- activities and
  the inner/outer cycle (#1254 onward), reads, wiring, and engine-gating flipped
  behind it (#1266, #1268), native retry and the tier-B heartbeat model, then the
  engine flipped Temporal-only (#1282). Pinned to temporal-server 1.31.2 (#1287),
  with a workflow janitor + retention sweep (#1288), a schema-compatibility guard
  (#1290), and the payload/transport ceilings raised to the real limit (#1286).
  Work survives disconnect and restart because the sidecar persists it.

- **The Python orchestrator is demolished.** With Temporal owning execution, the
  Prefect/Python orchestration layer is deleted (#1284); the connector host and
  chat surface move to Go, and path validation goes Go-native (#1283). No PR
  increases net Python.

- **Per-user story and workstream ownership.** Stories and workstreams carry an
  owner; a guard stops one user acting on another's work, assignment is explicit,
  and the owner shows through the CLI and the watch TUI (#1277, #1278, #1280).

- **Source install works end to end.** A from-scratch source install was broken
  by ordering (tools installed after the step that needed them) and a dead
  first-install path; both fixed, plus the forge CLIs (gh/glab/bkt/tea) are now
  vendored by the shared installer so source installs get them too (#1291, #1292).

- **add-commit and first-run onboarding.** add-commit no longer strands or drops
  work (a refused commit is surfaced, not appended; one added at ready_to_merge
  returns the workstream to active), clarification answers are attributed
  honestly, `project add` reminds you to set a setup hook, and a missing agent
  warns instead of failing the install (#1293).

- **`hashd show` renders the detail it already had.** Provisioning diagnostics,
  pending clarifications, and error detail now show in the plain view instead of
  only in `--json`; a merged workstream stops flagging its removed worktree
  (#1294).

- **Reliability and fixes.** AI merge-conflict resolution legs (#1281),
  tech-tree resume fallback (#1276), petshop-validation fixes (#1279),
  release-surface cleanup (#1285), and a bot-view prompt-lint pass (#1289).

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.11...v0.9.12

## v0.9.11 - 2026-07-09

The plumbing release. The Go server becomes the single writer of record for
workstream state; the CLI, TUI, bot, and connectors move onto a shared
hashd-client SDK with the watch TUI as a pure viewer; migrations run through a
Go runner; and Telegram gains self-service per-user pairing. Mostly invisible
from the outside, but it is the foundation the team-server story stands on.

### What's Changed

- **One writer of record: the Go server owns every state mutation.** Commit
  hash-chains and run records (#1225), then clarifications, story transcripts,
  and workstream-id allocation (#1226), then the clarification / plan-split /
  run-transcript writes (#1227) all move behind the server -- no process other
  than the server writes the database. The events schema is synced and a
  generate-drift gate plus clarification-flip events close the residue (#1228,
  #1229), and the dead Python review parser is deleted. This shuts the last
  split-brain window where a Python helper and the server could both touch the
  same rows.

- **A shared `hashd-client` SDK; the watch TUI is a pure viewer.** The client
  logic is extracted into a reusable SDK (#1234); the TUI (#1235) and the
  Telegram bot plus connectors (#1236) cut over to it, and every transitional
  shim is deleted. The TUI now renders server state and dispatches through the
  SDK with no authority of its own, so local and remote mode share one client
  path.

- **Migrations run through a Go runner.** Schema and runtime migrations move to
  a Go migration runner with M000-M017 frozen as the baseline, and the old
  Python migration framework is deleted (#1237). Migrations apply the same way
  whether the trigger is a database open or a restart.

- **Telegram: self-service per-user pairing.** A user pairs their own Telegram
  account to the server and receives a per-user scoped token minted at
  provisioning, with a two-sided bind -- no operator hand-holding, and every
  action is attributed to the user who took it (#1232).

- **Client/server hardening.** A wire-contract handshake refuses a connection
  when the client and server disagree on the event contract (with a Diagnostic
  that points at the upgrade command), `hashd doctor` checks the contract before
  the version, the request header carries the build version, and agent
  retry-budget caps are pinned in lockstep with the retry logic (#1230).

- **Reliability and infra.** Fixed three live bugs -- a housekeeping cancel
  path, worker liveness, and the remote agent check (#1222). The ZMQ event-bus
  forwarder is reimplemented in Go with structured subprocess diagnostics
  (#1224). `hashd` now runs the tool copy it installed or fails loudly instead
  of silently falling back to `PATH` (#1233). The two cross-language
  review-prompt seams are pinned against drift (#1223).

- Internal: tombstone phrasing swept out of the user-facing docs (#1231).

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.10...v0.9.11

## v0.9.10 - 2026-07-06

Remote and team-server mode, made real. Driving a hashd-server from another
machine over TLS worked in pieces but fell apart at the one step that matters --
restarting the server -- and was undocumented. This release fixes the restart
path, adds a one-command way to onboard a teammate, and ships the manual that
explains how to run hashd for more than one person.

### What's Changed

- **`hashd restart` supervises an off-loopback TLS server instead of killing
  it.** When the server listens on a LAN address it serves HTTPS with a
  self-signed certificate and requires a bearer token on every request --
  including the health probe the restart supervisor uses. The supervisor sent a
  tokenless plain-HTTP probe, read the connection failure as "server dead," and
  tore the server down on every restart. It now probes with the resolved token
  over TLS, pinning the server's persisted certificate fingerprint, and the
  probe never writes TLS material. This was the last thing standing between
  "remote mode works" and "remote mode works after a restart." (#1218)

- **`hashd admin user add` mints a per-user access token.** Adding a user now
  returns a single token that carries both the bearer secret and the server's
  certificate fingerprint, so a teammate pairs with one
  `hashd server set <url> --token <token>` -- no separate certificate step and
  no second command. The token is attributed to that user even in solo mode.
  Full autocomplete and `--help`; the `admin` command group stays hidden. (#1218)

- **Remote and team-server mode are documented.** New `docs/REMOTE.md` covers
  the trust model (self-signed cert + fingerprint-in-token pinning, off-loopback
  fails closed), making a server reachable, provisioning users, pairing a
  client, the optional password-login path, and troubleshooting. README and
  QUICKSTART gain real onboarding sections for all three shapes -- solo-local, a
  shared server, and the unmanaged solo-shared-repo layout -- and the E2E plan's
  remote phase is now an executable mirror of that manual. (#1219)

- Internal: the release tooling's run-finder tolerates a local clock running
  ahead of GitHub (a WSL2 cut no longer dies waiting for a dispatched run it
  cannot see), and a comment records why the automatic TLS certificate is reused
  across listen-host changes rather than regenerated -- regenerating would change
  the pinned fingerprint and break every already-paired client. (#1220)

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.9...v0.9.10

## v0.9.9 - 2026-07-05

The butter release: a day of hunting operator-experience bugs end to end.
Quitting the watch TUI is instant instead of a 6-second stall, restarts no
longer leak event-bus daemons, upgrades stop re-running first-install
ceremony, and an operator-level smoke suite now drives hashd the way a
human does so this class of bug gets caught before it ships.

### What's Changed

- **Quitting `hashd watch` is instant.** Every quit (and project switch)
  stalled ~6.3 seconds: the event subscriber's stop path closed the SSE
  response to interrupt a blocked read, but closing a file descriptor does
  not wake a thread parked in recv() -- only a socket shutdown does. stop()
  now shuts the raw socket down first. Measured through the real TUI:
  6.35s before, 0.33s after. (#1215)

- **`hashd restart` no longer leaks event-bus daemons.** Every restart
  stacked a fresh ZMQ forwarder pair on top of the old one (the pid file
  named a process whose group id did not exist, so the stop silently killed
  nothing), and a superseded pair's eventual exit deleted the live pair's
  socket files -- silently killing real-time updates for the TUI, Telegram,
  and web. Stops now resolve the real process group, cleanup only removes
  files it still owns, and a sweep converges boxes that already accumulated
  strays back to exactly one forwarder on the next restart. (#1207)

- **Upgrades stop re-running first-install ceremony.** `setup.sh` now
  detects a working install and: never rewrites your per-stage agent
  assignments (previously it re-applied the default to all stages on every
  upgrade), no longer hard-fails on missing golangci-lint (a lint tool is
  needed to contribute, not to run hashd), and closes with an upgrade
  summary instead of "register your project" onboarding copy. (#1208)

- **Schema-gate errors say what they looked at.** "schema checkpoint behind
  source" now names the exact ops root, checkpoint file, and both versions,
  plus a HASHD_OPS_ROOT hint -- so a stale leftover install can no longer
  produce an undebuggable refusal. (#1210)

- **Operator-level smoke suite, wired into every release.** A hermetic
  harness boots a fully isolated hashd instance and drives it the way an
  operator does: `hashd watch` under a real pty (paints, owns the terminal
  foreground, quits clean), restart lifecycle (the forwarder-leak detector
  is a hard gate), an event-bus roundtrip, and a no-TTY contract table.
  Runs via `task smoke` locally, and every release candidate must now pass
  it -- plus a Tier 3 upgrade gate that installs the previous release,
  populates it with state, upgrades to the candidate, and asserts the
  server comes back healthy with the owner and data intact.
  (#1209, #1214, #1216, #1217)

- Internal: release tooling fails a cut with missing release notes in
  seconds instead of after the full CI pipeline, and stops compiling
  toolchain binaries just to record their version strings (~2.5 minutes
  saved per release). Code generators write atomically so parallel build
  chains can no longer truncate a generated artifact. Release builds
  actually reuse their Go module and C-compile caches across cuts (the
  Go cache restore was silently failing; the ccache directory died with
  the runner). Test-suite hygiene: TUI tests no longer leak a fake server
  URL across tests (the suite dropped from 112s to under 4s) and the api
  dispatch tests no longer sleep through production retry backoffs
  (70s to 38s cold). (#1206, #1212)

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.8...v0.9.9

## v0.9.8 - 2026-07-05

Fixes the two ways a working install could go dark: `hashd watch` freezing on
a blank screen at launch, and upgrades stranding a solo server that then
refused to start.

### What's Changed

- **`hashd watch` no longer freezes at launch.** Since v0.9.0 the CLI started
  the Python TUI in its own background process group (for clean Ctrl-C
  group-kill), but never handed it the terminal foreground -- and a TUI in a
  background group suspends itself waiting for an `fg` that never comes. The
  operator saw a frozen blank screen before the first paint, in local and
  remote mode alike. The launcher now starts the TUI's process group as the
  terminal foreground group and takes the terminal back when it exits; Ctrl-C
  reaches the TUI directly. Scripted / non-tty invocations are unchanged.
  (#1205)

- **Upgrades can no longer strand a solo server without an owner.** A
  solo-mode server that starts with no active user now self-heals by
  provisioning the implicit owner (derived from git config, the same way the
  installers do) instead of failing closed. A leftover non-active row for the
  same email is promoted, not collided with. Manual source upgrades
  (git pull + rebuild + restart) get a speed bump: a bare `hashd restart`
  that is really an upgrade asks for `--yes` so it isn't mistaken for a
  routine restart, and the installers hard-fail if owner provisioning fails
  instead of leaving a dead server behind. Team mode still fails closed on
  missing identity. (#1204)

- **One event surface for the watch TUI.** The TUI now consumes the server's
  SSE stream in local mode too, instead of opening its own ZMQ socket --
  local and remote share one code path, and the footer indicator now says
  "server disconnected" honestly. Remote mode also gains a client/server
  version banner: when the connecting CLI's build differs from the server's,
  the status line flags it in red (banner only, never blocks). (#1203)

- **Autonomous runs no longer park on final-review concerns.** In autonomous
  mode a final-review `CONCERNS` verdict now feeds a bounded self-heal loop
  (matching how the per-commit qa-gate already auto-continues) instead of
  stopping the unattended run at the first concern. Gatekeeper and supervised
  behavior are unchanged. (#1201)

- **Quieter doctor and install output.** Dropped the per-tool "dev-only;
  skipped in packaged install" noise, the raw schema version number in
  `hashd status` (only a mismatch is actionable), and other non-actionable
  chatter. (#1202)

- Internal: dead Python swept out (net -322 lines). (#1200)

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.7...v0.9.8

## v0.9.7 - 2026-07-02

Fixes the fresh-macOS binary install: `hashd`/`wf` now land on the zsh PATH,
completions work, and the bundled secret scanner no longer trips a timeout on
first run.

### What's Changed

- **Fresh macOS installs work end to end.** The binary installer wired PATH and
  shell completions only into `~/.bashrc`, which macOS Terminal (zsh) never
  sources -- so `hashd`/`wf` read as command-not-found and `hashd <TAB>`
  completion did nothing. The installer now writes the managed PATH + completion
  blocks to `~/.zshrc` too (on macOS, or when the login shell is zsh), including
  the entry-points directory. Linux and bash behavior is unchanged.

- **gitleaks no longer times out on first run.** The bundled secret scanner is now
  warmed once at install time -- paying macOS's one-time Gatekeeper cost up front
  -- and ad-hoc-signed with its quarantine attribute cleared, so `hashd doctor`'s
  dependency check passes on the first run instead of being killed by the probe
  timeout. That per-check timeout is also raised to 1s as a backstop.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.6...v0.9.7

## v0.9.6 - 2026-07-02

Makes provisioning fail loud when a fresh worktree can't run its toolchain, and
surfaces auth and mode in the watch dashboard.

### What's Changed

- **Baseline gate fails loud on a missing toolchain.** When a fresh worktree can't
  launch its configured test/build runner -- exit 126/127 or an exec launch error,
  e.g. a local-toolchain project whose dependencies aren't reachable from the
  worktree -- provisioning now stops at `provisioning / failed` with an actionable
  diagnostic (make the runner resolvable from a fresh worktree, or configure a
  `hooks.setup` install) instead of silently passing and surfacing the failure
  cryptically a few commits later. A legitimate greenfield non-zero exit (no tests
  yet) still passes.

- **Watch dashboard shows auth and mode.** The `hashd watch` dashboard header now
  surfaces the server's authentication surface and deployment mode.

- **Docs use the canonical `hashd` command.** QUICKSTART and the product docs now
  reference `hashd` throughout instead of the legacy `wf` alias (the alias still
  works).

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.5...v0.9.6

## v0.9.5 - 2026-07-01

Attributes work to the user who did it (team mode), and lets the implementer resolve
non-regression test conflicts it previously stalled on.

### What's Changed

- **Work is attributed to the acting user.** Stories, workstreams, suggestions, and
  clarification answers now record which user created or acted on them, backed by
  `user_id` columns on the core work items; existing unowned items are backfilled to
  the host owner. In team mode this makes "who did what" queryable. Solo mode is
  unaffected.

- **Legitimate test conflicts no longer stall the implementer.** When a failing test
  is judged a non-regression -- your change is fine, but the failure comes from a
  superseded test or an environmental/setup/harness issue -- the implementer is now
  explicitly authorized to fix that root cause, even in a file outside the current
  commit, while keeping the fix tightly scoped. Previously it documented the fix but
  wouldn't make it, and the commit looped to exhaustion.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.4...v0.9.5

## v0.9.4 - 2026-07-01

Adds multi-user / team-server identity, and finishes the local-only merge story so AI
conflict resolution works without a remote.

### What's Changed

- **Multi-user identity and team-server mode.** hashd now supports real users. A host
  provisions accounts (users table + host-local provisioning); a new user completes setup
  with a self-service password (replacing the shared setup key); and `hashd login` exchanges
  that password for a user-scoped bearer token. Deployment modes make it explicit: **solo**
  stays the default -- one implicit user, no auth ceremony, exactly like today -- while
  **team** enforces per-user identity on every request. Existing single-user setups are
  unaffected.

- **AI conflict resolution works on local-only repos.** `hashd merge --ai-resolve` assumed a
  git remote and aborted immediately (without ever running the resolver) on a project with
  no `origin`. It now rebases against the local base and resolves locally, matching the
  local-merge support added in 0.9.3.

- **Reviewers see the implementer's scope reasoning.** The per-commit reviewer can now read
  the implementer's optional `reason` (why work was deferred -- e.g. "tests belong to a
  later commit") and is told to verify it against this commit's scope rather than guess, so
  it stops docking confidence on deferrals it had to infer.

- **Completed requirements are captured verbatim at merge.** When a story merges and its
  requirement block is removed from REQS.md, hashd now records a durable `requirement_burned`
  event holding the exact original wording, the consuming story, the completion timestamp,
  and (when REQS.md is git-tracked) the source commit -- so the full history of completed
  requirements is queryable instead of being discarded on burn-down.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.3...v0.9.4

## v0.9.3 - 2026-06-30

A follow-up to 0.9.2 that restores local-only merges and makes a declined breakdown
recoverable.

### What's Changed

- **Local-only merges work again.** A project with no git remote couldn't merge -- the
  pre-merge rebase/test safety gate added in 0.9.2 unconditionally fetched `origin` and
  aborted when there wasn't one. It now sources the latest base locally when no remote is
  configured, so the same rebase-onto-latest-then-retest gate runs for local and remote
  projects alike.

- **A declined breakdown is now a recoverable operator decision, not a dead end.** When the
  breakdown step declines to break a story down, it blocks with the agent's reason and a
  proceed/hold choice -- `hashd answer <ws> proceed` to build it anyway, or `hold` to fix
  the story first -- instead of failing with an opaque "no JSON" error. The step is also
  clearer that REQS work-in-progress markers are internal bookkeeping (not a "not ready"
  signal) and that a plan carrying more detail than REQS is expected.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.2...v0.9.3

## v0.9.2 - 2026-06-30

A follow-up to 0.9.1 that fixes a review-loop stall on stories that span more than
one micro-commit.

### What's Changed

- **Micro-commit reviews no longer stall on deferred work.** The per-commit reviewer
  scored its confidence against the *whole story's* acceptance criteria, so an early
  micro-commit that legitimately leaves some criteria to later commits (for example,
  validation handled in its own commit) couldn't reach the confidence bar and looped
  through implement/review until it exhausted its attempts. The micro-commit reviewers now
  score against the commit's own scope -- story acceptance criteria are shown for context,
  and criteria a commit isn't responsible for no longer lower its confidence or raise
  findings. The whole-branch final review still verifies every acceptance criterion before
  merge.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.1...v0.9.2

## v0.9.1 - 2026-06-30

A focused follow-up to 0.9.0 that unblocks autonomous end-to-end runs on a clean
install, brings live streaming to Codex chat, and repairs several agents' headless
commands.

### What's Changed

- **Breakdown no longer refuses ready stories.** A persona line shipped in 0.9.0 told
  the breakdown stage to "refuse to break down a story that isn't ready" -- and on a
  requirements-anchored project it read hashd's *own* internal WIP markers (which claim a
  region of REQS for an active story) as a human "not ready" signal and refused,
  dead-ending the run before any code was written. That directive is reverted so breakdown
  proceeds normally; a readiness check with proper, surfaced refusal handling will return
  in a later release.

- **Merge gate finds the bundled gitleaks.** The mandatory secret-scan merge gate searched
  for `gitleaks` on `PATH` only, so a fresh install -- where the installer places gitleaks
  in hashd's own tools directory rather than on `PATH` -- failed every merge with "install
  gitleaks" even though it was already present. The gate now resolves bundled tools the same
  tools-dir-first way the rest of hashd does (honoring `$HASHD_TOOLS_DIR`, falling back to
  `PATH`).

- **Codex chat reaches parity with Claude.** The in-TUI thinking-partner chat now streams
  Codex replies token-by-token over the app-server transport, and Codex gains the read-only
  hashd MCP tool to query project state over that same transport -- bringing it to
  co-primary parity with Claude for chat.

- **Agent fixes across the fleet.** Gemini's headless invocation is fixed and live-verified
  so it runs non-interactively again; OpenCode's non-chat shapes no longer emit broken
  flags; and `_resume` stages now inherit their original base agent (covered by a live Codex
  regression test), so a resumed stage runs on the same agent it started on.

- **Internal robustness and cleanup.** hashd resolves which Python interpreter its
  subprocesses use through a single shared resolver, fixing divergence for non-default
  virtualenvs, and a batch of orphaned Python modules plus dead, uncalled functions was
  removed (a net reduction of roughly nine hundred lines).

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.9.0...v0.9.1

## v0.9.0 - 2026-06-29

A major release on three fronts: hashd now runs as a real **client/server** (CLI and
TUI on one machine, the server on another, over the internet, securely); the in-TUI
**AI thinking-partner chat** moved onto the server with live streaming that survives
disconnects; and the tool itself is now **`hashd`** (`wf` lives on as an alias). Plus
durable PR reviews and uniform agent permissions.

### What's Changed

- **Run hashd remotely, securely.** Point the CLI and TUI at a server on another box with
  `hashd server set https://host:1337 --token <token>` -- set it once and every command and
  the TUI follow. Same-machine use is unchanged: loopback stays fully transparent, with no
  auth or setup. The server auto-generates its own TLS certificate and `hashd auth create`
  mints a single pairing token that carries the certificate's fingerprint, so the client
  trusts it by pinning -- no CA files, no OS trust-store edits. Off-loopback is fail-closed:
  the server refuses to bind to a public address without TLS, and every remote request needs
  a valid bearer token. Manage tokens with `hashd auth {create,list,delete}`.

- **The CLI is now `hashd`.** The command renamed from `wf` to `hashd`; `wf` and `ha` remain
  permanent aliases, so existing muscle memory and scripts keep working. Pure rename, no
  behavior change.

- **AI chat / thinking-partner, now server-side and first-class.** The in-TUI chat runs on
  the Go server and streams the reply live, token by token, over SSE -- and generation is
  detached server-side, so you can drop the connection and reconnect, replay, or resume
  mid-turn (built for remote/SSH use). It auto-injects the right context for the scope (a
  story chat loads that story's diff, commits, review, clarifications, and timeline; a
  project chat loads its stories and workstreams) and resolves `@`-references server-side --
  `@diff`, `@file`, `@story`, `@commits`, `@review`, `@reqs`, `@spec`, `@timeline`, and
  connectors `@github` / `@jira` / `@figma`. The agent can propose story edits for you to
  confirm and apply, and has a read-only hashd MCP tool to query project state. In the answer
  box, `Ctrl+G` opens a clarification assistant that drafts an answer (refining your current
  draft if you've started one) for you to edit and submit -- nothing is ever sent on your
  behalf. Works across all seven agents (Claude, Codex, Gemini, Qwen, Copilot, OpenCode,
  Kimi) with per-agent live streaming and session reuse on resume.

- **Durable PR reviews.** Rejecting a PR no longer closes it and opens a fresh one -- the
  same PR gains a FIX commit and is reused, preserving review threads, resolutions, and bot
  incremental reviews across cycles. hashd reads forge review threads (GitHub, GitLab,
  Bitbucket, Gitea) with their resolution state, keeps a durable finding ledger, and feeds
  only still-open findings forward; it never marks a finding resolved itself -- the reviewer
  does. Late final-review concerns are now posted as PR comments.

- **Uniform agent permissions.** Each stage's tool-permission intent (read-only vs. write,
  shell access) is declared once and rendered to each agent's own flags, instead of being
  hand-maintained per agent -- fixing drift such as a review-resume that wasn't actually
  read-only. Agents without a native read-only mode (OpenCode, Kimi) are explicitly flagged
  as best-effort.

- **A thinner, server-owned core (the foundation for remote).** The Telegram bot and TUI are
  now database-clean -- clients reach the server over REST and SSE, never the database
  directly. Crash/health recovery is native in the Go server (the redundant Python monitor
  is gone), housekeeping sweeps and project-config reads moved server-side, forge PR/MR
  operations run through the server, and project Telegram config is served over REST.

- **Installer and tooling.** The installer shows per-wheel download progress and retries
  transient fetch failures (no more silent hangs or a single CDN blip aborting the install),
  and vendors the forge CLIs (`gh`, `glab`, `bkt`, `tea`) into hashd's own tools directory;
  its version parser no longer misreads `tea`'s build-metadata line, fixing aborted installs.
  A REQS.md viewer/editor opens with `R` from the TUI dashboard. Hyphenated project names are
  valid end to end, and `project add` preserves the build commands it detects.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.8.7...v0.9.0

## v0.8.7 - 2026-06-19

### What's Changed

- New `wf project` views surface a project's REQS and SPEC artifacts directly,
  so you can read the requirements and spec a project is working against without
  leaving the CLI.
- `wf` is far more responsive to interruption: it now exits promptly on Ctrl-C
  and SIGTERM instead of hanging, renders friendly, actionable diagnostics for
  bad arguments instead of a bare usage dump, and its shell completion works even
  on machines without the `bash-completion` package installed.
- `wf restart` is now a careful neighbor: it only stops processes hashd itself
  launched, and when a foreign process is holding a hashd port it tells you which
  one instead of killing it.
- `wf watch` no longer goes down with the server -- a dead or half-dead server
  surfaces as an error state in the TUI instead of crashing it.
- Hardened the boundary between the clients (`wf`, TUI, Telegram bot) and the
  server -- groundwork for running the server on a separate, eventually
  multi-tenant, host. The CLI now routes every call through a single cancellable
  HTTP path that reports clearly when a remote server is unreachable, and the
  Telegram bot gained the same CI-enforced "no direct database access" guard the
  TUI already enforced.
- Fresh installs now deliver `gitleaks` and `git-delta` and converge on an honest
  `wf doctor` that reports what is actually installed and authenticated. `wf
  project add` runs and classifies your configured test and build commands at
  setup time -- catching a broken toolchain before the first story instead of
  hours in -- and adds a Gitea on-ramp.
- Project discovery now runs on Sonnet instead of Opus: faster and cheaper for a
  step that does not need the larger model.
- Internal hardening: pinned every GitHub Action in the dev and back-merge
  workflows to commit SHAs (matching the release workflow) to close a
  supply-chain gap, removed dead Python now that the work moved to Go (the
  `prompt_registry` and the `timeline` mirror, ~760 lines, both superseded by
  Go-canonical paths), and made the pubsub tests self-heal stale runtime
  directories.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.8.6...v0.8.7

## v0.8.6 - 2026-06-18

### What's Changed

- Onboarding now works on a bare machine in one command. `curl … | install.sh`
  bootstraps a Python 3.11+ runtime via `uv` when none is present, so a fresh Arch
  or macOS box no longer dead-ends on a missing Python or a PEP-668 pipx wall. The
  installer output is quieter and clearer, errors carry the one OS-correct fix, and
  it finishes by running `wf doctor` and pointing you at your first project.
- Fixed installs that died with "No wheel found": wheels are now fetched from
  direct release CDN URLs instead of the unauthenticated GitHub API, which a fresh
  box (no `gh` yet) could exhaust at 60 requests/hour.
- Drew an honest dependency boundary: hashd needs `git` and an AI agent CLI; Python
  is handled by `uv`, and Node is documented as the agent CLI's prerequisite, not
  hashd's. The README now leads with the install command, and `wf doctor` guides you
  through installing and authenticating an agent.
- Trimmed the published docs to a curated, customer-facing set (internal design and
  planning papers no longer ship), moved QUICKSTART and the workflow reference to the
  front page, and hid the internal `wf upgrade` command (it runs data migrations,
  not a self-update) from the CLI surface.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.8.5...v0.8.6

## v0.8.5 - 2026-06-17

### What's Changed

- Fixed an install/startup crash for returning users. hashd shares the global
  `~/.prefect` database, so a machine whose `~/.prefect` was stamped by a newer
  Prefect (including hashd's own earlier install) crash-looped under the pinned
  older Prefect -- surfaced only as an opaque "health check timed out". Bumped the
  Prefect pin to 3.6.29, the newest pre-3.7 release, whose schema reads and
  forward-upgrades those databases; the FastAPI/Starlette web stack stays frozen
  at the proven-booting versions.
- `wf restart` and Prefect auto-start now surface the real server-start failure
  (tailed from the Prefect log) instead of a bare timeout, and point at the
  `PREFECT_HOME` workaround when the database was written by a newer Prefect.
- The TUI diff view now works out of the box: `git-delta` (pinned 0.19.2,
  SHA-verified) is auto-installed by both source setup and packaged installs and
  resolved from `~/.hashd/tools/bin`, so it is no longer a manual package-manager
  prerequisite.
- Release/vendor tooling: the bundled codebase-memory-mcp bump is now manual-only
  (dropped the weekly auto-bump) and mirror-aware (DeusData canonical, codr1
  mirror), with a release-time staleness nudge in the cut script.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.8.4...v0.8.5

## v0.8.4 - 2026-06-17

### What's Changed

- Closed the commit gate's biggest hole: a red micro-commit can no longer land.
  Exhausted test/build failures terminate instead of falling through to commit,
  the qa and human-review gates verify the test outcome and fail closed, and a
  failure caused by an earlier commit self-heals with reframed guidance instead
  of grinding.
- Reworked test-conflict escalation onto a single breakdown engine: the Tier-2
  architect/replanner became a partial breakdown, the oscillation guard now
  fires correctly and detects the same concern recurring across runs (not just
  within one run), and red-test conflicts are adjudicated against the
  requirement.
- `wf reject` now folds the review gate's own findings into the next attempt by
  default -- with provenance and recurring-concern framing -- so iterating no
  longer means re-typing what the reviewer already said. Reset/replan/reject were
  unified onto one engine and their feedback moved to a consistent `-f` flag.
- Lifted model and reasoning-effort out of agent command strings into
  declarative `model`/`effort` config, added per-stage agent retries with honest
  timeout reporting, attributed the harness-reported model, and gave the
  implementer the story's business goal as orientation.
- Added planning observability and recovery: see what is blocking planning,
  auto-heal orphaned planning state, and a `/plan/reconcile` endpoint with
  `wf plan reset`.
- Fixed cloned stories failing to load by declaring clone metadata fields and
  making the story loader tolerant of unknown server-written `data` keys, so
  future server-side fields can't crash it. Story `depends_on` is now validated
  at accept time.
- Reworked onboarding around the system rather than the command list, made
  Claude the universal default with `wf agents --suggest` and gatekeeper
  autonomy, and improved `wf project add`/describe with docs-first prompts and
  multi-repo role framing.
- Hardened fresh installs across platforms: pinned the Prefect/FastAPI/Starlette
  trio to a tested set (a fresh resolve was landing on a broken Starlette 1.x),
  dropped the installer's `awk` dependency for minimal Fedora, and moved the
  bundled codebase-memory-mcp binary onto a hashd-controlled fork.
- Smaller fixes: derive Prefect task timeouts from config, find the venv Python
  on dev-rig installs, a Telegram retry command for draft-failed stories,
  flow-status discovery by tag, and an in-place elapsed/cap timer for long AI
  steps.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.8.3...v0.8.4

## v0.8.3 - 2026-06-10

### What's Changed

- Fixed macOS release tooling by using `python3` in cbm lock parsing and bump
  automation.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.8.2...v0.8.3

## v0.8.2 - 2026-06-10

### What's Changed

- Fixed Apple Silicon cbm startup by forcing ad-hoc signing onto a fresh inode.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.8.1...v0.8.2

## v0.8.1 - 2026-06-09

### What's Changed

- Fixed planning retry recovery for suggestion-derived stories whose suggestion
  was already self-owned or done.
- Improved macOS cbm packaging by ad-hoc signing the bundled cbm binary.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.8.0...v0.8.1

## v0.8.0 - 2026-06-09

### What's Changed

- Replaced the native code-index backend with cbm-backed `wf code` and MCP code
  tools, including telemetry, prompt routing, and grep-redirect experiments.
- Made cbm lifecycle safer across workstreams: fixed list-project parsing,
  cross-project reconciliation, restart preservation, and telemetry writes.
- Added server-derived current errors and transitional dispatch status so
  summary surfaces show current operator state instead of stale history.
- Hardened startup and runtime recovery by cancelling orphan Prefect flows and
  sweeping stale active invocations before resume reconcilers run.
- Moved more TUI actions to REST, removed local-path consumers from screens,
  surfaced workstream clarifications, and gated actions from server-provided
  availability.
- Fixed repeated Rich markup failures in TUI status/log panels by escaping
  untrusted content at the formatter boundary.
- Restored optional client-side git-delta diff rendering for side-by-side,
  syntax-highlighted, word-level diffs.
- Improved project onboarding with narrated `wf project add`, editable detected
  git identity, and nested .NET solution detection.
- Added automatic merge-gate recovery for regenerated rebase conflicts and
  framed/contaminated fix-generation parser hardening.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.7.11...v0.8.0

## v0.7.11 - 2026-06-01

### What's Changed

- Unwrapped agent response text consistently before downstream parsing.
- Fixed workstream feedback project routing.
- Warned on planner file references outside the project.
- Made merge failures recoverable.
- Removed orphaned implement history prompt content.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.7.10...v0.7.11

## v0.7.10 - 2026-06-01

### What's Changed

- Added story split breakdown flow and plan-split wheel packaging.
- Flattened reviewer verdict schema and fixed review verdict consumers.
- Added review session resume, review observability CLI surfaces, acknowledged
  concern lifecycle, and final review history context.
- Fixed stale conflict-resolution state surfaces, TUI Rich bracket escaping,
  review feedback selection, TUI review schema display, and approval resume.
- Improved prompt composition documentation and fix-cycle prompt coverage.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.7.9...v0.7.10

## v0.7.9 - 2026-05-28

### What's Changed

- Added tech tree planner backend and TUI plan rendering.
- Made story-run claims transactional.
- Allowed ad-hoc planning without REQS anchors and extended the policy to edit
  flow.
- Checked auto-resolved rebase builds before continuing.
- Rendered auto-skipped implementation stages as success in `wf show`.
- Added final review deletion-reversal evidence and artifact-edit deterrents.
- Consolidated blocked suggestion rendering and moved tech-tree toggle hints to
  the footer.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.7.8...v0.7.9

## v0.7.8 - 2026-05-28

### What's Changed

- Self-healed accepted stories at implementation finalize.
- Sharpened plan discovery prompt behavior.
- Locked tech tree architecture and terminology.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.7.7...v0.7.8

## v0.7.7 - 2026-05-28

### What's Changed

- Added merge-gate secret scanning with gitleaks.
- Added JSON output for `wf show` and `wf list`.
- Added bounded review verification and richer review schema diagnostics.
- Ported final branch review to Go and consolidated FSM contracts in Go.
- Added wait flags for merge and answer workflows.
- Surfaced workstream blocked reasons and review fields in display surfaces.
- Improved OAuth/auth detection for Claude, Kimi, and Qwen.
- Hardened release wheel source retention with KEEP_FILES drift checks and
  globbed Prefect parameter schemas.
- Improved WSL filesystem diagnostics and chmod tolerance.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.7.6...v0.7.7

## v0.7.6 - 2026-05-26

### What's Changed

- Kept `deployment_refresh.py` as source in wheels so restart/doctor
  subprocess module execution works after install.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.7.5...v0.7.6

## v0.7.5 - 2026-05-26

### What's Changed

- Switched consumers to server-provided available actions and added FSM guard
  coverage for PR, merge, and replan flows.
- Preserved final review feedback and reshaped concern lifecycle handling.
- Improved final-review context by injecting authoritative stage results and
  test-stage evidence.
- Guarded terminal states from accidental rewrites.
- Forbade workflow-owned artifact edits and bounded implementation summaries.
- Escaped review/TUI markup and added fallback rendering for malformed Rich
  markup.
- Fixed `wf open`, `wf show` gate display, fuzzy 404 suggestions, stale merge
  toasts, timeout blocked-event duplication, and release workflow secret
  handling.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.7.4...v0.7.5

## v0.7.4 - 2026-05-22

### What's Changed

- Moved TUI and Telegram bot into separate installable subpackages and restored
  connector entry-point packages.
- Added connector host boundary and connector package discovery.
- Added transcript table storage, run-dir blobs, UTC event timestamps, and
  Go-routed ledger events.
- Fixed multi-repo worktree rooting and cross-repo provisioning defects.
- Improved release safety with DOA install gates, wheel smoke scripts,
  release-merge-before-tag behavior, ccache for wheel builds, and Python module
  execution checks.
- Added project-add single-repo flags, merge-gate/test command sync, and Go
  build environment setup in source installs.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.7.3...v0.7.4

## v0.7.3 - 2026-05-21

### What's Changed

- Redesigned release process around candidate CI, fresh checkout gates, pinned
  actions, and automated main-to-dev back-merges.
- Added `wf version` and `wf flow status`.
- Moved prompt transport to stdin and hardened prompt retry tests.
- Fixed wheel contract data packaging and first-run install/doctor UX.
- Added editing timeout recovery and edit-flow cleanup.
- Handled ZMQ forwarder restarts in `wf watch`.
- Hardened Prefect startup, work pool setup, and fresh-install restart gates.
- Added real install DOA gates and tzdata handling for packaged installs.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.7.2...v0.7.3

## v0.7.2 - 2026-05-20

### What's Changed

- Completed the review-stage migration to Go, including retry layers,
  cancellation handling, persistence, and deletion of the Python review path.
- Cut over detect parsing and execution through Go.
- Consolidated suggestion lifecycle writes through Go.
- Added release prepare/execute commands and offline OpenAPI regeneration.
- Added Gitea forge support.
- Fixed wheel `python -m` entrypoint source retention, install/doctor first-run
  UX, planning log-dir validation, and task build failure checks.
- Aligned GitHub and Jira connectors with the reference connector contract.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.7.1...v0.7.2

## v0.7.1 - 2026-05-18

### What's Changed

- Added system-wide stage-use defaults.
- Extracted and restored shared chat engine behavior while honoring repo skip
  gates.
- Backported release wheel smoke tests and synced OpenAPI output with the live
  server runtime.
- Dropped a stale wheel smoke requirement for `migrations/runner.py`.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.7.0...v0.7.1

## v0.7.0 - 2026-05-15

### What's Changed

- Added derived workstream runtime status and documented the canonical
  workstream state model.
- Added implementing, merging, and provisioning substages with timeout
  failsafes.
- Began the Go agent-runner migration for PM, route, concern triage, review,
  and related agent stages.
- Added structured diagnostics, parser drift contracts, and richer operator
  help for failure cases.
- Improved planning, REQS, and suggestion flows with drift handling, blocked
  suggestion display, queued planning cancellation, and planning retry reasons.
- Added remote-watch data-source seams, SSE/ZMQ coverage, TUI reconnection, and
  clarification action visibility.
- Hardened restart, Prefect, git-lock, runner shutdown, and auto-resume paths.
- Improved project setup and detection with build-system registry, test/merge
  command handling, project-add suggestions, and half-initialized project
  recovery.
- Fixed release/wheel packaging for migrations, Pydantic models, docs flow
  deployment, and fresh-checkout safety.

**Full Changelog**: https://github.com/codr1/hashd/compare/v0.5.10...v0.7.0
