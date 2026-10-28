pragma ComponentBehavior: Bound

// Personal overlay (VPN app): "All servers" and one chip per subscription.
// A click shows only that subscription; refresh and remove buttons on each.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Hyprstack.Config
import qs.components
import qs.components.controls
import qs.services

Flow {
    id: root

    required property var app

    spacing: Tokens.spacing.small
    visible: app.groups.length > 0

    Chip {
        groupId: ""
        label: root.app.l("All", "Все")
        count: root.app.profiles.length
    }

    Repeater {
        model: root.app.groups

        Chip {
            required property var modelData
            groupId: modelData.id
            label: modelData.name
            count: modelData.count ?? 0
            subscription: modelData.subscription
        }
    }

    component Chip: StyledRect {
        id: chip

        required property string groupId
        required property string label
        required property int count
        property bool subscription: false
        readonly property bool active: root.app.groupFilter === groupId

        implicitWidth: chipRow.implicitWidth + Tokens.padding.large * 2
        implicitHeight: 38
        radius: Tokens.rounding.full
        color: active ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHigh

        StateLayer {
            radius: chip.radius
            color: chip.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
            onClicked: root.app.groupFilter = chip.groupId
        }

        RowLayout {
            id: chipRow

            anchors.centerIn: parent
            spacing: Tokens.spacing.small

            StyledText {
                text: chip.label
                color: chip.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
            }
            StyledText {
                text: chip.count
                font: Tokens.font.label.medium
                color: chip.active ? Qt.alpha(Colours.palette.m3onPrimary, 0.75) : Colours.palette.m3onSurfaceVariant
            }
            IconButton {
                visible: chip.groupId.length > 0 && chip.subscription
                type: IconButton.Text
                icon: "sync"
                disabled: root.app.working
                implicitWidth: 26
                implicitHeight: 26
                onClicked: root.app.updateGroup(chip.groupId)
                ToolTip.visible: hovered
                ToolTip.text: root.app.l("Update", "Обновить")
            }
            IconButton {
                visible: chip.groupId.length > 0
                type: IconButton.Text
                icon: "close"
                disabled: root.app.working
                implicitWidth: 26
                implicitHeight: 26
                onClicked: root.app.removeGroup(chip.groupId)
                ToolTip.visible: hovered
                ToolTip.text: root.app.l("Remove subscription", "Удалить подписку")
            }
        }
    }
}
