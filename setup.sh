#!/usr/bin/env bash
# Vibe-To-Do setup — installs Bun if needed, then starts the server.
#
#   ./setup.sh               install deps + run the server in the foreground
#   ./setup.sh --autostart   also register the server to start at login
#                            (launchd on macOS, systemd user unit on Linux)
set -euo pipefail
cd "$(dirname "$0")"

PORT="${PORT:-7788}"
AUTOSTART=0
for arg in "$@"; do
  case "$arg" in
    --autostart) AUTOSTART=1 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -5
      exit 0 ;;
    *) echo "Unknown option: $arg (try --help)"; exit 1 ;;
  esac
done

# ── 1. Bun (the only dependency) ────────────────────────────────────────
if ! command -v bun >/dev/null 2>&1; then
  echo "→ Bun not found — installing (https://bun.sh)…"
  curl -fsSL https://bun.sh/install | bash
  export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
  export PATH="$BUN_INSTALL/bin:$PATH"
fi
if ! command -v bun >/dev/null 2>&1; then
  echo "✗ Bun install finished but 'bun' is not on PATH. Open a new terminal and re-run ./setup.sh"
  exit 1
fi
BUN="$(command -v bun)"
APP_DIR="$(pwd)"
echo "→ Bun $(bun --version) at $BUN"

# ── 2. Optional: start at login ─────────────────────────────────────────
if [ "$AUTOSTART" = "1" ]; then
  case "$(uname -s)" in
    Darwin)
      PLIST="$HOME/Library/LaunchAgents/com.vibe-to-do.plist"
      mkdir -p "$HOME/Library/LaunchAgents"
      cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.vibe-to-do</string>
  <key>ProgramArguments</key>
  <array>
    <string>${BUN}</string>
    <string>${APP_DIR}/server.ts</string>
  </array>
  <key>WorkingDirectory</key><string>${APP_DIR}</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>${APP_DIR}/server.log</string>
  <key>StandardErrorPath</key><string>${APP_DIR}/server.log</string>
</dict>
</plist>
EOF
      launchctl unload "$PLIST" 2>/dev/null || true
      launchctl load "$PLIST"
      echo "→ Registered launchd agent com.vibe-to-do (starts at login)."
      ;;
    Linux)
      UNIT_DIR="$HOME/.config/systemd/user"
      mkdir -p "$UNIT_DIR"
      cat > "$UNIT_DIR/vibe-to-do.service" <<EOF
[Unit]
Description=Vibe-To-Do server

[Service]
ExecStart=${BUN} ${APP_DIR}/server.ts
WorkingDirectory=${APP_DIR}
Restart=always

[Install]
WantedBy=default.target
EOF
      systemctl --user daemon-reload
      systemctl --user enable --now vibe-to-do.service
      echo "→ Registered systemd user service vibe-to-do (starts at login)."
      ;;
    *)
      echo "✗ --autostart is only supported on macOS and Linux here. On Windows use setup.ps1 -AutoStart."
      exit 1 ;;
  esac
  sleep 1
  if curl -fsS "http://localhost:${PORT}/api/health" >/dev/null 2>&1; then
    echo "✓ Vibe-To-Do is running → http://localhost:${PORT}"
  else
    echo "… server registered; if it isn't up yet, check server.log"
  fi
  exit 0
fi

# ── 3. Foreground run ────────────────────────────────────────────────────
echo "→ Starting Vibe-To-Do on http://localhost:${PORT}  (Ctrl+C to stop)"
exec "$BUN" server.ts
