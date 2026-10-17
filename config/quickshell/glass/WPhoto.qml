import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io

// Фото в фигуре Material 3 (как виджет «Фото» на Pixel): картинки из папки с обоями, раз в
// 15 минут следующая с плавной сменой. Клик или «Следующее фото» — сразу следующая;
// «Другая форма» — печенька, клевер, скруглённый квадрат, шестиугольник, круг.
Item {
    id: root
    property date now: new Date()
    property string wid: ""
    property var cfg: ({})

    readonly property var shapes: ["squircle", "cookie", "clover", "hex", "circle"]
    readonly property string shape: shapes.indexOf(cfg.shape) >= 0 ? cfg.shape : "squircle"
    property var files: []
    readonly property int idx: files.length ? ((cfg.i | 0) % files.length + files.length) % files.length : 0
    readonly property string src: files.length ? "file://" + files[idx] : ""

    function next() { if (files.length > 1) Widgets.setExtra(wid, "i", (idx + 1) % files.length); }
    Connections {
        target: Widgets
        function onCommand(wid, name) {
            if (wid !== root.wid) return;
            if (name === "next") root.next();
            else if (name === "shape") Widgets.setExtra(root.wid, "shape", root.shapes[(root.shapes.indexOf(root.shape) + 1) % root.shapes.length]);
        }
    }
    Timer { interval: 15 * 60 * 1000; repeat: true; running: root.files.length > 1; onTriggered: root.next() }

    // только картинки: GIF и видео из папки обоев не берём
    Process {
        running: true
        command: ["find", "-L", Theme.wallpaperDir, "-maxdepth", "1", "-type", "f", "(", "-iname", "*.jpg", "-o", "-iname", "*.jpeg",
                  "-o", "-iname", "*.png", "-o", "-iname", "*.webp", ")"]
        stdout: StdioCollector { onStreamFinished: root.files = text.split("\n").filter(x => x !== "").sort() }
    }

    WidgetSurface { id: ws; cfg: root.cfg; anchors.fill: parent; tone: "secondary"; defaultBg: "none" }

    // две картинки по очереди: новая грузится в заднюю и, когда готова, проявляется поверх
    Item {
        id: pics
        anchors.fill: parent
        visible: false
        layer.enabled: true
        property int front: 0                  // 0 — видна a, 1 — b
        property url want: ""                  // url, а не строка: пробелы в имени файла кодируются одинаково
        function show(s) {
            if (s === "") return;
            want = s;
            (front === 0 ? b : a).source = s;
        }
        Image {
            id: a
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: Math.max(root.width, root.height) * 1.2
            asynchronous: true
            opacity: pics.front === 0 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 900; easing.type: Easing.InOutCubic } }
            onStatusChanged: if (status === Image.Ready && String(source) === String(pics.want)) pics.front = 0
        }
        Image {
            id: b
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: Math.max(root.width, root.height) * 1.2
            asynchronous: true
            opacity: pics.front === 1 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 900; easing.type: Easing.InOutCubic } }
            onStatusChanged: if (status === Image.Ready && String(source) === String(pics.want)) pics.front = 1
        }
    }
    onSrcChanged: pics.show(src)
    Component.onCompleted: pics.show(src)

    // маска — фигура M3
    AodShape {
        id: mask
        anchors.fill: parent
        kind: root.shape
        lobes: 10
        color: "white"
        visible: false
        layer.enabled: true
    }
    MultiEffect {
        anchors.fill: parent
        source: pics
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1
        scale: pm.pressed ? 0.97 : 1
        Behavior on scale { Anim { kind: "fast" } }
    }
    // пока картинок нет — пустая фигура в цвет темы
    AodShape {
        anchors.fill: parent
        visible: root.files.length === 0
        kind: root.shape
        lobes: 10
        color: Qt.alpha(ws.container, Theme.m3 ? Math.max(0.02, Theme.m3Opacity) : Theme.glass.a)
        Icon { anchors.centerIn: parent; name: "photo"; size: 44; fill: 1; color: ws.accent }
    }
    MouseArea { id: pm; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.next() }
}
