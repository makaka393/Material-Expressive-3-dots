import QtQuick

// Текст в стиле M3 Expressive: Google Sans Flex со скруглением (ROND)
Text {
    property int size: 14
    property int weight: 500
    property real round: 100

    color: Theme.fg
    font.family: Theme.font
    font.pixelSize: size
    font.variableAxes: ({ "wght": weight, "ROND": round, "opsz": Math.max(6, Math.min(144, size)) })
    font.features: ({ "tnum": 1 })
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideRight

    // Оптическая центровка: добиваем строку до чётной высоты так, чтобы середина прописных букв
    // и цифр попала ровно в центр (см. Theme.capCenter). Только одна строка и обычные размеры —
    // крупные цифры часов выставляются вручную.
    readonly property int lift: text.length === 0 || size > 40 || lineCount > 1 ? 0
                                : Math.round(contentHeight) - 2 * Math.round(Theme.capCenter * size + 0.1)
    topPadding: Math.max(0, lift)
    bottomPadding: Math.max(0, -lift)

    Behavior on color { ColorAnimation { duration: 300 } }
}
