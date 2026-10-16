import QtQuick

// Иконка Material Symbols Rounded по имени лигатуры: Icon { name: "play_arrow" }
Text {
    property string name: ""
    property real fill: 0
    property int size: 20
    property int weight: 500

    text: name
    color: Theme.fg
    font.family: Theme.iconFont
    font.pixelSize: size
    font.variableAxes: ({ "FILL": fill, "wght": weight, "opsz": Math.max(20, Math.min(48, size)), "GRAD": 0 })
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    // строка чётной высоты: с нечётной иконка в кнопке встаёт на пиксель выше центра
    topPadding: name.length > 0 && Math.round(contentHeight) % 2 === 1 ? 1 : 0

    Behavior on fill { Anim { kind: "effects" } }
    Behavior on color { ColorAnimation { duration: 300 } }
}
