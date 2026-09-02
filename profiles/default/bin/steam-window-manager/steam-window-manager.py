#!/usr/bin/env python3
import json
import os
import re
import select
import subprocess
import sys
import time

def log(msg):
    print(f"[SteamWindowManager] {time.strftime('%Y-%m-%d %H:%M:%S')} - {msg}", flush=True)

def get_tree():
    try:
        p = subprocess.run(["swaymsg", "-t", "get_tree"], capture_output=True, text=True, timeout=2)
        if p.returncode == 0:
            return json.loads(p.stdout)
    except Exception as e:
        log(f"Erro ao obter árvore do Sway: {e}")
    return None

def run_sway_cmd(cmd):
    try:
        subprocess.run(["swaymsg", cmd], capture_output=True, text=True, timeout=2)
    except Exception as e:
        log(f"Erro ao executar comando Sway '{cmd}': {e}")

def is_game_window(node):
    wp = node.get("window_properties") or {}
    wclass = wp.get("class") or ""
    winstance = wp.get("instance") or ""
    wtitle = wp.get("title") or node.get("name") or ""
    appid = node.get("app_id") or ""

    if re.match(r"^steam_app_\d+", wclass, re.IGNORECASE):
        return True
    if wclass.lower() in ["wine", "wine64", "proton", "gamescope", "steam_proton"]:
        return True
    if "steam_app_" in wclass.lower():
        return True

    system_classes = ["steam", "steamwebhelper", "waybar", "sway", "foot", "kitty", "dmenu", "wmenu"]
    if wclass.lower() in system_classes or winstance.lower() in system_classes or appid.lower() in system_classes:
        return False
    if wclass == "" and appid == "":
        return False
    return True

def is_steam_bp(node):
    wp = node.get("window_properties") or {}
    wclass = wp.get("class") or ""
    return wclass.lower() == "steam"

def find_windows(node):
    res = []
    if "id" in node and (node.get("window_properties") or node.get("app_id")):
        res.append(node)
    for c in node.get("nodes", []) + node.get("floating_nodes", []):
        res.extend(find_windows(c))
    return res

def enforce_window_rules():
    tree = get_tree()
    if not tree:
        return

    windows = find_windows(tree)
    game_windows = [w for w in windows if is_game_window(w)]

    if game_windows:
        target_game = None
        for g in reversed(game_windows):
            if g.get("focused"):
                target_game = g
                break
        if not target_game:
            target_game = game_windows[-1]

        target_id = target_game["id"]
        is_fs = target_game.get("fullscreen_mode") == 1
        is_foc = target_game.get("focused", False)

        if not is_fs or not is_foc:
            wp = target_game.get("window_properties") or {}
            log(f"Priorizando jogo: ID={target_id}, Title='{target_game.get('name')}', Class='{wp.get('class')}' (fullscreen={is_fs}, focused={is_foc})")
            run_sway_cmd(f"[con_id={target_id}] focus; [con_id={target_id}] fullscreen enable")
    else:
        steam_bp = [w for w in windows if is_steam_bp(w)]
        if steam_bp:
            bp_win = steam_bp[0]
            # Ensure Steam BP is not floating and focused
            if bp_win.get("type") == "floating_con":
                run_sway_cmd(f"[con_id={bp_win['id']}] floating disable")
            if not any(w.get("focused") for w in windows):
                run_sway_cmd(f"[con_id={bp_win['id']}] focus")

def main():
    log("Iniciando daemon de gerenciamento de janelas para Steam...")
    
    sway_sock = os.environ.get("SWAYSOCK", "/run/user/wolf/sway.socket")
    for _ in range(60):
        if os.path.exists(sway_sock):
            break
        time.sleep(0.5)

    if not os.path.exists(sway_sock):
        log("Aviso: Socket do Sway não encontrado de imediato, continuando tentativa...")

    enforce_window_rules()

    while True:
        try:
            proc = subprocess.Popen(
                ["swaymsg", "-t", "subscribe", "-m", '["window", "workspace"]'],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True
            )

            last_enforce = time.time()
            while True:
                rlist, _, _ = select.select([proc.stdout], [], [], 2.0)
                if rlist:
                    line = proc.stdout.readline()
                    if not line:
                        break
                    enforce_window_rules()
                    last_enforce = time.time()
                else:
                    if time.time() - last_enforce >= 2.0:
                        enforce_window_rules()
                        last_enforce = time.time()

            proc.poll()
        except Exception as e:
            log(f"Exceção no loop de eventos: {e}")
            time.sleep(2)

if __name__ == "__main__":
    main()
