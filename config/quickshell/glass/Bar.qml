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
        shotView: shot
        shotTex: shotTex
    }

    // снимок экрана для линзы Веги: один кадр в момент вызова (DynamicIsland), пока остров компактный —
    // линза преломляет то, что под ней, без петли «линза в линзе». На экране не рисуется (hideSource)
    ScreencopyView {
        id: shot
        captureSource: bar.screen
        live: false
        width: bar.screen ? bar.screen.width : 1
        height: bar.screen ? bar.screen.height : 1
    }
    ShaderEffectSource {
        id: shotTex
        sourceItem: shot
        hideSource: true
        live: true
        mipmap: true
        smooth: true
        textureSize: Qt.size(Math.max(1, shot.width), Math.max(1, shot.height))   // полное: линза увеличивает
        visible: false
        width: 1; height: 1
    }
}
