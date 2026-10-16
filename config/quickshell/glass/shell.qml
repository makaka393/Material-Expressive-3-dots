//@ pragma UseQApplication
import QtQuick
import Quickshell

ShellRoot {
    // блюр Hyprland под выбранный стиль (см. Blur.qml) — синглтон живёт, пока на него кто-то ссылается
    readonly property bool glassBlur: Blur.want

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
