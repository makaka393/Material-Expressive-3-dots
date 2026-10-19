import QtQuick

// Свет Веги внутри острова (shaders/gemini.frag): аврора цветов Gemini, огни по краю в духе Siri,
// волна при вызове. Слушает — свет поднимается от громкости микрофона; говорит — от громкости её
// собственной речи (служба шлёт «level» и пока говорит); думает — свет кружит.
ShaderEffect {
    id: fx
    property string st: "idle"
    property real level: 0               // Assistant.level: микрофон или речь Веги, 0…1
    property bool error: false
    property bool active: false          // остров открыт для Веги — волна при каждом вызове
    property real islandRadius: height / 2

    fragmentShader: "shaders/gemini.frag.qsb"
    property vector2d size: Qt.vector2d(width, height)
    property real radius: islandRadius
    property real t: 0

    // огибающая голоса: быстрая атака, медленный спад — как стрелка индикатора, без дрожи
    readonly property real target: st === "listening" ? Math.min(1, level * 2.6)
                                 : st === "speaking" ? 0.22 + Math.min(1, level * 1.8) * 0.78
                                 : st === "thinking" || st === "transcribing" ? 0.35 : 0.15
    property real energy: 0.15
    FrameAnimation {
        running: fx.visible
        onTriggered: {
            fx.t += frameTime;
            const k = fx.target > fx.energy ? 0.38 : 0.06;
            fx.energy += (fx.target - fx.energy) * Math.min(1, k * frameTime * 60);
        }
    }

    property real listen: st === "listening" || st === "idle" ? 1 : 0
    property real speak: st === "speaking" ? 1 : 0
    property real think: st === "thinking" || st === "transcribing" ? 1 : 0
    property real err: error ? 1 : 0
    Behavior on listen { NumberAnimation { duration: 520; easing.type: Easing.InOutSine } }
    Behavior on speak { NumberAnimation { duration: 520; easing.type: Easing.InOutSine } }
    Behavior on think { NumberAnimation { duration: 520; easing.type: Easing.InOutSine } }
    Behavior on err { NumberAnimation { duration: 300 } }

    // волна света из центра — когда остров открылся для Веги
    property real wake: 0
    NumberAnimation { id: wakeAnim; target: fx; property: "wake"; from: 0.02; to: 1; duration: 1100; easing.type: Easing.OutCubic }
    onActiveChanged: if (active) wakeAnim.restart()
}
