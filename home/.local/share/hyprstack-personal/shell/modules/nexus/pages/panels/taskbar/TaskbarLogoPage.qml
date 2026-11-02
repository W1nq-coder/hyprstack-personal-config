// Personal overlay: Settings → Panels → Taskbar → Logo. Choose the picture of the logo button:
// the HyperStack logo, the distribution logo, a built-in symbol or a picture of your own.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Hyprstack.Components
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.controls
import qs.components.effects
import qs.components.filedialog
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property bool ru: String(Tr.language || Qt.locale().name).startsWith("ru")
    function l(en: string, rus: string): string { return root.ru ? rus : en; }

    title: l("Taskbar logo", "Логотип панели")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.small

        // ---- the current logo ----
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: 96
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer

            RowLayout {
                anchors.centerIn: parent
                spacing: 20

                Item {
                    implicitWidth: 56
                    implicitHeight: 56

                    Loader {
                        anchors.centerIn: parent
                        sourceComponent: {
                            switch (TaskbarStyle.logoMode) {
                            case "hyprstack":
                                return hyprLogo;
                            case "distro":
                                return distroLogo;
                            case "glyph":
                                return glyphLogo;
                            case "image":
                                return TaskbarStyle.logoPath !== "" ? imageLogo : hyprLogo;
                            default:
                                return SysInfo.isDefaultLogo ? hyprLogo : distroLogo;
                            }
                        }
                    }
                }

                StyledText {
                    text: root.l("Current logo. Right click it on the taskbar to open this page.", "Текущий логотип. Правый клик по нему на панели открывает эту страницу.")
                    color: Colours.palette.m3onSurfaceVariant
                    wrapMode: Text.Wrap
                    Layout.maximumWidth: 360
                }
            }
        }

        // ---- ready-made ----
        SectionHeader { text: root.l("Ready-made", "Готовые") }

        Flow {
            Layout.fillWidth: true
            spacing: 8

            LogoCard {
                selected: TaskbarStyle.logoMode === "default"
                label: root.l("Default", "По умолчанию")
                onClicked: TaskbarStyle.resetLogo()

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "restart_alt"
                    color: Colours.palette.m3onSurface
                    fontStyle: Tokens.font.icon.large
                }
            }

            LogoCard {
                selected: TaskbarStyle.logoMode === "hyprstack"
                label: "HyperStack"
                onClicked: TaskbarStyle.setLogo("hyprstack", "", "")

                Logo {
                    anchors.centerIn: parent
                    implicitWidth: 34
                    implicitHeight: 34
                }
            }

            LogoCard {
                selected: TaskbarStyle.logoMode === "distro"
                label: root.l("Distribution", "Дистрибутив")
                onClicked: TaskbarStyle.setLogo("distro", "", "")

                ColouredIcon {
                    anchors.centerIn: parent
                    source: SysInfo.osLogo
                    implicitSize: 32
                    colour: Colours.palette.m3tertiary
                }
            }
        }

        // ---- symbols ----
        SectionHeader { text: root.l("Symbols", "Значки") }

        Flow {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: TaskbarStyle.glyphs

                LogoCard {
                    id: sym

                    required property string modelData

                    compact: true
                    selected: TaskbarStyle.logoMode === "glyph" && TaskbarStyle.logoGlyph === modelData
                    onClicked: TaskbarStyle.setLogo("glyph", modelData, "")

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: sym.modelData
                        color: Colours.palette.m3tertiary
                        fill: 1
                        fontStyle: Tokens.font.icon.large
                    }
                }
            }
        }

        // ---- own picture ----
        SectionHeader { text: root.l("Your own picture", "Своя картинка") }

        ButtonRow {
            Layout.alignment: Qt.AlignLeft
            spacing: Tokens.spacing.small

            IconTextButton {
                icon: "add_photo_alternate"
                text: root.l("Choose picture…", "Выбрать картинку…")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                onClicked: pictureDialog.open()

                // The dialog is a child of the button (like on the wallpaper page): it is not an item.
                FileDialog {
                    id: pictureDialog

                    title: root.l("Select a logo picture", "Выберите картинку для логотипа")
                    filterLabel: root.l("Image files", "Изображения")
                    filters: Images.validImageExtensions
                    onAccepted: path => TaskbarStyle.setLogo("image", "", path)
                }
            }

            IconTextButton {
                icon: "restart_alt"
                text: root.l("Reset logo", "Сбросить логотип")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                type: IconTextButton.Tonal
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                onClicked: TaskbarStyle.resetLogo()
            }
        }

        ToggleRow {
            first: true
            last: true
            text: root.l("Recolour with the theme colour", "Перекрасить в цвет темы")
            subtext: root.l("Off keeps a photo as it is. Turn on for one-colour icons (PNG/SVG)", "Выключено: фото остаётся как есть. Включите для одноцветных значков (PNG/SVG)")
            enabled: TaskbarStyle.logoMode === "image"
            checked: TaskbarStyle.logoTint
            onToggled: TaskbarStyle.setLogoTint(checked)
        }

        // Pictures for the preview (non-visual, so they can live inside the layout).
        Component {
            id: hyprLogo

            Logo {
                implicitWidth: 48
                implicitHeight: 48
            }
        }

        Component {
            id: distroLogo

            ColouredIcon {
                source: SysInfo.osLogo
                implicitSize: 44
                colour: Colours.palette.m3tertiary
            }
        }

        Component {
            id: glyphLogo

            MaterialIcon {
                text: TaskbarStyle.logoGlyph
                color: Colours.palette.m3tertiary
                fill: 1
                fontStyle: Tokens.font.icon.extraLarge
            }
        }

        Component {
            id: imageLogo

            Image {
                width: 56
                height: 56
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(112, 112)
                source: Paths.fileUrl(TaskbarStyle.logoPath)
            }
        }
    }

    // A square card with a picture in it; the border shows the chosen one.
    component LogoCard: StyledRect {
        id: card

        property bool selected
        property bool compact
        property string label
        default property alias content: slot.data
        signal clicked

        implicitWidth: compact ? 64 : 150
        implicitHeight: compact ? 64 : 96
        radius: Tokens.rounding.large
        color: selected ? Qt.alpha(Colours.palette.m3primary, 0.18) : Colours.tPalette.m3surfaceContainer
        border.width: selected ? 2 : 0
        border.color: Colours.palette.m3primary

        StateLayer {
            radius: card.radius
            onClicked: card.clicked()
        }

        Item {
            id: slot

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: card.compact ? card.height : card.height - 28
        }

        StyledText {
            visible: card.label !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            text: card.label
            font: Tokens.font.label.medium
            color: Colours.palette.m3onSurfaceVariant
        }
    }
}
