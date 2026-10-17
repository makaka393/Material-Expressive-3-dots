import QtQuick

// День, месяц или год точками: прошедшее — цветом темы, сегодня (или этот час) светится,
// впереди — тусклые. Клик или «День / месяц / год» в меню — сменить период.
Item {
    id: root
    property date now: new Date()
    property string wid: ""
    property var cfg: ({})

    readonly property var modes: ["year", "month", "day"]
    readonly property string mode: modes.indexOf(cfg.mode) >= 0 ? cfg.mode : (width * height > 260 * 260 ? "year" : "month")
    function cycle() { Widgets.setExtra(wid, "mode", modes[(modes.indexOf(mode) + 1) % modes.length]); }
    Connections { target: Widgets; function onCommand(wid, name) { if (wid === root.wid && name === "mode") root.cycle(); } }

    readonly property int year: now.getFullYear()
    readonly property int yearDays: new Date(year, 1, 29).getMonth() === 1 ? 366 : 365
    readonly property int dayOfYear: Math.floor((new Date(year, now.getMonth(), now.getDate()) - new Date(year, 0, 1)) / 86400000) + 1
    readonly property int monthDays: new Date(year, now.getMonth() + 1, 0).getDate()

    readonly property int total: mode === "year" ? yearDays : mode === "month" ? monthDays : 24
    readonly property int current: mode === "year" ? dayOfYear : mode === "month" ? now.getDate() : now.getHours() + 1   // 1…total
    readonly property real pct: mode === "day" ? (now.getHours() * 60 + now.getMinutes()) / 1440
                              : (current - 1 + (now.getHours() * 60 + now.getMinutes()) / 1440) / total
    readonly property string title: mode === "year" ? String(year)
                                  : mode === "month" ? (s => s.charAt(0).toUpperCase() + s.slice(1))(I18n.locale.standaloneMonthName(now.getMonth(), Locale.LongFormat))
                                  : I18n.t("Сегодня", "Today")
    readonly property string remain: mode === "day" ? (24 - current) + I18n.t(" ч осталось", "h left")
                                 : (total - current) + I18n.t(" дн. осталось", " days left")

    WidgetSurface { id: ws; cfg: root.cfg; anchors.fill: parent; tone: "primary"; radius: 40 }

    Item {
        id: head
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 20; rightMargin: 20; topMargin: 16 }
        height: 26
        Label { anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: root.title; size: 15; weight: 750; color: ws.fg; elide: Text.ElideNone }
        Label { anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: Math.floor(root.pct * 100) + "%"; size: 15; weight: 750; color: ws.accent; elide: Text.ElideNone }
    }

    // ── точки: столбцов столько, чтобы точки вышли покрупнее
    Item {
        id: field
        anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: foot.top; margins: 18; topMargin: 10; bottomMargin: 6 }
        readonly property var fit: {
            let best = { c: 1, r: root.total, p: 0 };
            for (let c = 1; c <= root.total; c++) {
                const r = Math.ceil(root.total / c);
                const p = Math.min(width / c, height / r);
                if (p > best.p) best = { c: c, r: r, p: p };
            }
            return best;
        }
        Grid {
            anchors.centerIn: parent
            columns: field.fit.c
            Repeater {
                model: root.total
                Item {
                    required property int index
                    readonly property int n: index + 1
                    width: field.fit.p; height: field.fit.p
                    Rectangle {
                        anchors.centerIn: parent
                        visible: parent.n === root.current
                        width: parent.width * 1.05; height: width; radius: width / 2
                        color: Qt.alpha(ws.accent, 0.28)
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * (parent.n === root.current ? 0.78 : 0.62); height: width; radius: width / 2
                        color: parent.n < root.current ? ws.accent : parent.n === root.current ? ws.fg : Qt.alpha(ws.fg, 0.16)
                    }
                }
            }
        }
    }

    Label {
        id: foot
        anchors { left: parent.left; bottom: parent.bottom; leftMargin: 20; bottomMargin: 12 }
        height: root.height >= 200 ? 20 : 0
        visible: height > 0
        text: root.remain; size: 12; weight: 600; color: ws.fgDim; elide: Text.ElideNone
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.cycle() }
}
