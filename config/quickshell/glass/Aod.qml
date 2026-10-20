import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Always On Display в стиле Pixel: отошёл от компьютера — фон плавно темнеет
// (обои чуть видны, окна гаснут — WinHide), остаются часы, музыка и погода. Любое движение — назад.
// Не включается поверх полноэкранных игр/видео и когда приложение просит не засыпать.
// Пароль при возвращении (настройки): после AOD — экран блокировки оболочки (Locker).
//   qs ipc -c glass call aod open | close | toggle
PanelWindow {
    id: win

    property bool open: false
    property bool byIdle: false

    property double shownAt: 0
    property bool locking: false

    function show(idle) {
        if (open) return;
        byIdle = idle;
        shownAt = Date.now();
        open = true;
    }
    // вернулся: если в настройках нужен пароль — сначала поднимаем экран блокировки,
    // и только потом убираем AOD (чтобы между ними не мелькнул рабочий стол)
    function hide() {
        if (!open || locking) return;
        const need = byIdle && Config.aodLock >= 0 && Date.now() - shownAt >= Config.aodLock * 1000;
        if (!need) { open = false; return; }
        locking = true;
        Locker.lock(true);        // экран блокировки «проснётся» из AOD
        lockDelay.restart();
    }
    Timer { id: lockDelay; interval: 800; onTriggered: { win.locking = false; win.open = false; } }
    Binding { target: Config; property: "aodScreen"; value: win.open && win.screen ? win.screen.name : "" }
    // окна на время AOD становятся полностью прозрачными (остаются обои, затемнение и часы)
    Binding { target: WinHide; property: "hide"; value: win.open && Config.aodHideWindows }

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: open || veil.opacity > 0.002
    WlrLayershell.namespace: "quickshell-aod"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // ── простой
    IdleMonitor {
        id: idle
        enabled: Config.aodEnabled
        timeout: Math.max(30, Config.aodTimeout)
        respectInhibitors: true          // видео в браузере, mpv и т.п. — не включаемся
        onIsIdleChanged: {
            if (isIdle) fsCheck.running = true;
            else if (win.byIdle) win.hide();
        }
    }
    // поверх полноэкранного окна (игра на геймпаде, фильм) — не показываем
    Process {
        id: fsCheck
        command: ["hyprctl", "activewindow", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let fs = false;
                try { const j = JSON.parse(text); fs = !!j.fullscreen && j.fullscreen !== 0; } catch (e) {}
                if (!fs && idle.isIdle && Config.aodEnabled) win.show(true);
            }
        }
    }
    // «Показать сейчас» из настроек
    Connections {
        target: Config
        function onAodPingChanged() { pingDelay.restart(); }
    }
    Timer { id: pingDelay; interval: 450; onTriggered: win.show(false) }

    // ── затемнение: только фон, без блюра
    Rectangle {
        id: veil
        anchors.fill: parent
        color: "black"
        opacity: win.open ? Config.aodDim : 0
        Behavior on opacity { NumberAnimation { duration: win.open ? 1100 : 280; easing.type: Easing.OutCubic } }
    }

    Loader {
        anchors.fill: parent
        active: win.visible
        sourceComponent: AodFace {
            open: win.open
            onDismiss: win.hide()
        }
    }

    // ── Вега на AOD: позвали по имени, пока экран спит, — тот же остров с линзой и светом, на том же
    // месте, что в баре (бар под AOD спрятан). Ответила — остров сворачивается и уходит
    readonly property bool vega: Assistant.showing && Assistant.voice && !Assistant.windowed
    property bool vegaShown: false
    onVegaChanged: if (vega) vegaShown = true; else vegaHide.restart()
    Timer { id: vegaHide; interval: 900; onTriggered: win.vegaShown = win.vega }
    // снимок экрана для линзы — как в Bar.qml; живёт вместе с окном AOD: к вызову Веги уже готов снимать
    ScreencopyView {
        id: shot
        captureSource: win.screen
        live: false
        width: win.width
        height: win.height
    }
    ShaderEffectSource {
        id: shotTex
        sourceItem: shot
        hideSource: true
        live: true
        mipmap: true
        smooth: true
        textureSize: Qt.size(Math.max(1, shot.width), Math.max(1, shot.height))
        visible: false
        width: 1; height: 1
    }
    Loader {
        anchors.fill: parent
        active: win.open && win.vegaShown
        sourceComponent: Item {
            id: vg
            property bool shown: false
            Component.onCompleted: shown = Qt.binding(() => win.vega)
            opacity: shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: vg.shown ? 260 : 600; easing.type: Easing.OutCubic } }

            DynamicIsland {
                anchors { top: parent.top; topMargin: Theme.outer; horizontalCenter: parent.horizontalCenter }
                shotView: shot
                shotTex: shotTex
                screenSize: Qt.vector2d(win.width, win.height)
                transformOrigin: Item.Top
                scale: vg.shown ? 1 : 0.9
                Behavior on scale { Anim { kind: "fast" } }
            }
        }
    }

    IpcHandler {
        target: "aod"
        // не «show»: qs ipc принимает это слово за свою подкоманду и ничего не вызывает
        function open(): void { win.show(false); }
        function close(): void { win.hide(); }
        function hide(): void { win.hide(); }
        function toggle(): void { if (win.open) win.hide(); else win.show(false); }
    }
}
