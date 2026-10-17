pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Блюр «как у One UI» для стиля «стекло». Пока стиль выбран, оболочка делает размытие Hyprland
// сильным и мягким; сила размытия в Hyprland одна на всю систему, так что матовыми становятся
// и окна. При уходе на M3 возвращаются значения из hyprland.conf — они сохраняются в файл
// в $XDG_RUNTIME_DIR перед первой подменой.
Singleton {
    id: root

    readonly property bool want: !Theme.m3
    // что ставим в decoration:blur (size — из настроек, «Сила размытия»)
    readonly property string preset: "size=" + Math.max(1, Math.round(Config.glassBlur))
        + " passes=3 vibrancy=0.24 vibrancy_darkness=0.2 noise=0.03 brightness=0.9 contrast=0.95"
    readonly property string target: want ? preset : ""
    property string done: "?"            // что применено; «?» при старте — применить или вернуть заново
    property bool reloaded: false        // hyprland перечитал конфиг: сохранённые значения устарели

    readonly property string stateFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/glass-blur-saved"

    // $0 — файл, $1 — «ключ=значение …». Сначала запоминаем текущие значения (если ещё не запомнили);
    // не удалось прочитать хоть одно — ничего не трогаем.
    // hset: работает и со старым hyprland.conf, и с hyprland.lua
    readonly property string applyCmd: 'hset() { [ "$(hyprctl keyword "$1" "$2" 2>&1)" = ok ] && return 0; p=$(printf %s "$1" | sed "s/:/={/g"); c=$(printf %s "$1" | tr -cd : | sed "s/:/}/g"); hyprctl eval "hl.config({$p=$2$c})" >/dev/null; }; '
        + 'f="$0"; if [ ! -s "$f" ]; then t="$f.tmp"; : > "$t"; for kv in $1; do k=${kv%%=*}; '
        + 'v=$(hyprctl getoption "decoration:blur:$k" -j | sed -n \'s/.*"\\(int\\|float\\)": *\\([0-9.]*\\).*/\\2/p\'); '
        + '[ -n "$v" ] || { rm -f "$t"; exit 1; }; echo "$k $v" >> "$t"; done; mv "$t" "$f"; fi; '
        + 'for kv in $1; do hset "decoration:blur:${kv%%=*}" "${kv#*=}"; done'
    readonly property string restoreCmd: 'hset() { [ "$(hyprctl keyword "$1" "$2" 2>&1)" = ok ] && return 0; p=$(printf %s "$1" | sed "s/:/={/g"); c=$(printf %s "$1" | tr -cd : | sed "s/:/}/g"); hyprctl eval "hl.config({$p=$2$c})" >/dev/null; }; '
        + 'f="$0"; [ -s "$f" ] || exit 0; '
        + 'while read -r k v; do [ -n "$v" ] && hset "decoration:blur:$k" "$v"; done < "$f"; rm -f "$f"'

    onTargetChanged: sync()
    Component.onCompleted: sync()

    // команды идут строго по одной
    function sync() {
        if (proc.running || done === target) return;
        proc.t = target;
        const cmd = (reloaded ? 'rm -f "$0"; ' : "") + (target !== "" ? applyCmd : restoreCmd);
        reloaded = false;
        proc.command = ["sh", "-c", cmd, stateFile, target];
        proc.running = true;
    }
    Process {
        id: proc
        property string t: ""
        // следующую команду запускаем, когда процесс уже точно остановлен (running === false)
        onRunningChanged: if (!running) { root.done = t; root.sync(); }
    }

    // после перезагрузки конфига Hyprland размытие снова как в файле — ставим своё заново
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (ev.name !== "configreloaded") return;
            root.reloaded = true;
            root.done = "?";
            root.sync();
        }
    }
}
