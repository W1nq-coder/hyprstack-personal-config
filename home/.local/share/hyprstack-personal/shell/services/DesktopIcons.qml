pragma Singleton

// Personal overlay: desktop icons and the right-click menu in the floating ("Windows-like", stacking)
// layout. Shows the contents of the user's Desktop folder. Settings (icon size, sort order) live in
// ~/.config/hyprstack/desktop.json. All file operations go through small shell commands that receive
// paths as arguments (never spliced into a command line).

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
    readonly property var iconSizes: ({
            small: 48,
            medium: 72,
            large: 104
        })
    readonly property int iconPx: iconSizes[iconSize] ?? 104

    // ---- state ----
    property var items: []                 // sorted FileSystemEntry list
    property string selected: ""           // path of the selected item
    property string renaming: ""           // path being renamed (in place)
    property string pendingRename: ""      // created, waiting for the folder watcher to see it

    function setIconSize(value: string): void {
        if (!(value in iconSizes) || value === iconSize)
            return;
        iconSize = value;
        saveTimer.restart();
    }

    function setSortBy(value: string): void {
        if (!["name", "type", "size"].includes(value) || value === sortBy)
            return;
        sortBy = value;
        rebuild();
        saveTimer.restart();
    }

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
        if (pendingRename && list.some(e => e.path === pendingRename)) {
            selected = pendingRename;
            renaming = pendingRename;
            pendingRename = "";
        }
        if (selected && !list.some(e => e.path === selected))
            selected = "";
    }

    // ---- opening ----
    function open(entry: var): void {
        if (entry.suffix === "desktop")
            Quickshell.execDetached(["gio", "launch", entry.path]);
        else
            Quickshell.execDetached(["xdg-open", entry.path]);
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

    // ---- creating ----
    // A new folder / empty text file with a free name, then the name is edited in place.
    function create(kind: string, baseName: string): void {
        createProc.command = ["sh", "-c", 'd="$1"; kind="$2"; n="$3"; ext="$4"; mkdir -p -- "$d" || exit 1; ' + 't="$d/$n$ext"; i=2; while [ -e "$t" ]; do t="$d/$n ($i)$ext"; i=$((i+1)); done; ' + 'if [ "$kind" = dir ]; then mkdir -- "$t" || exit 1; else : > "$t" || exit 1; fi; printf "%s" "$t"', "sh", desktopDir, kind, baseName, kind === "dir" ? "" : ".txt"];
        createProc.running = true;
    }

    function rename(path: string, newName: string): void {
        renaming = "";
        newName = newName.trim();
        const oldName = path.split("/").pop();
        if (!newName || newName === oldName || newName.includes("/") || newName === "." || newName === "..")
            return;
        Quickshell.execDetached(["mv", "-n", "--", path, path.slice(0, path.length - oldName.length) + newName]);
    }

    function trash(path: string): void {
        Quickshell.execDetached(["gio", "trash", "--", path]);
    }

    // Paste files copied in a file manager (text/uri-list in the clipboard) into the desktop folder.
    function paste(): void {
        Quickshell.execDetached(["sh", "-c", 'wl-paste --no-newline --type text/uri-list 2>/dev/null | python3 -I -c \'' + 'import sys, shutil, os, urllib.parse\n' + 'dst = sys.argv[1]\n' + 'for line in sys.stdin.read().splitlines():\n' + '    if not line.startswith("file://"): continue\n' + '    src = urllib.parse.unquote(line[7:])\n' + '    if not os.path.exists(src): continue\n' + '    name = os.path.basename(src.rstrip("/"))\n' + '    target = os.path.join(dst, name)\n' + '    i = 2\n' + '    while os.path.exists(target):\n' + '        base, ext = os.path.splitext(name)\n' + '        target = os.path.join(dst, "%s (%d)%s" % (base, i, ext)); i += 1\n' + '    (shutil.copytree if os.path.isdir(src) else shutil.copy2)(src, target)\n' + '\' "$1"', "sh", desktopDir]);
    }

    // ---- persistence ----
    function apply(text: string): void {
        let data = {};
        try {
            data = JSON.parse(text) ?? {};
        } catch (err) {
            data = {};
        }
        root.iconSize = (data.iconSize in root.iconSizes) ? data.iconSize : "large";
        root.sortBy = ["name", "type", "size"].includes(data.sortBy) ? data.sortBy : "name";
        root.rebuild();
    }

    Timer {
        id: saveTimer

        interval: 300
        onTriggered: file.setText(JSON.stringify({
            iconSize: root.iconSize,
            sortBy: root.sortBy
        }, null, 4) + "\n")
    }

    FileView {
        id: file

        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/hyprstack/desktop.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }

    // ---- the desktop folder ----
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
