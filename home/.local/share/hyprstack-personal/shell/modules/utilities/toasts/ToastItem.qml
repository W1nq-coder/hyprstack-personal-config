import QtQuick
import QtQuick.Layouts
import Hyprstack
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.effects
import qs.services

StyledRect {
    id: root

    // Personal overlay (security): messages carry names of devices, networks, VPN servers and tracks
    // that come from outside; a tag such as <img src="http://…"> must not make the shell fetch it.
    function safeMarkup(text: var): string {
        const keep = [];
        const hold = tag => "\u0001" + (keep.push(tag) - 1) + "\u0002";
        let s = String(text ?? "").replace(/[\u0001\u0002]/g, "");
        s = s.replace(/<(\/?)(b|i|u|s|br|p)\s*\/?>/gi, (m, c, t) => hold("<" + c + t.toLowerCase() + ">"));
        s = s.replace(/&(?!(?:amp|lt|gt|quot|apos|#\d+|#x[0-9a-f]+);)/gi, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        return s.replace(/\u0001(\d+)\u0002/g, (m, i) => keep[Number(i)]);
    }

    required property Toast modelData

    anchors.left: parent.left
    anchors.right: parent.right
    implicitHeight: layout.implicitHeight + Tokens.padding.large

    radius: Tokens.rounding.large
    color: {
        if (root.modelData.type === Toast.Success)
            return Colours.palette.m3successContainer;
        if (root.modelData.type === Toast.Warning)
            return Colours.palette.m3secondary;
        if (root.modelData.type === Toast.Error)
            return Colours.palette.m3errorContainer;
        return Colours.palette.m3surface;
    }

    border.width: 1
    border.color: {
        let colour = Colours.palette.m3outlineVariant;
        if (root.modelData.type === Toast.Success)
            colour = Colours.palette.m3success;
        if (root.modelData.type === Toast.Warning)
            colour = Colours.palette.m3secondaryContainer;
        if (root.modelData.type === Toast.Error)
            colour = Colours.palette.m3error;
        return Qt.alpha(colour, 0.3);
    }

    Elevation {
        anchors.fill: parent
        radius: parent.radius
        opacity: parent.opacity
        z: -1
        level: 3
    }

    RowLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.small
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        spacing: Tokens.spacing.medium

        StyledRect {
            radius: Tokens.rounding.large
            color: {
                if (root.modelData.type === Toast.Success)
                    return Colours.palette.m3success;
                if (root.modelData.type === Toast.Warning)
                    return Colours.palette.m3secondaryContainer;
                if (root.modelData.type === Toast.Error)
                    return Colours.palette.m3error;
                return Colours.palette.m3surfaceContainerHigh;
            }

            implicitWidth: implicitHeight
            implicitHeight: icon.implicitHeight + Tokens.padding.large

            MaterialIcon {
                id: icon

                anchors.centerIn: parent
                text: root.modelData.icon
                color: {
                    if (root.modelData.type === Toast.Success)
                        return Colours.palette.m3onSuccess;
                    if (root.modelData.type === Toast.Warning)
                        return Colours.palette.m3onSecondaryContainer;
                    if (root.modelData.type === Toast.Error)
                        return Colours.palette.m3onError;
                    return Colours.palette.m3onSurfaceVariant;
                }
                fontStyle: Tokens.font.icon.builders.large.scale(1.2).build()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                id: title

                Layout.fillWidth: true
                text: Tr.trMarked(root.modelData.title)
                color: {
                    if (root.modelData.type === Toast.Success)
                        return Colours.palette.m3onSuccessContainer;
                    if (root.modelData.type === Toast.Warning)
                        return Colours.palette.m3onSecondary;
                    if (root.modelData.type === Toast.Error)
                        return Colours.palette.m3onErrorContainer;
                    return Colours.palette.m3onSurface;
                }
                font: Tokens.font.title.small
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                textFormat: Text.StyledText
                text: root.safeMarkup(Tr.trMarked(root.modelData.message))
                color: {
                    if (root.modelData.type === Toast.Success)
                        return Colours.palette.m3onSuccessContainer;
                    if (root.modelData.type === Toast.Warning)
                        return Colours.palette.m3onSecondary;
                    if (root.modelData.type === Toast.Error)
                        return Colours.palette.m3onErrorContainer;
                    return Colours.palette.m3onSurface;
                }
                opacity: 0.8
                elide: Text.ElideRight
            }
        }
    }

    Behavior on border.color {
        CAnim {}
    }
}
