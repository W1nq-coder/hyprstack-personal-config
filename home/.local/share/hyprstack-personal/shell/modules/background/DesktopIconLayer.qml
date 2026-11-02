pragma ComponentBehavior: Bound

// Personal overlay: desktop icons + right-click menu for the floating (Windows-like) layout.
// Content: the user's Desktop folder (see services/DesktopIcons.qml). Double click opens a file or
// folder with the default application / file manager, right click opens the context menu.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Hyprstack.Config
import Hyprstack.I18n
import Hyprstack.Models
import qs.components
import qs.services

Item {
    id: root

    required property ShellScreen screen

    readonly property bool ru: String(Tr.language || Qt.locale().name).startsWith("ru")
    function l(en: string, rus: string): string { return root.ru ? rus : en; }

    // The floating layout keeps its taskbar at the bottom: icons stay above it.
    readonly property real bottomReserve: ShellState.componentsFor(root.screen)?.bar?.exclusiveZone ?? 0
    readonly property real pad: Tokens.padding.large

    anchors.fill: parent

    // Empty desktop: left click clears the selection, right click opens the menu.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: mouse => {
            root.forceActiveFocus();   // finishes an in-place rename
            DesktopIcons.selected = "";
            if (mouse.button === Qt.RightButton)
                menu.openDesktop(mouse.x, mouse.y);
        }
    }

    GridView {
        id: grid

        anchors.fill: parent
        anchors.topMargin: root.pad
        anchors.leftMargin: root.pad
        anchors.rightMargin: root.pad
        anchors.bottomMargin: root.pad + root.bottomReserve

        // Icons fill a column from the top, then the next column (like the Windows desktop).
        flow: GridView.FlowTopToBottom
        cellWidth: DesktopIcons.iconPx + 40
        cellHeight: DesktopIcons.iconPx + 56
        interactive: false
        clip: true
        model: DesktopIcons.items

        delegate: DesktopItem {}
    }

    // ------------------------------------------------------------------ icon
    component DesktopItem: Item {
        id: item

        required property var modelData

        readonly property bool isSelected: DesktopIcons.selected === modelData.path
        readonly property bool isRenaming: DesktopIcons.renaming === modelData.path
        readonly property var appEntry: modelData.suffix === "desktop" ? (DesktopEntries.byId(modelData.name.replace(/\.desktop$/, "")) ?? DesktopEntries.heuristicLookup(modelData.name.replace(/\.desktop$/, ""))) : null
        readonly property string label: appEntry?.name ?? modelData.name

        width: grid.cellWidth
        height: grid.cellHeight

        Rectangle {
            anchors.fill: parent
            anchors.margins: 4
            radius: Tokens.rounding.large
            color: item.isSelected ? Qt.alpha(Colours.palette.m3primary, 0.30) : ma.containsMouse ? Qt.alpha(Colours.palette.m3onSurface, 0.12) : "transparent"
            border.width: item.isSelected ? 1 : 0
            border.color: Qt.alpha(Colours.palette.m3primary, 0.7)
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4

            Item {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: DesktopIcons.iconPx
                implicitHeight: DesktopIcons.iconPx

                // Pictures show a preview, everything else the theme icon for its type.
                Image {
                    anchors.fill: parent
                    visible: item.modelData.isImage
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(DesktopIcons.iconPx * 2, DesktopIcons.iconPx * 2)
                    source: item.modelData.isImage ? Qt.resolvedUrl(item.modelData.path) : ""
                }

                IconImage {
                    anchors.fill: parent
                    visible: !item.modelData.isImage
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

            anchors.fill: parent
            hoverEnabled: true
            enabled: !item.isRenaming
            acceptedButtons: Qt.LeftButton | Qt.RightButton

            onPressed: mouse => {
                root.forceActiveFocus();
                DesktopIcons.selected = item.modelData.path;
                if (mouse.button === Qt.RightButton) {
                    const p = mapToItem(root, mouse.x, mouse.y);
                    menu.openItem(item.modelData, p.x, p.y);
                }
            }
            onDoubleClicked: mouse => {
                if (mouse.button === Qt.LeftButton)
                    DesktopIcons.open(item.modelData);
            }
        }
    }

    // ------------------------------------------------------------------ menu
    Item {
        id: menu

        property var rows: []
        property string expanded: ""      // the open group
        property var target: null         // the icon the menu was opened on
        property real px
        property real py

        function show(x: real, y: real): void {
            px = x;
            py = y;
            expanded = "";
            visible = true;
        }

        function close(): void {
            visible = false;
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

        function build(): var {
            const D = DesktopIcons;
            const sizeOpt = (id, en, rus) => ({
                    text: root.l(en, rus),
                    checked: D.iconSize === id,
                    action: () => D.setIconSize(id)
                });
            const sortOpt = (id, en, rus) => ({
                    text: root.l(en, rus),
                    checked: D.sortBy === id,
                    action: () => D.setSortBy(id)
                });
            if (target) {
                const t = target;
                return [
                    {
                        text: root.l("Open", "Открыть"),
                        icon: "open_in_new",
                        action: () => D.open(t)
                    },
                    {
                        text: root.l("Rename", "Переименовать"),
                        icon: "edit",
                        action: () => D.renaming = t.path
                    },
                    {
                        sep: true
                    },
                    {
                        text: root.l("Move to trash", "В корзину"),
                        icon: "delete",
                        danger: true,
                        action: () => D.trash(t.path)
                    }
                ];
            }
            return [
                {
                    id: "view",
                    text: root.l("View", "Вид"),
                    icon: "grid_view",
                    children: [sizeOpt("large", "Large icons", "Крупные значки"), sizeOpt("medium", "Medium icons", "Средние значки"), sizeOpt("small", "Small icons", "Мелкие значки")]
                },
                {
                    id: "sort",
                    text: root.l("Sort by", "Сортировка"),
                    icon: "sort",
                    children: [sortOpt("name", "Name", "По имени"), sortOpt("type", "Type", "По типу"), sortOpt("size", "Size", "По размеру")]
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
                    children: [
                        {
                            text: root.l("Folder", "Папку"),
                            icon: "create_new_folder",
                            action: () => D.create("dir", root.l("New folder", "Новая папка"))
                        },
                        {
                            text: root.l("Text document", "Текстовый документ"),
                            icon: "note_add",
                            action: () => D.create("file", root.l("New text document", "Новый текстовый документ"))
                        }
                    ]
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

        // Flat list of visible rows: a group shows its children right under it when open.
        function flatten(): var {
            const out = [];
            for (const e of build()) {
                out.push(e);
                if (e.children && e.id === expanded)
                    for (const c of e.children)
                        out.push(Object.assign({
                            child: true
                        }, c));
            }
            return out;
        }

        anchors.fill: parent
        visible: false
        z: 100
        onVisibleChanged: if (visible)
            rows = flatten()
        onExpandedChanged: rows = flatten()

        // Click anywhere outside closes the menu.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: menu.close()
        }

        StyledRect {
            id: panel

            x: Math.max(8, Math.min(menu.px, menu.width - width - 8))
            y: Math.max(8, Math.min(menu.py, menu.height - height - 8 - root.bottomReserve))
            implicitWidth: 340
            implicitHeight: column.implicitHeight + 16
            radius: Tokens.rounding.large
            color: Colours.palette.m3surfaceContainer
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outline, 0.5)

            // Swallow clicks on the panel itself.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
            }

            ColumnLayout {
                id: column

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                spacing: 2

                Repeater {
                    model: menu.rows

                    Item {
                        id: row

                        required property var modelData

                        Layout.fillWidth: true
                        implicitHeight: modelData.sep ? 9 : 40

                        Rectangle {
                            visible: row.modelData.sep ?? false
                            anchors.centerIn: parent
                            width: parent.width - 16
                            height: 1
                            color: Qt.alpha(Colours.palette.m3outline, 0.4)
                        }

                        StateLayer {
                            visible: !(row.modelData.sep ?? false)
                            radius: Tokens.rounding.medium
                            onClicked: {
                                if (row.modelData.children)
                                    menu.expanded = menu.expanded === row.modelData.id ? "" : row.modelData.id;
                                else
                                    menu.run(row.modelData.action);
                            }
                        }

                        RowLayout {
                            visible: !(row.modelData.sep ?? false)
                            anchors.fill: parent
                            anchors.leftMargin: row.modelData.child ? 36 : 12
                            anchors.rightMargin: 12
                            spacing: 12

                            MaterialIcon {
                                text: row.modelData.checked ? "check" : (row.modelData.icon ?? "")
                                color: row.modelData.danger ? Colours.palette.m3error : row.modelData.checked ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: row.modelData.text ?? ""
                                color: row.modelData.danger ? Colours.palette.m3error : Colours.palette.m3onSurface
                                font: Tokens.font.body.medium
                            }

                            MaterialIcon {
                                visible: row.modelData.children !== undefined
                                text: menu.expanded === row.modelData.id ? "expand_less" : "chevron_right"
                                color: Colours.palette.m3onSurfaceVariant
                            }
                        }
                    }
                }
            }
        }
    }
}
