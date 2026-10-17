import QtQuick

// Заметка-стикер. Клик — пиши (рабочий стол на это время берёт клавиатуру), Esc или клик
// мимо — готово. Текст хранится в раскладке виджетов (widgets.json). «Очистить» — в меню по правому клику.
Item {
    id: root
    property string wid: ""
    property var cfg: ({})

    Connections {
        target: Widgets
        function onCommand(wid, name) {
            if (wid === root.wid && name === "clear") { edit.text = ""; Widgets.setExtra(root.wid, "text", ""); }
        }
        function onEditingChanged() { if (Widgets.editing) edit.focus = false; }
    }

    WidgetSurface { id: ws; anchors.fill: parent; tone: "tertiary"; radius: 36 }

    Icon {
        id: pin
        anchors { left: parent.left; top: parent.top; leftMargin: 18; topMargin: 16 }
        name: "sticky_note_2"; size: 20; fill: 1; color: ws.accent
    }
    Label {
        anchors { left: pin.right; leftMargin: 8; verticalCenter: pin.verticalCenter; right: parent.right; rightMargin: 18 }
        text: edit.activeFocus ? I18n.t("Esc — готово", "Esc — done") : I18n.t("Заметка", "Note")
        size: 13; weight: 700; color: edit.activeFocus ? ws.accent : ws.fgDim
    }

    Flickable {
        id: flick
        anchors { fill: parent; topMargin: 46; leftMargin: 18; rightMargin: 18; bottomMargin: 16 }
        contentHeight: edit.contentHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        function follow(r) {
            if (r.y < contentY) contentY = r.y;
            else if (r.y + r.height > contentY + height) contentY = r.y + r.height - height;
        }
        TextEdit {
            id: edit
            width: flick.width
            wrapMode: TextEdit.Wrap
            color: ws.fg
            selectionColor: Qt.alpha(ws.accent, 0.4)
            selectedTextColor: ws.fg
            font.family: Theme.font
            font.pixelSize: root.width >= 400 && root.height >= 300 ? 19 : 16
            font.variableAxes: ({ "wght": 520, "ROND": 100 })
            selectByMouse: true
            persistentSelection: false
            Component.onCompleted: text = root.cfg.text || ""
            onCursorRectangleChanged: flick.follow(cursorRectangle)
            onTextChanged: if (activeFocus) saver.restart()
            onActiveFocusChanged: {
                Widgets.typing = activeFocus;
                if (!activeFocus) { saver.stop(); Widgets.setExtra(root.wid, "text", text); }
            }
            Keys.onEscapePressed: focus = false
            Text {
                visible: edit.text === "" && !edit.activeFocus
                width: parent.width
                text: I18n.t("Нажми, чтобы написать", "Click to write")
                font: edit.font
                color: ws.fgDim; wrapMode: Text.Wrap
            }
        }
    }
    Timer { id: saver; interval: 800; onTriggered: Widgets.setExtra(root.wid, "text", edit.text) }

    // первый клик — фокус в заметку (рабочий стол сначала должен получить клавиатуру)
    MouseArea {
        anchors.fill: parent
        visible: !edit.activeFocus
        cursorShape: Qt.IBeamCursor
        onClicked: { Widgets.typing = true; focusLater.restart(); }
    }
    Timer { id: focusLater; interval: 60; onTriggered: { edit.forceActiveFocus(); edit.cursorPosition = edit.length; } }
}
