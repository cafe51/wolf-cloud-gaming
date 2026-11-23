# Runbooks Operacionais — Wolf Cloud Gaming

Procedimentos práticos para operar o servidor, adicionar componentes e manter o repositório Git sincronizado e sanitizado.

---

## 1. Operação e Diagnóstico do Servidor

> **Atenção:** reiniciar o `wolf` derruba qualquer sessão Moonlight ativa. Sempre confirme com o usuário antes de reiniciar em produção.

```bash
# Status do serviço e containers
sudo systemctl status wolf
docker compose ps

# Logs do Wolf e verificação de encoder VAAPI / controle virtual
docker logs -f wolf
docker logs wolf 2>&1 | grep -E "Using.*encoder|Creating Xbox"

# Validar sintaxe do compose após alterações
docker compose config

# Reiniciar (somente com confirmação em produção)
sudo systemctl restart wolf
```

Logs úteis dentro dos containers / host:
- Heroic: `logs/heroic.log` (montado em `/logs/heroic.log`).
- Dolphin Standalone: `/tmp/dolphin.log` (dentro do container ES-DE).
- Steam Window Manager: `/tmp/steam-window-manager.log` (dentro do container Steam).

**Nota sobre `wolf.service`:** o arquivo ativo no sistema fica em `/etc/systemd/system/wolf.service` (cópia independente do arquivo no repo). Ao alterar o unit em produção, copie para `/etc/systemd/system/wolf.service` e execute `sudo systemctl daemon-reload`.

---

## 2. Alterar `config.toml` e Sincronizar `config.example.toml`

1. Edite a configuração ativa em `/etc/wolf/cfg/config.toml` (acessível por `./config.toml`).
2. Verifique se a alteração se aplica tanto à variante **720p** quanto à **1080p** do app.
3. Se a mudança fizer parte da stack replicável, replique-a em `config.example.toml` substituindo caminhos locais pelos placeholders esperados por `setup.sh`:
   - `${WOLF_BASE_DIR}` -> `/opt/wolf-data`
   - `${ROMS_DIR}` -> `/home/user/roms-gdrive`
   - `${STEAM_LIBRARY_DIR}` -> `/mnt/storage/games/steam`
4. Nunca copie blocos `[[paired_clients]]`, `uuid` real ou caminhos pessoais para `config.example.toml`.
5. Para aplicar mudanças no `config.toml`, o Wolf precisa ser reiniciado (com confirmação do usuário).

---

## 3. Adicionar Novo Emulador, Wrapper ou App

1. Adicione o script/wrapper em `profiles/default/bin/` e aplique `chmod +x`.
2. Valide a sintaxe antes de testar no container:
   - Shell: `bash -n <script>`
   - Python: `python3 -m py_compile <script.py>`
3. Se depender de `.AppImage`, extraia com `--appimage-extract` para uma pasta ignorada pelo `.gitignore` e monte como `:ro` no container.
4. Adicione os bind-mounts necessários no app correspondente em `/etc/wolf/cfg/config.toml` (720p e 1080p) e espelhe de forma sanitizada em `config.example.toml`.
5. Se for integrado ao EmulationStation, ajuste `profiles/default/es-de-config/custom_systems/`.
6. Documente o novo componente em `docs/components.md` (e só adicione ao `GEMINI.md` se criar um novo invariante global sempre-ativo).

---

## 4. Checklist Pré-Commit e Push (GitHub)

O ambiente local é sempre a fonte de verdade; o GitHub serve como backup e vitrine pública. Antes de commitar ou enviar (`git push`):

1. Execute `git status` e `git diff` (ou `git diff --cached`) para revisar tudo que vai entrar no commit.
2. Confirme que **nenhum** arquivo sensível ou pesado foi incluído:
   - `config.toml`, `config-edited.toml`, `.env`, `state/`, `backups/`, `logs/`, `*.local.md`, ROMs, saves, `.deb`, `.iso` ou pastas extraídas (`squashfs-root/`).
3. Verifique que arquivos públicos (`GEMINI.md`, `docs/*.md`, `config.example.toml`, `.env.example`) não contêm segredos, certificados, IPs privados ou caminhos/usuários locais não intencionais.
   - *Atenção especial ao `wolf.service`:* se a cópia local no repo estiver preenchida com usuário/disco reais do host, decida com o usuário se deve ser sanitizada antes de publicar no GitHub (sem tocar em `/etc/systemd/system/wolf.service`).
4. Valide `docker compose config` caso `docker-compose.yml` tenha sido alterado.
