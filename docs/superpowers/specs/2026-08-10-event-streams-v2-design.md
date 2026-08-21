# event-streams v2 — design

**Date:** 2026-08-10
**Status:** awaiting user approval
**Supersedes:** the script-backed `event-streams` skill in `atiksh17/event-sourcing`

---

## What changes and why

The v1 skill drove a Python package: `PYTHONPATH=src .venv/bin/python -m stream.cli`,
ten subcommands, a Google Sheet as control plane, and the whole discovery layer
(JustGiving, Google News, GDELT crawling and judging) running locally.

That discovery layer now lives behind an n8n endpoint and a NocoDB base. The
skill no longer needs to *do* discovery — it needs to *ask for it*, and to
enrich what comes back. So v2 has no Python, no virtualenv, no scripts of its
own. It is a markdown skill plus two MCP servers.

**Goal:** one person who does not know how any of this works clones a repo, runs
one command, and can immediately (a) trial keyword/prompt combinations and
(b) turn yesterday's automated results into an enriched CSV.

## Non-goals

- No skill-owned scripts. The one shell script in the repo is `setup.sh`, and it
  runs once at install, never during skill operation.
- No writes to NocoDB. Production mode is read-only against the base.
- No discovery in production mode; no NocoDB in test mode. The two modes share
  no integration at all, which is what keeps each one explainable.
- No marketplace publication. This is built for a single named user.

---

## Architecture

Two modes that touch disjoint systems.

```
TEST MODE                              PRODUCTION MODE
  user: keywords + prompt                user: "enrich rows 1-40 of <table>"
        │                                      │
        ▼                                      ▼
  POST n8n /webhook/stream              NocoDB MCP  (read only)
        │  (5-15 min, backgrounded)            │
        ▼                                      ▼
  JSON array of judged companies        rows already judged by the
        │                               automated daily stream
        ▼                                      │
  show table, user critiques,                  ▼
  rewrite prompt, re-run                 ask user for job titles
        │                                      │
        ▼                                      ▼
  user adds the winning row to           AI Ark MCP → people + email + LinkedIn
  the NocoDB Streams tab by hand                │
                                                ▼
                                         data/<table>-YYYY-MM-DD.csv
```

Test mode never sees NocoDB. Production mode never sees the discovery endpoint.

### Why the modes are split this way

The NocoDB `Streams` table is a scheduler: a row there means "run these keywords
against this prompt every day, forever". Test mode exists precisely so a bad row
never gets added. Letting test mode write to `Streams` would let a five-minute
experiment become a permanent daily cost, so the skill prints the row and the
user adds it. That is a deliberate manual gate, not an omission.

---

## Repository layout

Standalone repo at `~/Documents/event-streams`, published to
`github.com/atiksh17/<repo-name>` (private).

```
event-streams/
├── .claude/
│   ├── skills/event-streams/SKILL.md   canonical skill — the only real copy
│   └── settings.json                   enableAllProjectMcpServers: true
├── .codex/
│   ├── skills/event-streams  →  ../../.claude/skills/event-streams   (symlink)
│   └── config.toml                     Codex MCP wiring
├── .mcp.json                           Claude MCP wiring
├── setup.sh                            the one command
├── CLAUDE.md                           router
├── AGENTS.md                           identical mirror of CLAUDE.md
├── README.md                           paste-block for a non-technical user
├── docs/
│   ├── INDEX.md
│   ├── test-mode.md
│   ├── production-mode.md
│   ├── troubleshooting.md
│   └── reference/endpoints.md
└── data/.gitkeep                       CSV output lands here
```

### Skill discovery — verified, not assumed

Both facts were tested in this session rather than read from documentation:

| Harness | Path | How it was verified |
|---|---|---|
| Claude Code | `.claude/skills/<name>/SKILL.md` | The harness announced `event-sourcing:event-streams` when a nested skill was read. |
| Codex | `.codex/skills/<name>/SKILL.md` | Planted `zzz-probe-skill` in a scratch repo; `codex exec` listed it beside its built-ins. |

Cloning is therefore sufficient to install the skill itself. `setup.sh` exists
for the MCP servers, not the skill.

### One canonical SKILL.md

`.codex/skills/event-streams` is a **git symlink** to the `.claude` copy. Two
real files drift, and the copy that drifts is the one nobody reads.

Windows clones need `git config --global core.symlinks true`. The README says
so, and a parity check in `setup.sh` fails loudly if the symlink has become a
divergent regular file.

---

## Install

Two paths. Both work; the second is the supported one.

**Zero-command.** `.mcp.json` plus `enableAllProjectMcpServers: true` in
`.claude/settings.json` wires both MCP servers on clone with no approval dialog.
Codex reads `.codex/config.toml` after its one-time repo-trust prompt.

**One-command.** `./setup.sh`:

1. Verifies `claude` and `codex` are on PATH; skips either half if absent rather
   than failing.
