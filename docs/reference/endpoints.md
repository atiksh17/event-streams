# Reference: endpoints and tools

Exact facts about the systems this skill touches — the discovery endpoint,
AI Ark, and NocoDB. Probed live on 2026-08-10, with one later addition
(AI Ark's transport shape, below) probed 2026-08-11 and dated inline.
Where a value hasn't been confirmed against a real run yet, it's marked
"not yet verified" rather than guessed.

## Discovery endpoint (test mode)

- **Production**: `POST https://n8n.goautofusion.com/webhook/stream` — the
  only URL the skill's procedure uses.
- **Test-only**: `https://n8n.goautofusion.com/webhook-test/stream` —
  single-shot, and 404s with
  `{"code":404,"message":"The requested webhook \"stream\" is not registered.","hint":"Click the 'Execute workflow' button on the canvas, then try again."}`
  until someone arms it by clicking *Execute workflow* in the n8n canvas. A
  debugging aid only — never the skill's path.
- **Request body**: three fields, all required —
  `{"keywords": "<comma separated>", "qualificationPrompt": "<text>", "sources": [...]}`
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
- **Response**: an array of objects shaped
  `{companyName, relevant, confidence, reason, source, content}`. Not yet
  verified against a real completed run — Task 9.
- **Timing**: a run takes 5–15 minutes and the HTTP call blocks for the
  whole duration. Must be backgrounded — a foreground call gets killed by
  the agent harness at 10 minutes, which looks exactly like a dead
  endpoint and leads to debugging the wrong thing.

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
  described as such.** The "production mode never writes to NocoDB"
  property is therefore enforced entirely by this skill's own
  prohibition (see `.claude/skills/event-streams/SKILL.md`), not by any
  restriction on the credential.
- **Permitted by the skill's procedure (read-only use)**: `getBaseInfo`,
  `getTablesList`, `getTableSchema`, `queryRecords`, `getRecord`,
  `countRecords`, `aggregate`, `readAttachment`.
- **Never called by the skill's procedure, despite being reachable**:
  `createRecords`, `updateRecords`, `deleteRecords`.
- **Base**: titled `Streams`, id `p49fpgg54ke8bb9`, workspace `w5fnx5lz` —
  from `GET /api/v2/meta/bases`, 2026-08-10.
- **Tables** — ids from `GET /api/v2/meta/bases/p49fpgg54ke8bb9/tables`,
  2026-08-10:
  - `Streams` — id `mfo88n8n35b9qvl`. **Critical.** The scheduler; read it to
    see what's running. Read-only: never modified, never deleted, never an
    enrichment target.
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
  `Streams`. Table creation, config, and `Enabled` all belong to the
  automated system — this skill does none of them, and the MCP endpoint
  could not create a table anyway (its scope is record-level only, see
  above). An empty `Table ID` means the table does not exist yet.
- **`Streams` columns** — from a live `queryRecords` against
  `mfo88n8n35b9qvl`, 2026-08-11. Wider than the skill previously described:
  `Stream Name`, `Stream Description`, `Keywords`, `Qualification Prompt`,
  `Sources`, `Job Titles`, `Max Results`, `Lookback`, `Table ID`, `Status`,
  `Enabled`, `Anchor`, `Last Run`, `Last Run Status`, `Total Found`,
  `Total Passed`, `Total Contacts`, `Valid Emails`, `Cost`, `Last 24h`,
  `Last 3d`, `Last 7d`, `Last 1m`, plus `CreatedAt` / `UpdatedAt`.
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
| Discovery endpoint response | integer **0–100** (a real response carried `"confidence": 95`) |
| NocoDB `Confidence` column type | **Decimal** — fits 0–1 and 0–100 equally |
| Live demo stream's `Qualification Prompt` | *"Return a confidence score from 0 to 1"* |

No stream has written rows yet, so which scale actually lands in the column
is **not yet verified**. Read a real value before applying any threshold, and
do not assume the 0–100 bands in [../test-mode.md](../test-mode.md) describe
stored rows — they describe the endpoint's response. Reconciling the demo
prompt with the endpoint's actual output is a human decision, and it is a
change to the NocoDB base, which this skill never writes.

## Codex quirk worth recording

`codex mcp add` exposes only `--bearer-token-env-var`, with no `--header`
flag, so NocoDB's custom `xc-mcp-token` header cannot be set from that
CLI. The `http_headers` key in `~/.codex/config.toml` is the only working
route — that's why `setup.sh` writes that file directly for the NocoDB
server instead of shelling out to `codex mcp add`.
