pragma ComponentBehavior: Bound

// Personal overlay (VPN app): settings behind the gear button. Look and
// behaviour of the window (services/VpnPrefs.qml) and connection settings of
// the backend (mode, routes, DNS, proxy port).

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
    readonly property bool busy: app.working

    RowLayout {
        id: head

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        IconButton {
            type: IconButton.Text
            icon: "arrow_back"
            onClicked: root.app.settingsOpen = false
        }
        StyledText {
            Layout.fillWidth: true
            text: root.app.l("VPN settings", "Настройки VPN")
            font: Tokens.font.headline.small
        }
        BusyIndicator {
            visible: root.busy
            running: visible
            implicitWidth: 26
            implicitHeight: 26
        }
        StyledText {
            visible: root.busy
            text: root.app.stepLabel
            color: Colours.palette.m3onSurfaceVariant
        }
        IconButton {
            type: IconButton.Text
            icon: "close"
            onClicked: root.app.close()
        }
    }

    Flickable {
        anchors.top: head.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Tokens.spacing.medium
        clip: true
        contentHeight: column.implicitHeight + Tokens.padding.large * 2
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        ColumnLayout {
            id: column

            x: (parent.width - width) / 2
            width: Math.min(parent.width - Tokens.padding.large * 2, 760)
            spacing: Tokens.spacing.small

            StyledText {
                Layout.fillWidth: true
                visible: root.app.failure.length > 0 && !root.busy
                text: root.app.failure
                color: Colours.palette.m3error
                wrapMode: Text.Wrap
            }

            // ---- Look ----
            Section { text: root.app.l("Look", "Внешний вид") }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                Choice {
                    selected: VpnPrefs.design === "orb"
                    icon: "power_settings_new"
                    title: root.app.l("Button", "Кнопка")
                    text: root.app.l("One big button, the server list slides up", "Одна большая кнопка, список серверов выезжает снизу")
                    onPicked: VpnPrefs.set("design", "orb")
                }
                Choice {
                    selected: VpnPrefs.design === "list"
                    icon: "view_list"
                    title: root.app.l("List", "Список")
                    text: root.app.l("Side panel with subscriptions and a compact list", "Панель подписок слева и компактный список")
                    onPicked: VpnPrefs.set("design", "list")
                }
                Choice {
                    selected: VpnPrefs.design === "cards"
                    icon: "grid_view"
                    title: root.app.l("Tiles", "Плитки")
                    text: root.app.l("Large server cards with all details", "Крупные карточки серверов со всеми данными")
                    onPicked: VpnPrefs.set("design", "cards")
                }
            }

            Row3 {
                title: root.app.l("Sort servers", "Сортировать серверы")
                options: [["ping", root.app.l("By ping", "По пингу")], ["name", root.app.l("By name", "По названию")], ["source", root.app.l("As in subscription", "Как в подписке")]]
                current: VpnPrefs.sort
                onPicked: key => VpnPrefs.set("sort", key)
            }
            SwitchRow {
                title: root.app.l("Show IP address", "Показывать IP-адрес")
                checked: VpnPrefs.showAddress
                onToggled: on => VpnPrefs.set("showAddress", on)
            }
            SwitchRow {
                title: root.app.l("Show protocol", "Показывать протокол")
                sub: root.app.l("For example VLESS · Reality XTLS", "Например, VLESS · Reality XTLS")
                checked: VpnPrefs.showProtocol
                onToggled: on => VpnPrefs.set("showProtocol", on)
            }

            // ---- Connection ----
            Section { text: root.app.l("Connection", "Подключение") }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                Choice {
                    selected: root.app.mode === "tun"
                    icon: "lan"
                    title: root.app.l("Whole computer", "Весь компьютер")
                    text: root.app.l("All apps go through the VPN (tunnel, like Happ's TUN mode)", "Все программы идут через VPN (туннель, как режим TUN в Happ)")
                    onPicked: if (root.app.mode !== "tun") root.app.setMode("tun")
                }
                Choice {
                    selected: root.app.mode === "proxy"
                    icon: "settings_ethernet"
                    title: root.app.l("Proxy only", "Только прокси")
                    text: root.app.l(`Only apps set to 127.0.0.1:${root.app.options.port} (SOCKS) or :${root.app.options.port + 1} (HTTP)`,
                        `Только программы, где указан 127.0.0.1:${root.app.options.port} (SOCKS) или :${root.app.options.port + 1} (HTTP)`)
                    onPicked: if (root.app.mode !== "proxy") root.app.setMode("proxy")
                }
            }
            SwitchRow {
                title: root.app.l("Connect after login", "Подключаться при входе в систему")
                checked: GlobalConfig.utilities.vpn.enabled
                onToggled: on => GlobalConfig.utilities.vpn.enabled = on
            }
            SwitchRow {
                title: root.app.l("Connect to the fastest server", "Подключаться к самому быстрому серверу")
                sub: root.app.l("The connect button picks the server with the best ping", "Кнопка подключения выбирает сервер с лучшим пингом")
                checked: VpnPrefs.connectFastest
                onToggled: on => VpnPrefs.set("connectFastest", on)
            }

            // ---- Routing ----
            Section { text: root.app.l("Routing", "Маршрутизация") }

            SwitchRow {
                title: root.app.l("Russian sites without VPN", "Российские сайты без VPN")
                sub: root.app.l("Banks, Gosuslugi and other .ru sites open directly", "Банки, Госуслуги и другие российские сайты открываются напрямую")
                checked: root.app.bypassRu
                onToggled: on => root.app.setBypassRu(on)
            }
            Block {
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: root.app.l("My sites without VPN", "Свои сайты без VPN")
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.app.l("Domains separated by commas or spaces, e.g. example.com, mybank.ru; subdomains are included",
                            "Домены через запятую или пробел, например example.com, mybank.ru; поддомены тоже")
                        font: Tokens.font.label.medium
                        color: Colours.palette.m3onSurfaceVariant
                        wrapMode: Text.Wrap
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        StyledTextField {
                            id: directField
                            Layout.fillWidth: true
                            text: (root.app.options.direct ?? []).join(", ")
                            placeholderText: "example.com, mybank.ru"
                            onAccepted: saveDirect.clicked()
                        }
                        IconTextButton {
                            id: saveDirect
                            icon: "save"
                            text: root.app.l("Save", "Сохранить")
                            disabled: root.busy
                            onClicked: root.app.setOptions({direct: directField.text.split(/[\s,;]+/).filter(t => t)})
                        }
                    }
                }
                implicitHeight: 150
            }

            // ---- DNS ----
            Section { text: "DNS" }

            Repeater {
                model: [
                    ["cloudflare", "Cloudflare", "1.1.1.1 · " + root.app.l("fast, by default", "быстрый, по умолчанию")],
                    ["google", "Google", "8.8.8.8"],
                    ["quad9", "Quad9", "9.9.9.9 · " + root.app.l("blocks dangerous sites", "блокирует опасные сайты")],
                    ["adguard", "AdGuard", "94.140.14.14 · " + root.app.l("blocks ads and trackers", "блокирует рекламу и трекеры")]
                ]

                RadioRow {
                    required property var modelData
                    title: modelData[1]
                    sub: modelData[2]
                    checked: (root.app.options.dns ?? "cloudflare") === modelData[0]
                    onPicked: if (!checked) root.app.setOptions({dns: modelData[0]})
                }
            }

            // ---- Proxy port ----
            Section { text: root.app.l("Proxy port", "Порт прокси") }

            Block {
                implicitHeight: 74
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.medium
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            text: root.app.l("Local SOCKS port", "Локальный порт SOCKS")
                        }
                        StyledText {
                            text: root.app.l("HTTP uses the next one", "HTTP — на следующем")
                            font: Tokens.font.label.medium
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                    StyledTextField {
                        id: portField
                        Layout.preferredWidth: 110
                        text: String(root.app.options.port ?? 2080)
                        validator: IntValidator { bottom: 1024; top: 65534 }
                        onAccepted: savePort.clicked()
                    }
                    IconTextButton {
                        id: savePort
                        icon: "save"
                        text: root.app.l("Save", "Сохранить")
                        disabled: root.busy || !portField.acceptableInput
                        onClicked: root.app.setOptions({port: parseInt(portField.text)})
                    }
                }
            }

            // ---- Subscriptions ----
            Section { text: root.app.l("Subscriptions", "Подписки") }

            SwitchRow {
                title: root.app.l("Update subscriptions when the window opens", "Обновлять подписки при открытии окна")
                checked: VpnPrefs.updateOnOpen
                onToggled: on => VpnPrefs.set("updateOnOpen", on)
            }
            SwitchRow {
                title: root.app.l("Check ping when the window opens", "Проверять пинг при открытии окна")
                checked: VpnPrefs.pingOnOpen
                onToggled: on => VpnPrefs.set("pingOnOpen", on)
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.small
                IconTextButton {
                    type: TextButton.Tonal
                    icon: "sync"
                    text: root.app.l("Update all subscriptions now", "Обновить все подписки сейчас")
                    disabled: root.busy || !root.app.groups.some(g => g.subscription)
                    onClicked: root.app.updateGroup("")
                }
                Item {
                    Layout.fillWidth: true
                }
            }
        }
    }

    component Section: StyledText {
        Layout.topMargin: Tokens.spacing.large
        Layout.bottomMargin: Tokens.spacing.extraSmall
        font: Tokens.font.title.small
        color: Colours.palette.m3primary
    }

    component Block: StyledRect {
        Layout.fillWidth: true
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainer
    }

    component SwitchRow: StyledRect {
        id: sw

        property string title
        property string sub
        property bool checked
        signal toggled(on: bool)

        Layout.fillWidth: true
        implicitHeight: swRow.implicitHeight + Tokens.padding.medium * 2
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainer

        RowLayout {
            id: swRow
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.large
            anchors.rightMargin: Tokens.padding.large
            spacing: Tokens.spacing.medium
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: sw.title
                    wrapMode: Text.Wrap
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: sw.sub.length > 0
                    text: sw.sub
                    font: Tokens.font.label.medium
                    color: Colours.palette.m3onSurfaceVariant
                    wrapMode: Text.Wrap
                }
            }
            StyledSwitch {
                checked: sw.checked
                enabled: !root.busy
                onToggled: sw.toggled(checked)
            }
        }
    }

    component RadioRow: StyledRect {
        id: rr

        property string title
        property string sub
        property bool checked
        signal picked

        Layout.fillWidth: true
        implicitHeight: 58
        radius: Tokens.rounding.large
        color: checked ? Qt.alpha(Colours.palette.m3primary, 0.12) : Colours.tPalette.m3surfaceContainer

        StateLayer {
            radius: rr.radius
            disabled: root.busy
            onClicked: rr.picked()
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.large
            anchors.rightMargin: Tokens.padding.large
            spacing: Tokens.spacing.medium
            MaterialIcon {
                text: rr.checked ? "radio_button_checked" : "radio_button_unchecked"
                color: rr.checked ? Colours.palette.m3primary : Colours.palette.m3outline
            }
            StyledText {
                text: rr.title
            }
            StyledText {
                Layout.fillWidth: true
                text: rr.sub
                color: Colours.palette.m3onSurfaceVariant
                elide: Text.ElideRight
            }
        }
    }

    // A big choice tile (design, connection mode)
    component Choice: StyledRect {
        id: ch

        property bool selected
        property string icon
        property string title
        property string text
        signal picked

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        implicitHeight: chCol.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.large
        color: selected ? Qt.alpha(Colours.palette.m3primary, 0.14) : Colours.tPalette.m3surfaceContainer
        border.width: selected ? 2 : 1
        border.color: selected ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3outlineVariant, 0.5)

        StateLayer {
            radius: ch.radius
            disabled: root.busy
            onClicked: ch.picked()
        }
        ColumnLayout {
            id: chCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.small
            MaterialIcon {
                text: ch.icon
                fontStyle: Tokens.font.icon.large
                color: ch.selected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            }
            StyledText {
                text: ch.title
                font: Tokens.font.title.small
            }
            StyledText {
                Layout.fillWidth: true
                text: ch.text
                font: Tokens.font.label.medium
                color: Colours.palette.m3onSurfaceVariant
                wrapMode: Text.Wrap
            }
        }
    }

    // Three-way choice in one row (sorting)
    component Row3: StyledRect {
        id: r3

        property string title
        property var options: []
        property string current
        signal picked(key: string)

        Layout.fillWidth: true
        implicitHeight: 64
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainer

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.large
            anchors.rightMargin: Tokens.padding.medium
            spacing: Tokens.spacing.small
            StyledText {
                Layout.fillWidth: true
                text: r3.title
            }
            Repeater {
                model: r3.options
                IconTextButton {
                    required property var modelData
                    type: r3.current === modelData[0] ? TextButton.Filled : TextButton.Tonal
                    icon: r3.current === modelData[0] ? "check" : ""
                    text: modelData[1]
                    onClicked: r3.picked(modelData[0])
                }
            }
        }
    }
}
