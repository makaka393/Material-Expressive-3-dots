import QtQuick

// Большие часы как у Pixel. Квадратный — часы над минутами, широкий — «ЧЧ:ММ» в строку,
// а если остаётся место — ещё и дата. Размер цифр — от размера виджета.
Item {
    id: root
    property date now: new Date()
    function pad(n) { return (n < 10 ? "0" : "") + n; }

    readonly property bool wide: width >= height * 1.7
    readonly property bool dated: wide ? height >= 190 : height >= 300

    WidgetSurface { id: ws; anchors.fill: parent; tone: "primary"; radius: Math.min(44, root.height / 2) }

    readonly property color strongColor: Theme.m3 ? ws.fg : ws.accent
    readonly property color weakColor: Qt.alpha(ws.fg, 0.8)

    // ── стопкой
    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.dated ? -root.height * 0.05 : 0
        visible: !root.wide
        spacing: -sz * 0.2
        readonly property real sz: Math.min(root.height * (root.dated ? 0.34 : 0.4), root.width * 0.55)
        WDigits { anchors.horizontalCenter: parent.horizontalCenter; text: root.pad(root.now.getHours()); font.pixelSize: parent.sz; strongColor: root.strongColor; weakColor: root.weakColor }
        WDigits { anchors.horizontalCenter: parent.horizontalCenter; text: root.pad(root.now.getMinutes()); font.pixelSize: parent.sz; strongColor: root.strongColor; weakColor: root.weakColor; strong: false }
    }
    // ── в строку
    Row {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.dated ? -root.height * 0.08 : 0
        visible: root.wide
        readonly property real sz: Math.min(root.height * (root.dated ? 0.5 : 0.66), root.width / 3.4)
        WDigits { text: root.pad(root.now.getHours()); font.pixelSize: parent.sz; strongColor: root.strongColor; weakColor: root.weakColor }
        WDigits { text: ":"; font.pixelSize: parent.sz; strongColor: root.strongColor; weakColor: root.weakColor; strong: false; opacity: 0.7 }
        WDigits { text: root.pad(root.now.getMinutes()); font.pixelSize: parent.sz; strongColor: root.strongColor; weakColor: root.weakColor; strong: false }
    }
    Label {
        visible: root.dated
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: root.height * 0.1 }
        text: I18n.longDate(root.now)
        size: Math.max(13, Math.min(22, root.height * 0.08)); weight: 600
        color: ws.fgDim; elide: Text.ElideNone
    }
}
