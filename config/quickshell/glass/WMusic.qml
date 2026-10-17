import QtQuick
import Quickshell.Widgets

// Плеер. В один ряд — мини-плеер (обложка, трек, кнопки); квадрат — обложка во весь виджет
// и кнопка play; широкий — обложка слева, трек и кнопки; в три ряда — ещё и волнистый прогресс.
// Ничего не играет — тихая заглушка.
Item {
    id: root
    property date now: new Date()
    property string wid: ""
    property var cfg: ({})
    readonly property var pl: Players.active
    readonly property bool has: !!pl && (pl.trackTitle ?? "") !== ""
    readonly property bool playing: has && pl.isPlaying
    readonly property string art: Players.art(pl)

    readonly property bool row: height < 150
    readonly property bool square: !row && width < height * 1.45
    readonly property bool tall: !row && !square && height >= 300

    WidgetSurface { id: ws; cfg: root.cfg; anchors.fill: parent; tone: "tertiary"; radius: Math.min(44, root.height / 2) }

    // ── квадрат: обложка во весь виджет
    ClippingRectangle {
        anchors.fill: parent
        visible: root.square
        radius: ws.radius
        color: "transparent"
        Image {
            anchors.fill: parent
            visible: root.art !== ""
            source: root.square ? root.art : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 420
            asynchronous: true
        }
        Rectangle {
            anchors.fill: parent
            visible: root.art !== ""
            gradient: Gradient {
                GradientStop { position: 0.35; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.72) }
            }
        }
        Icon { anchors.centerIn: parent; anchors.verticalCenterOffset: -16; visible: root.art === ""; name: "music_note"; size: 56; fill: 1; color: ws.accent }
        Column {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 18; rightMargin: 70 }
            Label { width: parent.width; text: root.has ? root.pl.trackTitle : I18n.t("Ничего не играет", "Nothing playing")
                    size: 15; weight: 700; color: root.art !== "" ? "white" : ws.fg }
            Label { width: parent.width; visible: root.has; text: root.has ? (root.pl.trackArtist || root.pl.identity || "") : ""
                    size: 12; weight: 550; color: root.art !== "" ? Qt.rgba(1, 1, 1, 0.8) : ws.fgDim }
        }
        IconButton {
            anchors { right: parent.right; bottom: parent.bottom; margins: 14 }
            visible: root.has
            icon: root.playing ? "pause" : "play_arrow"
            size: 48; iconSize: 28
            bg: ws.fill; color: ws.fillInk
            onClicked: root.pl.togglePlaying()
        }
    }

    // ── мини-плеер в ряд
    Item {
        anchors.fill: parent
        visible: root.row
        ClippingRectangle {
            id: miniArt
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            width: parent.height - 28; height: width
            radius: width / 2
            color: Qt.alpha(ws.accent, 0.2)
            Image { anchors.fill: parent; source: root.row ? root.art : ""; fillMode: Image.PreserveAspectCrop; sourceSize.width: 160; asynchronous: true }
            Icon { anchors.centerIn: parent; visible: root.art === ""; name: "music_note"; size: 28; fill: 1; color: ws.accent }
            // крутится, пока играет — как пластинка
            RotationAnimation on rotation { from: 0; to: 360; duration: 12000; loops: Animation.Infinite; running: root.row && root.playing && root.visible }
        }
        Column {
            anchors { left: miniArt.right; leftMargin: 14; right: miniBtns.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            Label { width: parent.width; text: root.has ? root.pl.trackTitle : I18n.t("Ничего не играет", "Nothing playing"); size: 15; weight: 700; color: ws.fg }
            Label { width: parent.width; visible: root.has; text: root.has ? (root.pl.trackArtist || root.pl.identity || "") : ""; size: 12; weight: 550; color: ws.fgDim }
        }
        Row {
            id: miniBtns
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 2
            visible: root.has
            IconButton { visible: root.width >= 320; icon: "skip_previous"; size: 40; iconSize: 24; color: ws.fg; onClicked: root.pl.previous() }
            IconButton { icon: root.playing ? "pause" : "play_arrow"; size: 52; iconSize: 28; bg: ws.fill; color: ws.fillInk; onClicked: root.pl.togglePlaying() }
            IconButton { visible: root.width >= 260; icon: "skip_next"; size: 40; iconSize: 24; color: ws.fg; onClicked: root.pl.next() }
        }
    }

    // ── широкий
    Item {
        anchors.fill: parent
        visible: !root.row && !root.square
        ClippingRectangle {
            id: artBox
            anchors { left: parent.left; top: parent.top; margins: 16 }
            width: Math.min(parent.height, parent.width * 0.45) - 32; height: width
            radius: 30
            color: Qt.alpha(ws.accent, 0.2)
            Image {
                anchors.fill: parent
                source: !root.row && !root.square ? root.art : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 360
                asynchronous: true
            }
            Icon { anchors.centerIn: parent; visible: root.art === ""; name: "music_note"; size: 44; fill: 1; color: ws.accent }
        }
        Column {
            anchors { left: artBox.right; leftMargin: 18; right: parent.right; rightMargin: 18; top: parent.top; topMargin: 24 }
            spacing: 3
            Label {
                width: parent.width
                text: root.has ? root.pl.trackTitle : I18n.t("Ничего не играет", "Nothing playing")
                size: root.tall ? 22 : 19; weight: 700
                color: ws.fg
            }
            Label {
                width: parent.width
                text: root.has ? (root.pl.trackArtist || root.pl.identity || "") : I18n.t("Включи музыку — она появится здесь", "Play something — it shows up here")
                size: 14; weight: 550
                color: ws.fgDim
            }
        }
        WavyProgress {
            id: wavy
            visible: root.tall && root.has && (root.pl.length ?? 0) > 0
            anchors { left: artBox.right; leftMargin: 18; right: parent.right; rightMargin: 22; bottom: btns.top; bottomMargin: 10 }
            value: root.has && root.pl.length > 0 ? root.pl.position / root.pl.length : 0
            playing: root.playing
            activeColor: ws.accent
            trackColor: Qt.alpha(ws.fg, 0.2)
            onSeek: f => { if (root.pl?.canSeek) root.pl.position = f * root.pl.length; }
            Timer { interval: 500; repeat: true; running: wavy.visible && root.playing; onTriggered: root.pl.positionChanged() }
        }
        Row {
            id: btns
            anchors { left: artBox.right; leftMargin: 10; bottom: parent.bottom; bottomMargin: 16 }
            spacing: 6
            visible: root.has
            IconButton { icon: "skip_previous"; size: 46; iconSize: 26; color: ws.fg; onClicked: root.pl.previous() }
            IconButton {
                icon: root.playing ? "pause" : "play_arrow"
                size: 54; iconSize: 30
                bg: ws.fill; color: ws.fillInk
                onClicked: root.pl.togglePlaying()
            }
            IconButton { icon: "skip_next"; size: 46; iconSize: 26; color: ws.fg; onClicked: root.pl.next() }
        }
    }
}
