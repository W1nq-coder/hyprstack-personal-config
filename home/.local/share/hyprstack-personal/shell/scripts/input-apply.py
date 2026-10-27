#!/usr/bin/env python3
"""Save mouse & touchpad settings from Settings and apply them to Hyprland.

Usage: input-apply.py '<settings JSON>'   (the whole new content of input.json)
       input-apply.py --refresh           (re-apply, e.g. after a mouse was plugged in)

Every value is checked and clamped (unknown keys are rejected), input.json is
backed up to input.json.bak and replaced atomically. Changes are applied live with
`hyprctl eval "hyprstack_input.apply()"`; when a value was removed (reset) Hyprland
needs `hyprctl reload`, since a device config can only be added to at runtime.
Errors restore the previous file. Exit code 0 on success, reason on stderr otherwise.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "hyprstack"
TARGET = CONFIG / "input.json"
BACKUP = CONFIG / "input.json.bak"

BOOL = ("bool",)
POINTER = {
    "sensitivity": ("float", -1.0, 1.0),
    "accel_profile": ("enum", "flat", "adaptive"),
    "left_handed": BOOL,
    "natural_scroll": BOOL,
    "scroll_factor": ("float", 0.1, 3.0),
    "middle_button_emulation": BOOL,
}
TOUCHPAD = dict(POINTER, **{
    "enabled": BOOL,
    "disable_while_typing": BOOL,
    "tap_to_click": BOOL,
    "tap_and_drag": BOOL,
    "drag_lock": ("int", 0, 2),
    "clickfinger_behavior": BOOL,
    "tap_button_map": ("enum", "lrm", "lmr"),
    "scroll_method": ("enum", "2fg", "edge"),
})
GESTURES = {
    "enabled": BOOL,
    "invert": BOOL,
    "distance": ("int", 200, 1500),
}


def fail(message, code=1):
    print(message, file=sys.stderr)
    sys.exit(code)


def check(value, rule, where):
    kind = rule[0]
    if kind == "bool":
        if not isinstance(value, bool):
            raise ValueError(where + ": ожидалось да/нет")
        return value
    if kind == "enum":
        if value not in rule[1:]:
            raise ValueError(where + ": недопустимое значение " + repr(value))
        return value
    if isinstance(value, bool) or not isinstance(value, (int, float)) or value != value:
        raise ValueError(where + ": ожидалось число")
    value = min(rule[2], max(rule[1], value))
    return int(round(value)) if kind == "int" else round(float(value), 3)


def clean_options(options, rules, where):
    if options is None:
        return {}
    if not isinstance(options, dict):
        raise ValueError(where + ": ожидался объект")
    out = {}
    for key, value in options.items():
        if key not in rules:
            raise ValueError(where + ": неизвестная настройка " + key)
        if value is not None:
            out[key] = check(value, rules[key], where + "." + key)
    return out


def clean_section(section, rules, where, extra=None):
    section = section or {}
    if not isinstance(section, dict):
        raise ValueError(where + ": ожидался объект")
    out = {}
    options = clean_options(section.get("all"), rules, where + ".all")
    if options:
        out["all"] = options
    devices = section.get("devices") or {}
    if not isinstance(devices, dict):
        raise ValueError(where + ".devices: ожидался объект")
    kept = {}
    for name, value in devices.items():
        if not isinstance(name, str) or not name.strip() or any(c in name for c in "\n\r\0\"'\\"):
            raise ValueError(where + ": недопустимое имя устройства " + repr(name))
        options = clean_options(value, rules, where + "[" + name + "]")
        if options:
            kept[name] = options
    if kept:
        out["devices"] = kept
    for key, rule in (extra or {}).items():
        if section.get(key) is not None:
            out[key] = check(section[key], rule, where + "." + key)
    unknown = set(section) - {"all", "devices"} - set(extra or {})
    if unknown:
        raise ValueError(where + ": неизвестные поля " + ", ".join(sorted(unknown)))
    return out


def validate(data):
    if not isinstance(data, dict):
        raise ValueError("Ожидался объект настроек")
    unknown = set(data) - {"version", "mouse", "touchpad", "gestures"}
    if unknown:
        raise ValueError("Неизвестные поля: " + ", ".join(sorted(unknown)))
    out = {"version": 1}
    mouse = clean_section(data.get("mouse"), POINTER, "mouse")
    touchpad = clean_section(data.get("touchpad"), TOUCHPAD, "touchpad", {"auto_disable": BOOL})
    gestures = clean_options(data.get("gestures"), GESTURES, "gestures")
    if mouse:
        out["mouse"] = mouse
    if touchpad:
        out["touchpad"] = touchpad
    if gestures:
        out["gestures"] = gestures
    return out


def leaves(data, prefix=""):
    if isinstance(data, dict):
        result = set()
        for key, value in data.items():
            result |= leaves(value, prefix + "/" + key)
        return result
    return {prefix}


def hyprctl(*args):
    result = subprocess.run(["hyprctl", *args], capture_output=True, text=True, timeout=20)
    return result.returncode, (result.stdout + result.stderr).strip()


def hook_loaded():
    code, out = hyprctl("eval", "assert(hyprstack_input and hyprstack_input.apply)")
    return code == 0 and out == "ok"


def apply(reload_needed):
    if reload_needed or not hook_loaded():
        code, out = hyprctl("reload")
        time.sleep(0.3)
        if code != 0 or "error" in out.lower():
            return out or "hyprctl reload завершился с ошибкой"
        if not hook_loaded():
            return "Хук input-ui.lua не загружен (проверьте ~/.config/hyprstack/hypr-vars.lua)"
        return None
    code, out = hyprctl("eval", "hyprstack_input.apply()")
    return None if code == 0 and out == "ok" else out or "hyprctl eval завершился с ошибкой"


def write_atomic(data):
    CONFIG.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".input.", suffix=".json", dir=CONFIG)
    with os.fdopen(fd, "w") as stream:
        json.dump(data, stream, indent=4, ensure_ascii=False, sort_keys=True)
        stream.write("\n")
    os.chmod(tmp, 0o600)
    os.replace(tmp, TARGET)


def main():
    if len(sys.argv) != 2:
        fail("Usage: input-apply.py JSON | --refresh")
    if sys.argv[1] == "--refresh":
        error = apply(False)
        if error:
            fail(error, 2)
        return 0
    try:
        new = validate(json.loads(sys.argv[1]))
    except (ValueError, json.JSONDecodeError) as error:
        fail(str(error))

    had_file = TARGET.exists()
    try:
        old = json.loads(TARGET.read_text()) if had_file else {}
    except (OSError, ValueError):
        old = {}
    if old == new:
        return 0
    if had_file:
        shutil.copy2(TARGET, BACKUP)
    write_atomic(new)

    error = apply(bool(leaves(old) - leaves(new)))
    if not error:
        return 0
    if had_file:
        shutil.copy2(BACKUP, TARGET)
    else:
        TARGET.unlink(missing_ok=True)
    hyprctl("reload")
    fail("Hyprland не принял настройки, восстановлено прежнее состояние:\n" + error, 2)


if __name__ == "__main__":
    sys.exit(main())
