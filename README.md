# Vibe-To-Do ✓

A fast, keyboard-friendly **weekly task board** in a single HTML file — with an optional tiny local server that persists everything to plain JSON on disk.

No accounts. No cloud. No build step. No dependencies except [Bun](https://bun.sh). Your tasks never leave your machine.

## Features

- **Weekly board** — Monday–Friday columns (weekends optional in settings), plus a slide-in **backlog** drawer for unscheduled tasks
- **Fast capture** — quick-add in any column; `!!` / `!!!` in a title sets medium/high priority
- **Drag & drop** — between days, reorder within a day, drop on ← / → to move a task a whole week
- **Task details** — deadlines (with overdue tracking), notes, links, priorities
- **Search** — `/` or `Ctrl+K`, searches titles, links, and notes
- **Streaks & stats** — daily completion streak, weekly completion %, overdue count
- **Roll over** — pull yesterday's unfinished tasks into today with one click
- **Import / export** — JSON and CSV, with date-range filters
- **3 themes** — Dark, Light, Neon
- **Mobile gestures** — swipe right to complete, left to delete
- **Confetti** 🎉 when you clear a day

## Quick start

**macOS / Linux**

```bash
git clone https://github.com/dubey-amit/vibe-to-do.git
cd vibe-to-do
./setup.sh
```

**Windows (PowerShell)**

```powershell
git clone https://github.com/dubey-amit/vibe-to-do.git
cd vibe-to-do
powershell -ExecutionPolicy Bypass -File setup.ps1
```

The script installs Bun if you don't have it, then starts the server. Open **http://localhost:7788** — that's it.

> **Zero-install mode:** you can also just open `index.html` directly in a browser. The app works fully standalone and stores data in the browser's localStorage. The server only adds on-disk JSON persistence and backups.

### Start automatically at login

```bash
./setup.sh --autostart        # macOS (launchd) / Linux (systemd user service)
```

```powershell
powershell -ExecutionPolicy Bypass -File setup.ps1 -AutoStart   # Windows (Task Scheduler)
```

To remove it later:

- **macOS** — `launchctl unload ~/Library/LaunchAgents/com.vibe-to-do.plist && rm ~/Library/LaunchAgents/com.vibe-to-do.plist`
- **Linux** — `systemctl --user disable --now vibe-to-do.service`
- **Windows** — `Unregister-ScheduledTask -TaskName 'Vibe-To-Do'`

## How it works

```
index.html            ← the app (works standalone over file://)
server.ts             ← optional persistence server (Bun, zero npm deps)
setup.sh / setup.ps1  ← one-shot installers
data/                 ← created on first run (gitignored)
  tasks.json          ← your tasks
  settings.json       ← theme, weekends, archive policy
  completions.json    ← completion counts per day (for the streak)
  backups/            ← rolling snapshots (last 50 per file)
```

The app picks a storage mode automatically at page load:

| Mode | When | Where data lives | Indicator |
|---|---|---|---|
| **● server** | `/api/health` responds on the same origin or `http://localhost:7788` | `./data/*.json` on disk (plus a localStorage mirror) | green dot |
| **● local** | no server reachable | browser localStorage only | gray dot |

The indicator sits next to the app name in the header.

Override the port with `PORT=9000 bun server.ts`. The client only auto-detects `7788`; on a custom port, open `http://localhost:PORT/` directly.

## Settings

- **Theme** — Dark (default), Light, or Neon
- **Weekends** — off by default (Mon–Fri board); enable for a full 7-day week
- **Archive completed after (days)** — completed tasks hide after N days (0 = immediately)

## Keyboard shortcuts

| Key | Action |
|---|---|
| `N` | focus the new-task input |
| `/` or `Ctrl+K` | search |
| `T` | jump to today |
| `←` / `→` | previous / next week |
| `Esc` | close modals & drawer |
| double-click a task | edit it |

## Data safety

- **Atomic writes** — the server writes a temp file then renames, so a crash mid-write never corrupts the live file.
- **Rotating backups** — every write snapshots the previous state into `data/backups/`; the last 50 per file are kept.
- **Local mirror** — every server-mode save also writes to localStorage. If the server dies, the next reload falls back to local mode without losing the session.
- **Multi-tab safety** — writes are revision-checked; if two tabs race, the loser adopts the winner's state instead of silently overwriting it (see API below).
- **No network egress** — the server binds to `127.0.0.1`. Nothing leaves your machine.

### Restore a backup

```bash
ls data/backups/
cp data/backups/tasks-<timestamp>.json data/tasks.json
# then refresh the page
```

## Contributing

The whole app is one HTML file and one server file — read both in ten minutes. PRs welcome. Please keep the zero-dependency, single-file spirit.

## License

[MIT](LICENSE)
