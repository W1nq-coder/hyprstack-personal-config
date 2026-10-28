pragma ComponentBehavior: Bound

// Personal overlay: cover shape (wavy, circle, rounded square, vinyl record),
// spinning while music plays and the audio bars are set in Settings → Media
// (services/MediaSettings.qml).

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import M3Shapes
import Hyprstack.Config
import Hyprstack.Services
import qs.components
import qs.components.effects
import qs.components.images
import qs.components.widgets
import qs.services

Item {
    id: root

    readonly property string kind: MediaSettings.coverShape
    readonly property bool vinyl: kind === "vinyl"
    readonly property real coverSize: Tokens.sizes.dashboard.mediaCoverArtSize
    readonly property real centerX: width / 2
    readonly property real centerY: height / 2
    readonly property real spacing: Tokens.spacing.medium
    readonly property real maxMagnitude: (implicitWidth - coverSize) / 2 - spacing
    readonly property bool spinning: MediaSettings.spin && root.visible && (Players.active?.isPlaying ?? false)

    // Outline used for the bars and as the mask of the cover image.
    MaterialShape {
        id: outline

        visible: false
        implicitSize: root.coverSize
        shape: root.kind === "circle" || root.vinyl ? MaterialShape.Circle
            : root.kind === "square" ? MaterialShape.Square
            : MaterialShape.Cookie9Sided
    }

    ServiceRef {
        service: root.visible && MediaSettings.visualiser ? Audio.cava : null
    }

    Shape {
        anchors.fill: parent
        visible: MediaSettings.visualiser
        asynchronous: true
        preferredRendererType: Shape.CurveRenderer
        data: bars.instances
    }

    Variants {
        id: bars

        model: MediaSettings.visualiser ? Array.from({
            length: GlobalConfig.services.visualiserBars
        }, (_, i) => i) : []

        ShapePath {
            id: bar

            required property int modelData
            readonly property real value: Math.max(1e-2, Math.min(1, Audio.cava.values[modelData]))

            readonly property real angle: modelData * 2 * Math.PI / GlobalConfig.services.visualiserBars
            readonly property real dist: shapeEdgeDist + value * root.maxMagnitude
            readonly property real shapeEdgeDist: {
                outline.shape; // update when the shape changes
                const sDist = outline.distanceAtAngle(modelData * 360 / GlobalConfig.services.visualiserBars + 90);
                return sDist + root.spacing + strokeWidth / 2;
            }
            readonly property real cos: Math.cos(angle)
            readonly property real sin: Math.sin(angle)

            asynchronous: true
            capStyle: root.Tokens.rounding.scale === 0 ? ShapePath.SquareCap : ShapePath.RoundCap
            strokeWidth: 360 / GlobalConfig.services.visualiserBars - root.Tokens.spacing.small / 4
            strokeColor: Colours.palette.m3primary

            startX: root.centerX + shapeEdgeDist * cos
            startY: root.centerY + shapeEdgeDist * sin

            PathLine {
                x: root.centerX + bar.dist * bar.cos
                y: root.centerY + bar.dist * bar.sin
            }

            Behavior on strokeColor {
                CAnim {}
            }
        }
    }

    // The cover (or the record); it turns as a whole while music plays.
    Item {
        id: disc

        anchors.centerIn: parent
        width: root.coverSize
        height: root.coverSize

        layer.enabled: Effects.uiShadowsEnabled
        layer.effect: MultiEffect {
            shadowEnabled: true
            blurMax: Math.max(1, Math.round(Effects.shadowSize * Tokens.scale))
            shadowColor: Colours.palette.m3shadow
            shadowOpacity: Effects.shadowOpacity
            shadowVerticalOffset: 2 * Tokens.scale
        }

        RotationAnimator on rotation {
            running: root.spinning
            from: disc.rotation
            to: disc.rotation + 360
            // a record turns faster than the slowly drifting cover
            duration: root.vinyl ? 8000 : 24000
            loops: Animation.Infinite
        }

        Connections {
            target: MediaSettings
            function onSpinChanged(): void {
                if (!MediaSettings.spin)
                    disc.rotation = 0;
            }
        }

        // Vinyl record: dark disc with grooves, the cover is the label in the middle.
        Item {
            anchors.fill: parent
            visible: root.vinyl

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "#141414"
                border.width: 1
                border.color: "#2a2a2a"
            }

            Repeater {
                model: 7

                Rectangle {
                    required property int index
                    readonly property real size: root.coverSize * (0.94 - index * 0.06)

                    anchors.centerIn: parent
                    width: size
                    height: size
                    radius: size / 2
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, index % 2 ? 0.05 : 0.09)
                }
            }

            // light reflection, so the turning is visible
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                opacity: 0.12
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.45; color: "white" }
                    GradientStop { position: 0.55; color: "transparent" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
        }

        Item {
            id: art

            readonly property real size: root.vinyl ? root.coverSize * 0.46 : root.coverSize

            anchors.centerIn: parent
            width: size
            height: size

            Item {
                id: maskShape

                anchors.fill: parent
                layer.enabled: true
                visible: false

                MaterialShape {
                    implicitSize: art.size
                    shape: outline.shape
                    color: "white"
                }
            }

            MaterialShape {
                implicitSize: art.size
                shape: outline.shape
                color: Colours.layer(Colours.palette.m3surfaceContainerHighest, 2)
            }

            MaterialIcon {
                anchors.centerIn: parent
                grade: 200
                text: image.status === Image.Error ? "broken_image" : "art_track"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.size((art.size * 0.35) || 1).build()
                visible: image.status === Image.Null || image.status === Image.Error
            }

            FadeImage {
                id: image

                anchors.fill: parent
                source: Players.getArtUrl(Players.active)

                layer.enabled: true
                layer.effect: Mask {
                    maskSource: maskShape
                }
            }

            // spindle hole of the record
            Rectangle {
                visible: root.vinyl
                anchors.centerIn: parent
                width: art.size * 0.1
                height: width
                radius: width / 2
                color: "#141414"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.15)
            }
        }
    }
}
