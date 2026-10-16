import QtQuick
import Quickshell
import Quickshell.Widgets

// Одно уведомление: иконка приложения, «Discord · сейчас», заголовок, текст, кнопки действий.
// Используется во всплывашке острова и в истории шторки (compact).
Item {
    id: root
    property var n: null
    property bool compact: false
    readonly property string icon: Notifs.iconFor(n)
    readonly property bool crit: Notifs.critical(n)
    readonly property var actions: n ? n.actions.filter(a => a.identifier !== "default" && a.text !== "") : []

    implicitHeight: Math.max(icn.height, col.implicitHeight)

    // иконка: картинка из уведомления / иконка приложения / колокольчик
    Item {
        id: icn
        width: root.compact ? 36 : 44; height: width
        ClippingRectangle {
            anchors.fill: parent
            radius: root.compact ? 12 : 14
            color: root.crit ? Qt.alpha(Theme.error, 0.28) : Theme.primaryContainer
            visible: root.icon !== ""
            Image {
                anchors.fill: parent
                source: root.icon
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 96; sourceSize.height: 96
                asynchronous: true
            }
        }
        Rectangle {
            anchors.fill: parent
            visible: root.icon === ""
            radius: root.compact ? 12 : 14
            color: root.crit ? Theme.error : Theme.primaryContainer
            Icon { anchors.centerIn: parent; name: root.crit ? "priority_high" : "notifications"; size: root.compact ? 18 : 22; fill: 1; color: root.crit ? Theme.surface : Theme.primaryContainerFg }
        }
    }

    Column {
        id: col
        anchors { left: icn.right; leftMargin: 12; right: parent.right; rightMargin: closeBtn.width + 4 }
        spacing: 2
        Label {
            width: parent.width
            text: { void Notifs.tick; return (root.n ? (root.n.appName || I18n.t("Уведомление", "Notification")) : "") + "  ·  " + (root.n ? Notifs.ago(root.n) : ""); }
            size: 11; weight: 600; color: root.crit ? Theme.error : Theme.fgVariant
        }
        Label {
            width: parent.width
            text: root.n ? root.n.summary : ""
            size: root.compact ? 13 : 15; weight: 700
        }
        Text {
            width: parent.width
            visible: text !== ""
            text: root.n ? root.n.body.replace(/<[^>]*>/g, "") : ""
            color: Theme.fgVariant
            font.family: Theme.font
            font.pixelSize: root.compact ? 12 : 13
            wrapMode: Text.Wrap
            maximumLineCount: root.compact ? 1 : 2
            elide: Text.ElideRight
        }
        // кнопки действий (Ответить, Открыть, Принять…)
        Row {
            visible: !root.compact && root.actions.length > 0
            topPadding: 6
            spacing: 6
            Repeater {
                model: root.actions.slice(0, 3)
                Rectangle {
                    id: act
                    required property var modelData
                    width: actLbl.implicitWidth + 24; height: 30
                    radius: actMouse.pressed ? 10 : 15
                    color: actMouse.containsMouse ? Theme.primary : Theme.glassChip
                    Behavior on radius { Anim { kind: "fast" } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Label { id: actLbl; anchors.centerIn: parent; text: act.modelData.text; size: 12; weight: 650; color: actMouse.containsMouse ? Theme.primaryFg : Theme.fg; elide: Text.ElideNone }
                    MouseArea {
                        id: actMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { act.modelData.invoke(); Notifs.dismiss(root.n); }
                    }
                }
            }
        }
    }

    // клик по уведомлению — открыть приложение
    MouseArea {
        anchors.fill: col
        z: -1
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.n) Notifs.open(root.n)
    }

    IconButton {
        id: closeBtn
        anchors { right: parent.right; top: parent.top; topMargin: -4 }
        size: root.compact ? 26 : 30; iconSize: root.compact ? 15 : 17
        icon: "close"; color: Theme.fgVariant
        onClicked: if (root.n) Notifs.dismiss(root.n)
    }
}
