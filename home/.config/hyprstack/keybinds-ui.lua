-- Keyboard shortcuts edited in Settings → Keyboard shortcuts.
-- Loaded from hypr-vars.lua, i.e. before the shell creates any bind.
--
-- Every bind is identified by a "slot": submap + description + its original
-- chord. keybinds.json maps slots to new chords. hl.bind/hl.unbind are wrapped
-- so the shell's own action is bound to the new chord instead of the original
-- one; no action is copied here. Without edits every call passes through as is.
-- Delete keybinds.json (or these hook lines in hypr-vars.lua) to drop all edits.
local home = os.getenv("HOME")
local config = os.getenv("XDG_CONFIG_HOME") or home .. "/.config"
local state = os.getenv("XDG_STATE_HOME") or home .. "/.local/state"
local json = require("utils.json")

local function read(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local text = file:read("*a")
    file:close()
    return text
end

local function write(path, text)
    if read(path) == text then return end
    local file = io.open(path, "w")
    if file then
        file:write(text)
        file:close()
    end
end

-- Must match normalise() in the shell's services/Keybinds.js.
local MOD_ALIASES = { SUPER = "SUPER", WIN = "SUPER", LOGO = "SUPER", MOD4 = "SUPER", META = "SUPER",
    CTRL = "CTRL", CONTROL = "CTRL", ALT = "ALT", MOD1 = "ALT", SHIFT = "SHIFT", CAPS = "CAPS",
    MOD2 = "MOD2", MOD3 = "MOD3", MOD5 = "MOD5" }
local MOD_ORDER = { "SUPER", "CTRL", "ALT", "SHIFT", "CAPS", "MOD2", "MOD3", "MOD5" }

local function normalise(chord)
    local parts = {}
    for raw in tostring(chord):gmatch("[^+]+") do
        local part = raw:match("^%s*(.-)%s*$")
        if part ~= "" then parts[#parts + 1] = part end
    end
    local mods, key = {}, ""
    for i, part in ipairs(parts) do
        local alias = MOD_ALIASES[part:upper()]
        if alias and i < #parts then mods[alias] = true else key = part end
    end
    local ordered = {}
    for _, mod in ipairs(MOD_ORDER) do
        if mods[mod] then ordered[#ordered + 1] = mod end
    end
    return table.concat(ordered, "+") .. "|" .. key:lower()
end

local function slot_id(submap, description, chord)
    return submap .. "\t" .. description .. "\t" .. normalise(chord)
end

-- Edits: slot → list of chords ([] = no shortcut).
-- Custom: shortcuts added in Settings, {id, chord, name, icon, command} each.
local slots = {}
local custom = {}
do
    local text = read(config .. "/hyprstack/keybinds.json")
    local ok, data = pcall(json.decode, text or "")
    if ok and type(data) == "table" and type(data.custom) == "table" then
        for _, item in ipairs(data.custom) do
            if type(item) == "table" and type(item.chord) == "string" and item.chord:match("%S")
                and type(item.command) == "string" and item.command:match("%S") then
                custom[#custom + 1] = item
            end
        end
    end
    if ok and type(data) == "table" and type(data.slots) == "table" then
        for id, value in pairs(data.slots) do
            local list = type(value) == "string" and { value } or value
            local valid = type(id) == "string" and type(list) == "table"
            if valid then
                for _, chord in pairs(list) do
                    if type(chord) ~= "string" or not chord:match("%S") then valid = false end
                end
            end
            if valid then slots[id] = list end
        end
    end
end

-- Keep the original functions when the Lua state survives a reload.
local real = hyprstack_keyremap_real or { bind = hl.bind, unbind = hl.unbind, define_submap = hl.define_submap }
hyprstack_keyremap_real = real

local current_submap = ""
local bound = {}  -- live binds created through the wrapper: {slot, default, chord, action, opts, submap}
local seen = {}   -- every slot bound during this load, for Settings

hl.bind = function(key, action, opts)
    local description = type(opts) == "table" and opts.description or ""
    local id = slot_id(current_submap, description, key)
    local targets = slots[id] or { key }
    if #targets == 0 then -- "no shortcut": still report the slot so Settings can reset it
        seen[#seen + 1] = { slot = id, default = key, chord = "", submap = current_submap, description = description }
    end
    for _, chord in ipairs(targets) do
        real.bind(chord, action, opts)
        bound[#bound + 1] = { slot = id, default = key, chord = chord, action = action, opts = opts, submap = current_submap }
        seen[#seen + 1] = { slot = id, default = key, chord = chord, submap = current_submap, description = description }
    end
end

-- Unbinding the original chord also removes the shortcut moved away from it,
-- while shortcuts moved onto that chord from elsewhere are kept.
hl.unbind = function(key)
    local target = normalise(key)
    local chords = { { norm = target, chord = key } }
    for _, entry in ipairs(bound) do
        if entry.submap == current_submap and normalise(entry.default) == target then
            local norm = normalise(entry.chord)
            local known = false
            for _, item in ipairs(chords) do
                if item.norm == norm then known = true end
            end
            if not known then chords[#chords + 1] = { norm = norm, chord = entry.chord } end
        end
    end
    for _, item in ipairs(chords) do
        local survivors, rest = {}, {}
        for _, entry in ipairs(bound) do
            if entry.submap == current_submap and normalise(entry.chord) == item.norm then
                if normalise(entry.default) ~= target then survivors[#survivors + 1] = entry end
            else
                rest[#rest + 1] = entry
            end
        end
        bound = rest
        real.unbind(item.chord)
        for _, entry in ipairs(survivors) do
            real.bind(entry.chord, entry.action, entry.opts)
            bound[#bound + 1] = entry
        end
    end
end

hl.define_submap = function(name, fn)
    return real.define_submap(name, function(...)
        local previous = current_submap
        current_submap = name
        local ok, err = pcall(fn, ...)
        current_submap = previous
        if not ok then error(err, 0) end
    end)
end

-- Empty submap used while Settings records a new shortcut, so pressing a
-- bound chord reaches the window instead of running its action.
-- Hyprland only registers a submap with at least one bind. Plain Escape still
-- reaches the window (non_consuming) and also leaves the submap on its own.
hl.define_submap("hyprstack-keyrecord", function()
    hl.bind("Escape", function() hl.dispatch(hl.dsp.submap("reset")) end,
        { non_consuming = true, description = "Shell: Cancel shortcut recording" })
end)
hyprstack_keyrecord = hyprstack_keyrecord or {}
local generation = 0
function hyprstack_keyrecord.start()
    generation = generation + 1
    local mine = generation
    hl.dispatch(hl.dsp.submap("hyprstack-keyrecord"))
    hl.timer(function()
        if mine == generation then hl.dispatch(hl.dsp.submap("reset")) end
    end, { timeout = 20000, type = "oneshot" })
end
function hyprstack_keyrecord.stop()
    generation = generation + 1
    hl.dispatch(hl.dsp.submap("reset"))
end

-- Custom shortcuts are bound once the whole config (including layouts.lua, which
-- unbinds some chords) has loaded, so nothing later removes them. They run the
-- command like the shell's own app shortcuts: exec_cmd, i.e. `sh -c command`.
hl.timer(function()
    for _, item in ipairs(custom) do
        local name = type(item.name) == "string" and item.name:match("%S") and item.name or item.command
        local ok, err = pcall(real.bind, item.chord, hl.dsp.exec_cmd(item.command), { description = "Custom: " .. name })
        if not ok then print("hyprstack: custom shortcut " .. item.chord .. ": " .. tostring(err)) end
    end
end, { timeout = 1, type = "oneshot" })

-- After the whole config is loaded, tell Settings which slot each bind belongs to.
hl.timer(function()
    local out = {}
    for _, entry in ipairs(seen) do
        out[#out + 1] = { slot = entry.slot, default = entry.default, chord = entry.chord,
            submap = entry.submap, description = entry.description }
    end
    local ok, encoded = pcall(json.encode, out)
    if ok then write(state .. "/hyprstack/keybind-slots.json", encoded) end
end, { timeout = 50, type = "oneshot" })

-- Personal shortcut variables that are not part of the shell's variables.lua.
local extra_defaults = { kbPowerMenu = "XF86PowerOff" }

return function(user_vars)
    local result = {}
    for key, value in pairs(user_vars) do result[key] = value end
    for key, value in pairs(extra_defaults) do
        if result[key] == nil then result[key] = value end
    end
    return result
end
