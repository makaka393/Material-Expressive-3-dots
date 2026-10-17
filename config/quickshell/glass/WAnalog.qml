import QtQuick

// Стрелочные часы на фигуре Material 3 (как циферблат Pixel). Форма — в меню по правому клику
// («Другая форма»), запоминается в настройках виджета. Без секундной стрелки: обновляется раз в минуту.
Item {
    id: root
    property date now: new Date()
    property string wid: ""
    property var cfg: ({})

    readonly property var shapes: ["cookie", "clover", "squircle", "hex", "circle"]
    readonly property string shape: shapes.indexOf(cfg.shape) >= 0 ? cfg.shape : "cookie"
    Connections {
        target: Widgets
        function onCommand(wid, name) {
            if (wid === root.wid && name === "shape")
                Widgets.setExtra(root.wid, "shape", root.shapes[(root.shapes.indexOf(root.shape) + 1) % root.shapes.length]);
        }
    }

    readonly property real d: Math.min(width, height)
    readonly property real hAngle: (now.getHours() % 12) * 30 + now.getMinutes() * 0.5
    readonly property real mAngle: now.getMinutes() * 6

    WidgetSurface { id: ws; anchors.fill: parent; tone: "secondary"; plain: true }

    Item {
        id: dial
        anchors.centerIn: parent
        width: root.d; height: root.d

        // подложка-фигура в цвет и прозрачность темы
        AodShape {
            anchors.fill: parent
            kind: root.shape
            lobes: 12
            color: Theme.m3 ? Qt.alpha(ws.container, Math.max(0.02, Theme.m3Opacity))
                            : Qt.alpha(Qt.tint(Theme.frost, Qt.alpha(ws.container, 0.5)), Theme.glass.a)
        }
        // часовые точки
        Repeater {
            model: 12
            Rectangle {
                required property int index
                readonly property real a: index / 12 * Math.PI * 2
                readonly property real r: root.d * 0.36
                width: (index % 3 === 0 ? 0.045 : 0.025) * root.d; height: width; radius: width / 2
                x: root.d / 2 + r * Math.sin(a) - width / 2
                y: root.d / 2 - r * Math.cos(a) - height / 2
                color: index % 3 === 0 ? ws.accent : Qt.alpha(ws.fg, 0.45)
            }
        }
        // часовая
        Rectangle {
            readonly property real len: root.d * 0.25
            width: root.d * 0.075; height: len + width / 2; radius: width / 2
            x: root.d / 2 - width / 2; y: root.d / 2 - len
            color: ws.accent
            antialiasing: true
            transform: Rotation {
                origin.x: root.d * 0.0375; origin.y: root.d * 0.25
                angle: root.hAngle
                Behavior on angle { RotationAnimation { duration: 700; direction: RotationAnimation.Clockwise; easing.type: Easing.OutBack } }
            }
        }
        // минутная
        Rectangle {
            readonly property real len: root.d * 0.36
            width: root.d * 0.04; height: len + width / 2; radius: width / 2
            x: root.d / 2 - width / 2; y: root.d / 2 - len
            color: ws.fg
            antialiasing: true
            transform: Rotation {
                origin.x: root.d * 0.02; origin.y: root.d * 0.36
                angle: root.mAngle
                Behavior on angle { RotationAnimation { duration: 700; direction: RotationAnimation.Clockwise; easing.type: Easing.OutBack } }
            }
        }
        Rectangle {
            anchors.centerIn: parent
            width: root.d * 0.085; height: width; radius: width / 2
            color: ws.container
            border.width: root.d * 0.022; border.color: ws.accent
        }
    }
}
