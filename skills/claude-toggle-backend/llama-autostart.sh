#!/bin/bash
# Optional: start the local llama.cpp server automatically at login via a launchd LaunchAgent.
# OFF by default — only run `install` if you explicitly want auto-start.
#
# Usage: llama-autostart.sh [install|uninstall|status]
# Env:   LLAMACPP_PORT (default 8730), LOCAL_MODELS_DIR (default ~/Local-Models)
#
# Notes:
#  - Uses KeepAlive=false: starts ONCE at login (RunAtLoad), but you can still `llama-cpp-down`
#    it without it respawning until the next login. So it coexists with the manual aliases.
#  - Holds the model (~14 GB) in RAM from login on. On a 24 GB machine, don't also run Ollama.
#  - macOS shows a one-time "background item added" (Login Items) notification on install.
set -euo pipefail

LABEL="com.localclaude.llama-server"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SERVE="$HOME/.claude/localclaude-plugins/localclaude/skills/claude-toggle-backend/llama-serve.sh"
PORT="${LLAMACPP_PORT:-8730}"
MODELS_DIR="${LOCAL_MODELS_DIR:-$HOME/Local-Models}"
LOG="$HOME/.claude/llama-server.log"
DOMAIN="gui/$(id -u)"
CMD="${1:-status}"

case "$CMD" in
  install)
    [ -f "$SERVE" ] || { echo "llama-serve.sh not found at $SERVE (is the plugin installed?)" >&2; exit 1; }
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$SERVE</string>
    <string>foreground</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>LLAMACPP_PORT</key><string>$PORT</string>
    <key>LOCAL_MODELS_DIR</key><string>$MODELS_DIR</string>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PLIST
    # reload if already present, then bootstrap (which also starts it via RunAtLoad)
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    launchctl bootstrap "$DOMAIN" "$PLIST"
    echo "Installed + loaded $LABEL (auto-starts at login on port $PORT)."
    echo "macOS may show a 'background item added' notification. To remove: $(basename "$0") uninstall"
    # Add a convenience alias (only while auto-start is enabled; uninstall removes it again).
    # Marked block so it can be cleanly stripped. Guarded so re-install doesn't duplicate.
    if ! grep -q "# >>> localclaude autostart-alias" "$HOME/.zshrc" 2>/dev/null; then
      cat >> "$HOME/.zshrc" <<'ALIAS'

# >>> localclaude autostart-alias >>>
alias llama-cpp-autostart='bash "$HOME/.claude/localclaude-plugins/localclaude/skills/claude-toggle-backend/llama-autostart.sh"'
# <<< localclaude autostart-alias <<<
ALIAS
      echo "Added 'llama-cpp-autostart' alias to ~/.zshrc (open a new shell, then: llama-cpp-autostart status|install|uninstall)."
    fi
    ;;
  uninstall)
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    # Remove the convenience alias too, so the skill (llama-autostart.sh install) is the single
    # obvious way to re-enable auto-start. Strips the marked block; leaves all other zshrc lines.
    if [ -f "$HOME/.zshrc" ] && grep -q "# >>> localclaude autostart-alias" "$HOME/.zshrc"; then
      awk '/# >>> localclaude autostart-alias/{s=1} /# <<< localclaude autostart-alias/{s=0;next} !s' "$HOME/.zshrc" > "$HOME/.zshrc.tmp" && mv "$HOME/.zshrc.tmp" "$HOME/.zshrc"
      echo "Removed 'llama-cpp-autostart' alias from ~/.zshrc."
    fi
    echo "Uninstalled $LABEL (removed plist; auto-start disabled). The running server, if any, is left alone — stop it with llama-cpp-down."
    ;;
  status)
    if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
      echo "auto-start: ENABLED (LaunchAgent $LABEL loaded; starts at login on port $PORT)"
    elif [ -f "$PLIST" ]; then
      echo "auto-start: plist present but not loaded ($PLIST) — run '$(basename "$0") install' to (re)load"
    else
      echo "auto-start: DISABLED (no LaunchAgent) — manual via llama-cpp-up"
    fi
    ;;
  *)
    echo "usage: llama-autostart.sh [install|uninstall|status]" >&2
    exit 1
    ;;
esac
