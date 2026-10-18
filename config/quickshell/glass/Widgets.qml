pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Виджеты на рабочем столе: что стоит, где и какого размера (в клетках сетки), режим правки и каталог.
// Раскладка — в ~/.config/glass/widgets.json. Рисует их Desktop.qml, сами виджеты — W*.qml.
// Список — ListModel, а не массив: правка одного виджета не пересоздаёт остальные.
//   qs ipc -c glass call widgets edit | done | toggle | add <тип> | remove <id> | reset | list
//   qs ipc -c glass call widgets move <id> <x> <y> | resize <id> <w> <h>
Singleton {
    id: root

    // каталог: размер по умолчанию и пределы в клетках; tone и bg — цвет темы и подложка по умолчанию
    // (каждый виджет можно перенастроить: «Настроить» в режиме правки); menu — свои пункты меню;
    // variants — что предлагает каталог (размер, свои настройки и подпись), первый — по умолчанию
    readonly property var catalog: [
        { type: "clock", cat: "time", w: 2, h: 2, minW: 2, minH: 1, maxW: 6, maxH: 4, tone: "neutral", bg: "blur", icon: "schedule", ru: "Часы", en: "Clock",
          variants: [{ w: 2, h: 2, extra: { face: "analog" },   ru: "Стрелки",  en: "Analog" },
                     { w: 2, h: 2, extra: { face: "bubble" },   ru: "Формы",    en: "Shapes" },
                     { w: 2, h: 2, extra: { face: "orbit" },    ru: "Орбита",   en: "Orbit" },
                     { w: 2, h: 2, extra: { face: "planets" },  ru: "Планеты",  en: "Planets" },
                     { w: 3, h: 2, extra: { face: "horizon" },  ru: "Горизонт", en: "Horizon" },
                     { w: 4, h: 2, extra: { face: "dots" },     ru: "Точки",    en: "Dots" },
                     { w: 4, h: 2, extra: { face: "segments" }, ru: "Сегменты", en: "Segments" }] },
        { type: "glance", cat: "time", w: 4, h: 1, minW: 3, minH: 1, maxW: 8, maxH: 2, tone: "primary", bg: "none", icon: "wb_sunny", ru: "Коротко о главном", en: "At a glance",
          variants: [{ w: 4, h: 1, ru: "Строка", en: "Line" }, { w: 6, h: 2, ru: "Крупно, с закатом", en: "Large, with sunset" }] },
        { type: "calendar", cat: "time", w: 3, h: 3, minW: 2, minH: 2, maxW: 4, maxH: 4, tone: "neutral", bg: "blur", icon: "calendar_month", ru: "Календарь", en: "Calendar",
          variants: [{ w: 2, h: 2, ru: "Сегодня", en: "Today" }, { w: 3, h: 3, ru: "Месяц", en: "Month" }, { w: 4, h: 4, ru: "Месяц крупно", en: "Large month" }] },
        { type: "progress", cat: "time", w: 2, h: 2, minW: 2, minH: 2, maxW: 6, maxH: 3, tone: "primary", bg: "blur", icon: "data_usage", ru: "День и год", en: "Day & year",
          variants: [{ w: 2, h: 2, extra: { mode: "day" }, ru: "День", en: "Day" }, { w: 2, h: 2, extra: { mode: "month" }, ru: "Месяц", en: "Month" },
                     { w: 4, h: 2, extra: { mode: "year" }, ru: "Год", en: "Year" }] },
        { type: "weather", cat: "weather", w: 2, h: 2, minW: 2, minH: 1, maxW: 6, maxH: 3, tone: "secondary", bg: "blur", icon: "partly_cloudy_day", ru: "Погода", en: "Weather",
          variants: [{ w: 2, h: 1, ru: "Мини", en: "Mini" }, { w: 2, h: 2, ru: "Сейчас", en: "Now" },
                     { w: 4, h: 2, ru: "По часам", en: "Hourly" }, { w: 4, h: 3, ru: "По часам и дням", en: "Hourly and daily" }] },
        { type: "forecast", cat: "weather", w: 4, h: 2, minW: 3, minH: 2, maxW: 8, maxH: 3, tone: "tertiary", bg: "blur", icon: "show_chart", ru: "Прогноз", en: "Forecast",
          variants: [{ w: 4, h: 2, ru: "Кривая на полдня", en: "Half-day curve" }, { w: 6, h: 3, ru: "Кривая и неделя", en: "Curve and week" }] },
        { type: "sun", cat: "weather", w: 2, h: 2, minW: 2, minH: 1, maxW: 4, maxH: 2, tone: "tertiary", bg: "blur", icon: "wb_twilight", ru: "Солнце", en: "Sun",
          variants: [{ w: 2, h: 1, ru: "Ближайшее событие", en: "Next event" }, { w: 2, h: 2, ru: "Дуга дня", en: "Day arc" }, { w: 4, h: 2, ru: "Широкая дуга", en: "Wide arc" }] },
        { type: "music", cat: "media", w: 4, h: 2, minW: 2, minH: 1, maxW: 6, maxH: 3, tone: "tertiary", bg: "blur", icon: "music_note", ru: "Музыка", en: "Music",
          variants: [{ w: 4, h: 1, ru: "Мини-плеер", en: "Mini player" }, { w: 2, h: 2, ru: "Обложка", en: "Cover" },
                     { w: 4, h: 2, ru: "Плеер", en: "Player" }, { w: 4, h: 3, ru: "Большая обложка", en: "Large cover" }] },
        { type: "photo", cat: "media", w: 2, h: 2, minW: 2, minH: 2, maxW: 6, maxH: 4, tone: "secondary", bg: "none", icon: "photo", ru: "Фото", en: "Photo",
          menu: [{ id: "next", icon: "skip_next", ru: "Следующее фото", en: "Next photo" }],
          variants: [{ w: 2, h: 2, extra: { shape: "squircle" }, ru: "Скруглённое", en: "Rounded" },
                     { w: 2, h: 2, extra: { shape: "cookie" },   ru: "Печенька",   en: "Cookie" },
                     { w: 2, h: 2, extra: { shape: "clover" },   ru: "Клевер",     en: "Clover" },
                     { w: 2, h: 2, extra: { shape: "hex" },      ru: "Шестиугольник", en: "Hexagon" },
                     { w: 2, h: 2, extra: { shape: "circle" },   ru: "Круг",       en: "Circle" },
                     { w: 4, h: 3, extra: { shape: "squircle" }, ru: "Большое",    en: "Large" }] },
        { type: "search", cat: "tools", w: 4, h: 1, minW: 3, minH: 1, maxW: 8, maxH: 1, tone: "neutral", bg: "blur", icon: "search", ru: "Поиск", en: "Search",
          variants: [{ w: 4, h: 1, ru: "Строка поиска", en: "Search bar" }, { w: 6, h: 1, ru: "Широкая, с кнопками", en: "Wide, with buttons" }] },
        { type: "apps", cat: "tools", w: 4, h: 1, minW: 2, minH: 1, maxW: 8, maxH: 2, tone: "neutral", bg: "blur", icon: "apps", ru: "Частые приложения", en: "Frequent apps",
          variants: [{ w: 4, h: 1, ru: "Ряд", en: "Row" }, { w: 4, h: 2, ru: "Два ряда с подписями", en: "Two rows with labels" }] },
        { type: "timer", cat: "tools", w: 2, h: 2, minW: 2, minH: 1, maxW: 4, maxH: 2, tone: "tertiary", bg: "blur", icon: "timer", ru: "Таймер", en: "Timer",
          variants: [{ w: 4, h: 1, ru: "Ряд", en: "Row" }, { w: 2, h: 2, ru: "Кольцо", en: "Ring" }, { w: 4, h: 2, ru: "Кольцо и кнопки", en: "Ring and buttons" }] },
        { type: "note", cat: "tools", w: 2, h: 2, minW: 2, minH: 2, maxW: 6, maxH: 4, tone: "tertiary", bg: "blur", icon: "sticky_note_2", ru: "Заметка", en: "Note",
          menu: [{ id: "clear", icon: "ink_eraser", ru: "Очистить заметку", en: "Clear note" }],
          variants: [{ w: 2, h: 2, ru: "Стикер", en: "Sticker" }, { w: 4, h: 2, ru: "Широкая", en: "Wide" }, { w: 3, h: 3, ru: "Большая", en: "Large" }] },
        { type: "toggles", cat: "system", w: 2, h: 2, minW: 2, minH: 1, maxW: 4, maxH: 2, tone: "primary", bg: "blur", icon: "toggle_on", ru: "Быстрые кнопки", en: "Quick toggles",
          variants: [{ w: 4, h: 1, ru: "Ряд", en: "Row" }, { w: 2, h: 2, ru: "Квадрат", en: "Square" }, { w: 4, h: 2, ru: "С подписями", en: "With labels" }] },
        { type: "system", cat: "system", w: 2, h: 2, minW: 2, minH: 1, maxW: 4, maxH: 2, tone: "secondary", bg: "blur", icon: "memory", ru: "Система", en: "System",
          variants: [{ w: 2, h: 1, ru: "Мини", en: "Mini" }, { w: 2, h: 2, ru: "Полоски", en: "Bars" }, { w: 4, h: 2, ru: "Кольца", en: "Rings" }] }
    ]
    // категории каталога — в этом порядке
    readonly property var categories: [
        { id: "time",    icon: "schedule",          ru: "Время и дата",  en: "Time & date" },
        { id: "weather", icon: "partly_cloudy_day", ru: "Погода",        en: "Weather" },
        { id: "media",   icon: "play_circle",       ru: "Музыка и фото", en: "Music & photos" },
        { id: "tools",   icon: "handyman",          ru: "Инструменты",   en: "Tools" },
        { id: "system",  icon: "memory",            ru: "Система",       en: "System" }
    ]
    function inCategory(cat) { return catalog.filter(c => c.cat === cat); }
    function spec(type) { return catalog.find(c => c.type === type) || catalog[0]; }
    function known(type) { return catalog.some(c => c.type === type); }
    // старые раскладки: «Циферблат» стал одним из стилей «Часов»
    function migrate(it) {
        if (it.type === "analog") { it.type = "clock"; it.extra = Object.assign({ face: "analog" }, it.extra || {}); }
        return it;
    }

    property ListModel model: ListModel {}     // роли: wid, type, gx, gy, gw, gh, extra (JSON-строка — свои настройки виджета)
    property bool editing: false
    property bool typing: false          // пишем в заметке — рабочему столу нужна клавиатура
    property bool picking: false         // открыт каталог «Добавить виджет»
    property string pickType: "clock"    // какой виджет открыт в каталоге (вкладка слева)
    property string tuning: ""           // wid виджета, у которого открыта панель «Настроить»
    property int rev: 0                  // растёт при каждой правке настроек виджета — для привязок
    property var backdrop: null          // размытые обои (текстура рабочего стола) — подложка «стекла» виджетов
    property string leaving: ""          // wid виджета, который сейчас уезжает (анимация удаления)
    property string fresh: ""            // wid только что добавленного (анимация появления)
    property int cols: 20                // размер сетки — сообщает Desktop по своему экрану
    property int rows: 10
    property bool loaded: false
    property string file: Config.dir + "/widgets.json"
    onEditingChanged: { if (editing) typing = false; else { picking = false; tuning = ""; } }
    onPickingChanged: if (picking) tuning = ""
    onTuningChanged: if (tuning !== "") picking = false

    // команда виджету из меню по правому клику (см. menu в каталоге): виджет слушает своё wid
    signal command(string wid, string name)

    readonly property var defaults: [
        { wid: "w1", type: "glance",  gx: 0, gy: 0, gw: 4, gh: 1 },
        { wid: "w2", type: "clock",   gx: 0, gy: 1, gw: 2, gh: 2 },
        { wid: "w3", type: "weather", gx: 2, gy: 1, gw: 2, gh: 2 },
        { wid: "w4", type: "search",  gx: 0, gy: 3, gw: 4, gh: 1 }
    ]

    function indexOf(wid) {
        for (let i = 0; i < model.count; i++) if (model.get(i).wid === wid) return i;
        return -1;
    }
    function clampW(type, w) { const s = spec(type); return Math.max(s.minW, Math.min(s.maxW, Math.round(w))); }
    function clampH(type, h) { const s = spec(type); return Math.max(s.minH, Math.min(s.maxH, Math.round(h))); }

    // ── занятость клеток
    function fits(x, y, w, h, skip) {
        if (x < 0 || y < 0 || x + w > cols || y + h > rows) return false;
        for (let i = 0; i < model.count; i++) {
            const it = model.get(i);
            if (it.wid === skip || it.wid === leaving) continue;
            if (x < it.gx + it.gw && it.gx < x + w && y < it.gy + it.gh && it.gy < y + h) return false;
        }
        return true;
    }
    function freeSpot(w, h) {
        for (let y = 0; y < rows; y++)
            for (let x = 0; x < cols; x++)
                if (fits(x, y, w, h, "")) return { x: x, y: y };
        return null;
    }

    // ── правки
    function add(type, w0, h0, extra) {
        if (!known(type)) return;
        const s = spec(type);
        let w = clampW(type, w0 || s.w), h = clampH(type, h0 || s.h), p = freeSpot(w, h);
        if (!p) { w = s.minW; h = s.minH; p = freeSpot(w, h); }      // не влез — пробуем самый маленький
        if (!p) {
            Activity.show({ icon: "grid_off", title: I18n.t("Нет места", "No room"), sub: I18n.t("Убери или уменьши виджеты", "Remove or shrink widgets") }, 2200);
            return;
        }
        let n = 1;
        while (indexOf("w" + n) >= 0) n++;
        fresh = "w" + n;
        model.append({ wid: fresh, type: type, gx: p.x, gy: p.y, gw: w, gh: h, extra: JSON.stringify(extra || {}) });
        save();
    }
    function remove(wid) {
        if (leaving !== "" || indexOf(wid) < 0) return;
        if (tuning === wid) tuning = "";
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
        if (i < 0) return false;
        const it = model.get(i);
        if (!fits(x, y, it.gw, it.gh, wid)) return false;
        model.setProperty(i, "gx", x);
        model.setProperty(i, "gy", y);
        save();
        return true;
    }
    // новый прямоугольник целиком: тянем за левый или верхний край — меняется и положение
    function resize(wid, x, y, w, h) {
        const i = indexOf(wid);
        if (i < 0) return false;
        const it = model.get(i);
        if (w !== clampW(it.type, w) || h !== clampH(it.type, h) || !fits(x, y, w, h, wid)) return false;
        model.setProperty(i, "gx", x);
        model.setProperty(i, "gy", y);
        model.setProperty(i, "gw", w);
        model.setProperty(i, "gh", h);
        save();
        return true;
    }
    function extraOf(wid) {
        const i = indexOf(wid);
        try { return i >= 0 ? JSON.parse(model.get(i).extra || "{}") : {}; } catch (e) { return {}; }
    }
    function setExtra(wid, key, value) {
        const i = indexOf(wid);
        if (i < 0) return;
        const d = extraOf(wid);
        if (JSON.stringify(d[key]) === JSON.stringify(value)) return;
        if (value === undefined) delete d[key]; else d[key] = value;
        model.setProperty(i, "extra", JSON.stringify(d));
        rev++;
        save();
    }
    function fill(list) {
        model.clear();
        for (const it of list) {
            const s = spec(it.type);
            model.append({ wid: it.wid, type: it.type, gx: it.gx, gy: it.gy,
                           gw: clampW(it.type, it.gw || s.w), gh: clampH(it.type, it.gh || s.h),
                           extra: it.extra ? JSON.stringify(it.extra) : "{}" });
        }
    }
    function reset() { fill(defaults); save(); }

    // ── файл (version 1 — без размеров: берутся из каталога)
    FileView {
        id: fileView
        path: root.file
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.fill((d.items || []).map(i => i && i.id ? root.migrate(i) : i).filter(i => i && i.id && root.known(i.type))
                          .map(i => ({ wid: i.id, type: i.type, gx: i.x | 0, gy: i.y | 0, gw: i.w | 0, gh: i.h | 0, extra: i.extra })));
            } catch (e) { root.fill(root.defaults); }
            root.loaded = true;
        }
        onLoadFailed: { root.fill(root.defaults); root.loaded = true; root.save(); }
    }
    // запись — с короткой задержкой: перенос, размер и удаление подряд дают одну запись
    function save() { if (loaded) saveTimer.restart(); }
    Timer { id: saveTimer; interval: 400; onTriggered: root.write() }
    function write() {
        const items = [];
        for (let i = 0; i < model.count; i++) {
            const it = model.get(i);
            const o = { id: it.wid, type: it.type, x: it.gx, y: it.gy, w: it.gw, h: it.gh };
            const ex = extraOf(it.wid);
            if (Object.keys(ex).length) o.extra = ex;
            items.push(o);
        }
        fileView.setText(JSON.stringify({ version: 2, items: items }, null, 2) + "\n");
    }

    IpcHandler {
        target: "widgets"
        function edit(): void { root.editing = true; }
        function done(): void { root.editing = false; }
        function toggle(): void { root.editing = !root.editing; }
        function catalog(): void { root.editing = true; root.picking = true; }
        function pick(type: string): void { root.editing = true; root.picking = true; if (root.known(type)) root.pickType = type; }
        function add(type: string): void { root.add(type); }
        function remove(wid: string): void { root.remove(wid); }
        function move(wid: string, x: int, y: int): bool { return root.move(wid, x, y); }
        function resize(wid: string, w: int, h: int): bool {
            const i = root.indexOf(wid);
            return i >= 0 && root.resize(wid, root.model.get(i).gx, root.model.get(i).gy, w, h);
        }
        function command(wid: string, name: string): void { root.command(wid, name); }
        function tune(wid: string): void { root.editing = true; root.tuning = wid; }
        // настройка виджета: значение — JSON («"blur"», «0.3»); пусто — по умолчанию
        function set(wid: string, key: string, value: string): void { root.setExtra(wid, key, value === "" ? undefined : JSON.parse(value)); }
        function reset(): void { root.reset(); }
        function list(): string {
            const out = [];
            for (let i = 0; i < root.model.count; i++) {
                const it = root.model.get(i);
                out.push(it.wid + " " + it.type + " " + it.gx + "," + it.gy + " " + it.gw + "x" + it.gh);
            }
            return out.join("\n");
        }
    }
}
