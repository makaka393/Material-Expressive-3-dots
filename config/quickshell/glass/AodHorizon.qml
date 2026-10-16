import QtQuick
import QtQuick.Shapes

// «Горизонт» для AOD: дуга над линией горизонта — путь солнца от восхода до заката, ночью по ней
// идёт луна. Светило стоит там, где сейчас день (или ночь); под горизонтом — время и
// ближайшие восход/закат. Восход и закат считаются по Theme.lat / Theme.lon, без сети.
Column {
    id: hz

    required property var clock          // AodClock: hh, mm, now, date, k, p, at(), fade()
    readonly property real k: clock.k

    readonly property var sun: Sun.times(clock.now)
    readonly property real hourNow: clock.now.getHours() + clock.now.getMinutes() / 60
    readonly property bool day: hourNow >= sun[0] && hourNow < sun[1]
    // 0…1 — какая часть дня (или ночи) прошла
    readonly property real t: day ? (hourNow - sun[0]) / (sun[1] - sun[0])
                                  : ((hourNow - sun[1] + 24) % 24) / (24 - (sun[1] - sun[0]))
    function hm(h) {
        const m = Math.round(((h % 24) + 24) % 24 * 60);
        return clock.pad(Math.floor(m / 60) % 24) + ":" + clock.pad(m % 60);
    }

    spacing: 20 * k

    Item {
        id: sky
        readonly property real w: 600 * hz.k
        readonly property real rx: 250 * hz.k
        readonly property real ry: 190 * hz.k
        readonly property real baseY: 236 * hz.k
        property real tt: hz.t
        Behavior on tt { enabled: hz.clock.p >= 1; NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
        readonly property real grow: Math.min(1, hz.clock.at(0.1, 0.8))
        readonly property real ang: Math.PI * (1 - tt * grow)              // π — слева, 0 — справа

        anchors.horizontalCenter: parent.horizontalCenter
        width: w; height: 250 * hz.k

        // звёзды — только ночью
        Repeater {
            model: [[0.16, 0.30], [0.27, 0.12], [0.41, 0.36], [0.52, 0.08], [0.63, 0.30], [0.74, 0.14], [0.86, 0.34], [0.35, 0.60], [0.68, 0.58]]
            Rectangle {
                required property var modelData
                required property int index
                visible: !hz.day
                x: modelData[0] * sky.w; y: modelData[1] * sky.baseY
                width: (index % 3 === 0 ? 7 : 4) * hz.k; height: width; radius: width / 2
                color: Theme.fg
                opacity: (index % 3 === 0 ? 0.55 : 0.32) * hz.clock.fade(0.3 + index * 0.03, 0.3)
            }
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            // весь путь — пунктиром
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.alpha(Theme.fg, 0.22)
                strokeWidth: 4 * hz.k
                strokeStyle: ShapePath.DashLine
                dashPattern: [0.1, 3.2]
                capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: sky.w / 2; centerY: sky.baseY; radiusX: sky.rx; radiusY: sky.ry; startAngle: 180; sweepAngle: 180 }
            }
            // пройденная часть
            ShapePath {
                fillColor: "transparent"
                strokeColor: hz.day ? Theme.primary : Theme.tertiary
                strokeWidth: 6 * hz.k
                capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: sky.w / 2; centerY: sky.baseY; radiusX: sky.rx; radiusY: sky.ry
                               startAngle: 180; sweepAngle: Math.max(0.5, 180 * sky.tt * sky.grow) }
            }
            // горизонт
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.alpha(Theme.fg, 0.30)
                strokeWidth: 4 * hz.k
                capStyle: ShapePath.RoundCap
                startX: 14 * hz.k; startY: sky.baseY
                PathLine { x: sky.w - 14 * hz.k; y: sky.baseY }
            }
        }

        // светило
        Item {
            id: body
            width: 76 * hz.k; height: width
            x: sky.w / 2 + sky.rx * Math.cos(sky.ang) - width / 2
            y: sky.baseY - sky.ry * Math.sin(sky.ang) - height / 2
            scale: hz.clock.at(0.2, 0.6)
            Rectangle {                                  // свечение
                anchors.centerIn: parent
                width: parent.width * 1.7; height: width; radius: width / 2
                color: Qt.alpha(hz.day ? Theme.primary : Theme.tertiary, 0.16)
            }
            AodShape {
                anchors.fill: parent
                visible: hz.day
                kind: "cookie"; lobes: 10
                color: Theme.primary
            }
            Icon {
                anchors.centerIn: parent
                visible: !hz.day
                name: "bedtime"; fill: 1
                size: 70 * hz.k
                color: Theme.tertiary
            }
        }
    }

    // под горизонтом: что позади — время — что впереди
    Item {
        anchors.horizontalCenter: parent.horizontalCenter
        width: sky.w; height: timeRow.implicitHeight
        Row {
            id: timeRow
            anchors.horizontalCenter: parent.horizontalCenter
            AodDigit { ch: hz.clock.hh[0]; size: 100 * hz.k; weight: 520; appear: hz.clock.at(0.20, 0.5) }
            AodDigit { ch: hz.clock.hh[1]; size: 100 * hz.k; weight: 520; appear: hz.clock.at(0.25, 0.5) }
            AodDigit { ch: ":"; size: 100 * hz.k; weight: 520; color: hz.day ? Theme.primary : Theme.tertiary; appear: hz.clock.at(0.30, 0.5) }
            AodDigit { ch: hz.clock.mm[0]; size: 100 * hz.k; weight: 520; appear: hz.clock.at(0.35, 0.5) }
            AodDigit { ch: hz.clock.mm[1]; size: 100 * hz.k; weight: 520; appear: hz.clock.at(0.40, 0.5) }
        }
        Column {
            anchors { left: parent.left; leftMargin: 8 * hz.k; verticalCenter: parent.verticalCenter }
            opacity: hz.clock.fade(0.5, 0.3)
            Icon { name: hz.day ? "wb_twilight" : "bedtime"; size: Math.max(8, 26 * hz.k); fill: 1; color: Theme.fgVariant }
            Label { text: hz.hm(hz.day ? hz.sun[0] : hz.sun[1]); size: Math.max(8, 21 * hz.k); weight: 600; color: Theme.fgVariant; elide: Text.ElideNone }
        }
        Column {
            anchors { right: parent.right; rightMargin: 8 * hz.k; verticalCenter: parent.verticalCenter }
            opacity: hz.clock.fade(0.5, 0.3)
            Icon { anchors.right: parent.right; name: hz.day ? "bedtime" : "wb_twilight"; size: Math.max(8, 26 * hz.k); fill: 1; color: Theme.fgVariant }
            Label { text: hz.hm(hz.day ? hz.sun[1] : hz.sun[0]); size: Math.max(8, 21 * hz.k); weight: 600; color: Theme.fgVariant; elide: Text.ElideNone }
        }
    }
    Label {
        visible: hz.clock.showDate
        anchors.horizontalCenter: parent.horizontalCenter
        text: hz.clock.date
        size: Math.max(8, 26 * hz.k); weight: 550
        color: Theme.fgVariant
        opacity: hz.clock.fade(0.5, 0.3)
        elide: Text.ElideNone
    }
}
