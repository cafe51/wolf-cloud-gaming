#!/bin/bash
# Espera até o controle virtual aparecer (máx 10 segundos)
for i in $(seq 1 20); do
    for dev in /dev/input/event*; do
        [ -e "$dev" ] || continue
        if cat "/sys/class/input/$(basename "$dev")/device/name" 2>/dev/null | grep -qi "wolf\|xbox\|pad"; then
            echo "Controller found at $dev!"
            break 2
        fi
    done
    sleep 0.5
done
exec /Applications/esde.AppImage --appimage-extract-and-run --no-update-check "$@"
