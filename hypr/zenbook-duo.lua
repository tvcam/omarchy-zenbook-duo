-- ASUS Zenbook Duo support for Omarchy (omarchy-zenbook-duo).
-- Installed to ~/.config/hypr/zenbook-duo.lua and loaded from hyprland.lua with:
--   require("hypr.zenbook-duo")

local home = os.getenv("HOME")
local duo = home .. "/.local/bin/zenbook-duo"
local state = (os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")) .. "/zenbook-duo/monitors.lua"

-- Screen layout and bottom-screen on/off, written by `zenbook-duo`.
-- Loaded on every config reload so a reload never undoes the current state.
local f = io.open(state, "r")
if f then
  f:close()
  dofile(state)
end

-- Watch the keyboard: bottom screen off while docked, Bluetooth reconnect when lifted.
o.launch_on_start(duo .. " watch")

-- Brightness keys adjust the focused screen; SUPER + keys adjust both.
o.rebind("XF86MonBrightnessUp", "Brightness up (focused screen)", duo .. " brightness +5%", { locked = true, repeating = true })
o.rebind("XF86MonBrightnessDown", "Brightness down (focused screen)", duo .. " brightness 5%-", { locked = true, repeating = true })
o.bind("SUPER + XF86MonBrightnessUp", "Brightness up (both screens)", duo .. " brightness --both +5%", { locked = true, repeating = true })
o.bind("SUPER + XF86MonBrightnessDown", "Brightness down (both screens)", duo .. " brightness --both 5%-", { locked = true, repeating = true })
o.rebind("ALT + XF86MonBrightnessUp", "Brightness up precise", duo .. " brightness +1%", { locked = true, repeating = true })
o.rebind("ALT + XF86MonBrightnessDown", "Brightness down precise", duo .. " brightness 1%-", { locked = true, repeating = true })

-- ASUS Fn keys, translated by the zenbook-duo-keys service. F5/F6 arrive as the
-- standard brightness keys above and F9 as XF86AudioMicMute; F4 (keyboard light)
-- and Fn+Esc (Fn-lock) are handled inside the service. F7 sends SUPER + P, which
-- Omarchy uses for "Pseudo window", and F10 only pairs the keyboard over Bluetooth.
o.bind("XF86Launch1", "Swap top and bottom screens", duo .. " swap")                              -- F8
o.bind("XF86Launch2", "Emojis", { panel = "omarchy.emojis" })                                     -- F11
o.bind("XF86Launch3", "Zenbook Duo panel", "omarchy-shell zenbook-duo toggle")                    -- F12 (MyASUS)
o.bind("XF86Launch4", "Bottom screen on/off", duo .. " bottom toggle")                            -- key right of F12
o.rebind("CTRL + XF86MonBrightnessUp", "Keyboard brightness up", duo .. " kbd-light up", { locked = true })
o.rebind("CTRL + XF86MonBrightnessDown", "Keyboard brightness down", duo .. " kbd-light down", { locked = true })

-- Alt+Tab cycles every visible window on every screen (Omarchy's default only
-- cycles the current workspace, often a single window with two built-in screens).
o.rebind("ALT + TAB", "Focus next window (all screens)", duo .. " cycle next")
o.rebind("ALT + SHIFT + TAB", "Focus previous window (all screens)", duo .. " cycle prev")
