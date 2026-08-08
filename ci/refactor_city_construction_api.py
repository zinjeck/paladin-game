#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
WORLD_PATH = ROOT / "scripts/world/simulation/WorldData.gd"
SYSTEM_PATH = ROOT / "scripts/city/simulation/systems/CityConstructionSystem.gd"
STATE_PATH = ROOT / "scripts/city/simulation/CityConstructionState.gd"
AUDIT_PATH = ROOT / "ci/audit_gdscript.py"
ROOT_STATE_PATH = ROOT / "scripts/city/simulation/CitySettlementSimulationState.gd"

STATE_FIELDS = {
    "city_construction_sites": "construction_sites",
    "city_construction_site_index_by_id": "construction_site_index_by_id",
    "city_construction_site_id_by_tile": "construction_site_id_by_tile",
    "next_city_construction_site_id": "next_construction_site_id",
    "city_construction_version": "construction_version",
}

CONSTRUCTION_CONSTANTS = [
    "CITY_CONSTRUCTION_PHASE_CLEARING",
    "CITY_CONSTRUCTION_PHASE_GATHERING",
    "CITY_CONSTRUCTION_PHASE_LABOR",
    "CITY_CONSTRUCTION_FINALIZATION_STATE_NONE",
    "CITY_CONSTRUCTION_FINALIZATION_STATE_AWAITING_CLEARANCE",
    "CITY_CONSTRUCTION_TARGET_NEW",
    "CITY_CONSTRUCTION_TARGET_MODIFICATION",
    "CITY_CONSTRUCTION_TASK_PRIORITY",
    "CITY_CONSTRUCTION_FAIRNESS_BONUS_PER_MINUTE",
    "CITY_CONSTRUCTION_MAX_FAIRNESS_BONUS",
    "CITY_CONSTRUCTION_LABOR_ATOMIC_MINUTES",
]

MOVE_FUNCTIONS = [
    "get_city_object_construction_materials",
    "city_object_type_uses_construction",
    "mark_city_construction_changed",
    "get_city_construction_site_index_by_id",
    "get_city_construction_site_by_id",
    "can_place_city_construction_footprint",
    "reset_city_construction_state",
    "get_city_construction_site_work_positions",
    "get_city_construction_site_reserved_resource_amount",
    "get_city_construction_site_remaining_resource_amount",
    "get_city_construction_site_destination_reserved_resource_amount",
    "get_city_construction_site_unreserved_resource_space",
    "get_city_construction_site_unreserved_total_space",
    "_prepare_city_construction_task_assignment",
    "can_place_city_object_construction",
]

RENAME_FUNCTIONS = {
    "_prepare_city_construction_task_assignment": "prepare_city_construction_task_assignment",
}

CONSTANT_BLOCK = '''const CITY_CONSTRUCTION_PHASE_CLEARING := "clearing"
const CITY_CONSTRUCTION_PHASE_GATHERING := "gathering"
const CITY_CONSTRUCTION_PHASE_LABOR := "labor"
const CITY_CONSTRUCTION_FINALIZATION_STATE_NONE := "none"
const CITY_CONSTRUCTION_FINALIZATION_STATE_AWAITING_CLEARANCE := (
\t"awaiting_clearance"
)
const CITY_CONSTRUCTION_TARGET_NEW := "new"
const CITY_CONSTRUCTION_TARGET_MODIFICATION := "modification"
const CITY_CONSTRUCTION_TASK_PRIORITY: int = 1000
const CITY_CONSTRUCTION_FAIRNESS_BONUS_PER_MINUTE: int = 100
const CITY_CONSTRUCTION_MAX_FAIRNESS_BONUS: int = 20_000
# A construction labor task contributes at most this many continuous world
# minutes before releasing its concrete claim and returning to the parent-order
# scheduler. This is the shared safe boundary for fairness and hunger policy.
const CITY_CONSTRUCTION_LABOR_ATOMIC_MINUTES: int = 30
'''


def fail(message: str) -> None:
    raise SystemExit(message)


