pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Что чаще запускаешь из лаунчера — то выше в списке. Плюс недавние эмодзи.
// Файл: ~/.config/glass/launcher.json
Singleton {
    id: root

    readonly property var apps: data.apps         // id приложения → сколько раз запускали
    readonly property var emoji: data.emoji       // недавние эмодзи, свежие — первые

    function count(id) { return apps[id] || 0; }
    function used(id) {
        const a = Object.assign({}, data.apps);
        a[id] = (a[id] || 0) + 1;
        data.apps = a;
    }
    function usedEmoji(e) {
        data.emoji = [e].concat(data.emoji.filter(x => x !== e)).slice(0, 27);
    }

    FileView {
        path: Config.dir + "/launcher.json"
        printErrors: false
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter(); }
        JsonAdapter {
            id: data
            property var apps: ({})
            property var emoji: []
        }
    }
}
