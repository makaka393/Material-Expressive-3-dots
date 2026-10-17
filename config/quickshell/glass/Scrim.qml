import QtQuick

// Затемнение под окнами оболочки (лаунчер, настройки, шпаргалка). Стиль — в настройках
// (Оформление → «Фон под окнами»):
//   dots — светящиеся точки без сетки: плывут, мерцают, проявляются волной из origin;
//   dark — просто ровное затемнение.
// Клик по затемнению — clicked(). Шейдер: shaders/scrim.frag (собран в .qsb).
//
// Точки запечены заранее в бесшовную текстуру (shaders/dots.png, make-dots.py), шейдеру остаются
// две выборки из неё на пиксель. Время идёт ~30 раз в секунду, а не с частотой монитора: на 144 Гц
// это в несколько раз меньше перерисовок, а медленное движение выглядит так же плавно.
// Альфа нигде не выше ~0.39: у этих слоёв Hyprland размывает только то, что плотнее
// ignore_alpha (0.4 в hyprland.lua), — иначе под затемнением появился бы размытый «квадрат».
Item {
    id: root

    property bool shown: false
    property point origin: Qt.point(width / 2, height * 0.25)
    property real dim: 0.3
    property string style: Config.scrim
    property real zoom: 1150                 // размер тайла точек на экране (меньше — мельче и гуще)
    signal clicked()

    readonly property bool dotted: style !== "dark"

    property real progress: 0
    NumberAnimation on progress {
        id: reveal
        from: 0; to: 1; duration: 1100
        easing.type: Easing.OutCubic
        running: false
    }
    // каждый раз с нового места «фильма» — узор не повторяется от открытия к открытию
    onShownChanged: if (shown) { t0 = Date.now() - Math.random() * 600000; reveal.restart(); }
    function replay() { reveal.restart(); }

    property double t0: Date.now()
    property real time: 0
    Timer {
        interval: 33
        repeat: true
        running: root.visible && root.dotted
        onTriggered: root.time = (Date.now() - root.t0) / 1000 % 3600
    }

    opacity: shown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: root.shown ? 160 : 220; easing.type: Easing.OutCubic } }

    // светлые оттенки цветов темы — тёмный primary на тёмном затемнении не светился бы
    function glowOf(c) { return Qt.hsla(c.hslHue, Math.max(0.45, c.hslSaturation), 0.78, 1); }

    // шейдер и текстура живут, только пока затемнение видно
    Loader {
        anchors.fill: parent
        active: root.visible
        sourceComponent: Item {
            Image {
                id: tileImg
                width: 1024; height: 1024
                source: "shaders/dots.png"
                smooth: true
                onStatusChanged: if (status === Image.Ready) tileTex.scheduleUpdate()
            }
            ShaderEffectSource {
                id: tileTex
                sourceItem: tileImg
                hideSource: true
                live: false
                mipmap: true
                smooth: true
                wrapMode: ShaderEffectSource.Repeat
                width: 1; height: 1
                visible: false
            }
            ShaderEffect {
                anchors.fill: parent
                fragmentShader: "shaders/scrim.frag.qsb"
                property vector2d res: Qt.vector2d(width, height)
                property vector2d origin: Qt.vector2d(root.origin.x, root.origin.y)
                property real progress: root.progress
                property real time: root.time
                property real dim: root.dotted ? root.dim : Math.min(0.36, root.dim * 1.25)
                property real flatness: root.dotted ? 0 : 0.6
                property real dots: root.dotted ? 1 : 0
                property real zoom: root.zoom
                property color tintA: root.glowOf(Theme.primary)
                property color tintB: root.glowOf(Theme.tertiary)
                property color shade: Theme.surfaceLowest
                property var tile: tileTex
            }
        }
    }

    MouseArea { anchors.fill: parent; onClicked: root.clicked() }
}
