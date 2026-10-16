pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Спектр звука с выхода (cava): полосы 0…1 — чтобы эквалайзеры двигались под настоящую музыку.
// cava работает, только пока спектр кто-то показывает (users > 0). Нет cava или звук не
// ловится — live остаётся false, и виджеты играют свою обычную анимацию.
Singleton {
    id: root

    property int users: 0                // сколько виджетов сейчас показывают спектр
    readonly property int bars: 12
    property var values: []              // bars значений 0…1, от низких частот к высоким
    property bool live: false            // идут ненулевые данные

    readonly property string conf: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/glass-cava.conf"

    // средний уровень полос from…to (включительно)
    function level(from, to) {
        if (values.length < bars) return 0;
        let s = 0;
        for (let i = from; i <= to; i++) s += values[i];
        return s / (to - from + 1);
    }

    Process {
        id: proc
        running: root.users > 0
        command: ["sh", "-c", 'command -v cava >/dev/null || exit 0; '
            + 'printf "[general]\\nbars = %s\\nframerate = 30\\n[output]\\nmethod = raw\\nraw_target = /dev/stdout\\ndata_format = ascii\\nascii_max_range = 100\\n[smoothing]\\nnoise_reduction = 35\\n" "$1" > "$0"; '
            + 'exec cava -p "$0"', root.conf, String(root.bars)]
        stdout: SplitParser {
            onRead: line => {
                const p = line.split(";");
                if (p.length < root.bars) return;
                const v = new Array(root.bars);
                let any = false;
                for (let i = 0; i < root.bars; i++) { v[i] = Math.min(1, Number(p[i]) / 100); if (v[i] > 0.02) any = true; }
                root.values = v;
                if (any) { root.live = true; quiet.restart(); }
            }
        }
        onRunningChanged: if (!running) { root.values = []; root.live = false; }
    }
    // две секунды тишины — считаем, что звука нет
    Timer { id: quiet; interval: 2000; onTriggered: root.live = false }
}
