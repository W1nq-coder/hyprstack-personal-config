pragma Singleton

// Personal overlay: look of the taskbar in the floating ("Windows-like", stacking) layout.
// Stored in ~/.config/hyprstack/taskbar-style.json:
//   view          "labels" (icons + titles), "icons" (icons only) or "dock" (GNOME style: the bar
//                 on one edge, the applications in a separate dock on the opposite edge)
//   stackingEdge  edge of the taskbar in the floating layout: "bottom" | "top" | "left" | "right"
//   logo          the picture on the logo button: {mode, glyph, path, tint}
//   layout        order of the bar elements in the floating layout (null = default, see editor)

import QtQuick
import Quickshell
import Quickshell.Io
import Hyprstack.Config

Singleton {
    id: root

    readonly property var views: ["labels", "icons", "dock"]
    readonly property var edges: ["bottom", "top", "left", "right"]
    readonly property var logoModes: ["default", "hyprstack", "distro", "glyph", "image"]

    // Built-in logo pictures (Material symbols, they follow the theme colours).
    readonly property var glyphs: ["apps", "grid_view", "dashboard", "widgets", "rocket_launch", "bolt", "star", "favorite", "terminal", "home", "deployed_code", "hexagon", "token", "diamond", "circle", "flare", "pets", "eco", "public", "code", "sports_esports", "music_note", "bug_report", "psychiatry"]

    property string view: "labels"
    property string stackingEdge: "bottom"
    property string logoMode: "default"
    property string logoGlyph: "apps"
    property string logoPath: ""
    property bool logoTint: false          // recolour a custom picture with the theme colour
    property var layout: null              // array of element ids, see the editor

    readonly property bool dock: view === "dock"

    // ---- layout of the bar elements in the floating layout ----
    // Elements the editor can place; everything not placed is hidden. "tasks" is the list of open windows.
    readonly property var catalog: ["logo", "tasks", "tray", "clock", "statusIcons", "vpn", "notifications", "power"]
    // The default follows the element switches of Settings → Panels → Taskbar, so what was switched off
    // there stays off until the layout is edited.
    readonly property var defaultLayout: {
        const entries = GlobalConfig.bar.entries.values;
        const on = id => id === "notifications" ? GlobalConfig.bar.showNotifications : (entries.find(e => e.id === id)?.enabled ?? true);
        return ["logo", "spacer", "tasks", "spacer", ...["tray", "clock", "statusIcons", "vpn", "notifications", "power"].filter(on)].filter(id => id === "spacer" || id === "tasks" || on(id));
    }

    // The saved list split into the three zones around its two "spacer" markers; unknown or repeated
    // ids are dropped, so a damaged file can never break the bar.
    function zonesOf(list: var): var {
        const src = Array.isArray(list) ? list : defaultLayout;
        const zones = [[], [], []];
        const seen = new Set();
        let z = 0;
        for (const id of src) {
            if (id === "spacer") {
                if (z < 2)
                    z++;
                continue;
            }
            if (!catalog.includes(id) || seen.has(id))
                continue;
            seen.add(id);
            zones[z].push(id);
        }
        return {
            left: zones[0],
            center: zones[1],
            right: zones[2]
        };
    }

    function layoutOf(zones: var): var {
        return [...zones.left, "spacer", ...zones.center, "spacer", ...zones.right];
    }

    readonly property var zones: zonesOf(layout)
    readonly property var hidden: catalog.filter(id => !zones.left.includes(id) && !zones.center.includes(id) && !zones.right.includes(id))
    // "tasks" alone in the middle zone stays exactly centred on the screen (see Bar.qml).
    readonly property bool tasksCentred: zones.center.length === 1 && zones.center[0] === "tasks"

    function setZones(zones: var): void {
        setLayout(layoutOf(zones));
    }

    function resetLayout(): void {
        setLayout(null);
    }

    function setView(value: string): void {
        if (!views.includes(value) || value === view)
            return;
        view = value;
        saveTimer.restart();
    }

    function setStackingEdge(value: string): void {
        if (!edges.includes(value) || value === stackingEdge)
            return;
        stackingEdge = value;
        saveTimer.restart();
    }

    function setLogo(mode: string, glyph: string, path: string): void {
        if (!logoModes.includes(mode))
            return;
        logoMode = mode;
        if (mode === "glyph" && glyphs.includes(glyph))
            logoGlyph = glyph;
        if (mode === "image" && path.startsWith("/"))
            logoPath = path;
        saveTimer.restart();
    }

    function setLogoTint(value: bool): void {
        logoTint = value;
        saveTimer.restart();
    }

    function resetLogo(): void {
        logoMode = "default";
        logoPath = "";
        logoTint = false;
        saveTimer.restart();
    }

    function setLayout(value: var): void {
        layout = value;
        saveTimer.restart();
    }

    // Open the settings window on Panels -> Taskbar (2) or one of its subpages
    // (11 = logo, 12 = bar editor).
    function openSettings(subpage: int): void {
        Quickshell.execDetached(["qs", "--path", Quickshell.shellDir, "ipc", "call", "settings", "open", "4", String(subpage)]);
    }

    function apply(text: string): void {
        let data;
        try {
            data = JSON.parse(text);
        } catch (err) {
            return;   // half-written or damaged file: keep the current settings
        }
        if (data === null || typeof data !== "object" || Array.isArray(data))
            return;
        root.view = views.includes(data.view) ? data.view : "labels";
        root.stackingEdge = edges.includes(data.stackingEdge) ? data.stackingEdge : "bottom";
        const logo = (data.logo !== null && typeof data.logo === "object") ? data.logo : {};
        root.logoMode = logoModes.includes(logo.mode) ? logo.mode : "default";
        root.logoGlyph = glyphs.includes(logo.glyph) ? logo.glyph : "apps";
        root.logoPath = (typeof logo.path === "string" && logo.path.startsWith("/")) ? logo.path : "";
        root.logoTint = logo.tint === true;
        root.layout = Array.isArray(data.layout) && data.layout.every(id => typeof id === "string") ? data.layout : null;
    }

    Timer {
        id: saveTimer

        interval: 300
        onTriggered: file.setText(JSON.stringify({
            view: root.view,
            stackingEdge: root.stackingEdge,
            logo: {
                mode: root.logoMode,
                glyph: root.logoGlyph,
                path: root.logoPath,
                tint: root.logoTint
            },
            layout: root.layout
        }, null, 4) + "\n")
    }

    FileView {
        id: file

        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/hyprstack/taskbar-style.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }
}
