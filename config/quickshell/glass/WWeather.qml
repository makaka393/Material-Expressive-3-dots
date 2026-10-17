import QtQuick

// Погода как у Pixel: крупная температура, значок, описание и разброс за день.
Rectangle {
    id: root
    radius: 44
    color: Qt.alpha(Theme.secondaryContainer, 0.94)
    Behavior on color { ColorAnimation { duration: 400 } }

    Icon {
        anchors { left: parent.left; top: parent.top; leftMargin: 20; topMargin: 18 }
        name: Weather.ready ? Weather.icon(Weather.code, Weather.isDay) : "cloud_off"
        size: 46; fill: 1
        color: Theme.tertiary
    }
    Label {
        anchors { right: parent.right; top: parent.top; rightMargin: 20; topMargin: 14 }
        text: Weather.ready ? Math.round(Weather.temp) + "°" : "—"
        size: 50; weight: 450; elide: Text.ElideNone
        color: Theme.secondaryContainerFg
    }
    Column {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 20; bottomMargin: 18 }
        spacing: 2
        Label {
            width: parent.width
            text: Weather.ready ? Weather.describe(Weather.code) : I18n.t("Нет данных", "No data")
            size: 15; weight: 650
            color: Theme.secondaryContainerFg
        }
        Label {
            width: parent.width
            visible: Weather.ready
            text: "↑" + Math.round(Weather.tMax) + "°  ↓" + Math.round(Weather.tMin) + "°  ·  " + Theme.city
            size: 13; weight: 550
            color: Qt.alpha(Theme.secondaryContainerFg, 0.75)
        }
    }
}
