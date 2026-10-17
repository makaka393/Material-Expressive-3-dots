pragma Singleton
import QtQuick
import Quickshell

// Связки между окнами оболочки без IPC: виджет на рабочем столе открывает лаунчер и т.п.
Singleton {
    signal launcher(string prefill)       // открыть лаунчер (prefill: "", ":" эмодзи, "=" калькулятор, "?" ассистент)
}
