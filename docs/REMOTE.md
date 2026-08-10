# Remote and Team Servers

Hashd is a client (`hashd`, `hashd watch`) talking to a server (`hashd-server`).
By default both run on your machine as one implicit user with no auth ceremony --
that is [QUICKSTART](../QUICKSTART.md), and if you are a solo developer on your
own box you do not need anything here.

This document is for the other shape: **one `hashd-server` that clients connect
to over the network** -- your laptop driving a box in the closet, or a shared
team server. It covers the trust model, how the operator turns a local install
into a reachable server, how users are provisioned, and how a client pairs.

There is also a third, unmanaged shape -- several solo developers sharing one git
repo with no server -- described at the end under
[Solo shared-repo mode](#solo-shared-repo-mode).

## How trust works

When `hashd-server` listens on anything other than loopback, two things switch on
automatically:

- **TLS.** The server serves HTTPS using a self-signed certificate it generates
  once and persists at `<ops-dir>/tls/server.{crt,key}`. There is no CA to
  configure.
- **Auth.** Every request -- `/health` included -- requires a per-request bearer
  token. Off-loopback fails closed: no token, no answer.

Clients do not trust the self-signed certificate through a CA. Instead, the
certificate's fingerprint is carried **inside the bearer token** the server
mints. When a client pairs with `hashd server set <url> --token <token>`, it
extracts that fingerprint and pins it: the connection is trusted only if the
server presents exactly that certificate. So a single relayed token establishes
both identity (the bearer secret) and transport trust (the pinned fingerprint) --
no separate certificate exchange.

(If you front the server with your own CA-signed certificate by hand-launching
`hashd-server --tls-cert-file ... --tls-key-file ...`, standard TLS verification
applies and no fingerprint pin is used. The managed `hashd restart` path always
uses the automatic self-signed certificate.)

## Scripting hashd over SSH: use a login shell

The installer wires `PATH` from `~/.bashrc` / `~/.zshrc`. Those are **interactive**
shell files: a stock Debian/Ubuntu `~/.bashrc` opens with a guard that returns
immediately when the shell is not interactive, so anything appended below it never
runs — and that guard fires under `bash -lc` too, because a login shell is still
not an *interactive* one.

**Use absolute paths in scripts.** That is the only form that holds regardless of
distro or shell:

```bash
ssh box 'hashd list'                      # hashd: command not found
ssh box '~/.local/bin/hashd list'         # reliable
ssh box '~/.hashd/tools/bin/gh pr list'   # reliable
```

`bash -lc` is not a portable substitute, and the two directories behave
differently under it:

- `~/.local/bin` (where `hashd`, `wf`, `ha` live) is added by *many* distros'
  stock `~/.profile`, which a login shell does read — so `ssh box 'bash -lc "hashd
  list"'` often works, but because of the distro's profile, not because of
  anything hashd installed. On an image whose `~/.profile` lacks that stanza it
  fails.
- `~/.hashd/tools/bin` (the bundled `gh`, `gitleaks`, `delta`, Temporal binaries)
  is wired **only** from the interactive rc files, so it is absent under `bash -lc`
  on every distro.

If you want `bash -lc` to work uniformly, add the PATH entries to a login profile
(`~/.profile`) yourself; the installer deliberately does not edit login profiles.

## Server operator: make the server reachable

Run these on the **server host**. A fresh install already runs on loopback
(`http://127.0.0.1:1337`), so start there.

1. **Mint yourself an owner token** (over the loopback connection, where no token
   is needed yet):

   ```bash
   hashd auth create --description "server host"
   ```

   Copy the `hashd_...` token it prints once.

2. **Point the host at its own LAN address and restart.** On the server host the
   client connection setting doubles as the server's bind address:

   ```bash
   hashd server set https://<lan-ip>:1337 --token <owner-token>
   hashd restart server
   ```

   The server now listens on `<lan-ip>:1337`, serving TLS with its persisted
   self-signed certificate. Confirm:

   ```bash
   hashd status
   ```

   You should see `Server: https://<lan-ip>:1337 (remote)` and `Health: server ok`.

3. **(Optional) Enforce per-user identity everywhere with team mode.** In the
   default solo mode there is one implicit owner, and tokens minted for named
   users are still attributed to those users. Team mode additionally requires a
   token on *every* connection including loopback, so there is no unattributed
   access:

   ```bash
   hashd config set deployment_mode team
   hashd restart server
   ```

## Server operator: add a user

User provisioning is **host-local** -- run it on the server host; it writes the
server database directly, so it needs no network round-trip and works before the
server is even reachable.

```bash
hashd admin user add alice@example.com --name "Alice"
```

This creates the user and prints a **one-time access token** to relay to Alice.
Grant admin rights with `--admin`. Manage users with:

- `hashd admin user list` -- show all users.
- `hashd admin user remove <email>` -- remove a user (and revoke their tokens).
- `hashd admin user reset-key <email>` -- issue a fresh setup key for the password
  login path (see [Password login](#password-login-optional)).

Relay the URL and token to Alice over a trusted channel (the token is a
credential -- do not paste it into shared logs).

## Client: pair and use

Run these on **Alice's machine**. Pairing is identical whether Alice is the owner
or a team member, and identical to how a solo remote client connects:

```bash
hashd server set https://<lan-ip>:1337 --token <token>
hashd status
```

`status` should report the server, `Health: server ok`, and Alice's identity --
e.g. `Identity: Alice <alice@example.com> (user)`. From there everything works
as it does locally:

```bash
hashd list -p <project>
hashd watch -p <project>
```

To stop talking to the remote server and return to local behavior:

```bash
hashd server unset
```

One more step before dispatching runs on a team server: register your agent
credential, so runs on your workstreams bill your own account instead of the
server host's:

```bash
hashd agents login claude      # or codex / gemini / copilot / qwen / kimi
```

Runs on a workstream you own refuse to dispatch until its owner has a live
credential for the run's agents; the refusal names the exact command. See
[AGENT_MANAGEMENT.md](AGENT_MANAGEMENT.md#per-user-credentials-team-servers)
for what each agent needs and how credential health is tracked.

## Password login (optional)

The token from `admin user add` is all a user needs. If you would rather log in
with a password than carry a token, use the setup-key path instead:

1. Operator issues a one-time setup key:

   ```bash
   hashd admin user reset-key alice@example.com
   ```

2. Alice points at the server and redeems the key, then logs in:

   ```bash
   hashd server set https://<lan-ip>:1337
   hashd set-password --key <hsk-setup-key>
   hashd login alice@example.com
   ```

   `login` stores a client token, after which usage is the same as the token
   path. `reset-key` is also the password-reset path: issue a new key, redeem it,
   set a new password.

## Troubleshooting

- **`bearer token is required` (401).** The server is off-loopback and your
  client has no token, or the token is not stored. Re-run
  `hashd server set <url> --token <token>`.
- **`server certificate fingerprint mismatch`.** The token you paired with was
  minted for a different certificate than the server now serves (for example the
  ops dir's `tls/` was regenerated). You need a token minted against the *current*
  certificate.

  If someone else runs the server, ask them for a fresh token and re-pair with
  `hashd server set <url> --token <token>`.

  **If you are the operator on that host, you have to break a chicken-and-egg:**
  every command goes through the pinned client, including `hashd auth create` --
  so you cannot mint the token that would restore trust, and even
  `hashd server unset` is refused. Clear the stale pin *first*, then mint against
  the live certificate:

  ```bash
  hashd server unset          # drop the stale pin; run on the server host
  hashd restart --yes         # ensure the server is up on its current cert
  hashd auth create           # now reachable: mints a token carrying the CURRENT pin
  hashd server set https://<host>:1337 --token <that token>
  hashd restart --yes
  ```

  `hashd admin user add <email>` is the other way out, and the better one when
  the client cannot reach the server at all: it is host-local, writes directly to
  the ops DB, and its token carries the current pin -- so it works even when
  every pinned path is refused.
- **`cannot connect to hashd-server`.** The server is not reachable at that
  address -- check the URL, that `hashd restart server` succeeded on the host,
  and that the LAN address and port are open.
- **Which certificate is the server serving?** On the host:
  `openssl x509 -in <ops-dir>/tls/server.crt -noout -fingerprint -sha256`.

## Solo shared-repo mode

There is a third, unmanaged shape: several developers each run their own **solo**
hashd against the **same git repository**, with each person's per-project state
living side by side under `.hashd`, and **no server** coordinating them. Git is
the only shared substrate -- people see each other's work through commits, not
through a live server.

This works, but it is **not recommended** for real collaboration: there is no
shared workstream registry, no cross-user gate, and no single source of truth for
in-flight state. Prefer a server (above) when more than one person is driving
work on the same project.
