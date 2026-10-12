#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
mkdir -p dist

run_godot_checked() {
    local log_file
    log_file="$(mktemp /tmp/aimlocal-build.XXXXXX)"
    bash tools/godot.sh "$@" 2>&1 | tee "$log_file"
    while IFS= read -r log_line; do
        case "$log_line" in
            ERROR:*|"SCRIPT ERROR:"*) printf 'Erreur Godot : %s\nJournal : %s\n' "$log_line" "$log_file" >&2; exit 1 ;;
        esac
    done < "$log_file"
}

run_godot_checked --headless --editor --import
bash tools/test.sh
run_godot_checked --headless --export-release "Windows Desktop" dist/AimLocal.exe
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
assets_completed=false
profiles_completed=false
crosshairs_completed=false
while IFS= read -r log_line; do
    case "$log_line" in
        ERROR:*|"SCRIPT ERROR:"*) printf 'Erreur dans les exercices exportés : %s\n' "$log_line" >&2; exit 1 ;;
        "EXPORT SMOKE : 18 exercices embarqués, 0 échecs.") smoke_completed=true ;;
        "EXPORT ASSETS : 3 profils d’arme embarqués, 0 échecs.") assets_completed=true ;;
        "EXPORT PROFILES : 3 imports, protocole 4, 25 essais de 60 s et routine 3 phases embarqués, 0 échecs.") profiles_completed=true ;;
        "EXPORT CROSSHAIRS : 4 styles embarqués, 0 échecs.") crosshairs_completed=true ;;
    esac
done < "$export_validation_dir/exercises.log"
if [ "$smoke_completed" != true ] || [ "$assets_completed" != true ] || [ "$profiles_completed" != true ] || [ "$crosshairs_completed" != true ]; then
    printf 'Les exercices exportés n’ont pas terminé leur contrôle.\n' >&2
    exit 1
fi
python3 tools/package_windows.py
