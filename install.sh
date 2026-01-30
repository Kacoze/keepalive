#!/bin/bash

# Check if run as root (required for installation and sudoers)
if [ "$EUID" -ne 0 ]; then
  echo "Run this script with sudo (sudo bash install.sh)"
  exit 1
fi

# Get real username (not root)
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6)

if [ -z "$USER_HOME" ] || [ ! -d "$USER_HOME" ]; then
  echo "Could not determine home directory for user $REAL_USER."
  exit 1
fi

# Uninstall
if [ "$1" = "--uninstall" ]; then
  SCRIPT_PATH="$USER_HOME/.local/bin/keepalive.sh"
  SYMLINK_PATH="$USER_HOME/.local/bin/keepalive"
  DESKTOP_FILE="$USER_HOME/.local/share/applications/keepalive.desktop"
  SUDOERS_FILE="/etc/sudoers.d/keepalive-nopasswd"
  CONFIG_DIR="$USER_HOME/.config/keepalive"

  echo "--- Uninstalling KeepAlive ---"
  [ -f "$SUDOERS_FILE" ] && { rm -f "$SUDOERS_FILE"; echo "Removed sudoers entry."; } || echo "Sudoers file not found (already removed?)."
  [ -L "$SYMLINK_PATH" ] && { rm -f "$SYMLINK_PATH"; echo "Removed symlink $SYMLINK_PATH"; } || true
  [ -f "$SCRIPT_PATH" ] && { rm -f "$SCRIPT_PATH"; echo "Removed $SCRIPT_PATH"; } || echo "Main script not found."
  [ -f "$DESKTOP_FILE" ] && { rm -f "$DESKTOP_FILE"; echo "Removed desktop entry."; update-desktop-database "$USER_HOME/.local/share/applications/" 2>/dev/null; } || echo "Desktop entry not found."
  [ -d "$CONFIG_DIR" ] && { rm -rf "$CONFIG_DIR"; echo "Removed config directory."; }
  echo "--- Done. KeepAlive has been uninstalled. ---"
  exit 0
fi

# When run from pipe (e.g. curl ... | sudo bash), show a short message
[[ ! -t 0 ]] && echo "Installing KeepAlive…"

if ! command -v apt-get &>/dev/null; then
  echo "This installer expects Debian/Ubuntu (apt-get)."
  exit 1
fi

echo "--- Installing dependencies ---"
apt-get update -qq
apt-get install -y xdotool zenity

echo "--- Configuring permissions (passwordless rtcwake) ---"
# Use a dedicated file in sudoers.d instead of editing main sudoers
echo "$REAL_USER ALL=(ALL) NOPASSWD: /usr/sbin/rtcwake" > /etc/sudoers.d/keepalive-nopasswd
chmod 0440 /etc/sudoers.d/keepalive-nopasswd

echo "--- Creating main script ---"
mkdir -p "$USER_HOME/.local/bin"
SCRIPT_PATH="$USER_HOME/.local/bin/keepalive.sh"

# Inject main program code
cat << 'ENDOFSCRIPT' > "$SCRIPT_PATH"
#!/bin/bash

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/keepalive"
CONFIG_FILE="$CONFIG_DIR/config"
PID_FILE="$CONFIG_DIR/keepalive.pid"

validate_time() {
  local t="$1"
  date -d "today $t" +%s >/dev/null 2>&1
}

load_config() {
  TARGET_HOUR="14:00"
  WAKE_UP_TIME="08:00"
  KEEPALIVE_INTERVAL=30
  ALERT_BEFORE_SEC=120
  [ -f "$CONFIG_FILE" ] || return 0
  while IFS= read -r line; do
    [[ "$line" =~ ^TARGET_HOUR=(.*)$ ]] && TARGET_HOUR="${BASH_REMATCH[1]}"
    [[ "$line" =~ ^WAKE_UP_TIME=(.*)$ ]] && WAKE_UP_TIME="${BASH_REMATCH[1]}"
    [[ "$line" =~ ^KEEPALIVE_INTERVAL=(.*)$ ]] && KEEPALIVE_INTERVAL="${BASH_REMATCH[1]}"
    [[ "$line" =~ ^ALERT_BEFORE_SEC=(.*)$ ]] && ALERT_BEFORE_SEC="${BASH_REMATCH[1]}"
  done < "$CONFIG_FILE"
}

save_config() {
  mkdir -p "$CONFIG_DIR"
  echo "TARGET_HOUR=$TARGET_HOUR" > "$CONFIG_FILE"
  echo "WAKE_UP_TIME=$WAKE_UP_TIME" >> "$CONFIG_FILE"
}

