import QtQuick
import QtMultimedia

// Видеообои без звука, по кругу. Отдельным файлом: если QtMultimedia не установлен,
// падает только этот Loader, а экран входа работает с картинкой.
Item {
    id: root
    property url source
    readonly property bool playing: player.playbackState === MediaPlayer.PlayingState && player.position > 0

    MediaPlayer {
        id: player
        source: root.source
        loops: MediaPlayer.Infinite
        videoOutput: out
        onSourceChanged: if (source.toString() !== "") play()
    }
    VideoOutput {
        id: out
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
    }
}
