# Event Streams — agent instructions

This repo holds the `event-streams` skill: finding companies whose staff are
doing organised events, and finding the senior people to contact at them.

The skill itself lives at `.claude/skills/event-streams/SKILL.md`
(canonical) — `.codex/skills/event-streams` is a symlink to the same
directory, kept in sync automatically. Read the skill first; it is short
and complete for both modes. Do not edit the `.codex` path, and do not
convert the symlink to a real file.

Start at [docs/INDEX.md](docs/INDEX.md) for the full doc map — it lists
every doc in this repo with a "read this when..." line.

## Credentials

Every key is already in **`.env`** at the repo root — `AI_ARK_API_KEY`,
`NOCODB_MCP_TOKEN`, `NOCODB_MCP_URL`, `DISCOVERY_URL`. Nothing to request from
anyone, nothing to paste into a chat. Read them from that file. This repo is
private by design and `.env` is deliberately committed, which is why
`.gitignore` does not list it.

If the MCP servers are not connected yet, run `./setup.sh` once. It wires both
of them to this folder and nowhere else.

## Running as Codex? One thing does not work

Enrichment via AI Ark fails in Codex — `Transport channel closed`, or a tool
call reporting `tools.mcp__ai_ark__… is not a function`. It is an upstream bug
in AI Ark's server, not a fault in this repo, and not something the user did.

Test mode and reading NocoDB both work in Codex. Only enrichment is affected.

Read [docs/codex-ai-ark-setup.md](docs/codex-ai-ark-setup.md) before trying
anything. The one-step fix is to open this same folder in Claude Code — same
skill, same `.env`, nothing to reconfigure.

## Two modes, and they share nothing

**Test mode** — trialling keywords, sources and a qualification prompt. Touches the
discovery endpoint only. No NocoDB, no AI Ark, nothing is spent.

**Production mode** — enriching rows a daily stream already collected.
Touches NocoDB and AI Ark only. Never calls the discovery endpoint.

If a task pulls you toward NocoDB while in test mode, or toward the
discovery endpoint while in production mode, you have the wrong mode —
stop and re-read the skill.

## Four rules that must not need a lookup

1. **Never print a secret.** Not a key, not a token. They live in
   `.env`. To check whether one is set, print whether it's set
   and how long it is — never its value.
2. **Job titles are asked for every single time**, before any
   production-mode spend, no exceptions. Titles from an earlier run in the
   same conversation may be *offered*, never carried over silently.
3. **Nothing in production mode writes to NocoDB.** `createRecords`,
   `updateRecords`, and `deleteRecords` are never called — the base belongs
   to the automated daily system, not to a one-off enrichment run.
4. **Test mode and production mode share nothing.** Each touches exactly
   one external system. Reaching for the other's system means the task has
   been misread.

Full detail per mode: [docs/test-mode.md](docs/test-mode.md),
[docs/production-mode.md](docs/production-mode.md). Exact endpoint and tool
facts: [docs/reference/endpoints.md](docs/reference/endpoints.md).
Something broken: [docs/troubleshooting.md](docs/troubleshooting.md).
