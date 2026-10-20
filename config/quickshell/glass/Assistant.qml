pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Связь с ассистентом — службой glass-assistant (~/glass-dots/assistant, systemd --user):
// unix-сокет $XDG_RUNTIME_DIR/glass-assistant.sock, JSON по строке. Отсюда же его настройки
// (~/.config/glass/assistant.json — служба перечитывает их на каждом вопросе).
// Отвечает локальная модель; «морковь, …» в начале фразы, «??» в лаунчере или Super+Alt+A — Claude,
// и его ответ открывается в лаунчере.
//   qs ipc -c glass call assistant talk | listenClaude | stop | ask "вопрос" | askClaude "вопрос" | warm | unload
Singleton {
    id: root

    // имя — одно, оно же слово-активатор (assistant/glass_assistant/config.py: NAME)
    readonly property string name: I18n.t("Аянами", "Ayanami")
    // голоса — как VOICES в config.py: Silero (свои 5) и Piper; английские отвечают по-английски
    readonly property var voices: [
        { id: "xenia", ru: "Шёлк", en: "Silk", lang: "ru", female: true },
        { id: "kseniya", ru: "Мята", en: "Mint", lang: "ru", female: true },
        { id: "baya", ru: "Карамель", en: "Caramel", lang: "ru", female: true },
        { id: "aidar", ru: "Бархат", en: "Velvet", lang: "ru", female: false },
        { id: "eugene", ru: "Гранит", en: "Granite", lang: "ru", female: false },
        { id: "lessac", ru: "Мёд", en: "Honey", lang: "en", female: true, accent: "us" },
        { id: "alba", ru: "Вереск", en: "Heather", lang: "en", female: true, accent: "scot" },
        { id: "ryan", ru: "Графит", en: "Graphite", lang: "en", female: false, accent: "us" },
        { id: "northern", ru: "Дым", en: "Smoke", lang: "en", female: false, accent: "uk" }
    ]
    function voiceInfo(id) { return voices.find(v => v.id === id) || voices[0]; }
    readonly property string sockPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/glass-assistant.sock"
    readonly property bool online: sock.connected
    property string state: "idle"          // idle | listening | transcribing | thinking | speaking
    property bool hasKey: false            // у службы есть ключ Claude API
    property real level: 0                 // громкость: микрофона, пока слушает, её голоса — пока говорит
    property var bands: [0.25, 0.25, 0.25, 0.25]   // и доли четырёх полос спектра (свет острова)
    property string heard: ""              // вопрос: распознанный или набранный
    property string answer: ""             // ответ, по мере появления
    property string backend: ""            // кто отвечает: claude | local (известно до ответа — событие route)
    property var actions: []               // что сделано в ответ: [{ name, ok, show }]
    property bool windowed: false          // ответ Claude на голосовой вопрос показан в лаунчере, не в острове
    property string error: ""
    property bool voice: false             // последний вопрос задан голосом
    readonly property bool busy: state !== "idle"
    // карточке в острове: показывать, пока идёт разговор, и ещё немного после ответа
    readonly property bool showing: busy || linger.running

    Socket {
        id: sock
        path: root.sockPath
        connected: true
        parser: SplitParser { onRead: line => root.handle(line) }
    }
    // служба перезапустилась или ещё не запущена — переподключаемся
    Timer {
        interval: 3000; repeat: true; running: !sock.connected
        onTriggered: { sock.connected = false; sock.connected = true; }
    }
    // после ответа карточка висит, пока его можно дочитать: от 5 до 15 секунд по длине
    Timer { id: linger; interval: Math.max(5000, Math.min(15000, root.answer.length * 55)) }

    function handle(line) {
        let ev;
        try { ev = JSON.parse(line); } catch (e) { return; }
        switch (ev.ev) {
        case "state":
            if (ev.state === "listening" && state === "idle") { heard = ""; answer = ""; error = ""; voice = true; fresh(); }
            // ответ остаётся на экране: таймер — раньше, чем idle, иначе showing на миг гаснет и остров
            // Веги закрывается и открывается заново (с волной вызова)
            if (ev.state === "idle" && (answer !== "" || error !== "")) linger.restart();
            state = ev.state;
            hasKey = !!ev.key;
            if (ev.state !== "listening") level = 0;
            break;
        case "level": level = ev.v; if (ev.b) bands = ev.b; break;
        case "heard": heard = ev.text; answer = ""; break;
        case "route":
            backend = ev.brain;
            // голосом спросили Claude — его ответ длинный, показываем в лаунчере, а не в острове
            if (ev.brain === "claude" && voice) { heard = ev.text; windowed = true; Ui.launcher("?" + ev.text); }
            break;
        case "action": actions = actions.concat([{ name: ev.name, ok: ev.ok, show: ev.show }]); break;
        case "delta": answer += ev.text; break;
        case "done": answer = ev.text; backend = ev.backend; if (ev.actions) actions = ev.actions; break;
        case "error": error = ev.text; linger.restart(); break;
        }
    }
    function send(obj) {
        if (!sock.connected) {
            error = I18n.t("Ассистент не запущен: systemctl --user start glass-assistant", "Assistant is not running: systemctl --user start glass-assistant");
            linger.restart();
            return false;
        }
        sock.write(JSON.stringify(obj) + "\n");
        sock.flush();
        return true;
    }
    function fresh() { actions = []; windowed = false; }
    // выключена в настройках — не спрашиваем, а говорим, где включить
    function off() {
        if (acfg.enabled) return false;
        heard = ""; answer = "";
        error = I18n.t("Аянами выключена — включить: Настройки → Ассистент", "Ayanami is off — turn it on in Settings → Assistant");
        linger.restart();
        return true;
    }
    // главный тумблер: выключить — остановить службу и не запускать её при входе (память, микрофон, видеокарта
    // свободны); включить — запустить и вернуть в автозапуск
    function setEnabled(on) {
        acfg.enabled = on;
        svc.command = ["systemctl", "--user", on ? "enable" : "disable", "--now", "glass-assistant"];
        svc.running = true;
    }
    Process { id: svc }
    // «??вопрос» — сразу Claude (в карточке лаунчера вопрос остаётся с «?», чтобы она узнала свой ответ)
    function ask(text) {
        if (text.trim() === "") return;
        if (off()) return;
        heard = text.trim(); answer = ""; error = ""; backend = ""; voice = false; fresh();
        if (heard.startsWith("?")) send({ cmd: "ask", text: heard.slice(1).trim(), speak: cfg.speakTyped, to: "claude" });
        else send({ cmd: "ask", text: heard, speak: cfg.speakTyped });
    }
    function askClaude(text) {
        if (text.trim() === "") return;
        if (off()) return;
        heard = text.trim(); answer = ""; error = ""; backend = ""; voice = false; fresh();
        send({ cmd: "ask", text: heard, speak: cfg.speakTyped, to: "claude" });
    }
    // вопрос «как голосом», но текстом: карточка в острове, ответ вслух (если включено)
    function askVoice(text) {
        if (text.trim() === "") return;
        if (off()) return;
        heard = text.trim(); answer = ""; error = ""; backend = ""; voice = true; fresh();
        send({ cmd: "ask", text: heard, speak: cfg.speakVoice });
    }
    function listen() { if (off()) return; voice = true; if (!busy) { heard = ""; answer = ""; error = ""; fresh(); } send({ cmd: "listen" }); }
    function listenClaude() { if (off()) return; voice = true; if (!busy) { heard = ""; answer = ""; error = ""; fresh(); } send({ cmd: "listen", to: "claude" }); }
    // локальная модель грузится ~2 с — начинаем, как только ясно, что сейчас спросят (режим «?» лаунчера)
    function warm() { if (sock.connected) send({ cmd: "warm" }); }
    function unload() { if (sock.connected) send({ cmd: "unload" }); }
    function stop() { send({ cmd: "stop" }); linger.stop(); }
    function say(text) { send({ cmd: "say", text: text }); }
    // «прослушать» в настройках: голос и ползунки — прямо в команде (файл настроек мог ещё не записаться),
    // новое прослушивание обрывает прошлое. Фраза всегда русская: Silero говорит только по-русски
    function preview() {
        if (!sock.connected) return;
        const en = voiceInfo(acfg.voice).lang === "en";
        send({ cmd: "say", preview: true, text: en ? "Hi! I'm Ayanami. This is how my voice will sound." : "Привет. Я Аянами. Так будет звучать мой голос.",
               voice: acfg.voice, tone: acfg.voiceTone, speed: acfg.voiceSpeed, height: acfg.voiceHeight });
    }
    function reset() { send({ cmd: "reset" }); heard = ""; answer = ""; }
    function dismiss() { linger.stop(); }

    // ── настройки ассистента (их читает служба)
    property alias cfg: acfg
    FileView {
        path: Config.dir + "/assistant.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter(); }
        JsonAdapter {
            id: acfg
            property string backend: "auto"            // auto — локально, «морковь» — Claude | claude — всегда | local — никогда
            property string model: "claude-opus-5-5"
            property string effort: "low"
            property string voice: "xenia"
            property real voiceTone: 0                  // −1 мягче … +1 твёрже
            property real voiceSpeed: 1.0               // 0,75 … 1,35
            property real voiceHeight: 0                // −1 ниже … +1 выше
            property bool speakVoice: true
            property bool speakTyped: false
            property bool enabled: true                 // главный тумблер: выключено — служба остановлена
            property bool wake: false
            property bool callVolumeOn: true            // позвали — громкость системы на callVolume %
            property real callVolume: 35
            property bool pauseMedia: true              // позвали — пауза музыке и видео, после разговора — снова
            property bool followUp: true                // после голосового ответа слушать продолжение
            property real pause: 2.0                    // с тишины — конец фразы
            property var wakeWords: []                  // ещё слова-активаторы, кроме имени
            property bool advanced: false               // в настройках раскрыты «Расширенные» (служба не читает)
            property var claudeWords: ["морковь"]
            property string mic: ""
            property string about: ""                   // о пользователе — в промпт Claude (служба читает сама)
            property bool farMic: true                  // слушать через glass_vega_mic: шумодав, усиление, эхоподавление
        }
    }

    IpcHandler {
        target: "assistant"
        // «listen» — зарезервированное слово «qs ipc» с Quickshell 0.3 («Signal required to listen.»): Super+A зовёт talk
        function talk(): void { root.listen(); }
        function listen(): void { root.listen(); }
        function listenClaude(): void { root.listenClaude(); }
        function askClaude(text: string): void { root.askClaude(text); }
        function warm(): void { root.warm(); }
        function unload(): void { root.unload(); }
        function stop(): void { root.stop(); }
        function ask(text: string): void { root.ask(text); }
        function askVoice(text: string): void { root.askVoice(text); }
    }
}
