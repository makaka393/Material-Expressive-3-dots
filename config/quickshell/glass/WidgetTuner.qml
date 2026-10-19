import QtQuick

// Панель «Настроить» виджета в режиме правки — как настройки виджетов на Samsung, в духе
// M3 Expressive: стиль (циферблат часов, форма фото, период «Дня и года»), подложка (размытие /
// цвет / без фона), цвет темы и прозрачность. Всё меняется сразу и плавно; «Сбросить» — как у оболочки.
Item {
    id: t
    property string wid: ""
    property bool shown: false
    property date now: new Date()

    // пока панель уезжает, показываем то, что было (wid уже пустой)
    property string cur: ""
    onWidChanged: if (wid !== "") cur = wid
    readonly property var entry: { Widgets.rev; const i = Widgets.indexOf(cur); return i >= 0 ? Widgets.model.get(i) : null; }
    readonly property string type: entry ? entry.type : ""
    readonly property var sp: Widgets.spec(type)
    readonly property var cfg: { Widgets.rev; return cur !== "" ? Widgets.extraOf(cur) : {}; }
    readonly property string bg: ["blur", "solid", "none"].indexOf(cfg.bg) >= 0 ? cfg.bg : (sp.bg || "blur")
    readonly property string tone: ["primary", "secondary", "tertiary", "neutral"].indexOf(cfg.tone) >= 0 ? cfg.tone : (sp.tone || "primary")
    readonly property real alpha: typeof cfg.alpha === "number" ? cfg.alpha : (Theme.m3 ? Config.m3Opacity : Config.glassOpacity)
    function set(k, v) { Widgets.setExtra(cur, k, v); }

    width: 400
    height: col.implicitHeight + 36
    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0.92
    visible: opacity > 0.01
    Behavior on opacity { Anim { kind: "effects" } }
    Behavior on scale { Anim { kind: "spatial" } }
    Behavior on height { Anim { kind: "fast" } }

    MouseArea { anchors.fill: parent }                 // клики по панели не уходят на рабочий стол
    // стекло из размытых обоев рабочего стола (как у виджетов), с прозрачностью темы
    WidgetSurface { anchors.fill: parent; radius: 32; tone: "neutral"; cfg: ({ alpha: Theme.glassStrong.a }) }

    Column {
        id: col
        x: 20; y: 18
        width: parent.width - 40
        spacing: 14

        // ── заголовок
        Item {
            width: parent.width; height: 44
            Rectangle {
                id: badge
                width: 44; height: 44; radius: 16
                color: Theme.primaryContainer
                Icon { anchors.centerIn: parent; name: t.sp.icon || "widgets"; size: 24; fill: 1; color: Theme.primaryContainerFg }
            }
            Column {
                anchors { left: badge.right; leftMargin: 12; verticalCenter: parent.verticalCenter; right: closeBtn.left; rightMargin: 8 }
                Label { width: parent.width; text: t.sp ? I18n.t(t.sp.ru, t.sp.en) : ""; size: 17; weight: 750 }
                Label { width: parent.width; text: I18n.t("Настроить виджет", "Customize widget"); size: 12; color: Theme.fgVariant }
            }
            IconButton { id: closeBtn; anchors { right: parent.right; verticalCenter: parent.verticalCenter } icon: "close"; size: 38; iconSize: 20; onClicked: Widgets.tuning = "" }
        }

        // ── стиль: циферблат
        Column {
            visible: t.type === "clock"
            width: parent.width
            spacing: 8
            Label { text: I18n.t("Циферблат", "Clock face"); size: 13; weight: 700; color: Theme.primaryText; elide: Text.ElideNone }
            Grid {
                columns: 4
                spacing: 8
                Repeater {
                    model: [
                        { id: "bubble",   t: I18n.t("Формы", "Shapes"),      k: 0.27 },
                        { id: "analog",   t: I18n.t("Стрелки", "Analog"),    k: 0.25 },
                        { id: "orbit",    t: I18n.t("Орбита", "Orbit"),      k: 0.215 },
                        { id: "dots",     t: I18n.t("Точки", "Dots"),        k: 0.185 },
                        { id: "planets",  t: I18n.t("Планеты", "Planets"),   k: 0.2 },
                        { id: "horizon",  t: I18n.t("Горизонт", "Horizon"),  k: 0.2 },
                        { id: "segments", t: I18n.t("Сегменты", "Segments"), k: 0.2 }
                    ]
                    Item {
                        id: fc
                        required property var modelData
                        readonly property bool on: (Config.aodFaces.indexOf(t.cfg.face) >= 0 ? t.cfg.face : Config.aodFace) === modelData.id
                        width: (col.width - 24) / 4; height: width + 20
                        Rectangle {
                            id: fcBox
                            width: parent.width; height: width
                            radius: fc.on ? 18 : fcMouse.pressed ? 14 : width / 2
                            color: Qt.rgba(0, 0, 0, 0.55)
                            border.width: fc.on ? 3 : 0; border.color: Theme.primaryText
                            clip: true
                            Behavior on radius { Anim { kind: "fast" } }
                            AodClock {
                                anchors.centerIn: parent
                                style: fc.modelData.id
                                k: fc.modelData.k * fcBox.width / 100
                                showDate: false
                                now: t.now
                                p: 1
                            }
                        }
                        Label { anchors { top: fcBox.bottom; topMargin: 4; horizontalCenter: parent.horizontalCenter }
                                text: fc.modelData.t; size: 11; weight: fc.on ? 750 : 550; color: fc.on ? Theme.primaryText : Theme.fgVariant; elide: Text.ElideNone }
                        scale: fcMouse.pressed ? 0.94 : 1
                        Behavior on scale { Anim { kind: "fast" } }
                        MouseArea { id: fcMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: t.set("face", fc.modelData.id) }
                    }
                }
            }
        }

        // ── стиль: форма фото
        Column {
            visible: t.type === "photo"
            width: parent.width
            spacing: 8
            Label { text: I18n.t("Форма", "Shape"); size: 13; weight: 700; color: Theme.primaryText; elide: Text.ElideNone }
            Row {
                spacing: 10
                Repeater {
                    model: ["squircle", "cookie", "clover", "hex", "circle"]
                    Item {
                        id: sh
                        required property string modelData
                        readonly property bool on: (t.cfg.shape || "squircle") === modelData
                        width: (col.width - 40) / 5; height: width
                        AodShape {
                            anchors.fill: parent; anchors.margins: sh.on ? 0 : 6
                            kind: sh.modelData; lobes: 10
                            color: sh.on ? Theme.primary : Qt.alpha(Theme.fg, 0.18)
                            Behavior on anchors.margins { Anim { kind: "fast" } }
                        }
                        Icon { anchors.centerIn: parent; visible: sh.on; name: "check"; size: 22; weight: 700; color: Theme.primaryFg }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: t.set("shape", sh.modelData) }
                    }
                }
            }
        }

        // ── стиль: период «Дня и года»
        Column {
            visible: t.type === "progress"
            width: parent.width
            spacing: 8
            Label { text: I18n.t("Период", "Period"); size: 13; weight: 700; color: Theme.primaryText; elide: Text.ElideNone }
            TunerChoice {
                width: parent.width
                options: [{ id: "day", t: I18n.t("День", "Day") }, { id: "month", t: I18n.t("Месяц", "Month") }, { id: "year", t: I18n.t("Год", "Year") }]
                current: t.cfg.mode || ""
                onPicked: v => t.set("mode", v)
            }
        }

        // ── подложка
        Column {
            width: parent.width
            spacing: 8
            Label { text: I18n.t("Фон", "Background"); size: 13; weight: 700; color: Theme.primaryText; elide: Text.ElideNone }
            TunerChoice {
                width: parent.width
                options: [{ id: "blur", icon: "blur_on", t: I18n.t("Размытие", "Blur") },
                          { id: "solid", icon: "format_color_fill", t: I18n.t("Цвет", "Color") },
                          { id: "none", icon: "hide_source", t: I18n.t("Без фона", "None") }]
                current: t.bg
                onPicked: v => t.set("bg", v)
            }
        }

        // ── цвет темы
        Column {
            width: parent.width
            spacing: 8
            Label { text: I18n.t("Цвет", "Color"); size: 13; weight: 700; color: Theme.primaryText; elide: Text.ElideNone }
            Row {
                spacing: 12
                Repeater {
                    model: [
                        { id: "primary",   c: Theme.primaryContainer,   d: Theme.primary,   t: I18n.t("Основной", "Primary") },
                        { id: "secondary", c: Theme.secondaryContainer, d: Theme.secondary, t: I18n.t("Второй", "Secondary") },
                        { id: "tertiary",  c: Theme.tertiaryContainer,  d: Theme.tertiary,  t: I18n.t("Третий", "Tertiary") },
                        { id: "neutral",   c: Theme.surfaceHigh,        d: Theme.fgVariant, t: I18n.t("Нейтральный", "Neutral") }
                    ]
                    Item {
                        id: sw
                        required property var modelData
                        readonly property bool on: t.tone === modelData.id
                        width: 52; height: 52
                        Rectangle {
                            anchors.centerIn: parent
                            width: sw.on ? 52 : 44; height: width; radius: sw.on ? 18 : width / 2
                            color: "transparent"
                            border.width: 3; border.color: sw.on ? Theme.primaryText : "transparent"
                            Behavior on width { Anim { kind: "fast" } }
                            Behavior on radius { Anim { kind: "fast" } }
                        }
                        // половинки — контейнер и сам цвет, как образцы цвета на Pixel и Galaxy
                        Item {
                            anchors.centerIn: parent
                            width: 38; height: 38
                            Rectangle { anchors.fill: parent; radius: sw.on ? 13 : 19; color: sw.modelData.c; Behavior on radius { Anim { kind: "fast" } } }
                            Rectangle { width: 19; height: 19; radius: 9.5; x: 16; y: 16; color: sw.modelData.d }
                        }
                        scale: swMouse.pressed ? 0.9 : 1
                        Behavior on scale { Anim { kind: "fast" } }
                        MouseArea { id: swMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: t.set("tone", sw.modelData.id) }
                    }
                }
            }
        }

        // ── прозрачность (без фона — нечего делать прозрачным)
        Column {
            width: parent.width
            spacing: 8
            visible: t.bg !== "none"
            Label { text: I18n.t("Прозрачность", "Transparency"); size: 13; weight: 700; color: Theme.primaryText; elide: Text.ElideNone }
            Rectangle {
                id: sl
                width: parent.width; height: 44; radius: 22
                color: Theme.glassChip
                readonly property real frac: 1 - t.alpha
                Rectangle {
                    height: parent.height; radius: 22
                    width: Math.max(parent.height, parent.width * sl.frac)
                    color: Theme.primary
                    Behavior on width { enabled: !slMouse.pressed; Anim { kind: "fast" } }
                }
                Icon { anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                       name: "opacity"; size: 20; fill: 1; color: Theme.primaryFg }
                Label { anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                        text: Math.round(sl.frac * 100) + "%"; size: 13; weight: 700; color: sl.frac > 0.86 ? Theme.primaryFg : Theme.fg; elide: Text.ElideNone }
                MouseArea {
                    id: slMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    function put(x) { t.set("alpha", Math.round((1 - Math.max(0, Math.min(1, x / width))) * 100) / 100); }
                    onPressed: m => put(m.x)
                    onPositionChanged: m => { if (pressed) put(m.x); }
                    onWheel: w => t.set("alpha", Math.round(Math.max(0, Math.min(1, t.alpha + (w.angleDelta.y > 0 ? -0.05 : 0.05))) * 100) / 100)
                }
            }
        }

        // ── снизу: сбросить / готово
        Item {
            width: parent.width; height: 44
            Rectangle {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: rsRow.implicitWidth + 28; height: 40; radius: rsMouse.pressed ? 12 : 20
                color: rsMouse.containsMouse ? Theme.glassChip : "transparent"
                Behavior on radius { Anim { kind: "fast" } }
                Row {
                    id: rsRow
                    anchors.centerIn: parent
                    spacing: 6
                    Icon { anchors.verticalCenter: parent.verticalCenter; name: "restart_alt"; size: 18; color: Theme.primaryText }
                    Label { anchors.verticalCenter: parent.verticalCenter; text: I18n.t("Сбросить", "Reset"); size: 13; weight: 700; color: Theme.primaryText; elide: Text.ElideNone }
                }
                MouseArea { id: rsMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { for (const k of ["bg", "tone", "alpha", "face", "shape", "mode"]) t.set(k, undefined); } }
            }
            Rectangle {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: dnRow.implicitWidth + 32; height: 44; radius: dnMouse.pressed ? 14 : 22
                color: Theme.primary
                Behavior on radius { Anim { kind: "fast" } }
                Row {
                    id: dnRow
                    anchors.centerIn: parent
                    spacing: 6
                    Icon { anchors.verticalCenter: parent.verticalCenter; name: "check"; size: 18; weight: 700; color: Theme.primaryFg }
                    Label { anchors.verticalCenter: parent.verticalCenter; text: I18n.t("Готово", "Done"); size: 14; weight: 750; color: Theme.primaryFg; elide: Text.ElideNone }
                }
                MouseArea { id: dnMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Widgets.tuning = "" }
            }
        }
    }
}
