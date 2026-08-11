# Reference: endpoints and tools

Exact facts about the systems this skill touches — the discovery endpoint,
AI Ark, and NocoDB. Probed live on 2026-08-10. Where a value hasn't been
confirmed against a real run yet, it's marked "not yet verified" rather
than guessed.

## Discovery endpoint (test mode)

- **Production**: `POST https://n8n.goautofusion.com/webhook/stream` — the
  only URL the skill's procedure uses.
- **Test-only**: `https://n8n.goautofusion.com/webhook-test/stream` —
  single-shot, and 404s with
  `{"code":404,"message":"The requested webhook \"stream\" is not registered.","hint":"Click the 'Execute workflow' button on the canvas, then try again."}`
  until someone arms it by clicking *Execute workflow* in the n8n canvas. A
  debugging aid only — never the skill's path.
- **Request body**: `{"keywords": "<comma separated>", "qualificationPrompt": "<text>"}`
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
- **Status**: connected and verified working.
- **Server info**: `serverInfo {name: "mcp", version: "1.0.0"}`, protocol
  `2025-06-18` — from a live `initialize` call, 2026-08-10.
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

- **URL**: `https://db.goautofusion.com/mcp/<base-mcp-id>`, header
  `xc-mcp-token`.
- **Scope**: record-level only. Cannot create or alter tables, fields, or
  views.
- **Permitted (read)**: `getBaseInfo`, `getTablesList`, `getTableSchema`,
  `queryRecords`, `getRecord`, `countRecords`, `aggregate`,
  `readAttachment`.
- **Forbidden (write)**: `createRecords`, `updateRecords`,
  `deleteRecords` — never called by this skill's procedure.
- **Status: currently NOT connected.** The endpoint configured in
  `credentials.env` returns `404 {"msg":"MCP Token not found"}`. The
  credential there is a NocoDB **API token** (works as `xc-token` against
  `/api/v2`), not an **MCP endpoint token** — two different credential
  types from the same product. See
  [../troubleshooting.md](../troubleshooting.md) for the fix. This is the
  single most likely thing to be broken on a fresh install.
- **Base**: titled `Streams`, id `p49fpgg54ke8bb9`, workspace `w5fnx5lz` —
  from `GET /api/v2/meta/bases`, 2026-08-10.
- **Tables** — ids from `GET /api/v2/meta/bases/p49fpgg54ke8bb9/tables`,
  2026-08-10:
  - `Streams` — id `mfo88n8n35b9qvl`. The scheduler; read it to see what's
    running. Never an enrichment target.
  - `Demo Stream — Dealership Group Expansions` — id `m52q1ugrrytkoov`. A
    real stream and a valid enrichment target.
  - `Template (DO NOT TOUCH)` — id `m0liglo73sxjwa8`. Reserved — never
    read, never write, never offer as a target.
  - New stream tables appear over time. The rule is "not `Streams`, not
    `Template (DO NOT TOUCH)`" — never a fixed list to memorize.

## Codex quirk worth recording

`codex mcp add` exposes only `--bearer-token-env-var`, with no `--header`
flag, so NocoDB's custom `xc-mcp-token` header cannot be set from that
CLI. The `http_headers` key in `~/.codex/config.toml` is the only working
route — that's why `setup.sh` writes that file directly for the NocoDB
server instead of shelling out to `codex mcp add`.
