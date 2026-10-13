#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if rg -q '^config/version="1\.0\.0"$' "$project_root/project.godot"; then
    exec bash "$project_root/tools/v2_visual_smoke.sh"
fi
visual_log="$(mktemp /tmp/aimlocal-visual.XXXXXX)"
server_log="$(mktemp /tmp/aimlocal-display.XXXXXX)"
server_pid=""

cleanup() {
    if [ -n "$server_pid" ]; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
}
trap cleanup EXIT

if [ -z "${DISPLAY:-}" ] || ! xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
    export DISPLAY=":$((100 + RANDOM % 900))"
    if command -v Xvfb >/dev/null 2>&1; then
        Xvfb "$DISPLAY" -screen 0 1920x1080x24 -nolisten tcp >"$server_log" 2>&1 &
    elif command -v Xorg >/dev/null 2>&1 && [ -f /usr/lib/xorg/modules/drivers/dummy_drv.so ]; then
        Xorg "$DISPLAY" -config "$project_root/tools/xorg-dummy.conf" -noreset -nolisten tcp -logfile "$server_log" >"$server_log.stdout" 2>&1 &
    else
        printf 'Contrôle graphique non exécuté : affichage X11, Xvfb ou Xorg avec pilote dummy requis.\n' >&2
        exit 1
    fi
    server_pid=$!
    ready=false
    for attempt in $(seq 1 50); do
        if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
            ready=true
            break
        fi
        sleep 0.1
    done
    if [ "$ready" != true ]; then
        printf 'Affichage de test inaccessible. Journal : %s\n' "$server_log" >&2
        exit 1
    fi
fi

export LIBGL_ALWAYS_SOFTWARE=1
timeout 240s bash "$project_root/tools/godot.sh" --audio-driver Dummy \
    --script res://tests/visual_smoke.gd 2>&1 | tee "$visual_log"
if rg -q '^(SCRIPT ERROR:|ERROR:)' "$visual_log" || ! rg -q '^VISUAL SMOKE : [0-9]+ captures, 0 échec\.$' "$visual_log"; then
    printf 'La validation graphique a échoué. Journal : %s\n' "$visual_log" >&2
    exit 1
fi
printf 'Captures : %s\n' "${AIM_LOCAL_SCREENSHOT_DIR:-$project_root/dist/preview}"
