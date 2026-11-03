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

        // Any edge (Settings → Panels → Taskbar → Appearance); "auto" = opposite to the bar.
        readonly property string edge: TaskbarStyle.dockActualEdge
        readonly property bool vertical: edge === "left" || edge === "right"
        readonly property string align: TaskbarStyle.dockAlign
        readonly property real gap: TaskbarStyle.dockGap * Tokens.scale     // space between the dock and the screen edge

        screen: modelData
        name: "dock"
        visible: Hypr.stacking && TaskbarStyle.dock && icons.groups.length > 0
        // Anchored to one edge (centred along it) or to a corner of it (start / end).
        anchors.top: edge === "top" || (vertical && align === "start")
        anchors.bottom: edge === "bottom" || (vertical && align === "end")
        anchors.left: edge === "left" || (!vertical && align === "start")
        anchors.right: edge === "right" || (!vertical && align === "end")
        exclusionMode: ExclusionMode.Auto
        implicitWidth: panel.implicitWidth + gap * 2
        implicitHeight: panel.implicitHeight + gap * 2
        // Only the dock itself takes the mouse, the margin around it stays click-through.
        mask: Region {
            item: panel
        }

        StyledRect {
            id: panel

            anchors.centerIn: parent
            implicitWidth: icons.implicitWidth + Tokens.padding.small * 2
            implicitHeight: icons.implicitHeight + Tokens.padding.small * 2
            radius: TaskbarStyle.dockRadius * Tokens.scale
            color: TaskbarStyle.tone(Colours.tPalette.m3surfaceContainer, TaskbarStyle.dockDim, TaskbarStyle.dockOpacity)
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
