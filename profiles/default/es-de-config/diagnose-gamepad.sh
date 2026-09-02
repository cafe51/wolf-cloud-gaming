#!/bin/bash
# Diagnóstico: gamepad quebra ao voltar do RetroArch para ES-DE
# Uso: /home/retro/ES-DE/diagnose-gamepad.sh
# O script monitora continuamente e salva em /home/retro/ES-DE/gamepad-diag.log

LOG="/home/retro/ES-DE/gamepad-diag.log"
DURATION=${1:-120}  # segundos para monitorar (default 2 min)

echo "=== DIAGNÓSTICO GAMEPAD - $(date) ===" > "$LOG"
echo "Monitorando por ${DURATION}s..." >> "$LOG"

# Função para capturar estado atual
snapshot() {
    local label="$1"
    echo "" >> "$LOG"
    echo "--- SNAPSHOT: $label ($(date +%H:%M:%S.%N)) ---" >> "$LOG"
    
    # Dispositivos de input
    echo "  /dev/input/event*:" >> "$LOG"
    for d in /dev/input/event*; do
        [ -e "$d" ] || continue
        name=$(cat /sys/class/input/$(basename $d)/device/name 2>/dev/null || echo "N/A")
        perms=$(stat -c "%a %u:%g" "$d" 2>/dev/null || echo "N/A")
        echo "    $d ($perms): $name" >> "$LOG"
    done
    
    echo "  /dev/input/js*:" >> "$LOG"
    ls -la /dev/input/js* >> "$LOG" 2>&1
    
    # SDL2 - quantos joysticks vê?
    echo "  SDL2 joysticks:" >> "$LOG"
    python3 -c "
import os, ctypes
os.environ['SDL_VIDEODRIVER'] = 'dummy'
os.environ['SDL_GAMECONTROLLERCONFIG'] = '030015655e040000ea02000008040000,Wolf X-Box One (virtual) pad,platform:Linux,a:b0,b:b1,x:b2,y:b3,back:b6,start:b7,guide:b8,leftstick:b9,rightstick:b10,leftshoulder:b4,rightshoulder:b5,dpup:h0.1,dpright:h0.2,dpdown:h0.4,dpleft:h0.8,leftx:a0,lefty:a1,rightx:a3,righty:a4,lefttrigger:a2,righttrigger:a5'
try:
    sdl = ctypes.CDLL('libSDL2-2.0.so.0')
    sdl.SDL_Init(0x200)  # SDL_INIT_JOYSTICK
    sdl.SDL_InitSubSystem(0x2000)  # SDL_INIT_GAMECONTROLLER
    num = sdl.SDL_NumJoysticks()
    print(f'    Joysticks: {num}')
    for i in range(num):
        name_ptr = sdl.SDL_JoystickNameForIndex(i)
        name = ctypes.c_char_p(name_ptr).value.decode() if name_ptr else 'NULL'
        guid_ptr = sdl.SDL_JoystickGetGUIDString(sdl.SDL_JoystickGetDeviceGUID(i), ctypes.create_string_buffer(33), 33)
        print(f'    [{i}]: {name} | GUID: {guid_ptr}')
        # Tenta abrir
        js = sdl.SDL_JoystickOpen(i)
        if js:
            print(f'          open OK, buttons={sdl.SDL_JoystickNumButtons(js)}, axes={sdl.SDL_JoystickNumAxes(js)}')
            sdl.SDL_JoystickClose(js)
        else:
            err = sdl.SDL_GetError()
            err_str = ctypes.c_char_p(err).value.decode() if err else 'unknown'
            print(f'          open FAILED: {err_str}')
    # GameController
    num_gc = 0
    # SDL_GameControllerAddMappingsFromRW is complex; rely on SDL_GAMECONTROLLERCONFIG env
    for i in range(num):
        if sdl.SDL_IsGameController(i):
            num_gc += 1
            name_ptr = sdl.SDL_GameControllerNameForIndex(i)
            name = ctypes.c_char_p(name_ptr).value.decode() if name_ptr else 'NULL'
            print(f'    GameController [{i}]: {name}')
    print(f'    Total GameControllers: {num_gc}')
    sdl.SDL_Quit()
except Exception as e:
    print(f'    SDL2 ERROR: {e}')
" >> "$LOG" 2>&1
    
    # Processos que estão usando dispositivos de input
    echo "  Processos com /dev/input aberto:" >> "$LOG"
    fuser /dev/input/* 2>/dev/null | while read pid; do
        cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' ' >> "$LOG"
        echo " (pid=$pid)" >> "$LOG"
    done || echo "    (nenhum)" >> "$LOG"
    
    # Estado do udev (Wolf fake-udev)
    echo "  UDEV data:" >> "$LOG"
    ls -la /run/udev/data/ 2>/dev/null >> "$LOG" || echo "    /run/udev/data/ não existe" >> "$LOG"
}

# Snapshot inicial
snapshot "ANTES - estado inicial"

# Loop de monitoramento
START=$(date +%s)
LAST_HASH=""
while true; do
    NOW=$(date +%s)
    ELAPSED=$((NOW - START))
    [ $ELAPSED -ge $DURATION ] && break
    
    # Hash dos dispositivos para detectar mudanças
    CURRENT=$(ls -la /dev/input/event* /dev/input/js* 2>/dev/null | md5sum)
    if [ "$CURRENT" != "$LAST_HASH" ] && [ -n "$LAST_HASH" ]; then
        echo "" >> "$LOG"
        echo ">>> MUDANÇA DETECTADA em T+${ELAPSED}s ($(date +%H:%M:%S)) <<<" >> "$LOG"
        snapshot "MUDANÇA T+${ELAPSED}s"
    fi
    LAST_HASH="$CURRENT"
    
    sleep 0.5
done

# Snapshot final
snapshot "DEPOIS - estado final (T+${DURATION}s)"

echo "" >> "$LOG"
echo "=== DIAGNÓSTICO CONCLUÍDO ===" >> "$LOG"
echo "Log salvo em: $LOG" >> "$LOG"
echo "Para ler: cat $LOG"
cat "$LOG"
