pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Wi-Fi через NetworkManager (nmcli): состояние для плитки в шторке, список сетей,
// подключение (с паролем, если сеть новая), «забыть». Обновляется по событиям `nmcli monitor`.
Singleton {
    id: root

    property bool available: true       // есть nmcli
    property bool hasWifi: false        // есть Wi-Fi адаптер
    property bool radio: false          // радио Wi-Fi включено
    property bool connected: false
    property string ssid: ""
    property int signal: 0
    property bool ethernet: false       // подключён кабель
    property string ethName: ""
    property var networks: []           // [{ ssid, signal, secure, active, known }]
    property bool scanning: false
    property string connecting: ""      // к какой сети подключаемся
    property string failed: ""          // к какой не вышло
    property bool typing: false         // вводим пароль — бару нужна клавиатура
    property bool watch: false          // шторка открыта — обновляемся чаще

    readonly property string icon: !available || !hasWifi ? (ethernet ? "lan" : "signal_wifi_off")
                                 : !radio ? "wifi_off"
                                 : connected ? (signal >= 75 ? "network_wifi" : signal >= 50 ? "network_wifi_3_bar" : signal >= 25 ? "network_wifi_2_bar" : "network_wifi_1_bar")
                                 : ethernet ? "lan" : "signal_wifi_0_bar"

    function sigIcon(s) { return s >= 75 ? "network_wifi" : s >= 50 ? "network_wifi_3_bar" : s >= 25 ? "network_wifi_2_bar" : "network_wifi_1_bar"; }

    // поля nmcli -t: разделитель «:», внутри значения «\:»
    function fields(line) {
        const out = [];
        let cur = "";
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (c === "\\" && i + 1 < line.length) { cur += line[++i]; }
            else if (c === ":") { out.push(cur); cur = ""; }
            else cur += c;
        }
        out.push(cur);
        return out;
    }

    function parse(text) {
        if (text.trim() === "NONMCLI") { available = false; return; }
        available = true;
        const parts = text.split("\n---\n");
        const dev = (parts[0] || "").split("\n").filter(l => l);
        const radioState = (parts[1] || "").trim();
        const list = (parts[2] || "").split("\n").filter(l => l);
        const conns = (parts[3] || "").split("\n").filter(l => l);

        let wifi = false, wConn = "", wOn = false, eth = false, eName = "";
        for (const l of dev) {
            const f = fields(l);
            if (f[0] === "wifi") { wifi = true; if (f[1] === "connected") { wOn = true; wConn = f[2]; } }
            else if (f[0] === "ethernet" && f[1] === "connected") { eth = true; eName = f[2]; }
        }
        const known = conns.map(fields).filter(f => f[1] === "802-11-wireless").map(f => f[0]);

        const map = {};
        for (const l of list) {
            const f = fields(l);
            const name = f[3] || "";
            if (name === "") continue;
            const n = { ssid: name, signal: parseInt(f[1]) || 0, secure: !!f[2] && f[2] !== "--", active: f[0] === "*", known: known.indexOf(name) >= 0 };
            const old = map[name];
            if (!old || n.active || (!old.active && n.signal > old.signal)) map[name] = n;
        }
        const nets = Object.keys(map).map(k => map[k]);
        nets.sort((a, b) => (b.active - a.active) || (b.known - a.known) || (b.signal - a.signal));

        hasWifi = wifi;
        root.radio = radioState === "enabled";
        connected = wOn;
        const act = nets.find(n => n.active);
        ssid = act ? act.ssid : wConn;
        signal = act ? act.signal : 0;
        ethernet = eth;
        ethName = eName;
        networks = nets;
    }

    function refresh() { if (!stat.running) stat.running = true; else again = true; }
    property bool again: false
    Process {
        id: stat
        command: ["sh", "-c", "command -v nmcli >/dev/null || { echo NONMCLI; exit 0; }; "
            + "nmcli -t -f TYPE,STATE,CONNECTION device; echo ---; nmcli radio wifi; echo ---; "
            + "nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID device wifi list --rescan no; echo ---; "
            + "nmcli -t -f NAME,TYPE connection show"]
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
        onExited: if (root.again) { root.again = false; running = true; }
    }

    // события NetworkManager → обновиться (с задержкой, их приходит пачка)
    Process {
        id: mon
        running: root.available
        command: ["nmcli", "monitor"]
        stdout: SplitParser { onRead: soon.restart() }
        onExited: monRestart.restart()
    }
    Timer { id: monRestart; interval: 5000; onTriggered: if (root.available) mon.running = true }
    Timer { id: soon; interval: 400; onTriggered: root.refresh() }
    Timer { interval: root.watch ? 8000 : 60000; repeat: true; running: true; triggeredOnStart: true; onTriggered: root.refresh() }

    // ── действия
    function setEnabled(on) { run(["nmcli", "radio", "wifi", on ? "on" : "off"]); radio = on; }
    function rescan() {
        if (scanning) return;
        scanning = true;
        run(["nmcli", "device", "wifi", "rescan"]);
        scanDone.restart();
    }
    Timer { id: scanDone; interval: 3500; onTriggered: { root.scanning = false; root.refresh(); } }

    function connect(n, password) {
        failed = "";
        connecting = n.ssid;
        if (n.known && !password) conn.command = ["nmcli", "connection", "up", "id", n.ssid];
        else if (password) conn.command = ["sh", "-c", 'nmcli connection delete id "$1" >/dev/null 2>&1; nmcli device wifi connect "$1" password "$2" || { nmcli connection delete id "$1" >/dev/null 2>&1; exit 1; }', "sh", n.ssid, password];
        else conn.command = ["nmcli", "device", "wifi", "connect", n.ssid];
        conn.running = true;
    }
    function disconnect(n) { run(["nmcli", "connection", "down", "id", n.ssid]); }
    function forget(n) { run(["nmcli", "connection", "delete", "id", n.ssid]); }

    Process {
        id: conn
        onExited: code => {
            if (code !== 0) root.failed = root.connecting;
            root.connecting = "";
            root.refresh();
        }
    }
    function run(cmd) { Quickshell.execDetached(cmd); soon.restart(); }
}
