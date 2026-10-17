import QtQuick
import Quickshell
import Quickshell.Hyprland

// Воркспейсы 1..N. Активный — «жидкая» пилюля primary, которая
// тянется передним краем и догоняет задним (как в M3 Expressive).
Island {
    id: root

    readonly property int count: Theme.workspaceCount
    readonly property int cell: 30
    readonly property int activeId: Hyprland.focusedMonitor?.activeWorkspace?.id ?? 1
    readonly property bool inRange: activeId >= 1 && activeId <= count
    readonly property int target: Math.max(0, Math.min(count - 1, activeId - 1))

    targetWidth: count * cell + 10 + (inRange ? 0 : cell + 4)

    function occupied(id) {
        const list = Hyprland.workspaces.values;
        for (let i = 0; i < list.length; i++)
            if (list[i].id === id) return list[i].toplevels.values.length > 0;
        return false;
    }

    // края индикатора анимируются с разной скоростью → эффект растяжения
    property bool movingRight: true
    property int prev: target
    onTargetChanged: {
        movingRight = target > prev;
        prev = target;
        leftEdge = target;
        rightEdge = target;
    }
    property real leftEdge: target
    property real rightEdge: target
    Behavior on leftEdge { Anim { kind: root.movingRight ? "spatial" : "fast"; duration: root.movingRight ? 520 : 300 } }
    Behavior on rightEdge { Anim { kind: root.movingRight ? "fast" : "spatial"; duration: root.movingRight ? 300 : 520 } }

    Item {
        id: track
        x: 5
        anchors.verticalCenter: parent.verticalCenter
        width: root.count * root.cell
        height: root.cell

        // точки занятых воркспейсов
        Repeater {
            model: root.count
            Rectangle {
                required property int index
                readonly property bool busy: root.occupied(index + 1)
                x: index * root.cell + 3
                y: 3
                width: root.cell - 6
                height: root.cell - 6
                radius: height / 2
                color: Theme.glassChip
                opacity: busy ? 1 : 0
                scale: busy ? 1 : 0.4
                Behavior on opacity { Anim { kind: "effects" } }
                Behavior on scale { Anim { kind: "fast" } }
            }
        }

        // активная пилюля
        Rectangle {
            x: root.leftEdge * root.cell + 2
            y: 2
            width: (root.rightEdge - root.leftEdge) * root.cell + root.cell - 4
            height: root.cell - 4
            radius: height / 2
            color: Theme.primary
            opacity: root.inRange ? 1 : 0
            Behavior on opacity { Anim { kind: "effects" } }
            Behavior on color { ColorAnimation { duration: 350 } }
        }

        Repeater {
            model: root.count
            Item {
                id: cellItem
                required property int index
                readonly property int wsId: index + 1
                readonly property bool active: root.activeId === wsId
                readonly property bool busy: root.occupied(wsId)
                x: index * root.cell
                width: root.cell
                height: root.cell

                Label {
                    anchors.centerIn: parent
                    text: cellItem.wsId
                    size: 13
                    weight: cellItem.active ? 700 : 550
                    color: cellItem.active ? Theme.primaryFg
                         : cellItem.busy ? Theme.fg : Qt.alpha(Theme.fg, 0.42)
                    scale: cellItem.active ? 1.08 : 1
                    Behavior on scale { Anim { kind: "fast" } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hypr.workspace(cellItem.wsId)
                }
            }
        }
    }

    // если ты на воркспейсе > N — показываем его номер отдельной пилюлей
    Rectangle {
        anchors { left: track.right; leftMargin: 4; verticalCenter: parent.verticalCenter }
        width: root.cell - 4
        height: root.cell - 4
        radius: height / 2
        color: Theme.primary
        opacity: root.inRange ? 0 : 1
        scale: root.inRange ? 0.5 : 1
        Behavior on opacity { Anim { kind: "effects" } }
        Behavior on scale { Anim { kind: "fast" } }
        Label {
            anchors.centerIn: parent
            text: root.activeId
            size: 13
            weight: 700
            color: Theme.primaryFg
        }
    }

    WheelHandler {
        property real acc: 0
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: ev => {
            acc += ev.angleDelta.y;
            if (Math.abs(acc) >= 120) {
                Hypr.workspace(acc > 0 ? "e-1" : "e+1");
                acc = 0;
            }
        }
    }
}
