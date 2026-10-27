#!/usr/bin/env python3
"""List installed applications for Settings → Keyboard shortcuts → Add shortcut.

Reads .desktop files from ~/.local/share/applications, the flatpak export
directories and $XDG_DATA_DIRS (default /usr/local/share:/usr/share), the first
one found wins for each desktop id, like the XDG spec says.

Prints a JSON list: [{id, name, comment, icon, command}], sorted by name.
`command` is the Exec line without field codes (%u, %F, …), re-quoted for
`sh -c` (which is how Hyprland runs exec_cmd). Terminal=true apps are wrapped
in the terminal given with --terminal (default: kitty -e).
"""
import json
import os
import re
import shlex
import shutil
import sys
from pathlib import Path

FIELD_CODES = set("fFuUdDnNickvm")


def data_dirs():
    home = Path.home()
    user = Path(os.environ.get("XDG_DATA_HOME") or home / ".local/share")
    system = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    dirs = [user, user / "flatpak/exports/share", Path("/var/lib/flatpak/exports/share")]
    dirs += [Path(p) for p in system.split(":") if p]
    seen, result = set(), []
    for d in dirs:
        app = d / "applications"
        if app not in seen:
            seen.add(app)
            result.append(app)
    return result


def unescape_value(value):
    # String-level escapes of the desktop entry spec.
    out, i = [], 0
    while i < len(value):
        ch = value[i]
        if ch == "\\" and i + 1 < len(value):
            nxt = value[i + 1]
            out.append({"s": " ", "n": "\n", "t": "\t", "r": "\r", "\\": "\\"}.get(nxt, "\\" + nxt))
            i += 2
        else:
            out.append(ch)
            i += 1
    return "".join(out)


def parse_entry(path):
    group, values = None, {}
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("["):
            group = line.strip("[]")
            continue
        if group != "Desktop Entry" or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values.setdefault(key.strip(), value.strip())
    return values


def localized(values, key):
    lang = (os.environ.get("LC_MESSAGES") or os.environ.get("LC_ALL") or os.environ.get("LANG") or "").split(".")[0]
    for candidate in (lang, lang.split("_")[0]):
        if candidate and f"{key}[{candidate}]" in values:
            return unescape_value(values[f"{key}[{candidate}]"])
    return unescape_value(values.get(key, ""))


def split_exec(exec_line):
    """Exec value → argv, following the quoting rules of the spec."""
    args, cur, quoted, have, i = [], [], False, False, 0
    while i < len(exec_line):
        ch = exec_line[i]
        if quoted:
            if ch == "\\" and i + 1 < len(exec_line) and exec_line[i + 1] in '"`$\\':
                cur.append(exec_line[i + 1])
                i += 2
                continue
            if ch == '"':
                quoted = False
            else:
                cur.append(ch)
        elif ch == '"':
            quoted, have = True, True
        elif ch in " \t":
            if cur or have:
                args.append("".join(cur))
            cur, have = [], False
        else:
            cur.append(ch)
        i += 1
    if quoted:
        raise ValueError("unterminated quote")
    if cur or have:
        args.append("".join(cur))
    return args


def strip_field_codes(args):
    result = []
    for arg in args:
        if len(arg) == 2 and arg[0] == "%" and arg[1] in FIELD_CODES:
            continue  # standalone %u, %F, … are dropped entirely
        arg = re.sub(r"%(.)", lambda m: "%" if m.group(1) == "%" else "", arg)
        if arg:
            result.append(arg)
    return result


def command_for(values, terminal):
    args = strip_field_codes(split_exec(unescape_value(values.get("Exec", ""))))
    if not args:
        return ""
    if len(args) > 1 and args[-1] == "--":
        args.pop()  # separator that only preceded the dropped file/URL codes
    if values.get("Terminal", "").lower() == "true":
        args = terminal + args
    return shlex.join(args)


def shown(values, desktop):
    if values.get("Type") != "Application":
        return False
    if values.get("NoDisplay", "").lower() == "true" or values.get("Hidden", "").lower() == "true":
        return False
    only = [d for d in values.get("OnlyShowIn", "").split(";") if d]
    if only and not desktop & set(only):
        return False
    if desktop & set(d for d in values.get("NotShowIn", "").split(";") if d):
        return False
    try_exec = values.get("TryExec")
    if try_exec and not (os.path.isabs(try_exec) and os.access(try_exec, os.X_OK)) and not shutil.which(try_exec):
        return False
    return True


def main():
    terminal = ["kitty", "-e"]
    if len(sys.argv) == 3 and sys.argv[1] == "--terminal":
        terminal = shlex.split(sys.argv[2])
    desktop = set((os.environ.get("XDG_CURRENT_DESKTOP") or "Hyprland").split(":"))
    seen, apps = set(), []
    for directory in data_dirs():
        if not directory.is_dir():
            continue
        for path in sorted(directory.rglob("*.desktop")):
            app_id = str(path.relative_to(directory)).replace("/", "-")
            if app_id in seen:
                continue
            seen.add(app_id)  # a hidden user copy also hides the system one
            values = parse_entry(path)
            if not values or not shown(values, desktop):
                continue
            try:
                command = command_for(values, terminal)
            except ValueError:
                continue
            name = localized(values, "Name")
            if not command or not name:
                continue
            apps.append({"id": app_id[:-len(".desktop")], "name": name,
                         "comment": localized(values, "Comment") or localized(values, "GenericName"),
                         "icon": values.get("Icon", ""), "command": command})
    apps.sort(key=lambda a: a["name"].casefold())
    json.dump(apps, sys.stdout, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
