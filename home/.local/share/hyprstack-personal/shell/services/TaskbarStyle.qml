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
import Hyprstack.I18n

Singleton {
    id: root

    readonly property var views: ["labels", "icons", "dock"]
    readonly property var edges: ["bottom", "top", "left", "right"]
    readonly property var logoModes: ["default", "hyprstack", "distro", "glyph", "image", "logo"]

    // Built-in logo pictures (Material symbols, they follow the theme colours).
    readonly property var glyphs: ["apps", "grid_view", "dashboard", "widgets", "rocket_launch", "bolt", "star", "favorite", "terminal", "home", "deployed_code", "hexagon", "token", "diamond", "circle", "flare", "pets", "eco", "public", "code", "sports_esports", "music_note", "bug_report", "psychiatry"]

    property string view: "labels"
    property string stackingEdge: "bottom"
    property string logoMode: "default"
    property string logoGlyph: "apps"
    property string logoPath: ""
    property string logoId: ""             // a logo from the built-in catalogue (assets/distro-logos)
    property bool logoTint: false          // recolour a custom picture with the theme colour
    property var layout: null              // array of element ids, see the editor

    readonly property bool dock: view === "dock"

    // ---- catalogue of logos (assets/distro-logos/index.json: [{id, name}]) ----
    property var catalogue: []
    readonly property string logoDir: Quickshell.shellDir + "/assets/distro-logos"

    // The distribution of this computer (ID of /etc/os-release) as a logo of the catalogue, or "".
    property string osId: ""
    readonly property string detectedLogo: {
        const alias = ({arch: "archlinux", opensuse: "opensuse", "opensuse-leap": "opensuse-leap", "opensuse-tumbleweed": "opensuse-tumbleweed", pop: "pop-os", popos: "pop-os", endeavouros: "endeavour", rocky: "rocky-linux", almalinux: "almalinux", kali: "kali-linux", mint: "linuxmint", rhel: "redhat", alpine: "alpine"});
        const id = alias[osId] ?? osId;
        return logoKnown(id) ? id : "";
    }

    FileView {
        path: "/etc/os-release"
        printErrors: false
        onLoaded: {
            const m = text().match(/^ID=("?)([A-Za-z0-9._-]+)\1\s*$/m);
            root.osId = m ? m[2].toLowerCase() : "";
        }
    }

    function logoKnown(id: var): bool {
        return typeof id === "string" && /^[a-z0-9-]+$/.test(id) && catalogue.some(e => e.id === id);
    }

    function logoFile(id: string): string {
        return logoKnown(id) ? logoDir + "/" + id + ".svg" : "";
    }

    function setLogoId(id: string): void {
        if (!logoKnown(id))
            return;
        logoMode = "logo";
        logoId = id;
        saveTimer.restart();
    }

    FileView {
        path: root.logoDir + "/index.json"
        printErrors: false
        onLoaded: {
            try {
                const list = JSON.parse(text());
                root.catalogue = Array.isArray(list) ? list.filter(e => e && typeof e.id === "string" && typeof e.name === "string" && /^[a-z0-9-]+$/.test(e.id)) : [];
            } catch (err) {
                root.catalogue = [];
            }
        }
    }

    // ---- appearance (Settings → Panels → Taskbar → Appearance) ----
    // Sizes and opacity are percentages, the corner radius and the gap are pixels.
    readonly property var dockEdges: ["auto", "bottom", "top", "left", "right"]
    readonly property var dockAligns: ["center", "start", "end"]
    property string dockEdge: "auto"         // "auto" = the edge opposite to the bar
    property string dockAlign: "center"      // along the edge: centre, start (left/top) or end
    property int dockRadius: 16
    property int dockScale: 100
    property int dockOpacity: 100
    property int dockDim: 0                  // 0..80: how much the background is darkened
    property int dockGap: 10
    property int barScale: 100
    property int barOpacity: 100
    property int barDim: 0

    readonly property string dockActualEdge: dockEdge !== "auto" ? dockEdge : ({
            bottom: "top",
            top: "bottom",
            left: "right",
            right: "left"
        })[stackingEdge] ?? "top"

    // A theme colour darkened by `dim` percent and made `opacity` percent as opaque.
    function tone(c: color, dim: int, opacity: int): color {
        const k = 1 - dim / 100;
        return Qt.rgba(c.r * k, c.g * k, c.b * k, c.a * opacity / 100);
    }

    readonly property var limits: ({
            dockRadius: [0, 48],
            dockScale: [60, 180],
            dockOpacity: [10, 100],
            dockDim: [0, 80],
            dockGap: [0, 60],
            barScale: [70, 180],
            barOpacity: [10, 100],
            barDim: [0, 80]
        })

    function setAppearance(key: string, value: var): void {
        if (key === "dockEdge") {
            if (!dockEdges.includes(value))
                return;
            dockEdge = value;
        } else if (key === "dockAlign") {
            if (!dockAligns.includes(value))
                return;
            dockAlign = value;
        } else if (limits[key] !== undefined) {
            root[key] = clampInt(value, limits[key][0], limits[key][1], root[key]);
        } else {
            return;
        }
        saveTimer.restart();
    }

    function resetAppearance(): void {
        dockEdge = "auto";
        dockAlign = "center";
        dockRadius = 16;
        dockScale = 100;
        dockOpacity = 100;
        dockDim = 0;
        dockGap = 10;
        barScale = 100;
        barOpacity = 100;
        barDim = 0;
        saveTimer.restart();
    }

    function clampInt(v: var, lo: int, hi: int, fallback: int): int {
        const n = Math.round(Number(v));
        return Number.isFinite(n) ? Math.max(lo, Math.min(hi, n)) : fallback;
    }

    // ---- editing the bar in place (right click on the bar -> "Customize taskbar") ----
    property bool editing: false
    readonly property bool ru: String(Tr.language || Qt.locale().name).startsWith("ru")

    function l(en: string, rus: string): string {
        return ru ? rus : en;
    }

    function label(id: string): string {
        return ({
                logo: l("Logo", "Логотип"),
                tasks: l("Windows", "Окна"),
                tray: l("Tray", "Трей"),
                clock: l("Clock", "Часы"),
                statusIcons: l("Status icons", "Значки состояния"),
                vpn: "VPN",
                notifications: l("Notifications", "Уведомления"),
                power: l("Power", "Питание")
            })[id] ?? id;
    }

    function iconOf(id: string): string {
        return ({
                logo: "image",
                tasks: "web_asset",
                tray: "widgets",
                clock: "schedule",
                statusIcons: "signal_cellular_alt",
                vpn: "vpn_key",
                notifications: "notifications",
                power: "power_settings_new"
            })[id] ?? "circle";
    }

    function startEditing(): void {
        editing = true;
    }

    function stopEditing(): void {
        editing = false;
    }

    // Put element `id` into `zone` ("left" | "center" | "right") in front of `beforeId`
    // (null = at the end); zone "hidden" takes it off the bar.
    function moveElement(id: string, zone: string, beforeId: var): void {
        if (!catalog.includes(id))
            return;
        const z = {
            left: [...zones.left],
            center: [...zones.center],
            right: [...zones.right]
        };
        for (const name of ["left", "center", "right"])
            z[name] = z[name].filter(x => x !== id);
        if (zone !== "hidden" && z[zone]) {
            const i = beforeId ? z[zone].indexOf(beforeId) : -1;
            if (i < 0)
                z[zone].push(id);
            else
                z[zone].splice(i, 0, id);
        }
        setZones(z);
    }

    Connections {
        target: Hypr

        function onStackingChanged(): void {
            if (!Hypr.stacking)
                root.editing = false;
        }
    }

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
        logoId = "";
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
        root.logoId = typeof logo.id === "string" && /^[a-z0-9-]+$/.test(logo.id) ? logo.id : "";
        root.logoPath = (typeof logo.path === "string" && logo.path.startsWith("/")) ? logo.path : "";
        root.logoTint = logo.tint === true;
        const look = (data.appearance !== null && typeof data.appearance === "object") ? data.appearance : {};
        root.dockEdge = dockEdges.includes(look.dockEdge) ? look.dockEdge : "auto";
        root.dockAlign = dockAligns.includes(look.dockAlign) ? look.dockAlign : "center";
        for (const key of Object.keys(limits))
            root[key] = clampInt(look[key], limits[key][0], limits[key][1], key === "dockRadius" ? 16 : key === "dockGap" ? 10 : (key.endsWith("Scale") || key.endsWith("Opacity")) ? 100 : 0);
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
                id: root.logoId,
                tint: root.logoTint
            },
            appearance: {
                dockEdge: root.dockEdge,
                dockAlign: root.dockAlign,
                dockRadius: root.dockRadius,
                dockScale: root.dockScale,
                dockOpacity: root.dockOpacity,
                dockDim: root.dockDim,
                dockGap: root.dockGap,
                barScale: root.barScale,
                barOpacity: root.barOpacity,
                barDim: root.barDim
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