cmd_uninstall() {
  echo "To uninstall KeepAlive, run:"
  echo "  sudo bash install.sh --uninstall"
  echo "from the directory where you have the project (where install.sh is)."
  echo "Or uninstall with (if you installed via one-liner):"
  echo "  curl -sSL https://raw.githubusercontent.com/Kacoze/keepalive/master/install.sh | sudo bash -s -- --uninstall"
}

cmd_status() {
  if [ -f "$PID_FILE" ]; then
    read -r pid < "$PID_FILE"
    until_time=""
    [ -r "$PID_FILE" ] && until_time=$(sed -n '2p' "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      echo "Running until ${until_time:-$TARGET_HOUR}"
    else
      echo "Not running (stale PID file)"
      rm -f "$PID_FILE"
    fi
  else
    echo "Not running"
  fi
}

cmd_config() {
  local end_arg="" wake_arg=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --end)   end_arg="$2"; shift 2 ;;
      --wake)  wake_arg="$2"; shift 2 ;;
      *)       shift ;;
    esac
  done
  if [ -n "$end_arg" ] && [ -n "$wake_arg" ]; then
    TARGET_HOUR="$end_arg"
    WAKE_UP_TIME="$wake_arg"
    if ! validate_time "$TARGET_HOUR"; then echo "Invalid time: $TARGET_HOUR" >&2; exit 1; fi
    if ! validate_time "$WAKE_UP_TIME"; then echo "Invalid time: $WAKE_UP_TIME" >&2; exit 1; fi
    save_config
    echo "Saved: end $TARGET_HOUR, wake $WAKE_UP_TIME"
    return 0
  fi
  load_config
  [ -n "$end_arg" ] && TARGET_HOUR="$end_arg"
  [ -n "$wake_arg" ] && WAKE_UP_TIME="$wake_arg"
  SETTINGS=$(zenity --forms --title="KeepAlive - Config" --text="Current: End $TARGET_HOUR, Wake $WAKE_UP_TIME" \
    --add-entry="End of work (HH:MM)" \
    --add-entry="Wake up (HH:MM)" \
    --separator="|")
  [ $? -ne 0 ] && exit 0
  TARGET_HOUR=$(echo "$SETTINGS" | cut -d| -f1)
  WAKE_UP_TIME=$(echo "$SETTINGS" | cut -d| -f2)
  [ -z "$TARGET_HOUR" ] && TARGET_HOUR="14:00"
  [ -z "$WAKE_UP_TIME" ] && WAKE_UP_TIME="08:00"
  if ! validate_time "$TARGET_HOUR"; then zenity --error --text="Invalid time: $TARGET_HOUR"; exit 1; fi
  if ! validate_time "$WAKE_UP_TIME"; then zenity --error --text="Invalid time: $WAKE_UP_TIME"; exit 1; fi
  save_config
  zenity --info --text="Saved: end $TARGET_HOUR, wake $WAKE_UP_TIME"
}

