pragma ComponentBehavior: Bound

// Personal overlay: desktop icons + right-click menu for the floating (Windows-like) layout.
// Content: the user's Desktop folder (see services/DesktopIcons.qml).
//   - click selects, Ctrl+click adds, drag on an empty spot selects with a rubber band
//   - drag icons to any cell of the grid (several selected icons move together)
//   - double click / Enter opens, F2 renames, Delete moves to the trash, Ctrl+A / Ctrl+C / Ctrl+V
//   - right click: menu with side panels (View, Sort by, New, Icon) that open on hover

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Hyprstack.Config
import Hyprstack.I18n
import Hyprstack.Models
import qs.components
import qs.components.filedialog
import qs.services
import qs.utils

Item {
    id: root

    required property ShellScreen screen

    readonly property bool ru: String(Tr.language || Qt.locale().name).startsWith("ru")
    function l(en: string, rus: string): string { return root.ru ? rus : en; }

    // The floating layout keeps its taskbar at the bottom: icons stay above it.
    readonly property real bottomReserve: ShellState.componentsFor(root.screen)?.bar?.exclusiveZone ?? 0
    readonly property real pad: Tokens.padding.large
    readonly property real cellW: DesktopIcons.iconPx + 40
    readonly property real cellH: DesktopIcons.iconPx + 56
    readonly property int cols: Math.max(1, Math.floor((width - pad * 2) / cellW))
    readonly property int rows: Math.max(1, Math.floor((height - pad * 2 - bottomReserve) / cellH))

    function cellX(col: int): real { return root.pad + col * root.cellW; }
    function cellY(row: int): real { return root.pad + row * root.cellH; }

    // ---- drag state ----
    property bool dragging: false
    property real dragDx
    property real dragDy
    property var dragAnchor: null          // the icon the mouse grabbed

    // ---- rubber band ----
    property bool banding: false
    property real bandX0
    property real bandY0
    property real bandX1
    property real bandY1
    property var bandBase: ({})

    function updateBand(): void {
        const bx = Math.min(bandX0, bandX1), by = Math.min(bandY0, bandY1);
        const bw = Math.abs(bandX1 - bandX0), bh = Math.abs(bandY1 - bandY0);
        const sel = Object.assign({}, bandBase);
        for (const e of DesktopIcons.items) {
            const p = DesktopIcons.positions[e.name];
            if (!p)
                continue;
            const rx = cellX(p[0]) + 4, ry = cellY(p[1]) + 4, rw = cellW - 8, rh = cellH - 8;
            if (!(rx > bx + bw || rx + rw < bx || ry > by + bh || ry + rh < by))
                sel[e.path] = true;
        }
        DesktopIcons.selection = sel;
    }

    anchors.fill: parent
    focus: true

    Binding {
        target: DesktopIcons
        property: "cols"
        value: root.cols
    }

    Binding {
        target: DesktopIcons
        property: "rows"
        value: root.rows
    }

    Component.onCompleted: {
        DesktopIcons.layoutReady = true;
        DesktopIcons.autoPlace();
    }
    onRowsChanged: DesktopIcons.autoPlace()

    // ------------------------------------------------------------------ keyboard
    Keys.onPressed: event => {
        if (!DesktopIcons.showIcons)
            return;
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        const sel = DesktopIcons.selectedEntries();
        if (event.key === Qt.Key_Delete && sel.length > 0) {
            DesktopIcons.trash(sel.map(e => e.path));
        } else if (event.key === Qt.Key_F2 && sel.length === 1) {
            DesktopIcons.renaming = sel[0].path;
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && sel.length > 0) {
            DesktopIcons.openSelected();
        } else if (ctrl && event.key === Qt.Key_A) {
            DesktopIcons.selectAll();
        } else if (ctrl && event.key === Qt.Key_C && sel.length > 0) {
            DesktopIcons.copyFiles(sel.map(e => e.path));
        } else if (ctrl && event.key === Qt.Key_V) {
            DesktopIcons.paste();
        } else if (event.key === Qt.Key_Escape) {
            DesktopIcons.clearSelection();
        } else {
            return;
        }
        event.accepted = true;
    }

    // ------------------------------------------------------------------ empty desktop
    MouseArea {
        id: bg

        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onPressed: mouse => {
            root.forceActiveFocus();   // also finishes an in-place rename
            const ctrl = (mouse.modifiers & Qt.ControlModifier) !== 0;
            if (mouse.button === Qt.RightButton) {
                DesktopIcons.clearSelection();
                menu.openDesktop(mouse.x, mouse.y);
                return;
            }
            if (!DesktopIcons.showIcons)
                return;
            root.bandBase = ctrl ? Object.assign({}, DesktopIcons.selection) : ({});
            if (!ctrl)
                DesktopIcons.clearSelection();
            root.bandX0 = root.bandX1 = mouse.x;
            root.bandY0 = root.bandY1 = mouse.y;
        }
        onPositionChanged: mouse => {
            if (!(pressedButtons & Qt.LeftButton) || !DesktopIcons.showIcons)
                return;
            root.bandX1 = mouse.x;
            root.bandY1 = mouse.y;
            if (Math.abs(root.bandX1 - root.bandX0) + Math.abs(root.bandY1 - root.bandY0) > 6)
                root.banding = true;
            if (root.banding)
                root.updateBand();
        }
        onReleased: root.banding = false
    }

    Rectangle {
        visible: root.banding
        x: Math.min(root.bandX0, root.bandX1)
        y: Math.min(root.bandY0, root.bandY1)
        width: Math.abs(root.bandX1 - root.bandX0)
        height: Math.abs(root.bandY1 - root.bandY0)
        color: Qt.alpha(Colours.palette.m3primary, 0.18)
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3primary, 0.8)
        radius: 3
    }

    // Where the dragged icons will land.
    Rectangle {
        readonly property var p: root.dragAnchor ? DesktopIcons.positions[root.dragAnchor.name] : undefined
        readonly property int col: p ? Math.max(0, Math.min(root.cols - 1, p[0] + Math.round(root.dragDx / root.cellW))) : 0
        readonly property int row: p ? Math.max(0, Math.min(root.rows - 1, p[1] + Math.round(root.dragDy / root.cellH))) : 0

        visible: root.dragging && p !== undefined
        x: root.cellX(col) + 4
        y: root.cellY(row) + 4
        width: root.cellW - 8
        height: root.cellH - 8
        radius: Tokens.rounding.large
        color: Qt.alpha(Colours.palette.m3primary, 0.12)
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3primary, 0.5)
    }

    Repeater {
        model: DesktopIcons.showIcons ? DesktopIcons.items : []

        delegate: DesktopItem {}
    }

    // ------------------------------------------------------------------ icon
    component DesktopItem: Item {
        id: item

        required property var modelData

        readonly property var pos: DesktopIcons.positions[modelData.name]
        readonly property bool isSelected: DesktopIcons.selection[modelData.path] === true
        readonly property bool isRenaming: DesktopIcons.renaming === modelData.path
        readonly property bool moving: root.dragging && isSelected
        readonly property var appEntry: modelData.suffix === "desktop" ? (DesktopEntries.byId(modelData.name.replace(/\.desktop$/, "")) ?? DesktopEntries.heuristicLookup(modelData.name.replace(/\.desktop$/, ""))) : null
        readonly property string label: appEntry?.name ?? modelData.name
        readonly property string customIcon: DesktopIcons.customIcons[modelData.name] ?? ""

        visible: pos !== undefined
        x: pos ? root.cellX(pos[0]) + (moving ? root.dragDx : 0) : 0
        y: pos ? root.cellY(pos[1]) + (moving ? root.dragDy : 0) : 0
        z: moving ? 10 : 0
        opacity: moving ? 0.85 : 1
        width: root.cellW
        height: root.cellH

        Behavior on x {
            enabled: !root.dragging

            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }

        Behavior on y {
            enabled: !root.dragging

            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 4
            radius: Tokens.rounding.large
            color: item.isSelected ? Qt.alpha(Colours.palette.m3primary, 0.30) : ma.containsMouse ? Qt.alpha(Colours.palette.m3onSurface, 0.12) : "transparent"
            border.width: item.isSelected ? 1 : 0
            border.color: Qt.alpha(Colours.palette.m3primary, 0.7)

            Behavior on color {
                ColorAnimation {
                    duration: 120
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4

            Item {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: DesktopIcons.iconPx
                implicitHeight: DesktopIcons.iconPx

                // A chosen picture, a preview for pictures, otherwise the theme icon for the file type.
                Image {
                    anchors.fill: parent
                    visible: item.customIcon !== "" || item.modelData.isImage
                    asynchronous: true
                    fillMode: item.customIcon !== "" ? Image.PreserveAspectFit : Image.PreserveAspectCrop
                    sourceSize: Qt.size(DesktopIcons.iconPx * 2, DesktopIcons.iconPx * 2)
                    source: item.customIcon !== "" ? Qt.resolvedUrl(item.customIcon) : item.modelData.isImage ? Qt.resolvedUrl(item.modelData.path) : ""
                }

                IconImage {
                    anchors.fill: parent
                    visible: item.customIcon === "" && !item.modelData.isImage
                    asynchronous: true
                    source: {
                        if (item.modelData.isDir)
                            return Quickshell.iconPath("inode-directory", "folder");
                        if (item.appEntry)
                            return Quickshell.iconPath(item.appEntry.icon, "application-x-executable");
                        return Quickshell.iconPath(item.modelData.mimeType.replace("/", "-"), "application-x-zerosize");
                    }
                }
            }

            // Name: two lines at most; an input field while renaming.
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                StyledRect {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    visible: !item.isRenaming
                    width: Math.min(parent.width, nameText.implicitWidth + 12)
                    height: nameText.implicitHeight + 4
                    radius: Tokens.rounding.small
                    color: Qt.alpha(Colours.palette.m3surface, 0.62)

                    StyledText {
                        id: nameText

                        anchors.centerIn: parent
                        width: parent.parent.width - 12
                        horizontalAlignment: Text.AlignHCenter
                        text: item.label
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        font: Tokens.font.label.medium
                    }
                }

                Loader {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    width: parent.width
                    active: item.isRenaming

                    sourceComponent: StyledRect {
                        implicitHeight: edit.implicitHeight + 8
                        radius: Tokens.rounding.small
                        color: Colours.palette.m3surfaceContainerHighest
                        border.width: 1
                        border.color: Colours.palette.m3primary

                        TextInput {
                            id: edit

                            property bool done

                            anchors.fill: parent
                            anchors.margins: 4
                            color: Colours.palette.m3onSurface
                            selectionColor: Colours.palette.m3primary
                            selectedTextColor: Colours.palette.m3onPrimary
                            font: Tokens.font.label.medium
                            horizontalAlignment: TextInput.AlignHCenter
                            text: item.modelData.name
                            clip: true

                            function commit(): void {
                                if (done)
                                    return;
                                done = true;
                                DesktopIcons.rename(item.modelData.path, text);
                            }

                            Component.onCompleted: {
                                forceActiveFocus();
                                // Select the name without the extension, like a file manager does.
                                const dot = text.lastIndexOf(".");
                                select(0, dot > 0 && !item.modelData.isDir ? dot : text.length);
                            }
                            onAccepted: commit()
                            onActiveFocusChanged: if (!activeFocus)
                                commit()
                            Keys.onEscapePressed: {
                                done = true;
                                DesktopIcons.renaming = "";
                            }
                        }
                    }
                }
            }
        }

        MouseArea {
            id: ma

            property real startX
            property real startY
            property bool wasSelected
            property bool moved

            anchors.fill: parent
            hoverEnabled: true
            enabled: !item.isRenaming
            acceptedButtons: Qt.LeftButton | Qt.RightButton

            onPressed: mouse => {
                root.forceActiveFocus();
                const ctrl = (mouse.modifiers & Qt.ControlModifier) !== 0;
                wasSelected = item.isSelected;
                moved = false;
                const p = mapToItem(root, mouse.x, mouse.y);
                startX = p.x;
                startY = p.y;
                if (mouse.button === Qt.RightButton) {
                    // Right click keeps a multi-selection that already contains this icon.
                    if (!item.isSelected)
                        DesktopIcons.selectOnly(item.modelData.path);
                    menu.openItem(item.modelData, p.x, p.y);
                    return;
                }
                if (ctrl)
                    DesktopIcons.toggleSelected(item.modelData.path);
                else if (!item.isSelected)
                    DesktopIcons.selectOnly(item.modelData.path);
            }
            onPositionChanged: mouse => {
                if (!(pressedButtons & Qt.LeftButton) || !item.isSelected)
                    return;
                const p = mapToItem(root, mouse.x, mouse.y);
                if (!moved && Math.abs(p.x - startX) + Math.abs(p.y - startY) < 8)
                    return;
                moved = true;
                root.dragAnchor = item.modelData;
                root.dragDx = p.x - startX;
                root.dragDy = p.y - startY;
                root.dragging = true;
            }
            onReleased: mouse => {
                if (root.dragging && moved) {
                    DesktopIcons.moveSelection(Math.round(root.dragDx / root.cellW), Math.round(root.dragDy / root.cellH));
                } else if (!moved && wasSelected && !(mouse.modifiers & Qt.ControlModifier) && mouse.button === Qt.LeftButton) {
                    // A plain click on an icon of a multi-selection selects just that one.
                    DesktopIcons.selectOnly(item.modelData.path);
                }
                root.dragging = false;
                root.dragAnchor = null;
                root.dragDx = root.dragDy = 0;
            }
            onDoubleClicked: mouse => {
                if (mouse.button === Qt.LeftButton)
                    DesktopIcons.open(item.modelData);
            }
        }
    }

    // ------------------------------------------------------------------ choose a picture for an icon
    FileDialog {
        id: iconDialog

        property string targetName

        title: root.l("Select a picture for the icon", "Выберите картинку для значка")
        filterLabel: root.l("Image files", "Изображения")
        filters: Images.validImageExtensions
        onAccepted: path => DesktopIcons.setCustomIcon(targetName, path)
    }

    // ------------------------------------------------------------------ menu
    Item {
        id: menu

        property var rows: []
        property var target: null          // the icon the menu was opened on, if any
        property real px
        property real py
        property string openGroup: ""      // id of the group whose side panel is open
        property var subRows: []
        property real subY
        property bool shown: false

        function show(x: real, y: real): void {
            px = x;
            py = y;
            openGroup = "";
            rows = build();
            visible = true;
            shown = true;
        }

        function close(): void {
            shown = false;
            openGroup = "";
            hideTimer.restart();
        }

        function openDesktop(x: real, y: real): void {
            target = null;
            show(x, y);
        }

        function openItem(entry: var, x: real, y: real): void {
            target = entry;
            show(x, y);
        }

        function run(fn: var): void {
            close();
            fn();
        }

        // Hover on a group row opens its side panel next to the row.
        function hoverGroup(entry: var, rowItem: Item): void {
            closeTimer.stop();
            if (openGroup === entry.id)
                return;
            subRows = entry.children;
            subY = rowItem.mapToItem(menu, 0, 0).y - 8;
            openGroup = entry.id;
        }

        function hoverPlain(): void {
            closeTimer.restart();
        }

        function build(): var {
            const D = DesktopIcons;
            const opt = (checked, en, rus, fn) => ({
                    text: root.l(en, rus),
                    checked: checked,
                    action: fn
                });
            if (target) {
                const sel = D.selectedEntries();
                const many = sel.length > 1;
                const t = target;
                return [
                    {
                        text: many ? root.l("Open (%1)", "Открыть (%1)").arg(sel.length) : root.l("Open", "Открыть"),
                        icon: "open_in_new",
                        action: () => D.openSelected()
                    },
                    {
                        text: root.l("Copy", "Копировать"),
                        icon: "content_copy",
                        action: () => D.copyFiles(sel.map(e => e.path))
                    },
                    {
                        text: root.l("Rename", "Переименовать"),
                        icon: "edit",
                        disabled: many,
                        action: () => D.renaming = t.path
                    },
                    {
                        id: "icon",
                        text: root.l("Icon", "Значок"),
                        icon: "image",
                        disabled: many,
                        children: [
                            {
                                text: root.l("Change icon…", "Сменить значок…"),
                                icon: "add_photo_alternate",
                                action: () => {
                                    iconDialog.targetName = t.name;
                                    iconDialog.open();
                                }
                            },
                            {
                                text: root.l("Reset icon", "Сбросить значок"),
                                icon: "restart_alt",
                                disabled: !(D.customIcons[t.name] ?? ""),
                                action: () => D.setCustomIcon(t.name, "")
                            }
                        ]
                    },
                    {
                        text: root.l("Copy path", "Копировать путь"),
                        icon: "link",
                        action: () => D.copyText(sel.map(e => e.path).join("\n"))
                    },
                    {
                        sep: true
                    },
                    {
                        text: many ? root.l("Move to trash (%1)", "В корзину (%1)").arg(sel.length) : root.l("Move to trash", "В корзину"),
                        icon: "delete",
                        danger: true,
                        action: () => D.trash(sel.map(e => e.path))
                    }
                ];
            }
            return [
                {
                    id: "view",
                    text: root.l("View", "Вид"),
                    icon: "grid_view",
                    children: [opt(D.showIcons, "Show icons", "Показывать значки", () => D.setShowIcons(!D.showIcons)), {
                            sep: true
                        }, opt(D.iconSize === "large", "Large icons", "Крупные значки", () => D.setIconSize("large")), opt(D.iconSize === "medium", "Medium icons", "Средние значки", () => D.setIconSize("medium")), opt(D.iconSize === "small", "Small icons", "Мелкие значки", () => D.setIconSize("small"))]
                },
                {
                    id: "sort",
                    text: root.l("Sort by", "Сортировка"),
                    icon: "sort",
                    children: [opt(D.sortBy === "name", "Name", "По имени", () => D.setSortBy("name")), opt(D.sortBy === "type", "Type", "По типу", () => D.setSortBy("type")), opt(D.sortBy === "size", "Size", "По размеру", () => D.setSortBy("size"))]
                },
                {
                    text: root.l("Refresh", "Обновить"),
                    icon: "refresh",
                    action: () => D.rebuild()
                },
                {
                    sep: true
                },
                {
                    id: "new",
                    text: root.l("New", "Создать"),
                    icon: "add",
                    children: D.newTypes.map(t => ({
                                text: root.ru ? t[3].replace(/^Нов(ая|ый|ое) /, "") .replace(/^./, c => c.toUpperCase()) : t[2].replace(/^New /, "").replace(/^./, c => c.toUpperCase()),
                                icon: ({
                                        dir: "create_new_folder",
                                        txt: "description",
                                        md: "markdown",
                                        html: "html",
                                        py: "terminal",
                                        sh: "terminal",
                                        json: "data_object",
                                        empty: "note_add"
                                    })[t[0]],
                                action: () => D.create(t[0], root.ru ? t[3] : t[2], t[1])
                            }))
                },
                {
                    text: root.l("Paste", "Вставить"),
                    icon: "content_paste",
                    action: () => D.paste()
                },
                {
                    text: root.l("Open terminal here", "Открыть терминал здесь"),
                    icon: "terminal",
                    action: () => D.openTerminalHere()
                },
                {
                    sep: true
                },
                {
                    text: root.l("Hide all windows", "Скрыть все окна"),
                    icon: "desktop_windows",
                    action: () => D.hideAllWindows()
                },
                {
                    text: root.l("Change wallpaper", "Сменить обои"),
                    icon: "wallpaper",
                    action: () => D.openSettings(1)
                },
                {
                    text: root.l("HyperStack settings", "Настройки HyperStack"),
                    icon: "settings",
                    action: () => D.openSettings(0)
                }
            ];
        }

        anchors.fill: parent
        visible: false
        z: 100

        // After the fade-out the whole menu stops taking clicks.
        Timer {
            id: hideTimer

            interval: 160
            onTriggered: if (!menu.shown)
                menu.visible = false
        }

        // Leaving a group row for another row closes the side panel after a short grace period.
        Timer {
            id: closeTimer

            interval: 220
            onTriggered: menu.openGroup = ""
        }

        // A click anywhere outside closes the menu.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: menu.close()
        }

        // ---- main panel ----
        StyledRect {
            id: panel

            x: Math.max(8, Math.min(menu.px, menu.width - width - 8))
            y: Math.max(8, Math.min(menu.py, menu.height - height - 8 - root.bottomReserve))
            implicitWidth: 300
            implicitHeight: mainColumn.implicitHeight + 16
            radius: Tokens.rounding.large
            color: Colours.palette.m3surfaceContainer
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outline, 0.5)
            opacity: menu.shown ? 1 : 0
            scale: menu.shown ? 1 : 0.96
            transformOrigin: Item.TopLeft

            Behavior on opacity {
                NumberAnimation {
                    duration: 130
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on scale {
                NumberAnimation {
                    duration: 130
                    easing.type: Easing.OutCubic
                }
            }

            // Swallow clicks on the panel itself.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
            }

            ColumnLayout {
                id: mainColumn

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                spacing: 2

                Repeater {
                    model: menu.rows

                    MenuRow {
                        required property var modelData

                        entry: modelData
                        sub: false
                    }
                }
            }
        }

        // ---- side panel of the group under the pointer ----
        StyledRect {
            id: subPanel

            readonly property bool rightSide: panel.x + panel.width + 4 + width + 8 <= menu.width

            x: (rightSide ? panel.x + panel.width + 4 : panel.x - width - 4) + (open ? 0 : (rightSide ? -10 : 10))
            y: Math.max(8, Math.min(menu.subY, menu.height - height - 8 - root.bottomReserve))
            readonly property bool open: menu.shown && menu.openGroup !== ""
            implicitWidth: 300
            implicitHeight: subColumn.implicitHeight + 16
            radius: Tokens.rounding.large
            color: Colours.palette.m3surfaceContainer
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outline, 0.5)
            opacity: open ? 1 : 0
            visible: opacity > 0

            Behavior on x {
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on y {
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 130
                    easing.type: Easing.OutCubic
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onEntered: closeTimer.stop()
            }

            ColumnLayout {
                id: subColumn

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                spacing: 2

                Repeater {
                    model: menu.subRows

                    MenuRow {
                        required property var modelData

                        entry: modelData
                        sub: true
                    }
                }
            }
        }
    }

    // One row of a menu panel.
    component MenuRow: Item {
        id: row

        property var entry
        property bool sub

        readonly property bool isSep: entry.sep ?? false
        readonly property bool isGroup: entry.children !== undefined
        readonly property bool disabled: entry.disabled ?? false

        Layout.fillWidth: true
        implicitHeight: isSep ? 9 : 40
        opacity: disabled ? 0.45 : 1

        Rectangle {
            visible: row.isSep
            anchors.centerIn: parent
            width: parent.width - 16
            height: 1
            color: Qt.alpha(Colours.palette.m3outline, 0.4)
        }

        // Keeps the group highlighted while its side panel is open.
        Rectangle {
            anchors.fill: parent
            visible: row.isGroup && !row.sub
            radius: Tokens.rounding.medium
            color: Qt.alpha(Colours.palette.m3onSurface, menu.openGroup === row.entry.id ? 0.10 : 0)

            Behavior on color {
                ColorAnimation {
                    duration: 120
                }
            }
        }

        StateLayer {
            visible: !row.isSep
            disabled: row.disabled
            radius: Tokens.rounding.medium
            onEntered: {
                if (row.sub)
                    closeTimer.stop();
                else if (row.isGroup && !row.disabled)
                    menu.hoverGroup(row.entry, row);
                else
                    menu.hoverPlain();
            }
            onClicked: {
                if (row.isGroup)
                    menu.hoverGroup(row.entry, row);
                else
                    menu.run(row.entry.action);
            }
        }

        RowLayout {
            visible: !row.isSep
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 12

            MaterialIcon {
                text: row.entry.checked ? "check" : (row.entry.icon ?? "")
                color: row.entry.danger ? Colours.palette.m3error : row.entry.checked ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            }

            StyledText {
                Layout.fillWidth: true
                text: row.entry.text ?? ""
                color: row.entry.danger ? Colours.palette.m3error : Colours.palette.m3onSurface
                font: Tokens.font.body.medium
                elide: Text.ElideRight
            }

            MaterialIcon {
                visible: row.isGroup
                text: "chevron_right"
                color: Colours.palette.m3onSurfaceVariant
            }
        }
    }
}
