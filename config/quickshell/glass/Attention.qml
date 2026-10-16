pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// «Игра найдена»: когда окно игры просит внимания (Dota 2 мигает окном, когда нашлась катка),
// приходит важное уведомление со звуком — даже в «Не беспокоить», а AOD сразу гаснет.
// Срабатывает, когда окно игры не в фокусе: другой стол, AOD, отошёл от компьютера.
//   qs ipc -c glass call attention test     — проверить, как это выглядит и звучит
Singleton {
    id: root

    // какие окна считать играми: класс или заголовок
    readonly property var games: [/dota/i]
    readonly property string sound: "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"
    property double last: 0

    function alert(name) {
        if (Date.now() - last < 8000) return;      // окно мигает несколько раз подряд — уведомление одно
        last = Date.now();
        Config.aodWakePing++;
        Quickshell.execDetached(["sh", "-c",
            'notify-send -u critical -a "$0" -i dota2 "$1" "$2"; '
            + '[ -f "$3" ] && command -v pw-play >/dev/null && { pw-play --volume 0.9 "$3"; pw-play --volume 0.9 "$3"; }',
            name, I18n.t("Игра найдена!", "Match found!"), I18n.t("Скорее прими катку", "Accept the match"), root.sound]);
    }

    // urgent>>адрес окна → класс и заголовок спрашиваем у Hyprland
    Process {
        id: look
        property string addr: ""
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const w = JSON.parse(text).find(c => c.address === look.addr || c.address === "0x" + look.addr);
                    if (w && root.games.some(r => r.test(w.class) || r.test(w.title))) root.alert(w.title || w.class);
                } catch (e) {}
            }
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (ev.name !== "urgent" || look.running) return;
            look.addr = ev.data.trim();
            look.running = true;
        }
    }

    IpcHandler {
        target: "attention"
        function test(): void { root.last = 0; root.alert("Dota 2"); }
    }
}
