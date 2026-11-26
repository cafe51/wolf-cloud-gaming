#!/usr/bin/env bash
# ==============================================================================
# Init Auxiliar do Container Heroic (/etc/cont-init.d/10-gamepad-udev.sh)
# ==============================================================================
# Executado via `source` pelo /entrypoint.sh (como root, com `set -e` ativo).
# Nota: o isolamento e metadados udev dos controles são responsabilidade
# exclusiva de /etc/cont-init.d/99-isolate-inputs.sh.
# ==============================================================================

# 0. Garantir fuso horário (/etc/localtime e /etc/timezone) e permissão de /home/retro/.config
if [ -n "${TZ:-}" ] && [ -f "/usr/share/zoneinfo/${TZ}" ]; then
  ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime
  printf '%s\n' "${TZ}" > /etc/timezone
fi

# (o Docker cria diretórios-pai intermediários como root:root ao montar subpastas como .config/heroic)
mkdir -p /home/retro/.config/sway
chown "${PUID:-1000}:${PGID:-1000}" /home/retro/.config /home/retro/.config/sway 2>/dev/null || true

# 1. Instalar bibliotecas 32-bit (i386) do cache persistente somente se compatíveis
if [ -d "/home/retro/.config/heroic/apt-cache" ] && compgen -G "/home/retro/.config/heroic/apt-cache/*.deb" >/dev/null 2>&1; then
  _heroic_mesa_ver=$(dpkg-query -W -f='${Version}' mesa-libgallium 2>/dev/null || true)
  _heroic_os_ver=$(. /etc/os-release 2>/dev/null && printf '%s' "${VERSION_ID:-unknown}" || printf 'unknown')
  _heroic_mesa_deb="/home/retro/.config/heroic/apt-cache/mesa-libgallium_${_heroic_mesa_ver}_i386.deb"

  if [ -n "${_heroic_mesa_ver}" ] && [ -f "${_heroic_mesa_deb}" ]; then
    dpkg --add-architecture i386 2>/dev/null || true
    if dpkg -i /home/retro/.config/heroic/apt-cache/*.deb >/dev/null 2>&1; then
      echo "[Heroic-Init] 32-bit libraries (Mesa ${_heroic_mesa_ver}, Ubuntu ${_heroic_os_ver}) setup complete"
    else
      echo "[Heroic-Init] AVISO: dpkg -i retornou alertas ao instalar cache i386 (Mesa ${_heroic_mesa_ver}); verifique dependências."
    fi
  else
    echo "[Heroic-Init] AVISO: apt-cache i386 incompatível com Mesa '${_heroic_mesa_ver:-desconhecida}' (Ubuntu ${_heroic_os_ver}) — pulando dpkg -i para evitar corrupção. Atualize os .deb em apt-cache."
  fi
  unset _heroic_mesa_ver _heroic_os_ver _heroic_mesa_deb
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
