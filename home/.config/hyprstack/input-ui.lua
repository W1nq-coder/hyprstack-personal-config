-- Mouse and touchpad settings from Settings → Mouse & touchpad.
-- Loaded from hypr-vars.lua (before the shell's own config) and applied once the
-- whole config has loaded, so these values win over hyprland/input.lua and local.lua.
--
--   ~/.config/hyprstack/input.json                 settings (written by Settings)
--   ~/.local/state/hyprstack/input-devices.json    known devices, external mouse flag (shell)
--   ~/.local/state/hyprstack/input-baseline.json   values from the config files, for Settings
--
-- Settings calls `hyprctl eval "hyprstack_input.apply()"` after a change; removing a
-- value needs `hyprctl reload`, because hl.device() only adds to a device's config.
-- Delete input.json (or the hook lines in hypr-vars.lua) to drop all of it.
local home = os.getenv("HOME")
local config = os.getenv("XDG_CONFIG_HOME") or home .. "/.config"
local state = os.getenv("XDG_STATE_HOME") or home .. "/.local/state"
local json = require("utils.json")

local function read_json(path)
    local file = io.open(path, "r")
    if not file then return {} end
    local text = file:read("*a")
    file:close()
    local ok, data = pcall(json.decode, text)
    return ok and type(data) == "table" and data or {}
end

local function write(path, text)
    local file = io.open(path, "w")
    if file then
        file:write(text)
        file:close()
    end
end

local function tbl(value)
    return type(value) == "table" and value or {}
end

-- Pointer options that Hyprland only has globally (input.*), not under input.touchpad.
local GENERIC = { "sensitivity", "accel_profile", "left_handed" }
local MOUSE_GLOBAL = { "sensitivity", "accel_profile", "left_handed", "natural_scroll", "scroll_factor" }
local MOUSE_DEVICE = { "sensitivity", "accel_profile", "left_handed", "natural_scroll", "scroll_factor",
    "middle_button_emulation" }
local TOUCHPAD_GLOBAL = { "disable_while_typing", "natural_scroll", "scroll_factor", "tap_to_click", "tap_and_drag",
    "drag_lock", "clickfinger_behavior", "tap_button_map", "middle_button_emulation" }
local TOUCHPAD_DEVICE = { "enabled", "sensitivity", "accel_profile", "left_handed", "scroll_method",
    "disable_while_typing", "natural_scroll", "scroll_factor", "tap_to_click", "tap_and_drag", "drag_lock",
    "clickfinger_behavior", "tap_button_map", "middle_button_emulation" }

local function pick(keys, ...)
    local sources, out, any = { ... }, {}, false
    for _, key in ipairs(keys) do
        for _, source in ipairs(sources) do
            if source[key] ~= nil then
                out[key] = source[key]
                any = true
                break
            end
        end
    end
    return out, any
end

-- Values of the config files, captured before anything here changes them.
local baseline
local function capture_baseline()
    local get = function(key)
        local ok, value = pcall(hl.get_config, key)
        if ok then return value end
        return nil
    end
    baseline = { input = {}, touchpad = {}, gestures = {} }
    for _, key in ipairs({ "sensitivity", "accel_profile", "left_handed", "natural_scroll", "scroll_factor",
        "scroll_method" }) do
        baseline.input[key] = get("input." .. key)
    end
    for _, key in ipairs(TOUCHPAD_GLOBAL) do
        baseline.touchpad[key] = get("input.touchpad." .. key)
    end
    baseline.gestures.invert = get("gestures.workspace_swipe_invert")
    baseline.gestures.distance = get("gestures.workspace_swipe_distance")
    local ok, encoded = pcall(json.encode, baseline)
    if ok then write(state .. "/hyprstack/input-baseline.json", encoded) end
end

-- The workspace swipe is created by the shell (gestures.lua, layouts.lua). Remember
-- what the shell wants and only let it through while the gesture is enabled.
local real_gesture = hyprstack_input_real_gesture or hl.gesture
hyprstack_input_real_gesture = real_gesture
local shell_swipe -- last workspace-swipe spec requested by the shell
local swipe_enabled = true

local function is_swipe(spec)
    return type(spec) == "table" and spec.direction == "vertical"
        and (spec.action == "workspace" or spec.action == "unset")
        and spec.fingers == require("variables").workspaceSwipeFingers
end

hl.gesture = function(spec)
    if is_swipe(spec) then
        shell_swipe = spec
        if not swipe_enabled and spec.action == "workspace" then
            return real_gesture({ fingers = spec.fingers, direction = spec.direction, action = "unset" })
        end
    end
    return real_gesture(spec)
end

hyprstack_input = {}

function hyprstack_input.apply()
    if not baseline then capture_baseline() end
    local data = read_json(config .. "/hyprstack/input.json")
    local devices = read_json(state .. "/hyprstack/input-devices.json")
    local mouse, touchpad, gestures = tbl(data.mouse), tbl(data.touchpad), tbl(data.gestures)
    local mouse_all, touchpad_all = tbl(mouse.all), tbl(touchpad.all)

    -- "All devices": global options.
    local input, any = pick(MOUSE_GLOBAL, mouse_all)
    local tp_global, tp_any = pick(TOUCHPAD_GLOBAL, touchpad_all)
    if tp_any then input.touchpad = tp_global end
    if any or tp_any then hl.config({ input = input }) end

    local external = devices.external == true and touchpad.auto_disable == true
    for _, device in ipairs(tbl(devices.devices)) do
        if type(device) == "table" and type(device.name) == "string" then
            if device.type == "touchpad" then
                local own = tbl(tbl(touchpad.devices)[device.name])
                local spec = pick(TOUCHPAD_DEVICE, own, touchpad_all)
                -- Global pointer options set for mice must not reach the touchpad.
                for _, key in ipairs(GENERIC) do
                    if spec[key] == nil and mouse_all[key] ~= nil then spec[key] = baseline.input[key] end
                end
                local enabled = spec.enabled ~= false
                spec.enabled = enabled and not external
                spec.name = device.name
                hl.device(spec)
            elseif device.type == "mouse" then
                local own = tbl(tbl(mouse.devices)[device.name])
                local spec, has = pick(MOUSE_DEVICE, own, { middle_button_emulation = mouse_all.middle_button_emulation })
                if has then
                    spec.name = device.name
                    hl.device(spec)
                end
            end
        end
    end

    -- Workspace swipe
    local gesture_config = {}
    if gestures.invert ~= nil then gesture_config.workspace_swipe_invert = gestures.invert end
    if gestures.distance ~= nil then gesture_config.workspace_swipe_distance = gestures.distance end
    if next(gesture_config) then hl.config({ gestures = gesture_config }) end
    local enabled = gestures.enabled ~= false
    if enabled ~= swipe_enabled then
        swipe_enabled = enabled
        if shell_swipe then
            real_gesture({ fingers = shell_swipe.fingers, direction = shell_swipe.direction,
                action = enabled and shell_swipe.action or "unset" })
        end
    end
end

-- Respect a disabled swipe from the very first gesture call of this load.
swipe_enabled = tbl(read_json(config .. "/hyprstack/input.json").gestures).enabled ~= false

hl.timer(function()
    local ok, err = pcall(hyprstack_input.apply)
    if not ok then print("hyprstack: input settings: " .. tostring(err)) end
end, { timeout = 1, type = "oneshot" })
