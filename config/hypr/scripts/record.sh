#!/usr/bin/env bash
# record.sh — запись экрана для бара (Quickshell, остров «Запись экрана»)
#
#   record.sh start <region|full> <звук 0|1> <микрофон 0|1> <gif 0|1>
#   record.sh stop          остановить (и сделать GIF, если просили)
#   record.sh toggle        идёт запись → стоп, иначе открыть меню в баре
#
# Пишет gpu-screen-recorder (NVENC — почти не грузит систему), если его нет — wf-recorder.
# Файлы: ~/Videos/Screencasts. Готовый файл сразу в буфере обмена — можно вставить в Telegram.
set -uo pipefail

RUN="${XDG_RUNTIME_DIR:-/tmp}"
STATE="$RUN/glass-rec.json"
PIDF="$RUN/glass-rec.pid"
INFO="$RUN/glass-rec.info"
VID="$(xdg-user-dir VIDEOS 2>/dev/null || echo "$HOME/Videos")"
[ "$VID" = "$HOME" ] && VID="$HOME/Videos"
DIR="$VID/Screencasts"
mkdir -p "$DIR"

state() { printf '%s' "$1" > "$STATE"; }   # пишем в тот же файл (бар следит за ним)
notify() { timeout 2 notify-send -a "Запись экрана" "$@" 2>/dev/null || true; }
running() { [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; }

case "${1:-toggle}" in

toggle)
  if running; then exec "$0" stop; fi
  exec qs ipc -c glass call recorder menu ;;

start)
  running && exit 0
  MODE="${2:-region}"; AUDIO="${3:-1}"; MIC="${4:-0}"; GIF="${5:-0}"
  F="$DIR/$(date +%Y-%m-%d_%H-%M-%S).mp4"

  # монитор в фокусе
  MON=$(hyprctl monitors -j | python3 -c 'import json,sys; m=json.load(sys.stdin); print(next((x["name"] for x in m if x.get("focused")), m[0]["name"]))')

  GEOM=""
  if [ "$MODE" = region ]; then
    eval "$(python3 - <<'PY'
import json, os
try: c = json.load(open(os.path.expanduser("~/.cache/matugen/colors.json")))
except Exception: c = {}
g = lambda k, d: c.get(k, d).lstrip("#")
print(f'P={g("primary","a8c7fa")} S={g("surfaceLowest","0c0e13")}')
PY
)"
    G=$(slurp -d -b "${S}88" -c "${P}ff" -s "${P}1f" -B "${P}55" -w 3 -f '%x %y %w %h') || exit 0
    read -r X Y W H <<<"$G"
    W=$((W / 2 * 2)); H=$((H / 2 * 2))          # кодеки любят чётные размеры
    [ "$W" -ge 16 ] && [ "$H" -ge 16 ] || exit 0
    GEOM="$X $Y $W $H"
  fi

  # job control: иначе фоновому процессу достаётся «игнорировать SIGINT», и стоп не сработает
  set -m
  if command -v gpu-screen-recorder >/dev/null; then
    ARGS=(-f 60 -c mp4 -k h264 -q very_high -cursor yes -o "$F")
    if [ -n "$GEOM" ]; then read -r X Y W H <<<"$GEOM"; ARGS=(-w region -region "${W}x${H}+${X}+${Y}" "${ARGS[@]}")
    else ARGS=(-w "$MON" "${ARGS[@]}"); fi
    if [ "$AUDIO" = 1 ] && [ "$MIC" = 1 ]; then ARGS+=(-a "default_output|default_input")
    elif [ "$AUDIO" = 1 ]; then ARGS+=(-a default_output)
    elif [ "$MIC" = 1 ]; then ARGS+=(-a default_input); fi
    gpu-screen-recorder "${ARGS[@]}" >"$RUN/glass-rec.log" 2>&1 < /dev/null &
  else
    ARGS=(-f "$F" -c libx264 -p preset=veryfast -p crf=20 -x yuv420p)
    if [ -n "$GEOM" ]; then read -r X Y W H <<<"$GEOM"; ARGS+=(-g "$X,$Y ${W}x${H}"); else ARGS+=(-o "$MON"); fi
    # wf-recorder не умеет смешивать два источника — берём звук системы, иначе микрофон
    if [ "$AUDIO" = 1 ]; then ARGS+=("--audio=$(pactl get-default-sink).monitor")
    elif [ "$MIC" = 1 ]; then ARGS+=("--audio=$(pactl get-default-source)"); fi
    wf-recorder "${ARGS[@]}" >"$RUN/glass-rec.log" 2>&1 < /dev/null &
  fi
  echo $! > "$PIDF"; disown
  printf '%s\n%s\n' "$F" "$GIF" > "$INFO"
  sleep 0.4
  if ! running; then
    state '{"recording":false}'
    notify -u critical "Не удалось начать запись" "$(tail -n 3 "$RUN/glass-rec.log")"
    exit 1
  fi
  state "{\"recording\":true,\"start\":$(date +%s),\"file\":\"$F\"}" ;;

stop)
  running || { state '{"recording":false}'; exit 0; }
  PID=$(cat "$PIDF")
  kill -INT "$PID" 2>/dev/null
  for _ in $(seq 100); do kill -0 "$PID" 2>/dev/null || break; sleep 0.1; done
  rm -f "$PIDF"
  F=$(sed -n 1p "$INFO"); GIF=$(sed -n 2p "$INFO")
  OUT="$F"
  if [ "$GIF" = 1 ] && [ -s "$F" ]; then
    state '{"recording":false,"busy":true}'
    OUT="${F%.mp4}.gif"
    ffmpeg -nostdin -y -loglevel error -i "$F" \
      -vf "fps=15,scale='min(960,iw)':-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" \
      "$OUT" || OUT="$F"
  fi
  state '{"recording":false}'
  [ -s "$OUT" ] || { notify -u critical "Запись пустая" "$(tail -n 3 "$RUN/glass-rec.log")"; exit 1; }

  # в буфер обмена как файл — вставляется в Telegram/Discord/Dolphin
  printf 'file://%s\n' "$OUT" | wl-copy -t text/uri-list
  THUMB="$RUN/glass-rec-thumb.jpg"
  ffmpeg -nostdin -y -loglevel error -i "$F" -frames:v 1 -vf "scale=256:-2" "$THUMB" 2>/dev/null || THUMB=video-x-generic
  timeout 3 qs ipc -c glass call island recording "$THUMB" "$OUT" >/dev/null 2>&1 || true   # всплывашка в острове
  SIZE=$(du -h "$OUT" | cut -f1)
  (
    A=$(notify-send -a "Запись экрана" -i "$THUMB" -A "open=Открыть" -A "folder=Папка" \
        "Запись сохранена" "$(basename "$OUT") · $SIZE · скопирована в буфер" 2>/dev/null)
    case "$A" in
      open) xdg-open "$OUT" ;;
      folder) xdg-open "$DIR" ;;
    esac
  ) >/dev/null 2>&1 &
  disown ;;

*) echo "record.sh start <region|full> <звук 0|1> <мик 0|1> <gif 0|1> | stop | toggle"; exit 1 ;;
esac
