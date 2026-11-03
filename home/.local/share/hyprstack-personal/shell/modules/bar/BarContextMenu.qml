// Personal overlay: the small menu that a right click on the taskbar opens (instead of opening
// the settings straight away, so an accidental click does nothing).

import QtQuick
import Quickshell
import Hyprstack.Config
import qs.components
import qs.components.effects
import qs.services

PopupWindow {
    id: menu

    required property Item target

    readonly property string edge: BarPosition.activeEdge

    function openAt(x: real, y: real): void {
        const horizontal = edge === "top" || edge === "bottom";
        anchor.rect = Qt.rect(horizontal ? x : (edge === "left" ? target.width : 0), horizontal ? (edge === "top" ? target.height : 0) : y, 1, 1);
        visible = true;
    }

    anchor.item: target
    anchor.edges: edge === "bottom" ? Edges.Top : edge === "top" ? Edges.Bottom : edge === "left" ? Edges.Right : Edges.Left
    anchor.gravity: anchor.edges
    visible: false
    grabFocus: true
    color: "transparent"
    implicitWidth: 300
    implicitHeight: column.implicitHeight + 16

    Rectangle {
        anchors.fill: parent
        color: Colours.palette.m3surfaceContainerLow
        border.color: Colours.palette.m3outlineVariant
        border.width: 1
        radius: Tokens.rounding.large
        focus: true
        Keys.onEscapePressed: menu.visible = false

        Column {
            id: column

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            spacing: 2

            MenuButton {
                icon: "edit"
                text: TaskbarStyle.l("Customize taskbar", "Настроить панель")
                onClicked: TaskbarStyle.startEditing()
            }

            MenuButton {
                icon: "settings"
                text: TaskbarStyle.l("Taskbar settings", "Параметры панели")
                onClicked: TaskbarStyle.openSettings(2)
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
