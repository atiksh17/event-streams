# Test mode, in depth

This is the long-form companion to the `## Test mode` section of the skill.
Read the skill for the exact steps; read this when a run comes back and you're
not sure whether the result is good, or when you need help writing a
qualification prompt that actually works.

Test mode answers one question: **if we ran this stream for real, would it
find the right companies?** It costs nothing but time — 5 to 15 minutes per
run — but that time adds up if you re-run on guesses instead of on reasoned
changes. This doc is mostly about avoiding wasted runs.

## What "keywords" and "qualification prompt" actually do

The discovery endpoint doesn't do one job — it does two, in sequence, and
they fail in different ways.

1. **Keywords** cast a wide net across sources (news, fundraising pages,
   press releases) and pull back anything that mentions them. This step is
   dumb on purpose — it over-collects.
2. **The qualification prompt** is handed to a model, one candidate company
   at a time, and asked to judge: does this company actually belong on the
   list? This step is where discrimination happens.

If your results are wrong, the fix is almost always in one of these two
places, and the symptom tells you which one:

- Too few results, or an empty array → keyword problem. The net wasn't wide
  enough, or the terms don't match how sources actually phrase things.
- Plenty of results but the wrong companies, or a flood of `relevant: false`
  → qualification prompt problem. The net was fine; the judgment was loose
  or wrong.

Fix the one that's broken. A vague prompt does not get better by adding more
keywords, and a bad keyword list does not get better by tightening the
prompt.

## Writing a qualification prompt that discriminates

The single biggest mistake is writing a prompt that describes the *topic*
instead of the *test*. A topic invites the model to agree with almost
anything that's in the neighborhood. A test gives it a specific bar to clear
and specific reasons to say no.

### Weak example

> The company does cycling events.

This looks reasonable and will pass almost everything the keyword step
hands it: bike shops, cycling clubs, race organisers, tourism boards
promoting a regional sportive, a city council announcing road closures for a
charity ride, a gear retailer running a blog post about "top 10 cycling
events this year." None of these are what you're actually after — companies
whose *own staff* took part — but the prompt never said staff had to be
involved, so the model has no reason to reject them.

### Strong rewrite of the same intent

> The company is NOT a cycling business itself — rule out bike shops,
> cycling clubs, race organisers, and tourism/travel content about cycling
> destinations.
>
> Mark relevant only if employees of the company personally took part in an
> organised cycling event (e.g. a sponsored ride, a charity cyclosportive, a
> corporate challenge event) within roughly the last 12 months, and this is
> evidenced by one of: a JustGiving/fundraising page naming the company and
> its staff, a company blog or LinkedIn post describing employee
> participation, or a local news article naming the company and describing
> staff riding.
>
> Do NOT mark relevant if the company only sponsored the event financially
> without employees riding, or if the company is merely mentioned as a
> nearby business, a route landmark, or an event sponsor logo.

Notice what changed: the rewrite names the exclusion category explicitly
(cycling businesses), names the exact evidence that counts (a fundraising
page, a post, an article — all things a source can actually produce), and
names the near-miss that keeps sneaking through (sponsorship without
participation). Every one of those three additions came from looking at
specific wrong rows in a real run, not from imagining edge cases in
advance — which is why you iterate against results, not against a blank
page.

### The general pattern

A prompt that discriminates well usually has three parts:

1. **What counts** — the specific, observable thing you're looking for
   (staff participation, not company sponsorship; a named event, not a
   generic mention).
2. **What doesn't, even though it looks similar** — the near-miss category
   that keyword matching keeps surfacing. You often don't know this until
   you've seen a real run's false positives.
3. **What evidence is acceptable** — tell the model which source types
   should be enough to say yes, so it isn't guessing at your evidentiary
   bar either.

If your qualification prompt has none of part 2, expect a high pass rate
that's wrong rather than right.

## What a healthy pass rate looks like

There's no universal number — it depends on how common the thing you're
looking for actually is — but a few reference points help:

- **A pass rate near 100%** almost always means the prompt isn't
  discriminating. If literally everything the keywords bring back is
  "relevant," the qualification step did no work; it just rubber-stamped
  the keyword net. Go find the loosest few passes and ask whether they'd
  really belong on a real prospect list.
