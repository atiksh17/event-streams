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
| **Test** | Trialling keywords, sources and a qualification prompt | Discovery endpoint only |
| **Production** | Enriching rows a daily stream already collected | NocoDB + AI Ark only |

Test mode never reads NocoDB. Production mode never calls the discovery
endpoint.

## Test mode

Trialling keywords, sources and a qualification prompt. Touches the discovery
endpoint and nothing else — no NocoDB, no AI Ark, nothing is spent.

### Before you start, say this out loud

> This takes 5 to 15 minutes. I'll tell you the moment it lands.

A silent ten-minute wait reads as a crash.

### Pick the sources

Every request carries a third field, `sources` — an array of the sources the
run sweeps. **Three values are accepted, and the spelling is exact:**

    "Google News"
    "Justgiving"
    "LinkedIn"

- **At least one.** An empty array is not a valid request, and neither is
  omitting the field.
- **Copy those strings; do not retype them from memory.** `"Google news"`,
  `"JustGiving"`, `"Linkedin"`, `"Just Giving"` are all wrong.
- The brand styles itself *JustGiving* in public. The endpoint wants
  `Justgiving`, lowercase g. **Do not "correct" it.**
- Whatever is in the array is what runs. All three strings = all three
  sources.

Ask the user which sources they want. If they have no preference, use all
three and say that you did — a pass rate means nothing without knowing which
sources produced it.

### Fire the request

**Never run this in the foreground.** A discovery run can take 15 minutes and
the agent harness kills a foreground command at 10. The kill looks exactly like
a dead endpoint, and you will debug the wrong thing.

    mkdir -p data/.runs
    RUN=$(date +%Y%m%d-%H%M%S)
    cat > "data/.runs/$RUN.request.json" <<'JSON'
    {"keywords": "...",
     "qualificationPrompt": "...",
     "sources": ["Google News", "Justgiving", "LinkedIn"]}
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

`sources` is the third lever, and the cheapest one to reason about: if every
bad row came from one source, drop it from the array rather than writing a
sentence into the prompt to exclude it. If a run found almost nothing, widen
the array before you widen the keywords.

Every re-run costs another 5–15 minutes, so it is worth one more question up
front rather than three more runs.

### When the user is happy

Print the row for them to add to the `Streams` table:

    keywords:            <the winning keywords>
    qualificationPrompt: <the winning prompt>
    sources:             <the sources that run used, exactly as spelled>

Give the sources even if `Streams` has no field for them — the result the
user is about to schedule came from those sources and no others.

**You do not write this row.** A row in `Streams` means "run this every day,
forever" — that is the user's decision to make in NocoDB, not a side effect of
a successful test.

### When it goes wrong

| What you see | What it means | What to say |
|---|---|---|
| `404 ... "The workflow must be active for a production URL to run"` | Right URL, but the n8n workflow is switched off | Only a human can fix this: ask them to activate the workflow with the toggle at the top-right of the n8n editor, then re-run. Do not retry until they confirm — it will 404 every time |
| `404 ... webhook "stream" is not registered` (no "must be active" hint) | The test URL was used | Use the production URL |
| `{"message":"Workflow was started"}` | n8n is set to respond immediately | The workflow needs a *Respond to Webhook* node; results are not coming |
| Any error naming `sources` | A misspelled value, or an empty/missing array | Re-check the array against the three exact strings, character by character. Fix and re-run — this one is yours, not the user's |
| `[]` | Keywords matched nothing, or the sources were too narrow | A keyword or sources problem, not a fault |
| Every row `relevant: false` | Prompt too strict | A prompt problem — offer a looser rewrite |
| Body is not JSON | n8n returned an error page | Show the first 500 bytes, do not parse |
| `.status` never appears | Run exceeded 30 minutes | Report the timeout. Do not silently retry |

## Production mode

The daily stream has already done discovery and judging. You start from its
rows. You never call the discovery endpoint here.

Reads NocoDB via the `nocodb-streams` MCP server, enriches via the `ai-ark`
MCP server. Never writes to either. Two different agent harnesses run this
skill; both are configured with servers of these same two names.

On Codex, `ai-ark` is project-scoped through the pinned `mcp-remote` STDIO
bridge because AI Ark's remote endpoint does not return the event stream
Codex's direct HTTP client requires. If the AI Ark tools are missing, run
`./setup.sh`, restart Codex, and see
[docs/codex-ai-ark-setup.md](../../../docs/codex-ai-ark-setup.md). Do not fall
back to direct `url = ...` configuration while AI Ark still returns plain
JSON; that path fails with `Transport channel closed`.

