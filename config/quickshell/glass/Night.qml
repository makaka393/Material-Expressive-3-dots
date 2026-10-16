pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Ночной режим (тёплый экран) через hyprsunset. Один на все мониторы.
// Состояние помнится в ~/.cache/glass-night.json — после перезапуска бара включится снова.
//   qs ipc -c glass call night toggle | enable | disable
Singleton {
    id: root

    readonly property string stateFile: Quickshell.env("HOME") + "/.cache/glass-night.json"
    property bool active: false
    property int temp: 4000                 // K: меньше — теплее (2500…6000)
    property bool loaded: false
    property int gamma: 100                 // яркость через гамму (если монитор без DDC) — задаёт Brightness

    function toggle() { active = !active; save(); }
    // плитка в шторке: выкл → вкл → авто → выкл
    function cycle() {
        if (Config.nightAuto) { Config.nightAuto = false; active = false; save(); }
        else if (!active) { active = true; save(); }
        else Config.nightAuto = true;
    }

    // авто-режим (Config.nightAuto): на закате включаемся, на рассвете выключаемся. Ручное
    // переключение действует до следующего заката или рассвета.
    function applyAuto() {
        if (!Config.nightAuto || !loaded || active === !Sun.day) return;
        active = !Sun.day;
        save();
    }
    onLoadedChanged: applyAuto()
    Connections { target: Sun; function onDayChanged() { root.applyAuto(); } }
    Connections { target: Config; function onNightAutoChanged() { root.applyAuto(); } }
    function setTemp(t) {
        temp = Math.max(2500, Math.min(6000, Math.round(t / 100) * 100));
        save();
        if (active) applyTimer.restart();
    }
    function save() {
        if (!loaded) return;
        saver.command = ["sh", "-c", 'printf \'{"on":%s,"temp":%s}\' "$1" "$2" > "$0"', stateFile, active ? "true" : "false", String(temp)];
        saver.running = true;
    }

    // сам hyprsunset живёт, пока включено
    readonly property bool needed: (root.active || root.gamma < 100) && root.loaded
    Process {
        id: sunset
        running: root.needed
        command: (root.active ? ["hyprsunset", "-t", String(root.temp)] : ["hyprsunset", "-i"])
                 .concat(root.gamma < 100 ? ["-g", String(root.gamma)] : [])
    }
    // гамма поменялась на ходу
    function setGamma(g) {
        const was = gamma;
        gamma = Math.max(20, Math.min(100, Math.round(g)));
        if (sunset.running && was < 100 && gamma < 100) gammaTimer.restart();
    }
    Timer { id: gammaTimer; interval: 120; onTriggered: gammaIpc.running = true }
    Process {
        id: gammaIpc
        command: ["sh", "-c", 'hyprctl hyprsunset gamma "$0" 2>/dev/null | grep -qi ok', String(root.gamma)]
        onExited: code => { if (code !== 0 && root.needed) { sunset.running = false; restart.restart(); } }
    }
    // сменили температуру на лету: сначала через IPC hyprsunset (без мигания),
    // если версия старая — перезапускаем
    Timer { id: applyTimer; interval: 250; onTriggered: ipc.running = true }
    Process {
        id: ipc
        command: ["sh", "-c", 'hyprctl hyprsunset temperature "$0" 2>/dev/null | grep -qi ok', String(root.temp)]
        onExited: code => { if (code !== 0 && root.needed) { sunset.running = false; restart.restart(); } }
    }
    // вкл/выкл ночного режима при включённой гамме — перезапуск с новыми аргументами
    onActiveChanged: if (sunset.running) { sunset.running = false; restart.restart(); }
    Timer { id: restart; interval: 120; onTriggered: sunset.running = Qt.binding(() => root.needed) }

    Process { id: saver }

    FileView {
        path: root.stateFile
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.temp = d.temp || 4000;
                root.active = !!d.on;
            } catch (e) {}
            root.loaded = true;
        }
        onLoadFailed: root.loaded = true
    }

    IpcHandler {
        target: "night"
        function toggle(): void { root.toggle(); }
        function enable(): void { root.active = true; root.save(); }
        function disable(): void { root.active = false; root.save(); }
    }
}