- **A pass rate in the teens to thirties** is typical for a decently tight
  prompt run against a broad keyword sweep. Most things a keyword net drags
  in are noise; that's expected, not a bug in the stream.
- **A pass rate near 0%**, or an empty array, can be correct — some
  qualification bars are genuinely rare in the data — but check the
  keyword step first. If the keywords only returned three candidates total,
  a 0% pass rate tells you nothing about the prompt; it tells you the net
  was too narrow to test the prompt at all.

The instinct to treat a low pass rate as something broken is usually wrong.
A stream that returns 14 qualified companies out of 61 candidates did its
job — it looked at 61 things and correctly said no to 47 of them. That's the
point of running qualification at all. Don't loosen a prompt just to make
the number go up; loosen it only when you've read specific false negatives
and agree they should have passed.

## Reading the `confidence` field

`confidence` is an integer 0–100 the model attaches to its own `relevant`
judgment on that specific row. It is not a probability that the company is
real, and it is not a lead-quality score — it's how sure the model was about
its yes/no call, given the evidence it saw.

How to use it:

- **High confidence (80+), either direction** — trust it and move on. These
  rows are rarely where prompt problems live.
- **Low-to-mid confidence (below ~50)** — this is the interesting band.
  These are the rows where the evidence was thin, ambiguous, or the prompt's
  wording left room for judgment calls. When you're deciding what to fix in
  the prompt, read the `reason` on these rows first — they usually show you
  exactly which distinction the prompt failed to make clearly.
- **A `relevant: true` row with low confidence** is often a near-miss that
  slipped through — a good candidate for tightening.
- **A `relevant: false` row with low confidence** is often a real candidate
  the prompt talked itself out of — a good candidate for loosening, but only
  after confirming the `reason` shows a wording problem rather than a
  correct rejection.

If most rows cluster at very high or very low confidence with almost none
in between, the prompt is drawing a clean line — good. A pile of rows in the
40–60 range across many companies suggests the wording itself is
ambiguous, not just that individual cases are hard.

## Why it pays to think before you re-run

Every run costs 5 to 15 minutes, and that time is spent whether the change
you made was right or not. Three guessed changes cost 15–45 minutes; one
considered change costs 5–15. The gap compounds fast.

Before re-running, do this instead of guessing:

1. Read every `reason` for the rows you disagree with — not just the
   company names, the actual stated reasoning.
2. Sort those into two buckets: false positives (should not have passed)
   and false negatives (should have passed but didn't, if you know of any
   that were missed entirely).
3. For each bucket, write down the *specific distinguishing fact* that
   separates it from a correct result — not "too broad," but "these are
   cycling retailers, not companies whose staff rode."
4. Turn each distinguishing fact into one added sentence in the prompt, not
   a rewrite of the whole thing. Show the user the before/after diff of just
   that change.
5. Only then re-run.

This is also why the skill pushes back on "too broad" as a complete answer —
it's a symptom, not a diagnosis. "Too broad because X keeps showing up" is
a diagnosis, and it's the only kind of input that reliably improves a prompt
on the next try instead of the one after that.

## Worked example: one full iteration

Starting prompt: *"The company does cycling events."*

Run 1: 61 candidates, 52 passed. Pass rate: 85%. Immediately suspicious —
see "what a healthy pass rate looks like" above.

Spot-checking ten passes: three are bike shops, two are cycling tourism
boards, one is a city council. Common thread in their `reason` fields: all
mention "cycling event" prominently, none mention any specific company's
employees.

Diagnosis: the prompt never required staff participation, and never
excluded cycling-industry businesses — exactly the gap a keyword net can't
close on its own.

Rewrite: add the two missing constraints — exclude cycling businesses,
require staff participation with named evidence types (the "strong
rewrite" example above).

Run 2: same 61 candidates, 14 passed. Pass rate: 23%. Spot-checking ten
passes now: all ten name a specific company and a specific employee or team,
sourced from JustGiving or a company post. This is the row to hand to the
user for the `Streams` table.

Total cost: two runs, roughly 10–30 minutes, because the second prompt
change targeted the exact failure mode found in the first run's `reason`
fields rather than a generic "make it stricter" guess.
