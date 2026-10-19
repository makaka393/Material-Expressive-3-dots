pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Команды Hyprland, которые пишутся по-разному в старом (hyprland.conf) и новом (hyprland.lua)
// формате конфига: «workspace 2» против «hl.dsp.focus({ workspace = 2 })». Формат узнаём
// по журналу Hyprland при старте оболочки. При входе в систему журнал бывает ещё не дописан —
// проверяем до 10 секунд, иначе весь сеанс команды шли бы в старом формате и не срабатывали.
Singleton {
    id: root

    property bool lua: false

    function dispatch(legacy, luaCode) { Hyprland.dispatch(lua ? luaCode : legacy); }
    function workspace(w) {
        dispatch("workspace " + w, "hl.dsp.focus({ workspace = " + (typeof w === "number" ? w : '"' + w + '"') + " })");
    }

    Process {
        running: true
        command: ["sh", "-c", 'for i in $(seq 20); do grep -q "Using lua config" "${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/hyprland.log" 2>/dev/null && exit 0; sleep 0.5; done; exit 1']
        onExited: code => root.lua = code === 0
    }
}
