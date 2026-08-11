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

<!-- Task 5 -->

## Production mode

<!-- Task 6 -->

## Rules that must not need a lookup

<!-- Task 6 -->
