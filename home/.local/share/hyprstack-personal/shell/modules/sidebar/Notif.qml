pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils

StyledRect {
    id: root

    // Personal overlay (security): text from other programs (notification bodies, device and track
    // names, VPN names) may contain <img src="http://…"> or ![](http://…): Qt would fetch that address
    // when showing it, so anyone who can send you a message could make this computer open a connection.
    // Only plain simple tags stay; everything else is shown as text.
    function safeMarkup(text: var): string {
        const keep = [];
        const hold = tag => "\u0001" + (keep.push(tag) - 1) + "\u0002";
        let s = String(text ?? "").replace(/[\u0001\u0002]/g, "");
        s = s.replace(/<(\/?)(b|i|u|s|br|p)\s*\/?>/gi, (m, c, t) => hold("<" + c + t.toLowerCase() + ">"));
        s = s.replace(/<a\s+href\s*=\s*(["'])(https?:\/\/[^"'<>\s]*)\1\s*>/gi, (m, q, url) => hold('<a href="' + url + '">'));
        s = s.replace(/<\/a\s*>/gi, () => hold("</a>"));
        s = s.replace(/&(?!(?:amp|lt|gt|quot|apos|#\d+|#x[0-9a-f]+);)/gi, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        return s.replace(/\u0001(\d+)\u0002/g, (m, i) => keep[Number(i)]);
    }

    function safeMarkdown(text: var): string {
        return String(text ?? "").replace(/!\[[^\]]*\]\([^)]*\)/g, "").replace(/!\[[^\]]*\]\[[^\]]*\]/g, "");
    }

    function safeLink(link: string): bool {
        return /^(https?:|mailto:)/i.test(link);
    }

    // Notification pictures: only local files and the shell's own image providers, never http(s) addresses.
    function safeImage(value: var): string {
        const v = String(value ?? "");
        return v.startsWith("/") || v.startsWith("file:") || v.startsWith("image:") ? Paths.fileUrl(v) : "";
    }

    required property NotifData modelData
    required property Props props
    required property bool expanded
    required property ScreenState screenState

    readonly property StyledText body: bodyText
    readonly property real nonAnimHeight: content.implicitHeight + Tokens.padding.medium * 2

    implicitHeight: nonAnimHeight
    radius: Tokens.rounding.medium
    color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

    ColumnLayout {
        id: content

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.medium
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall

            Rectangle {
                visible: !(root.modelData?.read ?? true)
                width: 5 * Tokens.scale
                height: 5 * Tokens.scale
                radius: 3 * Tokens.scale
                color: Colours.palette.m3primary
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: summary.implicitHeight

                StateLayer {
                    onClicked: {
                        if (root.modelData?.activate())
                            root.screenState.sidebar = false;
                        else {
                            const app = root.modelData?.appName;
                            if (root.props.expandedNotifs.includes(app))
                                root.props.expandedNotifs.splice(root.props.expandedNotifs.indexOf(app), 1);
                            else
                                root.props.expandedNotifs.push(app);
                        }
                    }
                }
                StyledText {
                    id: summary
                    anchors.fill: parent
                    text: root.modelData?.summary ?? ""
                    textFormat: Text.PlainText
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    maximumLineCount: root.expanded ? 5 : 2
                    elide: Text.ElideRight
                }
            }

            IconButton {
                objectName: "dismissNotification_" + (root.modelData?.historyId ?? "")
                icon: "close"
                type: IconButton.Text
                padding: 2 * Tokens.scale
                onClicked: root.modelData?.close()
                Accessible.name: Tr.tr("Dismiss notification")
            }
        }

        StyledText {
            id: bodyText

            Layout.fillWidth: true
            visible: text.length > 0
            text: root.safeMarkup(root.modelData?.body)
            textFormat: Text.RichText
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            maximumLineCount: root.expanded ? Number.MAX_SAFE_INTEGER : 2
            elide: Text.ElideRight
            onLinkActivated: link => {
                if (root.safeLink(link))
                    Qt.openUrlExternally(link);
                root.screenState.sidebar = false;
            }
        }

        Item {
            Layout.fillWidth: true
            visible: root.modelData?.screenshot ?? false
            implicitHeight: Math.min(180, width * .625)

            Rectangle {
                anchors.fill: parent
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerLowest
            }
            Image {
                id: screenshot
                objectName: "notificationScreenshot_" + (root.modelData?.historyId ?? "")
                anchors.fill: parent
                anchors.margins: 2 * Tokens.scale
                source: root.safeImage(root.modelData?.image)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                sourceSize.width: 800
            }
            MaterialIcon {
                anchors.centerIn: parent
                visible: screenshot.status === Image.Error
                text: "broken_image"
                color: Colours.palette.m3onSurfaceVariant
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.modelData?.imageAction("open")
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignRight
            text: root.modelData?.timeStr ?? ""
            color: Colours.palette.m3outline
            font: Tokens.font.label.small
        }

        NotifActionList {
            // Personal overlay: notifications with their own buttons (e.g. "Update" / "Cancel") keep them visible in the centre, even in a collapsed group.
            visible: root.expanded || (root.modelData?.screenshot ?? false) || (root.modelData?.actions?.length ?? 0) > 0
            notif: root.modelData
        }
    }

    Behavior on implicitHeight { Anim {} }
}
