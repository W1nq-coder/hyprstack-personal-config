-- Local settings (preserved on HyperStack updates).
local home = os.getenv("HOME")
local config = os.getenv("XDG_CONFIG_HOME") or home .. "/.config"

-- NVIDIA (GeForce RTX 5060): environment for Wayland/GBM and VA-API.
hl.env("GBM_BACKEND", "nvidia-drm")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("NVD_BACKEND", "direct")

-- Keyboard: US + Russian, switch with Alt+Shift (from hyprstack-personal-config).
hl.config({ input = { kb_layout = "us,ru", kb_options = "grp:alt_shift_toggle",
    numlock_by_default = true, accel_profile = "flat" } })

-- Personal NVIDIA frame scheduler setting (hyprstack-personal-config).
hl.config({ render = { new_render_scheduling = false } })

-- Voice input, night light, screenshots and the power key menu (hyprstack-personal-config).
dofile(config .. "/hyprstack/extras.lua")
