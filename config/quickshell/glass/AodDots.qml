import QtQuick

// Точечное табло для AOD: цифры 5×7 из круглых точек. Горящие — цветом темы (часы) и
// светлым (минуты), погашенные едва видны; при смене цифры точки перетекают.
Column {
    id: m

    required property var clock          // AodClock: hh, mm, date, k, at(), fade()
    readonly property real k: clock.k
    readonly property real dot: 22 * k
    readonly property real pitch: 29 * k

    // строки сверху вниз, бит 4 — левая точка
    readonly property var glyphs: ({
        "0": [14, 17, 19, 21, 25, 17, 14], "1": [4, 12, 4, 4, 4, 4, 14], "2": [14, 17, 1, 2, 4, 8, 31],
        "3": [14, 17, 1, 6, 1, 17, 14], "4": [2, 6, 10, 18, 31, 2, 2], "5": [31, 16, 30, 1, 1, 17, 14],
        "6": [6, 8, 16, 30, 17, 17, 14], "7": [31, 1, 2, 4, 8, 8, 8], "8": [14, 17, 17, 14, 17, 17, 14],
        "9": [14, 17, 17, 15, 1, 2, 12]
    })

    spacing: 34 * k

    component Matrix: Grid {
        id: mx
        property string ch: "0"
        property color lit: m.clock.cFg
        property real appear: 1
        property bool colon: false
        columns: colon ? 1 : 5
        spacing: m.pitch - m.dot
        Repeater {
            model: mx.colon ? 7 : 35
            Rectangle {
                required property int index
                readonly property int row: Math.floor(index / mx.columns)
                readonly property int col: index % mx.columns
                readonly property bool on: mx.colon ? (row === 2 || row === 4)
                                                    : ((m.glyphs[mx.ch] ?? m.glyphs["0"])[row] >> (4 - col) & 1) === 1
                width: m.dot; height: m.dot; radius: m.dot / 2
                color: on ? mx.lit : Qt.alpha(m.clock.cFg, 0.07)
                scale: (on ? 1 : 0.5) * Math.min(1.15, m.clock.at(mx.appearAt + col * 0.02 + row * 0.012, 0.45))
                Behavior on color { ColorAnimation { duration: 320 } }
                Behavior on scale { enabled: m.clock.p >= 1; NumberAnimation { duration: 420; easing.type: Easing.OutBack } }
            }
        }
        property real appearAt: 0
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 24 * m.k
        Matrix { ch: m.clock.hh[0]; lit: m.clock.cPrimary; appearAt: 0.04 }
        Matrix { ch: m.clock.hh[1]; lit: m.clock.cPrimary; appearAt: 0.10 }
        Matrix { colon: true; lit: m.clock.cTertiary; appearAt: 0.16 }
        Matrix { ch: m.clock.mm[0]; appearAt: 0.20 }
        Matrix { ch: m.clock.mm[1]; appearAt: 0.26 }
    }
    Label {
        visible: m.clock.showDate
        anchors.horizontalCenter: parent.horizontalCenter
        text: m.clock.date
        size: Math.max(8, 26 * m.k); weight: 550
        color: m.clock.dateColor
        opacity: m.clock.fade(0.5, 0.3)
        elide: Text.ElideNone
    }
}
