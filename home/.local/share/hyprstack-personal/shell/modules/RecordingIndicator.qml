pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Hyprstack.Config
import qs.components
import qs.components.containers
import qs.components.effects
import qs.services

// Personal overlay: small "screen recording" pill at the bottom of every screen
// while a recording is running (services/Recorder.qml, also for recordings
// started with `hyprstack record`). Click it to stop the recording.
Variants {
    model: Quickshell.screens

    StyledWindow {
        id: win

        required property ShellScreen modelData
        readonly property bool shown: Recorder.running

        screen: modelData
        name: "recording-indicator"
        visible: shown || card.opacity > 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        // Sit above the taskbar when it is at the bottom.
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        anchors.bottom: true
        margins.bottom: Tokens.padding.small
        implicitWidth: card.implicitWidth + shadowPad * 2
        implicitHeight: card.implicitHeight + shadowPad * 2
        // Only the pill takes clicks, the rest of the window lets them through.
        mask: Region {
            item: card
        }

        readonly property real shadowPad: Tokens.padding.large

        function elapsedText(): string {
            const elapsed = Recorder.elapsed;
            const hours = Math.floor(elapsed / 3600);
            const mins = Math.floor((elapsed % 3600) / 60);
            const secs = Math.floor(elapsed % 60).toString().padStart(2, "0");
            return hours > 0 ? `${hours}:${mins.toString().padStart(2, "0")}:${secs}` : `${mins}:${secs}`;
        }

        Elevation {
            anchors.fill: card
            radius: card.radius
            level: 2
            opacity: card.opacity
        }

        StyledRect {
            id: card

            readonly property color accent: Recorder.paused ? Colours.palette.m3tertiary : Colours.palette.m3error

            anchors.centerIn: parent
            implicitWidth: row.implicitWidth + Tokens.padding.medium * 2
            implicitHeight: row.implicitHeight + Tokens.padding.small * 2
            radius: Tokens.rounding.full
            color: mouse.containsMouse ? Colours.palette.m3errorContainer : Colours.tPalette.m3surfaceContainer
            border.width: 1
            border.color: Qt.alpha(accent, 0.4)
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

            MouseArea {
                id: mouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Recorder.stop()
            }

            Row {
                id: row

                anchors.centerIn: parent
                spacing: Tokens.spacing.small

                // Blinking dot while recording, pause icon while paused.
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: Tokens.font.icon.small.pointSize * 1.2
                    implicitHeight: implicitWidth

                    Rectangle {
                        anchors.centerIn: parent
                        visible: !Recorder.paused && !mouse.containsMouse
                        width: parent.width * 0.6
                        height: width
                        radius: width / 2
                        color: Colours.palette.m3error

                        SequentialAnimation on opacity {
                            running: Recorder.running && !Recorder.paused && win.visible
                            loops: Animation.Infinite
                            alwaysRunToEnd: true
                            NumberAnimation { from: 1; to: 0.25; duration: 700; easing.type: Easing.InOutQuad }
                            NumberAnimation { from: 0.25; to: 1; duration: 700; easing.type: Easing.InOutQuad }
                        }
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        visible: Recorder.paused || mouse.containsMouse
                        text: mouse.containsMouse ? "stop" : "pause"
                        color: mouse.containsMouse ? Colours.palette.m3onErrorContainer : Colours.palette.m3tertiary
                        fill: 1
                    }
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: mouse.containsMouse ? "Остановить запись"
                        : Recorder.paused ? "Пауза · " + win.elapsedText() : "Запись · " + win.elapsedText()
                    color: mouse.containsMouse ? Colours.palette.m3onErrorContainer : Colours.palette.m3onSurface
                    font: Tokens.font.body.small
                }
            }
        }
    }
}
