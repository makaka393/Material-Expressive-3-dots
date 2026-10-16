pragma Singleton
import QtQuick
import Quickshell

// Погода с open-meteo.com (без ключа). Обновляется раз в 15 минут.
Singleton {
    id: root

    property bool ready: false
    property real temp: 0
    property real feels: 0
    property real wind: 0
    property int humidity: 0
    property int code: 0
    property bool isDay: true
    property real tMax: 0
    property real tMin: 0
    property var hourly: []     // [{ hour: "14", temp: 9, code: 3, day: true }]

    function refresh() {
        const url = "https://api.open-meteo.com/v1/forecast?latitude=" + Theme.lat + "&longitude=" + Theme.lon
            + "&current=temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m,relative_humidity_2m"
            + "&hourly=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min"
            + "&timezone=auto&forecast_days=2";
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200) return;
            try {
                const d = JSON.parse(xhr.responseText);
                root.temp = d.current.temperature_2m;
                root.feels = d.current.apparent_temperature;
                root.wind = d.current.wind_speed_10m;
                root.humidity = d.current.relative_humidity_2m;
                root.code = d.current.weather_code;
                root.isDay = d.current.is_day === 1;
                root.tMax = d.daily.temperature_2m_max[0];
                root.tMin = d.daily.temperature_2m_min[0];
                const now = d.current.time.slice(0, 13);
                let start = d.hourly.time.findIndex(t => t.slice(0, 13) > now);
                if (start < 0) start = 0;
                const out = [];
                for (let i = start; i < d.hourly.time.length && out.length < 6; i += 2)
                    out.push({ hour: d.hourly.time[i].slice(11, 16), temp: d.hourly.temperature_2m[i],
                               code: d.hourly.weather_code[i], day: d.hourly.is_day[i] === 1 });
                root.hourly = out;
                root.ready = true;
            } catch (e) {
                console.warn("weather:", e);
            }
        };
        xhr.open("GET", url);
        xhr.send();
    }

    // WMO weather code → Material Symbol
    function icon(c, day) {
        if (c === 0) return day ? "clear_day" : "clear_night";
        if (c <= 2) return day ? "partly_cloudy_day" : "partly_cloudy_night";
        if (c === 3) return "cloud";
        if (c === 45 || c === 48) return "foggy";
        if (c >= 51 && c <= 57) return "rainy_light";
        if (c === 61 || c === 80) return "rainy_light";
        if (c === 63 || c === 81) return "rainy";
        if (c === 65 || c === 82) return "rainy_heavy";
        if (c === 66 || c === 67) return "rainy_snow";
        if (c >= 71 && c <= 77) return "weather_snowy";
        if (c === 85 || c === 86) return "snowing";
        if (c >= 95) return "thunderstorm";
        return "cloud";
    }

    function describe(c) {
        if (c === 0) return I18n.t("Ясно", "Clear");
        if (c === 1) return I18n.t("Почти ясно", "Mostly clear");
        if (c === 2) return I18n.t("Переменная облачность", "Partly cloudy");
        if (c === 3) return I18n.t("Пасмурно", "Overcast");
        if (c === 45 || c === 48) return I18n.t("Туман", "Fog");
        if (c >= 51 && c <= 57) return I18n.t("Морось", "Drizzle");
        if (c >= 61 && c <= 67) return I18n.t("Дождь", "Rain");
        if (c >= 71 && c <= 77) return I18n.t("Снег", "Snow");
        if (c >= 80 && c <= 82) return I18n.t("Ливень", "Showers");
        if (c === 85 || c === 86) return I18n.t("Снегопад", "Snowfall");
        if (c >= 95) return I18n.t("Гроза", "Thunderstorm");
        return "—";
    }

    Timer {
        interval: 15 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
