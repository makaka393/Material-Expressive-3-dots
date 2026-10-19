#!/usr/bin/env bash
# Ставит ассистента glass: Python-окружение (Claude SDK, PyTorch для процессора, scipy),
# модели (Whisper large-v3-turbo q5_0, Silero v5_ru, голоса Piper, Gemma 4 E4B Q4_K_M — локальная, отвечает по умолчанию),
# whisper.cpp с CUDA и службу systemd --user. Повторный запуск докачивает недостающее.
# Локальную модель запускает llama-server — пакет llama.cpp-cuda (AUR).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
A=${GLASS_ASSISTANT_DATA:-$HOME/.local/share/glass-assistant}
mkdir -p "$A"/models/{llm,whisper,tts/piper} "$A"/src "$A"/logs "$A"/app

get() {   # get URL FILE
    [ -s "$2" ] && return 0
    echo "→ $(basename "$2")"
    curl -L --fail -C - -o "$2.part" "$1" && mv "$2.part" "$2"
}

echo "== Python"
[ -x "$A/venv/bin/python" ] || python3 -m venv --system-site-packages "$A/venv"
"$A/venv/bin/pip" install -q --upgrade anthropic scipy piper-tts
"$A/venv/bin/pip" install -q torch --index-url https://download.pytorch.org/whl/cpu

echo "== Модели"
get https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin "$A/models/whisper/ggml-large-v3-turbo-q5_0.bin"
get https://models.silero.ai/models/tts/ru/v5_ru.pt "$A/models/tts/v5_ru.pt"
# английские голоса — Piper (rhasspy/piper-voices), по ~63 МБ
for v in en/en_US/lessac/medium/en_US-lessac-medium en/en_US/ryan/medium/en_US-ryan-medium \
         en/en_GB/alba/medium/en_GB-alba-medium en/en_GB/northern_english_male/medium/en_GB-northern_english_male-medium; do
    for ext in onnx onnx.json; do
        get "https://huggingface.co/rhasspy/piper-voices/resolve/main/$v.$ext" "$A/models/tts/piper/$(basename "$v").$ext"
    done
done
get https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf "$A/models/llm/gemma-4-E4B-it-Q4_K_M.gguf"
command -v llama-server >/dev/null || echo "!! нет llama-server — поставь llama.cpp-cuda (AUR), иначе ответит только Claude"

echo "== whisper.cpp (CUDA)"
if [ ! -x "$A/src/whisper.cpp/build/bin/whisper-server" ]; then
    [ -d "$A/src/whisper.cpp" ] || git clone --depth 1 https://github.com/ggml-org/whisper.cpp.git "$A/src/whisper.cpp"
    cmake -S "$A/src/whisper.cpp" -B "$A/src/whisper.cpp/build" -G Ninja -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CUDA_COMPILER=/opt/cuda/bin/nvcc -DWHISPER_BUILD_TESTS=OFF
    cmake --build "$A/src/whisper.cpp/build" --target whisper-server -j "$(nproc)"
fi

echo "== Служба"
rsync -a --delete --exclude __pycache__ "$HERE/glass_assistant/" "$A/app/glass_assistant/"
mkdir -p "$HOME/.config/systemd/user" "$HOME/.config/glass"
cp "$HERE/glass-assistant.service" "$HOME/.config/systemd/user/"
E="$HOME/.config/glass/assistant.env"
if [ ! -e "$E" ]; then
    printf '# Ключ Claude API для ассистента glass (console.anthropic.com → API Keys).\n# ANTHROPIC_API_KEY=\n' > "$E"
    chmod 600 "$E"
fi
systemctl --user daemon-reload
systemctl --user enable --now glass-assistant
systemctl --user restart glass-assistant
echo "Готово. Ключ Claude — в $E, потом: systemctl --user restart glass-assistant"
