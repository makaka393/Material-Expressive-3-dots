import QtQuick

// Затемнение под окнами оболочки (лаунчер, настройки, шпаргалка): мягкая виньетка и
// точечная сетка в духе Pixel — точки проявляются волной из origin, когда окно открывается.
// Клик по затемнению — clicked(). Шейдер: shaders/scrim.frag (собран в .qsb).
//
// Альфа нигде не выше ~0.35: у этих слоёв Hyprland размывает только то, что плотнее
// ignore_alpha (0.4 в hyprland.lua), — иначе под затемнением появился бы размытый «квадрат».
Item {
    id: root

    property bool shown: false
    property point origin: Qt.point(width / 2, height * 0.25)
    property real dim: 0.3
    signal clicked()

    property real progress: 0
    NumberAnimation on progress {
        id: reveal
        from: 0; to: 1; duration: 900
        easing.type: Easing.OutCubic
        running: false
    }
    onShownChanged: if (shown) reveal.restart()

    opacity: shown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: root.shown ? 160 : 220; easing.type: Easing.OutCubic } }

    ShaderEffect {
        anchors.fill: parent
        fragmentShader: "shaders/scrim.frag.qsb"
        property vector2d res: Qt.vector2d(width, height)
        property vector2d origin: Qt.vector2d(root.origin.x, root.origin.y)
        property real progress: root.progress
        property real dim: root.dim
        property real cell: 18
        property real dots: 0.85
        property color tint: Qt.alpha(Theme.primary, 0.7)
        property color shade: Theme.surfaceLowest
    }

    MouseArea { anchors.fill: parent; onClicked: root.clicked() }
}
