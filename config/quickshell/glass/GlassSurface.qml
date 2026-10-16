import QtQuick

// Поверхность островов и карточек. В стиле «стекло» — матовое стекло в духе One UI: тонировка
// поверх блюра Hyprland, блик сверху, светлая кромка по верхнему краю и лёгкая тень у нижнего —
// от этого стекло выглядит объёмным. В стиле M3 — ровная тональная поверхность.
Item {
    id: g

    property real radius: 20
    property bool strong: false            // плотнее (раскрытые карточки и окна)
    property real sheenEnd: 0.45           // где кончается блик (доля высоты)

    Rectangle {
        anchors.fill: parent
        radius: g.radius
        color: g.strong ? Theme.glassStrong : Theme.glass
        border.width: 1
        border.color: Theme.glassBorder
        Behavior on color { ColorAnimation { duration: 350 } }
    }
    // блик сверху и тень у нижнего края
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, g.radius - 1)
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.glassSheen }
            GradientStop { position: g.sheenEnd; color: "transparent" }
            GradientStop { position: 0.62; color: "transparent" }
            GradientStop { position: 1.0; color: Theme.glassShade }
        }
    }
    // светлая кромка: только верхний край и верхние скругления
    Item {
        visible: !Theme.m3
        width: parent.width
        height: Math.min(g.radius, parent.height / 2) + 1
        clip: true
        Rectangle {
            width: g.width; height: g.height
            radius: g.radius
            color: "transparent"
            border.width: 1
            border.color: Theme.glassRim
        }
    }
}
