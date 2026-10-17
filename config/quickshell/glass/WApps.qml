import QtQuick
import Quickshell
import Quickshell.Widgets

// Частые приложения: что чаще всего запускаешь из лаунчера (Usage), столько, сколько влезает.
// Пока статистики нет — первые по алфавиту. Клик — запустить.
Item {
    id: root

    readonly property int cell: 84
    readonly property int perRow: Math.max(1, Math.floor((width - 16) / cell))
    readonly property int rowsN: Math.max(1, Math.floor((height - 8) / 96))
    readonly property bool labels: height / rowsN >= 90

    readonly property var apps: {
        const v = DesktopEntries.applications.values;
        const list = [];
        for (let i = 0; i < v.length; i++) if (!v[i].noDisplay) list.push(v[i]);
        list.sort((a, b) => Usage.count(b.id) - Usage.count(a.id) || a.name.toLowerCase().localeCompare(b.name.toLowerCase()));
        return list.slice(0, perRow * rowsN);
    }
    function iconFor(e) {
        const i = e.icon || "";
        if (i.startsWith("/")) return "file://" + i;
        return Quickshell.iconPath(i, true) || Quickshell.iconPath("application-x-executable", true);
    }
    function launch(e) {
        Usage.used(e.id);
        if (e.runInTerminal && e.command && e.command.length) Quickshell.execDetached(["kitty", "--"].concat(e.command));
        else e.execute();
    }

    WidgetSurface { id: ws; anchors.fill: parent; tone: "neutral"; radius: Math.min(44, root.height / 2) }

    Grid {
        anchors.centerIn: parent
        columns: root.perRow
        Repeater {
            model: root.apps
            Item {
                id: app
                required property var modelData
                width: Math.min(root.cell, (root.width - 16) / root.perRow)
                height: (root.height - 8) / root.rowsN
                scale: am.pressed ? 0.9 : 1
                Behavior on scale { Anim { kind: "fast" } }
                Rectangle {
                    anchors.centerIn: icon
                    width: icon.width + 14; height: width; radius: width / 2
                    color: ws.fg
                    opacity: am.containsMouse ? 0.1 : 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }
                IconImage {
                    id: icon
                    anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter; verticalCenterOffset: root.labels ? -10 : 0 }
                    implicitSize: 46
                    source: root.iconFor(app.modelData)
                    asynchronous: true
                }
                Label {
                    visible: root.labels
                    anchors { top: icon.bottom; topMargin: 6; horizontalCenter: parent.horizontalCenter }
                    width: parent.width - 6
                    horizontalAlignment: Text.AlignHCenter
                    text: app.modelData.name
                    size: 11; weight: 600; color: ws.fg
                }
                MouseArea { id: am; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.launch(app.modelData) }
            }
        }
    }
}
