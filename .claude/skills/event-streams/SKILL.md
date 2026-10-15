---
name: event-streams
description: Use when trialling keywords and qualification prompts for lead sourcing ("test these keywords", "the results are too broad", "try a tighter prompt"); when setting up or managing a stream that collects on a schedule ("run this every Monday", "schedule it", "what has my stream found?", "pause that stream", "change its keywords"); or when turning the companies a stream has collected into an enriched contact CSV ("enrich the new companies", "get me contacts for these"). One hosted lead pipeline does discovery, judging, scheduling and storage; AI Ark does the contact enrichment.
---

# Event Streams

Finds companies whose staff are doing organised events, and finds the senior
people to contact at them.

**One system does the collecting.** The **lead pipeline** at
`http://169.58.58.243:3000` runs every stage — source → resolve → dedup →
crawl → classify → sink — and owns the streams, their schedules, the companies
they have found and the workbooks. There is no second place the data lives.
`ai-ark` is the only other service, and it does one job: turning a company into
named contacts with emails.

Three things happen here, and they are asked for in different words.

| | Use when | Touches |
|---|---|---|
| **Test run** | Trialling keywords, sources and a qualification prompt | `POST /stream`, one run, one workbook |
| **Stream** | Collecting the same thing on a schedule, forever | `POST /schedules`, one growing workbook per stream |
| **Enrichment** | Turning companies already collected into contacts | `ai-ark`, reading companies from the pipeline |

A test run is minutes of nobody's money. A stream spends on every tick, and
enrichment spends per company — so both have gates, and the gates are the
point of this document.

