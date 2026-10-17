import QtQuick

// Часы — любой из циферблатов AOD (формы, стрелки, орбита, точки, планеты, горизонт, сегменты),
// по умолчанию тот же, что выбран для AOD. Стиль — в «Настроить». Без подложки по умолчанию:
// циферблат прямо на обоях, как «Коротко о главном». Циферблат вписывается в виджет целиком;
// при появлении и смене стиля он собирается своей анимацией (как при входе в AOD).
Item {
    id: root
    property date now: new Date()
    property string wid: ""
    property var cfg: ({})

    readonly property string face: Config.aodFaces.indexOf(cfg.face) >= 0 ? cfg.face : Config.aodFace
    readonly property bool dated: height >= 300 && width >= 300

    WidgetSurface { id: ws; cfg: root.cfg; anchors.fill: parent; tone: "primary"; defaultBg: "none"; radius: Math.min(44, root.height / 2) }

    AodClock {
        id: clock
        anchors.centerIn: parent
        style: root.face
        k: 0.5
        showDate: root.dated
        now: root.now
        property real pp: 0
        p: pp
        // вписать целиком (k задаёт «чертёж», масштаб — в размер виджета)
        readonly property real inset: ws.bare ? 8 : 28
        scale: implicitWidth > 0 && implicitHeight > 0
               ? Math.min((root.width - 2 * inset) / implicitWidth, (root.height - 2 * inset) / implicitHeight) : 1
        Behavior on scale { enabled: clock.pp >= 1; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        NumberAnimation { id: build; target: clock; property: "pp"; from: 0; to: 1; duration: 1500; easing.type: Easing.Linear }
        Component.onCompleted: build.start()
    }
    onFaceChanged: build.restart()
}
