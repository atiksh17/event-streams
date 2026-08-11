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

## What works in Codex, and what does not

| | Codex |
|---|---|
| The `event-streams` skill | works |
| Test mode (trialling keywords) | works |
| Reading stream rows from NocoDB | works |
| **Enriching contacts via AI Ark** | **does not work** |

If enrichment fails with `Transport channel closed`, or a tool call reports
`tools.mcp__ai_ark__… is not a function`, that is the known issue — **not**
a mistake in this repo and not something the user did.

**Read [`../docs/codex-ai-ark-setup.md`](../docs/codex-ai-ark-setup.md)** for
what is wrong, the workarounds, and how to check whether it has been fixed.

Short version: AI Ark's server demands an event-stream reply then sends plain
JSON. Codex's client refuses it; Claude Code tolerates it. The quickest path
is to open this same folder in Claude Code for the enrichment step — same
skill, same credentials, nothing to reconfigure.

Do not "fix" `.codex/config.toml`. It is correct and identical to the working
Claude Code configuration.

## The skill itself

[`skills/event-streams/SKILL.md`](skills/event-streams/SKILL.md) — a symlink
to the canonical copy under `.claude/`, so both agents read exactly one file.

Start at [`../docs/INDEX.md`](../docs/INDEX.md) for everything else.
