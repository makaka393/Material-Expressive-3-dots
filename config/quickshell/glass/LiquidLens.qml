import QtQuick

// Линза Liquid Glass под обычным островом (shaders/liquid.frag): преломляет снимок экрана, сделанный в
// момент вызова, на стыке — свет цветов Gemini. Свет дышит голосом: микрофоном, пока слушает, и речью
// Веги, пока говорит (служба шлёт «level»), думает — бегает; при вызове — волна.
ShaderEffect {
    id: fx
    property string st: "idle"
    property real level: 0
    property bool error: false
    property bool active: false          // линза раскрыта
    property real islandRadius: 20
    property real seam: Theme.barHeight
    property vector2d origin: Qt.vector2d(0, 0)
    property vector2d screen: Qt.vector2d(1, 1)
    property var shot: null              // ShaderEffectSource снимка экрана (Bar.qml)
    property color tint: Theme.frost

    fragmentShader: "shaders/liquid.frag.qsb"
    property vector2d size: Qt.vector2d(width, height)
    property real radius: islandRadius
    property real hasShot: shot ? 1 : 0
    property real t: 0

    // огибающая голоса: быстрая атака, медленный спад
    readonly property real target: st === "listening" ? Math.min(1, level * 2.6)
                                 : st === "speaking" ? 0.2 + Math.min(1, level * 1.8) * 0.8
                                 : st === "thinking" || st === "transcribing" ? 0.35 : 0.12
    property real energy: 0.12
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

    // линза раскрывается от стыка вниз пружинкой, при раскрытии — волна
    property real open: active ? 1 : 0
    Behavior on open { Anim { kind: "spatial" } }
    property real wake: 0
    NumberAnimation { id: wakeAnim; target: fx; property: "wake"; from: 0.02; to: 1; duration: 1200; easing.type: Easing.OutCubic }
    onActiveChanged: if (active) wakeAnim.restart()
}
