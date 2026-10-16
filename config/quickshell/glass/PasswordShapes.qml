import QtQuick
import "shapes/material-shapes.js" as MS

// Пароль фигурами Material 3 Expressive (как в ii от end-4): каждый символ —
// своя фигура (клевер, печенька, солнышко, сердечко…). Появляется пружинкой
// цвета primary и остывает в цвет текста. Пока идёт вход — все фигуры
// волной перетекают в следующие. Библиотека фигур: shapes/ (end-4, Apache-2.0).
Item {
    id: root

    property int count: 0                // сколько символов в пароле
    property real size: 24
    property real gap: 6
    property color color: "white"        // «остывший» цвет
    property color accent: "#a8c7fa"    // цвет только что введённой фигуры
    property color errorColor: "#ffb4ab"
    property bool busy: false            // идёт проверка — фигуры морфятся
    property bool failed: false
    property bool caret: true

    readonly property var getters: [
        MS.getClover4Leaf, MS.getCookie7Sided, MS.getSunny, MS.getPill, MS.getSoftBurst,
        MS.getHeart, MS.getDiamond, MS.getCookie4Sided, MS.getFlower, MS.getClamShell,
        MS.getPentagon, MS.getPuffy, MS.getGem, MS.getCookie9Sided, MS.getArch,
        MS.getCircle, MS.getBun, MS.getSoftBoom, MS.getGhostish, MS.getTriangle
    ]
    property int phase: 0
    property int seed: Math.floor(Math.random() * 1000)

    // фигура для позиции: «случайная», но стабильная, и соседние не повторяются
    function pick(i) {
        const n = getters.length;
        return ((i * 7 + seed) % n + n) % n;
    }

    ListModel { id: chars }
    onCountChanged: sync()
    Component.onCompleted: sync()
    function sync() {
        while (chars.count < count) chars.append({ shape: pick(chars.count) });
        while (chars.count > count) chars.remove(chars.count - 1);
        Qt.callLater(() => view.positionViewAtEnd());
    }
    // каждый новый пароль — новый набор фигур
    onFailedChanged: if (failed) seed = Math.floor(Math.random() * 1000)

    Timer {
        interval: 420; repeat: true; running: root.busy
        onTriggered: root.phase++
        onRunningChanged: if (!running) root.phase = 0
    }

    ListView {
        id: view
        anchors.fill: parent
        orientation: ListView.Horizontal
        interactive: false
        spacing: root.gap
        model: chars
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        // фигуры не обрезаются при «пружинке»
        leftMargin: 4; rightMargin: root.size

        add: Transition {
            ParallelAnimation {
                NumberAnimation { property: "scale"; from: 0.15; to: 1; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.42, 1.67, 0.21, 0.90, 1, 1] }
                NumberAnimation { property: "rotation"; from: -70; to: 0; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.38, 1.21, 0.22, 1.00, 1, 1] }
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 90 }
            }
        }
        remove: Transition {
            ParallelAnimation {
                NumberAnimation { property: "scale"; to: 0.1; duration: 200; easing.type: Easing.InCubic }
                NumberAnimation { property: "rotation"; to: 45; duration: 200 }
                NumberAnimation { property: "opacity"; to: 0; duration: 200 }
            }
        }
        displaced: Transition {
            NumberAnimation { property: "x"; duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.38, 1.21, 0.22, 1.00, 1, 1] }
        }

        delegate: Item {
            id: ch
            required property int index
            required property int shape
            width: root.size
            height: view.height
            property bool fresh: true
            Timer { interval: 450; running: true; onTriggered: ch.fresh = false }

            MorphShape {
                anchors.centerIn: parent
                width: root.size; height: root.size
                // волна: каждая следующая фигура морфится чуть позже соседки
                roundedPolygon: root.getters[(ch.shape + (root.busy ? Math.max(0, root.phase - ch.index % 3) : 0)) % root.getters.length]()
                color: root.failed ? root.errorColor : (ch.fresh || root.busy) ? root.accent : root.color
                Behavior on color { ColorAnimation { duration: 700; easing.type: Easing.OutCubic } }
            }
        }

        // курсор: мигающая «пилюля» после последней фигуры
        footer: Item {
            width: root.size * 0.6
            height: view.height
            Rectangle {
                anchors.centerIn: parent
                width: 3; height: root.size * 0.95; radius: 1.5
                color: root.accent
                visible: root.caret && !root.busy
                SequentialAnimation on opacity {
                    running: root.caret && !root.busy
                    loops: Animation.Infinite
                    NumberAnimation { to: 0; duration: 500; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 500; easing.type: Easing.InOutSine }
                }
            }
        }
    }
}
