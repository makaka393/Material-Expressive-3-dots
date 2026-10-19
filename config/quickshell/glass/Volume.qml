import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Громкость.
//  колесо — ±5%, клик по иконке — mute
//  при изменении громкости остров вытягивается и показывает слайдер
//  при наведении — ещё и раскрывается вниз со списком устройств вывода
Island {
    id: root
    objectName: "volume"

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real vol: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    property bool osd: false
    property bool armed: false            // не показываем OSD при старте
    property bool menu: false             // список устройств
    readonly property bool open: hovered || osd || slider.dragging || menu

    // аппаратные выходы (без программ и loopback)
    readonly property var sinks: Pipewire.nodes.values.filter(n =>
        n.isSink && !n.isStream && n.audio && !(n.description || n.name || "").toLowerCase().includes("loopback"))

    strong: menu
    targetWidth: menu ? 300 : open ? 230 : 86
    targetHeight: menu ? Theme.barHeight + 10 + sinks.length * 40 + 8 : Theme.barHeight

    PwObjectTracker { objects: [root.sink] }

    Timer { interval: 1500; running: true; onTriggered: root.armed = true }
    Timer { id: osdTimer; interval: 1400; onTriggered: root.osd = false }
    Timer { id: menuOpen; interval: 220; onTriggered: if (root.hovered) root.menu = true }
    Timer { id: menuClose; interval: 420; onTriggered: if (!root.hovered) root.menu = false }
    onHoveredChanged: hovered ? menuOpen.restart() : menuClose.restart()
    // громкость колёсиком/клавишами — показываем в центральном острове (Dynamic Island)
    onVolChanged: if (armed && !hovered) Activity.volume(root.vol, root.muted)
    onMutedChanged: if (armed && !hovered) Activity.volume(root.vol, root.muted)

    // громкость меняем через wpctl — так же, как бинды Hyprland
    property int lastSent: -1
    function setVol(v) {
        const pct = Math.round(Math.max(0, Math.min(1, v)) * 100);
        if (pct === lastSent) return;
        lastSent = pct;
        if (muted) Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"]);
        Quickshell.execDetached(["wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", pct + "%"]);
    }
    function toggleMute() {
        Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
    }
    Timer { interval: 300; running: root.lastSent >= 0; onTriggered: root.lastSent = -1 }

    function prettyName(n) {
        let s = n.nickname || n.description || n.name || "?";
        s = s.replace(/ (Analog|Digital) Stereo/, "")
             .replace(/Family 17h \(Models 00h-0fh\) HD Audio Controller/, I18n.t("Колонки (разъём)", "Speakers (jack)"))
             .replace(/TU106 High Definition Audio Controller/, I18n.t("Монитор", "Monitor"))
             .replace(/ Gaming Headset/, "");
        return s;
    }
    function deviceIcon(n) {
        const s = ((n.description || "") + " " + (n.name || "")).toLowerCase();
        if (s.includes("headset") || s.includes("headphone") || s.includes("bluez")) return "headphones";
        if (s.includes("hdmi") || s.includes("displayport") || s.includes("tu106")) return "tv";
        return "speaker";
    }

    readonly property string iconName: muted || vol <= 0.001 ? "volume_off"
                                      : vol < 0.34 ? "volume_mute"
                                      : vol < 0.67 ? "volume_down" : "volume_up"

    // ───────── строка в баре ─────────
    Item {
        id: topRow
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: Theme.barHeight

        IconButton {
            id: btn
            anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
            size: 32
            icon: root.iconName
            iconSize: 20
            color: root.muted ? Theme.error : Theme.fg
            onClicked: root.toggleMute()
        }

        // M3 Expressive слайдер: толстый трек, разрыв и «ручка»-черта
        Item {
            id: slider
            property bool dragging: area.pressed
            anchors { left: btn.right; leftMargin: 6; right: pct.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            height: 20
            opacity: root.open ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { Anim { kind: "effects" } }

            readonly property real v: root.muted ? 0 : root.vol
            readonly property real hx: Math.max(2, Math.min(width - 2, v * width))

            Rectangle {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: Math.max(0, slider.hx - 4)
                height: 14
                radius: 7
                color: Theme.primary
                topRightRadius: 3
                bottomRightRadius: 3
            }
            Rectangle {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: Math.max(0, slider.width - slider.hx - 4)
                height: 14
                radius: 7
                color: Qt.alpha(Theme.fg, 0.16)
                topLeftRadius: 3
                bottomLeftRadius: 3
            }
            Rectangle {
                x: slider.hx - 1.5
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: area.pressed ? 24 : 20
                radius: 1.5
                color: Theme.primary
                Behavior on height { Anim { kind: "fast" } }
            }
            MouseArea {
                id: area
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                function apply(x) { root.setVol((x - 6) / slider.width); }
                onPressed: m => apply(m.x)
                onPositionChanged: m => { if (pressed) apply(m.x); }
            }
        }

        Label {
            id: pct
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            width: 36
            horizontalAlignment: Text.AlignRight
            text: root.muted ? I18n.t("выкл", "off") : Math.round(root.vol * 100) + "%"
            size: 13
            weight: 650
            elide: Text.ElideNone
        }

        WheelHandler {
            property real acc: 0
            onWheel: ev => {
                acc += ev.angleDelta.y;
                if (Math.abs(acc) >= 120) {
                    root.setVol(Math.round(root.vol * 20) / 20 + (acc > 0 ? 0.05 : -0.05));
                    acc = 0;
                }
            }
        }
    }

    // ───────── устройства вывода ─────────
    Column {
        anchors { top: topRow.bottom; topMargin: 6; left: parent.left; right: parent.right; leftMargin: 6; rightMargin: 6 }
        spacing: 2
        opacity: root.menu ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { Anim { kind: "effects"; duration: root.menu ? 300 : 120 } }

        Repeater {
            model: root.sinks

            Item {
                id: dev
                required property var modelData
                required property int index
                readonly property bool current: root.sink !== null && root.sink.id === modelData.id
                width: parent.width
                height: 38

                property real yOff: root.menu ? 0 : -6 * (index + 1)
                Behavior on yOff { Anim { kind: "fast" } }
                transform: Translate { y: dev.yOff }

                Rectangle {
                    anchors.fill: parent
                    radius: dev.current ? 14 : height / 2
                    color: dev.current ? Qt.alpha(Theme.primary, 0.22)
                         : devMouse.containsMouse ? Theme.glassChip : "transparent"
                    Behavior on radius { Anim { kind: "fast" } }
                    Behavior on color { ColorAnimation { duration: 180 } }
                }
                Icon {
                    id: devIcon
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    name: root.deviceIcon(dev.modelData)
                    size: 19
                    fill: dev.current ? 1 : 0
                    color: dev.current ? Theme.primary : Theme.fg
                }
                Label {
                    anchors { left: devIcon.right; leftMargin: 10; right: check.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    text: root.prettyName(dev.modelData)
                    size: 13
                    weight: dev.current ? 700 : 500
                    color: dev.current ? Theme.primary : Theme.fg
                }
                Icon {
                    id: check
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    name: "check_circle"
                    size: 18
                    fill: 1
                    color: Theme.primaryText
                    opacity: dev.current ? 1 : 0
                    scale: dev.current ? 1 : 0.4
                    Behavior on opacity { Anim { kind: "effects" } }
                    Behavior on scale { Anim { kind: "fast" } }
                }
                MouseArea {
                    id: devMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // делаем выход основным и переносим на него всё, что уже играет
                    onClicked: Quickshell.execDetached(["sh", "-c",
                        'pactl set-default-sink "$1"; for i in $(pactl list short sink-inputs | cut -f1); do pactl move-sink-input "$i" "$1"; done',
                        "_", dev.modelData.name])
                }
            }
        }
    }
}
