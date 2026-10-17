import QtQuick
import Quickshell

// «Коротко о главном» как на Pixel: дата и погода прямо на обоях — чистый текст, без подложки,
// размытия и тени (подложку можно включить в «Настроить»). Выше виджет — крупнее текст;
// в два ряда добавляется ближайший восход или закат.
Item {
    id: root
    property date now: new Date()
    property string wid: ""
    property var cfg: ({})

    readonly property real k: Math.min(1.7, Math.max(0.8, height / 96))
    readonly property var sun: Sun.today
    readonly property real hourNow: now.getHours() + now.getMinutes() / 60

    WidgetSurface { id: ws; cfg: root.cfg; anchors.fill: parent; tone: "primary"; defaultBg: "none"; radius: Math.min(40, root.height / 2) }

    Column {
        anchors { left: parent.left; leftMargin: ws.bare ? 8 : 26; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        spacing: 4 * root.k

        Label {
            width: parent.width
            text: I18n.longDate(root.now)
            size: Math.round(Math.min(30 * root.k, root.width / 11)); weight: 600
            color: ws.fg
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 16
        }
        Row {
            spacing: 8 * root.k
            visible: Weather.ready
            Icon { anchors.verticalCenter: parent.verticalCenter; name: Weather.icon(Weather.code, Weather.isDay); size: Math.round(24 * root.k); fill: 1; color: ws.fgDim }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(Weather.temp) + "°  ·  " + Weather.describe(Weather.code)
                size: Math.round(18 * root.k); weight: 550; elide: Text.ElideNone
                color: ws.fgDim
            }
        }
        // в два ряда — ближайший восход или закат
        Row {
            spacing: 8 * root.k
            visible: root.height >= 180
            readonly property bool toSet: root.hourNow >= root.sun[0] && root.hourNow < root.sun[1]
            Icon { anchors.verticalCenter: parent.verticalCenter; name: parent.toSet ? "wb_twilight" : "wb_sunny"; size: Math.round(20 * root.k); fill: 1; color: ws.accent }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: (parent.toSet ? I18n.t("Закат в ", "Sunset at ") + Sun.hm(root.sun[1]) : I18n.t("Восход в ", "Sunrise at ") + Sun.hm(root.sun[0]))
                size: Math.round(16 * root.k); weight: 550; elide: Text.ElideNone
                color: ws.fgDim
            }
        }
    }
}
