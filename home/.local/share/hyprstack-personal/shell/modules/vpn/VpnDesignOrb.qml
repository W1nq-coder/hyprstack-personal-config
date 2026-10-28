pragma ComponentBehavior: Bound

// Personal overlay (VPN app), design "Button": one big round button in the
// middle, the chosen server under it; the server list slides up on demand.

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
    property bool sheetOpen: false

    // ---- Top line ----
    RowLayout {
        id: top

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        MaterialIcon {
            text: "shield_lock"
            color: Colours.palette.m3primary
            fontStyle: Tokens.font.icon.medium
            fill: 1
        }
        StyledText {
            Layout.fillWidth: true
            text: "VPN"
            font: Tokens.font.title.large
        }
        VpnToolButtons {
            app: root.app
        }
    }

    // ---- Middle ----
    ColumnLayout {
        anchors.top: top.bottom
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: Tokens.padding.large
        anchors.bottomMargin: Tokens.padding.large * 2
        width: Math.min(parent.width - Tokens.padding.large * 4, 560)
        spacing: Tokens.spacing.large

        Item {
            Layout.fillHeight: true
        }

        // the big button
        Item {
            id: orb

            readonly property real size: Math.min(240, root.height * 0.32)

            Layout.alignment: Qt.AlignHCenter
            implicitWidth: size + 48
            implicitHeight: size + 48

            // soft halo while connected
            Rectangle {
                anchors.centerIn: parent
                width: orb.size + 48
                height: width
                radius: width / 2
                color: Qt.alpha(Colours.palette.m3primary, root.app.connected ? 0.14 : 0)

                Behavior on color {
                    CAnim {}
                }
            }
            Rectangle {
                anchors.centerIn: parent
                width: orb.size + 22
                height: width
                radius: width / 2
                color: "transparent"
                border.width: 2
                border.color: Qt.alpha(root.app.connected ? Colours.palette.m3primary : Colours.palette.m3outline, root.app.connected ? 0.6 : 0.3)
            }
            // spinner while working
            Rectangle {
                id: spinner

                anchors.centerIn: parent
                width: orb.size + 22
                height: width
                radius: width / 2
                visible: root.app.working
                color: "transparent"
                border.width: 4
                border.color: "transparent"

                Rectangle {
                    x: parent.width / 2 - 7
                    y: -5
                    width: 14
                    height: 14
                    radius: 7
                    color: Colours.palette.m3primary
                }

                RotationAnimation on rotation {
                    running: spinner.visible
                    from: 0
                    to: 360
                    duration: 1400
                    loops: Animation.Infinite
                }
            }
            StyledRect {
                id: button

                anchors.centerIn: parent
                width: orb.size
                height: width
                radius: width / 2
                color: root.app.connected ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHigh

                StateLayer {
                    radius: button.radius
                    color: root.app.connected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                    disabled: root.app.working || (!root.app.connected && !root.sel)
                    onClicked: root.app.toggleConnect()
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "power_settings_new"
                        fontStyle: Tokens.font.icon.builders.large.scale(orb.size / 90).build()
                        color: root.app.connected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.app.connected ? root.app.l("ON", "ВКЛ") : root.app.l("OFF", "ВЫКЛ")
                        font: Tokens.font.title.medium
                        color: root.app.connected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                    }
                }
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.app.statusText
            font: Tokens.font.headline.small
            color: root.app.connected ? Colours.palette.m3primary : Colours.palette.m3onSurface
            elide: Text.ElideRight
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: root.app.mode === "tun" ? root.app.l("All traffic of the computer", "Весь трафик компьютера")
                : root.app.l(`Proxy for apps: 127.0.0.1:${root.app.options.port}`, `Прокси для программ: 127.0.0.1:${root.app.options.port}`)
            color: Colours.palette.m3onSurfaceVariant
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.app.failure.length > 0 && !root.app.working
            horizontalAlignment: Text.AlignHCenter
            text: root.app.failure
            color: Colours.palette.m3error
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }

        Item {
            Layout.preferredHeight: Tokens.spacing.medium
        }

        // the chosen server, opens the list
        StyledRect {
            Layout.fillWidth: true
            visible: root.app.profiles.length > 0
            implicitHeight: 76
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.6)

            StateLayer {
                radius: parent.radius
                onClicked: root.sheetOpen = true
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.medium
                anchors.rightMargin: Tokens.padding.large
                spacing: Tokens.spacing.medium

                VpnFlag {
                    flag: root.info.flag
                    size: 52
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: root.sel ? root.info.city : root.app.l("Choose a server", "Выберите сервер")
                        font: Tokens.font.title.medium
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: !!root.sel
                        text: [root.info.country, VpnPrefs.showProtocol ? root.app.protocolOf(root.sel) : "", VpnPrefs.showAddress ? (root.sel?.server ?? "") : ""].filter(t => t).join(" · ")
                        color: Colours.palette.m3onSurfaceVariant
                        elide: Text.ElideRight
                    }
                }
                VpnPing {
                    visible: !!root.sel
                    app: root.app
                    ms: root.sel?.latency_ms ?? -1
                }
                MaterialIcon {
                    text: "expand_less"
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }

        // first start: paste a subscription right here
        VpnAddField {
            Layout.fillWidth: true
            visible: root.app.profiles.length === 0
            app: root.app
        }

        Item {
            Layout.fillHeight: true
        }
    }

    // ---- Server list sheet ----
    Rectangle {
        anchors.fill: parent
        color: Colours.palette.m3scrim
        opacity: root.sheetOpen ? 0.45 : 0
        visible: opacity > 0

        Behavior on opacity {
            Anim {}
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.sheetOpen = false
        }
    }

    StyledRect {
        id: sheet

        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width, 760)
        height: parent.height * 0.82
        y: root.sheetOpen ? parent.height - height : parent.height + 10
        visible: y < parent.height
        topLeftRadius: Tokens.rounding.extraLarge
        topRightRadius: Tokens.rounding.extraLarge
        color: Colours.palette.m3surfaceContainer

        Behavior on y {
            Anim {
                type: Anim.Emphasized
            }
        }

        // swallow clicks so they do not close the sheet
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.medium

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 40
                implicitHeight: 4
                radius: 2
                color: Colours.palette.m3outline
            }

            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    text: root.app.l("Servers", "Серверы") + " · " + root.app.shown.length
                    font: Tokens.font.title.large
                }
                IconButton {
                    type: IconButton.Text
                    icon: "network_ping"
                    disabled: root.app.working
                    onClicked: root.app.pingAll()
                    ToolTip.visible: hovered
                    ToolTip.text: root.app.l("Check ping", "Проверить пинг")
                }
                IconButton {
                    type: IconButton.Text
                    icon: "close"
                    onClicked: root.sheetOpen = false
                }
            }

            VpnGroupChips {
                Layout.fillWidth: true
                app: root.app
            }

            VpnAddField {
                Layout.fillWidth: true
                app: root.app
                compact: true
            }

            ListView {
                id: list

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: root.app.shown
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}

                delegate: StyledRect {
                    id: row

                    required property var modelData
                    readonly property var info: root.app.describe(modelData.name)
                    readonly property bool current: String(modelData.id) === root.app.selectedId

                    width: list.width
                    implicitHeight: 60
                    radius: Tokens.rounding.medium
                    color: current ? Qt.alpha(Colours.palette.m3primary, 0.14) : "transparent"

                    StateLayer {
                        radius: row.radius
                        disabled: root.app.working
                        onClicked: {
                            root.app.choose(row.modelData);
                            root.sheetOpen = false;
                        }
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
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: row.info.city
                                elide: Text.ElideRight
                                color: row.current ? Colours.palette.m3primary : Colours.palette.m3onSurface
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: [row.info.country, VpnPrefs.showProtocol ? root.app.protocolOf(row.modelData) : ""].filter(t => t).join(" · ")
                                font: Tokens.font.label.medium
                                color: Colours.palette.m3onSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }
                        VpnBars {
                            app: root.app
                            ms: row.modelData.latency_ms ?? -1
                        }
                        MaterialIcon {
                            text: row.current && root.app.connected ? "check_circle" : row.current ? "radio_button_checked" : "radio_button_unchecked"
                            color: row.current ? Colours.palette.m3primary : Colours.palette.m3outline
                            fill: row.current && root.app.connected ? 1 : 0
                        }
                    }
                }
            }
        }
    }
}
