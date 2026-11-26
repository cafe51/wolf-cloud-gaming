# Componentes Customizados e Wrappers

Documentação técnica dos scripts e daemons mantidos em `profiles/default/bin/` e `profiles/default/es-de-config/`. Leia a seção correspondente antes de alterar qualquer componente.

---

## 1. Isolamento de Inputs (`profiles/default/bin/dolphin-standalone/99-isolate-inputs.sh`)

- **Escopo real:** apesar de estar na pasta `dolphin-standalone/`, este script é montado em `/etc/cont-init.d/99-isolate-inputs.sh:ro` nos containers **Steam, EmulationStation e Heroic** (executado via `source` pelo `/entrypoint.sh` como `root`, com `set -e` ativo). Qualquer alteração nele impacta todos esses apps.
- **O que faz:**
  1. Aplica isolamento imediato no boot do container e sobe um **daemon único** (`--isolate-inputs-daemon`, protegido por PID file `/run/isolate-inputs.pid`) monitorando `/dev/input/js*` e `/dev/input/event*` a cada 1s.
  2. **Gamepads virtuais do Wolf:** aplica `chmod 0666` e gera metadados udev em `/run/udev/data/c<major>:<minor>` lendo `major:minor` **em decimal** direto de `/sys/class/input/<dev>/dev` (perfil Xbox One `045e:02ea` para pads Xbox; metadados genéricos de joystick para PS5/Nintendo). Dispositivos virtuais do Wolf que não são gamepads (`mouse`, `keyboard`, `touch`, `motion sensors`) são preservados intactos.
  3. **Controles virtuais do Steam Input (`/sys/devices/virtual/*`):** liberados com `0666` e metadados udev mínimos quando ausentes, sem nunca serem bloqueados.
  4. **Joysticks/gamepads físicos do host (fora de `/sys/devices/virtual/*`):** bloqueados dentro do container com `chmod 000` para evitar roubo de slot ou inputs cruzados (sem afetar teclados/mouses).

---

## 2. Dolphin Standalone (`profiles/default/bin/dolphin-standalone/`)

- **Motivação:** o core `dolphin_libretro.so` não suporta códigos Gecko/ActionReplay (`codehandler.bin`) necessários para hacks widescreen 16:9 no GameCube, exigindo o Dolphin standalone.
- **Inicialização (`s6-overlay` no container ES-DE):**
  - `init-dolphin.sh` (`/etc/cont-init.d/89-dolphin.sh:ro`): instala `dolphin-emu`, `xwayland`, `xdotool`, `python3-evdev`, `evtest`, `wmctrl`, `openbox` e dependências Qt/Wayland.
  - `init-dolphin-sys.sh` (`/etc/cont-init.d/90-dolphin-sys.sh:ro`): aguarda `/usr/games/dolphin-emu-nogui` existir e sobrescreve a pasta `sys/` com arquivos atualizados (ex.: `GameSettings`) caso `/tmp/dolphin-sys-v2606` esteja montado.
- **Wrapper de execução (`run-dolphin.sh`):**
  - Montado em `/home/retro/dolphin-standalone/run-dolphin.sh:ro` e invocado pelo sistema `gc` em `profiles/default/es-de-config/custom_systems/es_systems.xml`.
  - **Prevenção de double-input:** como o Dolphin lê `/dev/input/event*` diretamente em paralelo ao frontend, o wrapper congela o ES-DE com `kill -STOP $(pidof es-de)` antes de abrir o jogo e descongela com `kill -CONT` no `trap EXIT`.
  - Sobe um **Xwayland dedicado (`:5 -fullscreen`)**, configura áudio no socket do Wolf (`PULSE_SERVER="unix:/run/user/wolf/pulse-socket"`, `PULSE_LATENCY_MSEC=30`, `CUBEB_BACKEND=pulse`) e executa `/usr/games/dolphin-emu-nogui -p x11 -a HLE -C Display.Fullscreen=True -e "$2"`.
  - Log dentro do container: `/tmp/dolphin.log`.
- **Watchdog de hotkeys (`dolphin-hotkeys.py`):**
  - `dolphin-emu-nogui` ignora `Hotkeys.ini`, mas o backend X11 aceita teclas nativas (`PlatformX11.cpp`).
  - O daemon lê o evdev cujo nome contém `Wolf X-Box One` e injeta teclas no display `:5` via `xdotool`:
    - `Guide (BTN_MODE) + Start` -> `Escape` (sair do jogo e voltar ao ES-DE)
    - `Guide + X (BTN_WEST)` -> `F9` (screenshot)
    - `Guide + Y (BTN_NORTH)` -> `F10` (pausar/retomar)
    - `Guide + LB (BTN_TL)` -> `F1` (load state slot 1)
    - `Guide + RB (BTN_TR)` -> `Shift+F1` (save state slot 1)

---

## 3. Steam Window Manager (`profiles/default/bin/steam-window-manager/`)

