#!/bin/bash
exec > >(tee -a /logs/heroic.log) 2>&1
set -x
source /opt/gow/bash-lib/utils.sh

sudo -S -p '' /opt/gow/startdbus 2>/dev/null || true

prepare_joysticks() {
  local found=0
  for dev in /dev/input/js*; do
    [ -e "$dev" ] || continue
    found=1
    chmod 0666 "$dev" 2>/dev/null || true
    local minor=$(stat -c '%T' "$dev" 2>/dev/null)
    local dbfile="/run/udev/data/c13:${minor}"
    if [ ! -f "$dbfile" ]; then
      gow_log "udev: criando entrada ${dbfile} para ${dev}"
      mkdir -p /run/udev/data
      printf 'I:1\nE:ID_INPUT=1\nE:ID_INPUT_JOYSTICK=1\nE:ID_BUS=usb\n' > "$dbfile"
    elif ! grep -q '^E:ID_INPUT_JOYSTICK=1' "$dbfile"; then
      gow_log "udev: adicionando ID_INPUT_JOYSTICK em ${dbfile}"
      printf 'E:ID_INPUT=1\nE:ID_INPUT_JOYSTICK=1\n' >> "$dbfile"
    fi
  done
  return $((1 - found))
}

gow_log "Aguardando gamepad virtual do Wolf..."
for i in $(seq 1 40); do
  if prepare_joysticks; then
    gow_log "Gamepad(s) encontrado(s):"
    ls -l /dev/input/js* || true
    break
  fi
  sleep 0.5
done

export GDK_BACKEND=wayland
export QT_QPA_PLATFORM=wayland
unset DISPLAY
export APPDIR=/opt/heroic

gow_log "Lancando Heroic..."
/opt/heroic/heroic --no-sandbox \
  --ozone-platform=wayland \
  --enable-features=UseOzonePlatform,WaylandWindowDecorations \
  --remote-debugging-port=9222 &
HEROIC_PID=$!

(
  while kill -0 "$HEROIC_PID" 2>/dev/null; do
    prepare_joysticks >/dev/null 2>&1
    sleep 3
  done
) &

wait "$HEROIC_PID"
echo "heroic saiu com $?"
sleep infinity
