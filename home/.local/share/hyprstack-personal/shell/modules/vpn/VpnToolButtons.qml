// Personal overlay (VPN app): settings, maximize and close buttons.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Hyprstack.Config
import qs.components
import qs.components.controls

RowLayout {
    id: root

    required property var app

    spacing: 0

    IconButton {
        type: IconButton.Text
        icon: "settings"
        onClicked: root.app.settingsOpen = true
        ToolTip.visible: hovered
        ToolTip.text: root.app.l("Settings", "Настройки")
    }
    IconButton {
        type: IconButton.Text
        icon: "open_in_full"
        onClicked: root.app.maximize()
        ToolTip.visible: hovered
        ToolTip.text: root.app.l("Maximize", "Развернуть")
    }
    IconButton {
        type: IconButton.Text
        icon: "close"
        onClicked: root.app.close()
    }
}
