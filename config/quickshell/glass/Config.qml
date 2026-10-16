pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Настройки оболочки: ~/.config/glass/settings.json. Меняются из окна настроек
// и сразу применяются везде (файл пишется сам при изменении любого свойства).
//   qs ipc -c glass call settings toggle
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.config/glass"

    // оформление: "glass" — матовое стекло с блюром, "m3" — Material Expressive (тональные поверхности)
    property alias style: cfg.style
    property alias glassOpacity: cfg.glassOpacity     // стекло: 0.15 (почти прозрачно) … 0.7
    property alias m3Opacity: cfg.m3Opacity           // M3: 0.5 (полупрозрачно) … 1 (сплошной)
    property alias glassBlur: cfg.glassBlur           // стекло: сила размытия Hyprland (decoration:blur:size), 3…16
    property alias brightness: cfg.brightness         // яркость, если монитор не понимает DDC (через гамму)
    property alias lang: cfg.lang                     // язык оболочки: "ru" | "en"
    property alias exactColor: cfg.exactColor         // true — тема точно выбранного цвета, false — мягкий Material (как у Google)
    property alias dnd: cfg.dnd                       // «Не беспокоить»: уведомления только в историю
    // AOD (Always On Display): отошёл от компьютера — фон темнеет, остаются часы и виджеты
    property alias aodEnabled: cfg.aodEnabled
    property alias aodClock: cfg.aodClock             // один из aodFaces
    readonly property var aodFaces: ["bubble", "analog", "orbit", "dots", "planets", "horizon", "segments"]
    // выбранный циферблат; если в настройках остался удалённый или незнакомый — стрелки
    readonly property string aodFace: aodFaces.indexOf(cfg.aodClock) >= 0 ? cfg.aodClock : "analog"
    property alias aodTimeout: cfg.aodTimeout         // через сколько секунд простоя
    property alias aodDim: cfg.aodDim                 // насколько темнеет фон: 0.5…1
    property alias aodMusic: cfg.aodMusic
    property alias aodWeather: cfg.aodWeather
    property alias aodLock: cfg.aodLock               // пароль после AOD: -1 — не нужен, 0 — сразу, N — если AOD висел N секунд
    property alias aodHideWindows: cfg.aodHideWindows // на время AOD окна становятся полностью прозрачными
    property alias nightAuto: cfg.nightAuto           // защита глаз сама включается на закате и выключается на рассвете
    property alias lockOnStart: cfg.lockOnStart       // запирать экран при входе в сессию (вместо экрана входа) — см. Locker
    property int aodWakePing: 0                       // разбудить AOD (важное событие, например «игра найдена»)
    property int aodPing: 0                           // «Показать сейчас» из настроек

    property bool settingsOpen: false
    property string aodScreen: ""                     // монитор, на котором сейчас AOD, — там бар прячется

    // папка может не существовать — создаём до первой записи
    Process {
        running: true
        command: ["mkdir", "-p", root.dir]
    }

    FileView {
        id: file
        path: root.dir + "/settings.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter(); }

        JsonAdapter {
            id: cfg
            property string style: "glass"
            property real glassOpacity: 0.34
            property real m3Opacity: 1.0
            property int glassBlur: 9
            property int brightness: 100
            property bool exactColor: false
            property string lang: "ru"
            property bool dnd: false
            property bool aodEnabled: true
            property string aodClock: "analog"
            property int aodTimeout: 300
            property real aodDim: 0.86
            property bool aodMusic: true
            property bool aodWeather: true
            property int aodLock: -1
            property bool aodHideWindows: true
            property bool lockOnStart: false
            property bool nightAuto: false
        }
    }

    IpcHandler {
        target: "settings"
        function toggle(): void { root.settingsOpen = !root.settingsOpen; }
        function open(): void { root.settingsOpen = true; }
        function close(): void { root.settingsOpen = false; }
    }
}
