import QtQuick
import Quickshell.Widgets

// Содержимое выбора обоев: карусель превью + цвета с обоев + схема + тёмная/светлая тема
Item {
    id: root

    property var model: null            // ListModel { path, thumb }
    property string current: ""         // применённые обои
    property string scheme: "scheme-vibrant"
    property string mode: "dark"
    property bool busy: false
    property string currentSource: ""   // цвет, от которого построена текущая тема ("" — авто)
    // палитры для выбранных в карусели обоев: [{ src, p, s, t, pc }] — заполняет Picker
    property var palettes: []
    property bool palLoading: false
    property int palIdx: 0
    // свой цвет (палитра с hex): { src, p, s, t, pc } — палитру считает Picker
    property var customPal: null
    property bool customSel: false
    property bool customOpen: false
    signal requestCustom(string hex)
    readonly property string selPath: model && list.currentIndex >= 0 && list.currentIndex < model.count ? model.get(list.currentIndex).path : ""
    readonly property string selThumb: model && list.currentIndex >= 0 && list.currentIndex < model.count ? model.get(list.currentIndex).thumb : ""
    readonly property string selColor: customSel && customPal ? customPal.src
                                     : palettes.length > 0 ? palettes[Math.min(palIdx, palettes.length - 1)].src : ""
    signal apply(string path, string color)
    signal setScheme(string scheme)
    signal setMode(string mode)
    signal close()

    readonly property var schemes: [
        { id: "scheme-vibrant",     name: I18n.t("Яркая", "Vibrant") },
        { id: "scheme-expressive",  name: I18n.t("Экспрессивная", "Expressive") },
        { id: "scheme-tonal-spot",  name: I18n.t("Спокойная", "Calm") },
        { id: "scheme-fidelity",    name: I18n.t("Как на обоях", "As wallpaper") },
        { id: "scheme-rainbow",     name: I18n.t("Радуга", "Rainbow") },
        { id: "scheme-monochrome",  name: I18n.t("Моно", "Mono") }
    ]

    function focusList() { list.forceActiveFocus(); }
    // новые палитры пришли: для уже применённых обоев подсветить цвет, который стоит сейчас
    function setPalettes(arr) {
        let idx = 0;
        if (selPath === current && currentSource !== "")
            for (let i = 0; i < arr.length; i++)
                if (arr[i].src.toLowerCase() === currentSource.toLowerCase()) { idx = i; break; }
        palIdx = idx;
        palettes = arr;
        // тема стоит от своего цвета, которого нет среди цветов обоев — показать его как свой
        const own = selPath === current && currentSource !== ""
                    && !arr.some(a => a.src.toLowerCase() === currentSource.toLowerCase());
        customSel = own;
        if (own && (!customPal || customPal.src.toLowerCase() !== currentSource.toLowerCase())) requestCustom(currentSource);
    }
    function applySelected() { if (selPath !== "") apply(selPath, selColor); }
    function cyclePalette(d) {
        if (customSel) { customSel = false; return; }
        if (palettes.length > 1) palIdx = (palIdx + d + palettes.length) % palettes.length;
    }
    function selectCurrent() {
        if (!model) return;
        for (let i = 0; i < model.count; i++)
            if (model.get(i).path === current) { list.currentIndex = i; list.positionViewAtIndex(i, ListView.Center); return; }
    }

    // ── свотч палитры: сверху primary, снизу secondary + tertiary, в центре primary container
    component Swatch: Item {
        id: sw
        property var pal: ({ p: "#888", s: "#888", t: "#888", pc: "#888", src: "" })
        property bool on: false
        property bool applied: false
        signal picked()
        width: 56; height: 56
        scale: swMouse.pressed ? 0.9 : 1
        Behavior on scale { Anim { kind: "fast" } }
        Rectangle {
            anchors.centerIn: parent
            width: 56; height: 56
            radius: sw.on ? 20 : 28
            color: "transparent"
            border.width: 3
            border.color: Theme.primary
            opacity: sw.on ? 1 : 0
            Behavior on opacity { Anim { kind: "effects" } }
            Behavior on radius { Anim { kind: "fast" } }
        }
        Item {
            id: face
            anchors.centerIn: parent
            width: sw.on ? 42 : 46; height: width
            readonly property real r: sw.on ? 14 : width / 2
            Behavior on width { Anim { kind: "fast" } }
            // «Точный цвет» в настройках — сверху сам выбранный цвет, снизу его мягкие оттенки
            readonly property bool exact: Config.exactColor && /^#/.test(sw.pal.src || "")
            readonly property color src: exact ? sw.pal.src : "black"
            function soft(dh, k, l) { return Qt.hsla((src.hslHue + dh + 1) % 1, Math.max(0.25, src.hslSaturation * k), l, 1); }
            readonly property color cTop: exact ? src : sw.pal.p
            readonly property color cLeft: exact ? soft(0, 0.55, 0.76) : sw.pal.s
            readonly property color cRight: exact ? soft(0.025, 0.85, 0.65) : sw.pal.t
            Rectangle { anchors.fill: parent; radius: face.r; color: face.cTop }
            Repeater {
                model: 2
                Item {
                    required property int index
                    x: index * face.width / 2; y: face.height / 2
                    width: face.width / 2; height: face.height / 2
                    clip: true
                    Rectangle {
                        x: -parent.x; y: -face.height / 2
                        width: face.width; height: face.height; radius: face.r
                        color: index === 0 ? face.cLeft : face.cRight
                    }
                }
            }
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.42; height: width; radius: width / 2
                color: sw.pal.pc
                Icon { anchors.centerIn: parent; name: "check"; size: 14; weight: 700; color: sw.pal.p; opacity: sw.applied ? 1 : 0 }
            }
        }
        MouseArea { id: swMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sw.picked() }
    }

    // ── заголовок
    Row {
        id: header
        anchors { top: parent.top; left: parent.left; topMargin: 22; leftMargin: 28 }
        spacing: 10
        Icon { anchors.verticalCenter: parent.verticalCenter; name: "wallpaper"; size: 26; fill: 1; color: Theme.primary }
        Label { anchors.verticalCenter: parent.verticalCenter; text: I18n.t("Обои и тема", "Wallpaper & style"); size: 22; weight: 750; elide: Text.ElideNone }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: root.model ? root.model.count : ""
            size: 13; weight: 600; color: Theme.fgVariant; elide: Text.ElideNone
        }
    }

    // ── справа: тёмная/светлая
    Rectangle {
        id: modeSwitch
        anchors { top: parent.top; right: parent.right; topMargin: 18; rightMargin: 24 }
        width: 96; height: 40; radius: 20
        color: Theme.glassChip
        Rectangle {
            x: root.mode === "dark" ? 4 : 50
            y: 4; width: 42; height: 32; radius: 16
            color: Theme.primary
            Behavior on x { Anim { kind: "fast" } }
        }
        Row {
            anchors.fill: parent
            anchors.margins: 4
            Repeater {
                model: [{ m: "dark", i: "dark_mode" }, { m: "light", i: "light_mode" }]
                Item {
                    required property var modelData
                    width: 44; height: 32
                    Icon {
                        anchors.centerIn: parent
                        name: modelData.i; size: 18; fill: 1
                        color: root.mode === modelData.m ? Theme.primaryFg : Theme.fgVariant
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.mode !== modelData.m) root.setMode(modelData.m)
                    }
                }
            }
        }
    }

    // ── схемы цветов
    Row {
        anchors { top: parent.top; right: modeSwitch.left; topMargin: 18; rightMargin: 12 }
        spacing: 6
        Repeater {
            model: root.schemes
            Rectangle {
                id: chip
                required property var modelData
                readonly property bool on: root.scheme === modelData.id
                width: chipText.implicitWidth + (on ? 50 : 28)
                height: 40
                radius: on ? 14 : 20
                color: on ? Theme.secondaryContainer : chipMouse.containsMouse ? Qt.alpha(Theme.fg, 0.12) : Theme.glassChip
                Behavior on width { Anim { kind: "fast" } }
                Behavior on radius { Anim { kind: "fast" } }
                Behavior on color { ColorAnimation { duration: 180 } }
                Icon {
                    id: tick
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    name: "check"; size: 16
                    color: Theme.secondaryContainerFg
                    opacity: chip.on ? 1 : 0
                    scale: chip.on ? 1 : 0.3
                    Behavior on opacity { Anim { kind: "effects" } }
                    Behavior on scale { Anim { kind: "fast" } }
                }
                Label {
                    id: chipText
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    text: chip.modelData.name
                    size: 13; weight: chip.on ? 700 : 550
                    color: chip.on ? Theme.secondaryContainerFg : Theme.fg
                    elide: Text.ElideNone
                }
                MouseArea {
                    id: chipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (!chip.on) root.setScheme(chip.modelData.id)
                }
            }
        }
    }

    // ── карусель
    ListView {
        id: list
        // фиксированные размеры: если ListView меняет ширину при открытии окна,
        // Qt 6.11 падает (QQuickItemView::setPreferredHighlightEnd)
        anchors { horizontalCenter: parent.horizontalCenter; top: header.bottom; topMargin: 22 }
        width: 1200
        height: 230
        orientation: ListView.Horizontal
        spacing: 18
        clip: true
        model: root.model
        focus: true
        keyNavigationEnabled: true
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: 430
        preferredHighlightEnd: 770
        highlightMoveDuration: 380
        cacheBuffer: 2000

        Keys.onReturnPressed: root.applySelected()
        Keys.onEnterPressed: root.applySelected()
        Keys.onTabPressed: root.cyclePalette(1)
        Keys.onBacktabPressed: root.cyclePalette(-1)
        Keys.onDownPressed: root.cyclePalette(1)
        Keys.onUpPressed: root.cyclePalette(-1)
        Keys.onEscapePressed: root.customOpen ? root.customOpen = false : root.close()

        WheelHandler {
            property real acc: 0
            onWheel: ev => {
                acc += ev.angleDelta.y + ev.angleDelta.x;
                if (Math.abs(acc) >= 120) {
                    acc > 0 ? list.decrementCurrentIndex() : list.incrementCurrentIndex();
                    acc = 0;
                }
            }
        }

        delegate: Item {
            id: card
            required property string path
            required property string thumb
            required property int index
            readonly property bool sel: ListView.isCurrentItem
            readonly property bool applied: root.current === path
            width: 340
            height: 230

            Item {
                anchors.centerIn: parent
                width: 340
                height: 192
                scale: card.sel ? 1.08 : mouse.containsMouse ? 1.03 : 0.92
                opacity: card.sel ? 1 : 0.62
                Behavior on scale { Anim { kind: "spatial" } }
                Behavior on opacity { Anim { kind: "effects" } }

                ClippingRectangle {
                    anchors.fill: parent
                    radius: card.sel ? 22 : 30
                    color: Theme.surfaceHigh
                    Behavior on radius { Anim { kind: "fast" } }
                    Image {
                        anchors.fill: parent
                        source: card.thumb !== "" ? "file://" + card.thumb : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 480
                        sourceSize.height: 270
                    }
                }
                // рамка выбранного
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -5
                    radius: (card.sel ? 22 : 30) + 5
                    color: "transparent"
                    border.width: 3
                    border.color: Theme.primary
                    opacity: card.sel ? 1 : 0
                    Behavior on opacity { Anim { kind: "effects" } }
                }
                // значок «видео» / «гиф»
                Rectangle {
                    readonly property string kind: /\.(mp4|webm|mkv|mov)$/i.test(card.path) ? "movie"
                                                 : /\.gif$/i.test(card.path) ? "gif" : ""
                    visible: kind !== ""
                    anchors { left: parent.left; top: parent.top; margins: 10 }
                    width: kindRow.implicitWidth + 16; height: 26; radius: 13
                    color: Qt.alpha(Theme.surfaceLowest, 0.7)
                    Row {
                        id: kindRow
                        anchors.centerIn: parent
                        spacing: 4
                        Icon { anchors.verticalCenter: parent.verticalCenter; name: parent.parent.kind === "movie" ? "play_circle" : "animation"; size: 15; fill: 1; color: Theme.primary }
                        Label { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.kind === "movie" ? I18n.t("видео", "video") : "GIF"; size: 11; weight: 700; elide: Text.ElideNone }
                    }
                }
                // значок «применено»
                Rectangle {
                    anchors { right: parent.right; bottom: parent.bottom; margins: 10 }
                    width: 34; height: 34; radius: 17
                    color: Theme.primary
                    opacity: card.applied ? 1 : 0
                    scale: card.applied ? 1 : 0.3
                    Behavior on opacity { Anim { kind: "effects" } }
                    Behavior on scale { Anim { kind: "fast" } }
                    Icon { anchors.centerIn: parent; name: "check"; size: 20; weight: 700; color: Theme.primaryFg }
                }
                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        // первый клик — выбрать (появятся цвета), второй — применить
                        if (list.currentIndex !== card.index) list.currentIndex = card.index;
                        else root.applySelected();
                    }
                }
            }
        }
    }

    // ── подпись: имя файла
    Label {
        id: fileName
        anchors { horizontalCenter: parent.horizontalCenter; top: list.bottom; topMargin: 6 }
        width: 600
        horizontalAlignment: Text.AlignHCenter
        text: root.selPath.split("/").pop()
        size: 13; weight: 600
    }

    // ── цвета с обоев: из какого строить тему (как «Обои и стиль» на Pixel) + свой цвет
    Item {
        id: palRow
        anchors { horizontalCenter: parent.horizontalCenter; top: fileName.bottom; topMargin: 12 }
        width: swatches.implicitWidth
        height: 60

        Row {
            id: swatches
            anchors.centerIn: parent
            spacing: 14

            Repeater {
                model: root.palettes
                Swatch {
                    required property var modelData
                    required property int index
                    pal: modelData
                    opacity: root.palLoading ? 0.35 : 1
                    on: !root.customSel && root.palIdx === index
                    applied: root.selPath === root.current && root.currentSource !== ""
                             && modelData.src.toLowerCase() === root.currentSource.toLowerCase()
                    onPicked: { root.customSel = false; root.palIdx = index; root.applySelected(); list.forceActiveFocus(); }
                }
            }
            // свой цвет (появляется, когда выбран в палитре)
            Swatch {
                visible: root.customPal !== null
                pal: root.customPal || ({ p: "#888", s: "#888", t: "#888", pc: "#888", src: "" })
                on: root.customSel
                applied: root.customPal !== null && root.selPath === root.current
                         && root.customPal.src.toLowerCase() === root.currentSource.toLowerCase()
                onPicked: { root.customSel = true; root.applySelected(); list.forceActiveFocus(); }
            }
            // кнопка «свой цвет»
            Rectangle {
                id: addBtn
                width: 56; height: 56
                radius: root.customOpen ? 20 : 28
                color: root.customOpen ? Theme.secondaryContainer : addMouse.containsMouse ? Qt.alpha(Theme.fg, 0.14) : Theme.glassChip
                Behavior on radius { Anim { kind: "fast" } }
                Behavior on color { ColorAnimation { duration: 180 } }
                Icon {
                    anchors.centerIn: parent
                    name: root.customOpen ? "close" : "colorize"
                    size: 24; fill: 1
                    color: root.customOpen ? Theme.secondaryContainerFg : Theme.fg
                }
                MouseArea {
                    id: addMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.customOpen = !root.customOpen;
                        if (root.customOpen) {
                            const start = root.customPal ? root.customPal.src : root.selColor !== "" ? root.selColor : String(Theme.primary);
                            picker.setHex(start);
                            hexField.forceActiveFocus();
                        } else list.forceActiveFocus();
                    }
                }
            }
        }
    }

    // ── палитра: квадрат насыщенность/яркость + полоса оттенка + hex
    Rectangle {
        id: picker
        z: 10
        anchors { horizontalCenter: palRow.horizontalCenter; bottom: palRow.top; bottomMargin: 10 }
        width: 380; height: 266
        radius: 28
        color: Theme.surfaceHigh
        border.width: 1; border.color: Theme.glassBorder
        visible: opacity > 0
        opacity: root.customOpen ? 1 : 0
        scale: root.customOpen ? 1 : 0.92
        transformOrigin: Item.Bottom
        Behavior on opacity { Anim { kind: "effects" } }
        Behavior on scale { Anim { kind: "fast" } }

        property real h: 0.6
        property real s: 0.6
        property real v: 0.8
        readonly property color col: Qt.hsva(h, s, v, 1)
        function hex2(n) { const x = Math.round(n * 255).toString(16); return x.length < 2 ? "0" + x : x; }
        readonly property string hex: "#" + hex2(col.r) + hex2(col.g) + hex2(col.b)
        function setHex(t) {
            const c = Qt.color(t);
            if (c.hsvHue >= 0) h = c.hsvHue;
            s = c.hsvSaturation; v = c.hsvValue;
            hexField.text = hex;
        }
        // ползали — обновить поле и посчитать палитру (с задержкой, чтобы не дёргать matugen на каждый пиксель)
        onHexChanged: { if (!hexField.activeFocus) hexField.text = hex; previewTimer.restart(); }
        Timer { id: previewTimer; interval: 160; onTriggered: if (root.customOpen) root.requestCustom(picker.hex) }

        MouseArea { anchors.fill: parent }   // клики не проваливаются в карусель

        // квадрат S/V
        Rectangle {
            id: sv
            x: 18; y: 18
            width: parent.width - 36; height: 130
            radius: 16
            color: Qt.hsva(picker.h, 1, 1, 1)
            Rectangle {
                anchors.fill: parent; radius: 16
                gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: "white" } GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) } }
            }
            Rectangle {
                anchors.fill: parent; radius: 16
                gradient: Gradient { GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0) } GradientStop { position: 1; color: "black" } }
            }
            Rectangle {
                width: 22; height: 22; radius: 11
                x: picker.s * sv.width - 11; y: (1 - picker.v) * sv.height - 11
                color: picker.col
                border.width: 3; border.color: "white"
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.CrossCursor
                function set(m) { picker.s = Math.max(0, Math.min(1, m.x / width)); picker.v = 1 - Math.max(0, Math.min(1, m.y / height)); }
                onPressed: m => set(m)
                onPositionChanged: m => set(m)
            }
        }
        // полоса оттенка
        Rectangle {
            id: hue
            x: 18; anchors.top: sv.bottom; anchors.topMargin: 14
            width: sv.width; height: 20; radius: 10
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.000; color: "#ff0000" }
                GradientStop { position: 0.167; color: "#ffff00" }
                GradientStop { position: 0.333; color: "#00ff00" }
                GradientStop { position: 0.500; color: "#00ffff" }
                GradientStop { position: 0.667; color: "#0000ff" }
                GradientStop { position: 0.833; color: "#ff00ff" }
                GradientStop { position: 1.000; color: "#ff0000" }
            }
            Rectangle {
                width: 14; height: 28; radius: 7
                anchors.verticalCenter: parent.verticalCenter
                x: picker.h * hue.width - 7
                color: Qt.hsva(picker.h, 1, 1, 1)
                border.width: 3; border.color: "white"
            }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                function set(m) { picker.h = Math.max(0, Math.min(0.999, (m.x - 6) / hue.width)); }
                onPressed: m => set(m)
                onPositionChanged: m => set(m)
            }
        }
        // hex + применить
        Row {
            x: 18; anchors.top: hue.bottom; anchors.topMargin: 16
            spacing: 10
            Rectangle {
                width: 40; height: 40; radius: 14
                color: picker.col
                border.width: 1; border.color: Theme.glassBorder
            }
            Rectangle {
                width: 170; height: 40; radius: 20
                color: Theme.glassChip
                border.width: hexField.activeFocus ? 2 : 0
                border.color: Theme.primary
                TextInput {
                    id: hexField
                    anchors.fill: parent
                    anchors.leftMargin: 16; anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    selectionColor: Theme.primary
                    selectedTextColor: Theme.primaryFg
                    font.family: Theme.font
                    font.pixelSize: 16
                    font.capitalization: Font.AllLowercase
                    maximumLength: 7
                    validator: RegularExpressionValidator { regularExpression: /#?[0-9a-fA-F]{0,6}/ }
                    onTextEdited: {
                        const t = text.startsWith("#") ? text : "#" + text;
                        if (/^#[0-9a-fA-F]{6}$/.test(t)) picker.setHex(t);
                    }
                    Keys.onReturnPressed: applyBtn.go()
                    Keys.onEnterPressed: applyBtn.go()
                    Keys.onEscapePressed: { root.customOpen = false; list.forceActiveFocus(); }
                }
            }
            Rectangle {
                id: applyBtn
                width: 122; height: 40; radius: applyMouse.pressed ? 12 : 20
                color: Theme.primary
                Behavior on radius { Anim { kind: "fast" } }
                function go() {
                    root.customPal = root.customPal && root.customPal.src === picker.hex ? root.customPal
                                   : { src: picker.hex, p: picker.hex, s: picker.hex, t: picker.hex, pc: picker.hex };
                    root.requestCustom(picker.hex);
                    root.customSel = true;
                    root.customOpen = false;
                    root.applySelected();
                    list.forceActiveFocus();
                }
                Label { anchors.centerIn: parent; text: I18n.t("Применить", "Apply"); size: 14; weight: 700; color: Theme.primaryFg; elide: Text.ElideNone }
                MouseArea { id: applyMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: applyBtn.go() }
            }
        }
    }

    // ── подсказка
    Label {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 14 }
        text: root.busy ? I18n.t("применяю…", "applying…") : I18n.t("← → обои  ·  ↑ ↓ цвет  ·  Enter применить  ·  Esc закрыть", "← → wallpaper  ·  ↑ ↓ color  ·  Enter apply  ·  Esc close")
        size: 12; color: Theme.fgVariant; elide: Text.ElideNone
    }
}
