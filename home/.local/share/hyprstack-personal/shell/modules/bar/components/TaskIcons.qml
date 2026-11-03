// Personal overlay: applications of the floating layout as icons only. Used for the "icons only"
// view of the taskbar, on a vertical taskbar and in the GNOME-style dock. Same behaviour as the
// labelled list (Tasks.qml): click shows/minimises, middle click closes, wheel switches between the
// windows of one application, right click opens the menu (pin, new window, window actions).
// Pinned applications and their order come from services/Taskbar.qml.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.services
import qs.utils

StyledClippingRect {
    id: root

    required property ShellScreen screen
    // Edge of the screen the host (taskbar or dock) stands on: popups open to the opposite side.
    property string edge: "bottom"
    property bool dock: false
    property real maxLength: 100000
    readonly property bool vertical: edge === "left" || edge === "right"

    readonly property real look: (dock ? TaskbarStyle.dockScale : TaskbarStyle.barScale) / 100
    readonly property real across: (dock ? 52 : 40) * Tokens.scale * look
    readonly property real iconSize: (dock ? 34 : 22) * Tokens.scale * look
    readonly property real inset: Tokens.padding.extraSmall
    readonly property var appEntries: DesktopEntries.applications.values
    property Item menuTask: null
    property string lastTargets: ""

    function lookup(app: string): var {
        return appEntries.find(e => !!e.startupClass && e.startupClass.toLowerCase() === app.toLowerCase())
            ?? DesktopEntries.heuristicLookup(app)
            ?? DesktopEntries.heuristicLookup(app.replace(/-browser$/, ""))
            ?? DesktopEntries.heuristicLookup(app.replace(/\.desktop$/, "").split(".").pop());
    }

    readonly property var groups: {
        const groups = new Map();
        const windows = Hypr.taskWindows(screen).slice().sort((a, b) =>
            a.lastIpcObject.stableId.localeCompare(b.lastIpcObject.stableId));
        for (const window of windows) {
            const app = window.lastIpcObject.class;
            const entry = lookup(app);
            const key = entry?.id ?? app.toLowerCase();
            if (!groups.has(key))
                groups.set(key, { app: app, key: key, entry: entry, windows: [] });
            groups.get(key).windows.push(window);
        }
        for (const key of Taskbar.pinned) {
            if (groups.has(key))
                continue;
            const entry = DesktopEntries.byId(key) ?? lookup(key);
            if (entry)
                groups.set(key, { app: key, key: key, entry: entry, windows: [] });
        }
        return Array.from(groups.values()).sort((a, b) => {
            const ai = Taskbar.order.indexOf(a.key), bi = Taskbar.order.indexOf(b.key);
            return (ai < 0 ? 100000 : ai) - (bi < 0 ? 100000 : bi);
        });
    }

    // Where each button is on the screen: the window manager uses it for the minimise animation.
    function reportTargets(): void {
        if (!Hypr.stacking || !visible || !QsWindow.window)
            return;
        const targets = [];
        const monitor = Hypr.monitorFor(screen)?.lastIpcObject;
        const originX = monitor?.x ?? screen.x, originY = monitor?.y ?? screen.y;
        const barTop = originY + mapToItem(QsWindow.window.contentItem, 0, 0).y;
        for (let i = 0; i < repeater.count; i++) {
            const button = repeater.itemAt(i);
            if (!button)
                continue;
            const p = button.mapToItem(QsWindow.window.contentItem, 0, 0);
            for (const window of button.windows)
                targets.push({ address: window.lastIpcObject.address, id: window.lastIpcObject.stableId,
                    x: Math.round(originX + p.x), y: Math.round(originY + p.y),
                    w: Math.round(button.width), h: Math.round(button.height), barTop: Math.round(barTop) });
        }
        const data = JSON.stringify(targets);
        if (data !== lastTargets) {
            lastTargets = data;
            Hypr.setTaskTargets(screen.name, targets);
        }
    }

    function closePopup(): void {
        if (menuTask)
            menuTask.menuOpen = false;
        menuTask = null;
    }

    onVisibleChanged: {
        if (!visible) {
            closePopup();
            Hypr.setTaskTargets(screen.name, []);
        }
        lastTargets = "";
    }
    onGroupsChanged: Qt.callLater(reportTargets)

    implicitWidth: vertical ? across : Math.min(maxLength, flick.contentWidth + inset * 2)
    implicitHeight: vertical ? Math.min(maxLength, flick.contentHeight + inset * 2) : across
    radius: dock ? Tokens.rounding.large : Tokens.rounding.full
    color: "transparent"

    GroupBackground {
        visible: !root.dock
    }

    Timer {
        interval: 250
        repeat: true
        triggeredOnStart: true
        running: root.visible && Hypr.stacking
        onTriggered: root.reportTargets()
    }

    Flickable {
        id: flick

        anchors.fill: parent
        anchors.margins: root.inset
        contentWidth: grid.implicitWidth
        contentHeight: grid.implicitHeight
        flickableDirection: root.vertical ? Flickable.VerticalFlick : Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        GridLayout {
            id: grid

            x: root.vertical ? 0 : Math.max(0, (flick.width - implicitWidth) / 2)
            y: root.vertical ? Math.max(0, (flick.height - implicitHeight) / 2) : 0
            width: implicitWidth
            height: implicitHeight
            flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
            rows: root.vertical ? Math.max(1, repeater.count) : 1
            columns: root.vertical ? 1 : Math.max(1, repeater.count)
            rowSpacing: Tokens.spacing.extraSmall
            columnSpacing: Tokens.spacing.extraSmall

            Repeater {
                id: repeater

                model: ScriptModel {
                    values: root.groups.map(g => g.app)
                }

                delegate: Item {
                    id: task

                    required property string modelData

                    readonly property var group: root.groups.find(g => g.app === modelData)
                    readonly property var windows: group?.windows ?? []
                    readonly property bool active: windows.some(w => w === Hypr.activeToplevel && !Hypr.isMinimized(w))
                    readonly property bool allMinimized: windows.length > 0 && windows.every(w => Hypr.isMinimized(w))
                    readonly property bool pinned: Taskbar.pinned.includes(group?.key ?? "")
                    readonly property var entry: group?.entry
                    readonly property string iconSource: entry?.icon ? Quickshell.iconPath(entry.icon, true) : ""
                    readonly property string label: entry?.name ?? modelData
                    property bool menuOpen
                    property bool tipOpen

                    implicitWidth: root.across - root.inset * 2
                    implicitHeight: root.across - root.inset * 2
                    onMenuOpenChanged: if (!menuOpen && root.menuTask === task)
                        root.menuTask = null

                    function showMenu(): void {
                        root.closePopup();
                        tipOpen = false;
                        menuOpen = true;
                        root.menuTask = task;
                    }

                    function act(operation: string, window: HyprlandToplevel): void {
                        tipTimer.stop();
                        tipOpen = false;
                        root.reportTargets();
                        root.closePopup();
                        Hypr.windowAction(operation, window);
                    }

                    function clickAction(): var {
                        const ordered = windows.slice().sort((a, b) =>
                            (a.lastIpcObject.focusHistoryID < 0 ? 100000 : a.lastIpcObject.focusHistoryID)
                            - (b.lastIpcObject.focusHistoryID < 0 ? 100000 : b.lastIpcObject.focusHistoryID));
                        const current = ordered.find(w => w === Hypr.activeToplevel && !Hypr.isMinimized(w));
                        if (ordered.length === 1)
                            return { operation: "task-click", window: ordered[0] };
                        return { operation: "activate", window: current ? ordered[1] : ordered[0] };
                    }

                    function launch(): void {
                        root.closePopup();
                        entry?.execute();
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: root.dock ? Tokens.rounding.medium : Tokens.rounding.full
                        color: task.active ? Qt.alpha(Colours.palette.m3primary, 0.30) : mouse.containsMouse || task.menuOpen ? Qt.alpha(Colours.palette.m3onSurface, 0.12) : "transparent"

                        Behavior on color {
                            ColorAnimation {
                                duration: 120
                            }
                        }
                    }

                    IconImage {
                        id: appIcon

                        anchors.centerIn: parent
                        implicitSize: root.iconSize
                        visible: !!task.iconSource && status !== Image.Error
                        source: task.iconSource
                        opacity: task.allMinimized ? 0.55 : 1
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        visible: !appIcon.visible
                        text: Icons.getAppCategoryIcon(task.entry?.id ?? task.modelData, "apps")
                        color: Colours.palette.m3onSurface
                        opacity: task.allMinimized ? 0.55 : 1
                    }

                    // One dot per open window (up to three) on the screen-side edge of the button.
                    Row {
                        visible: task.windows.length > 0 && !root.vertical
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 1
                        spacing: 3

                        Repeater {
                            model: Math.min(task.windows.length, 3)

                            Rectangle {
                                width: 4
                                height: 4
                                radius: 2
                                color: task.active ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                            }
                        }
                    }

                    Column {
                        visible: task.windows.length > 0 && root.vertical
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: root.edge === "left" ? parent.left : undefined
                        anchors.right: root.edge === "right" ? parent.right : undefined
                        anchors.leftMargin: 1
                        anchors.rightMargin: 1
                        spacing: 3

                        Repeater {
                            model: Math.min(task.windows.length, 3)

                            Rectangle {
                                width: 4
                                height: 4
                                radius: 2
                                color: task.active ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                            }
                        }
                    }

                    MouseArea {
                        id: mouse

                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor
                        onEntered: if (!task.menuOpen)
                            tipTimer.restart()
                        onExited: {
                            tipTimer.stop();
                            task.tipOpen = false;
                        }
                        onClicked: event => {
                            task.tipOpen = false;
                            if (event.button === Qt.RightButton) {
                                task.showMenu();
                            } else if (task.windows.length === 0) {
                                task.launch();
                            } else if (event.button === Qt.MiddleButton) {
                                const window = task.windows.find(w => w === Hypr.activeToplevel) ?? task.windows[0];
                                task.act("close", window);
                            } else {
                                const action = task.clickAction();
                                if (action.window)
                                    task.act(action.operation, action.window);
                            }
                        }
                        onWheel: event => {
                            if (task.windows.length === 0)
                                return;
                            const current = task.windows.findIndex(w => w === Hypr.activeToplevel);
                            const next = (current + (event.angleDelta.y > 0 ? 1 : -1) + task.windows.length) % task.windows.length;
                            task.act("activate", task.windows[next]);
                            event.accepted = true;
                        }
                    }

                    Timer {
                        id: tipTimer

                        interval: 450
                        onTriggered: task.tipOpen = true
                    }

                    // ---- name of the application (and of the window when there is just one) ----
                    PopupWindow {
                        anchor.item: task
                        anchor.edges: root.edge === "bottom" ? Edges.Top : root.edge === "top" ? Edges.Bottom : root.edge === "left" ? Edges.Right : Edges.Left
                        anchor.gravity: anchor.edges
                        anchor.rect.y: root.edge === "bottom" ? -8 : root.edge === "top" ? 8 : 0
                        anchor.rect.x: root.edge === "right" ? -8 : root.edge === "left" ? 8 : 0
                        visible: task.tipOpen && !task.menuOpen
                        color: "transparent"
                        implicitWidth: Math.min(root.screen.width / 3, tipText.implicitWidth + 24)
                        implicitHeight: tipText.implicitHeight + 16

                        Rectangle {
                            anchors.fill: parent
                            color: Colours.palette.m3surfaceContainerHigh
                            border.color: Colours.palette.m3outlineVariant
                            border.width: 1
                            radius: Tokens.rounding.medium

                            StyledText {
                                id: tipText

                                anchors.centerIn: parent
                                width: parent.width - 24
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: task.windows.length === 1 && task.windows[0]?.title ? `${task.label} — ${task.windows[0].title}` : task.label
                                font: Tokens.font.body.small
                            }
                        }
                    }

                    // ---- right click menu ----
                    PopupWindow {
                        anchor.item: task
                        anchor.edges: root.edge === "bottom" ? Edges.Top : root.edge === "top" ? Edges.Bottom : root.edge === "left" ? Edges.Right : Edges.Left
                        anchor.gravity: anchor.edges
                        anchor.rect.y: root.edge === "bottom" ? -8 : root.edge === "top" ? 8 : 0
                        anchor.rect.x: root.edge === "right" ? -8 : root.edge === "left" ? 8 : 0
                        visible: task.menuOpen
                        grabFocus: true
                        onVisibleChanged: if (!visible)
                            task.menuOpen = false
                        color: "transparent"
                        implicitWidth: Math.min(root.screen.width - 24, 300 * Tokens.scale)
                        implicitHeight: menuColumn.implicitHeight + 24 * Tokens.scale

                        Rectangle {
                            anchors.fill: parent
                            color: Colours.palette.m3surfaceContainerLow
                            border.color: Colours.palette.m3outlineVariant
                            border.width: 1
                            radius: Tokens.rounding.large
                            focus: true
                            Keys.onEscapePressed: task.menuOpen = false

                            Column {
                                id: menuColumn

                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: 12 * Tokens.scale
                                spacing: 4 * Tokens.scale

                                StyledText {
                                    width: parent.width
                                    text: task.label
                                    elide: Text.ElideRight
                                    font: Tokens.font.body.medium
                                }

                                MenuButton {
                                    width: parent.width
                                    visible: !!task.entry
                                    text: task.pinned ? Tr.tr("Unpin from taskbar") : Tr.tr("Pin to taskbar")
                                    onClicked: {
                                        root.closePopup();
                                        Taskbar.togglePin(task.group.key);
                                    }
                                }

                                MenuButton {
                                    width: parent.width
                                    visible: !!task.entry
                                    text: Tr.tr("Open new window")
                                    onClicked: task.launch()
                                }

                                Repeater {
                                    model: ScriptModel {
                                        values: task.windows
                                    }

                                    delegate: Column {
                                        id: menuWindow

                                        required property HyprlandToplevel modelData

                                        width: menuColumn.width
                                        spacing: 4 * Tokens.scale

                                        StyledText {
                                            width: parent.width
                                            text: menuWindow.modelData?.title ?? ""
                                            elide: Text.ElideRight
                                            font: Tokens.font.body.small
                                            color: Colours.palette.m3onSurfaceVariant
                                        }

                                        Row {
                                            spacing: 6 * Tokens.scale

                                            WindowButton {
                                                icon: "open_in_full"
                                                onClicked: task.act("activate", menuWindow.modelData)
                                            }

                                            WindowButton {
                                                icon: "minimize"
                                                onClicked: task.act("minimize", menuWindow.modelData)
                                            }

                                            WindowButton {
                                                icon: Hypr.isMaximized(menuWindow.modelData) ? "filter_none" : "crop_square"
                                                onClicked: task.act("maximize", menuWindow.modelData)
                                            }

                                            WindowButton {
                                                icon: "close"
                                                danger: true
                                                onClicked: task.act("close", menuWindow.modelData)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    component MenuButton: Rectangle {
        required property string text
        signal clicked

        implicitHeight: 34 * Tokens.scale
        radius: Tokens.rounding.small
        color: click.containsMouse ? Colours.palette.m3surfaceContainerHigh : "transparent"

        StyledText {
            anchors.fill: parent
            anchors.leftMargin: 6 * Tokens.scale
            verticalAlignment: Text.AlignVCenter
            text: parent.text
            font: Tokens.font.body.small
        }

        MouseArea {
            id: click

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    component WindowButton: Rectangle {
        required property string icon
        property bool danger
        signal clicked

        width: 38 * Tokens.scale
        height: 30 * Tokens.scale
        radius: Tokens.rounding.small
        color: buttonMouse.containsMouse ? Colours.palette.m3surfaceContainerHighest : "transparent"

        MaterialIcon {
            anchors.centerIn: parent
            text: parent.icon
            color: parent.danger ? Colours.palette.m3error : Colours.palette.m3onSurface
        }

        MouseArea {
            id: buttonMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }
}