def top_level_block(text: str, declaration_pattern: str) -> tuple[int, int, str]:
    match = re.search(declaration_pattern, text, re.MULTILINE)
    if not match:
        fail(f"missing expected declaration: {declaration_pattern}")
    start = match.start()
    line_end = text.find("\n", match.end())
    if line_end < 0:
        return start, len(text), text[start:]
    pos = line_end + 1
    while pos < len(text):
        next_end = text.find("\n", pos)
        if next_end < 0:
            next_end = len(text)
        line = text[pos:next_end]
        if line.strip() and not line[0].isspace():
            return start, pos, text[start:pos]
        pos = next_end + 1
    return start, len(text), text[start:]


def remove_top_level_function(text: str, name: str) -> tuple[str, str]:
    pattern = rf"^(?:static\s+)?func\s+{re.escape(name)}\s*\("
    matches = list(re.finditer(pattern, text, re.MULTILINE))
    if len(matches) != 1:
        fail(f"expected exactly one WorldData function {name}, found {len(matches)}")
    start, end, block = top_level_block(text, pattern)
    return text[:start] + text[end:], block.rstrip() + "\n"


def remove_top_level_const(text: str, name: str) -> str:
    pattern = rf"^const\s+{re.escape(name)}\b"
    matches = list(re.finditer(pattern, text, re.MULTILINE))
    if len(matches) != 1:
        fail(f"expected exactly one WorldData constant {name}, found {len(matches)}")
    start, end, _ = top_level_block(text, pattern)
    return text[:start] + text[end:]


def remove_top_level_var(text: str, name: str) -> str:
    pattern = rf"^static\s+var\s+{re.escape(name)}\b"
    matches = list(re.finditer(pattern, text, re.MULTILINE))
    if len(matches) != 1:
        fail(f"expected exactly one WorldData field {name}, found {len(matches)}")
    start, end, _ = top_level_block(text, pattern)
    return text[:start] + text[end:]


def qualify_moved_function(block: str, old_name: str) -> str:
    new_name = RENAME_FUNCTIONS.get(old_name, old_name)
    if new_name != old_name:
        block = re.sub(
            rf"^(static\s+func\s+){re.escape(old_name)}\b",
            rf"\1{new_name}",
            block,
            count=1,
            flags=re.MULTILINE,
        )

    for legacy, state_name in STATE_FIELDS.items():
        block = re.sub(rf"\b{re.escape(legacy)}\b", f"get_current_state().{state_name}", block)

    block = block.replace(
        "WorldData.can_place_city_construction_footprint",
        "can_place_city_construction_footprint",
    )

    qualify = {
        "TERRAIN_WATER",
        "TERRAIN_MOUNTAIN",
        "CITY_CARDINAL_TILE_OFFSETS",
        "is_city_tile_walkable_for_citizen",
        "INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID",
        "get_city_resource_types",
        "CITY_CITIZEN_TASK_SOURCE_PLAYER",
        "INVALID_CITY_TILE_POSITION",
        "make_rectangle_city_object_footprint_tiles",
    }
    for symbol in sorted(qualify, key=len, reverse=True):
        block = re.sub(
            rf"(?<![A-Za-z0-9_\.]){re.escape(symbol)}\b",
            f"WorldData.{symbol}",
            block,
        )

    return block


