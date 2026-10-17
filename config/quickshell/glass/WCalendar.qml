import QtQuick

// Календарь. Маленький — сегодняшняя дата крупно (день недели, число, месяц), как у Pixel;
// от 3×3 — месяц сеткой (та же, что в острове: стрелки и колёсико листают месяцы).
Item {
    id: root
    property string wid: ""
    property var cfg: ({})
    property date now: new Date()

    readonly property bool month: width >= 300 && height >= 300

    WidgetSurface { id: ws; cfg: root.cfg; anchors.fill: parent; tone: "neutral"; radius: 40 }

    CalendarCard {
        anchors.fill: parent
        visible: root.month
        now: root.now
    }

    // ── сегодня крупно
    Column {
        anchors.centerIn: parent
        visible: !root.month
        spacing: -4
        readonly property real k: Math.min(root.width, root.height) / 208
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: { const s = I18n.locale.standaloneDayName(root.now.getDay(), Locale.LongFormat); return s.charAt(0).toUpperCase() + s.slice(1); }
            size: Math.round(18 * parent.k); weight: 700; color: ws.accent; elide: Text.ElideNone
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.now.getDate()
            color: ws.fg
            font.family: Theme.font
            font.pixelSize: Math.round(96 * parent.k)
            font.variableAxes: ({ "wght": 620, "ROND": 100, "opsz": 144 })
            font.features: ({ "tnum": 1 })
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: { const s = I18n.locale.standaloneMonthName(root.now.getMonth(), Locale.LongFormat); return s.charAt(0).toUpperCase() + s.slice(1); }
            size: Math.round(16 * parent.k); weight: 600; color: ws.fgDim; elide: Text.ElideNone
        }
    }
}
