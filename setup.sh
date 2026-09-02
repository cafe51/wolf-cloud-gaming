#!/usr/bin/env bash
# ==============================================================================
# Wolf Cloud Gaming - Setup Helper Script
# ==============================================================================
# Este script automatiza a preparação do host e a geração do arquivo de
# configuração do Wolf (/etc/wolf/cfg/config.toml) a partir do .env local.
# ==============================================================================

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${REPO_DIR}/.env"

echo "=== Wolf Cloud Gaming: Configuração do Ambiente ==="

# 1. Carregar variáveis do .env ou usar fallbacks
if [ -f "$ENV_FILE" ]; then
    echo "-> Carregando variáveis de ${ENV_FILE}..."
    # shellcheck disable=SC1090
    source "$ENV_FILE"
else
    echo "-> Arquivo .env não encontrado. Copiando de .env.example..."
    cp "${REPO_DIR}/.env.example" "$ENV_FILE"
    # shellcheck disable=SC1090
    source "$ENV_FILE"
fi

WOLF_BASE_DIR="${WOLF_BASE_DIR:-$REPO_DIR}"
ROMS_DIR="${ROMS_DIR:-$HOME/roms-gdrive}"
STEAM_LIBRARY_DIR="${STEAM_LIBRARY_DIR:-/mnt/storage/games/steam}"

echo "-> Diretório base (WOLF_BASE_DIR): $WOLF_BASE_DIR"
echo "-> Diretório de ROMs (ROMS_DIR): $ROMS_DIR"
echo "-> Biblioteca Steam (STEAM_LIBRARY_DIR): $STEAM_LIBRARY_DIR"

# 2. Carregar módulos do kernel para gamepad virtual
echo "-> Verificando módulos de kernel uhid e uinput..."
sudo modprobe uhid uinput 2>/dev/null || true
if [ ! -f /etc/modules-load.d/uhid.conf ]; then
    echo "uhid" | sudo tee /etc/modules-load.d/uhid.conf >/dev/null || true
fi

# 3. Garantir permissões de execução nos scripts customizados
echo "-> Ajustando permissões de execução dos scripts..."
find "${REPO_DIR}/profiles/default/bin" -type f \( -name "*.sh" -o -name "*.py" -o -name "*.AppImage" -o -name "eden" -o -name "ryujinx*" \) -exec chmod +x {} + 2>/dev/null || true

# 4. Gerar /etc/wolf/cfg/config.toml
echo "-> Gerando configuração do Wolf em /etc/wolf/cfg/config.toml..."
sudo mkdir -p /etc/wolf/cfg

CONFIG_TARGET="/etc/wolf/cfg/config.toml"
sudo cp "${REPO_DIR}/config.example.toml" "$CONFIG_TARGET"

# Substituir placeholders pelos caminhos configurados
sudo sed -i "s|/opt/wolf-data|${WOLF_BASE_DIR}|g" "$CONFIG_TARGET"
sudo sed -i "s|/home/user/roms-gdrive|${ROMS_DIR}|g" "$CONFIG_TARGET"
sudo sed -i "s|/mnt/storage/games/steam|${STEAM_LIBRARY_DIR}|g" "$CONFIG_TARGET"

echo "-> Permissões em /dev/uinput..."
sudo chmod 0666 /dev/uinput 2>/dev/null || true

echo "=== Configuração concluída com sucesso! ==="
echo "Você já pode iniciar o servidor com:"
echo "  docker compose up -d"
