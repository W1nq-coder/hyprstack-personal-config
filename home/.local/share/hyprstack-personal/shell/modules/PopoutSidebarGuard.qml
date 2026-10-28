pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// Personal overlay: bar popouts (tray menus, volume, etc.) and the notification
// centre open in the same corner and used to overlap. Only one of them stays open:
// opening a popout closes the notification centre and vice versa.
Variants {
    model: Screens.screens

    Scope {
        id: scope

        required property ShellScreen modelData
        readonly property var screenState: ShellState.forScreen(modelData)
        readonly property var popouts: ShellState.componentsFor(modelData)?.panels?.popouts ?? null

        Connections {
            target: scope.popouts
            ignoreUnknownSignals: true

            function onHasCurrentChanged(): void {
                if (scope.popouts.hasCurrent && scope.screenState?.sidebar)
                    scope.screenState.sidebar = false;
            }
        }

        Connections {
            target: scope.screenState
            ignoreUnknownSignals: true

            function onSidebarChanged(): void {
                if (scope.screenState.sidebar && scope.popouts?.hasCurrent)
                    scope.popouts.close();
            }
        }
    }
}
