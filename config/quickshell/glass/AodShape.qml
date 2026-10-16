import QtQuick
import QtQuick.Shapes

// Форма M3 Expressive, заданная радиусом как функцией угла:
//   circle — круг, cookie — «печенька» с lobes зубцами, clover — четырёхлистник,
//   squircle — суперэллипс, hex — мягкий шестиугольник
Shape {
    id: s

    property string kind: "cookie"
    property color color: Theme.primary
    property int lobes: 9

    preferredRendererType: Shape.CurveRenderer
    Behavior on color { ColorAnimation { duration: 300 } }

    function r(a) {
        switch (kind) {
        case "cookie": return 0.94 + 0.06 * Math.cos(a * lobes);
        case "clover": return 0.82 + 0.18 * Math.cos(a * 4);
        case "hex": return 0.93 + 0.07 * Math.cos(a * 6);
        case "squircle": return 1 / Math.pow(Math.pow(Math.abs(Math.cos(a)), 4) + Math.pow(Math.abs(Math.sin(a)), 4), 0.25);
        }
        return 1;
    }

    ShapePath {
        fillColor: s.color
        strokeWidth: -1
        PathPolyline {
            path: {
                const pts = [], n = 180, R = Math.min(s.width, s.height) / 2, cx = s.width / 2, cy = s.height / 2;
                for (let i = 0; i <= n; i++) {
                    const a = i / n * Math.PI * 2;
                    pts.push(Qt.point(cx + R * s.r(a) * Math.cos(a), cy + R * s.r(a) * Math.sin(a)));
                }
                return pts;
            }
        }
    }
}
