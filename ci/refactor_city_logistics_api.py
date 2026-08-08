#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
WORLD_PATH = ROOT / "scripts/world/simulation/WorldData.gd"
SYSTEM_PATH = ROOT / "scripts/city/simulation/systems/CityLogisticsSystem.gd"
STATE_PATH = ROOT / "scripts/city/simulation/CityLogisticsState.gd"
AUDIT_PATH = ROOT / "ci/audit_gdscript.py"

EXTRACTED_FUNCTIONS = [
    "city_surface_feature_blocks_ground_pile",
    "_mark_city_ground_piles_changed",
    "_mark_city_haul_reservations_changed",
    "make_city_construction_site_haul_endpoint",
    "get_city_ground_pile_construction_site_id",
    "city_ground_pile_is_construction_reserved",
    "make_city_citizen_haul_endpoint",
    "make_city_ground_pile_haul_endpoint",
    "make_city_ground_tile_haul_endpoint",
    "city_citizen_haul_endpoints_match",
    "rebuild_city_ground_pile_index",
    "get_city_ground_pile_index_by_id",
    "get_city_ground_pile_by_id",
    "get_city_ground_pile_snapshot",
    "get_city_ground_piles_at_tile",
    "has_city_ground_pile_at_tile",
    "can_city_ground_pile_exist_at_tile",
    "get_city_ground_pile_free_space",
    "get_city_ground_pile_tile_distance_squared",
    "_find_city_ground_pile_merge_target_index",
    "add_resource_to_city_ground_piles_with_result",
    "add_resource_to_city_ground_pile",
    "rollback_city_ground_pile_additions",
    "get_city_ground_pile_resource_amount",
    "remove_resource_from_city_ground_pile",
    "reserve_city_ground_pile_for_construction",
    "get_total_city_ground_pile_resource_amount",
    "_get_city_haul_endpoint_key",
    "_get_city_haul_source_reservation_key",
    "_change_city_haul_reserved_source_amount",
    "_change_city_haul_reserved_destination_amount",
    "get_city_haul_reservation",
    "get_city_haul_reservation_snapshot",
    "city_haul_reservation_is_soft",
    "get_city_soft_haul_reservation_ids_for_destination_resource",
    "get_city_soft_haul_destination_reserved_resource_amount",
    "release_soft_city_haul_reservation_for_reassignment",
    "reduce_soft_city_haul_reservation_for_reassignment",
    "preempt_soft_city_haul_reservations_for_destination_resource",
    "get_city_haul_reservation_id_for_citizen",
    "get_city_haul_endpoint_source_reserved_amount",
    "get_city_haul_endpoint_destination_reserved_amount",
    "get_city_haul_endpoint_resource_amount",
    "get_city_haul_endpoint_unreserved_resource_amount",
    "get_city_haul_endpoint_unreserved_destination_space",
    "get_city_haul_endpoint_unreserved_destination_resource_space",
    "city_haul_endpoint_can_provide_resource",
    "city_haul_endpoint_can_accept_resource",
    "_normalize_city_haul_resource_manifest",
    "_get_city_haul_resource_manifest_total",
    "get_city_haul_reservation_destination_resources",
    "get_city_haul_reservation_destination_resource_amount",
    "create_city_haul_reservation",
    "_make_city_haul_reservation_context",
    "_prepare_city_haul_reservation_amounts",
    "_prepare_loaded_city_haul_reservation",
    "_prepare_pending_city_haul_reservation",
    "_commit_city_haul_reservation",
    "expand_pending_city_haul_reservation",
    "expand_pending_city_haul_reservations",
    "retarget_city_haul_reservation_source",
    "release_city_haul_reservation",
    "release_city_haul_reservation_for_citizen",
    "reset_city_ground_pile_state",
    "reset_city_haul_reservation_state",
]
EXTRACTED_SET = set(EXTRACTED_FUNCTIONS)

STATE_FIELDS = {
    "city_ground_piles": "ground_piles",
    "city_ground_pile_index_by_id": "ground_pile_index_by_id",
    "next_city_ground_pile_id": "next_ground_pile_id",
    "city_ground_pile_version": "ground_pile_version",
    "city_haul_reservations": "haul_reservations",
    "city_haul_reservation_id_by_citizen_id": "haul_reservation_id_by_citizen_id",
    "city_haul_source_reserved_amount_by_key": "haul_source_reserved_amount_by_key",
    "city_haul_destination_reserved_amount_by_key": "haul_destination_reserved_amount_by_key",
    "next_city_haul_reservation_id": "next_haul_reservation_id",
    "city_haul_reservation_version": "haul_reservation_version",
}

MOVED_CONSTANTS = {
    "CITY_GROUND_PILE_CAPACITY": "20",
    "CITY_GROUND_PILE_MERGE_RADIUS_TILES": "2",
    "CITY_GROUND_DROP_RESERVATION_CAPACITY": "1_000_000",
}

