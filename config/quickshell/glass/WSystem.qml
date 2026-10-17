import QtQuick
import QtQuick.Shapes

// Нагрузка: процессор, память, видеокарта (если есть nvidia-smi) — кольцами, как в шторке.
// Пока виджет на столе, Sys опрашивает систему раз в 4 секунды.
Item {
    id: root

    Component.onCompleted: Sys.widgets++
    Component.onDestruction: Sys.widgets--

    readonly property var items: [
        { icon: "memory", t: I18n.t("Процессор", "CPU"), v: Sys.cpu, extra: Sys.cpuTemp >= 0 ? Sys.cpuTemp + "°" : "" },
        { icon: "memory_alt", t: I18n.t("Память", "RAM"), v: Sys.mem, extra: Sys.memUsedGb > 0 ? Sys.memUsedGb.toFixed(1) + I18n.t(" ГБ", " GB") : "" }
    ].concat(Sys.gpu >= 0 ? [{ icon: "developer_board", t: I18n.t("Видеокарта", "GPU"), v: Sys.gpu, extra: Sys.gpuTemp >= 0 ? Sys.gpuTemp + "°" : "" }] : [])

    readonly property bool row: height < 150
    readonly property bool roomy: !row && width >= 400
    readonly property bool bars: !row && !roomy

    WidgetSurface { id: ws; anchors.fill: parent; tone: "secondary"; radius: Math.min(44, root.height / 2) }

    // ── квадрат: строки «значок · название · %» с полоской
    Column {
        visible: root.bars
        anchors { fill: parent; margins: 18; topMargin: 20 }
        spacing: 12
        Repeater {
            model: root.bars ? root.items.length : 0
            Item {
                id: bar
                required property int index
                readonly property var modelData: root.items[index]
                width: parent.width
                height: (parent.height - 12 * (root.items.length - 1)) / root.items.length
                property real shown: modelData.v
                Behavior on shown { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
                Icon { id: bIcon; anchors { left: parent.left; top: parent.top } name: bar.modelData.icon; size: 18; fill: 1; color: ws.accent }
                Label { anchors { left: bIcon.right; leftMargin: 6; verticalCenter: bIcon.verticalCenter }
                        text: bar.modelData.t; size: 13; weight: 650; color: ws.fg; elide: Text.ElideNone }
                Label { anchors { right: parent.right; verticalCenter: bIcon.verticalCenter }
                        text: Math.round(bar.modelData.v * 100) + "%"; size: 13; weight: 750; color: ws.fg; elide: Text.ElideNone }
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 10; radius: 5; color: ws.chip
                    Rectangle { width: Math.max(height, parent.width * bar.shown); height: parent.height; radius: 5
                                color: bar.shown > 0.9 ? Theme.error : ws.accent }
                }
            }
        }
    }

    Row {
        visible: !root.bars
        anchors.centerIn: parent
        spacing: root.row ? 10 : 14
        Repeater {
            model: root.bars ? 0 : root.items.length
            Item {
                id: g
                required property int index
                readonly property var modelData: root.items[index]
                readonly property real d: Math.min((root.width - 28 - (root.items.length - 1) * 14) / root.items.length,
                                                   root.row ? root.height - 20 : root.height - (root.roomy ? 70 : 56))
                width: Math.max(d, root.roomy ? 96 : 0); height: root.height - 16
                property real shown: modelData.v
                Behavior on shown { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }

                Item {
                    id: ring
                    width: g.d; height: g.d
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: root.row ? 0 : -(root.roomy ? 18 : 12)
                    readonly property real sw: Math.max(5, g.d * 0.1)
                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeColor: ws.chip; strokeWidth: ring.sw; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                            PathAngleArc { centerX: g.d / 2; centerY: g.d / 2; radiusX: (g.d - ring.sw) / 2; radiusY: radiusX; startAngle: 135; sweepAngle: 270 }
                        }
                        ShapePath {
                            strokeColor: g.shown > 0.9 ? Theme.error : ws.accent; strokeWidth: ring.sw; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                            PathAngleArc { centerX: g.d / 2; centerY: g.d / 2; radiusX: (g.d - ring.sw) / 2; radiusY: radiusX; startAngle: 135; sweepAngle: Math.max(0.5, 270 * g.shown) }
                        }
                    }
                    Label {
                        anchors.centerIn: parent
                        text: Math.round(g.modelData.v * 100) + "%"
                        size: Math.max(11, Math.round(g.d * 0.24)); weight: 700; color: ws.fg; elide: Text.ElideNone
                    }
                    Icon {
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: -2 }
                        visible: g.d >= 60
                        name: g.modelData.icon; size: Math.round(g.d * 0.2); fill: 1; color: ws.accent
                    }
                }
                Column {
                    visible: !root.row
                    anchors { top: ring.bottom; topMargin: 6; horizontalCenter: parent.horizontalCenter }
                    Label { anchors.horizontalCenter: parent.horizontalCenter; text: g.modelData.t; size: 12; weight: 650; color: ws.fg; elide: Text.ElideNone }
                    Label { anchors.horizontalCenter: parent.horizontalCenter; visible: root.roomy && g.modelData.extra !== ""; text: g.modelData.extra; size: 12; weight: 550; color: ws.fgDim; elide: Text.ElideNone }
                }
            }
        }
    }
}
