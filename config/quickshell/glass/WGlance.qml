import QtQuick
import QtQuick.Effects
import Quickshell

// «Коротко о главном» как на Pixel: дата и погода прямо на обоях, без подложки.
// Выше виджет — крупнее текст; в два ряда добавляется восход или закат.
Item {
    id: root
    property date now: new Date()

    readonly property real k: Math.min(1.7, Math.max(0.8, height / 96))
    readonly property var sun: Sun.today
    readonly property real hourNow: now.getHours() + now.getMinutes() / 60

    Column {
        anchors { left: parent.left; leftMargin: 8; right: parent.right; verticalCenter: parent.verticalCenter }
        spacing: 4 * root.k
        layer.enabled: true
        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "black"; shadowOpacity: 0.55; shadowBlur: 0.8; shadowVerticalOffset: 2; autoPaddingEnabled: true }

        Label {
            width: parent.width
            text: I18n.longDate(root.now)
            size: Math.round(Math.min(30 * root.k, root.width / 11)); weight: 600
            color: "white"
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 16
        }
        Row {
            spacing: 8 * root.k
            visible: Weather.ready
            Icon { anchors.verticalCenter: parent.verticalCenter; name: Weather.icon(Weather.code, Weather.isDay); size: Math.round(24 * root.k); fill: 1; color: Qt.rgba(1, 1, 1, 0.9) }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(Weather.temp) + "°  ·  " + Weather.describe(Weather.code)
                size: Math.round(18 * root.k); weight: 550; elide: Text.ElideNone
                color: Qt.rgba(1, 1, 1, 0.88)
            }
        }
        // в два ряда — ближайший восход или закат
        Row {
            spacing: 8 * root.k
            visible: root.height >= 180
            readonly property bool toSet: root.hourNow >= root.sun[0] && root.hourNow < root.sun[1]
            Icon { anchors.verticalCenter: parent.verticalCenter; name: parent.toSet ? "wb_twilight" : "wb_sunny"; size: Math.round(20 * root.k); fill: 1; color: Qt.rgba(1, 1, 1, 0.85) }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: (parent.toSet ? I18n.t("Закат в ", "Sunset at ") + Sun.hm(root.sun[1]) : I18n.t("Восход в ", "Sunrise at ") + Sun.hm(root.sun[0]))
                size: Math.round(16 * root.k); weight: 550; elide: Text.ElideNone
                color: Qt.rgba(1, 1, 1, 0.8)
            }
        }
    }
}