CONST_RE = re.compile(r"(?m)^const\s+([A-Za-z_][A-Za-z0-9_]*)\b")
STATIC_VAR_RE = re.compile(r"(?m)^static\s+var\s+([A-Za-z_][A-Za-z0-9_]*)\b")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def top_level_function_spans(text: str) -> dict[str, tuple[int, int, str]]:
    lines = text.splitlines(keepends=True)
    offsets: list[int] = []
    offset = 0
    for line in lines:
        offsets.append(offset)
        offset += len(line)

    result: dict[str, tuple[int, int, str]] = {}
    for i, line in enumerate(lines):
        match = re.match(r"^(?:static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", line)
        if not match:
            continue
        name = match.group(1)
        if name in result:
            raise RuntimeError(f"duplicate top-level function: {name}")

        paren_balance = 0
        signature_end = None
        for j in range(i, len(lines)):
            paren_balance += lines[j].count("(") - lines[j].count(")")
            if paren_balance <= 0 and lines[j].rstrip().endswith(":"):
                signature_end = j
                break
        if signature_end is None:
            raise RuntimeError(f"could not find signature end for {name}")

        end_line = len(lines)
        for j in range(signature_end + 1, len(lines)):
            candidate = lines[j]
            if not candidate.strip():
                continue
            if candidate[0] not in (" ", "\t"):
                end_line = j
                break

        start_offset = offsets[i]
        end_offset = offsets[end_line] if end_line < len(offsets) else len(text)
        result[name] = (start_offset, end_offset, text[start_offset:end_offset])
    return result


def replace_code_token(text: str, token: str, replacement: str) -> str:
    return re.sub(rf"(?<![A-Za-z0-9_.]){re.escape(token)}\b", replacement, text)


def transform_extracted_function(
    block: str,
    world_function_names: set[str],
    world_global_symbols: set[str],
) -> str:
    transformed = block

    for name in EXTRACTED_FUNCTIONS:
        transformed = transformed.replace(f"WorldData.{name}(", f"{name}(")

    for constant in MOVED_CONSTANTS:
        transformed = transformed.replace(f"WorldData.{constant}", constant)

    for legacy_field, state_field in STATE_FIELDS.items():
        transformed = transformed.replace(
            f"WorldData.{legacy_field}", f"_state().{state_field}"
        )
        transformed = replace_code_token(
            transformed, legacy_field, f"_state().{state_field}"
        )

    for name in sorted(world_function_names - EXTRACTED_SET, key=len, reverse=True):
        transformed = re.sub(
            rf"(?<![A-Za-z0-9_.]){re.escape(name)}\s*\(",
            f"WorldData.{name}(",
            transformed,
        )

    excluded_globals = set(STATE_FIELDS) | set(MOVED_CONSTANTS) | {"CityCitizensScript"}
    for symbol in sorted(world_global_symbols - excluded_globals, key=len, reverse=True):
        transformed = replace_code_token(transformed, symbol, f"WorldData.{symbol}")

    return transformed.rstrip() + "\n\n"


def update_world_data(original: str) -> tuple[str, str]:
    spans = top_level_function_spans(original)
    missing = [name for name in EXTRACTED_FUNCTIONS if name not in spans]
    if missing:
        raise RuntimeError("missing extraction functions: " + ", ".join(missing))

    world_function_names = set(spans)
    world_global_symbols = set(CONST_RE.findall(original)) | set(STATIC_VAR_RE.findall(original))

    blocks_in_source_order = sorted(
        (spans[name] for name in EXTRACTED_FUNCTIONS), key=lambda item: item[0]
    )
    moved_functions = "".join(
        transform_extracted_function(block, world_function_names, world_global_symbols)
        for _, _, block in blocks_in_source_order
    )

    world = original
    for start, end, _ in sorted(blocks_in_source_order, key=lambda item: item[0], reverse=True):
        world = world[:start] + world[end:]

    logistics_storage_start = world.find(
        "# Ground piles are nonblocking logistics entities, not city objects."
    )
    logistics_storage_end = world.find("static var city_citizens: Array = []")
    if logistics_storage_start < 0 or logistics_storage_end < 0:
        raise RuntimeError("could not locate WorldData logistics compatibility storage block")
    world = (
        world[:logistics_storage_start]
        + "# Physical ground-pile and haul-reservation ownership lives in\n"
        + "# CityLogisticsState/CityLogisticsSystem for the active settlement.\n"
        + world[logistics_storage_end:]
    )

    version_start = world.find("static var city_ground_pile_version: int:")
    version_end = world.find("static var city_construction_version: int = 0")
    if version_start < 0 or version_end < 0 or version_end <= version_start:
        raise RuntimeError("could not locate WorldData logistics version compatibility block")
    world = world[:version_start] + world[version_end:]

    for legacy_field, state_field in STATE_FIELDS.items():
        world = replace_code_token(
            world,
            legacy_field,
            f"CityLogisticsSystem.get_current_state().{state_field}",
        )

    for constant in MOVED_CONSTANTS:
        world = replace_code_token(world, constant, f"CityLogisticsSystem.{constant}")

    for name in EXTRACTED_FUNCTIONS:
        world = world.replace(
            f"WorldData.{name}(",
            f"CityLogisticsSystem.{name}(",
        )
        world = re.sub(
            rf"(?<![A-Za-z0-9_.]){re.escape(name)}\s*\(",
            f"CityLogisticsSystem.{name}(",
            world,
        )

    for symbol in STATE_FIELDS:
        if re.search(rf"^\s*static\s+var\s+{re.escape(symbol)}\b", world, re.MULTILINE):
            raise RuntimeError(f"legacy logistics field declaration remains in WorldData: {symbol}")
    for constant in MOVED_CONSTANTS:
        if re.search(rf"^\s*const\s+{re.escape(constant)}\b", world, re.MULTILINE):
            raise RuntimeError(f"legacy logistics constant remains in WorldData: {constant}")
    for name in EXTRACTED_FUNCTIONS:
        if re.search(
            rf"^\s*(?:static\s+)?func\s+{re.escape(name)}\s*\(",
            world,
            re.MULTILINE,
        ):
            raise RuntimeError(f"legacy logistics function remains in WorldData: {name}")

    return world, moved_functions


