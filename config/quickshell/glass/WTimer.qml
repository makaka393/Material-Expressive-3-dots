import QtQuick
import QtQuick.Shapes

// Таймер (тот же, что в острове и лаунчере — Countdown). Не идёт — кнопки на 1, 3, 5, 10, 25 минут;
// идёт — кольцо с остатком, «+1 мин» и стоп. В один ряд — полоска вместо кольца.
Item {
    id: root
    property date now: new Date()
    property string wid: ""
    property var cfg: ({})

    readonly property bool row: height < 150
    readonly property var presets: [1, 3, 5, 10, 15, 25]
    readonly property int nPresets: root.row ? Math.max(2, Math.min(6, Math.floor((width - 90) / 62))) : (width >= 400 ? 6 : 4)

    WidgetSurface { id: ws; cfg: root.cfg; anchors.fill: parent; tone: "tertiary"; radius: Math.min(44, root.height / 2) }

    property real frac: Countdown.frac
    Behavior on frac { NumberAnimation { duration: 500 } }

    // ── не идёт: быстрый старт
    Item {
        anchors.fill: parent
        visible: !Countdown.running
        Row {
            visible: !root.row
            anchors { left: parent.left; top: parent.top; leftMargin: 20; topMargin: 18 }
            spacing: 8
            Icon { anchors.verticalCenter: parent.verticalCenter; name: "timer"; size: 22; fill: 1; color: ws.accent }
            Label { anchors.verticalCenter: parent.verticalCenter; text: I18n.t("Таймер", "Timer"); size: 15; weight: 700; color: ws.fg; elide: Text.ElideNone }
        }
        Icon { visible: root.row; anchors { left: parent.left; leftMargin: 22; verticalCenter: parent.verticalCenter }
               name: "timer"; size: 28; fill: 1; color: ws.accent }
        Grid {
            anchors { horizontalCenter: root.row ? undefined : parent.horizontalCenter; bottom: root.row ? undefined : parent.bottom; bottomMargin: 18
                      right: root.row ? parent.right : undefined; rightMargin: 14; verticalCenter: root.row ? parent.verticalCenter : undefined }
            columns: root.row ? root.nPresets : (root.width >= 400 ? 3 : 2)
            spacing: 8
            Repeater {
                model: root.presets.slice(0, root.nPresets)
                Rectangle {
                    required property int modelData
                    width: root.row ? 56 : Math.min(84, (root.width - 40 - 8 * (parent.columns - 1)) / parent.columns)
                    height: root.row ? 56 : Math.min(56, (root.height - 70 - 8) / Math.ceil(root.nPresets / parent.columns))
                    radius: pm.pressed ? 14 : height / 2
                    color: pm.containsMouse ? Qt.alpha(ws.accent, 0.25) : ws.chip
                    Behavior on radius { Anim { kind: "fast" } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Label { anchors.centerIn: parent; text: modelData + I18n.t(" м", "m"); size: 15; weight: 700; color: ws.fg; elide: Text.ElideNone }
                    MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Countdown.start(modelData * 60, "") }
                }
            }
        }
    }

    // ── идёт: кольцо
    Item {
        anchors.fill: parent
        visible: Countdown.running && !root.row
        Item {
            id: ring
            readonly property real d: Math.min(root.height - 36, root.width * 0.62)
            readonly property real sw: Math.max(8, d * 0.08)
            width: d; height: d
            anchors { verticalCenter: parent.verticalCenter; horizontalCenter: root.width >= 400 ? undefined : parent.horizontalCenter
                      left: root.width >= 400 ? parent.left : undefined; leftMargin: 22 }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: ws.chip; strokeWidth: ring.sw; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: ring.d / 2; centerY: ring.d / 2; radiusX: (ring.d - ring.sw) / 2; radiusY: radiusX; startAngle: -90; sweepAngle: 360 }
                }
                ShapePath {
                    strokeColor: ws.accent; strokeWidth: ring.sw; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: ring.d / 2; centerY: ring.d / 2; radiusX: (ring.d - ring.sw) / 2; radiusY: radiusX; startAngle: -90; sweepAngle: Math.max(0.5, 360 * root.frac) }
                }
            }
            Column {
                anchors.centerIn: parent
                Label { anchors.horizontalCenter: parent.horizontalCenter; text: Countdown.fmt(Countdown.left); size: Math.round(ring.d * 0.2); weight: 700; color: ws.fg; elide: Text.ElideNone }
                Label { anchors.horizontalCenter: parent.horizontalCenter; visible: Countdown.label !== "" && ring.d > 120; width: ring.d * 0.7; horizontalAlignment: Text.AlignHCenter
                        text: Countdown.label; size: 12; weight: 600; color: ws.fgDim }
            }
        }
        Column {
            anchors { verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: root.width >= 400 ? 26 : 10 }
            spacing: 8
            visible: root.width >= 400
            IconButton { icon: "add"; size: 52; iconSize: 26; bg: ws.chip; color: ws.fg; onClicked: Countdown.add(60) }
            IconButton { icon: "stop"; size: 52; iconSize: 26; bg: ws.fill; color: ws.fillInk; onClicked: Countdown.stop() }
        }
        // узко — стоп по клику по кольцу
        MouseArea { anchors.fill: ring; visible: root.width < 400; cursorShape: Qt.PointingHandCursor; onClicked: Countdown.stop() }
    }

    // ── идёт, в один ряд: полоска
    Item {
        anchors.fill: parent
        visible: Countdown.running && root.row
        Label { id: timeLabel; anchors { left: parent.left; leftMargin: 24; verticalCenter: parent.verticalCenter }
                text: Countdown.fmt(Countdown.left); size: 26; weight: 700; color: ws.fg; elide: Text.ElideNone }
        Rectangle {
            anchors { left: timeLabel.right; leftMargin: 16; right: rowBtns.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            height: 10; radius: 5; color: ws.chip
            Rectangle { width: parent.width * root.frac; height: parent.height; radius: 5; color: ws.accent }
        }
        Row {
            id: rowBtns
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 4
            IconButton { visible: root.width >= 330; icon: "add"; size: 48; iconSize: 24; color: ws.fg; onClicked: Countdown.add(60) }
            IconButton { icon: "stop"; size: 48; iconSize: 24; bg: ws.fill; color: ws.fillInk; onClicked: Countdown.stop() }
        }
    }
}
