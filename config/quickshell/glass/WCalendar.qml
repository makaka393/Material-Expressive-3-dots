import QtQuick

// Календарь месяца на подложке (та же сетка, что в острове).
Rectangle {
    id: root
    property date now: new Date()
    radius: 40
    color: Qt.alpha(Theme.surfaceHigh, 0.94)
    Behavior on color { ColorAnimation { duration: 400 } }

    CalendarCard {
        anchors.fill: parent
        now: root.now
    }
}
