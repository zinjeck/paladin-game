#!/usr/bin/env python3
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
world_path = root / "scripts/world/simulation/WorldData.gd"
system_path = root / "scripts/city/simulation/systems/CityConstructionSystem.gd"
world = world_path.read_text(encoding="utf-8")
system = system_path.read_text(encoding="utf-8")

func_re = re.compile(r"^(?:static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", re.M)
starts = [(m.start(), m.group(1)) for m in func_re.finditer(world)]
print("=== WorldData construction-named functions ===")
for i, (start, name) in enumerate(starts):
    end = starts[i + 1][0] if i + 1 < len(starts) else len(world)
    if "construction" in name.lower():
        line = world.count("\n", 0, start) + 1
        print(f"{line}: {name}")

print("\n=== WorldData CITY_CONSTRUCTION constants ===")
for m in re.finditer(r"^const\s+(CITY_CONSTRUCTION[A-Za-z0-9_]*)\b", world, re.M):
    print(f"{world.count(chr(10), 0, m.start()) + 1}: {m.group(1)}")

print("\n=== ConstructionSystem WorldData construction references ===")
refs = sorted(set(re.findall(r"WorldData\s*\.\s*([A-Za-z_][A-Za-z0-9_]*construction[A-Za-z0-9_]*)", system, re.I)))
for ref in refs:
    print(ref)

print("\n=== ConstructionSystem all WorldData references ===")
all_refs = sorted(set(re.findall(r"WorldData\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)", system)))
for ref in all_refs:
    print(ref)

print("\n=== Repository legacy WorldData construction references by file ===")
pattern = re.compile(r"WorldData\s*\.\s*([A-Za-z_][A-Za-z0-9_]*construction[A-Za-z0-9_]*)", re.I)
for path in sorted(root.glob("scripts/**/*.gd")):
    text = path.read_text(encoding="utf-8")
    found = sorted(set(pattern.findall(text)))
    if found:
        print(path.relative_to(root))
        for ref in found:
            print(f"  {ref}")
