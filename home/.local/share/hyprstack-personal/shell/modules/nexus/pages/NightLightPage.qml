pragma ComponentBehavior: Bound

// Personal overlay: night light settings (services/NightLight.qml,
// ~/.local/bin/nightlight). Changes apply at once.

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

    title: l("Night light", "Ночной режим")
    objectName: "nightLightPage"

    readonly property int span: NightLight.maxTemperature - NightLight.minTemperature
    // Slider to the right = warmer (lower temperature).
    property int pendingTemperature: NightLight.temperature
    readonly property var shortcuts: ["Night light", "Night light warmer", "Night light cooler"].map(action => {
        const bind = Keybinds.bindings.find(b => b.action === action && !b.submap);
        return bind && bind.shortcuts.length ? bind.shortcuts[0].replace(/\bequal\b/i, "=").replace(/\bminus\b/i, "−") : l("not set", "не задано");
    })

    function hourOf(time: string): int { return Number(String(time).split(":")[0]) || 0; }
    function hh(hour: int): string { return (hour < 10 ? "0" : "") + hour + ":00"; }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Timer {
            id: temperatureTimer

            interval: 150
            onTriggered: NightLight.setTemperature(root.pendingTemperature)
        }

        Connections {
            target: NightLight
            function onTemperatureChanged(): void {
                if (!temperatureTimer.running)
                    root.pendingTemperature = NightLight.temperature;
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.bottomMargin: Tokens.spacing.small
            text: root.l("Makes the screen warmer and less blue, which is easier on the eyes in the evening.",
                "Делает экран тёплым, с меньшим количеством синего света: вечером так легче глазам.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
        }

        ToggleRow {
            first: true
            text: root.l("Night light", "Ночной режим")
            subtext: root.l("Also in the quick toggles and with %1", "Также в быстрых переключателях и по %1").arg(root.shortcuts[0])
            checked: NightLight.enabled
            onToggled: NightLight.setEnabled(checked)
        }
        SliderRow {
            last: true
            icon: "wb_twilight"
            label: root.l("Warmth", "Теплота")
            valueLabel: root.pendingTemperature + " K"
            value: Math.max(0, Math.min(1, (NightLight.maxTemperature - root.pendingTemperature) / root.span))
            onMoved: value => {
                root.pendingTemperature = Math.round((NightLight.maxTemperature - value * root.span) / 100) * 100;
                temperatureTimer.restart();
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            text: root.l("Shortcuts: %1 warmer, %2 cooler. They can be changed in Keyboard shortcuts.",
                "Сочетания: %1 — теплее, %2 — холоднее. Изменить их можно в разделе «Сочетания клавиш».")
                .arg(root.shortcuts[1]).arg(root.shortcuts[2])
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
        }

        SectionHeader { text: root.l("Schedule", "Расписание") }
        ToggleRow {
            first: true
            text: root.l("Turn on automatically", "Включать автоматически")
            subtext: root.l("From %1 to %2. You can still switch it manually in between.",
                "С %1 до %2. В это время его всё равно можно выключить вручную.")
                .arg(NightLight.scheduleFrom).arg(NightLight.scheduleTo)
            checked: NightLight.scheduleEnabled
            onToggled: NightLight.setSchedule(checked)
        }
        StepperRow {
            label: root.l("Turn on at (hour)", "Включать в (час)")
            subtext: root.hh(value)
            enabled: NightLight.scheduleEnabled
            value: root.hourOf(NightLight.scheduleFrom)
            from: 0
            to: 23
            onMoved: v => NightLight.setScheduleTimes(root.hh(v), NightLight.scheduleTo)
        }
        StepperRow {
            last: true
            label: root.l("Turn off at (hour)", "Выключать в (час)")
            subtext: root.hh(value)
            enabled: NightLight.scheduleEnabled
            value: root.hourOf(NightLight.scheduleTo)
            from: 0
            to: 23
            onMoved: v => NightLight.setScheduleTimes(NightLight.scheduleFrom, root.hh(v))
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            visible: !!NightLight.error
            text: NightLight.error
            color: Colours.palette.m3error
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
        }
    }
}
