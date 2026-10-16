import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Mpris

// Раскрытый плеер в стиле медиа-карточки Android / Pixel:
// размытая обложка фоном, большая кнопка play, которая меняет форму,
// и волнистый прогресс.
Item {
    id: root
    property var player: null
    readonly property real len: player?.length ?? 0
    readonly property real pos: player?.position ?? 0
    readonly property bool playing: player?.isPlaying ?? false
    readonly property string art: Players.art(player)

    Timer {
        interval: 250
        repeat: true
        running: root.visible && root.playing
        onTriggered: root.player.positionChanged()
    }

    // ── фон: размытая обложка
    ClippingRectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Theme.radiusCard - 1
        color: "transparent"

        Image {
            id: bgArt
            anchors.fill: parent
            source: root.art
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
            sourceSize.width: 256
            sourceSize.height: 256
        }
        MultiEffect {
            anchors.fill: parent
            source: bgArt
            blurEnabled: true
            blur: 1.0
            blurMax: 64
            saturation: 0.15
            opacity: bgArt.status === Image.Ready ? 0.8 : 0
            Behavior on opacity { Anim { kind: "effects"; duration: 500 } }
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.alpha(Theme.surfaceLowest, 0.62) }
                GradientStop { position: 1.0; color: Qt.alpha(Theme.surfaceLowest, 0.22) }
            }
        }
    }

    Item {
        anchors.fill: parent
        anchors.margins: 18

        // ── обложка
        ClippingRectangle {
            id: cover
            width: 96
            height: 96
            radius: 18
            color: Theme.surfaceHigh
            Image {
                anchors.fill: parent
                source: root.art
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 192
                sourceSize.height: 192
            }
            Icon {
                anchors.centerIn: parent
                visible: root.art === ""
                name: "music_note"
                size: 40
                color: Theme.fgVariant
            }
        }

        // ── текст
        Column {
            anchors { left: cover.right; leftMargin: 16; right: playBtn.left; rightMargin: 14; verticalCenter: cover.verticalCenter }
            spacing: 2
            Row {
                spacing: 6
                Icon { name: "graphic_eq"; size: 14; color: Theme.primary; fill: 1 }
                Label {
                    text: root.player?.identity ?? ""
                    size: 12
                    weight: 600
                    color: Theme.primary
                }
            }
            Label {
                width: parent.width
                text: root.player?.trackTitle || I18n.t("Ничего не играет", "Nothing playing")
                size: 20
                weight: 700
                maximumLineCount: 1
            }
            Label {
                width: parent.width
                text: root.player?.trackArtist ?? ""
                size: 14
                weight: 450
                color: Theme.fgVariant
            }
        }

        // ── большая кнопка play: круг на паузе → скруглённый квадрат при игре
        Item {
            id: playBtn
            anchors { right: parent.right; verticalCenter: cover.verticalCenter }
            width: 64
            height: 64
            Rectangle {
                anchors.fill: parent
                radius: playMouse.pressed ? 12 : root.playing ? 20 : 32
                color: Theme.primary
                scale: playMouse.pressed ? 0.92 : playMouse.containsMouse ? 1.04 : 1
                Behavior on radius { Anim { kind: "fast" } }
                Behavior on scale { Anim { kind: "fast" } }
                Behavior on color { ColorAnimation { duration: 350 } }
            }
            Icon {
                anchors.centerIn: parent
                name: root.playing ? "pause" : "play_arrow"
                size: 32
                fill: 1
                color: Theme.primaryFg
            }
            MouseArea {
                id: playMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.player?.togglePlaying()
            }
        }

        // ── нижняя строка: время, prev, волна, next, время
        Item {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 34

            Label {
                id: curTime
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: 38
                text: Players.fmt(root.pos)
                size: 12
                weight: 550
                color: Theme.fgVariant
            }
            IconButton {
                id: prevBtn
                anchors { left: curTime.right; verticalCenter: parent.verticalCenter }
                icon: "skip_previous"
                size: 34
                onClicked: root.player?.previous()
            }
            WavyProgress {
                anchors { left: prevBtn.right; right: nextBtn.left; leftMargin: 8; rightMargin: 8; verticalCenter: parent.verticalCenter }
                value: root.len > 0 ? root.pos / root.len : 0
                playing: root.playing
                onSeek: f => { if (root.player?.canSeek) root.player.position = f * root.len; }
            }
            IconButton {
                id: nextBtn
                anchors { right: totalTime.left; verticalCenter: parent.verticalCenter }
                icon: "skip_next"
                size: 34
                onClicked: root.player?.next()
            }
            Label {
                id: totalTime
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: 38
                horizontalAlignment: Text.AlignRight
                text: Players.fmt(root.len)
                size: 12
                weight: 550
                color: Theme.fgVariant
            }
        }
    }
}
