pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Яркость экрана. Если монитор понимает DDC/CI (ddcutil) — меняем настоящую подсветку,
// иначе — «программную» яркость через гамму hyprsunset (Night.gamma).
Singleton {
    id: root

    property string backend: "detecting"   // "ddc" | "gamma"
    property int value: 100                // 0…100, что показывает ползунок
    property int ddcMax: 100

    function set(v) {
        value = Math.max(backend === "ddc" ? 0 : 20, Math.min(100, Math.round(v)));
        if (backend === "ddc") ddcTimer.restart();
        else if (backend === "gamma") { Config.brightness = value; Night.setGamma(value); }
    }

    // монитор с DDC? ответ вида «VCP 10 C 60 100»
    Process {
        id: detect
        running: true
        command: ["sh", "-c", "command -v ddcutil >/dev/null && timeout 6 ddcutil getvcp 10 --brief 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/VCP\s+10\s+C\s+(\d+)\s+(\d+)/);
                if (m) {
                    root.ddcMax = parseInt(m[2]) || 100;
                    root.value = Math.round(parseInt(m[1]) * 100 / root.ddcMax);
                    root.backend = "ddc";
                } else {
                    root.backend = "gamma";
                    root.value = Config.brightness;
                    Night.setGamma(Config.brightness);
                }
            }
        }
    }

    // ddcutil медленный (~0.3 с на команду) — шлём только последнее значение ползунка
    Timer { id: ddcTimer; interval: 180; onTriggered: if (!ddcSet.running) ddcSet.go(); else ddcSet.again = true }
    Process {
        id: ddcSet
        property bool again: false
        function go() {
            command = ["ddcutil", "setvcp", "10", String(Math.round(root.value * root.ddcMax / 100)), "--noverify", "--sleep-multiplier", "0.3"];
            running = true;
        }
        onExited: if (again) { again = false; go(); }
    }
}
