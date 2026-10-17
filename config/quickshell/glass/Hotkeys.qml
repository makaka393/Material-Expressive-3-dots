import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Шпаргалка по горячим клавишам: читает bind-строки прямо из hyprland.conf, так что всегда
// совпадает с тем, что настроено. Открыть: qs ipc -c glass call hotkeys toggle (или из лаунчера).
PanelWindow {
    id: win

    property bool open: false
    property var cols: [[], []]          // две колонки групп: [{ title, rows: [{ keys: [..], text }] }]

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: open || card.opacity > 0
    WlrLayershell.namespace: "quickshell-settings"       // то же правило блюра, что у окна настроек
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    IpcHandler {
        target: "hotkeys"
        function toggle(): void { win.open = !win.open; }
        function open(): void { win.open = true; }
        function close(): void { win.open = false; }
    }
    onOpenChanged: if (open) { luaFile.reload(); confFile.reload(); card.forceActiveFocus(); }

    // новый формат (hyprland.lua) важнее старого: Hyprland тоже берёт его, если он есть
    property bool haveLua: false
    FileView {
        id: luaFile
        path: Quickshell.env("HOME") + "/.config/hypr/hyprland.lua"
        printErrors: false
        onLoaded: { win.haveLua = true; win.cols = win.build(win.luaToConf(text())); }
        onLoadFailed: win.haveLua = false
    }
    FileView {
        id: confFile
        path: Quickshell.env("HOME") + "/.config/hypr/hyprland.conf"
        printErrors: false
        onLoaded: if (!win.haveLua) win.cols = win.build(text())
    }

    // hl.bind("SUPER + SHIFT + 1", hl.dsp.window.move({ workspace = 1 })) → «bind = SUPER SHIFT, 1, movetoworkspace, 1»
    readonly property var luaDsp: ({ "window.close": "killactive", "exit": "exit", "window.float": "togglefloating",
        "window.pseudo": "pseudo", "window.fullscreen": "fullscreen", "window.drag": "movewindow", "window.resize": "resizewindow" })
    function luaToConf(text) {
        const vars = {}, out = [];
        for (const raw of text.split("\n")) {
            const line = raw.trim();
            let m = line.match(/^local\s+(\w+)\s*=\s*"([^"]*)"/);
            if (m) { vars[m[1]] = m[2]; continue; }
            m = line.match(/^hl\.bind\(\s*"([^"]+)"\s*,\s*hl\.dsp\.([\w.]+)\((.*?)\)\s*(,\s*\{.*\})?\s*\)\s*(--.*)?$/);
            if (!m) continue;
            const parts = m[1].split("+").map(x => x.trim());
            const key = parts.pop();
            const fn = m[2], a = m[3];
            let disp = luaDsp[fn] || fn, arg = "";
            if (fn === "exec_cmd") {
                disp = "exec";
                // склеиваем строку из литералов и переменных: "bash -c \"…" .. home .. "…"
                const re = /"((?:[^"\\]|\\.)*)"|([A-Za-z_]\w*)/g;
                let t;
                while ((t = re.exec(a)) !== null) arg += t[1] !== undefined ? t[1].replace(/\\(.)/g, "$1") : (vars[t[2]] ?? "");
            } else if (fn === "focus") {
                const d = a.match(/direction\s*=\s*"(\w)/), w = a.match(/workspace\s*=\s*"?([^"\s}]+)/);
                if (d) { disp = "movefocus"; arg = d[1]; } else if (w) { disp = "workspace"; arg = w[1]; }
            } else if (fn === "window.move") {
                const w = a.match(/workspace\s*=\s*"?([^"\s}]+)/);
                if (w) { disp = "movetoworkspace"; arg = w[1]; }
            }
            out.push("bind = " + parts.join(" ") + ", " + key + ", " + disp + (arg !== "" ? ", " + arg : ","));
        }
        return out.join("\n");
    }

    readonly property var modNames: ({ SUPER: "Super", SHIFT: "Shift", CTRL: "Ctrl", CONTROL: "Ctrl", ALT: "Alt" })
    readonly property var keyNames: ({ slash: "/", period: ".", comma: ",", return: "Enter", space: "Space", print: "PrtSc", escape: "Esc",
        left: "←", right: "→", up: "↑", down: "↓", tab: "Tab", "mouse:272": I18n.t("ЛКМ", "LMB"), "mouse:273": I18n.t("ПКМ", "RMB"),
        mouse_down: I18n.t("Колесо ↓", "Wheel ↓"), mouse_up: I18n.t("Колесо ↑", "Wheel ↑") })
    // команды оболочки и скриптов → понятные подписи
    readonly property var known: [
        [/launcher (toggle|open)/, "Лаунчер", "Launcher"], [/launcher emoji/, "Эмодзи", "Emoji"], [/launcher ask/, "Ассистент", "Assistant"],
        [/picker toggle/, "Обои и цвет темы", "Wallpaper & theme"], [/lock lock/, "Заблокировать экран", "Lock screen"],
        [/hotkeys/, "Эта шпаргалка", "This cheat sheet"], [/settings toggle/, "Настройки оболочки", "Shell settings"],
        [/screenshot\.sh region/, "Скриншот области", "Screenshot: region"], [/screenshot\.sh pretty/, "Скриншот в рамке", "Screenshot: framed"],
        [/screenshot\.sh full/, "Скриншот экрана", "Screenshot: screen"], [/screenshot\.sh lens/, "Область в Google Lens", "Region to Google Lens"],
        [/record\.sh/, "Запись экрана", "Screen recording"], [/aod /, "Always On Display", "Always On Display"]
    ]
    readonly property var arrows: ({ l: "←", r: "→", u: "↑", d: "↓" })

    function describe(disp, arg) {
        const t = (ru, en) => I18n.t(ru, en);
        switch (disp) {
        case "killactive": return [1, t("Закрыть окно", "Close window")];
        case "fullscreen": return [1, t("Во весь экран", "Fullscreen")];
        case "togglefloating": return [1, t("Плавающее окно", "Toggle floating")];
        case "togglesplit": return [1, t("Повернуть разделение", "Toggle split")];
        case "pseudo": return [1, t("Псевдотайлинг", "Pseudo-tile")];
        case "movefocus": return [1, t("Фокус ", "Focus ") + (arrows[arg] || arg)];
        case "movewindow": return [1, arg ? t("Сдвинуть окно ", "Move window ") + (arrows[arg] || arg) : t("Перетащить окно", "Drag window")];
        case "resizewindow": return [1, t("Изменить размер окна", "Resize window")];
        case "workspace": return [2, t("Рабочий стол ", "Workspace ") + arg.replace("e+1", t("следующий", "next")).replace("e-1", t("предыдущий", "previous"))];
        case "movetoworkspace": return [2, t("Окно на стол ", "Window to workspace ") + arg];
        case "togglespecialworkspace": return [2, t("Скрытый стол", "Scratchpad")];
        case "exit": return [1, t("Выйти из Hyprland", "Exit Hyprland")];
        case "exec":
            for (const k of known) if (k[0].test(arg)) return [0, t(k[1], k[2])];
            // sh -c "звук & kitty" → главное приложение — последняя команда в строке
            const inner = arg.match(/^(?:ba|z)?sh\s+-c\s+["']?(.*?)["']?$/);
            const cmd = (inner ? inner[1].split(/&&|;|&/).pop() : arg).trim();
            return [3, cmd.split(/\s+/)[0].replace(/^.*\//, "")];
        }
        return [1, disp + (arg ? " " + arg : "")];
    }

    function build(text) {
        const vars = {}, rows = [[], [], [], []], seen = {};
        for (const raw of text.split("\n")) {
            const line = raw.trim();
            let m = line.match(/^\$(\w+)\s*=\s*(.+)$/);
            if (m) { vars[m[1]] = m[2].trim(); continue; }
            m = line.match(/^bind[a-z]*\s*=\s*(.*)$/);
            if (!m) continue;
            const p = m[1].split(",").map(x => x.trim());
            if (p.length < 3 || /^XF86/i.test(p[1])) continue;
            const mods = p[0].replace(/\$(\w+)/g, (_, v) => vars[v] ?? v).split(/[\s+_&]+/).filter(x => x)
                             .map(x => modNames[x.toUpperCase()] || x);
            const key = keyNames[p[1].toLowerCase()] || (p[1].length === 1 ? p[1].toUpperCase() : p[1]);
            const d = describe(p[2], p.slice(3).join(", ").replace(/\$(\w+)/g, (s, v) => vars[v] ?? s));
            // «стол 1», «стол 2»… на цифрах сворачиваем в одну строку
            if (d[0] === 2 && /^\d$/.test(p[1])) {
                const id = mods.join("+") + "|" + p[2];
                if (seen[id]) continue;
                seen[id] = true;
                rows[2].push({ keys: mods.concat(["1…0"]), text: p[2] === "workspace" ? I18n.t("Рабочие столы", "Workspaces") : I18n.t("Окно на другой стол", "Window to workspace") });
                continue;
            }
            // то же действие на другой клавише («Фокус →» на стрелке и на L) — одной строкой: «→ / L»
            const id = mods.join("+") + "|" + d[1];
            if (seen[id]) {
                const k = seen[id].keys;
                if (k[k.length - 1].split(" / ").indexOf(key) < 0) k[k.length - 1] += " / " + key;
                continue;
            }
            const row = { keys: mods.concat([key]), text: d[1] };
            seen[id] = row;
            rows[d[0]].push(row);
        }
        const titles = [I18n.t("Оболочка", "Shell"), I18n.t("Окна", "Windows"), I18n.t("Рабочие столы", "Workspaces"), I18n.t("Приложения", "Apps")];
        const groups = [0, 3, 1, 2].filter(i => rows[i].length > 0).map(i => ({ title: titles[i], rows: rows[i] }));
        // две колонки примерно равной высоты
        const cols = [[], []], h = [0, 0];
        for (const g of groups) { const c = h[0] <= h[1] ? 0 : 1; cols[c].push(g); h[c] += g.rows.length + 2; }
        return cols;
    }

    // затемнение с точками (волна идёт из центра), клик мимо — закрыть
    Scrim {
        anchors.fill: parent
        shown: win.open
        origin: Qt.point(width / 2, height / 2)
        onClicked: win.open = false
    }

    Item {
        id: card
        anchors.centerIn: parent
        width: 980
        height: Math.min(win.height - 120, body.implicitHeight + 104)
        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.92
        Behavior on opacity { Anim { kind: "effects"; duration: win.open ? 260 : 160 } }
        Behavior on scale { Anim { kind: "spatial" } }
        focus: true
        Keys.onPressed: win.open = false

        MouseArea { anchors.fill: parent }
        GlassSurface { anchors.fill: parent; radius: 36; strong: true; sheenEnd: 0.3 }

        Row {
            x: 30; y: 24
            spacing: 12
            Icon { anchors.verticalCenter: parent.verticalCenter; name: "keyboard"; size: 28; fill: 1; color: Theme.primary }
            Label { anchors.verticalCenter: parent.verticalCenter; text: I18n.t("Горячие клавиши", "Keyboard shortcuts"); size: 24; weight: 750; elide: Text.ElideNone }
        }
        IconButton {
            anchors { top: parent.top; right: parent.right; topMargin: 18; rightMargin: 18 }
            icon: "close"; size: 40; iconSize: 22
            onClicked: win.open = false
        }

        Flickable {
            anchors { fill: parent; topMargin: 76; bottomMargin: 24; leftMargin: 30; rightMargin: 30 }
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Row {
                id: body
                spacing: 36
                Repeater {
                    model: win.cols
                    Column {
                        id: col
                        required property var modelData
                        width: (card.width - 60 - 36) / 2
                        spacing: 18
                        Repeater {
                            model: col.modelData
                            Column {
                                id: grp
                                required property var modelData
                                width: col.width
                                spacing: 4
                                Label { text: grp.modelData.title; size: 14; weight: 700; color: Theme.primary; elide: Text.ElideNone; bottomPadding: 4 }
                                Repeater {
                                    model: grp.modelData.rows
                                    Item {
                                        id: row
                                        required property var modelData
                                        width: grp.width; height: 34
                                        Label {
                                            anchors { left: parent.left; right: keysRow.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                            text: row.modelData.text; size: 14; weight: 550
                                        }
                                        Row {
                                            id: keysRow
                                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                            spacing: 4
                                            Repeater {
                                                model: row.modelData.keys
                                                Rectangle {
                                                    required property string modelData
                                                    width: Math.max(28, keyLabel.implicitWidth + 16); height: 26; radius: 9
                                                    color: Theme.glassChip
                                                    border.width: 1; border.color: Qt.alpha(Theme.fg, 0.10)
                                                    Label { id: keyLabel; anchors.centerIn: parent; text: parent.modelData; size: 12; weight: 700; elide: Text.ElideNone }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
