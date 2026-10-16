pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Что показать в центральном острове (как Dynamic Island): короткие всплывашки
// (громкость, яркость, защита глаз, тема, скриншот, запись сохранена) и «живые»
// занятия (идёт запись экрана — красная точка с таймером в самом острове).
//   qs ipc -c glass call island screenshot <файл>
//   qs ipc -c glass call island recording <превью> <файл>
//   qs ipc -c glass call island toast <иконка> <заголовок> <подпись>
Singleton {
    id: root

    // текущая всплывашка
    property bool shown: false
    property string icon: ""
    property string title: ""
    property string sub: ""
    property real value: -1          // 0…1 — полоска (громкость/яркость), -1 — без неё
    property string image: ""        // превью (скриншот, запись)
    property var dots: []            // цвета (смена темы)
    property int serial: 0

    function show(o, ms) {
        icon = o.icon || ""; title = o.title || ""; sub = o.sub || "";
        value = o.value !== undefined ? o.value : -1;
        image = o.image || ""; dots = o.dots || [];
        shown = true; serial++;
        hideTimer.interval = ms || 1800;
        hideTimer.restart();
    }
    Timer { id: hideTimer; onTriggered: root.shown = false }

    // ── громкость (зовёт остров громкости)
    function volume(v, muted) {
        show({ icon: muted || v <= 0 ? "volume_off" : v < 0.35 ? "volume_mute" : v < 0.7 ? "volume_down" : "volume_up",
               title: I18n.t("Громкость", "Volume"),
               sub: muted ? I18n.t("Без звука", "Muted") : Math.round(v * 100) + "%",
               value: muted ? 0 : Math.min(1, v) });
    }

    // ── следим сами: яркость, защита глаз, смена темы (после старта, чтобы не мигать)
    property bool armed: false
    Timer { interval: 4000; running: true; onTriggered: root.armed = true }

    Connections {
        target: Brightness
        function onValueChanged() {
            if (!root.armed || Brightness.backend === "detecting") return;
            const v = Brightness.value;
            root.show({ icon: v > 60 ? "brightness_7" : v > 30 ? "brightness_6" : "brightness_4",
                        title: I18n.t("Яркость", "Brightness"), sub: v + "%", value: v / 100 });
        }
    }
    Connections {
        target: Night
        function onActiveChanged() {
            if (!root.armed) return;
            root.show({ icon: "nightlight",
                        title: I18n.t("Защита глаз", "Eye comfort"),
                        sub: Night.active ? I18n.t("Включена", "On") + " · " + Night.temp + "K" : I18n.t("Выключена", "Off") });
        }
        function onTempChanged() {
            if (!root.armed || !Night.active) return;
            root.show({ icon: "nightlight", title: I18n.t("Защита глаз", "Eye comfort"), sub: Night.temp + "K",
                        value: (6000 - Night.temp) / 3500 });
        }
    }
    Connections {
        target: Theme
        function onPrimaryChanged() { themeTimer.restart(); }
    }
    // цвета приходят по одному — ждём, пока все поменяются
    Timer {
        id: themeTimer
        interval: 400
        onTriggered: if (root.armed) root.show({ icon: "palette", title: I18n.t("Тема обновлена", "Theme updated"),
                                                 sub: Theme.m3 ? "Material Expressive" : I18n.t("Стекло", "Glass"),
                                                 dots: [Theme.primary, Theme.secondary, Theme.tertiary, Theme.primaryContainer] }, 2200)
    }
    Connections {
        target: Config
        function onDndChanged() { if (root.armed) root.show({ icon: Config.dnd ? "do_not_disturb_on" : "notifications_active",
                                                               title: I18n.t("Не беспокоить", "Do not disturb"),
                                                               sub: Config.dnd ? I18n.t("Включено", "On") : I18n.t("Выключено", "Off") }); }
        function onLangChanged() { if (root.armed) root.show({ icon: "translate", title: I18n.t("Русский язык", "English"), sub: I18n.t("Интерфейс переключён", "Interface switched") }); }
    }

    IpcHandler {
        target: "island"
        function toast(icon: string, title: string, sub: string): void { root.show({ icon: icon, title: title, sub: sub }, 2200); }
        function screenshot(path: string): void {
            root.show({ image: path, icon: "screenshot_region", title: I18n.t("Скриншот", "Screenshot"),
                        sub: I18n.t("Скопирован в буфер", "Copied to clipboard") }, 2600);
        }
        function recording(thumb: string, file: string): void {
            root.show({ image: thumb, icon: "videocam", title: I18n.t("Запись сохранена", "Recording saved"),
                        sub: file.split("/").pop() }, 3000);
        }
    }
}
