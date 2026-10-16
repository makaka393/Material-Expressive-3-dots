import QtQuick
import Quickshell

// Шторка справа (как на телефоне): Wi-Fi, Bluetooth, яркость, защита глаз, запись экрана, питание
// и кнопка настроек. В баре — кнопка питания; клик раскрывает остров вниз.
// Опасные действия (выход, перезагрузка, выключение) — по второму нажатию.
Island {
    id: root
    objectName: "power"

    property bool open: false
    property string armed: ""
    property string detail: ""          // "wifi" | "bt" — открыт список сетей/устройств
    property string lastDetail: "wifi"  // что показывать, пока панель уезжает
    onDetailChanged: if (detail !== "") lastDetail = detail; else detailHold.restart()
    Timer { id: detailHold; interval: 350 }   // панель доигрывает анимацию ухода
    onOpenChanged: if (!open) { detail = ""; Net.typing = false; }
    Binding { target: Net; property: "watch"; value: root.open }
    Binding { target: Bt; property: "watch"; value: root.open }
    Binding { target: Sys; property: "watch"; value: root.open }

    strong: open
    targetWidth: open ? 380 : Theme.barHeight
    // высота: быстрые настройки + история уведомлений (до 4 штук видно, дальше прокрутка)
    readonly property real histH: Notifs.count > 0 ? 44 + Math.min(Notifs.count, 4) * 66 : 0
    targetHeight: open ? (detail !== "" ? 500 : 500 + histH) : Theme.barHeight

    readonly property var actions: [
        { id: "lock",     icon: "lock",               label: I18n.t("Заблокировать", "Lock"), cmd: [],                              confirm: false },
        { id: "suspend",  icon: "bedtime",            label: I18n.t("Сон", "Sleep"),           cmd: ["systemctl", "suspend"],        confirm: false },
        { id: "logout",   icon: "logout",             label: I18n.t("Выйти", "Log out"),         cmd: ["hyprctl", "dispatch", "exit"], confirm: true },
        { id: "reboot",   icon: "restart_alt",        label: I18n.t("Перезагрузить", "Restart"), cmd: ["systemctl", "reboot"],         confirm: true },
        { id: "poweroff", icon: "power_settings_new", label: I18n.t("Выключить", "Shut down"),     cmd: ["systemctl", "poweroff"],       confirm: true }
    ]
    readonly property var armedAction: actions.find(a => a.id === armed) || null

    function run(a) {
        if (a.confirm && armed !== a.id) { armed = a.id; disarm.restart(); return; }
        open = false; armed = "";
        if (a.id === "lock") { Locker.lock(); return; }
        // перед сном запираем экран: после пробуждения — экран блокировки, а не рабочий стол
        if (a.id === "suspend") { Locker.lock(); Quickshell.execDetached(["sh", "-c", "sleep 0.8; exec systemctl suspend"]); return; }
        Quickshell.execDetached(a.cmd);
    }

    Timer { id: disarm; interval: 3000; onTriggered: root.armed = "" }
    Timer { id: collapse; interval: 500; onTriggered: if (!root.hovered && !slider.dragging && !Net.typing) { root.open = false; root.armed = ""; } }
    onHoveredChanged: if (!hovered && open) collapse.restart()

    // ── плитка быстрой настройки (M3 Expressive): включённая — тональная и «квадратнее»
    component Tile: Rectangle {
        id: tile
        property string icon: ""
        property string title: ""
        property string sub: ""
        property bool on: false
        property color accent: Theme.primary
        property bool more: false           // стрелка справа — открыть список
        signal clicked()
        signal wheel(int dir)
        signal moreClicked()

        height: 72
        radius: on ? 22 : 36
        color: on ? Theme.primaryContainer : tileMouse.containsMouse ? Qt.alpha(Theme.fg, 0.12) : Theme.glassChip
        Behavior on radius { Anim { kind: "fast" } }
        Behavior on color { ColorAnimation { duration: 200 } }
        scale: tileMouse.pressed ? 0.96 : 1
        Behavior on scale { Anim { kind: "fast" } }

        Rectangle {
            id: badge
            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
            width: 40; height: 40
            radius: tile.on ? 13 : 20
            color: tile.on ? tile.accent : Qt.alpha(Theme.fg, 0.08)
            Behavior on radius { Anim { kind: "fast" } }
            Behavior on color { ColorAnimation { duration: 200 } }
            Icon {
                anchors.centerIn: parent
                name: tile.icon; size: 22; fill: tile.on ? 1 : 0
                color: tile.on ? Theme.primaryFg : Theme.fg
            }
        }
        Column {
            anchors { left: badge.right; leftMargin: 10; right: parent.right; rightMargin: tile.more ? 34 : 10; verticalCenter: parent.verticalCenter }
            spacing: 1
            Label { width: parent.width; text: tile.title; size: 14; weight: 700; color: tile.on ? Theme.primaryContainerFg : Theme.fg }
            Label { width: parent.width; text: tile.sub; size: 12; weight: 550; color: tile.on ? Qt.alpha(Theme.primaryContainerFg, 0.8) : Theme.fgVariant }
        }
        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.clicked()
            onWheel: w => tile.wheel(w.angleDelta.y > 0 ? 1 : -1)
        }
        Rectangle {
            visible: tile.more
            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
            width: 30; height: 56
            radius: moreMouse.pressed ? 10 : 17
            color: moreMouse.containsMouse ? Qt.alpha(tile.on ? Theme.primaryContainerFg : Theme.fg, 0.12) : "transparent"
            Behavior on radius { Anim { kind: "fast" } }
            Icon { anchors.centerIn: parent; name: "chevron_right"; size: 22; color: tile.on ? Theme.primaryContainerFg : Theme.fgVariant }
            MouseArea { id: moreMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tile.moreClicked() }
        }
    }

    // ── нагрузка: значок, значение и заливка по доле (Sys)
    component Gauge: Rectangle {
        id: gauge
        property string icon: ""
        property real value: 0               // 0…1
        property string text: ""
        property string extra: ""            // справа мелко: температура
        readonly property bool hot: value > 0.9

        height: 52
        radius: 18
        color: Theme.glassChip
        // полоска внизу плитки
        Rectangle {
            x: 12; y: parent.height - 11
            width: parent.width - 24; height: 3; radius: 1.5
            color: Qt.alpha(Theme.fg, 0.10)
            Rectangle {
                height: parent.height; radius: 1.5
                width: Math.max(3, parent.width * Math.max(0, Math.min(1, gauge.value)))
                color: gauge.hot ? Theme.error : Theme.primary
                Behavior on width { Anim { kind: "fast" } }
                Behavior on color { ColorAnimation { duration: 300 } }
            }
        }
        Icon {
            id: gaugeIcon
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter; verticalCenterOffset: -4 }
            name: gauge.icon; size: 19; fill: 1
            color: gauge.hot ? Theme.error : Theme.primary
        }
        Label {
            anchors { left: gaugeIcon.right; leftMargin: 6; verticalCenter: parent.verticalCenter; verticalCenterOffset: -4 }
            text: gauge.text; size: 13; weight: 700; elide: Text.ElideNone
        }
        Label {
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter; verticalCenterOffset: -4 }
            text: gauge.extra; size: 11; weight: 600; color: Theme.fgVariant; elide: Text.ElideNone
        }
    }

    // ── кнопка в баре
    Item {
        id: head
        anchors { top: parent.top; right: parent.right }
        width: Theme.barHeight
        height: Theme.barHeight
        Icon {
            anchors.centerIn: parent
            name: root.open ? "close" : "power_settings_new"
            size: 20; fill: 1
            color: root.open ? Theme.fg : Theme.error
            rotation: root.open ? 90 : 0
            scale: headMouse.pressed ? 0.8 : headMouse.containsMouse ? 1.12 : 1
            Behavior on rotation { Anim { kind: "fast" } }
            Behavior on scale { Anim { kind: "fast" } }
        }
        // есть непрочитанные уведомления
        Rectangle {
            x: parent.width - width - 7; y: 7
            width: 9; height: 9; radius: 4.5
            color: Theme.primary
            scale: Notifs.count > 0 && !root.open ? 1 : 0
            Behavior on scale { Anim { kind: "fast" } }
        }
        MouseArea {
            id: headMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.open = !root.open; root.armed = ""; }
        }
    }

    // ── содержимое шторки
    Item {
        id: body
        anchors { fill: parent; margins: 10; topMargin: 0 }
        opacity: root.open ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { Anim { kind: "effects"; duration: root.open ? 320 : 120 } }

        // заголовок (дата) + настройки
        Label {
            anchors { left: parent.left; leftMargin: 10; verticalCenter: gear.verticalCenter }
            text: I18n.longDate(new Date())
            size: 15; weight: 700; elide: Text.ElideNone
        }
        IconButton {
            id: gear
            anchors { right: parent.right; rightMargin: Theme.barHeight - 6 }
            y: (Theme.barHeight - height) / 2
            size: 34; iconSize: 20; icon: "settings"; fill: 0
            onClicked: { root.open = false; Config.settingsOpen = true; }
        }

        // ── главная страница шторки
        Item {
            id: mainPage
            anchors.fill: parent
            opacity: root.detail === "" ? 1 : 0
            x: root.detail === "" ? 0 : -40
            visible: opacity > 0
            Behavior on opacity { Anim { kind: "effects" } }
            Behavior on x { Anim { kind: "fast" } }

            // яркость
            Rectangle {
                id: slider
                property bool dragging: sliderMouse.pressed
                y: Theme.barHeight + 6
                width: parent.width; height: 48; radius: 24
                color: Theme.glassChip
                Rectangle {
                    height: parent.height
                    width: Math.max(parent.height, parent.width * Brightness.value / 100)
                    radius: 24
                    color: Theme.primary
                    Behavior on width { enabled: !slider.dragging; Anim { kind: "fast" } }
                }
                Icon {
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    name: Brightness.value > 60 ? "brightness_7" : Brightness.value > 30 ? "brightness_6" : "brightness_4"
                    size: 22; fill: 1; color: Theme.primaryFg
                }
                Label {
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    text: Brightness.backend === "detecting" ? "…" : Brightness.value + "%"
                    size: 14; weight: 700
                    color: Brightness.value > 85 ? Theme.primaryFg : Theme.fg
                    elide: Text.ElideNone
                }
                MouseArea {
                    id: sliderMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    enabled: Brightness.backend !== "detecting"
                    function set(x) { Brightness.set(x / width * 100); }
                    onPressed: m => set(m.x)
                    onPositionChanged: m => set(m.x)
                    onWheel: w => Brightness.set(Brightness.value + (w.angleDelta.y > 0 ? 5 : -5))
                }
            }

            // Wi-Fi и Bluetooth
            Row {
                id: netTiles
                anchors { top: slider.bottom; topMargin: 10 }
                width: parent.width
                spacing: 8
                Tile {
                    width: (netTiles.width - 8) / 2
                    more: true
                    icon: Net.icon
                    title: Net.hasWifi || !Net.ethernet ? "Wi-Fi" : "Ethernet"
                    sub: !Net.available ? I18n.t("Нет NetworkManager", "No NetworkManager")
                       : !Net.hasWifi ? (Net.ethernet ? I18n.t("Подключён", "Connected") : I18n.t("Нет адаптера", "No adapter"))
                       : !Net.radio ? I18n.t("Выкл", "Off")
                       : Net.connecting !== "" ? I18n.t("Подключаюсь…", "Connecting…")
                       : Net.connected ? Net.ssid : I18n.t("Не подключено", "Not connected")
                    on: Net.hasWifi ? Net.radio && Net.connected : Net.ethernet
                    onClicked: if (Net.hasWifi) Net.setEnabled(!Net.radio); else root.detail = "wifi"
                    onMoreClicked: { root.detail = "wifi"; if (Net.radio) Net.rescan(); }
                }
                Tile {
                    width: (netTiles.width - 8) / 2
                    more: true
                    icon: Bt.icon
                    title: "Bluetooth"
                    sub: !Bt.available ? I18n.t("Нет адаптера", "No adapter")
                       : !Bt.powered ? I18n.t("Выкл", "Off")
                       : Bt.connectedList.length > 0 ? Bt.connectedList[0].name + (Bt.connectedList[0].battery >= 0 ? " · " + Bt.connectedList[0].battery + "%" : "")
                       : I18n.t("Вкл", "On")
                    on: Bt.available && Bt.powered
                    onClicked: if (Bt.available) Bt.setPowered(!Bt.powered)
                    onMoreClicked: { root.detail = "bt"; if (Bt.powered && Bt.devices.filter(d => d.paired).length === 0) Bt.scan(); }
                }
            }

            // плитки
            Row {
                id: tiles
                anchors { top: netTiles.bottom; topMargin: 8 }
                width: parent.width
                spacing: 8
                Tile {
                    width: (tiles.width - 8) / 2
                    icon: "nightlight"
                    title: I18n.t("Защита глаз", "Eye comfort")
                    // клик по кругу: выкл → вкл → авто (с заката до рассвета) → выкл
                    sub: Config.nightAuto ? (Night.active ? Night.temp + "K · " + I18n.t("авто", "auto")
                                                          : I18n.t("Авто · с ", "Auto · from ") + Sun.hm(Sun.today[1]))
                       : Night.active ? Night.temp + "K" : I18n.t("Выкл", "Off")
                    on: Night.active
                    onClicked: Night.cycle()
                    onWheel: d => Night.setTemp(Night.temp + d * 250)
                }
                Tile {
                    width: (tiles.width - 8) / 2
                    icon: Rec.recording ? "stop_circle" : "screen_record"
                    title: I18n.t("Запись экрана", "Screen record")
                    sub: Rec.recording ? I18n.t("Идёт · ", "Recording · ") + Rec.fmt(Rec.elapsed) : Rec.busy ? I18n.t("Делаю GIF…", "Making GIF…") : I18n.t("Выкл", "Off")
                    on: Rec.recording
                    accent: Theme.error
                    onClicked: {
                        if (Rec.recording) { Rec.stop(); return; }
                        root.open = false;
                        Rec.openMenu();
                    }
                }
            }

            // «Не беспокоить» — на всю ширину
            Tile {
                id: dndTile
                anchors { top: tiles.bottom; topMargin: 8 }
                width: parent.width
                icon: Config.dnd ? "do_not_disturb_on" : "notifications"
                title: I18n.t("Не беспокоить", "Do not disturb")
                sub: Config.dnd ? I18n.t("Уведомления тихо уходят в историю", "Notifications go silently to history")
                                : Notifs.count > 0 ? I18n.t("Уведомлений: ", "Notifications: ") + Notifs.count : I18n.t("Выкл", "Off")
                on: Config.dnd
                onClicked: Config.dnd = !Config.dnd
            }

            // нагрузка: процессор, память, видеокарта
            Row {
                id: sysRow
                anchors { top: dndTile.bottom; topMargin: 8 }
                width: parent.width
                spacing: 8
                Gauge { width: (sysRow.width - 16) / 3; icon: "memory"; value: Sys.cpu
                        text: Math.round(Sys.cpu * 100) + "%"; extra: Sys.cpuTemp >= 0 ? Sys.cpuTemp + "°" : "" }
                Gauge { width: (sysRow.width - 16) / 3; icon: "memory_alt"; value: Sys.mem
                        text: Sys.memUsedGb.toFixed(1) + I18n.t(" ГБ", " GB") }
                Gauge { width: (sysRow.width - 16) / 3; icon: "developer_board"; value: Math.max(0, Sys.gpu)
                        text: Sys.gpu >= 0 ? Math.round(Sys.gpu * 100) + "%" : "—"; extra: Sys.gpuTemp >= 0 ? Sys.gpuTemp + "°" : "" }
            }

            // питание
            Row {
                id: powerRow
                anchors { top: sysRow.bottom; topMargin: 12; horizontalCenter: parent.horizontalCenter }
                spacing: 14
                Repeater {
                    model: root.actions
                    Rectangle {
                        id: pb
                        required property var modelData
                        readonly property bool armedHere: root.armed === modelData.id
                        width: 52; height: 44
                        radius: armedHere ? 14 : 22
                        color: armedHere ? Theme.error : pbMouse.containsMouse ? Qt.alpha(Theme.fg, 0.12) : Theme.glassChip
                        Behavior on radius { Anim { kind: "fast" } }
                        Behavior on color { ColorAnimation { duration: 180 } }
                        scale: pbMouse.pressed ? 0.9 : 1
                        Behavior on scale { Anim { kind: "fast" } }
                        Icon {
                            anchors.centerIn: parent
                            name: pb.modelData.icon; size: 21; fill: pb.armedHere ? 1 : 0
                            color: pb.armedHere ? Theme.surface : pb.modelData.id === "poweroff" ? Theme.error : Theme.fg
                        }
                        MouseArea { id: pbMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.run(pb.modelData) }
                    }
                }
            }
            Label {
                anchors { top: powerRow.bottom; topMargin: 8; horizontalCenter: parent.horizontalCenter }
                text: root.armedAction ? I18n.t("Нажми ещё раз: ", "Press again: ") + root.armedAction.label.toLowerCase() : ""
                size: 12; weight: 600; color: Theme.error; elide: Text.ElideNone
            }

            // история уведомлений (новые сверху)
            Item {
                id: hist
                visible: Notifs.count > 0
                anchors { top: powerRow.bottom; topMargin: 36; left: parent.left; right: parent.right }
                height: root.histH
                Label {
                    anchors { left: parent.left; leftMargin: 8; top: parent.top }
                    height: 32
                    text: I18n.t("Уведомления", "Notifications")
                    size: 14; weight: 700; color: Theme.primary; elide: Text.ElideNone
                }
                Rectangle {
                    anchors { right: parent.right; top: parent.top }
                    width: clearLbl.implicitWidth + 24; height: 30; radius: 15
                    color: clearMouse.containsMouse ? Qt.alpha(Theme.fg, 0.12) : Theme.glassChip
                    Label { id: clearLbl; anchors.centerIn: parent; text: I18n.t("Очистить", "Clear all"); size: 12; weight: 650; elide: Text.ElideNone }
                    MouseArea { id: clearMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Notifs.clearAll() }
                }
                ListView {
                    anchors { top: parent.top; topMargin: 40; left: parent.left; right: parent.right; bottom: parent.bottom }
                    clip: true
                    spacing: 6
                    model: Notifs.list.slice().reverse()
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        required property var modelData
                        width: ListView.view.width
                        height: 60
                        radius: 18
                        color: Theme.glassChip
                        NotifCard {
                            anchors { fill: parent; margins: 10; rightMargin: 8 }
                            n: parent.modelData
                            compact: true
                        }
                    }
                    add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 } }
                    displaced: Transition { NumberAnimation { properties: "y"; duration: 250; easing.type: Easing.OutCubic } }
                }
            }
        }

        // ── список сетей / устройств
        Loader {
            id: detailLoader
            anchors { fill: parent; topMargin: Theme.barHeight + 2 }
            active: root.detail !== "" || detailHold.running
            sourceComponent: NetPanel {
                kind: root.lastDetail
                opacity: root.detail !== "" ? 1 : 0
                x: root.detail !== "" ? 0 : 40
                Behavior on opacity { Anim { kind: "effects" } }
                Behavior on x { Anim { kind: "fast" } }
                onBack: { root.detail = ""; Net.typing = false; }
            }
        }
    }
}
