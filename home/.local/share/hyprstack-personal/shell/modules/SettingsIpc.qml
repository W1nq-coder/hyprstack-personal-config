pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.services
import qs.modules.nexus

// Personal overlay: `qs ipc call settings open <page> <subpage>` opens the
// settings window on a page (index in Settings' side list, from 0) and,
// unless subpage is -1, on one of its subpages (e.g. 4 2 = Panels → Taskbar).
Scope {
    id: root

    IpcHandler {
        target: "settings"

        function open(page: int, subpage: int): void {
            windowComp.createObject(root, {page, subpage});
        }
    }

    Component {
        id: windowComp

        FloatingWindow {
            id: win

            required property int page
            required property int subpage

            color: Colours.tPalette.m3surface
            surfaceFormat.opaque: false

            onVisibleChanged: {
                if (!visible)
                    destroy();
            }

            implicitWidth: nexus.implicitWidth
            implicitHeight: nexus.implicitHeight

            minimumSize.width: Math.min(contentItem.Tokens.sizes.nexus.minWidth, nexus.availableWidth)
            minimumSize.height: Math.min(contentItem.Tokens.sizes.nexus.minHeight, nexus.availableHeight)

            contentItem.Config.screen: screen.name
            contentItem.Tokens.screen: screen.name

            title: Tr.tr("Nexus — %1").arg(PageRegistry.pages[nexus.nState.currentPageIdx].label)

            Nexus {
                id: nexus

                anchors.fill: parent
                nState.screen: win.screen
                nState.isWindow: true
                onClose: win.destroy()
            }

            Component.onCompleted: {
                nexus.nState.currentPageIdx = Math.max(0, Math.min(win.page, PageRegistry.pages.length - 1));
                if (win.subpage >= 0)
                    Qt.callLater(() => nexus.nState.openSubPage(win.subpage));
            }
        }
    }
}
