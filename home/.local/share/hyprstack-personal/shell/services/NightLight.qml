pragma Singleton

// Personal overlay: night light. ~/.local/bin/nightlight does the work
// (hyprsunset) and keeps the settings in ~/.config/hyprstack/nightlight.json,
// which this service watches, so the quick toggle and Settings → Night light
// follow changes made by shortcuts or the schedule.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string script: Quickshell.env("HOME") + "/.local/bin/nightlight"

    property bool enabled: false
    property int temperature: 4000
    property bool scheduleEnabled: false
    property string scheduleFrom: "21:00"
    property string scheduleTo: "07:00"
    readonly property int minTemperature: 2500
    readonly property int maxTemperature: 6000
    property string error: ""

    function run(args: var): void {
        root.error = "";
        runner.queue.push([root.script, ...args]);
        runner.next();
    }

    function toggle(): void {
        root.enabled = !root.enabled; // show the new state right away
        run(["toggle"]);
    }
    function setEnabled(on: bool): void {
        root.enabled = on;
        run([on ? "on" : "off"]);
    }
    function setTemperature(value: int): void {
        root.temperature = value;
        run(["set-temperature", String(value)]);
    }
    function setSchedule(on: bool): void {
        root.scheduleEnabled = on;
        run(["schedule", on ? "on" : "off"]);
    }
    function setScheduleTimes(from: string, to: string): void {
        root.scheduleFrom = from;
        root.scheduleTo = to;
        run(["set-schedule", from, to]);
    }

    function apply(text: string): void {
        let data;
        try {
            data = JSON.parse(text);
        } catch (e) {
            return;
        }
        root.enabled = data.enabled === true;
        root.temperature = Number(data.temperature ?? 4000);
        root.scheduleEnabled = data.schedule?.enabled === true;
        root.scheduleFrom = data.schedule?.from ?? "21:00";
        root.scheduleTo = data.schedule?.to ?? "07:00";
    }

    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/hyprstack/nightlight.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }

    Process {
        id: runner

        property var queue: []

        function next(): void {
            if (running || !queue.length)
                return;
            command = queue.shift();
            running = true;
        }

        stderr: StdioCollector {
            id: runnerErr
        }
        onExited: code => {
            if (code !== 0)
                root.error = runnerErr.text.trim() || "Не удалось изменить ночной режим";
            next();
        }
    }
}
