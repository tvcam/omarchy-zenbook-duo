# omarchy-zenbook-duo

ASUS Zenbook Duo support for [Omarchy](https://omarchy.org/) (Arch + Hyprland): a Linux take on ASUS ScreenXpert.

- **Bottom screen follows the keyboard.** It turns off when the keyboard is docked on it and back on when you lift the keyboard off.
- **Keyboard reconnects automatically.** It reconnects over Bluetooth as soon as you lift it off.
- **Per-screen brightness.** The brightness keys and sliders change the screen you're working on. Super + brightness keys change both, or you can link the two screens.
- **ASUS Fn keys work:** keyboard backlight, brightness, mic mute, emoji, screen swap and layout.
- **External monitors in the stack.** Choose where your monitor sits (above, left, right or below the laptop). The presets lay everything out around it, and it goes back to that spot whenever you plug it in.
- **Drag-to-arrange screens, like Windows display settings.** Drag screens in the panel and they snap edge-to-edge. Each external monitor is remembered by its make, model and serial, so it goes back to its own spot whenever you plug it in, on any port, even after a reboot.
- **Bar panel:** sliders for each screen, bottom screen on/off, auto-off, layout presets (stacked, side by side, top only), and keyboard status with battery level.
- **Smooth Bluetooth touchpad (optional).** BlueZ defaults to a 30–50 ms connection interval, which makes the cursor choppy. `--bluetooth` lowers it to 7.5–11.25 ms.

Tested on the **Zenbook Duo 2025 (UX8406CA)**: keyboard `0b05:1bf2` docked over USB, `0b05:1bf3` over Bluetooth. The 2024 keyboard (`0b05:1b2c`) is also recognised by the Fn key service but hasn't been tested.

## Install

```bash
git clone https://github.com/tvcam/omarchy-zenbook-duo ~/omarchy-zenbook-duo
cd ~/omarchy-zenbook-duo
./install.sh --bluetooth      # drop --bluetooth to leave /etc/bluetooth/main.conf alone
```

Or install only the bar panel straight from Omarchy (then run `./install.sh` from `~/.config/omarchy/plugins/zenbook-duo` for the rest):

```bash
omarchy plugin add https://github.com/tvcam/omarchy-zenbook-duo
```

`install.sh` does the following:

| What | Where |
|---|---|
| Bar panel plugin | `~/.config/omarchy/plugins/zenbook-duo/` |
| `zenbook-duo` CLI | `~/.local/bin/zenbook-duo` (symlink) |
| Hyprland config: dock watcher autostart, key bindings, saved screen layout | `~/.config/hypr/zenbook-duo.lua`, loaded from `hyprland.lua` |
| Fn key service (root, needs sudo) | `/usr/local/lib/zenbook-duo/`, `zenbook-duo-keys.service` |
| Touchpad palm rejection while typing | Section added to `/etc/libinput/local-overrides.quirks` |
| BlueZ tuning (`--bluetooth` only) | `/etc/bluetooth/main.conf`, backed up first |

### Pair the keyboard once

Linux has nothing like MyASUS to pair the keyboard over the dock connection, so pair it once by hand. Lift the keyboard off the screen, make sure its power switch is on, and run:

```bash
zenbook-duo keyboard pair
```

After that it reconnects on its own.

## Keys

| Key | Action |
|---|---|
| F1–F3 | Mute, volume down/up (already handled by the generic driver) |
| F4 | Keyboard backlight: off → low → medium → high |
| F5 / F6 | Brightness of the focused screen |
| Super + F5 / F6 | Brightness of both screens |
| Alt + F5 / F6 | Brightness in 1% steps |
| Ctrl + F5 / F6 | Keyboard backlight down / up |
| F7 | Sends Super+P, which Omarchy uses for "Pseudo window" (left alone) |
| F8 | Swap workspaces between the top and bottom screens |
| F9 | Mute microphone |
| F10 | The keyboard's own Bluetooth pairing key (nothing reaches the computer) |
| F11 | Emoji picker |
| F12 (MyASUS) | Open the Zenbook Duo panel |
| Key right of F12 | Bottom screen on/off |
| Alt + Tab / Shift + Alt + Tab | Cycle every visible window across all screens. The selected window flashes a thick border and its title pops up on its screen. (Omarchy's default only cycles the current workspace.) |
| Fn + Esc | Fn-lock: the top row sends F1–F12 instead of the functions above |

To change what a key does, edit `~/.config/hypr/zenbook-duo.lua`. F8, F11, F12 and the key right of F12 arrive as `XF86Launch1`, `XF86Launch2`, `XF86Launch3` and `XF86Launch4`. The keyboard forgets its backlight level and Fn-lock state each time it docks or reconnects, so the service sends them again.

## CLI

```
zenbook-duo state                                  JSON state (used by the panel)
zenbook-duo brightness [--monitor M|--both] [--no-osd] [get|+N%|N%-|N%]
zenbook-duo bottom on|off|toggle
zenbook-duo auto on|off|toggle                     bottom screen off while docked
zenbook-duo link on|off|toggle                     move both screens' brightness together
zenbook-duo layout stacked|side|top-only|next
zenbook-duo external above|below|left|right        where external monitors go in the presets
zenbook-duo arrange <monitor> <x> <y>              move a screen (logical px), saved per monitor
zenbook-duo swap
zenbook-duo cycle [next|prev]
zenbook-duo kbd-light 0-3|up|down|cycle
zenbook-duo keyboard pair|connect
zenbook-duo apply | watch
```

## How it works

- **Dock detection.** When the keyboard sits on the bottom screen it connects over USB through pogo pins. `zenbook-duo watch` follows USB add and remove events through `udevadm monitor`.
- **Saved screen layout.** The desired monitor rules are written to `~/.local/state/zenbook-duo/monitors.lua`, which `zenbook-duo.lua` loads on every config load. Running `hyprctl reload` therefore keeps the current state instead of turning the bottom screen back on.
- **Screen arrangement.** Positions are saved in `~/.local/state/zenbook-duo/positions`. Built-in screens are keyed by connector (`eDP-1`) and external monitors by `desc:<make model serial>`, the same matching Hyprland's own monitor rules use. Saved monitors that aren't plugged in keep their rules, so Hyprland moves a known monitor into place the moment it's connected. Arrangements that would make screens overlap are refused.
- **Brightness.** Each built-in screen has its own backlight device, such as `intel_backlight` → `eDP-1` and `card1-eDP-2-backlight` → `eDP-2`. The device for each screen is found from `/sys/class/backlight/*/device`. External monitors are passed to `omarchy-brightness-display`.
- **Fn keys.** The kernel's `hid-asus` driver doesn't list the 2025 keyboard, so its ASUS vendor report (ID `0x5a`, usage page `0xff31`) is ignored. `zenbook-duo-keys` reads that report from hidraw and sends standard keys through a virtual uinput keyboard called *Zenbook Duo Fn keys*. It sets the backlight with the feature report `5a ba c5 c4 <0-3>`.

## Known limitations

- **Docking is detected by the keyboard's USB connection.** If you plug the keyboard in with a USB-C cable, it also counts as docked and the bottom screen turns off. You can turn off "Turn off when keyboard is docked" in the panel, or run `zenbook-duo auto off`.
- **Upstream kernel support is still in progress.** A patch series adding these keyboards to `hid-asus` was applied and then dropped in June 2026 ([thread](https://ratatoskr.run/linux-input/2026/05/9004316/t)). If it lands, the Fn key service can probably be removed.

## Credits

The key codes and backlight protocol were checked against [cceelen/asus-zenbook-duo-ux8406](https://github.com/cceelen/asus-zenbook-duo-ux8406), [zakstam/zenbook-duo-linux](https://github.com/zakstam/zenbook-duo-linux), [alesya-h/zenbook-duo-2024-ux8406ma-linux](https://github.com/alesya-h/zenbook-duo-2024-ux8406ma-linux) and the pending kernel patches.

## Uninstall

```bash
./uninstall.sh
```

The BlueZ change is not reverted automatically. To undo it, restore `/etc/bluetooth/main.conf.bak.*`.

## License

MIT
