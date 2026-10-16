import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

// Запущенные приложения (по одному значку на приложение).
// Клик — фокус, повторный клик — следующее окно этого приложения.
Island {
    id: root

    readonly property var groups: {
        const map = {};
        const order = [];
        const list = ToplevelManager.toplevels.values;
        for (let i = 0; i < list.length; i++) {
            const t = list[i];
            const key = (t.appId || t.title || "?").toLowerCase();
            if (!map[key]) {
                map[key] = { appId: t.appId, wins: [] };
                order.push(key);
            }
            map[key].wins.push(t);
        }
        return order.map(k => map[k]);
    }
    readonly property int size: 34

    // значок под курсором — для подписи под доком (её рисует BarContent)
    property string hoverName: ""
    property real hoverX: 0
    function nameFor(appId) {
        const id = appId || "";
        const e = DesktopEntries.heuristicLookup(id) ?? DesktopEntries.byId(id.toLowerCase());
        return e?.name ?? id;
    }

    targetWidth: groups.length > 0 ? groups.length * size + (groups.length - 1) * 2 + 12 : 0
    opacity: groups.length > 0 ? 1 : 0
    Behavior on opacity { Anim { kind: "effects" } }

    // ищем иконку: .desktop → имя приложения → варианты в нижнем регистре
    function iconFor(appId) {
        const id = appId || "";
        const low = id.toLowerCase();
        const entry = DesktopEntries.heuristicLookup(id) ?? DesktopEntries.byId(low);
        const icon = entry?.icon ?? "";
        if (icon.startsWith("/")) return "file://" + icon;
        const cands = [icon, id, low, low + "-browser", low + "-desktop", low.split(".").pop()];
        for (let i = 0; i < cands.length; i++)
            if (cands[i] && Quickshell.hasThemeIcon(cands[i])) return Quickshell.iconPath(cands[i]);
        return Quickshell.iconPath("application-x-executable");
    }

    Row {
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: root.groups

            Item {
                id: app
                required property var modelData
                readonly property bool active: modelData.wins.some(w => w.activated)
                width: root.size
                height: root.size

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: app.active ? 12 : height / 2
                    color: app.active ? Qt.alpha(Theme.primary, 0.22)
                         : appMouse.containsMouse ? Theme.glassChip : "transparent"
                    Behavior on radius { Anim { kind: "fast" } }
                    Behavior on color { ColorAnimation { duration: 200 } }
                }

                IconImage {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -1
                    implicitSize: 22
                    source: root.iconFor(app.modelData.appId)
                    scale: appMouse.pressed ? 0.82 : appMouse.containsMouse ? 1.14 : 1
                    Behavior on scale { Anim { kind: "fast" } }
                }

                // индикатор: длинная черта у активного, точки по числу окон у остальных
                Row {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 1 }
                    spacing: 2
                    Repeater {
                        model: Math.min(3, app.modelData.wins.length)
                        Rectangle {
                            width: app.active ? 10 : 3
                            height: 3
                            radius: 1.5
                            color: app.active ? Theme.primary : Qt.alpha(Theme.fg, 0.55)
                            Behavior on width { Anim { kind: "fast" } }
                        }
                    }
                }

                MouseArea {
                    id: appMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: {
                        const n = root.nameFor(app.modelData.appId);
                        if (containsMouse) { root.hoverX = app.mapToItem(root, app.width / 2, 0).x; root.hoverName = n; }
                        else if (root.hoverName === n) root.hoverName = "";
                    }
                    onClicked: mouse => {
                        const wins = app.modelData.wins;
                        if (mouse.button === Qt.MiddleButton) {
                            wins[0].close();
                            return;
                        }
                        const cur = wins.findIndex(w => w.activated);
                        wins[(cur + 1) % wins.length].activate();
                    }
                }
            }
        }
    }
}
