import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Выбор обоев. Открыть/закрыть: qs ipc -c glass call picker toggle
PanelWindow {
    id: win

    property bool open: false
    readonly property string home: Quickshell.env("HOME")
    readonly property string envFile: home + "/.config/hypr/scripts/theme.env"
    readonly property string script: home + "/.config/hypr/scripts/changetheme.sh"
    readonly property string palScript: home + "/.config/hypr/scripts/wall-palettes.py"
    property string contrast: "0"

    anchors { top: true; left: true; right: true }
    implicitHeight: 610
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: open || card.opacity > 0
    WlrLayershell.namespace: "quickshell-bar"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    mask: Region { item: card }

    ListModel { id: walls }
    // закрыли — отпускаем превью обоев и кэш цветов (при открытии всё пересканируется)
    onVisibleChanged: if (!visible) { walls.clear(); content.palettes = []; win.palCache = ({}); }

    IpcHandler {
        target: "picker"
        function toggle(): void { win.open = !win.open; }
        // не «show»: qs ipc принимает это слово за свою подкоманду и ничего не вызывает
        function open(): void { win.open = true; }
        function close(): void { win.open = false; }
        function hide(): void { win.open = false; }
    }

    onOpenChanged: if (!open) content.customOpen = false; else if (open) { scan.running = true; readEnv.running = true; focusTimer.restart(); win.requestPalettes(); }
    Timer { id: focusTimer; interval: 60; onTriggered: content.focusList() }

    HyprlandFocusGrab {
        windows: [win]
        active: win.open
        onCleared: win.open = false
    }

    // список обоев + превью (imagemagick, кэш в ~/.cache/wallthumbs)
    Process {
        id: scan
        command: ["sh", "-c", `
            d="$1"; c="$HOME/.cache/wallthumbs"; mkdir -p "$c"
            printf 'CUR\\t%s\\n' "$(readlink -f "$HOME/.cache/matugen/wallpaper")"
            printf 'SRC\\t%s\\n' "$(cat "$HOME/.cache/matugen/source" 2>/dev/null)"
            find "$d" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mkv' -o -iname '*.mov' \\) -printf '%T@\\t%p\\n' \\
              | sort -rn | cut -f2- | while IFS= read -r f; do
                t="$c/$(printf '%s' "$f" | md5sum | cut -c1-16).jpg"
                if [ ! -f "$t" ]; then
                  case "$f" in
                    *.[mM][pP]4|*.[wW][eE][bB][mM]|*.[mM][kK][vV]|*.[mM][oO][vV])
                      ffmpeg -nostdin -y -loglevel error -ss 1 -i "$f" -frames:v 1 -vf "scale=480:270:force_original_aspect_ratio=increase,crop=480:270" "$t" 2>/dev/null ;;
                    *) magick "$f[0]" -auto-orient -thumbnail 480x270^ -gravity center -extent 480x270 -quality 85 "$t" 2>/dev/null ;;
                  esac
                fi
                [ -s "$t" ] || t="$f"
                printf 'W\\t%s\\t%s\\n' "$f" "$t"
              done`, "_", Theme.wallpaperDir]
        property bool first: true
        onRunningChanged: if (running) { walls.clear(); first = true; }
        stdout: SplitParser {
            onRead: line => {
                const p = line.split("\t");
                if (p[0] === "CUR") { content.current = p[1]; return; }
                if (p[0] === "SRC") { content.currentSource = p[1] || ""; return; }
                if (p[0] === "W") {
                    walls.append({ path: p[1], thumb: p[2] });
                    if (p[1] === content.current) content.selectCurrent();
                }
            }
        }
    }

    Process {
        id: readEnv
        command: ["cat", win.envFile]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = text.match(/^SCHEME=(.*)$/m);
                const m = text.match(/^MODE=(.*)$/m);
                const k = text.match(/^CONTRAST=(.*)$/m);
                if (k) win.contrast = k[1].trim().replace(/["']/g, "");
                if (s) content.scheme = s[1].trim();
                if (m) content.mode = m[1].trim();
            }
        }
    }

    // ── цвета с выбранных обоев (matugen --dry-run, ничего не применяет)
    property var palCache: ({})
    function palKey() { return content.selThumb + "|" + content.scheme + "|" + content.mode + "|" + win.contrast; }
    Connections {
        target: content
        function onSelThumbChanged() { win.requestPalettes(); }
        function onSchemeChanged() { win.requestPalettes(); if (content.customPal) content.requestCustom(content.customPal.src); }
        function onModeChanged() { win.requestPalettes(); if (content.customPal) content.requestCustom(content.customPal.src); }
    }
    function requestPalettes() {
        if (!win.open || content.selThumb === "") return;
        const cached = win.palCache[win.palKey()];
        if (cached) { content.palLoading = false; content.setPalettes(cached); return; }
        content.palettes = [];
        content.palLoading = true;
        palTimer.restart();
    }
    Timer { id: palTimer; interval: 140; onTriggered: win.startPal() }
    function startPal() {
        if (palProc.running) { palProc.again = true; return; }
        palProc.key = win.palKey();
        palProc.command = ["python3", win.palScript, content.selThumb, content.scheme, content.mode, win.contrast];
        palProc.running = true;
    }
    Process {
        id: palProc
        property string key: ""
        property bool again: false
        stdout: StdioCollector {
            onStreamFinished: {
                const buf = [];
                for (const line of text.split("\n")) {
                    const p = line.split("\t");
                    if (p[0] === "P" && p.length >= 6) buf.push({ src: p[1], p: p[2], s: p[3], t: p[4], pc: p[5] });
                }
                const c = win.palCache; c[palProc.key] = buf; win.palCache = c;
                if (palProc.again) { palProc.again = false; palTimer.restart(); return; }
                if (palProc.key === win.palKey()) { content.palLoading = false; content.setPalettes(buf); }
                else win.requestPalettes();
            }
        }
    }

    // свой цвет из палитры → его палитра для свотча
    Connections {
        target: content
        function onRequestCustom(hex) { customProc.pending = hex; if (!customProc.running) win.startCustom(); }
    }
    function startCustom() {
        if (customProc.pending === "") return;
        customProc.hex = customProc.pending;
        customProc.pending = "";
        customProc.command = ["python3", win.palScript, customProc.hex, content.scheme, content.mode, win.contrast];
        customProc.running = true;
    }
    Process {
        id: customProc
        property string hex: ""
        property string pending: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split("\t");
                if (p[0] === "P" && p.length >= 6) content.customPal = { src: p[1], p: p[2], s: p[3], t: p[4], pc: p[5] };
                if (customProc.pending !== "") Qt.callLater(win.startCustom);
            }
        }
    }

    Process {
        id: applyProc
        onRunningChanged: content.busy = running
    }
    function run(cmd) {
        if (applyProc.running) return;
        // $1 theme.env, $2 changetheme.sh, $3 обои, $4 цвет-источник (может быть пустым — тогда авто)
        applyProc.command = ["sh", "-c", cmd, "_", win.envFile, win.script, content.current, content.currentSource];
        applyProc.running = true;
    }

    // ── карточка
    Item {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.barHeight + Theme.outer + 10 + (win.open ? 0 : -24)
        width: 1200
        height: 450
        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.94
        Behavior on y { Anim { kind: "spatial" } }
        Behavior on opacity { Anim { kind: "effects"; duration: win.open ? 260 : 160 } }
        Behavior on scale { Anim { kind: "spatial" } }

        GlassSurface { anchors.fill: parent; radius: 32; strong: true; sheenEnd: 0.3 }

        PickerCard {
            id: content
            anchors.fill: parent
            model: walls
            onClose: win.open = false
            onApply: (path, color) => {
                if (applyProc.running) return;
                content.current = path;
                content.currentSource = color;
                win.run('"$2" "$3" ${4:+"$4"}');
            }
            // схема/режим: обои и выбранный цвет остаются, меняется только палитра
            onSetScheme: s => {
                if (applyProc.running) return;
                content.scheme = s;
                win.run(`sed -i 's/^SCHEME=.*/SCHEME=${s}/' "$1" && "$2" "$3" \${4:+"$4"}`);
            }
            onSetMode: m => {
                if (applyProc.running) return;
                content.mode = m;
                win.run(`sed -i 's/^MODE=.*/MODE=${m}/' "$1" && "$2" "$3" \${4:+"$4"}`);
            }
        }
    }
}
