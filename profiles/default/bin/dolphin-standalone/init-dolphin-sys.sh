#!/usr/bin/env bash
set -e
source /opt/gow/bash-lib/utils.sh

gow_log "Updating Dolphin Sys to v2606..."

# Wait for dolphin to be installed by 89-dolphin.sh
for i in $(seq 1 30); do
    if [ -f /usr/games/dolphin-emu-nogui ]; then
        break
    fi
    sleep 1
done

if [ -d /tmp/dolphin-sys-v2606/GameSettings ]; then
    gow_log "Copying Sys v2606 files..."
    cp -af /tmp/dolphin-sys-v2606/* /usr/share/games/dolphin-emu/sys/ 2>/dev/null || \
    cp -af /tmp/dolphin-sys-v2606/* /usr/share/dolphin-emu/sys/ 2>/dev/null
    gow_log "Dolphin Sys updated to v2606 (GameSettings: $(ls /usr/share/games/dolphin-emu/sys/GameSettings/ 2>/dev/null | wc -l) files)"
else
    gow_log "WARNING: Sys v2606 not found, using apt version"
fi
