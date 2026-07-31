# Hashd Architecture Notes

This document captures architecture rules that affect product behavior and
distribution. It is the public reference for rules that customer-facing docs,
developer docs, and release artifacts may cite.

## Client And Server Boundary

`hashd` is a thin Go client. Operator-visible diagnostics, queries, and mutations
go through the hashd-server REST API. Local mode means the client and server
run on the same host. Remote mode means the client runs elsewhere. Both modes
use the same code path.

UI clients, including the TUI and Telegram bot, do not directly mutate entity
state. They dispatch through server endpoints and react to published events.

## Public Interface Changes

CLI commands, subcommands, flags, and REST API patterns are public interfaces.
Changing or adding them requires explicit maintainer agreement on naming,
placement, and behavior before implementation.

Every `hashd` command must work non-interactively. Commands that prompt for
confirmation need a non-interactive confirmation flag, and commands that ask
for values need flags or arguments that provide those values in scripts.

## Event Bus And Durable Events

Every state change is published to the realtime event bus and recorded in
SQLite. the bus is ephemeral; SQLite is durable.

Two choke points cover state changes:

- FSM transitions for workstreams, stories, and suggestions.
- User-facing notification helpers.

Publishing must be non-blocking. If the realtime bus is down, the durable event
record still exists for catch-up consumers.

Side effects that must happen as part of a transition belong in the Go server
transition handler, next to the CAS write. They do not belong in a subscriber:
subscribers can be down, race the transition, and require catch-up machinery.

## State Model

Workstream display state is a combination of:

- `stage`: the macro lifecycle state, currently stored as `status`.
- `runtime_status`: a derived liveness/blocking status computed from primitive
  fields.
- `runner_stage`: the active substage inside a running stage.

The canonical user-facing state model lives in `WF.md`. Derived display fields
such as `runtime_status`, transitional status, and current errors are computed
server-side so CLI, TUI, bot, and future clients do not drift.

## Python And Go Ownership

Go owns server-side state mutation, FSM validation, operator-facing REST
surfaces, CLI command routing, and generated OpenAPI/sqlc contracts.

Python owns Prefect orchestration, runner flow bodies, and agent-stage glue.
Python wrappers that transition workstreams, stories, and suggestions delegate
to the Go server.

Generated artifacts are never hand-edited. SQL files, Go types with Huma
annotations, and `msgspec.Struct` definitions are authored sources. JSON
Schema, OpenAPI YAML/JSON, sqlc outputs, generated Prefect parameter types, and
generated Python DB/OpenAPI code are downstream artifacts.

## Canonical Parsers

Plan parsing and plan markdown mutation are Go-canonical in
`server/internal/plan`. Python consumers use the REST compatibility shim.

Duration parsing is Go-canonical in `server/internal/duration`. Python
consumers use the REST compatibility shim.

## Logging And Transcripts

Agent output is always logged. Agent stages run through the Go agent runner,
which streams wrapper logs, records transcripts, registers active invocations,
and emits stage-change events.

File logs live in workstream/run stage directories. Run transcripts live in the
run directory. Story transcripts are persisted through the events table and
rendered on demand.

## Diagnostics

User-facing errors use the structured Diagnostic shape on both Go and Python
sides. Diagnostics include a clear title, optional cause, subsystem source, and
concrete next steps.

Do not introduce parallel user-visible error formats for new work.

## Reviews And Concerns

Per-commit reviews are cumulative across runs. Final review lookups pull the
latest record.

Per-commit reviewer concerns form a single-shot workstream-level pool for the
first final review. Once consumed, the pool stays consumed for the workstream
lifetime.
