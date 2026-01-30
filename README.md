# KeepAlive

Keeps your session active (e.g. for “online” status) and suspends the system at a chosen time, then wakes it at another time.

## What it does

- **Keeps activity:** Moves the mouse slightly every 30 seconds so the session stays active.
- **Alert:** Shows a dialog 2 minutes before the chosen end time (with options to wait, cancel, or postpone by 5 minutes).
- **Suspend & wake:** At the end time, suspends the system (to RAM) and schedules wake at the configured wake-up time using `rtcwake`.

## Requirements

- **Linux** (Debian/Ubuntu; uses `apt-get` for dependencies).
- **X11:** Uses `xdotool` for mouse movement; it does not work under Wayland.
- Installed by the script: `xdotool`, `zenity`, and `rtcwake` (usually from `util-linux`).

## One-liner installation

Install without cloning the repo. You may be prompted for your password when `sudo` runs. Prefer reviewing the script at the URL first if you care about security.

**Install (curl):**

```bash
curl -sSL https://raw.githubusercontent.com/Kacoze/keepalive/master/install.sh | sudo bash
```

**Install (wget):**

```bash
wget -qO- https://raw.githubusercontent.com/Kacoze/keepalive/master/install.sh | sudo bash
```

**Uninstall (same URL, with argument):**

```bash
curl -sSL https://raw.githubusercontent.com/Kacoze/keepalive/master/install.sh | sudo bash -s -- --uninstall
```

## Installation (from repo)

```bash
sudo bash install.sh
```

After installation, a **KeepAlive** entry should appear in your application menu. On first run you will be asked for:

- **End of work (HH:MM)** – when to suspend.
- **Wake up (HH:MM)** – when to wake.

Settings are saved to `~/.config/keepalive/config` and reused on the next run. You can optionally add `KEEPALIVE_INTERVAL=30` (seconds between mouse moves) and `ALERT_BEFORE_SEC=120` (seconds before end time to show the dialog) to the config file.

## Uninstall

```bash
sudo bash install.sh --uninstall
```

This removes the main script, desktop entry, sudoers rule for `rtcwake`, and the config directory.

## CLI

The main script is installed as `keepalive.sh` in `~/.local/bin/`, with a symlink `keepalive` (so you can run `keepalive` or `keepalive.sh`). Use it from the terminal:

- **`keepalive`** or **`keepalive run`** – Start the session (zenity dialog, or use saved config). With **`--end HH:MM --wake HH:MM`** runs without zenity (e.g. for cron).
- **`keepalive config`** – Show or edit settings (zenity form). With **`--end HH:MM --wake HH:MM`** saves from the command line.
- **`keepalive status`** – Print whether a session is running and until when.
- **`keepalive uninstall`** – Print the command to uninstall (requires sudo).

Examples:

```bash
keepalive run --end 14:00 --wake 08:00
keepalive config --end 15:00 --wake 07:00
keepalive status
```

## Notes

- The installer adds a sudoers rule so `rtcwake` can be run without a password (required for scheduled wake).
- Under Wayland, mouse movement via `xdotool` may not work; the tool is intended for X11.

## License

[MIT](LICENSE)
