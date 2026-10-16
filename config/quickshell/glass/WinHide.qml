pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Прячет все окна на время AOD: прозрачность окон Hyprland уводится в ноль (окна плавно
// гаснут вместе с рамками и тенями), при выходе возвращаются прежние значения.
// Прежние значения лежат в файле в $XDG_RUNTIME_DIR: если оболочка упала или её перезапустили,
// пока окна скрыты, при следующем старте они вернутся сами.
Singleton {
    id: root

    property bool hide: false            // чего хотим (ставит Aod)
    property bool applied: true          // что применено; true при старте — чтобы первым делом вернуть окна после сбоя

    readonly property string stateFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/glass-aod-opacity"
    readonly property string keys: "active_opacity inactive_opacity fullscreen_opacity"

    // сохраняем текущие значения (если ещё не сохранены) и только потом гасим;
    // не удалось прочитать хоть одно — ничего не трогаем
    readonly property string hideCmd: 'f="$0"; if [ ! -s "$f" ]; then t="$f.tmp"; : > "$t"; for k in $1; do '
        + 'v=$(hyprctl getoption "decoration:$k" -j | sed -n \'s/.*"float": *\\([0-9.]*\\).*/\\1/p\'); '
        + '[ -n "$v" ] || { rm -f "$t"; exit 1; }; echo "$k $v" >> "$t"; done; mv "$t" "$f"; fi; '
        + 'for k in $1; do hyprctl keyword "decoration:$k" 0 >/dev/null; done'
    readonly property string showCmd: 'f="$0"; [ -s "$f" ] || exit 0; '
        + 'while read -r k v; do [ -n "$v" ] && hyprctl keyword "decoration:$k" "$v" >/dev/null; done < "$f"; rm -f "$f"'

    onHideChanged: sync()
    Component.onCompleted: sync()

    // команды идут строго по одной: быстрое «вошёл-вышел» не должно оставить окна невидимыми
    function sync() {
        if (proc.running || applied === hide) return;
        proc.target = hide;
        proc.command = ["sh", "-c", hide ? hideCmd : showCmd, stateFile, keys];
        proc.running = true;
    }
    Process {
        id: proc
        property bool target: false
        // следующую команду запускаем, когда процесс уже точно остановлен (running === false)
        onRunningChanged: if (!running) { root.applied = target; root.sync(); }
    }
}
