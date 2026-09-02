#!/usr/bin/env bash
set -e
source /opt/gow/bash-lib/utils.sh
gow_log "Installing Dolphin + deps..."
apt-get update -qq
apt-get install -y -qq dolphin-emu qt6-wayland libxcb-cursor0 gdb strace evtest xdotool xwayland wmctrl openbox python3-evdev
gow_log "Dolphin: $(which dolphin-emu), Xwayland: $(which Xwayland), openbox: $(which openbox)"
