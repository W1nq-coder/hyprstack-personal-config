import QtQuick.Layouts
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.services

StyledRect {
    id: root

    readonly property bool ru: String(Tr.language || Qt.locale().name).startsWith("ru")
    function l(en: string, rus: string): string { return root.ru ? rus : en; }

    required property var dialog
    required property FolderContents folder

    implicitHeight: inner.implicitHeight + Tokens.padding.medium * 2

    color: Colours.tPalette.m3surfaceContainer

    RowLayout {
        id: inner

        anchors.fill: parent
        anchors.margins: Tokens.padding.medium

        spacing: Tokens.spacing.small

        StyledText {
            text: Tr.trCtx("Filter:", "file filter")
        }

        StyledRect {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.rightMargin: Tokens.spacing.medium

            color: Colours.tPalette.m3surfaceContainerHigh
            radius: Tokens.rounding.medium

            StyledText {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium

                text: {
                    const filters = root.dialog.filters.map(f => `*.${f}`).join(Tr.trCtx(", ", "file filter separator"));
                    // TRANSLATORS: %1 = filter label, %2 = file patterns
                    return Tr.trCtx("%1 (%2)", "file filter label and patterns").arg(root.dialog.filterLabel).arg(filters);
                }
            }
        }

        StyledRect {
            visible: root.dialog.folderMode
            color: Colours.palette.m3primaryContainer
            radius: Tokens.rounding.medium

            implicitWidth: folderText.implicitWidth + Tokens.padding.medium * 2
            implicitHeight: folderText.implicitHeight + Tokens.padding.medium * 2

            StateLayer {
                onClicked: root.dialog.folderAccepted(root.dialog.currentPath)
            }

            StyledText {
                id: folderText

                anchors.centerIn: parent
                anchors.margins: Tokens.padding.medium

                text: root.l("Use this folder", "Выбрать эту папку")
                color: Colours.palette.m3onPrimaryContainer
            }
        }

        StyledRect {
            color: Colours.tPalette.m3surfaceContainerHigh
            radius: Tokens.rounding.medium

            implicitWidth: cancelText.implicitWidth + Tokens.padding.medium * 2
            implicitHeight: cancelText.implicitHeight + Tokens.padding.medium * 2

            StateLayer {
                disabled: !root.dialog.selectionValid
                onClicked: root.dialog.accepted(root.folder.currentItem.modelData.path)
            }

            StyledText {
                id: selectText

                anchors.centerIn: parent
                anchors.margins: Tokens.padding.medium

                text: Tr.trCtx("Select", "button")
                color: root.dialog.selectionValid ? Colours.palette.m3onSurface : Colours.palette.m3outline
            }
        }

        StyledRect {
            color: Colours.tPalette.m3surfaceContainerHigh
            radius: Tokens.rounding.medium

            implicitWidth: cancelText.implicitWidth + Tokens.padding.medium * 2
            implicitHeight: cancelText.implicitHeight + Tokens.padding.medium * 2

            StateLayer {
                onClicked: {
                    root.dialog.rejected();
                }
            }

            StyledText {
                id: cancelText

                anchors.centerIn: parent
                anchors.margins: Tokens.padding.medium

                text: Tr.trCtx("Cancel", "button")
            }
        }
    }
}
