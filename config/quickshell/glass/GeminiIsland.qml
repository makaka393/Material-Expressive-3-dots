import QtQuick

// Остров Веги целиком — в духе Gemini (shaders/gemini.frag): тёмное стекло, свет снизу, градиент Google.
// Слушает — бело-голубой свет поднимается от голоса; говорит — волна синий → голубой → фиолетовый →
// розовый; думает — волна кружит. Переходы между состояниями плавные; форма — как у острова.
ShaderEffect {
    id: fx
    property string st: "idle"
    property real level: 0
    property bool error: false
    property real islandRadius: height / 2

    fragmentShader: "shaders/gemini.frag.qsb"
    property vector2d size: Qt.vector2d(width, height)
    property real radius: islandRadius
    property real t: 0
    FrameAnimation { running: fx.visible; onTriggered: fx.t += frameTime }

    property real energy: st === "listening" ? Math.min(1, level * 2.4)
                        : st === "speaking" ? 0.45 + 0.25 * Math.abs(Math.sin(t * 5.1)) + 0.15 * Math.abs(Math.sin(t * 8.3))
                        : 0.3
    Behavior on energy { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    property real listen: st === "listening" || st === "idle" ? 1 : 0
    property real speak: st === "speaking" ? 1 : 0
    property real think: st === "thinking" || st === "transcribing" ? 1 : 0
    property real err: error ? 1 : 0
    Behavior on listen { NumberAnimation { duration: 420; easing.type: Easing.InOutSine } }
    Behavior on speak { NumberAnimation { duration: 420; easing.type: Easing.InOutSine } }
    Behavior on think { NumberAnimation { duration: 420; easing.type: Easing.InOutSine } }
    Behavior on err { NumberAnimation { duration: 300 } }
}
