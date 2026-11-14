#!/bin/bash
# Install omarchy-zenbook-duo for the current user.
#
#   ./install.sh               Plugin, CLI, Hyprland snippet, keyboard watcher,
#                              Fn key service (needs sudo)
#   ./install.sh --no-keys     Skip the Fn key service
#   ./install.sh --bluetooth   Also tune BlueZ for a smooth Bluetooth touchpad
#                              and fast reconnects (edits /etc/bluetooth/main.conf, needs sudo)

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="zenbook-duo"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
HYPR_DIR="$HOME/.config/hypr"
BIN="$HOME/.local/bin/zenbook-duo"
bluetooth=0
keys=1

for arg in "$@"; do
  case $arg in
    --bluetooth) bluetooth=1 ;;
    --no-keys) keys=0 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }

product=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
if [[ $product != *"Zenbook Duo"* ]]; then
  echo "Warning: this machine reports '$product', not a Zenbook Duo. Continuing anyway."
fi
for cmd in hyprctl jq brightnessctl bluetoothctl udevadm omarchy; do
  command -v "$cmd" >/dev/null || { echo "missing dependency: $cmd" >&2; exit 1; }
done

# 1. Shell plugin. Skip the copy when installed with `omarchy plugin add`.
if [[ $SRC != "$PLUGIN_DIR" ]]; then
  say "Installing bar plugin to $PLUGIN_DIR"
  mkdir -p "$PLUGIN_DIR"
  cp -r "$SRC/manifest.json" "$SRC/Panel.qml" "$SRC/i18n" "$SRC/bin" "$SRC/hypr" \
    "$SRC/libinput" "$SRC/install.sh" "$SRC/uninstall.sh" "$SRC/zenbook-duo-keys.service" "$PLUGIN_DIR/"
fi
chmod +x "$PLUGIN_DIR/bin/zenbook-duo"

# 2. CLI on PATH.
say "Linking $BIN"
mkdir -p "$(dirname "$BIN")"
ln -sfn "$PLUGIN_DIR/bin/zenbook-duo" "$BIN"

# 3. Hyprland snippet: autostart watcher, brightness keys, persistent layout.
say "Installing Hyprland config to $HYPR_DIR/zenbook-duo.lua"
cp "$SRC/hypr/zenbook-duo.lua" "$HYPR_DIR/zenbook-duo.lua"
if ! grep -q 'require("hypr.zenbook-duo")' "$HYPR_DIR/hyprland.lua"; then
  cp "$HYPR_DIR/hyprland.lua" "$HYPR_DIR/hyprland.lua.bak.$(date +%s)"
  printf '\n-- ASUS Zenbook Duo (omarchy-zenbook-duo)\nrequire("hypr.zenbook-duo")\n' >>"$HYPR_DIR/hyprland.lua"
fi

# 4. Fn key + keyboard backlight service (root: reads hidraw, writes uinput).
#    Installed to a root-owned path; never run as root from the user's home.
if ((keys)); then
  say "Installing Fn key service (sudo)"
  sudo install -Dm755 "$SRC/bin/zenbook-duo-keys" /usr/local/lib/zenbook-duo/zenbook-duo-keys
  sudo install -Dm644 "$SRC/zenbook-duo-keys.service" /etc/systemd/system/zenbook-duo-keys.service
  sudo systemctl daemon-reload
  sudo systemctl enable zenbook-duo-keys.service
  sudo systemctl restart zenbook-duo-keys.service

  # Palm rejection for the keyboard's touchpad. libinput reads only this one
  # local file, so append our section instead of replacing the file.
  if ! sudo grep -qs "Zenbook Duo Keyboard Touchpad" /etc/libinput/local-overrides.quirks; then
    sudo mkdir -p /etc/libinput
    { echo; cat "$SRC/libinput/zenbook-duo.quirks"; } | sudo tee -a /etc/libinput/local-overrides.quirks >/dev/null
  fi
fi

# 5. Optional BlueZ tuning.
if ((bluetooth)); then
  say "Tuning /etc/bluetooth/main.conf (sudo)"
  sudo cp /etc/bluetooth/main.conf "/etc/bluetooth/main.conf.bak.$(date +%s)"
  # Connection interval 7.5-11.25 ms (BlueZ default 30-50 ms makes the touchpad choppy),
  # faster and more persistent reconnects, silent re-pairing.
  sudo sed -i -E \
    -e 's/^#?MinConnectionInterval=.*/MinConnectionInterval=6/' \
    -e 's/^#?MaxConnectionInterval=.*/MaxConnectionInterval=9/' \
    -e 's/^#?ConnectionLatency=.*/ConnectionLatency=0/' \
    -e 's/^#?FastConnectable *=.*/FastConnectable = true/' \
    -e 's/^#?JustWorksRepairing *=.*/JustWorksRepairing = always/' \
    -e 's/^#?ReconnectAttempts=.*/ReconnectAttempts=15/' \
    -e 's/^#?ReconnectIntervals=.*/ReconnectIntervals=1,1,2,2,4,4,8/' \
    -e 's/^#?AutoEnable=.*/AutoEnable=true/' \
    /etc/bluetooth/main.conf
  sudo systemctl restart bluetooth
fi

# 6. Apply now.
say "Applying"
"$BIN" apply
hyprctl reload >/dev/null
errors=$(hyprctl configerrors)
[[ -z ${errors//[[:space:]]/} ]] || { echo "Hyprland config errors:"; echo "$errors"; }
# Restart the watcher so it runs the code just installed.
pkill -f "zenbook-duo watch$" 2>/dev/null || true
pkill -f "socat -u UNIX-CONNECT:.*/.socket2.sock -$" 2>/dev/null || true
sleep 0.5
setsid -f "$BIN" watch >/dev/null 2>&1
# The shell needs a moment to discover a newly copied plugin before it can be enabled.
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
for _ in 1 2 3 4 5; do
  sleep 1
  omarchy plugin list 2>/dev/null | grep -q "^$PLUGIN_ID .*enabled" && break
  omarchy plugin enable "$PLUGIN_ID" --section right >/dev/null 2>&1 || true
done

say "Done."
if [[ -z $("$BIN" state | jq -r 'select(.keyboard.paired) | 1') ]]; then
  echo
  echo "Next: pair the keyboard over Bluetooth once. Lift it off the screen and run:"
  echo "  zenbook-duo keyboard pair"
fi
