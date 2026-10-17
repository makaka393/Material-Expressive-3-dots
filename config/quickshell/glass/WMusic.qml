import QtQuick
import Quickshell.Widgets

// Плеер: обложка, трек и кнопки. Ничего не играет — тихая заглушка.
Rectangle {
    id: root
    readonly property var pl: Players.active
    readonly property bool has: !!pl && (pl.trackTitle ?? "") !== ""

    radius: 44
    color: Qt.alpha(Theme.tertiaryContainer, 0.94)
    Behavior on color { ColorAnimation { duration: 400 } }

    ClippingRectangle {
        id: art
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 16 }
        width: height
        radius: 30
        color: Qt.alpha(Theme.tertiary, 0.25)
        Image {
            anchors.fill: parent
            source: Players.art(root.pl)
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 360
            asynchronous: true
        }
        Icon { anchors.centerIn: parent; visible: Players.art(root.pl) === ""; name: "music_note"; size: 44; fill: 1; color: Theme.tertiary }
    }

    Column {
        anchors { left: art.right; leftMargin: 18; right: parent.right; rightMargin: 18; top: parent.top; topMargin: 24 }
        spacing: 3
        Label {
            width: parent.width
            text: root.has ? root.pl.trackTitle : I18n.t("Ничего не играет", "Nothing playing")
            size: 19; weight: 700
            color: Theme.tertiaryContainerFg
        }
        Label {
            width: parent.width
            text: root.has ? (root.pl.trackArtist || root.pl.identity || "") : I18n.t("Включи музыку — она появится здесь", "Play something — it shows up here")
            size: 14; weight: 550
            color: Qt.alpha(Theme.tertiaryContainerFg, 0.75)
        }
    }
    Row {
        anchors { left: art.right; leftMargin: 10; bottom: parent.bottom; bottomMargin: 16 }
        spacing: 6
        visible: root.has
        IconButton { icon: "skip_previous"; size: 46; iconSize: 26; color: Theme.tertiaryContainerFg; onClicked: root.pl.previous() }
        IconButton {
            icon: root.has && root.pl.isPlaying ? "pause" : "play_arrow"
            size: 54; iconSize: 30
            bg: Theme.tertiary; color: Theme.tertiaryContainer
            onClicked: root.pl.togglePlaying()
        }
        IconButton { icon: "skip_next"; size: 46; iconSize: 26; color: Theme.tertiaryContainerFg; onClicked: root.pl.next() }
    }
}
