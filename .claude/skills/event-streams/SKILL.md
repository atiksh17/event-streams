---
name: event-streams
description: Use when trialling keywords and qualification prompts for a lead-sourcing stream ("test these keywords", "the results are too broad", "try a tighter prompt"), or when turning rows an automated stream has already collected into an enriched contact CSV ("enrich the new rows in <table>", "get me contacts for these companies"). Two modes, one endpoint each, no scripts.
---

# Event Streams

Finds companies whose staff are doing organised events, and finds the senior
people to contact at them.

Two modes. They share no systems, and picking the wrong one wastes either
fifteen minutes or real money.

| Mode | Use when | Touches |
|---|---|---|
| **Test** | Trialling keywords and a qualification prompt | Discovery endpoint only |
| **Production** | Enriching rows a daily stream already collected | NocoDB + AI Ark only |

Test mode never reads NocoDB. Production mode never calls the discovery
endpoint.

## Test mode

Trialling keywords and a qualification prompt. Touches the discovery endpoint
and nothing else — no NocoDB, no AI Ark, nothing is spent.

### Before you start, say this out loud

> This takes 5 to 15 minutes. I'll tell you the moment it lands.

A silent ten-minute wait reads as a crash.

### Fire the request

**Never run this in the foreground.** A discovery run can take 15 minutes and
the agent harness kills a foreground command at 10. The kill looks exactly like
a dead endpoint, and you will debug the wrong thing.

    mkdir -p data/.runs
    RUN=$(date +%Y%m%d-%H%M%S)
    cat > "data/.runs/$RUN.request.json" <<'JSON'
    {"keywords": "...", "qualificationPrompt": "..."}
    JSON
    nohup curl -sS --max-time 1800 -X POST https://n8n.goautofusion.com/webhook/stream \
      -H 'Content-Type: application/json' \
      -d @"data/.runs/$RUN.request.json" \
      -o "data/.runs/$RUN.response.json" \
      -w '%{http_code}' > "data/.runs/$RUN.status" 2>&1 &

Then poll for `data/.runs/$RUN.status`. When it appears, the run is done and the
file holds the HTTP status.

Use `https://n8n.goautofusion.com/webhook/stream`. The `webhook-test/` variant
is single-shot and only works right after someone clicks *Execute workflow* in
n8n — it is a debugging aid, never the skill's path.

### Show the results

One row per company. `content` is long — show it only when asked.

| Company | Relevant | Confidence | Why |
|---|---|---|---|

Then state the pass rate plainly: *"14 of 61 passed."*

### Iterate

Ask what is wrong with it, specifically. "Too broad" is a start, not an answer —
push for which companies should not be there and why. Then rewrite the
qualification prompt, **show the before and after**, and re-run only once the
user agrees.

Every re-run costs another 5–15 minutes, so it is worth one more question up
front rather than three more runs.

### When the user is happy

Print the row for them to add to the `Streams` table:

    keywords:            <the winning keywords>
    qualificationPrompt: <the winning prompt>

**You do not write this row.** A row in `Streams` means "run this every day,
forever" — that is the user's decision to make in NocoDB, not a side effect of
a successful test.

### When it goes wrong

| What you see | What it means | What to say |
|---|---|---|
| `404 ... webhook "stream" is not registered` | The test URL was used | Use the production URL |
| `{"message":"Workflow was started"}` | n8n is set to respond immediately | The workflow needs a *Respond to Webhook* node; results are not coming |
| `[]` | Keywords matched nothing | A keyword problem, not a fault |
| Every row `relevant: false` | Prompt too strict | A prompt problem — offer a looser rewrite |
| Body is not JSON | n8n returned an error page | Show the first 500 bytes, do not parse |
| `.status` never appears | Run exceeded 30 minutes | Report the timeout. Do not silently retry |

## Production mode

The daily stream has already done discovery and judging. You start from its
rows. You never call the discovery endpoint here.

Reads NocoDB via the `nocodb-streams` MCP server, enriches via the `ai-ark`
MCP server. Never writes to either. Two different agent harnesses run this
skill; both are configured with servers of these same two names.

