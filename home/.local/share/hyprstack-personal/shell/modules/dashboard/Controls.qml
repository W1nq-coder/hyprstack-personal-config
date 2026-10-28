// Personal overlay: the "Controls" dashboard tab. The cards of the corner
// utilities panel (quick toggles, keep awake, screen recording) live here, so
// everything opens from one dashboard; the corner panel is switched off in
// Settings → Panels → Utilities.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Hyprstack.Config
import qs.components
import qs.modules.utilities as Utilities
import qs.modules.utilities.cards as Cards

Item {
    id: root

    required property ScreenState screenState

    readonly property PersistentProperties props: PersistentProperties {
        property bool recordingListExpanded: false
        property string recordingConfirmDelete
        property string recordingMode

        reloadableId: "dashboardControls"
    }

    implicitWidth: Math.round(Tokens.sizes.utilities.width * 1.5)
    implicitHeight: layout.implicitHeight

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Tokens.spacing.medium

        Cards.Toggles {
            Layout.fillWidth: true
            screenState: root.screenState
            popouts: null
        }

        Cards.IdleInhibit {
            Layout.fillWidth: true
        }

        Cards.Record {
            Layout.fillWidth: true
            z: 1
            props: root.props
            screenState: root.screenState
        }
    }

    Utilities.RecordingDeleteModal {
        props: root.props
        deformMatrix: Qt.matrix4x4()
    }
}
