import QtQuick
import QtQuick.Shapes

// Солнце: дуга дня от восхода до заката и солнце на ней сейчас; ночью — луна и сколько до восхода.
// В один ряд — только ближайшее событие. Считается на месте (Sun.qml), без сети.
Item {
    id: root
    property string wid: ""
    property var cfg: ({})
    property date now: new Date()

    readonly property var t: Sun.times(now)
    readonly property real h: now.getHours() + now.getMinutes() / 60
    readonly property bool day: h >= t[0] && h < t[1]
    readonly property real frac: Math.max(0, Math.min(1, (h - t[0]) / (t[1] - t[0])))
    readonly property bool row: height < 150
    // до ближайшего события
    readonly property real until: day ? t[1] - h : (h < t[0] ? t[0] - h : t[0] + 24 - h)
    function dur(x) {
        const m = Math.round(x * 60), hh = Math.floor(m / 60), mm = m % 60;
        return hh > 0 ? hh + I18n.t(" ч ", "h ") + mm + I18n.t(" мин", "m") : mm + I18n.t(" мин", " min");
    }

    WidgetSurface { id: ws; cfg: root.cfg; anchors.fill: parent; tone: "tertiary"; radius: Math.min(44, root.height / 2) }

    // ── в один ряд
    Row {
        visible: root.row
        anchors { left: parent.left; leftMargin: 22; verticalCenter: parent.verticalCenter }
        spacing: 12
        Icon { anchors.verticalCenter: parent.verticalCenter; name: root.day ? "wb_twilight" : "wb_sunny"; size: 34; fill: 1; color: ws.accent }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            Label { text: (root.day ? I18n.t("Закат ", "Sunset ") + Sun.hm(root.t[1]) : I18n.t("Восход ", "Sunrise ") + Sun.hm(root.t[0])); size: 17; weight: 700; color: ws.fg; elide: Text.ElideNone }
            Label { text: I18n.t("через ", "in ") + root.dur(root.until); size: 13; weight: 550; color: ws.fgDim; elide: Text.ElideNone }
        }
    }

    // ── дуга
    Item {
        id: arc
        visible: !root.row
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 22; topMargin: 26 }
        height: root.height - 92
        readonly property real cx: width / 2
        readonly property real by: height                     // линия горизонта
        readonly property real rx: width / 2
        readonly property real ry: Math.min(height - 8, width / 2)
        function pt(f) { const a = Math.PI * (1 - f); return Qt.point(cx + rx * Math.cos(a), by - ry * Math.sin(a)); }

        // путь солнца (пунктир) и пройденная часть
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Qt.alpha(ws.fg, 0.28); strokeWidth: 2.5; fillColor: "transparent"
                strokeStyle: ShapePath.DashLine; dashPattern: [2, 3]
                PathAngleArc { centerX: arc.cx; centerY: arc.by; radiusX: arc.rx; radiusY: arc.ry; startAngle: 180; sweepAngle: 180 }
            }
            ShapePath {
                strokeColor: ws.accent; strokeWidth: 4; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: arc.cx; centerY: arc.by; radiusX: arc.rx; radiusY: arc.ry; startAngle: 180; sweepAngle: 180 * (root.day ? root.frac : 0) }
            }
        }
        Rectangle { x: -6; y: arc.by - 1; width: arc.width + 12; height: 2; radius: 1; color: Qt.alpha(ws.fg, 0.35) }
        // солнце или луна
        Item {
            readonly property point p: root.day ? arc.pt(root.frac) : Qt.point(arc.cx, arc.by - arc.ry * 0.55)
            x: p.x - width / 2; y: p.y - height / 2
            width: 34; height: 34
            Rectangle { anchors.centerIn: parent; width: 54; height: 54; radius: 27; color: Qt.alpha(ws.accent, root.day ? 0.22 : 0); }
            Rectangle { anchors.centerIn: parent; width: 26; height: 26; radius: 13; color: ws.accent; visible: root.day }
            Icon { anchors.centerIn: parent; visible: !root.day; name: "bedtime"; size: 30; fill: 1; color: ws.accent }
        }
    }
    Item {
        visible: !root.row
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 20; bottomMargin: 16 }
        height: 40
        Column {
            anchors.left: parent.left
            Label { text: Sun.hm(root.t[0]); size: 15; weight: 700; color: ws.fg; elide: Text.ElideNone }
            Label { text: I18n.t("восход", "sunrise"); size: 11; weight: 550; color: ws.fgDim; elide: Text.ElideNone }
        }
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.width >= 330
            Label { anchors.horizontalCenter: parent.horizontalCenter; text: root.dur(root.until); size: 13; weight: 700; color: ws.accent; elide: Text.ElideNone }
            Label { anchors.horizontalCenter: parent.horizontalCenter; text: root.day ? I18n.t("до заката", "to sunset") : I18n.t("до восхода", "to sunrise"); size: 11; weight: 550; color: ws.fgDim; elide: Text.ElideNone }
        }
        Column {
            anchors.right: parent.right
            Label { anchors.right: parent.right; text: Sun.hm(root.t[1]); size: 15; weight: 700; color: ws.fg; elide: Text.ElideNone }
            Label { anchors.right: parent.right; text: I18n.t("закат", "sunset"); size: 11; weight: 550; color: ws.fgDim; elide: Text.ElideNone }
        }
    }
}
