#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tool_root="${AIM_LOCAL_TOOLS_DIR:-/workspace/.aim-local-tools}"
export XDG_DATA_HOME="$tool_root/data"
export XDG_CACHE_HOME="$tool_root/cache"
export XDG_CONFIG_HOME="$tool_root/config"
mkdir -p "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"

godot_binary="${GODOT_BIN:-$tool_root/godot/4.7.2/Godot_v4.7.2-stable_linux.x86_64}"
if [ ! -x "$godot_binary" ]; then
    printf 'Godot 4.7.2 absent. Exécuter bash tools/setup_godot.sh ou définir GODOT_BIN.\n' >&2
    exit 1
fi
godot_version="$("$godot_binary" --version)"
case "$godot_version" in
    4.7.2.stable.*) ;;
    *) printf 'Version Godot incompatible : %s (4.7.2 stable requis).\n' "$godot_version" >&2; exit 1 ;;
esac

exec "$godot_binary" --path "${GODOT_PROJECT_PATH:-$project_root}" "$@"
