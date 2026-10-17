import QtQuick
import QtQuick.Effects
import Quickshell

// «Коротко о главном» как на Pixel: дата и погода прямо на обоях, без подложки.
Item {
    id: root
    property date now: new Date()

    Column {
        anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
        spacing: 4
        layer.enabled: true
        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "black"; shadowOpacity: 0.55; shadowBlur: 0.8; shadowVerticalOffset: 2; autoPaddingEnabled: true }

        Label {
            text: I18n.longDate(root.now)
            size: 30; weight: 600; elide: Text.ElideNone
            color: "white"
        }
        Row {
            spacing: 8
            visible: Weather.ready
            Icon { anchors.verticalCenter: parent.verticalCenter; name: Weather.icon(Weather.code, Weather.isDay); size: 24; fill: 1; color: Qt.rgba(1, 1, 1, 0.9) }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(Weather.temp) + "°  ·  " + Weather.describe(Weather.code)
                size: 18; weight: 550; elide: Text.ElideNone
                color: Qt.rgba(1, 1, 1, 0.88)
            }
        }
    }
}
