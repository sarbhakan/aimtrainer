#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
mkdir -p dist
bash tools/godot.sh --headless --editor --import
bash tools/test.sh
bash tools/godot.sh --headless --export-release "Windows Desktop" dist/AimLocal.exe
export_validation_dir="$(mktemp -d /tmp/aimlocal-export.XXXXXX)"
GODOT_PROJECT_PATH="$export_validation_dir" bash tools/godot.sh \
    --headless --main-pack "$project_root/dist/AimLocal.exe" --quit-after 10 \
    --log-file "$export_validation_dir/runtime.log"
while IFS= read -r log_line; do
    case "$log_line" in
        ERROR:*|"SCRIPT ERROR:"*) printf 'Erreur dans le pack exporté : %s\n' "$log_line" >&2; exit 1 ;;
    esac
done < "$export_validation_dir/runtime.log"
GODOT_PROJECT_PATH="$export_validation_dir" bash tools/godot.sh \
    --headless --main-pack "$project_root/dist/AimLocal.exe" \
    --script "$project_root/tests/export_smoke.gd" --log-file "$export_validation_dir/exercises.log"
smoke_completed=false
while IFS= read -r log_line; do
    case "$log_line" in
        ERROR:*|"SCRIPT ERROR:"*) printf 'Erreur dans les exercices exportés : %s\n' "$log_line" >&2; exit 1 ;;
        "EXPORT SMOKE : 16 exercices embarqués, 0 échecs.") smoke_completed=true ;;
    esac
done < "$export_validation_dir/exercises.log"
if [ "$smoke_completed" != true ]; then
    printf 'Les exercices exportés n’ont pas terminé leur contrôle.\n' >&2
    exit 1
fi
python3 tools/package_windows.py
