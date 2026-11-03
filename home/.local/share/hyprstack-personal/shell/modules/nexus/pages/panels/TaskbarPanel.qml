// Personal overlay: Position — the screen edge of the taskbar (services/BarPosition.qml).

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQml.Models
import Quickshell
import Hyprstack.Config
import Hyprstack.I18n
import qs.modules.nexus.common
import qs.components.controls
import qs.services

PageBase {
    id: root

    title: Tr.tr("Taskbar")
    isSubPage: true

    property string selectedScreen: ""
    property int screenRevision: 0
    readonly property var targetConfig: selectedScreen ? GlobalConfig.forScreen(selectedScreen) : GlobalConfig
    readonly property list<MenuItem> screenChoices: {
        screenRevision;
        const result = [allScreens];
        for (let i = 0; i < screenItems.count; ++i) {
            const choice = screenItems.objectAt(i);
            if (choice) result.push(choice);
        }
        return result;
    }
    readonly property var componentChoices: [
        {id: "logo", label: Tr.tr("Logo")},
        {id: "workspaces", label: Tr.tr("Workspaces")},
        {id: "activeWindow", label: Tr.tr("Active window")},
        {id: "tray", label: Tr.tr("Tray")},
        {id: "clock", label: Tr.tr("Clock")},
        {id: "statusIcons", label: Tr.tr("Status icons")},
        {id: "vpn", label: Tr.tr("VPN")},
        {id: "power", label: Tr.tr("Power button")}
    ]

    readonly property bool ru: String(Tr.language || Qt.locale().name).startsWith("ru")
    function l(en: string, rus: string): string { return root.ru ? rus : en; }
    readonly property var edgeNames: ({
        top: l("Top", "Сверху"),
        bottom: l("Bottom", "Снизу"),
        left: l("Left", "Слева"),
        right: l("Right", "Справа")
    })
    readonly property var edgeIcons: ({
        top: "vertical_align_top",
        bottom: "vertical_align_bottom",
        left: "align_horizontal_left",
        right: "align_horizontal_right"
    })

    readonly property MenuItem allScreens: MenuItem { text: Tr.tr("All screens"); icon: "desktop_windows"; value: "" }
    readonly property QtObject screenModel: Instantiator {
        id: screenItems
        model: Quickshell.screens
        delegate: MenuItem {
            required property var modelData
            text: modelData.name
            icon: "monitor"
            value: modelData.name
        }
        onObjectAdded: root.screenRevision++
        onObjectRemoved: (index, object) => {
            root.screenRevision++;
            if (root.selectedScreen === object.value) root.selectedScreen = "";
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Variants {
            id: edgeItems

            model: BarPosition.edges

            MenuItem {
                required property string modelData
                readonly property string key: modelData

                icon: root.edgeIcons[modelData]
                text: root.edgeNames[modelData]
            }
        }

        Variants {
            id: viewItems

            model: TaskbarStyle.views

            MenuItem {
                required property string modelData
                readonly property string key: modelData

                icon: ({labels: "view_list", icons: "apps", dock: "dock_to_bottom"})[modelData]
                text: ({
                        labels: root.l("Icons with titles", "Значки с названиями"),
                        icons: root.l("Icons only", "Только значки"),
                        dock: root.l("Dock (GNOME style)", "Док (как в GNOME)")
                    })[modelData]
            }
        }

        Variants {
            id: stackEdgeItems

            model: TaskbarStyle.edges

            MenuItem {
                required property string modelData
                readonly property string key: modelData

                icon: root.edgeIcons[modelData]
                text: root.edgeNames[modelData]
            }
        }

        Variants {
            id: dockEdgeItems

            model: TaskbarStyle.dockEdges

            MenuItem {
                required property string modelData
                readonly property string key: modelData

                icon: modelData === "auto" ? "swap_vert" : root.edgeIcons[modelData]
                text: modelData === "auto" ? root.l("Opposite to the bar", "Напротив панели") : root.edgeNames[modelData]
            }
        }

        Variants {
            id: dockAlignItems

            model: TaskbarStyle.dockAligns

            MenuItem {
                required property string modelData
                readonly property string key: modelData

                icon: ({center: "align_horizontal_center", start: "align_horizontal_left", end: "align_horizontal_right"})[modelData]
                text: ({
                        center: root.l("Centre", "По центру"),
                        start: root.l("Start (left / top)", "В начале (слева / сверху)"),
                        end: root.l("End (right / bottom)", "В конце (справа / снизу)")
                    })[modelData]
            }
        }

        // Behaviour
        SectionHeader {
            first: true
            text: Tr.tr("Behaviour")
        }

        SelectRow {
            first: true
            label: root.l("Position", "Расположение")
            subtext: root.l("Or hold an empty spot of the bar and drag it to an edge. This is the edge in the tiling mode; the floating windows mode has its own, below",
                "Или зажмите пустое место панели и перетащите её к краю. Это сторона в режиме тайлинга; у режима «как в Windows» своя, ниже")
            menuItems: edgeItems.instances
            active: edgeItems.instances.find(i => i.key === BarPosition.edge) ?? null
            fallbackIcon: root.edgeIcons[BarPosition.edge] ?? "vertical_align_top"
            fallbackText: root.edgeNames[BarPosition.edge] ?? ""
            onSelected: item => BarPosition.setEdge(item.key)
        }

        ToggleRow {
            text: Tr.tr("Persistent")
            subtext: Tr.tr("Keep the bar visible at all times")
            checked: Config.bar.persistent
            onToggled: GlobalConfig.bar.persistent = checked
        }

        ToggleRow {
            text: Tr.tr("Show on hover")
            subtext: Tr.tr("Reveal the bar when the cursor reaches the screen edge")
            checked: Config.bar.showOnHover
            onToggled: GlobalConfig.bar.showOnHover = checked
        }

        StepperRow {
            last: true
            label: Tr.tr("Drag threshold")
            subtext: Tr.tr("Pixels dragged before the bar reveals")
            value: Config.bar.dragThreshold
            from: 0
            to: 200
            stepSize: 5
            onMoved: v => GlobalConfig.bar.dragThreshold = v
        }

        // Floating (Windows-like) layout
        SectionHeader { text: root.l("Floating windows mode", "Режим «как в Windows»") }

        SelectRow {
            first: true
            label: root.l("Taskbar position", "Расположение панели")
            subtext: root.l("Bottom, top, left or right. You can also hold an empty spot of the bar and drag it to an edge",
                "Снизу, сверху, слева или справа. Можно и зажать пустое место панели и перетащить её к краю")
            menuItems: stackEdgeItems.instances
            active: stackEdgeItems.instances.find(i => i.key === TaskbarStyle.stackingEdge) ?? null
            fallbackIcon: root.edgeIcons[TaskbarStyle.stackingEdge] ?? "vertical_align_bottom"
            fallbackText: root.edgeNames[TaskbarStyle.stackingEdge] ?? ""
            onSelected: item => TaskbarStyle.setStackingEdge(item.key)
        }

        SelectRow {
            last: true
            label: root.l("Taskbar view", "Вид панели")
            subtext: root.l("Icons with titles, icons only, or a GNOME-style dock: the bar on one edge and the applications in a dock on the opposite one",
                "Значки с названиями, только значки или док как в GNOME: панель с одной стороны, а приложения в доке с противоположной")
            menuItems: viewItems.instances
            active: viewItems.instances.find(i => i.key === TaskbarStyle.view) ?? null
            fallbackIcon: "view_list"
            fallbackText: ""
            onSelected: item => TaskbarStyle.setView(item.key)
        }

        // Appearance of the bar and the dock (floating windows mode)
        SectionHeader { text: root.l("Appearance (floating windows mode)", "Внешний вид (режим «как в Windows»)") }

        SelectRow {
            first: true
            label: root.l("Dock edge", "Сторона дока")
            subtext: root.l("Where the dock stands. Used with the dock view of the taskbar", "Где стоит док. Работает с видом панели «Док»")
            menuItems: dockEdgeItems.instances
            active: dockEdgeItems.instances.find(i => i.key === TaskbarStyle.dockEdge) ?? null
            fallbackIcon: "swap_vert"
            fallbackText: ""
            onSelected: item => TaskbarStyle.setAppearance("dockEdge", item.key)
        }

        SelectRow {
            label: root.l("Dock alignment", "Выравнивание дока")
            subtext: root.l("Along its edge: in the centre or at one end", "Вдоль стороны: по центру или у края")
            menuItems: dockAlignItems.instances
            active: dockAlignItems.instances.find(i => i.key === TaskbarStyle.dockAlign) ?? null
            fallbackIcon: "align_horizontal_center"
            fallbackText: ""
            onSelected: item => TaskbarStyle.setAppearance("dockAlign", item.key)
        }

        StepperRow {
            label: root.l("Dock corner radius, px", "Скругление дока, px")
            subtext: root.l("0 gives square corners", "0 даёт прямые углы")
            value: TaskbarStyle.dockRadius
            from: 0
            to: 48
            stepSize: 2
            onMoved: v => TaskbarStyle.setAppearance("dockRadius", v)
        }

        StepperRow {
            label: root.l("Dock size, %", "Размер дока, %")
            subtext: root.l("Size of the dock and its icons", "Размер дока и его значков")
            value: TaskbarStyle.dockScale
            from: 60
            to: 180
            stepSize: 10
            onMoved: v => TaskbarStyle.setAppearance("dockScale", v)
        }

        StepperRow {
            label: root.l("Dock gap from the edge, px", "Отступ дока от края, px")
            value: TaskbarStyle.dockGap
            from: 0
            to: 60
            stepSize: 2
            onMoved: v => TaskbarStyle.setAppearance("dockGap", v)
        }

        StepperRow {
            label: root.l("Dock opacity, %", "Непрозрачность дока, %")
            value: TaskbarStyle.dockOpacity
            from: 10
            to: 100
            stepSize: 5
            onMoved: v => TaskbarStyle.setAppearance("dockOpacity", v)
        }

        StepperRow {
            label: root.l("Dock darkening, %", "Затемнение дока, %")
            subtext: root.l("Makes the dock background darker", "Делает фон дока темнее")
            value: TaskbarStyle.dockDim
            from: 0
            to: 80
            stepSize: 5
            onMoved: v => TaskbarStyle.setAppearance("dockDim", v)
        }

        StepperRow {
            label: root.l("Taskbar size, %", "Размер панели, %")
            subtext: root.l("Thickness of the taskbar and size of its icons", "Толщина панели и размер её значков")
            value: TaskbarStyle.barScale
            from: 70
            to: 180
            stepSize: 10
            onMoved: v => TaskbarStyle.setAppearance("barScale", v)
        }

        StepperRow {
            label: root.l("Taskbar opacity, %", "Непрозрачность панели, %")
            value: TaskbarStyle.barOpacity
            from: 10
            to: 100
            stepSize: 5
            onMoved: v => TaskbarStyle.setAppearance("barOpacity", v)
        }

        StepperRow {
            last: true
            label: root.l("Taskbar darkening, %", "Затемнение панели, %")
            subtext: root.l("Makes the taskbar background darker", "Делает фон панели темнее")
            value: TaskbarStyle.barDim
            from: 0
            to: 80
            stepSize: 5
            onMoved: v => TaskbarStyle.setAppearance("barDim", v)
        }

        NavRow {
            icon: "restart_alt"
            text: root.l("Reset appearance", "Сбросить внешний вид")
            onClicked: TaskbarStyle.resetAppearance()
        }

        // Components
        SectionHeader { text: Tr.tr("Element visibility") }

        SelectRow {
            first: true
            objectName: "taskbarScreenSelector"
            label: Tr.tr("Screen")
            subtext: Tr.tr("Choose a screen to hide individual panel elements")
            menuItems: root.screenChoices
            active: root.screenChoices.find(item => item.value === root.selectedScreen) ?? allScreens
            onSelected: item => root.selectedScreen = item.value
        }

        Repeater {
            model: root.componentChoices
            delegate: ToggleRow {
                required property var modelData
                objectName: "taskbarElement_" + modelData.id
                text: modelData.label
                checked: root.targetConfig.bar.entries.values.find(entry => entry.id === modelData.id)?.enabled ?? false
                onToggled: {
                    const entries = root.targetConfig.bar.entries;
                    const entry = entries.values.find(entry => entry.id === modelData.id);
                    if (entry) entry.enabled = checked;
                    else {
                        const beforePower = modelData.id === "vpn" ? entries.values.findIndex(item => item.id === "power") : -1;
                        entries.insert({id: modelData.id, enabled: checked}, beforePower);
                    }
                }
            }
        }

        ToggleRow {
            objectName: "taskbarElement_notifications"
            text: Tr.tr("Notification centre")
            checked: root.targetConfig.bar.showNotifications
            onToggled: root.targetConfig.bar.showNotifications = checked
        }

        ToggleRow {
            last: true
            objectName: "taskbarElement_tasks"
            text: Tr.tr("Applications in stacking mode")
            checked: root.targetConfig.bar.showTasks
            onToggled: root.targetConfig.bar.showTasks = checked
        }

        SectionHeader { text: root.l("Logo and layout", "Логотип и состав") }

        NavRow {
            first: true
            icon: "dock_to_bottom"
            text: root.l("Customize taskbar", "Настроить панель задач")
            subtext: root.l("Drag elements between the left, centre and right zones or hide them", "Перетаскивайте элементы между зонами слева, по центру и справа или скрывайте их")
            onClicked: TaskbarStyle.startEditing()
        }

        NavRow {
            last: true
            icon: "image"
            text: root.l("Taskbar logo", "Логотип панели")
            subtext: root.l("HyperStack, distribution, symbols or your own picture", "HyperStack, дистрибутив, значки или своя картинка")
            onClicked: root.nState.openSubPage(11)
        }

        SectionHeader {
            text: Tr.tr("Components")
        }

        NavRow {
            first: true
            icon: "workspaces"
            text: Tr.tr("Workspaces")
            subtext: Tr.tr("Indicators, window icons")
            onClicked: root.nState.openSubPage(6)
        }

        NavRow {
            icon: "web_asset"
            text: Tr.tr("Active window")
            subtext: Tr.tr("Title display, popout")
            onClicked: root.nState.openSubPage(7)
        }

        NavRow {
            icon: "widgets"
            text: Tr.tr("Tray")
            subtext: Tr.tr("System tray icons")
            onClicked: root.nState.openSubPage(8)
        }

        NavRow {
            icon: "signal_cellular_alt"
            text: Tr.tr("Status icons")
            subtext: Tr.tr("Visible indicators")
            onClicked: root.nState.openSubPage(9)
        }

        NavRow {
            last: true
            icon: "schedule"
            text: Tr.tr("Clock")
            subtext: Tr.tr("Date, icon, background")
            onClicked: root.nState.openSubPage(10)
        }

        // Scroll actions
        SectionHeader {
            text: Tr.tr("Scroll actions")
        }

        ToggleRow {
            first: true
            last: true
            text: Tr.tr("Workspaces")
            subtext: Tr.tr("Scroll over the workspace indicator to switch workspaces")
            checked: Config.bar.scrollActions.workspaces
            onToggled: GlobalConfig.bar.scrollActions.workspaces = checked
        }

    }
}
