// Personal overlay (VPN app): a country flag in a rounded box, or a globe.
import QtQuick
import Hyprstack.Config
import qs.components
import qs.services

StyledRect {
    id: root

    property string flag
    property int size: 56

    implicitWidth: size
    implicitHeight: size
    radius: Math.round(size * 0.22)
    color: Colours.palette.m3surfaceContainerHigh
    border.width: 1
    border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.5)

    Text {
        anchors.centerIn: parent
        visible: root.flag.length > 0
        text: root.flag
        font.family: "Noto Color Emoji"
        font.pixelSize: Math.round(root.size * 0.55)
    }
    MaterialIcon {
        anchors.centerIn: parent
        visible: root.flag.length === 0
        text: "public"
        fontStyle: Tokens.font.icon.large
        color: Colours.palette.m3onSurfaceVariant
    }
}