**Enrichment is one procedure wherever the companies came from.** Companies
from a test run and companies from a six-week-old stream go through the same
[Enrichment](#enrichment) steps, gates and all. Test output does not get a
shortcut around the job-titles question, the news-publication screening or the
spend confirmation just because it came from a test.

## The endpoint

Base **`http://169.58.58.243:3000`** — a remote server, not this machine.
Plain HTTP, no trailing path.

### Runs

| Method | Path | Use |
|---|---|---|
| `GET` | `/health` | Free liveness check. `{"status":"ok",...}` means the service is up |
| `GET` | `/config` | Free. Whether auth is required, which sinks are on, `maxConcurrentRuns`, schedule limits |
| `POST` | `/stream` | Start one run. Answers `202 {"status":"queued","runId":"..."}` immediately |
| `GET` | `/runs/<runId>` | Status (`queued` / `running` / `completed` / `failed` / `cancelled`), `currentStage`, per-stage `done`/`total`, `progress`, `warnings` |
| `GET` | `/runs/<runId>/log?tail=50` | The run log — read it before theorising about any failure |
| `GET` | `/runs/<runId>/xlsx` | The run's workbook. `404` until the run has finished |
| `GET` | `/runs/<runId>/csv` | Same rows as CSV |
| `POST` | `/runs/<runId>/cancel` | Stop a run. **Discards its results** — see [Stopping a run](#4-stopping-a-run) |

### Streams

| Method | Path | Use |
|---|---|---|
| `POST` | `/schedules` | **Create a stream.** `201` with a `scheduleId`. Spends on every tick — see [Streams](#streams) |
| `GET` | `/schedules` | Every stream: cadence, `nextRunAt`, totals |
| `GET` | `/schedules/<id>` | One stream, plus a line per tick in `runs` |
| `PATCH` | `/schedules/<id>` | Change its config. Only the fields you send |
| `POST` | `/schedules/<id>/pause` | Stop future ticks. The run in flight is left to finish |
| `POST` | `/schedules/<id>/resume` | Arm it again |
| `POST` | `/schedules/<id>/run` | Fire one tick now |
| `DELETE` | `/schedules/<id>` | Remove it. Its collected rows stay on disk |

### Reading what streams have collected

| Method | Path | Use |
|---|---|---|
| `GET` | `/schedules/<id>/companies` | **One entry per organisation.** The read to reach for first |
| `GET` | `/schedules/<id>/leads` | The articles behind them, filterable |
| `GET` | `/companies` | Every stream's companies, each labelled with the stream that found it |
| `GET` | `/leads` | Every stream's rows, same filters |
| `GET` | `/schedules/<id>/xlsx` | The accumulated workbook — for the user, not for you |
| `GET` | `/schedules/<id>/csv` | The same rows as CSV |

**Auth.** `GET /config` says whether a token is needed. Today it reads
`"authRequired":false`, so no header is sent. If it ever reads `true`, every
route but `/health` needs `Authorization: Bearer <token>` — ask the user for
the token rather than guessing one, and never print it (rule 1).

**The server is not yours to start or restart.** It runs on a remote host. If
`/health` does not answer, that is the user's to fix — say so and stop, rather
than firing runs at it.

## Timing, measured

**A full run with all three sources takes about an hour.** Two runs on
2026-09-28 took 64 and 66 minutes: sourcing 4–8 minutes, resolve up to ~1.5,
crawl 5–9, and **classify ~50 minutes** for ~825 crawled rows. Most of a run is
judgement. Tell the user this before firing, not after they start waiting.

The time scales with how many rows the keywords and sources bring back, so
fewer keywords and fewer sources is how a run gets faster. **The pass rate is
roughly 10–20%** of rows judged.

This is also why a stream's interval cannot be short — see
[Pick a day and a time](#pick-a-day-and-a-time).

## Pick the sources

Every request carries `sources` — an array of the sources to sweep. **Three
values are accepted, and the spelling is exact:**

    "Google News"
    "Justgiving"
    "LinkedIn"

- **At least one.** An empty array is not a valid request, and neither is
  omitting the field — the pipeline answers `400`.
- **Copy those strings; do not retype them from memory.** `"Google news"`,
  `"JustGiving"`, `"Linkedin"`, `"Just Giving"` are all wrong.
- The brand styles itself *JustGiving* in public. The request wants
  `Justgiving`, lowercase g. **Do not "correct" it.**

### Offer them as a choice

**Do not pick silently.** Lay the three out and let the user choose, saying
what each one actually brings — they answer very different questions, and a
user who has only ever seen "all three" has never had the chance to narrow it:

> Which sources should it sweep? You can pick any combination:
>
> - **Google News** — press coverage. Articles about events that already
>   happened or were announced. The widest net and most of the volume.
> - **Justgiving** — fundraising pages. UK charity events and the groups
>   running them, straight from the platform rather than from reporting.
> - **LinkedIn** — posts by the organisations and staff themselves. Often the
>   earliest signal, and the post's author usually *is* the company.
>
> All three is the default if you have no preference.

Multi-select, not one-of: any combination of the three is valid, and
**at least one** is required.

If they genuinely have no preference, use all three — and **say that you
did**, because a pass rate means nothing without knowing which sources produced
it. "I used all three" is a report, not a reason to skip the question.

When a result disappoints, sources are the cheapest lever to reach for before
rewriting a prompt — see [Iterate](#iterate).

## Testing a stream

A test answers one question: **if we ran this for real, would it find the right
companies?** Keep the keyword list short and the sources no wider than the
question needs.

### 0. Ask for all four inputs, before starting a run

**Every run. All four. Before anything is fired.**

| # | Ask for | Notes |
|---|---|---|
| 1 | **Search keywords** | The terms that build the seed list of articles and posts. |
| 2 | **Qualification prompt** | Plain-English instructions for judging whether a post or article is actually relevant. |
| 3 | **Sources** | Which of the three to sweep. **Offer them as a list** — see [Offer them as a choice](#offer-them-as-a-choice). Any combination; at least one. |
| 4 | **How many qualified results** | How many to show. **Default 10.** |

On the fourth, be accurate about what it does. **The pipeline judges every row
it crawled, and cannot stop early without losing the run** (step 4). So this
number decides how many qualified companies you present, highest confidence
first. It does not change how long the run takes; keywords and sources do.

> How many qualified companies do you want to look at? Default is 10. The run
> itself takes about an hour whatever you pick — fewer keywords or sources is
> what makes it quicker.

**If the user asks you to write the keywords or the prompt, do it — within
limits.** Keep the keyword list **short**; a wide sweep buries the signal.
Keep the prompt **close to what they actually asked for** rather than an
improved version of it — they are testing their idea, not yours. **If you
cannot tell what they are after, ask before writing anything.** A prompt built
on a guess produces a pass rate that answers no question at all.
[docs/test-mode.md](../../../docs/test-mode.md) has the pattern for a prompt
that discriminates.

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
means other runs are ahead (`MAX_CONCURRENT_RUNS`, default 3).

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

Classify sitting on the same batch for several minutes is normal; each LLM
call can take a couple of minutes, and retries are logged. Check
`/runs/<runId>/log?tail=50` before calling it stuck.

### 3. Download the Excel and read it

Once `status` is `completed`:

    curl -sS -f -o "data/.runs/$RUN.xlsx" \
      "http://169.58.58.243:3000/runs/<runId>/xlsx"

That local copy is the one to read and to hand the user — the server's own
files are on the remote host.

**The workbook has two sheets.**

- **`Leads`** — one row per crawled lead, frozen header. Columns, as headed:
  **`Company`**, `Title`, `Published`, `Link`, `URL`, `Source`, `Domain`,
  `Quality`, `Bot blocked`, `Tier`, `Type`, `Author`, `Content`,
  `Qualification prompt`, `Match`, `Confidence`, `Reason`.
- **`Run`** — the request (keywords, sources, prompt), per-stage timings and
  row counts, and every counter.

**`Company` is the organisation the lead is about**, extracted by the model
during judging — not the publisher. It is empty when the model could not tell
from the headline and excerpt; that is honest, not broken.

**`Match` is text, not a boolean**: `true`, `false`, or **empty**. Empty means
the row was **never judged** — its LLM batch failed — which is not the same as
a rejection. `Confidence` is a number 0–100, empty on unjudged rows.

**Read it with a script, not through your context.** `Content` runs to
thousands of characters per row:

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
        print(l["Confidence"], l["Company"], "|", l["Source"], l["Title"], "|", l["Reason"])
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

### 5. Show the results, then ask what next

Show the top `N` qualified companies by confidence, using the `Company`
column. `Content` is long, so show it only when asked.

| Company | Source | Confidence | Why |
|---|---|---|---|

State the pass rate plainly — *"27 passed out of 152 judged (673 not judged —
LLM batches failed)"* — and name the sources the run used. Give them the
workbook path too, so they can open `data/.runs/<RUN>.xlsx` themselves. Then:

> Ten qualified companies from those keywords and that prompt. Do these look
> right to you?

Three ways forward, and the user picks:

- **Not happy** → iterate on the prompt, keywords or sources, below.
- **Happy, and wants contacts now** → [Enrichment](#enrichment).
- **Happy, and wants this collecting on a schedule** → [Streams](#streams).

Those last two are **separate offers, and neither is implied by liking the
data**. Offer them as two questions, and take no for an answer on either.

If they want it collecting, that is when you ask for the day and time — not
before, and never by assuming one. See [Is this even a stream?](#is-this-even-a-stream).

### Iterate

Ask what is wrong with it, specifically. "Too broad" is a start, not an
answer — push for which companies should not be there and why. Then rewrite the
qualification prompt, **show the before and after**, and re-run only once the
user agrees.

`sources` is the third lever, and the cheapest to reason about: if every bad
row came from one source, drop it from the array rather than writing a sentence
into the prompt to exclude it. If a run found almost nothing, widen the array
before you widen the keywords.

**Every change is a full re-run.** The pipeline cannot re-judge an earlier
run's rows against a new prompt, so even a prompt-only change scrapes again.
That is about an hour each time, so it is worth one more question up front
rather than three more runs.

### When it goes wrong

| What you see | What it means | What to say |
|---|---|---|
| `curl: (7) Failed to connect`, or a timeout on `/health` | The remote pipeline server is down or unreachable | Not yours to fix — tell the user the server at `169.58.58.243:3000` is not answering, and stop. Nothing was lost |
| `400 {"status":"error","errors":[...]}` | The request was rejected — a missing field, an empty `sources`, an unknown source name | Read the `errors` array, fix the request, re-fire. This one is yours, not the user's |
| `401` | The server now requires a token (`/config` → `"authRequired":true`) | Ask the user for it and send `Authorization: Bearer <token>`. Never print it |
| `404` from `/runs/<runId>/xlsx` | The run has not finished, or produced no rows | Check `/runs/<runId>`. Still running → keep polling. `completed` with nothing → a keyword or sources problem |
| `status: failed` | The run broke. `error` says why; *every requested source failed* is the common one | Read `/runs/<runId>/log?tail=50` and report the actual error. One failed source alone does not fail a run — that shows up in `warnings` |
| `status: failed`, *"interrupted by a server restart"* | The remote server restarted mid-run | Nothing is recoverable. Tell the user, and re-fire only on their go-ahead |
| `warnings` naming one source | That source failed; the run carried on | Say which source is missing, so the pass rate is read in that light |
| Most rows have an empty `Match` | LLM batches failed, so those rows were never judged | Report judged and unjudged counts separately. Grep the log for `classify request failed`. Not a prompt problem |
| Many rows have an empty `Company` | The model could not name the organisation from the headline and excerpt | Normal on thin or listicle-style articles. If it is most of the run, the keywords are pulling in roundups rather than stories about one organisation |
| Every judged row `false` | Prompt too strict | A prompt problem — offer a looser rewrite |

## Streams

A **stream** is a saved keyword set and qualification prompt that the pipeline
runs on a schedule, by itself, collecting the companies it finds into one place
that grows. The user never has to type the keywords again and never has to
trigger it.

    POST /schedules                     → scheduleId     the saved config + when to run
    GET  /schedules/<id>/companies      → the companies  what it has found
    GET  /schedules/<id>                → status         next run, totals, a line per tick

**Each tick only keeps companies the stream has not already collected.** Two
articles about the same organisation are one lead, whether they arrive in the
same tick or six weeks apart — so week two's run stores the handful of new
companies, not another copy of week one's. See
[Repeats are skipped, not collected](#repeats-are-skipped-not-collected).

**Every row carries the stream that found it**, so companies from several
streams can sit in one view and still be attributable.

### Two paths, and only two

Everything the user can ask for is one of these. There is no third option, and
nothing in between.

| | What it is | How |
|---|---|---|
| **A run** | Once. It happens, it produces a workbook, it is over | `POST /stream` — [Testing a stream](#testing-a-stream) |
| **A stream** | The same search repeating by itself on a slot they pick | `POST /schedules` — this section |

**A run is the default.** "Find me companies doing X", "run this", "test these
keywords" is a run. Do not raise scheduling, do not offer a stream, do not ask
about repeating. Fire it, show the results, stop.

**A stream only happens when the user asks for one.** "Run this every Monday",
"set it up so it collects by itself", "keep it going weekly" — that is a
stream, and nothing short of that is.

There is no way to save a keyword set without it running, and that is
deliberate: a saved-but-idle stream is just a run nobody fired yet. If the user
wants the config kept without it going off, they want a run now and a stream
later — say so rather than inventing a third thing.

### The two questions a stream needs

The moment the user asks to stream something, **both of these are asked and
answered before anything is created**. Not one, not assumed, not defaulted.

> Two things before I set it up:
>
> 1. **When should it run?** A day and a time — something like "every Monday
>    at 9am". Tell me the timezone if it isn't UK.
> 2. **How many times?** Give me a number — say 4, and it collects four runs
>    then stops — or say **no limit** and it keeps going until you stop it.

If they already gave one in their request ("stream this every Monday at 9am"),
you have that one — ask only for the other. Do not re-ask what they just said.

Those two are what a *stream* adds. It still needs the config a run needs —
keywords, qualification prompt and **sources** — so if the stream is being set
up from scratch rather than from a run the user just watched, collect those
first, offering the three sources as a choice
([Offer them as a choice](#offer-them-as-a-choice)). Carrying them over from a
run they just saw is fine; inventing them is not.

**1. When — the cadence.** A day *and* a time; a day alone is refused by the
server and is not an answer. **Never invent one and never fall back to a
default.** There is no default day and no default time. A stream fires on
whatever slot it is given, forever, so a slot you guessed is a recurring spend
the user never agreed to. Details in
[Pick a day and a time](#pick-a-day-and-a-time).

**2. How many — `maxRuns`.** A number, or no limit:

| They say | Send | What happens |
|---|---|---|
| "four runs", "a month of it" | `maxRuns: 4` | Collects four ticks, then parks itself at `finished` |
| "no limit", "keep it going", "until I stop it" | `maxRuns: 0` | Runs forever. **The user has to say this** |
| Nothing | — | Not an answer. Ask again |

`maxRuns: 0` is the default in the API, and that is exactly why it must be
asked for out loud: unlimited is the expensive answer, and nobody should arrive
at it by not answering a question. Give them the number as a real option — a
fixed count is a trial, and a trial is often what they meant.

Quote both answers back in the confirmation below, in the `Runs:` and
`Stop after:` lines, so they see what they agreed to.

### Creating one costs money on every tick

A stream runs until someone stops it, and every tick is a full LLM pass over
everything the keywords found.

**Never create a stream off the back of a test the user liked.** Liking the
data is not asking for it on repeat. Get the cadence as its own question, show
the whole thing back, and wait:

> Set this up as a stream?
>
>     Name:                 <name>
>     Description:          <one line on what it is looking for>
>     Keywords:             <the keywords>
>     Qualification Prompt: <the full prompt, not a summary>
>     Sources:              <the sources, exactly as spelled>
>     Runs:                 <the day and time THE USER GAVE>
>     Job titles:           <the titles, or "not set">
>     Stop after:           <maxRuns, or "until you stop it">
>
> Each run is a full pass: about an hour of pipeline time and a full LLM pass.

Every line there is filled from what the user actually said. **If the `Runs:`
line is one you chose rather than one you were given, stop and ask instead** —
that line is the one that spends money on a timer.

Show the **full qualification prompt** in that confirmation, never a
paraphrase. It is the one field whose wording decides what the stream costs and
what it returns, and a user agreeing to "the prompt we discussed" has not read
it.

`jobTitles` is stored on the stream so enrichment has a default to **offer**.
It is never a licence to spend without asking (rule 2).

### Pick a day and a time

**The user picks it. You never do.** The examples below are shapes to fill in,
not values to reuse — `monday` and `09:00` appear because something had to go
in the slot, and an agent that ships them because the user did not say has
scheduled a weekly spend out of thin air.

Two cadences, and the first is what people usually mean:

**By the clock** — `timeOfDay`, optionally `dayOfWeek`, optionally `timezone`:

```jsonc
{ "dayOfWeek": "<day>", "timeOfDay": "<HH:MM>", "timezone": "<IANA zone>" }
```

`dayOfWeek` takes a name (`monday`, `Mon`) or `0`–`6` where **0 is Sunday**.
Omit it for every day. `timeOfDay` takes `09:00`, `0900` or `9am`. `timezone`
is any IANA zone and defaults to `Europe/London`. A clock schedule holds its
local hour across daylight saving — 09:00 in June is still 09:00 in December.

**By elapsed time** — `intervalMinutes`, when the user genuinely wants "every
N hours" rather than a named slot. The floor is 5 minutes.

**A run takes about an hour and ticks never overlap**, so an interval under
about 90 minutes does not mean "more often" — it means **back to back
forever**. Say that rather than accepting the number.

| They want | Send | What it does |
|---|---|---|
| Weekly, on a day they named | `dayOfWeek` + `timeOfDay` | One run that day, that local hour |
| Daily at a time they named | `timeOfDay` alone | One run a day |
| Every few hours, a number they named | `intervalMinutes` | e.g. `360` is ~4 runs a day |
| "As often as possible" | Push back | Under ~90 minutes it runs continuously. Ask what they are trying to catch |
| **They did not say** | **Nothing — ask** | There is no default. A guessed slot is a recurring spend nobody agreed to |

If both a `timeOfDay` and an `intervalMinutes` are sent, **the clock wins** —
naming a time is the more specific instruction.

### Creating it

    curl -sS --max-time 30 -X POST http://169.58.58.243:3000/schedules \
      -H 'Content-Type: application/json' \
      --data-binary @"data/.runs/$RUN.stream.json" \
      | tee "data/.runs/$RUN.stream.response.json"

The body is the ordinary `/stream` body plus the stream's own fields:

```jsonc
{
  "name": "Village hall appeals",         // defaults to the first keywords
  "description": "Community groups running their own events",
  "keywords": "...",                      // one comma-separated string, as always
  "sources": ["Google News", "Justgiving", "LinkedIn"],
  "qualificationPrompt": "...",
  "dayOfWeek": "<day the user gave>",     // with timeOfDay: a clock schedule
  "timeOfDay": "<time the user gave>",    // never a value you picked
  "timezone": "<their zone>",
  "jobTitles": ["Owner", "Marketing Director"],
  "startImmediately": true,               // default true — one run now, then the slot
  "maxRuns": 0                            // default 0 = until stopped
}
```

Expect `201` with
`{"status":"scheduled","schedule":{"scheduleId":"sch-...","cadence":"every Monday at 09:00 (Europe/London)","nextRunAt":"..."}}`.
**Keep the `scheduleId`** and give it to the user with the `cadence` sentence —
read that sentence back rather than restating what you sent, because it is the
server telling you what it understood.

`maxRuns` is not optional to ask — see
[The two questions a stream needs](#the-two-questions-a-stream-needs). `0` runs
until stopped and `4` collects four ticks then parks at `finished`; both are
only ever sent because the user said so.

`startImmediately: true` on a weekly stream means one run now **and** its
named slot from then on. If the user only wants it from that slot, send
`false`. Ask which they want rather than assuming — the default fires a
full run the moment you create it.

### Reading a stream back

**This is how you get a stream's data. Not the workbook.** The workbook is a
binary file for a person to open; these return JSON, leave `content` out, and
let you ask for exactly the slice you want.

#### The companies

    curl -sS "http://169.58.58.243:3000/schedules/<id>/companies"

One entry per organisation, best first, qualified only by default:

```jsonc
{
  "scheduleId": "sch-...", "streamName": "Village hall appeals", "total": 37,
  "companies": [{
    "company": "Oakfield Community Trust",
    "key": "oakfield community trust",   // normalised; what dedup matched on
    "streamName": "Village hall appeals",
    "scheduleId": "sch-...",
    "firstSeen": "2026-10-06T09:04:11Z", "lastSeen": "2026-10-13T09:07:52Z",
    "mentions": 3,            // rows naming it
    "matched": 2,             // of those, ones that qualified
    "confidence": 90,         // best across its matched rows
    "sources": ["google_news"], "domains": ["oxfordmail.co.uk"],
    "best": { "title": "...", "link": "...", "reason": "...", "confidence": "90", "match": "true" }
  }]
}
```

`?match=all` to include the rejected ones, `?limit=` to cap (default 200).

#### The articles behind them

    curl -sS "http://169.58.58.243:3000/schedules/<id>/leads?match=true&limit=50"

| Filter | Does |
|---|---|
| `?match=true` / `false` / `unjudged` / `all` | Qualified, rejected, never-judged, everything |
| `?since=2026-10-06` / `?until=` | By when the row was collected |
| `?runId=<id>` | Exactly what one tick added |
| `?company=Oakfield Trust` | One organisation. Ignores case, "The" and `Ltd` |
| `?q=flood` | Substring over company, title and domain |
| `?limit=` `?offset=` | Paging. Default 100, capped at 1000 |
| `?fields=company,title,link` | Only these columns |
| `?includeContent=true` | Add the article text back |

**`content` is omitted unless you ask for it, and you should almost never ask.**
It is thousands of characters a row; pulling 200 rows with it is hundreds of
kilobytes into your context for nothing. Ask for it per row when you need to
re-read one article — which is exactly what the screening step in
[Enrichment](#3-screen-for-news-publications-and-dodgy-rows) does.

#### Across every stream

    curl -sS "http://169.58.58.243:3000/companies?since=2026-10-06"

Same shapes, every stream pooled, each entry carrying `streamName` and
`scheduleId`. `?scheduleId=` narrows it back to one. A company two streams
both found appears once, labelled with the stream that saw it first — say that
when it matters, rather than implying only one stream found it.

#### The stream's own state

`GET /schedules/<id>` answers without the log:

- `status` — `active`, `paused` or `finished`; `cadence` — the sentence.
- `running` and `lastRunId` — a tick in flight, and the runId to poll at
  `/runs/<runId>` exactly as in [step 2](#2-watch-the-run).
- `nextRunAt` — when the next one fires. Absent while one is running.
- `totals.rows` — rows collected. `totals.duplicates` — repeats skipped.
- `runs[]` — newest first, one entry per tick: `rows`, `appended`,
  `duplicates`, `matched`, `error`.

### Repeats are skipped, not collected

A row is kept only if the stream has none of its three identities already: the
**company**, the canonical **URL**, and the **headline**.

Three consequences worth saying out loud:

**`appended` falls off a cliff after the first tick, and that is correct.**
Tick one appends everything; tick two appends the handful published since. A
second tick appending `0` of `200` rows is the dedup working, not a broken
run. Report it that way — a user told "the run found nothing" will reasonably
conclude the stream is dead.

**Two articles about one company are one lead**, even in the same tick. So
`totals.rows` is smaller than the number of articles judged, and should be.

**A rejected company is not blacklisted.** A company judged `false` in week one
can still arrive as a real lead in week six on a different article. Only
qualifying rows claim their company name.

A row the model could not name a company on is still kept, deduplicated by URL
and headline alone. If a stream's companies look thin against its row count,
that is why — check `?match=all` before concluding the keywords are wrong.

### The workbook

    curl -sS -f -o "data/<streamName>.xlsx" \
      "http://169.58.58.243:3000/schedules/<id>/xlsx"

For the user, not for you — three sheets:

- **`Leads`** — every row collected, the same columns a test workbook has plus
  **`Stream`**, **`Stream id`**, **`Run id`** and **`Collected`**.
- **`Schedule`** — the config, the cadence, the next run, the totals.
- **`Runs`** — one line per tick: rows, appended, repeats, matched, error.

Hand over the path. Reach for the JSON routes yourself.

### Changing one

`PATCH /schedules/<id>` with **only the fields that changed** — `keywords`,
`qualificationPrompt`, `sources`, `name`, `description`, `jobTitles`,
`dayOfWeek`/`timeOfDay`/`timezone`, `intervalMinutes`, `maxRuns`.

Show before and after, per field, then ask:

> `Village hall appeals` — Keywords
>
>     was: village hall appeal, community fundraiser
>     now: village hall appeal, community fundraiser, parish hall restoration
>
> Apply this?

Send only what changed. A write that re-sends unchanged fields looks harmless
and is not: it overwrites anything edited between your read and your write.

An edit does not touch the switch — a paused stream stays paused, an active one
stays active and its next tick uses the new config. Say so, because it means
the change takes effect without anyone starting anything.

**Rows already collected were judged against the old prompt.** The pipeline
cannot re-judge them, so after a prompt change the stream holds two populations
under one `Match` column. Tell the user, and use `?since=` or `?runId=` to
separate them.

### Stopping one

| The user says | Call |
|---|---|
| pause it · stop it · turn it off | `POST /schedules/<id>/pause` |
| start it again · resume it | `POST /schedules/<id>/resume` |
| run it now | `POST /schedules/<id>/run` |
| get rid of it | `DELETE /schedules/<id>` — confirm first |

**Pause does not cancel the run in flight, and that is deliberate.** Rows exist
only once classify has finished (rule 5), so killing a run 50 minutes in throws
away everything it judged. Pause stops the *next* tick and lets the current one
land its rows. `?cancelRunning=true` kills it too — only on the user's explicit
say-so, having told them what it costs.

`DELETE` removes the stream and **keeps everything it collected**; weeks of
companies are not something to lose as a side effect of switching something
off. `?purge=true` deletes them as well, and is never sent without the user
asking for exactly that.

**Confirm pause and delete by name, not by "that one".** Read `GET /schedules`
first and match on `name`; if two are close, ask which. Never act on a
`scheduleId` you have not read back.

### When it goes wrong

| What you see | What it means | What to say |
|---|---|---|
| `400` naming `cadence is required` | Neither a `timeOfDay` nor an `intervalMinutes` was sent | Ask what day and time they want. Do not pick one |
| `400` naming `timeOfDay` | A day was sent with no time, or the time did not parse | A day alone does not say when to run. Ask for the time |
| `400` naming `IANA` | The timezone is not a real zone | `Europe/London`, `America/New_York`. Ask rather than guess |
| `409` *"at most N schedules"* | The server's stream limit is full | List them, show what is already running, ask which to pause |
| `409` on `resume` | It used up its `maxRuns` | Raise `maxRuns` with `PATCH`, on the user's yes |
| `503` *"scheduling is disabled"* | `SCHEDULES_ENABLED=false` on that deployment | Not yours to change. Say so, and offer one-off runs instead |
| `404` from `/schedules/<id>/xlsx`, but `/companies` answers `total: 0` | No rows collected yet; the first tick is probably still running | Check `GET /schedules/<id>`; `running: true` means keep waiting |
| Every tick after the first appends `0` | The dedup working, or genuinely nothing new | Compare `duplicates` with `rows`. Equal means repeats, which is healthy. `rows: 0` means the sources found nothing — a keyword problem |
| `status: finished` unexpectedly | It hit its `maxRuns` | Say so; it did not fail. Offer to raise `maxRuns` and resume |
| `lastError` set, but `status` still `active` | A tick failed; the stream carried on | Read `/runs/<lastRunId>/log?tail=50`. A stream is not stopped by one bad tick, and should not be |
| `nextRunAt` is in the past | The server restarted and that slot was missed | A missed slot is **not** run late; the stream waits for its next one. Check `/health`, then re-read the stream |

## Enrichment

Turning companies into named contacts with emails. Via the `ai-ark` MCP
server, reading its input from the pipeline. **This is where the real money
goes**, which is why the gates below are not optional.

Enrichment **never writes back** — not to AI Ark, not to the stream. The
deliverable is a CSV.

On Codex, `ai-ark` is project-scoped through the pinned `mcp-remote` STDIO
bridge because AI Ark's remote endpoint does not return the event stream
Codex's direct HTTP client requires. If the AI Ark tools are missing, run
`./setup.sh`, restart Codex, and see
[docs/codex-ai-ark-setup.md](../../../docs/codex-ai-ark-setup.md). Do not fall
back to direct `url = ...` configuration while AI Ark still returns plain
JSON; that path fails with `Transport channel closed`.

### 1. Pick the stream and the companies

Ask which stream, and which companies. "The new ones" is a valid answer; ask
them which ones those are.

Read `GET /schedules` first and show what exists — name, cadence, status, how
many companies each has, when it last ran. That one read tells you what the
streams are, which are live, and what each has collected.

A stream with `runCount: 0` has never run and has nothing to enrich. Say that
plainly rather than reporting "no companies found" as if something broke.

**"The new ones" has an exact answer.** `?since=<the last enrichment date>` or
`?runId=<the last tick>` — do not eyeball it, and do not re-enrich companies
the user has already paid for.

### 2. Read the companies

    curl -sS "http://169.58.58.243:3000/schedules/<id>/companies?since=2026-10-06"

Qualified only, by default — the stream already judged them, so every company
that comes back is a pass. Do not report a pass rate from this; that lives on
`GET /schedules/<id>` as `totals`.

The fields that matter here: `company` is the name to search AI Ark with,
`best.reason` is why it qualified, `best.link` is the article, `confidence` is
0–100, and `mentions` is how many articles named it.

**`confidence` is stored 0–100.** If a stream's own qualification prompt still
asks for "a confidence score from 0 to 1", that instruction is stale and worth
correcting — offer the `PATCH`, show the before and after, and wait for a yes.
Do not slip it into an unrelated write.

To re-read one company's article text — which step 3 needs — fetch that one
row rather than the whole stream:

    curl -sS "http://169.58.58.243:3000/schedules/<id>/leads?company=Business%20News&includeContent=true&limit=3"

### 3. Screen for news publications and dodgy rows

The sources are news sites, so **news publications sweep into the results**.
They are the most common wrong row in any batch, and enriching one spends money
chasing contacts at a company that was never a lead.

Before anything is spent, sort into three buckets, then show the user.

**Clean** — an ordinary company. These enrich on the user's go-ahead like any
other row, with no extra question.

**News publication** — the `company` is a newspaper, magazine, trade title,
broadcaster, wire service or business-news outlet. Never enrich one on the
strength of the entry alone. Re-read that company's article content against the
stream's qualification prompt and work out whether the article genuinely
qualifies **the publication itself**.

**Dodgy** — the article does describe something qualifying, but what it
describes belongs to a *different* company mentioned inside it. Also treat as
dodgy any `company` that is not really a company: a team, a facility, a
department, a job function.

About nine in ten news publications are not leads. That is a base rate, not a
reason to skip the reading — the tenth is real. A publication whose own staff
rode in the event qualifies exactly as well as any other employer.

**Every flagged company needs its own confirmation, and that is a separate
question from the spend confirmation in step 5.** Never fold the two together
and never decide on the user's behalf. Give the full context — the name, why it
was flagged, what the article actually says, and which company the evidence
really points at — then ask, one at a time:

> `Business News` is a news publication. Its article describes its own CEO
> riding in the corporate cycling challenge it runs, so it may genuinely
> qualify on its own account. Enrich it, or skip it?

> `Doximity` is dodgy. It appears only as a tag in an article about staff at
> other healthcare organisations riding — the evidence points at them, not at
> Doximity. Enrich it, or skip it?

Wait for an answer on each one. "Enrich everything that isn't a news
publication" answers for the clean bucket only. A blanket approval given before
the flags were shown is not consent to spend on them.

Report the buckets before you ask:

    29 companies
    24 clean
    4 news publications (Business News ×4)
    1 dodgy (Doximity — appears only as a tag)

**The company extraction is good, not perfect.** It is a model reading a
headline and an excerpt, so it can name a sponsor instead of an organiser, or a
venue instead of the group that booked it. This screening step is what catches
that, and it is why the step did not go away when the extraction arrived.

### 4. Ask for the job titles

**Every run. Before anything is spent. No exceptions.**

The stream carries `jobTitles` — for example `Owner, Dealer Principal, General
Manager, Marketing Director, VP of Marketing, Director of Operations`.
**Offer it; never assume it.**

> This stream is configured for: Owner, Dealer Principal, General Manager,
> Marketing Director, VP of Marketing, Director of Operations.
> Use those, or different ones?

Wait for an answer. A configured default is a suggestion, not consent — it was
set once, possibly by someone else, possibly for a different campaign. This
question is the one thing standing between the user and money they did not mean
to spend.

Never carry titles over silently from an earlier run in the same conversation,
and never infer them from the companies.

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
`company_search` both require exact enum values for `industry`, `location` and
`technology` — resolve them first with `industry_search` / `location_search` /
`technology_search` and filter on the returned tokens. A free-text guess in
those fields does not error; it silently matches nobody. The path above
(company name + job title) never needs this.

A company where `people_search` returns nobody is not a failure. Move on and
record why.

**The record shape, verified live on 2026-08-11.** A `people_search` hit is
deeply nested — none of the CSV fields sit at the top level:

| CSV column | Path on a `people_search` record |
|---|---|
| `person_name` | `profile.full_name` (also `profile.first_name` / `last_name`) |
| `job_title` | `profile.title`, falling back to `profile.headline` |
| `linkedin_url` | `link.linkedin` |
| `email` | **not present** — see below |
| `company` | the `company` from the stream entry you started with |

Top-level keys on a hit: `id`, `identifier`, `profile`, `link`, `location`,
`languages`, `industry`, `position_groups`, `skills`, `member_badges`,
`statistics`, `company`, `department`, `last_updated`. Some records also carry
`educations`, `awards`, `volunteer_experiences` — treat every one as optional
and never assume a key exists.

**`people_search` returns no email whatsoever.** Not at the top level, not under
`profile`, not under `link`. This is why the second call exists: the email comes
only from `export_single`. If you find yourself reporting emails after a search
alone, you have invented them.

Watch the two similar link fields: `link.linkedin` is the *person's* profile,
while `company.link.linkedin` and `position_groups[].company.url` are the
*company's*. Writing a company URL into `linkedin_url` is a silent, plausible
wrong answer.

### 7. Write the CSV

`data/<stream-slug>-YYYY-MM-DD.csv`, unless the user has said they want
something else — in which case theirs wins and you do not argue.

Columns: `company`, `person_name`, `job_title`, `email`, `linkedin_url`,
`stream`, `enriched_at`. One row per person. Companies that returned nobody
appear in the report, not as blank rows.

### 8. Report honestly

    38 companies in
    91 people out
    64 with an email (70%)
    88 with a LinkedIn (97%)
    6 companies returned nobody
    5 skipped as news publications or dodgy (not enriched, not charged)

Companies skipped at step 3 belong in the report. One that was screened out
must never be indistinguishable from one that was searched and found nobody.

If coverage is poor, say so and say why. Do not round it up and do not present
a thin result as a good one.

## Rules that must not need a lookup

**1. Never print a secret.** Not a key, not a token. They live in `.env`. To
check one, print whether it is set and how long it is — never its value.

**2. Job titles are asked for every single time.** It is the one question that
stands between the user and money they did not mean to spend. A stream's
`jobTitles` is a default to offer, never a default to use.

**2b. News publications and dodgy companies are never enriched without their
own explicit yes.** The sources are news sites, so publications sweep in; about
nine in ten are not leads. Flag each one, re-read its article against the
qualification prompt, hand the user the full context, and ask per company. A
blanket "enrich the rest" covers the clean ones only.

**3. Creating a stream, and changing one, is confirmed first.** A stream runs
until someone stops it and spends on every tick, so it is never created off the
back of a liked test, a yes to the conversation, or a standing instruction from
earlier in the session. Show the full qualification prompt, and wait. On a
`PATCH`, send only the fields that changed and show before and after.

**3b. A stream needs two answers from the user, and has no defaults for
either.** **When it repeats** — a day and a time they gave — and **how many
times**, a number or an explicit "no limit". Ask for both before creating
anything; if they supplied one in their request, ask for the other. The
`monday` and `09:00` in this document are placeholders, and `maxRuns: 0` being
the API default is not the user choosing unlimited. Shipping either because
nobody answered schedules a recurring spend nobody agreed to.

**3c. There are two paths and no third.** A **run** happens once; a **stream**
repeats on a slot. A run is the default, and scheduling is never raised unless
the user asks for it. There is no "save it without running it".

**4. Deleting is confirmed, and purging is asked for by name.** `DELETE` keeps
everything the stream collected; `?purge=true` destroys it and there is no undo.
Never send `purge` because a delete was approved — they are two decisions.

**5. Cancelling a run throws its results away.** Rows are written only after
classify finishes, so `POST /runs/<runId>/cancel` — and
`pause?cancelRunning=true` — leave nothing behind. Cancel only on the user's
say-so, having told them that, and only a run you started.

**6. The pipeline is the only store.** Streams, companies, history and
workbooks all live there; `GET /schedules/<id>/companies` is where a stream's
data comes from. Enrichment reads from it and writes a CSV. Nothing in this
skill writes to any other system.
