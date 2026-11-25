# Backing Up hashd

`hashd backup create` writes this machine's hashd into one file while hashd
keeps serving. It replaces the old procedure (`hashd stop`, copy or snapshot
the whole ops directory, `hashd start`). You do not need to know the ops-root
layout, and the SQLite stores are copied consistently even while they are
being written.

`hashd backup restore` brings a backup back on a new host: see
[Restore onto a new host](#restore-onto-a-new-host).

## Create a backup

Run it on the machine that hosts hashd-server:

```bash
hashd backup create              # writes into <ops>/backups/
hashd backup create /mnt/backups # writes into the given directory
```

It prints the backup file's path, `hashd-backup-<UTC time>.tar.gz`, and the
notices below. The file appears under that name only once it is complete, so
a scheduled job can copy whatever is there (to S3, for example) without
picking up a half-written backup.

What it does, in order:

1. It takes the lock `hashd restart` and `hashd stop` take, so no restart can
   stop the server in the middle of the copy. While a restart or stop is
   running it refuses (`backup.concurrent`).
2. It puts the restart hold in force through the same gate and wait as
   `hashd stop` (WF.md "Restart holds"). New workflow work does not start,
   and running work stops at its next stopping point. The wait has no limit
   and prints progress the whole time. Ctrl-C during the wait releases the
   hold and writes nothing (`backup.cancelled`). A running hashd-server that
   cannot be held, including one older than the restart hold, is refused
   (`backup.hold_unavailable`) rather than copied while it keeps working.
3. It copies the stores online, and the other included entries as files.
   Ctrl-C during the copy stops it, and no backup file is left behind.
4. It releases the hold, whether or not a backup was written, and prints what
   the release reached. If the release cannot be confirmed, or does not
   reach every held workflow, the command exits non-zero (`backup.release`)
   even when the file is complete. While
   that hold stands, hashd may still refuse new work: run
   `hashd backup create` again and press Ctrl-C once it is holding, or
   restart hashd-server.

Without a local hashd-server running, it holds nothing and copies the stores
as they are. On a machine whose configured server is on another machine it
refuses (`backup.remote_target`) and writes nothing: run it on the machine
that hosts hashd-server. It works the same way in solo and team mode.

## Automatic backup before restart

On the server host, a full `hashd restart` with pending SQL migrations,
schema-completion work, a schema checkpoint, or runtime migrations writes an
upgrade backup into `<ops>/backups/` before stopping any service or running
migrations. `hashd restart server` also backs up pending migration work, but
requires a schema checkpoint that already permits server startup. A behind
checkpoint is refused before shutdown: use a full restart to advance it.
This includes the installers' `--in-place-upgrade` restart and a deliberate
full restart from a source checkout. It works headlessly in solo and team
mode, using the same local supervisor credentials as the restart hold.

Upgrade archives contain only the system `hashd.db`, each immediate
`projects/<name>/hashd.db`, the active story evidence files referenced by each project snapshot, the present Temporal stores, the schema checkpoint,
and completed runtime-migration markers, with archive structure and identification
metadata. Database snapshots include committed WAL contents. Both manual and upgrade backups read
the evidence inventory from the snapshot and verify each archived file against its recorded
SHA-256. After story closure, subsequent backups keep the execution summaries. Existing
archives retain the evidence they already contain until their usual expiry. Discovery uses the
ops-root relocation view, including interrupted moves, without walking project
contents, runner artifacts, agent homes, runs or logs. Repository discovery and
store-key payload planning are reserved for manual backups. Retain the existing
installation, including its key and non-database files: an upgrade archive is
recovery input, not a complete backup for a new host.

A protected restart requires the previous runnable build before `--auto-rebuild`,
shutdown or migration. Installers pass their retained location and build identity;
restart checks the executables and receipt against this installation and uses the
retained runtime selector to require resources, Python and infrastructure tools.
Source setup uses `hashd_install_preserve` before replacing the build. A direct
source restart without that pre-replacement installer handoff refuses: copying
already rebuilt binaries cannot establish a previous runnable build. Restore the
previous installation before rerunning setup if it was overwritten without a
handoff. Auto-rebuild protects an existing local source installation even when the
executing CLI sees no pending migrations; the replacement may introduce them,
so this path requires the retained build and creates a backup conservatively.
A replacement candidate alone is insufficient. If preservation fails, restore the
named prerequisites from the existing installation and rerun the installer;
keep the existing installation and retained directory until that succeeds.

The existing prechecks must pass first. Retention configuration is validated
before the copy. The lifecycle lock and the same restart hold stay in force
through the online copy and shutdown; hashd-server keeps serving during the
copy. The archive starts protected from retention. Its exact path is carried
through the restart: if an upgrade relocates the ops root, `backups/` stays
at the original root and the archive remains there.

Progress names the boundaries in order: `Starting online upgrade backup`,
`Backup written: <path>` with its recovery notice, `Online upgrade backup complete`,
then `Starting shutdown`. Snapshot integrity checks, gzip completion and durable
archive publication all finish before the completed-archive report. Both the old
server and Temporal owner remain available through that report; the restart hold
parks workflow advancement, rather than stopping either process. Shutdown performs
no deferred snapshot or archive creation. Previous-build validation and any source
rebuild also precede shutdown, under that same lock and hold.

A focused headless run on 2026-11-16 used a committed 16 MiB random-data
system store and live Temporal stores, co-built binaries, and the installers'
restart arguments. The measured online-backup interval (start report to completed
archive report) was 93 ms in solo mode and 89 ms in team mode. The separate
interval from confirmed old-server exit to replacement health was 2.276 s and
2.271 s respectively. These are observed fixture results, not downtime budgets;
they exclude waiting for work, preservation/rebuild, and stop-request-to-exit time.
The original server PID and Temporal PID still answered health/API requests at
archive completion. The test synchronizes on phase-report delivery and verifies
one complete archive with no staging work remaining before shutdown; it asserts
no elapsed-time threshold. Reproduce with co-built binaries and installed tools:

```bash
cd server
hashd test -- go test -tags smoke ./internal/cli -run '^TestOnlineUpgradeBackupCompletion$' -count=1 -v -timeout 15m
```

A prerequisite, copy, cancellation or required backup-report failure stops no
services and runs no migrations. The command returns the full diagnostic and
next steps and releases its hold; an incomplete or unconfirmed release is
reported with the steps needed to resume work. Correct the failure and rerun
the restart. A running server too old to support restart holds cannot be
backed up automatically. `--force` does not waive that prerequisite.

`--skip-backup` skips archive creation and the recovery-build prerequisite for this invocation only. It is
accepted on a full restart or server component restart only when that path
has pending backup work. It is refused on fresh installs, steady-state
restarts, remote clients, and web or Telegram component restarts. Those
paths create no automatic backup. No environment variable or persistent
setting enables this flag; `upgrade.backup.keep: 0` does not skip creation.

For example, on the server host with pending migration work:

```bash
hashd restart --skip-backup
# A deliberate source upgrade still needs its own acknowledgement:
hashd restart --in-place-upgrade --skip-backup --yes
# Only when the schema checkpoint already permits server startup:
hashd restart server --skip-backup
```

All applicable prechecks, workflow holds, waits and stop guards still apply.
`--yes` answers prompts and does not select `--force`. The server component
retains its runtime-migration-before-startup ordering; startup completes any
pending schema work. Actionable rerun commands preserve `--skip-backup`;
omit it on a later invocation to enable automatic backup creation again.

If a migration fails, including an identified migration failure during server
startup, restart keeps the lifecycle lock and confirms the server and Temporal
process groups have exited before restoring. Component recovery also stops the
Temporal sidecar. An unconfirmed stop prevents publication and startup of either
build. A restoration failure starts neither build.

Recovery restores only this attempt's protected archive, preserving its schema
without rerunning replacement migrations. Database-only recovery publishes the
system, project and Temporal database files in their existing directories, removes
stale WAL/SHM companions, and restores the archived schema checkpoint and runtime
completion markers, removing markers introduced by the failed attempt. Omitted
configuration, keys, project files, runs, agent homes and other directory contents
remain in place. Failed publication rolls displaced files back before either build
can start. It accounts for operations-root
relocation and preserves excluded repository clones and local-runner checkouts,
then starts the retained previous build at the recovered root. The diagnostic
keeps the original migration report and records stop, restoration and prior-build
startup outcomes, with archive, retained-build and failure paths.

Recovered-server readiness and released, held or unknown work outcomes are
reported independently of the upgrade result. The upgrade still exits nonzero
with `restart.migration_failed`; installers stop without success or a second
restart. Without this invocation's archive (`--skip-backup`), recovery remains
manual: hashd never discovers or substitutes an older upgrade or manual backup.
Correct the migration error before attempting the upgrade again.

The current archive loses protection only after this attempt's replacement or
recovered previous build confirms released startup readiness. This decision is
independent of the nonzero upgrade result: confirmed recovery with
`upgrade.backup.keep=0` removes the archive. Failed or unconfirmed recovery keeps
it protected, including when release is unknown or keep is zero; health alone
never releases protection. A later successful attempt does not release that older
archive. Stop, restoration and prior-build startup must all complete before a
released startup can authorize retention. The startup state `released` alone is
insufficient when its workflow release report is unconfirmed: unreachable held
runs keep this attempt's archive protected even after the server hold is removed.

Recovery records the retained carrier beside the existing installation receipt
in `hashd-install-recovery`. Both installers follow that selection on the next
attempt, preserving the recovered build rather than the failed replacement still
installed at the launcher. Only completed installation clears the selection. The installer owns its
retained
payload: even confirmed, released recovery leaves that payload available because
the installation still failed. Restart does not delete an installer-owned build.
There is currently no directly retained restart payload; direct restarts use the
validated installer handoff too. A healthy replacement with unresolved startup
or workflow release returns `restart.release_unconfirmed`, so both installers
preserve their payload instead of completing successfully. This also applies when
no migrations needed an archive.

## Inspect a backup

```bash
hashd backup inspect <file>
```

This reads the file, checks every entry against the manifest the file
carries, and prints:

- the hashd version that wrote the file, and when;
- its ownership: `manual` or `upgrade`;
- whether the store key is inside;
- every entry, and every special file (a socket or FIFO, for example) that
  was found and not copied;
- each project repository: its project, its path, whether it is hashd's
  clone or a link to a directory on the backed-up host, and its recorded
  remote, with credentials removed. A backup written by a hashd older than
  this format records no remotes, and the report says so.

Each entry's bytes, size, permissions and, for a symlink, its target are
checked. The manifest is read into memory, so a file whose manifest is
larger than 256 MiB is refused (`backup.not_a_backup`); `hashd backup create`
refuses to write a backup whose manifest would exceed that (`backup.archive`).

It reads only the file it is given. It needs no running server, no ops
directory and no valid local configuration, so you can check a backup on any
machine, including one with no hashd install.

### Upgrade ownership and protection

Format version 3 records ownership in the archive's manifest. Standalone
`hashd backup create` writes manual archives. Versions 1 and 2 are treated
as manual too. Manual archives never qualify for automatic upgrade backup
retention, regardless of their name or directory. Both manual and upgrade
archives can be inspected and restored using the same commands.

An upgrade archive starts protected from retention while recovery may need
it. The upgrade lifecycle releases that protection by durably publishing an
empty `<archive>.retention-eligible` companion file; removing that companion
protects the archive again. Only an archive with upgrade ownership and this
companion can qualify for retention. These are per-archive protection facts,
not a recovery journal or retry ledger, and survive later command invocations.
Lifecycle operations serialize protection changes and retention with their
existing lock. When deleting an archive, retention must also remove its
companion. A backup name cannot be reused while its old companion remains.

Keep the companion beside the archive to preserve released protection when
moving it. Copying only the archive leaves it protected at the destination.
Inspection and restoration need only the archive; inspection reports
ownership from the manifest, independently of local retention protection.

### Upgrade backup retention

The system-only `upgrade.backup.keep` setting controls how many
retention-eligible automatic upgrade backups to keep (default **2**).
Zero keeps none of those eligible backups; it does not disable backup
creation or delete protected upgrade backups or manual backups. Project
overrides are not supported. Values must be non-negative integers;
negative, fractional and non-integer values are refused.

After a restart reports a successful startup release, the current attempt’s
archive becomes eligible.
Retention in that archive’s directory keeps the newest eligible archives by
the manifest’s creation time, deleting older ones first and removing their
release markers. Renaming a file does not change its age or ownership. An
unresolved restart leaves its current archive protected while retention may still
remove older eligible archives. Protected archives do not count toward keep.

The setting is validated before shutdown and again before retention. Selection
and archive verification finish before any deletion. Retention failures report
every affected path and cause; independent deletions continue after a removal
failure. These diagnostics supplement the complete migration and recovery
reports without replacing them or changing `restart.migration_failed`.
A successful restart remains successful even if retention needs manual cleanup.

```bash
hashd config set upgrade.backup.keep 5
hashd config get upgrade.backup.keep
hashd config set upgrade.backup.keep 0
hashd config reset upgrade.backup.keep  # restore the default
```

## What is in a backup

A manual backup's contents are taken from hashd's list of its own ops-root entries
(`opsRootEntries` in `server/internal/upgrade/m029_ops_root_relocation.go`).
Each entry there says how it is backed up.

Included:

| Entry | How |
|---|---|
| `hashd.db` | the system store, copied online |
| `projects/` | each `projects/<name>/hashd.db` copied online; the rest of each project directory as files |
| `temporal/` | `temporal.db` and `visibility.db` copied online; the other files as files |
| `secret.key` | the store key, when it comes from this file (see below) |
| `config.yaml`, `config/` | settings |
| `secrets/`, `tls/` | as files |
| `agent-homes/` | as files |
| `runs/`, `workstreams/`, `logs/`, `runner-artifacts/`, `orchestrator/` | as files |
| `.db-migration-version` | the schema checkpoint |
| `~/.hashd/migrations` | the upgrade runner's record of the migrations already run (stored as `upgrade-markers/`) |

A store's `-wal` and `-shm` files are never copied raw: the online copy
covers them.

An included entry that is itself a symlink (`tls/` on another volume, for
example) is backed up as what it points to: a linked directory's files, or a
linked file's bytes. Symlinks inside an included entry are backed up as
symlinks.

Left out:

| Entry | Why |
|---|---|
| `repos/` | hashd rebuilds each project's clone from its remote |
| `runner/` | the local runner's checkouts, rebuilt from the remote |
| `cbm/`, `cache/` | caches |
| `config.yaml.lock`, `locks/` | lock files |
| `hashd-web/` | an installed program |
| `temporal/backups/` | the restore points hashd keeps when the pinned temporal-server version changes |

Anything else at the top of the ops directory is not one of those entries
and is never in a backup. That includes `backups/`, where
`hashd backup create` writes when it is given no directory.

A backup directory inside an included entry (for example under `logs/`)
does not take that entry's data out of the backup: everything in it is
backed up except the backups written there, and the staging and temp files
of the one being written.

Every backup states what is not in it:

> repos/ is not in this backup: hashd rebuilds each project's clone from its remote, so work committed only in that clone and never pushed cannot be recovered from this backup.

## The store key

The store key encrypts the secrets in hashd's stores. `HASHD_SECRET_KEY`,
when set, is the key in use; otherwise the key is `<ops>/secret.key`.

When the key is `secret.key`, the backup holds it, and says so:

> This backup contains the store key (secret.key); store it as a secret.

Anyone with the file can read every secret hashd stores. Treat the backup
file as a secret: keep it in encrypted storage, with access limited the way
you limit access to the key itself.

When the key comes from `HASHD_SECRET_KEY`, the backup does not hold it, and
says so:

> The store key is not in this backup: it comes from HASHD_SECRET_KEY. Back up HASHD_SECRET_KEY separately; this backup cannot be used without it.

`hashd backup create` decides where the key comes from by its own
environment, so run it with the same `HASHD_SECRET_KEY` setting hashd-server
runs with. Before it holds or names a key, it opens one of the secrets hashd
stores with that key: a forge token or SSH key, an agent credential, a
connector account, a sign-in token cache, or a project's build secret. If the key does not open it (an old `secret.key` left
beside a server that reads `HASHD_SECRET_KEY`, or the reverse), it refuses
(`backup.key`) and writes nothing. It refuses the same way when the variable
is not set for it and `secret.key` does not exist.