def migrate_external_references(path: Path, text: str) -> str:
    is_system = path == SYSTEM_PATH
    is_world = path == WORLD_PATH

    for constant in CONSTRUCTION_CONSTANTS:
        if is_system:
            text = re.sub(
                rf"WorldData\s*\.\s*{re.escape(constant)}\b",
                constant,
                text,
            )
        else:
            text = re.sub(
                rf"WorldData\s*\.\s*{re.escape(constant)}\b",
                f"CityConstructionSystem.{constant}",
                text,
            )

    for old_name in MOVE_FUNCTIONS:
        public_name = RENAME_FUNCTIONS.get(old_name, old_name)
        if old_name.startswith("_"):
            continue
        replacement = public_name if is_system else f"CityConstructionSystem.{public_name}"
        text = re.sub(
            rf"WorldData\s*\.\s*{re.escape(old_name)}\b",
            replacement,
            text,
        )

    for legacy, state_name in STATE_FIELDS.items():
        replacement = f"get_current_state().{state_name}" if is_system else f"CityConstructionSystem.get_current_state().{state_name}"
        text = re.sub(
            rf"WorldData\s*\.\s*{re.escape(legacy)}\b",
            replacement,
            text,
        )

    if is_world:
        text = text.replace(
            "_prepare_city_construction_task_assignment(assignment)",
            "CityConstructionSystem.prepare_city_construction_task_assignment(assignment)",
        )
        for constant in CONSTRUCTION_CONSTANTS:
            text = re.sub(
                rf"(?<![A-Za-z0-9_\.]){re.escape(constant)}\b",
                f"CityConstructionSystem.{constant}",
                text,
            )
        for legacy, state_name in STATE_FIELDS.items():
            text = re.sub(
                rf"(?<![A-Za-z0-9_\.]){re.escape(legacy)}\b",
                f"CityConstructionSystem.get_current_state().{state_name}",
                text,
            )
        for old_name in MOVE_FUNCTIONS:
            if old_name.startswith("_"):
                continue
            public_name = RENAME_FUNCTIONS.get(old_name, old_name)
            text = re.sub(
                rf"(?<![A-Za-z0-9_\.]){re.escape(old_name)}\b",
                f"CityConstructionSystem.{public_name}",
                text,
            )

    return text


world = WORLD_PATH.read_text(encoding="utf-8")
system = SYSTEM_PATH.read_text(encoding="utf-8")
state = STATE_PATH.read_text(encoding="utf-8")
audit = AUDIT_PATH.read_text(encoding="utf-8")

# Guard the expected pre-refactor ownership shape.
for name in MOVE_FUNCTIONS:
    if len(re.findall(rf"^(?:static\s+)?func\s+{re.escape(name)}\s*\(", world, re.MULTILINE)) != 1:
        fail(f"WorldData function guard failed: {name}")
    public_name = RENAME_FUNCTIONS.get(name, name)
    if re.search(rf"^(?:static\s+)?func\s+{re.escape(public_name)}\s*\(", system, re.MULTILINE):
        fail(f"CityConstructionSystem already defines target function: {public_name}")
for constant in CONSTRUCTION_CONSTANTS:
    if len(re.findall(rf"^const\s+{re.escape(constant)}\b", world, re.MULTILINE)) != 1:
        fail(f"WorldData constant guard failed: {constant}")
for legacy in STATE_FIELDS:
    if len(re.findall(rf"^static\s+var\s+{re.escape(legacy)}\b", world, re.MULTILINE)) != 1:
        fail(f"WorldData compatibility field guard failed: {legacy}")

moved_blocks: list[str] = []
for name in MOVE_FUNCTIONS:
    world, block = remove_top_level_function(world, name)
    moved_blocks.append(qualify_moved_function(block, name))

for constant in CONSTRUCTION_CONSTANTS:
    world = remove_top_level_const(world, constant)
for legacy in STATE_FIELDS:
    world = remove_top_level_var(world, legacy)

world = world.replace(
    "# A construction labor task contributes at most this many continuous world\n"
    "# minutes before releasing its concrete claim and returning to the parent-order\n"
    "# scheduler. This is the shared safe boundary for fairness and hunger policy.\n",
    "",
)
world = re.sub(
    r"\n#region Construction State Primitives\n\s*#endregion\n",
    "\n",
    world,
)
world = migrate_external_references(WORLD_PATH, world)

# Finish CityConstructionSystem as the behavior/API owner.
system = system.replace(
    "# File responsibility: Construction-site operations, lifecycle, work selection, material delivery, labor, and completion. Authoritative site collections remain in WorldData.\n",
    "# File responsibility: Authoritative construction behavior/API for one active city settlement. Mutable construction registries live in CityConstructionState.\n",
)
preload_anchor = 'const CityNavigationSystemScript = preload(\n'
if preload_anchor not in system:
    fail("missing CityConstructionSystem preload anchor")
system = system.replace(
    preload_anchor,
    'const CityObjectCatalogScript = preload(\n\t"res://scripts/city/data/CityObjectCatalog.gd"\n)\n' + preload_anchor,
    1,
)

