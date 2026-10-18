import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

// Содержимое окна настроек. Пока один раздел — «Оформление»: стиль (стекло / M3) и прозрачность.
Item {
    id: root
    signal close()
    property string section: "look"
    // высота окна под раздел: AOD длинный (два ряда часов), «Язык» короткий
    readonly property int wantHeight: section === "aod" ? 840 : section === "lang" ? 380 : section === "assistant" ? 1020 : Theme.m3 ? 830 : 930

    readonly property string wallSrc: Quickshell.env("HOME") + "/.cache/matugen/wallpaper"
    readonly property string frameSrc: Quickshell.env("HOME") + "/.cache/matugen/frame.png"
    // обои могут быть видео/GIF — тогда для превью берём их кадр (frame.png от changetheme.sh)
    property string previewSrc: ""
    Process {
        id: resolve
        running: true
        command: ["sh", "-c", 'w=$(readlink -f "$0"); case "$w" in *.[mM][pP]4|*.[wW][eE][bB][mM]|*.[mM][kK][vV]|*.[mM][oO][vV]|*.[gG][iI][fF]|*.[wW][eE][bB][pP]) echo "$1";; *) echo "$w";; esac', root.wallSrc, root.frameSrc]
        stdout: StdioCollector { onStreamFinished: root.previewSrc = text.trim() }
    }
    onVisibleChanged: if (visible) resolve.running = true

    // ── мини-превью стиля: обои, мини-бар из островов и карточка меню
    component StylePreview: Item {
        id: pv
        property string kind: "glass"
        readonly property bool m3: kind === "m3"
        // те же формулы, что в Theme, но для конкретного стиля (а не текущего)
        readonly property real op: m3 ? Config.m3Opacity : Config.glassOpacity
        readonly property color tint: m3 ? Qt.alpha(Theme.surfaceMid, op) : Qt.alpha(Theme.frost, op)
        readonly property color tintStrong: m3 ? Qt.alpha(Theme.surfaceHigh, Math.min(1, op + 0.25)) : Qt.alpha(Theme.frost, Math.min(1, op + 0.25))
        readonly property color border: m3 ? Qt.alpha(Theme.fg, op < 0.97 ? 0.07 : 0) : Qt.alpha(Theme.fg, 0.12)
        readonly property real k: width / 300

        // обои
        Item {
            id: scene
            anchors.fill: parent
            visible: false
            layer.enabled: true
            Rectangle { anchors.fill: parent; color: Theme.surface }
            Image {
                id: wp
                anchors.fill: parent
                source: root.previewSrc !== "" ? "file://" + root.previewSrc : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 640
                asynchronous: true
            }
        }
        // размытая копия — то, что видно сквозь стекло
        MultiEffect { id: blurred; anchors.fill: parent; source: scene; blurEnabled: true; blur: 1; blurMax: 40; visible: false; layer.enabled: true }
        // формы островов (маска для блюра)
        Item {
            id: shapes
            anchors.fill: parent
            visible: false
            layer.enabled: true
            Repeater {
                model: pv.boxes
                Rectangle { required property var modelData; x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h; radius: modelData.r; color: "white" }
            }
        }
        readonly property var boxes: [
            { x: 8 * k,   y: 8 * k,  w: 70 * k,  h: 18 * k, r: 9 * k },     // рабочие столы
            { x: 112 * k, y: 8 * k,  w: 76 * k,  h: 18 * k, r: 9 * k },     // остров по центру
            { x: 222 * k, y: 8 * k,  w: 70 * k,  h: 18 * k, r: 9 * k },     // справа
            { x: 150 * k, y: 34 * k, w: 142 * k, h: 120 * k, r: 18 * k }    // раскрытая шторка
        ]

        // собираем: обои → блюр под островами → тонировка островов
        Item {
            id: composed
            anchors.fill: parent
            visible: false
            layer.enabled: true
            Image { anchors.fill: parent; source: wp.source; fillMode: Image.PreserveAspectCrop; sourceSize.width: 640 }
            MultiEffect { anchors.fill: parent; source: blurred; maskEnabled: true; maskSource: shapes; maskThresholdMin: 0.5; maskSpreadAtMin: 0.2 }
            Repeater {
                model: pv.boxes
                Rectangle {
                    required property var modelData
                    required property int index
                    x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h; radius: modelData.r
                    color: index === 3 ? pv.tintStrong : pv.tint
                    border.width: 1; border.color: pv.border
                    Behavior on color { ColorAnimation { duration: 250 } }
                    // блик стекла
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 1; radius: parent.radius - 1
                        visible: !pv.m3
                        gradient: Gradient { GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.10) } GradientStop { position: 0.5; color: "transparent" } }
                    }
                }
            }
            // содержимое шторки: ползунок и две плитки
            Rectangle { x: 160 * pv.k; y: 46 * pv.k; width: 122 * pv.k; height: 16 * pv.k; radius: 8 * pv.k; color: Qt.alpha(Theme.fg, 0.10)
                Rectangle { width: parent.width * 0.62; height: parent.height; radius: parent.radius; color: Theme.primary } }
            Rectangle { x: 160 * pv.k; y: 70 * pv.k; width: 58 * pv.k; height: 30 * pv.k; radius: 10 * pv.k; color: Theme.primaryContainer }
            Rectangle { x: 224 * pv.k; y: 70 * pv.k; width: 58 * pv.k; height: 30 * pv.k; radius: 15 * pv.k; color: Qt.alpha(Theme.fg, 0.10) }
            Row {
                x: 168 * pv.k; y: 116 * pv.k; spacing: 8 * pv.k
                Repeater { model: 5; Rectangle { width: 16 * pv.k; height: 16 * pv.k; radius: 8 * pv.k; color: Qt.alpha(Theme.fg, 0.14) } }
            }
            // точки рабочих столов и часы
            Row {
                x: 16 * pv.k; y: 14 * pv.k; spacing: 5 * pv.k
                Repeater { model: 5; Rectangle { required property int index; width: index === 1 ? 16 * pv.k : 6 * pv.k; height: 6 * pv.k; radius: 3 * pv.k; color: index === 1 ? Theme.primary : Qt.alpha(Theme.fg, 0.5) } }
            }
            Rectangle { x: 132 * pv.k; y: 15 * pv.k; width: 36 * pv.k; height: 4 * pv.k; radius: 2 * pv.k; color: Theme.fg; opacity: 0.85 }
        }
        // скругление всей карточки
        Rectangle { id: cardMask; anchors.fill: parent; radius: pv.radius; visible: false; layer.enabled: true }
        property real radius: 24
        MultiEffect { anchors.fill: parent; source: composed; maskEnabled: true; maskSource: cardMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
    }

    // ── большой ползунок M3 Expressive
    component BigSlider: Rectangle {
        id: sl
        property real from: 0
        property real to: 1
        property real value: 0.5
        property string icon: ""
        property string text: ""
        signal moved(real v)
        height: 48; radius: 24
        color: Theme.glassChip
        readonly property real frac: (value - from) / (to - from)
        Rectangle {
            height: parent.height; radius: 24
            width: Math.max(parent.height, parent.width * sl.frac)
            color: Theme.primary
            Behavior on width { enabled: !slMouse.pressed; Anim { kind: "fast" } }
        }
        Icon { anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            name: sl.icon; size: 22; fill: 1; color: Theme.primaryFg }
        Label { anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
            text: sl.text; size: 14; weight: 700; color: sl.frac > 0.88 ? Theme.primaryFg : Theme.fg; elide: Text.ElideNone }
        MouseArea {
            id: slMouse
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            function set(x) { const f = Math.max(0, Math.min(1, x / width)); sl.moved(sl.from + f * (sl.to - sl.from)); }
            onPressed: m => set(m.x)
            onPositionChanged: m => set(m.x)
            onWheel: w => sl.moved(Math.max(sl.from, Math.min(sl.to, sl.value + (w.angleDelta.y > 0 ? 0.05 : -0.05) * (sl.to - sl.from))))
        }
    }

    // ── переключатель M3 Expressive
    component M3Switch: Rectangle {
        id: sw
        property bool checked: false
        signal toggled()
        width: 56; height: 32; radius: 16
        color: checked ? Theme.primary : Qt.alpha(Theme.fg, 0.10)
        border.width: checked ? 0 : 2; border.color: Theme.outline
        Behavior on color { ColorAnimation { duration: 180 } }
        Rectangle {
            property real d: sw.checked ? 24 : swMouse.pressed ? 26 : 16
            width: d; height: d; radius: d / 2
            anchors.verticalCenter: parent.verticalCenter
            x: sw.checked ? sw.width - d - 4 : 8 - (d - 16) / 2
            color: sw.checked ? Theme.primaryFg : Theme.outline
            Behavior on x { Anim { kind: "fast" } }
            Behavior on d { Anim { kind: "fast" } }
            Icon { anchors.centerIn: parent; name: "check"; size: 16; weight: 700; color: Theme.primary; opacity: sw.checked ? 1 : 0 }
        }
        MouseArea { id: swMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sw.toggled() }
    }

    // ── слева: разделы
    Item {
        id: nav
        width: 220
        anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
        Row {
            x: 22; y: 22
            spacing: 10
            Icon { anchors.verticalCenter: parent.verticalCenter; name: "settings"; size: 24; fill: 1; color: Theme.primary }
            Label { anchors.verticalCenter: parent.verticalCenter; text: I18n.t("Настройки", "Settings"); size: 20; weight: 750; elide: Text.ElideNone }
        }
        Column {
            x: 12; y: 76
            width: parent.width - 24
            spacing: 4
            Repeater {
                model: [{ id: "look", icon: "palette", t: I18n.t("Оформление", "Appearance") },
                        { id: "aod", icon: "bedtime", t: "Always On Display" },
                        { id: "assistant", icon: "auto_awesome", t: I18n.t("Ассистент", "Assistant") },
                        { id: "lang", icon: "translate", t: I18n.t("Язык", "Language") }]
                Rectangle {
                    id: navItem
                    required property var modelData
                    readonly property bool on: root.section === modelData.id
                    width: parent.width; height: 48
                    radius: on ? 16 : 24
                    color: on ? Theme.secondaryContainer : navMouse.containsMouse ? Theme.glassChip : "transparent"
                    Behavior on radius { Anim { kind: "fast" } }
                    Row {
                        anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                        spacing: 12
                        Icon { anchors.verticalCenter: parent.verticalCenter; name: navItem.modelData.icon; size: 20; fill: navItem.on ? 1 : 0; color: navItem.on ? Theme.secondaryContainerFg : Theme.fg }
                        Label { anchors.verticalCenter: parent.verticalCenter; text: navItem.modelData.t; size: 14; weight: navItem.on ? 700 : 550; color: navItem.on ? Theme.secondaryContainerFg : Theme.fg; elide: Text.ElideNone }
                    }
                    MouseArea { id: navMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.section = navItem.modelData.id }
                }
            }
        }
    }

    // ── справа: раздел «Оформление»
    Item {
        id: page
        visible: root.section === "look"
        anchors { top: parent.top; bottom: parent.bottom; left: nav.right; right: parent.right; margins: 24; leftMargin: 8 }

        IconButton {
            anchors { top: parent.top; right: parent.right; topMargin: -6; rightMargin: -6 }
            icon: "close"; size: 40; iconSize: 22
            onClicked: root.close()
        }
        Column {
            width: parent.width
            spacing: 4
            Label { text: I18n.t("Оформление", "Appearance"); size: 26; weight: 750; elide: Text.ElideNone }
            Label { text: I18n.t("Как выглядят бар, меню и окна оболочки", "How the bar, menus and shell windows look"); size: 14; color: Theme.fgVariant; elide: Text.ElideNone }
        }

        Label { id: styleTitle; y: 84; text: I18n.t("Стиль", "Style"); size: 15; weight: 700; color: Theme.primaryText; elide: Text.ElideNone }

        Row {
            id: cards
            anchors { top: styleTitle.bottom; topMargin: 12 }
            spacing: 18
            Repeater {
                model: [
                    { id: "glass", t: I18n.t("Стекло", "Glass"), s: I18n.t("Матовое стекло с блюром — как в One UI", "Frosted blurred glass — like One UI") },
                    { id: "m3",    t: "Material Expressive", s: I18n.t("Тональные поверхности Material 3", "Material 3 tonal surfaces") }
                ]
                Item {
                    id: card
                    required property var modelData
                    readonly property bool on: Config.style === modelData.id
                    width: (page.width - 18) / 2
                    height: prev.height + 64
                    scale: cardMouse.pressed ? 0.97 : 1
                    Behavior on scale { Anim { kind: "fast" } }

                    Rectangle {
                        x: -5; y: -5
                        width: prev.width + 10; height: prev.height + 10
                        radius: prev.radius + 5
                        color: "transparent"
                        border.width: 3; border.color: Theme.primary
                        opacity: card.on ? 1 : 0
                        Behavior on opacity { Anim { kind: "effects" } }
                    }
                    StylePreview {
                        id: prev
                        kind: card.modelData.id
                        width: parent.width
                        height: width * 0.6
                        radius: card.on ? 20 : 30
                        Behavior on radius { Anim { kind: "fast" } }
                    }
                    // галочка выбранного
                    Rectangle {
                        anchors { right: prev.right; bottom: prev.bottom; margins: 10 }
                        width: 32; height: 32; radius: 16
                        color: Theme.primary
                        opacity: card.on ? 1 : 0
                        scale: card.on ? 1 : 0.3
                        Behavior on opacity { Anim { kind: "effects" } }
                        Behavior on scale { Anim { kind: "fast" } }
                        Icon { anchors.centerIn: parent; name: "check"; size: 20; weight: 700; color: Theme.primaryFg }
                    }
                    Column {
                        anchors { top: prev.bottom; topMargin: 12; left: parent.left; right: parent.right }
                        spacing: 2
                        Label { text: card.modelData.t; size: 16; weight: 700; color: card.on ? Theme.primaryText : Theme.fg; elide: Text.ElideNone }
                        Label { width: parent.width; text: card.modelData.s; size: 13; color: Theme.fgVariant }
                    }
                    MouseArea { id: cardMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Config.style = card.modelData.id }
                }
            }
        }

        Label { id: opTitle; anchors { top: cards.bottom; topMargin: 22 }
            text: Theme.m3 ? I18n.t("Прозрачность поверхностей", "Surface opacity") : I18n.t("Плотность стекла", "Glass density"); size: 15; weight: 700; color: Theme.primaryText; elide: Text.ElideNone }
        BigSlider {
            id: opSlider
            anchors { top: opTitle.bottom; topMargin: 10 }
            width: parent.width
            icon: "opacity"
            from: 0
            to: 1.0
            value: Theme.m3 ? Config.m3Opacity : Config.glassOpacity
            text: Theme.m3 && Config.m3Opacity >= 0.995 ? I18n.t("сплошной", "solid")
                : Math.round((Theme.m3 ? Config.m3Opacity : Config.glassOpacity) * 100) + "%"
            onMoved: v => { if (Theme.m3) Config.m3Opacity = Math.round(v * 100) / 100; else Config.glassOpacity = Math.round(v * 100) / 100; }
        }

        // ── сила размытия: только у стекла (блюр Hyprland общий на всю систему — см. Blur.qml)
        Item {
            id: blurBox
            anchors { top: opSlider.bottom }
            width: parent.width
            height: Theme.m3 ? 0 : 100
            opacity: Theme.m3 ? 0 : 1
            visible: opacity > 0
            clip: true
            Behavior on height { Anim { kind: "fast" } }
            Behavior on opacity { Anim { kind: "effects" } }
            Label { id: blurTitle; y: 22
                text: I18n.t("Сила размытия", "Blur strength"); size: 15; weight: 700; color: Theme.primaryText; elide: Text.ElideNone }
            BigSlider {
                anchors { top: blurTitle.bottom; topMargin: 10 }
                width: parent.width
                icon: "blur_on"
                from: 3
                to: 16
                value: Config.glassBlur
                text: Math.round(Config.glassBlur)
                onMoved: v => Config.glassBlur = Math.round(v)
            }
        }

        // ── насколько точно тема повторяет выбранный цвет
        Label { id: colTitle; anchors { top: blurBox.bottom; topMargin: 26 }
            text: I18n.t("Цвет темы", "Theme color"); size: 15; weight: 700; color: Theme.primaryText; elide: Text.ElideNone }
        Row {
            id: colModes
            anchors { top: colTitle.bottom; topMargin: 10 }
            spacing: 12
            Repeater {
                model: [
                    { id: false, icon: "palette", t: "Material", s: I18n.t("Мягкие пастельные тона, как у Google", "Soft pastel tones, like Google"),
                      dots: ["#ffb4ac", "#ffb77b", "#a2c9ff", "#e8b3ff"] },
                    { id: true, icon: "colorize", t: I18n.t("Точный цвет", "Exact color"), s: I18n.t("Выбрал красный — тема красная", "Pick red — get a red theme"),
                      dots: ["#e53935", "#fb8c00", "#1e88e5", "#8e24aa"] }
                ]
                Rectangle {
                    id: cm
                    required property var modelData
                    readonly property bool on: Config.exactColor === modelData.id
                    width: (page.width - 12) / 2; height: 84
                    radius: on ? 20 : 30
                    color: on ? Theme.secondaryContainer : cmMouse.containsMouse ? Qt.alpha(Theme.fg, 0.12) : Theme.glassChip
                    border.width: on ? 2 : 0; border.color: Theme.primary
                    Behavior on radius { Anim { kind: "fast" } }
                    Behavior on color { ColorAnimation { duration: 180 } }
                    Icon {
                        id: cmIcon
                        anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                        name: cm.modelData.icon; size: 24; fill: cm.on ? 1 : 0
                        color: cm.on ? Theme.secondaryContainerFg : Theme.fg
                    }
                    Column {
                        anchors { left: cmIcon.right; leftMargin: 14; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                        spacing: 4
                        Label { text: cm.modelData.t; size: 15; weight: 700; color: cm.on ? Theme.secondaryContainerFg : Theme.fg; elide: Text.ElideNone }
                        Row {
                            spacing: 4
                            Repeater { model: cm.modelData.dots; Rectangle { required property var modelData; width: 14; height: 14; radius: 7; color: modelData } }
                        }
                        Label { width: parent.width; text: cm.modelData.s; size: 12; color: cm.on ? Qt.alpha(Theme.secondaryContainerFg, 0.8) : Theme.fgVariant }
                    }
                    MouseArea { id: cmMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: {
                        if (cm.on) return;
                        Config.exactColor = cm.modelData.id;
                        // перекрасить текущую тему (настройки успевают записаться в файл)
                        Quickshell.execDetached(["sh", "-c", 'sleep 0.4; s=$(cat "$HOME/.cache/matugen/source" 2>/dev/null); exec "$HOME/.config/hypr/scripts/changetheme.sh" "$(readlink -f "$HOME/.cache/matugen/wallpaper")" $s']);
                    } }
                }
            }
        }

        // ── фон под лаунчером, настройками и шпаргалкой (Scrim)
        Label { id: bgTitle; anchors { top: colModes.bottom; topMargin: 26 }
            text: I18n.t("Фон под окнами", "Behind windows"); size: 15; weight: 700; color: Theme.primaryText; elide: Text.ElideNone }
        Row {
            id: bgModes
            anchors { top: bgTitle.bottom; topMargin: 10 }
            spacing: 12
            Repeater {
                model: [
                    { id: "dots", t: I18n.t("Точки", "Dots"), s: I18n.t("Светящиеся точки плывут и мерцают", "Glowing dots drift and twinkle") },
                    { id: "dark", t: I18n.t("Тёмный", "Dark"), s: I18n.t("Просто затемнение, без анимации", "Just a dim, no animation") }
                ]
                Rectangle {
                    id: bm
                    required property var modelData
                    readonly property bool on: Config.scrim === modelData.id || (modelData.id === "dots" && Config.scrim !== "dark")
                    width: (page.width - 12) / 2; height: 96
                    radius: on ? 20 : 30
                    color: on ? Theme.secondaryContainer : bmMouse.containsMouse ? Qt.alpha(Theme.fg, 0.12) : Theme.glassChip
                    border.width: on ? 2 : 0; border.color: Theme.primary
                    Behavior on radius { Anim { kind: "fast" } }
                    Behavior on color { ColorAnimation { duration: 180 } }
                    scale: bmMouse.pressed ? 0.97 : 1
                    Behavior on scale { Anim { kind: "fast" } }
                    // живое превью: обои и это затемнение поверх
                    ClippingRectangle {
                        id: bmPrev
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        width: 128; height: 72
                        radius: bm.on ? 12 : 18
                        color: Theme.surface
                        Behavior on radius { Anim { kind: "fast" } }
                        Image {
                            anchors.fill: parent
                            source: root.previewSrc !== "" ? "file://" + root.previewSrc : ""
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 256
                            asynchronous: true
                        }
                        Scrim {
                            id: bmScrim
                            anchors.fill: parent
                            shown: root.visible && root.section === "look"
                            style: bm.modelData.id
                            dim: 0.34
                            zoom: 560
                            origin: Qt.point(width / 2, height / 2)
                            onClicked: bm.pick()
                        }
                    }
                    function pick() { Config.scrim = modelData.id; bmScrim.replay(); }
                    Column {
                        anchors { left: bmPrev.right; leftMargin: 14; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                        spacing: 4
                        Label { text: bm.modelData.t; size: 15; weight: 700; color: bm.on ? Theme.secondaryContainerFg : Theme.fg; elide: Text.ElideNone }
                        Label { width: parent.width; text: bm.modelData.s; size: 12; wrapMode: Text.Wrap; maximumLineCount: 2
                                color: bm.on ? Qt.alpha(Theme.secondaryContainerFg, 0.8) : Theme.fgVariant }
                    }
                    MouseArea { id: bmMouse; anchors.fill: parent; z: -1; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: bm.pick() }
                }
            }
        }
    }

    // ── справа: раздел «Always On Display»
    Item {
        id: aodPage
        visible: root.section === "aod"
        anchors { top: parent.top; bottom: parent.bottom; left: nav.right; right: parent.right; margins: 24; leftMargin: 8 }

        IconButton {
            anchors { top: parent.top; right: parent.right; topMargin: -6; rightMargin: -6 }
            icon: "close"; size: 40; iconSize: 22
            onClicked: root.close()
        }
        Column {
            width: parent.width - 60
            spacing: 4
            Label { text: "Always On Display"; size: 26; weight: 750; elide: Text.ElideNone }
            Label { width: parent.width; text: I18n.t("Отошёл от компьютера — фон темнеет, остаются часы, музыка и погода. Двинул мышь — всё назад.",
                                                      "Step away — the background dims, leaving the clock, music and weather. Move the mouse — it's back.")
                    size: 14; color: Theme.fgVariant; wrapMode: Text.Wrap; elide: Text.ElideNone }
        }

        // ── главный выключатель
        Rectangle {
            id: aodMaster
            y: 80
            width: parent.width; height: 52
            radius: Config.aodEnabled ? 20 : 30
            color: Config.aodEnabled ? Theme.primaryContainer : Theme.glassChip
            Behavior on radius { Anim { kind: "fast" } }
            Behavior on color { ColorAnimation { duration: 200 } }
            Label {
                anchors { left: parent.left; leftMargin: 22; verticalCenter: parent.verticalCenter }
                text: Config.aodEnabled ? I18n.t("Включено", "On") : I18n.t("Выключено", "Off")
                size: 17; weight: 700; elide: Text.ElideNone
                color: Config.aodEnabled ? Theme.primaryContainerFg : Theme.fg
            }
            M3Switch {
                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                checked: Config.aodEnabled
                onToggled: Config.aodEnabled = !Config.aodEnabled
            }
            MouseArea { anchors.fill: parent; z: -1; cursorShape: Qt.PointingHandCursor; onClicked: Config.aodEnabled = !Config.aodEnabled }
        }

        Item {
            id: aodBody
            anchors { top: aodMaster.bottom; topMargin: 12; left: parent.left; right: parent.right; bottom: parent.bottom }
            opacity: Config.aodEnabled ? 1 : 0.4
            enabled: Config.aodEnabled
            Behavior on opacity { Anim { kind: "effects" } }

            Label { id: clkTitle; text: I18n.t("Часы", "Clock"); size: 15; weight: 700; color: Theme.primaryText; elide: Text.ElideNone }
            // показать AOD прямо сейчас
            Rectangle {
                anchors { right: parent.right; verticalCenter: clkTitle.verticalCenter }
                width: showRow.implicitWidth + 28; height: 32
                radius: showMouse.pressed ? 10 : 16
                color: Theme.primary
                Behavior on radius { Anim { kind: "fast" } }
                Row {
                    id: showRow
                    anchors.centerIn: parent
                    spacing: 6
                    Icon { anchors.verticalCenter: parent.verticalCenter; name: "visibility"; size: 18; fill: 1; color: Theme.primaryFg }
                    Label { anchors.verticalCenter: parent.verticalCenter; text: I18n.t("Показать", "Preview"); size: 13; weight: 750; color: Theme.primaryFg; elide: Text.ElideNone }
                }
                MouseArea {
                    id: showMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.close(); Config.aodPing++; }
                }
            }
            Grid {
                id: clkRow
                anchors { top: clkTitle.bottom; topMargin: 10 }
                columns: 4
                spacing: 12
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
                        id: cc
                        required property var modelData
                        readonly property bool on: Config.aodFace === modelData.id
                        width: (aodBody.width - 36) / 4
                        height: 130
                        scale: ccMouse.pressed ? 0.96 : 1
                        Behavior on scale { Anim { kind: "fast" } }

                        Rectangle {
                            id: ccFace
                            width: parent.width; height: 100
                            radius: cc.on ? 22 : 34
                            color: Qt.rgba(0, 0, 0, 0.82)
                            border.width: cc.on ? 3 : 0; border.color: Theme.primary
                            Behavior on radius { Anim { kind: "fast" } }
                            clip: true
                            AodClock {
                                id: ccClock
                                anchors.centerIn: parent
                                style: cc.modelData.id
                                k: cc.modelData.k
                                showDate: false
                                now: new Date()
                                property real pp: 1
                                p: pp
                                NumberAnimation { id: replay; target: ccClock; property: "pp"; from: 0; to: 1; duration: 1600 }
                            }
                        }
                        Label {
                            anchors { top: ccFace.bottom; topMargin: 8; horizontalCenter: parent.horizontalCenter }
                            text: cc.modelData.t; size: 14; weight: cc.on ? 750 : 550
                            color: cc.on ? Theme.primary : Theme.fg; elide: Text.ElideNone
                        }
                        MouseArea {
                            id: ccMouse
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { Config.aodClock = cc.modelData.id; replay.restart(); }
                        }
                    }
                }
            }

            // ── через сколько
            Label { id: toTitle; anchors { top: clkRow.bottom; topMargin: 12 }
                text: I18n.t("Включать через", "Turn on after"); size: 15; weight: 700; color: Theme.primaryText; elide: Text.ElideNone }
            Row {
                id: toRow
                anchors { top: toTitle.bottom; topMargin: 10 }
                spacing: 8
                Repeater {
                    model: [60, 120, 300, 600, 900]
                    Rectangle {
                        id: tc
                        required property int modelData
                        readonly property bool on: Config.aodTimeout === modelData
                        width: (aodBody.width - 32) / 5; height: 44
                        radius: on ? 14 : 22
                        color: on ? Theme.secondaryContainer : tcMouse.containsMouse ? Qt.alpha(Theme.fg, 0.12) : Theme.glassChip
                        Behavior on radius { Anim { kind: "fast" } }
                        Behavior on color { ColorAnimation { duration: 160 } }
                        Label {
                            anchors.centerIn: parent
                            text: (tc.modelData / 60) + I18n.t(" мин", " min")
                            size: 14; weight: tc.on ? 750 : 550
                            color: tc.on ? Theme.secondaryContainerFg : Theme.fg; elide: Text.ElideNone
                        }
                        MouseArea { id: tcMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Config.aodTimeout = tc.modelData }
                    }
                }
            }

            // ── пароль при возвращении
            Label { id: lockTitle; anchors { top: toRow.bottom; topMargin: 12 }
                text: I18n.t("Пароль при возвращении", "Password when you return"); size: 15; weight: 700; color: Theme.primaryText; elide: Text.ElideNone }
            Row {
                id: lockRow
                anchors { top: lockTitle.bottom; topMargin: 10 }
                spacing: 8
                Repeater {
                    model: [
                        { v: -1,  icon: "lock_open", t: I18n.t("Не нужен", "Never") },
                        { v: 0,   icon: "lock",      t: I18n.t("Сразу", "Right away") },
                        { v: 60,  icon: "timer",     t: I18n.t("Через 1 мин", "After 1 min") },
                        { v: 300, icon: "timer",     t: I18n.t("Через 5 мин", "After 5 min") }
                    ]
                    Rectangle {
                        id: lk
                        required property var modelData
                        readonly property bool on: Config.aodLock === modelData.v
                        width: (aodBody.width - 24) / 4; height: 44
                        radius: on ? 14 : 22
                        color: on ? Theme.secondaryContainer : lkMouse.containsMouse ? Qt.alpha(Theme.fg, 0.12) : Theme.glassChip
                        Behavior on radius { Anim { kind: "fast" } }
                        Behavior on color { ColorAnimation { duration: 160 } }
                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Icon { anchors.verticalCenter: parent.verticalCenter; name: lk.modelData.icon; size: 18; fill: lk.on ? 1 : 0; color: lk.on ? Theme.secondaryContainerFg : Theme.fgVariant }
                            Label { anchors.verticalCenter: parent.verticalCenter; text: lk.modelData.t; size: 14; weight: lk.on ? 750 : 550
                                    color: lk.on ? Theme.secondaryContainerFg : Theme.fg; elide: Text.ElideNone }
                        }
                        MouseArea { id: lkMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Config.aodLock = lk.modelData.v }
                    }
                }
            }

            // ── затемнение
            Label { id: dimTitle; anchors { top: lockRow.bottom; topMargin: 12 }
                text: I18n.t("Затемнение фона", "Background dimming"); size: 15; weight: 700; color: Theme.primaryText; elide: Text.ElideNone }
            BigSlider {
                id: dimSlider
                anchors { top: dimTitle.bottom; topMargin: 10 }
                width: parent.width
                icon: "dark_mode"
                from: 0.5; to: 1
                value: Config.aodDim
                text: Config.aodDim >= 0.995 ? I18n.t("чёрный", "black") : Math.round(Config.aodDim * 100) + "%"
                onMoved: v => Config.aodDim = Math.round(v * 100) / 100
            }

            // ── виджеты + показать
            Row {
                id: wgRow
                anchors { top: dimSlider.bottom; topMargin: 12 }
                spacing: 10
                Repeater {
                    model: [
                        { id: "music",   icon: "music_note",        t: I18n.t("Музыка", "Music"),              w: 0.28 },
                        { id: "weather", icon: "partly_cloudy_day", t: I18n.t("Погода", "Weather"),            w: 0.30 },
                        { id: "windows", icon: "web_asset_off",     t: I18n.t("Скрывать окна", "Hide windows"), w: 0.42 }
                    ]
                    Rectangle {
                        id: wg
                        required property var modelData
                        readonly property bool on: modelData.id === "music" ? Config.aodMusic : modelData.id === "weather" ? Config.aodWeather : Config.aodHideWindows
                        function flip() {
                            if (modelData.id === "music") Config.aodMusic = !Config.aodMusic;
                            else if (modelData.id === "weather") Config.aodWeather = !Config.aodWeather;
                            else Config.aodHideWindows = !Config.aodHideWindows;
                        }
                        width: (aodBody.width - 20) * modelData.w; height: 56
                        radius: on ? 18 : 28
                        color: on ? Theme.secondaryContainer : Theme.glassChip
                        Behavior on radius { Anim { kind: "fast" } }
                        Behavior on color { ColorAnimation { duration: 160 } }
                        Icon {
                            id: wgIcon
                            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                            name: wg.modelData.icon; size: 22; fill: wg.on ? 1 : 0
                            color: wg.on ? Theme.secondaryContainerFg : Theme.fg
                        }
                        Label {
                            anchors { left: wgIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            text: wg.modelData.t; size: 14; weight: 650
                            color: wg.on ? Theme.secondaryContainerFg : Theme.fg; elide: Text.ElideNone
                        }
                        M3Switch {
                            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            scale: 0.8
                            checked: wg.on
                            onToggled: wg.flip()
                        }
                    }
                }
            }
        }
    }

    // ── справа: раздел «Ассистент» (настройки службы glass-assistant — Assistant.cfg)
    Item {
        id: asPage
        visible: root.section === "assistant"
        anchors { top: parent.top; bottom: parent.bottom; left: nav.right; right: parent.right; margins: 24; leftMargin: 8 }

        IconButton {
            anchors { top: parent.top; right: parent.right; topMargin: -6; rightMargin: -6 }
            icon: "close"; size: 40; iconSize: 22
            onClicked: root.close()
        }
        Column {
            width: parent.width - 60
            spacing: 4
            Label { text: I18n.t("Ассистент", "Assistant"); size: 26; weight: 750; elide: Text.ElideNone }
            Label { width: parent.width; wrapMode: Text.Wrap; elide: Text.ElideNone; size: 14; color: Theme.fgVariant
                    text: I18n.t("«Обсидиан» или Super+A — голосом, Super+Space и «?» — текстом. Отвечает локальная модель; «морковь» в начале фразы, «??» или Super+Alt+A — Claude.",
                                 "“Obsidian” or Super+A — by voice, Super+Space then “?” — by text. A local model answers; “morkov” first, “??” or Super+Alt+A — Claude.") }
        }

        // ── состояние службы и ключа
        Rectangle {
            id: asStatus
            y: 84
            width: parent.width; height: 56
            radius: 20
            color: Assistant.online && Assistant.hasKey ? Theme.primaryContainer : Theme.glassChip
            Icon { id: asIcon; anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                   name: !Assistant.online ? "power_off" : Assistant.hasKey ? "cloud_done" : "key_off"; size: 22; fill: 1
                   color: Assistant.online && Assistant.hasKey ? Theme.primaryContainerFg : Theme.fg }
            Column {
                anchors { left: asIcon.right; leftMargin: 12; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                Label { width: parent.width; size: 14; weight: 700; color: Assistant.online && Assistant.hasKey ? Theme.primaryContainerFg : Theme.fg
                        text: !Assistant.online ? I18n.t("Служба не запущена", "Service is not running")
                            : Assistant.hasKey ? I18n.t("Работает · Claude подключён", "Running · Claude connected")
                            : I18n.t("Работает · без ключа Claude — отвечает локальная модель", "Running · no Claude key — the local model answers") }
                Label { width: parent.width; size: 12; color: Assistant.online && Assistant.hasKey ? Qt.alpha(Theme.primaryContainerFg, 0.75) : Theme.fgVariant
                        text: !Assistant.online ? "systemctl --user start glass-assistant"
                            : I18n.t("Ключ: ~/.config/glass/assistant.env → ANTHROPIC_API_KEY=…", "Key: ~/.config/glass/assistant.env → ANTHROPIC_API_KEY=…") }
            }
        }

        Column {
            anchors { top: asStatus.bottom; topMargin: 18; left: parent.left; right: parent.right }
            spacing: 10
            Label { text: I18n.t("Модель Claude", "Claude model"); size: 15; weight: 700; color: Theme.primaryText; elide: Text.ElideNone }
            TunerChoice {
                width: parent.width
                options: [{ id: "claude-opus-5-5", icon: "psychology", t: "Opus 5.5" },
                          { id: "claude-sonnet-5-5", icon: "bolt", t: "Sonnet 5.5" },
                          { id: "claude-haiku-5-5", icon: "speed", t: "Haiku 5.5" }]
                current: Assistant.cfg.model
                onPicked: v => Assistant.cfg.model = v
            }
            Label { topPadding: 6; text: I18n.t("Где думать", "Where to think"); size: 15; weight: 700; color: Theme.primaryText; elide: Text.ElideNone }
            TunerChoice {
                width: parent.width
                options: [{ id: "auto", icon: "auto_mode", t: I18n.t("Локально + Claude по слову", "Local + Claude on cue") },
                          { id: "claude", icon: "cloud", t: I18n.t("Всегда Claude", "Always Claude") },
                          { id: "local", icon: "memory", t: I18n.t("Только локально", "Local only") }]
                current: Assistant.cfg.backend
                onPicked: v => Assistant.cfg.backend = v
            }
            Item {
                width: parent.width; height: 30
                Label { anchors { left: parent.left; bottom: parent.bottom } text: I18n.t("Голос", "Voice"); size: 15; weight: 700; color: Theme.primaryText; elide: Text.ElideNone }
                Rectangle {
                    anchors { right: parent.right; bottom: parent.bottom }
                    width: hearRow.implicitWidth + 24; height: 30; radius: hearMouse.pressed ? 10 : 15
                    color: Theme.primary
                    Behavior on radius { Anim { kind: "fast" } }
                    Row { id: hearRow; anchors.centerIn: parent; spacing: 6
                          Icon { anchors.verticalCenter: parent.verticalCenter; name: "volume_up"; size: 16; fill: 1; color: Theme.primaryFg }
                          Label { anchors.verticalCenter: parent.verticalCenter; text: I18n.t("Прослушать", "Preview"); size: 12; weight: 750; color: Theme.primaryFg; elide: Text.ElideNone } }
                    MouseArea { id: hearMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: voiceBox.preview({}) }
                }
            }
            // голос: 3 женских и 2 мужских Silero, у каждого — тон и темп; выбор сразу звучит
            Column {
                id: voiceBox
                width: parent.width
                spacing: 6
                function preview(o) {
                    const c = Assistant.cfg;
                    if (o.voice) c.voice = o.voice;
                    if (o.pitch) c.voicePitch = o.pitch;
                    if (o.rate) c.voiceRate = o.rate;
                    Assistant.say(I18n.t("Привет! Так я буду тебе отвечать.", "Hi! This is how I will answer you."),
                                  { voice: c.voice, pitch: c.voicePitch, rate: c.voiceRate });
                }
                Label { text: I18n.t("Женский", "Female"); size: 12; weight: 650; color: Theme.fgVariant; elide: Text.ElideNone }
                TunerChoice {
                    width: parent.width
                    options: [{ id: "xenia", icon: "face_3", t: "Ксения" }, { id: "kseniya", icon: "face_3", t: "Ксюша" },
                              { id: "baya", icon: "face_3", t: "Бая" }]
                    current: Assistant.cfg.voice
                    onPicked: v => voiceBox.preview({ voice: v })
                }
                Label { topPadding: 4; text: I18n.t("Мужской", "Male"); size: 12; weight: 650; color: Theme.fgVariant; elide: Text.ElideNone }
                TunerChoice {
                    width: parent.width
                    options: [{ id: "aidar", icon: "face_6", t: "Айдар" }, { id: "eugene", icon: "face_6", t: "Евгений" }]
                    current: Assistant.cfg.voice
                    onPicked: v => voiceBox.preview({ voice: v })
                }
                Label { topPadding: 4; text: I18n.t("Тон", "Pitch"); size: 12; weight: 650; color: Theme.fgVariant; elide: Text.ElideNone }
                TunerChoice {
                    width: parent.width
                    options: [{ id: "low", t: I18n.t("Ниже", "Lower") }, { id: "medium", t: I18n.t("Обычный", "Normal") },
                              { id: "high", t: I18n.t("Выше", "Higher") }]
                    current: Assistant.cfg.voicePitch
                    onPicked: v => voiceBox.preview({ pitch: v })
                }
                Label { topPadding: 4; text: I18n.t("Темп", "Speed"); size: 12; weight: 650; color: Theme.fgVariant; elide: Text.ElideNone }
                TunerChoice {
                    width: parent.width
                    options: [{ id: "slow", t: I18n.t("Медленнее", "Slower") }, { id: "medium", t: I18n.t("Обычный", "Normal") },
                              { id: "fast", t: I18n.t("Быстрее", "Faster") }]
                    current: Assistant.cfg.voiceRate
                    onPicked: v => voiceBox.preview({ rate: v })
                }
            }
            Repeater {
                model: [
                    { k: "speakVoice", icon: "record_voice_over", t: I18n.t("Отвечать голосом на голосовые вопросы", "Speak answers to voice questions") },
                    { k: "speakTyped", icon: "keyboard", t: I18n.t("Озвучивать и ответы из лаунчера", "Also speak answers from the launcher") },
                    { k: "wake", icon: "hearing", t: I18n.t("Слово-активатор: «" + (Assistant.cfg.wakeWords[0] || "обсидиан") + "»; «" + (Assistant.cfg.claudeWords[0] || "морковь") + "» после него — Claude",
                                                         "Wake word: “" + (Assistant.cfg.wakeWords[0] || "obsidian") + "”; “" + (Assistant.cfg.claudeWords[0] || "morkov") + "” after it — Claude") },
                    { k: "followUp", icon: "forum", t: I18n.t("Разговор: после ответа слушать продолжение без «обсидиан»",
                                                              "Conversation: after an answer, keep listening without the wake word") }
                ]
                Rectangle {
                    id: asOpt
                    required property var modelData
                    readonly property bool on: !!Assistant.cfg[modelData.k]
                    width: parent.width; height: 52
                    radius: on ? 18 : 26
                    color: on ? Theme.secondaryContainer : Theme.glassChip
                    Behavior on radius { Anim { kind: "fast" } }
                    Behavior on color { ColorAnimation { duration: 160 } }
                    Icon { id: asOptIcon; anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                           name: asOpt.modelData.icon; size: 20; fill: asOpt.on ? 1 : 0; color: asOpt.on ? Theme.secondaryContainerFg : Theme.fg }
                    Label { anchors { left: asOptIcon.right; leftMargin: 12; right: asSw.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            text: asOpt.modelData.t; size: 14; weight: 600; color: asOpt.on ? Theme.secondaryContainerFg : Theme.fg }
                    M3Switch { id: asSw; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                               scale: 0.85; checked: asOpt.on; onToggled: Assistant.cfg[asOpt.modelData.k] = !asOpt.on }
                    MouseArea { anchors.fill: parent; z: -1; cursorShape: Qt.PointingHandCursor; onClicked: Assistant.cfg[asOpt.modelData.k] = !asOpt.on }
                }
            }
        }
    }

    // ── справа: раздел «Язык»
    Item {
        id: langPage
        visible: root.section === "lang"
        anchors { top: parent.top; bottom: parent.bottom; left: nav.right; right: parent.right; margins: 24; leftMargin: 8 }

        IconButton {
            anchors { top: parent.top; right: parent.right; topMargin: -6; rightMargin: -6 }
            icon: "close"; size: 40; iconSize: 22
            onClicked: root.close()
        }
        Column {
            width: parent.width
            spacing: 4
            Label { text: I18n.t("Язык", "Language"); size: 26; weight: 750; elide: Text.ElideNone }
            Label { text: I18n.t("Язык бара, шторки, настроек и выбора обоев", "Language of the bar, quick settings, settings and wallpaper picker"); size: 14; color: Theme.fgVariant; elide: Text.ElideNone }
        }
        Row {
            y: 96
            spacing: 18
            Repeater {
                model: [{ id: "ru", big: "Аа", t: "Русский", s: "Интерфейс на русском" }, { id: "en", big: "Aa", t: "English", s: "English interface" }]
                Rectangle {
                    id: lc
                    required property var modelData
                    readonly property bool on: Config.lang === modelData.id
                    width: (langPage.width - 18) / 2; height: 150
                    radius: on ? 24 : 36
                    color: on ? Theme.secondaryContainer : lcMouse.containsMouse ? Qt.alpha(Theme.fg, 0.12) : Theme.glassChip
                    border.width: on ? 2 : 0; border.color: Theme.primary
                    Behavior on radius { Anim { kind: "fast" } }
                    Behavior on color { ColorAnimation { duration: 180 } }
                    scale: lcMouse.pressed ? 0.97 : 1
                    Behavior on scale { Anim { kind: "fast" } }
                    Label {
                        anchors { left: parent.left; leftMargin: 24; top: parent.top; topMargin: 16 }
                        text: lc.modelData.big; size: 48; weight: 700
                        color: lc.on ? Theme.primary : Theme.fgVariant; elide: Text.ElideNone
                    }
                    Column {
                        anchors { left: parent.left; leftMargin: 24; bottom: parent.bottom; bottomMargin: 18 }
                        spacing: 2
                        Label { text: lc.modelData.t; size: 17; weight: 700; color: lc.on ? Theme.secondaryContainerFg : Theme.fg; elide: Text.ElideNone }
                        Label { text: lc.modelData.s; size: 13; color: lc.on ? Qt.alpha(Theme.secondaryContainerFg, 0.8) : Theme.fgVariant; elide: Text.ElideNone }
                    }
                    Rectangle {
                        anchors { right: parent.right; top: parent.top; margins: 16 }
                        width: 32; height: 32; radius: 16; color: Theme.primary
                        opacity: lc.on ? 1 : 0; scale: lc.on ? 1 : 0.3
                        Behavior on opacity { Anim { kind: "effects" } }
                        Behavior on scale { Anim { kind: "fast" } }
                        Icon { anchors.centerIn: parent; name: "check"; size: 20; weight: 700; color: Theme.primaryFg }
                    }
                    MouseArea { id: lcMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Config.lang = lc.modelData.id }
                }
            }
        }
    }
}
