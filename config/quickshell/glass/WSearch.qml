import QtQuick

// Строка поиска как на главном экране Pixel: клик — лаунчер; справа — эмодзи, калькулятор
// и ассистент (лаунчер сразу в нужном режиме).
Item {
    id: root

    WidgetSurface { id: ws; anchors.fill: parent; tone: "neutral"; radius: height / 2 }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: Ui.launcher("")
        Rectangle { anchors.fill: parent; radius: height / 2; color: ws.fg; opacity: parent.pressed ? 0.1 : parent.containsMouse ? 0.05 : 0
                    Behavior on opacity { NumberAnimation { duration: 150 } } }
    }
    Icon {
        id: lens
        anchors { left: parent.left; leftMargin: 26; verticalCenter: parent.verticalCenter }
        name: "search"; size: 30; weight: 600; color: ws.accent
    }
    Label {
        anchors { left: lens.right; leftMargin: 14; right: btns.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
        text: I18n.t("Приложения, расчёты, сайты…", "Apps, math, websites…")
        size: 17; weight: 550; color: ws.fgDim
    }
    Row {
        id: btns
        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
        spacing: 4
        Repeater {
            model: [
                { p: ":", icon: "mood", min: 340 },
                { p: "=", icon: "calculate", min: 520 },
                { p: "?", icon: "auto_awesome", min: 0 }
            ]
            IconButton {
                required property var modelData
                visible: root.width >= modelData.min
                icon: modelData.icon; size: 52; iconSize: 26
                color: modelData.p === "?" ? ws.fillInk : ws.fg
                bg: modelData.p === "?" ? ws.fill : "transparent"
                onClicked: Ui.launcher(modelData.p)
            }
        }
    }
}
