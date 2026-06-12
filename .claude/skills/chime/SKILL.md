---
name: chime
description: Query and orchestrate the user's daily schedule via Chime (the macOS desktop widget). Use when the user asks "what should I do now", "what's my schedule today", "what's next", wants to add/move/remove a time block, change today's plan, or wants you to act based on the current block (e.g. prep for the next block, stay focused during deep work).
---

# Chime — schedule-aware orchestration

The user runs **Chime**, a desktop widget that shows the current time block of their day. The schedule is the single source of truth at `~/.config/chime/schedule.json`. The widget **hot-reloads it within 30 seconds** of any change — edit the file and you're done, no restart.

## Reading the current state

Prefer the bundled `chime` CLI (read-only, outputs JSON):

```sh
chime status --json   # current block + remaining + next  (./chime from repo root if not on PATH)
chime next --json     # the upcoming block and when it starts
chime today --json    # the full day, current block flagged
```

`status --json` shape:
```json
{ "now": "14:32", "free": false,
  "current": { "start": "13:30", "end": "17:00", "emoji": "🔨", "title": "Focus",
               "task": "...", "remaining_minutes": 148, "remaining": "2h28m" },
  "next":    { "start": "17:00", "title": "Exercise", "starts_in": "2h28m", ... } }
```
`current` is `null` and `free` is `true` during gaps. If the CLI isn't available, read `~/.config/chime/schedule.json` directly (format below) and compute the current block yourself — a block is active when `start <= now < end`, or for blocks that cross midnight (`start > end`) when `now >= start || now < end`.

## Schedule format

A JSON array of blocks:
```json
{ "start": "09:00", "end": "12:30", "emoji": "💻", "title": "Deep work",
  "task": "Hardest task first; notifications off", "notify": true }
```
- `start`/`end` are 24-hour `HH:mm`; `end` may wrap past midnight (e.g. `23:00`→`07:00`).
- `task` segments split on `;` and render as separate lines (card + notification body).
- `notify` defaults to true; set false for sleep/breaks/optional blocks.
- Blocks must not overlap; gaps are fine (shown as "Free time").

## Modifying the schedule

1. **Back up first:** `cp ~/.config/chime/schedule.json ~/.config/chime/schedule.json.bak`
2. Edit the JSON, then validate: `python3 -m json.tool ~/.config/chime/schedule.json`
3. Check no overlaps and valid `HH:mm`.
4. Tell the user it takes effect within 30s (or they can right-click → Reload).
5. **Temporary change for today?** The file has no concept of dates — say so, and offer to revert later or keep a `schedule.default.json` copy.

## Orchestration patterns

- **"What should I do now?"** → `chime status` → answer with the block + its tasks, concisely.
- **Block-aware behavior** — check `chime status --json` before acting. In a deep-work/focus block, stay terse and don't suggest side quests; in a writing/creation block, proactively offer to draft or gather material; during free time or breaks, don't push work.
- **Prep the next block** — `chime next` → get the user ready ("Writing block in 18 min — want me to pull up today's notes?").
- **Pair with schedulers** — a cron job or scheduled AI task can call `chime today` at the start of the day to know its shape, or `chime status --json` to decide whether to run now or defer.
- **Respect the boundaries** — the schedule encodes the user's intent for their day. Don't silently reshuffle it; propose changes and let them confirm.

## Files

- Schedule: `~/.config/chime/schedule.json`
- CLI: `chime` (repo root; `chime status`, `chime next`, `chime today`, all accept `--json`)
- Widget source: `Chime.swift` (rebuild with `./build.sh && open Chime.app`)