def build_logistics_system(moved_functions: str) -> str:
    constants = "\n".join(
        f"const {name}: int = {value}" for name, value in MOVED_CONSTANTS.items()
    )
    return f'''extends RefCounted
class_name CityLogisticsSystem

# File responsibility: Physical city logistics for the active CITY settlement.
# CityLogisticsState owns pile/reservation data; this system owns ground-pile
# mutation, haul endpoint accounting, reservation lifecycle, and related rules.
# Construction, citizens, food, and object storage remain owned by their current
# systems and are consulted through their existing APIs rather than absorbed here.

const CityCitizensScript = preload(
\t"res://scripts/citizens/simulation/CityCitizens.gd"
)

{constants}


static func get_current_state() -> CityLogisticsState:
\treturn WorldPoliticalState.get_current_city_logistics_state()


static func _state() -> CityLogisticsState:
\treturn get_current_state()


{moved_functions.rstrip()}
'''


def migrate_script_callers() -> None:
    for path in sorted((ROOT / "scripts").rglob("*.gd")):
        if path in {WORLD_PATH, SYSTEM_PATH}:
            continue
        text = path.read_text(encoding="utf-8")
        original = text

        for name in EXTRACTED_FUNCTIONS:
            text = text.replace(f"WorldData.{name}", f"CityLogisticsSystem.{name}")

        for legacy_field, state_field in STATE_FIELDS.items():
            text = text.replace(
                f"WorldData.{legacy_field}",
                f"CityLogisticsSystem.get_current_state().{state_field}",
            )

        for constant in MOVED_CONSTANTS:
            text = text.replace(f"WorldData.{constant}", f"CityLogisticsSystem.{constant}")

        text = text.replace(
            "WorldData compatibility fields must resolve to the active City's logistics state.",
            "CityLogisticsSystem must resolve to the active City's logistics state.",
        )

        if text != original:
            path.write_text(text, encoding="utf-8")


def update_state_comment() -> None:
    text = STATE_PATH.read_text(encoding="utf-8")
    old = '''# This object owns only the physical ground-pile registry and atomic hauling
# reservation registries/counters. WorldData temporarily exposes compatibility
# accessors while the existing logistics APIs are migrated in a later pass.
#
# Ground-pile and reservation behavior remains in the existing systems for now;
# this class is deliberately a small state container rather than a second
# simulation brain.
'''
    new = '''# This object owns only the physical ground-pile registry and atomic hauling
# reservation registries/counters. CityLogisticsSystem owns the behavior and
# resolves this state through the active settlement context.
#
# Keep this class a small state container rather than a second simulation brain.
'''
    text = replace_once(text, old, new, "CityLogisticsState ownership comment")
    STATE_PATH.write_text(text, encoding="utf-8")


