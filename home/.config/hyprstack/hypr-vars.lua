-- HyperStack variables with the hyprstack-personal-config additions.
-- Your own variables live in vars.lua (a file that returns a table, like the
-- stock hypr-vars.lua); this file only adds the Settings hooks on top.
local config = (os.getenv("XDG_CONFIG_HOME") or os.getenv("HOME") .. "/.config") .. "/hyprstack"

local vars = {}
local vars_ok, loaded = pcall(dofile, config .. "/vars.lua")
if vars_ok and type(loaded) == "table" then
    vars = loaded
elseif io.open(config .. "/vars.lua") then
    print("hyprstack: vars.lua: " .. tostring(loaded))
end

-- Mouse & touchpad settings from Settings (input.json). Remove these lines to ignore them.
local input_ui = config .. "/input-ui.lua"
local input_ok, input_err = pcall(dofile, input_ui)
if not input_ok and io.open(input_ui) then print("hyprstack: " .. tostring(input_err)) end

-- Shortcuts changed in Settings → Keyboard shortcuts (keybinds.json).
-- Remove these lines to ignore them; the variables above are used unchanged then.
local ok, apply = pcall(dofile, config .. "/keybinds-ui.lua")
if ok and type(apply) == "function" then
    local applied, result = pcall(apply, vars)
    if applied and type(result) == "table" then return result end
end
return vars
