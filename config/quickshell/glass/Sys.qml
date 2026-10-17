pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Нагрузка на систему для шторки и виджета «Система»: процессор, память, видеокарта (NVIDIA).
// Опрашивается только пока шторка открыта (watch) — раз в 2 секунды одной командой — или пока
// на рабочем столе есть виджет (widgets > 0) — раз в 4 секунды.
Singleton {
    id: root

    property bool watch: false
    property int widgets: 0              // сколько виджетов «Система» сейчас на столе
    readonly property bool active: watch || widgets > 0
    property real cpu: 0                 // 0…1
    property int cpuTemp: -1             // °C, -1 — датчик не найден
    property real mem: 0                 // 0…1
    property real memUsedGb: 0
    property real gpu: -1                // 0…1, -1 — нет nvidia-smi
    property int gpuTemp: -1
    property real vram: 0                // 0…1
    property var prev: null              // [простой, всего] из прошлого чтения /proc/stat

    function parse(text) {
        let total = 0, avail = 0;
        for (const l of text.split("\n")) {
            const f = l.trim().split(/[\s,]+/);
            if (f[0] === "cpu") {
                const v = f.slice(1).map(Number);
                const idle = v[3] + (v[4] || 0), all = v.reduce((a, b) => a + b, 0);
                if (prev && all > prev[1]) cpu = Math.max(0, Math.min(1, 1 - (idle - prev[0]) / (all - prev[1])));
                prev = [idle, all];
            } else if (f[0] === "MemTotal:") total = Number(f[1]);
            else if (f[0] === "MemAvailable:") avail = Number(f[1]);
            else if (f[0] === "T") cpuTemp = Math.round(Number(f[1]) / 1000);
            else if (f[0] === "G" && f.length >= 5) {
                gpu = Number(f[1]) / 100;
                gpuTemp = Number(f[2]);
                vram = Number(f[4]) > 0 ? Number(f[3]) / Number(f[4]) : 0;
            }
        }
        if (total > 0) { mem = 1 - avail / total; memUsedGb = (total - avail) / 1048576; }
    }

    Process {
        id: proc
        command: ["sh", "-c", 'head -n1 /proc/stat; grep -E "^(MemTotal|MemAvailable):" /proc/meminfo; '
            + 'for f in /sys/class/hwmon/hwmon*/name; do case "$(cat "$f")" in k10temp|coretemp|zenpower) echo "T $(cat "${f%name}temp1_input")"; break;; esac; done; '
            + 'command -v nvidia-smi >/dev/null && echo "G $(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits | head -n1)"']
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
    }
    function poll() { if (!proc.running) proc.running = true; }
    onActiveChanged: if (active) { prev = null; poll(); soon.restart(); }
    // загрузка процессора — разница двух чтений, поэтому второе делаем почти сразу
    Timer { id: soon; interval: 700; onTriggered: root.poll() }
    Timer { interval: root.watch ? 2000 : 4000; repeat: true; running: root.active; onTriggered: root.poll() }
}
