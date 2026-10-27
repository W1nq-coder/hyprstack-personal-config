pragma Singleton

// Personal overlay: mouse & touchpad settings (Settings → Mouse & touchpad).
// Settings live in ~/.config/hyprstack/input.json and are applied by
// ~/.config/hyprstack/input-ui.lua (hooked from hypr-vars.lua). This service
// edits the file through scripts/input-apply.py, lists pointer devices with
// scripts/input-devices.py and watches udev, so the touchpad can be turned off
// while an external mouse is connected.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root

    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/hyprstack"
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/hyprstack"
    readonly property string applyScript: Quickshell.shellDir + "/scripts/input-apply.py"
    readonly property string devicesScript: Quickshell.shellDir + "/scripts/input-devices.py"

    property var settings: ({version: 1})
    property var baseline: ({input: {}, touchpad: {}, gestures: {}})
    property var devices: []
    property bool external
    readonly property var touchpads: devices.filter(d => d.type === "touchpad")
    readonly property var mice: devices.filter(d => d.type === "mouse" && !d.companion)
    readonly property bool saving: applier.running || saveTimer.running
    property string error
    property string lastDevices

    // Options Hyprland keeps only globally (input.*), shared by mice and touchpads.
    readonly property var generic: ["sensitivity", "accel_profile", "left_handed"]

    function section(name: string): var {
        return settings[name] ?? {};
    }

    function own(name: string, scope: string): var {
        const s = section(name);
        return (scope ? s.devices?.[scope] : s.all) ?? {};
    }

    function fallback(name: string, key: string): var {
        const input = baseline.input ?? {}, touchpad = baseline.touchpad ?? {};
        if (key === "enabled")
            return true;
        if (key === "middle_button_emulation" && name === "mouse")
            return false;
        if (key === "scroll_method")
            return input.scroll_method || "2fg";
        if (key === "tap_button_map")
            return touchpad.tap_button_map || "lrm";
        if (name === "mouse" || generic.includes(key))
            return input[key];
        return touchpad[key];
    }

    // Value shown for `key`: device → all devices → config files.
    function value(name: string, scope: string, key: string): var {
        const device = scope ? own(name, scope)[key] : undefined;
        if (device !== undefined)
            return device;
        const all = own(name, "")[key];
        return all !== undefined ? all : fallback(name, key);
    }

    function gesture(key: string): var {
        const g = settings.gestures ?? {};
        if (g[key] !== undefined)
            return g[key];
        if (key === "enabled")
            return true;
        return baseline.gestures?.[key];
    }

    function hasChanges(name: string, scope: string): bool {
        if (Object.keys(own(name, scope)).length)
            return true;
        if (name === "touchpad" && !scope)
            return Object.keys(settings.gestures ?? {}).length > 0 || section("touchpad").auto_disable !== undefined;
        return false;
    }

    function clone(): var {
        return JSON.parse(JSON.stringify(settings));
    }

    function set(name: string, scope: string, key: string, v: var): void {
        const next = clone();
        const s = next[name] = next[name] ?? {};
        if (scope) {
            s.devices = s.devices ?? {};
            s.devices[scope] = Object.assign({}, s.devices[scope] ?? {}, {[key]: v});
        } else {
            s.all = Object.assign({}, s.all ?? {}, {[key]: v});
        }
        update(next);
    }

    function setAutoDisable(v: bool): void {
        const next = clone();
        next.touchpad = Object.assign({}, next.touchpad ?? {}, {auto_disable: v});
        update(next);
    }

    function setGesture(key: string, v: var): void {
        const next = clone();
        next.gestures = Object.assign({}, next.gestures ?? {}, {[key]: v});
        update(next);
    }

    // Removes this page's values for the section in the given scope; "all devices"
    // also resets gestures and the external-mouse option of the touchpad section.
    function reset(name: string, scope: string): void {
        const next = clone();
        const s = next[name];
        if (s) {
            if (scope) {
                if (s.devices)
                    delete s.devices[scope];
            } else {
                delete s.all;
                if (name === "touchpad")
                    delete s.auto_disable;
            }
        }
        if (name === "touchpad" && !scope)
            delete next.gestures;
        update(next);
    }

    function update(next: var): void {
        root.settings = next;
        root.error = "";
        saveTimer.restart();
    }

    function refreshDevices(): void {
        if (!lister.running)
            lister.running = true;
    }

    function reload(): void {
        configFile.reload();
        baselineFile.reload();
        refreshDevices();
    }

    Component.onCompleted: refreshDevices()

    // Sliders report every step; write once the value settles.
    Timer {
        id: saveTimer
        interval: 300
        onTriggered: {
            if (applier.running) {
                restart();
                return;
            }
            applier.command = ["python3", "-I", root.applyScript, JSON.stringify(root.settings)];
            applier.running = true;
        }
    }

    Process {
        id: applier
        stderr: StdioCollector {
            id: applierErr
        }
        onExited: code => {
            root.error = code === 0 ? "" : (applierErr.text.trim() || "Unable to apply the settings");
            if (code !== 0)
                configFile.reload();
        }
    }

    Process {
        id: refresher
        command: ["python3", "-I", root.applyScript, "--refresh"]
    }

    Process {
        id: lister
        command: ["python3", "-I", root.devicesScript]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.devices = data.devices ?? [];
                    root.external = !!data.external;
                    // A new device or an external mouse changes what Hyprland must apply.
                    if (text !== root.lastDevices && !refresher.running)
                        refresher.running = true;
                    root.lastDevices = text;
                } catch (err) {
                    root.devices = [];
                }
            }
        }
    }

    // Input devices plugged in or removed.
    Process {
        running: true
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=input"]
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("UDEV"))
                    hotplug.restart();
            }
        }
    }

    Timer {
        id: hotplug
        interval: 800
        onTriggered: root.refreshDevices()
    }

    Connections {
        target: Hyprland
        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "configreloaded")
                reloadTimer.restart();
        }
    }

    Timer {
        id: reloadTimer
        interval: 300
        onTriggered: baselineFile.reload()
    }

    FileView {
        id: configFile
        path: root.configDir + "/input.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            if (saveTimer.running || applier.running)
                return; // our own write in progress; keep what the user just chose
            try {
                root.settings = JSON.parse(text()) ?? {version: 1};
            } catch (err) {
                root.settings = {version: 1};
            }
        }
        onLoadFailed: {
            if (!saveTimer.running && !applier.running)
                root.settings = {version: 1};
        }
    }

    FileView {
        id: baselineFile
        path: root.stateDir + "/input-baseline.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.baseline = JSON.parse(text());
            } catch (err) {}
        }
    }
}
