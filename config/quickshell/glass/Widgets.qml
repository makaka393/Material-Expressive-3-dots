pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Виджеты на рабочем столе: что стоит и где (клетки сетки), режим правки и каталог.
// Раскладка — в ~/.config/glass/widgets.json. Рисует их Desktop.qml.
// Список — ListModel, а не массив: добавление или перенос одного виджета не пересоздаёт остальные.
//   qs ipc -c glass call widgets edit | done | toggle | add <тип> | reset
Singleton {
    id: root

    // каталог: размер в клетках сетки
    readonly property var catalog: [
        { type: "glance",   w: 4, h: 1, icon: "wb_sunny",          ru: "Коротко о главном", en: "At a glance" },
        { type: "clock",    w: 2, h: 2, icon: "schedule",          ru: "Часы",              en: "Clock" },
        { type: "weather",  w: 2, h: 2, icon: "partly_cloudy_day", ru: "Погода",            en: "Weather" },
        { type: "music",    w: 4, h: 2, icon: "music_note",        ru: "Музыка",            en: "Music" },
        { type: "calendar", w: 3, h: 3, icon: "calendar_month",    ru: "Календарь",         en: "Calendar" }
    ]
    function spec(type) { return catalog.find(c => c.type === type) || catalog[0]; }

    property ListModel model: ListModel {}     // роли: wid, type, gx, gy
    property bool editing: false
    property string leaving: ""          // wid виджета, который сейчас уезжает (анимация удаления)
    property string fresh: ""            // wid только что добавленного (анимация появления)
    property int cols: 20                // размер сетки — сообщает Desktop по своему экрану
    property int rows: 10
    property bool loaded: false

    readonly property var defaults: [
        { wid: "w1", type: "glance", gx: 0, gy: 0 },
        { wid: "w2", type: "clock", gx: 0, gy: 1 },
        { wid: "w3", type: "weather", gx: 2, gy: 1 }
    ]

    function at(i) { return model.get(i); }
    function indexOf(wid) {
        for (let i = 0; i < model.count; i++) if (model.get(i).wid === wid) return i;
        return -1;
    }

    // ── занятость клеток
    function fits(type, x, y, skip) {
        const s = spec(type);
        if (x < 0 || y < 0 || x + s.w > cols || y + s.h > rows) return false;
        for (let i = 0; i < model.count; i++) {
            const it = model.get(i);
            if (it.wid === skip || it.wid === leaving) continue;
            const o = spec(it.type);
            if (x < it.gx + o.w && it.gx < x + s.w && y < it.gy + o.h && it.gy < y + s.h) return false;
        }
        return true;
    }
    function freeSpot(type) {
        for (let y = 0; y < rows; y++)
            for (let x = 0; x < cols; x++)
                if (fits(type, x, y, "")) return { x: x, y: y };
        return null;
    }

    // ── правки
    function add(type) {
        const p = freeSpot(type);
        if (!p) {
            Activity.show({ icon: "grid_off", title: I18n.t("Нет места", "No room"), sub: I18n.t("Убери или подвинь виджеты", "Remove or move widgets") }, 2200);
            return;
        }
        let n = 1;
        while (indexOf("w" + n) >= 0) n++;
        fresh = "w" + n;
        model.append({ wid: fresh, type: type, gx: p.x, gy: p.y });
        save();
    }
    function remove(wid) {
        if (leaving !== "") return;
        leaving = wid;
        dropTimer.restart();
    }
    Timer {
        id: dropTimer
        interval: 300
        onTriggered: {
            const i = root.indexOf(root.leaving);
            if (i >= 0) root.model.remove(i);
            root.leaving = "";
            root.save();
        }
    }
    function move(wid, x, y) {
        const i = indexOf(wid);
        if (i < 0 || !fits(model.get(i).type, x, y, wid)) return false;
        model.setProperty(i, "gx", x);
        model.setProperty(i, "gy", y);
        save();
        return true;
    }
    function fill(list) {
        model.clear();
        for (const it of list) model.append({ wid: it.wid, type: it.type, gx: it.gx, gy: it.gy });
    }
    function reset() { fill(defaults); save(); }

    // ── файл
    FileView {
        id: file
        path: Config.dir + "/widgets.json"
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.fill((d.items || []).filter(i => i && i.id && root.catalog.some(c => c.type === i.type))
                          .map(i => ({ wid: i.id, type: i.type, gx: i.x | 0, gy: i.y | 0 })));
            } catch (e) { root.fill(root.defaults); }
            root.loaded = true;
        }
        onLoadFailed: { root.fill(root.defaults); root.loaded = true; root.save(); }
    }
    // запись — с короткой задержкой: перенос, добавление и удаление подряд дают одну запись
    function save() { if (loaded) saveTimer.restart(); }
    Timer { id: saveTimer; interval: 400; onTriggered: root.write() }
    function write() {
        const items = [];
        for (let i = 0; i < model.count; i++) {
            const it = model.get(i);
            items.push({ id: it.wid, type: it.type, x: it.gx, y: it.gy });
        }
        file.setText(JSON.stringify({ version: 1, items: items }, null, 2) + "\n");
    }

    IpcHandler {
        target: "widgets"
        function edit(): void { root.editing = true; }
        function done(): void { root.editing = false; }
        function toggle(): void { root.editing = !root.editing; }
        function add(type: string): void { root.add(type); }
        function reset(): void { root.reset(); }
    }
}
