-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")

-- Open Codex desktop instead of the default ChatGPT webapp.
hl.unbind("SUPER + SHIFT + A")
o.bind("SUPER + SHIFT + A", "Codex desktop", { launch = "codex-desktop" })

-- Make Super+F maximize the window while keeping the top bar visible.
hl.unbind("SUPER + F")
o.bind("SUPER + F", "Full width", hl.dsp.window.fullscreen({ mode = "maximized" }))

-- Bring selected workspaces to the current monitor instead of changing screens.
for workspace = 1, 10 do
  local key = "SUPER + code:" .. tostring(workspace + 9)
  hl.unbind(key)
  o.bind(key, "Switch to workspace " .. workspace .. " on current monitor",
    hl.dsp.focus({ workspace = tostring(workspace), on_current_monitor = true }))
end

for _, binding in ipairs({
  { "SUPER + TAB", "e+1", "Next workspace on current monitor" },
  { "SUPER + SHIFT + TAB", "e-1", "Previous workspace on current monitor" },
  { "SUPER + CTRL + TAB", "previous", "Former workspace on current monitor" },
  { "SUPER + mouse_down", "e+1", "Scroll workspace forward on current monitor" },
  { "SUPER + mouse_up", "e-1", "Scroll workspace backward on current monitor" },
}) do
  hl.unbind(binding[1])
  o.bind(binding[1], binding[3],
    hl.dsp.focus({ workspace = binding[2], on_current_monitor = true }))
end
