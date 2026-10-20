//@ pragma UseQApplication
import QtQuick
import Quickshell

ShellRoot {
    // блюр Hyprland под выбранный стиль (см. Blur.qml) — синглтон живёт, пока на него кто-то ссылается
    readonly property bool glassBlur: Blur.want
    // игровой режим и без gamemoderun (см. Games.qml)
    readonly property bool gaming: Games.playing

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
    Desktop {}
}
