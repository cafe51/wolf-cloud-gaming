#!/usr/bin/env bash
# Daemon de isolamento: bloqueia joysticks/gamepads físicos vindo do host.
# Whitelist: apenas controles virtuais do Wolf/Moonlight ou virtuais do Steam Input.

isolate_devices() {
  for dev in /dev/input/js* /dev/input/event*; do
    [ -e "$dev" ] || continue

    devname=$(cat "/sys/class/input/$(basename "$dev")/device/name" 2>/dev/null)
    [ -n "$devname" ] || continue

    case "$devname" in
      *Wolf*|*wolf*)
        # Whitelist: Controle virtual do Wolf / Moonlight (SEMPRE Slot 0 / Player 1)
        chmod 0777 "$dev" 2>/dev/null || true
        minor=$(stat -c '%T' "$dev" 2>/dev/null)
        if [ -n "$minor" ]; then
          mkdir -p /run/udev/data
          printf 'I:1\nE:ID_INPUT=1\nE:ID_INPUT_JOYSTICK=1\nE:ID_BUS=usb\nE:ID_VENDOR=Microsoft\nE:ID_VENDOR_ID=045e\nE:ID_MODEL=Xbox_One_Controller\nE:ID_MODEL_ID=02ea\nE:ID_REVISION=0408\nE:ID_SERIAL=noserial\nE:ID_TYPE=hid\nG:seat\nG:uaccess\nQ:seat\nQ:uaccess\nV:1\n' > "/run/udev/data/c13:${minor}" 2>/dev/null || true
        fi
        ;;
      *)
        is_joystick=0
        if [[ "$(basename "$dev")" == js* ]]; then
          is_joystick=1
        elif [ -d "/sys/class/input/$(basename "$dev")/device/js0" ] || [ -e "/sys/class/input/$(basename "$dev")/device/js0" ] || ls -d "/sys/class/input/$(basename "$dev")/device/js"* >/dev/null 2>&1; then
          is_joystick=1
        else
          case "$devname" in
            *pad*|*Pad*|*Joystick*|*joystick*|*Gamepad*|*gamepad*|*Controller*|*controller*|"Microsoft X-Box 360 pad"|*X-Box*|*Xbox*|*DualSense*|*DualShock*|*Nintendo*|*Sony*|*8BitDo*|*EasySMX*|*SHANWAN*|*Flydigi*|*Generic*|*Logitech*)
              is_joystick=1
              ;;
          esac
        fi

        if [ "$is_joystick" -eq 1 ]; then
          perms=$(stat -c "%a" "$dev" 2>/dev/null)
          if [ "$perms" != "0" ] && [ "$perms" != "000" ]; then
            chmod 000 "$dev"
            echo "[Isolamento] Bloqueado: $dev ($devname)"
          fi
        fi
        ;;
    esac
  done
}

echo "[Isolamento] Aplicando bloqueio imediato inicial..."
isolate_devices

echo "[Isolamento] Iniciando daemon de monitoramento contínuo em segundo plano..."
nohup bash -c '
isolate_devices() {
  for dev in /dev/input/js* /dev/input/event*; do
    [ -e "$dev" ] || continue

    devname=$(cat "/sys/class/input/$(basename "$dev")/device/name" 2>/dev/null)
    [ -n "$devname" ] || continue

    case "$devname" in
      *Wolf*|*wolf*)
        chmod 0777 "$dev" 2>/dev/null || true
        minor=$(stat -c '%T' "$dev" 2>/dev/null)
        if [ -n "$minor" ]; then
          mkdir -p /run/udev/data
          printf 'I:1\nE:ID_INPUT=1\nE:ID_INPUT_JOYSTICK=1\nE:ID_BUS=usb\nE:ID_VENDOR=Microsoft\nE:ID_VENDOR_ID=045e\nE:ID_MODEL=Xbox_One_Controller\nE:ID_MODEL_ID=02ea\nE:ID_REVISION=0408\nE:ID_SERIAL=noserial\nE:ID_TYPE=hid\nG:seat\nG:uaccess\nQ:seat\nQ:uaccess\nV:1\n' > "/run/udev/data/c13:${minor}" 2>/dev/null || true
        fi
        ;;
      *)
        is_joystick=0
        if [[ "$(basename "$dev")" == js* ]]; then
          is_joystick=1
        elif [ -d "/sys/class/input/$(basename "$dev")/device/js0" ] || [ -e "/sys/class/input/$(basename "$dev")/device/js0" ] || ls -d "/sys/class/input/$(basename "$dev")/device/js"* >/dev/null 2>&1; then
          is_joystick=1
        else
          case "$devname" in
            *pad*|*Pad*|*Joystick*|*joystick*|*Gamepad*|*gamepad*|*Controller*|*controller*|"Microsoft X-Box 360 pad"|*X-Box*|*Xbox*|*DualSense*|*DualShock*|*Nintendo*|*Sony*|*8BitDo*|*EasySMX*|*SHANWAN*|*Flydigi*|*Generic*|*Logitech*)
              is_joystick=1
              ;;
          esac
        fi

        if [ "$is_joystick" -eq 1 ]; then
          perms=$(stat -c "%a" "$dev" 2>/dev/null)
          if [ "$perms" != "0" ] && [ "$perms" != "000" ]; then
            chmod 000 "$dev"
          fi
        fi
        ;;
    esac
  done
}

while true; do
  isolate_devices
  sleep 1
done
' >/dev/null 2>&1 &
disown
