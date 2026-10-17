import QtQuick

// Погода как у Pixel. В один ряд — пилюля «значок · температура · описание»; квадрат — крупная
// температура, значок и разброс за день; шире — ещё и прогноз по часам; в три ряда — по дням.
Item {
    id: root

    readonly property bool row: height < 150
    readonly property bool wide: !row && width >= 420
    readonly property bool tall: !row && height >= 300

    WidgetSurface { id: ws; anchors.fill: parent; tone: "secondary"; radius: Math.min(44, root.height / 2) }

    // ── в один ряд
    Row {
        visible: root.row
        anchors { left: parent.left; leftMargin: 22; verticalCenter: parent.verticalCenter }
        spacing: 12
        Icon { anchors.verticalCenter: parent.verticalCenter; name: Weather.ready ? Weather.icon(Weather.code, Weather.isDay) : "cloud_off"; size: 36; fill: 1; color: ws.accent }
        Label { anchors.verticalCenter: parent.verticalCenter; text: Weather.ready ? Math.round(Weather.temp) + "°" : "—"; size: 34; weight: 500; color: ws.fg; elide: Text.ElideNone }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.width >= 300
            Label { text: Weather.ready ? Weather.describe(Weather.code) : I18n.t("Нет данных", "No data"); size: 15; weight: 650; color: ws.fg; elide: Text.ElideNone }
            Label { visible: Weather.ready; text: "↑" + Math.round(Weather.tMax) + "°  ↓" + Math.round(Weather.tMin) + "°"; size: 13; weight: 550; color: ws.fgDim; elide: Text.ElideNone }
        }
    }

    // ── текущая погода (квадрат и левая часть широкого)
    Item {
        id: now
        visible: !root.row
        width: root.wide ? 210 : root.width
        height: root.tall ? 208 : root.height

        Icon {
            anchors { left: parent.left; top: parent.top; leftMargin: 20; topMargin: 18 }
            name: Weather.ready ? Weather.icon(Weather.code, Weather.isDay) : "cloud_off"
            size: 46; fill: 1
            color: ws.accent
        }
        Label {
            anchors { right: parent.right; top: parent.top; rightMargin: 20; topMargin: 14 }
            text: Weather.ready ? Math.round(Weather.temp) + "°" : "—"
            size: 50; weight: 450; elide: Text.ElideNone
            color: ws.fg
        }
        Column {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 20; bottomMargin: 18 }
            spacing: 2
            Label {
                width: parent.width
                text: Weather.ready ? Weather.describe(Weather.code) : I18n.t("Нет данных", "No data")
                size: 15; weight: 650
                color: ws.fg
            }
            Label {
                width: parent.width
                visible: Weather.ready
                text: "↑" + Math.round(Weather.tMax) + "°  ↓" + Math.round(Weather.tMin) + "°  ·  " + Theme.city
                size: 13; weight: 550
                color: ws.fgDim
            }
        }
    }

    // ── по часам (справа в широком)
    Row {
        visible: root.wide && Weather.ready
        anchors { left: now.right; right: parent.right; rightMargin: 18; top: parent.top; topMargin: 22 }
        height: 170
        readonly property int n: Math.max(2, Math.min(6, Math.floor(width / 64)))
        Repeater {
            model: Weather.hourly.slice(0, parent.n)
            Column {
                required property var modelData
                width: (parent.width) / parent.n
                spacing: 8
                Label { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.hour; size: 13; weight: 600; color: ws.fgDim; elide: Text.ElideNone }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 46; height: 72; radius: 23
                    color: ws.chip
                    Icon { anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 8 }
                           name: Weather.icon(modelData.code, modelData.day); size: 26; fill: 1; color: ws.accent }
                    Label { anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 10 }
                            text: Math.round(modelData.temp) + "°"; size: 15; weight: 650; color: ws.fg; elide: Text.ElideNone }
                }
            }
        }
    }

    // ── по дням (внизу в три ряда и выше)
    Row {
        visible: root.tall && Weather.days.length > 1
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 18; bottomMargin: 20 }
        readonly property int n: Math.max(2, Math.min(7, Math.floor(width / 58)))
        Repeater {
            model: Weather.days.slice(0, parent.n)
            Column {
                required property var modelData
                required property int index
                width: parent.width / parent.n
                spacing: 4
                Label { anchors.horizontalCenter: parent.horizontalCenter
                        text: index === 0 ? I18n.t("Сег.", "Today") : I18n.locale.toString(modelData.date, "ddd")
                        size: 12; weight: 650; color: index === 0 ? ws.accent : ws.fgDim; elide: Text.ElideNone }
                Icon { anchors.horizontalCenter: parent.horizontalCenter; name: Weather.icon(modelData.code, true); size: 24; fill: 1; color: ws.accent }
                Label { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(modelData.max) + "°"; size: 14; weight: 650; color: ws.fg; elide: Text.ElideNone }
                Label { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(modelData.min) + "°"; size: 12; weight: 550; color: ws.fgDim; elide: Text.ElideNone }
            }
        }
    }
}
