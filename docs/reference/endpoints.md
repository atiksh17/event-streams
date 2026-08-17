# Reference: endpoints and tools

Exact facts about the systems this skill touches — the discovery and
qualification endpoints, AI Ark, and NocoDB. Probed live on 2026-08-10, with
later additions dated inline (AI Ark's transport shape 2026-08-11; the
two-endpoint test-mode architecture 2026-08-17). Where a value hasn't been
confirmed against a real run yet, it's marked "not yet verified" rather than
guessed.

## Test mode's two endpoints

Test mode is **two endpoints fired in order**, not one. Verified end to end
2026-08-17. Base `https://n8n.goautofusion.com`.

| Stage | Default — always use this | Dev endpoint |
|---|---|---|
| Discovery | `POST /webhook/stream` | `POST /webhook-test/stream` |
| Qualification | `POST /webhook/qualification` | `POST /webhook-test/qualification` |

**Naming, and it matters.** The `webhook-test/` pair are **dev endpoints** —
never "test endpoints". *Test mode* is a user-facing mode that runs on the
default column; a dev endpoint is for whoever is debugging the backend. The
collision between the two names is a live source of misfires. Use a dev
endpoint only when the user has stated they are the developer.

**Dev endpoints are single-shot and human-armed.** They 404 with
`{"code":404,"message":"The requested webhook \"stream\" is not registered.","hint":"Click the 'Execute workflow' button on the canvas, then try again."}`
in ~0.5s until someone clicks *Execute workflow* on the n8n canvas, and they
disarm after answering one call. An agent cannot arm one.

**Two workflow copies per stage.** Each stage has a webhook-triggered workflow
(what test mode calls) and an `executeWorkflow`-triggered one the daily
production system calls. Split deliberately so a failure is attributable to one
half.

### The trays

| Tray | Table id | Holds |
|---|---|---|
| Source Tray | `m3s2n0eevrh9d5p` | Every item discovery scraped, judged or not |
| Relevance Tray | `mz8e0h1xfwalzeh` | Only what qualification passed, each row carrying an `Execution ID` |

Both are disposable scratch space and **read-only to the agent** — never
written, never deleted from. All rows written by one qualification execution
carry the same `Execution ID`, which is what the stop call needs.

### Discovery — request and behaviour

- **Request body**: three fields, all required —
  `{"keywords": "<comma separated>", "qualificationPrompt": "<text>", "sources": [...]}`
- **Where the output goes**: the Source Tray, not just the response. A measured
  run on 2026-08-17 banked **243 rows** — 158 Justgiving, 45 Google News, 40
  LinkedIn — from two keywords, and returned `200` in **~5.5 minutes**.
- **How to know it finished**: poll `countRecords` on the Source Tray. Rows
  appearing means it is working; the count going flat for 20–60 seconds means
  it is done.

### Qualification — request and behaviour

- **Request body**: exactly two fields.
  - `data` — an array of objects, **one per Source Tray row**, using the tray's
    own column names as keys: `title`, `pubDate`, `link`, `source`, `domain`,
    `quality`, `bot_blocked`, `url`, `tier`, `content`.
  - `qualificationPrompt` — camelCase, a plain string. Its value is the prompt
    stored identically on every Source Tray row.
- **Response**: `200` with `{"message":"Workflow was started"}` in **1–13
  seconds**. That is **success for this endpoint** — it acks and then works in
  the background. The same body from `/webhook/stream` would be a fault.
- **Where the output goes**: the Relevance Tray, over roughly **10–15 minutes**,
  one row at a time.
- **Pass rate: 10–20%** — one qualified company per 10 to 20 rows judged.
- **Payload size.** Whole-tray sends are the intent; the run is bounded by
  stopping at the target, not by sending fewer rows. Measured: ~60 rows is
  0.44MB and acks in 1.35s, 243 rows is 2.97MB. Large single bodies stalled the
  n8n worker repeatedly on 2026-08-15, so if a big send is rejected or stalls,
  batch it in sequence rather than dropping rows.

### Stopping a run

`POST /api/v1/executions/<id>/stop`, header `X-N8N-API-KEY` from `.env`, with
`<id>` taken from the `Execution ID` column of a Relevance Tray row *this run
wrote*. Never `/workflows/{id}/deactivate` — that switches off the daily
production stream and fails silently.

