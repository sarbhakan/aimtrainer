#!/usr/bin/env bash
set -euo pipefail

v2_project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
v2_capture_root="${AIM_LOCAL_V2_SCREENSHOT_DIR:-$v2_project_root/dist/preview_v2}"
v2_runtime_dir="$(mktemp -d /tmp/aimlocal-v2-visual.XXXXXX)"
v2_server_pid=""
v2_display_ready=false

cleanup_v2_display() {
    if [ -n "$v2_server_pid" ]; then
        kill "$v2_server_pid" 2>/dev/null || true
        wait "$v2_server_pid" 2>/dev/null || true
    fi
}
trap cleanup_v2_display EXIT

if [ "$(realpath -m "$v2_capture_root")" = "$(realpath -m "$v2_project_root/dist/preview")" ]; then
    printf 'Le dossier historique 0.9 est réservé. Utiliser dist/preview_v2.\n' >&2
    exit 1
fi
mkdir -p "$v2_capture_root"
if [ -f "$v2_capture_root/CURRENT" ]; then
    python3 - "$v2_capture_root/CURRENT" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as current_file:
    current = json.load(current_file)
if current.get("schema_version") != "aimlocal.visuals.current.v2.0" or current.get("app_version") != "1.0.0":
    raise SystemExit("CURRENT existant hors contrat V2 : choisir un dossier de captures distinct.")
PY
fi

export AIM_LOCAL_V2_SCREENSHOT_DIR="$(realpath "$v2_capture_root")"
export AIM_LOCAL_V2_VISUAL_STORE="$v2_runtime_dir/userdata"
v2_parse_log="$v2_runtime_dir/parse.log"
timeout 40s bash "$v2_project_root/tools/godot.sh" --headless --check-only --script res://tests/v2_visual_smoke.gd 2>&1 | tee "$v2_parse_log"
if rg -q '^(ERROR:|SCRIPT ERROR:)' "$v2_parse_log"; then
    printf 'Compilation V2 refusée. Journal : %s\n' "$v2_parse_log" >&2
    exit 1
fi

if [ -n "${DISPLAY:-}" ] && xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
    v2_display_ready=true
else
    export DISPLAY=":$((100 + RANDOM % 900))"
    if command -v Xvfb >/dev/null 2>&1; then
        Xvfb "$DISPLAY" -screen 0 1920x1080x24 -nolisten tcp >"$v2_runtime_dir/display.log" 2>&1 &
    elif command -v Xorg >/dev/null 2>&1 && [ -f /usr/lib/xorg/modules/drivers/dummy_drv.so ]; then
        Xorg "$DISPLAY" -config "$v2_project_root/tools/xorg-dummy.conf" -noreset -nolisten tcp -logfile "$v2_runtime_dir/display.log" >"$v2_runtime_dir/display.stdout" 2>&1 &
    else
        printf 'Rendu natif non exécuté : X11, Xvfb ou Xorg dummy requis.\n' >&2
        exit 1
    fi
    v2_server_pid=$!
    for v2_attempt in $(seq 1 50); do
        if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
            v2_display_ready=true
            break
        fi
        sleep 0.1
    done
fi
if [ "$v2_display_ready" != true ]; then
    printf 'Affichage V2 inaccessible. Journaux : %s\n' "$v2_runtime_dir" >&2
    exit 1
fi

export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
v2_visual_log="$v2_runtime_dir/visual.log"
timeout 240s bash "$v2_project_root/tools/godot.sh" --audio-driver Dummy --rendering-method gl_compatibility --script res://tests/v2_visual_smoke.gd 2>&1 | tee "$v2_visual_log"
if rg -q '^(ERROR:|SCRIPT ERROR:)|WARNING:.*leaked' "$v2_visual_log" || ! rg -q '^V2 VISUAL SMOKE : [1-9][0-9]* captures, [1-9][0-9]* assertions, 0 échecs\.$' "$v2_visual_log"; then
    printf 'Validation visuelle V2 refusée. Journal : %s\n' "$v2_visual_log" >&2
    exit 1
fi
if [ "${AIM_LOCAL_V2_VISUAL_DRAFT:-0}" != "1" ]; then
    v2_run_directory="$(sed -n 's/^V2 VISUAL DIRECTORY : //p' "$v2_visual_log" | tail -n 1)"
    python3 "$v2_project_root/tools/package_v2_visuals.py" --captures-dir "$AIM_LOCAL_V2_SCREENSHOT_DIR" --current-marker CURRENT.pending --expected-run-dir "$v2_run_directory" --verify-only
    mv "$AIM_LOCAL_V2_SCREENSHOT_DIR/CURRENT.pending" "$AIM_LOCAL_V2_SCREENSHOT_DIR/CURRENT"
fi
printf 'Captures V2 : %s\nJournaux et profil QA isolé : %s\n' "$AIM_LOCAL_V2_SCREENSHOT_DIR" "$v2_runtime_dir"
