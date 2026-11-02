// Personal overlay: the GNOME-style dock of the floating layout. With the "dock" view of the taskbar
// (services/TaskbarStyle.qml) the bar keeps everything except the windows, and the applications sit
// in a separate dock, centred on the screen edge opposite to the bar. Windows keep clear of it.

pragma ComponentBehavior: Bound

import "components"
import QtQuick
import Quickshell
import Quickshell.Wayland
import Hyprstack.Config
import qs.components
import qs.components.containers
import qs.services

Variants {
    model: Screens.screens

    StyledWindow {
        id: win

        required property ShellScreen modelData

        readonly property string edge: ({
                bottom: "top",
                top: "bottom",
                left: "right",
                right: "left"
            })[TaskbarStyle.stackingEdge] ?? "top"
        readonly property bool vertical: edge === "left" || edge === "right"
        readonly property real gap: 10 * Tokens.scale     // space between the dock and the screen edge

        screen: modelData
        name: "dock"
        visible: Hypr.stacking && TaskbarStyle.dock && icons.groups.length > 0
        // Anchored to one edge only: the compositor centres the dock along it.
        anchors.top: edge === "top"
        anchors.bottom: edge === "bottom"
        anchors.left: edge === "left"
        anchors.right: edge === "right"
        exclusionMode: ExclusionMode.Auto
        implicitWidth: panel.implicitWidth + (vertical ? gap * 2 : 0)
        implicitHeight: panel.implicitHeight + (vertical ? 0 : gap * 2)
        // Only the dock itself takes the mouse, the margin around it stays click-through.
        mask: Region {
            item: panel
        }

        StyledRect {
            id: panel

            anchors.centerIn: parent
            implicitWidth: icons.implicitWidth + Tokens.padding.small * 2
            implicitHeight: icons.implicitHeight + Tokens.padding.small * 2
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outline, 0.35)

            TaskIcons {
                id: icons

                anchors.centerIn: parent
                screen: win.modelData
                edge: win.edge
                dock: true
                maxLength: (win.vertical ? win.screen.height : win.screen.width) * 0.8
            }
        }
    }
}
