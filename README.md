# Event Streams

Finds companies whose staff are doing organised events, and finds the senior
people to contact at them.

## Install

```bash
git clone https://github.com/atiksh17/event-streams.git
cd event-streams
./setup.sh
```

That is the whole install. Open the folder in Claude Code or Codex afterwards
and just say what you want.

## What to say to your agent

Copy this:

> I want to use the event-streams skill in this folder.
> Test some keywords for me first, then we'll enrich.

## The two modes

**Testing keywords** — you give keywords and a description of what counts as a
good result. It goes and looks, then shows you what it found so you can sharpen
the description. Takes 5 to 15 minutes each time.

**Enriching** — the system collects results every day on its own. When you want
contacts, name the table and it produces a spreadsheet of people with emails and
LinkedIn profiles.

Full detail in [docs/INDEX.md](docs/INDEX.md).

## If something breaks

[docs/troubleshooting.md](docs/troubleshooting.md).
