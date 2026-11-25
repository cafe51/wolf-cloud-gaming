#!/usr/bin/env python3
"""Gerenciador de foco e tela cheia para Steam (e atalhos Heroic/Proton) no Sway/Wolf.

Regras principais:
- Classifica apenas janelas reais de jogo (sem catch-all que captura dialogs/launchers).
- Aplica foco + fullscreen apenas quando uma NOVA janela de jogo surge ou quando
  nenhuma janela está focada — respeitando o foco do usuário no Steam Big Picture/Overlay.
- Reconecta ao Sway IPC com wait() + backoff para evitar processos zumbis e loops de CPU.
"""
import json
import os
import re
import select
import subprocess
import time

LOG_PREFIX = "[SteamWindowManager]"

EXCLUDED_CLASSES = {
    "steam",
    "steamwebhelper",
    "heroic",
    "waybar",
    "sway",
    "foot",
    "kitty",
    "dmenu",
    "wmenu",
    "zenity",
    "yad",
    "winetricks",
    "xdg-desktop-portal-gtk",
    "polkit-gnome-authentication-agent-1",
}

NON_GAME_WINDOW_TYPES = {
    "dialog",
    "utility",
    "popup_menu",
    "dropdown_menu",
    "tooltip",
    "notification",
    "splash",
    "menu",
}

GAME_EXACT_CLASSES = {
    "gamescope",
    "wine",
    "wine64",
    "proton",
    "steam_proton",
}

STEAM_APP_RE = re.compile(r"^steam_app_\d+", re.IGNORECASE)


def log(msg: str) -> None:
    print(f"{LOG_PREFIX} {time.strftime('%Y-%m-%d %H:%M:%S')} - {msg}", flush=True)


def get_tree():
    try:
        p = subprocess.run(
            ["swaymsg", "-t", "get_tree"],
            capture_output=True,
            text=True,
            timeout=2,
        )
        if p.returncode == 0 and p.stdout:
            return json.loads(p.stdout)
    except Exception as e:
        log(f"Erro ao obter árvore do Sway: {e}")
    return None


def run_sway_cmd(cmd: str) -> None:
    try:
        subprocess.run(["swaymsg", cmd], capture_output=True, text=True, timeout=2)
    except Exception as e:
        log(f"Erro ao executar comando Sway '{cmd}': {e}")


def is_game_window(node: dict) -> bool:
    wp = node.get("window_properties") or {}
    wclass = (wp.get("class") or "").strip()
    winstance = (wp.get("instance") or "").strip()
    wtype = (wp.get("window_type") or "").strip().lower()
    appid = (node.get("app_id") or "").strip()

    # Nunca capturar diálogos, popups, utilitários ou sub-janelas transientes
    if wtype in NON_GAME_WINDOW_TYPES or wp.get("transient_for"):
        return False

    wclass_l = wclass.lower()
    winstance_l = winstance.lower()
    appid_l = appid.lower()

    if wclass_l in EXCLUDED_CLASSES or winstance_l in EXCLUDED_CLASSES or appid_l in EXCLUDED_CLASSES:
        return False

    # Jogos Steam nativos, Proton e UMU/Heroic (steam_app_<id> / steam_app_0)
    if STEAM_APP_RE.match(wclass) or "steam_app_" in wclass_l or "steam_app_" in appid_l:
        return True

    # Gamescope ou wrappers Wine/Proton explícitos
    if wclass_l in GAME_EXACT_CLASSES or appid_l in GAME_EXACT_CLASSES:
        return True

    # Executáveis Windows via Proton/Wine/Heroic (--no-gui)
    if wclass_l.endswith(".exe") or winstance_l.endswith(".exe") or appid_l.endswith(".exe"):
        return True

    return False


def is_steam_bp(node: dict) -> bool:
    wp = node.get("window_properties") or {}
    wclass_l = (wp.get("class") or "").strip().lower()
    wtype = (wp.get("window_type") or "").strip().lower()
    if wtype in NON_GAME_WINDOW_TYPES:
        return False
    return wclass_l in ("steam", "steamwebhelper")