2. `claude mcp add --transport http --scope user` for both servers.
3. Merges `[mcp_servers.*]` blocks into `~/.codex/config.toml`, idempotently.
4. Checks the `.codex/skills` symlink resolves to the `.claude` copy.
5. `mkdir -p data`.
6. Verifies both servers answer, and exits non-zero if either does not.

`--scope user` means the MCPs work in every directory, not only this repo. The
zero-command path only covers this repo — that difference is why `setup.sh` is
the documented route.

Full user-facing install:

```bash
git clone https://github.com/atiksh17/<repo>.git && cd <repo> && ./setup.sh
```

### MCP wiring — exact, verified configs

**AI Ark.** Remote HTTP. The token is a **query parameter**, not a header
(from `docs.ai-ark.com/docs/mcp`):

```
https://api.ai-ark.com/v1/mcp?token=<AI_ARK_API_KEY>
```

**NocoDB.** Remote HTTP with a custom header `xc-mcp-token`. Per
`nocodb-mcp.md`, the config NocoDB's own UI generates does not work on
self-hosted: `mcp-remote` only speaks OAuth, which self-hosted NocoDB does not
have ([nocodb#12692](https://github.com/nocodb/nocodb/issues/12692)). Use native
HTTP transport.

```
https://db.lrc-limited.com/mcp/ncuiv55fi0t1x0em
header: xc-mcp-token: <NOCODB_MCP_TOKEN>
```

**The Codex problem, and its fix.** `codex mcp add` exposes only
`--bearer-token-env-var` — there is no `--header` flag, so NocoDB cannot be
added from the Codex CLI at all. Inspecting the binary's TOML schema shows
`http_headers` and `env_http_headers` are supported *in the config file* even
though no flag reaches them. `setup.sh` therefore writes Codex's NocoDB entry
directly rather than shelling out to `codex mcp add`:

```toml
[mcp_servers.nocodb-streams]
url = "https://db.lrc-limited.com/mcp/ncuiv55fi0t1x0em"
[mcp_servers.nocodb-streams.http_headers]
"xc-mcp-token" = "<token>"

[mcp_servers.ai-ark]
url = "https://api.ai-ark.com/v1/mcp?token=<key>"
```

This is the only route by which NocoDB reaches Codex. Do not replace it with
`codex mcp add` on the assumption a flag was missed.

### Secrets

Real API keys are committed to the repo. This is the user's explicit decision,
made on the grounds that the repo is private and the skill is for one person.

Recorded consequences, so nobody has to rediscover them: git history is
permanent, so a leaked key is rotated by issuing a new one rather than by
rewriting history; every clone carries the keys; and "private" is a setting that
can later be changed by someone who does not know what is inside.

The NocoDB token should be a **read-only / fine-grained** token. Production mode
never writes, so the restriction costs nothing — and `deleteRecords` against the
live base has no undo. Enforce it at the token, not by trusting the agent.

---

## Test mode

### Contract

```
POST https://n8n.lrc-limited.com/webhook/stream
Content-Type: application/json

{ "keywords": "a, b, c", "qualificationPrompt": "..." }
```

Response: a JSON array of judged companies, each

```json
{
  "companyName": "Aveva",
  "relevant": true,
  "confidence": 85,
  "reason": "…why it passed or failed…",
  "source": "justgiving",
  "content": "…the article text the judgement was made from…"
}
```

`https://n8n.lrc-limited.com/webhook-test/stream` is the n8n *test* URL. It is
single-shot — it 404s with `"The requested webhook \"stream\" is not
registered"` until someone clicks **Execute workflow** on the canvas, and dies
again after one call. It belongs in the docs as a debugging aid; the skill only
ever calls the production URL.

### The 15-minute problem

A discovery run takes 5–15 minutes and the endpoint blocks for the whole
duration. **Claude Code caps a foreground shell command at 10 minutes** (the
Bash tool's documented `timeout` maximum is 600000 ms). A plain blocking `curl`
is therefore killed by the tool, not by n8n, and the failure looks exactly like
a dead endpoint.

Codex's own foreground cap has not been measured. Rather than depend on it, the
skill uses one backgrounded shape that is safe under any cap.

The skill therefore always backgrounds the call to a file and polls:

```bash
mkdir -p data/.runs
curl -sS --max-time 1800 -X POST https://n8n.lrc-limited.com/webhook/stream \
  -H 'Content-Type: application/json' \
  -d @data/.runs/<run>.request.json \
  -o data/.runs/<run>.response.json \
  -w '%{http_code}' > data/.runs/<run>.status 2>&1 &
```

Then poll for `<run>.status`. This shape works identically in Claude Code and
Codex, which is why it is preferred over either harness's native background
mechanism.

The skill must tell the user the run takes 5–15 minutes **before** starting it.
A silent ten-minute wait reads as a hang.

### The loop

1. Take keywords and a qualification prompt from the user. If either is vague,
   ask — a bad prompt costs fifteen minutes to discover.
2. Warn about the duration, fire the backgrounded request, poll.
3. Render results as a table: company, relevant, confidence, one-line reason.
   `content` is long; show it only on request.
4. Report the pass rate. Invite the specific critique — too broad, too narrow,
   wrong industry, right companies but wrong signal.
5. Rewrite the prompt against that critique, show the diff, re-run on approval.
6. When the user is satisfied, print the `Streams` row for them to paste into
   NocoDB. The skill does not write it.

### Failure handling

| Symptom | Meaning | Skill does |
|---|---|---|
| HTTP 404 `webhook … not registered` | test URL used, workflow not armed | Say so; point at the production URL |
| Empty array | keywords matched nothing | Report as a keyword problem, not a fault |
| All `relevant: false` | prompt too strict | Report as a prompt problem; offer a loosened rewrite |
| Non-JSON body | n8n returned an error page | Show the first 500 bytes rather than parsing |
| `.status` never appears | run exceeded 30 min | Report the timeout; do not silently retry a paid run |

---

## Production mode

The daily automated stream has already done discovery and judging. The skill
picks up from the rows.

1. User names a table and which rows — "the new ones", "rows 1–40", "everything
   from yesterday". The user is the authority on scope, because their view of
   the base is not necessarily the skill's.
2. Read those rows via the NocoDB MCP (`getTablesList`, `getTableSchema`,
   `queryRecords`). Never `createRecords`, `updateRecords`, or `deleteRecords`.
3. **Ask for job titles. Every time, before anything is spent.** Never carry
   titles over from an earlier run in the same conversation, and never infer
   them from the table. Offer the previous run's titles as a *suggestion* the
   user must confirm.
4. Confirm the scope out loud: N companies × the named titles. Wait for yes.
5. Enrich company by company via the AI Ark MCP. Isolate failures — one company
   that returns nothing must not abort the batch. Record why each empty one was
   empty.
6. Write the CSV. Report coverage honestly: companies in, people out, how many
   have an email, how many have a LinkedIn, and how many companies returned
   nothing.

### Reserved tables

Two tables in the base are not streams:

- **`Streams`** — the scheduler. Read to list what is running. Never written.
- **`Template`** — marked *Do not delete*. Never read as a data source, never
  written, never offered as an enrichment target.

Every other table is an individual stream and a valid target.

### Output

`data/<table-slug>-YYYY-MM-DD.csv`, created under the working directory, unless
the user states a different convention — in which case theirs wins and the skill
does not argue.

Columns: `company`, `person_name`, `job_title`, `email`, `linkedin_url`,
`source_table`, `enriched_at`. Final column list is fixed after the first real
AI Ark call, not before.

One row per person. Companies that returned no people appear in the run report,
not as blank CSV rows.

---

## Documentation

Four files, following the shape that worked in `event-sourcing`:

| File | Job |
|---|---|
| `README.md` | Router plus a five-line block the user pastes to their agent |
| `docs/test-mode.md` | The loop, prompt-writing guidance, what good output looks like |
| `docs/production-mode.md` | Reading rows, job titles, reading the coverage report |
| `docs/troubleshooting.md` | Every failure in the two tables above, with its fix |
| `docs/reference/endpoints.md` | Exact URLs, headers, payloads, MCP tool names |

`CLAUDE.md` and `AGENTS.md` are identical and point at `docs/INDEX.md`. Setup
documentation is addressed to the *agent*, with an explicit split between what
the agent runs and what only a human in a browser can do.

---

## Verification

The plan is not done until these pass on a clean checkout:

1. `git clone` into a scratch dir; both harnesses list the skill without any
   install step.
2. `./setup.sh` on a machine with no prior MCP config; `claude mcp list` and
   `codex mcp list` both show `ai-ark` and `nocodb-streams` connected.
3. `setup.sh` run twice — second run changes nothing.
4. A real test-mode run against the production endpoint returns a parsed table.
5. A real production-mode run over a small row range produces a CSV, and the
   skill asked for job titles before spending anything.
6. NocoDB token is read-only: a deliberate `createRecords` attempt is rejected
   by the server, not merely declined by the agent.

Point 6 matters most. Everything else is behaviour; that one is enforcement.

---

## Open items

Needed before implementation completes. None block starting.

| Item | Needed for |
|---|---|
| Repo name | `git init`, README, clone command |
| `AI_ARK_API_KEY` value | `.mcp.json`, `.codex/config.toml`, `setup.sh` |
| `NOCODB_MCP_TOKEN` value (read-only) | same |
| AI Ark MCP **tool names** | The enrichment steps in the skill |
| A real discovery response | Confirming the field names before parsing |
| Real NocoDB table names | Naming the reserved tables precisely |

**AI Ark's documentation never lists its MCP tool names.** The first
implementation task connects the server and enumerates them. Writing tool names
from memory is how the last project lost a day: *"Unit tests encode the shape
you assumed; they cannot disagree with you about what a third party returns.
Make one real call and record the field names before writing any parser."*
