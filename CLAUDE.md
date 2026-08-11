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

## Two modes, and they share nothing

**Test mode** — trialling keywords and a qualification prompt. Touches the
discovery endpoint only. No NocoDB, no AI Ark, nothing is spent.

**Production mode** — enriching rows a daily stream already collected.
Touches NocoDB and AI Ark only. Never calls the discovery endpoint.

If a task pulls you toward NocoDB while in test mode, or toward the
discovery endpoint while in production mode, you have the wrong mode —
stop and re-read the skill.

## Four rules that must not need a lookup

1. **Never print a secret.** Not a key, not a token. They live in
   `credentials.env`. To check whether one is set, print whether it's set
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
