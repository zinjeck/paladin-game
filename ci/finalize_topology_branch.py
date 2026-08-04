#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]

smoke_path = root / "scripts/city/rendering/CityRendererRefactorSmokeTest.gd"
smoke = smoke_path.read_text(encoding="utf-8")
old = '''\t_expect(
\t\trenderer.construction_site_info_panel.size
\t\t== panel_size_before_zoom,
\t\t"Construction panel dimensions must remain screen-constant under zoom."
\t)
'''
new = '''\tvar panel_size_after_zoom := (
\t\trenderer.construction_site_info_panel.size
\t)
\t_expect(
\t\tis_equal_approx(
\t\t\tpanel_size_after_zoom.x,
\t\t\tpanel_size_before_zoom.x
\t\t)
\t\tand is_equal_approx(
\t\t\tpanel_size_after_zoom.y,
\t\t\tpanel_size_before_zoom.y
\t\t),
\t\t"Construction panel dimensions must remain screen-constant under zoom. "
\t\t\t+ "Before: "
\t\t\t+ str(panel_size_before_zoom)
\t\t\t+ ", after: "
\t\t\t+ str(panel_size_after_zoom)
\t)
'''
count = smoke.count(old)
if count != 1:
    raise RuntimeError(f"Expected one construction-panel size assertion, found {count}")
smoke_path.write_text(smoke.replace(old, new, 1), encoding="utf-8")

final_workflow = '''name: Godot CI

on:
  push:
    branches:
      - main
  pull_request:
    branches:
      - main

permissions:
  contents: read

concurrency:
  group: godot-ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test:
    name: Godot 4.7.1 headless tests
    runs-on: ubuntu-latest
    timeout-minutes: 30

    steps:
      - name: Check out Paladin
        uses: actions/checkout@v4

      - name: Cache Godot
        id: cache-godot
        uses: actions/cache@v4
        with:
          path: ${{ runner.tool_cache }}/godot-4.7.1
          key: godot-4.7.1-linux-x86-64

      - name: Install Godot 4.7.1
        if: steps.cache-godot.outputs.cache-hit != 'true'
        shell: bash
        run: |
          set -euo pipefail
          GODOT_DIR="${RUNNER_TOOL_CACHE}/godot-4.7.1"
          mkdir -p "$GODOT_DIR"
          curl --fail --location --retry 3 \\
            --output /tmp/godot.zip \\
            "https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/Godot_v4.7.1-stable_linux.x86_64.zip"
          unzip -q /tmp/godot.zip -d "$GODOT_DIR"
          mv "$GODOT_DIR/Godot_v4.7.1-stable_linux.x86_64" "$GODOT_DIR/godot"
          chmod +x "$GODOT_DIR/godot"

      - name: Put Godot on PATH
        shell: bash
        run: |
          echo "${RUNNER_TOOL_CACHE}/godot-4.7.1" >> "$GITHUB_PATH"

      - name: Show Godot version
        run: godot --version

      - name: Audit GDScript structure and resource paths
        shell: bash
        run: |
          set -o pipefail
          mkdir -p ci-logs
          python3 ci/audit_gdscript.py 2>&1 | tee ci-logs/static-audit.log

      - name: Import project resources
        shell: bash
        run: |
          set -o pipefail
          mkdir -p ci-logs
          timeout 300s godot --headless --path . --import 2>&1 | tee ci-logs/import.log

      - name: Run Paladin tests
        shell: bash
        run: bash ci/run_godot_tests.sh

      - name: Upload Godot logs
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: godot-ci-logs
          path: ci-logs/
          if-no-files-found: warn
          retention-days: 14
'''
(root / ".github/workflows/godot-ci.yml").write_text(
    final_workflow,
    encoding="utf-8",
)

for relative in [
    ".github/workflows/apply-topology-safety-pass.yml",
    "ci/apply_topology_safety_pass.py",
    "ci/repair_topology_transformer.py",
]:
    target = root / relative
    if target.exists():
        target.unlink()

# The running interpreter keeps this file open, so it can remove itself safely.
Path(__file__).unlink()
print("Topology branch finalized and temporary tooling removed.")
