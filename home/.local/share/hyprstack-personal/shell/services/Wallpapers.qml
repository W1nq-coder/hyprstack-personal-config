pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Hyprstack.Config
import Hyprstack.Models
import qs.services
import qs.utils

Searcher {
    id: root

    readonly property string currentNamePath: `${Paths.state}/wallpaper/path.txt`
    readonly property list<string> smartArg: GlobalConfig.services.smartScheme ? [] : ["--no-smart"]

    property bool showPreview: false
    readonly property string current: showPreview ? previewPath : actualCurrent
    property string previewPath
    property string actualCurrent
    property bool previewColourLock
    property bool pendingPreviewClear

    // ---- Personal overlay: wallpaper folders added with "Browse" (kept between sessions) ----
    // Stored in ~/.config/hyprstack/wallpaper-sources.json: {"folders": ["/path", ...]}.
    // Pictures picked one by one are copied to <wallpapers dir>/<userCategory>.
    readonly property string userCategory: "My wallpapers"
    readonly property string sourcesPath: `${Paths.config}/wallpaper-sources.json`
    property list<string> sources: []
    // Entries of every model: the main folder first, then each added folder.
    property var extraEntries: []

    function isInsideMain(path: string): bool {
        return path === Paths.wallsdir || path.startsWith(Paths.wallsdir + "/");
    }

    function sourceFor(w: FileSystemEntry): string {
        for (const s of sources)
            if (w.path.startsWith(s + "/"))
                return s;
        return "";
    }

    function baseName(path: string): string {
        return path.replace(/\/+$/, "").split("/").pop();
    }

    function saveSources(): void {
        sourcesFile.setText(JSON.stringify({
            folders: root.sources
        }, null, 4) + "\n");
    }

    function addSource(path: string): void {
        path = path.replace(/\/+$/, "");
        // Too broad: "/" or the home folder itself (or anything that contains it) would make the shell
        // scan the whole disk recursively.
        if (!path || path === Paths.home || Paths.home.startsWith(path + "/"))
            return;
        // Already shown: the main folder or one that is already added.
        if (isInsideMain(path) || sources.includes(path) || sources.some(s => path.startsWith(s + "/")))
            return;
        // A parent of existing sources replaces them.
        sources = [...sources.filter(s => !s.startsWith(path + "/")), path];
        saveSources();
    }

    function removeSource(path: string): void {
        sources = sources.filter(s => s !== path);
        saveSources();
    }

    // Add one picture: copy it into the user category (unless it is already visible) and select it.
    function addFile(path: string): void {
        if (isInsideMain(path) || sources.some(s => path.startsWith(s + "/"))) {
            setWallpaper(path);
            return;
        }
        copyProc.command = ["sh", "-c", 'd="$1"; f="$2"; mkdir -p "$d" || exit 1; b=$(basename "$f"); t="$d/$b"; if [ -e "$t" ] && ! cmp -s "$f" "$t"; then t="$d/${b%.*}-$(date +%s).${b##*.}"; fi; [ -e "$t" ] || cp -- "$f" "$t" || exit 1; printf "%s" "$t"', "sh", `${Paths.wallsdir}/${userCategory}`, path];
        copyProc.running = true;
    }

    function getCategoryFor(w: FileSystemEntry): string {
        if (!isInsideMain(w.path)) {
            const source = sourceFor(w);
            if (source)
                return baseName(source);
        }
        let category = w.parentDir.slice(Paths.wallsdir.length + 1);
        if (category.includes("/"))
            category = category.slice(0, category.indexOf("/"));
        return category;
    }

    function setRandom(): void {
        Quickshell.execDetached(["hyprstack", "wallpaper", "-r", ...smartArg]);
    }

    function setWallpaper(path: string): void {
        actualCurrent = path;
        Quickshell.execDetached(["hyprstack", "wallpaper", "-f", path, ...smartArg]);
    }

    function preview(path: string): void {
        previewPath = path;
        showPreview = true;
        pendingPreviewClear = false;

        if (Colours.scheme === "dynamic")
            requestPreviewColours();
        else
            Colours.showPreview = false;
    }

    function requestPreviewColours(): void {
        if (!showPreview || Colours.scheme !== "dynamic" || getPreviewColoursProc.running)
            return;
        getPreviewColoursProc.requestedPath = previewPath;
        getPreviewColoursProc.running = true;
    }

    function stopPreview(): void {
        showPreview = false;
        if (previewColourLock)
            pendingPreviewClear = true;
        else
            Colours.showPreview = false;
    }

    onPreviewColourLockChanged: {
        if (!previewColourLock && pendingPreviewClear)
            Colours.showPreview = false;
    }

    list: extraEntries
    key: "relativePath"
    useFuzzy: GlobalConfig.launcher.useFuzzy.wallpapers
    extraOpts: useFuzzy ? ({}) : ({
            forward: false
        })

    IpcHandler {
        function get(): string {
            return root.actualCurrent;
        }

        function set(path: string): void {
            root.setWallpaper(path);
        }

        function list(): string {
            return root.list.map(w => w.path).join("\n");
        }

        target: "wallpaper"
    }

    FileView {
        path: root.currentNamePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.actualCurrent = text().trim();
            root.previewColourLock = false;
        }
        onLoadFailed: {
            root.actualCurrent = "";
            root.previewColourLock = false;
        }
    }

    FileSystemModel {
        id: wallpapers

        recursive: true
        path: Paths.wallsdir
        filter: FileSystemModel.Images
        onEntriesChanged: root.rebuild()
    }

    // One model per added folder.
    Instantiator {
        id: extraModels

        model: root.sources

        FileSystemModel {
            required property string modelData

            recursive: true
            path: modelData
            filter: FileSystemModel.Images
            onEntriesChanged: root.rebuild()
        }

        onObjectAdded: root.rebuild()
        onObjectRemoved: Qt.callLater(root.rebuild)
    }

    function rebuild(): void {
        const all = [...wallpapers.entries];
        for (let i = 0; i < extraModels.count; i++)
            all.push(...extraModels.objectAt(i).entries);
        extraEntries = all;
    }

    onSourcesChanged: Qt.callLater(rebuild)

    FileView {
        id: sourcesFile

        path: root.sourcesPath
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text()) ?? {};
                const folders = (data.folders ?? []).filter(f => typeof f === "string" && f.startsWith("/") && f.length > 1 && f !== Paths.home && !Paths.home.startsWith(f + "/"));
                if (JSON.stringify(folders) !== JSON.stringify(root.sources))
                    root.sources = folders;
            } catch (err) {
                root.sources = [];
            }
        }
    }

    Process {
        id: copyProc

        stdout: StdioCollector {
            onStreamFinished: if (text.trim())
                root.setWallpaper(text.trim())
        }
    }

    Process {
        id: getPreviewColoursProc

        property string requestedPath
        command: ["hyprstack", "wallpaper", "-p", requestedPath, ...root.smartArg]
        onExited: if (requestedPath !== root.previewPath) Qt.callLater(root.requestPreviewColours)
        stdout: StdioCollector {
            onStreamFinished: {
                // A cancelled preview must not replace the selected static
                // theme when its asynchronous colour extraction finishes.
                if (!root.showPreview || Colours.scheme !== "dynamic" || getPreviewColoursProc.requestedPath !== root.previewPath)
                    return;
                Colours.load(text, true);
                Colours.showPreview = true;
            }
        }
    }
}