- **Motivação:** no Sway, jogos rodando via Proton/Wine/Gamescope ou lançados por atalhos do Heroic (`--no-gui`) frequentemente perdiam foco, abriam em split screen ou ficavam atrás do Steam Big Picture.
- **Arquivos montados no container consolidado `Steam` (`WolfSteam`, resolução dinâmica controlada pelo Moonlight):**
  - `sway-steam.conf` (`/etc/sway/config.d/98-steam-window-manager.conf:ro`): força `workspace_layout tabbed`, aplica `fullscreen enable, focus` para `steam_app_*`, `wine*` e `proton*`, e mantém janelas `dialog`/`utility`/`notification` do Steam como `floating`.
  - `init-steam-window-manager.sh` (`/etc/cont-init.d/98-steam-window-manager.sh:ro`): sincroniza `/etc/localtime` e `/etc/timezone` a partir de `TZ` (necessário para o sandbox `pressure-vessel`/`steamwebhelper` exibir o horário local correto) e inicia o daemon como usuário `retro` usando `SWAYSOCK=/run/user/wolf/sway.socket` (log em `/tmp/steam-window-manager.log`).
  - `steam-window-manager.py` (`/usr/local/bin/steam-window-manager.py:ro`): assina eventos IPC do Sway (`window`, `workspace`) com `wait()` + backoff de 1,5s na reconexão (sem zumbis/CPU spin). Classifica apenas janelas reais de jogo (`steam_app_*`, `gamescope`, `wine*`/`proton*`, `*.exe`), ignorando diálogos/popups/transientes e respeitando o foco quando o usuário alterna para o Steam Big Picture/Overlay (só prioriza novas janelas de jogo ou recupera foco quando nenhuma janela está focada).
- **Biblioteca única e limites:** `/mnt/storage/games/steam/steamapps` é montado diretamente em `/home/retro/.steam/steam/steamapps:rw` (eliminando escolha duplicada de pasta na instalação), com `nofile=524288` para Esync/Proton e `PROTON_LOG` desativado globalmente (ativar por jogo apenas quando depurar).
- **Pitfall Unreal Engine / Proton (swapchain travado em fullscreen exclusivo):** usar Gamescope nas opções de lançamento do jogo na Steam: `gamescope -w 1280 -h 720 -r 60 -f -- %command%`.

---

## 4. Heroic Games Launcher (`profiles/default/bin/heroic-startup.sh` e `heroic-init.d/`)

- **Container base:** `ghcr.io/games-on-whales/xfce:edge` (app consolidado **`Heroic`** / `WolfHeroic`, resolução dinâmica controlada pelo Moonlight e `nofile=524288`).
- **Execução sem FUSE:** o AppImage do Heroic deve estar extraído em `profiles/default/bin/squashfs-root` (ignorado pelo Git) e montado em `/opt/heroic:ro` (e em `/opt/Heroic:ro` no container do Steam para atalhos `--no-gui`).
- **`heroic-startup.sh` (`/opt/gow/startup.sh:rw`):**
  - Trunca `/logs/heroic.log` a cada sessão (evitando crescimento infinito).
  - Gera `${XDG_RUNTIME_DIR:-/tmp}/sway-heroic.conf` com `xwayland enable`, `workspace_layout tabbed`, resolução dinâmica `${GAMESCOPE_WIDTH}x${GAMESCOPE_HEIGHT}` e regras de tela cheia para jogos Proton/Wine/Gamescope (`steam_app_*`, `wine*`, `proton*`, `*.exe`).
  - Executa `dbus-run-session -- sway --unsupported-gpu -c "$SWAY_CFG"`, abrindo `/opt/heroic/heroic --no-sandbox --ozone-platform=wayland --enable-features=UseOzonePlatform,WaylandWindowDecorations` (sem porta de debug `9222`) e encerrando o Sway automaticamente (`; swaymsg exit || killall sway`) ao fechar o Heroic.
  - Benefícios: suporte a foco `xdg_activation_v1`, fallback Xwayland automático para jogos/Protons antigos (ex.: `GE-Proton8-32`, `Proton 9`) e encerramento limpo da sessão Moonlight.
- **`heroic-init.d/10-gamepad-udev.sh` (`/etc/cont-init.d/10-gamepad-udev.sh:ro`):**
  - Sincroniza `/etc/localtime` e `/etc/timezone` a partir de `TZ` e garante propriedade `retro:retro` em `/home/retro/.config` e `/home/retro/.config/sway` (evitando erro `Permission denied` quando o Docker cria o pai `.config` como `root:root` por causa do bind mount `.config/heroic`, sem `chown -R` recursivo no mount).
  - Valida compatibilidade de versão (`mesa-libgallium` da imagem vs. `.deb` em `/home/retro/.config/heroic/apt-cache/`) antes de instalar libs `i386` (pulando com aviso explícito em caso de mismatch pós-`docker pull`).
  - Aplica o patch opcional de `steam.exe` dummy em prefixos Proton clássicos (`/home/*/Games/Heroic/Prefixes/default/...`). O isolamento de inputs e metadados udev dos controles fica centralizado exclusivamente em `99-isolate-inputs.sh`.
- **Nota operacional:** não abrir o Heroic no desktop do host simultaneamente à sessão do Wolf enquanto `~/.config/heroic` for compartilhado em `:rw`.

---

## 5. ES-DE, Switch (Ryujinx) e Diagnóstico

- **`profiles/default/bin/citron.AppImage` (NÃO RENOMEAR):**
  - Apesar da extensão `.AppImage`, é um script bash wrapper que exporta `LD_LIBRARY_PATH` e executa `/ryujinx/squashfs-root/AppRun "$@"`.
  - O ES-DE exige exatamente o nome `citron.AppImage` no seletor de emuladores de Nintendo Switch (`/Applications/citron.AppImage:ro`).
- **`profiles/default/bin/ryujinx-wrapper`:** remove as flags `-f` e `-g` (estilo Yuzu) antes de invocar `/ryujinx/squashfs-root/AppRun`.
- **`profiles/default/bin/controller-debug` (NÃO MOVER):** montado diretamente em `/home/retro/controller-debug:ro` no container do ES-DE.
- **`profiles/default/es-de-config/custom_systems/`:** define launchers customizados do ES-DE (ex.: `es_systems.xml` redirecionando `gc` para `run-dolphin.sh`).
