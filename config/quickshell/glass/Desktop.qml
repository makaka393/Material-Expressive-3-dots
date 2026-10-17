import QtQuick
import Quickshell
import Quickshell.Wayland

// Рабочий стол: виджеты под окнами (слой Bottom — над обоями, под окнами).
// Правый клик по пустому месту — меню; в режиме правки видна точечная сетка, виджеты
// перетаскиваются (встают в клетки), удаляются крестиком, добавляются из каталога снизу.
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
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: Widgets.editing ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        // сетка: клетка 96 px и зазор 16 → шаг 112
        readonly property int margin: 28
        readonly property int gap: 16
        readonly property int pitch: 112
        readonly property int cols: Math.max(1, Math.floor((width - 2 * margin + gap) / pitch))
        readonly property int rows: Math.max(1, Math.floor((height - 2 * margin + gap) / pitch))
        readonly property bool main: modelData === Quickshell.screens[0]
        Binding { when: win.main && win.width > 0; target: Widgets; property: "cols"; value: win.cols }
        Binding { when: win.main && win.height > 0; target: Widgets; property: "rows"; value: win.rows }
        function px(c) { return margin + c * pitch; }
        function cell(p) { return Math.round((p - margin) / pitch); }

        SystemClock { id: clock; precision: SystemClock.Minutes }

        // ── пустое место
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: m => {
                if (m.button === Qt.RightButton) { menu.openAt(m.x, m.y); return; }
                if (menu.shown) menu.shown = false;
                else if (sheet.shown) sheet.shown = false;
            }
        }
        Item {
            anchors.fill: parent
            focus: Widgets.editing
            Keys.onEscapePressed: { if (sheet.shown) sheet.shown = false; else Widgets.editing = false; }
        }

        // ── точечная сетка в правке: точки разбегаются волной из центра
        Item {
            id: dots
            anchors.fill: parent
            visible: Widgets.editing || dotsFade.running
            Repeater {
                model: Widgets.editing || dotsFade.running ? (win.cols + 1) * (win.rows + 1) : 0
                Rectangle {
                    required property int index
                    readonly property int cx: index % (win.cols + 1)
                    readonly property int cy: Math.floor(index / (win.cols + 1))
                    readonly property real delay: Math.hypot(cx - win.cols / 2, cy - win.rows / 2) * 22
                    x: win.margin + cx * win.pitch - win.gap / 2 - width / 2
                    y: win.margin + cy * win.pitch - win.gap / 2 - height / 2
                    width: 5; height: 5; radius: 2.5
                    color: Qt.alpha(Theme.fg, 0.6)
                    scale: 0
                    Component.onCompleted: scale = Qt.binding(() => Widgets.editing ? 1 : 0)
                    Behavior on scale {
                        SequentialAnimation {
                            PauseAnimation { duration: Widgets.editing ? delay : 0 }
                            NumberAnimation { duration: 380; easing.type: Easing.OutBack; easing.overshoot: 2 }
                        }
                    }
                }
            }
            Timer { id: dotsFade; interval: 420 }
            Connections { target: Widgets; function onEditingChanged() { if (!Widgets.editing) dotsFade.restart(); } }
        }

        // ── куда встанет перетаскиваемый виджет
        Rectangle {
            id: ghost
            property bool ok: true
            visible: false
            radius: 40
            color: Qt.alpha(ok ? Theme.primary : Theme.error, 0.16)
            border.width: 2
            border.color: Qt.alpha(ok ? Theme.primary : Theme.error, 0.7)
            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
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
                readonly property var sp: Widgets.spec(type)
                readonly property bool leaving: Widgets.leaving === wid
                readonly property bool dragging: drag.drag.active

                width: sp.w * win.pitch - win.gap
                height: sp.h * win.pitch - win.gap
                x: win.px(gx)
                y: win.px(gy)
                z: dragging ? 10 : 1
                Behavior on x { enabled: !host.dragging; Anim { kind: "spatial" } }
                Behavior on y { enabled: !host.dragging; Anim { kind: "spatial" } }

                // появление: при старте — по очереди, новый — с пружинкой
                property real appear: 0
                Component.onCompleted: {
                    pop.delay = Widgets.fresh === wid ? 0 : 120 + index * 80;
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
                scale: (leaving ? 0.55 : 0.55 + 0.45 * appear) * (Widgets.editing && !dragging ? 0.94 : dragging ? 1.04 : 1)
                Behavior on opacity { enabled: host.leaving; NumberAnimation { duration: 260; easing.type: Easing.InCubic } }
                Behavior on scale { enabled: host.leaving || host.appear >= 1; Anim { kind: "fast" } }

                Loader {
                    anchors.fill: parent
                    sourceComponent: host.type === "glance" ? glanceC : host.type === "clock" ? clockC
                                   : host.type === "weather" ? weatherC : host.type === "music" ? musicC : calendarC
                    // в правке виджеты не нажимаются — только двигаются
                    enabled: !Widgets.editing
                }
                Component { id: glanceC; WGlance { now: clock.date } }
                Component { id: clockC; WClock { now: clock.date } }
                Component { id: weatherC; WWeather {} }
                Component { id: musicC; WMusic {} }
                Component { id: calendarC; WCalendar { now: clock.date } }

                // рамка в правке
                Rectangle {
                    anchors { fill: parent; margins: -6 }
                    radius: 48
                    color: "transparent"
                    border.width: 2
                    border.color: Qt.alpha(Theme.primary, host.dragging ? 0.9 : 0.55)
                    opacity: Widgets.editing ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { Anim { kind: "effects" } }
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
                        const cx = win.cell(host.x), cy = win.cell(host.y);
                        ghost.ok = Widgets.fits(host.type, cx, cy, host.wid);
                        ghost.x = win.px(Math.max(0, Math.min(Widgets.cols - host.sp.w, cx)));
                        ghost.y = win.px(Math.max(0, Math.min(Widgets.rows - host.sp.h, cy)));
                        ghost.width = host.width; ghost.height = host.height;
                        ghost.visible = true;
                    }
                    onReleased: {
                        ghost.visible = false;
                        const cx = win.cell(host.x), cy = win.cell(host.y);
                        if (!(cx === host.gx && cy === host.gy)) Widgets.move(host.wid, cx, cy);
                        // вернуть привязку к клетке (Behavior доведёт виджет пружинкой)
                        host.x = Qt.binding(() => win.px(host.gx));
                        host.y = Qt.binding(() => win.px(host.gy));
                    }
                }

                // убрать
                Rectangle {
                    x: -14; y: -14
                    width: 32; height: 32; radius: 16
                    color: rmMouse.containsMouse ? Theme.error : Theme.surfaceHighest
                    border.width: 1; border.color: Qt.alpha(Theme.fg, 0.15)
                    scale: Widgets.editing && !host.dragging ? 1 : 0
                    visible: scale > 0
                    Behavior on scale { Anim { kind: "fast" } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Icon { anchors.centerIn: parent; name: "close"; size: 18; color: rmMouse.containsMouse ? Theme.surface : Theme.fg }
                    MouseArea { id: rmMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Widgets.remove(host.wid) }
                }
            }
        }

        // ── меню по правому клику
        Item {
            id: menu
            property bool shown: false
            function openAt(mx, my) {
                x = Math.min(mx, win.width - width - 12);
                y = Math.min(my, win.height - height - 12);
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

            GlassSurface { anchors.fill: parent; radius: 24; strong: true }
            Column {
                id: menuCol
                anchors { fill: parent; margins: 8 }
                Repeater {
                    model: [
                        { icon: "widgets", t: I18n.t("Изменить виджеты", "Edit widgets"), run: () => { Widgets.editing = true; } },
                        { icon: "add_circle", t: I18n.t("Добавить виджет", "Add widget"), run: () => { Widgets.editing = true; sheet.shown = true; } },
                        { icon: "wallpaper", t: I18n.t("Обои и цвет темы", "Wallpaper & theme"), run: () => Quickshell.execDetached(["qs", "ipc", "-c", "glass", "call", "picker", "open"]) },
                        { icon: "tune", t: I18n.t("Настройки оболочки", "Shell settings"), run: () => { Config.settingsOpen = true; } }
                    ]
                    Rectangle {
                        required property var modelData
                        width: menuCol.width; height: 44; radius: 16
                        color: miMouse.containsMouse ? Theme.glassChip : "transparent"
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Row {
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 12
                            Icon { anchors.verticalCenter: parent.verticalCenter; name: parent.parent.modelData.icon; size: 20; color: Theme.primary }
                            Label { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.modelData.t; size: 14; weight: 600; elide: Text.ElideNone }
                        }
                        MouseArea { id: miMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { menu.shown = false; parent.modelData.run(); } }
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
                    { icon: "add", t: I18n.t("Добавить виджет", "Add widget"), primary: false, run: () => { sheet.shown = !sheet.shown; } },
                    { icon: "check", t: I18n.t("Готово", "Done"), primary: true, run: () => { sheet.shown = false; Widgets.editing = false; } }
                ]
                Item {
                    required property var modelData
                    width: ebRow.implicitWidth + 40; height: 52
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
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: parent.modelData.run() }
                }
            }
        }

        // ── каталог виджетов
        Item {
            id: sheet
            property bool shown: false
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(win.width - 80, 900)
            height: 176
            y: editBar.y - height - 16 + (shown ? 0 : 30)
            z: 16
            opacity: shown && Widgets.editing ? 1 : 0
            visible: opacity > 0
            Behavior on y { Anim { kind: "spatial" } }
            Behavior on opacity { Anim { kind: "effects" } }

            GlassSurface { anchors.fill: parent; radius: 36; strong: true }
            Label { x: 26; y: 16; text: I18n.t("Виджеты", "Widgets"); size: 16; weight: 750; color: Theme.primary; elide: Text.ElideNone }
            Row {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 18; topMargin: 50 }
                spacing: 12
                Repeater {
                    model: Widgets.catalog
                    Rectangle {
                        id: cat
                        required property var modelData
                        width: (sheet.width - 36 - 12 * (Widgets.catalog.length - 1)) / Widgets.catalog.length
                        height: 104
                        radius: catMouse.pressed ? 18 : 26
                        color: catMouse.containsMouse ? Qt.alpha(Theme.primary, 0.2) : Theme.glassChip
                        Behavior on radius { Anim { kind: "fast" } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        scale: catMouse.pressed ? 0.95 : 1
                        Behavior on scale { Anim { kind: "fast" } }
                        Column {
                            anchors.centerIn: parent
                            spacing: 6
                            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: cat.modelData.icon; size: 30; fill: 1; color: Theme.primary }
                            Label { anchors.horizontalCenter: parent.horizontalCenter; text: I18n.t(cat.modelData.ru, cat.modelData.en); size: 13; weight: 650; elide: Text.ElideNone }
                            Label { anchors.horizontalCenter: parent.horizontalCenter; text: cat.modelData.w + " × " + cat.modelData.h; size: 11; color: Theme.fgVariant; elide: Text.ElideNone }
                        }
                        MouseArea { id: catMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { Widgets.add(cat.modelData.type); sheet.shown = false; } }
                    }
                }
            }
        }
    }
}
