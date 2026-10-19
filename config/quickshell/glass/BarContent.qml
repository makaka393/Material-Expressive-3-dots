import QtQuick

Item {
    id: root
    property var barWindow: null
    property var shotView: null            // снимок экрана для линзы Веги (Bar.qml)
    property var shotTex: null
    readonly property alias leftGroup: left
    readonly property alias centerGroup: center
    readonly property alias rightGroup: right

    // под AOD бар не должен просвечивать сквозь затемнение
    readonly property bool underAod: Config.aodScreen !== "" && barWindow !== null && barWindow.screen.name === Config.aodScreen
    opacity: underAod ? 0 : 1
    Behavior on opacity { NumberAnimation { duration: root.underAod ? 900 : 280; easing.type: Easing.OutCubic } }

    Row {
        id: left
        anchors { top: parent.top; left: parent.left; topMargin: Theme.outer; leftMargin: Theme.outer }
        spacing: Theme.gap
        Workspaces {}
        Apps { id: apps }
    }

    // подпись под значком в доке: название приложения
    Item {
        id: tip
        property string shown: ""
        readonly property bool on: apps.hoverName !== ""
        Connections { target: apps; function onHoverNameChanged() { if (apps.hoverName !== "") tip.shown = apps.hoverName; } }
        x: Math.max(Theme.outer, left.x + apps.x + apps.hoverX - width / 2)
        y: Theme.outer + Theme.barHeight + (on ? 6 : 0)
        width: tipLabel.implicitWidth + 24
        height: 30
        opacity: on ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { Anim { kind: "effects" } }
        Behavior on y { Anim { kind: "fast" } }
        Behavior on x { enabled: tip.opacity > 0.6; Anim { kind: "fast" } }
        GlassSurface { anchors.fill: parent; radius: 15; strong: true }
        Label { id: tipLabel; anchors.centerIn: parent; text: tip.shown; size: 13; weight: 600; elide: Text.ElideNone }
    }

    DynamicIsland {
        id: center
        anchors { top: parent.top; topMargin: Theme.outer; horizontalCenter: parent.horizontalCenter }
        shotView: root.shotView
        shotTex: root.shotTex
        screenSize: root.barWindow && root.barWindow.screen ? Qt.vector2d(root.barWindow.screen.width, root.barWindow.screen.height) : Qt.vector2d(1, 1)
    }

    Row {
        id: right
        anchors { top: parent.top; right: parent.right; topMargin: Theme.outer; rightMargin: Theme.outer }
        spacing: Theme.gap
        Tray { barWindow: root.barWindow }
        Recorder { barWindow: root.barWindow }
        Lang {}
        Volume {}
        Power {}
    }
}
