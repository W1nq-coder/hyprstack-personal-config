pragma ComponentBehavior: Bound

// Personal overlay: the VPN app. Opens from the VPN button (dashboard, taskbar)
// and from the app menu (Super → "VPN"). Paste subscription links (https://…,
// happ://add/…) or keys (vless://…); several subscriptions can be kept. Servers
// are cards with flag, ping, address and protocol; a click connects.
// Backend: services/ManagedVPN.qml → assets/vpn.py.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.controls
import qs.services

FloatingWindow {
    id: root

    readonly property bool ru: String(Tr.language || Qt.locale().name).startsWith("ru")
    function l(en: string, rus: string): string { return root.ru ? rus : en; }

    title: "VPN"
    color: Colours.palette.m3surface
    implicitWidth: 1000
    implicitHeight: 760
    minimumSize.width: 560
    minimumSize.height: 520

    readonly property var profiles: ManagedVPN.profiles
    readonly property var groups: ManagedVPN.data.groups ?? []
    readonly property string selectedId: String(ManagedVPN.data.selectedProfile ?? "")
    readonly property var selected: profiles.find(p => String(p.id) === selectedId) ?? null
    readonly property bool working: ManagedVPN.busy || VPN.connecting || VPN.disconnecting || steps.length > 0
    readonly property bool bypassRu: (ManagedVPN.routes.find(r => r.active)?.id ?? "all") === "bypass-ru"
    // "" = servers of all subscriptions
    property string groupFilter: ""
    readonly property var shown: groupFilter ? profiles.filter(p => p.group === groupFilter) : profiles

    // Pending actions run one after another: [{command, payload, label}].
    property var steps: []
    property string stepLabel: ""
    // Only errors of actions started in this window are shown.
    property string failure: ""

    function runSteps(list: var): void {
        root.failure = "";
        root.steps = list;
        root.next();
    }
    function next(): void {
        if (!root.steps.length) {
            root.stepLabel = "";
            return;
        }
        const step = root.steps[0];
        root.stepLabel = step.label ?? "";
        ManagedVPN.run(step.command, step.payload ?? {});
    }
    // Make sure the engine is there and the tunnel is allowed, then connect.
    function connectSteps(): var {
        return [
            {command: "install", label: root.l("Downloading the VPN engine…", "Скачиваю движок VPN…")},
            {command: "authorize", label: root.l("Allow the VPN tunnel: enter your password", "Разрешите VPN-туннель: введите пароль")},
            {command: "connect", label: root.l("Connecting…", "Подключаюсь…")}
        ];
    }
    function pingStep(group: string): var {
        return {command: "test-all", payload: group ? {group} : {}, label: root.l("Checking ping…", "Проверяю пинг…")};
    }
    function choose(profile: var): void {
        if (root.working)
            return;
        if (String(profile.id) === root.selectedId && VPN.connected)
            return;
        // Selecting while connected reconnects on its own.
        const pick = {command: "select", payload: {id: profile.id}, label: root.l("Switching server…", "Переключаю сервер…")};
        root.runSteps(VPN.connected ? [pick] : [pick, ...root.connectSteps()]);
    }
    function addLink(): void {
        const text = linkInput.text.trim();
        if (!text || root.working)
            return;
        const subscription = /^(https?:\/\/|happ:\/\/add\/)\S+$/i.test(text);
        root.runSteps([
            {command: "import", payload: {text}, label: subscription ? root.l("Loading the subscription…", "Загружаю подписку…") : root.l("Adding the key…", "Добавляю ключ…")},
            {command: "install", label: root.l("Downloading the VPN engine…", "Скачиваю движок VPN…")},
            root.pingStep(""),
            ...(VPN.connected ? [] : root.connectSteps().slice(1))
        ]);
    }

    // ---- Server names: "🇩🇪 Франкфурт" → flag, city and country ----
    readonly property var countries: ({
        AE: ["UAE", "ОАЭ"], AM: ["Armenia", "Армения"], AT: ["Austria", "Австрия"], AU: ["Australia", "Австралия"],
        AZ: ["Azerbaijan", "Азербайджан"], BE: ["Belgium", "Бельгия"], BG: ["Bulgaria", "Болгария"], BR: ["Brazil", "Бразилия"],
        BY: ["Belarus", "Беларусь"], CA: ["Canada", "Канада"], CH: ["Switzerland", "Швейцария"], CN: ["China", "Китай"],
        CY: ["Cyprus", "Кипр"], CZ: ["Czechia", "Чехия"], DE: ["Germany", "Германия"], DK: ["Denmark", "Дания"],
        EE: ["Estonia", "Эстония"], ES: ["Spain", "Испания"], FI: ["Finland", "Финляндия"], FR: ["France", "Франция"],
        GB: ["United Kingdom", "Великобритания"], GE: ["Georgia", "Грузия"], GR: ["Greece", "Греция"], HK: ["Hong Kong", "Гонконг"],
        HU: ["Hungary", "Венгрия"], IE: ["Ireland", "Ирландия"], IL: ["Israel", "Израиль"], IN: ["India", "Индия"],
        IS: ["Iceland", "Исландия"], IT: ["Italy", "Италия"], JP: ["Japan", "Япония"], KG: ["Kyrgyzstan", "Киргизия"],
        KR: ["South Korea", "Южная Корея"], KZ: ["Kazakhstan", "Казахстан"], LT: ["Lithuania", "Литва"], LU: ["Luxembourg", "Люксембург"],
        LV: ["Latvia", "Латвия"], MD: ["Moldova", "Молдова"], MX: ["Mexico", "Мексика"], NL: ["Netherlands", "Нидерланды"],
        NO: ["Norway", "Норвегия"], PL: ["Poland", "Польша"], PT: ["Portugal", "Португалия"], RO: ["Romania", "Румыния"],
        RS: ["Serbia", "Сербия"], RU: ["Russia", "Россия"], SE: ["Sweden", "Швеция"], SG: ["Singapore", "Сингапур"],
        SK: ["Slovakia", "Словакия"], TR: ["Türkiye", "Турция"], TW: ["Taiwan", "Тайвань"], UA: ["Ukraine", "Украина"],
        US: ["USA", "США"], UZ: ["Uzbekistan", "Узбекистан"], VN: ["Vietnam", "Вьетнам"], ZA: ["South Africa", "ЮАР"]
    })
    function describe(name: string): var {
        // walk code points by hand: flags are two "regional indicator" letters
        const text = String(name ?? "");
        const chars = [];
        for (let i = 0; i < text.length;) {
            const cp = text.codePointAt(i);
            const size = cp > 0xFFFF ? 2 : 1;
            chars.push({cp, s: text.substr(i, size)});
            i += size;
        }
        let flag = "", code = "";
        const rest = [];
        for (let i = 0; i < chars.length; i++) {
            const cp = chars[i].cp;
            const next = i + 1 < chars.length ? chars[i + 1].cp : 0;
            if (!flag && cp >= 0x1F1E6 && cp <= 0x1F1FF && next >= 0x1F1E6 && next <= 0x1F1FF) {
                flag = chars[i].s + chars[i + 1].s;
                code = String.fromCharCode(65 + cp - 0x1F1E6, 65 + next - 0x1F1E6);
                i++;
            } else {
                rest.push(chars[i].s);
            }
        }
        const country = root.countries[code];
        let city = rest.join("").replace(/^[\s|,·\-–—:]+|[\s|,·\-–—:]+$/g, "");
        if (!city)
            city = country ? country[root.ru ? 1 : 0] : String(name ?? "");
        return {flag, city, country: country ? country[root.ru ? 1 : 0] : code};
    }
    function groupName(id: string): string {
        return root.groups.find(g => g.id === id)?.name ?? "";
    }
    function serversWord(n: int): string {
        if (!root.ru)
            return n === 1 ? "1 server" : `${n} servers`;
        const d = n % 10, h = n % 100;
        const word = d === 1 && h !== 11 ? "сервер" : d >= 2 && d <= 4 && (h < 12 || h > 14) ? "сервера" : "серверов";
        return `${n} ${word}`;
    }

    // ping colours: green fast, amber medium, red slow or no answer
    readonly property color good: "#34d399"
    function pingColour(ms: int): color {
        if (ms < 0)
            return Colours.palette.m3outline;
        if (ms === 0)
            return Colours.palette.m3error;
        return ms < 150 ? root.good : ms < 400 ? Colours.palette.m3tertiary : Colours.palette.m3error;
    }
    function pingText(ms: int): string {
        if (ms < 0)
            return "—";
        if (ms === 0)
            return root.l("no answer", "нет ответа");
        return ms + root.l(" ms", " мс");
    }

    onVisibleChanged: {
        if (!visible) {
            ManagedVPN.window = null;
            destroy();
        }
    }

    Connections {
        target: ManagedVPN
        function onOperationFinished(command: string, success: bool): void {
            if (!root.steps.length || root.steps[0].command !== command)
                return;
            if (command === "import" && success)
                linkInput.text = "";
            // A failed ping does not stop the chain; any other failure does.
            if (!success && command !== "test-all") {
                root.failure = ManagedVPN.error || root.l("The action did not complete", "Не получилось выполнить действие");
                root.steps = [];
                root.stepLabel = "";
                return;
            }
            root.steps = root.steps.slice(1);
            Qt.callLater(root.next);
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large * 1.5
        spacing: Tokens.spacing.large

        // ---- Status and the main button ----
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.large

            StyledRect {
                implicitWidth: 56
                implicitHeight: 56
                radius: Tokens.rounding.large
                color: VPN.connected ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHigh

                MaterialIcon {
                    anchors.centerIn: parent
                    text: VPN.connected ? "shield_lock" : "shield"
                    fill: VPN.connected ? 1 : 0
                    fontStyle: Tokens.font.icon.large
                    color: VPN.connected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    text: "VPN"
                    font: Tokens.font.headline.small
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.stepLabel || (root.working ? root.l("Working…", "Подождите…")
                        : VPN.connected ? root.l("Connected", "Подключено") + (root.selected ? " · " + root.describe(root.selected.name).city : "")
                        : root.profiles.length ? root.l("Disconnected", "Отключено") : root.l("Add a subscription to start", "Добавьте подписку, чтобы начать"))
                    color: VPN.connected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    elide: Text.ElideRight
                }
            }

            BusyIndicator {
                visible: root.working
                running: visible
                implicitWidth: 32
                implicitHeight: 32
            }

            IconTextButton {
                objectName: "vpnConnectButton"
                icon: VPN.connected ? "power_settings_new" : "bolt"
                text: VPN.connected ? root.l("Disconnect", "Отключить") : root.l("Connect", "Подключить")
                disabled: root.working || (!VPN.connected && !root.selected)
                onClicked: VPN.connected ? VPN.disconnect() : root.runSteps(root.connectSteps())
            }

            IconButton {
                type: IconButton.Text
                icon: "close"
                onClicked: root.visible = false
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.failure.length > 0 && !root.working
            text: root.failure
            color: Colours.palette.m3error
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }

        // ---- Subscriptions ----
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: subsColumn.implicitHeight + Tokens.padding.large * 2
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer

            ColumnLayout {
                id: subsColumn

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                StyledText {
                    text: root.l("Subscriptions", "Подписки")
                    font: Tokens.font.title.small
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small
                    visible: root.groups.length > 0

                    Chip {
                        groupId: ""
                        label: root.l("All servers", "Все серверы")
                        count: root.profiles.length
                    }

                    Repeater {
                        model: root.groups

                        Chip {
                            required property var modelData
                            groupId: modelData.id
                            label: modelData.name
                            count: modelData.count ?? 0
                            subscription: modelData.subscription
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledTextField {
                        id: linkInput
                        objectName: "vpnImportInput"
                        Layout.fillWidth: true
                        enabled: !root.working
                        placeholderText: root.l("Paste a subscription link (https://…) or a key (vless://…), like in Happ",
                            "Вставьте ссылку подписки (https://…) или ключ (vless://…), как в Happ")
                        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                        onAccepted: root.addLink()
                    }
                    IconTextButton {
                        objectName: "vpnImportButton"
                        icon: "add_link"
                        text: root.l("Add", "Добавить")
                        disabled: root.working || linkInput.text.trim().length === 0
                        onClicked: root.addLink()
                    }
                }
            }
        }

        // ---- Servers ----
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledText {
                Layout.fillWidth: true
                text: root.l("Servers", "Серверы") + (root.shown.length ? " · " + root.shown.length : "")
                font: Tokens.font.title.medium
            }
            IconTextButton {
                type: TextButton.Tonal
                icon: "network_ping"
                text: root.l("Check ping", "Проверить пинг")
                visible: root.shown.length > 0
                disabled: root.working
                onClicked: root.runSteps([{command: "install", label: root.l("Downloading the VPN engine…", "Скачиваю движок VPN…")}, root.pingStep(root.groupFilter)])
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledText {
                anchors.centerIn: parent
                width: parent.width - Tokens.padding.large * 2
                visible: root.shown.length === 0
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.l("No servers yet. Paste the subscription link from your VPN provider above: the same one you added to Happ.",
                    "Серверов пока нет. Вставьте выше ссылку подписки от вашего VPN — ту же, что добавляли в Happ.")
                color: Colours.palette.m3onSurfaceVariant
            }

            GridView {
                id: grid

                readonly property int columns: Math.max(1, Math.floor(width / 440))

                anchors.fill: parent
                clip: true
                cellWidth: Math.floor(width / columns)
                cellHeight: 214
                model: root.shown
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}

                delegate: Item {
                    id: cell

                    required property var modelData
                    readonly property var info: root.describe(modelData.name)
                    readonly property bool current: String(modelData.id) === root.selectedId
                    readonly property bool live: current && VPN.connected
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

                        // warm glow on the selected server, as in the design
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: card.border.width
                            radius: card.radius - card.border.width
                            opacity: cell.current ? 1 : 0
                            gradient: Gradient {
                                GradientStop { position: 0; color: Qt.alpha(Colours.palette.m3primary, 0.12) }
                                GradientStop { position: 1; color: "transparent" }
                            }

                            Behavior on opacity {
                                Anim {}
                            }
                        }

                        StateLayer {
                            radius: card.radius
                            disabled: root.working
                            onClicked: root.choose(cell.modelData)
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.large * 1.2
                            spacing: Tokens.spacing.medium

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.large

                                StyledRect {
                                    implicitWidth: 60
                                    implicitHeight: 60
                                    radius: Tokens.rounding.medium
                                    color: Colours.palette.m3surfaceContainerHigh
                                    border.width: 1
                                    border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.5)

                                    Text {
                                        anchors.centerIn: parent
                                        visible: cell.info.flag.length > 0
                                        text: cell.info.flag
                                        font.family: "Noto Color Emoji"
                                        font.pixelSize: 32
                                    }
                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        visible: cell.info.flag.length === 0
                                        text: "public"
                                        fontStyle: Tokens.font.icon.large
                                        color: Colours.palette.m3onSurfaceVariant
                                    }
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
                                            Layout.maximumWidth: implicitWidth
                                            text: cell.info.city
                                            font: Tokens.font.title.large
                                            elide: Text.ElideRight
                                        }
                                        Badge {
                                            visible: cell.ms > 0 && cell.ms < 120
                                            text: root.l("FAST", "БЫСТРЫЙ")
                                            fill: Colours.palette.m3primary
                                            ink: Colours.palette.m3onPrimary
                                        }
                                        Badge {
                                            visible: cell.live
                                            text: root.l("ON", "ВКЛ")
                                            fill: root.good
                                            ink: "#06281b"
                                        }
                                        Item {
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 0
                                        }
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        text: cell.info.country || root.groupName(cell.modelData.group)
                                        color: Colours.palette.m3onSurfaceVariant
                                        elide: Text.ElideRight
                                    }
                                }

                                // ping pill
                                StyledRect {
                                    implicitWidth: pingRow.implicitWidth + Tokens.padding.large * 2
                                    implicitHeight: 36
                                    radius: Tokens.rounding.full
                                    color: Qt.alpha(root.pingColour(cell.ms), 0.12)
                                    border.width: 1
                                    border.color: Qt.alpha(root.pingColour(cell.ms), 0.35)

                                    RowLayout {
                                        id: pingRow

                                        anchors.centerIn: parent
                                        spacing: Tokens.spacing.small

                                        Rectangle {
                                            implicitWidth: 8
                                            implicitHeight: 8
                                            radius: 4
                                            color: root.pingColour(cell.ms)
                                        }
                                        StyledText {
                                            text: root.pingText(cell.ms)
                                            font: Tokens.font.mono.medium
                                            color: root.pingColour(cell.ms)
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 1
                                color: Qt.alpha(Colours.palette.m3outlineVariant, 0.6)
                            }

                            InfoLine {
                                label: root.l("IP address:", "IP-адрес:")
                                value: cell.modelData.server ?? ""
                                mono: true
                            }
                            InfoLine {
                                label: root.l("Protocol:", "Протокол:")
                                value: cell.modelData.protocol ?? String(cell.modelData.type ?? "").toUpperCase()
                                accent: true
                            }
                            InfoLine {
                                visible: root.groups.length > 1 && !root.groupFilter
                                label: root.l("Subscription:", "Подписка:")
                                value: root.groupName(cell.modelData.group)
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
                            visible: !cell.live && hoverWatch.hovered
                            disabled: root.working
                            onClicked: root.runSteps([{command: "delete", payload: {id: cell.modelData.id}, label: root.l("Deleting…", "Удаляю…")}])
                            ToolTip.visible: hovered
                            ToolTip.text: root.l("Delete server", "Удалить сервер")
                        }

                        HoverHandler {
                            id: hoverWatch
                        }
                    }
                }
            }
        }

        // ---- Options ----
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.large

            StyledText {
                text: root.l("Russian sites without VPN", "Российские сайты без VPN")
            }
            StyledSwitch {
                checked: root.bypassRu
                enabled: !root.working
                onToggled: root.runSteps([{command: "route", payload: {id: checked ? "bypass-ru" : "all"}, label: root.l("Applying…", "Применяю…")}])
            }
            Item {
                Layout.fillWidth: true
            }
            StyledText {
                text: root.l("Connect after login", "Подключаться при входе")
            }
            StyledSwitch {
                checked: GlobalConfig.utilities.vpn.enabled
                enabled: !root.working
                onToggled: GlobalConfig.utilities.vpn.enabled = checked
            }
        }
    }

    // A subscription: click shows only its servers; refresh and remove buttons.
    component Chip: StyledRect {
        id: chip

        required property string groupId
        required property string label
        required property int count
        property bool subscription: false
        readonly property bool active: root.groupFilter === groupId

        implicitWidth: chipRow.implicitWidth + Tokens.padding.large * 2
        implicitHeight: 40
        radius: Tokens.rounding.full
        color: active ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHigh

        StateLayer {
            radius: chip.radius
            color: chip.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
            onClicked: root.groupFilter = chip.groupId
        }

        RowLayout {
            id: chipRow

            anchors.centerIn: parent
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: chip.groupId ? (chip.subscription ? "cloud_sync" : "key") : "dns"
                color: chip.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
            }
            StyledText {
                text: chip.label
                color: chip.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
            }
            StyledText {
                text: root.serversWord(chip.count)
                font: Tokens.font.label.medium
                color: chip.active ? Qt.alpha(Colours.palette.m3onPrimary, 0.75) : Colours.palette.m3onSurfaceVariant
            }
            IconButton {
                visible: chip.groupId.length > 0 && chip.subscription
                type: IconButton.Text
                icon: "sync"
                disabled: root.working
                implicitWidth: 28
                implicitHeight: 28
                onClicked: root.runSteps([{command: "update", payload: {id: chip.groupId}, label: root.l("Updating the subscription…", "Обновляю подписку…")}, root.pingStep(chip.groupId)])
                ToolTip.visible: hovered
                ToolTip.text: root.l("Update", "Обновить")
            }
            IconButton {
                visible: chip.groupId.length > 0
                type: IconButton.Text
                icon: "close"
                disabled: root.working
                implicitWidth: 28
                implicitHeight: 28
                onClicked: {
                    if (root.groupFilter === chip.groupId)
                        root.groupFilter = "";
                    root.runSteps([{command: "remove-group", payload: {id: chip.groupId}, label: root.l("Removing…", "Удаляю…")}]);
                }
                ToolTip.visible: hovered
                ToolTip.text: root.l("Remove subscription", "Удалить подписку")
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
