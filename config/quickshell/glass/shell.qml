//@ pragma UseQApplication
import QtQuick
import Quickshell

ShellRoot {
    // блюр Hyprland под выбранный стиль (см. Blur.qml) — синглтон живёт, пока на него кто-то ссылается
    readonly property bool glassBlur: Blur.want
    readonly property bool gameAlerts: Attention.games.length > 0   // уведомление «игра найдена»

    Variants {
        model: Quickshell.screens
        Bar {}
    }
    Picker {}
    SettingsWindow {}
    Launcher {}
    Aod {}
    Lock {}
    Hotkeys {}
}
