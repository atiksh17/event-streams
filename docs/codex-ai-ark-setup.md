# Getting AI Ark working in Codex

**Read this if you are Codex and the enrichment step failed**, or if you saw
`Transport channel closed` / `tools.mcp__ai_ark__* is not a function`.

Short version: **NocoDB works in Codex. AI Ark does not.** Everything else in
this repo — the skill, test mode, reading stream rows — works in Codex today
with no extra steps. Only the enrichment step is affected.

Nothing here is a mistake in this repo's configuration. The config is correct
and identical to the one Claude Code uses successfully. Do not "fix" it by
editing `.codex/config.toml`; you will change a correct file.

---

## What is actually wrong

AI Ark's MCP server does two contradictory things.

1. It **refuses** a request unless you tell it you can accept an event stream.
   Send `Accept: application/json` on its own and it answers `400`.
2. It then **replies with ordinary JSON**, not an event stream —
   `content-type: application/json`.

Claude Code shrugs at this and carries on. Codex's MCP client takes the server
at its word: it asked for a stream, it did not get one, so it treats the
connection as broken and reports `Transport channel closed`. The tools from
that server then never appear, which is why a tool call fails with
`is not a function` rather than an error from AI Ark.

Verified on 2026-08-11 by calling both servers with identical headers:

| Server | Replies with | Works in Codex |
|---|---|---|
| NocoDB | `text/event-stream` | yes |
| AI Ark | `application/json` | no |

The fix belongs to AI Ark. Everything below is a way to work around it in the
meantime.

---

## Option 1 — use Claude Code for enrichment (recommended)

The least effort and the only option with nothing to maintain.

1. Do discovery and testing in whichever agent you like.
2. When you need contacts, open this same folder in Claude Code and ask for
   the enrichment there.

Both agents read the same skill file and the same `.env`, so nothing is lost
by switching. Claude Code has been verified end to end: it reads the NocoDB
rows and completes real AI Ark calls.

---

## Option 2 — bridge the connection with a helper

There is a standard bridge, `mcp-remote`, that sits between Codex and a remote
MCP server. Codex talks to the bridge, the bridge talks to AI Ark, and the
mismatch stops mattering.

**This is unverified.** When tried on 2026-08-11 it hung during startup and
never connected, most likely because it tries to negotiate a login that AI Ark
does not offer. It is written down because it may work on a different machine
or a newer version — not because it is known good. If it hangs for more than
about two minutes, stop and use Option 1.

You need Node.js installed (`node --version` should print something).

Add this to your Codex configuration file at `~/.codex/config.toml`, replacing
the whole existing `[mcp_servers.ai-ark]` section:

```toml
[mcp_servers.ai-ark]
command = "npx"
args = ["-y", "mcp-remote@latest", "https://api.ai-ark.com/v1/mcp?token=PUT_THE_KEY_HERE", "--transport", "http-only"]
startup_timeout_sec = 120
```

Take the key from `AI_ARK_API_KEY` in this repo's `.env` file and paste it in
place of `PUT_THE_KEY_HERE`. The key is part of the web address, not a
separate setting — that is unusual, and it is why the address has a `?token=`
on the end.

Then check whether it worked:

```bash
codex mcp list
```

If AI Ark's tools become usable, tell the repo owner so this document can be
updated from "unverified" to "works".

---

## Option 3 — call AI Ark directly, without MCP

AI Ark has an ordinary web API that works from anywhere, including Codex. It
is more work than the other options because you are making the requests
yourself rather than having tools handed to you.

The address is `https://api.ai-ark.com`, and the key goes in a header called
`X-TOKEN` rather than in the web address. The two calls the enrichment step
needs are the people search and the single-person export.

Only reach for this if enrichment must happen in Codex specifically and
Option 2 did not work. Note that it steps outside how the skill is written —
the skill assumes MCP tools — so you are hand-rolling the step rather than
following the procedure.

---

## How to check whether AI Ark has fixed it

This costs nothing and takes a second. From this repo:

```bash
./setup.sh
```

Look at the end of the output. If you see:

```
warn codex ai-ark answers HTTP 200 with content-type 'application/json',
     not text/event-stream ...
```

then the bug is still there. If instead you see:

```
ok   codex ai-ark answers with text/event-stream
```

then **AI Ark has fixed it**, and no workaround is needed. Remove any changes
you made under Option 2, re-run `./setup.sh`, and enrichment will work in
Codex normally.

Please tell the repo owner if that happens, so this document and the notes in
[reference/endpoints.md](reference/endpoints.md) can be corrected. A stale
warning that says something is broken after it has been fixed causes its own
kind of confusion.

---

## What to tell the person you are helping

If you are an agent and enrichment just failed, do not present this as a
problem with their setup or something they did wrong. Say something close to:

> Enrichment can't run in Codex right now — AI Ark's server has a bug that
> Codex's connection handling doesn't tolerate. Everything else works here.
> The quickest path is to open this same folder in Claude Code and ask me
> there; nothing needs reconfiguring. Details are in
> `docs/codex-ai-ark-setup.md`.

Then stop. Do not attempt the workarounds unasked — Option 2 involves editing
their global Codex configuration, and that is their decision to make.
