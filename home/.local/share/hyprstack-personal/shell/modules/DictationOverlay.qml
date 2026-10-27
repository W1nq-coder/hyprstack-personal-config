pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Hyprstack.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.services

// Personal overlay: voice input indicator next to the taskbar (top in scrolling,
// bottom in stacking layout). State comes from services/Dictation.qml.
Variants {
    model: Quickshell.screens

    StyledWindow {
        id: win

        required property ShellScreen modelData
        readonly property bool onFocusedMonitor: Hypr.focusedMonitor?.name === modelData.name
        readonly property bool shown: Dictation.visible && onFocusedMonitor
        readonly property bool atBottom: Hypr.stacking

        screen: modelData
        name: "dictation"
        visible: shown || card.opacity > 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        // Встать рядом с панелью, уважая её зарезервированную область.
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        anchors.top: !atBottom
        anchors.bottom: atBottom
        margins.top: Tokens.padding.small
        margins.bottom: Tokens.padding.small
        implicitWidth: card.implicitWidth + shadowPad * 2
        implicitHeight: card.implicitHeight + shadowPad * 2
        mask: Region {}

        readonly property real shadowPad: Tokens.padding.large

        Elevation {
            anchors.fill: card
            radius: card.radius
            level: 2
            opacity: card.opacity
        }

        StyledRect {
            id: card

            readonly property color accent: Dictation.failed ? Colours.palette.m3error
                : Dictation.recording ? Colours.palette.m3error : Colours.palette.m3primary

            anchors.centerIn: parent
            implicitWidth: row.implicitWidth + Tokens.padding.large * 2
            implicitHeight: row.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.full
            color: Dictation.failed ? Colours.palette.m3errorContainer : Colours.tPalette.m3surfaceContainer
            border.width: 1
            border.color: Qt.alpha(accent, 0.35)
            opacity: win.shown ? 1 : 0
            scale: win.shown ? 1 : 0.9

            Behavior on opacity {
                Anim {}
            }
            Behavior on scale {
                Anim {}
            }
            Behavior on implicitWidth {
                Anim {}
            }

            Row {
                id: row

                anchors.centerIn: parent
                spacing: Tokens.spacing.medium

                // Красная пульсирующая точка во время записи.
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: Tokens.font.icon.small.pointSize * 1.4
                    implicitHeight: implicitWidth
                    visible: Dictation.recording

                    Rectangle {
                        id: halo

                        anchors.centerIn: parent
                        width: parent.width
                        height: width
                        radius: width / 2
                        color: Colours.palette.m3error
                        opacity: 0

                        SequentialAnimation on opacity {
                            running: Dictation.recording && win.visible
                            loops: Animation.Infinite
                            NumberAnimation { from: 0.45; to: 0; duration: 1100; easing.type: Easing.OutQuad }
                        }
                        SequentialAnimation on scale {
                            running: Dictation.recording && win.visible
                            loops: Animation.Infinite
                            NumberAnimation { from: 0.5; to: 1.25; duration: 1100; easing.type: Easing.OutQuad }
                        }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * 0.55
                        height: width
                        radius: width / 2
                        color: Colours.palette.m3error
                    }
                }

                LoadingIndicator {
                    anchors.verticalCenter: parent.verticalCenter
                    implicitSize: Math.round(Tokens.font.icon.small.pointSize * 1.6)
                    visible: Dictation.transcribing
                }

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Dictation.failed
                    text: "error"
                    color: Colours.palette.m3onErrorContainer
                    fill: 1
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Dictation.failed ? Dictation.message
                        : Dictation.transcribing ? "Распознаю…" : "🎙 Идёт запись…"
                    color: Dictation.failed ? Colours.palette.m3onErrorContainer : Colours.palette.m3onSurface
                    font: Tokens.font.body.medium
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Dictation.recording
                    text: Dictation.elapsedText
                    color: Colours.palette.m3error
                    font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
                }
            }
        }
    }
}
