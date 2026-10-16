import QtQuick
import QtQuick.Shapes
import "shapes/shapes/morph.js" as Morph

// Фигура Material 3 Expressive с морфингом — рисуется видеокартой (QtQuick.Shapes),
// а не через Canvas: Canvas на NVIDIA/Xorg давал чёрные квадратики.
Shape {
    id: root
    property color color: "white"
    property var roundedPolygon: null
    property var prev: null
    property real progress: 1
    property var morph: roundedPolygon ? new Morph.Morph(roundedPolygon, roundedPolygon) : null

    preferredRendererType: Shape.CurveRenderer     // сглаженные кривые без мультисэмплинга
    asynchronous: false

    onRoundedPolygonChanged: {
        if (!roundedPolygon) return;
        morph = new Morph.Morph(prev ?? roundedPolygon, roundedPolygon);
        morphAnim.enabled = false;
        progress = 0;
        morphAnim.enabled = true;
        progress = 1;
        prev = roundedPolygon;
    }
    Behavior on progress {
        id: morphAnim
        NumberAnimation { duration: 350; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.42, 1.67, 0.21, 0.90, 1, 1] }
    }

    // кубические кривые морфа → SVG-путь в координатах фигуры
    readonly property string svg: {
        if (!morph || width <= 0) return "";
        const c = morph.asCubics(progress);
        if (!c.length) return "";
        const k = Math.min(width, height);
        const ox = (width - k) / 2, oy = (height - k) / 2;
        const f = v => (v * k).toFixed(2);
        let d = "M" + (c[0].anchor0X * k + ox).toFixed(2) + " " + (c[0].anchor0Y * k + oy).toFixed(2);
        for (const q of c)
            d += "C" + (q.control0X * k + ox).toFixed(2) + " " + (q.control0Y * k + oy).toFixed(2)
               + " " + (q.control1X * k + ox).toFixed(2) + " " + (q.control1Y * k + oy).toFixed(2)
               + " " + (q.anchor1X * k + ox).toFixed(2) + " " + (q.anchor1Y * k + oy).toFixed(2);
        return d + "Z";
    }

    ShapePath {
        fillColor: root.color
        strokeColor: "transparent"
        strokeWidth: 0
        PathSvg { path: root.svg }
    }
}
