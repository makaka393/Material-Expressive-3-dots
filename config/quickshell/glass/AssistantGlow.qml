import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

// Сияние Веги — в духе разговора с Gemini Live: мягкие пятна цветов Gemini вытекают из острова вниз,
// когда с ней говорят, и втягиваются обратно, когда разговор кончился. Слушает — пятна дышат громкостью
// микрофона; думает — медленно кружатся; отвечает — пульсируют в такт речи.
// Своё окно (слой quickshell-vega): в окне бара Hyprland размыл бы под ним фон — вышла бы матовая плашка.
// Окно поверх бара, но остров из света вырезан по его форме — стекло острова не красится. Кликов не ловит.
PanelWindow {
    id: win
    property Item island: null           // DynamicIsland этого экрана
    property bool active: false

    anchors { top: true; left: true; right: true }
    implicitHeight: 600
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}
    WlrLayershell.namespace: "quickshell-vega"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Item {
        id: glow
        readonly property string st: Assistant.state
        width: 980
        height: 480
        x: win.island ? win.island.x + win.island.width / 2 - width / 2 : 0
        y: win.island ? win.island.y + win.island.height / 2 - 70 : 0
        opacity: win.active ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { Anim { kind: "effects"; duration: win.active ? 380 : 520 } }

        // время и «энергия»: слушает — громкость микрофона, отвечает — дыхание речи, думает — ровный фон
        property real t: 0
        FrameAnimation { running: glow.visible; onTriggered: glow.t += frameTime }
        readonly property real target: st === "listening" ? 0.25 + Math.min(1, Assistant.level * 2.4) * 0.75
                                     : st === "speaking" ? 0.5 + 0.22 * Math.abs(Math.sin(t * 5.3)) + 0.12 * Math.abs(Math.sin(t * 8.9))
                                     : st === "thinking" || st === "transcribing" ? 0.38 : 0.2
        property real energy: target
        Behavior on energy { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        // появление — из острова: растёт вниз пружинкой
        Item {
            id: pour
            anchors.fill: parent
            transformOrigin: Item.Top
            scale: win.active ? 1 : 0.35
            Behavior on scale { Anim { kind: "spatial" } }

            Item {
                id: blobs
                anchors.fill: parent
                visible: false
                layer.enabled: true
                // цвета Gemini: синий, фиолетовый, розовый и голубой
                Repeater {
                    model: [{ c: "#4796E3", ph: 0.0, sp: 0.55, dx: 230, w: 360 },
                            { c: "#9177C7", ph: 2.1, sp: 0.42, dx: 190, w: 320 },
                            { c: "#CA6673", ph: 4.2, sp: 0.67, dx: 250, w: 300 },
                            { c: "#5AC8FA", ph: 1.2, sp: 0.36, dx: 160, w: 280 }]
                    Rectangle {
                        required property var modelData
                        readonly property real swirl: glow.st === "thinking" || glow.st === "transcribing" ? 1.8 : 1
                        readonly property real k: 0.72 + glow.energy * 0.55
                        width: modelData.w * k; height: width * 0.62; radius: height / 2
                        color: modelData.c
                        opacity: 0.5 + glow.energy * 0.35
                        x: glow.width / 2 - width / 2 + Math.sin(glow.t * modelData.sp * swirl + modelData.ph) * modelData.dx
                        y: 60 + Math.cos(glow.t * modelData.sp * 0.8 * swirl + modelData.ph) * 34 + (1 - glow.energy) * 30
                    }
                }
            }
            // форма острова — её из света вырезаем (маска с инверсией)
            Item {
                id: hole
                anchors.fill: parent
                visible: false
                layer.enabled: true
                Rectangle {
                    // координаты острова — в системе пятен (pour масштабируется от верха)
                    x: win.island ? win.island.x - glow.x : 0
                    y: win.island ? (win.island.y - glow.y) / pour.scale : 0
                    width: win.island ? win.island.width : 0
                    height: win.island ? win.island.height / pour.scale : 0
                    radius: win.island ? win.island.radius : 0
                    color: "black"
                }
            }
            // мягко: всё вместе — через размытие, без резких краёв
            MultiEffect {
                anchors.fill: blobs
                source: blobs
                blurEnabled: true
                blur: 1
                blurMax: 64
                blurMultiplier: 1.4
                maskEnabled: true
                maskSource: hole
                maskInverted: true
                opacity: 0.8
            }
        }
    }
}
