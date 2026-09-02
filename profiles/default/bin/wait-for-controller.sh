#!/bin/bash
# Espera até o controle virtual aparecer (máx 10 segundos)
for i in $(seq 1 20); do
    if [ -e /dev/input/event20 ] && cat /sys/class/input/event20/device/name 2>/dev/null | grep -qi "wolf\|xbox\|pad"; then
        echo "Controller found!"
        break
    fi
    sleep 0.5
done
exec /Applications/esde.AppImage --appimage-extract-and-run --no-update-check "$@"
