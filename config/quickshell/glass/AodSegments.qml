import QtQuick

// «Сегменты» для AOD: семисегментные цифры из толстых мягких пилюль. Горящие сегменты —
// цветом темы (часы) и светлым (минуты), погашенные едва видны; при смене цифры перетекают.
Column {
    id: sg

    required property var clock          // AodClock: hh, mm, date, k, p, at(), fade()
    readonly property real k: clock.k

    // сегменты a b c d e f g → какие горят у цифры
    readonly property var glyphs: ({
        "0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc",
        "5": "afgcd", "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abfgcd"
    })

    spacing: 34 * k

    component Digit: Item {
        id: dg
        property string ch: "0"
        property color lit: Theme.fg
        property real k: 1
        property real appear: 1
        property bool bound: false           // анимировать ли смену (после появления)

        readonly property real w: 118 * k
        readonly property real h: 216 * k
        readonly property real t: 30 * k      // толщина сегмента
        readonly property real gap: 5 * k
        readonly property real vlen: (h - t) / 2 - 2 * gap
        readonly property string on: sg.glyphs[ch] ?? ""

        width: w; height: h

        Repeater {
            model: [
                { id: "a", x: dg.t / 2 + dg.gap, y: 0,                       w: dg.w - dg.t - 2 * dg.gap, h: dg.t },
                { id: "g", x: dg.t / 2 + dg.gap, y: (dg.h - dg.t) / 2,        w: dg.w - dg.t - 2 * dg.gap, h: dg.t },
                { id: "d", x: dg.t / 2 + dg.gap, y: dg.h - dg.t,              w: dg.w - dg.t - 2 * dg.gap, h: dg.t },
                { id: "f", x: 0,                 y: dg.t / 2 + dg.gap,        w: dg.t, h: dg.vlen },
                { id: "b", x: dg.w - dg.t,       y: dg.t / 2 + dg.gap,        w: dg.t, h: dg.vlen },
                { id: "e", x: 0,                 y: dg.h / 2 + dg.gap,        w: dg.t, h: dg.vlen },
                { id: "c", x: dg.w - dg.t,       y: dg.h / 2 + dg.gap,        w: dg.t, h: dg.vlen }
            ]
            Rectangle {
                required property var modelData
                required property int index
                readonly property bool lit: dg.on.indexOf(modelData.id) >= 0
                x: modelData.x; y: modelData.y
                width: modelData.w; height: modelData.h
                radius: Math.min(width, height) / 2
                color: lit ? dg.lit : Qt.alpha(Theme.fg, 0.07)
                scale: (lit ? 1 : 0.9) * Math.min(1.1, dg.appear)
                opacity: Math.min(1, dg.appear * 1.5)
                Behavior on color { ColorAnimation { duration: 320 } }
                Behavior on scale { enabled: dg.bound; NumberAnimation { duration: 420; easing.type: Easing.OutBack } }
            }
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 26 * sg.k
        Digit { ch: sg.clock.hh[0]; lit: Theme.primary; k: sg.k; appear: sg.clock.at(0.04, 0.5); bound: sg.clock.p >= 1 }
        Digit { ch: sg.clock.hh[1]; lit: Theme.primary; k: sg.k; appear: sg.clock.at(0.10, 0.5); bound: sg.clock.p >= 1 }
        // двоеточие
        Item {
            width: 30 * sg.k; height: 216 * sg.k
            Repeater {
                model: [0.31, 0.69]
                Rectangle {
                    required property real modelData
                    width: 30 * sg.k; height: width; radius: width / 2
                    y: parent.height * modelData - height / 2
                    color: Theme.tertiary
                    scale: sg.clock.at(0.16, 0.5)
                    Behavior on color { ColorAnimation { duration: 300 } }
                }
            }
        }
        Digit { ch: sg.clock.mm[0]; k: sg.k; appear: sg.clock.at(0.20, 0.5); bound: sg.clock.p >= 1 }
        Digit { ch: sg.clock.mm[1]; k: sg.k; appear: sg.clock.at(0.26, 0.5); bound: sg.clock.p >= 1 }
    }
    Label {
        visible: sg.clock.showDate
        anchors.horizontalCenter: parent.horizontalCenter
        text: sg.clock.date
        size: Math.max(8, 26 * sg.k); weight: 550
        color: Theme.fgVariant
        opacity: sg.clock.fade(0.5, 0.3)
        elide: Text.ElideNone
    }
}
