#!/usr/bin/env bash
# ==============================================================================
# Heroic Games Launcher Startup (Sway + Xwayland + dbus-run-session)
# ==============================================================================
# Executado como usuário `retro` em /opt/gow/startup.sh dentro de xfce:edge.
# - Trunca /logs/heroic.log a cada sessão (sem crescimento infinito / set -x).
# - Roda sobre Sway com `xwayland enable` na resolução dinâmica do Moonlight
#   (suporte a xdg_activation_v1 + fallback X11 para Protons/jogos antigos).
# - Encerra o Sway (e o container) assim que o Heroic fecha (sem sleep infinity).
# - Isolamento e metadados udev de controles são tratados como root pelo
#   /etc/cont-init.d/99-isolate-inputs.sh.
# ==============================================================================
set -e

mkdir -p /logs 2>/dev/null || true
exec > >(tee /logs/heroic.log) 2>&1

source /opt/gow/bash-lib/utils.sh

gow_log "[Heroic] Iniciando sessão (resolução alvo: ${GAMESCOPE_WIDTH:-1920}x${GAMESCOPE_HEIGHT:-1080})"

# Aguarda brevemente o gamepad virtual aparecer apenas para diagnóstico (máx 5s)
for _ in $(seq 1 10); do
  if compgen -G "/dev/input/js*" >/dev/null 2>&1; then
    gow_log "[Heroic] Gamepad(s) detectado(s): $(ls /dev/input/js* 2>/dev/null | tr '\n' ' ')"
    break
  fi
  sleep 0.5
done

export GAMESCOPE_WIDTH="${GAMESCOPE_WIDTH:-1920}"
export GAMESCOPE_HEIGHT="${GAMESCOPE_HEIGHT:-1080}"
export XDG_CURRENT_DESKTOP="sway"
export XDG_SESSION_DESKTOP="sway"
export XDG_SESSION_TYPE="wayland"
export GDK_BACKEND="wayland,x11"
export QT_QPA_PLATFORM="wayland;xcb"
export SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS="0"
export APPDIR="/opt/heroic"

SWAY_CFG="${XDG_RUNTIME_DIR:-/tmp}/sway-heroic.conf"
mkdir -p "$(dirname "$SWAY_CFG")"
cat > "$SWAY_CFG" <<EOF
# Configuração Sway dedicada para Heroic Games Launcher no Wolf
xwayland enable
workspace_layout tabbed
default_border none
default_floating_border pixel 2

output * resolution ${GAMESCOPE_WIDTH}x${GAMESCOPE_HEIGHT} position 0,0

# Atalhos de emergência por teclado
bindsym Mod1+F4 kill
bindsym Mod1+Shift+q kill

# Jogos Proton/Wine/Gamescope em tela cheia com foco automático
for_window [class="^steam_app_.*"] fullscreen enable, focus
for_window [class="(?i)^(wine|wine64|proton|steam_proton|gamescope).*"] fullscreen enable, focus
for_window [class="(?i).*\\.exe$" window_type="normal"] fullscreen enable, focus

# Janela principal do Heroic ocupando 100% em aba
for_window [app_id="heroic"] layout tabbed
for_window [class="(?i)^heroic$"] layout tabbed

# Diálogos, popups de login e utilitários flutuantes
for_window [window_type="dialog"] floating enable
for_window [window_type="utility"] floating enable
for_window [window_type="popup_menu"] floating enable

# Inicia Heroic em Wayland nativo (com Xwayland disponível via Sway para jogos)
# e encerra o Sway automaticamente ao fechar o Heroic.
workspace main; exec sh -c '/opt/heroic/heroic --no-sandbox --ozone-platform=wayland --enable-features=UseOzonePlatform,WaylandWindowDecorations; swaymsg exit || killall sway'
EOF

gow_log "[Heroic] Subindo Sway + dbus-run-session (config: ${SWAY_CFG})..."
exec dbus-run-session -- sway --unsupported-gpu -c "$SWAY_CFG"
