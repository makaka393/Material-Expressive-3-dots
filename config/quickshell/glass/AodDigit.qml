import QtQuick

// Одна цифра часов AOD.
//  appear 0→1 — появление: цифра всплывает снизу и «выдыхает» из жирной в тонкую
//  смена цифры — старая уезжает вверх, новая выезжает снизу с пружинкой
Item {
    id: d

    property string ch: "0"
    property real size: 100
    property real weight: 300
    property real round: 100
    property color color: Theme.fg
    property real appear: 1

    property string shown: ch
    readonly property real a: Math.max(0, Math.min(1, appear))
    // Вес при появлении меняется ступенями по 40, а не каждый кадр: любое новое значение оси —
    // отдельный экземпляр вариативного шрифта со своим кэшем глифов (~1 МБ и заметная пауза).
    readonly property real wght: a >= 1 ? weight : Math.min(1000, Math.round((weight + (1 - a) * 520) / 40) * 40)

    implicitWidth: t.implicitWidth
    implicitHeight: size * 0.92

    onChChanged: if (ch !== shown) flip.restart()

    Text {
        id: t
        property real dy: 0
        property real fo: 1
        anchors.horizontalCenter: parent.horizontalCenter
        y: (d.height - height) / 2 + dy + (1 - d.appear) * d.size * 0.45
        text: d.shown
        color: d.color
        opacity: fo * d.a
        font.family: Theme.font
        font.pixelSize: d.size
        // появление: wght от жирного к нужному (как вдох-выдох)
        font.variableAxes: ({ "wght": d.wght, "ROND": d.round, "opsz": Math.min(144, d.size) })
        font.features: ({ "tnum": 1 })
    }

    SequentialAnimation {
        id: flip
        ParallelAnimation {
            NumberAnimation { target: t; property: "dy"; to: -d.size * 0.28; duration: 170; easing.type: Easing.InCubic }
            NumberAnimation { target: t; property: "fo"; to: 0; duration: 170 }
        }
        ScriptAction { script: { d.shown = d.ch; t.dy = d.size * 0.3; } }
        ParallelAnimation {
            NumberAnimation { target: t; property: "dy"; to: 0; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
            NumberAnimation { target: t; property: "fo"; to: 1; duration: 240 }
        }
    }
}
