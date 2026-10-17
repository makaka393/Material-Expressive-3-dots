import QtQuick
import QtQuick.Window

// Подложка виджета рабочего стола и цвета для его содержимого. Как выглядит — настраивается
// у каждого виджета («Настроить» в режиме правки, как на Samsung); по умолчанию — как оболочка:
//   bg    "blur"  — размытые обои под виджетом с оттенком темы (в стиле «Стекло» — с бликом и кромкой);
//         "solid" — цвет темы с прозрачностью прямо поверх обоев;
//         "none"  — без подложки, текст прямо на обоях (как «Коротко о главном»);
//   tone  "primary" | "secondary" | "tertiary" | "neutral" — какой цвет темы;
//   alpha — сила цвета 0…1 (по умолчанию — прозрачность из настроек оболочки).
// Размытые обои — общая текстура рабочего стола (Widgets.backdrop, Desktop.qml): гладкие, без
// зерна блюра Hyprland. Шейдер — shaders/glass.frag.
Item {
    id: s

    property var cfg: ({})
    property string tone: "primary"          // по умолчанию для этого виджета (как в каталоге)
    property string defaultBg: "blur"
    property real radius: 44

    readonly property string bg: ["blur", "solid", "none"].indexOf(cfg.bg) >= 0 ? cfg.bg : defaultBg
    readonly property string toneNow: ["primary", "secondary", "tertiary", "neutral"].indexOf(cfg.tone) >= 0 ? cfg.tone : tone
    readonly property real alpha: typeof cfg.alpha === "number" ? cfg.alpha : (Theme.m3 ? Config.m3Opacity : Config.glassOpacity)
    readonly property bool bare: bg === "none"

    readonly property color container: toneNow === "secondary" ? Theme.secondaryContainer
                                     : toneNow === "tertiary" ? Theme.tertiaryContainer
                                     : toneNow === "neutral" ? Theme.surfaceHigh : Theme.primaryContainer
    readonly property color containerInk: toneNow === "secondary" ? Theme.secondaryContainerFg
                                        : toneNow === "tertiary" ? Theme.tertiaryContainerFg
                                        : toneNow === "neutral" ? Theme.fg : Theme.primaryContainerFg
    readonly property color hue: toneNow === "secondary" ? Theme.secondary : toneNow === "tertiary" ? Theme.tertiary
                               : toneNow === "neutral" ? Theme.fgVariant : Theme.primary

    // текст и значки поверх: без подложки — светлые, как «Коротко о главном» на обоях
    readonly property color fg: bare ? "white" : Theme.m3 ? containerInk : Theme.fg
    readonly property color fgDim: Qt.alpha(fg, bare ? 0.82 : 0.72)
    readonly property color accent: bare ? Qt.hsla(hue.hslHue, Math.max(0.35, hue.hslSaturation), 0.84, 1)
                                         : Theme.legible(hue, container, 4.5)
    readonly property color fill: accent
    readonly property color fillInk: Theme.lum(accent) > 0.3 ? Qt.darker(container, 1.25) : "white"
    readonly property color chip: Qt.alpha(fg, bare ? 0.16 : 0.1)            // неактивные кнопки и дорожки

    // цвет подложки: у стекла — матовая поверхность с оттенком контейнера, у M3 — сам контейнер
    readonly property color tint: Theme.m3 ? container : Qt.tint(Theme.frost, Qt.alpha(container, 0.5))

    ShaderEffect {
        id: glass
        anchors.fill: parent
        visible: !s.bare && !!Widgets.backdrop
        fragmentShader: "shaders/glass.frag.qsb"
        property vector2d res: Qt.vector2d(Math.max(1, s.Window.width), Math.max(1, s.Window.height))
        property vector2d size: Qt.vector2d(width, height)
        property real radius: Math.min(s.radius, width / 2, height / 2)
        property real flipY: GraphicsInfo.api === GraphicsInfo.OpenGL ? 1 : 0
        property real solid: s.bg === "solid" ? 1 : 0
        property real amount: s.bg === "solid" ? Math.max(0.05, s.alpha) : Math.max(0, Math.min(0.95, s.alpha))
        property real sheen: Theme.m3 ? 0.3 : 1
        property color tint: s.tint
        property var backdrop: Widgets.backdrop
        Behavior on amount { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on tint { ColorAnimation { duration: 350 } }
    }
    // пока текстуры обоев нет (первые миги после запуска) — просто цвет
    Rectangle {
        anchors.fill: parent
        visible: !s.bare && !Widgets.backdrop
        radius: Math.min(s.radius, width / 2, height / 2)
        color: Qt.alpha(s.tint, Math.max(0.3, s.alpha))
    }
}
