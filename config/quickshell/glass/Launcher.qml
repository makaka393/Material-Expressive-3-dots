import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Лаунчер в стекле (вместо rofi). SUPER+SPACE, эмодзи сразу — SUPER+.
//   qs ipc -c glass call launcher toggle | open | close | emoji | ask
PanelWindow {
    id: win

    property bool open: false
    property string prefill: ""
    function show(p) { prefill = p || ""; open = true; if (loader.item) loader.item.reset(prefill); }

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: open && scrim.backingWindowVisible || card.opacity > 0
    WlrLayershell.namespace: "quickshell-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // затемнение с точками (волна идёт от поля поиска) — своим слоем под окном
    ScrimWindow {
        id: scrim
        screen: win.screen
        hold: win.visible
        shown: win.open
        dim: 0.26
        origin: Qt.point(width / 2, Math.round(height * 0.17) + 36)
    }
    // клик мимо — закрыть
    MouseArea { anchors.fill: parent; onClicked: win.open = false }

    Item {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.17) + (win.open ? 0 : -18)
        width: 660
        height: loader.item ? loader.item.implicitHeight : 80
        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.96
        transformOrigin: Item.Top
        Behavior on opacity { Anim { kind: "effects"; duration: win.open ? 220 : 140 } }
        Behavior on scale { Anim { kind: "spatial" } }
        Behavior on y { Anim { kind: "spatial" } }
        Behavior on height { Anim { kind: "fast" } }

        MouseArea { anchors.fill: parent }   // клики по карточке не закрывают
        GlassSurface { anchors.fill: parent; radius: 36; strong: true; sheenEnd: 0.25 }
        // содержимое живёт только пока лаунчер открыт — закрытый не держит память
        Loader {
            id: loader
            width: parent.width
            active: win.visible
            sourceComponent: LauncherContent {
                initial: win.prefill
                onClose: win.open = false
            }
        }
    }

    Connections { target: Ui; function onLauncher(p) { win.show(p); } }

    IpcHandler {
        target: "launcher"
        function toggle(): void { if (win.open) win.open = false; else win.show(""); }
        function open(): void { win.show(""); }
        function close(): void { win.open = false; }
        function emoji(): void { win.show(":"); }
        function ask(): void { win.show("?"); }
        // открыть лаунчер и сразу спросить ассистента
        function askText(text: string): void { win.show("?" + text); Assistant.ask(text); }
    }
}
