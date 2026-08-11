# Codex: read this first

You are in the **event-streams** repo. Everything you need is already here —
the skill, both data connections, and the credentials.

## Setup

If `./setup.sh` has not been run in this folder yet, run it. One command, and
it only touches this folder:

```bash
./setup.sh
```

Credentials are already filled in at **`.env`** in the repo root. You do not
need to ask anyone for a key. All of them live there:
`AI_ARK_API_KEY`, `NOCODB_MCP_TOKEN`, `NOCODB_MCP_URL`, `DISCOVERY_URL`.

Never print a credential's value into the conversation, and never paste one
into a chat message. Read them from `.env` and use them.

## What works in Codex

| | Codex |
|---|---|
| The `event-streams` skill | works |
| Test mode (trialling keywords) | works |
| Reading stream rows from NocoDB | works |
| **Enriching contacts via AI Ark** | **works through the project STDIO bridge** |

AI Ark's remote endpoint still returns plain JSON after negotiating an event
stream, so Codex cannot use it as direct Streamable HTTP. This repo's
`.codex/config.toml` launches pinned `mcp-remote@0.1.37` over STDIO instead.

**Read [`../docs/codex-ai-ark-setup.md`](../docs/codex-ai-ark-setup.md)** for
the exact wiring and troubleshooting steps.

If the tools are missing, run `./setup.sh` and restart Codex. Node.js/npm is
required because the bridge launches through `npx`. Do not replace the bridge
with a direct `url = ...` entry while AI Ark still returns plain JSON.

## The skill itself

[`../.claude/skills/event-streams/SKILL.md`](../.claude/skills/event-streams/SKILL.md) — the canonical copy
read by both agents.

Start at [`../docs/INDEX.md`](../docs/INDEX.md) for everything else.