# Remove the old finalization aliases now that the canonical constants live here.
for alias in ("FINALIZATION_STATE_NONE", "FINALIZATION_STATE_AWAITING_CLEARANCE"):
    if re.search(rf"^const\s+{alias}\b", system, re.MULTILINE):
        start, end, _ = top_level_block(system, rf"^const\s+{alias}\b")
        system = system[:start] + system[end:]
system = re.sub(r"\bFINALIZATION_STATE_NONE\b", "CITY_CONSTRUCTION_FINALIZATION_STATE_NONE", system)
system = re.sub(r"\bFINALIZATION_STATE_AWAITING_CLEARANCE\b", "CITY_CONSTRUCTION_FINALIZATION_STATE_AWAITING_CLEARANCE", system)
system = migrate_external_references(SYSTEM_PATH, system)

insert_anchor = "\n#region Construction Site Registry Operations\n"
if insert_anchor not in system:
    fail("missing construction registry region anchor")
api_block = (
    "\n" + CONSTANT_BLOCK +
    "\n\nstatic func get_current_state() -> CityConstructionState:\n"
    "\treturn WorldPoliticalState.get_current_city_construction_state()\n\n\n"
    + "\n\n".join(block.rstrip() for block in moved_blocks)
    + "\n"
)
system = system.replace(insert_anchor, api_block + insert_anchor, 1)

# Migrate every other GDScript caller, including focused state tests/validators.
for path in sorted(ROOT.glob("scripts/**/*.gd")):
    if path in (WORLD_PATH, SYSTEM_PATH):
        continue
    original = path.read_text(encoding="utf-8")
    migrated = migrate_external_references(path, original)
    if migrated != original:
        path.write_text(migrated, encoding="utf-8")

# Update state documentation now that behavior ownership is complete.
state = state.replace(
    "# This object owns only construction-site collections, indexes, counters, and\n"
    "# the focused construction change version. Construction rules and behavior stay\n"
    "# in the existing construction APIs for this ownership-only pass.\n",
    "# This object owns only construction-site collections, indexes, counters, and\n"
    "# the focused construction change version. CityConstructionSystem owns the\n"
    "# construction rules, queries, mutations, lifecycle, and scheduling behavior.\n",
)

# Replace the temporary compatibility audit with the permanent ownership/API guard.
compat_def_re = re.compile(
    r"WORLD_DATA_CONSTRUCTION_COMPATIBILITY_FIELDS = \(\n.*?\n\)\n\n",
    re.DOTALL,
)
if not compat_def_re.search(audit):
    fail("missing construction compatibility audit definition")
forbidden_symbols = list(STATE_FIELDS.keys()) + CONSTRUCTION_CONSTANTS + MOVE_FUNCTIONS + [
    "prepare_city_construction_task_assignment",
]
forbidden_tuple = "WORLD_DATA_FORBIDDEN_CITY_CONSTRUCTION_SYMBOLS = (\n" + "".join(
    f'    "{symbol}",\n' for symbol in forbidden_symbols
) + ")\n\n"
audit = compat_def_re.sub(forbidden_tuple, audit, count=1)

start_marker = '    construction_state_path = ROOT / "scripts/city/simulation/CityConstructionState.gd"\n'
end_marker = '    report = {\n'
start = audit.find(start_marker)
end = audit.find(end_marker, start)
if start < 0 or end < 0:
    fail("missing construction compatibility audit block")
