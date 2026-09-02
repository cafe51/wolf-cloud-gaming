#!/usr/bin/env python3
"""Watchdog de hotkeys para o Dolphin standalone (nogui) no Wolf ES-DE.

Escuta o gamepad VIRTUAL do Wolf ("Wolf X-Box One (virtual) pad") e, quando o
botão Guide (BTN_MODE) estiver pressionado junto com outro botão, injeta a
tecla X11 correspondente no display :5 (onde o dolphin-emu-nogui roda).

O dolphin-emu-nogui NÃO processa o Hotkeys.ini, mas o platform X11 dele tem
hotkeys de teclado nativas (PlatformX11.cpp):
  Escape        → RequestShutdown (sai do jogo → wrapper → ES-DE)
  F10           → Toggle Pause
  F9            → Screenshot
  F1..F8        → Load State (slot N)
  Shift+F1..F8  → Save State (slot N)

Combinações (Guide = botão do meio do Xbox, BTN_MODE no evdev):
  Guide + Start     → Escape       (sair do jogo, voltar ao ES-DE)
  Guide + X (WEST)  → F9           (screenshot)
  Guide + Y (NORTH) → F10          (pausa/resume)
  Guide + LB (TL)   → F1           (load state 1)
  Guide + RB (TR)   → Shift+F1     (save state 1)
"""
import evdev
import subprocess
import sys
import os

# Display do Xwayland onde o Dolphin roda (iniciado pelo run-dolphin.sh)
os.environ["DISPLAY"] = ":5"

# Nome real do pad virtual do Wolf — confirmado no código do Wolf
# (input_handler.cpp: XboxOneJoypad::create({.name = "Wolf X-Box One (virtual) pad"})).
# O joystick físico Xbox 360 tem outro nome ("Microsoft X-Box 360 pad") e é
# bloqueado pelo 99-isolate-inputs.sh (chmod 000) — nem chega a ser legível.
DEVICE_NAME_FILTER = "Wolf X-Box One"


def inject_key(key):
    """Injeta uma tecla X11 no display :5 via xdotool."""
    try:
        subprocess.run(["xdotool", "key", key],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        # xdotool indisponível ou X11 fora do ar — segue sem travar o jogo
        pass


def find_gamepad():
    """Acha o primeiro device legível cujo nome contenha 'Wolf X-Box One'."""
    for path in evdev.list_devices():
        try:
            dev = evdev.InputDevice(path)
        except (PermissionError, OSError):
            # Device sem permissão de leitura (físico bloqueado) ou sumiu
            continue
        if DEVICE_NAME_FILTER in dev.name:
            return dev
    return None


def main():
    gamepad = find_gamepad()
    if not gamepad:
        print("Erro: pad virtual Wolf nao encontrado", file=sys.stderr)
        sys.exit(1)
    print(f"Watchdog: escutando {gamepad.path} ({gamepad.name})", flush=True)

    guide_pressed = False
    try:
        for event in gamepad.read_loop():
            if event.type != evdev.ecodes.EV_KEY:
                continue

            # Estado do botão Guide (BTN_MODE)
            if event.code == evdev.ecodes.BTN_MODE:
                guide_pressed = (event.value == 1)
                continue

            # Combinações: Guide pressionado + outro botão APERTADO (value==1)
            if guide_pressed and event.value == 1:
                if event.code == evdev.ecodes.BTN_START:
                    inject_key("Escape")       # sair do jogo → ES-DE
                elif event.code == evdev.ecodes.BTN_WEST:
                    inject_key("F9")           # screenshot
                elif event.code == evdev.ecodes.BTN_NORTH:
                    inject_key("F10")          # pausa/resume
                elif event.code == evdev.ecodes.BTN_TL:
                    inject_key("F1")           # load state 1
                elif event.code == evdev.ecodes.BTN_TR:
                    inject_key("shift+F1")     # save state 1
    except OSError:
        # Device desconectado (fim da sessão) — sai limpo
        pass


if __name__ == "__main__":
    main()
