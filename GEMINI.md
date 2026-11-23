# Wolf Cloud Gaming — Instruções Operacionais para Agentes

Servidor **Wolf Cloud Gaming** em produção. **Fonte de verdade:** o ambiente funcionando na máquina local sempre prevalece; o GitHub serve como backup e vitrine pública. Variáveis e caminhos reais do host ficam em `.env`, a configuração ativa do Wolf em `./config.toml` (symlink para `/etc/wolf/cfg/config.toml`) e detalhes de hardware/mounts locais em `docs/host.local.md` (se existir, fora do Git).

---

## Invariantes Críticos (Não Quebrar Produção)

1. **Checar mounts antes de mover/remover:** antes de renomear, mover ou apagar qualquer arquivo em `profiles/`, verifique se ele está bind-mounted em `/etc/wolf/cfg/config.toml`.
2. **Nunca renomear `profiles/default/bin/citron.AppImage`:** é um wrapper bash para o Ryujinx, mas o ES-DE exige exatamente esse nome no seletor de Switch.
3. **Nunca mover `profiles/default/bin/controller-debug`:** é montado diretamente no container do ES-DE (`/home/retro/controller-debug:ro`).
4. **Impacto cruzado de `profiles/default/bin/dolphin-standalone/99-isolate-inputs.sh`:** apesar do diretório, esse script é montado em **Steam, ES-DE e Heroic** (`/etc/cont-init.d/99-isolate-inputs.sh:ro`).
5. **Não reiniciar o Wolf sem confirmação:** `systemctl restart wolf` / `docker compose restart` derruba sessões Moonlight ativas.

---

## Git, Sanitização e Validação

- **Nunca commitar** segredos, blocos `[[paired_clients]]` (certificados/chaves), `config.toml`, `config-edited.toml`, `.env`, `state/`, `backups/`, `logs/`, ROMs/saves, binários `.AppImage`/`squashfs-root/` ou arquivos `*.local.md`.
- **Manter arquivos públicos sanitizados:** `GEMINI.md`, `docs/*.md`, `config.example.toml` e `.env.example` não devem conter credenciais, IPs privados nem caminhos/usuários fixos do host.
- **Sincronizar template:** ao adicionar ou alterar mounts/apps replicáveis em `/etc/wolf/cfg/config.toml`, reflita a mudança em `config.example.toml` usando os placeholders do `setup.sh` (`/opt/wolf-data`, `/home/user/roms-gdrive`, `/mnt/storage/games/steam`).
- **Validar antes de concluir:** rode `docker compose config` (se mexer no compose), `bash -n` (scripts shell), `python3 -m py_compile` (Python) e revise `git status` + `git diff`.

---

## Manutenção Viva deste Arquivo

Sempre que uma mudança no projeto alterar invariantes, mounts críticos, componentes customizados ou fluxos operacionais, **atualize `GEMINI.md` e/ou `docs/*.md` na mesma tarefa**, seguindo estritamente estes princípios:

- **`GEMINI.md` = instruções operacionais persistentes:** mantenha-o o **mais enxuto possível**, contendo apenas regras sempre-ativas e o mapa de referências.
- **Progressive disclosure:** detalhes arquiteturais, engenharia de scripts e runbooks longos pertencem a `docs/*.md`, referenciados aqui por caminho comum (nunca com include inline `@[...]`) para leitura apenas sob demanda.
- **Sem redundância nem drift:** não duplique o `README.md` e não mantenha árvores estáticas de diretórios neste arquivo.

---

## Referências Sob Demanda

Leia apenas o documento relevante para a tarefa atual:

- `docs/architecture.md` — `docker-compose.yml`, `config.toml` vs. template, GStreamer/VAAPI, `s6-overlay`/`apt-cache`, restrições NTFS/FUSE e isolamento `seat9`.
- `docs/components.md` — Dolphin Standalone (`Xwayland :5`, `SIGSTOP`/`SIGCONT`, hotkeys), isolamento de inputs, Steam Window Manager (Sway IPC), Heroic (Wayland) e Switch/ES-DE.
- `docs/runbooks.md` — operação/diagnóstico do serviço `wolf`, como adicionar novos emuladores/apps e checklist pré-commit/push.
- `.env` e `docs/host.local.md` *(locais, fora do Git)* — caminhos reais, hardware, serviço systemd instalado e mounts específicos desta máquina.
