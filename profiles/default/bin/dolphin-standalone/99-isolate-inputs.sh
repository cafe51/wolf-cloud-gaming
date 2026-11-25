#!/usr/bin/env bash
# ==============================================================================
# Isolamento de Inputs para Containers Wolf (Steam, ES-DE e Heroic)
# ==============================================================================
# Executado via `source` pelo /entrypoint.sh (como root, com `set -e` ativo) em
# /etc/cont-init.d/99-isolate-inputs.sh, e em modo daemon via `--isolate-inputs-daemon`.
#
# Regras:
#   1. Gamepads virtuais do Wolf: garante acesso (0666) e metadados udev em
#      /run/udev/data/c<major>:<minor> usando major:minor DECIMAIS do sysfs.
#   2. Outros dispositivos virtuais do Wolf (mouse, teclado, touch, motion):
#      mantidos intactos (nunca marcados como joystick nem bloqueados).
#   3. Controles virtuais do Steam Input (/sys/devices/virtual/*): liberados
#      (0666 + metadados udev mínimos se ausentes), nunca bloqueados.
#   4. Joysticks/gamepads físicos do host (fora de /sys/devices/virtual/*):
#      bloqueados dentro do container com chmod 000.
# ==============================================================================

_ISOLATE_PIDFILE="/run/isolate-inputs.pid"

_isolate_write_udev_joystick() {
  local devnum="$1"
  local profile="$2"
  [ -n "$devnum" ] || return 0

  local dbfile="/run/udev/data/c${devnum}"
  if [ -f "$dbfile" ] && grep -q '^E:ID_INPUT_JOYSTICK=1$' "$dbfile" 2>/dev/null; then
    return 0
  fi

  mkdir -p /run/udev/data 2>/dev/null || return 0

  if [ "$profile" = "wolf-xbox" ]; then
    printf 'I:1\nE:ID_INPUT=1\nE:ID_INPUT_JOYSTICK=1\nE:ID_BUS=usb\nE:ID_VENDOR=Microsoft\nE:ID_VENDOR_ID=045e\nE:ID_MODEL=Xbox_One_Controller\nE:ID_MODEL_ID=02ea\nE:ID_REVISION=0408\nE:ID_SERIAL=noserial\nE:ID_TYPE=hid\nG:seat\nG:uaccess\nQ:seat\nQ:uaccess\nV:1\n' > "$dbfile" 2>/dev/null || true
  else
    printf 'I:1\nE:ID_INPUT=1\nE:ID_INPUT_JOYSTICK=1\nE:ID_BUS=usb\nG:seat\nG:uaccess\nQ:seat\nQ:uaccess\nV:1\n' > "$dbfile" 2>/dev/null || true
  fi
}

_isolate_ensure_mode_0666() {
  local dev="$1"
  local perms
  perms=$(stat -c '%a' "$dev" 2>/dev/null || true)
  if [ "$perms" != "666" ] && [ "$perms" != "777" ]; then
    chmod 0666 "$dev" 2>/dev/null || true
  fi
}

_isolate_has_joystick_cap() {
  local base="$1"
  local devname="$2"

  if [[ "$base" == js* ]]; then
    return 0
  fi

  if compgen -G "/sys/class/input/${base}/device/js*" >/dev/null 2>&1; then
    return 0
  fi

  # Nunca classificar teclados/mouses/controles de mídia como joystick por nome
  case "$devname" in
    *[Kk]eyboard*|*[Mm]ouse*|*[Tt]ouch*|*Consumer\ Control*|*System\ Control*|*[Mm]otion*)
      return 1
      ;;
  esac

  case "$devname" in
    *[Gg]amepad*|*[Jj]oystick*|*[Cc]ontroller*|*X-Box*|*Xbox*|*DualSense*|*DualShock*|*Nintendo*|*8BitDo*|*EasySMX*|*SHANWAN*|*Flydigi*|*[Pp]ad*)
      return 0
      ;;
  esac

  return 1
}