**`N8N_API_KEY` returns `{"message":"unauthorized"}` on every endpoint as of
2026-08-17**, while the public API itself is live (docs at `/api/v1/docs/`,
spec `v1.1.1`, scheme `X-N8N-API-KEY`, `/executions/{id}/stop` present in the
spec, key a well-formed JWT with `aud: public-api`). Not a request-shape
problem — the key needs re-issuing on this instance. Until then the stop step
cannot run and a run continues to completion.

### The `sources` field — required on the discovery request

- **`sources`**: an array of strings naming which sources the run sweeps.
  Exactly three values are accepted, and they are **case- and
  spacing-sensitive literals**:
  - `"Google News"`
  - `"Justgiving"` — note the lowercase `g`. The brand styles itself
    *JustGiving*; the endpoint does not. Do not "correct" it.
  - `"LinkedIn"`

  **At least one is required** — an empty array is not a valid request, and
  neither is omitting the field. Whichever values are present are the
  sources used; all three present means all three run. Anything not spelled
  exactly as above is a mistake, not a variant. Added to the contract
  2026-08-11.
### Liveness — the free first probe

- **Probed 2026-08-14.** `GET /webhook/stream` → `HTTP/2 404` in **0.53s**,
  body
  `{"code":404,...,"This webhook is not registered for GET requests. Did you mean to make a POST request?"}`.
  That specific message means the host is up, the workflow is **active**, and
  the path is registered — it is not the "must be active for a production URL"
  message n8n returns for a disabled workflow. A GET runs no workflow and
  costs nothing, which makes it the correct first probe for any failure.
- **Backgrounding is still required** for discovery — a foreground call gets
  killed by the agent harness at 10 minutes, which looks exactly like a dead
  endpoint and leads to debugging the wrong thing.

### Historical — the single synchronous endpoint, superseded

Everything below describes the pre-split design, where one endpoint scraped,
judged and answered on the same connection. It is kept as the record of why the
two-endpoint architecture exists. **None of it describes current behaviour.**

- **Old response shape**: objects shaped
  `{companyName, relevant, confidence, reason, source, content}`. Verified
  against one real completed run (2026-08-11, `LinkedIn` only, one match):
  the body came back as a **bare JSON object, not an array of one**, with
  all six fields present and `confidence` an integer.
- **Old timing.** Every run recorded used a single source (`LinkedIn`) and
  finished in **6.9s to 114.8s**; the one successful run took **68.2s**. The
  "5–15 minutes" figure quoted elsewhere in this repo had no observation behind
  it, and quoting it cost real time — it is why four non-responses on
  2026-08-13/14 were each given a 30-minute benefit of the doubt instead of
  being called dead at five. Current figures are in the two sections above.
- **Cloudflare no longer fronts this endpoint (verified 2026-08-14).** The
  record was grey-clouded on 2026-08-12. A live request now returns no
  `cf-ray` and no `server: cloudflare`, so the ~120s edge ceiling and both
  error codes below are **historical**. Everything in the indented block is
  kept as the record of what was true before that change — not as current
  behaviour.
- **The failure the split fixed: POST hangs, zero bytes, no response ever.**
  Four runs on 2026-08-13/14 each held the connection open for the client's
  full 30-minute `--max-time` and returned 0 bytes. They varied the
  qualification prompt, keyword count (16 vs ~70) and sources (with and
  without `Justgiving`) and behaved identically, which rules out request
  content. Combined with the liveness probe above, the failure is isolated to
  the workflow's response path — the origin accepts the connection and never
  writes a response. **This is the same underlying condition the 524 was
  reporting**, minus the proxy that used to truncate it at ~120s into a fast,
  legible error. Removing Cloudflare changed the symptom, not the fault.
