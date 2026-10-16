pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Запись экрана: состояние + команды. Саму запись делает ~/.config/hypr/scripts/record.sh,
// он же пишет состояние в $XDG_RUNTIME_DIR/glass-rec.json — бар просто следит за файлом.
//   qs ipc -c glass call recorder menu | toggle | stop
Singleton {
    id: root

    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/record.sh"
    readonly property string stateFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/glass-rec.json"

    // ── настройки меню (запоминаются до перезапуска бара)
    property string mode: "region"      // region | full
    property bool audio: true           // звук системы
    property bool mic: false
    property bool gif: false

    // ── состояние записи (из файла)
    readonly property bool recording: st.recording
    readonly property bool busy: st.busy           // после стопа: конвертирую в GIF
    readonly property real startedAt: st.start
    property int elapsed: 0

    // какое меню открыть: на мониторе в фокусе
    property string menuScreen: ""
    property int menuToken: 0

    function openMenu() {
        menuScreen = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        menuToken++;
    }
    function start() {
        Quickshell.execDetached(["sh", "-c", 'sleep 0.35; exec "$0" start "$1" "$2" "$3" "$4"',
                                 script, mode, audio ? "1" : "0", mic ? "1" : "0", gif ? "1" : "0"]);
    }
    function stop() { Quickshell.execDetached([script, "stop"]); }

    function fmt(s) {
        const m = Math.floor(s / 60), x = s % 60;
        return (m < 10 ? "0" : "") + m + ":" + (x < 10 ? "0" : "") + x;
    }

    Timer {
        interval: 500; repeat: true; running: root.recording; triggeredOnStart: true
        onTriggered: root.elapsed = Math.max(0, Math.floor(Date.now() / 1000 - root.startedAt))
    }

    // файл может ещё не существовать — создаём пустой
    Process {
        running: true
        command: ["sh", "-c", '[ -s "$0" ] || printf \'{"recording":false}\' > "$0"', root.stateFile]
        onExited: file.reload()
    }
    FileView {
        id: file
        path: root.stateFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        JsonAdapter {
            id: st
            property bool recording: false
            property bool busy: false
            property real start: 0
            property string file: ""
        }
    }
    // на случай, если изменение файла пропущено — раз в 2 секунды перечитываем
    Timer { interval: 2000; repeat: true; running: root.recording || root.busy; onTriggered: file.reload() }

    IpcHandler {
        target: "recorder"
        function menu(): void { root.openMenu(); }
        function stop(): void { root.stop(); }
        function toggle(): void { if (root.recording) root.stop(); else root.openMenu(); }
    }
}
