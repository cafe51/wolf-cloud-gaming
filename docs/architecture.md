# Arquitetura Técnica — Wolf Cloud Gaming

Referência arquitetural para agentes e manutenção do stack. Para valores concretos do host atual (caminhos, GPU, partições), consulte `.env` e `docs/host.local.md` (locais, ignorados pelo Git).

---

## 1. Modelo de Operação e Fonte de Verdade

- **Multi-seat virtual sob demanda:** em vez de espelhar o desktop físico do host, o Wolf sobe containers Docker efêmeros com compositor **Wayland/Sway** e servidor **PulseAudio** dedicados por sessão Moonlight.
- **Host local como fonte de verdade:** o ambiente rodando na máquina local é a referência funcional. O repositório Git atua como backup de código/documentação e vitrine pública com templates sanitizados.
- **Ciclo de vida:**
  - `docker-compose.yml` define o serviço principal `wolf` (`network_mode: host`, acesso a `/var/run/docker.sock`, `/etc/wolf`, `/dev/dri`, `/dev/uinput`, `/dev/uhid` e cgroup `c 13:* rmw`).
  - Em produção com `systemd` (`wolf.service`), prefere-se `restart: "no"` no compose para deixar o `systemd` ordenar a subida após a montagem de discos secundários (`RequiresMountsFor`) e limpar containers órfãos (`ExecStartPre`).

---

## 2. Configuração Ativa vs. Templates Públicos

| Arquivo | Papel | No Git? |
|---|---|---|
| `/etc/wolf/cfg/config.toml` (symlink `./config.toml`) | Configuração ativa lida pelo Wolf (inclui `[[paired_clients]]` e caminhos reais do host) | Não |
| `config.example.toml` | Template público sanitizado (v7) usado por `setup.sh` | Sim |
| `.env` | Variáveis locais (`WOLF_BASE_DIR`, `ROMS_DIR`, `STEAM_LIBRARY_DIR`, `WOLF_RENDER_NODE`, etc.) | Não |
| `.env.example` | Template público de variáveis de ambiente | Sim |
| `docs/host.local.md` | Notas opcionais de hardware, mounts e storage do host local | Não (`*.local.md`) |

Placeholders substituídos automaticamente pelo `setup.sh` ao gerar `/etc/wolf/cfg/config.toml` a partir de `config.example.toml`:
- `/opt/wolf-data` -> `${WOLF_BASE_DIR}`
- `/home/user/roms-gdrive` -> `${ROMS_DIR}`
- `/mnt/storage/games/steam` -> `${STEAM_LIBRARY_DIR}`

---

## 3. Pipeline de Streaming e Encoders (GStreamer)

- Os pipelines de vídeo/áudio ficam nos blocos `[gstreamer.*]` do `config.toml` (v7).
- Encoders suportados na configuração:
  - **VAAPI (`va`):** `vah264enc`, `vah265enc`, `vaav1enc` + `vapostproc` (prioritário em GPUs AMD/Intel via `WOLF_RENDER_NODE`, padrão `/dev/dri/renderD128`).
  - **NVIDIA (`nvcodec`):** `nvh264enc`, `nvh265enc`, `nvav1enc`.
  - **Intel QSV (`qsv`):** `qsvh264enc`, `qsvh265enc`, `qsvav1enc`.
  - **Software fallback:** `x264enc`, `x265enc`, `av1enc`.
- O Wolf testa `check_elements` na subida e ignora automaticamente encoders incompatíveis com a GPU presente.

---

## 4. Padrão de Containers (`s6-overlay` + `apt-cache`)

Os containers de apps (`steam:edge`, `es-de:edge`, `xfce:edge`, `wolf-ui:main`) seguem o padrão `games-on-whales` com `s6-overlay`:
- Scripts montados em `/etc/cont-init.d/*.sh` executam em ordem lexicográfica como `root` antes do aplicativo subir.
- Dependências adicionais (como `dolphin-emu`, `xwayland`, `xdotool`, `python3-evdev` ou bibliotecas `i386` no Heroic) podem ser instaladas rapidamente usando caches persistentes de pacotes `.deb` (`apt-cache`) montados do host, evitando reconstruir imagens upstream.
- Aplicações distribuídas como `.AppImage` (ex.: Heroic, Ryujinx) são executadas **extraídas (`squashfs-root`)**, pois montagens FUSE internas falham em containers Docker convencionais.

---

## 5. Restrições de Host Linux, Storage e Dispositivos

1. **Docker `overlay2` vs. NTFS:** o `data-root` do Docker deve permanecer em filesystem POSIX nativo (ex.: `ext4`), pois `overlay2` requer chamadas como `renameat2` incompatíveis com partições NTFS/FUSE. Partições NTFS devem entrar apenas via **bind mounts** para bibliotecas de jogos, ROMs e dados.
2. **ROMs via `rclone` FUSE:** exige `user_allow_other` habilitado em `/etc/fuse.conf` (configurado pelo `setup.sh`) para que os containers enxerguem a montagem do host.
3. **Gamepads virtuais (`uhid` / `uinput`):**
   - Módulos `uhid` e `uinput` devem estar carregados no boot (`/etc/modules-load.d/uhid.conf`).
   - A regra `/etc/udev/rules.d/85-wolf-uinput.rules` (`KERNEL=="uinput", MODE="0666", GROUP="docker"`) garante permissões persistentes após reboots.
4. **Isolamento de seats (`seat9`):** dispositivos virtuais do Wolf devem ser isolados do `seat0` (desktop físico) via `ID_SEAT=seat9` no udev do host para não disparar inputs no desktop local enquanto alguém joga remotamente.