- Historical Cloudflare behaviour, before 2026-08-12:
  - `error code: 524` — edge timeout. Seen at ~125s on 2026-08-12 while the
    n8n workflow itself ran to completion and produced data.
  - `error code: 1010` with HTTP 403 — bot/browser-signature block. Seen
    once, 2026-08-11; the request never reached n8n.

  **The ceiling sits near 120 seconds, not the 100s Cloudflare's stock
  default would suggest** — a 114.8s response returned successfully on
  2026-08-11, and 125s did not. Anything slower cannot answer over this
  synchronous path regardless of the client's `--max-time`, and no retry
  changes that. Two fixes were identified. **One has been done, and it was
  the lesser of the two:**
  1. ~~**Take the hostname off the Cloudflare proxy**~~ — **done 2026-08-12.**
     It removed the 524s exactly as predicted, and taught us something
     unwelcome: the 524 was the only thing making the real fault legible.
     With no edge to cut the connection at ~120s, a workflow that never
     answers now holds the socket open until the client gives up. The fault
     did not change; the error message did. Cost as expected — WAF/DDoS
     cover on that hostname, and the origin address is exposed.
  2. ~~**Stop answering synchronously**~~ — **done 2026-08-17, and it was the
     fix that mattered.** This is exactly what the two-endpoint split
     delivered: qualification acks in seconds and writes its results into a
     NocoDB tray the way the daily streams already do. Any proxy ceiling,
     dropped connection, closed laptop, or non-answering response node stopped
     mattering — the results land in a tray either way, which is precisely what
     the four hung runs failed to do despite (probably) completing.

## AI Ark MCP (production mode)

- **URL**: `https://api.ai-ark.com/v1/mcp?token=<AI_ARK_API_KEY>` — the
  token is a **query parameter**, not a header.
- **Status**: connected and verified working from Claude Code directly and
  from Codex through the project's pinned `mcp-remote@0.1.37` STDIO bridge.
- **Server info**: `serverInfo {name: "mcp", version: "1.0.0"}`, protocol
  `2025-06-18` — from a live `initialize` call, 2026-08-10.
- **Transport shape (probed 2026-08-11)**: the server **requires**
  `Accept: application/json, text/event-stream` on every request — omit it
  and it 400s. But it always **replies** with `content-type: application/json`
  and a raw JSON body, never an actual `text/event-stream` SSE stream with
  `event:`/`data:` framing. Claude Code's MCP client tolerates that
  deviation. Codex's `rmcp` streamable-HTTP client does not: it asks for
  the stream it was told to expect, gets a non-stream back, and its
  transport worker dies with `rmcp::transport::worker: worker quit with
  fatal: Transport channel closed`. The project avoids that direct path:
  `.codex/config.toml` starts `mcp-remote@0.1.37` as a local STDIO server, and
  the bridge tolerates AI Ark's JSON response. A live bridge check completed
  `initialize` and `tools/list` on 2026-08-11. A fresh Codex process then
  loaded the bridged server and successfully called `industry_search`, proving
  the tool surface is available beyond the standalone bridge probe.
  **Contrast**: NocoDB's MCP server (below) replies
  `content-type: text/event-stream` with proper `event:`/`data:` framing
  for the same kind of request, and works from Codex — this contrast is
  the whole diagnosis: same client, same repo config, different server
  behavior. This is upstream AI Ark behavior, not a config choice in this
  repo, and it may change — treat this as a dated, probed fact to retest,
  not a permanent property of the server.
- **Tools (11)**: `company_search`, `people_search`, `email_finder`,
  `email_finder_results`, `export_single`, `reverse_people_lookup`,
  `mobile_phone_finder`, `personality_analysis`, `industry_search`,
  `technology_search`, `location_search`.
- `email_finder` is **asynchronous** — it returns a `trackId`; results come
  back from a separate call to `email_finder_results`. Not the path this
  skill's procedure uses.
- `export_single` is **synchronous**, keyed by an AI Ark `id` or a
  LinkedIn `url`. This is the path the skill uses, once per person.
- `people_search` takes 97 arguments in total (counted from `tools/list`
  against the live server, 2026-08-10 — not a remembered figure). The ones
  this skill's procedure actually uses: `title` (positive job-title filter),
  `excludeTitle`, `previousTitle` (past roles, not current), `seniority`
  (fixed enum: `c_suite, vp, director, manager, senior, mid-level, entry`
  — no lookup needed), `companyName`, `companyNameOrDomain`.
- `industry`, `location`, and `technology` filters each need an exact enum
  value resolved first via `industry_search` / `location_search` /
  `technology_search`. A free-text guess in one of these fields does not
  error — it silently matches nobody. Company name and job title, the two
  filters this skill's procedure actually uses, are free text and don't
  need this resolution step.

