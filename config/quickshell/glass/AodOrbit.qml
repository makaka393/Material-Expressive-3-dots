import QtQuick
import QtQuick.Shapes

// «Орбита» для AOD: время в центре кольца. Волнистая дуга (как прогресс в M3 Expressive)
// показывает, сколько минут часа прошло; точка на внешней орбите — текущий час.
Column {
    id: o

    required property var clock          // AodClock: hh, mm, now, date, k, at(), fade()
    readonly property real k: clock.k

    spacing: 30 * k

    Item {
        id: ring
        readonly property real d: 400 * o.k
        readonly property real rad: d / 2 - 34 * o.k            // радиус кольца (снаружи остаётся место орбите часа)
        readonly property real grow: Math.min(1, o.clock.at(0.1, 0.8))
        // доля часа; при появлении дуга «дорастает» до неё
        property real frac: o.clock.now.getMinutes() / 60
        Behavior on frac { enabled: o.clock.p >= 1; NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
        readonly property real sweep: Math.max(0.004, frac * grow) * Math.PI * 2

        anchors.horizontalCenter: parent.horizontalCenter
        width: d; height: d

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            // оставшаяся часть часа — ровная тонкая дорожка
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.alpha(o.clock.cFg, 0.14)
                strokeWidth: 6 * o.k
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.d / 2; centerY: ring.d / 2
                    radiusX: ring.rad; radiusY: ring.rad
                    startAngle: -90 + ring.sweep * 180 / Math.PI + 7
                    sweepAngle: Math.max(0, 360 - ring.sweep * 180 / Math.PI - 14)
                }
            }
            // прошедшие минуты — волна
            ShapePath {
                fillColor: "transparent"
                strokeColor: o.clock.cPrimary
                strokeWidth: 11 * o.k
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathPolyline {
                    path: {
                        const pts = [], c = ring.d / 2, amp = 7 * o.k, waves = 20;
                        const n = Math.max(2, Math.ceil(ring.sweep / (Math.PI * 2) * 360));
                        for (let i = 0; i <= n; i++) {
                            const a = -Math.PI / 2 + ring.sweep * i / n;
                            // волна плавно сходит на нет у концов дуги
                            const edge = Math.min(1, Math.min(i, n - i) / 6);
                            const r = ring.rad + amp * edge * Math.sin((a + Math.PI / 2) * waves);
                            pts.push(Qt.point(c + r * Math.cos(a), c + r * Math.sin(a)));
                        }
                        return pts;
                    }
                }
            }
        }

        // час — точка на внешней орбите
        Rectangle {
            readonly property real a: ((o.clock.now.getHours() % 12) + o.clock.now.getMinutes() / 60) / 12 * Math.PI * 2
            readonly property real r: ring.d / 2 - 9 * o.k
            width: 18 * o.k; height: width; radius: width / 2
            x: ring.d / 2 + r * Math.sin(a) - width / 2
            y: ring.d / 2 - r * Math.cos(a) - height / 2
            color: o.clock.cTertiary
            scale: o.clock.at(0.35, 0.5)
            Behavior on color { ColorAnimation { duration: 300 } }
        }

        Row {
            anchors.centerIn: parent
            AodDigit { ch: o.clock.hh[0]; size: 104 * o.k; weight: 480; appear: o.clock.at(0.10, 0.5) }
            AodDigit { ch: o.clock.hh[1]; size: 104 * o.k; weight: 480; appear: o.clock.at(0.15, 0.5) }
            AodDigit { ch: ":"; size: 104 * o.k; weight: 480; color: o.clock.cPrimary; appear: o.clock.at(0.20, 0.5) }
            AodDigit { ch: o.clock.mm[0]; size: 104 * o.k; weight: 480; appear: o.clock.at(0.25, 0.5) }
            AodDigit { ch: o.clock.mm[1]; size: 104 * o.k; weight: 480; appear: o.clock.at(0.30, 0.5) }
        }
    }
    Label {
        visible: o.clock.showDate
        anchors.horizontalCenter: parent.horizontalCenter
        text: o.clock.date
        size: Math.max(8, 26 * o.k); weight: 550
        color: o.clock.dateColor
        opacity: o.clock.fade(0.5, 0.3)
        elide: Text.ElideNone
    }
}
