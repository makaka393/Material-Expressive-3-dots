pragma Singleton
import QtQuick
import Quickshell

// Язык интерфейса оболочки (настройки → Язык). В QML: I18n.t("Русский текст", "English text").
// Даты и дни недели — через I18n.locale.
Singleton {
    id: root
    readonly property bool en: Config.lang === "en"
    readonly property var locale: Qt.locale(en ? "en_US" : "ru_RU")
    function t(ru, enText) { return root.en ? enText : ru; }
    // «Пятница, 9 октября» / «Friday, October 9»
    function longDate(d) {
        const s = locale.toString(d, en ? "dddd, MMMM d" : "dddd, d MMMM");
        return s.charAt(0).toUpperCase() + s.slice(1);
    }
}
