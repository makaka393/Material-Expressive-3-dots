import QtQuick
import Quickshell
import Quickshell.Widgets

// Центральный остров в духе Dynamic Island.
//  compact — часы · погода · текущий трек
//  media   — наведи на трек: остров перетекает в карточку плеера
//  weather — клик по часам/погоде: прогноз
//  toast   — всплывашка (Activity): громкость, яркость, тема, скриншот, запись…
//  идёт запись экрана — в компактном виде слева красная точка с таймером (клик — стоп)
//  assistant — голосовой ассистент (Super+A): слушаю → распознаю → думаю → отвечаю
Island {
    id: root
    objectName: "island"

    property string mode: "compact"
    readonly property var player: Players.active
    readonly property bool hasPlayer: player !== null && (player.trackTitle ?? "") !== ""

    // ассистент важнее всего: с ним сейчас разговаривают голосом
    readonly property bool assist: Assistant.showing && Assistant.voice && !Assistant.windowed && mode === "compact"
    // уведомление важнее всплывашки; пока открыт плеер/погода — не перебиваем
    readonly property bool notif: Notifs.popup !== null && mode === "compact" && !assist
    property var lastNotif: null
    Connections { target: Notifs; function onPopupChanged() { if (Notifs.popup) root.lastNotif = Notifs.popup; } }
    readonly property bool toast: Activity.shown && mode === "compact" && !notif && !assist
    readonly property bool toastImage: Activity.image !== ""

    strong: mode !== "compact" || toast || notif || assist
    // Вега: весь остров — эффект; слушает и думает — шар, говорит — пилюля (форма перетекает пружинкой)
    readonly property bool assistTalk: Assistant.state === "speaking"
    pill: assist
    targetWidth: assist ? (assistTalk ? 236 : 92) : notif ? 460 : toast ? (toastImage ? 400 : 360)
               : mode === "media" || mode === "weather" ? Math.max(520, compact.implicitWidth + 30)
               : mode === "calendar" ? Math.max(340, compact.implicitWidth + 30) : compact.implicitWidth + 30
    targetHeight: assist ? 92 : notif ? Math.max(72, notifCard.implicitHeight + 28) : toast ? (toastImage ? 84 : 64)
                : mode === "media" ? 184 : mode === "weather" ? 196 : mode === "calendar" ? 328 : Theme.barHeight

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // ── сворачивание с задержкой, чтобы не дёргалось
    Timer { id: collapse; interval: 380; onTriggered: if (!root.hovered) root.mode = "compact" }
    Timer { id: openMedia; interval: 140; onTriggered: if (mediaHover.hovered && root.hasPlayer) root.mode = "media" }
    onHoveredChanged: if (!hovered && mode !== "compact") collapse.restart()

    // ── «подглядывание» при смене трека
    Timer { id: peek; interval: 2600; onTriggered: if (!root.hovered && root.mode === "media") root.mode = "compact" }
    Connections {
        target: root.player
        enabled: Theme.mediaPeek
        function onTrackTitleChanged() {
            if (root.mode === "compact" && !root.hovered && root.hasPlayer && root.player.isPlaying) {
                root.mode = "media";
                peek.restart();
            }
        }
    }

    // ───────────── compact ─────────────
    Row {
        id: compact
        anchors.horizontalCenter: parent.horizontalCenter
        y: (Theme.barHeight - height) / 2
        height: 28
        spacing: 12
        opacity: root.mode === "compact" && !root.toast && !root.notif && !root.assist ? 1 : 0
        scale: root.mode === "compact" && !root.toast && !root.notif && !root.assist ? 1 : 0.86
        visible: opacity > 0
        Behavior on opacity { Anim { kind: "effects" } }
        Behavior on scale { Anim { kind: "fast" } }

        // идёт запись экрана — точка с таймером, клик — стоп
        Rectangle {
            id: recPill
            anchors.verticalCenter: parent.verticalCenter
            visible: Rec.recording || Rec.busy
            width: recRow.implicitWidth + 18; height: 26; radius: 13
            color: recMouse.containsMouse ? Qt.alpha(Theme.error, 0.32) : Qt.alpha(Theme.error, 0.18)
            Behavior on color { ColorAnimation { duration: 160 } }
            Row {
                id: recRow
                anchors.centerIn: parent
                spacing: 6
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10; height: 10; radius: 5; color: Theme.error
                    visible: Rec.recording
                    SequentialAnimation on opacity {
                        running: Rec.recording; loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                    }
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Rec.recording ? Rec.fmt(Rec.elapsed) : "GIF…"
                    size: 13; weight: 700; color: Theme.error; elide: Text.ElideNone
                }
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Rec.recording && recMouse.containsMouse
                    name: "stop_circle"; size: 16; fill: 1; color: Theme.error
                }
            }
            MouseArea { id: recMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (Rec.recording) Rec.stop() }
        }

        // таймер (Countdown): остаток и убывающая заливка, клик — отмена
        Rectangle {
            id: timerPill
            anchors.verticalCenter: parent.verticalCenter
            visible: Countdown.running
            width: timerRow.implicitWidth + 18; height: 26; radius: 13
            color: Qt.alpha(Theme.tertiary, 0.14)
            clip: true
            Rectangle {
                height: parent.height; radius: 13
                width: Math.max(parent.height, parent.width * Countdown.frac)
                color: Qt.alpha(Theme.tertiary, timerMouse.containsMouse ? 0.42 : 0.26)
                Behavior on width { NumberAnimation { duration: 500 } }
                Behavior on color { ColorAnimation { duration: 160 } }
            }
            Row {
                id: timerRow
                anchors.centerIn: parent
                spacing: 5
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: timerMouse.containsMouse ? "close" : "timer"; size: 16; fill: 1; color: Theme.tertiary
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Countdown.fmt(Countdown.left)
                    size: 13; weight: 700; color: Theme.tertiary; elide: Text.ElideNone
                }
            }
            MouseArea { id: timerMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Countdown.stop() }
        }

        // часы + погода (клик → прогноз)
        Row {
            id: clockWeather
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatTime(clock.date, "HH:mm")
                    size: 16
                    weight: 700
                    elide: Text.ElideNone
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: clock.date.toLocaleDateString(I18n.locale, "ddd, d MMM")
                    size: 13
                    weight: 500
                    color: Theme.fgVariant
                    elide: Text.ElideNone
                }
                TapHandler { onTapped: root.mode = root.mode === "calendar" ? "compact" : "calendar" }
            }
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                visible: Weather.ready
                TapHandler { onTapped: root.mode = root.mode === "weather" ? "compact" : "weather" }
                Icon { anchors.verticalCenter: parent.verticalCenter; name: Weather.icon(Weather.code, Weather.isDay); size: 20; fill: 1; color: Theme.tertiary }
                Label { anchors.verticalCenter: parent.verticalCenter; text: Math.round(Weather.temp) + "°"; size: 14; weight: 650; elide: Text.ElideNone }
            }
        }

        // трек
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.hasPlayer
            width: 4; height: 4; radius: 2
            color: Qt.alpha(Theme.fg, 0.35)
        }
        Row {
            id: mediaChip
            anchors.verticalCenter: parent.verticalCenter
            visible: root.hasPlayer
            spacing: 8
            HoverHandler { id: mediaHover; onHoveredChanged: if (hovered) openMedia.restart() }
            TapHandler { onTapped: root.mode = "media" }

            ClippingRectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 24; height: 24
                radius: root.player?.isPlaying ? 7 : 12
                color: Theme.surfaceHigh
                Behavior on radius { Anim { kind: "fast" } }
                Image {
                    anchors.fill: parent
                    source: Players.art(root.player)
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 48; sourceSize.height: 48
                    asynchronous: true
                }
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 260)
                text: (root.player?.trackTitle ?? "") + ((root.player?.trackArtist ?? "") !== "" ? "  ·  " + root.player.trackArtist : "")
                size: 13
                weight: 550
            }
            Equalizer {
                anchors.verticalCenter: parent.verticalCenter
                playing: root.player?.isPlaying ?? false
            }
        }
    }

    // ───────────── ассистент ─────────────
    // весь остров — свет Gemini в стекле (GeminiIsland), без надписей; клик — стоп
    GeminiIsland {
        id: assistBox
        anchors.fill: parent
        st: Assistant.state
        level: Assistant.level
        error: Assistant.error !== "" && !Assistant.busy
        islandRadius: root.radius
        opacity: root.assist ? 1 : 0
        scale: root.assist ? 1 : 0.6
        visible: opacity > 0.01
        Behavior on opacity { Anim { kind: "effects"; duration: root.assist ? 260 : 200 } }
        Behavior on scale { Anim { kind: "spatial" } }
        MouseArea {
            anchors.fill: parent
            enabled: root.assist
            cursorShape: Qt.PointingHandCursor
            onClicked: Assistant.busy ? Assistant.stop() : Assistant.dismiss()
        }
    }

    // ───────────── уведомление ─────────────
    Item {
        anchors.fill: parent
        anchors.margins: 14
        opacity: root.notif ? 1 : 0
        scale: root.notif ? 1 : 0.92
        visible: opacity > 0
        Behavior on opacity { Anim { kind: "effects"; duration: root.notif ? 300 : 150 } }
        Behavior on scale { Anim { kind: "spatial" } }
        HoverHandler { onHoveredChanged: Notifs.hovered = hovered }
        NotifCard {
            id: notifCard
            width: parent.width
            anchors.verticalCenter: parent.verticalCenter
            n: root.lastNotif
        }
    }

    // ───────────── всплывашка ─────────────
    Item {
        id: toastBox
        anchors.fill: parent
        anchors.margins: 12
        opacity: root.toast ? 1 : 0
        scale: root.toast ? 1 : 0.9
        visible: opacity > 0
        Behavior on opacity { Anim { kind: "effects"; duration: root.toast ? 280 : 140 } }
        Behavior on scale { Anim { kind: "spatial" } }

        // слева: превью (скриншот / запись) или иконка в тональном кружке
        ClippingRectangle {
            id: thumb
            visible: root.toastImage
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: 80; height: 54; radius: 14
            color: Theme.surfaceHigh
            Image {
                anchors.fill: parent
                source: Activity.image !== "" ? "file://" + Activity.image : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 240
                asynchronous: true
                cache: false
            }
        }
        Rectangle {
            id: badge
            visible: !root.toastImage
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: 40; height: 40; radius: 14
            color: Theme.primaryContainer
            Icon { anchors.centerIn: parent; name: Activity.icon; size: 22; fill: 1; color: Theme.primaryContainerFg }
        }
        Column {
            anchors { left: root.toastImage ? thumb.right : badge.right; leftMargin: 12; right: trail.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            spacing: 2
            Label { width: parent.width; text: Activity.title; size: 14; weight: 700 }
            Label { width: parent.width; text: Activity.sub; size: 12; weight: 550; color: Theme.fgVariant }
        }
        // справа: полоска уровня или цвета темы
        Item {
            id: trail
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: Activity.value >= 0 ? 120 : Activity.dots.length > 0 ? dotsRow.implicitWidth : 0
            height: 24
            Rectangle {
                visible: Activity.value >= 0
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width; height: 10; radius: 5
                color: Theme.glassChip
                Rectangle {
                    width: Math.max(10, parent.width * Activity.value); height: parent.height; radius: 5
                    color: Theme.primary
                    Behavior on width { Anim { kind: "fast" } }
                }
            }
            Row {
                id: dotsRow
                anchors.verticalCenter: parent.verticalCenter
                visible: Activity.dots.length > 0 && Activity.value < 0
                spacing: -6
                Repeater {
                    model: Activity.dots
                    Rectangle { required property var modelData; width: 22; height: 22; radius: 11; color: modelData; border.width: 2; border.color: Theme.surface }
                }
            }
        }
    }

    // ───────────── expanded ─────────────
    Loader {
        anchors.fill: parent
        active: root.mode === "media" || opacity > 0
        opacity: root.mode === "media" ? 1 : 0
        scale: root.mode === "media" ? 1 : 0.94
        Behavior on opacity { Anim { kind: "effects"; duration: root.mode === "media" ? 320 : 160 } }
        Behavior on scale { Anim { kind: "spatial" } }
        sourceComponent: MediaCard { player: root.player }
    }
    Loader {
        anchors.fill: parent
        active: root.mode === "weather" || opacity > 0
        opacity: root.mode === "weather" ? 1 : 0
        scale: root.mode === "weather" ? 1 : 0.94
        Behavior on opacity { Anim { kind: "effects"; duration: root.mode === "weather" ? 320 : 160 } }
        Behavior on scale { Anim { kind: "spatial" } }
        sourceComponent: WeatherCard { now: clock.date }
    }
    Loader {
        anchors.fill: parent
        active: root.mode === "calendar" || opacity > 0
        opacity: root.mode === "calendar" ? 1 : 0
        scale: root.mode === "calendar" ? 1 : 0.94
        Behavior on opacity { Anim { kind: "effects"; duration: root.mode === "calendar" ? 320 : 160 } }
        Behavior on scale { Anim { kind: "spatial" } }
        sourceComponent: CalendarCard { now: clock.date }
    }
}
