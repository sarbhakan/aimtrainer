#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
run_suite() {
    local script_path="$1"
    local marker="$2"
    local test_log
    local parse_log
    local completed=false
    test_log="$(mktemp /tmp/aimlocal-tests.XXXXXX)"
    parse_log="$(mktemp /tmp/aimlocal-parse.XXXXXX)"
    timeout 30s bash "$project_root/tools/godot.sh" --headless --check-only --script "$script_path" 2>&1 | tee "$parse_log"
    if rg -q '^(ERROR:|SCRIPT ERROR:)' "$parse_log"; then
        printf 'Compilation des tests refusée. Journal : %s\n' "$parse_log" >&2
        exit 1
    fi
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
run_suite res://tests/adaptive_calibration_tests.gd "ADAPTIVE CALIBRATION"
run_suite res://tests/ui_spacing_tests.gd "UI SPACING"
run_suite res://tests/preview_containment_tests.gd "PREVIEW CONTAINMENT"
run_suite res://tests/pattern_variation_tests.gd "PATTERN VARIATION"
run_suite res://tests/storage_roundtrip_tests.gd "STORAGE ROUNDTRIP"
run_suite res://tests/progressive_calibration_tests.gd "PROGRESSIVE CALIBRATION"
run_suite res://tests/exercise_070_tests.gd "EXERCISE 070"
run_suite res://tests/lifecycle_tests.gd "LIFECYCLE"
run_suite res://tests/presentation_080_tests.gd "PRESENTATION 080"
run_suite res://tests/temporal_ui_tests.gd "TEMPORAL UI"
