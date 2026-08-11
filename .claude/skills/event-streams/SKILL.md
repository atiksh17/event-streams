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

<!-- Task 6 -->

## Rules that must not need a lookup

<!-- Task 6 -->
