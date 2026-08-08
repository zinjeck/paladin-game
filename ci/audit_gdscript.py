#!/usr/bin/env python3
"""Repository-wide structural audit for Paladin's Godot source.

Godot remains the source of truth for parsing. This script adds fast checks that
are easy to miss in runtime smoke tests and emits maintainability metrics for
all scripts on every pull request.
"""

from __future__ import annotations

import collections
import hashlib
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOG_DIR = ROOT / "ci-logs"
LOG_DIR.mkdir(exist_ok=True)
REPORT_PATH = LOG_DIR / "static-audit.json"

FUNC_RE = re.compile(r"^(?:static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", re.MULTILINE)
CLASS_RE = re.compile(r"^class_name\s+([A-Za-z_][A-Za-z0-9_]*)\s*$", re.MULTILINE)
RESOURCE_RE = re.compile(r'(["\'])res://([^"\']+)\1')
REGION_RE = re.compile(r"^\s*#region\b", re.MULTILINE)
ENDREGION_RE = re.compile(r"^\s*#endregion\b", re.MULTILINE)
FUNC_LINE_RE = re.compile(r"^(?:static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")
QUEUE_REDRAW_RE = re.compile(r"\bqueue_redraw\b")
COMMENT_LINE_RE = re.compile(r"^\s*#(?!region\b|endregion\b)(.*)$", re.IGNORECASE)

FORBIDDEN_REPOSITORY_ARTIFACT_SUFFIXES = {
    ".bak",
    ".backup",
    ".log",
    ".old",
    ".orig",
    ".tmp",
    ".zip",
}
SUSPICIOUS_TEXT_FILE_PARTS = (
    "noop",
    "backup",
    "copy",
    "temporary",
    "temp_",
    "_temp",
    "old_",
    "_old",
)
AUDIT_EXCLUDED_DIRECTORIES = {".git", ".godot", "ci-logs"}
MINIMUM_DUPLICATE_FUNCTION_BODY_LINES = 10
MINIMUM_DUPLICATE_COMMENT_LENGTH = 28

ALLOWED_QUEUE_REDRAW_CALLS = {
    "scripts/city/rendering/CityRenderLayer.gd": 1,
    "scripts/ui/city/CityInformationPanel.gd": 2,
}

WORLD_DATA_FORBIDDEN_CITY_LOGISTICS_SYMBOLS = (
    "city_ground_piles",
    "city_ground_pile_index_by_id",
    "next_city_ground_pile_id",
    "city_ground_pile_version",
    "city_haul_reservations",
    "city_haul_reservation_id_by_citizen_id",
    "city_haul_source_reserved_amount_by_key",
    "city_haul_destination_reserved_amount_by_key",
    "next_city_haul_reservation_id",
    "city_haul_reservation_version",
    "CITY_GROUND_PILE_CAPACITY",
    "CITY_GROUND_PILE_MERGE_RADIUS_TILES",
    "CITY_GROUND_DROP_RESERVATION_CAPACITY",
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
)

WORLD_DATA_FORBIDDEN_CITY_CONSTRUCTION_SYMBOLS = (
    "city_construction_sites",
    "city_construction_site_index_by_id",
    "city_construction_site_id_by_tile",
    "next_city_construction_site_id",
    "city_construction_version",
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
    "prepare_city_construction_task_assignment",
)

