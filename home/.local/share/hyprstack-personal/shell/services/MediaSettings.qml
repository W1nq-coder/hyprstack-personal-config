pragma Singleton

// Personal overlay: settings of the Media tab in the dashboard (Settings → Media).
// Stored in ~/.config/hyprstack/media.json.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // "wavy" (the shell's own cookie shape), "circle", "square" (rounded), "vinyl"
    property string coverShape: "wavy"
    // Rotate the cover while music plays
    property bool spin: true
    // Audio bars around the cover
    property bool visualiser: true
    // Volume slider under the controls
    property bool showVolume: true
    // "Like" button (players that support it, e.g. Gnova)
    property bool showLike: true

    readonly property var shapes: ["wavy", "circle", "square", "vinyl"]

    // Start Gnova at login: a copy of its menu entry in ~/.config/autostart
    // (run by xdg-desktop-autostart.target of the session).
    readonly property string gnovaEntry: Quickshell.env("HOME") + "/.local/share/applications/gnova.desktop"
    readonly property string gnovaAutostartPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/autostart/gnova.desktop"
    property bool gnovaAutostart: false

    function setGnovaAutostart(on: bool): void {
        root.gnovaAutostart = on;
        const dir = root.gnovaAutostartPath.replace(/\/[^/]*$/, "");
        if (on)
            Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && cp "$2" "$3"', "sh", dir, root.gnovaEntry, root.gnovaAutostartPath]);
        else
            Quickshell.execDetached(["rm", "-f", root.gnovaAutostartPath]);
        autostartCheck.restart();
    }

    Timer {
        id: autostartCheck

        interval: 500
        onTriggered: autostartFile.reload()
    }

    FileView {
        id: autostartFile

        path: root.gnovaAutostartPath
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.gnovaAutostart = true
        onLoadFailed: root.gnovaAutostart = false
    }

    function set(key: string, value: var): void {
        root[key] = value;
        saveTimer.restart();
    }

    function apply(text: string): void {
        let data = {};
        try {
            data = JSON.parse(text) ?? {};
        } catch (err) {
            data = {};
        }
        root.coverShape = root.shapes.includes(data.coverShape) ? data.coverShape : "wavy";
        root.spin = data.spin !== false;
        root.visualiser = data.visualiser !== false;
        root.showVolume = data.showVolume !== false;
        root.showLike = data.showLike !== false;
    }

    Timer {
        id: saveTimer

        interval: 300
        onTriggered: file.setText(JSON.stringify({
            coverShape: root.coverShape,
            spin: root.spin,
            visualiser: root.visualiser,
            showVolume: root.showVolume,
            showLike: root.showLike
        }, null, 4) + "\n")
    }

    FileView {
        id: file

        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/hyprstack/media.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }
}
