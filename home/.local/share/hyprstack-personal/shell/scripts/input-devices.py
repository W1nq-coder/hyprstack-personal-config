#!/usr/bin/env python3
"""Pointer devices for Settings → Mouse & touchpad.

Combines `hyprctl devices -j` (Hyprland device names) with udev (device type),
so no root access or libinput tool is needed. Prints and also stores in
~/.local/state/hyprstack/input-devices.json (read by ~/.config/hyprstack/input-ui.lua):

  {"devices": [{"name", "label", "type": "mouse"|"touchpad", "companion", "external"}],
   "external": true if a real external mouse is connected}

"companion" marks the mouse interface that many touchpads also expose (same HID
device); it is not an external mouse.
"""
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

STATE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "hyprstack"
TARGET = STATE / "input-devices.json"


def hypr_name(name):
    # Hyprland: libinput name, lower case, spaces → "-".
    return re.sub(r"\s+", "-", name.strip().lower())


def udev_props(sys_path):
    try:
        out = subprocess.run(["udevadm", "info", "-q", "property", "-p", str(sys_path)],
                             capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return {}
    return dict(line.split("=", 1) for line in out.splitlines() if "=" in line)


def sysfs_devices():
    """hyprland-style name → {label, touchpad, mouse, parent, virtual}"""
    found = {}
    for event in sorted(Path("/sys/class/input").glob("event*")):
        try:
            label = (event / "device/name").read_text().strip()
            real = (event / "device").resolve()
        except OSError:
            continue
        props = udev_props(event)
        found.setdefault(hypr_name(label), {
            "label": label,
            "touchpad": props.get("ID_INPUT_TOUCHPAD") == "1",
            "mouse": props.get("ID_INPUT_MOUSE") == "1" or props.get("ID_INPUT_POINTINGSTICK") == "1",
            "parent": str(real.parent),
            "virtual": "/devices/virtual/" in str(real),
        })
    return found


def collect():
    try:
        mice = json.loads(subprocess.run(["hyprctl", "devices", "-j"], capture_output=True, text=True,
                                         timeout=5).stdout).get("mice", [])
    except (OSError, ValueError, subprocess.SubprocessError):
        mice = []
    info = sysfs_devices()
    devices = []
    for mouse in mice:
        name = mouse.get("name", "")
        # Hyprland adds "-1", "-2" … to repeated names.
        base = info.get(name) or info.get(re.sub(r"-\d+$", "", name)) or {}
        is_touchpad = base.get("touchpad", False) or name.endswith("-touchpad")
        devices.append({"name": name, "label": base.get("label", name), "type": "touchpad" if is_touchpad else "mouse",
                        "parent": base.get("parent", ""), "virtual": base.get("virtual", False)})
    touchpad_parents = {d["parent"] for d in devices if d["type"] == "touchpad" and d["parent"]}
    touchpad_prefixes = {d["name"].rsplit("-", 1)[0] for d in devices if d["type"] == "touchpad"}
    for d in devices:
        d["companion"] = d["type"] == "mouse" and (d["parent"] in touchpad_parents
                                                   or d["name"].rsplit("-", 1)[0] in touchpad_prefixes)
        d["external"] = d["type"] == "mouse" and not d["companion"] and not d["virtual"]
        del d["parent"], d["virtual"]
    return {"devices": devices, "external": any(d["external"] for d in devices)}


def main():
    data = collect()
    text = json.dumps(data, ensure_ascii=False)
    STATE.mkdir(parents=True, exist_ok=True)
    try:
        old = TARGET.read_text()
    except OSError:
        old = None
    if old != text:
        fd, tmp = tempfile.mkstemp(prefix=".input-devices.", dir=STATE)
        with os.fdopen(fd, "w") as stream:
            stream.write(text)
        os.replace(tmp, TARGET)
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
