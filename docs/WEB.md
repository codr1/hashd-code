# WEB.md -- Web Frontend

Server-rendered HTML dashboard for Hashd. No SPA, no build step.

---

## Motivation

The TUI and Telegram bot cover terminal users and mobile. A web dashboard
serves browser-based monitoring and team visibility without installing
anything.

Same principle as every other frontend: call `lib/` functions directly,
render the result. No API gateway, no JSON API layer, no client-side
state management.

---

## Stack

- **Starlette** or **Litestar** -- async ASGI framework. Litestar uses
  msgspec natively, giving automatic request/response validation from the
  same Struct definitions used on the ZMQ bus.
- **Jinja2** -- server-rendered HTML templates.
- **HTMX** -- partial page updates via HTML-over-the-wire. `hx-get`,
  `hx-post`, `hx-swap`, `hx-target`. No client-side rendering.
- **SSE** -- server-sent events for live updates. The SSE endpoint
  subscribes to ZMQ and yields HTML fragments as SSE data frames.
- **Alpine.js** -- minimal client-side interactivity (confirm dialogs,
  dropdowns, collapsible panels). No build step.

HTMX (~14KB) and Alpine.js (~15KB) are single JS files, vendored into
`static/` or loaded from CDN. No npm, no bundler, no build step.

---

## Two Interaction Patterns

The web frontend follows the same two patterns as CLI, TUI, and Telegram:

**Commands (request/response):** User clicks a button -> HTMX sends
`hx-post` -> route handler calls `lib/` function -> Jinja2 renders HTML
fragment -> HTMX swaps it into the DOM.

**Events (push):** Background state change -> ZMQ event -> SSE endpoint
yields HTML fragment -> HTMX's SSE extension swaps via `hx-swap-oob`.
Status badges, workstream rows, and notification banners update live
without any JavaScript.

---

## Routes

```
GET  /                     Dashboard (workstreams + stories)
GET  /ws/{id}              Workstream detail
POST /ws/{id}/approve      Approve (returns updated status partial)
POST /ws/{id}/reject       Reject (returns updated status partial)
GET  /ws/{id}/log          Log panel content
GET  /ws/{id}/diff         Diff panel content
GET  /ws/{id}/timeline     Timeline panel content
GET  /events               SSE endpoint (ZMQ -> SSE bridge)
GET  /login                Auth page
```

Every route calls a `lib/` function (e.g., `dashboard_snapshot()`,
`workstream_snapshot()` from `snapshots.py`), renders a Jinja2 template,
and returns HTML. Same data as TUI and Telegram, different renderer.

---

## SSE + ZMQ Bridge

The `/events` endpoint subscribes to ZMQ and streams HTML fragments:

```python
async def events(request):
    sub = zmq_context.socket(zmq.SUB)
    sub.connect(XPUB_ENDPOINT)
    sub.subscribe(b"")

    async def generate():
        while True:
            raw = await sub.recv()
            event = msgspec.msgpack.decode(raw, type=Event)
            html = render_partial(event)
            yield f"event: update\ndata: {html}\n\n"

    return StreamingResponse(generate(), media_type="text/event-stream")
```

HTMX's SSE extension receives frames and swaps elements via
`hx-swap-oob="true"`. When a workstream changes state, the status badge
updates live without writing any JavaScript.

---

## Security

### Localhost bind

**Bind `127.0.0.1` by default.** Non-negotiable as a default. OpenClaw's
CVE-2026-25253 (CVSS 8.8) happened because the default bind was `0.0.0.0`,
exposing 21,000+ instances to the internet. If remote access is needed,
put a reverse proxy in front (Caddy gives auto-TLS in one line).

### Cookie auth

A random token generated on first run, stored in ops config (never
committed). Login page accepts the token, sets a cookie:

- `SameSite=Strict` -- prevents cross-origin requests from sending the
  cookie.
- `HttpOnly` -- not accessible to JavaScript.
- `Secure` -- HTTPS only (enforced when behind reverse proxy).

The `SameSite=Strict` cookie combined with HTMX's `HX-Request` header
provides CSRF protection without tokens. A cross-origin request will
neither send the cookie nor include the header.

### What is NOT needed

- OAuth / OIDC -- single-user tool, shared token is appropriate.
- JWT -- no distributed auth.
- API keys per client -- all frontends are trusted.
- Rate limiting -- event volume is negligible, all clients are ours.
- WAF -- bind localhost; reverse proxy handles this if exposed.

---

## File Layout

```
orchestrator/
    commands/
        web/
            __init__.py
            server.py          # ASGI app (Starlette or Litestar)
            routes.py          # HTTP route handlers
            sse.py             # ZMQ -> SSE bridge
            templates/         # Jinja2 + HTMX templates
                base.html
                dashboard.html
                detail.html
                partials/      # HTMX swap fragments
                    ws_status.html
                    ws_row.html
                    ...
```

---

## Dependencies

| Package    | Purpose                | Size   |
|------------|------------------------|--------|
| `starlette`| ASGI web framework     | ~300KB |
| `uvicorn`  | ASGI server            | ~200KB |
| `jinja2`   | HTML templates         | ~500KB |

---

## Implementation Checklist

1. Add `starlette`, `uvicorn`, `jinja2` to `pyproject.toml`.
2. `wf schema export` -- JSON Schema 2020-12 from msgspec Structs + pretty
   docs. TypeScript types via `json-schema-to-typescript` on the exported
   schema.
3. Create `commands/web/` with routes, templates, SSE bridge.
4. Implement dashboard + workstream detail pages.
5. Implement approve/reject via HTMX.
6. Implement SSE live updates.
7. Add auth middleware.

---

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| HTMX/SSE over SPA | Server-rendered HTML with partial updates. No client framework, no build step, no JSON API layer. Calls lib/ directly. |
| Alpine.js over React/Vue | ~15KB, no build step, handles only client-side UI state (dialogs, dropdowns). Server owns all data. |
| Starlette/Litestar over Flask | Async framework matches ZMQ async subscriber and Prefect. Litestar uses msgspec natively. |
| Localhost bind default | OpenClaw CVE-2026-25253 demonstrated the cost of defaulting to 0.0.0.0. |
| Cookie auth over API keys | Single-user tool. SameSite=Strict cookie + HX-Request header = CSRF protection without tokens. |
