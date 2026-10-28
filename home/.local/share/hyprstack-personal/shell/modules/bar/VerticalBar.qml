pragma ComponentBehavior: Bound

// Personal overlay: the taskbar standing on the left or right screen edge.
// Same entries as the top bar (Settings → Panels → Taskbar), laid out from top
// to bottom; the active window title is left out, it does not fit sideways.

import "popouts" as BarPopouts
import "components"
import "components/workspaces"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import Hyprstack.Config
import qs.components
import qs.services

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts
    required property bool fullscreen
    readonly property real vPadding: Tokens.padding.large
    readonly property real spacing: Tokens.spacing.medium
    readonly property var entryItems: layout.children.filter(c => c.entryId && c.visible)

    function entryAt(y: real): Item {
        for (const item of entryItems) {
            if (item.entryId === "spacer")
                continue;
            const position = item.mapToItem(root, 0, 0);
            if (y >= position.y && y < position.y + item.height)
                return item;
        }
        return null;
    }

    function closeTray(): void {}

    // Popouts open beside the bar; currentCenter is a y coordinate here.
    function checkPopout(y: real): void {
        const ch = entryAt(y) as EntryWrapper;
        if (!ch) {
            popouts.hasCurrent = false;
            return;
        }

        const id = ch.entryId;
        if (id === "statusIcons" && Config.bar.popouts.statusIcons) {
            const items = (ch.item as StatusIcons).items;
            const icon = items.childAt(items.width / 2, mapToItem(items, 0, y).y);
            if (icon) {
                popouts.currentName = icon.name;
                popouts.currentCenter = Qt.binding(() => icon.mapToItem(root, 0, icon.height / 2).y);
                popouts.hasCurrent = true;
            } else {
                popouts.hasCurrent = false;
            }
        } else if (id === "tray" && Config.bar.popouts.tray) {
            const tray = ch.item as VTray;
            const item = tray.column.childAt(tray.column.width / 2, mapToItem(tray.column, 0, y).y) as TrayItem;
            const index = item ? tray.menuIndex(item.modelData) : -1;
            if (index >= 0) {
                popouts.currentName = `traymenu${index}`;
                popouts.currentCenter = Qt.binding(() => item.mapToItem(root, 0, item.height / 2).y);
                popouts.hasCurrent = true;
            } else {
                popouts.hasCurrent = false;
            }
        } else {
            popouts.hasCurrent = false;
        }
    }

    function handleWheel(y: real, angleDelta: point): void {
        const ch = entryAt(y) as EntryWrapper;
        if (ch?.entryId === "workspaces" && Config.bar.scrollActions.workspaces) {
            const mon = Hypr.monitorFor(screen);
            const specialWs = mon?.lastIpcObject.specialWorkspace.name;
            if (specialWs?.length > 0)
                Hypr.dispatch(Hypr.usingLua ? `hl.dsp.workspace.toggle_special("${specialWs.slice(8)}")` : `togglespecialworkspace ${specialWs.slice(8)}`);
            else if (angleDelta.y !== 0)
                Hypr.stepWorkspace(angleDelta.y > 0 ? -1 : 1, mon);
        }
    }

    ColumnLayout {
        id: layout

        anchors.fill: parent
        spacing: root.spacing

        Repeater {
            id: repeater

            model: ScriptModel {
                values: {
                    const entries = root.Config.bar.entries.values.filter(e => e.enabled
                        && !["notifications", "activeWindow"].includes(e.id));
                    const power = entries.findIndex(e => e.id === "power");
                    if (root.Config.sidebar.enabled && root.Config.bar.showNotifications)
                        entries.splice(power < 0 ? entries.length : power, 0, {id: "notifications", enabled: true});
                    return entries;
                }
            }

            DelegateChooser {
                role: "id"

                DelegateChoice {
                    roleValue: "spacer"
                    delegate: EntryWrapper {
                        Layout.fillHeight: true
                    }
                }
                DelegateChoice {
                    roleValue: "logo"
                    delegate: EntryWrapper {
                        OsIcon {}
                    }
                }
                DelegateChoice {
                    roleValue: "workspaces"
                    delegate: EntryWrapper {
                        Workspaces {
                            screen: root.screen
                            fullscreen: root.fullscreen
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "tray"
                    delegate: EntryWrapper {
                        VTray {}
                    }
                }
                DelegateChoice {
                    roleValue: "clock"
                    delegate: EntryWrapper {
                        VClock {}
                    }
                }
                DelegateChoice {
                    roleValue: "statusIcons"
                    delegate: EntryWrapper {
                        StatusIcons {
                            vertical: true
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "vpn"
                    delegate: EntryWrapper {
                        VpnToggle {}
                    }
                }
                DelegateChoice {
                    roleValue: "notifications"
                    delegate: EntryWrapper {
                        NotificationCenterButton {
                            screenState: root.screenState
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "power"
                    delegate: EntryWrapper {
                        Power {
                            screenState: root.screenState
                        }
                    }
                }
            }
        }
    }

    // Hours over minutes, so the clock fits the narrow bar.
    component VClock: StyledRect {
        id: clock

        readonly property color colour: Colours.palette.m3tertiary

        implicitWidth: Tokens.sizes.bar.innerWidth
        implicitHeight: clockColumn.implicitHeight + Tokens.padding.medium * 2
        color: "transparent"
        radius: Tokens.rounding.full

        GroupBackground {
            color: Qt.alpha(Colours.tPalette.m3surfaceContainer, Config.bar.clock.background ? Colours.tPalette.m3surfaceContainer.a : 0)
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.screenState.dashboard = !root.screenState.dashboard
        }

        ColumnLayout {
            id: clockColumn

            anchors.centerIn: parent
            spacing: 0

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: Tokens.spacing.extraSmall
                visible: Config.bar.clock.showIcon
                text: "calendar_month"
                color: clock.colour
            }

            Repeater {
                model: [Time.hourStr, Time.minuteStr].concat(Config.bar.clock.showSeconds ? [Time.format("ss")] : [])

                StyledText {
                    required property string modelData

                    Layout.alignment: Qt.AlignHCenter
                    text: modelData
                    font: Tokens.font.body.builders.small.scale(1.1).build()
                    color: clock.colour
                }
            }
        }
    }

    // Tray icons in a column; menus open beside the bar.
    component VTray: StyledRect {
        id: tray

        readonly property alias column: trayColumn
        readonly property var menuItems: SystemTray.items.values.filter(i => i.status !== Status.Passive && !GlobalConfig.bar.tray.hiddenIcons.includes(i.id))

        function redundant(item: var): bool {
            const id = item.id.toLowerCase();
            const status = Config.bar.statusIcons.values;
            if (/^(nm-applet|networkmanager(-applet)?)$/.test(id))
                return status.some(entry => entry.id === "network" && entry.enabled);
            if (/^(blueman(-applet|-tray)?)$/.test(id))
                return status.some(entry => entry.id === "bluetooth" && entry.enabled);
            return false;
        }

        function menuIndex(item: var): int {
            return tray.menuItems.findIndex(i => i.id === item?.id);
        }

        visible: trayItems.count > 0
        implicitWidth: Tokens.sizes.bar.innerWidth
        implicitHeight: trayItems.count > 0 ? trayColumn.implicitHeight + Tokens.padding.medium * 2 : 0
        color: "transparent"
        radius: Tokens.rounding.full

        GroupBackground {
            color: Qt.alpha(Colours.tPalette.m3surfaceContainer, (Config.bar.tray.background && trayItems.count > 0) ? Colours.tPalette.m3surfaceContainer.a : 0)
        }

        Column {
            id: trayColumn

            anchors.centerIn: parent
            spacing: Tokens.spacing.small

            Repeater {
                id: trayItems

                model: ScriptModel {
                    values: tray.menuItems.filter(i => !tray.redundant(i))
                }

                TrayItem {}
            }
        }
    }

    component EntryWrapper: Item {
        required property var modelData
        required property int index
        default property Item item
        readonly property string entryId: modelData.id

        Layout.topMargin: index === 0 ? root.vPadding : 0
        Layout.bottomMargin: index === repeater.count - 1 ? root.vPadding : 0
        Layout.alignment: Qt.AlignHCenter

        implicitWidth: item?.implicitWidth ?? 0
        implicitHeight: item?.implicitHeight ?? 0

        children: item
    }
}
