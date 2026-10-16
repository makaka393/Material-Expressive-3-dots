import QtQuick

// Три полоски, пока играет музыка: низкие, средние и высокие частоты по настоящему звуку
// (Spectrum); если спектра нет — просто прыгают.
Row {
    id: root
    property bool playing: false
    spacing: 2
    height: 14

    // спектр нужен, только пока полоски видны и музыка играет
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

    Repeater {
        model: 3
        Rectangle {
            id: bar
            required property int index
            anchors.bottom: parent.bottom
            width: 3
            radius: 1.5
            color: Theme.primary

            property real jump: 4
            height: root.live ? 3 + 11 * Math.min(1, Spectrum.level(index * 4, index * 4 + 3) * [1.0, 1.25, 1.6][index]) : jump
            Behavior on height { enabled: root.live; NumberAnimation { duration: 70 } }
            SequentialAnimation on jump {
                running: root.playing && !root.live
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { to: [12, 8, 14][bar.index]; duration: [380, 300, 450][bar.index]; easing.type: Easing.InOutSine }
                NumberAnimation { to: 4; duration: [320, 420, 260][bar.index]; easing.type: Easing.InOutSine }
            }
        }
    }
}