WORLD_DATA_FORBIDDEN_CITY_WORK_SYMBOLS = (
    "city_player_commands",
    "city_player_command_index_by_id",
    "city_player_command_id_by_tile",
    "next_city_player_command_id",
    "next_city_player_command_group_id",
    "city_player_command_version",
    "city_work_orders",
    "city_work_order_id_by_source_key",
    "next_city_work_order_id",
    "city_work_order_version",
    "CITY_PLAYER_COMMAND_TYPE_NONE",
    "CITY_PLAYER_COMMAND_TYPE_CHOP_TREE",
    "CITY_PLAYER_COMMAND_TYPE_COLLECT_ROCK",
    "CITY_PLAYER_COMMAND_STATUS_PENDING",
    "CITY_PLAYER_COMMAND_STATUS_CLAIMED",
    "CITY_PLAYER_COMMAND_STATUS_BLOCKED",
    "CITY_PLAYER_COMMAND_TASK_PRIORITY",
    "CITY_PLAYER_COMMAND_WORK_DURATION_MINUTES",
    "CITY_PLAYER_COMMAND_RESOURCE_YIELD",
    "CITY_PLAYER_COMMAND_BLOCKED_RETRY_DELAY_MINUTES",
    "get_city_player_command_types",
    "is_valid_city_player_command_type",
    "get_city_player_command_surface_feature",
    "mark_city_player_commands_changed",
    "mark_city_work_orders_changed",
    "reset_city_work_order_state",
    "get_city_player_command_index_by_id",
    "get_city_player_command_by_id",
    "is_city_player_command_target_valid",
    "release_city_player_command_claim",
    "reset_city_player_command_state",
)


@dataclass(frozen=True)
class FunctionMetric:
    path: str
    name: str
    start_line: int
    line_count: int


def script_paths() -> list[Path]:
    return sorted(ROOT.glob("scripts/**/*.gd"))


def repository_file_paths() -> list[Path]:
    return sorted(
        path
        for path in ROOT.rglob("*")
        if path.is_file()
        and not any(part in AUDIT_EXCLUDED_DIRECTORIES for part in path.parts)
    )


def normalized_function_body_groups(text: str) -> dict[str, list[tuple[str, int]]]:
    lines = text.splitlines()
    starts: list[tuple[int, str]] = []
    for index, line in enumerate(lines):
        match = FUNC_LINE_RE.match(line)
        if match:
            starts.append((index, match.group(1)))

    groups: dict[str, list[tuple[str, int]]] = collections.defaultdict(list)
    for position, (start, name) in enumerate(starts):
        end = starts[position + 1][0] if position + 1 < len(starts) else len(lines)
        normalized_lines: list[str] = []
        for line in lines[start + 1 : end]:
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            normalized_lines.append(re.sub(r"\s+", " ", stripped))

        if len(normalized_lines) < MINIMUM_DUPLICATE_FUNCTION_BODY_LINES:
            continue

        digest = hashlib.sha256("\n".join(normalized_lines).encode("utf-8")).hexdigest()
        groups[digest].append((name, start + 1))

    return groups


def duplicate_substantial_comments(text: str) -> list[tuple[str, list[int]]]:
    occurrences: dict[str, list[int]] = collections.defaultdict(list)
    for line_number, line in enumerate(text.splitlines(), start=1):
        match = COMMENT_LINE_RE.match(line)
        if not match:
            continue
        normalized = re.sub(r"\s+", " ", match.group(1).strip())
        if len(normalized) >= MINIMUM_DUPLICATE_COMMENT_LENGTH:
            occurrences[normalized].append(line_number)

    return [
        (comment, line_numbers)
        for comment, line_numbers in occurrences.items()
        if len(line_numbers) > 1
    ]


def function_metrics(path: Path, text: str) -> list[FunctionMetric]:
    lines = text.splitlines()
    starts: list[tuple[int, str]] = []
    for index, line in enumerate(lines):
        match = FUNC_LINE_RE.match(line)
        if match:
            starts.append((index, match.group(1)))

    metrics: list[FunctionMetric] = []
    for position, (start, name) in enumerate(starts):
        end = starts[position + 1][0] if position + 1 < len(starts) else len(lines)
        metrics.append(
            FunctionMetric(
                path=str(path.relative_to(ROOT)),
                name=name,
                start_line=start + 1,
                line_count=max(end - start, 1),
            )
        )
    return metrics


