pragma ComponentBehavior: Bound

// Personal overlay (VPN app), design "List": a desktop layout with a side
// panel (connect button, current server, subscriptions) and a compact,
// searchable server list.

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
    property string query: ""
    readonly property var visibleServers: {
        const q = query.trim().toLowerCase();
        if (!q)
            return app.shown;
        return app.shown.filter(p => {
            const i = root.app.describe(p.name);
            return [i.city, i.country, p.server ?? "", root.app.protocolOf(p)].join(" ").toLowerCase().includes(q);
        });
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Side panel ----
        StyledRect {
            Layout.fillHeight: true
            Layout.preferredWidth: Math.min(320, root.width * 0.38)
            color: Colours.tPalette.m3surfaceContainer

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Rectangle {
                        implicitWidth: 10
                        implicitHeight: 10
                        radius: 5
                        color: root.app.connected ? root.app.good : root.app.working ? Colours.palette.m3tertiary : Colours.palette.m3outline
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: "VPN"
                        font: Tokens.font.title.large
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.app.statusText
                    color: root.app.connected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    wrapMode: Text.Wrap
                }

                // connect button across the panel
                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 56
                    radius: Tokens.rounding.large
                    color: root.app.connected ? Colours.palette.m3surfaceContainerHighest : Colours.palette.m3primary
                    opacity: root.app.working || (!root.app.connected && !root.sel) ? 0.6 : 1

                    StateLayer {
                        radius: parent.radius
                        color: root.app.connected ? Colours.palette.m3onSurface : Colours.palette.m3onPrimary
                        disabled: root.app.working || (!root.app.connected && !root.sel)
                        onClicked: root.app.toggleConnect()
                    }
                    RowLayout {
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

                // current server
                RowLayout {
                    Layout.fillWidth: true
                    visible: !!root.sel
                    spacing: Tokens.spacing.medium
                    VpnFlag {
                        flag: root.info.flag
                        size: 44
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: root.info.city
                            font: Tokens.font.title.small
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.app.pingText(root.sel?.latency_ms ?? -1) + (root.info.country ? " · " + root.info.country : "")
                            color: Colours.palette.m3onSurfaceVariant
                            elide: Text.ElideRight
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.app.failure.length > 0 && !root.app.working
                    text: root.app.failure
                    color: Colours.palette.m3error
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Qt.alpha(Colours.palette.m3outlineVariant, 0.6)
                }

                StyledText {
                    text: root.app.l("Subscriptions", "Подписки")
                    font: Tokens.font.label.large
                    color: Colours.palette.m3onSurfaceVariant
                }

                ListView {
                    id: groupList

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: [{id: "", name: root.app.l("All servers", "Все серверы"), count: root.app.profiles.length, subscription: false}].concat(root.app.groups)

                    delegate: StyledRect {
                        id: grow

                        required property var modelData
                        readonly property bool active: root.app.groupFilter === modelData.id

                        width: groupList.width
                        implicitHeight: 44
                        radius: Tokens.rounding.medium
                        color: active ? Qt.alpha(Colours.palette.m3primary, 0.16) : "transparent"

                        StateLayer {
                            radius: grow.radius
                            onClicked: root.app.groupFilter = grow.modelData.id
                        }
                        HoverHandler {
                            id: ghover
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.padding.medium
                            anchors.rightMargin: Tokens.padding.small
                            spacing: Tokens.spacing.small
                            MaterialIcon {
                                text: !grow.modelData.id ? "dns" : grow.modelData.subscription ? "cloud_sync" : "key"
                                color: grow.active ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                            }
                            StyledText {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                text: grow.modelData.name
                                elide: Text.ElideRight
                                color: grow.active ? Colours.palette.m3primary : Colours.palette.m3onSurface
                            }
                            StyledText {
                                visible: !ghover.hovered || !grow.modelData.id
                                text: grow.modelData.count ?? 0
                                color: Colours.palette.m3onSurfaceVariant
                            }
                            IconButton {
                                visible: ghover.hovered && !!grow.modelData.id && grow.modelData.subscription
                                type: IconButton.Text
                                icon: "sync"
                                disabled: root.app.working
                                implicitWidth: 28
                                implicitHeight: 28
                                onClicked: root.app.updateGroup(grow.modelData.id)
                            }
                            IconButton {
                                visible: ghover.hovered && !!grow.modelData.id
                                type: IconButton.Text
                                icon: "delete"
                                disabled: root.app.working
                                implicitWidth: 28
                                implicitHeight: 28
                                onClicked: root.app.removeGroup(grow.modelData.id)
                            }
                        }
                    }
                }

                VpnAddField {
                    Layout.fillWidth: true
                    app: root.app
                    compact: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    IconTextButton {
                        type: TextButton.Text
                        icon: "settings"
                        text: root.app.l("Settings", "Настройки")
                        onClicked: root.app.settingsOpen = true
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                }
            }
        }

        // ---- Server list ----
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: Tokens.padding.large
            spacing: Tokens.spacing.medium

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledTextField {
                    Layout.fillWidth: true
                    placeholderText: root.app.l("Search: city, country, protocol", "Поиск: город, страна, протокол")
                    onTextChanged: root.query = text
                }
                IconButton {
                    type: IconButton.Text
                    icon: "network_ping"
                    disabled: root.app.working || root.app.shown.length === 0
                    onClicked: root.app.pingAll()
                    ToolTip.visible: hovered
                    ToolTip.text: root.app.l("Check ping", "Проверить пинг")
                }
                IconButton {
                    type: IconButton.Text
                    icon: "open_in_full"
                    onClicked: root.app.maximize()
                    ToolTip.visible: hovered
                    ToolTip.text: root.app.l("Maximize", "Развернуть")
                }
                IconButton {
                    type: IconButton.Text
                    icon: "close"
                    onClicked: root.app.close()
                }
            }

            // column titles
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.padding.medium
                Layout.rightMargin: Tokens.padding.medium
                spacing: Tokens.spacing.medium
                visible: root.visibleServers.length > 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.app.l("Server", "Сервер") + " · " + root.visibleServers.length
                    font: Tokens.font.label.medium
                    color: Colours.palette.m3onSurfaceVariant
                }
                StyledText {
                    Layout.preferredWidth: 170
                    visible: VpnPrefs.showProtocol && root.width > 760
                    text: root.app.l("Protocol", "Протокол")
                    font: Tokens.font.label.medium
                    color: Colours.palette.m3onSurfaceVariant
                }
                StyledText {
                    Layout.preferredWidth: 140
                    visible: VpnPrefs.showAddress && root.width > 900
                    text: root.app.l("Address", "Адрес")
                    font: Tokens.font.label.medium
                    color: Colours.palette.m3onSurfaceVariant
                }
                StyledText {
                    Layout.preferredWidth: 110
                    horizontalAlignment: Text.AlignRight
                    text: root.app.l("Ping", "Пинг")
                    font: Tokens.font.label.medium
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                StyledText {
                    anchors.centerIn: parent
                    width: parent.width - Tokens.padding.large * 2
                    visible: root.visibleServers.length === 0
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: root.app.profiles.length ? root.app.l("Nothing found", "Ничего не найдено")
                        : root.app.l("No servers yet. Paste the subscription link on the left: the same one you added to Happ.",
                            "Серверов пока нет. Вставьте слева ссылку подписки — ту же, что добавляли в Happ.")
                    color: Colours.palette.m3onSurfaceVariant
                }

                ListView {
                    id: list

                    anchors.fill: parent
                    clip: true
                    spacing: 2
                    model: root.visibleServers
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}

                    delegate: StyledRect {
                        id: row

                        required property var modelData
                        readonly property var info: root.app.describe(modelData.name)
                        readonly property bool current: String(modelData.id) === root.app.selectedId
                        readonly property bool live: current && root.app.connected

                        width: list.width - 8
                        implicitHeight: 62
                        radius: Tokens.rounding.medium
                        color: current ? Qt.alpha(Colours.palette.m3primary, live ? 0.2 : 0.1) : "transparent"
                        border.width: current ? 1 : 0
                        border.color: Qt.alpha(Colours.palette.m3primary, 0.5)

                        StateLayer {
                            radius: row.radius
                            disabled: root.app.working
                            onClicked: root.app.choose(row.modelData)
                        }
                        HoverHandler {
                            id: rhover
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.padding.medium
                            anchors.rightMargin: Tokens.padding.medium
                            spacing: Tokens.spacing.medium

                            VpnFlag {
                                flag: row.info.flag
                                size: 40
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.minimumWidth: 0
                                clip: true
                                spacing: 0
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: Tokens.spacing.small
                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 30
                                        Layout.maximumWidth: implicitWidth + 32 // emoji are wider than measured
                                        text: row.info.city
                                        font: Tokens.font.title.small
                                        elide: Text.ElideRight
                                        color: row.current ? Colours.palette.m3primary : Colours.palette.m3onSurface
                                    }
                                    MaterialIcon {
                                        Layout.alignment: Qt.AlignVCenter
                                        visible: row.live
                                        text: "check_circle"
                                        fill: 1
                                        color: root.app.good
                                    }
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: row.info.country || root.app.groupName(row.modelData.group)
                                    font: Tokens.font.label.medium
                                    color: Colours.palette.m3onSurfaceVariant
                                    elide: Text.ElideRight
                                }
                            }
                            StyledText {
                                Layout.preferredWidth: 170
                                visible: VpnPrefs.showProtocol && root.width > 760
                                text: root.app.protocolOf(row.modelData)
                                color: Colours.palette.m3primary
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.preferredWidth: 140
                                visible: VpnPrefs.showAddress && root.width > 900
                                text: row.modelData.server ?? ""
                                font: Tokens.font.mono.small
                                color: Colours.palette.m3onSurfaceVariant
                                elide: Text.ElideMiddle
                            }
                            Item {
                                Layout.preferredWidth: 110
                                implicitHeight: bars.implicitHeight
                                VpnBars {
                                    id: bars
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !rhover.hovered || row.live
                                    app: root.app
                                    ms: row.modelData.latency_ms ?? -1
                                }
                                IconButton {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: rhover.hovered && !row.live
                                    type: IconButton.Text
                                    icon: "delete"
                                    disabled: root.app.working
                                    onClicked: root.app.deleteServer(row.modelData.id)
                                    ToolTip.visible: hovered
                                    ToolTip.text: root.app.l("Delete server", "Удалить сервер")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