### 1. Find out what to enrich

Ask which stream, and which rows. The user can see the base and you cannot —
their answer is authoritative. "The new ones" is a valid answer; ask them
which ones those are.

Read the `Streams` table first and show what exists. Each row carries
`Stream Name`, `Status`, `Table ID`, `Job Titles`, `Keywords` and running
totals (`Total Found`, `Total Passed`, `Total Contacts`, `Valid Emails`,
`Cost`). That one read tells you what the streams are, which are live, where
each one's data lives, and what it has already cost.

A stream whose `Status` is `draft` has never run and its table will be empty.
Say that plainly rather than reporting "no rows found" as if something broke.

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
task — stop and ask. The token is write-capable, so nothing but this rule
stops you, and `deleteRecords` against the live base has no undo.

**Find the data table through `Streams`, not by guessing its name.** Each row
of `Streams` has a `Table ID` field holding the id of that stream's own data
table. Read `Streams` first, match on `Stream Name`, take `Table ID`.

**`queryRecords` takes `tableId`, not `tableName`, and pages with `pageSize`
and `page` — not `limit`.** Passing `tableName` is rejected outright; passing
`limit` is silently ignored, which is worse, because you will believe you
capped the read and you did not.

**Rows come back nested.** Each record is
`{"id": 1, "id_fields": {...}, "fields": {...}}` — the data you want is inside
`fields`. Reading `row["Company Name"]` returns nothing; you need
`row["fields"]["Company Name"]`.

**The column names are Title Case with spaces, and they are not the discovery
endpoint's field names.** A stream's data table has:

| Column | Was, in the discovery payload |
|---|---|
| `Company Name` | `companyName` |
| `Relevance Reason` | `reason` |
| `Source` | `source` |
| `Confidence` | `confidence` |
| `Scraped Content` | `content` |
| `Date Added` | — |

There is **no `relevant` column**. Only rows that passed qualification are
written, so every row you read is already a pass. Do not filter on `relevant`
and do not report a pass rate from this table — that number lives on the
`Streams` row (`Total Found`, `Total Passed`).

Verified live against the base on 2026-08-11. If a read returns nothing where
you expected rows, re-check the schema with `getTableSchema` before assuming
the table is empty — a renamed column looks exactly like no data.

### 3. Ask for the job titles

**Every run. Before anything is spent. No exceptions.**

The stream's own row in `Streams` has a `Job Titles` field — for example
`Owner, Dealer Principal, General Manager, Marketing Director, VP of
Marketing, Director of Operations`. **Offer it; never assume it.**

> This stream is configured for: Owner, Dealer Principal, General Manager,
> Marketing Director, VP of Marketing, Director of Operations.
> Use those, or different ones?

Wait for an answer. A configured default is a suggestion, not consent — it was
set once, possibly by someone else, possibly for a different campaign. The
question is the one thing standing between the user and money they did not
mean to spend.

Never carry titles over silently from an earlier run in the same conversation,
and never infer them from the table's contents.

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

**The record shape, verified live on 2026-08-11.** A `people_search` hit is
deeply nested — none of the CSV fields sit at the top level, so read them from
these paths rather than guessing:

| CSV column | Path on a `people_search` record |
|---|---|
| `person_name` | `profile.full_name` (also `profile.first_name` / `last_name`) |
| `job_title` | `profile.title`, falling back to `profile.headline` |
| `linkedin_url` | `link.linkedin` |
| `email` | **not present** — see below |
| `company` | the `Company Name` from the NocoDB row you started with |

Top-level keys on a hit: `id`, `identifier`, `profile`, `link`, `location`,
`languages`, `industry`, `position_groups`, `skills`, `member_badges`,
`statistics`, `company`, `department`, `last_updated`. Some records also carry
`educations`, `awards`, `volunteer_experiences` — treat every one of these as
optional and never assume a key exists.

**`people_search` returns no email whatsoever.** Not at the top level, not
under `profile`, not under `link`. This is why the second call exists: the
email comes only from `export_single`. If you find yourself reporting emails
after a search alone, you have invented them.

Watch the two similar link fields: `link.linkedin` is the *person's* profile,
while `company.link.linkedin` and `position_groups[].company.url` are the
*company's*. Writing a company URL into `linkedin_url` is a silent, plausible
wrong answer.

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
`.env`. To check one, print whether it is set and how long it is —
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
