import QtQuick

// Подложка виджета рабочего стола — в цвет и прозрачность темы, как бар и окна оболочки:
//   стиль «Стекло» — матовое стекло (плотность — Config.glassOpacity) с оттенком контейнера темы,
//                    бликом и светлой кромкой; под ним блюр Hyprland (layer_rule quickshell-desktop);
//   Material      — тональный контейнер M3 (прозрачность — Config.m3Opacity).
// tone: "primary" | "secondary" | "tertiary" | "neutral". Цвета для содержимого: fg, fgDim, accent,
// fill/fillInk — заливка кнопок и колец и цвет значков на ней.
Item {
    id: s

    property string tone: "primary"
    property real radius: 44
    property bool plain: false            // без подложки (рисует сам виджет), только цвета

    readonly property color container: tone === "secondary" ? Theme.secondaryContainer
                                     : tone === "tertiary" ? Theme.tertiaryContainer
                                     : tone === "neutral" ? Theme.surfaceHigh : Theme.primaryContainer
    readonly property color containerInk: tone === "secondary" ? Theme.secondaryContainerFg
                                       : tone === "tertiary" ? Theme.tertiaryContainerFg
                                       : tone === "neutral" ? Theme.fg : Theme.primaryContainerFg
    readonly property color hue: tone === "secondary" ? Theme.secondary : tone === "tertiary" ? Theme.tertiary : Theme.primary
    // на чём читается текст: у стекла — матовая поверхность, у M3 — сам контейнер
    readonly property color ground: Theme.m3 ? container : Theme.frost

    readonly property color fg: Theme.m3 ? containerInk : Theme.fg
    readonly property color fgDim: Qt.alpha(fg, 0.72)
    readonly property color accent: Theme.legible(hue, ground, 4.5)
    readonly property color fill: accent
    readonly property color fillInk: Theme.lum(accent) > 0.3 ? Qt.darker(container, 1.25) : "white"
    readonly property color chip: Qt.alpha(fg, 0.1)            // неактивные кнопки и дорожки

    // M3: тональный контейнер
    Rectangle {
        anchors.fill: parent
        visible: Theme.m3 && !s.plain
        radius: s.radius
        color: Qt.alpha(s.container, Theme.m3Opacity)
        border.width: 1
        border.color: Theme.glassBorder
        Behavior on color { ColorAnimation { duration: 350 } }
    }
    // стекло с оттенком контейнера
    GlassSurface {
        anchors.fill: parent
        visible: !Theme.m3 && !s.plain
        radius: s.radius
        tint: s.container
    }
}
