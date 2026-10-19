import QtQuick

// Календарь в острове (клик по часам): месяц сеткой, сегодня выделено, неделя с понедельника.
// Стрелки или колёсико листают месяцы, клик по названию месяца возвращает к текущему.
Item {
    id: root

    property date now: new Date()
    property int shift: 0                                  // на сколько месяцев ушли от текущего
    readonly property date first: new Date(now.getFullYear(), now.getMonth() + shift, 1)
    readonly property int lead: (first.getDay() + 6) % 7   // пустых ячеек до первого числа
    readonly property int days: new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate()
    readonly property int today: shift === 0 ? now.getDate() : -1
    readonly property int cell: 38
    // цвета — по умолчанию темы; виджет календаря подставляет свои, подобранные под его фон
    property color ink: Theme.fg
    property color inkDim: Theme.fgVariant
    property color accent: Theme.primary
    property color weekend: Theme.tertiary
    property color todayInk: Theme.primaryFg

    readonly property string title: {
        const s = I18n.locale.standaloneMonthName(first.getMonth(), Locale.LongFormat) + " " + first.getFullYear();
        return s.charAt(0).toUpperCase() + s.slice(1);
    }

    WheelHandler {
        property real acc: 0
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: ev => {
            acc += ev.angleDelta.y;
            if (Math.abs(acc) >= 120) { root.shift += acc > 0 ? -1 : 1; acc = 0; }
        }
    }

    Column {
        anchors { fill: parent; margins: 16; topMargin: 12 }
        spacing: 6

        Item {
            width: parent.width; height: 36
            Label {
                anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                text: root.title; size: 17; weight: 700; elide: Text.ElideNone
                color: root.shift === 0 ? root.ink : root.accent
                TapHandler { onTapped: root.shift = 0 }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                IconButton { icon: "chevron_left"; size: 34; iconSize: 22; fill: 0; color: root.ink; onClicked: root.shift-- }
                IconButton { icon: "chevron_right"; size: 34; iconSize: 22; fill: 0; color: root.ink; onClicked: root.shift++ }
            }
        }

        // дни недели
        Row {
            Repeater {
                model: 7
                Label {
                    required property int index
                    width: (root.width - 32) / 7; height: 22
                    horizontalAlignment: Text.AlignHCenter
                    text: I18n.locale.standaloneDayName((index + 1) % 7, Locale.ShortFormat)
                    size: 12; weight: 600; elide: Text.ElideNone
                    color: index >= 5 ? root.weekend : root.inkDim
                }
            }
        }

        Grid {
            columns: 7
            Repeater {
                model: 42
                Item {
                    id: day
                    required property int index
                    readonly property int n: index - root.lead + 1
                    readonly property bool inMonth: n >= 1 && n <= root.days
                    readonly property bool isToday: n === root.today
                    width: (root.width - 32) / 7; height: root.cell
                    visible: index < 35 || root.lead + root.days > 35      // пустую шестую неделю не рисуем
                    Rectangle {
                        anchors.centerIn: parent
                        width: 34; height: 34
                        radius: day.isToday ? 12 : 17
                        color: day.isToday ? root.accent : "transparent"
                    }
                    Label {
                        anchors.centerIn: parent
                        visible: day.inMonth
                        text: day.n
                        size: 14; weight: day.isToday ? 750 : 550; elide: Text.ElideNone
                        color: day.isToday ? root.todayInk : day.index % 7 >= 5 ? root.weekend : root.ink
                    }
                }
            }
        }
    }
}
