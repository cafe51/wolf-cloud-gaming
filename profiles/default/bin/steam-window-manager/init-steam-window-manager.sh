#!/usr/bin/env bash
# Script de inicialização do gerenciador de janelas e foco para o Steam no Wolf
set -e

echo "[SteamWindowManager] Inicializando configurações de foco e tela cheia..."

# Garante permissões de execução
chmod +x /usr/local/bin/steam-window-manager.py 2>/dev/null || true

# Inicia o daemon em segundo plano como usuário retro
nohup su - retro -c '
export XDG_RUNTIME_DIR=/run/user/wolf
export SWAYSOCK=/run/user/wolf/sway.socket
python3 /usr/local/bin/steam-window-manager.py
' > /tmp/steam-window-manager.log 2>&1 &
disown

echo "[SteamWindowManager] Daemon iniciado em segundo plano com sucesso."
