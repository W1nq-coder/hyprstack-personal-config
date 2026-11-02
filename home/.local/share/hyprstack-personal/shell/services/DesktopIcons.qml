pragma Singleton

// Personal overlay: desktop icons and the right-click menu in the floating ("Windows-like", stacking)
// layout. Shows the contents of the user's Desktop folder. Settings (icon size, sort order, icon
// positions, custom icons) live in ~/.config/hyprstack/desktop.json. All file operations go through
// small shell commands that receive paths as arguments (never spliced into a command line).

import QtQuick
import Quickshell
import Quickshell.Io
import Hyprstack.Config
import Hyprstack.Models

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    property string desktopDir: home + "/Desktop"

    // ---- settings ----
    property string iconSize: "large"      // "small" | "medium" | "large"
    property string sortBy: "name"         // "name" | "type" | "size"
    property bool showIcons: true          // View -> Show desktop icons
    readonly property var iconSizes: ({
            small: 48,
            medium: 72,
            large: 104
        })
    readonly property int iconPx: iconSizes[iconSize] ?? 104
    property var positions: ({})           // file name -> [column, row] on the desktop grid
    property var customIcons: ({})         // file name -> absolute path of an image

    // ---- grid (set by the icon layer) ----
    property int cols: 12
    property int rows: 8
    property bool layoutReady: false

    // ---- state ----
    property var items: []                 // sorted FileSystemEntry list
    property var selection: ({})           // path -> true
    property string renaming: ""           // path being renamed (in place)
    property string pendingRename: ""      // created, waiting for the folder watcher to see it

    // What can be created from the menu: [id, extension, English name, Russian name]
    readonly property var newTypes: [["dir", "", "New folder", "Новая папка"], ["txt", ".txt", "New text document", "Новый текстовый документ"], ["md", ".md", "New Markdown document", "Новый документ Markdown"], ["html", ".html", "New HTML page", "Новая страница HTML"], ["py", ".py", "New Python script", "Новый скрипт Python"], ["sh", ".sh", "New Bash script", "Новый скрипт Bash"], ["json", ".json", "New JSON file", "Новый файл JSON"], ["empty", "", "New file", "Новый файл"]]

    // ------------------------------------------------------------------ selection
    function isSelected(path: string): bool {
        return selection[path] === true;
    }

    function selectOnly(path: string): void {
        const s = {};
        s[path] = true;
        selection = s;
    }

    function toggleSelected(path: string): void {
        const s = Object.assign({}, selection);
        if (s[path])
            delete s[path];
        else
            s[path] = true;
        selection = s;
    }

    function clearSelection(): void {
        if (Object.keys(selection).length > 0)
            selection = {};
    }

    function selectAll(): void {
        const s = {};
        for (const e of items)
            s[e.path] = true;
        selection = s;
    }

    function selectedEntries(): var {
        return items.filter(e => selection[e.path] === true);
    }

    // ------------------------------------------------------------------ settings
    function setIconSize(value: string): void {
        if (!(value in iconSizes) || value === iconSize)
            return;
        iconSize = value;
        saveTimer.restart();
    }

    // Choosing a sort order arranges all icons again (like "Sort by" on the Windows desktop).
    function setSortBy(value: string): void {
        if (!["name", "type", "size"].includes(value))
            return;
        sortBy = value;
        positions = {};
        rebuild();
        saveTimer.restart();
    }

    function setShowIcons(value: bool): void {
        if (value === showIcons)
            return;
        showIcons = value;
        if (!value) {
            selection = {};
            renaming = "";
        }
        saveTimer.restart();
    }

    function setCustomIcon(name: string, path: string): void {
        const c = Object.assign({}, customIcons);
        if (path)
            c[name] = path;
        else
            delete c[name];
        customIcons = c;
        saveTimer.restart();
    }

    // ------------------------------------------------------------------ the list and the grid
    function rebuild(): void {
        const list = [...desk.entries];
        list.sort((a, b) => {
            if (a.isDir !== b.isDir)
                return a.isDir ? -1 : 1;
            if (sortBy === "type") {
                const c = (a.suffix || "").localeCompare(b.suffix || "");
                if (c !== 0)
                    return c;
            } else if (sortBy === "size") {
                if (a.size !== b.size)
                    return b.size - a.size;
            }
            return a.name.localeCompare(b.name, undefined, {
                numeric: true,
                sensitivity: "base"
            });
        });
        items = list;
        autoPlace();
        if (pendingRename && list.some(e => e.path === pendingRename)) {
            selectOnly(pendingRename);
            renaming = pendingRename;
            pendingRename = "";
        }
        // Drop selection of files that are gone.
        const paths = new Set(list.map(e => e.path));
        const left = Object.keys(selection).filter(p => paths.has(p));
        if (left.length !== Object.keys(selection).length) {
            const s = {};
            for (const p of left)
                s[p] = true;
            selection = s;
        }
    }

    // Files without a place yet fill the first free cells, top to bottom, then the next column.
    function autoPlace(): void {
        if (!layoutReady || items.length === 0)
            return;
        const taken = {};
        for (const e of items) {
            const p = positions[e.name];
            if (p)
                taken[p[0] + "," + p[1]] = true;
        }
        let changed = false;
        const next = Object.assign({}, positions);
        for (const e of items) {
            if (next[e.name])
                continue;
            let c = 0, r = 0;
            while (taken[c + "," + r]) {
                r++;
                if (r >= rows) {
                    r = 0;
                    c++;
                }
            }
            next[e.name] = [c, r];
            taken[c + "," + r] = true;
            changed = true;
        }
        if (changed) {
            positions = next;
            saveTimer.restart();
        }
    }

    function nearestFree(c: int, r: int, taken: var): var {
        const limit = Math.max(cols, rows) + 2;
        for (let d = 0; d < limit; d++) {
            for (let dc = -d; dc <= d; dc++) {
                for (let dr = -d; dr <= d; dr++) {
                    if (Math.max(Math.abs(dc), Math.abs(dr)) !== d)
                        continue;
                    const cc = c + dc, rr = r + dr;
                    if (cc < 0 || rr < 0 || cc >= cols || rr >= rows)
                        continue;
                    if (!taken[cc + "," + rr])
                        return [cc, rr];
                }
            }
        }
        return [c, r];
    }

    // Move every selected icon by (dc, dr) cells; an occupied target cell gives way to the nearest free one.
    function moveSelection(dc: int, dr: int): void {
        const sel = selectedEntries();
        if (sel.length === 0 || (dc === 0 && dr === 0))
            return;
        const moving = new Set(sel.map(e => e.name));
        const taken = {};
        for (const e of items) {
            const p = positions[e.name];
            if (p && !moving.has(e.name))
                taken[p[0] + "," + p[1]] = true;
        }
        const next = Object.assign({}, positions);
        for (const e of sel) {
            const p = positions[e.name] ?? [0, 0];
            const c = Math.max(0, Math.min(cols - 1, p[0] + dc));
            const r = Math.max(0, Math.min(rows - 1, p[1] + dr));
            const free = nearestFree(c, r, taken);
            next[e.name] = free;
            taken[free[0] + "," + free[1]] = true;
        }
        positions = next;
        saveTimer.restart();
    }

    // ------------------------------------------------------------------ actions
    function open(entry: var): void {
        if (entry.suffix === "desktop")
            Quickshell.execDetached(["gio", "launch", entry.path]);
        else
            Quickshell.execDetached(["xdg-open", entry.path]);
    }

    function openSelected(): void {
        for (const e of selectedEntries())
            open(e);
    }

    function openTerminalHere(): void {
        const term = GlobalConfig.general.apps.terminal;
        Quickshell.execDetached({
            command: term.length > 0 ? [...term] : ["kitty"],
            workingDirectory: desktopDir
        });
    }

    function openSettings(subpage: int): void {
        Quickshell.execDetached(["qs", "--path", Quickshell.shellDir, "ipc", "call", "settings", "open", "0", String(subpage)]);
    }

    // Like "Show desktop": minimise every window that is not minimised yet.
    function hideAllWindows(): void {
        for (const t of Hypr.toplevels.values) {
            if (Hypr.isMinimized(t) || (t.workspace?.name ?? "").startsWith("special:"))
                continue;
            Hypr.windowAction("minimize", t);
        }
    }

    // A new folder / file with a free name; its name is then edited in place.
    function create(typeId: string, baseName: string, ext: string): void {
        if (!showIcons)
            setShowIcons(true);   // the new item is renamed in place, so it has to be visible
        createProc.command = ["sh", "-c", 'd="$1"; kind="$2"; n="$3"; ext="$4"; mkdir -p -- "$d" || exit 1; ' + 't="$d/$n$ext"; i=2; while [ -e "$t" ]; do t="$d/$n ($i)$ext"; i=$((i+1)); done; ' + 'case "$kind" in ' + 'dir) mkdir -- "$t" || exit 1 ;; ' + 'sh) printf "#!/usr/bin/env bash\\n\\n" > "$t" && chmod +x "$t" || exit 1 ;; ' + 'py) printf "#!/usr/bin/env python3\\n\\n" > "$t" && chmod +x "$t" || exit 1 ;; ' + 'json) printf "{}\\n" > "$t" || exit 1 ;; ' + 'md) printf "# \\n" > "$t" || exit 1 ;; ' + 'html) printf "<!doctype html>\\n<html lang=\\"ru\\">\\n<head>\\n<meta charset=\\"utf-8\\">\\n<title></title>\\n</head>\\n<body>\\n\\n</body>\\n</html>\\n" > "$t" || exit 1 ;; ' + '*) : > "$t" || exit 1 ;; ' + 'esac; printf "%s" "$t"', "sh", desktopDir, typeId, baseName, ext];
        createProc.running = true;
    }

    function rename(path: string, newName: string): void {
        renaming = "";
        newName = newName.trim();
        const oldName = path.split("/").pop();
        if (!newName || newName === oldName || newName.includes("/") || newName === "." || newName === "..")
            return;
        // The icon keeps its place and its custom picture under the new name.
        const p = Object.assign({}, positions);
        if (p[oldName]) {
            p[newName] = p[oldName];
            delete p[oldName];
            positions = p;
        }
        if (customIcons[oldName]) {
            const c = Object.assign({}, customIcons);
            c[newName] = c[oldName];
            delete c[oldName];
            customIcons = c;
        }
        saveTimer.restart();
        Quickshell.execDetached(["mv", "-n", "--", path, path.slice(0, path.length - oldName.length) + newName]);
    }

    function trash(paths: var): void {
        if (paths.length > 0)
            Quickshell.execDetached(["gio", "trash", "--", ...paths]);
    }

    // Put files on the clipboard (text/uri-list), so a file manager or "Paste" can copy them.
    function copyFiles(paths: var): void {
        if (paths.length === 0)
            return;
        Quickshell.execDetached(["sh", "-c", 'python3 -I -c \'import sys, urllib.parse; sys.stdout.write("".join("file://" + urllib.parse.quote(p) + "\\n" for p in sys.argv[1:]))\' "$@" | wl-copy --type text/uri-list', "sh", ...paths]);
    }

    function copyText(text: string): void {
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | wl-copy', "sh", text]);
    }

    // Paste files copied in a file manager (text/uri-list in the clipboard) into the desktop folder.
    function paste(): void {
        Quickshell.execDetached(["sh", "-c", 'wl-paste --no-newline --type text/uri-list 2>/dev/null | python3 -I -c \'' + 'import sys, shutil, os, urllib.parse\n' + 'dst = sys.argv[1]\n' + 'for line in sys.stdin.read().splitlines():\n' + '    if not line.startswith("file://"): continue\n' + '    src = urllib.parse.unquote(line[7:])\n' + '    if not os.path.exists(src): continue\n' + '    name = os.path.basename(src.rstrip("/"))\n' + '    target = os.path.join(dst, name)\n' + '    i = 2\n' + '    while os.path.exists(target):\n' + '        base, ext = os.path.splitext(name)\n' + '        target = os.path.join(dst, "%s (%d)%s" % (base, i, ext)); i += 1\n' + '    (shutil.copytree if os.path.isdir(src) else shutil.copy2)(src, target)\n' + '\' "$1"', "sh", desktopDir]);
    }

    // ------------------------------------------------------------------ persistence
    function apply(text: string): void {
        let data = {};
        try {
            data = JSON.parse(text) ?? {};
        } catch (err) {
            data = {};
        }
        root.iconSize = (data.iconSize in root.iconSizes) ? data.iconSize : "large";
        root.sortBy = ["name", "type", "size"].includes(data.sortBy) ? data.sortBy : "name";
        root.showIcons = data.showIcons !== false;
        const pos = {};
        for (const [k, v] of Object.entries(data.positions ?? {}))
            if (Array.isArray(v) && v.length === 2 && Number.isInteger(v[0]) && Number.isInteger(v[1]) && v[0] >= 0 && v[1] >= 0)
                pos[k] = v;
        root.positions = pos;
        const icons = {};
        for (const [k, v] of Object.entries(data.customIcons ?? {}))
            if (typeof v === "string" && v.startsWith("/"))
                icons[k] = v;
        root.customIcons = icons;
        root.rebuild();
    }

    Timer {
        id: saveTimer

        interval: 300
        onTriggered: {
            // Forget places of files that no longer exist (not while the list is empty/unreadable).
            const names = new Set(root.items.map(e => e.name));
            const pos = {};
            for (const [k, v] of Object.entries(root.positions))
                if (root.items.length === 0 || names.has(k))
                    pos[k] = v;
            file.setText(JSON.stringify({
                iconSize: root.iconSize,
                sortBy: root.sortBy,
                showIcons: root.showIcons,
                positions: pos,
                customIcons: root.customIcons
            }, null, 4) + "\n");
        }
    }

    FileView {
        id: file

        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/hyprstack/desktop.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }

    // ------------------------------------------------------------------ the desktop folder
    FileSystemModel {
        id: desk

        path: root.desktopDir
        recursive: false
        watchChanges: true
        showHidden: false
        filter: FileSystemModel.NoFilter
        onEntriesChanged: root.rebuild()
    }

    Process {
        id: createProc

        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim();
                if (!path)
                    return;
                root.pendingRename = path;
                // The folder watcher may already have seen it.
                root.rebuild();
            }
        }
    }

    // Real location of the Desktop folder (localised, e.g. ~/Рабочий стол).
    Process {
        running: true
        command: ["xdg-user-dir", "DESKTOP"]
        stdout: StdioCollector {
            onStreamFinished: {
                const dir = text.trim();
                if (dir && dir !== root.home)
                    root.desktopDir = dir;
            }
        }
    }
}
