#!/usr/bin/env python3
"""Save keyboard shortcut edits from Settings and apply them to Hyprland.

Usage: keybinds-apply.py '{"slots": {"<submap>\t<description>\t<chord id>": ["SUPER + T"]},
                            "custom": [{"id": "…", "chord": "SUPER + D", "name": "Discord",
                                        "icon": "discord", "command": "discord"}]}'

A slot is one bind as the shell creates it (see ~/.config/hyprstack/keybinds-ui.lua);
its value lists the chords to use instead ([] = no shortcut).
"custom" lists shortcuts added in Settings; keybinds-ui.lua binds each one to
exec_cmd(command). Without "custom" in the payload the stored list is kept.

Validates every shortcut, backs up keybinds.json to keybinds.json.bak, writes
the new file atomically, runs `hyprctl reload` and checks `hyprctl configerrors`.
New config errors restore the backup and reload again. Exit code 0 on success;
otherwise the reason is printed to stderr.
"""
import ctypes
import ctypes.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "hyprstack"
TARGET = CONFIG / "keybinds.json"
BACKUP = CONFIG / "keybinds.json.bak"
MODIFIERS = {"SUPER", "WIN", "LOGO", "MOD4", "META", "CTRL", "CONTROL", "ALT", "MOD1", "SHIFT",
             "CAPS", "MOD2", "MOD3", "MOD5"}
SLOT = re.compile(r"^[^\t\n]*\t[^\t\n]+\t[^\t\n]*\|[^\t\n]+$")
CUSTOM_ID = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
SPECIAL_KEY = re.compile(r"^(mouse:\d+|mouse_(up|down|left|right)|code:\d+)$")


def fail(message, code=1):
    print(message, file=sys.stderr)
    sys.exit(code)


def keysym_checker():
    path = ctypes.util.find_library("xkbcommon")
    if not path:
        return None
    lib = ctypes.CDLL(path)
    lib.xkb_keysym_from_name.argtypes = [ctypes.c_char_p, ctypes.c_int]
    lib.xkb_keysym_from_name.restype = ctypes.c_uint32
    # XKB_KEYSYM_CASE_INSENSITIVE = 1, matching how Hyprland resolves key names.
    return lambda name: lib.xkb_keysym_from_name(name.encode(), 1) != 0


def validate_chord(chord, is_keysym):
    if not isinstance(chord, str) or not chord.strip():
        raise ValueError("Пустое сочетание клавиш")
    if any(ch in chord for ch in "\"'\\\n\r\t,"):
        raise ValueError("Недопустимые символы в сочетании: " + chord)
    parts = [part.strip() for part in chord.split("+")]
    if any(not part for part in parts):
        raise ValueError("Некорректное сочетание: " + chord)
    *mods, key = parts
    for mod in mods:
        if mod.upper() not in MODIFIERS:
            raise ValueError("Неизвестный модификатор «" + mod + "» в " + chord)
    if key.upper() in MODIFIERS:
        raise ValueError("Нет основной клавиши: " + chord)
    if not SPECIAL_KEY.match(key) and is_keysym and not is_keysym(key):
        raise ValueError("Неизвестная клавиша «" + key + "» в " + chord)


def chord_id(chord):
    *mods, key = [part.strip() for part in chord.split("+")]
    aliases = {"WIN": "SUPER", "LOGO": "SUPER", "MOD4": "SUPER", "META": "SUPER", "CONTROL": "CTRL", "MOD1": "ALT"}
    return "+".join(sorted({aliases.get(m.upper(), m.upper()) for m in mods})) + "|" + key.lower()


