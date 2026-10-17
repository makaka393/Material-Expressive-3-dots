import QtQuick

// Большие часы как у Pixel: часы над минутами на тональной подложке.
Rectangle {
    id: root
    property date now: new Date()
    function pad(n) { return (n < 10 ? "0" : "") + n; }

    radius: 44
    color: Qt.alpha(Theme.primaryContainer, 0.94)
    Behavior on color { ColorAnimation { duration: 400 } }

    Column {
        anchors.centerIn: parent
        spacing: -root.height * 0.08
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.pad(root.now.getHours())
            color: Theme.primaryContainerFg
            font.family: Theme.font
            font.pixelSize: root.height * 0.4
            font.variableAxes: ({ "wght": 760, "ROND": 100, "opsz": 144 })
            font.features: ({ "tnum": 1 })
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.pad(root.now.getMinutes())
            color: Qt.alpha(Theme.primaryContainerFg, 0.78)
            font.family: Theme.font
            font.pixelSize: root.height * 0.4
            font.variableAxes: ({ "wght": 380, "ROND": 100, "opsz": 144 })
            font.features: ({ "tnum": 1 })
        }
    }
}