cmd_run() {
  load_config
  local end_arg="" wake_arg=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --end)   end_arg="$2"; shift 2 ;;
      --wake)  wake_arg="$2"; shift 2 ;;
      *)       shift ;;
    esac
  done

  mkdir -p "$CONFIG_DIR"
  if [ -f "$PID_FILE" ]; then
    read -r pid < "$PID_FILE"
    until_time=$(sed -n '2p' "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      echo "Already running (until ${until_time:-?})." >&2
      exit 1
    fi
    rm -f "$PID_FILE"
  fi

  if [ -n "$end_arg" ] && [ -n "$wake_arg" ]; then
    TARGET_HOUR="$end_arg"
    WAKE_UP_TIME="$wake_arg"
    if ! validate_time "$TARGET_HOUR"; then echo "Invalid time: $TARGET_HOUR" >&2; exit 1; fi
    if ! validate_time "$WAKE_UP_TIME"; then echo "Invalid time: $WAKE_UP_TIME" >&2; exit 1; fi
    save_config
  else
    load_config
    SETTINGS=$(zenity --forms --title="KeepAlive" --text="Configure work time" \
      --add-entry="End of work (HH:MM)" \
      --add-entry="Wake up (HH:MM)" \
      --separator="|")
    [ $? -ne 0 ] && exit 0
    TARGET_HOUR=$(echo "$SETTINGS" | cut -d| -f1)
    WAKE_UP_TIME=$(echo "$SETTINGS" | cut -d| -f2)
    [ -z "$TARGET_HOUR" ] && TARGET_HOUR="14:00"
    [ -z "$WAKE_UP_TIME" ] && WAKE_UP_TIME="08:00"
    if ! validate_time "$TARGET_HOUR"; then zenity --error --text="Invalid time: $TARGET_HOUR"; exit 1; fi
    if ! validate_time "$WAKE_UP_TIME"; then zenity --error --text="Invalid time: $WAKE_UP_TIME"; exit 1; fi
    save_config
  fi

  TARGET_SEC=$(date -d "today $TARGET_HOUR" +%s)
  CURRENT_SEC=$(date +%s)
  [ "$TARGET_SEC" -le "$CURRENT_SEC" ] && TARGET_SEC=$(date -d "tomorrow $TARGET_HOUR" +%s)
  ALERT_SHOWN=false

  for cmd in xdotool zenity rtcwake; do
    if ! command -v "$cmd" &>/dev/null; then
      if [ -n "${DISPLAY:-}" ]; then
        zenity --error --text="Missing required command: $cmd"
      else
        echo "Missing required command: $cmd" >&2
      fi
      exit 1
    fi
  done
  if [ -z "${DISPLAY:-}" ]; then
    echo "DISPLAY is not set; zenity and xdotool require X11." >&2
    exit 1
  fi

  mkdir -p "$CONFIG_DIR"
  echo $$ > "$PID_FILE"
  echo "$TARGET_HOUR" >> "$PID_FILE"
  trap 'rm -f "$PID_FILE"' EXIT

  notify-send "KeepAlive" "Keeping active until $TARGET_HOUR. Wake up at $WAKE_UP_TIME."

  while true; do
    CURRENT_SEC=$(date +%s)
    TIME_LEFT=$((TARGET_SEC - CURRENT_SEC))

    if [ "$TIME_LEFT" -le "${ALERT_BEFORE_SEC:-120}" ] && [ "$TIME_LEFT" -gt 0 ] && [ "$ALERT_SHOWN" = false ]; then
      RESPONSE=$(zenity --question \
        --title="End of work" \
        --text="System will suspend in $(( ALERT_BEFORE_SEC / 60 )) minutes ($TARGET_HOUR)." \
        --ok-label="OK (Wait)" \
        --cancel-label="Cancel" \
        --extra-button="Postpone 5 min" \
        --timeout=60)
      EXIT_CODE=$?
      if [ "$RESPONSE" = "Postpone 5 min" ]; then
        TARGET_SEC=$((TARGET_SEC + 300))
        notify-send "KeepAlive" "Postponed by 5 minutes."
        ALERT_SHOWN=false
        continue
      elif [ "$EXIT_CODE" -eq 1 ]; then
        notify-send "Cancelled" "Computer will stay on."
        exit 0
      else
        ALERT_SHOWN=true
      fi
    fi

    if [ "$CURRENT_SEC" -ge "$TARGET_SEC" ]; then
      notify-send "KeepAlive" "Suspending system..."
      sleep 5
      WAKE_SEC=$(date -d "tomorrow $WAKE_UP_TIME" +%s)
      sudo rtcwake -m mem -t "$WAKE_SEC"
      exit 0
    fi

    xdotool mousemove_relative 1 0
    xdotool mousemove_relative -- -1 0
    sleep "${KEEPALIVE_INTERVAL:-30}"
  done
}

CMD="${1:-run}"
shift || true
case "$CMD" in
  run)      cmd_run "$@" ;;
  config)   cmd_config "$@" ;;
  uninstall) cmd_uninstall ;;
  status)   load_config; cmd_status ;;
  *)        echo "Usage: keepalive [run|config|uninstall|status] [run: --end HH:MM --wake HH:MM] [config: --end HH:MM --wake HH:MM]" >&2; exit 1 ;;
esac
ENDOFSCRIPT

# Make script executable and set ownership
chmod +x "$SCRIPT_PATH"
chown "$REAL_USER":"$REAL_USER" "$SCRIPT_PATH"
ln -sf keepalive.sh "$USER_HOME/.local/bin/keepalive"
chown -h "$REAL_USER":"$REAL_USER" "$USER_HOME/.local/bin/keepalive"

echo "--- Creating icon ---"
DESKTOP_FILE="$USER_HOME/.local/share/applications/keepalive.desktop"

cat << EOF > "$DESKTOP_FILE"
[Desktop Entry]
Name=KeepAlive
Comment=Keep activity and suspend at given time
Exec=$SCRIPT_PATH
Icon=preferences-system-time
Terminal=false
Type=Application
Categories=Utility;
EOF

chown "$REAL_USER":"$REAL_USER" "$DESKTOP_FILE"

# Refresh icon database (re-login may be required on some systems)
update-desktop-database "$USER_HOME/.local/share/applications/" 2>/dev/null

echo "--- Done! ---"
echo "The 'KeepAlive' icon should appear in the application menu."
echo "On first run it will ask for the times."