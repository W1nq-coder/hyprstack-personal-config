import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Personal overlay: `qs ipc call dashboard openTab 1` opens the dashboard on a tab
// (0 dashboard, 1 media, 2 performance, 3 weather) on the focused screen.
IpcHandler {
    target: "dashboard"

    function openTab(index: int): void {
        const state = ShellState.forActive();
        if (!state)
            return;
        state.dashboardTab = index;
        state.dashboard = true;
    }

    function close(): void {
        const state = ShellState.forActive();
        if (state)
            state.dashboard = false;
    }
}
