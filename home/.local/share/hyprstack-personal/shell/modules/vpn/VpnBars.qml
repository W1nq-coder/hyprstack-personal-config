// Personal overlay (VPN app): ping as three signal bars and the number.
import QtQuick
import QtQuick.Layouts
import Hyprstack.Config
import qs.components
import qs.services

RowLayout {
    id: root

    required property var app
    property int ms: -1
    readonly property int bars: app.pingBars(ms)
    readonly property color tone: app.pingColour(ms)

    spacing: Tokens.spacing.small

    Row {
        Layout.alignment: Qt.AlignVCenter
        spacing: 2

        Repeater {
            model: 3

            Rectangle {
                required property int index

                // bottom-aligned bars of growing height
                y: 16 - height
                width: 4
                height: 6 + index * 5
                radius: 2
                color: index < root.bars ? root.tone : Qt.alpha(Colours.palette.m3outline, 0.35)
            }
        }
    }
    StyledText {
        Layout.preferredWidth: 78
        horizontalAlignment: Text.AlignRight
        text: root.app.pingText(root.ms)
        font: Tokens.font.mono.medium
        color: root.tone
    }
}
