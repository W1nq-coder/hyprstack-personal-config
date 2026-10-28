pragma ComponentBehavior: Bound

// Personal overlay: Settings → Media. Look of the Media tab in the dashboard
// (services/MediaSettings.qml, ~/.config/hyprstack/media.json).

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

    title: l("Media", "Медиа")
    objectName: "mediaPage"

    readonly property var shapeNames: ({
        wavy: l("Wavy (default)", "Волнистая (как было)"),
        circle: l("Circle", "Круг"),
        square: l("Rounded square", "Квадрат со скруглением"),
        vinyl: l("Vinyl record", "Пластинка")
    })
    readonly property var shapeIcons: ({
        wavy: "cookie",
        circle: "circle",
        square: "square",
        vinyl: "album"
    })

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Variants {
            id: shapeItems

            model: MediaSettings.shapes

            MenuItem {
                required property string modelData
                readonly property string key: modelData

                icon: root.shapeIcons[modelData]
                text: root.shapeNames[modelData]
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.bottomMargin: Tokens.spacing.small
            text: root.l("How the Media tab of the dashboard looks. Changes apply immediately.",
                "Как выглядит вкладка «Медиа» в дашборде. Изменения применяются сразу.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
        }

        SectionHeader { text: root.l("Cover", "Обложка") }

        SelectRow {
            first: true
            label: root.l("Cover shape", "Форма обложки")
            subtext: root.l("The record shows the cover as its label", "У пластинки обложка — наклейка в центре")
            menuItems: shapeItems.instances
            active: shapeItems.instances.find(i => i.key === MediaSettings.coverShape) ?? null
            fallbackIcon: "cookie"
            fallbackText: root.shapeNames[MediaSettings.coverShape] ?? ""
            onSelected: item => MediaSettings.set("coverShape", item.key)
        }
        ToggleRow {
            text: root.l("Spin while playing", "Вращать во время музыки")
            subtext: root.l("Stops on pause", "На паузе останавливается")
            checked: MediaSettings.spin
            onToggled: MediaSettings.set("spin", checked)
        }
        ToggleRow {
            last: true
            text: root.l("Audio visualiser", "Визуализатор звука")
            subtext: root.l("Bars around the cover", "Полоски вокруг обложки")
            checked: MediaSettings.visualiser
            onToggled: MediaSettings.set("visualiser", checked)
        }

        SectionHeader { text: root.l("Controls", "Управление") }

        ToggleRow {
            first: true
            text: root.l("Volume", "Громкость")
            subtext: root.l("Player volume slider under the buttons", "Ползунок громкости плеера под кнопками")
            checked: MediaSettings.showVolume
            onToggled: MediaSettings.set("showVolume", checked)
        }
        ToggleRow {
            last: true
            text: root.l("Like button", "Кнопка «Мне нравится»")
            subtext: root.l("Adds the track to favourites; for players that support it (Gnova)",
                "Добавляет трек в избранное; для плееров, которые это умеют (Gnova)")
            checked: MediaSettings.showLike
            onToggled: MediaSettings.set("showLike", checked)
        }

        SectionHeader { text: "Gnova" }

        ToggleRow {
            first: true
            last: true
            text: root.l("Start Gnova at login", "Запускать Gnova при входе")
            subtext: root.l("Gnova is also in the app list (Super)", "Gnova также есть в списке приложений (Super)")
            checked: MediaSettings.gnovaAutostart
            onToggled: MediaSettings.setGnovaAutostart(checked)
        }

        SectionHeader { text: root.l("Lyrics", "Текст песни") }

        StyledText {
            Layout.fillWidth: true
            text: root.l("Lyrics are searched by artist and song; titles like \"Artists — Song (Official Video)\" are split automatically. The lyrics source is chosen in Settings → Services.",
                "Текст ищется по исполнителю и названию; названия вида «Исполнители — Песня (Official Video)» разбираются автоматически. Источник текстов выбирается в «Настройки → Службы».")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
        }
    }
}
