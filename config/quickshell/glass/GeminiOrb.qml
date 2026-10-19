import QtQuick
import QtQuick.Effects

// «Шар» Веги в острове — в духе Gemini, вписанный в стекло: тёмное полупрозрачное стекло, свет внутри.
//  слушает — круглый шар, снизу белёсо-голубой свет поднимается от громкости голоса;
//  говорит — шар перетекает в пилюлю, снизу волны синего, фиолетового и розового;
//  думает, распознаёт — круг, свет медленно кружит.
// Форма меняется пружинкой (M3 Expressive), появление — «выезжает» из острова, как новая Siri.
Item {
    id: orb
    property string st: "idle"
    property real level: 0               // громкость микрофона 0…1
    property bool error: false
    property bool shown: true
    readonly property bool talking: st === "speaking"
    readonly property bool swirl: st === "thinking" || st === "transcribing"

    width: talking ? 92 : 52
    height: talking ? 46 : 52
    Behavior on width { Anim { kind: "spatial" } }
    Behavior on height { Anim { kind: "spatial" } }
    readonly property real r: height / 2

    // появление: из точки в центре острова — с отскоком
    scale: shown ? 1 : 0.3
    Behavior on scale { Anim { kind: "spatial" } }

    property real t: 0
    FrameAnimation { running: orb.visible && orb.shown; onTriggered: orb.t += frameTime }
    property real voice: st === "listening" ? Math.min(1, level * 2.4)
                       : talking ? 0.55 + 0.25 * Math.abs(Math.sin(t * 5.1)) + 0.15 * Math.abs(Math.sin(t * 8.3)) : 0.35
    Behavior on voice { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    // свет — пятна, потом размытие и обрезка по форме
    Item {
        id: light
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle { anchors.fill: parent; color: orb.error ? "#3a1012" : "#06080d" }
        Repeater {
            // listening: белое и голубое у дна; speaking: синий, фиолетовый, розовый вдоль дна
            model: [{ c: "#4F8BFF", ph: 0.0, sp: 1.1, w: 0.95 }, { c: "#8E6BD6", ph: 2.2, sp: 0.8, w: 0.7 },
                    { c: "#D46A8C", ph: 4.1, sp: 1.3, w: 0.6 }, { c: "#BFD6FF", ph: 1.0, sp: 0.6, w: 0.75 }]
            Rectangle {
                required property var modelData
                required property int index
                readonly property bool white: index === 3
                // слушает — светят голубой и белый, говорит — все, думает — все по кругу
                opacity: orb.error ? 0 : orb.talking || orb.swirl ? (white ? 0.35 : 0.95) : (index === 0 || white ? 0.95 : 0)
                Behavior on opacity { Anim { kind: "effects" } }
                width: orb.width * modelData.w * (orb.talking ? 1.1 : 0.9 + orb.voice * 0.4)
                height: width * (orb.talking ? 0.55 : 0.8)
                radius: height / 2
                color: modelData.c
                x: orb.swirl ? orb.width / 2 - width / 2 + Math.cos(orb.t * 1.6 + modelData.ph) * orb.width * 0.28
                   : orb.width / 2 - width / 2 + Math.sin(orb.t * modelData.sp + modelData.ph) * orb.width * (orb.talking ? 0.32 : 0.08)
                // свет у дна: громче — выше; думает — по кругу
                y: orb.swirl ? orb.height / 2 - height / 2 + Math.sin(orb.t * 1.6 + modelData.ph) * orb.height * 0.28
                   : orb.height - height * (orb.talking ? 0.55 + orb.voice * 0.25 : 0.45 + orb.voice * 0.4)
                     + Math.cos(orb.t * modelData.sp * 1.3 + modelData.ph) * 2.5
            }
        }
    }
    Item {
        id: shape
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle { anchors.fill: parent; radius: orb.r; color: "black" }
    }
    MultiEffect {
        anchors.fill: parent
        source: light
        autoPaddingEnabled: false        // иначе маска растягивается на поля под размытие и свет вылезает за форму
        blurEnabled: true
        blur: 1
        blurMax: 40
        maskEnabled: true
        maskSource: shape
        opacity: 0.9            // стекло острова просвечивает
    }
    // стеклянный блик сверху и тонкий край
    Rectangle {
        anchors.fill: parent
        radius: orb.r
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.14)
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.13) }
            GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.0) }
        }
    }
}
