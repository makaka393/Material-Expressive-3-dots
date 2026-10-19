import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: bar
    required property var modelData
    screen: modelData

    anchors { top: true; left: true; right: true }
    // окно выше самого бара — чтобы острова могли раскрываться вниз.
    // Пустые места прозрачны и пропускают клики (mask).
    // Должно вмещать самую высокую шторку: отступ + Power с 4 уведомлениями (500 + 44 + 4×66) + отступ.
    implicitHeight: 832
    exclusiveZone: Theme.barHeight + Theme.outer + 2
    color: "transparent"

    WlrLayershell.namespace: "quickshell-bar"
    WlrLayershell.layer: WlrLayer.Top
    // клавиатура бару нужна только пока вводишь пароль от Wi-Fi в шторке
    WlrLayershell.keyboardFocus: Net.typing ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: Region {
        Region { item: content.leftGroup }
        Region { item: content.centerGroup }
        Region { item: content.rightGroup }
    }

    BarContent {
        id: content
        anchors.fill: parent
        barWindow: bar
    }

    // сияние Веги — своим окном поверх бара, вокруг острова (см. AssistantGlow)
    AssistantGlow {
        screen: bar.screen
        island: content.centerGroup
        active: content.centerGroup.assist && Assistant.busy
    }
}
