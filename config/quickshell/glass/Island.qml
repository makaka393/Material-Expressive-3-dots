import QtQuick

// «Остров» из матового стекла. Размеры меняются пружинной анимацией —
// получается эффект Dynamic Island. Blur делает Hyprland (layerrule).
Item {
    id: root

    property real targetWidth: 120
    property real targetHeight: Theme.barHeight
    property bool strong: false                    // плотнее стекло (для раскрытых карточек)
    readonly property bool hovered: hover.hovered
    property bool pill: false                      // круг или пилюля: скругление — половина высоты (остров Веги)
    readonly property real radius: pill ? height / 2 : Math.min(height / 2, Theme.radiusCard)
    default property alias content: inner.data

    implicitWidth: targetWidth
    implicitHeight: targetHeight
    Behavior on implicitWidth { Anim {} }
    Behavior on implicitHeight { Anim {} }

    HoverHandler { id: hover }

    GlassSurface {
        anchors.fill: parent
        radius: root.radius
        strong: root.strong
    }

    Item {
        id: inner
        anchors.fill: parent
        clip: true
    }
}
