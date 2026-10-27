local home = os.getenv("HOME")
local config = os.getenv("XDG_CONFIG_HOME") or home .. "/.config"
hl.config({ input = { kb_layout = "us,ru", kb_options = "grp:alt_shift_toggle",
    numlock_by_default = true, accel_profile = "flat" } })
dofile(config .. "/hypr/display-tuning.lua")
local data = os.getenv("XDG_DATA_HOME") or home .. "/.local/share"
hl.env("HYPRSTACK_SHELL_DIR", data .. "/hyprstack-personal/shell")
-- Initialize the existing wallet and application autostart.
hl.on("hyprland.start", function()
    hl.exec_cmd(home .. "/.local/bin/caelestia-session-start")
end)

-- Preserve the current NVIDIA frame scheduler across release updates.
hl.config({ render = { new_render_scheduling = false } })

-- Personal messaging apps. With the current per-monitor banks, workspace 21
-- is HDMI-A-1's local workspace 1; workspace 2 belongs to the main DP-1.
-- Class rules also cover launchers whose child processes lose exec rules.
hl.window_rule({
    name = "personal-discord-workspace",
    match = { class = "(?i)^discord$" },
    workspace = "21 silent",
})
hl.window_rule({
    name = "personal-ayugram-workspace",
    match = { class = "^com\\.ayugram\\.desktop$" },
    workspace = "2 silent",
})

-- Start once per graphical login; a config reload does not restart the apps.
hl.on("hyprland.start", function()
    if os.getenv("HYPRSTACK_NESTED") == "1" then return end
    hl.exec_cmd("/usr/bin/discord", { workspace = "21 silent" })
    hl.exec_cmd(home .. "/.local/bin/AyuGram", { workspace = "2 silent" })
end)

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
