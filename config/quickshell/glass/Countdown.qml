pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Таймер обратного отсчёта в острове: пока идёт — пилюля с остатком слева от часов
// (клик — отмена), по окончании — всплывашка. Запуск: в лаунчере «timer 5m» / «таймер 10 мин чай»
// или  qs ipc -c glass call timer start 300 "Чай" | add 60 | stop
Singleton {
    id: root

    property real endAt: 0               // момент окончания, мс; 0 — таймер не идёт
    property int total: 0                // на сколько заведён, с
    property int left: 0                 // осталось, с
    property string label: ""
    readonly property bool running: endAt > 0
    readonly property real frac: total > 0 ? Math.max(0, Math.min(1, left / total)) : 0     // 1 → 0

    function start(secs, name) {
        if (secs <= 0) return;
        total = secs;
        label = name || "";
        endAt = Date.now() + secs * 1000;
        tick();
    }
    function stop() { endAt = 0; left = 0; }
    function add(secs) {
        if (!running) return;
        endAt += secs * 1000;
        total = Math.max(1, total + secs);
        tick();
    }
    function tick() {
        if (!running) return;
        left = Math.max(0, Math.ceil((endAt - Date.now()) / 1000));
        if (left > 0) return;
        const name = label;
        stop();
        Activity.show({ icon: "timer", title: I18n.t("Таймер", "Timer"), sub: name !== "" ? name : I18n.t("Время вышло", "Time's up") }, 7000);
        Quickshell.execDetached(["sh", "-c", "command -v canberra-gtk-play >/dev/null && exec canberra-gtk-play -i complete"]);
    }

    // 75 → «1:15», 3700 → «1:01:40»
    function fmt(s) {
        const p = n => (n < 10 ? "0" : "") + n;
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), x = s % 60;
        return h > 0 ? h + ":" + p(m) + ":" + p(x) : m + ":" + p(x);
    }
    // «5» (минут), «90s», «1h 30m», «1:30», «10 мин чай» → { secs, label }
    function parse(text) {
        let t = text.trim(), secs = 0;
        let m = t.match(/^(\d+):(\d{1,2})(?::(\d{1,2}))?\s*/);
        if (m) {
            secs = m[3] !== undefined ? (+m[1]) * 3600 + (+m[2]) * 60 + (+m[3]) : (+m[1]) * 60 + (+m[2]);
            t = t.slice(m[0].length);
        } else {
            const re = /^(\d+(?:[.,]\d+)?)\s*(hours?|hr|h|час[а-яё]*|ч|min[a-z]*|m|мин[а-яё]*|м|sec[a-z]*|s|сек[а-яё]*|с)?(?![a-zа-яё])\s*/i;
            while ((m = t.match(re)) !== null && m[0].length > 0) {
                const u = (m[2] || "m").toLowerCase();
                secs += parseFloat(m[1].replace(",", ".")) * (/^(h|ч)/.test(u) ? 3600 : /^(s|с)/.test(u) ? 1 : 60);
                t = t.slice(m[0].length);
            }
        }
        return { secs: Math.round(secs), label: t.trim() };
    }

    Timer { interval: 500; repeat: true; running: root.running; onTriggered: root.tick() }

    IpcHandler {
        target: "timer"
        function start(seconds: int, label: string): void { root.start(seconds, label); }
        function add(seconds: int): void { root.add(seconds); }
        function stop(): void { root.stop(); }
    }
}
