#!/usr/bin/env bash
# ==============================================================================
# Init Auxiliar do Container Heroic (/etc/cont-init.d/10-gamepad-udev.sh)
# ==============================================================================
# Executado via `source` pelo /entrypoint.sh (como root, com `set -e` ativo).
# Nota: o isolamento e metadados udev dos controles agora são responsabilidade
# exclusiva de /etc/cont-init.d/99-isolate-inputs.sh (evitando daemons duplicados
# e bloqueio indevido de mouse/teclado).
# ==============================================================================

# 1. Instalar bibliotecas 32-bit (i386) do cache persistente, se presente
if [ -d "/home/retro/.config/heroic/apt-cache" ] && compgen -G "/home/retro/.config/heroic/apt-cache/*.deb" >/dev/null 2>&1; then
  dpkg --add-architecture i386 2>/dev/null || true
  dpkg -i /home/retro/.config/heroic/apt-cache/*.deb 2>/dev/null || true
  echo "[Heroic-Init] 32-bit libraries setup complete"
fi

# 2. Neutralizar dummy steam.exe em prefixo Proton clássico (evita crash lsteamclient)
# Busca variável explícita ou qualquer prefixo montado em /home/*/Games/Heroic/Prefixes/default/
_HEROIC_FALLOUT_CANDIDATES=()
if [ -n "${HEROIC_FALLOUT_PREFIX:-}" ]; then
  _HEROIC_FALLOUT_CANDIDATES+=("${HEROIC_FALLOUT_PREFIX}")
else
  for _candidate in /home/*/Games/Heroic/Prefixes/default/"Fallout 2 A Post Nuclear Role Playing Game"; do
    if [ -d "$_candidate" ]; then
      _HEROIC_FALLOUT_CANDIDATES+=("$_candidate")
    fi
  done
fi

for _prefix_dir in "${_HEROIC_FALLOUT_CANDIDATES[@]}"; do
  [ -d "$_prefix_dir" ] || continue
  for _sysdir in "${_prefix_dir}/drive_c/windows/system32" "${_prefix_dir}/drive_c/windows/syswow64"; do
    if [ -f "${_sysdir}/attrib.exe" ]; then
      cp -f "${_sysdir}/attrib.exe" "${_sysdir}/steam.exe" 2>/dev/null || true
      chmod 0555 "${_sysdir}/steam.exe" 2>/dev/null || true
    fi
  done
done

unset _HEROIC_FALLOUT_CANDIDATES _candidate _prefix_dir _sysdir
