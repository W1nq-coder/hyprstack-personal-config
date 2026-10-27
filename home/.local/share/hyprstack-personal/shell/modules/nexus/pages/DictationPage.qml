pragma ComponentBehavior: Bound

// Personal overlay: voice input settings. Values live in
// ~/.config/hyprstack-dictation/config and are changed through
// `dictation set` (services/Dictation.qml); every press of the shortcut reads
// them again, so changes apply at once.

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

    title: l("Voice input", "Голосовой ввод")
    objectName: "dictationPage"

    readonly property var config: Dictation.config
    readonly property var voiceBind: Keybinds.bindings.find(b => b.action === "Voice input" && !b.submap)
    readonly property string chordText: voiceBind && voiceBind.shortcuts.length ? voiceBind.shortcuts.join(", ") : l("Not set", "Не задано")

    readonly property var modelHints: ({
        "large-v3-turbo-q5_0": l("Best quality, recommended.", "Лучшее качество, рекомендуется."),
        "large-v3-turbo-q8_0": l("Best quality, uses more memory.", "Лучшее качество, занимает больше памяти."),
        "medium-q5_0": l("Good quality.", "Хорошее качество."),
        "small": l("Faster, more mistakes.", "Быстрее, больше ошибок."),
        "small-q5_1": l("Fastest, more mistakes.", "Самая быстрая, больше ошибок.")
    })
    readonly property string modelName: root.config.model ? String(root.config.model).split("/").pop().replace(/^ggml-/, "").replace(/\.bin$/, "") : ""

    function modelLabel(model: var): string {
        return model.name + ` · ${Math.round((model.size ?? 0) / 1048576)} ${l("MB", "МБ")}`;
    }

    function sourceLabel(name: string): string {
        const found = (root.config.sources ?? []).find(s => s.name === name);
        return found ? found.description : name;
    }

    readonly property list<MenuItem> modeItems: [
        MenuItem { text: root.l("Press to start, press to stop", "Нажать для старта / нажать для остановки"); value: "toggle" },
        MenuItem { text: root.l("Hold to talk", "Удерживать и говорить"); value: "hold" }
    ]
    readonly property list<MenuItem> languageItems: [
        MenuItem { text: root.l("Russian", "Русский"); value: "ru" },
        MenuItem { text: root.l("English", "Английский"); value: "en" },
        MenuItem { text: root.l("Detect automatically", "Определять автоматически"); value: "auto" }
    ]
    readonly property Variants modelItems: Variants {
        model: root.config.models ?? []
        MenuItem {
            required property var modelData
            text: root.modelLabel(modelData)
            value: modelData.path
        }
    }
    readonly property MenuItem defaultSourceItem: MenuItem {
        text: root.l("System default", "Системный по умолчанию")
            + (root.config.defaultSource ? " (" + root.sourceLabel(root.config.defaultSource) + ")" : "")
        value: ""
    }
    readonly property Variants sourceItems: Variants {
        model: root.config.sources ?? []
        MenuItem {
            required property var modelData
            text: modelData.description
            value: modelData.name
        }
    }

    Component.onCompleted: Dictation.reloadConfig()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        StyledText {
            Layout.fillWidth: true
            Layout.bottomMargin: Tokens.spacing.small
            text: root.l("Speech is recognised on this computer (whisper.cpp), nothing is sent to the internet. The microphone is only on while you record.",
                "Речь распознаётся на этом компьютере (whisper.cpp), в интернет ничего не отправляется. Микрофон включён только во время записи.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
        }

        SectionHeader { text: root.l("Recording", "Запись") }
        InfoRow {
            first: true
            icon: "keyboard"
            label: root.l("Shortcut", "Сочетание клавиш")
            subtext: root.l("Change it in Keyboard shortcuts → Voice input", "Изменить можно в разделе «Сочетания клавиш» → «Голосовой ввод»")
            value: root.chordText
        }
        SelectRow {
            label: root.l("Mode", "Режим")
            subtext: root.config.mode === "hold"
                ? root.l("Recording runs while the shortcut is held and stops when it is released",
                    "Запись идёт, пока сочетание зажато, и останавливается при отпускании")
                : root.l("The first press starts recording, the second one stops it",
                    "Первое нажатие начинает запись, второе останавливает")
            menuItems: root.modeItems
            active: root.modeItems.find(i => i.value === root.config.mode) ?? root.modeItems[0]
            onSelected: item => Dictation.set("MODE", item.value)
        }
        SelectRow {
            label: root.l("Microphone", "Микрофон")
            menuItems: [root.defaultSourceItem, ...root.sourceItems.instances]
            active: menuItems.find(i => i.value === (root.config.source ?? "")) ?? (root.config.source ? null : root.defaultSourceItem)
            fallbackText: root.config.source ? root.config.source + root.l(" (not connected)", " (не подключён)") : ""
            onSelected: item => Dictation.set("SOURCE", item.value)
        }
        ToggleRow {
            last: true
            text: root.l("Sound signals", "Звуковые сигналы")
            subtext: root.l("When recording starts and after the text is inserted", "При начале записи и после вставки текста")
            checked: root.config.sounds !== false
            onToggled: Dictation.set("SOUNDS", checked ? "1" : "0")
        }

        SectionHeader { text: root.l("Recognition", "Распознавание") }
        SelectRow {
            first: true
            label: root.l("Language", "Язык")
            subtext: root.config.language === "auto"
                ? root.l("Short phrases are sometimes detected wrongly; choose the language for better results",
                    "Короткие фразы иногда определяются неверно; для точности лучше выбрать язык")
                : root.l("English terms inside Russian speech are recognised too", "Английские термины внутри русской речи тоже распознаются")
            menuItems: root.languageItems
            active: root.languageItems.find(i => i.value === root.config.language) ?? root.languageItems[0]
            onSelected: item => Dictation.set("LANGUAGE", item.value)
        }
        SelectRow {
            last: true
            label: root.l("Model", "Модель")
            subtext: (root.modelHints[root.modelName] ? root.modelHints[root.modelName] + " " : "")
                + root.l("Runs on the Intel graphics (Vulkan). A new model loads on the next recording.",
                    "Работает на графике Intel (Vulkan). Новая модель загрузится при следующей записи.")
            menuItems: root.modelItems.instances
            active: menuItems.find(i => i.value === root.config.model) ?? null
            fallbackText: root.config.model ? String(root.config.model).split("/").pop() : root.l("No models found", "Модели не найдены")
            onSelected: item => Dictation.set("MODEL", item.value)
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            visible: !!Dictation.error
            text: Dictation.error
            color: Colours.palette.m3error
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
        }

        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignRight
            horizontalAlignment: Text.AlignRight
            visible: Dictation.saving
            text: root.l("Saving…", "Сохранение…")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }
    }
}
