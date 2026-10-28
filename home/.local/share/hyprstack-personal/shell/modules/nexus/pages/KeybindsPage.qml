pragma ComponentBehavior: Bound

// Personal overlay: keyboard shortcuts can be changed from this page, and new
// shortcuts that start an application can be added ("custom" in keybinds.json).

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.controls
import qs.components.containers
import qs.services
import qs.modules.nexus.common
import "../../../services/Keybinds.js" as Bindings

PageBase {
    id: root

    title: Tr.tr("Keyboard shortcuts")
    objectName: "keyboardShortcutsPage"
    property string query
    function translated(text: string): string { return Bindings.translateDescription(text, value => root.l(value)); }
    function l(text: string): string { return Bindings.localText(text, value => Tr.tr(value), Tr.language); }
    function shortcutText(value: string): string { return Bindings.translateShortcut(value, text => root.l(text)); }
    readonly property var filtered: Keybinds.bindings.filter(b => Bindings.matches(b, query, translated))

    // Shortcut being recorded: {name, index, entryKey, empty}
    property var editing: null
    property var heldMods: []
    // {chord, label, others: [{entry, name, index, label}], system: bool, own: bool}
    property var conflict: null

    // "Add shortcut" form
    property bool adding
    property bool addPending
    property string draftChord
    property var draftConflict: null
    property bool draftReplace
    property string draftMode: "app"
    property var draftApp: null
    property string appQuery
    readonly property var draftCommand: draftMode === "app" ? (draftApp?.command ?? "") : commandField.text.trim()
    readonly property string draftProblem: !draftChord ? "Record a key combination"
        : draftConflict && !draftReplace ? "Resolve the conflict first"
        : !draftCommand ? "Choose an application or enter a command" : ""
    readonly property var filteredApps: {
        const tokens = appQuery.trim().toLowerCase().replace(/ё/g, "е").split(/\s+/).filter(t => t);
        return Keybinds.apps.filter(a => {
            const text = (a.name + " " + a.comment + " " + a.id).toLowerCase().replace(/ё/g, "е");
            return tokens.every(t => text.includes(t));
        });
    }

    function conflictFor(chord: string, others: var): var {
        return {chord: chord, label: Bindings.displayChord(chord), others: others,
            system: others.some(c => !c.name || Bindings.isCustomName(c.name)),
            own: others.some(c => Bindings.isCustomName(c.name))};
    }

    function iconSource(icon: string): string {
        if (!icon)
            return Quickshell.iconPath("application-x-executable", "image-missing");
        return icon.startsWith("/") ? "file://" + icon : Quickshell.iconPath(icon, "application-x-executable");
    }

    function openAdd(): void {
        if (Keybinds.saving || editing)
            return;
        Keybinds.saveError = "";
        draftChord = "";
        draftConflict = null;
        draftReplace = false;
        draftMode = "app";
        draftApp = null;
        appQuery = "";
        appSearch.text = "";
        commandField.text = "";
        nameField.text = "";
        adding = true;
        Keybinds.loadApps();
    }

    function closeAdd(): void {
        if (editing?.isNew)
            cancelEdit();
        adding = false;
        addPending = false;
    }

    function recordNew(): void {
        if (Keybinds.saving)
            return;
        draftConflict = null;
        draftReplace = false;
        Keybinds.saveError = "";
        editing = {name: "", index: 0, entryKey: "", submap: "", empty: true, isNew: true};
        heldMods = [];
        Keybinds.startRecording();
        recorder.forceActiveFocus();
        recordTimeout.restart();
    }

    function saveNew(): void {
        if (draftProblem || Keybinds.saving)
            return;
        const id = Bindings.normalise(draftChord);
        const changes = {};
        if (draftConflict && draftReplace) {
            for (const other of draftConflict.others) {
                if (!other.name || Bindings.isCustomName(other.name))
                    continue;
                const list = changes[other.name] ?? Keybinds.effective(other.name);
                changes[other.name] = list.filter(c => Bindings.normalise(c) !== id);
            }
        }
        const app = draftMode === "app" ? draftApp : null;
        const command = draftCommand;
        addPending = true;
        Keybinds.saveCustom({chord: draftChord, command: command,
            name: app ? app.name : (nameField.text.trim() || Bindings.commandName(command)),
            icon: app ? app.icon : ""}, changes);
    }

    function deleteCustom(entry: var): void {
        if (Keybinds.saving || editing)
            return;
        Keybinds.deleteCustom(entry.customId);
    }

    readonly property Connections saveWatcher: Connections {
        target: Keybinds
        function onSaved(): void {
            if (root.addPending)
                root.closeAdd();
        }
        function onSaveErrorChanged(): void {
            if (Keybinds.saveError)
                root.addPending = false;
        }
    }

    function startEdit(entry: var, chip: var): void {
        if (Keybinds.saving)
            return;
        conflict = null;
        Keybinds.saveError = "";
        editing = {name: chip.name, index: chip.empty ? Keybinds.effective(chip.name).length : chip.index,
            entryKey: entry.key, submap: entry.submap, empty: !!chip.empty, chipLabel: chip.label};
        heldMods = [];
        Keybinds.startRecording();
        recorder.forceActiveFocus();
        recordTimeout.restart();
    }

    function stopCapture(): void {
        recordTimeout.stop();
        heldMods = [];
        Keybinds.stopRecording();
    }

    function cancelEdit(): void {
        stopCapture();
        editing = null;
        conflict = null;
    }

    function recordAgain(): void {
        const entry = Keybinds.bindings.find(b => b.key === editing?.entryKey);
        const target = editing;
        conflict = null;
        editing = null;
        if (entry && target)
            startEdit(entry, {name: target.name, index: target.index, empty: target.empty, label: target.chipLabel});
    }

    function finishRecording(chord: string): void {
        stopCapture();
        if (editing.isNew) {
            const found = Bindings.conflicts(Keybinds.bindings, chord, null);
            editing = null;
            draftChord = chord;
            draftReplace = false;
            draftConflict = found.length ? conflictFor(chord, found) : null;
            return;
        }
        const others = Bindings.conflicts(Keybinds.bindings, chord, editing).filter(c => c.name !== editing.name);
        if (!others.length) {
            commit(chord, []);
            return;
        }
        conflict = conflictFor(chord, others);
    }

    function commit(chord: string, others: var): void {
        if (Bindings.isCustomName(editing.name)) {
            const own = Keybinds.custom.find(c => c.id === Bindings.customId(editing.name));
            const taken = Bindings.normalise(chord);
            const moved = {};
            for (const other of others) {
                if (!other.name || Bindings.isCustomName(other.name))
                    continue;
                const was = moved[other.name] ?? Keybinds.effective(other.name);
                moved[other.name] = was.filter(c => Bindings.normalise(c) !== taken);
            }
            editing = null;
            conflict = null;
            if (own)
                Keybinds.saveCustom(Object.assign({}, own, {chord: chord}), moved);
            return;
        }
        const id = Bindings.normalise(chord);
        const changes = {};
        const own = Keybinds.effective(editing.name).slice();
        if (editing.empty || editing.index >= own.length)
            own.push(chord);
        else
            own[editing.index] = chord;
        // Drop duplicates of the new chord within the same shortcut.
        changes[editing.name] = own.filter((c, i) => Bindings.normalise(c) !== id || i === own.findIndex(x => Bindings.normalise(x) === id));
        for (const other of others) {
            if (!other.name)
                continue;
            const list = changes[other.name] ?? Keybinds.effective(other.name);
            changes[other.name] = list.filter(c => Bindings.normalise(c) !== id);
        }
        editing = null;
        conflict = null;
        Keybinds.save(changes);
    }

    // Scroll to and outline the entry using a shortcut, like settings search does.
    function showEntry(key: string): void {
        if (search.text !== "")
            search.text = "";
        revealKey = key;
        revealAttempts = 0;
        revealTimer.restart();
    }

    property string revealKey
    property int revealAttempts

    function findEntry(item: Item): Item {
        if (item.entryKey === revealKey)
            return item;
        for (const child of item.children ?? []) {
            const found = findEntry(child);
            if (found)
                return found;
        }
        return null;
    }

    readonly property Timer revealTimer: Timer {
        interval: 50
        repeat: true
        onTriggered: {
            const item = root.findEntry(root.contentChild);
            if (item && item.height > 0) {
                stop();
                const flick = root.flickable;
                const point = item.mapToItem(flick.contentItem, 0, 0);
                flick.cancelFlick();
                flick.contentY = Math.max(-flick.topMargin, Math.min(
                    Math.max(-flick.topMargin, flick.contentHeight - flick.height + flick.bottomMargin),
                    point.y - (flick.height - item.height) / 2));
                root.searchHighlight = item;
                root.highlightExpiry.restart();
            } else if (++root.revealAttempts >= 20) {
                stop();
            }
        }
    }

    readonly property Timer recordTimeout: Timer {
        interval: 15000
        onTriggered: root.cancelEdit()
    }

    // The service keeps the list up to date on its own (config reloads, file
    // changes), so opening the page does not re-read it and rebuild every row.
    // Applications are loaded only when the "Add shortcut" form opens.
    Component.onCompleted: {
        if (!Keybinds.bindings.length)
            Keybinds.reload();
    }
    Component.onDestruction: if (editing) Keybinds.stopRecording()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall

        // Receives key presses while a shortcut is being recorded.
        Item {
            id: recorder
            implicitWidth: 0
            implicitHeight: 0
            Layout.preferredHeight: 0

            function mods(flags: int): var {
                const result = root.heldMods.slice();
                for (const mod of Bindings.qtModifiers(flags))
                    if (!result.includes(mod))
                        result.push(mod);
                return result;
            }

            Keys.onShortcutOverride: event => event.accepted = !!root.editing && !root.conflict
            Keys.onPressed: event => {
                if (!root.editing || root.conflict)
                    return;
                event.accepted = true;
                const sym = Bindings.keysymFor(event.nativeScanCode);
                if (!sym)
                    return;
                const mod = Bindings.modifierFor(sym);
                if (Bindings.MODIFIER_SYMS.test(sym)) {
                    if (mod && !root.heldMods.includes(mod))
                        root.heldMods = root.heldMods.concat([mod]);
                    return;
                }
                const pressed = recorder.mods(event.modifiers);
                if (sym === "Escape" && !pressed.length) {
                    root.cancelEdit();
                    return;
                }
                root.finishRecording(Bindings.buildChord(pressed, Bindings.configKey(sym)));
            }
            Keys.onReleased: event => {
                if (!root.editing)
                    return;
                event.accepted = true;
                const mod = Bindings.modifierFor(Bindings.keysymFor(event.nativeScanCode));
                if (mod)
                    root.heldMods = root.heldMods.filter(m => m !== mod);
            }
            onActiveFocusChanged: {
                if (!activeFocus && root.editing && !root.conflict)
                    root.cancelEdit();
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: root.l("Current Hyprland shortcuts, including your custom bindings. Super is the Windows/Meta key. Click the pencil to change a shortcut.")
                + (String(Tr.language).startsWith("ru") ? " Свои сочетания для запуска приложений можно добавить кнопкой ниже." : " Use the button below to add your own shortcut that starts an application.")
            wrapMode: Text.WordWrap
            color: Colours.palette.m3onSurfaceVariant
        }

        IconTextButton {
            Layout.alignment: Qt.AlignLeft
            visible: !root.adding
            type: TextButton.Tonal
            icon: "add"
            text: root.l("Add shortcut…")
            disabled: Keybinds.saving || !!root.editing
            onClicked: root.openAdd()
        }

        // New shortcut form
        ConnectedRect {
            Layout.fillWidth: true
            visible: root.adding
            first: true
            last: true
            implicitHeight: addForm.implicitHeight + Tokens.padding.medium * 2

            ColumnLayout {
                id: addForm
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                StyledText {
                    text: root.l("New shortcut")
                    font: Tokens.font.body.medium
                }

                // Step 1: key combination
                StyledText {
                    text: "1. " + root.l("Shortcut")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledText {
                        Layout.fillWidth: true
                        readonly property bool recordingNew: !!root.editing?.isNew
                        text: recordingNew
                            ? (root.heldMods.length ? Bindings.liveText(root.heldMods) : root.l("Press a key combination… (Esc to cancel)"))
                            : root.draftChord ? root.shortcutText(Bindings.displayChord(root.draftChord)) : root.l("Not set")
                        textFormat: Text.PlainText
                        color: recordingNew ? Colours.palette.m3tertiary
                            : root.draftChord ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        wrapMode: Text.WordWrap
                    }
                    IconTextButton {
                        type: TextButton.Tonal
                        icon: root.editing?.isNew ? "close" : "keyboard"
                        text: root.editing?.isNew ? root.l("Cancel") : root.draftChord ? root.l("Record another") : root.l("Record")
                        disabled: Keybinds.saving || (!!root.editing && !root.editing.isNew)
                        onClicked: root.editing?.isNew ? root.cancelEdit() : root.recordNew()
                    }
                }

                // Conflict with an existing shortcut
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: !!root.draftConflict
                    spacing: Tokens.spacing.extraSmall

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            text: root.draftReplace ? "swap_horiz" : "warning"
                            color: root.draftReplace ? Colours.palette.m3tertiary : Colours.palette.m3error
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.draftConflict ? root.l("This shortcut is already in use: %1")
                                .arg(root.draftConflict.others.map(c => root.translated(c.entry.action)).join(", ")) : ""
                            color: root.draftReplace ? Colours.palette.m3tertiary : Colours.palette.m3error
                            wrapMode: Text.WordWrap
                        }
                        TextButton {
                            type: TextButton.Text
                            text: root.l("Show")
                            onClicked: root.showEntry(root.draftConflict.others[0].entry.key)
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: !!root.draftConflict?.system
                        text: root.draftConflict?.own ? root.l("It is one of your shortcuts. Change or delete it first.")
                            : root.l("It belongs to a system shortcut and cannot be reassigned here.")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                        wrapMode: Text.WordWrap
                    }
                    TextButton {
                        Layout.alignment: Qt.AlignRight
                        visible: !root.draftConflict?.system && !root.draftReplace
                        type: TextButton.Tonal
                        text: root.l("Replace")
                        onClicked: root.draftReplace = true
                    }
                }

                // Step 2: action
                StyledText {
                    Layout.topMargin: Tokens.spacing.small
                    text: "2. " + root.l("Action")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }
                RowLayout {
                    spacing: Tokens.spacing.small
                    IconTextButton {
                        type: root.draftMode === "app" ? TextButton.Filled : TextButton.Tonal
                        icon: "apps"
                        text: root.l("Application")
                        onClicked: root.draftMode = "app"
                    }
                    IconTextButton {
                        type: root.draftMode === "command" ? TextButton.Filled : TextButton.Tonal
                        icon: "terminal"
                        text: root.l("Command")
                        onClicked: root.draftMode = "command"
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.draftMode === "app"
                    spacing: Tokens.spacing.small

                    StyledTextField {
                        id: appSearch
                        Layout.fillWidth: true
                        leadingIcon: "search"
                        placeholderText: root.l("Search applications")
                        onTextChanged: root.appQuery = text
                    }

                    VerticalFadeListView {
                        id: appList
                        Layout.fillWidth: true
                        implicitHeight: 320
                        clip: true
                        model: root.filteredApps

                        delegate: StateLayer {
                            id: appItem
                            required property var modelData
                            readonly property bool selected: root.draftApp?.id === modelData.id

                            anchors.fill: undefined
                            anchors.left: appList.contentItem.left
                            anchors.right: appList.contentItem.right
                            implicitHeight: appRow.implicitHeight + appRow.anchors.margins * 2
                            radius: Tokens.rounding.small
                            onClicked: root.draftApp = modelData

                            StyledRect {
                                anchors.fill: parent
                                radius: Tokens.rounding.small
                                visible: appItem.selected
                                color: Colours.palette.m3secondaryContainer
                            }

                            RowLayout {
                                id: appRow
                                anchors.fill: parent
                                anchors.margins: Tokens.padding.medium
                                spacing: Tokens.spacing.medium

                                IconImage {
                                    asynchronous: true
                                    implicitSize: Math.round(Tokens.font.icon.large.pointSize * 1.8)
                                    source: root.iconSource(appItem.modelData.icon)
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: appItem.modelData.name
                                        textFormat: Text.PlainText
                                        font: Tokens.font.body.small
                                        elide: Text.ElideRight
                                        color: appItem.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        visible: text
                                        text: appItem.modelData.comment ?? ""
                                        textFormat: Text.PlainText
                                        color: Colours.palette.m3outline
                                        font: Tokens.font.label.small
                                        elide: Text.ElideRight
                                    }
                                }
                                MaterialIcon {
                                    visible: appItem.selected
                                    text: "check"
                                    color: Colours.palette.m3primary
                                }
                            }
                        }
                    }

                    StyledText {
                        visible: !root.filteredApps.length
                        text: Keybinds.appsLoading ? root.l("Loading applications…") : root.l("No applications found")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.draftMode === "command"
                    spacing: Tokens.spacing.small

                    StyledTextField {
                        id: commandField
                        Layout.fillWidth: true
                        leadingIcon: "terminal"
                        placeholderText: root.l("Command to run, e.g. firefox --private-window")
                    }
                    StyledTextField {
                        id: nameField
                        Layout.fillWidth: true
                        leadingIcon: "label"
                        placeholderText: root.l("Name (optional)")
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: !!Keybinds.saveError && root.adding
                    text: root.l(Keybinds.saveError)
                    color: Colours.palette.m3error
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledText {
                        Layout.fillWidth: true
                        text: Keybinds.saving ? root.l("Saving…") : root.draftProblem ? root.l(root.draftProblem) : ""
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                        wrapMode: Text.WordWrap
                    }
                    TextButton {
                        type: TextButton.Text
                        text: root.l("Cancel")
                        disabled: Keybinds.saving
                        onClicked: root.closeAdd()
                    }
                    TextButton {
                        type: TextButton.Filled
                        text: root.l("Save")
                        disabled: !!root.draftProblem || Keybinds.saving || !!root.editing
                        onClicked: root.saveNew()
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            StyledTextField {
                id: search
                objectName: "keyboardShortcutsSearch"
                Layout.fillWidth: true
                placeholderText: Tr.tr("Search keyboard shortcuts")
                onTextChanged: root.query = text
            }
            IconButton {
                icon: "refresh"
                disabled: Keybinds.loading
                onClicked: Keybinds.reload()
                Accessible.name: Tr.tr("Refresh")
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: !root.adding && (Keybinds.saving || !!Keybinds.saveError)
            text: Keybinds.saving ? root.l("Saving…") : root.l(Keybinds.saveError)
            color: Keybinds.saving ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3error
            wrapMode: Text.WordWrap
        }

        // Rows are built in the background a few at a time, so the page opens
        // immediately instead of creating ~200 rows in one go.
        Repeater {
            model: root.filtered
            Loader {
                id: entryLoader
                required property var modelData
                required property int index
                Layout.fillWidth: true
                asynchronous: true
                sourceComponent: ColumnLayout {
                id: entry
                readonly property var modelData: entryLoader.modelData
                readonly property int index: entryLoader.index
                readonly property bool editingHere: root.editing?.entryKey === modelData.key
                Layout.fillWidth: true
                spacing: 0

                SectionHeader {
                    visible: entry.index === 0 || root.filtered[entry.index - 1].category !== entry.modelData.category
                    first: entry.index === 0
                    text: root.l(entry.modelData.category)
                }
                ConnectedRect {
                    objectName: "keyboardShortcut_" + entry.index
                    readonly property string entryKey: entry.modelData.key
                    Layout.fillWidth: true
                    first: entry.index === 0 || root.filtered[entry.index - 1].category !== entry.modelData.category
                    last: entry.index === root.filtered.length - 1 || root.filtered[entry.index + 1].category !== entry.modelData.category
                    implicitHeight: content.implicitHeight + Tokens.padding.medium * 2

                    ColumnLayout {
                        id: content
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.padding.medium
                        spacing: Tokens.spacing.extraSmall

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.small

                            IconImage {
                                visible: !!entry.modelData.customId
                                asynchronous: true
                                implicitSize: Math.round(Tokens.font.icon.small.pointSize * 1.8)
                                source: visible ? root.iconSource(entry.modelData.icon) : ""
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: entry.modelData.customId ? entry.modelData.action : root.translated(entry.modelData.action)
                                textFormat: Text.PlainText
                                wrapMode: Text.WordWrap
                            }
                            StyledText {
                                visible: entry.modelData.modified
                                text: root.l("Modified")
                                color: Colours.palette.m3tertiary
                                font: Tokens.font.body.small
                            }
                            IconButton {
                                visible: entry.modelData.modified
                                type: IconButton.Text
                                icon: "restart_alt"
                                disabled: Keybinds.saving || !!root.editing
                                onClicked: root.reset(entry.modelData)
                                Accessible.name: root.l("Reset to default")
                            }
                            IconButton {
                                visible: !!entry.modelData.customId
                                type: IconButton.Text
                                icon: "delete"
                                disabled: Keybinds.saving || !!root.editing
                                onClicked: root.deleteCustom(entry.modelData)
                                Accessible.name: root.l("Delete shortcut")
                            }
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.small

                            Repeater {
                                model: entry.modelData.chips
                                Row {
                                    id: chip
                                    required property var modelData
                                    required property int index
                                    readonly property bool recordingThis: !!root.editing && !root.conflict
                                        && root.editing.entryKey === entry.modelData.key
                                        && root.editing.name === modelData.name
                                        && (modelData.empty ? root.editing.empty : root.editing.index === modelData.index && !root.editing.empty)
                                    spacing: Tokens.spacing.extraSmall / 2

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: chip.recordingThis
                                            ? (root.heldMods.length ? Bindings.liveText(root.heldMods) : root.l("Press a key combination… (Esc to cancel)"))
                                            : chip.modelData.empty ? root.l("No shortcut") : root.shortcutText(chip.modelData.label)
                                        textFormat: Text.PlainText
                                        color: chip.recordingThis ? Colours.palette.m3tertiary
                                            : chip.modelData.empty ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3primary
                                        font: Tokens.font.body.small
                                    }
                                    IconButton {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: !!chip.modelData.name && (Keybinds.editable || Bindings.isCustomName(chip.modelData.name))
                                        type: IconButton.Text
                                        font: Tokens.font.icon.small
                                        icon: chip.recordingThis ? "close" : chip.modelData.empty ? "add" : "edit"
                                        disabled: Keybinds.saving || (!!root.editing && !chip.recordingThis)
                                        onClicked: chip.recordingThis ? root.cancelEdit() : root.startEdit(entry.modelData, chip.modelData)
                                        Accessible.name: chip.recordingThis ? root.l("Cancel")
                                            : chip.modelData.empty ? root.l("Add shortcut") : root.l("Edit shortcut")
                                    }
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: chip.index < entry.modelData.chips.length - 1
                                        text: "  /  "
                                        color: Colours.palette.m3onSurfaceVariant
                                        font: Tokens.font.body.small
                                    }
                                }
                            }

                            StyledText {
                                visible: !!entry.modelData.submap
                                text: "· " + (entry.modelData.submap === "hyprstack-switcher" ? Tr.tr("Window switcher") : entry.modelData.submap)
                                textFormat: Text.PlainText
                                color: Colours.palette.m3primary
                                font: Tokens.font.body.small
                            }
                        }

                        // Conflict with another shortcut (created only when shown)
                        Loader {
                            Layout.fillWidth: true
                            Layout.topMargin: Tokens.spacing.extraSmall
                            active: entry.editingHere && !!root.conflict
                            visible: active
                            sourceComponent: ColumnLayout {
                            spacing: Tokens.spacing.extraSmall

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.small

                                MaterialIcon {
                                    text: "warning"
                                    color: Colours.palette.m3error
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.conflict ? root.l("This shortcut is already in use: %1")
                                        .arg(root.conflict.others.map(c => root.translated(c.entry.action)).join(", "))
                                        + " (" + root.shortcutText(root.conflict.label) + ")" : ""
                                    color: Colours.palette.m3error
                                    wrapMode: Text.WordWrap
                                }
                                TextButton {
                                    type: TextButton.Text
                                    text: root.l("Show")
                                    onClicked: root.showEntry(root.conflict.others[0].entry.key)
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: !!root.conflict?.system
                                text: root.conflict?.own ? root.l("It is one of your shortcuts. Change or delete it first.")
                                    : root.l("It belongs to a system shortcut and cannot be reassigned here.")
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.body.small
                                wrapMode: Text.WordWrap
                            }
                            RowLayout {
                                Layout.alignment: Qt.AlignRight
                                spacing: Tokens.spacing.small

                                TextButton {
                                    type: TextButton.Text
                                    text: root.l("Cancel")
                                    onClicked: root.cancelEdit()
                                }
                                TextButton {
                                    type: TextButton.Tonal
                                    text: root.l("Record another")
                                    onClicked: root.recordAgain()
                                }
                                TextButton {
                                    type: TextButton.Filled
                                    text: root.l("Replace")
                                    disabled: !!root.conflict?.system
                                    onClicked: root.commit(root.conflict.chord, root.conflict.others)
                                }
                            }
                            }
                        }
                    }
                }
            }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: !!Keybinds.error || (!Keybinds.loading && !root.filtered.length)
            text: Keybinds.error ? Tr.tr(Keybinds.error) : Tr.tr("No matching shortcuts")
            color: Keybinds.error ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
        }
    }

    function reset(entry: var): void {
        Keybinds.reset(entry.vars.filter(name => Object.prototype.hasOwnProperty.call(Keybinds.overrides, name)));
    }
}
