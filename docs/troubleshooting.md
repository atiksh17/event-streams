# Troubleshooting

Symptom-first. Find what you're seeing, read what it means, do what it says.

## Install

| What you see | What it means | What to do |
|---|---|---|
| `claude not on PATH - skipping Claude Code install` | Claude Code isn't installed, or isn't on `PATH` | Install it, then re-run `./setup.sh` — or ignore this if you only use Codex |
| `codex not on PATH - skipping Codex install` | Codex isn't installed, or isn't on `PATH` | Install it, then re-run `./setup.sh` — or ignore this if you only use Claude Code |
| `.codex/skills/event-streams is a real file, not a symlink` | The repo was cloned on Windows without symlink support, so the symlink arrived as a plain file | `git config --global core.symlinks true`, then re-clone the repo |
| `setup.sh` exits non-zero with `one or more servers did not come up` | A server failed its post-install connection check | See "MCP server won't connect" below for the likely cause |
| **NocoDB MCP server won't connect — `404 {"msg":"MCP Token not found"}`** | `NOCODB_MCP_TOKEN` in `.env` is a NocoDB **API token** (works as `xc-token` against `/api/v2`), not an **MCP endpoint token** — two different credential types from the same product | Mint one in the NocoDB UI: base → Overview → Settings → Model Context Protocol → New MCP Endpoint. Put the base's MCP id in `NOCODB_MCP_URL` and the new MCP token in `NOCODB_MCP_TOKEN`, then re-run `./setup.sh`. **This is the single most likely thing to be broken on a fresh install** — see [reference/endpoints.md](reference/endpoints.md) for the exact URL and header shape. |
| **The NocoDB MCP token is write-capable** | Expected, not a misconfiguration — this endpoint's tool set is fixed and includes `createRecords`, `updateRecords`, and `deleteRecords`; there's no read-only variant to mint. Full verification and NocoDB-docs research: [reference/endpoints.md](reference/endpoints.md) | Detect with the free `tools/list` call and check whether those three names appear. **Never detect it by attempting a write, not even an empty-array `createRecords`** — a write succeeding is how you'd find out by damaging the base. If it's write-capable, rely on the skill's own rule, not the token, to keep it from writing |
| AI Ark MCP server won't connect | `AI_ARK_API_KEY` is empty, wrong, or missing from `.env` | Get a key from https://app.ai-ark.com/settings/api-management/dashboard, set `AI_ARK_API_KEY` in `.env`, re-run `./setup.sh` |
| **`rmcp::transport::worker: worker quit with fatal: Transport channel closed` — from Codex, calling AI Ark, even though `codex mcp list` shows it enabled** | A protocol mismatch, not a credential or config problem. AI Ark's MCP server demands the header `Accept: application/json, text/event-stream` (it 400s without it) but always replies with `content-type: application/json` and a raw JSON body — never an actual SSE stream. Codex's `rmcp` streamable-HTTP client asks for the stream it was told to expect, gets a non-stream back, and its transport worker dies with exactly this message. Claude Code tolerates the same deviation and works fine against the same server. This is a bug in AI Ark's MCP server, confirmed by diagnosis on 2026-08-11 — see [reference/endpoints.md](reference/endpoints.md) for the probed request/response facts. It is **not** something `setup.sh` or this repo's config can fix; `./setup.sh`'s post-install probe detects and warns about it but does not fail the install over it, because the server works fine from Claude Code. | Switch to Claude Code for anything that calls AI Ark — in practice, the production-mode enrichment step. Test mode and reading NocoDB both still work fine from Codex; only AI Ark is affected. This is upstream behavior on AI Ark's side and may be fixed later — if you're reading this well after 2026-08-11, retest before trusting the claim rather than assuming it's still broken. |

## Test mode

| What you see | What it means | What to say |
|---|---|---|
| `404 ... webhook "stream" is not registered` | The test URL was used | Use the production URL |
| `{"message":"Workflow was started"}` | n8n is set to respond immediately | The workflow needs a *Respond to Webhook* node; results are not coming |
| `[]` | Keywords matched nothing | A keyword problem, not a fault |
| Every row `relevant: false` | Prompt too strict | A prompt problem — offer a looser rewrite |
| Body is not JSON | n8n returned an error page | Show the first 500 bytes, do not parse |
| `.status` never appears | Run exceeded 30 minutes | Report the timeout. Do not silently retry |

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

## Something not covered here

[reference/endpoints.md](reference/endpoints.md) has the exact URL, auth
shape, and tool list for every system this skill touches.
[INDEX.md](INDEX.md) maps every doc in this repo if none of the above fit.
