# Network access

hashd runs locally by default in Solo mode. **Network access** lets other
devices connect to the same installation. It is off by default in Solo and on
by default in Team. The server detects its reachable addresses; no adapter or
IP address needs to be chosen.

Use **Settings → Network access** in the TUI, or **Settings → Server → Network
access** in the Web. Both show the server's current settings, reachable addresses,
paired devices, runners, and the actions available to the signed-in person.

## Open a Solo installation to another device

On the server machine:

```bash
hashd network on
hashd network status
hashd pair
```

Turning Network access on or off restarts the managed server and Web processes.
The command and settings screen show the restart notice before applying the
change. With access on, hashd-server listens on all interfaces and serves HTTPS.
Requests from another device require authentication. Managed hashd-web stays
on loopback in every mode; browsers reach it through hashd-server's HTTPS
`/ui` and `/join` relay.

`hashd pair` returns a one-time join link and its expiry. Send that link through
a private channel. A paired device acts fully as the Solo owner; it is not a
read-only viewer. Its access can be revoked independently later.

On the other device, open the link in a browser, or run:

```bash
hashd join '<join-link>'
hashd status
hashd watch -p <project>
```

The client tries the addresses carried by the link in order, verifies the
server, and saves its connection and sign-in. Each link can be redeemed once;
create a new link for each device. Links carry credentials: keep them out of
shared logs, screenshots, and issue reports.

To close network access again, run this on the server machine:

```bash
hashd network off
```

hashd-server returns to a localhost-only listener; managed hashd-web remains
on loopback. Existing pairings can be managed from Network access; turning the
listener off is not a replacement for revoking an unwanted device.

## Invite someone to a Team server

From an authorized account on the server:

```bash
hashd invite alice@example.com
```

Send the returned join link to that person. The invitation belongs to that
account; first-time setup lets the person choose a password. They open the link
in a browser or use `hashd join '<join-link>'` on their machine.

Team mode keeps per-person identity and ownership. Only a story's owner may
change it; unassigned work is open to claim, and assignment remains open-grab.
Server settings are available only when the server offers their actions. The
TUI and Web do not grant permissions independently.

Before running agents, register the person's agent credentials:

```bash
hashd agents login claude
```