def update_audit() -> None:
    text = AUDIT_PATH.read_text(encoding="utf-8")

    old_def = '''WORLD_DATA_CITY_LOGISTICS_COMPATIBILITY_FIELDS = {
    "city_ground_piles": "ground_piles",
    "city_ground_pile_index_by_id": "ground_pile_index_by_id",
    "next_city_ground_pile_id": "next_ground_pile_id",
    "city_ground_pile_version": "ground_pile_version",
    "city_haul_reservations": "haul_reservations",
    "city_haul_reservation_id_by_citizen_id": "haul_reservation_id_by_citizen_id",
    "city_haul_source_reserved_amount_by_key": "haul_source_reserved_amount_by_key",
    "city_haul_destination_reserved_amount_by_key": "haul_destination_reserved_amount_by_key",
    "next_city_haul_reservation_id": "next_haul_reservation_id",
    "city_haul_reservation_version": "haul_reservation_version",
}
'''
    logistics_symbols = list(STATE_FIELDS) + list(MOVED_CONSTANTS) + EXTRACTED_FUNCTIONS
    new_def = "WORLD_DATA_FORBIDDEN_CITY_LOGISTICS_SYMBOLS = (\n" + "".join(
        f'    "{symbol}",\n' for symbol in logistics_symbols
    ) + ")\n"
    text = replace_once(text, old_def, new_def, "audit logistics symbol definition")

    old_check = '''        for symbol, state_field in WORLD_DATA_CITY_LOGISTICS_COMPATIBILITY_FIELDS.items():
            if re.search(
                rf"^\\s*static\\s+var\\s+{re.escape(symbol)}\\b[^\\n]*=",
                world_data_text,
                re.MULTILINE,
            ):
                errors.append(
                    "scripts/world/simulation/WorldData.gd: city logistics storage "
                    f"must not return to WorldData: {symbol}"
                )
            resolver = (
                "WorldPoliticalState.get_current_city_logistics_state()."
                + state_field
            )
            if world_data_text.count(resolver) < 2:
                errors.append(
                    "scripts/world/simulation/WorldData.gd: logistics compatibility "
                    f"field must forward getter/setter to settlement state: {symbol}"
                )

'''
    new_check = '''        for symbol in WORLD_DATA_FORBIDDEN_CITY_LOGISTICS_SYMBOLS:
            declaration_patterns = (
                rf"^\\s*static\\s+var\\s+{re.escape(symbol)}\\b",
                rf"^\\s*const\\s+{re.escape(symbol)}\\b",
                rf"^\\s*(?:static\\s+)?func\\s+{re.escape(symbol)}\\s*\\(",
            )
            if any(
                re.search(pattern, world_data_text, re.MULTILINE)
                for pattern in declaration_patterns
            ):
                errors.append(
                    "scripts/world/simulation/WorldData.gd: extracted city-logistics "
                    f"ownership declaration must not return to WorldData: {symbol}"
                )

'''
    text = replace_once(text, old_check, new_check, "audit WorldData logistics ownership check")

    old_cross = '''        for symbol in WORLD_DATA_FORBIDDEN_CITY_WORK_SYMBOLS:
            legacy_reference = f"WorldData.{symbol}"
            if legacy_reference in text:
                errors.append(
                    f"{relative}: legacy WorldData city-work reference remains: "
                    f"{legacy_reference}"
                )

'''
    new_cross = old_cross + '''        for symbol in WORLD_DATA_FORBIDDEN_CITY_LOGISTICS_SYMBOLS:
            legacy_reference = f"WorldData.{symbol}"
            if legacy_reference in text:
                errors.append(
                    f"{relative}: legacy WorldData city-logistics reference remains: "
                    f"{legacy_reference}"
                )

'''
    text = replace_once(text, old_cross, new_cross, "audit cross-file logistics reference check")

    AUDIT_PATH.write_text(text, encoding="utf-8")


def validate_no_legacy_script_references() -> None:
    forbidden = list(STATE_FIELDS) + list(MOVED_CONSTANTS) + EXTRACTED_FUNCTIONS
    errors: list[str] = []
    for path in sorted((ROOT / "scripts").rglob("*.gd")):
        text = path.read_text(encoding="utf-8")
        for symbol in forbidden:
            needle = f"WorldData.{symbol}"
            if needle in text:
                errors.append(f"{path.relative_to(ROOT)}: {needle}")
    if errors:
        raise RuntimeError("legacy WorldData logistics references remain:\n" + "\n".join(errors))


def main() -> None:
    if SYSTEM_PATH.exists():
        raise RuntimeError(f"refusing to overwrite existing {SYSTEM_PATH.relative_to(ROOT)}")

    original_world = WORLD_PATH.read_text(encoding="utf-8")
    world, moved_functions = update_world_data(original_world)
    WORLD_PATH.write_text(world, encoding="utf-8")
    SYSTEM_PATH.write_text(build_logistics_system(moved_functions), encoding="utf-8")

    migrate_script_callers()
    update_state_comment()
    update_audit()
    validate_no_legacy_script_references()

    print(f"Extracted {len(EXTRACTED_FUNCTIONS)} logistics functions into CityLogisticsSystem.gd")
    print("Removed WorldData logistics compatibility fields/constants and migrated script callers")


if __name__ == "__main__":
    main()
