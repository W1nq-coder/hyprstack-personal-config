pragma Singleton

// Personal overlay: voice input. The script ~/.local/bin/dictation does the
// work and writes $XDG_RUNTIME_DIR/hyprstack-dictation/state.json, which drives
// the indicator (modules/DictationOverlay.qml). Settings (Settings → Voice
// input) are read with `dictation config` and changed with `dictation set`.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string script: Quickshell.env("HOME") + "/.local/bin/dictation"

    // ---- state of the current recording ----
    property string status: "idle"
    property string message: ""
    property real since: 0
    property real now: Date.now()
    property bool errorShown: false

    readonly property bool recording: status === "recording"
    readonly property bool transcribing: status === "transcribing"
    readonly property bool failed: status === "error" && errorShown
    readonly property bool visible: recording || transcribing || failed
    readonly property int elapsed: Math.max(0, Math.floor((now - since) / 1000))
    readonly property string elapsedText: {
        const m = Math.floor(elapsed / 60);
        const s = elapsed % 60;
        return `${m}:${s < 10 ? "0" : ""}${s}`;
    }

    // ---- settings ----
    property var config: ({})
    property string error: ""
    readonly property bool saving: setter.running || pending.length > 0
    property var pending: []

    function toggle(): void {
        Quickshell.execDetached([root.script, "toggle"]);
    }

    function reloadConfig(): void {
        if (!reader.running)
            reader.running = true;
    }

    // Change one setting: key is MODE, LANGUAGE, MODEL, SOURCE or SOUNDS.
    function set(key: string, value: string): void {
        const next = Object.assign({}, root.config);
        next[key.toLowerCase()] = key === "SOUNDS" ? value === "1" : value;
        root.config = next; // show the new value right away
        root.pending = root.pending.concat([[key, value]]);
        root.error = "";
        root.runPending();
    }

    function runPending(): void {
        if (setter.running || !root.pending.length)
            return;
        const [key, value] = root.pending[0];
        root.pending = root.pending.slice(1);
        setter.command = [root.script, "set", key, value];
        setter.running = true;
    }

    function apply(text: string): void {
        let data = {};
        try {
            data = JSON.parse(text);
        } catch (e) {
            data = {};
        }
        root.status = data.state ?? "idle";
        root.message = data.message ?? "";
        root.since = data.since ?? Date.now();
        root.now = Date.now();
        // Show an error for a few seconds; old errors from before a shell restart are not shown.
        root.errorShown = root.status === "error" && Date.now() - root.since < 5000;
        if (root.errorShown)
            errorTimer.restart();
    }

    FileView {
        id: stateFile

        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/hyprstack-dictation/state.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
        onLoadFailed: root.apply("")
    }

    Timer {
        id: errorTimer

        interval: 5000
        onTriggered: root.errorShown = false
    }

    Timer {
        running: root.recording
        interval: 250
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }

    Process {
        id: reader

        command: [root.script, "config"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.config = JSON.parse(text);
                } catch (e) {
                    root.error = "Не удалось прочитать настройки голосового ввода";
                }
            }
        }
    }

    Process {
        id: setter

        stderr: StdioCollector {
            id: setterErr
        }
        onExited: code => {
            if (code !== 0)
                root.error = setterErr.text.trim() || "Не удалось сохранить настройку";
            if (root.pending.length)
                root.runPending();
            else
                root.reloadConfig();
        }
    }

    IpcHandler {
        target: "dictation"

        function refresh(): void {
            stateFile.reload();
        }

        function toggle(): void {
            root.toggle();
        }
    }
}
