// Personal overlay: the logo button of the taskbar. The picture is chosen in Settings → Panels →
// Taskbar → Logo (services/TaskbarStyle.qml); right click opens a small menu with the settings.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.effects
import qs.services
import qs.utils

Item {
    id: root

    readonly property bool ru: String(Tr.language || Qt.locale().name).startsWith("ru")
    function l(en: string, rus: string): string { return root.ru ? rus : en; }

    readonly property int logoSize: Math.round(Tokens.font.body.large.pointSize * 1.2)
    readonly property string mode: TaskbarStyle.logoMode

    implicitWidth: logoSize
    implicitHeight: logoSize

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                menu.visible = !menu.visible;
                return;
            }
            const screenState = ShellState.forActive();
            screenState.launcher = !screenState.launcher;
        }
    }

    Loader {
        anchors.centerIn: parent
        sourceComponent: {
            switch (root.mode) {
            case "hyprstack":
                return hyprstackLogo;
            case "distro":
                return distroIcon;
            case "glyph":
                return glyphLogo;
            case "image":
                return TaskbarStyle.logoPath !== "" ? (TaskbarStyle.logoTint ? tintedImage : plainImage) : hyprstackLogo;
            default:
                return SysInfo.isDefaultLogo ? hyprstackLogo : distroIcon;
            }
        }
    }

    Component {
        id: hyprstackLogo

        Logo {
            implicitWidth: Math.round(Tokens.font.body.large.pointSize * 1.6)
            implicitHeight: Math.round(Tokens.font.body.large.pointSize * 1.6)
        }
    }

    Component {
        id: distroIcon

        ColouredIcon {
            source: SysInfo.osLogo
            implicitSize: root.logoSize
            colour: Colours.palette.m3tertiary
        }
    }

    Component {
        id: glyphLogo

        MaterialIcon {
            text: TaskbarStyle.logoGlyph
            color: Colours.palette.m3tertiary
            fill: 1
            fontStyle: Tokens.font.icon.large
        }
    }

    // A picture of your own, shown as it is (rounded), or recoloured like the other panel icons.
    Component {
        id: plainImage

        Image {
            width: Math.round(root.logoSize * 1.4)
            height: width
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(width * 2, height * 2)
            source: Paths.fileUrl(TaskbarStyle.logoPath)
        }
    }

    Component {
        id: tintedImage

        ColouredIcon {
            source: Paths.fileUrl(TaskbarStyle.logoPath)
            implicitSize: root.logoSize
            colour: Colours.palette.m3tertiary
        }
    }

    // ---- right click menu ----
    PopupWindow {
        id: menu

        readonly property string edge: BarPosition.activeEdge

        anchor.item: root
        anchor.edges: edge === "bottom" ? Edges.Top : edge === "top" ? Edges.Bottom : edge === "left" ? Edges.Right : Edges.Left
        anchor.gravity: anchor.edges
        anchor.rect.y: edge === "bottom" ? -8 : edge === "top" ? 8 : 0
        anchor.rect.x: edge === "right" ? -8 : edge === "left" ? 8 : 0
        visible: false
        grabFocus: true
        color: "transparent"
        implicitWidth: 330
        implicitHeight: menuColumn.implicitHeight + 16

        Rectangle {
            anchors.fill: parent
            color: Colours.palette.m3surfaceContainerLow
            border.color: Colours.palette.m3outlineVariant
            border.width: 1
            radius: Tokens.rounding.large
            focus: true
            Keys.onEscapePressed: menu.visible = false

            Column {
                id: menuColumn

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                spacing: 2

                MenuButton {
                    icon: "image"
                    text: root.l("Customize logo", "Настроить логотип")
                    onClicked: TaskbarStyle.openSettings(11)
                }

                MenuButton {
                    icon: "dock_to_bottom"
                    text: root.l("Customize taskbar", "Настроить панель задач")
                    onClicked: TaskbarStyle.openSettings(12)
                }

                MenuButton {
                    icon: "settings"
                    text: root.l("Taskbar settings", "Параметры панели")
                    onClicked: TaskbarStyle.openSettings(2)
                }
            }
        }
    }

    component MenuButton: Item {
        id: button

        required property string text
        required property string icon
        signal clicked

        width: parent?.width ?? 0
        implicitHeight: 40

        StateLayer {
            radius: Tokens.rounding.medium
            onClicked: {
                menu.visible = false;
                button.clicked();
            }
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 12
            spacing: 12

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: button.icon
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: button.text
                font: Tokens.font.body.medium
            }
        }
    }
}
