import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Раскладка. Клик — переключить. Буквы «пролистываются» при смене.
Island {
    id: root
    property string layout: "EN"
    property string shown: layout
    targetWidth: 50

    function code(name) {
        const n = (name || "").toLowerCase();
        if (n.startsWith("english")) return "EN";
        if (n.startsWith("russian")) return "RU";
        if (n.startsWith("bulgarian")) return "BG";
        if (n.startsWith("ukrainian")) return "UA";
        return (name || "??").slice(0, 2).toUpperCase();
    }

    Process {
        command: ["hyprctl", "devices", "-j"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const kbs = JSON.parse(text).keyboards;
                    const kb = kbs.find(k => k.main) ?? kbs[0];
                    if (kb) root.layout = root.code(kb.active_keymap);
                } catch (e) {}
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (ev.name !== "activelayout") return;
            // данные: «клавиатура,раскладка» (в названии раскладки тоже бывают запятые).
            // Виртуальные клавиатуры (wtype при вставке эмодзи и т.п.) — не наша раскладка.
            const i = ev.data.indexOf(",");
            const kb = ev.data.slice(0, i), name = ev.data.slice(i + 1);
            if (i < 0 || kb.startsWith("hl-virtual-keyboard") || name === "" || name === "none" || name === "error") return;
            root.layout = root.code(name);
        }
    }

    onLayoutChanged: if (layout !== shown) swap.restart()

    SequentialAnimation {
        id: swap
        ParallelAnimation {
            NumberAnimation { target: txt; property: "y"; to: -12; duration: 120; easing.type: Easing.InCubic }
            NumberAnimation { target: txt; property: "opacity"; to: 0; duration: 120 }
        }
        ScriptAction { script: { root.shown = root.layout; txt.y = 12; } }
        ParallelAnimation {
            Anim { target: txt; property: "y"; to: 0; kind: "fast" }
            NumberAnimation { target: txt; property: "opacity"; to: 1; duration: 160 }
        }
    }

    Item {
        anchors.centerIn: parent
        width: 30
        height: 24
        clip: true
        Label {
            id: txt
            width: parent.width
            height: parent.height
            horizontalAlignment: Text.AlignHCenter
            text: root.shown
            size: 13
            weight: 700
            elide: Text.ElideNone
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", "next"])
    }
}
