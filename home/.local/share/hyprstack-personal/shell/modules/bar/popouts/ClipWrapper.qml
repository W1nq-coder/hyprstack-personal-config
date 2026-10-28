// Personal overlay: with the taskbar on the left or right (`edge`), popouts
// slide out sideways next to it; currentCenter is then a y coordinate.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.modules.bar.popouts // Need to import this module so the Wrapper type is the same as others

Item {
    id: root

    required property ShellScreen screen
    required property real borderThickness
    required property bool atBottom
    property string edge: atBottom ? "bottom" : "top"
    // distance from the bar's start to this item's parent (along the bar)
    property real crossOffset: borderThickness
    readonly property bool vertical: edge === "left" || edge === "right"

    readonly property alias content: content
    readonly property bool hovered: hover.hovered
    property real offsetScale: content.isDetached || content.hasCurrent ? 0 : 1

    visible: width > 0 && height > 0
    clip: true

    HoverHandler { id: hover }

    implicitWidth: vertical && !content.isDetached ? Math.max(0, content.implicitWidth * (1 - offsetScale)) : content.implicitWidth
    implicitHeight: vertical && !content.isDetached ? content.implicitHeight : Math.max(0, content.implicitHeight * (1 - offsetScale))

    x: {
        if (content.isDetached)
            return (parent.width - width) / 2;
        if (vertical)
            return edge === "right" ? parent.width - width : 0;
        return Math.max(0, Math.min(content.currentCenter - crossOffset - content.nonAnimWidth / 2,
            parent.width - content.nonAnimWidth));
    }
    y: {
        if (content.isDetached)
            return (parent.height - height) / 2;
        if (vertical)
            return Math.max(0, Math.min(content.currentCenter - crossOffset - content.nonAnimHeight / 2,
                parent.height - content.nonAnimHeight));
        return atBottom ? parent.height - height : 0;
    }

    Behavior on offsetScale {
        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
    }

    Behavior on x {
        enabled: root.offsetScale === 0 && !content.isDetached && !root.vertical
        Anim {
            duration: content.animLength
            easing: content.animCurve
        }
    }

    Behavior on y {
        enabled: root.offsetScale === 0 && !content.isDetached && root.vertical
        Anim {
            duration: content.animLength
            easing: content.animCurve
        }
    }

    Wrapper {
        id: content

        screen: root.screen
        offsetScale: root.offsetScale

        anchors.horizontalCenter: root.vertical && !isDetached ? undefined : parent.horizontalCenter
        anchors.verticalCenter: root.vertical && !isDetached ? parent.verticalCenter : undefined
        x: root.edge === "right" ? root.width - width + (width + 5) * root.offsetScale
            : (-width - 5) * root.offsetScale
        y: root.atBottom ? root.height - height + (height + 5) * root.offsetScale
            : (-height - 5) * root.offsetScale
    }
}
