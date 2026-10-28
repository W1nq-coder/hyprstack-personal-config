pragma ComponentBehavior: Bound

// Personal overlay (VPN app), design "Tiles": a wide banner with the current
// server and the connect button, then server tiles (flag, ping, address,
// protocol) as in the reference picture.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Hyprstack.Config
import qs.components
import qs.components.controls
import qs.services
import "."

Item {
    id: root

    required property var app
    readonly property var sel: app.selected
    readonly property var info: app.describe(sel?.name ?? "")

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.large

        // ---- Banner ----
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: 150
            radius: Tokens.rounding.extraLarge
            color: Colours.tPalette.m3surfaceContainer
            border.width: 1
            border.color: Qt.alpha(root.app.connected ? Colours.palette.m3primary : Colours.palette.m3outlineVariant, root.app.connected ? 0.8 : 0.5)

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.alpha(Colours.palette.m3primary, root.app.connected ? 0.22 : 0.06) }
                    GradientStop { position: 1; color: "transparent" }
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.large * 1.5
                anchors.rightMargin: Tokens.padding.large
                spacing: Tokens.spacing.large

                VpnFlag {
                    flag: root.info.flag
                    size: 76
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 2
                    StyledText {
                        text: root.app.connected ? root.app.l("PROTECTED", "ЗАЩИЩЕНО") : root.app.l("NOT PROTECTED", "НЕ ЗАЩИЩЕНО")
                        font: Tokens.font.label.builders.medium.weight(Font.Bold).build()
                        color: root.app.connected ? root.app.good : Colours.palette.m3onSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.sel ? root.info.city : "VPN"
                        font: Tokens.font.headline.medium
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.app.working || root.app.failure ? (root.app.failure && !root.app.working ? root.app.failure : root.app.statusText)
                            : root.sel ? [root.info.country, root.app.pingText(root.sel.latency_ms ?? -1), VpnPrefs.showProtocol ? root.app.protocolOf(root.sel) : ""].filter(t => t && t !== "—").join(" · ")
                            : root.app.statusText
                        color: root.app.failure && !root.app.working ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                        elide: Text.ElideRight
                    }
                }

                ColumnLayout {
                    spacing: Tokens.spacing.small
                    VpnToolButtons {
                        Layout.alignment: Qt.AlignRight
                        app: root.app
                    }
                    StyledRect {
                        Layout.alignment: Qt.AlignRight
                        implicitWidth: connectRow.implicitWidth + Tokens.padding.large * 3
                        implicitHeight: 54
                        radius: Tokens.rounding.full
                        color: root.app.connected ? Colours.palette.m3surfaceContainerHighest : Colours.palette.m3primary
                        opacity: root.app.working || (!root.app.connected && !root.sel) ? 0.6 : 1

                        StateLayer {
                            radius: parent.radius
                            color: root.app.connected ? Colours.palette.m3onSurface : Colours.palette.m3onPrimary
                            disabled: root.app.working || (!root.app.connected && !root.sel)
                            onClicked: root.app.toggleConnect()
                        }
                        RowLayout {
                            id: connectRow
                            anchors.centerIn: parent
                            spacing: Tokens.spacing.small
                            BusyIndicator {
                                visible: root.app.working
                                running: visible
                                implicitWidth: 22
                                implicitHeight: 22
                            }
                            MaterialIcon {
                                visible: !root.app.working
                                text: "power_settings_new"
                                color: root.app.connected ? Colours.palette.m3onSurface : Colours.palette.m3onPrimary
                            }
                            StyledText {
                                text: root.app.connected ? root.app.l("Disconnect", "Отключить") : root.app.l("Connect", "Подключить")
                                font: Tokens.font.title.small
                                color: root.app.connected ? Colours.palette.m3onSurface : Colours.palette.m3onPrimary
                            }
                        }
                    }
                }
            }
        }

        // ---- Subscriptions and ping ----
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            VpnGroupChips {
                Layout.fillWidth: true
                app: root.app
            }
            IconTextButton {
                type: TextButton.Tonal
                icon: "network_ping"
                text: root.app.l("Check ping", "Проверить пинг")
                visible: root.app.shown.length > 0
                disabled: root.app.working
                onClicked: root.app.pingAll()
            }
        }
        VpnAddField {
            Layout.fillWidth: true
            app: root.app
        }

        // ---- Tiles ----
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledText {
                anchors.centerIn: parent
                width: parent.width - Tokens.padding.large * 2
                visible: root.app.shown.length === 0
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.app.l("No servers yet. Paste the subscription link above: the same one you added to Happ.",
                    "Серверов пока нет. Вставьте выше ссылку подписки — ту же, что добавляли в Happ.")
                color: Colours.palette.m3onSurfaceVariant
            }

            GridView {
                id: grid

                readonly property int columns: Math.max(1, Math.floor(width / 420))
                // subscription line + address + protocol
                readonly property int lines: 1 + (VpnPrefs.showAddress ? 1 : 0) + (VpnPrefs.showProtocol ? 1 : 0)

                anchors.fill: parent
                clip: true
                cellWidth: Math.floor(width / columns)
                cellHeight: 138 + lines * 34
                model: root.app.shown
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}

                delegate: Item {
                    id: cell

                    required property var modelData
                    readonly property var info: root.app.describe(modelData.name)
                    readonly property bool current: String(modelData.id) === root.app.selectedId
                    readonly property bool live: current && root.app.connected
                    readonly property int ms: modelData.latency_ms ?? -1

                    width: grid.cellWidth
                    height: grid.cellHeight

                    StyledRect {
                        id: card

                        anchors.fill: parent
                        anchors.margins: Tokens.spacing.small
                        radius: Tokens.rounding.large
                        color: Colours.tPalette.m3surfaceContainer
                        border.width: cell.current ? 2 : 1
                        border.color: cell.current ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3outlineVariant, 0.6)

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: card.border.width
                            radius: card.radius - card.border.width
                            opacity: cell.current ? 1 : 0
                            gradient: Gradient {
                                GradientStop { position: 0; color: Qt.alpha(Colours.palette.m3primary, 0.12) }
                                GradientStop { position: 1; color: "transparent" }
                            }
                        }

                        StateLayer {
                            radius: card.radius
                            disabled: root.app.working
                            onClicked: root.app.choose(cell.modelData)
                        }
                        HoverHandler {
                            id: hover
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.large
                            spacing: Tokens.spacing.medium

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.large

                                VpnFlag {
                                    flag: cell.info.flag
                                    size: 56
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    Layout.minimumWidth: 0
                                    spacing: 2
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        spacing: Tokens.spacing.small
                                        StyledText {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 40
                                            Layout.maximumWidth: implicitWidth + 32 // emoji are wider than measured
                                            text: cell.info.city
                                            font: Tokens.font.title.large
                                            elide: Text.ElideRight
                                        }
                                        Badge {
                                            visible: cell.ms > 0 && cell.ms < 120
                                            text: root.app.l("FAST", "БЫСТРЫЙ")
                                            fill: Colours.palette.m3primary
                                            ink: Colours.palette.m3onPrimary
                                        }
                                        Badge {
                                            visible: cell.live
                                            text: root.app.l("ON", "ВКЛ")
                                            fill: root.app.good
                                            ink: "#06281b"
                                        }
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        text: cell.info.country || root.app.groupName(cell.modelData.group)
                                        color: Colours.palette.m3onSurfaceVariant
                                        elide: Text.ElideRight
                                    }
                                }
                                VpnPing {
                                    app: root.app
                                    ms: cell.ms
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 1
                                color: Qt.alpha(Colours.palette.m3outlineVariant, 0.6)
                            }

                            InfoLine {
                                visible: VpnPrefs.showAddress
                                label: root.app.l("IP address:", "IP-адрес:")
                                value: cell.modelData.server ?? ""
                                mono: true
                            }
                            InfoLine {
                                visible: VpnPrefs.showProtocol
                                label: root.app.l("Protocol:", "Протокол:")
                                value: root.app.protocolOf(cell.modelData)
                                accent: true
                            }
                            InfoLine {
                                label: root.app.l("Subscription:", "Подписка:")
                                value: root.app.groupName(cell.modelData.group)
                            }
                            Item {
                                Layout.fillHeight: true
                            }
                        }

                        IconButton {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: Tokens.spacing.small
                            type: IconButton.Text
                            icon: "delete"
                            visible: !cell.live && hover.hovered
                            disabled: root.app.working
                            onClicked: root.app.deleteServer(cell.modelData.id)
                            ToolTip.visible: hovered
                            ToolTip.text: root.app.l("Delete server", "Удалить сервер")
                        }
                    }
                }
            }
        }
    }

    component Badge: StyledRect {
        property alias text: badgeText.text
        property color fill
        property color ink

        implicitWidth: badgeText.implicitWidth + Tokens.padding.medium * 2
        implicitHeight: badgeText.implicitHeight + 6
        radius: Tokens.rounding.small
        color: fill

        StyledText {
            id: badgeText

            anchors.centerIn: parent
            color: parent.ink
            font: Tokens.font.label.builders.small.weight(Font.Bold).build()
        }
    }

    component InfoLine: RowLayout {
        property string label
        property string value
        property bool mono: false
        property bool accent: false

        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        StyledText {
            text: parent.label
            color: Colours.palette.m3onSurfaceVariant
        }
        StyledText {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.minimumWidth: 0
            horizontalAlignment: Text.AlignRight
            text: parent.value
            elide: Text.ElideMiddle
            font: parent.mono ? Tokens.font.mono.medium : Tokens.font.body.medium
            color: parent.accent ? Colours.palette.m3primary : Colours.palette.m3onSurface
        }
    }
}