Use the agent actually selected for the stage. See
[Agent management](AGENT_MANAGEMENT.md#per-user-credentials-team-servers) for
sign-in methods and runner placement.

## Add a runner

From Network access, choose **Add a runner**, or register it from the CLI:

```bash
hashd runner add build-box --project <project>
```

In Settings, enter the runner name and its allowed projects. Leaving Projects
blank registers the runner without project access. No project is granted
implicitly.

Run the returned link on the runner machine:

```bash
hashd runner connect '<join-link>'
```

For a shared terminal, `hashd runner connect -` reads the link from stdin,
keeping it out of shell history and process arguments. The runner connects
outward to the server; no inbound runner port is required.

The server decides whether a runner may be added and which projects it may
execute. Inspect the resulting registration and its observations with:

```bash
hashd runner list
hashd runner show build-box
```

To rejoin an existing runner after a CA change, its owner or a server
administrator issues a fresh link:

```bash
hashd runner join-link build-box
```

Pass that private link to `hashd runner connect -` on the same runner, then
restart its runner process. This preserves its ID, project grants, placements,
assignment journal and agent homes. Do not register a replacement with `runner
add`. Issuance replaces any earlier unused link; the current session stays valid
until redemption. The link expires one hour after issuance, regardless of when
the runner was registered. Drain running stages before restarting the process.

## Reachable addresses and trust

`hashd network status` and Network access settings show the same ranked list:
Public URL, Tailscale MagicDNS with a working browser-trusted certificate, a resolvable `hostname.local`, the default-route
LAN address, and other eligible interface addresses. Unavailable candidates
are omitted. Loopback, link-local, and container bridge addresses are not
advertised. A listed interface address does not open a firewall or establish a
route from another network; allow access only from the devices or networks
that should reach the server.

Direct HTTPS connections use a persisted hashd certificate authority. Join
links carry its CA pin, and the client saves the CA trust separately from its
sign-in. Server certificates cover the detected names and addresses. A changed
address can get a new serving certificate without replacing the CA or breaking
existing pairings.

CLI join saves trust for hashd clients; it does not install the CA into the
operating system or browser. A browser opening a direct hashd HTTPS address
needs the installation's CA trusted by that browser. The server's public CA
certificate is `~/.hashd/tls/ca.crt` (under the configured ops root); distribute
only that certificate, never `ca.key`. A Public URL with a system-trusted
certificate avoids this browser trust setup.

Clients also accept a certificate trusted by the system trust store for the
URL's hostname. This supports a TLS-terminating load balancer, Tailscale HTTPS,
or a corporate certificate. A failed certificate check is a refusal, not a
reason to disable verification; re-join with a fresh trusted link if the
installation's CA changed.

Old tokens containing a serving-certificate fingerprint and the old
`hashd server set --token` pairing flow are not supported. Existing remote
clients and runners must re-join using new links.

### Browser-trusted HTTPS over Tailscale

With Network access on, hashd asks the local tailscaled for a certificate when
a client connects to this machine's discovered `*.ts.net` name. Tailscaled
issues, caches, and renews it; hashd has no certificate setting or renewal job.
Other names and IP addresses keep the installation's configured certificate.
CLI, TUI, and Web Network access status report whether the Tailscale certificate
works, with the reason and recovery steps when it does not. Join links prefer
the Tailscale name over other detected addresses only while its certificate
works; an explicit Public URL remains first.

Enable **DNS > HTTPS Certificates** in the Tailscale admin console. Tailscale
shows its Certificate Transparency disclosure there: the certificate's machine
name becomes public. If tailscaled refuses hashd's user, set
`TS_PERMIT_CERT_UID=<hashd-server user>` in `/etc/default/tailscaled` and restart
tailscaled. Refresh Network access afterwards; hashd needs no restart.

On failure hashd keeps serving its configured certificate, so a browser may
still need the hashd CA. This integration uses tailscaled's Linux Unix socket;
it does not use Tailscale Serve, which makes tailnet connections appear local
and would bypass solo mode's loopback boundary.

Self-hosted tailnets are version-dependent: Headscale 0.29.7 cannot issue node
certificates; 0.30.0 adds support with a DNS challenge provider. This integration
selects only the local `*.ts.net` name. For a self-hosted domain use your own
certificate and Public URL.

### Private certificate authorities

Install the private CA into the client's system trust store. Python clients,
including the TUI and Telegram bot, also honor `SSL_CERT_FILE`:

```bash
SSL_CERT_FILE=/path/to/company-ca-bundle.pem hashd watch -p <project>
```

The file must contain the CA certificates needed to verify the server. Keep
hostname verification enabled.

## Public URL and load balancers

Set **Public URL** to the HTTPS address people and runners use. It is advertised
first and used in join links; it does not provision DNS, a load balancer, or a
certificate at that load balancer.

```bash
hashd network url https://hashd.example.com
hashd network status
```

To return to automatically detected addresses:

```bash
hashd network url --clear
```

For an AWS Application Load Balancer with an ACM certificate:

1. Create an HTTPS listener for the Public URL's hostname, using its ACM
   certificate, and point DNS at the ALB.
2. Enable Network access on hashd and restrict backend ingress to the load
   balancer. Configure an **HTTPS** target group for hashd-server's port. ALB
   accepts the target's hashd-issued certificate; clients verify the ACM
   certificate at the listener.
3. Route both API and browser requests, including `/ui`, `/ui/*` and `/join`,
   to that **HTTPS** target group. hashd-server relays browser requests to
   managed hashd-web over loopback HTTP. Managed Web has no external listener
   or separate ALB target group; clients use one HTTPS origin.
4. For hashd-server health checks, use `/health` and allow **200 and 401** as
   success codes. An authenticated server can answer a tokenless probe with
   401; that does not mean its listener is unhealthy.
5. Set the idle timeout **longer than 30 seconds**. Event streams and log/chat
   streams send heartbeats every 30 seconds. The runner's separate check-in
   does not keep an idle event-stream connection alive. Preserve streaming;
   do not buffer responses until completion.
6. If AWS WAF uses the managed core rule set, exclude
   **SizeRestrictions_BODY** on hashd-server API paths. Runner result bodies
   exceed 8 KB. Scope that exception to the API paths rather than unrelated
   applications behind the same load balancer.
7. Set the Public URL, then create fresh join links through that address.

Keep authentication enabled on the backend. Proxy headers do not grant
localhost access. Do not place a public proxy in front of a localhost-only Solo
listener and treat its loopback exemption as remote authentication.

## Revoke a device or runner

Network access settings list paired devices and runners with the revoke actions
the server allows. Revoke an unwanted registration there, or use its ID:

```bash
hashd auth delete <device-id>
hashd runner remove <runner-id>
```

A revoked device must join again to regain access. Runner removal revokes the
registration while retaining its history. Removing a Team user is broader:
`hashd admin user remove <email>` revokes their access and sign-ins while keeping
work attributed to them.

## Troubleshooting

| Symptom | What to check |
|---|---|
| No reachable addresses | Open Network access on the server; inspect the server's reported addresses and network connectivity. |
| A join link expired or was already used | Create a fresh link for that device or runner. |
| Certificate refusal | Check the hostname and trust chain. Use a fresh trusted join link after a CA change; install the corporate CA for a private certificate. |
| Public URL works in a browser but streams stop | Check the proxy idle timeout and response buffering. |
| Runner results fail behind WAF | Check the API-path exception for `SizeRestrictions_BODY`. |
| An action is absent | Read the server's reported reason and sign in with an account it authorizes for that action. |
| `hashd` is not found over SSH | Use `~/.local/bin/hashd`; non-interactive SSH shells may not source the installer's PATH entries. Bundled tools are under `~/.hashd/tools/bin`. |

## Runner observations

### Runner setup observations

Before accepting work, each runner reports hashd's own setup checks through
its existing check-in: Git 2.46 or newer (including the authenticated URL-reset
capability), the runner user's configured Git committer (and author in Solo), writable
runner storage, and directory/file creation under the actual stage fence.
The runner reports again on reconnect. These observations do not install tools,
set an identity, change placement eligibility, or describe a project's build tools.

Use `hashd runner show <id>` or `hashd doctor` to see the machine, observation
time and exact corrective commands. No report means unknown. A disconnected
or revoked runner's report is labelled stale; reconnection reports the current
state. Startup also prints each failed check locally. A journal or layout migration
failure is reported before the scratch probe runs, preserving migration order.

The fence does not allow a stage to create a new entry directly in any directory
containing the ops dir. Existing sibling directories remain usable. If a project
needs such a directory, create it as the runner user outside the stage before
running the project, or configure that project to use an existing writable
directory. Setup checks do not enumerate project caches or weaken the fence.

### Runner machine observations

`hashd runner list` and `hashd runner show <id>` also report the live connection
state, unfinished placed-story count across projects, and the last CPU/memory
observation. A revoked registration takes precedence over a still-closing
connection. An unreadable project makes the count unavailable rather than
silently reporting a partial total.

CPU is a percentage of total host capacity; memory reports bytes in use and
total bytes. Runners report on bootstrap, reconnect and every 60 seconds while
connected, through the same check-in. Two missed beats (120 seconds) remove
that connection from the live registry, including a silently dead idle stream.
Each beat names its own connection; an old stream cannot keep a replacement
alive. Offline registrations retain their last values and observation
times, marked historical. Missing or unreadable measurements are unavailable,
not zero. The server's `/status` read measures its own host with the same probe.

Remote link timings show the preceding successful check-in round trip and the
latest successful forwarded response, each with its measurement time. Failed
or cancelled reads do not replace a successful timing. Same-machine link
timings are not applicable to the local runner.

### Fleet login observations

Fleet reads machine-local sign-in metadata through the runner's existing
connection, including before its first story. `GET /agents/{agent}/login`
accepts `runner_id` and `owner_id` for this observation; without them it retains
its existing acting-owner local login-management reply. The runner's list/show
read supplies the eligible owners and supported agents, so clients do not infer
access from the runner's registrant or its filesystem.

Server owners and administrators may inspect all eligible active owners on
runners they can see; members may inspect only themselves. Eligibility follows
execution grants (the local runner admits owners before its first on-demand
grant). Authority is rechecked when the answer arrives. The response never
contains login files, tokens, or the remote home path. It does not sign in,
refresh, copy, or remove credentials, and registered credentials retain their
existing launch precedence.

Fleet also offers the acting person's own `sign_in` and `complete_sign_in`
actions through `POST /agents/{agent}/login` and `/login/complete`. The runner
owns the transient attempt over this same connection; only its owner receives
the URL/code instructions. Closing Fleet does not cancel it. A new press
supersedes it; failure, connection loss or the five-minute timeout stops its
process group and removes its temporary home. The previous login stays in place
until a successful attempt is confirmed by the agent and promoted.

The agent's own status command supplies sign-in state. Capability-declared
`login_expiry` names a relative login file, a JSON field path, its `unix_ms` or
`jwt_exp` encoding, and what expires. Claude's declared field is its access
expiry; Codex's is the access token's expiry, not the identity token's. No file
age stands in for expiry. Expired tokens override a positive status probe;
valid sign-ins within 24 hours of expiry are marked close to expiry. Missing
expiry remains explicitly unknown. Malformed or unreadable data is not reported
as signed out.

Reads use the existing 30-second login-status budget. Offline, revoked or
unanswering runners retain the last metadata observation and its original time,
marked stale with a reason; stale metadata is never a current signed-in claim.
The response names the machine and account to use with `hashd agents login`.
Session contents and login material are never stored in the Fleet observation
cache. Schema 159 retains only this metadata across down/up migrations.

Runner registry reads accept an exact ID or a unique visible active name, so
`hashd runner show ea-1` names the same runner as its ID. Duplicate visible
names require an ID; revoked registrations remain readable by ID.
