# Chime 🐦

A tiny **draggable desktop pet** for macOS that tells you what to do *right now*, based on a daily schedule you control. It floats above your work, counts down the current block, and chimes a notification when a new block begins.

**English** · [中文](README.zh-CN.md)

```
┌──────────────────────────────┐
│ 💻 Deep work             ➖  │        collapsed into a pill:
│ 09:00–12:30 · 2h14m left     │
│ · Hardest task first          │   ┌──────────────┐
│ · Notifications off           │   │  💻 2h14m     │
└──────────────────────────────┘   └──────────────┘
```

No menu bar clutter, no Dock icon, no window chrome — just a small card you can drag anywhere and collapse into a pill when you want it out of the way.

## Why

Most time-management apps make you *open them* to see what's next. Chime inverts that: the answer is always on screen, glanceable, and gets out of the way when you collapse it. It's built for people who run a structured day — deep-work blocks, exercise, creative time — and want a gentle, ambient nudge at each transition instead of a calendar full of alarms.

## Features

- **Always-on glance** — current block, time remaining, and the tasks for it, floating above everything
- **Drag anywhere** — position is remembered across restarts
- **Collapse to a pill** — shrinks to just an emoji + countdown; click to expand
- **Native notifications** — chimes when each block begins (per-block opt-out)
- **Plain-JSON schedule** — edit one file; the app hot-reloads it within 30s
- **Follows every Space**, adapts to light/dark mode, frosted-glass look
- **Launch at login** — one click
- **Zero dependencies** — a single Swift file, ~500 lines, builds with `swiftc`

## Install

Requires macOS 12+ and the Xcode command-line tools (`xcode-select --install`).

```sh
git clone https://github.com/partyfly/chime.git
cd chime
./build.sh
open Chime.app
```

A frosted card appears in the top-right of your screen. On first launch, macOS asks for notification permission — allow it so block transitions can chime.

> Chime is ad-hoc signed for local use. On first open you may need to right-click → **Open** to bypass Gatekeeper, or allow it in System Settings → Privacy & Security.

## Usage

| Action | What it does |
|---|---|
| **Drag** the card or pill | Move it anywhere; position is saved |
| Click **➖** (or the pill) | Toggle between full card and pill |
| **Right-click** | Menu: today's schedule, edit, reload, launch-at-login, quit |
| Double-click the app again | Brings the pet to the front and expands it |

The pill shows `💻 2h14m` during a block, `→🌙 32m` when the next block starts within 90 minutes, or `🐦` during free time.

## Customize your schedule

Right-click → **Edit schedule (JSON)** opens `~/.config/chime/schedule.json` (created on first edit):

```json
[
  { "start": "09:00", "end": "12:30", "emoji": "💻",
    "title": "Deep work",
    "task": "Hardest task first; notifications off",
    "notify": true },
  { "start": "12:30", "end": "13:30", "emoji": "🍽️",
    "title": "Lunch", "task": "Step away from the screen", "notify": false }
]
```

- `start` / `end` are 24-hour `HH:mm`. `end` may wrap past midnight (e.g. `23:00` → `07:00`).
- `task` segments split on `;` and render as separate lines (in the card and the notification body).
- `notify: false` silences a block (good for sleep, breaks, optional slots).
- Blocks shouldn't overlap; gaps are fine — the card shows "Free time" and counts down to the next block.

Save the file and the app reloads within 30 seconds (or right-click → **Reload schedule**). A starter `schedule.example.json` ships in this repo.

## Launch at login

Right-click → **Launch at login**. This writes `~/Library/LaunchAgents/com.partyfly.chime.plist`; click again to remove it.

## How it works

A single Swift file using AppKit. The widget is a borderless, transparent `NSWindow` at `.floating` level with `NSVisualEffectView` for the frosted look and `mouseDownCanMoveWindow` for drag-anywhere. A 30-second timer recomputes the current block, repaints the card, fires notifications via `UserNotifications`, and hot-reloads the schedule file when its modification time changes. Position and collapsed-state persist in `UserDefaults`. No frameworks, no package manager, no build system beyond `swiftc`.

## License

[MIT](LICENSE) © 2026 partyfly
