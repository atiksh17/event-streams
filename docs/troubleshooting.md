# Troubleshooting

Symptom-first. Find what you're seeing, read what it means, do what it says.

## Install

| What you see | What it means | What to do |
|---|---|---|
| `claude not on PATH - skipping Claude Code install` | Claude Code isn't installed, or isn't on `PATH` | Install it, then re-run `./setup.sh` — or ignore this if you only use Codex |
| `codex not on PATH - skipping Codex install` | Codex isn't installed, or isn't on `PATH` | Install it, then re-run `./setup.sh` — or ignore this if you only use Claude Code |
| `codex ai-ark needs Node.js/npm (npx was not found)` | Codex uses a local STDIO bridge for AI Ark and cannot launch it without `npx` | Install Node.js/npm, then re-run `./setup.sh` and restart Codex |
| `.codex/skills/event-streams is a real file, not a symlink` | The repo was cloned on Windows without symlink support, so the symlink arrived as a plain file | `git config --global core.symlinks true`, then re-clone the repo |
| `setup.sh` exits non-zero with `one or more servers did not come up` | A server failed its post-install connection check | See "MCP server won't connect" below for the likely cause |
| **NocoDB MCP server won't connect — `404 {"msg":"MCP Token not found"}`** | `NOCODB_MCP_TOKEN` in `.env` is a NocoDB **API token** (works as `xc-token` against `/api/v2`), not an **MCP endpoint token** — two different credential types from the same product | Mint one in the NocoDB UI: base → Overview → Settings → Model Context Protocol → New MCP Endpoint. Put the base's MCP id in `NOCODB_MCP_URL` and the new MCP token in `NOCODB_MCP_TOKEN`, then re-run `./setup.sh`. **This is the single most likely thing to be broken on a fresh install** — see [reference/endpoints.md](reference/endpoints.md) for the exact URL and header shape. |
| **The NocoDB MCP token is write-capable** | Expected, not a misconfiguration — this endpoint's tool set is fixed and includes `createRecords`, `updateRecords`, and `deleteRecords`; there's no read-only variant to mint. Full verification and NocoDB-docs research: [reference/endpoints.md](reference/endpoints.md) | Detect with the free `tools/list` call and check whether those three names appear. **Never detect it by attempting a write, not even an empty-array `createRecords`** — a write succeeding is how you'd find out by damaging the base. The token permits far more than the skill does — `deleteRecords`, every table, every column — so the skill's own rules, not the credential, are what keep writes inside the confirmed six-column `Streams` path |
| AI Ark MCP server won't connect | `AI_ARK_API_KEY` is empty, wrong, or missing from `.env` | Get a key from https://app.ai-ark.com/settings/api-management/dashboard, set `AI_ARK_API_KEY` in `.env`, re-run `./setup.sh` |
| **`Transport channel closed` from Codex when calling AI Ark** | Codex is using a stale direct-HTTP `url = ...` entry instead of this repo's STDIO bridge, or the session started before the project config was regenerated | Run `./setup.sh`, confirm `.codex/config.toml` describes `ai-ark` with `command = "npx"`, then restart Codex. Do not print the URL or token while checking. |
| `codex ai-ark bridge timed out during initialize` | `npx` could not fetch/start the pinned bridge, or the AI Ark endpoint did not answer within 120 seconds | Check Node.js/npm and network access, then re-run `./setup.sh`. The setup probe suppresses bridge stderr because it contains the credential-bearing URL. |

## Test mode