new_audit_block = '''    construction_state_path = ROOT / "scripts/city/simulation/CityConstructionState.gd"
    city_root_state_path = ROOT / "scripts/city/simulation/CitySettlementSimulationState.gd"
    construction_system_path = ROOT / "scripts/city/simulation/systems/CityConstructionSystem.gd"
    if world_data_path.exists() and construction_state_path.exists() and city_root_state_path.exists() and construction_system_path.exists():
        world_data_text = world_data_path.read_text(encoding="utf-8")
        construction_state_text = construction_state_path.read_text(encoding="utf-8")
        city_root_state_text = city_root_state_path.read_text(encoding="utf-8")
        construction_system_text = construction_system_path.read_text(encoding="utf-8")

        for symbol in WORLD_DATA_FORBIDDEN_CITY_CONSTRUCTION_SYMBOLS:
            declaration_patterns = (
                rf"^\\s*static\\s+var\\s+{re.escape(symbol)}\\b",
                rf"^\\s*const\\s+{re.escape(symbol)}\\b",
                rf"^\\s*(?:static\\s+)?func\\s+{re.escape(symbol)}\\s*\\(",
            )
            if any(re.search(pattern, world_data_text, re.MULTILINE) for pattern in declaration_patterns):
                errors.append(
                    "scripts/world/simulation/WorldData.gd: extracted city-construction "
                    f"ownership declaration must not return to WorldData: {symbol}"
                )

        for path in scripts:
            text = path.read_text(encoding="utf-8")
            relative = str(path.relative_to(ROOT))
            for symbol in WORLD_DATA_FORBIDDEN_CITY_CONSTRUCTION_SYMBOLS:
                legacy_pattern = rf"WorldData\\s*\\.\\s*{re.escape(symbol)}\\b"
                if re.search(legacy_pattern, text):
                    errors.append(
                        f"{relative}: legacy WorldData city-construction reference remains: "
                        f"WorldData.{symbol}"
                    )

        for state_name in ("construction_sites", "construction_site_index_by_id", "construction_site_id_by_tile", "next_construction_site_id", "construction_version"):
            if not re.search(rf"^var\\s+{re.escape(state_name)}\\b", construction_state_text, re.MULTILINE):
                errors.append(
                    f"scripts/city/simulation/CityConstructionState.gd: missing {state_name}"
                )
            if re.search(rf"^var\\s+{re.escape(state_name)}\\b", city_root_state_text, re.MULTILINE):
                errors.append(
                    "scripts/city/simulation/CitySettlementSimulationState.gd: construction storage "
                    f"{state_name} must live in CityConstructionState"
                )

        if "var construction_state: CityConstructionState" not in city_root_state_text:
            errors.append(
                "scripts/city/simulation/CitySettlementSimulationState.gd: missing construction_state owner"
            )
        if "static func get_current_state() -> CityConstructionState:" not in construction_system_text:
            errors.append(
                "scripts/city/simulation/systems/CityConstructionSystem.gd: missing typed construction-state accessor"
            )

'''
audit = audit[:start] + new_audit_block + audit[end:]

WORLD_PATH.write_text(world, encoding="utf-8")
SYSTEM_PATH.write_text(system, encoding="utf-8")
STATE_PATH.write_text(state, encoding="utf-8")
AUDIT_PATH.write_text(audit, encoding="utf-8")

# Final zero-leftover and owner-shape assertions.
world_final = WORLD_PATH.read_text(encoding="utf-8")
system_final = SYSTEM_PATH.read_text(encoding="utf-8")
for symbol in forbidden_symbols:
    patterns = (
        rf"^\s*static\s+var\s+{re.escape(symbol)}\b",
        rf"^\s*const\s+{re.escape(symbol)}\b",
        rf"^\s*(?:static\s+)?func\s+{re.escape(symbol)}\s*\(",
    )
    if any(re.search(pattern, world_final, re.MULTILINE) for pattern in patterns):
        fail(f"WorldData still declares construction symbol: {symbol}")

for path in sorted(ROOT.glob("scripts/**/*.gd")):
    text = path.read_text(encoding="utf-8")
    for symbol in forbidden_symbols:
        if re.search(rf"WorldData\s*\.\s*{re.escape(symbol)}\b", text):
            fail(f"legacy construction reference remains in {path.relative_to(ROOT)}: WorldData.{symbol}")

for constant in CONSTRUCTION_CONSTANTS:
    if not re.search(rf"^const\s+{re.escape(constant)}\b", system_final, re.MULTILINE):
        fail(f"CityConstructionSystem missing moved constant: {constant}")
for old_name in MOVE_FUNCTIONS:
    public_name = RENAME_FUNCTIONS.get(old_name, old_name)
    if not re.search(rf"^static\s+func\s+{re.escape(public_name)}\s*\(", system_final, re.MULTILINE):
        fail(f"CityConstructionSystem missing moved function: {public_name}")

print("Construction API extraction transformed successfully.")
