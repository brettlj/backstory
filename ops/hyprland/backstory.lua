-- Hyprland windowrule for the Backstory panel (tasks 93f7c6fd, 2606210b), in
-- Omarchy's Lua config format.
-- The panel is a regular floating toplevel (Quickshell FloatingWindow), not a
-- layer-shell surface, so Hyprland's own move/resize binds apply. Every
-- Quickshell FloatingWindow has class org.quickshell, so the rule matches BOTH
-- class and title: title `backstory` is Panel.qml's `windowTitle`;
-- ops/hyprland_windowrule_test.go keeps the two in sync.
-- Install: `make install` copies this to ~/.config/hypr/backstory.lua; add `require("hypr.backstory")` to hyprland.lua.
-- Size 380x640 matches Panel.qml's card (a Hyprland size rule overrides QML size).
-- `o` is Omarchy's global (default/hypr/helpers.lua defines it); no require.

local BACKSTORY = { class = "^(org\\.quickshell)$", title = "^(backstory)$" }

o.window(BACKSTORY, {
  float = true,
  size = { 380, 640 },
  move = { "(monitor_w-window_w-20)", "(monitor_h*0.04)" },
  -- No Hyprland window animation, as for Omarchy's own panels
  -- (apps/omarchy-shell.lua); Panel.qml fades the card in itself, as they do.
  no_anim = true,
  -- No shadow either: Omarchy's panels have no Hyprland decoration, and without
  -- the close animation a theme's shadow (a focus glow) stayed on screen.
  no_shadow = true,
})

-- Keybind: open the This Week window, focus it (bringing it to this workspace)
-- when open elsewhere, close it when it has focus. That is Panel.qml's own
-- toggle, over its IPC target; the shell's `shell toggle` would hide an open
-- window without asking it. With the window not loaded the target is missing,
-- so the bind opens it through the shell. A click on the bar widget opens its
-- own popup.
-- Change BACKSTORY_BIND to taste; `hl` is Hyprland's own Lua global.
local BACKSTORY_BIND = "CTRL + SHIFT + B"
hl.bind(BACKSTORY_BIND, hl.dsp.exec_cmd("omarchy-shell backstory.this-week toggle >/dev/null 2>&1 || omarchy-shell shell summon backstory.this-week '{}'"), { description = "Backstory This Week" })
