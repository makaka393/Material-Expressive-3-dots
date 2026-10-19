import QtQuick
import Quickshell
import Quickshell.Wayland

// Затемнение (Scrim) отдельным слоем под окном оболочки — лаунчером, настройками, шпаргалкой.
// Слой quickshell-scrim Hyprland не размывает, а у слоя окна блюр с ignore_alpha 0.01 — так размыто
// только то, что под карточкой, и карточка бывает прозрачной, как стекло темы. В одном слое
// с затемнением блюр пришлось бы отсекать по альфе выше затемнения, и карточка не могла бы быть
// прозрачнее ~45%.
// Клики проходят насквозь — «клик мимо — закрыть» ловит само окно. Окно показывать только когда
// затемнение уже на экране (visible: open && scrim.backingWindowVisible || …): слои одного уровня
// Hyprland кладёт по порядку создания, и слой окна ляжет сверху. Если показать оба разом,
// затемнение может оказаться над карточкой. И пока окно на экране, затемнение не уходит (hold):
// при быстром «закрыть — открыть» оно иначе пересоздалось бы поверх ещё живой карточки.
PanelWindow {
    id: w

    property alias shown: s.shown
    property alias dim: s.dim
    property alias origin: s.origin
    property bool hold: false            // окно над затемнением ещё на экране

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: shown || s.visible || hold
    mask: Region {}
    WlrLayershell.namespace: "quickshell-scrim"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Scrim { id: s; anchors.fill: parent }
}
