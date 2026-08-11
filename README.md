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

It works in **any** folder, and everything it sets up stays **inside that
folder**. Clone it twice into two directories and you get two independent
copies — neither one changes how your agents behave anywhere else on your
machine. Cloning gives you the skill; `./setup.sh` adds the two data
connections it needs.

One thing to know up front: the enrichment step works in Claude Code but not
in Codex, because of a bug in one of the upstream services. Everything else
works in both. `./setup.sh` tells you if this is still the case when you run
it, and [docs/troubleshooting.md](docs/troubleshooting.md) explains it.

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
