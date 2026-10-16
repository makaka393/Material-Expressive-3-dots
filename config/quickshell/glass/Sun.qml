pragma Singleton
import QtQuick
import Quickshell

// Восход и закат по координатам из Theme (lat / lon) — считается на месте, без сети
// (приближение NOAA, точность — минуты). Нужны циферблату «Горизонт» и авто-режиму защиты глаз.
Singleton {
    id: root

    // [восход, закат] в часах местного времени
    function times(date) {
        const rad = Math.PI / 180;
        const n = Math.floor((date - new Date(date.getFullYear(), 0, 0)) / 86400000);
        const decl = 23.44 * rad * Math.sin(2 * Math.PI * (284 + n) / 365);
        // солнце «встаёт», когда его центр на 0.833° ниже горизонта (рефракция + радиус диска)
        const x = (Math.sin(-0.833 * rad) - Math.sin(Theme.lat * rad) * Math.sin(decl)) / (Math.cos(Theme.lat * rad) * Math.cos(decl));
        const w = Math.acos(Math.max(-1, Math.min(1, x))) / rad / 15;                    // полдня, часы
        const b = 2 * Math.PI * (n - 81) / 364;
        const eot = 9.87 * Math.sin(2 * b) - 7.53 * Math.cos(b) - 1.5 * Math.sin(b);     // минуты
        const noon = 12 - (Theme.lon - (-date.getTimezoneOffset() / 60) * 15) / 15 - eot / 60;
        return [noon - w, noon + w];
    }
    function isDay(date) {
        const t = times(date), h = date.getHours() + date.getMinutes() / 60;
        return h >= t[0] && h < t[1];
    }
    // 18.82 → «18:49»
    function hm(h) {
        const m = Math.round(((h % 24) + 24) % 24 * 60);
        const p = n => (n < 10 ? "0" : "") + n;
        return p(Math.floor(m / 60) % 24) + ":" + p(m % 60);
    }

    // сейчас день? (обновляется раз в минуту)
    property bool day: isDay(new Date())
    readonly property var today: times(new Date())
    Timer { interval: 60000; repeat: true; running: true; onTriggered: root.day = root.isDay(new Date()) }
}