## NocoDB MCP (production mode)

- **URL**: `https://db.goautofusion.com/mcp/ncuiv55fi0t1x0em`, header
  `xc-mcp-token` (32-char token, never printed). This id replaces the
  stale `nc6gt1uozqt6i76m` previously written here — that one was a
  different credential type (a NocoDB **API token**, not an **MCP
  endpoint token**) and 404'd with `{"msg":"MCP Token not found"}`. See
  [../troubleshooting.md](../troubleshooting.md) for how that distinction
  surfaces on a fresh install.
- **Status: connected.** Probed live 2026-08-10 — `initialize` → `HTTP
  200`, `serverInfo {"name":"NoocDB MCP Server","version":"1.0.0"}`,
  protocol `2025-06-18`. (`NoocDB` — missing the "d" — is a real typo in
  the upstream server's own response, not an error in this doc. Leave it
  as-is; don't "fix" it here.)
- **Scope**: record-level only. Cannot create or alter tables, fields, or
  views.
- **Tools (11, from a live `tools/list`, 2026-08-10)**: `aggregate`,
  `countRecords`, `createRecords`, `deleteRecords`, `getBaseInfo`,
  `getRecord`, `getTableSchema`, `getTablesList`, `queryRecords`,
  `readAttachment`, `updateRecords`.
- **The three write tools are exposed and reachable with this
  credential.** `createRecords`, `updateRecords`, and `deleteRecords` all
  appear in `tools/list` and work with the same `xc-mcp-token` used for
  reads. This NocoDB instance's MCP endpoint has no read-only variant —
  it exposes a fixed 11-tool set per base, and any token that connects
  gets the full set. **The token is not read-only and must never be
  described as such.** Which writes are allowed is therefore decided
  entirely by this skill's own rules (see
  `.claude/skills/event-streams/SKILL.md`, `## Writing to Streams`), not
  by any restriction on the credential. `deleteRecords` in particular is
  fully available and is never called.
- **Reads, always permitted**: `getBaseInfo`, `getTablesList`,
  `getTableSchema`, `queryRecords`, `getRecord`, `countRecords`,
  `aggregate`, `readAttachment`.
- **Writes, permitted against the `Streams` table only and only on the
  user's explicit confirmation**: `createRecords`, `updateRecords` —
  restricted to six columns (`Stream Name`, `Stream Description`,
  `Keywords`, `Qualification Prompt`, `Sources`, `Enabled`). Starting a
  stream is `Enabled` → true; stopping it is `Enabled` → false. New rows
  are always created with `Enabled` false.
