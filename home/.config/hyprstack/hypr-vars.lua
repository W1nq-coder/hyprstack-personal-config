local vars = {
    sleepGestureCmd = "true",
    terminal = "kitty",
    browser = "firefox",
    editor = "codium",
    fileExplorer = "thunar",
    audioSettings = "pwvucontrol",
    cursorTheme = "sweet-cursors",
    cursorSize = 24,
    kbTerminal = "SUPER + Return",
    kbLock = "CTRL + SUPER + L",
    kbShowPanels = "SUPER + ALT + K",
    blurEnabled = false,
    windowOpacity = 0.95,
}

-- Mouse & touchpad settings from Settings (input.json). Remove these lines to ignore them.
local input_ui = (os.getenv("XDG_CONFIG_HOME") or os.getenv("HOME") .. "/.config") .. "/hyprstack/input-ui.lua"
local input_ok, input_err = pcall(dofile, input_ui)
if not input_ok and io.open(input_ui) then print("hyprstack: " .. tostring(input_err)) end

-- Shortcuts changed in Settings → Keyboard shortcuts (keybinds.json).
-- Remove these lines to ignore them; the table above is used unchanged then.
local path = (os.getenv("XDG_CONFIG_HOME") or os.getenv("HOME") .. "/.config") .. "/hyprstack/keybinds-ui.lua"
local ok, apply = pcall(dofile, path)
if ok and type(apply) == "function" then
    local applied, result = pcall(apply, vars)
    if applied and type(result) == "table" then return result end
end
return vars
