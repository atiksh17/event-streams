# Production mode, in depth

This is the long-form companion to the `## Production mode` section of the
skill. Read the skill for the exact steps; read this when you're screening a
batch for news publications, choosing job titles, deciding whether a coverage
report is healthy, or wondering why the skill hands you a CSV instead of
writing straight back into the table you just read.

Production mode is not exploratory the way test mode is. Every call to AI Ark
costs money, and there's no "just try it and see" — the job-title question
exists precisely so that the only expensive step happens once you've actually
decided what you want.

## News publications, and why they need their own gate

The streams read Google News and LinkedIn. That means the pipeline is looking
at articles and posts, and the thing that writes an article is a news
publication — so publications end up on the list as though they were leads.
This is structural, not a bug in the qualification prompt. No amount of prompt
tightening removes it entirely, because the publication genuinely is named in
the content, often repeatedly.

**About nine out of ten are not leads**, and enriching one buys contact
details for a newsroom that has no interest in what you're selling. The point
of the check isn't to delete them, though — it's the tenth one. A trade title
whose own staff rode in a charity event is a company whose staff rode in a
charity event, and a business-news outlet that organises a corporate cycling
challenge is a perfectly good target. Deleting all publications on sight
throws that away.

### The three buckets

**Clean.** An ordinary company. No extra question — these go ahead on the
normal spend confirmation like anything else.

**News publication.** The name is a newspaper, magazine, trade title,
broadcaster, wire service, or business-news outlet. Go back to that row's
`Scraped Content` and read it against the stream's `Qualification Prompt`.
The question is narrow: does the article qualify *the publication itself*?
A newsroom whose own employees took part qualifies. A newsroom that merely
reported on someone else's employees does not.

**Dodgy.** The article describes something that genuinely qualifies — but it
belongs to a different company mentioned inside the piece. The publication is
on the row because it did the writing, not the riding. This bucket also
catches names that aren't companies at all: a team, a facility, a department,
a job function. A row reading `Clevedon manufacturing facility` or
`NHS Trust (Pharmacy team)` can't be searched as a company name even when the
underlying story is real.

### Why each flagged row gets its own question

The spend confirmation covers scale — *38 companies × 3 titles, go?* It does
not cover judgement about which companies belong on the list at all. Those are
different decisions and folding them together loses the second one: a user who
says yes to a total has not looked at the individual rows behind it.

So give the full context per row and let the user decide each one. Name the
company, say why it was flagged, say what the article actually describes, and
say which company the evidence really points at. That last part matters most
for the dodgy bucket — "this article is about staff at three other hospitals,
and this company is just a tag in it" is the fact that lets someone decide in
two seconds.

A blanket instruction like *"enrich everything that isn't a news
publication"* is a complete answer for the clean bucket and no answer at all
for the flagged ones. Treat approval given before the flags were shown as
approval of what was shown — which was nothing.

### What this looks like in practice