def main() -> int:
    errors: list[str] = []
    warnings: list[str] = []
    class_owners: dict[str, list[str]] = collections.defaultdict(list)
    all_metrics: list[FunctionMetric] = []
    total_lines = 0
    total_functions = 0

    repository_files = repository_file_paths()
    content_hash_owners: dict[str, list[str]] = collections.defaultdict(list)

    for path in repository_files:
        relative = str(path.relative_to(ROOT))
        suffix = path.suffix.lower()
        lower_name = path.name.lower()

        if suffix in FORBIDDEN_REPOSITORY_ARTIFACT_SUFFIXES:
            errors.append(
                f"{relative}: repository artifact with forbidden suffix {suffix}"
            )
        elif suffix == ".txt" and any(
            marker in lower_name for marker in SUSPICIOUS_TEXT_FILE_PARTS
        ):
            errors.append(f"{relative}: suspicious temporary text artifact")

        if path.stat().st_size <= 2_000_000:
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            content_hash_owners[digest].append(relative)

    for owners in content_hash_owners.values():
        if len(owners) > 1:
            errors.append(
                "Duplicate repository file contents: " + ", ".join(sorted(owners))
            )

    scripts = script_paths()
    if not scripts:
        errors.append("No GDScript files were found under scripts/.")

    for path in scripts:
        relative = path.relative_to(ROOT).as_posix()
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines()
        total_lines += len(lines)

        functions = FUNC_RE.findall(text)
        total_functions += len(functions)
        duplicates = sorted(
            name for name, count in collections.Counter(functions).items() if count > 1
        )
        if duplicates:
            errors.append(f"{relative}: duplicate functions: {', '.join(duplicates)}")

        for body_group in normalized_function_body_groups(text).values():
            if len(body_group) <= 1:
                continue
            locations = ", ".join(
                f"{name}@{line_number}" for name, line_number in body_group
            )
            errors.append(
                f"{relative}: duplicate substantial function bodies: {locations}"
            )

        for comment, line_numbers in duplicate_substantial_comments(text):
            errors.append(
                f"{relative}: repeated substantial comment at lines "
                f"{', '.join(str(line) for line in line_numbers)}: {comment}"
            )

        classes = CLASS_RE.findall(text)
        if len(classes) > 1:
            errors.append(f"{relative}: declares multiple class_name values: {classes}")
        for class_name in classes:
            class_owners[class_name].append(relative)

        region_count = len(REGION_RE.findall(text))
        endregion_count = len(ENDREGION_RE.findall(text))
        if region_count != endregion_count:
            errors.append(
                f"{relative}: #region/#endregion mismatch "
                f"({region_count} vs {endregion_count})"
            )

        for _, resource_path in RESOURCE_RE.findall(text):
            resolved = ROOT / resource_path
            if not resolved.exists():
                errors.append(f"{relative}: missing resource path res://{resource_path}")

        redraw_call_count = len(QUEUE_REDRAW_RE.findall(text))
        allowed_redraw_calls = ALLOWED_QUEUE_REDRAW_CALLS.get(relative, 0)
        if redraw_call_count > allowed_redraw_calls:
            errors.append(
                f"{relative}: contains {redraw_call_count} queue_redraw references; "
                f"only {allowed_redraw_calls} are approved"
            )

        metrics = function_metrics(path, text)
        all_metrics.extend(metrics)
        for metric in metrics:
            if metric.line_count >= 300:
                warnings.append(
                    f"{metric.path}:{metric.start_line} {metric.name} is "
                    f"{metric.line_count} lines"
                )

    for class_name, owners in sorted(class_owners.items()):
        if len(owners) > 1:
            errors.append(f"class_name {class_name} is declared by: {', '.join(owners)}")

    # Validate scene/script resource paths as well as script-local preloads.
    for pattern in ("**/*.tscn", "**/*.tres", "project.godot"):
        paths = [ROOT / "project.godot"] if pattern == "project.godot" else ROOT.glob(pattern)
        for path in paths:
            if not path.is_file() or ".godot" in path.parts:
                continue
            relative = str(path.relative_to(ROOT))
            text = path.read_text(encoding="utf-8")
            for _, resource_path in RESOURCE_RE.findall(text):
                if not (ROOT / resource_path).exists():
                    errors.append(f"{relative}: missing resource path res://{resource_path}")

    map_cache_path = ROOT / "scripts/map/cache/MapTextureCache.gd"
    if map_cache_path.exists():
        map_cache_text = map_cache_path.read_text(encoding="utf-8")
        forbidden_staggered_terms = (
            "warmup_running",
            "process_warmup",
            "start_warmup",
            "finish_warmup",
            "_warmup_next_row",
            "_warmup_images",
        )
        for term in forbidden_staggered_terms:
            if term in map_cache_text:
                errors.append(
                    "scripts/map/cache/MapTextureCache.gd: retired staggered "
                    f"map loading term remains: {term}"
                )


    world_data_path = ROOT / "scripts/world/simulation/WorldData.gd"
    if world_data_path.exists():
        world_data_text = world_data_path.read_text(encoding="utf-8")
        for symbol in WORLD_DATA_FORBIDDEN_CITY_LOGISTICS_SYMBOLS:
            declaration_patterns = (
                rf"^\s*static\s+var\s+{re.escape(symbol)}\b",
                rf"^\s*const\s+{re.escape(symbol)}\b",
                rf"^\s*(?:static\s+)?func\s+{re.escape(symbol)}\s*\(",
            )
            if any(
                re.search(pattern, world_data_text, re.MULTILINE)
                for pattern in declaration_patterns
            ):
                errors.append(
                    "scripts/world/simulation/WorldData.gd: extracted city-logistics "
                    f"ownership declaration must not return to WorldData: {symbol}"
                )

        settlement_state_path = (
            ROOT / "scripts/city/simulation/CitySettlementSimulationState.gd"
        )
        if settlement_state_path.exists():
            settlement_state_text = settlement_state_path.read_text(encoding="utf-8")
            legacy_storage_declarations = (
                "var ground_piles:",
                "var ground_pile_index_by_id:",
                "var next_ground_pile_id:",
                "var ground_pile_version:",
                "var haul_reservations:",
                "var haul_reservation_id_by_citizen_id:",
                "var haul_source_reserved_amount_by_key:",
                "var haul_destination_reserved_amount_by_key:",
                "var next_haul_reservation_id:",
                "var haul_reservation_version:",
            )
            for declaration in legacy_storage_declarations:
                if declaration in settlement_state_text:
                    errors.append(
                        "scripts/city/simulation/CitySettlementSimulationState.gd: "
                        "logistics storage must live in CityLogisticsState, not "
                        f"the settlement root: {declaration}"
                    )

        for symbol in WORLD_DATA_FORBIDDEN_CITY_WORK_SYMBOLS:
            declaration_patterns = (
                rf"^\s*static\s+var\s+{re.escape(symbol)}\b",
                rf"^\s*const\s+{re.escape(symbol)}\b",
                rf"^\s*(?:static\s+)?func\s+{re.escape(symbol)}\s*\(",
                rf"^\s*(?:static\s+)?func\s+_{re.escape(symbol)}\s*\(",
            )
            if any(
                re.search(pattern, world_data_text, re.MULTILINE)
                for pattern in declaration_patterns
            ):
                errors.append(
                    "scripts/world/simulation/WorldData.gd: extracted city-work "
                    f"ownership declaration must not return to WorldData: {symbol}"
                )

    for path in scripts:
        if path == world_data_path:
            continue
        relative = str(path.relative_to(ROOT))
        text = path.read_text(encoding="utf-8")
        for symbol in WORLD_DATA_FORBIDDEN_CITY_WORK_SYMBOLS:
            legacy_reference = f"WorldData.{symbol}"
            if legacy_reference in text:
                errors.append(
                    f"{relative}: legacy WorldData city-work reference remains: "
                    f"{legacy_reference}"
                )

        for symbol in WORLD_DATA_FORBIDDEN_CITY_LOGISTICS_SYMBOLS:
            legacy_pattern = rf"WorldData\s*\.\s*{re.escape(symbol)}\b"
            if re.search(legacy_pattern, text):
                errors.append(
                    f"{relative}: legacy WorldData city-logistics reference remains: "
                    f"WorldData.{symbol}"
                )

    city_renderer_path = ROOT / "scripts/city/rendering/CityRenderer.gd"
    if city_renderer_path.exists():
        city_renderer_text = city_renderer_path.read_text(encoding="utf-8")
        if "change_scene_to_" in city_renderer_text:
            errors.append(
                "scripts/city/rendering/CityRenderer.gd: city/world switching must "
                "use the persistent GameSession, not scene replacement"
            )

    largest_files = []
    for path in scripts:
        count = len(path.read_text(encoding="utf-8").splitlines())
        largest_files.append((count, str(path.relative_to(ROOT))))
    largest_files.sort(reverse=True)

    construction_state_path = ROOT / "scripts/city/simulation/CityConstructionState.gd"
    city_root_state_path = ROOT / "scripts/city/simulation/CitySettlementSimulationState.gd"
    construction_system_path = ROOT / "scripts/city/simulation/systems/CityConstructionSystem.gd"
    if world_data_path.exists() and construction_state_path.exists() and city_root_state_path.exists() and construction_system_path.exists():
        world_data_text = world_data_path.read_text(encoding="utf-8")
        construction_state_text = construction_state_path.read_text(encoding="utf-8")
        city_root_state_text = city_root_state_path.read_text(encoding="utf-8")
        construction_system_text = construction_system_path.read_text(encoding="utf-8")

        for symbol in WORLD_DATA_FORBIDDEN_CITY_CONSTRUCTION_SYMBOLS:
            declaration_patterns = (
                rf"^\s*static\s+var\s+{re.escape(symbol)}\b",
                rf"^\s*const\s+{re.escape(symbol)}\b",
                rf"^\s*(?:static\s+)?func\s+{re.escape(symbol)}\s*\(",
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
                legacy_pattern = rf"WorldData\s*\.\s*{re.escape(symbol)}\b"
                if re.search(legacy_pattern, text):
                    errors.append(
                        f"{relative}: legacy WorldData city-construction reference remains: "
                        f"WorldData.{symbol}"
                    )

        for state_name in ("construction_sites", "construction_site_index_by_id", "construction_site_id_by_tile", "next_construction_site_id", "construction_version"):
            if not re.search(rf"^var\s+{re.escape(state_name)}\b", construction_state_text, re.MULTILINE):
                errors.append(
                    f"scripts/city/simulation/CityConstructionState.gd: missing {state_name}"
                )
            if re.search(rf"^var\s+{re.escape(state_name)}\b", city_root_state_text, re.MULTILINE):
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

    report = {
        "script_count": len(scripts),
        "total_script_lines": total_lines,
        "function_count": total_functions,
        "class_name_count": len(class_owners),
        "error_count": len(errors),
        "warning_count": len(warnings),
        "errors": errors,
        "warnings": warnings,
        "largest_files": [
            {"path": path, "line_count": count} for count, path in largest_files[:15]
        ],
        "largest_functions": [
            {
                "path": metric.path,
                "name": metric.name,
                "start_line": metric.start_line,
                "line_count": metric.line_count,
            }
            for metric in sorted(all_metrics, key=lambda item: item.line_count, reverse=True)[:25]
        ],
    }
    REPORT_PATH.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    print(
        f"Audited {len(scripts)} scripts, {total_lines:,} lines, "
        f"and {total_functions:,} functions."
    )
    if warnings:
        print(f"Maintainability warnings: {len(warnings)}")
        for warning in warnings[:20]:
            print(f"  WARNING: {warning}")
    if errors:
        print(f"Structural errors: {len(errors)}", file=sys.stderr)
        for error in errors:
            print(f"  ERROR: {error}", file=sys.stderr)
        return 1

    print("Static GDScript and resource audit passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
