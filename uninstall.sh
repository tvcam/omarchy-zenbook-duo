#!/bin/bash
# Remove omarchy-zenbook-duo. Leaves /etc/bluetooth/main.conf alone
# (restore a main.conf.bak.* there if you want the BlueZ defaults back).

set -uo pipefail

pkill -f "zenbook-duo watch$"
pkill -f "udevadm monitor --udev --subsystem-match=usb$"
if systemctl list-unit-files zenbook-duo-keys.service >/dev/null 2>&1; then
  sudo systemctl disable --now zenbook-duo-keys.service
  sudo rm -f /etc/systemd/system/zenbook-duo-keys.service
  sudo rm -rf /usr/local/lib/zenbook-duo /var/lib/zenbook-duo
  sudo systemctl daemon-reload
fi
if [[ -f /etc/libinput/local-overrides.quirks ]]; then
  # Drop our section (from its header to the next blank line).
  sudo sed -i '/^# ASUS Zenbook Duo detachable keyboard/,/^AttrTPKComboLayout=below$/d' /etc/libinput/local-overrides.quirks
fi
omarchy plugin disable zenbook-duo >/dev/null 2>&1
rm -rf "$HOME/.config/omarchy/plugins/zenbook-duo"
rm -f "$HOME/.local/bin/zenbook-duo" "$HOME/.config/hypr/zenbook-duo.lua"
rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/zenbook-duo"
sed -i '/-- ASUS Zenbook Duo (omarchy-zenbook-duo)/d; /require("hypr.zenbook-duo")/d' "$HOME/.config/hypr/hyprland.lua"
hyprctl eval 'hl.monitor({ output = "eDP-2", disabled = false })' >/dev/null
hyprctl reload >/dev/null
echo "Removed omarchy-zenbook-duo."
