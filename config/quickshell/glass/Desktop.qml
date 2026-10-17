import QtQuick
import Quickshell
import Quickshell.Wayland

// Рабочий стол: виджеты под окнами (слой Bottom — над обоями, под окнами).
// Правый клик по пустому месту или по виджету — меню. В режиме правки рабочий стол встаёт над
// окнами, обои мутнеют, проявляется светящаяся сетка; виджеты перетаскиваются (встают в клетки),
// меняют размер за ручки по краям, удаляются крестиком, добавляются из каталога снизу.
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: win
        required property var modelData
        screen: modelData

        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Normal          // под баром, а не за ним
        color: "transparent"
        WlrLayershell.namespace: "quickshell-desktop"
        // в правке — над окнами (как домашний экран Pixel в режиме правки), иначе — под ними
        WlrLayershell.layer: Widgets.editing ? WlrLayer.Top : WlrLayer.Bottom
        // клавиатура нужна в правке (Esc) и в заметке. В первый миг — Exclusive: так Hyprland отдаёт
        // фокус сразу, без второго клика; потом OnDemand — клик по окну забирает фокус обратно
        readonly property bool wantKeys: Widgets.editing || Widgets.typing
        property bool grab: false
        onWantKeysChanged: if (wantKeys) { grab = true; grabTimer.restart(); }
        Timer { id: grabTimer; interval: 300; onTriggered: win.grab = false }
        WlrLayershell.keyboardFocus: !wantKeys ? WlrKeyboardFocus.None : grab ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

        // сетка: клетка 96 px и зазор 16 → шаг 112, по центру экрана
        readonly property int edge: 28
        readonly property int gap: 16
        readonly property int pitch: 112
        readonly property int cols: Math.max(1, Math.floor((width - 2 * edge + gap) / pitch))
        readonly property int rows: Math.max(1, Math.floor((height - 2 * edge + gap) / pitch))
        readonly property real ox: Math.round((width - (cols * pitch - gap)) / 2)
        readonly property real oy: Math.round((height - (rows * pitch - gap)) / 2)
        readonly property bool main: modelData === Quickshell.screens[0]
        Binding { when: win.main && win.width > 0; target: Widgets; property: "cols"; value: win.cols }
        Binding { when: win.main && win.height > 0; target: Widgets; property: "rows"; value: win.rows }
        function px(c) { return ox + c * pitch; }
        function py(r) { return oy + r * pitch; }
        function span(n) { return n * pitch - gap; }
        function cellX(p) { return Math.round((p - ox) / pitch); }
        function cellY(p) { return Math.round((p - oy) / pitch); }

        SystemClock { id: clock; precision: SystemClock.Minutes }

        function widgetAt(x, y) {
            for (let i = 0; i < Widgets.model.count; i++) {
                const it = Widgets.model.get(i);
                if (x >= px(it.gx) && x < px(it.gx) + span(it.gw) && y >= py(it.gy) && y < py(it.gy) + span(it.gh)) return it;
            }
            return null;
        }

        // ── пустое место
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: m => {
                if (m.button === Qt.RightButton) { menu.openAt(m.x, m.y, win.widgetAt(m.x, m.y)); return; }
                if (menu.shown) menu.shown = false;
                else if (Widgets.picking) Widgets.picking = false;
                else if (Widgets.typing) Widgets.typing = false;
            }
        }
        Item {
            anchors.fill: parent
            focus: Widgets.editing
            Keys.onEscapePressed: { if (menu.shown) menu.shown = false; else if (Widgets.picking) Widgets.picking = false; else Widgets.editing = false; }
            HoverHandler { id: hover; enabled: Widgets.editing }
        }

        // ── сетка правки: светящиеся точки волной из центра, у курсора — крупнее (shaders/griddots.frag)
        Item {
            id: gridFx
            anchors.fill: parent
            property real progress: Widgets.editing ? 1 : 0
            Behavior on progress { NumberAnimation { duration: Widgets.editing ? 900 : 360; easing.type: Easing.OutCubic } }
            visible: progress > 0.002
            ShaderEffect {
                anchors.fill: parent
                fragmentShader: "shaders/griddots.frag.qsb"
                property vector2d res: Qt.vector2d(width, height)
                property vector2d start: Qt.vector2d(win.ox - win.gap / 2, win.oy - win.gap / 2)
                property vector2d count: Qt.vector2d(win.cols, win.rows)
                property real pitch: win.pitch
                property real progress: gridFx.progress
                property vector2d mouse: hover.hovered ? Qt.vector2d(hover.point.position.x, hover.point.position.y) : Qt.vector2d(-9999, -9999)
                property real dim: 0.22
                property color tint: Qt.hsla(Theme.primary.hslHue, Math.max(0.4, Theme.primary.hslSaturation), 0.82, 1)
                property color shade: Theme.surfaceLowest
            }
        }

        // ── куда встанет виджет (перенос и размер)
        Rectangle {
            id: ghost
            property bool ok: true
            property string size: ""
            visible: false
            radius: Math.min(44, height / 2)
            color: Qt.alpha(ok ? Theme.primary : Theme.error, 0.16)
            border.width: 2
            border.color: Qt.alpha(ok ? Theme.primaryText : Theme.error, 0.8)
            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
        // размер в клетках — над призраком (сам призрак почти весь под тянущимся виджетом)
        Rectangle {
            visible: ghost.visible && ghost.size !== ""
            z: 30
            x: ghost.x + ghost.width / 2 - width / 2
            y: ghost.y >= 60 ? ghost.y - height - 14 : ghost.y + ghost.height + 14
            width: sizeLabel.implicitWidth + 26; height: 36; radius: 18
            color: ghost.ok ? Theme.primary : Theme.error
            Label { id: sizeLabel; anchors.centerIn: parent; text: ghost.size; size: 15; weight: 750; color: ghost.ok ? Theme.primaryFg : Theme.surface; elide: Text.ElideNone }
        }
        function showGhost(x, y, w, h, ok, sized) {
            ghost.ok = ok;
            ghost.size = sized ? w + " × " + h : "";
            ghost.x = px(Math.max(0, Math.min(cols - w, x)));
            ghost.y = py(Math.max(0, Math.min(rows - h, y)));
            ghost.width = span(w); ghost.height = span(h);
            ghost.visible = true;
        }

        // ── виджеты
        Repeater {
            model: Widgets.model

            Item {
                id: host
                required property int index
                required property string wid
                required property string type
                required property int gx
                required property int gy
                required property int gw
                required property int gh
                required property string extra
                readonly property var sp: Widgets.spec(type)
                readonly property var cfg: { try { return JSON.parse(extra || "{}"); } catch (e) { return {}; } }
                readonly property bool leaving: Widgets.leaving === wid
                readonly property bool dragging: drag.drag.active
                property bool resizing: false
                readonly property bool hot: Widgets.editing && (hostHover.hovered || resizing || dragging)

                x: win.px(gx)
                y: win.py(gy)
                width: win.span(gw)
                height: win.span(gh)
                z: dragging || resizing ? 10 : hot ? 2 : 1
                Behavior on x { enabled: !host.dragging && !host.resizing; Anim { kind: "spatial" } }
                Behavior on y { enabled: !host.dragging && !host.resizing; Anim { kind: "spatial" } }
                Behavior on width { enabled: !host.resizing; Anim { kind: "spatial" } }
                Behavior on height { enabled: !host.resizing; Anim { kind: "spatial" } }

                function rebind() {
                    x = Qt.binding(() => win.px(host.gx));
                    y = Qt.binding(() => win.py(host.gy));
                    width = Qt.binding(() => win.span(host.gw));
                    height = Qt.binding(() => win.span(host.gh));
                }

                // ── размер за ручку: виджет тянется за мышью, призрак показывает клетки, отпустил — встаёт
                property var target: null
                function resizeTo(e, dx, dy, s) {
                    const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
                    const minW = win.span(sp.minW), maxW = win.span(sp.maxW), minH = win.span(sp.minH), maxH = win.span(sp.maxH);
                    let nx = s.x, ny = s.y, nw = s.w, nh = s.h;
                    if (e === "r") nw = clamp(s.w + dx, minW, maxW);
                    if (e === "l") { nw = clamp(s.w - dx, minW, maxW); nx = s.x + s.w - nw; }
                    if (e === "b") nh = clamp(s.h + dy, minH, maxH);
                    if (e === "t") { nh = clamp(s.h - dy, minH, maxH); ny = s.y + s.h - nh; }
                    x = nx; y = ny; width = nw; height = nh;
                    const cw = Widgets.clampW(type, (nw + win.gap) / win.pitch), ch = Widgets.clampH(type, (nh + win.gap) / win.pitch);
                    const cx = e === "l" ? gx + gw - cw : gx, cy = e === "t" ? gy + gh - ch : gy;
                    target = { x: cx, y: cy, w: cw, h: ch, ok: Widgets.fits(cx, cy, cw, ch, wid) };
                    win.showGhost(cx, cy, cw, ch, target.ok, true);
                }
                function finishResize() {
                    ghost.visible = false;
                    if (target && target.ok && (target.w !== gw || target.h !== gh)) Widgets.resize(wid, target.x, target.y, target.w, target.h);
                    target = null;
                    resizing = false;          // сначала включаем Behavior — виджет доедет до клеток пружинкой
                    rebind();
                }

                // появление: при старте — по очереди, новый — с пружинкой
                property real appear: 0
                Component.onCompleted: {
                    pop.delay = Widgets.fresh === wid ? 0 : 120 + index * 70;
                    pop.start();
                    if (Widgets.fresh === wid) Widgets.fresh = "";
                }
                SequentialAnimation {
                    id: pop
                    property int delay: 0
                    PauseAnimation { duration: pop.delay }
                    NumberAnimation { target: host; property: "appear"; from: 0; to: 1; duration: 620; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
                }

                opacity: leaving ? 0 : Math.min(1, appear * 1.6)
                scale: (leaving ? 0.55 : 0.55 + 0.45 * appear) * (dragging ? 1.04 : Widgets.editing && !resizing ? 0.95 : 1)
                Behavior on opacity { enabled: host.leaving; NumberAnimation { duration: 260; easing.type: Easing.InCubic } }
                Behavior on scale { enabled: host.leaving || host.appear >= 1; Anim { kind: "fast" } }

                // наведение — шире самого виджета: ручки торчат за край
                Item {
                    anchors { fill: parent; margins: -30 }
                    HoverHandler { id: hostHover; enabled: Widgets.editing }
                }

                Loader {
                    anchors.fill: parent
                    sourceComponent: ({ glance: glanceC, clock: clockC, analog: analogC, weather: weatherC, forecast: forecastC,
                                        music: musicC, calendar: calendarC, search: searchC, apps: appsC, toggles: togglesC,
                                        system: systemC, timer: timerC, note: noteC, sun: sunC, photo: photoC, progress: progressC })[host.type] ?? glanceC
                    // в правке виджеты не нажимаются — только двигаются и тянутся
                    enabled: !Widgets.editing
                }
                Component { id: glanceC; WGlance { now: clock.date } }
                Component { id: clockC; WClock { now: clock.date } }
                Component { id: analogC; WAnalog { now: clock.date; wid: host.wid; cfg: host.cfg } }
                Component { id: weatherC; WWeather {} }
                Component { id: forecastC; WForecast {} }
                Component { id: musicC; WMusic {} }
                Component { id: calendarC; WCalendar { now: clock.date } }
                Component { id: searchC; WSearch {} }
                Component { id: appsC; WApps {} }
                Component { id: togglesC; WToggles {} }
                Component { id: systemC; WSystem {} }
                Component { id: timerC; WTimer {} }
                Component { id: noteC; WNote { wid: host.wid; cfg: host.cfg } }
                Component { id: sunC; WSun { now: clock.date } }
                Component { id: photoC; WPhoto { wid: host.wid; cfg: host.cfg } }
                Component { id: progressC; WProgress { now: clock.date; wid: host.wid; cfg: host.cfg } }

                // рамка в правке
                Rectangle {
                    anchors { fill: parent; margins: -6 }
                    radius: Math.min(50, height / 2)
                    color: "transparent"
                    border.width: 2
                    border.color: Qt.alpha(Theme.primaryText, host.hot ? 0.95 : 0.45)
                    opacity: Widgets.editing ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { Anim { kind: "effects" } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                }

                // перетаскивание
                MouseArea {
                    id: drag
                    anchors.fill: parent
                    enabled: Widgets.editing
                    cursorShape: Widgets.editing ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor
                    drag.target: host
                    drag.threshold: 4
                    onPositionChanged: if (host.dragging) {
                        const cx = win.cellX(host.x), cy = win.cellY(host.y);
                        win.showGhost(cx, cy, host.gw, host.gh, Widgets.fits(cx, cy, host.gw, host.gh, host.wid), false);
                    }
                    onReleased: {
                        ghost.visible = false;
                        const cx = win.cellX(host.x), cy = win.cellY(host.y);
                        if (!(cx === host.gx && cy === host.gy)) Widgets.move(host.wid, cx, cy);
                        host.rebind();             // Behavior доведёт виджет до клетки пружинкой
                    }
                }

                // ручки размера по краям (только по тем осям, по которым виджет тянется)
                Repeater {
                    model: ["l", "r", "t", "b"]
                    Item {
                        id: handle
                        required property string modelData
                        readonly property bool horiz: modelData === "l" || modelData === "r"
                        readonly property bool can: horiz ? host.sp.minW < host.sp.maxW : host.sp.minH < host.sp.maxH
                        visible: can && Widgets.editing && !host.dragging
                        width: horiz ? 30 : 64; height: horiz ? 64 : 30
                        x: modelData === "l" ? -6 - width / 2 : modelData === "r" ? host.width + 6 - width / 2 : host.width / 2 - width / 2
                        y: modelData === "t" ? -6 - height / 2 : modelData === "b" ? host.height + 6 - height / 2 : host.height / 2 - height / 2
                        z: 5
                        Rectangle {
                            anchors.centerIn: parent
                            width: handle.horiz ? 10 : 40; height: handle.horiz ? 40 : 10; radius: 5
                            color: Theme.primaryText
                            border.width: 2; border.color: Qt.alpha(Theme.surfaceLowest, 0.6)
                            scale: host.hot ? (hm.containsMouse || hm.pressed ? 1.25 : 1) : 0
                            Behavior on scale { Anim { kind: "fast" } }
                        }
                        MouseArea {
                            id: hm
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: handle.horiz ? Qt.SizeHorCursor : Qt.SizeVerCursor
                            property var s0: null
                            onPressed: m => {
                                const g = mapToItem(null, m.x, m.y);
                                s0 = { x: host.x, y: host.y, w: host.width, h: host.height, mx: g.x, my: g.y };
                                host.resizing = true;
                            }
                            onPositionChanged: m => {
                                if (!pressed || !s0) return;
                                const g = mapToItem(null, m.x, m.y);
                                host.resizeTo(handle.modelData, g.x - s0.mx, g.y - s0.my, s0);
                            }
                            onReleased: { s0 = null; host.finishResize(); }
                            onCanceled: { s0 = null; host.target = null; host.finishResize(); }
                        }
                    }
                }

                // убрать
                Rectangle {
                    x: -14; y: -14
                    width: 32; height: 32; radius: 16
                    color: rmMouse.containsMouse ? Theme.error : Theme.surfaceHighest
                    border.width: 1; border.color: Qt.alpha(Theme.fg, 0.15)
                    scale: Widgets.editing && !host.dragging && !host.resizing ? 1 : 0
                    visible: scale > 0
                    z: 6
                    Behavior on scale { Anim { kind: "fast" } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Icon { anchors.centerIn: parent; name: "close"; size: 18; color: rmMouse.containsMouse ? Theme.surface : Theme.fg }
                    MouseArea { id: rmMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Widgets.remove(host.wid) }
                }
            }
        }

        // ── меню по правому клику: свои пункты виджета под курсором, затем общие
        Item {
            id: menu
            property bool shown: false
            property var items: []
            function openAt(mx, my, it) {
                const out = [];
                if (it) {
                    const sp = Widgets.spec(it.type);
                    const w = it.wid;
                    for (const m of (sp.menu || []))
                        out.push({ icon: m.icon, t: I18n.t(m.ru, m.en), run: () => Widgets.command(w, m.id) });
                    out.push({ icon: "delete", t: I18n.t("Убрать виджет", "Remove widget"), run: () => Widgets.remove(w), danger: true });
                    out.push({ sep: true });
                }
                out.push({ icon: "widgets", t: Widgets.editing ? I18n.t("Готово", "Done") : I18n.t("Изменить виджеты", "Edit widgets"),
                           run: () => { Widgets.editing = !Widgets.editing; } });
                out.push({ icon: "add_circle", t: I18n.t("Добавить виджет", "Add widget"), run: () => { Widgets.editing = true; Widgets.picking = true; } });
                out.push({ icon: "wallpaper", t: I18n.t("Обои и цвет темы", "Wallpaper & theme"), run: () => Quickshell.execDetached(["qs", "ipc", "-c", "glass", "call", "picker", "open"]) });
                out.push({ icon: "tune", t: I18n.t("Настройки оболочки", "Shell settings"), run: () => { Config.settingsOpen = true; } });
                items = out;
                x = Math.min(mx, win.width - width - 12);
                y = Math.min(my, win.height - (menuCol.implicitHeight + 16) - 12);
                shown = true;
            }
            width: 260
            height: menuCol.implicitHeight + 16
            z: 20
            opacity: shown ? 1 : 0
            scale: shown ? 1 : 0.9
            transformOrigin: Item.TopLeft
            visible: opacity > 0
            Behavior on opacity { Anim { kind: "effects" } }
            Behavior on scale { Anim { kind: "fast" } }

            // на одном слое с виджетами блюр Hyprland их не разделяет — подложка плотнее обычного стекла
            Rectangle { anchors.fill: parent; radius: 24; color: Qt.alpha(Theme.surfaceLow, 0.82) }
            GlassSurface { anchors.fill: parent; radius: 24; strong: true }
            Column {
                id: menuCol
                anchors { fill: parent; margins: 8 }
                Repeater {
                    model: menu.items
                    Item {
                        id: mi
                        required property var modelData
                        width: menuCol.width; height: modelData.sep ? 13 : 44
                        Rectangle { visible: !!mi.modelData.sep; anchors.centerIn: parent; width: parent.width - 24; height: 1; color: Qt.alpha(Theme.fg, 0.12) }
                        Rectangle {
                            visible: !mi.modelData.sep
                            anchors.fill: parent; radius: 16
                            color: miMouse.containsMouse ? (mi.modelData.danger ? Qt.alpha(Theme.error, 0.18) : Theme.glassChip) : "transparent"
                            Behavior on color { ColorAnimation { duration: 140 } }
                            Row {
                                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                spacing: 12
                                Icon { anchors.verticalCenter: parent.verticalCenter; name: mi.modelData.icon || ""; size: 20; color: mi.modelData.danger ? Theme.error : Theme.primaryText }
                                Label { anchors.verticalCenter: parent.verticalCenter; text: mi.modelData.t || ""; size: 14; weight: 600; elide: Text.ElideNone
                                        color: mi.modelData.danger ? Theme.error : Theme.fg }
                            }
                            MouseArea { id: miMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { menu.shown = false; mi.modelData.run(); } }
                        }
                    }
                }
            }
        }

        // ── панель правки: добавить / готово
        Row {
            id: editBar
            anchors.horizontalCenter: parent.horizontalCenter
            y: win.height - height - 28 + (Widgets.editing ? 0 : 90)
            spacing: 10
            z: 15
            opacity: Widgets.editing ? 1 : 0
            visible: opacity > 0
            Behavior on y { Anim { kind: "spatial" } }
            Behavior on opacity { Anim { kind: "effects" } }

            Repeater {
                model: [
                    { icon: "add", t: I18n.t("Добавить виджет", "Add widget"), primary: false, run: () => { Widgets.picking = !Widgets.picking; } },
                    { icon: "check", t: I18n.t("Готово", "Done"), primary: true, run: () => { Widgets.picking = false; Widgets.editing = false; } }
                ]
                Item {
                    required property var modelData
                    width: ebRow.implicitWidth + 40; height: 52
                    scale: ebMouse.pressed ? 0.95 : 1
                    Behavior on scale { Anim { kind: "fast" } }
                    GlassSurface { anchors.fill: parent; radius: 26; strong: true; visible: !parent.modelData.primary }
                    Rectangle { anchors.fill: parent; radius: 26; color: Theme.primary; visible: parent.modelData.primary }
                    Row {
                        id: ebRow
                        anchors.centerIn: parent
                        spacing: 8
                        Icon { anchors.verticalCenter: parent.verticalCenter; name: parent.parent.modelData.icon; size: 20; fill: 1
                               color: parent.parent.modelData.primary ? Theme.primaryFg : Theme.fg }
                        Label { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.modelData.t; size: 14; weight: 700; elide: Text.ElideNone
                                color: parent.parent.modelData.primary ? Theme.primaryFg : Theme.fg }
                    }
                    MouseArea { id: ebMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: parent.modelData.run() }
                }
            }
        }

        // ── каталог виджетов
        Item {
            id: sheet
            readonly property int perRow: Math.max(4, Math.min(8, Math.floor((width - 36 + 12) / 148)))
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(win.width - 80, 1240)
            height: 66 + Math.ceil(Widgets.catalog.length / perRow) * 116
            y: editBar.y - height - 16 + (Widgets.picking ? 0 : 30)
            z: 16
            opacity: Widgets.picking && Widgets.editing ? 1 : 0
            visible: opacity > 0
            Behavior on y { Anim { kind: "spatial" } }
            Behavior on opacity { Anim { kind: "effects" } }

            MouseArea { anchors.fill: parent }   // клики мимо карточек не уходят на рабочий стол
            Rectangle { anchors.fill: parent; radius: 36; color: Qt.alpha(Theme.surfaceLow, 0.82) }
            GlassSurface { anchors.fill: parent; radius: 36; strong: true }
            Label { x: 26; y: 18; text: I18n.t("Виджеты", "Widgets"); size: 16; weight: 750; color: Theme.primaryText; elide: Text.ElideNone }
            Label { anchors { right: parent.right; rightMargin: 26; top: parent.top; topMargin: 20 }
                    text: I18n.t("Размер — за ручки по краям виджета", "Resize with the handles on the edges"); size: 12; color: Theme.fgVariant; elide: Text.ElideNone }
            Grid {
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18; topMargin: 54 }
                columns: sheet.perRow
                spacing: 12
                Repeater {
                    model: Widgets.catalog
                    Rectangle {
                        id: cat
                        required property var modelData
                        width: (sheet.width - 36 - 12 * (sheet.perRow - 1)) / sheet.perRow
                        height: 104
                        radius: catMouse.pressed ? 18 : 26
                        color: catMouse.containsMouse ? Qt.alpha(Theme.primary, 0.22) : Theme.glassChip
                        Behavior on radius { Anim { kind: "fast" } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        scale: catMouse.pressed ? 0.95 : 1
                        Behavior on scale { Anim { kind: "fast" } }
                        Column {
                            anchors.centerIn: parent
                            width: parent.width - 16
                            spacing: 6
                            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: cat.modelData.icon; size: 30; fill: 1; color: Theme.primaryText }
                            Label { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: I18n.t(cat.modelData.ru, cat.modelData.en); size: 13; weight: 650 }
                            Label { anchors.horizontalCenter: parent.horizontalCenter; text: cat.modelData.w + " × " + cat.modelData.h; size: 11; color: Theme.fgVariant; elide: Text.ElideNone }
                        }
                        MouseArea { id: catMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { Widgets.add(cat.modelData.type); Widgets.picking = false; } }
                    }
                }
            }
        }
    }
}
