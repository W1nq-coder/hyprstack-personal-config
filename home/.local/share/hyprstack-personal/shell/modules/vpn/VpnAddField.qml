// Personal overlay (VPN app): paste a subscription link or a key and add it.
import QtQuick
import QtQuick.Layouts
import Hyprstack.Config
import qs.components
import qs.components.controls
import qs.services

RowLayout {
    id: root

    required property var app
    property bool compact: false

    spacing: Tokens.spacing.small

    StyledTextField {
        id: input

        Layout.fillWidth: true
        enabled: !root.app.working
        placeholderText: root.compact ? root.app.l("Subscription link or key", "Ссылка подписки или ключ")
            : root.app.l("Paste a subscription link (https://…) or a key (vless://…), like in Happ",
                "Вставьте ссылку подписки (https://…) или ключ (vless://…), как в Happ")
        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
        onAccepted: root.app.addLink(text)
    }
    IconTextButton {
        icon: "add_link"
        text: root.compact ? "" : root.app.l("Add", "Добавить")
        disabled: root.app.working || input.text.trim().length === 0
        onClicked: root.app.addLink(input.text)
    }

    Connections {
        target: root.app
        function onLinkAdded(): void {
            input.text = "";
        }
    }
}
