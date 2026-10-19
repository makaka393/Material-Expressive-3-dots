import QtQuick

// Часы — любой из циферблатов AOD (формы, стрелки, орбита, точки, планеты, горизонт, сегменты),
// по умолчанию тот же, что выбран для AOD. Подложка — стекло темы (размытие и прозрачность как
// у остальных виджетов; «Без фона» в «Настроить» — как на AOD, прямо на обоях):
//   «Стрелки» — сама «печенька» циферблата, «Формы» — фигуры под цифрами,
//   «Орбита» и «Планеты» — круг, остальные — скруглённая плашка по размеру циферблата.
// Циферблат вписывается в виджет целиком; при появлении и смене стиля собирается своей анимацией.
Item {
    id: root
    property date now: new Date()
    property string wid: ""
    property var cfg: ({})

    readonly property string face: Config.aodFaces.indexOf(cfg.face) >= 0 ? cfg.face : Config.aodFace
    readonly property bool dated: height >= 300 && width >= 300
    readonly property bool bare: cfg.bg === "none"
    readonly property bool inner: face === "analog" || face === "bubble"       // подложка — внутри циферблата
    readonly property bool round: face === "orbit" || face === "planets"

    // цвета и подложка-плашка для циферблатов без своих фигур
    WidgetSurface {
        id: ws
        cfg: root.cfg
        tone: "neutral"            // тёмная поверхность темы: светлые стрелки и цифры AOD на ней читаются
        defaultBg: "blur"
        anchors.centerIn: parent
        visible: !root.bare && !root.inner
        shape: root.round ? "circle" : "rect"
        readonly property real fw: clock.implicitWidth * clock.scale + (root.round ? 18 : 40)
        readonly property real fh: clock.implicitHeight * clock.scale + (root.round ? 18 : 32)
        width: root.round ? Math.min(root.width, Math.max(fw, fh)) : Math.min(root.width, fw)
        height: root.round ? width : Math.min(root.height, fh)
        radius: Math.min(40, height / 2)
        opacity: Math.min(1, clock.pp * 3)
    }

    AodClock {
        id: clock
        anchors.centerIn: parent
        style: root.face
        k: 0.5
        showDate: root.dated
        // цвета стрелок и цифр — под фон виджета (стекло и обои под ним); дата лежит на плашке,
        // а у «Стрелок», «Форм» и без фона — прямо на обоях
        ink: ({ fg: ws.fg, dim: ws.fgDim, primary: Theme.legible(Theme.primary, ws.seen, 3),
                tertiary: Theme.legible(Theme.tertiary, ws.seen, 3), base: ws.seen })
        dateColor: root.bare || root.inner ? Qt.alpha(ws.wallInk, 0.85) : ws.fgDim
        now: root.now
        surface: root.bare || !root.inner ? null : { cfg: root.cfg, tone: "neutral" }
        property real pp: 0
        p: pp
        // вписать целиком (k задаёт «чертёж», масштаб — в размер виджета; плашке оставляем поля)
        readonly property real inset: root.bare || root.inner ? 8 : (root.round ? 22 : 34)
        scale: implicitWidth > 0 && implicitHeight > 0
               ? Math.min((root.width - 2 * inset) / implicitWidth, (root.height - 2 * inset) / implicitHeight) : 1
        Behavior on scale { enabled: clock.pp >= 1; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        NumberAnimation { id: build; target: clock; property: "pp"; from: 0; to: 1; duration: 1500; easing.type: Easing.Linear }
        Component.onCompleted: build.start()
    }
    onFaceChanged: build.restart()
}
