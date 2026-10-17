pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Все настройки бара в одном месте. Цвета берутся из matugen
// (~/.cache/matugen/colors.json) и плавно перетекают при смене обоев.
Singleton {
    id: root

    // ───────── настройки ─────────
    readonly property string city: I18n.t("София", "Sofia")
    readonly property real lat: 42.6977
    readonly property real lon: 23.3219
    readonly property int workspaceCount: 5
    readonly property bool mediaPeek: true      // при смене трека остров на 2.5с раскрывается в плеер
    // оформление и прозрачность — из окна настроек (Config → ~/.config/glass/settings.json)
    readonly property bool m3: Config.style === "m3"
    readonly property real glassOpacity: Math.max(0.02, Config.glassOpacity)   // 0% — только блюр
    readonly property string wallpaperDir: Quickshell.env("HOME") + "/Downloads/Wallpapers"   // папка с обоями для выбора

    // ───────── размеры ─────────
    readonly property int barHeight: 40
    readonly property int outer: 8              // отступ от края экрана
    readonly property int gap: 8                // между островами
    readonly property int radiusCard: 28        // M3 extra-large

    // ───────── шрифты ─────────
    readonly property string font: "Google Sans Flex"
    readonly property string iconFont: "Material Symbols Rounded"
    // Оптическая центровка (Label): расстояние от верха строки до середины прописной буквы, в em.
    // Строка шрифта несимметрична относительно букв и цифр — без поправки текст в кнопках
    // и пилюлях стоит на пиксель выше центра.
    readonly property real capCenter: (fontM.ascent - capM.tightBoundingRect.height / 2) / 100
    FontMetrics { id: fontM; font.family: root.font; font.pixelSize: 100 }
    TextMetrics { id: capM; font: fontM.font; text: "H" }

    // ───────── motion: токены M3 Expressive ─────────
    readonly property var spatial: [0.38, 1.21, 0.22, 1.00, 1, 1]       // default spatial, 500ms
    readonly property var spatialFast: [0.42, 1.67, 0.21, 0.90, 1, 1]   // fast spatial, 350ms
    readonly property var effects: [0.34, 0.80, 0.34, 1.00, 1, 1]       // default effects, 200ms
    readonly property var emphasized: [0.05, 0.70, 0.10, 1.00, 1, 1]
    readonly property int durSpatial: 500
    readonly property int durFast: 350
    readonly property int durEffects: 220

    // ───────── цвета (Material 3) ─────────
    readonly property color primary: c.primary
    readonly property color primaryFg: c.primaryFg
    readonly property color primaryContainer: c.primaryContainer
    readonly property color primaryContainerFg: c.primaryContainerFg
    readonly property color secondary: c.secondary
    readonly property color secondaryContainer: c.secondaryContainer
    readonly property color secondaryContainerFg: c.secondaryContainerFg
    readonly property color tertiary: c.tertiary
    readonly property color tertiaryContainer: c.tertiaryContainer
    readonly property color tertiaryContainerFg: c.tertiaryContainerFg
    readonly property color error: c.error
    readonly property color surface: c.surface
    readonly property color surfaceLowest: c.surfaceLowest
    readonly property color surfaceLow: c.surfaceLow
    readonly property color surfaceMid: c.surfaceMid
    readonly property color surfaceHigh: c.surfaceHigh
    readonly property color surfaceHighest: c.surfaceHighest
    readonly property color fg: c.surfaceFg
    readonly property color fgVariant: c.surfaceVariantFg
    readonly property color outline: c.outline
    readonly property color outlineVariant: c.outlineVariant

    // поверхности островов: «стекло» (тёмная дымка + блюр Hyprland) или M3 (тональные поверхности)
    readonly property real m3Opacity: Math.max(0.02, Config.m3Opacity)
    // стекло — матовое, как плавающие панели One UI: чуть высветленная поверхность поверх сильного блюра
    readonly property color frost: Qt.tint(surfaceHigh, Qt.rgba(1, 1, 1, 0.08))
    readonly property color glass: m3 ? Qt.alpha(surfaceMid, m3Opacity) : Qt.alpha(frost, glassOpacity)
    // раскрытые карточки/окна не бывают совсем прозрачными — иначе нечитаемо
    readonly property color glassStrong: m3 ? Qt.alpha(surfaceHigh, Math.max(0.45, Math.min(1, m3Opacity + 0.25)))
                                            : Qt.alpha(frost, Math.max(0.45, Math.min(1, glassOpacity + 0.25)))
    readonly property color glassBorder: m3 ? Qt.alpha(fg, m3Opacity < 0.97 ? 0.07 : 0) : Qt.alpha(fg, 0.10)
    readonly property color glassSheen: m3 ? "transparent" : Qt.rgba(1, 1, 1, 0.09)      // блик сверху
    readonly property color glassRim: m3 ? "transparent" : Qt.rgba(1, 1, 1, 0.34)        // светлая кромка по верхнему краю
    readonly property color glassShade: m3 ? "transparent" : Qt.rgba(0, 0, 0, 0.13)      // тень у нижнего края
    readonly property color glassChip: m3 ? Qt.alpha(surfaceHighest, Math.max(0.35, m3Opacity)) : Qt.alpha(fg, 0.08)

    // цвет, который читается текстом на bg: у «точного цвета» primary бывает тёмным, и заголовки
    // им на тёмной поверхности почти не видны — тогда берём тот же оттенок, но светлее (или темнее)
    function lum(c) {
        const f = x => x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4);
        return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
    }
    function contrast(a, b) { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); }
    function legible(c, bg, need) {
        const k = need || 3.4;
        if (contrast(c, bg) >= k) return c;
        const up = lum(bg) < 0.18;
        for (let l = c.hslLightness; up ? l <= 0.97 : l >= 0.03; l += up ? 0.04 : -0.04) {
            const t = Qt.hsla(c.hslHue, Math.min(1, c.hslSaturation * 1.1), l, 1);
            if (contrast(t, bg) >= k) return t;
        }
        return up ? "white" : "black";
    }
    readonly property color primaryText: legible(primary, surface)
    readonly property color tertiaryText: legible(tertiary, surface)

    function css(col) {
        return "rgba(" + Math.round(col.r * 255) + "," + Math.round(col.g * 255) + ","
               + Math.round(col.b * 255) + "," + col.a + ")";
    }

    FileView {
        path: Quickshell.env("HOME") + "/.cache/matugen/colors.json"
        watchChanges: true
        onFileChanged: reload()

        JsonAdapter {
            id: c
            property string primary: "#a8c7fa"
            property string primaryFg: "#062e6f"
            property string primaryContainer: "#284777"
            property string primaryContainerFg: "#d6e3ff"
            property string secondary: "#bec6dc"
            property string secondaryContainer: "#3e4759"
            property string secondaryContainerFg: "#dae2f9"
            property string tertiary: "#ddbce0"
            property string tertiaryContainer: "#573e5c"
            property string tertiaryContainerFg: "#fad8fd"
            property string error: "#ffb4ab"
            property string surface: "#111318"
            property string surfaceLowest: "#0c0e13"
            property string surfaceLow: "#191c20"
            property string surfaceMid: "#1d2024"
            property string surfaceHigh: "#282a2f"
            property string surfaceHighest: "#33353a"
            property string surfaceFg: "#e2e2e9"
            property string surfaceVariantFg: "#c4c6d0"
            property string outline: "#8e9099"
            property string outlineVariant: "#44474f"
        }
    }
}
