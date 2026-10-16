import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io

// То, что видно на экране блокировки: обои рабочего стола (для видео — сам ролик), часы,
// погода и ввод пароля. Пароль рисуется фигурами Material 3 Expressive, как на Pixel.
//   покой — чёткие обои и крупные часы;
//   ввод  — любое нажатие: обои размываются, часы уезжают вверх, появляется поле пароля.
Item {
    id: s

    property bool preview: false
    property bool active: false
    readonly property real k: Math.max(0.6, height / 1440)

    // ── обои: настоящий файл и картинка для фона (у видео — его кадр)
    property string wallFile: ""
    property string frameFile: ""
    readonly property bool isVideo: /\.(mp4|webm|mkv|mov)$/i.test(wallFile)
    Process {
        running: true
        command: ["sh", "-c", 'w=$(readlink -f "$HOME/.cache/matugen/wallpaper"); echo "$w"; '
            + 'case "$w" in *.[mM][pP]4|*.[wW][eE][bB][mM]|*.[mM][kK][vV]|*.[mM][oO][vV]|*.[gG][iI][fF]|*.[wW][eE][bB][pP]) echo "$HOME/.cache/matugen/frame.png";; *) echo "$w";; esac']
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                s.wallFile = l[0] || "";
                s.frameFile = l[1] || "";
            }
        }
    }

    // появление
    property real p: 0
    NumberAnimation on p { from: 0; to: 1; duration: 1500; running: true }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // ── ввод: невидимое поле собирает текст, фигуры рисуются по его длине
    function wake() { s.active = true; idle.restart(); }
    Timer { id: idle; interval: 25000; onTriggered: if (Locker.text === "" && !Locker.checking) s.active = false }
    TextInput {
        id: input
        width: 1; height: 1
        opacity: 0
        focus: true
        echoMode: TextInput.Password
        enabled: !Locker.checking
        onTextChanged: { if (Locker.text !== text) Locker.text = text; if (text !== "") s.wake(); }
        Keys.onPressed: ev => {
            if (ev.key === Qt.Key_Escape) {
                if (text !== "") text = "";
                else if (s.active) s.active = false;
                else if (s.preview) Locker.unlock();
                ev.accepted = true;
                return;
            }
            s.wake();
            if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) { Locker.submit(); ev.accepted = true; }
        }
    }
    Connections {
        target: Locker
        function onTextChanged() { if (input.text !== Locker.text) input.text = Locker.text; }
        function onFailedChanged() { if (Locker.failed) { shake.restart(); s.wake(); } }
        function onCheckingChanged() { if (!Locker.checking) input.forceActiveFocus(); }
    }
    Component.onCompleted: input.forceActiveFocus()
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPressed: { s.wake(); input.forceActiveFocus(); }
    }

    // ── фон
    Item {
        id: bg
        anchors.fill: parent
        layer.enabled: true
        visible: false
        Rectangle { anchors.fill: parent; color: Theme.surfaceLowest }
        Image {
            anchors.fill: parent
            source: s.frameFile !== "" ? "file://" + s.frameFile : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: s.width
            sourceSize.height: s.height
        }
        Loader {
            id: video
            anchors.fill: parent
            active: s.isVideo
            source: "VideoBg.qml"
            onLoaded: item.source = "file://" + s.wallFile
            opacity: item && item.playing ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 600 } }
        }
    }
    MultiEffect {
        anchors.fill: parent
        source: bg
        blurEnabled: true
        blurMax: 64
        blur: s.active ? 0.9 : 0
        saturation: s.active ? 0.12 : 0
        Behavior on blur { Anim { kind: "effects"; duration: 450 } }
    }
    // затемнение для читаемости: снизу сильнее, в режиме ввода — везде
    Rectangle {
        anchors.fill: parent
        opacity: Math.min(1, s.p * 2)
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.alpha(Theme.surfaceLowest, s.active ? 0.40 : 0.30) }
            GradientStop { position: 0.55; color: Qt.alpha(Theme.surfaceLowest, s.active ? 0.42 : 0.12) }
            GradientStop { position: 1.0; color: Qt.alpha(Theme.surfaceLowest, s.active ? 0.64 : 0.46) }
        }
    }

    // ── часы (тот же циферблат, что выбран для AOD) и погода
    Column {
        id: top
        anchors.horizontalCenter: parent.horizontalCenter
        y: s.height * (s.active ? 0.07 : 0.15)
        spacing: 26 * s.k
        Behavior on y { Anim { kind: "spatial" } }
        // мягкая тень: часы читаются и на светлых обоях
        layer.enabled: true
        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "black"; shadowOpacity: 0.5; shadowBlur: 0.9; shadowVerticalOffset: 3; autoPaddingEnabled: true }

        AodClock {
            anchors.horizontalCenter: parent.horizontalCenter
            style: Config.aodFace
            showDate: false                 // дата — в пилюле ниже: там она читается на любых обоях
            now: clock.date
            // уменьшаем масштабом, а не размером шрифта: иначе каждый кадр анимации — новый шрифт
            transformOrigin: Item.Top
            scale: s.active ? 0.6 : 1
            Behavior on scale { Anim { kind: "spatial" } }
            k: s.k * 1.15
            p: s.p
        }
        Rectangle {
            id: weatherPill
            anchors.horizontalCenter: parent.horizontalCenter
            width: wRow.implicitWidth + 40 * s.k
            height: 54 * s.k; radius: height / 2
            color: Qt.alpha(Theme.surfaceLowest, 0.38)
            border.width: 1; border.color: Qt.alpha(Theme.fg, 0.10)
            opacity: (s.active ? 0 : 1) * Math.min(1, Math.max(0, (s.p - 0.4) * 3))
            Behavior on opacity { Anim { kind: "effects" } }
            Row {
                id: wRow
                anchors.centerIn: parent
                spacing: 10 * s.k
                Label { anchors.verticalCenter: parent.verticalCenter; text: I18n.longDate(clock.date); size: 18 * s.k; weight: 650; elide: Text.ElideNone }
                Rectangle { anchors.verticalCenter: parent.verticalCenter; visible: Weather.ready; width: 4 * s.k; height: width; radius: width / 2; color: Qt.alpha(Theme.fg, 0.4) }
                Icon { anchors.verticalCenter: parent.verticalCenter; visible: Weather.ready; name: Weather.icon(Weather.code, Weather.isDay); size: 26 * s.k; fill: 1; color: Theme.tertiary }
                Label { anchors.verticalCenter: parent.verticalCenter; visible: Weather.ready; text: Math.round(Weather.temp) + "°"; size: 18 * s.k; weight: 650; elide: Text.ElideNone }
                Label { anchors.verticalCenter: parent.verticalCenter; visible: Weather.ready; text: Weather.describe(Weather.code); size: 16 * s.k; color: Theme.fgVariant; elide: Text.ElideNone }
            }
        }
    }

    // что играет и сколько уведомлений ждёт (без их текста — экран заперт)
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: top.y + top.height + 16 * s.k
        spacing: 10 * s.k
        opacity: (s.active ? 0 : 1) * Math.min(1, Math.max(0, (s.p - 0.5) * 3))
        visible: opacity > 0
        Behavior on opacity { Anim { kind: "effects" } }

        Rectangle {
            id: musicPill
            readonly property var pl: Players.active
            readonly property bool has: !!pl && (pl.trackTitle ?? "") !== ""
            visible: has
            width: musicRow.implicitWidth + 36 * s.k; height: 46 * s.k; radius: height / 2
            color: Qt.alpha(Theme.surfaceLowest, 0.38)
            border.width: 1; border.color: Qt.alpha(Theme.fg, 0.10)
            Row {
                id: musicRow
                anchors.centerIn: parent
                spacing: 8 * s.k
                Icon { anchors.verticalCenter: parent.verticalCenter; name: musicPill.has && musicPill.pl.isPlaying ? "music_note" : "pause"; size: 22 * s.k; fill: 1; color: Theme.primary }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, 460 * s.k)
                    text: musicPill.has ? musicPill.pl.trackTitle + ((musicPill.pl.trackArtist || "") !== "" ? "  ·  " + musicPill.pl.trackArtist : "") : ""
                    size: 16 * s.k; weight: 600
                }
            }
        }
        Rectangle {
            visible: Notifs.count > 0
            width: notifRow.implicitWidth + 32 * s.k; height: 46 * s.k; radius: height / 2
            color: Qt.alpha(Theme.surfaceLowest, 0.38)
            border.width: 1; border.color: Qt.alpha(Theme.fg, 0.10)
            Row {
                id: notifRow
                anchors.centerIn: parent
                spacing: 6 * s.k
                Icon { anchors.verticalCenter: parent.verticalCenter; name: "notifications"; size: 22 * s.k; fill: 1; color: Theme.tertiary }
                Label { anchors.verticalCenter: parent.verticalCenter; text: Notifs.count; size: 16 * s.k; weight: 700; elide: Text.ElideNone }
            }
        }
    }

    // ── вход
    Column {
        id: login
        anchors.horizontalCenter: parent.horizontalCenter
        y: s.height * (s.active ? 0.56 : 0.64)
        spacing: 22 * s.k
        opacity: s.active ? 1 : 0
        visible: opacity > 0
        Behavior on y { Anim { kind: "spatial" } }
        Behavior on opacity { Anim { kind: "effects" } }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10 * s.k
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 44 * s.k; height: width; radius: width / 2
                color: Theme.primaryContainer
                Icon { anchors.centerIn: parent; name: "person"; size: 26 * s.k; fill: 1; color: Theme.primaryContainerFg }
            }
            Label { anchors.verticalCenter: parent.verticalCenter; text: Quickshell.env("USER") || ""; size: 22 * s.k; weight: 650; elide: Text.ElideNone }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10 * s.k

            Item {
                id: field
                width: 470 * s.k; height: 66 * s.k
                transform: Translate { id: shakeX }
                SequentialAnimation {
                    id: shake
                    NumberAnimation { target: shakeX; property: "x"; to: -16 * s.k; duration: 55 }
                    NumberAnimation { target: shakeX; property: "x"; to: 14 * s.k; duration: 70 }
                    NumberAnimation { target: shakeX; property: "x"; to: -9 * s.k; duration: 70 }
                    NumberAnimation { target: shakeX; property: "x"; to: 6 * s.k; duration: 70 }
                    NumberAnimation { target: shakeX; property: "x"; to: 0; duration: 90; easing.type: Easing.OutCubic }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Locker.failed ? Qt.alpha(Theme.error, 0.22) : Qt.alpha(Theme.frost, 0.62)
                    border.width: 1
                    border.color: Locker.failed ? Qt.alpha(Theme.error, 0.7) : Qt.alpha(Theme.fg, 0.16)
                    Behavior on color { ColorAnimation { duration: 220 } }
                    Behavior on border.color { ColorAnimation { duration: 220 } }
                }
                Icon {
                    id: lockIcon
                    anchors { left: parent.left; leftMargin: 22 * s.k; verticalCenter: parent.verticalCenter }
                    name: Locker.checking ? "progress_activity" : Locker.failed ? "lock_reset" : "lock"
                    size: 26 * s.k; fill: 1
                    color: Locker.failed ? Theme.error : Theme.fgVariant
                    RotationAnimation on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: Locker.checking }
                    onNameChanged: if (!Locker.checking) rotation = 0
                }
                PasswordShapes {
                    anchors { left: lockIcon.right; leftMargin: 14 * s.k; right: go.left; rightMargin: 10 * s.k; verticalCenter: parent.verticalCenter }
                    height: 40 * s.k
                    count: Locker.text.length
                    size: 26 * s.k
                    gap: 6 * s.k
                    color: Theme.fg
                    accent: Theme.primary
                    errorColor: Theme.error
                    busy: Locker.checking
                    failed: Locker.failed
                    caret: Locker.text.length > 0
                }
                Label {
                    anchors { left: lockIcon.right; leftMargin: 14 * s.k; verticalCenter: parent.verticalCenter }
                    opacity: Locker.text === "" ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Locker.text === "" ? 380 : 60 } }
                    text: Locker.failed ? I18n.t("Неверный пароль", "Wrong password")
                        : Locker.checking ? I18n.t("Проверяю…", "Checking…") : I18n.t("Пароль", "Password")
                    size: 19 * s.k; weight: 550
                    color: Locker.failed ? Theme.error : Theme.fgVariant
                    elide: Text.ElideNone
                }
                Rectangle {
                    id: go
                    anchors { right: parent.right; rightMargin: 9 * s.k; verticalCenter: parent.verticalCenter }
                    width: 48 * s.k; height: width
                    radius: goMouse.pressed ? 14 * s.k : width / 2
                    color: Locker.text !== "" ? Theme.primary : Qt.alpha(Theme.fg, 0.10)
                    Behavior on radius { Anim { kind: "fast" } }
                    Behavior on color { ColorAnimation { duration: 200 } }
                    Icon { anchors.centerIn: parent; name: "arrow_forward"; size: 24 * s.k; color: Locker.text !== "" ? Theme.primaryFg : Theme.fgVariant }
                    MouseArea { id: goMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { Locker.submit(); input.forceActiveFocus(); } }
                }
            }
            // раскладка — пароль не угадаешь, если не знаешь, на каком языке печатаешь
            Lang { anchors.verticalCenter: parent.verticalCenter }
        }
    }

    // подсказка внизу
    Label {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 56 * s.k }
        text: s.active ? I18n.t("Enter — войти   ·   Esc — назад", "Enter — unlock   ·   Esc — back")
                       : I18n.t("Нажми любую клавишу", "Press any key")
        size: 16 * s.k; weight: 500
        color: Qt.alpha(Theme.fg, 0.72)
        opacity: Math.min(1, Math.max(0, (s.p - 0.6) * 3))
        elide: Text.ElideNone
    }
}
