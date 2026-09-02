#!/bin/bash
LOG=/home/retro/sdl-debug.log
echo "=== $(date) - SDL2/Controller Debug ===" > $LOG

echo "--- ENV ---" >> $LOG
env | grep -iE 'SDL|JOY|GAME|INPUT|UDEV|DISPLAY|WAYLAND' >> $LOG

echo "--- INPUT DEVICES ---" >> $LOG
for d in /dev/input/event*; do
    name=$(cat /sys/class/input/$(basename $d)/device/name 2>/dev/null)
    echo "  $d: $name" >> $LOG
done

echo "--- SDL2 JOYSTICK TEST ---" >> $LOG
python3 -c "
import os, ctypes
os.environ['SDL_VIDEODRIVER'] = 'dummy'
try:
    sdl = ctypes.CDLL('libSDL2-2.0.so.0')
    sdl.SDL_Init(0x200)
    num = sdl.SDL_NumJoysticks()
    print(f'SDL_NumJoysticks: {num}')
    for i in range(num):
        name_ptr = sdl.SDL_JoystickNameForIndex(i)
        if name_ptr:
            name = ctypes.c_char_p(name_ptr).value.decode()
            print(f'  Joystick {i}: {name}')
    sdl.SDL_Quit()
except Exception as e:
    print(f'SDL2 error: {e}')
" >> $LOG 2>&1

echo "--- ES-DE STARTING ---" >> $LOG
# Agora inicia o ES-DE normalmente
exec /Applications/esde.AppImage --appimage-extract-and-run "$@"
