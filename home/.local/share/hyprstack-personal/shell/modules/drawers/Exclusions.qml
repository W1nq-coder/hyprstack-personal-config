// Personal overlay: windows make room for the taskbar on any edge.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Hyprstack.Config
import qs.components.containers
import qs.modules.bar as Bar
import qs.services

Scope {
    id: root

    required property ShellScreen screen
    required property Bar.BarWrapper bar
    readonly property real frameThickness: Hypr.stacking || !Tiling.desktopFrame ? 0 : (root.bar.Config.border.thickness * root.bar.Tokens.scale)

    ExclusionZone {
        anchors.left: true
        exclusiveZone: root.bar.edge === "left" ? root.bar.exclusiveZone : root.frameThickness
    }

    ExclusionZone {
        anchors.top: true
        exclusiveZone: root.bar.edge === "top" ? root.bar.exclusiveZone : root.frameThickness
    }

    ExclusionZone {
        anchors.right: true
        exclusiveZone: root.bar.edge === "right" ? root.bar.exclusiveZone : root.frameThickness
    }

    ExclusionZone {
        anchors.bottom: true
        exclusiveZone: root.bar.edge === "bottom" ? root.bar.exclusiveZone : root.frameThickness
    }

    component ExclusionZone: StyledWindow {
        screen: root.screen
        name: "border-exclusion"
        exclusiveZone: root.frameThickness
        mask: Region {}
        implicitWidth: 1
        implicitHeight: 1
    }
}