| What you see | What it means | What to say |
|---|---|---|
| `404 ... webhook "stream" is not registered ... Click the 'Execute workflow' button` in ~0.5s | A **dev endpoint** (`webhook-test/`) was fired, and nobody armed it | Switch to `/webhook/stream` — the default, no arming needed. Only stay on a dev endpoint if the user said they're the developer, in which case ask them to click *Execute workflow* and fire once. Never retry blind |
| `{"message":"Workflow was started"}` from **`/webhook/qualification`** | **Success.** That endpoint acks in 1–13s and works in the background | Expected. Watch the Relevance Tray; results never come back in this response |
| `{"message":"Workflow was started"}` from **`/webhook/stream`** | Wrong for discovery — that one returns its rows | The workflow needs a *Respond to Webhook* node; results are not coming |
| Relevance Tray still empty a few minutes in | Normal. Qualification runs **10–15 minutes** at a **10–20% pass rate** | Keep polling every 30–60s. Only call it stalled after ~15 minutes of no movement |
| `401 unauthorized` from `/api/v1/executions/<id>/stop` | **`N8N_API_KEY` was minted on a different n8n instance.** This is the only cause seen; the request shape, header, base path and spec were all verified correct while it failed for a full day | Re-issue the key on `n8n.lrc-limited.com` → Settings → n8n API and paste it into `.env`. Do not investigate the request. Meanwhile say so plainly, stop polling, and tell the user the run is still spending |
| `200` with `"status":"canceled","finished":false` from the stop call | **Success.** Verified 2026-08-17 on execution 882 | Confirm by watching the Relevance Tray count go flat for ~60s. A `200` alone is not proof the writes stopped |
| `[]` | Keywords matched nothing | A keyword problem, not a fault |
| Every row `relevant: false` | Prompt too strict | A prompt problem — offer a looser rewrite |
| **`http=000 bytes=0`, `time` equal to the full `--max-time`** | **The current failure mode.** The origin accepts the connection and never writes a response. Confirmed 2026-08-14: host up, workflow active, GET answers in 0.53s — so this is neither an outage nor a slow run, and it is not caused by anything in the request. Four runs on 2026-08-13/14 varied prompt, keyword count (16 vs ~70) and sources, and hung identically at 30 minutes each | **Stop; do not re-fire.** Ask the owner to open the n8n execution log for those runs — the workflow often completes and the results are already there. Also check for executions still stuck in `running`: they can occupy workers and make every later request hang regardless of content. The fix is the workflow's response path, not the request |
| Body is not JSON | n8n returned an error page | Show the first 500 bytes, do not parse |
| ~~`error code: 524`~~ / ~~`error code: 1010` + HTTP 403~~ | **Historical, and structurally impossible now.** Both are generated only at Cloudflare's edge. The DNS record was grey-clouded 2026-08-12 and verified proxy-free 2026-08-14 — no `cf-ray`, no `server: cloudflare` | If either reappears, someone re-proxied the hostname; check the response headers before touching n8n. **What the 524 was hiding matters:** it was truncating the same non-response that now hangs, at ~120s, into a fast legible error. Removing the proxy did not break anything — it removed the thing that was making the breakage visible |

Same table as the skill's `## Test mode` section. Reasoning behind each row:
[test-mode.md](test-mode.md).

## Production mode

| What you see | What it means | What to do |
|---|---|---|
| A company returns nobody from `people_search` | Name mismatch against how AI Ark indexes the company, or job titles too narrow for that company's size | Not a failure by itself — record it in the report. `company_search` can confirm how the company is actually indexed if a name mismatch is suspected |
| `people_search` returns nobody across most of the batch | The job titles are too narrow — real HR departments rarely share one exact title string | Loosen to a short synonym list, e.g. "HR Manager, People Director, Head of People, CSR Manager" |
| LinkedIn % is well below 100 | An unusually thin match (a stale profile, a name collision) rather than a confident hit | Worth a second look — `people_search` finds people via their LinkedIn presence in the first place, so a low LinkedIn % is unusual |
| Email % is meaningfully lower than LinkedIn % | Expected, not a fault — `export_single` is a real-time per-person lookup, and not every professional has a discoverable email even when identity is confirmed | Normal at typical rates (~70%); flag to the user only if dramatically lower |
| A filter on industry, location, or technology matches nobody | These fields need an exact enum value; a free-text guess silently matches nothing instead of erroring | Resolve the exact token first via `industry_search` / `location_search` / `technology_search` — company name and job title don't need this |

Reasoning behind each row: [production-mode.md](production-mode.md).

## Writing to `Streams`

| What you see | What it means | What to do |
|---|---|---|
| A write to `Sources` is rejected or lands empty | `Sources` is a `MultiSelect` with exactly three choices — `Google News`, `LinkedIn`, `Justgiving`. Anything else isn't a variant, it's an invalid option | Send the literals exactly, as an array. `Google news`, `JustGiving`, `Linkedin` are all wrong — see [reference/endpoints.md](reference/endpoints.md) |
| `Enabled` reads back as `0` or `1` rather than `false`/`true` | Expected — it's a NocoDB `Checkbox`, stored as `0`/`1`, `default_value` `"0"` | Nothing to fix. Read `1` as running and `0` as stopped |
| A stream was started but its `Table ID` is still empty and there's no data table | Normal lag — the automated system creates the table and writes `Table ID` back on its own schedule | Say so plainly and wait. Never write a `Table ID` yourself; it's not one of the six writable columns |
| A field the user edited in NocoDB has reverted | A write re-sent unchanged fields and overwrote a human edit made between the read and the write | Send only the fields that changed, always. Re-read the row before the next write |
| A write is needed to a column outside the six | The task has been misread, or it belongs to the automated system (`Table ID`, `Last Run`, `Last Run Status`, any totals) | Don't write it. Report what looks wrong and let the user decide |
| A stream needs removing | Not something this skill does — `deleteRecords` is never called | Set `Enabled` false, on confirmation. The row stays |

Reasoning and the exact call shapes: the `## Writing to Streams` section of
[../.claude/skills/event-streams/SKILL.md](../.claude/skills/event-streams/SKILL.md).

## Something not covered here

[reference/endpoints.md](reference/endpoints.md) has the exact URL, auth
shape, and tool list for every system this skill touches.
[INDEX.md](INDEX.md) maps every doc in this repo if none of the above fit.
