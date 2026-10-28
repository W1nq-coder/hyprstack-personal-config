-- hyprstack-personal-config: voice input, night light and the power key menu.
-- Loaded from local.lua: dofile(config .. "/hyprstack/extras.lua")
local home = os.getenv("HOME")

-- Power key opens the HyperStack session menu (logind: HandlePowerKey=ignore)
-- The key is the kbPowerMenu variable, editable in Settings → Keyboard shortcuts.
local power_keys = require("variables").kbPowerMenu
if power_keys == nil then power_keys = "XF86PowerOff" end
for _, key in ipairs(type(power_keys) == "table" and power_keys or { power_keys }) do
    if type(key) == "string" and key:match("%S") then
        hl.bind(key, hl.dsp.global("hyprstack:session"), { description = "Session: Open session menu" })
    end
end

-- Voice input (~/.local/bin/dictation). Two binds on one chord, press and
-- release; the script picks the behaviour from MODE in
-- ~/.config/hyprstack-dictation/config (toggle: release does nothing).
-- The same description makes them one entry in Settings → Keyboard shortcuts,
-- where the chord can be changed with the pencil.
local dictation = home .. "/.local/bin/dictation"
hl.bind("SUPER + SHIFT + D", hl.dsp.exec_cmd(dictation .. " press"), { description = "Shell: Voice input" })
hl.bind("SUPER + SHIFT + D", hl.dsp.exec_cmd(dictation .. " release"),
    { release = true, description = "Shell: Voice input" })

-- Night light (~/.local/bin/nightlight, hyprsunset). Settings: Settings → Night light
-- or ~/.config/hyprstack/nightlight.json. The chords are editable in Settings →
-- Keyboard shortcuts.
local nightlight = home .. "/.local/bin/nightlight"
hl.on("hyprland.start", function()
    hl.exec_cmd(nightlight .. " apply")
end)
hl.bind("SUPER + SHIFT + N", hl.dsp.exec_cmd(nightlight .. " toggle --notify"), { description = "Shell: Night light" })
hl.bind("SUPER + ALT + equal", hl.dsp.exec_cmd(nightlight .. " warmer --notify"),
    { repeating = true, description = "Shell: Night light warmer" })
hl.bind("SUPER + ALT + minus", hl.dsp.exec_cmd(nightlight .. " cooler --notify"),
    { repeating = true, description = "Shell: Night light cooler" })

-- Screenshots like Omarchy (~/.local/bin/screenshot): Print selects an area (click a window
-- to take the whole window) and opens it in Satty (Enter = copy + save); Shift+Print copies
-- and saves the area at once. HyperStack's own full-monitor screenshot is moved to Ctrl+Print
-- in Settings → Keyboard shortcuts.
local screenshot = home .. "/.local/bin/screenshot"
hl.bind("Print", hl.dsp.exec_cmd(screenshot .. " edit"), { description = "Capture: Screenshot area with editor" })
hl.bind("SHIFT + Print", hl.dsp.exec_cmd(screenshot .. " region"), { description = "Capture: Screenshot area to clipboard" })
hl.window_rule({ name = "screenshot-satty", match = { class = "^(com\\.gabm\\.satty)$" }, float = true, center = true })
