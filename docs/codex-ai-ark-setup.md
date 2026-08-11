# AI Ark in Codex

AI Ark enrichment works in Codex through a project-scoped STDIO bridge. The
bridge is already declared in `.codex/config.toml`; a clone does not need a
global MCP server entry.

Run once after cloning:

```bash
./setup.sh
```

Then restart Codex so it reloads the project MCP configuration. Node.js and
npm are required because Codex launches the bridge with `npx`.

## Why a bridge is necessary

AI Ark's MCP endpoint does two contradictory things:

1. It refuses a request unless the client advertises
   `Accept: application/json, text/event-stream`.
2. It replies with ordinary JSON (`content-type: application/json`) instead
   of an event stream.

Codex's direct Streamable HTTP client correctly expects the negotiated event
stream and closes the transport when it receives JSON. The familiar symptom
is `Transport channel closed`. Claude Code tolerates the same server response.

The project avoids Codex's direct HTTP path:

```text
Codex <-> local STDIO <-> mcp-remote <-> AI Ark HTTP/JSON
```

`mcp-remote` accepts proper MCP over STDIO from Codex and uses a tolerant HTTP
client for AI Ark. Version `0.1.37` completed both `initialize` and
`tools/list` against the live AI Ark server on 2026-08-11. A separate fresh
Codex process also loaded the project MCP and successfully called
`industry_search`; no paid enrichment call was used for verification.

## Project-scoped configuration

`setup.sh` generates this shape in `.codex/config.toml`:

```toml
[mcp_servers.ai-ark]
command = "npx"
args = [
  "-y",
  "mcp-remote@0.1.37",
  "https://api.ai-ark.com/v1/mcp?token=<AI_ARK_API_KEY>",
  "--transport",
  "http-only"
]
startup_timeout_sec = 120
```

The actual key comes from `.env`; never print it while inspecting the config.
The bridge version is pinned so every clone uses the version that was tested,
rather than silently changing behavior when npm publishes a new release.

Codex ignores project MCP configuration until the project is trusted. The
server declaration remains inside this repo; `setup.sh` adds only the trust
marker for this clone's path to the user's Codex config. It also removes old
global event-streams MCP blocks so they cannot shadow the project entry.

## What setup verifies

The full `./setup.sh` run checks more than configuration presence:

- `codex mcp list` sees `ai-ark` in this project.
- The server is absent from an unrelated directory.
- `npx` is installed.
- The pinned bridge starts and completes a real, free MCP `initialize` call.
- NocoDB independently returns a valid event stream over direct HTTP.

The bridge's stderr is deliberately suppressed during the probe because
`mcp-remote` logs its remote URL, and AI Ark's URL contains the API key.

## Troubleshooting

### AI Ark tools are missing

Run `./setup.sh`, restart Codex, and open the cloned folder as the trusted
project. MCP servers are loaded at session startup; changing the TOML does not
inject tools into a session that is already running.

### `npx` was not found

Install Node.js/npm, then re-run `./setup.sh`. The first launch needs network
access to download `mcp-remote@0.1.37`; npm can reuse its cache afterwards.

### `Transport channel closed`

The session is probably using a stale direct configuration. Regenerate with
`./setup.sh` and confirm—without printing the credential—that the `ai-ark`
entry has `command = "npx"` and no top-level `url` field. Restart Codex.

### The bridge times out

Check network access, npm availability, and the AI Ark credential, then run
`./setup.sh` again. The setup probe allows 120 seconds for first-time package
download and initialization.

## If AI Ark fixes its endpoint

The bridge can be reassessed if AI Ark begins replying with a real
`text/event-stream`. Do not switch back based on an announcement alone: probe
the live endpoint, then test both `initialize` and `tools/list` from Codex.
Until that succeeds, keep the pinned bridge.