- **Never called, despite being reachable**: `deleteRecords`, on any
  table. Also any write to a stream's data table or to `Template (DO NOT
  TOUCH)`, and any write to a `Streams` column outside the six above.
- **Base**: titled `Streams`, id `p49fpgg54ke8bb9`, workspace `w5fnx5lz` —
  from `GET /api/v2/meta/bases`, 2026-08-10.
- **Tables** — ids from `GET /api/v2/meta/bases/p49fpgg54ke8bb9/tables`,
  2026-08-10:
  - `Streams` — id `mfo88n8n35b9qvl`. **Critical.** The scheduler; read it to
    see what's running. The one writable table — six columns, confirmed per
    write. Never deleted, never an enrichment target.
  - `Template (DO NOT TOUCH)` — id `m0liglo73sxjwa8`. **Critical.** Reserved
    — never read, never write, never delete, never offer as a target.
  - `Demo Stream — Dealership Group Expansions` — id `m52q1ugrrytkoov`. A
    real stream and a valid enrichment target.
  - New stream tables appear over time. The rule is "not `Streams`, not
    `Template (DO NOT TOUCH)`" — never a fixed list to memorize. Match on
    the two ids above as well as the names, since a rename would defeat a
    name-only check.
- **Every other table is one stream's data table, linked by `Table ID`.** A
  row in `Streams` holds its own table's id in the `Table ID` column — that
  is the only reliable route from a stream to its rows. Confirmed live
  2026-08-11: the single `Streams` row carries `Table ID`
  `m52q1ugrrytkoov`, which is the demo stream's table.
- **Stream-table lifecycle.** A `Streams` row needs `Keywords`,
  `Qualification Prompt` and `Sources` set, and `Enabled` true. The automated
  system then creates the stream's data table, names it after the stream, and
  writes that table's id back into the `Table ID` column of the row in
  `Streams`. The config and `Enabled` are the skill's to write on
  confirmation; **table creation and `Table ID` are not**, and the MCP
  endpoint could not create a table anyway (its scope is record-level only,
  see above). An empty `Table ID` means the table does not exist yet —
  expected on a freshly enabled stream, until the automated system catches
  up.
- **`Streams` columns** — from a live `queryRecords` against
  `mfo88n8n35b9qvl`, 2026-08-11. Wider than the skill previously described:
  `Stream Name`, `Stream Description`, `Keywords`, `Qualification Prompt`,
  `Sources`, `Job Titles`, `Max Results`, `Lookback`, `Table ID`, `Status`,
  `Enabled`, `Anchor`, `Last Run`, `Last Run Status`, `Total Found`,
  `Total Passed`, `Total Contacts`, `Valid Emails`, `Cost`, `Last 24h`,
  `Last 3d`, `Last 7d`, `Last 1m`, plus `CreatedAt` / `UpdatedAt`.
- **The six writable columns, with types from a live `getTableSchema`
  against `mfo88n8n35b9qvl`, 2026-08-13**: `Stream Name` (SingleLineText),
  `Stream Description` (LongText), `Keywords` (LongText),
  `Qualification Prompt` (LongText), `Sources` (MultiSelect — choices are
  exactly `Google News`, `LinkedIn`, `Justgiving`), `Enabled` (Checkbox,
  `default_value` `"0"`, reads back as `0`/`1`). No other column may be
  written.
- **Schema drift, seen 2026-08-13 and not yet reconciled.** That same
  `getTableSchema` returned only ten fields — `Id`, the six above,
  `Table ID`, `Last Run`, `Last Run Status` — and `queryRecords` returned
  zero rows. The wider column list above (`Job Titles`, `Status`,
  `Max Results`, `Lookback`, `Anchor`, the totals and rolling counts) and
  the demo stream table `m52q1ugrrytkoov` were not present. `getTablesList`
  showed `Streams`, `Template (DO NOT TOUCH)`, and a new
  `(DO NOT DELETE)` (`mou5hgure552wdx`). Read the schema live before
  relying on any column named here.
- **`Streams` has a `Sources` column, and it is populated.** A multi-value
  field carrying the same exact literals the request body uses — the live row
  holds `["Google News", "LinkedIn", "Justgiving"]`. Earlier docs told the
  agent to report sources "even if `Streams` has no field for them"; that was
  wrong, and the winning sources belong in this column.
- **`Status` and `Enabled` are independent.** The live demo row is
  `Enabled: 1` **and** `Status: draft` simultaneously. `Enabled` alone does
  not mean a stream is running.

### The `Confidence` scale is unresolved

Three sources disagree about what number belongs in `Confidence`, all
observed 2026-08-11:

| Where | Scale it implies |
|---|---|
| Qualification output (and the old single endpoint's response) | integer **0–100** (a real response carried `"confidence": 95`) |
| NocoDB `Confidence` column type | **Decimal** — fits 0–1 and 0–100 equally |
| Live demo stream's `Qualification Prompt` | *"Return a confidence score from 0 to 1"* |

No stream has written rows yet, so which scale actually lands in the column
is **not yet verified**. Read a real value before applying any threshold, and
do not assume the 0–100 bands in [../test-mode.md](../test-mode.md) describe
stored rows — they describe the endpoint's response. Reconciling a stream's
prompt with the endpoint's actual output is a human decision; the skill can
carry it out, since `Qualification Prompt` is one of the six writable
columns, but only as a confirmed write with the before and after shown.

## Codex quirk worth recording

`codex mcp add` exposes only `--bearer-token-env-var`, with no `--header`
flag, so NocoDB's custom `xc-mcp-token` header cannot be set from that
CLI. The `http_headers` key in `~/.codex/config.toml` is the only working
route — that's why `setup.sh` writes that file directly for the NocoDB
server instead of shelling out to `codex mcp add`.
