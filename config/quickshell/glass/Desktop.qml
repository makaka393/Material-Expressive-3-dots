import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// Рабочий стол: виджеты под окнами (слой Bottom — над обоями, под окнами), на главном экране.
// Правый клик по пустому месту или по виджету — меню. В режиме правки рабочий стол встаёт над
// окнами: обои закрывают их и плавно расфокусируются, проявляется светящаяся сетка; виджеты
// переносятся (встают в клетки), меняют размер за ручки по краям, настраиваются («Настроить»:
// фон, цвет, прозрачность, стиль — как на Samsung), удаляются крестиком, добавляются из каталога.
//
// Размытые обои считаются здесь один раз на смену обоев (MultiEffect) — это подложка «стекла»
// виджетов (glassBackdrop — берут только виджеты этого окна) и фон правки. Своё гладкое размытие вместо блюра Hyprland: без зерна
// и без ореолов вокруг текста.
Variants {
    model: Quickshell.screens.slice(0, 1)

    PanelWindow {
        id: win
        required property var modelData
        screen: modelData

        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore          // на весь экран: фон правки закрывает и полосу бара
        color: "transparent"
        WlrLayershell.namespace: "quickshell-desktop"
        // в правке (и пока фон правки уходит) — над окнами, иначе — под ними
        WlrLayershell.layer: Widgets.editing || editFx.veil > 0.001 ? WlrLayer.Top : WlrLayer.Bottom
        // клавиатура нужна в правке (Esc) и в заметке. В первый миг — Exclusive: так Hyprland отдаёт
        // фокус сразу, без второго клика; потом OnDemand — клик по окну забирает фокус обратно
        readonly property bool wantKeys: Widgets.editing || Widgets.typing
        property bool grab: false
        onWantKeysChanged: if (wantKeys) { grab = true; grabTimer.restart(); }
        Timer { id: grabTimer; interval: 300; onTriggered: win.grab = false }
        WlrLayershell.keyboardFocus: !wantKeys ? WlrKeyboardFocus.None : grab ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

        // сетка: клетка 96 px и зазор 16 → шаг 112, по центру экрана под баром
        readonly property int top: Theme.barHeight + Theme.outer + 2          // как exclusiveZone бара
        readonly property int edge: 28
        readonly property int gap: 16
        readonly property int pitch: 112
        readonly property int cols: Math.max(1, Math.floor((width - 2 * edge + gap) / pitch))
        readonly property int rows: Math.max(1, Math.floor((height - top - 2 * edge + gap) / pitch))
        readonly property real ox: Math.round((width - (cols * pitch - gap)) / 2)
        readonly property real oy: top + Math.round((height - top - (rows * pitch - gap)) / 2)
        Binding { when: win.width > 0; target: Widgets; property: "cols"; value: win.cols }
        Binding { when: win.height > 0; target: Widgets; property: "rows"; value: win.rows }
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

        // ── обои: чёткие и размытые (половина разрешения — дальше всё равно размытие)
        Item {
            id: wallBox
            width: Math.max(1, win.width / 2); height: Math.max(1, win.height / 2)
            Image {
                anchors.fill: parent
                source: Locker.frameFile !== "" ? "file://" + Locker.frameFile + "?" + Locker.frameRev : ""
                fillMode: Image.PreserveAspectCrop          // как awww (crop) и mpvpaper (panscan=1)
                sourceSize.width: 1280
                asynchronous: true
                cache: false
                smooth: true
            }
        }
        ShaderEffectSource { id: sharpTex; sourceItem: wallBox; hideSource: true; live: true; smooth: true; visible: false; width: 1; height: 1 }
        MultiEffect {
            id: wallBlur
            width: wallBox.width; height: wallBox.height
            source: sharpTex
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1.0
            blurMax: 48
            saturation: 0.08
        }
        ShaderEffectSource { id: blurTex; sourceItem: wallBlur; hideSource: true; live: true; smooth: true; visible: false; width: 1; height: 1 }
        readonly property var glassBackdrop: blurTex

        // AOD на этом экране — виджеты гаснут: на затемнённых обоях остаются только часы AOD
        readonly property bool underAod: Config.aodScreen !== "" && !!win.screen && Config.aodScreen === win.screen.name
        property real widgetsShown: underAod ? 0 : 1
        Behavior on widgetsShown { NumberAnimation { duration: win.underAod ? 700 : 280; easing.type: Easing.OutCubic } }

        // ── средний цвет обоев по участкам ~32×32 px (обои кадрируются по центру, как у awww):
        // по нему виджеты подбирают цвет текста — тёмный на светлых обоях, светлый на тёмных
        // (WidgetSurface.under). Считается раз на смену обоев
        property var wallCells: null           // { w, h, px: [r, g, b, …] 0…1 }
        Process {
            id: wallProc
            readonly property int cw: Math.max(1, Math.round(win.width / 32))
            readonly property int ch: Math.max(1, Math.round(win.height / 32))
            readonly property string key: Locker.frameFile + "|" + Locker.frameRev + "|" + cw + "x" + ch
            property bool again: false
            function refresh() { if (Locker.frameFile === "" || win.width <= 0) return; if (running) again = true; else running = true; }
            onKeyChanged: Qt.callLater(refresh)
            onRunningChanged: if (!running && again) { again = false; running = true; }
            command: ["magick", Locker.frameFile, "-resize", cw + "x" + ch + "^", "-gravity", "center", "-extent", cw + "x" + ch,
                      "-depth", "8", "-compress", "none", "ppm:-"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const n = text.trim().split(/\s+/);
                    if (n[0] !== "P3" || n.length < 4) return;
                    const mx = +n[3] || 255;
                    win.wallCells = { w: +n[1], h: +n[2], px: n.slice(4).map(v => v / mx) };
                }
            }
        }
        // средний цвет обоев в прямоугольнике окна (до первого расчёта — тёмный, как у темы)
        function wallAt(x, y, w, h) {
            const c = wallCells;
            if (!c || c.w < 1 || c.px.length < c.w * c.h * 3) return Theme.surfaceLowest;
            const x0 = Math.max(0, Math.floor(x / win.width * c.w)), x1 = Math.min(c.w - 1, Math.ceil((x + w) / win.width * c.w) - 1);
            const y0 = Math.max(0, Math.floor(y / win.height * c.h)), y1 = Math.min(c.h - 1, Math.ceil((y + h) / win.height * c.h) - 1);
            let r = 0, g = 0, b = 0, k = 0;
            for (let j = y0; j <= y1; j++)
                for (let i = x0; i <= x1; i++) { const o = (j * c.w + i) * 3; r += c.px[o]; g += c.px[o + 1]; b += c.px[o + 2]; k++; }
            return k > 0 ? Qt.rgba(r / k, g / k, b / k, 1) : Theme.surfaceLowest;
        }

        // ── пустое место
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: m => {
                if (m.button === Qt.RightButton) { menu.openAt(m.x, m.y, win.widgetAt(m.x, m.y)); return; }
                if (menu.shown) menu.shown = false;
                else if (Widgets.tuning !== "") Widgets.tuning = "";
                else if (Widgets.picking) Widgets.picking = false;
                else if (Widgets.typing) Widgets.typing = false;
            }
        }
        Item {
            anchors.fill: parent
            focus: Widgets.editing
            Keys.onEscapePressed: {
                if (menu.shown) menu.shown = false;
                else if (Widgets.tuning !== "") Widgets.tuning = "";
                else if (Widgets.picking) Widgets.picking = false;
                else Widgets.editing = false;
            }
            HoverHandler { id: hover; enabled: Widgets.editing }
        }

        // ── фон правки: обои закрывают окна и расфокусируются, поверх — светящаяся сетка
        Item {
            id: editFx
            anchors.fill: parent
            property real veil: Widgets.editing ? 1 : 0
            property real blurAmt: Widgets.editing ? 1 : 0
            property real progress: Widgets.editing ? 1 : 0
            Behavior on veil { NumberAnimation { duration: Widgets.editing ? 320 : 380; easing.type: Easing.OutCubic } }
            Behavior on blurAmt { NumberAnimation { duration: Widgets.editing ? 700 : 300; easing.type: Easing.OutCubic } }
            Behavior on progress { NumberAnimation { duration: Widgets.editing ? 1000 : 300; easing.type: Easing.OutCubic } }
            visible: veil > 0.001
            ShaderEffect {
                anchors.fill: parent
                fragmentShader: "shaders/griddots.frag.qsb"
                property vector2d res: Qt.vector2d(width, height)
                property vector2d start: Qt.vector2d(win.ox - win.gap / 2, win.oy - win.gap / 2)
                property vector2d count: Qt.vector2d(win.cols, win.rows)
                property real pitch: win.pitch
                property real progress: editFx.progress
                property vector2d mouse: hover.hovered ? Qt.vector2d(hover.point.position.x, hover.point.position.y) : Qt.vector2d(-9999, -9999)
                property real veil: editFx.veil
                property real blurAmt: editFx.blurAmt
                property real dim: 0.28
                property color tint: Qt.hsla(Theme.primary.hslHue, Math.max(0.35, Theme.primary.hslSaturation), 0.84, 1)
                property color shade: Theme.surfaceLowest
                property var sharp: sharpTex
                property var blurred: blurTex
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
            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
        // размер в клетках — над призраком (сам призрак почти весь под тянущимся виджетом)
        Rectangle {
            visible: ghost.visible && ghost.size !== ""
            z: 30
            x: ghost.x + ghost.width / 2 - width / 2
            y: ghost.y >= win.top + 60 ? ghost.y - height - 14 : ghost.y + ghost.height + 14
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

        // ── сами виджеты (общие для стола и превью в каталоге)
        readonly property var comps: ({ glance: glanceC, clock: clockC, weather: weatherC, forecast: forecastC, music: musicC,
                                         calendar: calendarC, search: searchC, apps: appsC, toggles: togglesC, system: systemC,
                                         timer: timerC, note: noteC, sun: sunC, photo: photoC, progress: progressC })
        Component { id: glanceC; WGlance {} }
        Component { id: clockC; WClock {} }
        Component { id: weatherC; WWeather {} }
        Component { id: forecastC; WForecast {} }
        Component { id: musicC; WMusic {} }
        Component { id: calendarC; WCalendar {} }
        Component { id: searchC; WSearch {} }
        Component { id: appsC; WApps {} }
        Component { id: togglesC; WToggles {} }
        Component { id: systemC; WSystem {} }
        Component { id: timerC; WTimer {} }
        Component { id: noteC; WNote {} }
        Component { id: sunC; WSun {} }
        Component { id: photoC; WPhoto {} }
        Component { id: progressC; WProgress {} }

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
                readonly property bool tuned: Widgets.tuning === wid
                property bool resizing: false
                readonly property bool hot: Widgets.editing && (hostHover.hovered || resizing || dragging || tuned)
                // средний цвет обоев под виджетом (по клеткам, а не по x/y — не пересчитывается на каждом
                // кадре переноса): по нему WidgetSurface выбирает цвет текста
                readonly property color wallUnder: win.wallAt(win.px(gx), win.py(gy), win.span(gw), win.span(gh))

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
                // вход в правку — волной от центра экрана, как «вдох» домашнего экрана
                property real editK: Widgets.editing ? 1 : 0
                readonly property int wave: Math.round(Math.hypot(x + width / 2 - win.width / 2, y + height / 2 - win.height / 2) / 9)
                Behavior on editK {
                    SequentialAnimation {
                        PauseAnimation { duration: Widgets.editing ? host.wave : 0 }
                        NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                    }
                }

                opacity: (leaving ? 0 : Math.min(1, appear * 1.6)) * win.widgetsShown
                scale: (leaving ? 0.55 : 0.55 + 0.45 * appear) * (dragging ? 1.04 : resizing ? 1 : 1 - 0.05 * editK)
                Behavior on opacity { enabled: host.leaving; NumberAnimation { duration: 260; easing.type: Easing.InCubic } }

                // наведение — шире самого виджета: ручки торчат за край
                Item {
                    anchors { fill: parent; margins: -30 }
                    HoverHandler { id: hostHover; enabled: Widgets.editing }
                }

                Loader {
                    id: content
                    anchors.fill: parent
                    sourceComponent: win.comps[host.type] ?? glanceC
                    // в правке виджеты не нажимаются — только двигаются, тянутся и настраиваются
                    enabled: !Widgets.editing
                }
                Binding { target: content.item; property: "now"; value: clock.date; when: !!content.item }
                Binding { target: content.item; property: "wid"; value: host.wid; when: !!content.item }
                Binding { target: content.item; property: "cfg"; value: host.cfg; when: !!content.item }

                // рамка в правке
                Rectangle {
                    anchors { fill: parent; margins: -6 }
                    radius: Math.min(50, height / 2)
                    color: "transparent"
                    border.width: host.tuned ? 3 : 2
                    border.color: Qt.alpha(Theme.primaryText, host.hot ? 0.95 : 0.4)
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
                    // клик без переноса — настроить этот виджет
                    onClicked: Widgets.tuning = Widgets.tuning === host.wid ? "" : host.wid
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

                // убрать (слева) и настроить (справа)
                Repeater {
                    model: [{ icon: "close", left: true }, { icon: "tune", left: false }]
                    Rectangle {
                        id: corner
                        required property var modelData
                        x: modelData.left ? -14 : host.width - 18
                        y: -14
                        width: 32; height: 32; radius: cm.pressed ? 10 : 16
                        color: modelData.left ? (cm.containsMouse ? Theme.error : Theme.surfaceHighest)
                             : (host.tuned || cm.containsMouse ? Theme.primary : Theme.surfaceHighest)
                        border.width: 1; border.color: Qt.alpha(Theme.fg, 0.15)
                        scale: Widgets.editing && !host.dragging && !host.resizing ? 1 : 0
                        visible: scale > 0
                        z: 6
                        Behavior on scale { Anim { kind: "fast" } }
                        Behavior on radius { Anim { kind: "fast" } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Icon { anchors.centerIn: parent; name: corner.modelData.icon; size: 18; fill: 1
                               color: corner.modelData.left ? (cm.containsMouse ? Theme.surface : Theme.fg)
                                    : (host.tuned || cm.containsMouse ? Theme.primaryFg : Theme.fg) }
                        MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: corner.modelData.left ? Widgets.remove(host.wid) : (Widgets.tuning = host.tuned ? "" : host.wid) }
                    }
                }
            }
        }

        // ── «Настроить»: панель рядом с виджетом
        WidgetTuner {
            id: tuner
            z: 18
            wid: Widgets.tuning
            readonly property var it: { Widgets.rev; const i = Widgets.indexOf(Widgets.tuning); return i >= 0 ? Widgets.model.get(i) : null; }
            readonly property real wx: it ? win.px(it.gx) : 0
            readonly property real wy: it ? win.py(it.gy) : 0
            readonly property real ww: it ? win.span(it.gw) : 0
            x: !it ? x : wx + ww + 28 + width < win.width - 20 ? wx + ww + 28 : Math.max(20, wx - width - 28)
            y: !it ? y : Math.max(win.top + 16, Math.min(win.height - height - 100, wy - 10))
            Behavior on x { enabled: tuner.shown; Anim { kind: "spatial" } }
            Behavior on y { enabled: tuner.shown; Anim { kind: "spatial" } }
            now: clock.date
            shown: Widgets.editing && !!it
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
                    out.push({ icon: "tune", t: I18n.t("Настроить", "Customize"), run: () => { Widgets.editing = true; Widgets.tuning = w; } });
                    for (const m of (sp.menu || []))
                        out.push({ icon: m.icon, t: I18n.t(m.ru, m.en), run: () => Widgets.command(w, m.id) });
                    out.push({ icon: "delete", t: I18n.t("Убрать виджет", "Remove widget"), run: () => Widgets.remove(w), danger: true });
                    out.push({ sep: true });
                }
                out.push({ icon: "widgets", t: Widgets.editing ? I18n.t("Готово", "Done") : I18n.t("Изменить виджеты", "Edit widgets"),
                           run: () => { Widgets.editing = !Widgets.editing; } });
                out.push({ icon: "add_circle", t: I18n.t("Добавить виджет", "Add widget"), run: () => { Widgets.editing = true; Widgets.picking = true; } });
                out.push({ icon: "wallpaper", t: I18n.t("Обои и цвет темы", "Wallpaper & theme"), run: () => Quickshell.execDetached(["qs", "ipc", "-c", "glass", "call", "picker", "open"]) });
                out.push({ icon: "settings", t: I18n.t("Настройки оболочки", "Shell settings"), run: () => { Config.settingsOpen = true; } });
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

            // блюра Hyprland на этом слое нет (иначе ореолы вокруг текста на обоях) — стекло из своих
            // размытых обоев, как у виджетов, с прозрачностью темы
            WidgetSurface { anchors.fill: parent; radius: 24; tone: "neutral"; cfg: ({ alpha: Theme.glassStrong.a }) }
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
                    { icon: "check", t: I18n.t("Готово", "Done"), primary: true, run: () => { Widgets.editing = false; } }
                ]
                Item {
                    id: eb
                    required property var modelData
                    width: ebRow.implicitWidth + 40; height: 52
                    scale: ebMouse.pressed ? 0.95 : 1
                    Behavior on scale { Anim { kind: "fast" } }
                    WidgetSurface { anchors.fill: parent; radius: ebMouse.pressed ? 16 : 26; visible: !eb.modelData.primary
                                    tone: "neutral"; cfg: ({ alpha: Theme.glassStrong.a })
                                    Behavior on radius { Anim { kind: "fast" } } }
                    Rectangle { anchors.fill: parent; radius: ebMouse.pressed ? 16 : 26; color: Theme.primary; visible: eb.modelData.primary
                                Behavior on radius { Anim { kind: "fast" } } }
                    Row {
                        id: ebRow
                        anchors.centerIn: parent
                        spacing: 8
                        Icon { anchors.verticalCenter: parent.verticalCenter; name: eb.modelData.icon; size: 20; fill: 1
                               color: eb.modelData.primary ? Theme.primaryFg : Theme.fg }
                        Label { anchors.verticalCenter: parent.verticalCenter; text: eb.modelData.t; size: 14; weight: 700; elide: Text.ElideNone
                                color: eb.modelData.primary ? Theme.primaryFg : Theme.fg }
                    }
                    MouseArea { id: ebMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: eb.modelData.run() }
                }
            }
        }

        // ── каталог: слева вкладки — виды виджетов по категориям, справа — варианты этого вида живыми
        // превью (размеры и стили). Превью создаются, только пока каталог открыт.
        Item {
            id: sheet
            readonly property var cur: Widgets.spec(Widgets.pickType)
            readonly property real k: 0.5                      // масштаб превью: клетка 112 → 56
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(win.width - 80, 1240)
            height: Math.min(win.height - win.top - 140, 600)
            y: editBar.y - height - 16 + (Widgets.picking ? 0 : 50)
            z: 16
            transformOrigin: Item.Bottom
            opacity: Widgets.picking && Widgets.editing ? 1 : 0
            scale: Widgets.picking ? 1 : 0.94
            visible: opacity > 0
            Behavior on y { Anim { kind: "spatial" } }
            Behavior on scale { Anim { kind: "spatial" } }
            Behavior on opacity { Anim { kind: "effects" } }

            MouseArea { anchors.fill: parent }   // клики мимо карточек не уходят на рабочий стол
            WidgetSurface { anchors.fill: parent; radius: 36; tone: "neutral"; cfg: ({ alpha: Theme.glassStrong.a }) }

            // ── вкладки
            Flickable {
                id: tabs
                x: 14; y: 14
                width: 268; height: parent.height - 28
                contentHeight: tabCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: tabCol
                    width: parent.width
                    spacing: 2
                    Label { leftPadding: 14; topPadding: 6; bottomPadding: 2; text: I18n.t("Виджеты", "Widgets"); size: 18; weight: 750; color: Theme.primaryText; elide: Text.ElideNone }
                    Repeater {
                        model: Widgets.categories
                        Column {
                            id: catCol
                            required property var modelData
                            width: tabCol.width
                            spacing: 2
                            Label { leftPadding: 16; topPadding: 12; bottomPadding: 4; text: I18n.t(catCol.modelData.ru, catCol.modelData.en)
                                    size: 12; weight: 700; color: Theme.fgVariant; elide: Text.ElideNone }
                            Repeater {
                                model: Widgets.inCategory(catCol.modelData.id)
                                Rectangle {
                                    id: tab
                                    required property var modelData
                                    readonly property bool on: Widgets.pickType === modelData.type
                                    width: catCol.width; height: 46
                                    radius: tabMouse.pressed ? 12 : on ? 23 : 16
                                    color: on ? Theme.secondaryContainer : tabMouse.containsMouse ? Theme.glassChip : "transparent"
                                    Behavior on radius { Anim { kind: "fast" } }
                                    Behavior on color { ColorAnimation { duration: 180 } }
                                    Icon { id: tabIcon; anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                                           name: tab.modelData.icon; size: 20; fill: tab.on ? 1 : 0
                                           color: tab.on ? Theme.secondaryContainerFg : Theme.fg }
                                    Label { anchors { left: tabIcon.right; leftMargin: 12; right: tabCount.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                            text: I18n.t(tab.modelData.ru, tab.modelData.en); size: 14; weight: tab.on ? 700 : 550
                                            color: tab.on ? Theme.secondaryContainerFg : Theme.fg }
                                    Label { id: tabCount; anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                                            text: (tab.modelData.variants || []).length; size: 12; weight: 650
                                            color: tab.on ? Qt.alpha(Theme.secondaryContainerFg, 0.7) : Theme.fgVariant; elide: Text.ElideNone }
                                    MouseArea { id: tabMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: Widgets.pickType = tab.modelData.type }
                                }
                            }
                        }
                    }
                }
            }

            // ── варианты выбранного вида
            Item {
                id: pane
                anchors { left: tabs.right; leftMargin: 16; right: parent.right; rightMargin: 20; top: parent.top; topMargin: 22; bottom: parent.bottom; bottomMargin: 16 }
                Rectangle {
                    id: paneBadge
                    width: 44; height: 44; radius: 16
                    color: Theme.primaryContainer
                    Icon { anchors.centerIn: parent; name: sheet.cur.icon; size: 24; fill: 1; color: Theme.primaryContainerFg }
                }
                Column {
                    anchors { left: paneBadge.right; leftMargin: 12; right: parent.right; verticalCenter: paneBadge.verticalCenter }
                    Label { width: parent.width; text: I18n.t(sheet.cur.ru, sheet.cur.en); size: 18; weight: 750 }
                    Label { width: parent.width; size: 12; color: Theme.fgVariant
                            text: I18n.t("Выбери вариант — встанет на свободное место. Размер — за ручки, вид — «Настроить»",
                                         "Pick a variant — it lands on a free spot. Resize with the handles, restyle with Customize") }
                }
                Flickable {
                    anchors { fill: parent; topMargin: 62 }
                    contentHeight: vflow.implicitHeight + 8
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Flow {
                        id: vflow
                        width: parent.width
                        spacing: 14
                        Repeater {
                            model: Widgets.picking ? (sheet.cur.variants || []) : []
                            Rectangle {
                                id: vc
                                required property var modelData
                                required property int index
                                readonly property real pw: win.span(modelData.w) * sheet.k
                                readonly property real ph: win.span(modelData.h) * sheet.k
                                width: Math.max(150, pw + 28); height: ph + 66
                                radius: vm.pressed ? 18 : 28
                                color: vm.containsMouse ? Qt.alpha(Theme.primary, 0.2) : Theme.glassChip
                                Behavior on radius { Anim { kind: "fast" } }
                                Behavior on color { ColorAnimation { duration: 150 } }
                                // карточки выезжают по очереди с пружинкой
                                opacity: 0
                                scale: 0.88
                                Component.onCompleted: appear.start()
                                SequentialAnimation {
                                    id: appear
                                    PauseAnimation { duration: vc.index * 45 }
                                    ParallelAnimation {
                                        NumberAnimation { target: vc; property: "opacity"; to: 1; duration: 220 }
                                        NumberAnimation { target: vc; property: "scale"; to: 1; duration: 460; easing.type: Easing.OutBack; easing.overshoot: 1.5 }
                                    }
                                }
                                Item {
                                    id: vp
                                    x: (parent.width - vc.pw) / 2; y: 14
                                    width: vc.pw; height: vc.ph
                                    scale: vm.pressed ? 0.95 : 1
                                    Behavior on scale { Anim { kind: "fast" } }
                                    Loader {
                                        id: vl
                                        width: win.span(vc.modelData.w); height: win.span(vc.modelData.h)
                                        scale: sheet.k
                                        transformOrigin: Item.TopLeft
                                        enabled: false
                                        sourceComponent: win.comps[Widgets.pickType] ?? null
                                    }
                                    Binding { target: vl.item; property: "now"; value: clock.date; when: !!vl.item }
                                    Binding { target: vl.item; property: "cfg"; value: vc.modelData.extra || ({}); when: !!vl.item }
                                }
                                Label { anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 28 }
                                        width: parent.width - 16; horizontalAlignment: Text.AlignHCenter
                                        text: I18n.t(vc.modelData.ru, vc.modelData.en); size: 13; weight: 650 }
                                Label { anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 10 }
                                        text: vc.modelData.w + " × " + vc.modelData.h; size: 11; color: Theme.fgVariant; elide: Text.ElideNone }
                                MouseArea { id: vm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: { Widgets.add(Widgets.pickType, vc.modelData.w, vc.modelData.h, vc.modelData.extra); Widgets.picking = false; } }
                            }
                        }
                    }
                }
            }
        }
    }
}
