pragma Singleton

// Personal overlay: which screen edge the taskbar sits on (Settings → Panels →
// Taskbar → Position, or hold an empty spot of the bar and drag it to an edge).
// Stored in ~/.config/hyprstack/bar.json. The floating (stacking) layout always
// keeps its own taskbar at the bottom.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // "top", "bottom", "left" or "right"
    property string edge: "top"
    readonly property var edges: ["top", "bottom", "left", "right"]

    // What the bar actually does now (the stacking layout wins)
    readonly property string activeEdge: Hypr.stacking ? "bottom" : edge
    readonly property bool vertical: activeEdge === "left" || activeEdge === "right"

    function setEdge(value: string): void {
        if (!root.edges.includes(value) || value === root.edge)
            return;
        root.edge = value;
        saveTimer.restart();
    }

    function apply(text: string): void {
        let data = {};
        try {
            data = JSON.parse(text) ?? {};
        } catch (err) {
            data = {};
        }
        root.edge = root.edges.includes(data.edge) ? data.edge : "top";
    }

    Timer {
        id: saveTimer

        interval: 300
        onTriggered: file.setText(JSON.stringify({ edge: root.edge }, null, 4) + "\n")
    }

    FileView {
        id: file

        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/hyprstack/bar.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }
}
