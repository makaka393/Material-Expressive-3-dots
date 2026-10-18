pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Связь с ассистентом — службой glass-assistant (~/glass-dots/assistant, systemd --user):
// unix-сокет $XDG_RUNTIME_DIR/glass-assistant.sock, JSON по строке. Отсюда же его настройки
// (~/.config/glass/assistant.json — служба перечитывает их на каждом вопросе).
// Отвечает локальная модель; «морковь, …» в начале фразы, «??» в лаунчере или Super+Alt+A — Claude,
// и его ответ открывается в лаунчере.
//   qs ipc -c glass call assistant listen | listenClaude | stop | ask "вопрос" | askClaude "вопрос" | warm | unload
Singleton {
    id: root

    readonly property string sockPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/glass-assistant.sock"
    readonly property bool online: sock.connected
    property string state: "idle"          // idle | listening | transcribing | thinking | speaking
    property bool hasKey: false            // у службы есть ключ Claude API
    property real level: 0                 // громкость микрофона, пока слушает
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
            state = ev.state;
            hasKey = !!ev.key;
            if (ev.state !== "listening") level = 0;
            if (ev.state === "idle" && (answer !== "" || error !== "")) linger.restart();
            break;
        case "level": level = ev.v; break;
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
    // «??вопрос» — сразу Claude (в карточке лаунчера вопрос остаётся с «?», чтобы она узнала свой ответ)
    function ask(text) {
        if (text.trim() === "") return;
        heard = text.trim(); answer = ""; error = ""; backend = ""; voice = false; fresh();
        if (heard.startsWith("?")) send({ cmd: "ask", text: heard.slice(1).trim(), speak: cfg.speakTyped, to: "claude" });
        else send({ cmd: "ask", text: heard, speak: cfg.speakTyped });
    }
    function askClaude(text) {
        if (text.trim() === "") return;
        heard = text.trim(); answer = ""; error = ""; backend = ""; voice = false; fresh();
        send({ cmd: "ask", text: heard, speak: cfg.speakTyped, to: "claude" });
    }
    // вопрос «как голосом», но текстом: карточка в острове, ответ вслух (если включено)
    function askVoice(text) {
        if (text.trim() === "") return;
        heard = text.trim(); answer = ""; error = ""; backend = ""; voice = true; fresh();
        send({ cmd: "ask", text: heard, speak: cfg.speakVoice });
    }
    function listen() { voice = true; if (!busy) { heard = ""; answer = ""; error = ""; fresh(); } send({ cmd: "listen" }); }
    function listenClaude() { voice = true; if (!busy) { heard = ""; answer = ""; error = ""; fresh(); } send({ cmd: "listen", to: "claude" }); }
    // локальная модель грузится ~2 с — начинаем, как только ясно, что сейчас спросят (режим «?» лаунчера)
    function warm() { if (sock.connected) send({ cmd: "warm" }); }
    function unload() { if (sock.connected) send({ cmd: "unload" }); }
    function stop() { send({ cmd: "stop" }); linger.stop(); }
    // o — голос для «прослушать»: { voice, pitch, rate } (иначе — из настроек)
    function say(text, o) { send(Object.assign({ cmd: "say", text: text }, o || {})); }
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
            property string voicePitch: "medium"       // low | medium | high
            property string voiceRate: "medium"        // slow | medium | fast
            property bool speakVoice: true
            property bool speakTyped: false
            property bool wake: false
            property bool followUp: true                // после голосового ответа слушать продолжение
            property real pause: 1.3                    // с тишины — конец фразы
            property var wakeWords: ["обсидиан"]
            property var claudeWords: ["морковь"]
            property string mic: ""
        }
    }

    IpcHandler {
        target: "assistant"
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
