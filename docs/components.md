# Componentes Customizados e Wrappers

Documentação técnica dos scripts e daemons mantidos em `profiles/default/bin/` e `profiles/default/es-de-config/`. Leia a seção correspondente antes de alterar qualquer componente.

---

## 1. Isolamento de Inputs (`profiles/default/bin/dolphin-standalone/99-isolate-inputs.sh`)

- **Escopo real:** apesar de estar na pasta `dolphin-standalone/`, este script é montado em `/etc/cont-init.d/99-isolate-inputs.sh:ro` nos containers **Steam, EmulationStation e Heroic**. Qualquer alteração nele impacta todos esses apps.
- **O que faz:**
  1. Aplica isolamento imediato no boot do container e sobe um daemon em background (loop de 1s) monitorando `/dev/input/js*` e `/dev/input/event*`.
  2. **Whitelist (`*Wolf*` / `*wolf*`):** libera com `chmod 0777` e gera metadados udev em `/run/udev/data/c13:<minor>` simulando Xbox One Controller (`045e:02ea`) para manter o controle virtual do Moonlight como Player 1.
  3. **Demais joysticks/gamepads físicos do host:** bloqueia com `chmod 000` dentro do container para evitar roubo de slot ou inputs cruzados.

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

- **Motivação:** no Sway, jogos rodando via Proton/Wine/Gamescope frequentemente perdiam foco, abriam em split screen ou ficavam atrás do Steam Big Picture.
- **Arquivos montados nos containers Steam (720p e 1080p):**
  - `sway-steam.conf`: força `workspace_layout tabbed`, aplica `fullscreen enable, focus` para `steam_app_*`, `wine*` e `proton*`, e mantém janelas `dialog`/`utility`/`notification` do Steam como `floating`.
  - `init-steam-window-manager.sh`: inicia o daemon como usuário `retro` usando `SWAYSOCK=/run/user/wolf/sway.socket` (log em `/tmp/steam-window-manager.log`).
  - `steam-window-manager.py`: assina eventos IPC do Sway (`window`, `workspace`) com checagem periódica a cada 2s; prioriza e força foco + tela cheia na janela de jogo ativa, ou garante foco no Steam Big Picture quando não há jogo aberto.
- **Pitfall Unreal Engine / Proton (swapchain travado em fullscreen exclusivo):** usar Gamescope nas opções de lançamento do jogo na Steam: `gamescope -w 1280 -h 720 -r 60 -f -- %command%`.

---

## 4. Heroic Games Launcher (`profiles/default/bin/heroic-startup.sh` e `heroic-init.d/`)

- **Container base:** `ghcr.io/games-on-whales/xfce:edge`.
- **Execução sem FUSE:** o AppImage do Heroic deve estar extraído em `profiles/default/bin/squashfs-root` (ignorado pelo Git) e montado em `/opt/heroic:ro`.
- **`heroic-startup.sh` (`/opt/gow/startup.sh`):**
  - Registra logs em `/logs/heroic.log`.
  - Aguarda o gamepad virtual em `/dev/input/js*`, cria/atualiza entradas udev e mantém um loop a cada 3s reaplicando permissões enquanto o Heroic estiver ativo.
  - Inicia `/opt/heroic/heroic` em **Wayland nativo** (`GDK_BACKEND=wayland`, `QT_QPA_PLATFORM=wayland`, `unset DISPLAY`, `--no-sandbox --ozone-platform=wayland --enable-features=UseOzonePlatform,WaylandWindowDecorations --remote-debugging-port=9222`).
- **`heroic-init.d/10-gamepad-udev.sh` (`/etc/cont-init.d/10-gamepad-udev.sh:ro`):**
  - Configura metadados udev do pad Wolf, executa `99-isolate-inputs.sh` se presente, instala libs `i386` de `/home/retro/.config/heroic/apt-cache/*.deb` (se existir) e inclui patch opcional para neutralizar `steam.exe` dummy em prefixos Proton clássicos.

---

## 5. ES-DE, Switch (Ryujinx) e Diagnóstico

- **`profiles/default/bin/citron.AppImage` (NÃO RENOMEAR):**
  - Apesar da extensão `.AppImage`, é um script bash wrapper que exporta `LD_LIBRARY_PATH` e executa `/ryujinx/squashfs-root/AppRun "$@"`.
  - O ES-DE exige exatamente o nome `citron.AppImage` no seletor de emuladores de Nintendo Switch (`/Applications/citron.AppImage:ro`).
- **`profiles/default/bin/ryujinx-wrapper`:** remove as flags `-f` e `-g` (estilo Yuzu) antes de invocar `/ryujinx/squashfs-root/AppRun`.
- **`profiles/default/bin/controller-debug` (NÃO MOVER):** montado diretamente em `/home/retro/controller-debug:ro` no container do ES-DE.
- **`profiles/default/es-de-config/custom_systems/`:** define launchers customizados do ES-DE (ex.: `es_systems.xml` redirecionando `gc` para `run-dolphin.sh`).
