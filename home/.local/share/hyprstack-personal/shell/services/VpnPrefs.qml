pragma Singleton

// Personal overlay: how the VPN app looks and behaves (gear button in the VPN
// window). Stored in ~/.config/hyprstack/vpn-ui.json. Connection settings
// (mode, routes, DNS, port) live in the VPN backend itself.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // "orb" (big button), "list" (two panes), "cards" (server tiles)
    property string design: "orb"
    readonly property var designs: ["orb", "list", "cards"]
    // "ping", "name" or "source" (order of the subscription)
    property string sort: "ping"
    readonly property var sorts: ["ping", "name", "source"]
    property bool showAddress: true
    property bool showProtocol: true
    // Connect button picks the server with the best ping
    property bool connectFastest: false
    property bool pingOnOpen: true
    property bool updateOnOpen: false

    readonly property var keys: ["design", "sort", "showAddress", "showProtocol", "connectFastest", "pingOnOpen", "updateOnOpen"]

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
        root.design = root.designs.includes(data.design) ? data.design : "orb";
        root.sort = root.sorts.includes(data.sort) ? data.sort : "ping";
        root.showAddress = data.showAddress !== false;
        root.showProtocol = data.showProtocol !== false;
        root.connectFastest = data.connectFastest === true;
        root.pingOnOpen = data.pingOnOpen !== false;
        root.updateOnOpen = data.updateOnOpen === true;
    }

    Timer {
        id: saveTimer

        interval: 300
        onTriggered: {
            const data = {};
            for (const key of root.keys)
                data[key] = root[key];
            file.setText(JSON.stringify(data, null, 4) + "\n");
        }
    }

    FileView {
        id: file

        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/hyprstack/vpn-ui.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }
}
