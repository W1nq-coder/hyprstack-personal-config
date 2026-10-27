pragma Singleton

// Personal overlay: adds editing of every shortcut.
// Edits are stored per slot in ~/.config/hyprstack/keybinds.json and applied to the
// Hyprland config by ~/.config/hyprstack/keybinds-ui.lua (hooked from hypr-vars.lua),
// which also reports the slots in ~/.local/state/hyprstack/keybind-slots.json.
// Shortcuts added in Settings are the "custom" list of keybinds.json; keybinds-ui.lua
// binds each one to exec_cmd(command) after the config has loaded.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "Keybinds.js" as Bindings

Singleton {
    id: root

    property var bindings: []
    property var raw: []
    property string error
    readonly property bool loading: reader?.running ?? false

    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/hyprstack"
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/hyprstack"
    readonly property string applyScript: Quickshell.shellDir + "/scripts/keybinds-apply.py"
    readonly property string appsScript: Quickshell.shellDir + "/scripts/keybinds-apps.py"

    property var custom: []
    // Installed applications: [{id, name, comment, icon, command}]
    property var apps: []
    readonly property bool appsLoading: appsReader?.running ?? false

    property var slots: []
    readonly property var defaults: Bindings.slotIndex(slots).defaults
    property var overrides: ({})
    readonly property bool editable: Object.keys(defaults).length > 0
    readonly property bool saving: applier?.running ?? false
    property string saveError
    property bool recording

    signal saved

    function reload(): void {
        if (!reader.running)
            reader.running = true;
    }

    function rebuild(): void {
        try {
            root.bindings = Bindings.fromHyprland(root.raw, {slots: root.slots, overrides: root.overrides, custom: root.custom});
            root.error = "";
        } catch (err) {
            root.error = "Unable to read keyboard shortcuts";
        }
    }

    function effective(name: string): var {
        return Bindings.effectiveValue(name, defaults, overrides);
    }

    // changes: {slot: [chords]}; a value equal to the default removes the override.
    function save(changes: var): void {
        const next = Object.assign({}, overrides);
        for (const name of Object.keys(changes)) {
            if (defaults[name] !== undefined && Bindings.sameList(changes[name], [defaults[name]]))
                delete next[name];
            else
                next[name] = Bindings.packValue(Bindings.asList(changes[name]));
        }
        root.apply(next, root.custom);
    }

    function apply(slots: var, custom: var): void {
        root.saveError = "";
        applier.command = ["python3", "-I", root.applyScript, JSON.stringify({slots: slots, custom: custom})];
        applier.running = true;
    }

    // item: {id?, chord, name, icon, command}; slotChanges as for save() (shortcuts
    // whose chord is taken over). An existing id is updated in place, never duplicated.
    function saveCustom(item: var, slotChanges: var): void {
        const list = root.custom.slice();
        const at = item.id ? list.findIndex(c => c.id === item.id) : -1;
        const entry = {id: item.id || Bindings.newCustomId(list), chord: item.chord, name: item.name || "",
            icon: item.icon || "", command: item.command};
        if (at >= 0)
            list[at] = Object.assign({}, list[at], entry);
        else
            list.push(entry);
        const next = Object.assign({}, overrides);
        for (const name of Object.keys(slotChanges || {})) {
            if (defaults[name] !== undefined && Bindings.sameList(slotChanges[name], [defaults[name]]))
                delete next[name];
            else
                next[name] = Bindings.packValue(Bindings.asList(slotChanges[name]));
        }
        root.apply(next, list);
    }

    function deleteCustom(id: string): void {
        root.apply(root.overrides, root.custom.filter(c => c.id !== id));
    }

    function loadApps(): void {
        if (!appsReader.running)
            appsReader.running = true;
    }

    // Removing the edit restores the shell's own shortcut.
    function reset(names: var): void {
        const next = Object.assign({}, overrides);
        for (const name of names)
            delete next[name];
        root.apply(next, root.custom);
    }

    // While recording, Hyprland switches to an empty submap so bound chords reach
    // the settings window. keybinds-ui.lua also resets it after 20 s on its own.
    function startRecording(): void {
        root.recording = true;
        Hyprland.dispatch('hl.dsp.submap("hyprstack-keyrecord")');
        Quickshell.execDetached(["hyprctl", "eval", "if hyprstack_keyrecord then hyprstack_keyrecord.start() end"]);
    }

    function stopRecording(): void {
        if (!root.recording)
            return;
        root.recording = false;
        Quickshell.execDetached(["hyprctl", "eval", "if hyprstack_keyrecord then hyprstack_keyrecord.stop() else hl.dispatch(hl.dsp.submap(\"reset\")) end"]);
        Hyprland.dispatch('hl.dsp.submap("reset")');
    }

    Component.onCompleted: reload()
    Component.onDestruction: stopRecording()

    Connections {
        target: Hyprland
        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "configreloaded")
                refreshTimer.restart();
        }
    }

    Timer {
        id: refreshTimer
        interval: 200
        onTriggered: root.reload()
    }

    FileView {
        path: root.stateDir + "/keybind-slots.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.slots = JSON.parse(text()) ?? [];
            } catch (err) {
                root.slots = [];
            }
            root.rebuild();
        }
    }

    FileView {
        path: root.configDir + "/keybinds.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.overrides = data.slots ?? {};
                root.custom = Bindings.customList(data.custom);
            } catch (err) {
                root.overrides = {};
                root.custom = [];
            }
            root.rebuild();
        }
        onLoadFailed: {
            root.overrides = {};
            root.custom = [];
            root.rebuild();
        }
    }

    Process {
        id: reader
        command: ["hyprctl", "-j", "binds"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.raw = JSON.parse(text);
                    root.rebuild();
                } catch (err) {
                    root.error = "Unable to read keyboard shortcuts";
                }
            }
        }
        onExited: (code, status) => {
            if (code !== 0 || status !== 0)
                root.error = "Unable to read keyboard shortcuts";
        }
    }

    Process {
        id: appsReader
        command: ["python3", "-I", root.appsScript, "--terminal", "kitty -e"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.apps = JSON.parse(text) ?? [];
                } catch (err) {
                    root.apps = [];
                }
            }
        }
    }

    Process {
        id: applier
        stderr: StdioCollector {
            id: applierErr
        }
        onExited: (code, status) => {
            if (code === 0) {
                root.saveError = "";
                root.saved();
            } else {
                root.saveError = applierErr.text.trim() || "Unable to save the shortcut";
            }
            root.reload();
        }
    }
}
