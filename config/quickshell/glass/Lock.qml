import QtQuick
import Quickshell
import Quickshell.Wayland

// Замок сессии (ext-session-lock: пока он активен, композитор не показывает ничего, кроме
// этого экрана) и предпросмотр того же экрана без блокировки. Состояние — в Locker.
Scope {
    WlSessionLock {
        locked: Locker.locked
        WlSessionLockSurface {
            color: "black"
            LockSurface { anchors.fill: parent }
        }
    }

    PanelWindow {
        id: pv
        visible: Locker.preview
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "black"
        WlrLayershell.namespace: "quickshell-lock"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        Loader {
            anchors.fill: parent
            active: pv.visible
            sourceComponent: LockSurface { preview: true }
        }
    }
}
