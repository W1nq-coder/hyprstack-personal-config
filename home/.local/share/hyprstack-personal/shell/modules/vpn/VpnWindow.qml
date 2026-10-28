pragma ComponentBehavior: Bound

// Personal overlay: the VPN app. Opens from the VPN button (dashboard) and from
// the app menu (Super → "VPN"). This file holds the logic; the look is one of
// three designs (VpnDesignOrb/List/Cards.qml), picked with the gear button
// (VpnSettingsPage.qml, services/VpnPrefs.qml).
// Backend: services/ManagedVPN.qml → assets/vpn.py.
//
// The window is hidden, not destroyed, when closed: destroying a window while
// its frame is being drawn could crash the shell in the graphics driver.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.controls
import qs.services
import "."

FloatingWindow {
    id: root

    readonly property bool ru: String(Tr.language || Qt.locale().name).startsWith("ru")
    function l(en: string, rus: string): string { return root.ru ? rus : en; }

    title: "VPN"
    color: Colours.palette.m3surface
    implicitWidth: 1040
    implicitHeight: 760
    minimumSize.width: 480
    minimumSize.height: 560

    // ---- State ----
    readonly property var profiles: ManagedVPN.profiles
    readonly property var groups: ManagedVPN.data.groups ?? []
    readonly property var options: ManagedVPN.data.options ?? ({dns: "cloudflare", port: 2080, direct: []})
    readonly property string selectedId: String(ManagedVPN.data.selectedProfile ?? "")
    readonly property var selected: profiles.find(p => String(p.id) === selectedId) ?? null
    readonly property bool connected: VPN.connected
    readonly property bool working: ManagedVPN.busy || VPN.connecting || VPN.disconnecting || steps.length > 0
    readonly property bool bypassRu: (ManagedVPN.routes.find(r => r.active)?.id ?? "all") === "bypass-ru"
    readonly property string mode: ManagedVPN.data.mode ?? "tun"
    // tunnels of other VPN apps (Happ…) that fight with this one
    readonly property var otherTunnels: ManagedVPN.data.otherTunnels ?? []
    // "" = servers of all subscriptions
    property string groupFilter: ""
    property bool settingsOpen: false
    readonly property var shown: {
        const list = (groupFilter ? profiles.filter(p => p.group === groupFilter) : profiles).slice();
        if (VpnPrefs.sort === "name")
            list.sort((a, b) => root.describe(a.name).city.localeCompare(root.describe(b.name).city));
        else if (VpnPrefs.sort === "ping")
            list.sort((a, b) => root.pingRank(a.latency_ms) - root.pingRank(b.latency_ms));
        return list;
    }
    readonly property var fastest: profiles.filter(p => p.latency_ms > 0).sort((a, b) => a.latency_ms - b.latency_ms)[0] ?? null
    readonly property string statusText: stepLabel || (working ? l("Working…", "Подождите…")
        : connected ? l("Connected", "Подключено") + (selected ? " · " + describe(selected.name).city : "")
        : profiles.length ? l("Disconnected", "Отключено") : l("Add a subscription to start", "Добавьте подписку, чтобы начать"))

    signal linkAdded

    // ---- Actions run one after another: [{command, payload, label}] ----
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
    function installStep(): var {
        return {command: "install", label: l("Downloading the VPN engine…", "Скачиваю движок VPN…")};
    }
    // The tunnel needs a one-time permission; proxy mode does not.
    function connectSteps(): var {
        const list = [root.installStep()];
        if (root.mode === "tun")
            list.push({command: "authorize", label: l("Allow the VPN tunnel: enter your password", "Разрешите VPN-туннель: введите пароль")});
        list.push({command: "connect", label: l("Connecting…", "Подключаюсь…")});
        return list;
    }
    function pingStep(group: string): var {
        return {command: "test-all", payload: group ? {group} : {}, label: l("Checking ping…", "Проверяю пинг…")};
    }
    function choose(profile: var): void {
        if (root.working || !profile)
            return;
        if (String(profile.id) === root.selectedId && root.connected)
            return;
        // Selecting while connected reconnects on its own.
        const pick = {command: "select", payload: {id: profile.id}, label: l("Switching server…", "Переключаю сервер…")};
        root.runSteps(root.connected ? [pick] : [pick, ...root.connectSteps()]);
    }
    function toggleConnect(): void {
        if (root.working)
            return;
        if (root.connected) {
            VPN.disconnect();
            return;
        }
        if (VpnPrefs.connectFastest && root.fastest && String(root.fastest.id) !== root.selectedId)
            root.choose(root.fastest);
        else if (root.selected)
            root.runSteps(root.connectSteps());
    }
    function addLink(text: string): void {
        text = String(text ?? "").trim();
        if (!text || root.working)
            return;
        const subscription = /^(https?:\/\/|happ:\/\/add\/)\S+$/i.test(text);
        root.runSteps([
            {command: "import", payload: {text}, label: subscription ? l("Loading the subscription…", "Загружаю подписку…") : l("Adding the key…", "Добавляю ключ…")},
            root.installStep(),
            root.pingStep(""),
            ...(root.connected ? [] : root.connectSteps().slice(1))
        ]);
    }
    function pingAll(): void {
        root.runSteps([root.installStep(), root.pingStep(root.groupFilter)]);
    }
    function updateGroup(id: string): void {
        root.runSteps([{command: "update", payload: id ? {id} : {}, label: l("Updating the subscription…", "Обновляю подписку…")}, root.pingStep(id)]);
    }
    function removeGroup(id: string): void {
        if (root.groupFilter === id)
            root.groupFilter = "";
        root.runSteps([{command: "remove-group", payload: {id}, label: l("Removing…", "Удаляю…")}]);
    }
    function deleteServer(id: string): void {
        root.runSteps([{command: "delete", payload: {id}, label: l("Deleting…", "Удаляю…")}]);
    }
    function setMode(value: string): void {
        root.runSteps([{command: "mode", payload: {mode: value}, label: l("Applying…", "Применяю…")}]);
    }
    function setBypassRu(on: bool): void {
        root.runSteps([{command: "route", payload: {id: on ? "bypass-ru" : "all"}, label: l("Applying…", "Применяю…")}]);
    }
    function setOptions(change: var): void {
        root.runSteps([{command: "options", payload: change, label: l("Applying…", "Применяю…")}]);
    }
    function maximize(): void {
        Hypr.dispatch(Hypr.usingLua ? 'hl.dsp.window.fullscreen({ mode = "maximized" })' : "fullscreen 1");
    }
    function close(): void {
        root.visible = false;
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
        const countryName = country ? country[root.ru ? 1 : 0] : code;
        let city = rest.join("").replace(/^[\s|,·\-–—:]+|[\s|,·\-–—:]+$/g, "");
        if (!city)
            city = countryName || String(name ?? "");
        // "🇩🇪 Германия 🔥": the name already says the country
        const repeats = countryName && city.toLowerCase().startsWith(countryName.toLowerCase());
        return {flag, city, country: repeats ? "" : countryName};
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
    function protocolOf(p: var): string {
        return p?.protocol ?? String(p?.type ?? "").toUpperCase();
    }

    // ---- Ping: green fast, amber medium, red slow or no answer ----
    readonly property color good: "#34d399"
    function pingRank(ms: int): int {
        return ms > 0 ? ms : ms === 0 ? 1000000 : 999999;
    }
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
            return l("no answer", "нет ответа");
        return ms + l(" ms", " мс");
    }
    // 0–3 signal bars
    function pingBars(ms: int): int {
        return ms <= 0 ? 0 : ms < 120 ? 3 : ms < 300 ? 2 : 1;
    }

    function onOpened(): void {
        if (root.working || root.profiles.length === 0)
            return;
        const list = [];
        if (VpnPrefs.updateOnOpen && root.groups.some(g => g.subscription))
            list.push({command: "update", payload: {}, label: l("Updating subscriptions…", "Обновляю подписки…")});
        if (VpnPrefs.pingOnOpen)
            list.push(root.installStep(), root.pingStep(""));
        if (list.length)
            root.runSteps(list);
    }
    onVisibleChanged: {
        if (visible)
            root.onOpened();
        else
            root.settingsOpen = false;
    }
    Component.onCompleted: Qt.callLater(root.onOpened)

    Connections {
        target: ManagedVPN
        function onOperationFinished(command: string, success: bool): void {
            if (!root.steps.length || root.steps[0].command !== command)
                return;
            if (command === "import" && success)
                root.linkAdded();
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
        visible: !root.settingsOpen
        spacing: 0

        // Another VPN app keeps its own tunnel up: both fight over the traffic.
        StyledRect {
            Layout.fillWidth: true
            visible: root.otherTunnels.length > 0
            implicitHeight: conflictRow.implicitHeight + Tokens.padding.medium * 2
            color: Qt.alpha(Colours.palette.m3error, 0.16)

            RowLayout {
                id: conflictRow

                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.large
                anchors.rightMargin: Tokens.padding.large
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "warning"
                    color: Colours.palette.m3error
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.l(`Another VPN is on (${root.otherTunnels.join(", ")}${root.otherTunnels.some(t => t.startsWith("happ")) ? " — Happ" : ""}). Two VPNs fight over the traffic: turn it off so ping and connection work right.`,
                        `Включён другой VPN (${root.otherTunnels.join(", ")}${root.otherTunnels.some(t => t.startsWith("happ")) ? " — это Happ" : ""}). Два VPN мешают друг другу: выключите его, тогда пинг и подключение будут работать правильно.`)
                    color: Colours.palette.m3onSurface
                    wrapMode: Text.Wrap
                }
            }
        }

        Loader {
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: VpnPrefs.design === "list" ? listDesign : VpnPrefs.design === "cards" ? cardsDesign : orbDesign
        }
    }

    Component {
        id: orbDesign
        VpnDesignOrb { app: root }
    }
    Component {
        id: listDesign
        VpnDesignList { app: root }
    }
    Component {
        id: cardsDesign
        VpnDesignCards { app: root }
    }

    Loader {
        anchors.fill: parent
        active: root.settingsOpen
        sourceComponent: Component {
            VpnSettingsPage { app: root }
        }
    }
}
