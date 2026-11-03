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
    // 0 = top, 1 = bottom; follows the stacking switch so the bar slides between the edges of the
    // tiling and the floating layout (each has its own edge, see services/TaskbarStyle.qml)
    readonly property real tileBottom: BarPosition.edge === "bottom" ? 1 : 0
    readonly property real stackBottom: TaskbarStyle.stackingEdge === "bottom" ? 1 : 0
    readonly property real bottomProgress: tileBottom + (stackBottom - tileBottom) * Hypr.stackingProgress
    // both layouts keep the bar on the same edge: no fading needed
    readonly property bool sameEdge: BarPosition.edge === TaskbarStyle.stackingEdge
    readonly property real fade: sameEdge ? 1 : (Hypr.stacking ? Hypr.stackingProgress : 1 - Hypr.stackingProgress)
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
    readonly property int contentWidth: Hypr.stacking && !vertical ? Math.round(40 * Tokens.scale * TaskbarStyle.barScale / 100) : Tokens.sizes.bar.innerWidth + padding * 2
    readonly property int exclusiveZone: !disabled && (Config.bar.persistent || screenState.bar) ? contentWidth : frameThickness
    readonly property bool editing: TaskbarStyle.editing && Hypr.stacking
    readonly property bool shouldBeVisible: !fullscreen && !disabled && (Config.bar.persistent || screenState.bar || isHovered || editing)

    // ---- editing in place: drag the elements of the bar (floating layout) ----
    property string dragId: ""
    property Item dragItem: null
    property bool dragMoved: false
    property bool dragOutside: false
    property point dragPoint
    property string dropZone: ""
    property var dropBefore: null
    property real dropMark: -1
    property bool isHovered
    property bool popoutHoverPaused
    property point lastHoverPosition
    property point pausedHoverPosition

    function closeTray(): void {
        hbar.closeTray();
        vcontent.closeTray();
    }

    function openMenu(x: real, y: real): void {
        contextMenu.openAt(x, y);
    }

    // Element under the pointer: {id, item} or null
    function editHit(x: real, y: real): var {
        const pos = vertical ? y : x;
        const inside = item => {
            const p = item.mapToItem(root, 0, 0);
            const a = vertical ? p.y : p.x;
            return pos >= a && pos < a + (vertical ? item.height : item.width);
        };
        for (const item of content.entryItems) {
            if (["spacer", "activeWindow", "workspaces"].includes(item.entryId) || !TaskbarStyle.catalog.includes(item.entryId))
                continue;
            if (inside(item))
                return {id: item.entryId, item: item};
        }
        const tasks = content.centredTasksItem;
        if (tasks && inside(tasks))
            return {id: "tasks", item: tasks};
        return null;
    }

    // Zone, the element to put the dragged one in front of, and where the marker goes
    function updateDrop(x: real, y: real): void {
        const pos = vertical ? y : x;
        const axis = item => {
            const p = item.mapToItem(root, 0, 0);
            return vertical ? p.y : p.x;
        };
        const size = item => vertical ? item.height : item.width;
        const items = content.entryItems;
        const spacers = items.filter(i => i.entryId === "spacer");
        const c1 = spacers.length > 0 ? axis(spacers[0]) + size(spacers[0]) / 2 : Infinity;
        const c2 = spacers.length > 1 ? axis(spacers[1]) + size(spacers[1]) / 2 : Infinity;
        const zone = pos < c1 ? "left" : pos < c2 ? "center" : "right";
        const inZone = [];
        let z = 0;
        for (const item of items) {
            if (item.entryId === "spacer") {
                z++;
                continue;
            }
            if (!TaskbarStyle.catalog.includes(item.entryId) || item.entryId === dragId)
                continue;
            if ((z === 0 ? "left" : z === 1 ? "center" : "right") === zone)
                inZone.push(item);
        }
        let index = 0;
        while (index < inZone.length && axis(inZone[index]) + size(inZone[index]) / 2 < pos)
            index++;
        dropZone = zone;
        dropBefore = index < inZone.length ? inZone[index].entryId : null;
        if (index < inZone.length)
            dropMark = axis(inZone[index]) - 4;
        else if (inZone.length > 0)
            dropMark = axis(inZone[index - 1]) + size(inZone[index - 1]) + 2;
        else
            dropMark = pos;
    }

    function endDrag(): void {
        if (dragItem)
            dragItem.opacity = 1;
        if (dragId && dragMoved) {
            if (dragOutside)
                TaskbarStyle.moveElement(dragId, "hidden", null);
            else if (dropZone)
                TaskbarStyle.moveElement(dragId, dropZone, dropBefore);
        }
        dragId = "";
        dragItem = null;
        dragMoved = false;
        dragOutside = false;
        dropZone = "";
    }

    onEditingChanged: {
        if (!editing)
            endDrag();
        else
            popouts.close();
    }

    function checkPopout(x: real, y: real): void {
        if (editing) {
            popouts.hasCurrent = false;
            return;
        }
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
    y: vertical ? 0 : atBottom ? (parent?.height ?? 0) - height * (BarPosition.edge === "bottom" ? 1 : Hypr.stackingProgress)
        : -height * (BarPosition.edge === "top" ? 0 : 1 - Hypr.stackingProgress)

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
        opacity: root.fade
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
        opacity: root.fade
        screen: root.screen
        screenState: root.screenState
        popouts: root.popouts // qmllint disable incompatible-type
        fullscreen: root.fullscreen
    }

    BarContextMenu {
        id: contextMenu

        target: root
    }

    // Edit mode: the bar itself only takes drags, its buttons do nothing until "Done".
    Rectangle {
        anchors.fill: parent
        visible: root.editing
        z: 998
        color: Qt.alpha(Colours.palette.m3primary, 0.08)
        border.width: 2
        border.color: Colours.palette.m3primary
    }

    Rectangle {
        visible: root.editing && root.dragMoved && !root.dragOutside && root.dropMark >= 0
        z: 1000
        x: root.vertical ? 4 : root.dropMark - 1
        y: root.vertical ? root.dropMark - 1 : 4
        width: root.vertical ? root.width - 8 : 3
        height: root.vertical ? 3 : root.height - 8
        radius: 2
        color: Colours.palette.m3primary
    }

    StyledRect {
        visible: root.editing && root.dragMoved
        z: 1001
        x: root.dragPoint.x - width / 2
        y: root.dragPoint.y - height / 2
        implicitWidth: ghostText.implicitWidth + 20
        implicitHeight: ghostText.implicitHeight + 10
        radius: Tokens.rounding.full
        color: root.dragOutside ? Colours.palette.m3errorContainer : Colours.palette.m3primaryContainer

        StyledText {
            id: ghostText

            anchors.centerIn: parent
            text: root.dragOutside ? TaskbarStyle.l("Hide: ", "Скрыть: ") + TaskbarStyle.label(root.dragId) : TaskbarStyle.label(root.dragId)
            color: root.dragOutside ? Colours.palette.m3onErrorContainer : Colours.palette.m3onPrimaryContainer
            font: Tokens.font.body.small
        }
    }

    MouseArea {
        id: editArea

        anchors.fill: parent
        visible: root.editing
        z: 999
        hoverEnabled: true
        preventStealing: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: root.dragMoved ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        onPressed: event => {
            if (event.button !== Qt.LeftButton)
                return;
            const hit = root.editHit(event.x, event.y);
            if (!hit)
                return;
            root.dragId = hit.id;
            root.dragItem = hit.item;
            root.dragPoint = Qt.point(event.x, event.y);
            root.dragMoved = false;
        }
        onPositionChanged: event => {
            if (!root.dragId)
                return;
            root.dragPoint = Qt.point(event.x, event.y);
            const start = root.dragItem ? root.dragItem.mapToItem(root, root.dragItem.width / 2, root.dragItem.height / 2) : root.dragPoint;
            if (!root.dragMoved && Math.hypot(event.x - start.x, event.y - start.y) < 8)
                return;
            if (!root.dragMoved) {
                root.dragMoved = true;
                if (root.dragItem)
                    root.dragItem.opacity = 0.35;
            }
            root.dragOutside = root.vertical ? (event.x < -24 || event.x > root.width + 24) : (event.y < -24 || event.y > root.height + 24);
            root.updateDrop(event.x, event.y);
        }
        onReleased: root.endDrag()
        onCanceled: root.endDrag()
    }
}
