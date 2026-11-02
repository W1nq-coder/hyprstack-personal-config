// Personal overlay: Settings → Panels → Taskbar → Customize. The elements of the taskbar in the
// floating layout sit in three zones (left, centre, right); drag an element to another zone or to
// another place in the same zone. Dragged to "Hidden" it disappears from the bar. Changes apply at
// once (services/TaskbarStyle.qml).

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Hyprstack.Components
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property bool ru: String(Tr.language || Qt.locale().name).startsWith("ru")
    function l(en: string, rus: string): string { return root.ru ? rus : en; }

    title: l("Customize taskbar", "Настроить панель задач")
    isSubPage: true

    readonly property var names: ({
            logo: l("Logo", "Логотип"),
            tasks: l("Windows", "Окна"),
            tray: l("Tray", "Трей"),
            clock: l("Clock", "Часы"),
            statusIcons: l("Status icons", "Значки состояния"),
            vpn: "VPN",
            notifications: l("Notifications", "Уведомления"),
            power: l("Power", "Питание")
        })
    readonly property var icons: ({
            logo: "image",
            tasks: "web_asset",
            tray: "widgets",
            clock: "schedule",
            statusIcons: "signal_cellular_alt",
            vpn: "vpn_key",
            notifications: "notifications",
            power: "power_settings_new"
        })
    readonly property var zoneTitles: ({
            left: l("Left", "Слева"),
            center: l("Centre", "По центру"),
            right: l("Right", "Справа"),
            hidden: l("Hidden", "Скрытые")
        })

    function idsOf(zone: string): var {
        return zone === "hidden" ? TaskbarStyle.hidden : TaskbarStyle.zones[zone];
    }

    // ---- drag and drop ----
    property bool dragging: false
    property string dragId: ""
    property point dragPos
    property string hoverZone: ""
    property int hoverIndex: -1
    property real markX
    property real markY
    property real markH
    property var boxes: ({})

    function beginDrag(id: string): void {
        dragId = id;
        dragging = true;
    }

    // Which zone is under the pointer and where in it the element would land.
    function updateDrag(p: point): void {
        dragPos = p;
        hoverZone = "";
        hoverIndex = -1;
        for (const name of ["left", "center", "right", "hidden"]) {
            const box = boxes[name];
            if (!box)
                continue;
            const o = box.mapToItem(dragLayer, 0, 0);
            if (p.x < o.x || p.x > o.x + box.width || p.y < o.y || p.y > o.y + box.height)
                continue;
            hoverZone = name;
            const chips = box.chips();
            if (chips.length === 0) {
                hoverIndex = 0;
                markX = o.x + 14;
                markY = o.y + 40;
                markH = 32;
                break;
            }
            let best = 0, bestDist = Infinity, before = true;
            for (let i = 0; i < chips.length; i++) {
                const c = chips[i].mapToItem(dragLayer, chips[i].width / 2, chips[i].height / 2);
                const d = Math.hypot(p.x - c.x, p.y - c.y);
                if (d < bestDist) {
                    bestDist = d;
                    best = i;
                    before = p.x < c.x;
                }
            }
            hoverIndex = before ? best : best + 1;
            const c = chips[best].mapToItem(dragLayer, 0, 0);
            markX = before ? c.x - 5 : c.x + chips[best].width + 3;
            markY = c.y;
            markH = chips[best].height;
            break;
        }
    }

    function endDrag(): void {
        const id = dragId, zone = hoverZone;
        let index = hoverIndex;
        dragging = false;
        dragId = "";
        hoverZone = "";
        hoverIndex = -1;
        if (!id || !zone)
            return;
        moveTo(id, zone, index);
    }

    // Take the element out of wherever it is and put it into `zone` at `index` ("hidden" just removes it).
    function moveTo(id: string, zone: string, index: int): void {
        const z = {
            left: [...TaskbarStyle.zones.left],
            center: [...TaskbarStyle.zones.center],
            right: [...TaskbarStyle.zones.right]
        };
        if (zone !== "hidden") {
            // the index counts the dragged element itself when it is in the same zone
            const before = z[zone].slice(0, Math.max(0, index)).filter(x => x === id).length;
            index -= before;
        }
        for (const name of ["left", "center", "right"])
            z[name] = z[name].filter(x => x !== id);
        if (zone !== "hidden")
            z[zone].splice(Math.max(0, Math.min(index, z[zone].length)), 0, id);
        TaskbarStyle.setZones(z);
    }

    // A tap on a hidden element brings it back to its usual place.
    function reveal(id: string): void {
        moveTo(id, id === "logo" ? "left" : id === "tasks" ? "center" : "right", id === "logo" ? 0 : 1000);
    }

    // The page has a single content slot: one wrapper holds the layout and the drag layer.
    Item {
        id: wrap

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        height: implicitHeight
        implicitHeight: column.implicitHeight

    ColumnLayout {
        id: column

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Tokens.spacing.small

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Colours.palette.m3onSurfaceVariant
            text: root.l("Drag the elements between the zones or to another place. Drop an element on “Hidden” to remove it from the bar. This is the taskbar of the floating windows mode.",
                "Перетаскивайте элементы между зонами и меняйте их порядок. Бросьте элемент в «Скрытые», чтобы убрать его с панели. Это панель режима «как в Windows».")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            ZoneBox {
                zone: "left"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
            }

            ZoneBox {
                zone: "center"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
            }

            ZoneBox {
                zone: "right"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
            }
        }

        ZoneBox {
            zone: "hidden"
            Layout.fillWidth: true
        }

        ButtonRow {
            Layout.alignment: Qt.AlignLeft
            Layout.topMargin: Tokens.spacing.small

            IconTextButton {
                icon: "restart_alt"
                text: root.l("Reset to default", "Сбросить по умолчанию")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                type: IconTextButton.Tonal
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                onClicked: TaskbarStyle.resetLayout()
            }
        }
    }

    // The element under the pointer while it is dragged, and the place it would land.
    Item {
        id: dragLayer

        anchors.fill: parent
        z: 100

        Rectangle {
            visible: root.dragging && root.hoverZone !== "" && root.hoverZone !== "hidden"
            x: root.markX
            y: root.markY
            width: 3
            height: root.markH
            radius: 2
            color: Colours.palette.m3primary
        }

        StyledRect {
            id: ghost

            visible: root.dragging
            x: root.dragPos.x - width / 2
            y: root.dragPos.y - height / 2
            implicitWidth: ghostRow.implicitWidth + 28
            implicitHeight: 40
            radius: Tokens.rounding.full
            color: Colours.palette.m3primaryContainer
            border.width: 1
            border.color: Colours.palette.m3primary
            opacity: 0.95

            Row {
                id: ghostRow

                anchors.centerIn: parent
                spacing: 8

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.icons[root.dragId] ?? ""
                    color: Colours.palette.m3onPrimaryContainer
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.names[root.dragId] ?? ""
                    color: Colours.palette.m3onPrimaryContainer
                }
            }
        }
    }

    }

    // ------------------------------------------------------------------ a zone
    component ZoneBox: StyledRect {
        id: box

        required property string zone
        readonly property bool target: root.dragging && root.hoverZone === zone
        readonly property var ids: root.idsOf(zone)

        function chips(): var {
            const list = [];
            for (let i = 0; i < repeater.count; i++) {
                const c = repeater.itemAt(i);
                if (c)
                    list.push(c);
            }
            return list;
        }

        Component.onCompleted: root.boxes[zone] = box
        Component.onDestruction: if (root && root.boxes)
            delete root.boxes[zone]

        implicitHeight: 40 + Math.max(flow.implicitHeight, 40) + 30
        radius: Tokens.rounding.large
        color: target ? Qt.alpha(Colours.palette.m3primary, 0.14) : Colours.tPalette.m3surfaceContainer
        border.width: target ? 2 : 1
        border.color: target ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3outline, 0.3)

        StyledText {
            id: header

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 14
            text: root.zoneTitles[box.zone]
            font: Tokens.font.title.small
            color: Colours.palette.m3onSurfaceVariant
        }

        StyledText {
            visible: box.ids.length === 0
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 12
            text: root.l("Drop here", "Бросьте сюда")
            color: Colours.palette.m3outline
        }

        Flow {
            id: flow

            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 14
            anchors.topMargin: 10
            spacing: 8

            Repeater {
                id: repeater

                model: box.ids

                delegate: StyledRect {
                    id: chip

                    required property string modelData

                    implicitWidth: chipRow.implicitWidth + 28
                    implicitHeight: 40
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3surfaceContainerHigh
                    opacity: root.dragging && root.dragId === modelData ? 0.3 : 1

                    Row {
                        id: chipRow

                        anchors.centerIn: parent
                        spacing: 8

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.icons[chip.modelData] ?? ""
                            color: box.zone === "hidden" ? Colours.palette.m3outline : Colours.palette.m3primary
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.names[chip.modelData] ?? chip.modelData
                            color: box.zone === "hidden" ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3onSurface
                        }
                    }

                    MouseArea {
                        property point start
                        property bool moved

                        anchors.fill: parent
                        cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        onPressed: mouse => {
                            moved = false;
                            start = mapToItem(dragLayer, mouse.x, mouse.y);
                        }
                        onPositionChanged: mouse => {
                            if (!pressed)
                                return;
                            const p = mapToItem(dragLayer, mouse.x, mouse.y);
                            if (!moved && Math.abs(p.x - start.x) + Math.abs(p.y - start.y) < 8)
                                return;
                            if (!moved) {
                                moved = true;
                                root.beginDrag(chip.modelData);
                            }
                            root.updateDrag(p);
                        }
                        onReleased: {
                            if (moved)
                                root.endDrag();
                        }
                        onCanceled: {
                            root.dragging = false;
                            root.dragId = "";
                        }
                        onClicked: {
                            if (!moved && box.zone === "hidden")
                                root.reveal(chip.modelData);
                        }
                    }
                }
            }
        }
    }
}