_isolate_input_devices() {
  local verbose="${1:-0}"
  local dev base devname devnum devpath perms

  for dev in /dev/input/js* /dev/input/event*; do
    [ -e "$dev" ] || continue

    base=$(basename "$dev")
    devname=$(cat "/sys/class/input/${base}/device/name" 2>/dev/null || true)
    [ -n "$devname" ] || continue

    devnum=$(cat "/sys/class/input/${base}/dev" 2>/dev/null || true)
    devpath=$(readlink -f "/sys/class/input/${base}/device" 2>/dev/null || true)

    # 1. Dispositivos virtuais do Wolf
    case "$devname" in
      *[Ww]olf*)
        case "$devname" in
          *[Mm]ouse*|*[Kk]eyboard*|*[Tt]ouch*|*[Mm]otion*|*[Aa]ccelerometer*)
            # Preserva mouse/teclado/touch/sensores virtuais do Wolf sem marcá-los como joystick
            continue
            ;;
        esac

        if _isolate_has_joystick_cap "$base" "$devname"; then
          _isolate_ensure_mode_0666 "$dev"
          case "$devname" in
            *X-Box*|*Xbox*|*xbox*)
              _isolate_write_udev_joystick "$devnum" "wolf-xbox"
              ;;
            *)
              _isolate_write_udev_joystick "$devnum" "generic-joystick"
              ;;
          esac
        fi
        continue
        ;;
    esac

    # 2. Dispositivos virtuais fora do Wolf (ex.: Steam Virtual Gamepad / Steam Input via uinput)
    case "$devpath" in
      /sys/devices/virtual/*)
        if _isolate_has_joystick_cap "$base" "$devname"; then
          _isolate_ensure_mode_0666 "$dev"
          _isolate_write_udev_joystick "$devnum" "generic-joystick"
        fi
        continue
        ;;
    esac

    # 3. Dispositivos físicos do host: bloqueia apenas joysticks/gamepads
    if _isolate_has_joystick_cap "$base" "$devname"; then
      perms=$(stat -c '%a' "$dev" 2>/dev/null || true)
      if [ "$perms" != "0" ] && [ "$perms" != "000" ]; then
        chmod 000 "$dev" 2>/dev/null || true
        if [ "$verbose" = "1" ]; then
          echo "[Isolamento] Bloqueado joystick físico: ${dev} (${devname})"
        fi
      fi
    fi
  done
}

# Modo daemon (executado em processo próprio via `bash <script> --isolate-inputs-daemon`)
if [ "${1:-}" = "--isolate-inputs-daemon" ]; then
  trap 'rm -f "${_ISOLATE_PIDFILE}"' EXIT INT TERM
  echo "$$" > "${_ISOLATE_PIDFILE}" 2>/dev/null || true

  while true; do
    _isolate_input_devices 0
    sleep 1
  done
  exit 0
fi

# Execução inicial (sourced pelo /entrypoint.sh — NÃO usar `exit` aqui!)
echo "[Isolamento] Aplicando isolamento imediato de inputs (sysfs decimal + whitelist virtual)..."
_isolate_input_devices 1

# Garante instância única do daemon em background
_ISOLATE_RUNNING=0
if [ -f "${_ISOLATE_PIDFILE}" ]; then
  _ISOLATE_OLD_PID=$(cat "${_ISOLATE_PIDFILE}" 2>/dev/null || true)
  if [ -n "${_ISOLATE_OLD_PID}" ] && kill -0 "${_ISOLATE_OLD_PID}" 2>/dev/null; then
    _ISOLATE_RUNNING=1
  fi
fi

if [ "${_ISOLATE_RUNNING}" -eq 0 ]; then
  _ISOLATE_SCRIPT="${BASH_SOURCE[0]:-/etc/cont-init.d/99-isolate-inputs.sh}"
  echo "[Isolamento] Iniciando daemon único de monitoramento em segundo plano..."
  nohup bash "${_ISOLATE_SCRIPT}" --isolate-inputs-daemon </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
else
  echo "[Isolamento] Daemon já em execução (PID ${_ISOLATE_OLD_PID}); ignorando duplicata."
fi

unset _ISOLATE_RUNNING _ISOLATE_OLD_PID _ISOLATE_SCRIPT _ISOLATE_PIDFILE
