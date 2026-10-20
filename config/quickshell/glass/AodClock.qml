import QtQuick
import QtQuick.Shapes

// Часы для AOD — несколько стилей (выбор в настройках → Always On Display):
//   bubble   — каждая цифра в своей форме M3 Expressive
//   analog   — стрелки на «печеньке» (scalloped-форма из M3); он же — запасной для неизвестного стиля
//   orbit    — время в кольце с волнистой дугой минут (AodOrbit)
//   dots     — точечное табло 5×7 (AodDots)
//   planets  — час в «солнце», минуты — планета на орбите (AodPlanets)
//   horizon  — солнце или луна на дуге над горизонтом (AodHorizon)
//   segments — семисегментные цифры из мягких пилюль (AodSegments)
// k — масштаб (1 — на весь экран, ~0.3 — превью в настройках), p — прогресс появления 0…1.
Item {
    id: c

    property string style: "analog"
    property date now: new Date()
    property real k: 1
    property real p: 1
    property bool showDate: true
    // цвета циферблата: на AOD и экране блокировки — цвета темы, на рабочем столе виджет «Часы»
    // передаёт свои (ink), подобранные под его фон, — иначе на светлом стекле светлые стрелки терялись.
    // В монохромной теме часы чисто белые: стрелки, цифры, точки и дата, а не серые оттенки палитры.
    //   ink: { fg, dim, primary, tertiary, base } или null
    property var ink: null
    readonly property color cFg: ink ? ink.fg : Theme.mono ? "white" : Theme.fg
    readonly property color cDim: ink ? ink.dim : Theme.mono ? "white" : Theme.fgVariant
    readonly property color cPrimary: ink ? ink.primary : Theme.mono ? "white" : Theme.primary
    readonly property color cTertiary: ink ? ink.tertiary : Theme.mono ? "white" : Theme.tertiary
    readonly property color cBase: ink ? ink.base : Theme.surface
    // крупные залитые фигуры (солнце «Планет», «Формы») и цифры на них; в моно — белые с тёмными цифрами
    readonly property color cFill: Theme.mono ? "white" : Theme.primaryContainer
    readonly property color cOnFill: Theme.mono ? Theme.primaryFg : Theme.primaryContainerFg
    property color dateColor: cDim                // дата под циферблатом (на рабочем столе — под цвет обоев)
    // на рабочем столе: подложки фигур — стекло темы (WidgetSurface: размытие и прозрачность из
    // настроек виджета и оболочки) вместо полупрозрачной заливки AOD. { cfg, tone } или null
    property var surface: null

    function pad(n) { return (n < 10 ? "0" : "") + n; }
    readonly property string hh: pad(now.getHours())
    readonly property string mm: pad(now.getMinutes())
    readonly property string date: {
        const s = I18n.locale.toString(now, I18n.en ? "ddd, MMMM d" : "ddd, d MMMM");
        return s.charAt(0).toUpperCase() + s.slice(1);
    }

    function clamp01(x) { return Math.max(0, Math.min(1, x)); }
    // пружинка с перелётом: 0 → чуть больше 1 → 1
    function back(t) { const c1 = 1.5, c3 = c1 + 1; return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2); }
    function at(delay, len) { const t = clamp01((p - delay) / len); return t <= 0 ? 0 : back(t); }
    function fade(delay, len) { const t = clamp01((p - delay) / len); return 1 - Math.pow(1 - t, 3); }

    implicitWidth: ld.item ? ld.item.implicitWidth : 0
    implicitHeight: ld.item ? ld.item.implicitHeight : 0

    Loader {
        id: ld
        anchors.centerIn: parent
        sourceComponent: c.style === "bubble" ? bubbleC : c.style === "orbit" ? orbitC : c.style === "dots" ? dotsC
                       : c.style === "planets" ? planetsC : c.style === "horizon" ? horizonC
                       : c.style === "segments" ? segmentsC : analogC
    }

    Component { id: orbitC; AodOrbit { clock: c } }
    Component { id: dotsC; AodDots { clock: c } }
    Component { id: planetsC; AodPlanets { clock: c } }
    Component { id: horizonC; AodHorizon { clock: c } }
    Component { id: segmentsC; AodSegments { clock: c } }

    // ── цифры в формах M3 Expressive
    Component {
        id: bubbleC
        Column {
            spacing: 22 * c.k
            Grid {
                anchors.horizontalCenter: parent.horizontalCenter
                columns: 2
                spacing: 10 * c.k
                Repeater {
                    model: Theme.mono ? [                    // монохромная тема — все фигуры белые
                        { ch: c.hh[0], bg: c.cFill, fg: c.cOnFill, shape: "cookie" },
                        { ch: c.hh[1], bg: c.cFill, fg: c.cOnFill, shape: "squircle" },
                        { ch: c.mm[0], bg: c.cFill, fg: c.cOnFill, shape: "clover" },
                        { ch: c.mm[1], bg: c.cFill, fg: c.cOnFill, shape: "hex" }
                    ] : [
                        { ch: c.hh[0], bg: Theme.primaryContainer,   fg: Theme.primaryContainerFg,   shape: "cookie" },    // «печенька»
                        { ch: c.hh[1], bg: Theme.tertiaryContainer,  fg: Theme.tertiaryContainerFg,  shape: "squircle" },  // суперэллипс
                        { ch: c.mm[0], bg: Theme.secondaryContainer, fg: Theme.secondaryContainerFg, shape: "clover" },    // четырёхлистник
                        { ch: c.mm[1], bg: Theme.primary,            fg: Theme.primaryFg,            shape: "hex" }        // мягкий шестиугольник
                    ]
                    Item {
                        id: cell
                        required property var modelData
                        required property int index
                        readonly property real s: c.at(0.06 + index * 0.08, 0.55)
                        width: 140 * c.k; height: 140 * c.k
                        AodShape {
                            anchors.fill: parent
                            visible: !c.surface
                            kind: cell.modelData.shape
                            color: Qt.alpha(cell.modelData.bg, 0.92)
                            scale: cell.s
                            rotation: (1 - Math.min(1, cell.s)) * (cell.index % 2 ? 40 : -40)
                        }
                        WidgetSurface {
                            id: cellSurf
                            anchors.fill: parent
                            visible: !!c.surface
                            cfg: c.surface ? c.surface.cfg : ({})
                            defaultBg: "blur"
                            shape: cell.modelData.shape
                            tintOverride: cell.modelData.bg
                            scale: cell.s
                            rotation: (1 - Math.min(1, cell.s)) * (cell.index % 2 ? 40 : -40)
                        }
                        AodDigit {
                            anchors.centerIn: parent
                            ch: cell.modelData.ch
                            size: 92 * c.k; weight: 640
                            // на рабочем столе форма — стекло: цифра подстраивается под то, что под ней видно
                            color: c.surface ? Theme.legible(cell.modelData.fg, cellSurf.seen, 4.5) : cell.modelData.fg
                            appear: c.at(0.14 + cell.index * 0.08, 0.5)
                        }
                    }
                }
            }
            Label {
                visible: c.showDate
                anchors.horizontalCenter: parent.horizontalCenter
                text: c.date
                size: Math.max(8, 24 * c.k); weight: 550
                color: c.dateColor
                opacity: c.fade(0.5, 0.3)
                elide: Text.ElideNone
            }
        }
    }

    // ── стрелки на «печеньке»
    Component {
        id: analogC
        Column {
            spacing: 26 * c.k
            Item {
                id: dial
                readonly property real d: 330 * c.k
                readonly property real s: c.at(0.02, 0.6)
                anchors.horizontalCenter: parent.horizontalCenter
                width: d; height: d

                WidgetSurface {
                    anchors.fill: parent
                    visible: !!c.surface
                    cfg: c.surface ? c.surface.cfg : ({})
                    tone: c.surface ? c.surface.tone : "primary"
                    defaultBg: "blur"
                    shape: "cookie"
                    lobes: 12
                    scale: dial.s
                    rotation: (1 - Math.min(1, dial.s)) * -120
                }
                Shape {
                    anchors.fill: parent
                    visible: !c.surface
                    preferredRendererType: Shape.CurveRenderer
                    scale: dial.s
                    rotation: (1 - Math.min(1, dial.s)) * -120
                    ShapePath {
                        fillColor: Qt.alpha(c.cPrimary, 0.16)
                        strokeWidth: -1
                        PathPolyline {
                            path: {
                                const pts = [], n = 240, R = dial.d / 2, cx = dial.d / 2;
                                for (let i = 0; i <= n; i++) {
                                    const a = i / n * Math.PI * 2;
                                    const r = R * (0.95 + 0.05 * Math.cos(a * 12));
                                    pts.push(Qt.point(cx + r * Math.cos(a), cx + r * Math.sin(a)));
                                }
                                return pts;
                            }
                        }
                    }
                }
                // точки часов
                Repeater {
                    model: 12
                    Rectangle {
                        required property int index
                        readonly property real a: index / 12 * Math.PI * 2
                        readonly property real r: dial.d * 0.36
                        width: (index % 3 === 0 ? 10 : 6) * c.k; height: width; radius: width / 2
                        x: dial.d / 2 + r * Math.sin(a) - width / 2
                        y: dial.d / 2 - r * Math.cos(a) - height / 2
                        color: index % 3 === 0 ? c.cPrimary : Qt.alpha(c.cFg, 0.4)
                        opacity: c.fade(0.15 + index * 0.02, 0.2)
                    }
                }
                // часовая
                Rectangle {
                    width: 22 * c.k; height: dial.d * 0.27 + width / 2; radius: width / 2
                    x: dial.d / 2 - width / 2; y: dial.d / 2 - height + width / 2
                    color: c.cPrimary
                    antialiasing: true
                    transform: Rotation {
                        origin.x: 11 * c.k; origin.y: dial.d * 0.27
                        angle: ((c.now.getHours() % 12) * 30 + c.now.getMinutes() * 0.5) * Math.min(1.04, c.at(0.2, 0.7)) - 90 * (1 - Math.min(1, c.at(0.2, 0.7)))
                    }
                }
                // минутная
                Rectangle {
                    width: 12 * c.k; height: dial.d * 0.39 + width / 2; radius: width / 2
                    x: dial.d / 2 - width / 2; y: dial.d / 2 - height + width / 2
                    color: c.cFg
                    antialiasing: true
                    transform: Rotation {
                        origin.x: 6 * c.k; origin.y: dial.d * 0.39
                        angle: c.now.getMinutes() * 6 * Math.min(1.04, c.at(0.28, 0.7))
                        Behavior on angle { enabled: c.p >= 1; NumberAnimation { duration: 600; easing.type: Easing.OutBack } }
                    }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 26 * c.k; height: width; radius: width / 2
                    color: c.cBase
                    border.width: 6 * c.k; border.color: c.cPrimary
                    scale: dial.s
                }
            }
            Label {
                visible: c.showDate
                anchors.horizontalCenter: parent.horizontalCenter
                text: c.date
                size: Math.max(8, 26 * c.k); weight: 550
                color: c.dateColor
                opacity: c.fade(0.5, 0.3)
                elide: Text.ElideNone
            }
        }
    }
}
