// Personal overlay: a picture of a distribution logo for the taskbar. Colours follow
// Settings → Panels → Taskbar → Logo: the original colours, the theme colour or a colour of choice.

import QtQuick
import Quickshell.Widgets
import qs.components.effects
import qs.services

Item {
    id: root

    required property url source
    property int size: 24
    property string logoId: ""      // id in the catalogue ("" = the system logo, shown as it is)

    readonly property string colourMode: TaskbarStyle.logoColour
    readonly property string brand: logoId !== "" ? TaskbarStyle.brandColour(logoId) : ""

    implicitWidth: size
    implicitHeight: size

    Loader {
        anchors.fill: parent
        sourceComponent: root.colourMode === "original" && root.brand === "" ? plain : tinted
    }

    Component {
        id: plain

        IconImage {
            source: root.source
            implicitSize: root.size
            asynchronous: true
        }
    }

    Component {
        id: tinted

        ColouredIcon {
            source: root.source
            implicitSize: root.size
            colour: root.colourMode === "original" ? root.brand : root.colourMode === "theme" ? Colours.palette.m3tertiary : root.colourMode
        }
    }
}