**On Codex, step 5 (enrich) will fail** — AI Ark's MCP server has a known
upstream bug where Codex's client can't consume its response shape (see
[docs/troubleshooting.md](../../../docs/troubleshooting.md), `Transport
channel closed`). Reading NocoDB and test mode both still work from Codex.
If you're running as Codex, say this up front and switch to Claude Code
before reading any rows for enrichment.

### 1. Find out what to enrich

Ask which table, and which rows. The user can see the base and you cannot —
their answer is authoritative. "The new ones" is a valid answer; ask them
which ones those are.

The NocoDB base itself is titled "Streams", and it also contains a table
titled `Streams` — when it could be misread, say "the base" or name the table,
not just "Streams".

`Streams` and `Template (DO NOT TOUCH)` are never enrichment targets.
`Streams` is the scheduler — read it to list what is running. `Template (DO
NOT TOUCH)` is reserved — never read it, never write it, never offer it.
Every other table (for example `Demo Stream — Dealership Group Expansions`)
is an individual stream and a valid target. New stream tables appear over
time, so the rule is "not `Streams`, not `Template (DO NOT TOUCH)`" — never a
fixed list you memorize.

### 2. Read the rows

Read-only, always: `getBaseInfo`, `getTablesList`, `getTableSchema`,
`queryRecords`, `getRecord`, `countRecords`, `aggregate`, `readAttachment`.

**Never** `createRecords`, `updateRecords`, or `deleteRecords`. Nothing in this
mode writes to NocoDB. If you believe you need to write, you have misread the
task — stop and ask.

### 3. Ask for the job titles

**Every run. Before anything is spent. No exceptions.**

> Which job titles do you want at these companies?

If an earlier run in this same conversation used titles, you may *offer* them —
"last time you used Head of HR, People Director, CSR Manager — same again?" —
but the user must say yes. Never carry them over silently, and never infer them
from the table.

### 4. Confirm the spend

State it plainly and wait:

> 38 companies × 3 job titles. Enriching now?

### 5. Enrich

Per company, then per person — this is what makes failure isolate to one
record instead of aborting the batch:

1. `people_search`, filtered on `companyName` (or `currentCompany` /
   `latestCompany`) and the job titles just confirmed. Company name and job
   title are free text; neither needs resolving first.
2. For each person the search returns, `export_single` — synchronous, one
   person at a time, keyed by the AI Ark `id` from the search hit (or a
   LinkedIn `url`) — to get their email and confirmed LinkedIn URL.

**Filtering by industry or location is a different case.** `people_search` and
`company_search` both require exact enum values for `industry`, `location`,
and `technology` — resolve them first with `industry_search` /
`location_search` / `technology_search` and filter on the returned tokens. A
free-text guess in those fields does not error; it silently matches nobody.
The path above (company name + job title) never needs this — only reach for
the resolvers when a run also filters by industry or region.

A company where `people_search` returns nobody is not a failure. Move on and
record why (see the report below).

### 6. Write the CSV

`data/<table-slug>-YYYY-MM-DD.csv`, unless the user has said they want
something else — in which case theirs wins and you do not argue.

Columns: `company`, `person_name`, `job_title`, `email`, `linkedin_url`,
`source_table`, `enriched_at`. One row per person. Companies that returned
nobody appear in the report, not as blank rows.

### 7. Report honestly

    38 companies in
    91 people out
    64 with an email (70%)
    88 with a LinkedIn (97%)
    6 companies returned nobody

If coverage is poor, say so and say why. Do not round it up and do not present
a thin result as a good one.

## Rules that must not need a lookup

**1. Never print a secret.** Not a key, not a token. They live in
`credentials.env`. To check one, print whether it is set and how long it is —
never its value.

**2. Job titles are asked for every single time.** It is the one question that
stands between the user and money they did not mean to spend.

**3. Nothing in production mode writes to NocoDB.** The base is the automated
system's, not yours. This rule is the only thing stopping a write — the
connected token is write-capable and does not block `createRecords`,
`updateRecords`, or `deleteRecords` itself. `deleteRecords` against the live
base has no undo.

**4. Test mode and production mode share nothing.** If you are reaching for
NocoDB in test mode or the discovery endpoint in production mode, you are in
the wrong mode.
