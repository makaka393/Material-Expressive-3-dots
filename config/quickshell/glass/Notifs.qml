pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// Уведомления: свой сервер (вместо mako/dunst/swaync). Новое уведомление выезжает
// из центрального острова, история — в шторке справа. «Не беспокоить» — плитка в шторке.
//   qs ipc -c glass call notifs dnd | set true|false | clear
Singleton {
    id: root

    readonly property var list: server.trackedNotifications.values   // история (новые — в конце)
    readonly property int count: list.length
    property var popup: null            // что сейчас показывает остров
    property bool hovered: false        // мышь над уведомлением — не прячем
    property var times: ({})            // id → время прихода

    function iconFor(n) {
        if (!n) return "";
        if (n.image && n.image !== "") return n.image;
        if (n.appIcon && n.appIcon !== "") {
            if (n.appIcon.startsWith("/") || n.appIcon.startsWith("file:")) return n.appIcon.startsWith("/") ? "file://" + n.appIcon : n.appIcon;
            const p = Quickshell.iconPath(n.appIcon, true);
            if (p !== "") return p;
        }
        if (n.desktopEntry && n.desktopEntry !== "") {
            const p2 = Quickshell.iconPath(n.desktopEntry.toLowerCase(), true);
            if (p2 !== "") return p2;
        }
        return "";
    }
    function ago(n) {
        const t = times[n.id];
        if (!t) return "";
        const s = Math.floor((Date.now() - t) / 1000);
        if (s < 60) return I18n.t("сейчас", "now");
        if (s < 3600) return Math.floor(s / 60) + I18n.t(" мин", " min");
        return new Date(t).toLocaleTimeString(I18n.locale, "HH:mm");
    }
    function critical(n) { return n && n.urgency === NotificationUrgency.Critical; }

    function open(n) {
        // клик по уведомлению — действие по умолчанию, если есть
        const def = n.actions.find(a => a.identifier === "default");
        if (def) def.invoke();
        dismiss(n);
    }
    function dismiss(n) {
        if (popup === n) popup = null;
        n.dismiss();
    }
    function clearAll() {
        popup = null;
        for (const n of list.slice()) n.dismiss();
    }
    function hidePopup() { popup = null; }

    NotificationServer {
        id: server
        keepOnReload: true
        actionsSupported: true
        imageSupported: true
        bodySupported: true
        bodyMarkupSupported: false
        persistenceSupported: true

        onNotification: n => {
            n.tracked = true;
            const t = root.times; t[n.id] = Date.now(); root.times = t;
            if (Config.dnd && !root.critical(n)) return;   // тихо: только в историю
            root.popup = n;
            const ms = n.expireTimeout > 0 ? (n.expireTimeout < 1000 ? n.expireTimeout * 1000 : n.expireTimeout) : 5500;
            hideTimer.interval = Math.max(2500, Math.min(15000, ms));
            if (!root.critical(n)) hideTimer.restart(); else hideTimer.stop();
        }
    }
    // уведомление закрыли где-то ещё (приложение само отозвало)
    Connections {
        target: root.popup
        function onClosed() { root.popup = null; }
    }
    Timer {
        id: hideTimer
        onTriggered: if (root.hovered) restart(); else root.popup = null
    }
    // «сейчас / 3 мин» в истории
    property int tick: 0
    Timer { interval: 30000; repeat: true; running: root.count > 0; onTriggered: root.tick++ }

    IpcHandler {
        target: "notifs"
        function dnd(): void { Config.dnd = !Config.dnd; }
        function set(on: bool): void { Config.dnd = on; }
        function clear(): void { root.clearAll(); }
    }
}
