// Personal overlay: the card shown beside the taskbar while it is being edited in place
// (right click on the bar -> "Customize taskbar"). Elements are dragged on the bar itself
// (modules/bar/BarWrapper.qml); this card holds the hidden elements, "Reset" and "Done".

import QtQuick
import QtQuick.Layouts
import Hyprstack.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.bar as Bar

StyledRect {
    id: root

    required property Bar.BarWrapper bar
    required property real areaWidth
    required property real areaHeight

    readonly property real gap: 16

    visible: TaskbarStyle.editing && Hypr.stacking && !bar.fullscreen
    z: 500
    implicitWidth: 460
    implicitHeight: column.implicitHeight + 28
    radius: Tokens.rounding.large
    color: Colours.palette.m3surfaceContainer
    border.width: 1
    border.color: Colours.palette.m3outlineVariant

    x: bar.edge === "left" ? bar.width + gap : bar.edge === "right" ? areaWidth - bar.width - width - gap : (areaWidth - width) / 2
    y: bar.edge === "top" ? bar.height + gap : bar.edge === "bottom" ? areaHeight - bar.height - height - gap : (areaHeight - height) / 2

    ColumnLayout {
        id: column

        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        StyledText {
            Layout.fillWidth: true
            text: TaskbarStyle.l("Customize taskbar", "Настройка панели")
            font: Tokens.font.title.small
        }

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            text: root.bar.dragMoved && root.bar.dragOutside
                ? TaskbarStyle.l("Release to hide the element", "Отпустите, чтобы скрыть элемент")
                : TaskbarStyle.l("Drag elements along the bar. Drag one off the bar to hide it.", "Перетаскивайте элементы по панели. Вытащите элемент за панель, чтобы скрыть его.")
        }

        StyledText {
            visible: TaskbarStyle.hidden.length > 0
            text: TaskbarStyle.l("Hidden (click to return):", "Скрытые (нажмите, чтобы вернуть):")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
        }

        Flow {
            Layout.fillWidth: true
            visible: TaskbarStyle.hidden.length > 0
            spacing: 6

            Repeater {
                model: TaskbarStyle.hidden

                StyledRect {
                    id: chip

                    required property string modelData

                    implicitWidth: chipRow.implicitWidth + 20
                    implicitHeight: 32
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3secondaryContainer

                    StateLayer {
                        radius: chip.radius
                        onClicked: TaskbarStyle.moveElement(chip.modelData, chip.modelData === "tasks" ? "center" : "right", null)
                    }

                    Row {
                        id: chipRow

                        anchors.centerIn: parent
                        spacing: 6

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: TaskbarStyle.iconOf(chip.modelData)
                            color: Colours.palette.m3onSecondaryContainer
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: TaskbarStyle.label(chip.modelData)
                            color: Colours.palette.m3onSecondaryContainer
                            font: Tokens.font.body.small
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Item {
                Layout.fillWidth: true
            }

            Btn {
                text: TaskbarStyle.l("Reset", "Сбросить")
                onClicked: TaskbarStyle.resetLayout()
            }

            Btn {
                text: TaskbarStyle.l("Done", "Готово")
                primary: true
                onClicked: TaskbarStyle.stopEditing()
            }
        }
    }

    component Btn: StyledRect {
        id: btn

        property string text
        property bool primary
        signal clicked

        implicitWidth: label.implicitWidth + 32
        implicitHeight: 36
        radius: Tokens.rounding.full
        color: primary ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHigh

        StateLayer {
            radius: btn.radius
            onClicked: btn.clicked()
        }

        StyledText {
            id: label

            anchors.centerIn: parent
            text: btn.text
            color: btn.primary ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
            font: Tokens.font.body.medium
        }
    }
}
