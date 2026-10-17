import QtQuick

// Выбор одного из нескольких — соединённая группа кнопок M3 Expressive: выбранная — залитая
// пилюля, остальные — тональные с меньшим скруглением; нажатие сжимает форму.
Row {
    id: c
    property var options: []          // [{ id, t, icon? }]
    property string current: ""
    signal picked(string v)
    spacing: 4

    Repeater {
        model: c.options
        Rectangle {
            id: o
            required property var modelData
            readonly property bool on: c.current === modelData.id
            width: (c.width - c.spacing * (c.options.length - 1)) / c.options.length
            height: 44
            radius: om.pressed ? 10 : on ? height / 2 : 14
            color: on ? Theme.primary : om.containsMouse ? Qt.alpha(Theme.fg, 0.14) : Theme.glassChip
            Behavior on radius { Anim { kind: "fast" } }
            Behavior on color { ColorAnimation { duration: 180 } }
            scale: om.pressed ? 0.96 : 1
            Behavior on scale { Anim { kind: "fast" } }
            Row {
                anchors.centerIn: parent
                spacing: 6
                Icon { visible: !!o.modelData.icon; anchors.verticalCenter: parent.verticalCenter; name: o.modelData.icon || ""; size: 18
                       fill: o.on ? 1 : 0; color: o.on ? Theme.primaryFg : Theme.fg }
                Label { anchors.verticalCenter: parent.verticalCenter; text: o.modelData.t; size: 13; weight: o.on ? 750 : 600
                        color: o.on ? Theme.primaryFg : Theme.fg; elide: Text.ElideNone }
            }
            MouseArea { id: om; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: c.picked(o.modelData.id) }
        }
    }
}
