import QtQuick

// Спектр из 12 полос по настоящему звуку (Spectrum) — для карточки музыки на AOD.
// Нет спектра (нет cava, тишина) — полосы плавно «дышат», чтобы было видно, что музыка играет.
Row {
    id: root
    property bool playing: false
    property color color: Theme.primary
    spacing: 3
    height: 34

    readonly property bool want: playing && visible
    property bool counted: false
    function sync() {
        if (want === counted) return;
        Spectrum.users += want ? 1 : -1;
        counted = want;
    }
    onWantChanged: sync()
    Component.onCompleted: sync()
    Component.onDestruction: if (counted) Spectrum.users--

    readonly property bool live: playing && Spectrum.live

    // запасная анимация: одна фаза на все полосы
    property real phase: 0
    NumberAnimation on phase { from: 0; to: Math.PI * 2; duration: 2400; loops: Animation.Infinite; running: root.playing && !root.live }

    Repeater {
        model: Spectrum.bars
        Rectangle {
            required property int index
            anchors.verticalCenter: parent.verticalCenter
            width: 4
            radius: 2
            color: root.color
            opacity: root.playing ? 1 : 0.4
            height: !root.playing ? 4
                  : root.live ? 4 + (root.height - 4) * Math.min(1, (Spectrum.values[index] ?? 0) * (1 + index * 0.06))
                  : 4 + (root.height - 4) * 0.35 * (1 + Math.sin(root.phase + index * 0.7))
            Behavior on height { enabled: root.live; NumberAnimation { duration: 70 } }
            Behavior on opacity { NumberAnimation { duration: 300 } }
        }
    }
}
