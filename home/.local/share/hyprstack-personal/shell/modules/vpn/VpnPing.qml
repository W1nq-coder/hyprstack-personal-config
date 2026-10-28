// Personal overlay (VPN app): ping in a pill with a coloured dot.
import QtQuick
import QtQuick.Layouts
import Hyprstack.Config
import qs.components
import qs.services

StyledRect {
    id: root

    required property var app
    property int ms: -1
    readonly property color tone: app.pingColour(ms)

    implicitWidth: row.implicitWidth + Tokens.padding.large * 2
    implicitHeight: 32
    radius: Tokens.rounding.full
    color: Qt.alpha(tone, 0.12)
    border.width: 1
    border.color: Qt.alpha(tone, 0.35)

    RowLayout {
        id: row

        anchors.centerIn: parent
        spacing: Tokens.spacing.small

        Rectangle {
            implicitWidth: 8
            implicitHeight: 8
            radius: 4
            color: root.tone
        }
        StyledText {
            text: root.app.pingText(root.ms)
            font: Tokens.font.mono.medium
            color: root.tone
        }
    }
}
