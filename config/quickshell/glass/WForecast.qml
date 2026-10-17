import QtQuick
import QtQuick.Shapes

// Прогноз по часам плавной кривой температуры (как в погоде Pixel): над точками — градусы,
// под ними — значки и часы. Сколько часов видно — от ширины; в три ряда снизу ещё и дни недели.
Item {
    id: root
    property date now: new Date()
    property string wid: ""
    property var cfg: ({})

    readonly property bool tall: height >= 300
    readonly property int n: Math.max(4, Math.min(12, Math.floor((width - 40) / 62)))
    readonly property int step: width >= 700 ? 1 : 2                     // узко — через час
    readonly property var pts: {
        const out = [];
        for (let i = 0; i < Weather.hours.length && out.length < n; i += step) out.push(Weather.hours[i]);
        return out;
    }
    readonly property real tMin: pts.length ? Math.min(...pts.map(p => p.temp)) : 0
    readonly property real tMax: pts.length ? Math.max(...pts.map(p => p.temp)) : 1

    WidgetSurface { id: ws; cfg: root.cfg; anchors.fill: parent; tone: "tertiary" }

    Row {
        id: head
        anchors { left: parent.left; top: parent.top; leftMargin: 22; topMargin: 16 }
        spacing: 8
        Icon { anchors.verticalCenter: parent.verticalCenter; name: Weather.ready ? Weather.icon(Weather.code, Weather.isDay) : "cloud_off"; size: 22; fill: 1; color: ws.accent }
        Label { anchors.verticalCenter: parent.verticalCenter; text: Weather.ready ? Math.round(Weather.temp) + "° · " + Weather.describe(Weather.code) : I18n.t("Нет данных", "No data")
                size: 15; weight: 700; color: ws.fg; elide: Text.ElideNone }
    }
    Label {
        anchors { right: parent.right; rightMargin: 22; verticalCenter: head.verticalCenter }
        visible: Weather.ready && root.width >= 380
        text: "↑" + Math.round(Weather.tMax) + "°  ↓" + Math.round(Weather.tMin) + "°"
        size: 13; weight: 600; color: ws.fgDim; elide: Text.ElideNone
    }

    // ── кривая
    Item {
        id: chart
        visible: root.pts.length > 1
        anchors { left: parent.left; right: parent.right; top: head.bottom; leftMargin: 20; rightMargin: 20; topMargin: 6 }
        height: root.tall ? root.height - head.height - 140 : root.height - head.height - 28
        readonly property real colW: width / root.pts.length
        readonly property real yTop: 26
        readonly property real yBot: height - 52
        function px(i) { return colW * (i + 0.5); }
        function py(t) { return root.tMax - root.tMin < 0.5 ? (yTop + yBot) / 2 : yBot - (t - root.tMin) / (root.tMax - root.tMin) * (yBot - yTop); }
        // Catmull-Rom → гладкая ломаная
        readonly property var curve: {
            const p = root.pts.map((q, i) => Qt.point(px(i), py(q.temp)));
            const out = [];
            if (p.length < 2) return out;
            for (let i = 0; i < p.length - 1; i++) {
                const p0 = p[Math.max(0, i - 1)], p1 = p[i], p2 = p[i + 1], p3 = p[Math.min(p.length - 1, i + 2)];
                for (let k = 0; k < 12; k++) {
                    const t = k / 12, t2 = t * t, t3 = t2 * t;
                    out.push(Qt.point(
                        0.5 * (2 * p1.x + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3),
                        0.5 * (2 * p1.y + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)));
                }
            }
            out.push(p[p.length - 1]);
            return out;
        }

        // заливка под кривой
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1
                fillGradient: LinearGradient {
                    x1: 0; y1: chart.yTop; x2: 0; y2: chart.yBot + 10
                    GradientStop { position: 0; color: Qt.alpha(ws.accent, 0.32) }
                    GradientStop { position: 1; color: Qt.alpha(ws.accent, 0) }
                }
                PathPolyline { path: chart.curve.length ? chart.curve.concat([Qt.point(chart.px(root.pts.length - 1), chart.yBot + 10), Qt.point(chart.px(0), chart.yBot + 10)]) : [] }
            }
        }
        // сама кривая
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: ws.accent
                strokeWidth: 3
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathPolyline { path: chart.curve }
            }
        }
        Repeater {
            model: root.pts
            Item {
                required property var modelData
                required property int index
                x: chart.px(index) - width / 2
                width: chart.colW; height: chart.height
                readonly property real y0: chart.py(modelData.temp)
                Rectangle {
                    x: parent.width / 2 - 5; y: parent.y0 - 5
                    width: 10; height: 10; radius: 5
                    color: index === 0 ? ws.accent : ws.container
                    border.width: 2.5; border.color: ws.accent
                }
                Label { anchors.horizontalCenter: parent.horizontalCenter; y: parent.y0 - 30
                        text: Math.round(modelData.temp) + "°"; size: 14; weight: 700; color: ws.fg; elide: Text.ElideNone }
                Icon { anchors.horizontalCenter: parent.horizontalCenter; y: chart.yBot + 12
                       name: Weather.icon(modelData.code, modelData.day); size: 20; fill: 1; color: ws.accent }
                Label { anchors.horizontalCenter: parent.horizontalCenter; y: chart.yBot + 34
                        text: index === 0 ? I18n.t("Сейчас", "Now") : modelData.hour; size: 12; weight: 600; color: ws.fgDim; elide: Text.ElideNone }
            }
        }
    }

    // ── по дням (в три ряда)
    Row {
        visible: root.tall && Weather.days.length > 1
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 20; bottomMargin: 18 }
        readonly property int n: Math.max(2, Math.min(7, Math.floor(width / 64)))
        Repeater {
            model: Weather.days.slice(0, parent.n)
            Rectangle {
                required property var modelData
                required property int index
                width: parent.width / parent.n - 6
                height: 100; radius: 22
                color: index === 0 ? Qt.alpha(ws.accent, 0.18) : ws.chip
                Column {
                    anchors.centerIn: parent
                    spacing: 4
                    Label { anchors.horizontalCenter: parent.horizontalCenter
                            text: index === 0 ? I18n.t("Сег.", "Today") : I18n.locale.toString(modelData.date, "ddd")
                            size: 12; weight: 650; color: index === 0 ? ws.accent : ws.fgDim; elide: Text.ElideNone }
                    Icon { anchors.horizontalCenter: parent.horizontalCenter; name: Weather.icon(modelData.code, true); size: 24; fill: 1; color: ws.accent }
                    Label { anchors.horizontalCenter: parent.horizontalCenter
                            text: Math.round(modelData.max) + "° " + Math.round(modelData.min) + "°"; size: 13; weight: 650; color: ws.fg; elide: Text.ElideNone }
                }
            }
        }
    }

    Label {
        anchors.centerIn: parent
        visible: root.pts.length < 2
        text: I18n.t("Прогноз загружается…", "Loading forecast…"); size: 14; color: ws.fgDim; elide: Text.ElideNone
    }
}