def validate_custom(items, is_keysym):
    if not isinstance(items, list):
        raise ValueError("Ожидался список custom")
    result, by_id, by_chord = [], {}, {}
    for item in items:
        if not isinstance(item, dict):
            raise ValueError("Недопустимая запись в custom")
        ident = item.get("id")
        if not isinstance(ident, str) or not CUSTOM_ID.match(ident):
            raise ValueError("Недопустимый идентификатор сочетания: " + str(ident))
        command = item.get("command")
        if not isinstance(command, str) or not command.strip():
            raise ValueError("Пустая команда")
        if any(ch in command for ch in "\n\r\0"):
            raise ValueError("Команда должна быть одной строкой")
        validate_chord(item.get("chord"), is_keysym)
        name = item.get("name") if isinstance(item.get("name"), str) else ""
        name = name.strip() or command.split()[0].rsplit("/", 1)[-1]
        if any(ch in name for ch in "\n\r\t\0") or len(name) > 120:
            raise ValueError("Недопустимое название: " + name)
        icon = item.get("icon") if isinstance(item.get("icon"), str) else ""
        clean = {"id": ident, "chord": item["chord"].strip(), "name": name,
                 "icon": icon.strip(), "command": command.strip()}
        cid = chord_id(clean["chord"])
        if ident in by_id:  # same id saved twice: keep the newest values
            result[by_id[ident]] = clean
            continue
        if cid in by_chord:
            twin = result[by_chord[cid]]
            if twin["command"] == clean["command"]:
                continue  # identical shortcut, do not store it twice
            raise ValueError("Сочетание " + clean["chord"] + " уже назначено на «" + twin["name"] + "»")
        by_id[ident] = len(result)
        by_chord[cid] = len(result)
        result.append(clean)
    return result


def validate(payload):
    slots = payload.get("slots")
    if not isinstance(slots, dict):
        raise ValueError("Ожидался объект slots")
    is_keysym = keysym_checker()
    for name, value in slots.items():
        if not SLOT.match(name):
            raise ValueError("Недопустимый идентификатор сочетания: " + name.replace("\t", " · "))
        if not isinstance(value, list):
            raise ValueError("Недопустимое значение для " + name.replace("\t", " · "))
        for chord in value:
            validate_chord(chord, is_keysym)
    custom = payload.get("custom")
    if custom is None:
        custom = stored_custom()
    return slots, validate_custom(custom, is_keysym)


def stored_custom():
    try:
        data = json.loads(TARGET.read_text())
    except (OSError, ValueError):
        return []
    custom = data.get("custom") if isinstance(data, dict) else None
    return custom if isinstance(custom, list) else []


def config_errors():
    result = subprocess.run(["hyprctl", "configerrors"], capture_output=True, text=True, timeout=10)
    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    return {line for line in lines if line.lower() not in ("no errors", "ok")}


def reload():
    result = subprocess.run(["hyprctl", "reload"], capture_output=True, text=True, timeout=20)
    time.sleep(0.4)
    return result.returncode == 0


def write_atomic(data):
    CONFIG.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".keybinds.", suffix=".json", dir=CONFIG)
    with os.fdopen(fd, "w") as stream:
        json.dump(data, stream, indent=4, ensure_ascii=False, sort_keys=True)
        stream.write("\n")
    os.chmod(tmp, 0o600)
    os.replace(tmp, TARGET)


def main():
    if len(sys.argv) != 2:
        fail("Usage: keybinds-apply.py JSON")
    try:
        slots, custom = validate(json.loads(sys.argv[1]))
    except (ValueError, AttributeError, json.JSONDecodeError) as error:
        fail(str(error))

    had_file = TARGET.exists()
    if had_file:
        shutil.copy2(TARGET, BACKUP)
    before = config_errors()
    data = {"version": 2, "slots": slots}
    if custom:
        data["custom"] = custom
    write_atomic(data)

    ok = reload()
    new_errors = config_errors() - before
    if ok and not new_errors:
        return 0

    # Roll back to the previous state.
    if had_file:
        shutil.copy2(BACKUP, TARGET)
    else:
        TARGET.unlink(missing_ok=True)
    reload()
    fail("Конфигурация Hyprland отклонила изменение, восстановлено прежнее состояние:\n"
         + "\n".join(sorted(new_errors) or ["hyprctl reload завершился с ошибкой"]), 2)


if __name__ == "__main__":
    sys.exit(main())
