pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Bluetooth через bluetoothctl: вкл/выкл, сопряжённые и найденные устройства,
// подключение (новое — сопряжение + доверие + подключение), заряд наушников.
Singleton {
    id: root

    property bool available: true       // есть bluetoothctl и адаптер
    property bool powered: false
    property bool scanning: false
    property var devices: []            // [{ mac, name, paired, connected, icon, battery }]
    property string busy: ""            // mac, с которым сейчас что-то делаем
    property string failed: ""
    property bool watch: false

    readonly property var connectedList: devices.filter(d => d.connected)
    readonly property string icon: !available || !powered ? "bluetooth_disabled" : connectedList.length > 0 ? "bluetooth_connected" : "bluetooth"

    function iconFor(i) {
        if (/headset|headphone/.test(i)) return "headphones";
        if (/audio/.test(i)) return "speaker";
        if (/mouse/.test(i)) return "mouse";
        if (/keyboard/.test(i)) return "keyboard";
        if (/gaming|joystick/.test(i)) return "sports_esports";
        if (/phone/.test(i)) return "smartphone";
        if (/computer/.test(i)) return "computer";
        if (/watch/.test(i)) return "watch";
        return "bluetooth";
    }

    function parse(text) {
        if (text.trim() === "NOBT") { available = false; return; }
        const parts = text.split("\n---\n");
        const show = parts[0] || "";
        available = /Powered:/.test(show);
        powered = /Powered:\s*yes/.test(show);
        const paired = (parts[1] || "").split("\n").map(l => (l.match(/^Device ([0-9A-F:]{17})/i) || [])[1]).filter(x => x);
        const all = (parts[2] || "").split("\n").map(l => l.match(/^Device ([0-9A-F:]{17}) (.*)$/i)).filter(x => x);
        // подробности: @MAC, затем строки info
        const info = {};
        let cur = null;
        for (const l of (parts[3] || "").split("\n")) {
            if (l.startsWith("@")) { cur = l.slice(1).trim(); info[cur] = { icon: "", battery: -1, connected: false }; continue; }
            if (!cur) continue;
            let m;
            if ((m = l.match(/Icon:\s*(\S+)/))) info[cur].icon = m[1];
            else if ((m = l.match(/Battery Percentage:.*\((\d+)\)/))) info[cur].battery = parseInt(m[1]);
            else if (/Connected:\s*yes/.test(l)) info[cur].connected = true;
        }
        const out = [];
        for (const m of all) {
            const mac = m[1].toUpperCase(), name = m[2].trim();
            const isPaired = paired.indexOf(mac) >= 0;
            // безымянные найденные устройства (вместо имени — тот же адрес) не показываем
            if (!isPaired && (/^([0-9A-F]{2}[-:]){5}[0-9A-F]{2}$/i.test(name) || name === "")) continue;
            const inf = info[mac] || { icon: "", battery: -1, connected: false };
            out.push({ mac: mac, name: name, paired: isPaired, connected: inf.connected, icon: iconFor(inf.icon), battery: inf.battery });
        }
        out.sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name));
        devices = out.slice(0, 30);
    }

    function refresh() { if (!stat.running) stat.running = true; }
    Process {
        id: stat
        // без адаптера или без bluetoothd bluetoothctl ждёт вечно — сначала проверяем, show — с таймаутом
        command: ["sh", "-c", 'command -v bluetoothctl >/dev/null && [ -d /sys/class/bluetooth ] || { echo NOBT; exit 0; }; '
            + 's=$(timeout 3 bluetoothctl show 2>/dev/null | grep -E "Powered:|Discovering:"); [ -n "$s" ] || { echo NOBT; exit 0; }; '
            + 'echo "$s"; echo ---; '
            + 'bluetoothctl devices Paired 2>/dev/null; echo ---; '
            + 'bluetoothctl devices 2>/dev/null; echo ---; '
            + 'for m in $(bluetoothctl devices Paired 2>/dev/null | cut -d" " -f2 | head -15); do echo "@$m"; '
            + 'bluetoothctl info "$m" 2>/dev/null | grep -E "Icon:|Battery Percentage:|Connected:"; done']
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
    }
    Timer {
        interval: root.scanning ? 2000 : root.watch ? 4000 : root.available ? 30000 : 300000   // без адаптера — раз в 5 минут
        repeat: true; running: true; triggeredOnStart: true
        onTriggered: root.refresh()
    }
    Timer { id: soon; interval: 700; onTriggered: root.refresh() }

    // ── действия
    function setPowered(on) {
        if (!available) return;
        powered = on;
        Quickshell.execDetached(["sh", "-c", on ? "rfkill unblock bluetooth 2>/dev/null; sleep 0.3; timeout 10 bluetoothctl power on" : "timeout 10 bluetoothctl power off"]);
        if (!on) scanning = false;
        soon.restart();
    }
    function scan() {
        if (scanning || !powered) return;
        scanning = true;
        scanProc.running = true;
    }
    Process {
        id: scanProc
        command: ["bluetoothctl", "--timeout", "15", "scan", "on"]
        onExited: { root.scanning = false; root.refresh(); }
    }

    function toggle(d) {
        failed = "";
        busy = d.mac;
        if (d.connected) act.command = ["bluetoothctl", "disconnect", d.mac];
        else if (d.paired) act.command = ["bluetoothctl", "--timeout", "15", "connect", d.mac];
        else act.command = ["sh", "-c", 'bluetoothctl --timeout 20 pair "$1" && bluetoothctl trust "$1" && bluetoothctl --timeout 15 connect "$1"', "sh", d.mac];
        act.running = true;
    }
    function forget(d) { Quickshell.execDetached(["bluetoothctl", "remove", d.mac]); soon.restart(); }

    Process {
        id: act
        property int code: 0
        stdout: StdioCollector { id: actOut }
        onExited: c => { code = c; finish.restart(); }
    }
    // текст и код выхода приходят в любом порядке — разбираем чуть позже
    Timer {
        id: finish
        interval: 150
        onTriggered: {
            // bluetoothctl часто возвращает 0 даже при ошибке — смотрим и на текст
            if (act.code !== 0 || /Failed|not available|Error/i.test(actOut.text)) root.failed = root.busy;
            root.busy = "";
            root.refresh();
        }
    }
}
