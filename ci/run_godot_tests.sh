#!/usr/bin/env bash

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/ci-logs"
mkdir -p "$LOG_DIR"

failures=0

run_godot_command() {
    local name="$1"
    shift
    local log_file="$LOG_DIR/${name}.log"

    echo
    echo "============================================================"
    echo "Running: $name"
    echo "============================================================"

    set +e
    timeout 45s godot --headless --path "$PROJECT_ROOT" "$@" >"$log_file" 2>&1
    local status=$?
    set -e

    cat "$log_file"

    if [[ $status -eq 124 ]]; then
        echo "::error::$name timed out after 45 seconds."
        failures=$((failures + 1))
    elif [[ $status -ne 0 ]]; then
        echo "::error::$name exited with status $status."
        failures=$((failures + 1))
    fi

    if grep -Eqi \
        'SCRIPT ERROR:|Parse Error:|Compile Error:|Failed to load script|Failed loading resource|Invalid call\. Nonexistent function|Invalid access to property or key' \
        "$log_file"; then
        echo "::error::$name produced a Godot script or resource error."
        failures=$((failures + 1))
    fi
}

cd "$PROJECT_ROOT"

mapfile -t test_scenes < <(find scripts -type f -name '*Test.tscn' -print | sort)

if [[ ${#test_scenes[@]} -eq 0 ]]; then
    echo "::error::No *Test.tscn scenes were found under scripts/."
    exit 1
fi

echo "Discovered ${#test_scenes[@]} Godot test scene(s)."

for scene in "${test_scenes[@]}"; do
    safe_name="${scene#scripts/}"
    safe_name="${safe_name//\//__}"
    safe_name="${safe_name%.tscn}"
    run_godot_command "test__${safe_name}" "res://$scene"
done

# Boot the actual configured main scene for a small, fixed number of frames.
# This catches startup-only failures that isolated test scenes may not touch.
run_godot_command "main_scene_boot" --quit-after 180

if [[ $failures -ne 0 ]]; then
    echo
    echo "Godot CI failed with $failures detected problem(s)."
    exit 1
fi

echo
echo "All Godot tests and the main-scene boot check passed."
