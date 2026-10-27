pragma ComponentBehavior: Bound

// Personal overlay: mouse & touchpad settings, modelled on KDE Plasma's
// Input Devices → Mouse / Touchpad. See services/InputSettings.qml.

import QtQuick
import QtQuick.Layouts
import Hyprstack.Config
import Hyprstack.I18n
import Quickshell
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property bool ru: String(Tr.language || Qt.locale().name).startsWith("ru")
    function l(en: string, rus: string): string { return root.ru ? rus : en; }

    title: l("Mouse & touchpad", "Мышь и тачпад")
    objectName: "inputDevicesPage"

    property string tab: InputSettings.touchpads.length && !InputSettings.mice.length ? "touchpad" : "mouse"
    property string mouseScope: ""
    property string touchpadScope: ""
    readonly property string section: tab
    readonly property string scope: tab === "mouse" ? mouseScope : touchpadScope

    function v(key: string): var { return InputSettings.value(root.section, root.scope, key); }
    function put(key: string, value: var): void { InputSettings.set(root.section, root.scope, key, value); }

    // Slider ranges (sliders work with 0…1)
    function toUnit(value: real, from: real, to: real): real { return Math.max(0, Math.min(1, (value - from) / (to - from))); }
    function fromUnit(value: real, from: real, to: real, step: real): real { return Math.round((from + value * (to - from)) / step) * step; }

    readonly property list<MenuItem> accelItems: [
        MenuItem { text: root.l("Adaptive", "Адаптивный"); value: "adaptive" },
        MenuItem { text: root.l("Flat", "Плоский"); value: "flat" }
    ]
    readonly property list<MenuItem> clickItems: [
        MenuItem { text: root.l("Button areas", "Зоны кнопок"); value: false },
        MenuItem { text: root.l("Number of fingers", "Число пальцев"); value: true }
    ]
    readonly property list<MenuItem> tapMapItems: [
        MenuItem { text: root.l("2 fingers: right, 3: middle", "2 пальца: правая, 3: средняя"); value: "lrm" },
        MenuItem { text: root.l("2 fingers: middle, 3: right", "2 пальца: средняя, 3: правая"); value: "lmr" }
    ]
    readonly property list<MenuItem> dragLockItems: [
        MenuItem { text: root.l("Off", "Выключена"); value: 0 },
        MenuItem { text: root.l("With timeout", "С тайм-аутом"); value: 1 },
        MenuItem { text: root.l("Until tapped again", "До повторного касания"); value: 2 }
    ]
    readonly property list<MenuItem> scrollMethodItems: [
        MenuItem { text: root.l("Two fingers", "Двумя пальцами"); value: "2fg" },
        MenuItem { text: root.l("Touchpad edge", "По краю тачпада"); value: "edge" }
    ]

    readonly property MenuItem allMice: MenuItem { text: root.l("All mice", "Все мыши"); value: "" }
    readonly property MenuItem allTouchpads: MenuItem { text: root.l("All touchpads", "Все тачпады"); value: "" }
    readonly property Variants mouseItems: Variants {
        model: InputSettings.mice
        MenuItem {
            required property var modelData
            text: modelData.label
            value: modelData.name
        }
    }
    readonly property Variants touchpadItems: Variants {
        model: InputSettings.touchpads
        MenuItem {
            required property var modelData
            text: modelData.label
            value: modelData.name
        }
    }

    Component.onCompleted: InputSettings.reload()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        RowLayout {
            Layout.bottomMargin: Tokens.spacing.small
            spacing: Tokens.spacing.small
            IconTextButton {
                type: root.tab === "mouse" ? TextButton.Filled : TextButton.Tonal
                icon: "mouse"
                text: root.l("Mouse", "Мышь")
                onClicked: root.tab = "mouse"
            }
            IconTextButton {
                type: root.tab === "touchpad" ? TextButton.Filled : TextButton.Tonal
                icon: "touchpad_mouse"
                text: root.l("Touchpad", "Тачпад")
                onClicked: root.tab = "touchpad"
            }
        }

        // Device
        SelectRow {
            first: true
            last: true
            label: root.l("Device", "Устройство")
            subtext: root.scope ? root.l("Settings apply to this device only", "Настройки только для этого устройства")
                : root.l("Settings apply to every device of this kind, including ones connected later",
                    "Настройки для всех устройств этого типа, в том числе подключённых позже")
            menuItems: root.tab === "mouse" ? [root.allMice, ...root.mouseItems.instances] : [root.allTouchpads, ...root.touchpadItems.instances]
            active: menuItems.find(item => item.value === root.scope) ?? menuItems[0]
            onSelected: item => {
                if (root.tab === "mouse")
                    root.mouseScope = item.value;
                else
                    root.touchpadScope = item.value;
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            visible: root.tab === "mouse" && !InputSettings.mice.length
            text: root.l("No external mouse is connected. These settings will be used when one is plugged in.",
                "Внешняя мышь не подключена. Эти настройки применятся, когда она будет подключена.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            visible: root.tab === "touchpad" && !InputSettings.touchpads.length
            text: root.l("No touchpad found.", "Тачпад не найден.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
        }

        StyledText {
            Layout.fillWidth: true
            visible: !!InputSettings.error
            text: InputSettings.error
            color: Colours.palette.m3error
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
        }

        // ---- Touchpad: general -------------------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.tab === "touchpad" && InputSettings.touchpads.length > 0
            spacing: Tokens.spacing.extraSmall / 2

            SectionHeader { text: root.l("General", "Общие") }
            ToggleRow {
                first: true
                text: root.l("Touchpad enabled", "Тачпад включён")
                checked: root.v("enabled") !== false
                onToggled: root.put("enabled", checked)
            }
            ToggleRow {
                text: root.l("Disable while typing", "Отключать при наборе текста")
                subtext: root.l("The delay is chosen by libinput and cannot be changed in Hyprland",
                    "Задержку выбирает libinput, в Hyprland её изменить нельзя")
                checked: !!root.v("disable_while_typing")
                onToggled: root.put("disable_while_typing", checked)
            }
            ToggleRow {
                last: true
                visible: !root.scope
                text: root.l("Disable when an external mouse is connected", "Отключать, когда подключена внешняя мышь")
                subtext: (InputSettings.external ? root.l("A mouse is connected now. ", "Мышь сейчас подключена. ")
                    : root.l("No mouse connected now. ", "Мышь сейчас не подключена. "))
                    + root.l("Works while the shell is running.", "Работает, пока запущена оболочка.")
                checked: InputSettings.section("touchpad").auto_disable === true
                onToggled: InputSettings.setAutoDisable(checked)
            }
        }

        // ---- Pointer (both tabs) -------------------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.tab === "mouse" || InputSettings.touchpads.length > 0
            spacing: Tokens.spacing.extraSmall / 2

            SectionHeader { text: root.l("Pointer", "Указатель") }
            SliderRow {
                first: true
                icon: "speed"
                label: root.l("Pointer speed", "Скорость указателя")
                readonly property real current: Number(root.v("sensitivity") ?? 0)
                valueLabel: (current > 0 ? "+" : "") + current.toFixed(2)
                value: root.toUnit(current, -1, 1)
                onMoved: value => root.put("sensitivity", root.fromUnit(value, -1, 1, 0.05))
            }
            ToggleRow {
                text: root.l("Pointer acceleration", "Ускорение указателя")
                subtext: root.l("Off uses the flat profile: the pointer moves exactly as far as the hand",
                    "Выключено — плоский профиль: указатель движется ровно на столько же, на сколько рука")
                checked: root.v("accel_profile") === "adaptive"
                onToggled: root.put("accel_profile", checked ? "adaptive" : "flat")
            }
            SelectRow {
                label: root.l("Acceleration profile", "Профиль ускорения")
                menuItems: root.accelItems
                active: root.accelItems.find(i => i.value === root.v("accel_profile")) ?? root.accelItems[0]
                onSelected: item => root.put("accel_profile", item.value)
            }
            ToggleRow {
                last: true
                text: root.l("Left-handed mode", "Режим для левши")
                subtext: root.l("Swap left and right buttons", "Поменять местами левую и правую кнопки")
                checked: !!root.v("left_handed")
                onToggled: root.put("left_handed", checked)
            }
        }

        // ---- Touchpad: tapping and clicking --------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.tab === "touchpad" && InputSettings.touchpads.length > 0
            spacing: Tokens.spacing.extraSmall / 2

            SectionHeader { text: root.l("Tapping", "Касания") }
            ToggleRow {
                first: true
                text: root.l("Tap to click", "Нажатие касанием")
                checked: !!root.v("tap_to_click")
                onToggled: root.put("tap_to_click", checked)
            }
            SelectRow {
                enabled: !!root.v("tap_to_click")
                label: root.l("Multi-finger tap", "Касание несколькими пальцами")
                menuItems: root.tapMapItems
                active: root.tapMapItems.find(i => i.value === root.v("tap_button_map")) ?? root.tapMapItems[0]
                onSelected: item => root.put("tap_button_map", item.value)
            }
            ToggleRow {
                disabled: !root.v("tap_to_click")
                text: root.l("Tap-and-drag", "Перетаскивание касанием")
                subtext: root.l("Tap twice and keep the finger down to drag", "Двойное касание с удержанием пальца перетаскивает")
                checked: !!root.v("tap_and_drag")
                onToggled: root.put("tap_and_drag", checked)
            }
            SelectRow {
                last: true
                enabled: !!root.v("tap_to_click") && !!root.v("tap_and_drag")
                label: root.l("Drag lock", "Фиксация перетаскивания")
                subtext: root.l("Keep dragging after the finger is lifted", "Продолжать перетаскивание после отрыва пальца")
                menuItems: root.dragLockItems
                active: root.dragLockItems.find(i => i.value === Number(root.v("drag_lock") ?? 0)) ?? root.dragLockItems[0]
                onSelected: item => root.put("drag_lock", item.value)
            }

            SectionHeader { text: root.l("Clicking", "Нажатие") }
            SelectRow {
                first: true
                label: root.l("Right and middle click", "Правая и средняя кнопки")
                subtext: root.v("clickfinger_behavior")
                    ? root.l("Press with two fingers for right click, three for middle", "Нажатие двумя пальцами — правая кнопка, тремя — средняя")
                    : root.l("Press the bottom-right corner for right click, bottom middle for middle", "Нажатие в правом нижнем углу — правая кнопка, внизу посередине — средняя")
                menuItems: root.clickItems
                active: root.clickItems.find(i => i.value === !!root.v("clickfinger_behavior")) ?? root.clickItems[0]
                onSelected: item => root.put("clickfinger_behavior", item.value)
            }
            ToggleRow {
                last: true
                text: root.l("Middle-click emulation", "Эмуляция средней кнопки")
                subtext: root.l("Press left and right together", "Одновременное нажатие левой и правой")
                checked: !!root.v("middle_button_emulation")
                onToggled: root.put("middle_button_emulation", checked)
            }
        }

        // ---- Scrolling (both tabs) --------------------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.tab === "mouse" || InputSettings.touchpads.length > 0
            spacing: Tokens.spacing.extraSmall / 2

            SectionHeader { text: root.l("Scrolling", "Прокрутка") }
            ToggleRow {
                first: true
                text: root.l("Invert scroll direction (natural scrolling)", "Обратное направление (естественная прокрутка)")
                checked: !!root.v("natural_scroll")
                onToggled: root.put("natural_scroll", checked)
            }
            SelectRow {
                visible: root.tab === "touchpad"
                label: root.l("Scrolling method", "Способ прокрутки")
                menuItems: root.scrollMethodItems
                active: root.scrollMethodItems.find(i => i.value === root.v("scroll_method")) ?? root.scrollMethodItems[0]
                onSelected: item => root.put("scroll_method", item.value)
            }
            SliderRow {
                last: root.tab === "touchpad"
                icon: "swap_vert"
                label: root.l("Scrolling speed", "Скорость прокрутки")
                readonly property real current: Number(root.v("scroll_factor") ?? 1)
                valueLabel: "×" + current.toFixed(2)
                value: root.toUnit(current, 0.1, 3)
                onMoved: value => root.put("scroll_factor", root.fromUnit(value, 0.1, 3, 0.05))
            }
            ToggleRow {
                last: true
                visible: root.tab === "mouse"
                text: root.l("Middle-click emulation", "Эмуляция средней кнопки")
                subtext: root.l("Press left and right together", "Одновременное нажатие левой и правой")
                checked: !!root.v("middle_button_emulation")
                onToggled: root.put("middle_button_emulation", checked)
            }
        }

        // ---- Touchpad: gestures (shell-wide) ---------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.tab === "touchpad" && !root.scope && InputSettings.touchpads.length > 0
            spacing: Tokens.spacing.extraSmall / 2

            SectionHeader { text: root.l("Gestures", "Жесты") }
            ToggleRow {
                first: true
                text: root.l("Switch workspaces with a three-finger swipe", "Переключение рабочих столов свайпом тремя пальцами")
                subtext: root.l("Swipe up or down. Horizontal three-finger swipes scroll the window columns.",
                    "Свайп вверх или вниз. Свайп тремя пальцами по горизонтали прокручивает колонки окон.")
                checked: InputSettings.gesture("enabled") !== false
                onToggled: InputSettings.setGesture("enabled", checked)
            }
            ToggleRow {
                disabled: InputSettings.gesture("enabled") === false
                text: root.l("Invert swipe direction", "Обратное направление свайпа")
                checked: !!InputSettings.gesture("invert")
                onToggled: InputSettings.setGesture("invert", checked)
            }
            SliderRow {
                last: true
                enabled: InputSettings.gesture("enabled") !== false
                icon: "swipe"
                label: root.l("Swipe sensitivity", "Чувствительность свайпа")
                readonly property int distance: Number(InputSettings.gesture("distance") ?? 700)
                valueLabel: root.l("%1 px per workspace", "%1 пикс. на рабочий стол").arg(distance)
                // Shorter distance = more sensitive.
                value: root.toUnit(1500 - distance, 0, 1300)
                onMoved: value => InputSettings.setGesture("distance", 1500 - root.fromUnit(value, 0, 1300, 50))
            }
        }

        TextButton {
            Layout.alignment: Qt.AlignRight
            Layout.topMargin: Tokens.spacing.medium
            visible: root.tab === "mouse" || InputSettings.touchpads.length > 0
            type: TextButton.Tonal
            text: root.l("Reset to defaults", "Сбросить к значениям по умолчанию")
            disabled: !InputSettings.hasChanges(root.section, root.scope)
            onClicked: InputSettings.reset(root.section, root.scope)
        }

        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignRight
            horizontalAlignment: Text.AlignRight
            visible: InputSettings.saving
            text: root.l("Applying…", "Применение…")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }
    }
}
