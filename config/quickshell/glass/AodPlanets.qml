import QtQuick
import QtQuick.Shapes

// «Планеты» для AOD: час написан в «солнце» по центру, минуты — планета на внешней орбите
// (стоит там, где была бы минутная стрелка, и несёт число минут). Маленькая луна на
// внутренней орбите показывает час, как часовая стрелка.
Column {
    id: pl

    required property var clock          // AodClock: hh, mm, now, date, k, p, at(), fade()
    readonly property real k: clock.k

    spacing: 30 * k

    Item {
        id: sys
        readonly property real d: 444 * pl.k
        readonly property real rOut: 176 * pl.k
        readonly property real rIn: 110 * pl.k
        // углы в градусах от «12 часов» по часовой стрелке
        property real minDeg: pl.clock.now.getMinutes() * 6
        property real hourDeg: ((pl.clock.now.getHours() % 12) + pl.clock.now.getMinutes() / 60) * 30
        Behavior on minDeg {
            enabled: pl.clock.p >= 1
            RotationAnimation { direction: RotationAnimation.Clockwise; duration: 900; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        }
        function px(deg, r) { return d / 2 + r * Math.sin(deg * Math.PI / 180); }
        function py(deg, r) { return d / 2 - r * Math.cos(deg * Math.PI / 180); }

        anchors.horizontalCenter: parent.horizontalCenter
        width: d; height: d

        // орбиты и пройденная часть часа
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            opacity: pl.clock.fade(0.1, 0.4)
            ShapePath {
                fillColor: "transparent"; strokeColor: Qt.alpha(pl.clock.cFg, 0.13); strokeWidth: 3 * pl.k
                PathAngleArc { centerX: sys.d / 2; centerY: sys.d / 2; radiusX: sys.rOut; radiusY: sys.rOut; startAngle: 0; sweepAngle: 360 }
            }
            ShapePath {
                fillColor: "transparent"; strokeColor: Qt.alpha(pl.clock.cFg, 0.09); strokeWidth: 3 * pl.k
                PathAngleArc { centerX: sys.d / 2; centerY: sys.d / 2; radiusX: sys.rIn; radiusY: sys.rIn; startAngle: 0; sweepAngle: 360 }
            }
            ShapePath {
                fillColor: "transparent"; strokeColor: Qt.alpha(pl.clock.cPrimary, 0.55); strokeWidth: 5 * pl.k
                capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: sys.d / 2; centerY: sys.d / 2; radiusX: sys.rOut; radiusY: sys.rOut; startAngle: -90; sweepAngle: sys.minDeg % 360 }
            }
        }

        // солнце: час
        AodShape {
            anchors.centerIn: parent
            width: 150 * pl.k; height: width
            kind: "cookie"; lobes: 12
            color: Theme.primaryContainer
            scale: pl.clock.at(0.02, 0.6)
            rotation: sys.minDeg / 12
        }
        Row {
            anchors.centerIn: parent
            AodDigit { ch: pl.clock.hh[0]; size: 66 * pl.k; weight: 680; color: Theme.primaryContainerFg; appear: pl.clock.at(0.12, 0.5) }
            AodDigit { ch: pl.clock.hh[1]; size: 66 * pl.k; weight: 680; color: Theme.primaryContainerFg; appear: pl.clock.at(0.17, 0.5) }
        }

        // луна: где сейчас час
        Rectangle {
            width: 26 * pl.k; height: width; radius: width / 2
            x: sys.px(sys.hourDeg, sys.rIn) - width / 2
            y: sys.py(sys.hourDeg, sys.rIn) - height / 2
            color: pl.clock.cTertiary
            scale: pl.clock.at(0.3, 0.5)
            Behavior on color { ColorAnimation { duration: 300 } }
        }

        // планета: минуты
        Item {
            width: 88 * pl.k; height: width
            x: sys.px(sys.minDeg, sys.rOut) - width / 2
            y: sys.py(sys.minDeg, sys.rOut) - height / 2
            scale: pl.clock.at(0.22, 0.55)
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: pl.clock.cPrimary
                Behavior on color { ColorAnimation { duration: 300 } }
            }
            Row {
                anchors.centerIn: parent
                AodDigit { ch: pl.clock.mm[0]; size: 38 * pl.k; weight: 720; color: Theme.primaryFg }
                AodDigit { ch: pl.clock.mm[1]; size: 38 * pl.k; weight: 720; color: Theme.primaryFg }
            }
        }
    }
    Label {
        visible: pl.clock.showDate
        anchors.horizontalCenter: parent.horizontalCenter
        text: pl.clock.date
        size: Math.max(8, 26 * pl.k); weight: 550
        color: pl.clock.dateColor
        opacity: pl.clock.fade(0.5, 0.3)
        elide: Text.ElideNone
    }
}
