// Personal overlay: a colour palette — a square of saturation (left→right) and brightness (top→bottom),
// a strip of hues, a preview and the #rrggbb code. Emits picked("#rrggbb") while the colour is dragged.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Hyprstack.Config
import qs.components
import qs.components.controls
import qs.services

StyledRect {
    id: root

    property string colour: "#1e88e5"
    signal picked(string value)

    property real hue: 0.58
    property real sat: 0.9
    property real val: 0.9
    property bool dragging: false

    readonly property color current: Qt.hsva(hue, sat, val, 1)

    function hex(c: color): string {
        const h = n => Math.round(n * 255).toString(16).padStart(2, "0");
        return "#" + h(c.r) + h(c.g) + h(c.b);
    }

    function load(value: string): void {
        if (!/^#[0-9a-fA-F]{6}$/.test(value))
            return;
        const c = Qt.color(value);
        if (c.hsvSaturation > 0.001 && c.hsvValue > 0.001)
            hue = c.hsvHue;
        sat = c.hsvSaturation;
        val = c.hsvValue;
    }

    function emit(): void {
        picked(hex(current));
    }

    onColourChanged: {
        if (!dragging)
            load(colour);
    }
    Component.onCompleted: load(colour)

    implicitHeight: body.implicitHeight + 24
    radius: Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer

    ColumnLayout {
        id: body

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 12

        // saturation / brightness
        Item {
            id: field

            Layout.fillWidth: true
            Layout.preferredHeight: 190

            Rectangle {
                anchors.fill: parent
                radius: 12
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#ffffff" }
                    GradientStop { position: 1; color: Qt.hsva(root.hue, 1, 1, 1) }
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: 12
                gradient: Gradient {
                    GradientStop { position: 0; color: "#00000000" }
                    GradientStop { position: 1; color: "#000000" }
                }
            }

            Rectangle {
                x: root.sat * field.width - width / 2
                y: (1 - root.val) * field.height - height / 2
                width: 22
                height: 22
                radius: 11
                color: root.current
                border.width: 3
                border.color: "#ffffff"

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -1
                    radius: width / 2
                    color: "transparent"
                    border.width: 1
                    border.color: "#66000000"
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.CrossCursor
                function pick(mouse): void {
                    root.sat = Math.max(0, Math.min(1, mouse.x / width));
                    root.val = 1 - Math.max(0, Math.min(1, mouse.y / height));
                    root.emit();
                }
                onPressed: mouse => { root.dragging = true; pick(mouse); }
                onPositionChanged: mouse => { if (pressed) pick(mouse); }
                onReleased: root.dragging = false
                onCanceled: root.dragging = false
            }
        }

        // hue
        Item {
            id: strip

            Layout.fillWidth: true
            Layout.preferredHeight: 22

            Rectangle {
                anchors.fill: parent
                radius: 11
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0 / 6; color: Qt.hsva(0 / 6, 1, 1, 1) }
                    GradientStop { position: 1 / 6; color: Qt.hsva(1 / 6, 1, 1, 1) }
                    GradientStop { position: 2 / 6; color: Qt.hsva(2 / 6, 1, 1, 1) }
                    GradientStop { position: 3 / 6; color: Qt.hsva(3 / 6, 1, 1, 1) }
                    GradientStop { position: 4 / 6; color: Qt.hsva(4 / 6, 1, 1, 1) }
                    GradientStop { position: 5 / 6; color: Qt.hsva(5 / 6, 1, 1, 1) }
                    GradientStop { position: 6 / 6; color: Qt.hsva(0, 1, 1, 1) }
                }
            }

            Rectangle {
                x: root.hue * (strip.width - width)
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                height: 28
                radius: 11
                color: Qt.hsva(root.hue, 1, 1, 1)
                border.width: 3
                border.color: "#ffffff"
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                function pick(mouse): void {
                    root.hue = Math.max(0, Math.min(0.999, (mouse.x - 11) / (width - 22)));
                    root.emit();
                }
                onPressed: mouse => { root.dragging = true; pick(mouse); }
                onPositionChanged: mouse => { if (pressed) pick(mouse); }
                onReleased: root.dragging = false
                onCanceled: root.dragging = false
            }
        }

        // preview and code
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                radius: 22
                color: root.current
                border.width: 1
                border.color: Colours.palette.m3outlineVariant
            }

            StyledText {
                text: root.hex(root.current).toUpperCase()
                font: Tokens.font.body.large
            }

            Item { Layout.fillWidth: true }

            StyledTextField {
                id: code

                Layout.preferredWidth: 130
                placeholderText: "#1e88e5"
                maximumLength: 7
                validator: RegularExpressionValidator { regularExpression: /^#?[0-9a-fA-F]{0,6}$/ }
                onAccepted: {
                    const v = (text.startsWith("#") ? text : "#" + text).toLowerCase();
                    if (/^#[0-9a-f]{6}$/.test(v)) {
                        root.load(v);
                        root.emit();
                    }
                }
            }
        }
    }
}
