pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

// Экран блокировки: состояние, проверка пароля и команды. Сам замок сессии и то, что на
// экране, — в Lock.qml и LockSurface.qml.
//   qs ipc -c glass call lock lock | preview | unlock | test
// Пароль проверяет pam_unix по своему конфигу pam/password.conf — без системного счётчика
// неудачных попыток, так что опечатки не блокируют учётную запись.
// unlock — запасной выход без пароля для того, кто уже вошёл под этим пользователем
// (например, с соседнего tty); так же устроен SIGUSR1 у hyprlock.
Singleton {
    id: root

    property bool locked: false          // настоящий замок сессии
    property bool preview: false         // показать экран без блокировки
    readonly property bool shown: locked || preview

    property string text: ""             // то, что набрано
    property bool checking: false
    property bool failed: false
    property int tries: 0
    property bool testing: false
    property bool wake: false            // заперли, уходя с AOD: экран «просыпается» из AOD, без заставки

    // обои для экрана блокировки — узнаём заранее, чтобы при блокировке не мелькал чёрный экран
    property string wallFile: ""
    property string frameFile: ""
    function resolveWall() { if (!wallProc.running) wallProc.running = true; }
    Process {
        id: wallProc
        running: true
        command: ["sh", "-c", 'w=$(readlink -f "$HOME/.cache/matugen/wallpaper"); echo "$w"; '
            + 'case "$w" in *.[mM][pP]4|*.[wW][eE][bB][mM]|*.[mM][kK][vV]|*.[mM][oO][vV]|*.[gG][iI][fF]|*.[wW][eE][bB][pP]) echo "$HOME/.cache/matugen/frame.png";; *) echo "$w";; esac']
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                root.wallFile = l[0] || "";
                root.frameFile = l[1] || "";
            }
        }
    }
    // обои сменили — путь обновится к следующей блокировке
    FileView {
        path: Quickshell.env("HOME") + "/.cache/matugen/colors.json"
        watchChanges: true
        printErrors: false
        onFileChanged: root.resolveWall()
    }

    // Файлы-метки лежат в папке текущего экземпляра Hyprland: новый вход — новые метки.
    readonly property string inst: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/hypr/" + Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
    readonly property string lockedFile: inst + "/glass-locked"       // экран заперт (переживает сбой и перезапуск оболочки)
    readonly property string startedFile: inst + "/glass-started"     // оболочка в этом сеансе уже запускалась

    function reset() { text = ""; checking = false; failed = false; }
    function lock(fromAod) {
        if (locked) return;
        wake = fromAod === true;
        preview = false;
        reset();
        Quickshell.execDetached(["touch", lockedFile]);
        locked = true;
    }
    function unlock() {
        if (pam.active) pam.abort();
        Quickshell.execDetached(["rm", "-f", lockedFile]);
        locked = false;
        preview = false;
        testing = false;
        wake = false;
        reset();
    }
    function submit() {
        if (checking || text === "") return;
        failed = false;
        checking = true;
        if (!pam.start()) fail();
    }
    function fail() {
        checking = false;
        tries++;
        failed = true;
        text = "";
        failReset.restart();
    }

    PamContext {
        id: pam
        configDirectory: "pam"
        config: "password.conf"
        onPamMessage: if (responseRequired) respond(root.text)
        onCompleted: result => {
            if (result === PamResult.Success) root.unlock();
            else root.fail();
        }
        onError: root.fail()
    }
    Timer { id: failReset; interval: 2400; onTriggered: root.failed = false }
    // «test» — настоящая блокировка, которая сама снимается через 15 секунд
    Timer { id: testTimer; interval: 15000; onTriggered: if (root.testing) root.unlock() }

    IpcHandler {
        target: "lock"
        function lock(): void { root.lock(); }
        function preview(): void { if (!root.locked) { root.reset(); root.preview = true; } }
        function unlock(): void { root.unlock(); }
        function test(): void { root.testing = true; testTimer.restart(); root.lock(); }
        // то же, но как после AOD — проверить «пробуждение»
        function testWake(): void { root.testing = true; testTimer.restart(); root.lock(true); }
    }

    // При старте оболочки запираем экран в двух случаях:
    //  • он был заперт, а оболочка упала, перезапустилась или перечитала конфиг — композитор
    //    всё это время держит экран закрытым, и замок нужно перехватить заново
    //    (для этого Hyprland нужен misc:allow_session_lock_restore);
    //  • это первый запуск за сеанс и в settings.json включён lockOnStart — экран блокировки
    //    вместо экрана входа. Настройки читаем прямо из файла: запереть нужно как можно раньше.
    Process {
        running: true
        command: ["sh", "-c", 'hyprctl keyword misc:allow_session_lock_restore 1 >/dev/null 2>&1; '
            + '[ -e "$0" ] && exit 0; [ -e "$1" ] && exit 1; : > "$1"; grep -q \'"lockOnStart": *true\' "$2"',
            root.lockedFile, root.startedFile, Config.dir + "/settings.json"]
        onExited: code => { if (code === 0) root.lock(); }
    }
}
