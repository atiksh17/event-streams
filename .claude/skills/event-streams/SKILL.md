---
name: event-streams
description: Use when trialling keywords and qualification prompts for a lead-sourcing stream ("test these keywords", "the results are too broad", "try a tighter prompt"), when turning rows an automated stream has already collected into an enriched contact CSV ("enrich the new rows in <table>", "get me contacts for these companies"), or when managing the stream records themselves — saving a tested stream, editing one's config, and starting or stopping it ("start the stream", "stop that stream", "pause it", "turn this one on"). Test mode is the hosted lead pipeline and the Excel workbook it produces; production mode is NocoDB and AI Ark.
---

# Event Streams

Finds companies whose staff are doing organised events, and finds the senior
people to contact at them.

Two modes, with two narrow crossings between them. Picking the wrong one wastes
either a few minutes or real money.

| Mode | Use when | Touches |
|---|---|---|
| **Test** | Trialling keywords, sources and a qualification prompt | The hosted lead pipeline and its Excel workbook, plus `Streams` to save the result |
| **Production** | Enriching rows a daily stream already collected | NocoDB + AI Ark |

Production mode never calls the lead pipeline. Test mode touches no NocoDB
except one deliberate crossing: saving a tested stream into the `Streams`
table, on the user's explicit go-ahead. See
[Writing to `Streams`](#writing-to-streams), which both modes share and neither
may use without a yes.

**Enrichment is the same step in both modes.** A test that produces companies
the user likes hands them to the AI Ark procedure in
[Production mode](#production-mode) — steps 3 to 8, gates and all. Test mode
does not get a shortcut around the job-titles question, the news-publication
screening or the spend confirmation just because the rows came from a test
workbook.

## Test mode

Test mode answers one question: **if we ran this stream for real, would it find
the right companies?** Someone is trialling keywords and a qualification prompt
and wants a readable sample — so keep the keyword list short and the sources
no wider than the question needs.

One hosted service does the whole test: the **lead pipeline**, at
`http://169.58.58.243:3000`. One request runs every stage in
order — source → resolve → dedup → crawl → classify → sink — and the result
is an **Excel workbook** for that run. Test mode touches no NocoDB except the
deliberate crossing into `Streams`.

    POST /stream            → runId          one run, every stage
    GET  /runs/<runId>      → status          stage, progress, counters
    GET  /runs/<runId>/xlsx → the workbook    every judged row, with its verdict

Nothing is written to a stream's own table in test mode, and the pipeline
writes nothing to NocoDB at all: its NocoDB sink is switched off —
`GET /config` reports `"sinks":{"csv":true,"nocodb":false}`. If that ever
reads `"nocodb":true`, say so before firing a run: it points at a retired
scratch table.

### The endpoint

Base **`http://169.58.58.243:3000`** — a remote server, not this machine.
Plain HTTP, no trailing path. Verified 2026-09-30: `/health`, `/config` and
`/runs` all answer `200`.

| Method | Path | Use |
|---|---|---|
| `GET` | `/health` | Free liveness check. `{"status":"ok",...}` means the service is up |
| `GET` | `/config` | Free. Whether auth is required, which sinks are on, `maxConcurrentRuns` |
| `POST` | `/stream` | Start a run. Answers `202 {"status":"queued","runId":"..."}` immediately |
| `GET` | `/runs/<runId>` | Status (`queued` / `running` / `completed` / `failed` / `cancelled`), `currentStage`, per-stage `done`/`total`, `progress`, `warnings` |
| `GET` | `/runs/<runId>/log?tail=50` | The run log — read it before theorising about any failure |
| `GET` | `/runs/<runId>/xlsx` | **The result.** Excel workbook, `404` until the run has finished |
| `GET` | `/runs/<runId>/csv` | Same rows as CSV |
| `POST` | `/runs/<runId>/cancel` | Stop a run. **Discards its results** — see step 4 |

**Auth.** `GET /config` says whether a token is needed. Today it reads
`"authRequired":false`, so no header is sent. If it ever reads `true`, every
route but `/health` needs `Authorization: Bearer <token>` — ask the user for
the token rather than guessing one, and never print it (rule 1).

**The server is not yours to start or restart.** It runs on a remote host. If
`/health` does not answer, that is the user's to fix — say so and stop, rather
than firing runs at it.

### Timing, measured

**A full run with all three sources takes about an hour.** Two runs on
2026-09-28 took 64 and 66 minutes: sourcing 4–8 minutes, resolve up to ~1.5,
crawl 5–9, and **classify ~50 minutes** for ~825 crawled rows. Most of a run is
judgement. Tell the user this before firing, not after they start waiting.

The time scales with how many rows the keywords and sources bring back, so
fewer keywords and fewer sources is how a test gets faster.

**The pass rate is roughly 10–20%** of rows judged.

### Pick the sources

Every request carries a third field, `sources` — an array of the sources the
run sweeps. **Three values are accepted, and the spelling is exact:**

    "Google News"
    "Justgiving"
    "LinkedIn"

- **At least one.** An empty array is not a valid request, and neither is
  omitting the field — the pipeline answers `400`.
- **Copy those strings; do not retype them from memory.** `"Google news"`,
  `"JustGiving"`, `"Linkedin"`, `"Just Giving"` are all wrong.
- The brand styles itself *JustGiving* in public. The request wants
  `Justgiving`, lowercase g. **Do not "correct" it.**
- Whatever is in the array is what runs. All three strings = all three
  sources.

If the user has no preference, use all three and say that you did — a pass rate
means nothing without knowing which sources produced it.

### 0. Ask for all four inputs, before starting a run

**Every run. All four. Before anything is fired.**

| # | Ask for | Notes |
|---|---|---|
| 1 | **Search keywords** | The terms that build the seed list of articles and posts. |
| 2 | **Qualification prompt** | Plain-English instructions for judging whether a post or article is actually relevant. |
| 3 | **Sources** | Which of the three above to sweep. |
| 4 | **How many qualified results** | How many to show. **Default 10.** |

On the fourth, be accurate about what it does. **The pipeline judges
every row it crawled, and cannot stop early without losing the run** (step 4).
So this number decides how many qualified companies you present, highest
confidence first. It does not change how long the run takes; keywords and
sources do.

> How many qualified companies do you want to look at? Default is 10. The run
> itself takes about an hour whatever you pick — fewer keywords or sources is
> what makes it quicker.

Whatever they say is the display target `N`.

**If the user asks you to write the keywords or the prompt, do it — within
limits.** Keep the keyword list **short**; a test is meant to come back fast,
and a wide sweep buries the signal you are trying to read. Keep the prompt
**close to what they actually asked for** rather than an improved version of
it — they are testing their idea, not yours. **If you cannot tell what they are
after, ask before writing anything.** A prompt built on a guess produces a pass
rate that answers no question at all. [docs/test-mode.md](../../../docs/test-mode.md)
has the pattern for a prompt that discriminates.

### 1. Check the service, then start the run

    curl -sS --max-time 10 http://169.58.58.243:3000/health

Then write the request to disk and fire it. `POST /stream` answers in well
under a second, and the run carries on inside the pipeline's own process, so
there is nothing to background on your side.

    mkdir -p data/.runs
    RUN=$(date +%Y%m%d-%H%M%S)
    cat > "data/.runs/$RUN.request.json" <<'JSON'
    {"keywords": "...",
     "qualificationPrompt": "...",
     "sources": ["Google News", "Justgiving", "LinkedIn"]}
    JSON
    curl -sS --max-time 30 -X POST http://169.58.58.243:3000/stream \
      -H 'Content-Type: application/json' \
      --data-binary @"data/.runs/$RUN.request.json" \
      | tee "data/.runs/$RUN.response.json"

Expect `202` with `{"status":"queued","runId":"20260928T133025Z-37cunf",...}`.
**Keep the `runId`** — every later call uses it. A `queuePosition` above 0
means other runs are ahead (`MAX_CONCURRENT_RUNS`, default 3); it starts when a
slot frees.

`keywords` is one comma-separated string. A leading `#` keeps a hashtag for
LinkedIn. `daysInPast` is optional (default 14).

### 2. Watch the run

Poll `GET /runs/<runId>` every **60 seconds**. Report movement as it happens
rather than waiting in silence:

- `currentStage` and that stage's `done`/`total`/`unit` — e.g. *"crawl: 410 of
  1188 pages"*, *"classify: batch 12 of 33"*.
- `progress.sourced`, `progress.bySource`, `progress.afterDedup`,
  `progress.crawled` — as each stage closes.
- `warnings` — a source that failed while the others carried on. **Say so**:
  the run is still useful, but its pass rate describes fewer sources than the
  user asked for.

`progress.matched` is only filled in when classify finishes, so there is no
live qualified count — do not report one.

The run is finished when `status` is `completed` (or `failed` / `cancelled`).
Classify sitting on the same batch for several minutes is normal; each LLM
call can take a couple of minutes, and retries are logged. Check
`/runs/<runId>/log?tail=50` before calling it stuck.

### 3. Download the Excel and read it

Once `status` is `completed`:

    curl -sS -f -o "data/.runs/$RUN.xlsx" \
      "http://169.58.58.243:3000/runs/<runId>/xlsx"

That local copy is the one to read and to hand the user — the server's own
files are on the remote host. `GET /runs/<runId>/csv` gives the same rows as
CSV if that is ever easier.

**The workbook has two sheets.**

- **`Leads`** — one row per crawled lead, frozen header. Columns, as headed:
  `Title`, `Published`, `Link`, `URL`, `Source`, `Domain`, `Quality`,
  `Bot blocked`, `Tier`, `Type`, `Author`, `Content`, `Qualification prompt`,
  `Match`, `Confidence`, `Reason`.
- **`Run`** — the request (keywords, sources, prompt), per-stage timings and
  row counts, and every counter.

**`Match` is text, not a boolean**: `true`, `false`, or **empty**. Empty means
the row was **never judged** — its LLM batch failed — which is not the same as
a rejection. `Confidence` is a number 0–100, empty on unjudged rows.

**Read it with a script, not through your context.** `Content` runs to
thousands of characters per row. Pull the qualified rows out on disk:

    python - "data/.runs/$RUN.xlsx" <<'PY'
    import sys, openpyxl            # pip install openpyxl, if missing
    ws = openpyxl.load_workbook(sys.argv[1], read_only=True)["Leads"]
    rows = ws.iter_rows(values_only=True)
    head = next(rows)
    leads = [dict(zip(head, r)) for r in rows]
    judged = [l for l in leads if l["Match"] in ("true", "false")]
    passed = sorted((l for l in leads if l["Match"] == "true"),
                    key=lambda l: -(l["Confidence"] or 0))
    print(f"{len(leads)} rows, {len(judged)} judged, {len(passed)} passed")
    for l in passed:
        print(l["Confidence"], l["Source"], l["Domain"], l["Title"], "|", l["Reason"])
    PY

**Unjudged rows change the arithmetic.** On 2026-09-28 one run had 825 rows
and only 152 judged. The pass rate is **passed ÷ judged**, never passed ÷ all
rows. A large unjudged share is a fault to report — grep the run log for
`classify request failed` — not a verdict on the prompt.

### 4. Stopping a run

`POST /runs/<runId>/cancel` stops it — a queued run is dropped, a running one
has its requests aborted. **A cancelled run produces no workbook**: rows are
written only once classify has finished, so everything judged so far is lost.
Cancel only when the user asks for it, and tell them that first. Never cancel
a run you did not start.

### 5. Show the results, then ask whether to enrich

These are the qualified rows — the ones worth reaching out to. Show the top `N`
by confidence. The company is not a column of its own: name it from the
article, the `Domain`, or the `Author` on a LinkedIn row. `Content` is long, so
show it only when asked.

| Company | Source | Confidence | Why |
|---|---|---|---|

State the pass rate plainly — *"27 passed out of 152 judged (673 not judged —
LLM batches failed)"* — and name the sources the run used. Give them the
workbook path too, so they can open `data/.runs/<RUN>.xlsx` in Excel
themselves. Then ask what they make of it:

> Ten qualified companies from those keywords and that prompt. Do these look
> right to you?

Two ways forward, and the user picks:

- **They are not happy** → iterate on the prompt, keywords or sources, below.
- **They are happy** → offer to **enrich** them, and offer to **save the
  stream**. Two separate offers; neither is implied by liking the data.

**Enrichment is unchanged and is the production-mode procedure** — AI Ark via
the `ai-ark` MCP server, [steps 3 to 8](#3-screen-for-news-publications-and-dodgy-rows).
Every gate there still applies: screen the news publications and dodgy rows,
**ask for the job titles**, confirm the spend, then enrich. Rows arriving from
a workbook rather than a stream's table changes nothing about any of that.

### Iterate

Ask what is wrong with it, specifically. "Too broad" is a start, not an answer —
push for which companies should not be there and why. Then rewrite the
qualification prompt, **show the before and after**, and re-run only once the
user agrees.

`sources` is the third lever, and the cheapest one to reason about: if every
bad row came from one source, drop it from the array rather than writing a
sentence into the prompt to exclude it. If a run found almost nothing, widen
the array before you widen the keywords.

**Every change is a full re-run.** The pipeline cannot re-judge an
earlier run's rows against a new prompt, so even a prompt-only change scrapes
again. That is about an hour each time, so it is worth one more question up
front rather than three more runs.

### When the user is happy

Show the row that would go into the `Streams` table, using that table's own
column names rather than the request's field names:

    Stream Name:          <a short name for it>
    Stream Description:   <one line on what it is looking for>
    Keywords:             <the winning keywords>
    Qualification Prompt: <the winning prompt>
    Sources:              <the sources that run used, exactly as spelled>
    Enabled:              false

`Streams` **has** a `Sources` column — a multi-value field holding the same
exact strings the request uses, for example
`["Google News", "LinkedIn", "Justgiving"]`. Verified live 2026-08-11. Put the
sources in it; they are not an aside to mention in passing. The result the
user is about to schedule came from those sources and no others, and a row
saved without them will run against the wrong ones.

**Then offer to write it, and wait.** You may create the row yourself — see
[Writing to `Streams`](#writing-to-streams) for the exact shape — but only
once the user has said yes to that specific row. Showing it is not asking, and
a successful test is not consent.

**The new row is always created with `Enabled` false.** A row in `Streams`
means "run this every day, forever", and switching that on is its own separate
question, asked after the row exists. Never fold the two together.

### When it goes wrong

| What you see | What it means | What to say |
|---|---|---|
| `curl: (7) Failed to connect`, or a timeout on `/health` | The remote pipeline server is down or unreachable | Not yours to fix — tell the user the server at `169.58.58.243:3000` is not answering, and stop. Nothing was lost — no run started |
| `400 {"status":"error","errors":[...]}` | The request was rejected — a missing field, an empty `sources`, or an unknown source name | Read the `errors` array, fix the request, re-fire. This one is yours, not the user's |
| `401 {"status":"error","message":"unauthorized"}` | The server now requires a token (`/config` → `"authRequired":true`) | Ask the user for it and send `Authorization: Bearer <token>`. Never print it |
| `404` from `/runs/<runId>/xlsx` | The run has not finished, or produced no rows | Check `/runs/<runId>`. Still running → keep polling. `completed` with nothing → a keyword or sources problem |
| `status: failed` | The run broke. `error` on the record says why; *every requested source failed* is the common one | Read `/runs/<runId>/log?tail=50` and report the actual error. One failed source alone does not fail a run — that shows up in `warnings` instead |
| `status: failed`, `error` *"interrupted by a server restart"* | The remote server restarted mid-run | Nothing can be recovered from that run. Tell the user, and re-fire only on their go-ahead |
| `warnings` naming one source | That source failed; the run carried on with the others | Say which source is missing from the result, so the pass rate is read in that light |
| Most rows have an empty `Match` | LLM batches failed, so those rows were never judged | Report judged and unjudged counts separately. Grep the log for `classify request failed` — the cause is there. Not a prompt problem |
| Every judged row `false` | Prompt too strict | A prompt problem — offer a looser rewrite |
| Very few rows at all | Keywords matched little, or the sources were too narrow | A keyword or sources problem, not a fault |

## Production mode

The daily stream has already done discovery and judging. You start from its
rows. You never call the lead pipeline here.

Reads NocoDB via the `nocodb-streams` MCP server, enriches via the `ai-ark`
MCP server. Never writes to AI Ark, and writes to NocoDB only through
[Writing to `Streams`](#writing-to-streams) — the `Streams` table, six
columns, always on a confirmed yes. Enrichment output is a CSV, never a write
back into the table you read. Two different agent harnesses run this skill;
both are configured with servers of these same two names.

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

Read the `Streams` table first and show what exists. The full column list,
verified live 2026-08-11, is wider than the handful you usually need:

- **Identity and config** — `Stream Name`, `Stream Description`, `Keywords`,
  `Qualification Prompt`, `Sources`, `Job Titles`, `Max Results`, `Lookback`
- **Where the data lives** — `Table ID`
- **State** — `Status`, `Enabled`, `Anchor`, `Last Run`, `Last Run Status`
- **Running totals** — `Total Found`, `Total Passed`, `Total Contacts`,
  `Valid Emails`, `Cost`
- **Rolling counts** — `Last 24h`, `Last 3d`, `Last 7d`, `Last 1m`

That one read tells you what the streams are, which are live, where each
one's data lives, and what it has already cost.

`Status` and `Enabled` are **two separate gates**, not one. A row can read
`Enabled: 1` and still sit at `Status: draft` — that is the live demo row
today. Do not report a stream as running on the strength of `Enabled` alone.

A stream whose `Status` is `draft` has never run and its table will be empty.
Say that plainly rather than reporting "no rows found" as if something broke.
Confirm it with `getTableSchema` before you say it, though — an empty table
and a renamed column look identical from a query that returns nothing.

The NocoDB base itself is titled "Streams", and it also contains a table
titled `Streams` — when it could be misread, say "the base" or name the table,
not just "Streams".

#### Two critical tables — never deleted, never enrichment targets

| Table | Id | What it is |
|---|---|---|
| `Streams` | `mfo88n8n35b9qvl` | The scheduler. One row per stream. Read it to list what is running. Six of its columns are writable on a confirmed yes — [Writing to `Streams`](#writing-to-streams) — and nothing else about it is. Never an enrichment target, never deleted. |
| `Template (DO NOT TOUCH)` | `m0liglo73sxjwa8` | Reserved. Never read it, never write it, never offer it as a target. |

Every other table in the base is the data table of one individual stream — for
example `Demo Stream — Dealership Group Expansions` — and each is a valid
enrichment target. New ones appear over time, so the rule is "not `Streams`,
not `Template (DO NOT TOUCH)`", never a fixed list you memorize. Check the ids
as well as the names: a table can be renamed, and then a name-only check stops
protecting it.

#### How a stream and its table are linked

**Each row in `Streams` corresponds to exactly one data table, and the link is
the `Table ID` column.** That column on a stream's row holds the id of that
stream's own table. It is the only reliable route from a stream to its data.
Never guess a table name from a stream name and never pair them up by eye —
read `Streams`, match on `Stream Name`, take `Table ID`, query that id.

**How that table comes into existence.** A row in `Streams` needs `Keywords`,
`Qualification Prompt` and `Sources` filled in, and `Enabled` set true. The
automated system then creates that stream's data table, names it after the
stream, and writes the new table's id back into the `Table ID` column of that
row in `Streams`.

The config and the switch are yours to write, on a confirmed yes; the table is
not. You may fill in `Keywords`, `Qualification Prompt` and `Sources`, and you
may set `Enabled` true — that is what starting a stream *is*. Creating the
data table and writing `Table ID` back are the automated system's work, and
the MCP endpoint could not create a table anyway: its scope is record-level
only.

So expect a lag. A row you just enabled will have an empty `Table ID` until
the automated system has been round; that is the normal state of a
newly-started stream, not a fault, and not something to fix by writing an id
in yourself. A row whose `Table ID` is empty is a stream whose table has not
been created yet — say that plainly rather than hunting for a table that does
not exist.

### 2. Read the rows

Read-only, always: `getBaseInfo`, `getTablesList`, `getTableSchema`,
`queryRecords`, `getRecord`, `countRecords`, `aggregate`, `readAttachment`.

**A stream's data table is read-only, all of it.** Enrichment never writes
back into the table it read from — the deliverable is a CSV. `createRecords`
and `updateRecords` are for the `Streams` table alone, and only through
[Writing to `Streams`](#writing-to-streams). `deleteRecords` is never called
against anything, ever: it is not part of what this skill may do, and against
the live base it has no undo. The token is write-capable, so nothing but these
rules stops you.

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

| Column | NocoDB type | Was, in the discovery payload |
|---|---|---|
| `Company Name` | SingleLineText | `companyName` |
| `Relevance Reason` | LongText | `reason` |
| `Source` | SingleLineText | `source` |
| `Confidence` | Decimal | `confidence` |
| `Scraped Content` | LongText | `content` |
| `Date Added` | Date | — |

**`Confidence` is stored 0–100, even though the stream's prompt asks for
0–1.** Settled by the first real rows on 2026-08-11: 29 rows in the demo
stream carry 85, 90, 95 and 100 — the endpoint's integer scale written
straight through. Two things suggest otherwise and both are misleading: the
column's `Decimal` type, and the live stream's own `Qualification Prompt`,
which still ends *"Return a confidence score from 0 to 1"*. Trust the stored
values.

The 0–100 bands in [docs/test-mode.md](../../../docs/test-mode.md) therefore
read straight against these rows. The stale 0–1 instruction in the stream's
prompt is worth correcting, and `Qualification Prompt` is one of the six
columns you may write — so offer the fix, show the before and after, and wait
for the yes. Do not slip it into an unrelated write.

There is **no `relevant` column**. Only rows that passed qualification are
written, so every row you read is already a pass. Do not filter on `relevant`
and do not report a pass rate from this table — that number lives on the
`Streams` row (`Total Found`, `Total Passed`).

Verified live against the base on 2026-08-11. If a read returns nothing where
you expected rows, re-check the schema with `getTableSchema` before assuming
the table is empty — a renamed column looks exactly like no data.

### 3. Screen for news publications and dodgy rows

The streams read Google News and LinkedIn, so **news publications sweep into
the results**. They are the most common wrong row in any batch, and enriching
one spends money chasing contacts at a company that was never a lead.

Before anything is spent, sort the rows into three buckets, then show the user
what you found.

**Clean** — an ordinary company. These enrich on the user's go-ahead like any
other row, with no extra question.

**News publication** — the `Company Name` is a newspaper, magazine, trade
title, broadcaster, wire service or business-news outlet. Never enrich one on
the strength of the row alone. Re-read that row's `Scraped Content` against
the stream's `Qualification Prompt` and work out whether the article genuinely
qualifies **the publication itself**.

**Dodgy** — the article does describe something qualifying, but what it
describes belongs to a *different* company mentioned inside it. The
publication is on the list because it wrote the piece, not because it did the
thing. Also treat as dodgy any `Company Name` that is not really a company: a
team, a facility, a department, a job function.

About nine in ten news publications are not leads. That is a base rate, not a
reason to skip the reading — the tenth is real. A publication whose own staff
rode in the event qualifies exactly as well as any other employer, and a
newsroom that organises a corporate challenge is a legitimate target.

**Every flagged row needs its own confirmation, and that is a separate
question from the spend confirmation in step 5.** Never fold the two together
and never decide on the user's behalf. Give the full context — the name, why
it was flagged, what the article actually says, and which company the evidence
really points at — then ask, one row at a time:

> `Business News` is a news publication. Its article describes its own CEO
> riding in the corporate cycling challenge it runs, so it may genuinely
> qualify on its own account. Enrich it, or skip it?

> `Doximity` is dodgy. It appears only as a tag in an article about staff at
> other healthcare organisations riding — the evidence points at them, not at
> Doximity. Enrich it, or skip it?

Wait for an answer on each one. "Enrich everything that isn't a news
publication" answers for the clean bucket only; the flagged rows still need
their own yes. A blanket approval given before the flags were shown is not
consent to spend on them.

Report the buckets before you ask:

    29 rows
    24 clean
    4 news publications (Business News ×4)
    1 dodgy (Doximity — appears only as a tag)

### 4. Ask for the job titles

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

### 5. Confirm the spend

State it plainly and wait. Say what is included, and name anything flagged in
step 3 that the user agreed to keep, so the total is never a surprise:

> 24 clean companies, plus `Business News` which you approved, × 3 job titles.
> Enriching now?

### 6. Enrich

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

### 7. Write the CSV

`data/<table-slug>-YYYY-MM-DD.csv`, unless the user has said they want
something else — in which case theirs wins and you do not argue.

Columns: `company`, `person_name`, `job_title`, `email`, `linkedin_url`,
`source_table`, `enriched_at`. One row per person. Companies that returned
nobody appear in the report, not as blank rows.

### 8. Report honestly

    38 companies in
    91 people out
    64 with an email (70%)
    88 with a LinkedIn (97%)
    6 companies returned nobody
    5 skipped as news publications or dodgy (not enriched, not charged)

Rows skipped at step 3 belong in the report. A company that was screened out
must never be indistinguishable from one that was searched and found nobody.

If coverage is poor, say so and say why. Do not round it up and do not present
a thin result as a good one.

## Writing to `Streams`

The `Streams` table is the scheduler, and the row *is* the stream. You may
write to it: create a stream, edit its config, start it, stop it. Both modes
can, and it is the only system they share.

**Nothing here happens without the user's explicit yes to that specific
write.** Not a yes to the conversation, not a yes to the test run that
produced the values, not a standing instruction from earlier in the session.
The write itself is the thing being agreed to.

Table id `mfo88n8n35b9qvl`. Schema below verified live 2026-08-13.

### The six columns you may write

| Column | NocoDB type | Holds |
|---|---|---|
| `Stream Name` | SingleLineText | What the stream is called. The automated system names the data table after it. |
| `Stream Description` | LongText | One line on what it is looking for. |
| `Keywords` | LongText | The search terms, comma separated. |
| `Qualification Prompt` | LongText | The judging prompt applied to each result. |
| `Sources` | MultiSelect | Any of `Google News`, `LinkedIn`, `Justgiving` — the same exact literals the discovery request uses, and the only three the field accepts. |
| `Enabled` | Checkbox | The switch. True runs the stream daily; false does not. Reads back as `0`/`1`. |

**Every other column is the automated system's and is never written** —
`Table ID`, `Last Run`, `Last Run Status`, and any state, cost or totals
columns the base grows later. Not to correct one, not to backfill one, not to
tidy up. If a stream's numbers look wrong, say so; do not fix them.

`deleteRecords` is never called against any table in this base. Removing a
stream is not a thing this skill does — a stream the user is finished with
gets `Enabled` set false, and the row stays.

### Creating a stream

`Enabled` is **false on every new row, with no exception**, whatever the user
said about wanting it running. Create it off, confirm it landed, then ask
about starting it as a fresh question.

Show the full row, ask, wait:

> Create this stream?
>
>     Stream Name:          Dealership Group Expansions
>     Stream Description:   Dealer groups opening or acquiring sites
>     Keywords:             dealership acquisition, new showroom, ...
>     Qualification Prompt: <the full prompt, not a summary>
>     Sources:              Google News, LinkedIn
>     Enabled:              false
>
> It will be created switched off. I'll ask separately about starting it.

Then, and only on a yes:

    createRecords(tableId: "mfo88n8n35b9qvl",
                  records: [{fields: {"Stream Name": "...",
                                      "Stream Description": "...",
                                      "Keywords": "...",
                                      "Qualification Prompt": "...",
                                      "Sources": ["Google News", "LinkedIn"],
                                      "Enabled": false}}])

Show the full `Qualification Prompt` in the confirmation, not a paraphrase of
it. It is the one field whose wording decides what the stream costs and what
it returns, and a user agreeing to "the prompt we discussed" has not read it.

**`Sources` has not been written through this endpoint yet.** Reads return it
as an array, and the field's own default is stored comma-joined
(`"Google News,LinkedIn,Justgiving"`) — so if the array form is rejected, send
the comma-joined string instead and record which one worked in
[reference/endpoints.md](../../../docs/reference/endpoints.md). Either way the
three literals are exact. Read the row back after the first create and confirm
`Sources` actually landed before telling the user it did.

### Starting and stopping a stream

`Enabled` is the switch and flipping it is the whole operation.

| The user says | What you set |
|---|---|
| start it · turn it on · run it daily · resume it | `Enabled` → true |
| stop it · turn it off · pause it · shut it down | `Enabled` → false |

Confirm first, naming the stream and the direction so a misheard "that one"
surfaces before it costs a day of runs:

> Start `Dealership Group Expansions`? It will run every day from then on.

> Stop `Dealership Group Expansions`? It will stop collecting until you start
> it again.

Then one field, on the row's own `Id`:

    updateRecords(tableId: "mfo88n8n35b9qvl",
                  records: [{id: <the row's Id>, fields: {"Enabled": true}}])

Read `Streams` first and match on `Stream Name` to get that `Id` — never
assume a row number and never write to a row you have not read. If two
streams have similar names, ask which; do not pick the closer match.

Starting a stream is the write that spends money — it runs every day until
someone stops it. Treat it with the same care as the enrichment spend
confirmation.

### Editing a stream's config

Show before and after, per field, then ask:

> `Dealership Group Expansions` — `Keywords`
>
>     was: dealership acquisition, new showroom
>     now: dealership acquisition, new showroom, group expansion
>
> Apply this?

Send only the fields that changed. A write that re-sends unchanged fields
looks harmless and is not: it will silently overwrite anything a human edited
in NocoDB between your read and your write.

Editing config does not touch `Enabled`. A running stream stays running, and
its next daily run uses the new config — say so, because it means the change
takes effect without anyone starting anything.

## Rules that must not need a lookup

**1. Never print a secret.** Not a key, not a token. They live in
`.env`. To check one, print whether it is set and how long it is —
never its value.

**2. Job titles are asked for every single time.** It is the one question that
stands between the user and money they did not mean to spend.

**2b. News publications and dodgy rows are never enriched without their own
explicit yes.** The sources are news sites, so publications sweep in; about
nine in ten are not leads. Flag each one, re-read its article against the
qualification prompt, hand the user the full context, and ask per row. A
blanket "enrich the rest" covers the clean rows only.

**3. Every write to NocoDB is confirmed first, and only `Streams` is ever
written.** Six columns — `Stream Name`, `Stream Description`, `Keywords`,
`Qualification Prompt`, `Sources`, `Enabled` — and nothing else, on any table.
A new stream row is always created with `Enabled` false; enabling it is a
separate question. `deleteRecords` is never called. These rules are the only
thing stopping a bad write: the connected token is write-capable and blocks
none of it, and against the live base there is no undo.

**4. Test mode owns the hosted lead pipeline and its workbooks; production
mode owns the streams' own tables.** If you are reaching for the pipeline in
production mode, you are in the wrong mode. Two crossings are deliberate and
both need a yes: **saving a stream row**, and **enriching a test's qualified
companies** through the production procedure, gates included.

**5. The pipeline's NocoDB sink stays off.** Test mode writes nothing to
NocoDB; its output is the Excel workbook. Never set `NOCODB_ENABLED` true.

**6. Cancelling a run throws its results away.** `POST /runs/<runId>/cancel`
leaves no workbook, because rows are written only after classify finishes.
Cancel only on the user's say-so, having told them that, and only a run you
started.