Back up `HASHD_SECRET_KEY` separately, wherever you keep it (a secret manager
or the container's environment). Without it, the backed-up stores' secrets
cannot be read.

## Restore onto a new host

Run it on the machine that will host hashd-server, with hashd-server stopped:

```bash
hashd backup restore <file>
hashd backup restore -y <file>   # without a terminal
```

It unpacks the backup into the ops directory (`HASHD_OPS_ROOT`, else
`~/.hashd`) and the upgrade markers into `~/.hashd/migrations`, then prints
that the restore is complete and that `hashd start` starts hashd. Restore
does not start services: after a normal `hashd start`, every project, story,
workstream, event, transcript record and Temporal workflow history is as it
was when the backup was taken.

With a terminal it asks before writing, naming the file and the ops
directory. Without a terminal, `-y` is required; without it the restore is
refused (`backup.restore.confirm`) and the help is the same command with
`--yes`. Ctrl-C while it unpacks or publishes stops it and leaves nothing
behind.

### The target must be empty

A restore never overwrites or merges into an existing hashd. It is refused
(`backup.restore.target_not_empty`), and every item in the way is listed, when
any of these is already there:

- `hashd.db`, `hashd.db-wal`, `hashd.db-shm`, `secret.key` or `config.yaml`
  in the ops directory, and any project or Temporal store
  (`projects/<name>/hashd.db`, `temporal/temporal.db`,
  `temporal/visibility.db`) or its `-wal` or `-shm` file, whether or not the
  backup holds them: a WAL left behind by a moved-away store belongs to
  another database, and SQLite would read it over the restored one;
- any other top-level ops-directory entry the backup would write
  (`projects/`, `temporal/`, `logs/` and the like);
- `repos/`, when the restore rebuilds a project clone there (below);
- any file in `~/.hashd/migrations`, the upgrade runner's markers.

Apart from those, what a backup leaves out does not count: an installed
`hashd-web/`, caches, lock files, and anything else at the top of the ops
directory that a backup never holds. A symlink counts as itself.

### Refusals

Every refusal is checked, in this order, before anything is written, and
changes nothing:

| Source | When |
|---|---|
| `backup.restore.remote_target` | the configured hashd-server is on another machine: run the restore on the machine that hosts hashd-server |
| `backup.restore.concurrent` | the lock `hashd start`, `hashd restart` and `hashd stop` take is held |
| `backup.restore.server_running` | a hashd-server is running from this ops directory: stop it with `hashd stop` |
| `backup.read`, `backup.not_a_backup`, `backup.damaged` | the file cannot be read, is not a backup, or does not match its manifest, exactly as `hashd backup inspect` reports |
| `backup.restore.version` | the backup was written by a newer hashd, either version cannot be placed in release order, or the two are different builds release order cannot tell apart |
| `backup.restore.target_not_empty` | the target is not empty (above) |
| `backup.restore.confirm` | no terminal and no `-y`, or the prompt was declined |

The file is untrusted input. While it unpacks, the restore checks every
entry against the manifest again, so a file changed after it was checked is
refused. It refuses any entry that would land outside the target, and any
entry `hashd backup create` never writes: a store's `-wal` or `-shm` file,
`temporal/backups/`, an in-progress upgrade claim, a store or `secret.key`
that is not a regular file, and a symlink at `projects/`, a project's
directory, `tls/`, `temporal/`, or the sidecar's config files, where the
next start opens the stores or writes. Names are matched whatever their
case, as a case-insensitive volume opens them. It never applies setuid, setgid or sticky
bits, and it never writes through a symlink from the file. A refused or
failed restore leaves nothing behind.

### Project clones

`repos/` is not in a backup. The backup records each project repository
instead: where it was, and its fetch remote with any credentials removed.
The fetch remote is `origin`, or the clone's only remote under another name;
a local path relative to the clone is recorded as the absolute path it named,
and a URL with a query, which can carry a token under any name, is not
recorded. A project whose `config.yaml` cannot be loaded does not stop the
backup: its repositories are not recorded, and a notice says so wherever
the backup is described: when it is written, by `hashd backup inspect`, and
in the restore's report. A remote recorded as a path relative to its clone
(by an older hashd) is not cloned: the report names it as not recoverable.
The restore clones each repository that was hashd's own clone with a
recorded remote back into `repos/`, with `git clone` as `hashd project add
--clone` runs it, before anything is published, so Ctrl-C during a clone
leaves nothing behind. The remote carries no credentials, so this host's own
git credentials (an SSH key, a credential helper) must reach it. The remote
comes from the file, so git may clone it only over `file`, `git`, `http`,
`https` or `ssh`, after any `insteadOf` rewriting too: a remote helper such
as `ext::`, which runs a command, is refused even where this host's git
allows it.

The report names every recorded repository:

- `Rebuilt`: cloned from its remote.
- `Not rebuilt`: the clone failed. The restore is still published, and the
  report shows the clone's own error under the repository
  (`project.add.git_clone_failed`, or a clone stopped by `git.clone_timeout`
  or `git.clone_stall_timeout`), with the `git clone -- <remote> <path>`
  command that puts it at its restored path by hand, limited to the same
  transports (`GIT_ALLOW_PROTOCOL`).
- `Not recoverable from this backup`: the repository had no remote that could
  be recorded, or was a link to a directory on the old host (a linked project
  or a multi-repo container, or a repository outside the ops directory). The
  report says which, with the `git clone -- <remote> <path>` command that puts
  a repository at its restored path by hand; `<remote>` is the recorded remote
  when there is one. For a link, you can instead link that path to the
  directory again.

What a failed clone wrote is removed, so the path is free for the
`git clone` step. Where something else is in the way there, the step names it
and says to move it first: a file or symlink an earlier clone checked out on
the path, what an earlier clone checked out in it, or the directories holding
repositories rebuilt inside it, which go back in after the clone.

Work committed only in a clone and never pushed is not recovered:

> repos/ is not in this backup: hashd rebuilds each project's clone from its remote, so work committed only in that clone and never pushed cannot be recovered from this backup.

### Versions

A backup written by the same hashd build, by its version stamp, is restored. A backup from an older
release is restored too: the restore migrates its stores to this hashd's
schema, wherever it is restored, and the next `hashd start` runs the rest of
the upgrade, as it does for any older install. A backup written by a newer hashd is refused, as
is one where either version cannot be placed in release order (a `dev`
build, for example, even onto a `dev` build), or where the two are different
builds the same number of commits past one release, or the same dirty build
stamp: on the host the backup came from, take a new backup with a release
build, then restore it here with that release or a later one.

A backup from a hashd whose backups did not yet record their ops directory
(format version 1) is restored only when its project data holds no stored
path that may name that directory: an absolute path in a project config, a
`repos/` link or a project's repository list, or a path in a project
database's runs, clarifications or open workstreams. One that does, or that
holds a project config as a symlink, is refused (`backup.restore.format`),
with each such path named: take a new backup on the host it came from.

Once the restore is published it is complete, and the command succeeds: a
staging directory it could not remove, or a report standard output could
not take, is reported on standard error, the report whole.

### Restoring to a different ops path

The backup records the ops directory it was taken at. When you restore it
somewhere else, the stored paths that name the old ops directory (project
configs, project databases, open workstreams' worktrees) are rewritten to
name the new one, the same way M029 maps them when it relocates an ops root.
A backup that holds project data as symlinks cannot be mapped this way and
is refused (`backup.restore.relocate`): restore it at the path it was taken
at, or replace the links on the backed-up host and take a new backup.

If the ops directory, or `~/.hashd`, is a symlink (for example to a data
volume), the restore follows it, and refuses if it points somewhere else by
the time the restore is published.

### The store key

When the backup holds no store key, the restore says so: set
`HASHD_SECRET_KEY` to the backed-up hashd's key before `hashd start`, or the
restored secrets cannot be read.
