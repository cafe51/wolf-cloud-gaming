# 🐺 Wolf Cloud Gaming — Contexto de Projeto para Agentes IA (GEMINI.md)

Este documento fornece contexto arquitetural, regras de operação e diretrizes de desenvolvimento para agentes de Inteligência Artificial que forem interagir ou dar manutenção neste repositório.

---

## 📌 1. Visão Geral do Projeto

* **Nome do Projeto:** Wolf Cloud Gaming (Japhe Cloud Gaming)
* **Objetivo:** Servidor de **cloud gaming self-hosted de baixa latência e multi-seat real**, substituindo o Sunshine.
* **Core:** Baseado no projeto [Wolf (games-on-whales)](https://github.com/games-on-whales/wolf) e protocolo **Moonlight**.
* **Diferencial Arquitetural:** Ao invés de espelhar o desktop físico do host, o Wolf sobe **desktops Wayland/Sway virtuais isolados em containers Docker sob demanda**. O computador host continua 100% livre para uso diário enquanto outra pessoa joga remotamente.
* **Repositório Público:** [github.com/cafe51/wolf-cloud-gaming](https://github.com/cafe51/wolf-cloud-gaming)
* **Metodologia de Criação:** Desenvolvido integralmente via **Vibecoding & Orquestração Multi-Agente** (Hermes AI Platform + Gemini no Google Antigravity).

---

## 🖥️ 2. Hardware e Ambiente do Host

| Componente | Detalhe |
|---|---|
| **Host OS** | Ubuntu 26.04 / 24.04 LTS (Kernel Linux 6.x / 7.x) |
| **GPU** | **AMD Radeon RX 580 2048SP** (Polaris 20 XL) — Driver Mesa VAAPI (`/dev/dri/renderD128`) |
| **Encoders** | **VAAPI** (`vah264enc`, `vah265enc`, `vaav1enc`). Encoders NVENC e QSV são ignorados automaticamente. |
| **Rede** | Intel I219-V, rede mesh zero-trust via **Tailscale** + LAN |
| **Storage** | SSD (Sistema + Proton) + Disco NTFS (`/mnt/01D808191FE36330`) para jogos, ROMs e dados |
| **ROMs** | Google Drive montado via **rclone FUSE** (`~/roms-gdrive` -> `/ROMs/`) com `user_allow_other` |

---

## 📂 3. Estrutura de Diretórios e Arquivos Críticos

```
wolf-data/
├── GEMINI.md                          # Este arquivo de contexto para agentes
├── README.md                          # Documentação pública do repositório
├── setup.sh                           # Script de bootstrap e geração de configs
├── docker-compose.yml                 # Definição do serviço principal do Wolf
├── wolf.service                       # Template systemd para o serviço
├── .env                               # Variáveis de ambiente locais do host (NUNCA COMMITAR)
├── .env.example                       # Template público de variáveis de ambiente
├── config.example.toml                # Template público sanitizado da config do Wolf (v7)
├── config.toml                        # Symlink -> /etc/wolf/cfg/config.toml (CONFIG ATIVA)
├── profiles/
│   └── default/                       # Dados montados nos containers dos apps
│       ├── bin/                       # Daemons e scripts customizados
│       │   ├── dolphin-standalone/    # Launcher do Dolphin com Xwayland e SIGSTOP
│       │   │   ├── run-dolphin.sh     # Wrapper do emulador
│       │   │   ├── dolphin-hotkeys.py # Watchdog de hotkeys via evdev -> X11
│       │   │   ├── 99-isolate-inputs.sh # Script de isolamento de controles físicos
│       │   │   └── init-dolphin*.sh   # Scripts de inicialização s6-overlay
│       │   ├── steam-window-manager/  # Daemon Python de foco de janelas no Sway
│       │   ├── heroic-startup.sh      # Launcher do Heroic em Wayland puro
│       │   ├── heroic-init.d/         # Regras udev de inicialização do Heroic
│       │   ├── citron.AppImage        # Wrapper bash para Ryujinx (Switch)
│       │   └── controller-debug       # Ferramenta de diagnóstico de controles (MONTADA NO CONTAINER)
│       ├── es-de-config/              # Configurações do EmulationStation (custom_systems)
│       ├── retroarch-config/          # Configuração, saves e states do RetroArch
│       ├── pcsx2-config/              # Configuração do PCSX2
│       └── icons/                     # Ícones das aplicações exibidos no Moonlight
├── state/                             # Estado de pareamento e certificados do Wolf (NUNCA COMMITAR)
├── backups/                           # Backups históricos locais (~6 GB) (NUNCA COMMITAR)
└── logs/                              # Logs de execução locais (NUNCA COMMITAR)
```

---

## ⚠️ 4. REGRAS DE OURO PARA AGENTES (NÃO QUEBRAR O AMBIENTE!)

1. **ESTABILIDADE EM PRIMEIRO LUGAR:** O servidor em `/mnt/01D808191FE36330/ubuntu/programas/wolf-data/` está em produção e funcionando. **NUNCA** altere caminhos ou remova arquivos sem verificar se eles estão sendo bind-mounted no `config.toml` ativo.
2. **NUNCA RENOMEAR `citron.AppImage`:** O arquivo é um script bash, mas o EmulationStation (ES-DE) exige exatamente a string `citron.AppImage` no seletor de emuladores do Nintendo Switch. Renomear quebrará o frontend.
3. **NUNCA MOVER `controller-debug`:** Esse arquivo está montado diretamente no container do ES-DE (`/home/retro/controller-debug:ro`).
4. **CUIDADO COM DADOS SENSÍVEIS NO GIT:**
   - O `config.toml` ativo e `config-edited.toml` contêm blocos `[[paired_clients]]` com **certificados criptográficos e chaves privadas de dispositivos Moonlight reais**.
   - O diretório `state/` contém os tokens de sessão.
   - O diretório `backups/` contém mais de 6 GB de dados.
   - **SEMPRE** respeite o `.gitignore` e use `config.example.toml` para templates públicos.
5. **CONFIG ATIVA:** O Wolf lê `/etc/wolf/cfg/config.toml`. O arquivo `./config.toml` neste diretório é um symlink para `/etc/wolf/cfg/config.toml`.

---

## ⚙️ 5. Engenharia dos Componentes Customizados

### A. Dolphin Standalone (`profiles/default/bin/dolphin-standalone/`)
* **Problema Resolvido:** O core `dolphin_libretro.so` não suporta hacks widescreen via Gecko/ActionReplay (`codehandler.bin`), exigindo a versão standalone. Porém, o Dolphin standalone lê eventos evdev diretamente, causando **double-input** com a interface do ES-DE.
* **Solução:** `run-dolphin.sh` sobe um **Xwayland dedicado (:5)**, congela o processo do ES-DE enviando **`kill -STOP $ES_PID`**, roda o emulador e, no `trap EXIT`, descongela com **`kill -CONT $ES_PID`**.
* **Watchdog de Hotkeys (`dolphin-hotkeys.py`):** O frontend nogui do Dolphin não lê `Hotkeys.ini`. Este daemon escuta eventos `evdev` do pad virtual (`BTN_MODE` / Guide) e injeta teclas X11 nativas (`Escape`, `F1`, `F9`, `F10`) no display `:5` via `xdotool`.
* **Isolamento de Input (`99-isolate-inputs.sh`):** Bloqueia joysticks físicos do host dentro do container com `chmod 000`, liberando apenas o pad virtual `Wolf*` com `chmod 0777`.

### B. Steam Window Manager (`profiles/default/bin/steam-window-manager/`)
* **Problema Resolvido:** Jogos rodando via Proton/Wine ou Gamescope no Sway frequentemente perdiam foco ou abriam em abas ocultas.
* **Solução:** `steam-window-manager.py` é um daemon que escuta a árvore IPC do Sway e força foco imediato e tela cheia para janelas com classes `steam_app_*`, `wine*` e `proton*`.

### C. Heroic Games Launcher
* Roda diretamente sobre **Wayland** usando `--ozone-platform=wayland --no-sandbox`.
* Executado a partir do AppImage extraído (`squashfs-root`) pois FUSE interno não funciona em containers Docker comuns.

---

## 🛠️ 6. Comandos e Operações do Sistema

```bash
# Ver status do servidor Wolf
sudo systemctl status wolf
# ou
docker compose ps

# Logs em tempo real
docker logs -f wolf

# Reiniciar o stack
sudo systemctl restart wolf
# ou
docker compose restart

# Validar sintaxe do docker-compose
docker compose config

# Atualizar configuração do Wolf (após editar /etc/wolf/cfg/config.toml)
docker compose restart
```

---

## 🧠 7. Como os Agentes devem proceder em Novas Tarefas

1. Antes de criar novos scripts de automação, certifique-se de que eles não conflitam com a árvore de mounts em `/etc/wolf/cfg/config.toml`.
2. Se precisar adicionar um novo emulador ou runner:
   - Configure o binário ou wrapper em `profiles/default/bin/`.
   - Adicione o mount no perfil correspondente em `/etc/wolf/cfg/config.toml` (e no template `config.example.toml`).
   - Se for para o ES-DE, ajuste os sistemas em `profiles/default/es-de-config/custom_systems/`.
3. Para alterações no Git: sempre execute `git status` e `git diff` antes de comitar para garantir que nenhum dado pessoal, token ou backup de GBs foi incluído no stage.
