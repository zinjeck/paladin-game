#!/usr/bin/env python3
from pathlib import Path

path = Path("ci/refactor_city_construction_api.py")
lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
in_final_assertions = False
changed = False
for index, line in enumerate(lines):
    if line.startswith("# Final zero-leftover and owner-shape assertions."):
        in_final_assertions = True
    if in_final_assertions and 'rf"' in line and "\\\\" in line:
        fixed = line.replace("\\\\", "\\")
        if fixed != line:
            lines[index] = fixed
            changed = True
if not changed:
    raise SystemExit("No over-escaped final assertion regexes found")
path.write_text("".join(lines), encoding="utf-8")
print("Fixed construction refactor final assertion regex escaping.")
