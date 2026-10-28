//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
//@ pragma DefaultEnv QS_DROP_EXPENSIVE_FONTS=1
//@ pragma DefaultEnv QSG_RENDER_LOOP=threaded
//@ pragma DefaultEnv QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
//@ pragma IconTheme Adwaita

import "modules"
import "modules/drawers"
import "modules/background"
import "modules/areapicker"
import "modules/lock"
import "modules/overview" as OverviewModule
import "modules/switcher" as SwitcherModule
import "modules/polkit" as PolkitModule
import QtQuick
import Quickshell
import Hyprstack
import qs.services

ShellRoot {
    id: root

    settings.watchFiles: false

    Component.onCompleted: AnimationClock.activate()

    Binding {
        target: ShellState
        property: "shellRoot"
        value: root
    }

    GSFLoader {}
    ServiceLoader {}
    PolkitModule.Polkit {}

    Background {}
    Drawers {}
    AreaPicker {}
    Lock {
        id: lock
    }

    Shortcuts {}
    OverviewModule.OverviewWindows {}
    SwitcherModule.WindowSwitcher {}
    DictationOverlay {} // voice input indicator (personal overlay)
    RecordingIndicator {} // screen recording indicator (personal overlay)
    PopoutSidebarGuard {} // tray menus and notification centre never overlap (personal overlay)
    DashboardIpc {} // open the dashboard on a given tab (personal overlay)
    BatteryMonitor {}
    IdleMonitors {
        lock: lock
    }
}
