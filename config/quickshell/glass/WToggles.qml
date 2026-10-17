import QtQuick

// Быстрые кнопки: Wi-Fi, Bluetooth, «Не беспокоить», защита глаз — как плитки шторки.
// В ряд — круглые кнопки; квадрат — 2×2 плитки-значки; шире — плитки с подписью и состоянием.
Item {
    id: root

    readonly property bool row: height < 150
    readonly property bool labelled: !row && width >= 400

    readonly property var items: [
        { id: "wifi",
          icon: Net.icon, t: Net.hasWifi || !Net.ethernet ? "Wi-Fi" : "Ethernet",
          sub: !Net.available ? "—" : !Net.hasWifi ? (Net.ethernet ? I18n.t("Подключён", "Connected") : I18n.t("Нет адаптера", "No adapter"))
             : !Net.radio ? I18n.t("Выкл", "Off") : Net.connected ? Net.ssid : I18n.t("Не подключено", "Not connected"),
          on: Net.hasWifi ? Net.radio && Net.connected : Net.ethernet },
        { id: "bt",
          icon: Bt.icon, t: "Bluetooth",
          sub: !Bt.available ? I18n.t("Нет адаптера", "No adapter") : !Bt.powered ? I18n.t("Выкл", "Off")
             : Bt.connectedList.length > 0 ? Bt.connectedList[0].name : I18n.t("Вкл", "On"),
          on: Bt.available && Bt.powered },
        { id: "dnd",
          icon: Config.dnd ? "do_not_disturb_on" : "notifications", t: I18n.t("Не беспокоить", "Do not disturb"),
          sub: Config.dnd ? I18n.t("Вкл", "On") : I18n.t("Выкл", "Off"), on: Config.dnd },
        { id: "night",
          icon: "nightlight", t: I18n.t("Защита глаз", "Night light"),
          sub: Config.nightAuto ? I18n.t("Авто", "Auto") : Night.active ? Night.temp + "K" : I18n.t("Выкл", "Off"), on: Night.active }
    ]
    function flip(id) {
        if (id === "wifi") { if (Net.hasWifi) Net.setEnabled(!Net.radio); }
        else if (id === "bt") { if (Bt.available) Bt.setPowered(!Bt.powered); }
        else if (id === "dnd") Config.dnd = !Config.dnd;
        else Night.cycle();
    }

    WidgetSurface { id: ws; anchors.fill: parent; tone: "primary"; radius: Math.min(44, root.height / 2) }

    Grid {
        anchors { fill: parent; margins: root.row ? 0 : 14 }
        columns: root.row ? 4 : 2
        spacing: root.row ? 0 : 10
        Repeater {
            model: root.items.length
            Item {
                id: t
                required property int index
                readonly property var modelData: root.items[index]
                width: root.row ? root.width / 4 : (parent.width - 10) / 2
                height: root.row ? root.height : (parent.height - 10) / 2
                Rectangle {
                    id: tile
                    anchors.centerIn: parent
                    width: root.row ? Math.min(parent.width - 10, parent.height - 24) : parent.width
                    height: root.row ? width : parent.height
                    radius: t.modelData.on ? (root.row ? width / 2 : 22) : (root.row ? width / 2 : height / 2)
                    color: t.modelData.on ? ws.fill : ws.chip
                    scale: tm.pressed ? 0.94 : 1
                    Behavior on radius { Anim { kind: "fast" } }
                    Behavior on color { ColorAnimation { duration: 200 } }
                    Behavior on scale { Anim { kind: "fast" } }
                    Icon {
                        id: ic
                        anchors.horizontalCenter: root.labelled ? undefined : parent.horizontalCenter
                        anchors.left: root.labelled ? parent.left : undefined
                        anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        name: t.modelData.icon; size: root.row ? 26 : 28; fill: t.modelData.on ? 1 : 0
                        color: t.modelData.on ? ws.fillInk : ws.fg
                    }
                    Column {
                        visible: root.labelled
                        anchors { left: ic.right; leftMargin: 10; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        Label { width: parent.width; text: t.modelData.t; size: 14; weight: 700; color: t.modelData.on ? ws.fillInk : ws.fg }
                        Label { width: parent.width; text: t.modelData.sub; size: 12; weight: 550; color: t.modelData.on ? Qt.alpha(ws.fillInk, 0.8) : ws.fgDim }
                    }
                }
                MouseArea { id: tm; anchors.fill: tile; cursorShape: Qt.PointingHandCursor; onClicked: root.flip(t.modelData.id) }
            }
        }
    }
}
