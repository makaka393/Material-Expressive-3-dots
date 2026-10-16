import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray

// Системный трей: значки приложений в фоне (сеть, Steam, KDE Connect…).
// Левый клик — действие приложения, правый — его меню, средний — второе действие,
// колёсико передаётся приложению (громкость и т.п.). Без значков остров не показывается.
Island {
    id: root

    property var barWindow: null
    readonly property var items: SystemTray.items.values
    readonly property int cell: 30

    visible: items.length > 0
    targetWidth: items.length * cell + 12

    Row {
        anchors.centerIn: parent

        Repeater {
            model: root.items

            Item {
                id: it
                required property var modelData
                width: root.cell
                height: root.cell

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: height / 2
                    color: itMouse.containsMouse ? Theme.glassChip : "transparent"
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
                IconImage {
                    anchors.centerIn: parent
                    implicitSize: 18
                    source: it.modelData.icon
                    scale: itMouse.pressed ? 0.82 : itMouse.containsMouse ? 1.14 : 1
                    Behavior on scale { Anim { kind: "fast" } }
                }
                MouseArea {
                    id: itMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ev => {
                        const d = it.modelData;
                        if (ev.button === Qt.MiddleButton) { d.secondaryActivate(); return; }
                        if (ev.button === Qt.RightButton || d.onlyMenu) {
                            if (!d.hasMenu || !root.barWindow) return;
                            const p = it.mapToItem(null, 0, it.height + 6);
                            d.display(root.barWindow, Math.round(p.x), Math.round(p.y));
                            return;
                        }
                        d.activate();
                    }
                    onWheel: w => it.modelData.scroll(w.angleDelta.y, false)
                }
            }
        }
    }
}