From a real batch of 29 rows in the demo stream, read live 2026-08-11:

    29 rows
    24 clean
    4 news publications (Business News ×4)
    1 dodgy (Doximity — appears only as a tag in an article about
             other healthcare organisations' staff riding)

`Business News` is the instructive one. It's a Western Australian business
publication, so it lands in the publication bucket on sight — but reading the
articles shows its own CEO riding in a corporate cycling challenge that the
publication itself organises. That is a genuine qualifying signal about the
publication, not about someone else. It's the one-in-ten case, and it would
have been thrown away by a rule that just drops publications.

Note also that it appeared four separate times, once per article. Deduplicate
by company before you count, or you'll ask the same question four times and
pay four times if the user says yes.

## Choosing job titles that actually return people

The single biggest lever on how many people you get back is how you phrase
the titles — and the mistake runs in both directions.

### Weak example

> Corporate Wellness & Community Engagement Manager

This looks precise, and precision feels safe. But real job titles are set by
each company's own HR department, not by a shared standard, and almost no
company uses this exact string. AI Ark is matching against what's actually
printed on someone's LinkedIn profile — if the person who does this job at a
given company is titled "HR Manager" or "People Director" instead, a search
for this exact phrase returns nobody at that company, even though the right
person exists and is fully reachable. You'd read "6 companies returned
nobody" and conclude the data is thin, when really the title was too narrow
to find people who are there.

### Strong rewrite of the same intent

> HR Manager, People Director, Head of People, CSR Manager

Same target role, but named as a short list of the real synonyms companies
actually use for it. One company calls it HR Manager, another calls the same
job People Director, a third calls it CSR Manager because the role sits under
sustainability instead of HR. Asking for all four in one run means each
company's row gets checked against whichever term *that* company happens to
use, instead of betting the whole run on one company's specific phrasing.

### The general pattern

1. **Start from the function, not a job description.** You're not looking for
   someone whose day-to-day matches a paragraph — you're looking for someone
   whose LinkedIn title contains a recognizable string. Think in terms of
   what that string is likely to say.
2. **List synonyms, not one ideal title.** Three or four real-world variants
   of the same seniority and function beat one perfectly-worded title that
   only matches a fraction of companies.
3. **Match seniority to the company's size, if you know it.** "Head of
   People" is a real title at a 40-person company and a nonexistent one at a
   4,000-person company, where the equivalent might be "VP, People" or
   "Director of HR". If the batch spans very different company sizes,
   widening the title list is often more effective than picking one "right"
   level.

If a title list keeps returning empty at company after company, the title is
almost always the first thing to loosen — before concluding the companies
themselves don't have the right person.

## Reading the coverage report

Every run ends with a report shaped like this:

    38 companies in
    91 people out
    64 with an email (70%)
    88 with a LinkedIn (97%)
    6 companies returned nobody

Each line answers a different question, and they don't move together:

- **Companies in / people out** is about title breadth. A low people-per-company
  ratio (91 people across 38 companies is under 2.5 per company for what was
  likely 3+ titles asked for) usually means the title list didn't match well —
  see the section above.
- **LinkedIn %** should be close to 100. `people_search` finds people *via*
  their LinkedIn presence, so a low LinkedIn percentage is unusual and worth
  a second look — it can mean the search matched something thin (a stale
  profile, a name collision) rather than a confident hit.
- **Email %** is normally lower than LinkedIn %, and that's expected, not a
  fault. `export_single` does a real-time lookup per person, and not every
  professional has a discoverable email even when their identity and role
  are confirmed. 70% is a reasonable outcome; treat anything dramatically
  lower as worth flagging to the user rather than silently accepting.
- **Companies returned nobody** is the count to explain, not just report. Six
  out of 38 (16%) is plausible for a real batch; if it's a third or more,
  say so plainly before the user reads the CSV and wonders where the rest
  of their companies went.

Report all five lines every time, even when the numbers are good. Don't round
64/91 up to "most people have an email" — say 70% and let the user judge it.

## When a company returns nobody

This happens, and it is reported, not buried. Before treating it as a data
gap, check the two things actually within your control:

1. **Is the company name matching what AI Ark knows the company as?** A row
   that says "GoAuto" in the source table might be registered elsewhere as
   "GoAuto Family of Dealerships" or under its parent company's name. If you
   suspect this, `company_search` (a separate AI Ark tool) can confirm how a
   company is actually indexed before you conclude nobody exists there.
2. **Are the job titles too narrow for this specific company?** A five-person
   company almost certainly doesn't have anyone titled "Head of People" — but
   might have someone doing that job under the title "Office Manager." A
   company returning nobody while others in the same batch return several
   people is a title-fit problem more often than a true absence of the role.

What NOT to do: don't quietly re-run a company with different titles without
telling the user. If the fix seems clear, say what you'd try and why, and
treat trying it as a new enrichment decision — small as it is, it's still
spend the user should sign off on, the same way the original batch was.

If a company genuinely doesn't have anyone matching after a reasonable
attempt, that's a legitimate outcome. It goes in the report as one of the
"returned nobody" companies with a one-line reason (name mismatch suspected,
titles didn't match anyone at this size, etc.) — never as a blank row sitting
silently in the CSV, which would make it indistinguishable from a lookup that
just wasn't attempted.

## How the enrichment actually works, and why it's per-person

For each company, the skill does two things in sequence: `people_search` to
find the people at that company matching the confirmed titles, then
`export_single` once per person found, to get their email and confirm their
LinkedIn URL.

This is a deliberate choice, not the only way AI Ark could be used. AI Ark
also offers `email_finder`, which works on a whole company-and-titles filter
at once and hands back a `trackId` you poll for results later — fewer calls,
one poll loop instead of many lookups. For a handful of companies, though,
per-person calls are the safer default: each `export_single` call is
synchronous and self-contained, so one company having no matches, or one
person's lookup coming back empty, never threatens the rest of the batch and
never needs a retry-the-poll-loop step. The report's promise — that one bad
company doesn't take down the batch — is easiest to keep when every lookup is
already isolated by construction.

If a batch grows into the hundreds of companies, the per-call overhead of
`export_single` run one at a time becomes the bottleneck, and `email_finder`'s
batch-and-poll shape is worth revisiting. That's a future tuning decision, not
today's — the procedure in the skill is per-person.

One more thing worth knowing even though it rarely comes up on the main path:
if a run ever needs to filter by industry or geography as well as company and
title, AI Ark requires those values to be resolved to exact tokens first
(via separate lookup tools), or the filter silently matches nothing instead
of erroring. Company name and job title, the two filters this skill actually
uses, don't have that requirement — they're matched as free text.

## Why the CSV is the deliverable, not a write back to NocoDB

The skill can write to the base — but only to the `Streams` table, only in
six config columns, and only on a confirmed yes (see `## Writing to Streams`
in the skill). Enrichment output is not one of those things. It goes to a CSV
and never back into the table it was read from, for reasons that are about
ownership as much as risk:

- **A stream's data table belongs to the automated system, not to a one-off
  enrichment run.** The daily stream writes to it on its own schedule with
  its own schema. A skill-driven write risks colliding with that — wrong
  column, wrong row, or simply data the automated system didn't expect to see
  change — for a system that isn't watching for external edits. `Streams` is
  the exception precisely because its config columns are *meant* to be edited
  by a human, and the skill only ever edits them as that human's hands.
- **The NocoDB token this skill uses is not read-only — the endpoint exposes
  `createRecords`, `updateRecords`, and `deleteRecords`, and we verified live
  on 2026-08-10 that all three work with the connected token.** There is no
  credential-level safety margin here. Which tables can be written, which
  columns, and with what confirmation is decided entirely by the skill's own
  rules (see `.claude/skills/event-streams/SKILL.md`). If enrichment logic
  has a bug, the worst case being "a wrong CSV, which you notice and re-run"
  depends on enrichment never reaching for those tools at all — a bad write
  to a live production base doesn't have that same easy undo, and
  `deleteRecords` has none.
- **A CSV is something the user can actually look at before it goes
  anywhere else.** Whatever happens after enrichment — importing into a CRM,
  handing to a sales tool, spot-checking against LinkedIn — that step is a
  deliberate human decision made by reading a file, not an automatic
  consequence of the skill having run. The output being a file rather than a
  live write is what keeps that decision in the user's hands.

If a task ever seems to call for writing the enrichment results back into the
base, that's a sign the task has been misunderstood, not a sign the rule needs
bending. Stop and ask. Writing a *stream's config* is a different thing
entirely and has its own procedure.

## Starting and stopping streams

"Start this stream" and "stop this stream" both mean one field on one row:
`Enabled` true or false in the `Streams` table. There is no other switch, and
nothing else about the row changes.

Two things are worth holding onto when you do it.

**Starting a stream is a spend decision, not a settings change.** An enabled
stream runs every day until someone turns it off, and each run costs
whatever its keywords and sources cost. That is why the confirmation names
the stream and says what enabling means, rather than reading as a shrug —
"Start `Dealership Group Expansions`? It will run every day from then on."

**A new stream is never born enabled.** It is created with `Enabled` false
even when the user has just said they want it running, and starting it is a
second question asked after the row exists. This looks pedantic for about one
second, and it is the reason a mis-transcribed keyword or a prompt that
turned out too broad costs nothing: the row sits there, inert, until someone
has looked at what was actually written. Creating and starting in one motion
removes the only checkpoint between a typo and a daily bill.

The lag afterwards is normal. The automated system creates the stream's data
table and fills in `Table ID` on its own schedule, so a freshly started
stream has an empty `Table ID` and no table for a while. Say that plainly
rather than treating it as a failed start.
