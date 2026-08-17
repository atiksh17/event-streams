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
`NOCODB_MCP_TOKEN`, `NOCODB_MCP_URL`, `DISCOVERY_URL`, `N8N_API_KEY`. Nothing
to request from anyone, nothing to paste into a chat. Read them from that
file. This repo is private by design and `.env` is deliberately committed,
which is why `.gitignore` does not list it.

`N8N_API_KEY` authenticates the n8n public API (`/api/v1`, header
`X-N8N-API-KEY`) and exists solely to stop a running execution — rule 7.
**Known broken as of 2026-08-17:** every endpoint returns
`{"message":"unauthorized"}` even though the API itself is live. It needs
re-issuing on `n8n.goautofusion.com`. Until then the stop step cannot run, and
a test that reaches its target keeps spending until it finishes on its own.

If the MCP servers are not connected yet, run `./setup.sh` once. It wires both
of them to this folder and nowhere else.

## Running as Codex

Both modes work in Codex. AI Ark's remote endpoint still returns plain JSON
after negotiating an event stream, which Codex's direct HTTP client rejects.
The project-scoped `.codex/config.toml` therefore launches the pinned
`mcp-remote` STDIO bridge for `ai-ark`; NocoDB remains direct HTTP.

If the `ai-ark` tools are missing, run `./setup.sh` and restart Codex. Node.js
and npm must be installed because Codex launches the bridge through `npx`.
Read [docs/codex-ai-ark-setup.md](docs/codex-ai-ark-setup.md) for the exact
wiring and troubleshooting steps.

## Two modes, and the two crossings between them

**Test mode** — trialling keywords, sources and a qualification prompt. It is
one workflow no longer: **two endpoints, fired in order**, split so a failure
lands in an identifiable half. Both halves proven end to end 2026-08-17.

**0. Ask for all four inputs before firing anything.** Keywords, qualification
prompt, sources, and **how many qualified results to stop at — default 10**.
Say that a higher number makes the test slower. If the user asks you to write
the keywords or the prompt, keep the keyword list short, keep the prompt close
to what they asked for, and ask questions when their intent is unclear.

**1. Discovery** — `POST https://n8n.goautofusion.com/webhook/stream`. Banks
every scraped item into the **Source Tray** (`m3s2n0eevrh9d5p`), ~5.5 minutes.
Rows appearing means it is working; nothing is stopped at this stage. It is
finished when the row count stops rising for 20–60 seconds.

**2. Qualification** (a.k.a. relevance check) —
`POST https://n8n.goautofusion.com/webhook/qualification`. Body is exactly two
fields: `data`, holding **every Source Tray row** as an object with the tray's
column names as keys, and `qualificationPrompt`, the camelCase string carried
identically on every one of those rows. Winners land in the **Relevance Tray**
(`mz8e0h1xfwalzeh`) over roughly **10–15 minutes** at a **10–20% pass rate**,
so poll patiently. Stop the execution the moment the tray hits the target —
rule 7.

**3. Enrichment, only if the user likes what came back.** Show the qualified
companies, ask their opinion, and on a yes run the **unchanged production-mode
AI Ark procedure** — screening, job titles, spend confirmation, all of it.

Both trays are disposable scratch space, **read-only to the agent**, and the
only NocoDB steps 1 and 2 touch.

**Production mode** — enriching rows a daily stream already collected.
Touches NocoDB and AI Ark only. Never calls discovery or qualification.

**Managing the stream records themselves** — creating a stream, editing its
config, starting or stopping it — is a write to the `Streams` table, allowed
from either mode and only ever on the user's explicit yes. See rule 4 and the
`## Writing to Streams` section of the skill.

If a task pulls you toward the discovery or qualification endpoint while in
production mode, you have the wrong mode — stop and re-read the skill.

## Seven rules that must not need a lookup

1. **Never print a secret.** Not a key, not a token. They live in
   `.env`. To check whether one is set, print whether it's set
   and how long it is — never its value.
2. **Job titles are asked for every single time**, before any
   production-mode spend, no exceptions. Titles from an earlier run in the
   same conversation may be *offered*, never carried over silently.
3. **News publications are never enriched without their own explicit yes.**
   The streams read news sites, so publications sweep into every batch and
   roughly nine in ten are not leads. Flag each one, re-read its article
   against the qualification prompt, give the user the full context, and ask
   per row — separately from the spend confirmation. Same for *dodgy* rows,
   where the qualifying evidence actually belongs to another company named
   inside the article. "Enrich the rest" covers the clean rows only.
4. **The only table ever written is `Streams`, and never without the
   user's explicit yes.** The agent may create a stream, edit its config,
   and start or stop it — `createRecords` and `updateRecords` against
   **`Streams`** (`mfo88n8n35b9qvl`), in six columns and no others:
   `Stream Name`, `Stream Description`, `Keywords`, `Qualification Prompt`,
   `Sources`, `Enabled`. Everything else on the row — `Table ID`,
   `Last Run`, `Last Run Status`, any state or totals column — belongs to
   the automated daily system and is never touched. **Confirm the exact
   write every single time**; a yes to the conversation, or to the test run
   that produced the values, is not a yes to the write. **Starting a stream
   means setting `Enabled` true, stopping it means setting `Enabled`
   false** — both confirmed first, naming the stream. **A new stream row is
   always created with `Enabled` false**, whatever the user said about
   wanting it live; enabling it is a separate question asked afterwards.
   `deleteRecords` is never called on anything, and **`Template (DO NOT
   TOUCH)`** (`m0liglo73sxjwa8`) is never even read. Every other table is
   one stream's data — read-only, reached through the `Table ID` column of
   that stream's row, never by guessing its name.
5. **Test mode owns the two endpoints and the two trays; production mode owns
   AI Ark and the streams' own tables.** Reaching for an endpoint from
   production mode means the task has been misread. **Two crossings are
   deliberate and both need their own yes:** saving a tested stream into
   `Streams`, and enriching a test's qualified companies through the
   production procedure — gates included, never a shortcut around them.
6. **`webhook/` is the default; `webhook-test/` is the *dev endpoint*.**
   Fire `webhook/` for every test-mode run — it needs no arming. Use a dev
   endpoint **only when the user has said they are the developer exercising
   the backend**; the words "test", "testing" and "test mode" are not that
   statement. Never call `webhook-test/` a "test endpoint" — test mode is a
   user mode, and conflating the two is how a routine run fires an unarmed
   URL. Dev endpoints are single-shot and **only a human can arm them**: they
   answer exactly one call after someone clicks *Execute workflow* on the n8n
   canvas, then disarm, and an unarmed call 404s in half a second. Ask, wait
   for confirmation, fire once. Never retry blind.
7. **Stopping a run means stopping one execution, never a workflow.**
   `POST /api/v1/executions/<id>/stop` with header `X-N8N-API-KEY` from
   `.env`, and `<id>` read from the `Execution ID` column of a tray row **this
   run wrote**. Never `/workflows/{id}/deactivate` — that switches off the
   daily production stream and fails silently. If the key returns
   `unauthorized`, say so and stop polling; the run is still spending.

Full detail per mode: [docs/test-mode.md](docs/test-mode.md),
[docs/production-mode.md](docs/production-mode.md). Exact endpoint and tool
facts: [docs/reference/endpoints.md](docs/reference/endpoints.md).
Something broken: [docs/troubleshooting.md](docs/troubleshooting.md).
