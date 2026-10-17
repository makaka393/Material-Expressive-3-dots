import QtQuick

// Затемнение под окнами оболочки (лаунчер, настройки, шпаргалка): мягкая виньетка и
// живая сетка мелких точек разного размера — проявляется волной из origin и медленно «дышит».
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

    // время для «дыхания» точек — идёт только пока затемнение видно
    property real time: 0
    NumberAnimation on time {
        from: 0; to: 3600; duration: 3600000
        loops: Animation.Infinite
        running: root.visible
    }

    opacity: shown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: root.shown ? 160 : 220; easing.type: Easing.OutCubic } }

    ShaderEffect {
        anchors.fill: parent
        fragmentShader: "shaders/scrim.frag.qsb"
        property vector2d res: Qt.vector2d(width, height)
        property vector2d origin: Qt.vector2d(root.origin.x, root.origin.y)
        property real progress: root.progress
        property real time: root.time
        property real dim: root.dim
        property real cell: 15
        property real dots: 0.85
        // светлые с оттенком темы: тёмный primary на тёмном затемнении не видно
        property color tint: Qt.alpha(Qt.tint(Theme.fg, Qt.alpha(Theme.primary, 0.35)), 0.8)
        property color shade: Theme.surfaceLowest
    }

    MouseArea { anchors.fill: parent; onClicked: root.clicked() }
}
