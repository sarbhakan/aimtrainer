#!/usr/bin/env bash
set -euo pipefail

tool_root="${AIM_LOCAL_TOOLS_DIR:-/workspace/.aim-local-tools}"
release="4.7.2-stable"
binary_dir="$tool_root/godot/4.7.2"
download_dir="$tool_root/downloads"
template_dir="$tool_root/data/godot/export_templates/4.7.2.stable"
export XDG_DATA_HOME="$tool_root/data"
export XDG_CACHE_HOME="$tool_root/cache"
export XDG_CONFIG_HOME="$tool_root/config"

mkdir -p "$binary_dir" "$download_dir" "$template_dir" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"

download_verified() {
    local asset_name="$1"
    local expected_sha512="$2"
    local destination="$download_dir/$asset_name"
    if [ ! -f "$destination" ]; then
        curl --fail --location --silent --show-error --retry 2 --connect-timeout 20 --max-time 900 \
            "https://github.com/godotengine/godot-builds/releases/download/$release/$asset_name" \
            --output "$destination.part"
        printf '%s  %s\n' "$expected_sha512" "$destination.part" | sha512sum --check
        mv "$destination.part" "$destination"
    fi
    printf '%s  %s\n' "$expected_sha512" "$destination" | sha512sum --check
}

download_verified "Godot_v4.7.2-stable_linux.x86_64.zip" \
    "9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65"
download_verified "Godot_v4.7.2-stable_export_templates.tpz" \
    "ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079"

unzip -qo "$download_dir/Godot_v4.7.2-stable_linux.x86_64.zip" -d "$binary_dir"
unzip -qjo "$download_dir/Godot_v4.7.2-stable_export_templates.tpz" \
    templates/version.txt templates/windows_release_x86_64.exe templates/windows_debug_x86_64.exe \
    templates/linux_release.x86_64 templates/linux_debug.x86_64 -d "$template_dir"
chmod u+x "$binary_dir/Godot_v4.7.2-stable_linux.x86_64" "$template_dir/"linux_*.x86_64
"$binary_dir/Godot_v4.7.2-stable_linux.x86_64" --version