def find_windows(node: dict) -> list:
    res = []
    if "id" in node and (node.get("window_properties") or node.get("app_id")):
        res.append(node)
    for child in node.get("nodes", []) + node.get("floating_nodes", []):
        res.extend(find_windows(child))
    return res


def enforce_window_rules(seen_game_ids: set, reason: str = "poll") -> None:
    tree = get_tree()
    if not tree:
        return

    windows = find_windows(tree)
    present_ids = {w["id"] for w in windows}
    seen_game_ids.intersection_update(present_ids)

    game_windows = [w for w in windows if is_game_window(w)]
    any_focused = any(w.get("focused", False) for w in windows)

    if game_windows:
        new_games = [g for g in game_windows if g["id"] not in seen_game_ids]
        for g in game_windows:
            seen_game_ids.add(g["id"])

        target_game = None
        if new_games:
            # Nova janela de jogo: prioriza e coloca em tela cheia
            target_game = new_games[-1]
        elif not any_focused:
            # Nenhuma janela focada no Sway (ex.: popup/launcher fechou): devolve foco ao jogo
            target_game = game_windows[-1]

        if target_game is not None:
            target_id = target_game["id"]
            is_fs = target_game.get("fullscreen_mode") == 1
            is_foc = target_game.get("focused", False)
            if not is_fs or not is_foc:
                wp = target_game.get("window_properties") or {}
                log(
                    f"Priorizando jogo ({reason}): ID={target_id}, "
                    f"Title='{target_game.get('name')}', Class='{wp.get('class')}' "
                    f"(fullscreen={is_fs}, focused={is_foc})"
                )
                run_sway_cmd(f"[con_id={target_id}] focus; [con_id={target_id}] fullscreen enable")
        return

    # Sem jogos abertos: garante que o Steam Big Picture não fique perdido sem foco
    steam_wins = [w for w in windows if is_steam_bp(w)]
    if steam_wins:
        bp_win = steam_wins[0]
        if bp_win.get("type") == "floating_con":
            run_sway_cmd(f"[con_id={bp_win['id']}] floating disable")
        if not any_focused:
            run_sway_cmd(f"[con_id={bp_win['id']}] focus")


def wait_for_sway_socket(sway_sock: str, timeout_s: float = 30.0) -> bool:
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        if os.path.exists(sway_sock):
            return True
        time.sleep(0.5)
    return os.path.exists(sway_sock)


def main() -> None:
    log("Iniciando daemon de gerenciamento de janelas para Steam...")

    sway_sock = os.environ.get("SWAYSOCK", "/run/user/wolf/sway.socket")
    if not wait_for_sway_socket(sway_sock, timeout_s=30.0):
        log("Aviso: Socket do Sway não encontrado nos primeiros 30s; aguardando com backoff...")

    seen_game_ids = set()
    enforce_window_rules(seen_game_ids, reason="startup")

    while True:
        if not os.path.exists(sway_sock):
            time.sleep(1.5)
            continue

        proc = None
        try:
            proc = subprocess.Popen(
                ["swaymsg", "-t", "subscribe", "-m", '["window", "workspace"]'],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
            )

            last_enforce = time.time()
            while True:
                rlist, _, _ = select.select([proc.stdout], [], [], 5.0)
                if rlist:
                    line = proc.stdout.readline()
                    if not line:
                        break
                    try:
                        ev = json.loads(line)
                        change = ev.get("change", "")
                    except Exception:
                        change = ""
                    if change in ("new", "close", "focus", "move", ""):
                        enforce_window_rules(seen_game_ids, reason=f"event:{change or 'raw'}")
                        last_enforce = time.time()
                elif time.time() - last_enforce >= 5.0:
                    enforce_window_rules(seen_game_ids, reason="fallback-poll")
                    last_enforce = time.time()
        except Exception as e:
            log(f"Exceção no loop de eventos: {e}")
        finally:
            if proc is not None:
                try:
                    proc.terminate()
                    proc.wait(timeout=2)
                except Exception:
                    try:
                        proc.kill()
                        proc.wait(timeout=2)
                    except Exception:
                        pass
            time.sleep(1.5)


if __name__ == "__main__":
    main()
