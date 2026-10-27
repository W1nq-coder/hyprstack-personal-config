import QtQuick
import Quickshell
import Hyprstack.Config
import qs.services

Scope {
    Component.onCompleted: {
        // Force certain singletons to load on shell init instead of lazily

        IdleInhibitor;
        GameMode;
        Notifs;
        Players;
        WindowSwitcher;
        Brightness;
        InputSettings; // watches mouse hotplug (personal overlay)
        Dictation; // voice input state (personal overlay)
        Weather.reload();
        ThemeSync.requestSync();

        if (GlobalConfig.utilities.vpn.enabled)
            VPN;
    }
}
