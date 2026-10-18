import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import "calc.js" as Calc

// Лаунчер (вместо rofi): строка поиска + результаты.
//   просто текст — приложения (+ пример посчитается, + поиск в интернете)
//   =  калькулятор     :  эмодзи     ?  вопрос ассистенту (локальная модель; «??» или «морковь, …» — Claude; см. Assistant.qml)
// Ошибся раскладкой («ашкуащч») или пишешь по-русски («телеграм») — всё равно найдёт.
Item {
    id: root

    signal close()
    signal nudge()
    property string initial: ""

    readonly property int pad: 10
    readonly property bool ru: Config.lang === "ru"
    implicitWidth: 660
    implicitHeight: col.implicitHeight + pad * 2

    readonly property string query: input.text
    readonly property string mode: query.startsWith("?") ? "ai"
                                 : query.startsWith(":") ? "emoji"
                                 : query.startsWith("=") ? "calc" : "all"
    readonly property string q: (mode === "all" ? query : query.slice(1)).trim()
    property int sel: 0

    // ── цвета выбранной строки
    readonly property color selBg: Theme.m3 ? Theme.primaryContainer : Qt.alpha(Theme.primary, 0.22)
    readonly property color selFg: Theme.m3 ? Theme.primaryContainerFg : Theme.fg

    // ───────────────────────── поиск ─────────────────────────
    readonly property var layoutEn: "qwertyuiop[]asdfghjkl;'zxcvbnm,.`"
    readonly property var layoutRu: "йцукенгшщзхъфывапролджэячсмитьбюё"
    readonly property var tr: ({ "а":"a","б":"b","в":"v","г":"g","д":"d","е":"e","ё":"e","ж":"zh","з":"z","и":"i","й":"y",
                                 "к":"k","л":"l","м":"m","н":"n","о":"o","п":"p","р":"r","с":"s","т":"t","у":"u","ф":"f",
                                 "х":"h","ц":"c","ч":"ch","ш":"sh","щ":"sch","ъ":"","ы":"y","ь":"","э":"e","ю":"yu","я":"ya" })

    function swapLayout(s) {
        let o = "";
        for (const c of s) {
            const i = layoutEn.indexOf(c), j = layoutRu.indexOf(c);
            o += i >= 0 ? layoutRu[i] : j >= 0 ? layoutEn[j] : c;
        }
        return o;
    }
    function translit(s) {
        let o = "";
        for (const c of s) o += tr[c] !== undefined ? tr[c] : c;
        return o;
    }
    function norm(s) { return (s || "").toLowerCase().replace(/ё/g, "е"); }

    // насколько текст похож на запрос: 0 — никак
    function match(text, w) {
        const t = norm(text);
        if (!t || !w) return 0;
        if (t === w) return 120;
        if (t.startsWith(w)) return 100;
        const i = t.indexOf(w);
        if (i > 0 && /[\s\-_.:]/.test(t[i - 1])) return 88;
        if (i > 0) return 66;
        // буквы по порядку: «vsc» → visual studio code
        let p = 0, gaps = 0, last = -1;
        for (let k = 0; k < t.length && p < w.length; k++) {
            if (t[k] === w[p]) { if (last >= 0 && k - last > 1) gaps++; last = k; p++; }
        }
        return p === w.length && w.length >= 2 ? Math.max(8, 40 - gaps * 6 - (t.length - w.length) * 0.3) : 0;
    }

    function iconFor(e) {
        const i = e.icon || "";
        if (i.startsWith("/")) return "file://" + i;
        return Quickshell.iconPath(i, true) || Quickshell.iconPath("application-x-executable", true);
    }

    readonly property var allApps: {
        const v = DesktopEntries.applications.values;
        const out = [];
        for (let i = 0; i < v.length; i++) if (!v[i].noDisplay) out.push(v[i]);
        return out;
    }

    function appResults(w0) {
        const ws = [norm(w0)];
        const sw = norm(swapLayout(w0)); if (sw !== ws[0]) ws.push(sw);
        const tl = translit(ws[0]); if (tl !== ws[0]) ws.push(tl);
        const scored = [];
        for (const e of allApps) {
            let best = 0;
            for (let k = 0; k < ws.length; k++) {
                const w = ws[k];
                const pen = k === 0 ? 0 : 6;
                let s = Math.max(match(e.name, w),
                                 match(e.genericName, w) * 0.7,
                                 match((e.id || "").split(".").pop(), w) * 0.75,
                                 (e.keywords || []).reduce((m, x) => Math.max(m, match(x, w) * 0.6), 0),
                                 norm(e.comment).indexOf(w) >= 0 && w.length > 2 ? 22 : 0);
                best = Math.max(best, s - pen);
            }
            if (best > 0) scored.push({ e: e, s: best + Math.min(30, Usage.count(e.id) * 2) });
        }
        scored.sort((a, b) => b.s - a.s || a.e.name.localeCompare(b.e.name));
        return scored.slice(0, 7).map(x => appItem(x.e));
    }
    function appItem(e) {
        return { kind: "app", img: iconFor(e), title: e.name,
                 sub: e.genericName || e.comment || "", hint: I18n.t("Открыть", "Open"),
                 run: () => launch(e) };
    }
    function launch(e) {
        Usage.used(e.id);
        if (e.runInTerminal && e.command && e.command.length) Quickshell.execDetached(["kitty", "--"].concat(e.command));
        else e.execute();
        root.close();
    }

    // встроенные команды оболочки
    readonly property var actions: [
        { icon: "tune", ru: "Настройки оболочки", en: "Shell settings", k: "settings настройки оформление glass",
          run: () => { Config.settingsOpen = true; } },
        { icon: "wallpaper", ru: "Обои и цвет темы", en: "Wallpaper & theme color", k: "wallpaper picker обои тема цвет палитра",
          run: () => Quickshell.execDetached(["qs", "ipc", "-c", "glass", "call", "picker", "open"]) },
        { icon: "do_not_disturb_on", ru: "Не беспокоить", en: "Do not disturb", k: "dnd notifications уведомления тихо",
          run: () => { Config.dnd = !Config.dnd; } },
        { icon: "colorize", ru: "Пипетка: цвет с экрана", en: "Color picker", k: "color picker pipette пипетка цвет hex",
          run: () => Quickshell.execDetached(["sh", "-c", 'sleep 0.4; p=$(slurp -p) || exit 0; '
              + 'c=$(grim -g "$p" -t ppm - | magick - -format "%[hex:p{0,0}]" info:) || exit 0; c="#$(printf %s "$c" | cut -c1-6)"; '
              + 'wl-copy -- "$c"; qs ipc -c glass call island toast colorize "$c" "$0"', I18n.t("Цвет скопирован", "Color copied")]) },
        { icon: "widgets", ru: "Изменить виджеты", en: "Edit widgets", k: "widgets виджеты рабочий стол desktop",
          run: () => { Widgets.editing = true; } },
        { icon: "keyboard", ru: "Горячие клавиши", en: "Keyboard shortcuts", k: "hotkeys keys shortcuts клавиши шпаргалка бинды binds",
          run: () => Quickshell.execDetached(["qs", "ipc", "-c", "glass", "call", "hotkeys", "open"]) },
        { icon: "lock", ru: "Заблокировать экран", en: "Lock screen", k: "lock блокировка замок экран",
          run: () => Locker.lock() },
        { icon: "bedtime", ru: "Показать Always On Display", en: "Show Always On Display", k: "aod always on display часы",
          run: () => { Config.aodPing++; } },
        { icon: "nightlight", ru: "Защита глаз", en: "Eye comfort", k: "night ночной свет тёплый экран глаза",
          run: () => Night.toggle() },
        { icon: "timer_off", ru: "Остановить таймер", en: "Stop timer", k: "timer таймер стоп stop",
          run: () => Countdown.stop() },
        { icon: "screen_record", ru: "Запись экрана", en: "Screen recording", k: "record recorder запись видео",
          run: () => Quickshell.execDetached(["sh", "-c", "sleep 0.3; exec ~/.config/hypr/scripts/record.sh toggle"]) }
    ]
    function actionResults(w) {
        const out = [];
        for (const a of actions) {
            const s = Math.max(match(a.ru, w), match(a.en, w), match(a.k, w) * 0.8,
                               a.k.split(" ").reduce((m, x) => Math.max(m, match(x, w) * 0.8), 0));
            if (s >= 60) out.push({ kind: "action", icon: a.icon, title: I18n.t(a.ru, a.en), sub: I18n.t("Оболочка", "Shell"),
                                    hint: I18n.t("Выполнить", "Run"), run: () => { a.run(); root.close(); } });
        }
        return out;
    }

    // открытые окна по заголовку или приложению: «readme», «zen» → перейти к окну
    function windowResults(w) {
        const out = [], list = ToplevelManager.toplevels.values, q = norm(w);
        for (let i = 0; i < list.length; i++) {
            const t = list[i];
            const s = Math.max(match(t.title || "", q), match(t.appId || "", q) * 0.9);
            if (s < 60) continue;
            const e = DesktopEntries.heuristicLookup(t.appId || "");
            const it = { kind: "action", title: t.title || t.appId || "", sub: I18n.t("Окно · ", "Window · ") + (e?.name ?? t.appId ?? ""),
                         hint: I18n.t("Перейти", "Switch"), run: () => { t.activate(); root.close(); }, s: s };
            if (e && e.icon) it.img = e.icon.startsWith("/") ? "file://" + e.icon : Quickshell.iconPath(e.icon);
            else it.icon = "web_asset";
            out.push(it);
        }
        out.sort((a, b) => b.s - a.s);
        return out.slice(0, 3);
    }

    // «timer 5m», «таймер 10 мин чай» → таймер в острове (Countdown)
    function timerItem(w) {
        const m = w.match(/^\s*(?:timer|таймер)\s+(.+)$/i);
        if (!m) return null;
        const p = Countdown.parse(m[1]);
        if (p.secs <= 0) return null;
        return { kind: "action", icon: "timer",
                 title: I18n.t("Таймер на ", "Timer for ") + Countdown.fmt(p.secs) + (p.label !== "" ? " · " + p.label : ""),
                 sub: I18n.t("Оболочка", "Shell"), hint: I18n.t("Запустить", "Start"),
                 run: () => { Countdown.start(p.secs, p.label); root.close(); } };
    }

    function copy(text, what) {
        Quickshell.execDetached(["wl-copy", "--", text]);
        Activity.show({ icon: "content_copy", title: I18n.t("Скопировано", "Copied"), sub: what || text }, 1800);
    }
    function calcItem(expr) {
        const v = Calc.evaluate(expr);
        if (v === null) return null;
        const shown = Calc.pretty(v, ru);
        return { kind: "calc", icon: "calculate", title: "= " + shown, sub: expr.replace(/\*/g, "×"),
                 hint: I18n.t("Копировать", "Copy"), run: () => { copy(Calc.format(v), shown); root.close(); } };
    }
    function webItems(w) {
        const out = [];
        if (/^(https?:\/\/)?[\w-]+(\.[\w-]+)+(:\d+)?(\/\S*)?$/i.test(w) && !/^\d+(\.\d+)*$/.test(w)) {
            const url = /^https?:\/\//.test(w) ? w : "https://" + w;
            out.push({ kind: "web", icon: "public", title: w, sub: I18n.t("Открыть сайт", "Open website"),
                       hint: I18n.t("Открыть", "Open"), run: () => { Quickshell.execDetached(["xdg-open", url]); root.close(); } });
        }
        out.push({ kind: "web", icon: "travel_explore", title: w, sub: I18n.t("Найти в интернете", "Search the web"),
                   hint: I18n.t("Искать", "Search"),
                   run: () => { Quickshell.execDetached(["xdg-open", "https://www.google.com/search?q=" + encodeURIComponent(w)]); root.close(); } });
        return out;
    }

    readonly property var results: {
        const w = q;
        if (mode === "emoji") return [];
        if (mode === "ai") {
            const r = [{ kind: "ai", title: w }];
            if (w) r.push(webItems(w).pop());
            return r;
        }
        if (mode === "calc") {
            const c = calcItem(w);
            return c ? [c] : [{ kind: "note", icon: "calculate", title: w ? I18n.t("Пока не похоже на пример", "Not a valid expression yet")
                                                                        : I18n.t("Пиши пример: 2+2×2, 15% от 200 → 200*15%, sqrt 2", "Type an expression: 2+2*2, 200*15%, sqrt 2"),
                                sub: "" }];
        }
        if (!w) {
            // пусто — частые приложения (или просто первые по алфавиту)
            const a = allApps.slice().sort((x, y) => Usage.count(y.id) - Usage.count(x.id) || x.name.toLowerCase().localeCompare(y.name.toLowerCase()));
            return a.slice(0, 6).map(appItem);
        }
        let r = [];
        const tm = timerItem(w); if (tm) r.push(tm);
        if (Calc.looksLike(w)) { const c = calcItem(w); if (c) r.push(c); }
        r = r.concat(actionResults(norm(w)).slice(0, 2));
        r = r.concat(appResults(w));
        r = r.concat(windowResults(w));
        return r.concat(webItems(w));
    }
    onResultsChanged: sel = 0

    // ───────────────────────── эмодзи ─────────────────────────
    property var emojiData: null      // грузим только когда открыли «:» — остальное время не держим
    FileView {
        id: emojiFile
        path: root.mode === "emoji" || root.emojiData ? Quickshell.env("HOME") + "/.config/quickshell/glass/emoji.json" : ""
        printErrors: false
        onLoaded: { try { root.emojiData = JSON.parse(text()).e; } catch (err) {} }
    }
    readonly property var emojis: {
        if (mode !== "emoji" || !emojiData) return [];
        const ws = norm(q).split(/\s+/).filter(x => x);
        const all = emojiData;
        if (ws.length === 0) {
            const rec = Usage.emoji;
            const recent = all.filter(x => rec.indexOf(x[0]) >= 0).sort((a, b) => rec.indexOf(a[0]) - rec.indexOf(b[0]));
            return recent.concat(all.filter(x => rec.indexOf(x[0]) < 0));
        }
        const sws = ws.map(w => norm(swapLayout(w)));
        const out = [];
        for (const x of all) {
            const hay = x[1] + " " + x[3] + " " + norm(x[2]);
            let s = 0, ok = true;
            for (let k = 0; k < ws.length; k++) {
                const i = Math.max(hay.indexOf(ws[k]), hay.indexOf(sws[k]));
                if (i < 0) { ok = false; break; }
                s += i === 0 ? 3 : hay[i - 1] === " " ? 2 : 1;
            }
            // короче название — точнее совпало; флаги — в конец
            if (ok) out.push({ x: x, s: s + (Usage.emoji.indexOf(x[0]) >= 0 ? 3 : 0) - (x[4] === 8 ? 1.5 : 0) - x[1].length * 0.02 });
        }
        out.sort((a, b) => b.s - a.s);
        return out.slice(0, 120).map(o => o.x);
    }
    onEmojisChanged: if (mode === "emoji") sel = 0
    onModeChanged: if (mode === "ai") Assistant.warm()

    function pickEmoji(x) {
        Usage.usedEmoji(x[0]);
        Quickshell.execDetached(["sh", "-c", 'wl-copy -- "$1"; sleep 0.25; command -v wtype >/dev/null && wtype -- "$1"', "sh", x[0]]);
        Activity.show({ icon: "add_reaction", title: I18n.t("Эмодзи", "Emoji") + "  " + x[0], sub: I18n.t("Вставлено и скопировано", "Typed and copied") }, 1500);
        root.close();
    }

    // ───────────────────────── клавиши ─────────────────────────
    function count() { return mode === "emoji" ? emojis.length : results.length; }
    function move(d) {
        const n = count();
        if (n === 0) return;
        sel = Math.max(0, Math.min(n - 1, sel + d));
    }
    function activate() {
        if (mode === "emoji") { if (emojis[sel]) pickEmoji(emojis[sel]); return; }
        const r = results[sel];
        if (r && r.run) r.run();
        else if (r && r.kind === "ai") { if (r.title.trim() !== "") Assistant.ask(r.title); else root.nudge(); }
    }

    Column {
        id: col
        x: root.pad; y: root.pad
        width: root.width - root.pad * 2
        spacing: 8

        // ── строка поиска
        Rectangle {
            id: field
            width: parent.width
            height: 60
            radius: 30
            color: Theme.glassChip

            Rectangle {
                id: modeBadge
                x: 8; anchors.verticalCenter: parent.verticalCenter
                width: 44; height: 44
                radius: root.mode === "all" ? 22 : 14     // режим → квадратик (как в M3 Expressive)
                color: root.mode === "all" ? "transparent"
                     : root.mode === "ai" ? Theme.tertiaryContainer
                     : root.mode === "emoji" ? Theme.secondaryContainer : Theme.primaryContainer
                Behavior on radius { Anim { kind: "fast" } }
                Behavior on color { ColorAnimation { duration: 200 } }
                Icon {
                    anchors.centerIn: parent
                    size: 24
                    fill: root.mode === "all" ? 0 : 1
                    name: root.mode === "ai" ? "auto_awesome" : root.mode === "emoji" ? "mood"
                        : root.mode === "calc" ? "calculate" : "search"
                    color: root.mode === "all" ? Theme.fgVariant
                         : root.mode === "ai" ? Theme.tertiaryContainerFg
                         : root.mode === "emoji" ? Theme.secondaryContainerFg : Theme.primaryContainerFg
                }
            }

            TextInput {
                id: input
                anchors { left: modeBadge.right; leftMargin: 10; right: modeName.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                color: Theme.fg
                selectionColor: Qt.alpha(Theme.primary, 0.4)
                selectedTextColor: Theme.fg
                font.family: Theme.font
                font.pixelSize: 19
                font.variableAxes: ({ "wght": 450, "ROND": 100, "opsz": 19 })
                clip: true
                focus: true
                text: root.initial
                cursorDelegate: Rectangle { width: 2; radius: 1; color: Theme.primary
                    SequentialAnimation on opacity { loops: Animation.Infinite; running: true
                        PauseAnimation { duration: 500 } NumberAnimation { to: 0; duration: 120 }
                        PauseAnimation { duration: 380 } NumberAnimation { to: 1; duration: 120 } } }

                Label {
                    visible: input.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    size: 19; weight: 400
                    color: Theme.fgVariant
                    text: I18n.t("Приложения, примеры, сайты…", "Apps, math, websites…")
                }

                Keys.onPressed: ev => {
                    const k = ev.key;
                    const grid = root.mode === "emoji";
                    if (k === Qt.Key_Escape) { if (input.text !== "") input.text = ""; else root.close(); }
                    else if (k === Qt.Key_Down || (k === Qt.Key_J && ev.modifiers & Qt.ControlModifier)) root.move(grid ? emojiGrid.cols : 1);
                    else if (k === Qt.Key_Up || (k === Qt.Key_K && ev.modifiers & Qt.ControlModifier)) root.move(grid ? -emojiGrid.cols : -1);
                    else if (k === Qt.Key_Tab) root.move(1);
                    else if (k === Qt.Key_Backtab) root.move(-1);
                    else if (grid && k === Qt.Key_Right && input.cursorPosition === input.length) root.move(1);
                    else if (grid && k === Qt.Key_Left && input.cursorPosition === input.length && root.sel > 0) root.move(-1);
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.activate();
                    else return;
                    ev.accepted = true;
                }
            }

            Label {
                id: modeName
                anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                size: 12; weight: 600
                color: Theme.fgVariant
                opacity: root.mode === "all" ? 0 : 1
                Behavior on opacity { Anim { kind: "effects" } }
                text: root.mode === "ai" ? I18n.t("Ассистент", "Assistant") : root.mode === "emoji" ? I18n.t("Эмодзи", "Emoji")
                    : root.mode === "calc" ? I18n.t("Калькулятор", "Calculator") : ""
            }
        }

        // ── список: приложения, пример, сайты
        ListView {
            id: list
            visible: root.mode !== "emoji" && count > 0
            width: parent.width
            height: Math.min(contentHeight, 7 * 60)
            clip: true
            spacing: 2
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            model: root.mode === "emoji" ? [] : root.results
            currentIndex: root.sel
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
            highlightFollowsCurrentItem: false

            highlight: Rectangle {
                width: list.width
                y: list.currentItem ? list.currentItem.y : 0
                height: list.currentItem ? list.currentItem.height : 56
                radius: 22
                color: list.currentItem && list.currentItem.kind === "ai" ? "transparent" : root.selBg
                Behavior on y { Anim { kind: "fast" } }
                Behavior on height { Anim { kind: "fast" } }
            }

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property string kind: modelData.kind
                readonly property bool current: index === root.sel
                width: list.width
                height: kind === "ai" ? aiCard.implicitHeight : 58

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    // только когда мышь реально двигали — иначе список под курсором «крадёт» выбор при наборе
                    onPositionChanged: root.sel = row.index
                    onClicked: { root.sel = row.index; root.activate(); }
                }

                // ── обычная строка
                Item {
                    visible: row.kind !== "ai"
                    anchors.fill: parent

                    Rectangle {
                        id: badge
                        x: 9; anchors.verticalCenter: parent.verticalCenter
                        width: 40; height: 40
                        radius: row.current ? 14 : 20
                        visible: row.modelData.img === undefined
                        color: row.current ? Theme.primary : Theme.glassChip
                        Behavior on radius { Anim { kind: "fast" } }
                        Behavior on color { ColorAnimation { duration: 180 } }
                        Icon {
                            anchors.centerIn: parent
                            name: row.modelData.icon || ""
                            size: 22
                            fill: row.current ? 1 : 0
                            color: row.current ? Theme.primaryFg : Theme.fgVariant
                        }
                    }
                    IconImage {
                        visible: row.modelData.img !== undefined
                        x: 9; anchors.verticalCenter: parent.verticalCenter
                        implicitSize: 40
                        source: row.modelData.img || ""
                        asynchronous: true
                        scale: row.current ? 1.08 : 1
                        Behavior on scale { Anim { kind: "fast" } }
                    }
                    Column {
                        anchors { left: parent.left; leftMargin: 62; right: hintChip.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 1
                        Label {
                            width: parent.width
                            text: row.modelData.title || ""
                            size: row.kind === "calc" ? 20 : 15
                            weight: row.kind === "calc" ? 650 : 560
                            color: row.current ? root.selFg : Theme.fg
                        }
                        Label {
                            width: parent.width
                            visible: text !== ""
                            text: row.modelData.sub || ""
                            size: 12; weight: 450
                            color: row.current ? Qt.alpha(root.selFg, 0.75) : Theme.fgVariant
                        }
                    }
                    Rectangle {
                        id: hintChip
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        visible: !!row.modelData.hint
                        width: hintRow.implicitWidth + 20
                        height: 30; radius: 15
                        color: Qt.alpha(root.selFg, 0.10)
                        opacity: row.current ? 1 : 0
                        Behavior on opacity { Anim { kind: "effects" } }
                        Row {
                            id: hintRow
                            anchors.centerIn: parent
                            spacing: 4
                            Label { text: row.modelData.hint || ""; size: 12; weight: 600; color: root.selFg }
                            Icon { name: "keyboard_return"; size: 16; color: root.selFg }
                        }
                    }
                }

                // ── вопрос ассистенту: Enter — спросить, ответ приходит сюда же по кусочкам
                Rectangle {
                    id: aiCard
                    visible: row.kind === "ai"
                    width: parent.width
                    implicitHeight: aiCol.implicitHeight + 32
                    radius: 24
                    color: Qt.alpha(Theme.tertiaryContainer, Theme.m3 ? 1 : 0.55)
                    Behavior on implicitHeight { Anim { kind: "fast" } }
                    readonly property bool mine: Assistant.heard !== "" && Assistant.heard === (row.modelData.title || "").trim()
                                                 && (!Assistant.voice || Assistant.windowed)
                    readonly property bool toClaude: (row.modelData.title || "").startsWith("?") || /^\s*морков/i.test(row.modelData.title || "")
                    readonly property string claudeName: "Claude · " + Assistant.cfg.model.replace("claude-", "").replace(/-(\d)-(\d)$/, " $1.$2")
                    readonly property bool working: mine && Assistant.busy && Assistant.answer === ""
                    Connections { target: root; function onNudge() { shake.restart(); } }
                    SequentialAnimation {
                        id: shake
                        NumberAnimation { target: aiCard; property: "x"; to: 8; duration: 60 }
                        NumberAnimation { target: aiCard; property: "x"; to: -6; duration: 80 }
                        NumberAnimation { target: aiCard; property: "x"; to: 0; duration: 120; easing.type: Easing.OutBack }
                    }
                    Column {
                        id: aiCol
                        x: 18; y: 16
                        width: parent.width - 36
                        spacing: 8
                        Item {
                            width: parent.width; height: 32
                            Rectangle {
                                id: aiBadge
                                width: 32; height: 32; radius: aiCard.working ? 16 : 11
                                color: Theme.tertiary
                                Behavior on radius { Anim { kind: "fast" } }
                                Icon { anchors.centerIn: parent; name: "auto_awesome"; fill: 1; size: 19; color: Theme.surface }
                                RotationAnimation on rotation { from: 0; to: 360; duration: aiCard.working ? 1600 : 9000; loops: Animation.Infinite; running: aiCard.visible }
                            }
                            Column {
                                anchors { left: aiBadge.right; leftMargin: 10; verticalCenter: parent.verticalCenter; right: aiTools.left; rightMargin: 8 }
                                Label { text: I18n.t("Ассистент", "Assistant"); size: 14; weight: 650; color: Theme.tertiaryContainerFg; elide: Text.ElideNone }
                                Label {
                                    width: parent.width
                                    text: !Assistant.online ? I18n.t("служба не запущена", "service is not running")
                                        : aiCard.mine && Assistant.backend === "local" ? I18n.t("локальная модель · Gemma 4", "local model · Gemma 4")
                                        : aiCard.mine && Assistant.backend === "claude" ? aiCard.claudeName
                                        : aiCard.toClaude && Assistant.cfg.backend !== "local"
                                            ? (Assistant.hasKey ? aiCard.claudeName : I18n.t("нет ключа Claude — ответит локальная модель", "no Claude key — the local model will answer"))
                                        : Assistant.cfg.backend === "claude" ? aiCard.claudeName
                                        : I18n.t("локальная модель · «??» — спросить Claude", "local model · “??” — ask Claude")
                                    size: 11; color: Qt.alpha(Theme.tertiaryContainerFg, 0.7)
                                }
                            }
                            Row {
                                id: aiTools
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                spacing: 2
                                visible: aiCard.mine && Assistant.answer !== ""
                                IconButton { icon: "volume_up"; size: 32; iconSize: 18; color: Theme.tertiaryContainerFg; onClicked: Assistant.say(Assistant.answer) }
                                IconButton { icon: "content_copy"; size: 32; iconSize: 18; color: Theme.tertiaryContainerFg
                                             onClicked: Quickshell.execDetached(["wl-copy", Assistant.answer]) }
                            }
                        }
                        Label {
                            width: parent.width
                            visible: row.modelData.title !== "" && !aiCard.mine
                            text: "«" + row.modelData.title + "»"
                            size: 15; weight: 500
                            wrapMode: Text.Wrap; elide: Text.ElideNone; maximumLineCount: 3
                            color: Theme.tertiaryContainerFg
                        }
                        // ответ
                        Text {
                            width: parent.width
                            visible: aiCard.mine && (Assistant.answer !== "" || Assistant.error !== "")
                            text: Assistant.error !== "" && Assistant.answer === "" ? Assistant.error : Assistant.answer
                            textFormat: Text.MarkdownText
                            wrapMode: Text.Wrap
                            color: Theme.tertiaryContainerFg
                            font.family: Theme.font
                            font.pixelSize: 15
                            font.variableAxes: ({ "wght": 450, "ROND": 100 })
                            lineHeight: 1.15
                            onLinkActivated: link => Quickshell.execDetached(["xdg-open", link])
                        }
                        Label {
                            width: parent.width
                            visible: !aiCard.mine || aiCard.working
                            text: aiCard.working ? I18n.t("Думаю…", "Thinking…")
                                : row.modelData.title !== "" ? I18n.t("Enter — спросить. Голосом — Super+A, у Claude — Super+Alt+A", "Enter — ask. By voice — Super+A, Claude — Super+Alt+A")
                                : I18n.t("Напиши вопрос после «?». Голосом — Super+A", "Type a question after “?”. By voice — Super+A")
                            size: 13; weight: 450
                            wrapMode: Text.Wrap; elide: Text.ElideNone
                            color: Qt.alpha(Theme.tertiaryContainerFg, 0.8)
                        }
                    }
                }
            }
        }

        // ── эмодзи сеткой
        Column {
            visible: root.mode === "emoji"
            width: parent.width
            spacing: 6

            GridView {
                id: emojiGrid
                readonly property int cols: Math.floor(width / cellWidth)
                width: parent.width
                height: Math.min(Math.ceil(count / Math.max(1, cols)), 5) * cellHeight
                cellWidth: Math.floor(parent.width / 11)
                cellHeight: 56
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.emojis
                currentIndex: root.mode === "emoji" ? root.sel : -1
                onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, GridView.Contain)
                highlightFollowsCurrentItem: false
                highlight: Rectangle {
                    width: emojiGrid.cellWidth - 4; height: emojiGrid.cellHeight - 4
                    x: emojiGrid.currentItem ? emojiGrid.currentItem.x + 2 : 0
                    y: emojiGrid.currentItem ? emojiGrid.currentItem.y + 2 : 0
                    radius: 18
                    color: root.selBg
                    Behavior on x { Anim { kind: "fast" } }
                    Behavior on y { Anim { kind: "fast" } }
                }
                delegate: Item {
                    required property var modelData
                    required property int index
                    width: emojiGrid.cellWidth; height: emojiGrid.cellHeight
                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData[0]
                        font.family: "Noto Color Emoji"
                        // растим шрифт, а не scale: цветные эмодзи — картинки, при scale они мылятся
                        font.pixelSize: parent.index === root.sel ? 35 : 30
                        Behavior on font.pixelSize { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onPositionChanged: root.sel = parent.index
                        onClicked: root.pickEmoji(parent.modelData)
                    }
                }
            }
            Label {
                x: 14
                width: parent.width - 28
                height: 26
                readonly property var cur: root.emojis[root.sel]
                text: !root.emojiData ? I18n.t("Загружаю…", "Loading…")
                    : root.emojis.length === 0 ? I18n.t("Ничего не нашлось", "Nothing found")
                    : cur ? (root.ru && cur[2] ? cur[2] : cur[1]) + "   ·   ↵ " + I18n.t("вставить", "insert") : ""
                size: 13; weight: 500
                color: Theme.fgVariant
            }
        }

        // ── подсказки режимов (пока пусто)
        Row {
            visible: root.query === ""
            x: 4
            spacing: 6
            Repeater {
                model: [
                    { p: "=", ic: "calculate", t: I18n.t("калькулятор", "calculator") },
                    { p: ":", ic: "mood", t: I18n.t("эмодзи", "emoji") },
                    { p: "?", ic: "auto_awesome", t: I18n.t("ассистент", "assistant") }
                ]
                delegate: Rectangle {
                    required property var modelData
                    width: chipRow.implicitWidth + 22
                    height: 32; radius: chipMa.containsMouse ? 10 : 16
                    color: chipMa.containsMouse ? Theme.secondaryContainer : Theme.glassChip
                    Behavior on radius { Anim { kind: "fast" } }
                    Behavior on color { ColorAnimation { duration: 160 } }
                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 6
                        Label { text: modelData.p; size: 14; weight: 750; color: Theme.primary }
                        Icon { name: modelData.ic; size: 16; color: Theme.fgVariant }
                        Label { text: modelData.t; size: 12; weight: 550; color: Theme.fgVariant }
                    }
                    MouseArea {
                        id: chipMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { input.text = modelData.p; input.forceActiveFocus(); }
                    }
                }
            }
        }
    }

    function reset(t) { input.text = t; sel = 0; input.forceActiveFocus(); }
    Component.onCompleted: input.forceActiveFocus()
}
