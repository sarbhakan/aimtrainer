#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_log="$(mktemp /tmp/aimlocal-tests.XXXXXX)"
timeout 120s bash "$project_root/tools/godot.sh" --headless --script res://tests/run_tests.gd 2>&1 | tee "$test_log"
while IFS= read -r log_line; do
    case "$log_line" in
        ERROR:*|"SCRIPT ERROR:"*) printf 'Erreur dans les tests : %s\n' "$log_line" >&2; exit 1 ;;
    esac
done < "$test_log"
