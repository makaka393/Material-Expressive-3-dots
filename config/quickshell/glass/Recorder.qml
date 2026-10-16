import QtQuick
import Quickshell

// Запись экрана. Открывается из шторки (или SUPER+ALT+R) — остров раскрывается в меню:
// область / весь экран, звук, микрофон, GIF. Во время записи остров — красная точка
// с таймером, клик по нему — стоп.
Island {
    id: root
    objectName: "recorder"

    property var barWindow: null
    property bool open: false
    readonly property bool rec: Rec.recording
    readonly property bool busy: Rec.busy

    strong: open
    // в покое острова нет — запись запускается из шторки справа (или SUPER+ALT+R);
    // появляется меню настроек записи, а во время записи — точка с таймером
    // во время записи таймер теперь в центральном острове — здесь только меню
    targetWidth: open ? 272 : 0
    visible: open || implicitWidth > 1
    targetHeight: open ? 300 : Theme.barHeight

    // открыть по хоткею — только на мониторе в фокусе
    Connections {
        target: Rec
        function onMenuTokenChanged() {
            const name = root.barWindow && root.barWindow.screen ? root.barWindow.screen.name : "";
            if (Rec.menuScreen === "" || Rec.menuScreen === name) { root.open = true; idle.restart(); }
        }
    }
    onRecChanged: if (rec) open = false

    // закрыть: ушла мышь — или по хоткею открыли и так и не навели
    Timer { id: collapse; interval: 450; onTriggered: if (!root.hovered) root.open = false }
    Timer { id: idle; interval: 6000; onTriggered: if (!root.hovered) root.open = false }
    onHoveredChanged: { if (!hovered && open) collapse.restart(); if (hovered) idle.stop(); }

    // ── переключатель M3
    component Toggle: Item {
        id: tg
        property string icon: ""
        property string label: ""
        property bool on: false
        signal toggled()
        width: parent ? parent.width : 240
        height: 40

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: tgMouse.containsMouse ? Theme.glassChip : "transparent"
            Behavior on color { ColorAnimation { duration: 160 } }
        }
        Icon {
            id: tgIcon
            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
            name: tg.icon; size: 20; fill: tg.on ? 1 : 0
            color: tg.on ? Theme.primary : Theme.fgVariant
        }
        Label {
            anchors { left: tgIcon.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
            text: tg.label; size: 14; weight: 550; elide: Text.ElideNone
        }
        Rectangle {
            id: track
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            width: 46; height: 28; radius: 14
            color: tg.on ? Theme.primary : "transparent"
            border.width: tg.on ? 0 : 2
            border.color: Theme.outline
            Behavior on color { ColorAnimation { duration: 180 } }
            Rectangle {
                property real d: tg.on ? 20 : (tgMouse.pressed ? 20 : 14)
                width: d; height: d; radius: d / 2
                anchors.verticalCenter: parent.verticalCenter
                x: tg.on ? parent.width - d - 4 : 7 - (d - 14) / 2
                color: tg.on ? Theme.primaryFg : Theme.outline
                Behavior on x { Anim { kind: "fast" } }
                Behavior on d { Anim { kind: "fast" } }
                Behavior on color { ColorAnimation { duration: 180 } }
            }
        }
        MouseArea { id: tgMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tg.toggled() }
    }

    // ── кнопка в баре / индикатор записи
    Item {
        id: head
        anchors { top: parent.top; right: parent.right }
        width: root.open ? Theme.barHeight : root.width
        height: Theme.barHeight

        // покой: иконка
        Icon {
            anchors.centerIn: parent
            visible: !root.rec && !root.busy
            name: root.open ? "close" : "screen_record"
            size: 20; fill: 1
            color: root.open ? Theme.fg : Theme.fg
            rotation: root.open ? 90 : 0
            scale: headMouse.pressed ? 0.8 : headMouse.containsMouse ? 1.12 : 1
            Behavior on rotation { Anim { kind: "fast" } }
            Behavior on scale { Anim { kind: "fast" } }
        }
        // запись: пульсирующая точка + таймер + стоп
        Row {
            anchors.centerIn: parent
            visible: root.rec || root.busy
            spacing: 8
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 12; height: 12; radius: 6
                color: Theme.error
                visible: root.rec
                SequentialAnimation on opacity {
                    running: root.rec; loops: Animation.Infinite
                    NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                }
            }
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.busy && !root.rec
                name: "progress_activity"; size: 18; color: Theme.primary
                RotationAnimator on rotation { running: root.busy && !root.rec; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: root.rec ? Rec.fmt(Rec.elapsed) : "GIF…"
                size: 14; weight: 700; elide: Text.ElideNone
            }
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.rec
                name: "stop_circle"; size: 20; fill: 1
                color: headMouse.containsMouse ? Theme.error : Theme.fg
            }
        }
        MouseArea {
            id: headMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.rec) { Rec.stop(); return; }
                if (root.busy) return;
                root.open = !root.open;
            }
        }
    }

    // ── меню
    Label {
        anchors { left: parent.left; leftMargin: 20; verticalCenter: head.verticalCenter }
        text: I18n.t("Запись экрана", "Screen record")
        size: 15; weight: 700
        opacity: root.open ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { Anim { kind: "effects" } }
    }

    Column {
        anchors { top: head.bottom; topMargin: 8; left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 10 }
        spacing: 4
        opacity: root.open ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { Anim { kind: "effects"; duration: root.open ? 320 : 120 } }

        // область / весь экран — сегментированная кнопка M3
        Rectangle {
            width: parent.width; height: 48; radius: 24
            color: Theme.glassChip
            Rectangle {
                x: Rec.mode === "region" ? 4 : parent.width / 2
                y: 4; width: parent.width / 2 - 4; height: 40; radius: 20
                color: Theme.secondaryContainer
                Behavior on x { Anim { kind: "fast" } }
            }
            Row {
                anchors.fill: parent
                Repeater {
                    model: [{ m: "region", i: "crop_free", t: I18n.t("Область", "Area") }, { m: "full", i: "fullscreen", t: I18n.t("Весь экран", "Full screen") }]
                    Item {
                        id: seg
                        required property var modelData
                        readonly property bool on: Rec.mode === modelData.m
                        width: parent.width / 2; height: 48
                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Icon { anchors.verticalCenter: parent.verticalCenter; name: seg.modelData.i; size: 18; fill: seg.on ? 1 : 0; color: seg.on ? Theme.secondaryContainerFg : Theme.fgVariant }
                            Label { anchors.verticalCenter: parent.verticalCenter; text: seg.modelData.t; size: 13; weight: seg.on ? 700 : 550; color: seg.on ? Theme.secondaryContainerFg : Theme.fg; elide: Text.ElideNone }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Rec.mode = seg.modelData.m }
                    }
                }
            }
        }

        Toggle { icon: "volume_up"; label: I18n.t("Звук системы", "System audio"); on: Rec.audio; onToggled: Rec.audio = !Rec.audio }
        Toggle { icon: "mic"; label: I18n.t("Микрофон", "Microphone"); on: Rec.mic; onToggled: Rec.mic = !Rec.mic }
        Toggle { icon: "gif_box"; label: I18n.t("Сделать GIF", "Make GIF"); on: Rec.gif; onToggled: Rec.gif = !Rec.gif }

        // старт
        Rectangle {
            width: parent.width; height: 52
            radius: startMouse.pressed ? 16 : 26
            color: startMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary
            Behavior on radius { Anim { kind: "fast" } }
            Behavior on color { ColorAnimation { duration: 160 } }
            Row {
                anchors.centerIn: parent
                spacing: 10
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 14; height: 14; radius: 7; color: Theme.error; border.width: 2; border.color: Theme.primaryFg }
                Label { anchors.verticalCenter: parent.verticalCenter; text: Rec.mode === "region" ? I18n.t("Выбрать область", "Select area") : I18n.t("Начать запись", "Start recording"); size: 15; weight: 700; color: Theme.primaryFg; elide: Text.ElideNone }
            }
            MouseArea {
                id: startMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.open = false; Rec.start(); }
            }
        }
    }
}
