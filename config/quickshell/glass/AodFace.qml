import QtQuick
import Quickshell
import Quickshell.Widgets

// Что видно на AOD: часы, погода, музыка + анимация появления и защита от выгорания.
Item {
    id: face

    property bool open: true
    signal dismiss()
    focus: true
    Keys.onPressed: face.dismiss()

    // общий прогресс появления — от него пляшут все элементы
    property real p: 0
    NumberAnimation on p { id: intro; from: 0; to: 1; duration: 1900; running: true }
    onOpenChanged: if (open) intro.restart()

    opacity: face.open ? 1 : 0
    scale: face.open ? 1 : 0.94
    Behavior on opacity { NumberAnimation { duration: 220 } }
    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.InCubic } }

    Component.onCompleted: forceActiveFocus()

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // ── мышь: двинул — проснулись (первые полсекунды не считаем, курсор может дёрнуться)
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        property real sx: -1
        property real sy: -1
        onPositionChanged: m => {
            if (!wake.ready) return;
            if (sx < 0) { sx = m.x; sy = m.y; return; }
            if (Math.abs(m.x - sx) + Math.abs(m.y - sy) > 14) face.dismiss();
        }
        onPressed: face.dismiss()
        onWheel: face.dismiss()
    }
    Timer { id: wake; property bool ready: false; interval: 600; running: true; onTriggered: ready = true }

    // ── защита от выгорания: раз в минуту чуть сдвигаемся
    property real shiftX: 0
    property real shiftY: 0
    Behavior on shiftX { NumberAnimation { duration: 4000; easing.type: Easing.InOutSine } }
    Behavior on shiftY { NumberAnimation { duration: 4000; easing.type: Easing.InOutSine } }
    Timer {
        interval: 60000; repeat: true; running: true
        onTriggered: { face.shiftX = (Math.random() - 0.5) * 36; face.shiftY = (Math.random() - 0.5) * 28; }
    }

    // ── волны при появлении (как «вдох» Pixel)
    Repeater {
        model: 2
        Rectangle {
            required property int index
            readonly property real t: Math.max(0, Math.min(1, (face.p - index * 0.12) / 0.7))
            x: stack.x + stack.width / 2 - width / 2
            y: stack.y + clockItem.height / 2 - height / 2
            width: 760; height: 760; radius: 380
            color: "transparent"
            border.width: 3 - index
            border.color: Theme.primary
            scale: 0.25 + (1 - Math.pow(1 - t, 3)) * 1.25
            opacity: t <= 0 ? 0 : (1 - t) * 0.5
        }
    }

    Column {
        id: stack
        x: (face.width - width) / 2 + face.shiftX
        y: face.height * 0.47 - clockItem.height * 0.62 + face.shiftY
        spacing: 44

        AodClock {
            id: clockItem
            anchors.horizontalCenter: parent.horizontalCenter
            style: Config.aodFace
            now: clock.date
            k: Math.max(0.8, face.height / 1440) * 1.35
            p: face.p
        }

        // ── виджеты
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 14

            // погода
            Rectangle {
                id: weatherPill
                readonly property real a: clockItem.at(0.42, 0.5)
                visible: Config.aodWeather && Weather.ready
                anchors.horizontalCenter: parent.horizontalCenter
                width: wRow.implicitWidth + 44
                height: 60; radius: 30
                color: Qt.alpha(Theme.fg, 0.07)
                opacity: Math.min(1, a)
                transform: Translate { y: (1 - weatherPill.a) * 40 }
                Row {
                    id: wRow
                    anchors.centerIn: parent
                    spacing: 10
                    Icon { anchors.verticalCenter: parent.verticalCenter; name: Weather.icon(Weather.code, Weather.isDay); size: 30; fill: 1; color: Theme.tertiaryText }
                    Label { anchors.verticalCenter: parent.verticalCenter; text: Math.round(Weather.temp) + "°"; size: 22; weight: 650; elide: Text.ElideNone }
                    Label { anchors.verticalCenter: parent.verticalCenter; text: Weather.describe(Weather.code) + " · " + Theme.city; size: 17; color: Theme.fgVariant; elide: Text.ElideNone }
                }
            }

            // музыка
            Rectangle {
                id: musicCard
                readonly property var pl: Players.active
                readonly property bool has: !!pl && (pl.trackTitle ?? "") !== ""
                readonly property real a: clockItem.at(0.52, 0.5)
                visible: Config.aodMusic && has
                anchors.horizontalCenter: parent.horizontalCenter
                width: 500; height: 92; radius: 46
                color: Qt.alpha(Theme.fg, 0.07)
                opacity: Math.min(1, a)
                transform: Translate { y: (1 - musicCard.a) * 50 }

                // обложка — крутится, как пластинка, пока играет
                ClippingRectangle {
                    id: disc
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    width: 66; height: 66; radius: 33
                    color: Qt.alpha(Theme.primary, 0.25)
                    Image {
                        anchors.fill: parent
                        source: Players.art(musicCard.pl)
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 132
                        asynchronous: true
                    }
                    Icon { anchors.centerIn: parent; visible: Players.art(musicCard.pl) === ""; name: "music_note"; size: 24; color: Theme.primaryText }
                    RotationAnimation on rotation {
                        from: 0; to: 360; duration: 12000; loops: Animation.Infinite
                        running: musicCard.has && musicCard.pl.isPlaying
                    }
                }
                Rectangle { anchors.centerIn: disc; width: 8; height: 8; radius: 4; color: Qt.rgba(0, 0, 0, 0.6); visible: Players.art(musicCard.pl) !== "" }
                Column {
                    anchors { left: disc.right; leftMargin: 14; right: eq.left; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    Label { width: parent.width; text: musicCard.has ? musicCard.pl.trackTitle : ""; size: 19; weight: 650 }
                    Label { width: parent.width; text: musicCard.has ? (musicCard.pl.trackArtist || musicCard.pl.identity || "") : ""; size: 16; color: Theme.fgVariant }
                }
                SpectrumBars {
                    id: eq
                    anchors { right: parent.right; rightMargin: 26; verticalCenter: parent.verticalCenter }
                    playing: musicCard.has && musicCard.pl.isPlaying
                }
            }
        }
    }
}
