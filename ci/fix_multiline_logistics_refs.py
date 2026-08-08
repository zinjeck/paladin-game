#!/usr/bin/env python3
from pathlib import Path
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from refactor_city_logistics_api import EXTRACTED_FUNCTIONS, STATE_FIELDS, MOVED_CONSTANTS

ROOT = Path(__file__).resolve().parents[1]

for path in sorted((ROOT / "scripts").rglob("*.gd")):
    if path.name == "CityLogisticsSystem.gd":
        continue
    text = path.read_text(encoding="utf-8")
    original = text
    for name in EXTRACTED_FUNCTIONS:
        text = re.sub(
            rf"WorldData\s*\.\s*{re.escape(name)}\b",
            f"CityLogisticsSystem.{name}",
            text,
        )
    for legacy_field, state_field in STATE_FIELDS.items():
        text = re.sub(
            rf"WorldData\s*\.\s*{re.escape(legacy_field)}\b",
            f"CityLogisticsSystem.get_current_state().{state_field}",
            text,
        )
    for name in MOVED_CONSTANTS:
        text = re.sub(
            rf"WorldData\s*\.\s*{re.escape(name)}\b",
            f"CityLogisticsSystem.{name}",
            text,
        )
    if text != original:
        path.write_text(text, encoding="utf-8")

# Harden the permanent audit so formatting cannot bypass the logistics boundary.
audit_path = ROOT / "ci/audit_gdscript.py"
audit = audit_path.read_text(encoding="utf-8")
old = """        for symbol in WORLD_DATA_FORBIDDEN_CITY_LOGISTICS_SYMBOLS:
            legacy_reference = f\"WorldData.{symbol}\"
            if legacy_reference in text:
                errors.append(
                    f\"{relative}: legacy WorldData city-logistics reference remains: \"
                    f\"{legacy_reference}\"
                )
"""
new = """        for symbol in WORLD_DATA_FORBIDDEN_CITY_LOGISTICS_SYMBOLS:
            legacy_pattern = rf\"WorldData\\s*\\.\\s*{re.escape(symbol)}\\b\"
            if re.search(legacy_pattern, text):
                errors.append(
                    f\"{relative}: legacy WorldData city-logistics reference remains: \"
                    f\"WorldData.{symbol}\"
                )
"""
if audit.count(old) != 1:
    raise RuntimeError(f"expected one logistics audit block, found {audit.count(old)}")
audit = audit.replace(old, new, 1)
audit_path.write_text(audit, encoding="utf-8")

forbidden = list(STATE_FIELDS) + list(MOVED_CONSTANTS) + EXTRACTED_FUNCTIONS
leftovers = []
for path in sorted((ROOT / "scripts").rglob("*.gd")):
    text = path.read_text(encoding="utf-8")
    for symbol in forbidden:
        if re.search(rf"WorldData\s*\.\s*{re.escape(symbol)}\b", text):
            leftovers.append(f"{path.relative_to(ROOT)}: WorldData.{symbol}")
if leftovers:
    raise RuntimeError("legacy logistics references remain:\n" + "\n".join(leftovers))

print("All multiline logistics references migrated and audit hardened.")
