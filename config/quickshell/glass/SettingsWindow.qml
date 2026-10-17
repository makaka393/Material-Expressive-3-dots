import QtQuick
import Quickshell
import Quickshell.Wayland

// Окно настроек по центру экрана. Открывается шестерёнкой в шторке
// или: qs ipc -c glass call settings toggle. Закрыть — Esc, крестик или клик мимо.
PanelWindow {
    id: win

    readonly property bool open: Config.settingsOpen
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: open || card.opacity > 0
    WlrLayershell.namespace: "quickshell-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // затемнение с точками (волна идёт из центра), клик мимо — закрыть
    Scrim {
        anchors.fill: parent
        shown: win.open
        origin: Qt.point(width / 2, height / 2)
        onClicked: Config.settingsOpen = false
    }

    Item {
        id: card
        // верх карточки стоит на месте (там, где он у самого высокого раздела по центру экрана):
        // при смене раздела окно растёт вниз, а пункты слева не уезжают из-под курсора
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(40, Math.round((win.height - 840) / 2))
        width: 900
        // высоту задаёт открытый раздел (SettingsContent.wantHeight), но не больше экрана
        height: Math.min(win.height - 80, content.item ? content.item.wantHeight : 700)
        Behavior on height { Anim { kind: "spatial" } }
        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.92
        Behavior on opacity { Anim { kind: "effects"; duration: win.open ? 260 : 160 } }
        Behavior on scale { Anim { kind: "spatial" } }
        focus: true
        Keys.onEscapePressed: Config.settingsOpen = false

        MouseArea { anchors.fill: parent }   // клики по карточке не закрывают окно
        GlassSurface { anchors.fill: parent; radius: 36; strong: true; sheenEnd: 0.3 }
        // содержимое создаётся только пока окно открыто — закрытое не держит память
        Loader {
            id: content
            anchors.fill: parent
            active: win.visible
            sourceComponent: SettingsContent { onClose: Config.settingsOpen = false }
        }
    }
    onOpenChanged: if (open) card.forceActiveFocus()
}
