import QtQuick

// Цифры виджета «Часы»: жирные (часы) и тонкие (минуты) начертания Google Sans Flex.
Text {
    property bool strong: true
    property color strongColor: "white"
    property color weakColor: "white"
    color: strong ? strongColor : weakColor
    font.family: Theme.font
    font.variableAxes: ({ "wght": strong ? 760 : 380, "ROND": 100, "opsz": 144 })
    font.features: ({ "tnum": 1 })
    Behavior on color { ColorAnimation { duration: 300 } }
}
