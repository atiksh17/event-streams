---
name: event-streams
description: Use when trialling keywords and qualification prompts for a lead-sourcing stream ("test these keywords", "the results are too broad", "try a tighter prompt"), when turning rows an automated stream has already collected into an enriched contact CSV ("enrich the new rows in <table>", "get me contacts for these companies"), or when managing the stream records themselves — saving a tested stream, editing one's config, and starting or stopping it ("start the stream", "stop that stream", "pause it", "turn this one on"). Test mode is two endpoints and two trays; production mode is NocoDB and AI Ark.
---

# Event Streams

Finds companies whose staff are doing organised events, and finds the senior
people to contact at them.

Two modes, with two narrow crossings between them. Picking the wrong one wastes
either a few minutes or real money.

| Mode | Use when | Touches |
|---|---|---|
| **Test** | Trialling keywords, sources and a qualification prompt | Discovery + qualification endpoints and the two trays, plus `Streams` to save the result |
| **Production** | Enriching rows a daily stream already collected | NocoDB + AI Ark |

Production mode never calls the discovery or qualification endpoints. Test
mode's own NocoDB is the two trays, plus one deliberate crossing: saving a
tested stream into the `Streams` table, on the user's explicit go-ahead. See
[Writing to `Streams`](#writing-to-streams), which both modes share and neither
may use without a yes.

**Enrichment is the same step in both modes.** A test that produces companies
the user likes hands them to the AI Ark procedure in
[Production mode](#production-mode) — steps 3 to 8, gates and all. Test mode
does not get a shortcut around the job-titles question, the news-publication
screening or the spend confirmation just because the rows came from a tray.

## Test mode

Test mode answers one question: **if we ran this stream for real, would it find
the right companies?** Someone is trialling keywords and a qualification prompt
and wants a readable sample quickly — so keep the keyword list short and stop
the run at a small number of qualified results.

Two stages, two endpoints, two NocoDB trays. Proven end to end 2026-08-17.

    discovery endpoint     → Source Tray     m3s2n0eevrh9d5p   every scraped item
    qualification endpoint → Relevance Tray  mz8e0h1xfwalzeh   only what passed

**The split is the whole design.** Scraping is the expensive half, so it is
banked *before* judgement. A qualification run that fails, or a prompt you want
to re-tune, replays from the Source Tray at zero scraping cost. Before this
split, a failure at minute 44 destroyed everything — 129 qualified companies
were lost exactly that way on 2026-08-15.

Nothing is written to a stream's own table in test mode. The trays are
disposable scratch space and the only NocoDB the discovery/qualification path
touches.

### The endpoints

Base `https://n8n.lrc-limited.com`.

| Stage | **Use this — the default** | Dev endpoint — developer only |
|---|---|---|
| Discovery | `POST /webhook/stream` | `POST /webhook-test/stream` |
| Qualification | `POST /webhook/qualification` | `POST /webhook-test/qualification` |

"Qualification endpoint" and "relevance check" are the same thing; the user
uses both names.

**The left column is the default and covers test mode.** If the user handed
you keywords and a prompt and said nothing about which URL to use, fire the
left column. It needs no arming and can be fired as often as you like.

**Arming and being active are two different switches, and only one is yours to
reason about.** A `webhook/` URL needs no arming, but its workflow still has to
be **Active** in n8n — and the two stages are toggled independently, so
discovery being live tells you nothing about qualification. Verified 2026-08-17:
`/webhook/stream` answered while `/webhook/qualification` 404'd with *"The
workflow must be active for a production URL to run"*, and flipping that one
toggle fixed it. Run the [GET liveness check](#the-free-liveness-check--do-this-before-blaming-a-run)
on **the stage you are about to fire**, not on the one that worked last time.

**Call the right column the *dev endpoint*, never the "test endpoint".** Test
mode is a mode the *user* runs. A `webhook-test/` URL is for whoever is
debugging the *backend*. They are two different things and the names collide,
which is exactly how a routine test-mode run ends up firing an unarmed URL and
404ing. Use a dev endpoint **only when the user has said in this conversation
that they are the developer and want to exercise the backend.** The words
"test", "testing" and "test mode" are not that statement, and never imply it.

**The dev endpoints are single-shot and must be armed by a human.** One answers
exactly one call after someone clicks *Execute workflow* on the n8n canvas,
then disarms. An unarmed call returns `404` in ~0.5s with *"not registered…
Click the 'Execute workflow' button"*. **You cannot arm it yourself** — ask the
user, wait for them to confirm, then fire once. One arming, one call: re-firing
needs re-arming.

Each stage exists as **two workflow copies** — a webhook-triggered one (what
test mode calls) and an `executeWorkflow`-triggered one the daily system calls
(production). They were split so a failure lands in one identifiable workflow
instead of a single monolith. Test mode never touches the production pair.

### Timing, measured

**Discovery** runs **~5.5 minutes** and returns `200` with the banked rows.

**Qualification acks in 1–13 seconds** with `{"message":"Workflow was
started"}` — that body is the *correct* response here, not a fault — and then
grinds in the background for roughly **10 to 15 minutes**, writing qualified
companies into the Relevance Tray as it goes.

**The pass rate is 10–20%**: one qualified company per 10 to 20 rows judged. So
a target of 10 needs on the order of 50–150 rows judged, and it is slow on
purpose. Tell the user a higher target means a longer wait rather than letting
them discover it.

**Do not quote "5 to 15 minutes" for a whole run** — that figure was never
observed and predates the split.

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

If the user has no preference, use all three and say that you did — a pass rate
means nothing without knowing which sources produced it.

### 0. Ask for all four inputs, before touching any endpoint

**Every run. All four. Before anything is fired.**

| # | Ask for | Notes |
|---|---|---|
| 1 | **Search keywords** | The terms that build the seed list of articles and posts. |
| 2 | **Qualification prompt** | Plain-English instructions for judging whether a post or article is actually relevant. |
| 3 | **Sources** | Which of the three above to sweep. |
| 4 | **How many qualified results** | The stop target `N`. **Default 10.** |

On the fourth, **say that a higher number makes the test slower** — otherwise
someone asks for 100 out of habit and waits an hour for a sample nobody reads.

> How many qualified companies do you want out of this test? Default is 10.
> The higher the number the longer it runs — only about 1 in 10 to 1 in 20
> rows passes qualification, so 10 is usually enough to judge the keywords and
> the prompt.

Whatever they say is the stop target `N`. Everything past `N` is time and
credits spent on rows that will not be read.

**If the user asks you to write the keywords or the prompt, do it — within
limits.** Keep the keyword list **short**; a test is meant to come back fast,
and a wide sweep buries the signal you are trying to read. Keep the prompt
**close to what they actually asked for** rather than an improved version of
it — they are testing their idea, not yours. **If you cannot tell what they are
after, ask before writing anything.** A prompt built on a guess produces a pass
rate that answers no question at all. [docs/test-mode.md](../../../docs/test-mode.md)
has the pattern for a prompt that discriminates.

Then check the trays are clear of other runs' rows, and **note the highest
`Id` in each** — that is your baseline, and anything above it is yours.
Never delete tray rows (rule 3).

### 1. Fire discovery

**Never run this in the foreground** — the harness kills a foreground command
at 10 minutes and the kill looks exactly like a dead endpoint.

    mkdir -p data/.runs
    RUN=$(date +%Y%m%d-%H%M%S)
    cat > "data/.runs/$RUN.request.json" <<'JSON'
    {"keywords": "...",
     "qualificationPrompt": "...",
     "sources": ["Google News", "Justgiving", "LinkedIn"]}
    JSON
    nohup curl -sS --connect-timeout 15 --max-time 900 \
      -X POST https://n8n.lrc-limited.com/webhook/stream \
      -H 'Content-Type: application/json' \
      -d @"data/.runs/$RUN.request.json" \
      -D "data/.runs/$RUN.headers" \
      -o "data/.runs/$RUN.response.json" \
      -w 'http=%{http_code} time=%{time_total}s bytes=%{size_download}' \
      > "data/.runs/$RUN.status" 2>&1 &

Expect `200` in **~5.5 minutes**, and the Source Tray to hold everything
scraped. A measured run on 2026-08-17 banked **243 rows** — 158 Justgiving,
45 Google News, 40 LinkedIn — from two keywords.

**Read `$RUN.headers` before theorising about any failure.** It says which
layer answered. A failure diagnosed without it is a guess.

#### Knowing when discovery has finished

**Watch the Source Tray, not the curl.** Poll `countRecords` on
`m3s2n0eevrh9d5p` every ~30 seconds.

- **Rows start appearing** → discovery is working. That is the signal the
  endpoint is alive and scraping. Say so, and do **not** stop anything here —
  nothing needs stopping at this stage.
- **The count stops rising, and stays flat for 20–60 seconds** → discovery is
  done. Now say it plainly: *"Discovery finished — 243 rows in the Source
  Tray."*

Do not move to qualification while the count is still climbing. Rows banked
after you build the payload are rows the test never judges.

### 2. Build the qualification payload from the Source Tray

**Send every record the Source Tray holds.** The tray is what discovery just
banked, and the whole tray is what gets judged. You are not sampling it — the
run is bounded at the far end, by stopping at `N`, not by sending less.

The shape is mechanical: **one object per tray row, the tray's column names as
the keys, that row's cells as the values.** That list of objects goes in
`data`.

Body — two fields, nothing else:

    {"data": [ {title, pubDate, link, source, domain,
                quality, bot_blocked, url, tier, content}, ... ],
     "qualificationPrompt": "<the prompt>"}

`qualificationPrompt` is **camelCase, a plain string** — not `qualification-prompt`,
not `qualification prompt`. Its value is the prompt carried on every Source
Tray row: the same string on all of them, so read it from one row and use it.

**Build it on disk, not through your context.** Every row carries `content`
averaging ~12,000 characters, so 243 rows is ~3MB — enough to swamp a
conversation. This run's discovery response file holds the same records, so
script the transform from that file straight into
`data/.runs/qual-body.json`. Only page the tray itself if that file is missing.

**If a large payload is rejected or the worker stalls**, that is the known
2026-08-15 failure — big single bodies repeatedly stalled n8n. Say so, then
split the tray into batches and fire them in sequence rather than quietly
dropping rows. Never silently send a subset: a pass rate computed over rows the
user thinks were all judged is a wrong number, not a rough one.

### 3. Fire qualification

    nohup curl -sS --connect-timeout 15 --max-time 1800 \
      -X POST https://n8n.lrc-limited.com/webhook/qualification \
      -H 'Content-Type: application/json' \
      --data-binary @"data/.runs/qual-body.json" \
      -o "data/.runs/$RUN.qual.response.json" \
      -w 'http=%{http_code} time=%{time_total}s' \
      > "data/.runs/$RUN.qual.status" 2>&1 &

`200` with `{"message":"Workflow was started"}` in seconds is **success** —
the endpoint acks and works in the background. Results arrive in the Relevance
Tray, never in this response.

### 4. Watch the Relevance Tray, stop at `N`

Poll `countRecords` on `mz8e0h1xfwalzeh` every **30–60 seconds**. Rows appear
one at a time as companies qualify. Report progress as it moves rather than
waiting in silence.

**Be patient here — this is the slow half.** Expect **10 to 15 minutes**, and a
**10–20% pass rate**: one qualified row per 10 to 20 judged. A tray that is
still empty after two minutes is normal and is not a fault.

The moment the count reaches `N` above your baseline, **stop the execution**.
Take `Execution ID` from any row this run wrote — it is populated on every row,
and **every row from one execution carries the same id**, so any of them will
do. Then:

    curl -sS -X POST \
      -H "X-N8N-API-KEY: $N8N_API_KEY" -H 'Accept: */*' \
      "https://n8n.lrc-limited.com/api/v1/executions/<Execution ID>/stop"

**The n8n public API over `curl` is the only route. Never the n8n MCP server.**
Not to stop an execution, not to list them, not to check whether one is
running. The MCP server in this environment is pointed at a different n8n
instance entirely (`primary-production-d3217.up.railway.app`, verified
2026-08-17 returning *"Application not found"*), so anything it reports is
about the wrong system — and a stop issued through it would either fail or hit
a stranger's workflow. `curl` against `n8n.lrc-limited.com/api/v1` is the
contract; there is no fallback.

**Stop only an execution id you read from a row this run wrote.** Never
`/workflows/{id}/deactivate` — that switches off the daily production stream
and fails silently.

`N8N_API_KEY` lives in `.env`. **Verified working 2026-08-17**: execution
`882` was cancelled mid-run, returning
`{"mode":"webhook","stoppedAt":"...","finished":false,"status":"canceled"}`,
and the Relevance Tray stopped growing within a minute. A `200` with
`"status":"canceled"` is the success signature — confirm it by watching the
tray go flat, not by trusting the response alone.

**If the call returns `401 {"message":"unauthorized"}`, the key is for the
wrong n8n instance.** That exact failure ran for a full day against this same
live API (docs at `/api/v1/docs/`, spec `v1.1.1`, scheme `X-N8N-API-KEY` — all
correct) and was fixed by issuing a fresh key on `n8n.lrc-limited.com` →
Settings → n8n API. Do not go hunting for a request-shape bug; there isn't one.
Say so plainly, stop polling, and tell the user the run is still spending —
measured cost of not stopping: a run targeted at 5 qualified rows reached 14.

**Set a ceiling.** If the count stops moving below `N` for ~15 minutes, stop
the execution anyway and report what you have — *"6 of 10 requested; the
stream looks narrow"* is a useful test result. Polling forever is the failure
this whole design exists to prevent.

### 5. Show the results, then ask whether to enrich

These are the qualified companies — the ones worth reaching out to. One row per
company. `content` is long, so show it only when asked.

| Company | Relevant | Confidence | Why |
|---|---|---|---|

State the pass rate plainly — *"10 qualified out of 78 judged"* — and name the
sources the run used. Then ask what they make of it:

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
a tray rather than a stream's table changes nothing about any of that.

### Iterate

Ask what is wrong with it, specifically. "Too broad" is a start, not an answer —
push for which companies should not be there and why. Then rewrite the
qualification prompt, **show the before and after**, and re-run only once the
user agrees.

`sources` is the third lever, and the cheapest one to reason about: if every
bad row came from one source, drop it from the array rather than writing a
sentence into the prompt to exclude it. If a run found almost nothing, widen
the array before you widen the keywords.

**A prompt-only change does not need a new discovery run.** The Source Tray
still holds everything the last sweep scraped, so re-fire only step 3 against
those same rows — one stage instead of two, and no re-scraping. Re-run
discovery only when the keywords or the sources changed. That is the payoff for
banking the scrape separately; take it.

A full re-run costs fifteen to twenty minutes plus another round of reading
results, so it is worth one more question up front rather than three more runs.

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
| `404 ... "The workflow must be active for a production URL to run"` | Right URL, no arming needed — the n8n workflow is simply switched **off**. Each stage toggles independently, so this happens to qualification while discovery is happily running | Only a human can fix this: ask them to activate that workflow with the toggle at the top-right of the n8n editor, then re-run. Do not retry until they confirm — it will 404 every time. **Nothing is lost**: discovery's rows are already banked, so you resume at qualification with no re-scraping |
| `404 ... is not registered ... Click the 'Execute workflow' button` in ~0.5s | A **dev endpoint** (`webhook-test/`) that nobody has armed, or whose single call is already used | **You cannot fix this yourself.** First ask why you are on a dev endpoint at all — unless the user said they are the developer, the answer is that you should be on `/webhook/…`. If a dev endpoint is genuinely wanted, ask the user to click *Execute workflow*, wait for them to confirm, then fire once. Do not retry blind — every call 404s until it is armed |
| `{"message":"Workflow was started"}` from **`/qualification`** | **Success.** That endpoint acks immediately and works in the background | Expected. Go watch the Relevance Tray; results never come back in this response |
| `{"message":"Workflow was started"}` from **`/stream`** | Wrong for discovery — that one is supposed to return its rows | The workflow needs a *Respond to Webhook* node; results are not coming |
| Any error naming `sources` | A misspelled value, or an empty/missing array | Re-check the array against the three exact strings, character by character. Fix and re-run — this one is yours, not the user's |
| `[]` | Keywords matched nothing, or the sources were too narrow | A keyword or sources problem, not a fault |
| Every row `relevant: false` | Prompt too strict | A prompt problem — offer a looser rewrite |
| **`http=000 bytes=0` with `time` at the full `--max-time`** | **The failure to expect today.** The origin accepted the connection and never wrote a response. Not an outage, not a slow run, not your request's content — the workflow is not answering the webhook | Say so plainly and **stop**. Do not re-fire, and do not start varying keywords, sources or the prompt to isolate it: four such runs on 2026-08-13/14 varied all three and hung identically. Ask the user to open the n8n execution log — **the workflow often completes and the results are sitting there**. Hung executions can also saturate n8n's workers, so each blind retry makes the next one worse |
| Body is not JSON | n8n returned an error page | Show the first 500 bytes, do not parse |
| A 16-byte body reading `error code: 524`, or `error code: 1010` with HTTP 403 | **Historical — Cloudflare, and it is no longer in front of this hostname.** Both were edge behaviours (timeout at ~120s; bot-signature block). The record was grey-clouded 2026-08-12 and verified proxy-free 2026-08-14: no `cf-ray`, no `server: cloudflare` | If either ever reappears, the hostname has been put back behind the proxy — check `$RUN.headers` first and say so, rather than debugging n8n. Note what the 524 was really hiding: it was cutting off the *same* non-response that now hangs, and turning it into a fast, legible error |

#### The free liveness check — do this before blaming a run

A **GET** to the same URL costs nothing, runs no workflow, and answers in
under a second. It separates three things a failed POST cannot:

    curl -sS --max-time 20 -D - https://n8n.lrc-limited.com/webhook/stream

| What comes back | What it tells you |
|---|---|
| `{"code":404,...,"This webhook is not registered for GET requests. Did you mean to make a POST request?"}` | **Endpoint up, workflow active, path registered.** Verified 2026-08-14, 0.53s. A POST that then hangs is a response-path problem and nothing else |
| `404 ... "The workflow must be active for a production URL to run"` | The workflow is switched **off**. One human toggle fixes it; firing more POSTs will not |
| Connection refused / DNS failure / no answer | The host itself is down — not a workflow question at all |
| `server: cloudflare` or a `cf-ray` header in the dump | The proxy is back in front of the origin, and the ~120s ceiling is back with it |

Run this **first** whenever a POST fails. It is the cheapest fact available
and it rules out three of the four possible causes in half a second.

## Production mode

The daily stream has already done discovery and judging. You start from its
rows. You never call the discovery endpoint here.

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

**4. Test mode owns the two endpoints and the two trays; production mode owns
the streams' own tables.** If you are reaching for the discovery or
qualification endpoint in production mode, you are in the wrong mode. Two
crossings are deliberate and both need a yes: **saving a stream row**, and
**enriching a test's qualified companies** through the production procedure,
gates included.

**5. The `webhook/` endpoints are the default; `webhook-test/` are dev
endpoints.** Fire `webhook/` unless the user has said they are the developer
exercising the backend. A dev endpoint answers exactly one call and only after
a human clicks *Execute workflow* — you cannot arm it, so ask and wait.

**6. Stopping a run means stopping one execution, never a workflow.**
`POST /api/v1/executions/<id>/stop`, with `<id>` from the `Execution ID` column
of a tray row *this run wrote*. `/workflows/{id}/deactivate` switches off the
daily production stream and fails silently.
