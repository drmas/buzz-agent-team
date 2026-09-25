---
name: memory
description: Your long-term memory in ~/memory, via the `mem` command. Use it (1) before answering or acting on anything that may depend on earlier context - people, preferences, past decisions, ongoing projects, commitments - and (2) after work that produced something worth remembering. Search first; never read memory in bulk.
---

# Long-term memory (file based, token-frugal)

Memory is **not** loaded into your context automatically. It lives in `~/memory` and you pull
in only the few lines you need, with the `mem` command (every command's output is capped).

```
~/memory/
  INDEX.md            one line per topic file: `path` — what it holds
  tasks.md            open commitments (mem task …)
  people/<name>.md    who they are, role, preferences, how to work with them
  projects/<slug>.md  goal, status, owners, key links (channel + thread ids)
  decisions/<yyyy>.md dated decisions with the reason and who decided
  howto/<topic>.md    procedures and lessons you want to reuse
  log/<yyyy-mm>.md    append-only history, one line per significant event
```

## Reading: search first, then read slices

1. `mem find <2-4 keywords>` → matching lines with file paths (index hits first).
2. `mem show <file> [from] [n]` → only the part you need (40 lines by default, max 80).
3. `mem task list` when asked what's pending or before promising new work.

Never `cat`, `grep -r`, or `ls -R` the whole `~/memory`, and don't read INDEX.md or a file
"just in case". If a search finds nothing, proceed without memory; don't browse.

Skip memory entirely for self-contained requests (e.g. "rewrite this sentence").

For **raw conversation history**, don't copy it into memory. Query Buzz with a limit when you
need it: `buzz messages search --query <words> --limit 10`, or
`buzz messages thread …` for one thread. Store only the pointer (channel + thread event id).

## Writing: small, durable, deduplicated

Record things that will matter in a future conversation:
- decisions (what, why, who decided) → `decisions/<year>.md`
- facts about people, the team, the product, customers, preferences → `people/`, `projects/`
- commitments you or others made, with owner and date → `mem task add "…"`
- lessons and reusable procedures → `howto/`
- one line per significant event you handled → `mem log "…"`

Commands:
- `mem new <file> "<one-line hook>"` creates a file and registers it in INDEX.md.
- `mem add <file> "<fact>"` appends one dated bullet (≤300 characters, one fact per bullet).
- Before adding, `mem find` the key words: if the fact exists, update that line in place
  (edit the file) instead of adding a near-duplicate; if it changed, replace the old line.

Do **not** store: secrets or credentials of any kind, raw transcripts or long quotes, anything
you can cheaply re-fetch from Buzz, guesses presented as facts, or private details about
people that aren't needed for the work. Humans may ask what you remember: `mem find` / `mem show`
and answer honestly; delete lines when asked to forget something.

## Keep it small

Run `mem stats` about once a day or when a command warns you. Then:
- a topic file over 80 lines → consolidate: merge duplicates, drop stale or superseded lines,
  keep the newest truth.
- old monthly logs → fold the few lines still worth keeping into topic files, then delete the log.
- keep INDEX.md under 80 lines: merge small related files.

Write memory at natural checkpoints (end of a task, a decision, a new commitment), not every
turn, and never let memory work delay your reply to a human.

## Backup and visibility

`~/memory` is mirrored every night into your Buzz memory (encrypted so only you and your
owner can read it; the owner sees it on your profile in Buzz Desktop). The files are the
source of truth: don't write with `buzz mem` yourself, because the next mirror overwrites it.
Write only what you'd be comfortable with the owner reading.
