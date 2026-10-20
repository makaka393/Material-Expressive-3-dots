pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Игровой режим и без gamemoderun: раз в 3 с ~/.config/hypr/scripts/game-watch.sh ищет запущенную игру
// (Steam, Proton, Mobile Legends) и сам включает и выключает режим (gamemode-start.sh / gamemode-end.sh):
// без видеообоев, фоновые приложения тише, ассистент выгружает модели и не слушает.
Singleton {
    id: root

    property string game: ""                 // что запущено (имя процесса игры) или ""
    readonly property bool playing: game !== ""

    Process {
        id: watch
        command: [Quickshell.env("HOME") + "/.config/hypr/scripts/game-watch.sh"]
        stdout: StdioCollector { onStreamFinished: root.game = text.trim() }
    }
    Timer {
        interval: 3000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: if (!watch.running) watch.running = true
    }
}
