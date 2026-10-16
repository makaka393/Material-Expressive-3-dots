import QtQuick

// Раскрытая погода: сейчас + прогноз на 12 часов
Item {
    id: root
    property date now: new Date()

    Item {
        anchors.fill: parent
        anchors.margins: 20

        // ── слева: большая температура
        Row {
            id: big
            spacing: 12
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: Weather.icon(Weather.code, Weather.isDay)
                size: 56
                fill: 1
                color: Theme.tertiary
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(Weather.temp) + "°"
                size: 52
                weight: 400
                elide: Text.ElideNone
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Label { width: 195; text: Weather.describe(Weather.code); size: 14; weight: 650 }
                Label {
                    text: I18n.t("ощущается ", "feels like ") + Math.round(Weather.feels) + "° · "
                          + Math.round(Weather.tMax) + "° / " + Math.round(Weather.tMin) + "°"
                    size: 12; color: Theme.fgVariant
                }
                Row {
                    spacing: 10
                    Row { spacing: 3; Icon { name: "air"; size: 14; color: Theme.fgVariant } Label { text: Math.round(Weather.wind) + I18n.t(" км/ч", " km/h"); size: 12; color: Theme.fgVariant } }
                    Row { spacing: 3; Icon { name: "water_drop"; size: 14; color: Theme.fgVariant } Label { text: Weather.humidity + "%"; size: 12; color: Theme.fgVariant } }
                }
            }
        }

        // ── справа: город и дата
        Column {
            anchors { right: parent.right; top: big.top; topMargin: 4 }
            spacing: 2
            Row {
                anchors.right: parent.right
                spacing: 4
                Icon { name: "location_on"; size: 15; fill: 1; color: Theme.primary }
                Label { text: Theme.city; size: 13; weight: 650; color: Theme.primary }
            }
            Label {
                anchors.right: parent.right
                text: I18n.longDate(root.now)
                size: 12
                color: Theme.fgVariant
            }
        }

        // ── снизу: почасовой прогноз
        Row {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            spacing: 6
            Repeater {
                model: Weather.hourly
                Rectangle {
                    required property var modelData
                    width: (parent.width - 5 * 6) / 6
                    height: 76
                    radius: 18
                    color: Theme.glassChip
                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        Label { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.hour; size: 11; color: Theme.fgVariant }
                        Icon { anchors.horizontalCenter: parent.horizontalCenter; name: Weather.icon(modelData.code, modelData.day); size: 22; fill: 1; color: Theme.tertiary }
                        Label { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(modelData.temp) + "°"; size: 14; weight: 650 }
                    }
                }
            }
        }
    }
}
