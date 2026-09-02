#!/bin/bash
exec >/tmp/dolphin.log 2>&1
set -x
echo "=== Xwayland + audio + ES-DE freeze $(date) ==="
mkdir -p /home/retro/.local/share/dolphin-emu /home/retro/.config/dolphin-emu
export PULSE_SERVER="unix:/run/user/wolf/pulse-socket"
export PULSE_LATENCY_MSEC=30
export CUBEB_BACKEND=pulse

# Congela ES-DE para evitar double-input
ES_PID=$(pidof es-de)
if [ -n "$ES_PID" ]; then
    kill -STOP $ES_PID
fi

Xwayland :5 -fullscreen &
XPID=$!
WATCHDOG_PID=""

trap 'kill $WATCHDOG_PID 2>/dev/null; kill $XPID 2>/dev/null; [ -n "$ES_PID" ] && kill -CONT $ES_PID' EXIT

sleep 2
export DISPLAY=:5

# Watchdog de hotkeys no gamepad (Guide + botões → xdotool no :5)
/home/retro/.config/dolphin-emu/dolphin-hotkeys.py &
WATCHDOG_PID=$!

/usr/games/dolphin-emu-nogui -p x11 \
  -a HLE \
  -C Display.Fullscreen=True \
  -e "$2"
