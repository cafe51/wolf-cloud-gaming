#!/bin/bash
set -e

DOLPHIN_DIR="/home/retro/dolphin-standalone"
DOLPHIN_BIN="$DOLPHIN_DIR/usr/games/dolphin-emu"
DATA_DIR="/home/retro/.local/share/dolphin-emu"
CONFIG_DIR="/home/retro/.config/dolphin-emu"

# Instalar Dolphin se não estiver presente
if [ ! -f "$DOLPHIN_BIN" ]; then
    echo "Installing Dolphin standalone..."
    mkdir -p "$DOLPHIN_DIR"
    cd "$DOLPHIN_DIR"
    apt-get update -qq
    apt-get download dolphin-emu dolphin-emu-data
    for deb in *.deb; do
        dpkg-deb -x "$deb" .
    done
    # Instalar dependências
    apt-get install -y -qq $(apt-cache depends dolphin-emu 2>/dev/null | grep Depends | sed 's/.*Depends: //;s/<.*//' | tr '\n' ' ') 2>/dev/null || true
    echo "Dolphin installed."
fi

# Setup do diretório de dados (link para dados compartilhados)
mkdir -p "$DATA_DIR" "$CONFIG_DIR"

# Garantir que dados do host estão acessíveis
# Os bind mounts já cuidam disso via config.toml

# Launch Dolphin
exec "$DOLPHIN_BIN" "$@"
