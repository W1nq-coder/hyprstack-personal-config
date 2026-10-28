// Personal overlay: the taskbar can sit on any screen edge (services/BarPosition.qml).
// Top and bottom use the usual bar; left and right use VerticalBar.qml.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Hyprstack.Config
import qs.components
import qs.utils
import qs.services
import qs.modules.bar.popouts as BarPopouts

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts
    required property bool fullscreen
    readonly property Item content: vertical ? vcontent : hbar

    readonly property bool disabled: Strings.testRegexList(Config.bar.excludedScreens, screen.name)

    // "top", "bottom", "left" or "right"; the stacking layout keeps its bottom taskbar
    readonly property string edge: BarPosition.activeEdge
    readonly property bool atBottom: edge === "bottom"
    readonly property bool vertical: edge === "left" || edge === "right"
    // 0 = top, 1 = bottom; follows the stacking switch so the bar slides between them
    readonly property real bottomProgress: BarPosition.edge === "bottom" && !vertical ? 1 : Hypr.stackingProgress
    // bar thickness across its edge (animated when it hides or shows)
    readonly property real thickness: vertical ? implicitWidth : implicitHeight
    readonly property var activeWorkspace: Hypr.monitorFor(screen)?.activeWorkspace
    readonly property int clampedThickness: Math.max((Config.border.minThickness * Tokens.scale), thickness)
    readonly property real frameThickness: (Tiling.desktopFrame ? (Config.border.thickness * Tokens.scale) : 0) * (1 - Hypr.stackingProgress)
    readonly property real sideFrame: fullscreen ? 0 : frameThickness
    readonly property real topInset: vertical ? sideFrame : thickness * (1 - bottomProgress) + sideFrame * bottomProgress
    readonly property real bottomInset: vertical ? sideFrame : thickness * bottomProgress + sideFrame * (1 - bottomProgress)
    readonly property real leftInset: edge === "left" ? thickness : sideFrame
    readonly property real rightInset: edge === "right" ? thickness : sideFrame
    readonly property int padding: Math.max(Tokens.padding.small, (Config.border.thickness * Tokens.scale))
    readonly property int contentWidth: Hypr.stacking ? 40 * Tokens.scale : Tokens.sizes.bar.innerWidth + padding * 2
    readonly property int exclusiveZone: !disabled && (Config.bar.persistent || screenState.bar) ? contentWidth : frameThickness
    readonly property bool shouldBeVisible: !fullscreen && !disabled && (Config.bar.persistent || screenState.bar || isHovered)
    property bool isHovered
    property bool popoutHoverPaused
    property point lastHoverPosition
    property point pausedHoverPosition

    function closeTray(): void {
        hbar.closeTray();
        vcontent.closeTray();
    }

    function checkPopout(x: real, y: real): void {
        lastHoverPosition = Qt.point(x, y);
        if (popoutHoverPaused && x === pausedHoverPosition.x && y === pausedHoverPosition.y)
            return;
        popoutHoverPaused = false;
        (vertical ? vcontent : hbar).checkPopout(vertical ? y : x);
    }

    function resumePopoutHover(): void {
        popoutHoverPaused = false;
    }

    function handleWheel(x: real, angleDelta: point, y: real): void {
        (vertical ? vcontent : hbar).handleWheel(vertical ? (y ?? 0) : x, angleDelta);
    }

    clip: true
    onActiveWorkspaceChanged: {
        popouts.close();
        pausedHoverPosition = lastHoverPosition;
        popoutHoverPaused = true;
    }
    onEdgeChanged: {
        popouts.close();
        screenState.dashboard = false;
        screenState.launcher = false;
    }

    // across-edge size: frame when hidden, contentWidth when shown (see states)
    property real shownThickness: fullscreen ? 0 : frameThickness

    visible: thickness > frameThickness
    implicitWidth: vertical ? shownThickness : (parent?.width ?? 0)
    implicitHeight: vertical ? (parent?.height ?? 0) : shownThickness
    // Slide the new bar in from its edge while the frame changes shape.
    x: edge === "right" ? (parent?.width ?? 0) - width : 0
    y: vertical ? 0 : BarPosition.edge === "bottom" ? (parent?.height ?? 0) - height
        : atBottom ? (parent?.height ?? 0) - height * Hypr.stackingProgress : -height * Hypr.stackingProgress

    states: State {
        name: "visible"
        when: root.shouldBeVisible

        PropertyChanges {
            root.shownThickness: root.contentWidth
        }
    }

    transitions: [
        Transition {
            from: ""
            to: "visible"

            Anim {
                target: root
                property: "shownThickness"
            }
        },
        Transition {
            from: "visible"
            to: ""

            Anim {
                target: root
                property: "shownThickness"
                type: Anim.Emphasized
            }
        }
    ]

    Bar {
        id: hbar

        anchors.left: parent.left
        anchors.right: parent.right
        height: root.contentWidth
        y: root.atBottom ? 0 : root.height - height

        visible: root.shouldBeVisible && !root.vertical
        opacity: BarPosition.edge === "bottom" ? 1 : root.atBottom ? Hypr.stackingProgress : 1 - Hypr.stackingProgress
        screen: root.screen
        screenState: root.screenState
        popouts: root.popouts // qmllint disable incompatible-type
        fullscreen: root.fullscreen
    }

    VerticalBar {
        id: vcontent

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.contentWidth
        x: root.edge === "left" ? root.width - width : 0

        visible: root.shouldBeVisible && root.vertical
        opacity: 1 - Hypr.stackingProgress
        screen: root.screen
        screenState: root.screenState
        popouts: root.popouts // qmllint disable incompatible-type
        fullscreen: root.fullscreen
    }
}
