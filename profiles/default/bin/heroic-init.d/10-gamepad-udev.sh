#!/bin/bash
# Roda como root - cria entradas udev pros gamepads (com isolamento e metadados completos Xbox One)
for dev in /dev/input/js* /dev/input/event*; do
  [ -e "$dev" ] || continue
  devname=$(cat "/sys/class/input/$(basename "$dev")/device/name" 2>/dev/null)
  case "$devname" in
    *Wolf*|*wolf*)
      chmod 0777 "$dev" 2>/dev/null || true
      minor=$(stat -c '%T' "$dev" 2>/dev/null)
      if [ -n "$minor" ]; then
        dbfile="/run/udev/data/c13:${minor}"
        mkdir -p /run/udev/data
        printf 'I:1\nE:ID_INPUT=1\nE:ID_INPUT_JOYSTICK=1\nE:ID_BUS=usb\nE:ID_VENDOR=Microsoft\nE:ID_VENDOR_ID=045e\nE:ID_MODEL=Xbox_One_Controller\nE:ID_MODEL_ID=02ea\nE:ID_REVISION=0408\nE:ID_SERIAL=noserial\nE:ID_TYPE=hid\nG:seat\nG:uaccess\nQ:seat\nQ:uaccess\nV:1\n' > "$dbfile" 2>/dev/null || true
      fi
      ;;
    *)
      chmod 000 "$dev" 2>/dev/null || true
      ;;
  esac
done
if [ -f "/etc/cont-init.d/99-isolate-inputs.sh" ]; then
  /etc/cont-init.d/99-isolate-inputs.sh
fi
echo "Gamepad udev setup completo (Slot 0 isolado para Wolf com daemon de monitoramento)"

# Install 32-bit libraries from persistent apt-cache
if [ -d "/home/retro/.config/heroic/apt-cache" ]; then
  dpkg --add-architecture i386 2>/dev/null || true
  dpkg -i /home/retro/.config/heroic/apt-cache/*.deb 2>/dev/null || true
  echo "32-bit libraries setup complete"
fi

# Neutralize Proton dummy steam.exe that causes lsteamclient assertion crash
PREFIX_DIR="${HEROIC_FALLOUT_PREFIX:-$HOME/Games/Heroic/Prefixes/default/Fallout 2 A Post Nuclear Role Playing Game}"
if [ -d "$PREFIX_DIR" ]; then
  for dir in "$PREFIX_DIR/drive_c/windows/system32" "$PREFIX_DIR/drive_c/windows/syswow64"; do
    if [ -f "$dir/attrib.exe" ]; then
      cp -f "$dir/attrib.exe" "$dir/steam.exe" 2>/dev/null || true
      chmod 0555 "$dir/steam.exe" 2>/dev/null || true
    fi
  done
fi
