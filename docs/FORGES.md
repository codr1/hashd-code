# Forge Adapter Contract

What a forge backend under `server/internal/forge/` must do. It is written for someone adding a backend or fixing one, and it describes the code as it is: where a backend does not conform or cannot express something, section 5 says so.

Core has one forge-neutral model and vocabulary: the most common generic term for each concept (merge a PR, a reviewer's review state of approved, changes_requested, commented or none, unresolved threads, username). A forge backend is the only place that knows its forge's API, words, enums and rules; it maps them into the generic model and may carry the raw value verbatim (for example `forge_review`) for display only. Core decisions read the generic fields, never a raw forge value. Forge paths stay separate from connectors. A design or PR that couples core to one forge's view of the world is raised to the operator before it lands.

## 1. Where a backend is wired

- `forge.go`: the `Forge` interface and the shared types. `requirements.go`: requirement rows, reviewers, the review and decision vocabularies.
- `factory.go` `New` and `credentials.go` `NewAuthenticated` construct a backend by forge type; `config.ForgeHosts` (`server/internal/config/forge_hosts.go`) is the one list of types and the hosts that detect them.
- A CLI backend runs its vendored CLI through `authenticatedCLI` (`credentials.go`) and names it in `forgeBinaries` (`exec.go`); a REST backend asks a `CredentialSource` for every request.
- `push_refusal.go` `protectedPushSignatures`: the forge's wording for a refused direct push.
- Tests that hold every backend to the contract: `forge_parity_test.go`, `review_vocabulary_test.go`, `completion_test.go`.

## 2. The interface

Every call ends with its `ctx`; each forge call inside it is bounded by `deadline.APIFailsafe`. The call-count bounds are constants in `forge.go` (`StatusReadCalls`, `ReviewThreadReadCalls`, `ReviewVerdictReadCalls`, `CommentReadCalls`, `ChecksReadCalls`). Field-level detail is in the Go doc comments; this table is the obligation.

| Method | Obligation |
|---|---|
| `CheckAvailable` | Says whether the backend can reach the forge with its login. A missing CLI or an absent or rejected login is an answer (`ok` false, `err` nil). A check that was cut off or could not reach the forge is `err`, and then `ok` says nothing. |
| `GetPRStatus` | One normalized `PRStatus` (section 3). A failed read sets `Error` and nothing else is to be read. |
| `PRNumberFromURL` | Reads this forge's PR web URL for the repository, with no forge call. Not this forge's URL, or another repository's, is a refusal (`refusePRURL`); any other error is a failure to verify. Core never parses a forge URL. |
| `FindExistingPR` | The open PR for a branch against a base, if one exists. |
| `CreatePR` | Creates the PR with the whole body. A forge that takes a shorter description continues it in comments; it is never cut. A create refused because one exists wraps `ErrPRAlreadyExists`. |
| `CompleteAdoptedPR` | Brings a PR that a publish adopts up to the whole body the publish would have created it with. A forge that continues a shorter description in comments posts, in order, the parts the PR does not already carry, and changes nothing already on it; a forge whose description takes the whole body makes no forge call. A part not delivered, or not confirmed delivered, is an error naming the missing text. |
| `MergePR` | Completes the PR as `MergeOptions` asks. Options the backend cannot honour are refused before any forge call through `Capabilities().Check`. |
| `SetAutoMerge`, `ClearAutoMerge` | The forge completes the PR once its own policies pass; clear withdraws that, and is a success when none is set or the PR is no longer open. An already-merged PR seen before the write is `*AutoMergeCompleted`. No auto-merge: `*UnsupportedError`. |
| `Capabilities` | What the backend can honour, with no forge call: merge strategies, source-branch deletion, whether the status read lists every reviewer's review (`ReviewStates`), whether the thread read expresses resolution (`ThreadResolution`), completion modes, and the `review.bot_identities` fields its reads fill. |
| `PostPRComment`, `HasPRComment` | Post a top-level comment; report whether a comment with exactly that body exists, reading every comment. A failed read is an error, never false. |
| `ClosePR` | Closes without merging and posts no comment. Already closed is a success. |
| `ReopenPR` | Reopens a closed, unmerged PR. Already open is a success. Only `ErrPRReopenRefused` lets the caller create a replacement. |
| `FetchPRFeedback` | Review and line comments as `FeedbackItem`s. |
| `ListReviewThreads` | Review threads with a forge-stable `ID`, `IsResolved` and `IsOutdated`. A backend that cannot express resolution reports `IsResolved` false, so the thread is treated as open, and says so through `Capabilities().ThreadResolution` and the read's `resolutionUnread`. Every thread root is returned, one per thread and never a reply, a blank-bodied root included; an adapter whose readiness contract does not judge a root marks it `ReadinessExempt` (GitLab and Bitbucket, for a blank root; Bitbucket, for a general PR discussion), and no findings surface shows it. A thread whose status the forge reports unknown sets `ResolutionUnknown` (Azure DevOps): readiness reads it open, the attention badge does not count it. A listing the backend cannot read fails the read, never an empty result. |
| `ListReviewVerdicts` | One current verdict per reviewer who answered, never a review log, each dated by `CommitOID` where the forge dates it. Nobody answered is an empty result; a failed read is an error. |
| `ReadRequiredChecks`, `RerunCheck` | Section 6. No checks operations: `*UnsupportedError`. |

Writes return nil on success and the backend's own message on failure. A write the forge never answered is an `*OutcomeUnknownError` (matches `ErrOutcomeUnknown`; a CLI backend builds it with `writeError`), a call killed by its deadline matches `ErrTimedOut`, and a 429 from a REST backend is a `*ThrottledError`. The backend never waits and retries itself: the caller reads the forge and retries (`mergeflow.runForgeWrite`).

## 3. The vocabulary

**`PRStatus`.** `State` is `open`, `merged` or `closed`. `Mergeable` is false for every reason the forge withholds a merge; `Conflict` is true only when the branch must be rebased or its conflicts resolved. `MergeBlocker` names any other reason as `"<Forge>: <reason>"`. `HeadSHA` is the commit the PR points at (it may be abbreviated: compare by prefix). On a merged PR, `MergeCommit`, `MergedHeadSHA`, `Strategy`, `SquashCommit` and the `MergedBy*` fields carry what the forge's own read establishes; empty is "not reported", never a failure, and a requested strategy or a later branch head never stands in. `AutoMerge` is the forge reporting it will complete the PR. `ChecksStatus` is `success`, `failure`, `pending`, `none` (nothing to wait for) or empty (unknown, never ready).

**Requirement rows (`PRRequirement`).** One row per gate the forge evaluates.

- Kinds: `build`, `status_check`, `min_reviewers`, `required_reviewers`, `comment_resolution`, `work_item_link`, `merge_strategy`, `other`.
- States, a closed set: `satisfied`, `not_applicable`, `pending`, `failing`, `expired`, `not_queued`, `unknown`. `ForgeState` keeps the forge's own value verbatim.
- `Blocking` with `BlockingKnown`: a row whose blocking is not known is treated as blocking.
- `Requirements` with `RequirementsRead` true is the forge's complete list, so an empty list means no requirements. A backend that leaves `RequirementsRead` false is judged on `ChecksStatus`, `ReviewDecision` and `MergeBlocker` (`mergeflow.aggregateRequirements`), and on a `Policies` row `mergeable` in state `unknown`, which is how such a backend reports mergeability not computed yet; its other typed rows go in `Policies`, which only the `forge_autocomplete` rule reads.
- A backend that fills `Requirements` computes `ChecksStatus` with `ChecksStatusFromRequirements`, so the aggregate and the rows cannot disagree.
- Reserved row ids: `mergeable` (`RequirementMergeabilityRowID`) and `pipeline` (`RequirementHeadPipelineRowID`).

**Reviews.** A review is `approved`, `changes_requested`, `commented` or `none`; the PR's overall decision is `approved`, `changes_requested`, `review_required` or `none`. A `PRReviewer` row is one requested or answered reviewer, groups included, with `ForgeReview` verbatim, `ReviewHeadSHA` where the forge dates the review (an undated review never counts toward approval), `IsBot` where the forge declares it, and `NotCounted` naming why a review cannot count.

**Threads and verdicts.** `ReviewThread.IsResolved` is the forge's resolution and `IsOutdated` is the forge saying the code under the thread moved; an unresolved thread counts whether or not it is outdated. The forge owns resolution: hashd never resolves a thread.

**Thread resolution support.** `Capabilities().ThreadResolution` says the backend's `ListReviewThreads` reads each thread's resolution from the forge. A backend whose read reaches hosts that differ declares it, and a read whose host reports no resolution answers `resolutionUnread`, whether or not any thread came back; `ThreadResolutionRead` combines the two for one read. The PR watch records that answer with each snapshot that read the threads (`PRWatchSnapshot.ThreadResolution`), so a later read trusts an unresolved thread without a forge call. Supported reads: GitHub (`isResolved` on the review threads query), GitLab (`resolved` on a discussion's resolvable note), Azure DevOps (the thread status) and Bitbucket Cloud (a comment's `resolution`; bkt's listing names the workspace) and Gitea. Only Gitea's token read has complete conversation evidence: it reads the review API itself and returns each conversation (file, diff side, line and, on the new side, commit) as one thread: its root, with the root's `resolver` and the replies' text after the root's. A tea-managed login reads through tea's review-comment listing, which keeps the login's proxy, SSH signing and certificate modes but carries no diff side or commit: a comment there is resolved only on its own `resolver`, every other comment reads open, and the read answers `resolutionUnread`. A Bitbucket Data Center listing, which names a project, shapes its comments differently and exposes no resolution, fails the thread read. A backend that reads a review log collapses it with `currentReviewVerdicts`; a dismissed review is `none`. `Requests` carries every non-empty changes-requested body, each with its own commit.

**Bot identities.** `review.bot_identities` is applied once, at the forge resolver (`WithBotIdentities`). A backend declares in `Capabilities().IdentityFields` which of `display_name`, `username`, `id` its reads fill; a rule on any other field is refused naming the forge.

**Merge options.** Strategies are `merge`, `squash`, `rebase`, `rebase_merge`; completion modes are `hashd`, `forge`, `forge_autocomplete`, `person`. `forge` needs a status read that lists each reviewer's review and a merge call that holds `ExpectedHead`; `forge_autocomplete` needs those and an auto-merge that honours the options. A merge refused because the head moved is `HeadMovedError`. `Capabilities().Check` is the one rule: settings writes, merge dispatch and every `MergePR` run it.

**Protected push.** `ProtectedPushRefusal` recognizes a remote's own refusal to update a protected branch directly, from the wordings in `protectedPushSignatures`. Each wording names only that refusal: a generic hook decline, a moved remote or a refused credential carries none of them. That list is the only place a forge's wording lives.

## 4. Situations a backend must recognize

Fill one row at a time. "Core" says what reads the value.

| Situation on the forge | What the backend reports | Core |
|---|---|---|
| The read failed | `Error` (and `Cause` when a credential source failed) | Never read as "not approved" or "no requirements" |
| Branch conflicts with its target | `Conflict` true | Automatic rebase |
| Merge withheld for any other reason | `Mergeable` false, the reason as a blocking row or as `MergeBlocker`; never `Conflict` | Not-ready stop naming the reason |
| Mergeability not computed yet | A blocking row id `mergeable`, state `unknown`: in `Requirements`, or in `Policies` when `RequirementsRead` is false | When it is the only blocking reason the merge waits and asks again (`mergeflow.awaitsMergeabilityOnly`); any other shape is a not-ready stop |
| Draft | A blocking row, state `pending` | Blocked |
| A required check passed, failed, is running, was never started, expired | A `build` or `status_check` row in that state | `ChecksStatus` and the readiness verdict |
| A check that is not required | Row with `Blocking` false, `BlockingKnown` true | Listed, never decides |
| A native state the backend's table does not know | State `unknown`, never `satisfied`; `ForgeState` verbatim | Never ready |
| No per-requirement facts in the read | `RequirementsRead` false, the aggregates filled | Judged on the aggregates |
| The forge's own reviewer rule | A `min_reviewers` or `required_reviewers` row | The approval decision; hashd does not recount |
| A reviewer answered, or was asked | A `PRReviewer` row, dated where the forge dates it | Counted only when dated at head, not a bot, not `NotCounted` |
| A review thread is resolved, or its code moved | `IsResolved`, `IsOutdated` | Unresolved threads are readiness reasons; the findings ledger follows the forge's two flags |
| A review was superseded or dismissed | One current verdict per reviewer; dismissed is `none` | A superseded change request does not block |
| A verdict the forge does not date | Empty `CommitOID` | A note, never an error |
| Facts of a completed merge | The merged fields of `PRStatus`, empty where not established | Landing evidence |
| An operation the forge lacks | `*UnsupportedError`, before any call | A fact, not a failed call |
| A write the forge did not answer | `*OutcomeUnknownError` | Read, then retry |
| A direct push to a protected branch refused | Its wording in `protectedPushSignatures` | The archive's and the requirements writer's protected-branch refusal |

## 5. What each backend does today

| | GitHub | GitLab | Bitbucket | Gitea | Azure Repos (`azuredevops`) |
|---|---|---|---|---|---|
| Transport | `gh` | `glab` (reads through `glab api`, v4) | `bkt` | `tea` | REST, no CLI |
| Requirement rows | Complete (`RequirementsRead`): every check and status with whether it is required, the review decision, draft, mergeability | Complete: head pipeline, and each non-conflict `detailed_merge_status` as a row | None; aggregates only | None; aggregates only | In `Policies` only (`RequirementsRead` false): each blocking, enabled, applicable policy evaluation, the merge check, draft |
| Checks status | From the rows | From the rows | From the head's build statuses; none reported is `none` | Always `none`: the read carries no commit status | From blocking build policies; none is `none` |
| Conflict | `mergeable` is `CONFLICTING` | `conflict`, `need_rebase` | Never reported: the read carries no conflict field, and an open PR reads mergeable | An open PR whose `mergeable` is false | `mergeStatus` is `conflicts` |
| Mergeability not computed | Conforms: row `mergeable`, `unknown`, while `mergeable` is `UNKNOWN`; `Mergeable` stays true | Conforms: `checking` and `unchecked` are row `mergeable`, `unknown`, the status verbatim as its forge state, and a `MergeBlocker`; `Mergeable` is false | Cannot express | Cannot express: a false `mergeable` is read as a conflict | Conforms: `queued` is a `Policies` row `mergeable`, `unknown`, read by readiness, with no `MergeBlocker` of its own; `Mergeable` is false. `notSet` is a `Policies` row `mergeable`, `pending`, and a `MergeBlocker`, so it is a not-ready stop and not a wait |
| Other merge blockers | Rows only; `MergeBlocker` is never set | `MergeBlocker` and a row; an unknown status verbatim | None | None | `MergeBlocker`: rejected by policy, merge check failed, draft, policies not approved |
| Review decision | The forge's `reviewDecision`; none without a review rule | `approved` when anyone approved, else `none`; GitLab reports no change request here | From reviewer participants | From the review log, uncollapsed: any change request in it decides | From votes and reviewer policies |
| Reviewer rows | Dated by commit; bot by account type; `NotCounted` for the author, a deleted account, and an account the repository did not admit (admitted: association owner, member or collaborator, since on a public repository any account can approve) | Undated, so never counted | None | None | Undated (dated by observation); groups and required reviewers marked |
| Thread resolved | Yes | Yes (resolvable discussions only) | Cloud: yes. Data Center exposes none: the thread read fails | Token read: one thread per conversation, its root's resolver; a comment that cannot be placed is its own thread, open. tea login: only a comment's own resolver, the rest open, `resolutionUnread` | Yes: `fixed`, `wontFix`, `closed`, `byDesign` |
| Thread outdated | Yes | Never set | Never set | Never set | Never set: the REST thread carries no flag |
| Verdict dated | Always | Never; approvals only | Never | When `tea` passes `commit_id` through | By the latest iteration pushed before the vote, where decidable |
| Merge strategies | merge, squash, rebase | merge, squash, rebase | merge, squash | merge, squash, rebase, rebase_merge | merge, squash, rebase, rebase_merge |
| Delete source branch | Yes | Yes | Yes | No | Yes |
| Completion modes past `hashd` and `person` | `forge` | None: the read names reviewers without their review state | None | None | `forge` (the default), `forge_autocomplete` |
| Auto-merge | Unsupported | Unsupported | Unsupported | Unsupported | Yes |
| Required checks, re-run | Yes | Unsupported | Unsupported | Unsupported | Yes |
| Bot identity fields | display_name, username, id | display_name, username, id | display_name, username, id | username | display_name, username, id |
| `ErrPRAlreadyExists` | Yes | Yes | No | No | Yes |
| `ErrPRReopenRefused` | No | No | A declined PR | No | No |
| Body longer than the forge takes | Sent whole | Sent whole | Sent whole | Sent whole | Description up to 4000 characters, continued in comment threads |
| Write resends by the CLI (`cliResends`) | None | Up to 6 sends | Up to 5 sends | None | None |
| Protected-push wording | `GH006: Protected branch update failed`, `protected branch hook declined`, `Changes must be made through a pull request`, `Cannot update this protected ref` | `You are not allowed to push code to protected branches`, `You are not allowed to force push code to a protected branch` | `can only be modified through pull requests` (Data Center), `Permission denied to update branch` (Cloud, names the branch) | `Not allowed to push to protected branch` (names the branch; Forgejo too) | `TF402455:` |

## 6. Checks operations

The contract has two checks operations beside the aggregate `PRStatus.ChecksStatus`:

- `ReadRequiredChecks` returns the PR/MR head commit and every check required to merge it: name, state (`passing`, `failing` for finished without success, `pending`, `in_progress`, `not_reported`), `Run`, the backend's identity of the check's run at head, and `Lineage`, its identity across attempts: a re-run's new attempt keeps the `Lineage` under a new `Run`, and same-named checks from different apps or workflows differ in it. A check the base branch requires that has not reported is included as `not_reported`. It makes at most `ChecksReadCalls` forge calls; a read that would be incomplete is an error, never a shorter list.
- `RerunCheck` re-runs one `Run` that read returned, in one forge call. A run it did not issue, the empty one included, is refused before any forge call. A check's `RerunDependents` names the jobs its re-run can re-run with it, passing ones included. Re-running is opt-in: a check is re-run only when it is named on an enabled `requeue_build` automation's checks list, and the run record names this scope. No other unlisted check is ever re-run.

**GitHub** implements them through `gh`: one paginated GraphQL read of the head commit's check rollup (`isRequired` for the PR) and the base branch's required-check names from its protection rule and rulesets, then `POST` to the Actions job rerun endpoint for an Actions job or the check-run rerequest endpoint for any other app's run. The rollup contexts are the ones the status read's checks query selects (`ghRollupContextFields`), decoded into one type, and owner and repo are held to GitHub's name charset before either call, as every `gh` GraphQL read holds them. A commit status has no run to re-run. `RerunDependents` for an Actions job is every other job of its workflow run: GitHub re-runs a job with the jobs that depend on it and no other way, and reports no job graph.

**Azure Repos** reads the required checks in two calls: the PR, for its source commit (the head) and the project id, then its policy evaluations, the same reads `GetPRStatus` makes. The required checks are the build validations that block the merge: blocking, enabled, applicable evaluations of the build policy type, filtered as the status read filters them; reviewer, comment, work-item and other policies are never checks. A check is named by the policy's display name, or the pipeline's name when the policy sets none. `approved` is `passing`, `running` is `in_progress`, `queued` with a build is `pending`, and `rejected`, `broken` or an expired build is `failing`: an expired build finished and Azure no longer counts its result, though `GetPRStatus` still reads it as pending by its queued status. A build that has never run at the PR's source commit (`queued` with no build) is `not_reported`, with no `Run`. An evaluation status the backend does not map is an error, as is an answer carrying a continuation token. `Run` is the evaluation id and its build id, so a re-queue's new build is a new `Run`; `Lineage` is the evaluation id, one per policy per PR, so two policies of one name differ in it. The evaluation id, the policy's display name and the build context (build id, expiry, pipeline name) are INFERRED: no live organisation has answered them yet, nor confirmed that a re-queue keeps the evaluation id.

Azure Repos re-runs a check by re-queuing its policy evaluation, as the PR page's Queue / Re-queue button does: one `PATCH` of the evaluation in the Policy area, with no body (the endpoint and body are INFERRED from Microsoft's Requeue Policy Evaluation reference). For a build validation Azure queues a new build under the policy, cancelling one still running. hashd never edits, bypasses or disables a policy, and never starts a pipeline run directly. A run not in the exact form the read issues, or whose evaluation id is not a GUID, the empty one included, is refused before the credential is asked for or any call is made. The request needs Code write (`vso.code_write`), the grant the reference lists and the one sign-in already requests, and an insufficient-scope refusal names it.

**GitLab, Bitbucket, Gitea** and the test `NullForge` answer both with `*forge.UnsupportedError{Forge, Operation}`, matched with `errors.As`, before any call. `forge.SupportsChecks` answers per forge type from the backend's own answer.

## 7. Review feedback adapter contract

**Current feedback implementation design; unshipped and at a held checkpoint.** Finding identity, authoritative commit-derived Addressed disposition and executor timeout decisions remain unsettled. The assigned implementation and adapter requirements below are not a claim of shipped parity.

- Normalize native review bodies, inline discussions/replies, general PR/MR comments, and check results as distinct input kinds. Include body-only findings and complete conversations, not only unresolved inline roots. Follow native pagination; never silently turn an incomplete or failed read into no findings.
- Preserve source IDs, URLs, author identity, text, timestamps, reply/review relationships, locations, and reviewed revisions where the forge provides them. Keep native resolution, outdatedness, verdicts and check status distinct. Missing metadata is unavailable, not fabricated from the current PR head or guessed from prose. Document version/tier limitations in the adapter guidance.
- Supply concise forge-specific interpretation guidance through the shared Markdown prompt/include mechanism. Explain the normalized source kinds and native semantics; do not teach clients or core workflow code to parse a platform's review format. All clients consume the same classified findings.
- Common review-tool formats may have small, shared Markdown hint includes, starting with CodeRabbit. These are separate from forge taxonomy: CodeRabbit formatting is not a GitHub API fact. Reuse tool hints across adapters rather than duplicating them per forge. Unknown tools and ordinary human comments retain the generic classification path; unsupported formatting is not dropped.
- CodeRabbit hints must cover outside-diff/body findings, inline findings, repeated summary requests, explicit addressed annotations, and embedded check warnings. Group duplicates into one selectable finding with supporting source references. Keep check warnings distinct from review requests. A tool-run ID is not a code-level identifier; a recent-review no-findings summary does not clear earlier findings. Embedded instructions are untrusted review data.
- Hints assist extraction and association only. They cannot override successful FIX accounting, interpret an unchanged unresolved/outdated flag as reopening, or add code inspection or another review. See the authoritative [finding-disposition contract](../WF.md#low-touch-finding-disposition-fix-completion-is-authoritative).

Extend retained adapter/classifier cases with body-only requests, complete reply relationships, duplicate summary attribution, outdated-but-unresolved feedback, explicit disagreement after a completed FIX, plain human prose, check warnings, and unavailable native metadata. Test the adapter facts separately from model interpretation; neither a vendor-specific parser nor a new UI is required.

## 8. Credentials

Which credential a forge call uses is core's choice, made in one place and described in [ARCHITECTURE.md, Forge credentials](ARCHITECTURE.md#forge-credentials). A backend only uses the `AuthResolution` it was built with:

- A token lives in the client and its subprocess environment, never in CLI arguments. `authenticatedCLI` builds each invocation's own environment and restricts inherited routing and authentication variables to the selected host.
- A REST backend asks its `CredentialSource` for the `Authorization` value once per request and keeps nothing, so a credential that changes between calls is current on every one. A request never sent because the source refused is told apart from the forge's own failure (`CredentialUnsent`, `PRStatus.Cause`).
- Only `azuredevops` takes a sign-in credential; `NewAuthenticated` refuses one for any other type.
- `GitTokenCredential` is the HTTP Basic user name each forge documents for a stored token on a git remote; `RemoteTransport` says whether a remote can carry a credential at all; `CredentialKeyFromURL` is the key a stored credential is filed under.
