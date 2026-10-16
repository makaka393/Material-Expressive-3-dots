import QtQuick

// Список Wi-Fi сетей или Bluetooth-устройств внутри шторки (открывается стрелкой на плитке).
// Wi-Fi: клик — подключиться (новая защищённая сеть — спросит пароль), по активной — отключиться.
// Bluetooth: клик — подключить/отключить, новое устройство — сопряжение. Корзина — забыть.
Item {
    id: root

    property string kind: "wifi"
    signal back()
    readonly property bool wifi: kind === "wifi"
    property string pwFor: ""            // для какой сети открыт ввод пароля

    function closePw() { pwFor = ""; Net.typing = false; }

    // ── переключатель M3
    component Toggle: Rectangle {
        id: sw
        property bool checked: false
        signal toggled()
        width: 52; height: 30; radius: 15
        color: checked ? Theme.primary : Qt.alpha(Theme.fg, 0.10)
        border.width: checked ? 0 : 2; border.color: Theme.outline
        Behavior on color { ColorAnimation { duration: 180 } }
        Rectangle {
            property real d: sw.checked ? 22 : swMouse.pressed ? 24 : 14
            width: d; height: d; radius: d / 2
            anchors.verticalCenter: parent.verticalCenter
            x: sw.checked ? sw.width - d - 4 : 8 - (d - 14) / 2
            color: sw.checked ? Theme.primaryFg : Theme.outline
            Behavior on x { Anim { kind: "fast" } }
            Behavior on d { Anim { kind: "fast" } }
            Icon { anchors.centerIn: parent; name: "check"; size: 15; weight: 700; color: Theme.primary; opacity: sw.checked ? 1 : 0 }
        }
        MouseArea { id: swMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sw.toggled() }
    }

    // ── крутилка «подключаюсь»
    component Spinner: Icon {
        name: "progress_activity"
        size: 20
        color: Theme.primary
        RotationAnimation on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: true }
    }

    // ── шапка
    IconButton {
        id: backBtn
        x: 0; y: 2
        icon: "arrow_back"; size: 40; iconSize: 22
        onClicked: { root.closePw(); root.back(); }
    }
    Label {
        anchors { left: backBtn.right; leftMargin: 6; verticalCenter: backBtn.verticalCenter }
        text: root.wifi ? "Wi-Fi" : "Bluetooth"
        size: 19; weight: 750; elide: Text.ElideNone
    }
    Toggle {
        id: power
        anchors { right: parent.right; rightMargin: 6; verticalCenter: backBtn.verticalCenter }
        visible: root.wifi ? Net.available && Net.hasWifi : Bt.available
        checked: root.wifi ? Net.radio : Bt.powered
        onToggled: { if (root.wifi) Net.setEnabled(!Net.radio); else Bt.setPowered(!Bt.powered); }
    }
    IconButton {
        id: scanBtn
        anchors { right: power.left; rightMargin: 6; verticalCenter: backBtn.verticalCenter }
        visible: root.wifi ? Net.radio && Net.hasWifi : Bt.powered
        icon: root.wifi ? "refresh" : "bluetooth_searching"
        size: 38; iconSize: 21; fill: 0
        color: (root.wifi ? Net.scanning : Bt.scanning) ? Theme.primary : Theme.fg
        onClicked: root.wifi ? Net.rescan() : Bt.scan()
        RotationAnimation on rotation {
            running: root.wifi && Net.scanning
            from: 0; to: 360; duration: 1000; loops: Animation.Infinite
            onStopped: scanBtn.rotation = 0
        }
    }

    // ── подзаголовок: что происходит
    Label {
        id: status
        anchors { left: parent.left; leftMargin: 10; right: parent.right; top: backBtn.bottom; topMargin: 4 }
        size: 12; weight: 550
        color: Theme.fgVariant
        text: root.wifi
            ? (!Net.available ? I18n.t("NetworkManager не найден", "NetworkManager not found")
               : !Net.hasWifi ? (Net.ethernet ? I18n.t("Интернет по кабелю · ", "Wired · ") + Net.ethName : I18n.t("Wi-Fi адаптер не найден", "No Wi-Fi adapter"))
               : !Net.radio ? I18n.t("Wi-Fi выключен", "Wi-Fi is off")
               : Net.scanning ? I18n.t("Ищу сети…", "Scanning…")
               : I18n.t("Сетей рядом: ", "Networks nearby: ") + Net.networks.length)
            : (!Bt.available ? I18n.t("Bluetooth-адаптер не найден", "No Bluetooth adapter")
               : !Bt.powered ? I18n.t("Bluetooth выключен", "Bluetooth is off")
               : Bt.scanning ? I18n.t("Ищу устройства рядом… включи на них режим сопряжения", "Scanning… put your device in pairing mode")
               : I18n.t("Новое устройство? Нажми поиск ", "New device? Tap search ") + "⟳")
    }

    // ── список
    ListView {
        id: list
        anchors { top: status.bottom; topMargin: 10; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: true
        spacing: 6
        boundsBehavior: Flickable.StopAtBounds
        visible: root.wifi ? Net.radio && Net.hasWifi : Bt.powered
        model: root.wifi ? Net.networks : Bt.devices

        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property var d: modelData
            readonly property string key: root.wifi ? d.ssid : d.mac
            readonly property bool active: root.wifi ? d.active : d.connected
            readonly property bool busy: root.wifi ? Net.connecting === d.ssid : Bt.busy === d.mac
            readonly property bool bad: root.wifi ? Net.failed === d.ssid : Bt.failed === d.mac
            readonly property bool known: root.wifi ? d.known : d.paired
            readonly property bool pw: root.wifi && root.pwFor === d.ssid

            width: ListView.view.width
            height: pw ? 112 : 58
            radius: active ? 18 : 29
            color: active ? Theme.primaryContainer : rowMouse.containsMouse ? Qt.alpha(Theme.fg, 0.12) : Theme.glassChip
            Behavior on height { Anim { kind: "fast" } }
            Behavior on radius { Anim { kind: "fast" } }
            Behavior on color { ColorAnimation { duration: 160 } }

            MouseArea {
                id: rowMouse
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 58
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (row.busy) return;
                    if (root.wifi) {
                        if (row.active) Net.disconnect(row.d);
                        else if (row.d.secure && (!row.d.known || row.bad)) { root.pwFor = row.pw ? "" : row.d.ssid; Net.typing = root.pwFor !== ""; }
                        else { root.closePw(); Net.connect(row.d, ""); }
                    } else Bt.toggle(row.d);
                }
            }

            Rectangle {
                id: badge
                x: 9; y: 9
                width: 40; height: 40
                radius: row.active ? 13 : 20
                color: row.active ? Theme.primary : Qt.alpha(Theme.fg, 0.08)
                Behavior on radius { Anim { kind: "fast" } }
                Icon {
                    anchors.centerIn: parent
                    name: root.wifi ? Net.sigIcon(row.d.signal) : row.d.icon
                    size: 21; fill: root.wifi || row.active ? 1 : 0
                    color: row.active ? Theme.primaryFg : Theme.fg
                }
            }
            Column {
                anchors { left: badge.right; leftMargin: 11; right: trail.left; rightMargin: 8; verticalCenter: badge.verticalCenter }
                spacing: 1
                Label { width: parent.width; text: root.wifi ? row.d.ssid : row.d.name; size: 14; weight: 650
                        color: row.active ? Theme.primaryContainerFg : Theme.fg }
                Label {
                    width: parent.width
                    size: 12; weight: 500
                    color: row.bad ? Theme.error : row.active ? Qt.alpha(Theme.primaryContainerFg, 0.8) : Theme.fgVariant
                    text: root.wifi
                        ? (row.busy ? I18n.t("Подключаюсь…", "Connecting…")
                           : row.bad ? I18n.t("Не вышло — проверь пароль", "Failed — check the password")
                           : row.active ? I18n.t("Подключено · нажми, чтобы отключить", "Connected · tap to disconnect")
                           : row.d.known ? I18n.t("Сохранена", "Saved")
                           : row.d.secure ? I18n.t("Защищена", "Secured") : I18n.t("Открытая сеть", "Open network"))
                        : (row.busy ? (row.d.paired ? I18n.t("Подключаю…", "Connecting…") : I18n.t("Сопряжение…", "Pairing…"))
                           : row.bad ? I18n.t("Не вышло — включи режим сопряжения", "Failed — enable pairing mode")
                           : row.active ? I18n.t("Подключено", "Connected") + (row.d.battery >= 0 ? " · " + row.d.battery + "%" : "")
                           : row.d.paired ? I18n.t("Сопряжено", "Paired") : I18n.t("Новое · нажми, чтобы подключить", "New · tap to pair"))
                }
            }
            Row {
                id: trail
                anchors { right: parent.right; rightMargin: 10; verticalCenter: badge.verticalCenter }
                spacing: 2
                Spinner { visible: row.busy; anchors.verticalCenter: parent.verticalCenter }
                Icon {
                    visible: root.wifi && row.d.secure && !row.known && !row.busy
                    anchors.verticalCenter: parent.verticalCenter
                    name: "lock"; size: 18; color: Theme.fgVariant
                }
                // батарейка наушников
                Icon {
                    visible: !root.wifi && row.d.battery >= 0
                    anchors.verticalCenter: parent.verticalCenter
                    name: row.d.battery > 80 ? "battery_full" : row.d.battery > 50 ? "battery_5_bar" : row.d.battery > 20 ? "battery_3_bar" : "battery_1_bar"
                    size: 18; color: row.active ? Theme.primaryContainerFg : Theme.fgVariant
                }
                IconButton {
                    visible: row.known && !row.busy && (rowMouse.containsMouse || hovered)
                    property bool hovered: false
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "delete"; size: 32; iconSize: 18; fill: 0
                    color: row.active ? Theme.primaryContainerFg : Theme.fgVariant
                    onClicked: { if (root.wifi) Net.forget(row.d); else Bt.forget(row.d); }
                    HoverHandler { onHoveredChanged: parent.hovered = hovered }
                }
            }

            // ── пароль для новой сети
            Item {
                visible: row.pw
                opacity: row.pw ? 1 : 0
                Behavior on opacity { Anim { kind: "effects" } }
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 9 }
                height: 42
                Rectangle {
                    id: pwBox
                    anchors { left: parent.left; right: goBtn.left; rightMargin: 8 }
                    height: 42; radius: 21
                    color: Qt.alpha(Theme.fg, 0.08)
                    border.width: pwInput.activeFocus ? 2 : 0; border.color: Theme.primary
                    TextInput {
                        id: pwInput
                        anchors { left: parent.left; leftMargin: 16; right: eye.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                        color: Theme.fg
                        font.family: Theme.font; font.pixelSize: 14
                        echoMode: eye.show ? TextInput.Normal : TextInput.Password
                        passwordCharacter: "•"
                        clip: true
                        onVisibleChanged: if (visible) forceActiveFocus()
                        Keys.onReturnPressed: goBtn.go()
                        Keys.onEnterPressed: goBtn.go()
                        Keys.onEscapePressed: root.closePw()
                        Label {
                            visible: pwInput.text === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.t("Пароль", "Password"); size: 14; color: Theme.fgVariant
                        }
                    }
                    IconButton {
                        id: eye
                        property bool show: false
                        anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                        icon: show ? "visibility_off" : "visibility"; size: 34; iconSize: 18; fill: 0
                        color: Theme.fgVariant
                        onClicked: show = !show
                    }
                }
                Rectangle {
                    id: goBtn
                    function go() {
                        if (pwInput.text.length < 8) return;
                        Net.connect(row.d, pwInput.text);
                        root.closePw();
                    }
                    anchors.right: parent.right
                    width: 50; height: 42; radius: goMouse.pressed ? 12 : 21
                    color: pwInput.text.length >= 8 ? Theme.primary : Qt.alpha(Theme.fg, 0.08)
                    Behavior on radius { Anim { kind: "fast" } }
                    Icon { anchors.centerIn: parent; name: "arrow_forward"; size: 22; color: pwInput.text.length >= 8 ? Theme.primaryFg : Theme.fgVariant }
                    MouseArea { id: goMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: goBtn.go() }
                }
            }
        }
    }

    // ── пусто
    Column {
        anchors.centerIn: list
        spacing: 10
        visible: !list.visible || list.count === 0
        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: root.wifi ? Net.icon : Bt.icon
            size: 44; color: Theme.fgVariant
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            size: 13; color: Theme.fgVariant; elide: Text.ElideNone
            text: root.wifi ? (Net.radio && Net.hasWifi ? I18n.t("Сетей не видно", "No networks") : "")
                            : (Bt.powered ? (Bt.scanning ? I18n.t("Ищу…", "Searching…") : I18n.t("Нет устройств", "No devices")) : "")
        }
    }
}
