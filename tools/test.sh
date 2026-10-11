#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
run_suite() {
    local script_path="$1"
    local marker="$2"
    local test_log
    local completed=false
    test_log="$(mktemp /tmp/aimlocal-tests.XXXXXX)"
    timeout 120s bash "$project_root/tools/godot.sh" --headless --script "$script_path" 2>&1 | tee "$test_log"
    while IFS= read -r log_line; do
        case "$log_line" in
            ERROR:*|"SCRIPT ERROR:"*|WARNING:*leaked*) printf 'Erreur dans les tests : %s\n' "$log_line" >&2; exit 1 ;;
        esac
        if [[ "$log_line" == "$marker : "* && "$log_line" =~ [1-9][0-9]*\ assertions,\ 0\ échecs ]]; then
            completed=true
        fi
    done < "$test_log"
    if [ "$completed" != true ]; then
        printf 'La suite %s n’a pas confirmé l’exécution de ses assertions. Journal : %s\n' "$marker" "$test_log" >&2
        exit 1
    fi
}

run_suite res://tests/run_tests.gd "AIM/LOCAL"
run_suite res://tests/geometry_regression_tests.gd "GEOMETRY REGRESSION"
