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

WORLD_DATA_FORBIDDEN_CITY_OBJECT_SYMBOLS = (
    "city_objects",
    "city_object_index_by_id",
    "city_occupied_tiles",
    "next_city_object_id",
    "city_object_version",
    "_mark_city_objects_changed",
    "rebuild_city_object_index",
    "_register_city_object_index",
    "get_city_object_index_by_id",
    "get_city_object_by_id",
    "reset_city_object_state",
    "city_object_type_preserves_citizen_walkability",
    "get_city_object_topology_blocking_citizen_ids",
    "validate_city_object_topology_mutation",
    "can_place_city_object",
    "city_object_placement_has_walkable_access_tile",
    "make_rectangle_city_object_footprint_tiles",
    "get_city_object_footprint_tiles",
    "city_object_supports_citizen_interior",
    "get_city_object_citizen_interior_access_mode",
    "get_city_object_citizen_entry_policy",
    "get_city_object_citizen_entry_tiles",
    "_city_object_boundary_tile_allows_entry",
    "is_completed_city_road_tile",
    "add_city_object",
    "occupy_city_object_tiles",
    "get_city_object_at_tile",
    "has_city_object_type",
    "can_place_city_road_tile",
    "add_city_road_object",
)

WORLD_DATA_RETIRED_RESOURCE_LEDGER_SYMBOLS = (
    "city_resource_amounts",
    "ensure_city_resource_amounts",
    "get_city_resource_amount",
)

WORLD_DATA_FORBIDDEN_CITY_RESOURCE_ACCOUNTING_SYMBOLS = (
    "city_owned_resource_amount_cache",
    "city_owned_resource_amount_cache_container_version",
    "city_container_version",
    "city_public_storage_version",
    "get_city_container_version",
    "get_city_public_storage_version",
    "mark_city_container_changed",
    "_mark_city_container_changed",
    "reset_city_resource_accounting_state",
    "get_total_public_city_resource_amount",
    "get_total_public_city_resource_storage_capacity",
    "get_total_stored_city_resource_amount",
    "get_total_owned_city_resource_amount",
    "get_total_owned_city_resource_amounts",
    "get_total_city_resource_storage_capacity",
)

WORLD_DATA_FORBIDDEN_CITY_RESOURCE_CONTAINER_SYMBOLS = (
    "make_empty_resource_container",
    "make_sparse_resource_container",
    "get_resource_container_resource_amount",
    "get_resource_container_total_amount",
    "get_resource_container_present_resources",
    "get_food_nutrition_in_resource_container",
    "make_empty_city_object_storage_for_type",
    "get_city_object_container_type",
    "get_city_object_container_access_policy",
    "_get_container_policy_purposes",
    "city_object_container_is_publicly_usable",
    "city_object_counts_as_public_city_storage",
    "get_city_object_public_storage_tier",
    "get_public_city_storage_tiers",
    "city_object_counts_toward_city_storage_totals",
    "get_city_object_storage_resources",
    "get_city_object_present_storage_resources",
    "can_city_object_store_resource",
    "city_object_can_provide_haul_resource",
    "city_object_can_accept_haul_resource",
    "city_object_allows_direct_resource_withdrawal",
    "get_city_object_storage_capacity",
    "get_city_object_storage_used_capacity",
    "get_city_object_storage_free_space",
    "get_city_object_unreserved_storage_free_space",
    "get_city_object_storage_capacity_for_resource",
    "get_city_object_stored_resource_amount",
    "get_city_object_resource_free_space",
    "set_city_object_stored_resource_amount",
    "add_resource_to_city_object_storage",
    "add_resource_bundle_to_city_object_storage",
    "remove_resource_from_city_object_storage",
)

REQUIRED_CITY_RESOURCE_ACCOUNTING_SYSTEM_FUNCTIONS = (
    "get_current_state",
    "get_city_container_version",
    "get_city_public_storage_version",
    "mark_city_container_changed",
    "reset_city_resource_accounting_state",
    "get_total_public_city_resource_amount",
    "get_total_public_city_resource_storage_capacity",
    "get_total_stored_city_resource_amount",
    "get_total_owned_city_resource_amount",
    "get_total_owned_city_resource_amounts",
    "get_total_city_resource_storage_capacity",
)

REQUIRED_CITY_RESOURCE_CONTAINER_SYSTEM_FUNCTIONS = (
    "make_empty_resource_container",
    "make_sparse_resource_container",
    "get_resource_container_resource_amount",
    "get_resource_container_total_amount",
    "get_resource_container_present_resources",
    "get_food_nutrition_in_resource_container",
    "make_empty_city_object_storage_for_type",
    "get_city_object_container_type",
    "get_city_object_container_access_policy",
    "city_object_container_is_publicly_usable",
    "city_object_counts_as_public_city_storage",
    "get_city_object_public_storage_tier",
    "get_public_city_storage_tiers",
    "city_object_counts_toward_city_storage_totals",
    "get_city_object_storage_resources",
    "get_city_object_present_storage_resources",
    "can_city_object_store_resource",
    "city_object_can_provide_haul_resource",
    "city_object_can_accept_haul_resource",
    "city_object_allows_direct_resource_withdrawal",
    "get_city_object_storage_capacity",
    "get_city_object_storage_used_capacity",
    "get_city_object_storage_free_space",
    "get_city_object_unreserved_storage_free_space",
    "get_city_object_storage_capacity_for_resource",
    "get_city_object_stored_resource_amount",
    "get_city_object_resource_free_space",
    "set_city_object_stored_resource_amount",
    "add_resource_to_city_object_storage",
    "add_resource_bundle_to_city_object_storage",
    "remove_resource_from_city_object_storage",
)

RESOURCE_ACCOUNTING_STATE_FIELDS = {
    "owned_resource_amount_cache": "Dictionary",
    "owned_resource_amount_cache_container_version": "int",
    "container_version": "int",
    "public_storage_version": "int",
}

CITIZEN_REGISTRY_STATE_FIELDS = {
    "citizens": ("Array", "[]"),
    "citizen_index_by_id": ("Dictionary", "{}"),
    "next_citizen_id": ("int", "1"),
    "citizen_version": ("int", "0"),
}

WORLD_DATA_CITIZEN_REGISTRY_PROPERTIES = {
    "city_citizens": ("Array", "citizens"),
    "city_citizen_index_by_id": ("Dictionary", "citizen_index_by_id"),
    "next_city_citizen_id": ("int", "next_citizen_id"),
    "city_citizen_version": ("int", "citizen_version"),
}

CITIZEN_SPATIAL_STATE_FIELDS = {
    "citizen_ids_by_tile": ("Dictionary", "{}"),
    "citizen_spatial_version": ("int", "0"),
}

WORLD_DATA_CITIZEN_SPATIAL_PROPERTIES = {
    "city_citizen_ids_by_tile": ("Dictionary", "citizen_ids_by_tile"),
    "city_citizen_spatial_version": ("int", "citizen_spatial_version"),
}

CITIZEN_MOVEMENT_RUNTIME_STATE_FIELDS = {
    "active_mover_ids": ("Array\\[int\\]", "[]"),
    "active_mover_id_lookup": ("Dictionary", "{}"),
    "citizen_movement_visual_events": ("Array", "[]"),
    "citizen_movement_visual_tick_index": ("int", "-1"),
    "citizen_movement_version": ("int", "0"),
}

WORLD_DATA_CITIZEN_MOVEMENT_RUNTIME_PROPERTIES = {
    "city_active_mover_ids": ("Array\\[int\\]", "active_mover_ids"),
    "city_active_mover_id_lookup": ("Dictionary", "active_mover_id_lookup"),
    "city_citizen_movement_visual_events": (
        "Array",
        "citizen_movement_visual_events",
    ),
    "city_citizen_movement_visual_tick_index": (
        "int",
        "citizen_movement_visual_tick_index",
    ),
    "city_citizen_movement_version": ("int", "citizen_movement_version"),
}

CITIZEN_TASK_RUNTIME_STATE_FIELDS = {
    "active_task_ids": ("Array\\[int\\]", "[]"),
    "active_task_id_lookup": ("Dictionary", "{}"),
    "citizen_task_version": ("int", "0"),
}

WORLD_DATA_CITIZEN_TASK_RUNTIME_PROPERTIES = {
    "city_active_task_ids": ("Array\\[int\\]", "active_task_ids"),
    "city_active_task_id_lookup": ("Dictionary", "active_task_id_lookup"),
    "city_citizen_task_version": ("int", "citizen_task_version"),
}

DEFERRED_CITIZEN_ROOT_FIELDS = {
    "object_access_tile_cache": "city_object_access_tile_cache",
    "assignment_version": "city_assignment_version",
    "workplace_version": "city_workplace_version",
}

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

    object_state_path = ROOT / "scripts/city/simulation/CityObjectState.gd"
    object_system_path = (
        ROOT / "scripts/city/simulation/systems/CityObjectSystem.gd"
    )
    political_state_path = ROOT / "scripts/world/simulation/WorldPoliticalState.gd"
    if not object_state_path.exists():
        errors.append(
            "scripts/city/simulation/CityObjectState.gd: missing completed-object "
            "state owner"
        )
    if not object_system_path.exists():
        errors.append(
            "scripts/city/simulation/systems/CityObjectSystem.gd: missing "
            "completed-object behavior owner"
        )
    if (
        world_data_path.exists()
        and object_state_path.exists()
        and object_system_path.exists()
        and city_root_state_path.exists()
        and political_state_path.exists()
    ):
        world_data_text = world_data_path.read_text(encoding="utf-8")
        object_state_text = object_state_path.read_text(encoding="utf-8")
        object_system_text = object_system_path.read_text(encoding="utf-8")
        city_root_state_text = city_root_state_path.read_text(encoding="utf-8")
        political_state_text = political_state_path.read_text(encoding="utf-8")
        object_state_fields = {
            "objects": "Array",
            "object_index_by_id": "Dictionary",
            "occupied_tiles": "Dictionary",
            "next_object_id": "int",
            "object_version": "int",
        }
        declared_object_state_fields = set(
            re.findall(
                r"^var\s+([A-Za-z_][A-Za-z0-9_]*)\b",
                object_state_text,
                re.MULTILINE,
            )
        )
        if declared_object_state_fields != set(object_state_fields):
            errors.append(
                "scripts/city/simulation/CityObjectState.gd: must own exactly "
                "objects, object_index_by_id, occupied_tiles, next_object_id, "
                "and object_version"
            )
        if FUNC_RE.search(object_state_text):
            errors.append(
                "scripts/city/simulation/CityObjectState.gd: must remain data-only; "
                "completed-object behavior belongs in CityObjectSystem"
            )

        for state_name, state_type in object_state_fields.items():
            declaration_pattern = (
                rf"^var\s+{re.escape(state_name)}:\s*{state_type}\s*="
            )
            if not re.search(
                declaration_pattern,
                object_state_text,
                re.MULTILINE,
            ):
                errors.append(
                    "scripts/city/simulation/CityObjectState.gd: missing typed "
                    f"object-state field {state_name}"
                )
            if re.search(
                rf"^var\s+{re.escape(state_name)}\b",
                city_root_state_text,
                re.MULTILINE,
            ):
                errors.append(
                    "scripts/city/simulation/CitySettlementSimulationState.gd: "
                    f"object storage {state_name} must live in CityObjectState"
                )

        if "var object_state: CityObjectState" not in city_root_state_text:
            errors.append(
                "scripts/city/simulation/CitySettlementSimulationState.gd: "
                "missing object_state owner"
            )
        if "var _unbound_city_object_state" not in political_state_text:
            errors.append(
                "scripts/world/simulation/WorldPoliticalState.gd: missing "
                "pre-context CityObjectState owner"
            )
        if (
            "func get_current_city_object_state() -> CityObjectState:"
            not in political_state_text
        ):
            errors.append(
                "scripts/world/simulation/WorldPoliticalState.gd: missing typed "
                "current CityObjectState resolver"
            )

        required_object_system_surfaces = (
            "static func get_current_state() -> CityObjectState:",
            "static func get_city_object_snapshot() -> Array:",
            "static func get_city_object_index_by_id(object_id: int) -> int:",
            "static func get_city_object_by_id(object_id: int) -> Dictionary:",
            "static func get_city_object_at_tile(tile_position: Vector2i) -> Dictionary:",
            "static func register_completed_city_object(values: Dictionary) -> Dictionary:",
            "static func reset_city_object_state() -> void:",
        )
        for required_surface in required_object_system_surfaces:
            if required_surface not in object_system_text:
                errors.append(
                    "scripts/city/simulation/systems/CityObjectSystem.gd: "
                    f"missing required API: {required_surface}"
                )

        for symbol in WORLD_DATA_FORBIDDEN_CITY_OBJECT_SYMBOLS:
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
                    "scripts/world/simulation/WorldData.gd: extracted city-object "
                    f"behavior/state must not return to WorldData: {symbol}"
                )

        for path in scripts:
            text = path.read_text(encoding="utf-8")
            relative = str(path.relative_to(ROOT))
            for symbol in WORLD_DATA_FORBIDDEN_CITY_OBJECT_SYMBOLS:
                legacy_reference_pattern = (
                    rf"\bWorldData\s*\.\s*{re.escape(symbol)}\b"
                )
                dynamic_reference_pattern = (
                    rf"\bWorldData\s*\.\s*(?:get|set|call)\s*\(\s*"
                    rf"[\"']{re.escape(symbol)}[\"']"
                )
                if re.search(legacy_reference_pattern, text):
                    errors.append(
                        f"{relative}: legacy WorldData city-object reference "
                        f"remains: WorldData.{symbol}"
                    )
                if re.search(dynamic_reference_pattern, text):
                    errors.append(
                        f"{relative}: dynamic legacy WorldData city-object "
                        f"reference remains: {symbol}"
                    )

            if (
                path not in {object_system_path, political_state_path}
                and "WorldPoliticalState.get_current_city_object_state(" in text
            ):
                errors.append(
                    f"{relative}: completed-object state must resolve through "
                    "CityObjectSystem, not WorldPoliticalState directly"
                )

        construction_system_text = construction_system_path.read_text(
            encoding="utf-8"
        )
        completion_call_count = construction_system_text.count(
            "CityObjectSystem.register_completed_city_object("
        )
        if completion_call_count != 1:
            errors.append(
                "scripts/city/simulation/systems/CityConstructionSystem.gd: "
                "construction finalization must call the completed-object API "
                f"exactly once in source; found {completion_call_count} calls"
            )

    resource_accounting_state_path = (
        ROOT / "scripts/city/simulation/CityResourceAccountingState.gd"
    )
    resource_accounting_system_path = (
        ROOT
        / "scripts/city/simulation/systems/CityResourceAccountingSystem.gd"
    )
    resource_container_system_path = (
        ROOT
        / "scripts/city/simulation/systems/CityResourceContainerSystem.gd"
    )
    settlement_context_path = (
        ROOT / "scripts/world/simulation/SettlementSimulationContext.gd"
    )
    required_resource_owner_paths = (
        (
            resource_accounting_state_path,
            "resource/container accounting state owner",
        ),
        (
            resource_accounting_system_path,
            "settlement resource-accounting behavior owner",
        ),
        (
            resource_container_system_path,
            "generic resource-container behavior owner",
        ),
    )
    for required_path, owner_description in required_resource_owner_paths:
        if not required_path.exists():
            errors.append(
                f"{required_path.relative_to(ROOT)}: missing {owner_description}"
            )

    if (
        world_data_path.exists()
        and resource_accounting_state_path.exists()
        and resource_accounting_system_path.exists()
        and resource_container_system_path.exists()
        and city_root_state_path.exists()
        and political_state_path.exists()
        and settlement_context_path.exists()
    ):
        world_data_text = world_data_path.read_text(encoding="utf-8")
        resource_accounting_state_text = resource_accounting_state_path.read_text(
            encoding="utf-8"
        )
        resource_accounting_system_text = (
            resource_accounting_system_path.read_text(encoding="utf-8")
        )
        resource_container_system_text = (
            resource_container_system_path.read_text(encoding="utf-8")
        )
        city_root_state_text = city_root_state_path.read_text(encoding="utf-8")
        political_state_text = political_state_path.read_text(encoding="utf-8")
        settlement_context_text = settlement_context_path.read_text(encoding="utf-8")

        declared_accounting_fields = set(
            re.findall(
                r"^var\s+([A-Za-z_][A-Za-z0-9_]*)\b",
                resource_accounting_state_text,
                re.MULTILINE,
            )
        )
        if declared_accounting_fields != set(RESOURCE_ACCOUNTING_STATE_FIELDS):
            errors.append(
                "scripts/city/simulation/CityResourceAccountingState.gd: must "
                "own exactly owned_resource_amount_cache, "
                "owned_resource_amount_cache_container_version, "
                "container_version, and public_storage_version"
            )
        if FUNC_RE.search(resource_accounting_state_text):
            errors.append(
                "scripts/city/simulation/CityResourceAccountingState.gd: must "
                "remain data-only; behavior belongs in the resource systems"
            )

        for state_name, state_type in RESOURCE_ACCOUNTING_STATE_FIELDS.items():
            if not re.search(
                rf"^var\s+{re.escape(state_name)}:\s*{state_type}\s*=",
                resource_accounting_state_text,
                re.MULTILINE,
            ):
                errors.append(
                    "scripts/city/simulation/CityResourceAccountingState.gd: "
                    f"missing typed accounting field {state_name}"
                )

        if (
            "var resource_accounting_state: CityResourceAccountingState"
            not in city_root_state_text
        ):
            errors.append(
                "scripts/city/simulation/CitySettlementSimulationState.gd: "
                "missing resource_accounting_state owner"
            )
        if re.search(
            r"^var\s+resource_amounts\b",
            city_root_state_text,
            re.MULTILINE,
        ):
            errors.append(
                "scripts/city/simulation/CitySettlementSimulationState.gd: "
                "retired duplicate resource_amounts ledger must not return"
            )

        if "class_name CityResourceAccountingSystem" not in (
            resource_accounting_system_text
        ):
            errors.append(
                "scripts/city/simulation/systems/CityResourceAccountingSystem.gd: "
                "missing CityResourceAccountingSystem class_name"
            )
        if "class_name CityResourceContainerSystem" not in (
            resource_container_system_text
        ):
            errors.append(
                "scripts/city/simulation/systems/CityResourceContainerSystem.gd: "
                "missing CityResourceContainerSystem class_name"
            )

        for function_name in REQUIRED_CITY_RESOURCE_ACCOUNTING_SYSTEM_FUNCTIONS:
            if not re.search(
                rf"^static\s+func\s+{re.escape(function_name)}\s*\(",
                resource_accounting_system_text,
                re.MULTILINE,
            ):
                errors.append(
                    "scripts/city/simulation/systems/"
                    "CityResourceAccountingSystem.gd: missing required static API "
                    f"{function_name}()"
                )

        for function_name in REQUIRED_CITY_RESOURCE_CONTAINER_SYSTEM_FUNCTIONS:
            if not re.search(
                rf"^static\s+func\s+{re.escape(function_name)}\s*\(",
                resource_container_system_text,
                re.MULTILINE,
            ):
                errors.append(
                    "scripts/city/simulation/systems/"
                    "CityResourceContainerSystem.gd: missing required static API "
                    f"{function_name}()"
                )

        typed_accounting_state_accessor = re.search(
            r"^static\s+func\s+get_current_state\s*\(\s*\)\s*->\s*"
            r"CityResourceAccountingState\s*:",
            resource_accounting_system_text,
            re.MULTILINE,
        )
        resolver_call_count = resource_accounting_system_text.count(
            "WorldPoliticalState.get_current_city_resource_accounting_state()"
        )
        if typed_accounting_state_accessor is None or resolver_call_count != 1:
            errors.append(
                "scripts/city/simulation/systems/CityResourceAccountingSystem.gd: "
                "get_current_state() must be typed and be the system's single direct "
                "WorldPoliticalState accounting-state resolver"
            )

        required_political_accounting_surfaces = (
            "var _unbound_city_resource_accounting_state",
            "func get_current_city_resource_accounting_state() -> "
            "CityResourceAccountingState:",
            "capital_state.resource_accounting_state =",
            "city_state.resource_accounting_state =",
        )
        for required_surface in required_political_accounting_surfaces:
            if required_surface not in political_state_text:
                errors.append(
                    "scripts/world/simulation/WorldPoliticalState.gd: missing "
                    f"resource-accounting ownership surface: {required_surface}"
                )
        if "func get_city_resource_accounting_state():" not in settlement_context_text:
            errors.append(
                "scripts/world/simulation/SettlementSimulationContext.gd: missing "
                "resource-accounting context accessor"
            )

        forbidden_resource_symbols = (
            WORLD_DATA_FORBIDDEN_CITY_RESOURCE_ACCOUNTING_SYMBOLS
            + WORLD_DATA_FORBIDDEN_CITY_RESOURCE_CONTAINER_SYMBOLS
        )
        for symbol in forbidden_resource_symbols:
            declaration_patterns = (
                rf"^\s*(?:static\s+)?var\s+{re.escape(symbol)}\b",
                rf"^\s*const\s+{re.escape(symbol)}\b",
                rf"^\s*(?:static\s+)?func\s+{re.escape(symbol)}\s*\(",
            )
            if any(
                re.search(pattern, world_data_text, re.MULTILINE)
                for pattern in declaration_patterns
            ):
                errors.append(
                    "scripts/world/simulation/WorldData.gd: extracted city-resource "
                    f"behavior/state must not return to WorldData: {symbol}"
                )

        direct_state_resolver_pattern = re.compile(
            r"\bWorldPoliticalState\s*\.\s*"
            r"get_current_city_resource_accounting_state\s*\("
        )
        dynamic_state_resolver_pattern = re.compile(
            r"\bWorldPoliticalState\s*\.\s*(?:get|call|callv)\s*\(\s*"
            r"[\"']get_current_city_resource_accounting_state[\"']"
        )
        callable_state_resolver_pattern = re.compile(
            r"\bCallable\s*\(\s*WorldPoliticalState\s*,\s*"
            r"[\"']get_current_city_resource_accounting_state[\"']\s*\)"
        )
        allowed_accounting_state_resolvers = {
            political_state_path,
            resource_accounting_system_path,
        }
        city_object_system_path = (
            ROOT
            / "scripts"
            / "city"
            / "simulation"
            / "systems"
            / "CityObjectSystem.gd"
        )
        stored_resources_write_pattern = re.compile(
            r"(?:"
            r"\[\s*[\"']stored_resources[\"']\s*\]"
            r"|\.\s*stored_resources\b"
            r"|\.\s*get\s*\(\s*[\"']stored_resources[\"'][^\)]*\)"
            r")(?:\s*\[[^\]]+\])?\s*[+\-*/%]?=(?!=)"
            r"|(?:"
            r"\[\s*[\"']stored_resources[\"']\s*\]"
            r"|\.\s*stored_resources\b"
            r"|\.\s*get\s*\(\s*[\"']stored_resources[\"'][^\)]*\)"
            r")\s*\.\s*(?:clear|erase|merge|set)\s*\("
            r"|\.\s*set\s*\(\s*[\"']stored_resources[\"']\s*,"
        )
        accounting_state_write_patterns = []
        for state_name in RESOURCE_ACCOUNTING_STATE_FIELDS:
            escaped_state_name = re.escape(state_name)
            accounting_state_write_patterns.extend(
                [
                    re.compile(
                        rf"\.\s*{escaped_state_name}\b\s*"
                        rf"[+\-*/%]?=(?!=)"
                    ),
                    re.compile(
                        rf"\.\s*{escaped_state_name}\b\s*\[[^\]]+\]\s*"
                        rf"[+\-*/%]?=(?!=)"
                    ),
                    re.compile(
                        rf"\.\s*{escaped_state_name}\b\s*\.\s*"
                        rf"(?:assign|clear|erase|merge|set)\s*\("
                    ),
                    re.compile(
                        rf"\.\s*set\s*\(\s*[\"']{escaped_state_name}"
                        rf"[\"']\s*,"
                    ),
                ]
            )

        for path in scripts:
            text = path.read_text(encoding="utf-8")
            relative = str(path.relative_to(ROOT))

            if path != resource_accounting_state_path:
                for state_name in RESOURCE_ACCOUNTING_STATE_FIELDS:
                    if re.search(
                        rf"^(?:static\s+)?var\s+{re.escape(state_name)}\b",
                        text,
                        re.MULTILINE,
                    ):
                        errors.append(
                            f"{relative}: accounting storage {state_name} must "
                            "live only in CityResourceAccountingState"
                        )

            if (
                not path.name.endswith("Test.gd")
                and path != resource_accounting_system_path
                and any(
                    pattern.search(text)
                    for pattern in accounting_state_write_patterns
                )
            ):
                errors.append(
                    f"{relative}: CityResourceAccountingState writes must use "
                    "CityResourceAccountingSystem"
                )

            stored_resource_write_count = len(
                stored_resources_write_pattern.findall(text)
            )
            if (
                path == city_object_system_path
                and (
                    stored_resource_write_count != 1
                    or "CityResourceContainerSystem.make_empty_city_object_storage_for_type"
                    not in text
                )
            ):
                errors.append(
                    f"{relative}: CityObjectSystem may initialize stored_resources "
                    "exactly once through CityResourceContainerSystem"
                )
            elif (
                path != city_object_system_path
                and path != resource_container_system_path
                and stored_resource_write_count > 0
            ):
                errors.append(
                    f"{relative}: completed-object stored_resources writes must "
                    "use CityResourceContainerSystem"
                )

            for symbol in forbidden_resource_symbols:
                direct_reference_pattern = (
                    rf"\bWorldData\s*\.\s*{re.escape(symbol)}\b"
                )
                dynamic_reference_pattern = (
                    rf"\bWorldData\s*\.\s*(?:get|set|call|callv)\s*\(\s*"
                    rf"[\"']{re.escape(symbol)}[\"']"
                )
                callable_reference_pattern = (
                    rf"\bCallable\s*\(\s*WorldData\s*,\s*"
                    rf"[\"']{re.escape(symbol)}[\"']\s*\)"
                )
                if re.search(direct_reference_pattern, text):
                    errors.append(
                        f"{relative}: legacy WorldData city-resource reference "
                        f"remains: WorldData.{symbol}"
                    )
                if (
                    re.search(dynamic_reference_pattern, text)
                    or re.search(callable_reference_pattern, text)
                ):
                    errors.append(
                        f"{relative}: dynamic legacy WorldData city-resource "
                        f"reference remains: {symbol}"
                    )

            if path not in allowed_accounting_state_resolvers and (
                direct_state_resolver_pattern.search(text)
                or dynamic_state_resolver_pattern.search(text)
                or callable_state_resolver_pattern.search(text)
            ):
                errors.append(
                    f"{relative}: accounting state must resolve through "
                    "CityResourceAccountingSystem, not WorldPoliticalState directly"
                )

        for retired_symbol in WORLD_DATA_RETIRED_RESOURCE_LEDGER_SYMBOLS:
            declaration_patterns = (
                rf"^\s*static\s+var\s+{re.escape(retired_symbol)}\b",
                rf"^\s*(?:static\s+)?func\s+{re.escape(retired_symbol)}\s*\(",
            )
            if any(
                re.search(pattern, world_data_text, re.MULTILINE)
                for pattern in declaration_patterns
            ):
                errors.append(
                    "scripts/world/simulation/WorldData.gd: retired duplicate "
                    f"resource ledger must not return: {retired_symbol}"
                )

            for path in scripts:
                text = path.read_text(encoding="utf-8")
                relative = str(path.relative_to(ROOT))
                direct_reference_pattern = (
                    rf"\bWorldData\s*\.\s*{re.escape(retired_symbol)}\b"
                )
                dynamic_reference_pattern = (
                    rf"\bWorldData\s*\.\s*(?:get|set|call|callv)\s*\(\s*"
                    rf"[\"']{re.escape(retired_symbol)}[\"']"
                )
                callable_reference_pattern = (
                    rf"\bCallable\s*\(\s*WorldData\s*,\s*"
                    rf"[\"']{re.escape(retired_symbol)}[\"']\s*\)"
                )
                if re.search(direct_reference_pattern, text):
                    errors.append(
                        f"{relative}: retired WorldData resource-ledger reference "
                        f"remains: WorldData.{retired_symbol}"
                    )
                if (
                    re.search(dynamic_reference_pattern, text)
                    or re.search(callable_reference_pattern, text)
                ):
                    errors.append(
                        f"{relative}: dynamic retired WorldData resource-ledger "
                        f"reference remains: {retired_symbol}"
                    )

    citizen_registry_state_path = (
        ROOT / "scripts/city/simulation/CityCitizenRegistryState.gd"
    )
    citizen_registry_required_paths = (
        (citizen_registry_state_path, "citizen registry state owner"),
        (city_root_state_path, "City settlement root state"),
        (political_state_path, "settlement ownership registry"),
        (settlement_context_path, "settlement simulation context"),
        (world_data_path, "WorldData compatibility API"),
    )
    for required_path, owner_description in citizen_registry_required_paths:
        if not required_path.exists():
            errors.append(
                f"{required_path.relative_to(ROOT)}: missing {owner_description}"
            )

    if all(path.exists() for path, _ in citizen_registry_required_paths):
        citizen_registry_state_text = citizen_registry_state_path.read_text(
            encoding="utf-8"
        )
        city_root_state_text = city_root_state_path.read_text(encoding="utf-8")
        political_state_text = political_state_path.read_text(encoding="utf-8")
        settlement_context_text = settlement_context_path.read_text(
            encoding="utf-8"
        )
        world_data_text = world_data_path.read_text(encoding="utf-8")

        if "extends RefCounted" not in citizen_registry_state_text:
            errors.append(
                "scripts/city/simulation/CityCitizenRegistryState.gd: must "
                "extend RefCounted"
            )
        if "class_name CityCitizenRegistryState" not in citizen_registry_state_text:
            errors.append(
                "scripts/city/simulation/CityCitizenRegistryState.gd: missing "
                "CityCitizenRegistryState class_name"
            )

        declared_registry_fields = set(
            re.findall(
                r"^var\s+([A-Za-z_][A-Za-z0-9_]*)\b",
                citizen_registry_state_text,
                re.MULTILINE,
            )
        )
        if declared_registry_fields != set(CITIZEN_REGISTRY_STATE_FIELDS):
            errors.append(
                "scripts/city/simulation/CityCitizenRegistryState.gd: must own "
                "exactly citizens, citizen_index_by_id, next_citizen_id, and "
                "citizen_version"
            )
        if FUNC_RE.search(citizen_registry_state_text):
            errors.append(
                "scripts/city/simulation/CityCitizenRegistryState.gd: must "
                "remain data-only during the ownership pass"
            )

        for state_name, (state_type, default_value) in (
            CITIZEN_REGISTRY_STATE_FIELDS.items()
        ):
            declaration_pattern = (
                rf"^var\s+{re.escape(state_name)}:\s*{state_type}\s*=\s*"
                rf"{re.escape(default_value)}\s*$"
            )
            if not re.search(
                declaration_pattern,
                citizen_registry_state_text,
                re.MULTILINE,
            ):
                errors.append(
                    "scripts/city/simulation/CityCitizenRegistryState.gd: "
                    f"missing typed default for {state_name}"
                )

            for path in scripts:
                if path == citizen_registry_state_path:
                    continue
                text = path.read_text(encoding="utf-8")
                if re.search(
                    rf"^(?:static\s+)?var\s+{re.escape(state_name)}\b",
                    text,
                    re.MULTILINE,
                ):
                    errors.append(
                        f"{path.relative_to(ROOT)}: duplicate top-level citizen "
                        f"registry storage must not return: {state_name}"
                    )

        if (
            "var citizen_registry_state: CityCitizenRegistryState"
            not in city_root_state_text
        ):
            errors.append(
                "scripts/city/simulation/CitySettlementSimulationState.gd: "
                "missing citizen_registry_state owner"
            )

        for world_data_symbol in WORLD_DATA_CITIZEN_REGISTRY_PROPERTIES:
            if f"WorldData.{world_data_symbol}" in city_root_state_text:
                errors.append(
                    "scripts/city/simulation/CitySettlementSimulationState.gd: "
                    "extracted citizen registry must not be captured/applied "
                    f"through WorldData.{world_data_symbol}"
                )

            dynamic_root_reference = re.search(
                rf"\bWorldData\s*\.\s*(?:get|set|call|callv)\s*\(\s*"
                rf"[\"']{re.escape(world_data_symbol)}[\"']",
                city_root_state_text,
            )
            callable_root_reference = re.search(
                rf"\bCallable\s*\(\s*WorldData\s*,\s*"
                rf"[\"']{re.escape(world_data_symbol)}[\"']\s*\)",
                city_root_state_text,
            )
            if dynamic_root_reference or callable_root_reference:
                errors.append(
                    "scripts/city/simulation/CitySettlementSimulationState.gd: "
                    "dynamic citizen-registry workspace copying is forbidden: "
                    f"{world_data_symbol}"
                )

        for state_field, world_data_symbol in DEFERRED_CITIZEN_ROOT_FIELDS.items():
            if not re.search(
                rf"^var\s+{re.escape(state_field)}\b",
                city_root_state_text,
                re.MULTILINE,
            ):
                errors.append(
                    "scripts/city/simulation/CitySettlementSimulationState.gd: "
                    f"deferred citizen field left its root early: {state_field}"
                )
            capture_pattern = (
                rf"\b{re.escape(state_field)}\s*=\s*(?:\(\s*)?"
                rf"WorldData\s*\.\s*{re.escape(world_data_symbol)}\b"
            )
            apply_pattern = (
                rf"\bWorldData\s*\.\s*{re.escape(world_data_symbol)}\s*=\s*"
                rf"(?:\(\s*)?{re.escape(state_field)}\b"
            )
            if not re.search(
                capture_pattern,
                city_root_state_text,
                re.MULTILINE | re.DOTALL,
            ):
                errors.append(
                    "scripts/city/simulation/CitySettlementSimulationState.gd: "
                    f"missing deferred capture route for {state_field}"
                )
            if not re.search(
                apply_pattern,
                city_root_state_text,
                re.MULTILINE | re.DOTALL,
            ):
                errors.append(
                    "scripts/city/simulation/CitySettlementSimulationState.gd: "
                    f"missing deferred apply route for {state_field}"
                )

            if not re.search(
                rf"^static\s+var\s+{re.escape(world_data_symbol)}\b",
                world_data_text,
                re.MULTILINE,
            ):
                errors.append(
                    "scripts/world/simulation/WorldData.gd: deferred citizen "
                    f"workspace field moved during Pass 4: {world_data_symbol}"
                )

        required_political_registry_surfaces = (
            (
                "state preload",
                r"^const\s+CityCitizenRegistryStateScript\s*=\s*preload\(",
            ),
            (
                "unbound owner",
                r"^var\s+_unbound_city_citizen_registry_state\b",
            ),
            (
                "typed current-state resolver",
                r"^func\s+get_current_city_citizen_registry_state\s*\(\s*\)"
                r"\s*->\s*CityCitizenRegistryState\s*:",
            ),
            (
                "founding adoption",
                r"^\s*capital_state\.citizen_registry_state\s*=",
            ),
            (
                "legacy adoption",
                r"^\s*city_state\.citizen_registry_state\s*=",
            ),
        )
        for surface_description, required_pattern in (
            required_political_registry_surfaces
        ):
            if not re.search(
                required_pattern,
                political_state_text,
                re.MULTILINE,
            ):
                errors.append(
                    "scripts/world/simulation/WorldPoliticalState.gd: missing "
                    "citizen-registry ownership surface: "
                    f"{surface_description}"
                )
        if political_state_text.count("CityCitizenRegistryStateScript.new()") < 3:
            errors.append(
                "scripts/world/simulation/WorldPoliticalState.gd: citizen "
                "registry fallback must be created initially, on reset, and "
                "after legacy adoption"
            )
        if not re.search(
            r"^func\s+get_city_citizen_registry_state\s*\(\s*\)\s*:",
            settlement_context_text,
            re.MULTILINE,
        ):
            errors.append(
                "scripts/world/simulation/SettlementSimulationContext.gd: "
                "missing citizen-registry context accessor"
            )

        for property_name, (property_type, state_field) in (
            WORLD_DATA_CITIZEN_REGISTRY_PROPERTIES.items()
        ):
            declaration_matches = re.findall(
                rf"^static\s+var\s+{re.escape(property_name)}\b",
                world_data_text,
                re.MULTILINE,
            )
            property_match = re.search(
                rf"^static\s+var\s+{re.escape(property_name)}:\s*"
                rf"{property_type}:\s*\n"
                rf"(?P<body>.*?)"
                rf"(?=^static\s+var\s+|^const\s+|^#region\b|\Z)",
                world_data_text,
                re.MULTILINE | re.DOTALL,
            )
            if len(declaration_matches) != 1 or property_match is None:
                errors.append(
                    "scripts/world/simulation/WorldData.gd: citizen registry "
                    f"compatibility property must be accessor-only: {property_name}"
                )
                continue

            property_body = property_match.group("body")
            resolver_count = property_body.count(
                "WorldPoliticalState.get_current_city_citizen_registry_state()"
            )
            if (
                resolver_count != 2
                or not re.search(
                    rf"return\s+state\s*\.\s*{re.escape(state_field)}\b",
                    property_body,
                )
                or not re.search(
                    rf"state\s*\.\s*{re.escape(state_field)}\s*=\s*value\b",
                    property_body,
                )
            ):
                errors.append(
                    "scripts/world/simulation/WorldData.gd: citizen registry "
                    f"property must route getter/setter through one owner: {property_name}"
                )

        renderer_path = ROOT / "scripts/city/rendering/CityRenderer.gd"
        validator_path = ROOT / "scripts/city/simulation/CityStateValidator.gd"
        if renderer_path.exists():
            renderer_text = renderer_path.read_text(encoding="utf-8")
            if (
                "var observed_city_citizen_registry_state: "
                "CityCitizenRegistryState" not in renderer_text
                or "citizen_registry_state_changed" not in renderer_text
                or 'change_flags["city_citizen_registry_changed"]' not in renderer_text
                or "city_citizen_movement_presentation.initialize()"
                not in renderer_text
            ):
                errors.append(
                    "scripts/city/rendering/CityRenderer.gd: citizen refresh "
                    "must include registry-state identity"
                )
        if validator_path.exists():
            validator_text = validator_path.read_text(encoding="utf-8")
            if (
                "static var _cached_citizen_registry_state: "
                "CityCitizenRegistryState" not in validator_text
                or '"citizen_registry_state_instance_id"' not in validator_text
            ):
                errors.append(
                    "scripts/city/simulation/CityStateValidator.gd: validation "
                    "cache must include citizen-registry identity"
                )

    citizen_spatial_state_path = (
        ROOT / "scripts/city/simulation/CityCitizenSpatialState.gd"
    )
    citizen_spatial_required_paths = (
        (citizen_spatial_state_path, "citizen spatial state owner"),
        (city_root_state_path, "City settlement root state"),
        (political_state_path, "settlement ownership registry"),
        (settlement_context_path, "settlement simulation context"),
        (world_data_path, "WorldData compatibility API"),
    )
    for required_path, owner_description in citizen_spatial_required_paths:
        if not required_path.exists():
            errors.append(
                f"{required_path.relative_to(ROOT)}: missing {owner_description}"
            )

    if all(path.exists() for path, _ in citizen_spatial_required_paths):
        citizen_spatial_state_text = citizen_spatial_state_path.read_text(
            encoding="utf-8"
        )
        city_root_state_text = city_root_state_path.read_text(encoding="utf-8")
        political_state_text = political_state_path.read_text(encoding="utf-8")
        settlement_context_text = settlement_context_path.read_text(
            encoding="utf-8"
        )
        world_data_text = world_data_path.read_text(encoding="utf-8")

        if "extends RefCounted" not in citizen_spatial_state_text:
            errors.append(
                "scripts/city/simulation/CityCitizenSpatialState.gd: must "
                "extend RefCounted"
            )
        if "class_name CityCitizenSpatialState" not in citizen_spatial_state_text:
            errors.append(
                "scripts/city/simulation/CityCitizenSpatialState.gd: missing "
                "CityCitizenSpatialState class_name"
            )

        declared_spatial_fields = set(
            re.findall(
                r"^var\s+([A-Za-z_][A-Za-z0-9_]*)\b",
                citizen_spatial_state_text,
                re.MULTILINE,
            )
        )
        if declared_spatial_fields != set(CITIZEN_SPATIAL_STATE_FIELDS):
            errors.append(
                "scripts/city/simulation/CityCitizenSpatialState.gd: must own "
                "exactly citizen_ids_by_tile and citizen_spatial_version"
            )
        if FUNC_RE.search(citizen_spatial_state_text):
            errors.append(
                "scripts/city/simulation/CityCitizenSpatialState.gd: must "
                "remain data-only during the ownership pass"
            )

        for state_name, (state_type, default_value) in (
            CITIZEN_SPATIAL_STATE_FIELDS.items()
        ):
            declaration_pattern = (
                rf"^var\s+{re.escape(state_name)}:\s*{state_type}\s*=\s*"
                rf"{re.escape(default_value)}\s*$"
            )
            if not re.search(
                declaration_pattern,
                citizen_spatial_state_text,
                re.MULTILINE,
            ):
                errors.append(
                    "scripts/city/simulation/CityCitizenSpatialState.gd: "
                    f"missing typed default for {state_name}"
                )

            for path in scripts:
                if path == citizen_spatial_state_path:
                    continue
                text = path.read_text(encoding="utf-8")
                if re.search(
                    rf"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s+)*"
                    rf"(?:static\s+)?var\s+{re.escape(state_name)}\b",
                    text,
                    re.MULTILINE,
                ):
                    errors.append(
                        f"{path.relative_to(ROOT)}: duplicate top-level citizen "
                        f"spatial storage must not return: {state_name}"
                    )

        for compatibility_name in WORLD_DATA_CITIZEN_SPATIAL_PROPERTIES:
            for path in scripts:
                if path == world_data_path:
                    continue
                text = path.read_text(encoding="utf-8")
                if re.search(
                    rf"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s+)*"
                    rf"(?:static\s+)?var\s+{re.escape(compatibility_name)}\b",
                    text,
                    re.MULTILINE,
                ):
                    errors.append(
                        f"{path.relative_to(ROOT)}: duplicate WorldData citizen "
                        f"spatial storage must not return: {compatibility_name}"
                    )

        if (
            "var citizen_spatial_state: CityCitizenSpatialState"
            not in city_root_state_text
        ):
            errors.append(
                "scripts/city/simulation/CitySettlementSimulationState.gd: "
                "missing citizen_spatial_state owner"
            )

        for world_data_symbol in WORLD_DATA_CITIZEN_SPATIAL_PROPERTIES:
            if f"WorldData.{world_data_symbol}" in city_root_state_text:
                errors.append(
                    "scripts/city/simulation/CitySettlementSimulationState.gd: "
                    "extracted citizen spatial state must not be captured/applied "
                    f"through WorldData.{world_data_symbol}"
                )

            dynamic_root_reference = re.search(
                rf"\bWorldData\s*\.\s*(?:get|set|call|callv)\s*\(\s*"
                rf"[\"']{re.escape(world_data_symbol)}[\"']",
                city_root_state_text,
            )
            callable_root_reference = re.search(
                rf"\bCallable\s*\(\s*WorldData\s*,\s*"
                rf"[\"']{re.escape(world_data_symbol)}[\"']\s*\)",
                city_root_state_text,
            )
            if dynamic_root_reference or callable_root_reference:
                errors.append(
                    "scripts/city/simulation/CitySettlementSimulationState.gd: "
                    "dynamic citizen-spatial workspace copying is forbidden: "
                    f"{world_data_symbol}"
                )

        required_political_spatial_surfaces = (
            (
                "state preload",
                r"^const\s+CityCitizenSpatialStateScript\s*=\s*preload\(",
            ),
            (
                "unbound owner",
                r"^var\s+_unbound_city_citizen_spatial_state\b",
            ),
            (
                "typed current-state resolver",
                r"^func\s+get_current_city_citizen_spatial_state\s*\(\s*\)"
                r"\s*->\s*CityCitizenSpatialState\s*:",
            ),
            (
                "founding adoption",
                r"^\s*capital_state\.citizen_spatial_state\s*=",
            ),
            (
                "legacy adoption",
                r"^\s*city_state\.citizen_spatial_state\s*=",
            ),
        )
        for surface_description, required_pattern in (
            required_political_spatial_surfaces
        ):
            if not re.search(
                required_pattern,
                political_state_text,
                re.MULTILINE,
            ):
                errors.append(
                    "scripts/world/simulation/WorldPoliticalState.gd: missing "
                    "citizen-spatial ownership surface: "
                    f"{surface_description}"
                )
        if political_state_text.count("CityCitizenSpatialStateScript.new()") < 3:
            errors.append(
                "scripts/world/simulation/WorldPoliticalState.gd: citizen "
                "spatial fallback must be created initially, on reset, and "
                "after legacy adoption"
            )
        if not re.search(
            r"^func\s+get_city_citizen_spatial_state\s*\(\s*\)\s*:",
            settlement_context_text,
            re.MULTILINE,
        ):
            errors.append(
                "scripts/world/simulation/SettlementSimulationContext.gd: "
                "missing citizen-spatial context accessor"
            )

        for property_name, (property_type, state_field) in (
            WORLD_DATA_CITIZEN_SPATIAL_PROPERTIES.items()
        ):
            declaration_matches = re.findall(
                rf"^static\s+var\s+{re.escape(property_name)}\b",
                world_data_text,
                re.MULTILINE,
            )
            property_match = re.search(
                rf"^static\s+var\s+{re.escape(property_name)}:\s*"
                rf"{property_type}:\s*\n"
                rf"(?P<body>.*?)"
                rf"(?=^static\s+var\s+|^const\s+|^#region\b|\Z)",
                world_data_text,
                re.MULTILINE | re.DOTALL,
            )
            if len(declaration_matches) != 1 or property_match is None:
                errors.append(
                    "scripts/world/simulation/WorldData.gd: citizen spatial "
                    f"compatibility property must be accessor-only: {property_name}"
                )
                continue

            property_body = property_match.group("body")
            resolver_count = property_body.count(
                "WorldPoliticalState.get_current_city_citizen_spatial_state()"
            )
            if (
                resolver_count != 2
                or not re.search(
                    rf"return\s+state\s*\.\s*{re.escape(state_field)}\b",
                    property_body,
                )
                or not re.search(
                    rf"state\s*\.\s*{re.escape(state_field)}\s*=\s*value\b",
                    property_body,
                )
            ):
                errors.append(
                    "scripts/world/simulation/WorldData.gd: citizen spatial "
                    f"property must route getter/setter through one owner: {property_name}"
                )

        renderer_path = ROOT / "scripts/city/rendering/CityRenderer.gd"
        validator_path = ROOT / "scripts/city/simulation/CityStateValidator.gd"
        if renderer_path.exists():
            renderer_text = renderer_path.read_text(encoding="utf-8")
            if (
                "var observed_city_citizen_spatial_state: "
                "CityCitizenSpatialState" not in renderer_text
                or "citizen_spatial_state_changed" not in renderer_text
                or "get_current_city_citizen_spatial_state()" not in renderer_text
            ):
                errors.append(
                    "scripts/city/rendering/CityRenderer.gd: citizen spatial "
                    "refresh must include state-owner identity"
                )
        if validator_path.exists():
            validator_text = validator_path.read_text(encoding="utf-8")
            if (
                "static var _cached_citizen_spatial_state: "
                "CityCitizenSpatialState" not in validator_text
                or '"citizen_spatial_state_instance_id"' not in validator_text
            ):
                errors.append(
                    "scripts/city/simulation/CityStateValidator.gd: validation "
                    "cache must include citizen-spatial identity"
                )

    citizen_movement_runtime_state_path = (
        ROOT
        / "scripts/city/simulation/CityCitizenMovementRuntimeState.gd"
    )
    citizen_movement_runtime_required_paths = (
        (
            citizen_movement_runtime_state_path,
            "citizen movement-runtime state owner",
        ),
        (city_root_state_path, "City settlement root state"),
        (political_state_path, "settlement ownership registry"),
        (settlement_context_path, "settlement simulation context"),
        (world_data_path, "WorldData compatibility API"),
    )
    for required_path, owner_description in (
        citizen_movement_runtime_required_paths
    ):
        if not required_path.exists():
            errors.append(
                f"{required_path.relative_to(ROOT)}: missing "
                f"{owner_description}"
            )

    if all(
        path.exists()
        for path, _ in citizen_movement_runtime_required_paths
    ):
        movement_runtime_state_text = (
            citizen_movement_runtime_state_path.read_text(encoding="utf-8")
        )
        city_root_state_text = city_root_state_path.read_text(
            encoding="utf-8"
        )
        political_state_text = political_state_path.read_text(
            encoding="utf-8"
        )
        settlement_context_text = settlement_context_path.read_text(
            encoding="utf-8"
        )
        world_data_text = world_data_path.read_text(encoding="utf-8")

        if "extends RefCounted" not in movement_runtime_state_text:
            errors.append(
                "scripts/city/simulation/"
                "CityCitizenMovementRuntimeState.gd: must extend RefCounted"
            )
        if (
            "class_name CityCitizenMovementRuntimeState"
            not in movement_runtime_state_text
        ):
            errors.append(
                "scripts/city/simulation/"
                "CityCitizenMovementRuntimeState.gd: missing class_name"
            )

        declared_movement_runtime_fields = set(
            re.findall(
                r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s+)*"
                r"var\s+([A-Za-z_][A-Za-z0-9_]*)\b",
                movement_runtime_state_text,
                re.MULTILINE,
            )
        )
        if declared_movement_runtime_fields != set(
            CITIZEN_MOVEMENT_RUNTIME_STATE_FIELDS
        ):
            errors.append(
                "scripts/city/simulation/"
                "CityCitizenMovementRuntimeState.gd: must own exactly "
                "active_mover_ids, active_mover_id_lookup, "
                "citizen_movement_visual_events, "
                "citizen_movement_visual_tick_index, and "
                "citizen_movement_version"
            )
        annotated_movement_runtime_function = re.search(
            r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s+)*"
            r"(?:static\s+)?func\s+[A-Za-z_][A-Za-z0-9_]*\s*\(",
            movement_runtime_state_text,
            re.MULTILINE,
        )
        if annotated_movement_runtime_function:
            errors.append(
                "scripts/city/simulation/"
                "CityCitizenMovementRuntimeState.gd: must remain data-only "
                "during the ownership pass"
            )

        for state_name, (state_type, default_value) in (
            CITIZEN_MOVEMENT_RUNTIME_STATE_FIELDS.items()
        ):
            declaration_pattern = (
                rf"^var\s+{re.escape(state_name)}:\s*{state_type}\s*=\s*"
                rf"{re.escape(default_value)}\s*$"
            )
            if not re.search(
                declaration_pattern,
                movement_runtime_state_text,
                re.MULTILINE,
            ):
                errors.append(
                    "scripts/city/simulation/"
                    "CityCitizenMovementRuntimeState.gd: missing typed "
                    f"default for {state_name}"
                )

            for path in scripts:
                if path == citizen_movement_runtime_state_path:
                    continue
                text = path.read_text(encoding="utf-8")
                if re.search(
                    rf"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s+)*"
                    rf"(?:static\s+)?var\s+{re.escape(state_name)}\b",
                    text,
                    re.MULTILINE,
                ):
                    errors.append(
                        f"{path.relative_to(ROOT)}: duplicate top-level "
                        "citizen movement-runtime storage must not return: "
                        f"{state_name}"
                    )

        for compatibility_name in (
            WORLD_DATA_CITIZEN_MOVEMENT_RUNTIME_PROPERTIES
        ):
            for path in scripts:
                if path == world_data_path:
                    continue
                text = path.read_text(encoding="utf-8")
                if re.search(
                    rf"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s+)*"
                    rf"(?:static\s+)?var\s+"
                    rf"{re.escape(compatibility_name)}\b",
                    text,
                    re.MULTILINE,
                ):
                    errors.append(
                        f"{path.relative_to(ROOT)}: duplicate WorldData "
                        "citizen movement-runtime storage must not return: "
                        f"{compatibility_name}"
                    )

        if (
            "var citizen_movement_runtime_state: "
            "CityCitizenMovementRuntimeState"
            not in city_root_state_text
        ):
            errors.append(
                "scripts/city/simulation/CitySettlementSimulationState.gd: "
                "missing citizen_movement_runtime_state owner"
            )

        for world_data_symbol in (
            WORLD_DATA_CITIZEN_MOVEMENT_RUNTIME_PROPERTIES
        ):
            if f"WorldData.{world_data_symbol}" in city_root_state_text:
                errors.append(
                    "scripts/city/simulation/CitySettlementSimulationState.gd: "
                    "extracted citizen movement runtime must not be "
                    f"captured/applied through WorldData.{world_data_symbol}"
                )

            dynamic_root_reference = re.search(
                rf"\bWorldData\s*\.\s*(?:get|set|call|callv)\s*\(\s*"
                rf"[\"']{re.escape(world_data_symbol)}[\"']",
                city_root_state_text,
            )
            callable_root_reference = re.search(
                rf"\bCallable\s*\(\s*WorldData\s*,\s*"
                rf"[\"']{re.escape(world_data_symbol)}[\"']\s*\)",
                city_root_state_text,
            )
            if dynamic_root_reference or callable_root_reference:
                errors.append(
                    "scripts/city/simulation/CitySettlementSimulationState.gd: "
                    "dynamic citizen movement-runtime workspace copying is "
                    f"forbidden: {world_data_symbol}"
                )

        required_political_movement_runtime_surfaces = (
            (
                "state preload",
                r"^const\s+CityCitizenMovementRuntimeStateScript\s*=\s*"
                r"preload\(",
            ),
            (
                "unbound owner",
                r"^var\s+_unbound_city_citizen_movement_runtime_state\b",
            ),
            (
                "typed current-state resolver",
                r"^func\s+get_current_city_citizen_movement_runtime_state"
                r"\s*\(\s*\)\s*->\s*CityCitizenMovementRuntimeState\s*:",
            ),
            (
                "founding adoption",
                r"^\s*capital_state\.citizen_movement_runtime_state\s*=",
            ),
            (
                "legacy adoption",
                r"^\s*city_state\.citizen_movement_runtime_state\s*=",
            ),
        )
        for surface_description, required_pattern in (
            required_political_movement_runtime_surfaces
        ):
            if not re.search(
                required_pattern,
                political_state_text,
                re.MULTILINE,
            ):
                errors.append(
                    "scripts/world/simulation/WorldPoliticalState.gd: missing "
                    "citizen movement-runtime ownership surface: "
                    f"{surface_description}"
                )
        if (
            political_state_text.count(
                "CityCitizenMovementRuntimeStateScript.new()"
            )
            < 3
        ):
            errors.append(
                "scripts/world/simulation/WorldPoliticalState.gd: citizen "
                "movement-runtime fallback must be created initially, on "
                "reset, and after legacy adoption"
            )
        if not re.search(
            r"^func\s+get_city_citizen_movement_runtime_state"
            r"\s*\(\s*\)\s*:",
            settlement_context_text,
            re.MULTILINE,
        ):
            errors.append(
                "scripts/world/simulation/SettlementSimulationContext.gd: "
                "missing citizen movement-runtime context accessor"
            )

        for property_name, (property_type, state_field) in (
            WORLD_DATA_CITIZEN_MOVEMENT_RUNTIME_PROPERTIES.items()
        ):
            declaration_matches = re.findall(
                rf"^static\s+var\s+{re.escape(property_name)}\b",
                world_data_text,
                re.MULTILINE,
            )
            property_match = re.search(
                rf"^static\s+var\s+{re.escape(property_name)}:\s*"
                rf"{property_type}:\s*\n"
                rf"(?P<body>.*?)"
                rf"(?=^static\s+var\s+|^const\s+|^#region\b|\Z)",
                world_data_text,
                re.MULTILINE | re.DOTALL,
            )
            if len(declaration_matches) != 1 or property_match is None:
                errors.append(
                    "scripts/world/simulation/WorldData.gd: citizen "
                    "movement-runtime compatibility property must be "
                    f"accessor-only: {property_name}"
                )
                continue

            property_body = property_match.group("body")
            resolver_matches = re.findall(
                r"WorldPoliticalState\s*\.\s*"
                r"get_current_city_citizen_movement_runtime_state\s*\(\s*\)",
                property_body,
            )
            if (
                len(resolver_matches) != 2
                or not re.search(
                    rf"return\s+state\s*\.\s*{re.escape(state_field)}\b",
                    property_body,
                )
                or not re.search(
                    rf"state\s*\.\s*{re.escape(state_field)}\s*=\s*value\b",
                    property_body,
                )
            ):
                errors.append(
                    "scripts/world/simulation/WorldData.gd: citizen "
                    "movement-runtime property must route getter/setter "
                    f"through one owner: {property_name}"
                )

        renderer_path = ROOT / "scripts/city/rendering/CityRenderer.gd"
        validator_path = ROOT / "scripts/city/simulation/CityStateValidator.gd"
        if renderer_path.exists():
            renderer_text = renderer_path.read_text(encoding="utf-8")
            if (
                "var observed_city_citizen_movement_runtime_state: "
                "CityCitizenMovementRuntimeState" not in renderer_text
                or "citizen_movement_runtime_state_changed"
                not in renderer_text
                or "get_current_city_citizen_movement_runtime_state()"
                not in renderer_text
                or 'change_flags["city_citizen_movement_runtime_changed"]'
                not in renderer_text
            ):
                errors.append(
                    "scripts/city/rendering/CityRenderer.gd: citizen "
                    "movement refresh must include runtime-owner identity"
                )
        if validator_path.exists():
            validator_text = validator_path.read_text(encoding="utf-8")
            if (
                "static var _cached_citizen_movement_runtime_state: "
                "CityCitizenMovementRuntimeState" not in validator_text
                or '"citizen_movement_runtime_state_instance_id"'
                not in validator_text
            ):
                errors.append(
                    "scripts/city/simulation/CityStateValidator.gd: "
                    "validation cache must include citizen "
                    "movement-runtime identity"
                )

    citizen_task_runtime_state_path = (
        ROOT / "scripts/city/simulation/CityCitizenTaskRuntimeState.gd"
    )
    citizen_task_runtime_required_paths = (
        (citizen_task_runtime_state_path, "citizen task-runtime state owner"),
        (city_root_state_path, "City settlement root state"),
        (political_state_path, "settlement ownership registry"),
        (settlement_context_path, "settlement simulation context"),
        (world_data_path, "WorldData compatibility API"),
    )
    for required_path, owner_description in citizen_task_runtime_required_paths:
        if not required_path.exists():
            errors.append(
                f"{required_path.relative_to(ROOT)}: missing {owner_description}"
            )

    if all(path.exists() for path, _ in citizen_task_runtime_required_paths):
        task_runtime_state_text = citizen_task_runtime_state_path.read_text(
            encoding="utf-8"
        )
        city_root_state_text = city_root_state_path.read_text(encoding="utf-8")
        political_state_text = political_state_path.read_text(encoding="utf-8")
        settlement_context_text = settlement_context_path.read_text(
            encoding="utf-8"
        )
        world_data_text = world_data_path.read_text(encoding="utf-8")

        if "extends RefCounted" not in task_runtime_state_text:
            errors.append(
                "scripts/city/simulation/CityCitizenTaskRuntimeState.gd: "
                "must extend RefCounted"
            )
        if "class_name CityCitizenTaskRuntimeState" not in task_runtime_state_text:
            errors.append(
                "scripts/city/simulation/CityCitizenTaskRuntimeState.gd: "
                "missing class_name"
            )

        declared_task_runtime_fields = set(
            re.findall(
                r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s+)*"
                r"(?:static\s+)?var\s+([A-Za-z_][A-Za-z0-9_]*)\b",
                task_runtime_state_text,
                re.MULTILINE,
            )
        )
        if declared_task_runtime_fields != set(CITIZEN_TASK_RUNTIME_STATE_FIELDS):
            errors.append(
                "scripts/city/simulation/CityCitizenTaskRuntimeState.gd: "
                "must own exactly active_task_ids, active_task_id_lookup, and "
                "citizen_task_version"
            )
        if re.search(
            r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s+)*"
            r"(?:static\s+)?func\s+[A-Za-z_][A-Za-z0-9_]*\s*\(",
            task_runtime_state_text,
            re.MULTILINE,
        ):
            errors.append(
                "scripts/city/simulation/CityCitizenTaskRuntimeState.gd: "
                "must remain data-only during the ownership pass"
            )

        for state_name, (state_type, default_value) in (
            CITIZEN_TASK_RUNTIME_STATE_FIELDS.items()
        ):
            declaration_pattern = (
                rf"^var\s+{re.escape(state_name)}:\s*{state_type}\s*=\s*"
                rf"{re.escape(default_value)}\s*$"
            )
            if not re.search(
                declaration_pattern,
                task_runtime_state_text,
                re.MULTILINE,
            ):
                errors.append(
                    "scripts/city/simulation/CityCitizenTaskRuntimeState.gd: "
                    f"missing typed default for {state_name}"
                )

            for path in scripts:
                if path == citizen_task_runtime_state_path:
                    continue
                text = path.read_text(encoding="utf-8")
                if re.search(
                    rf"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s+)*"
                    rf"(?:static\s+)?var\s+{re.escape(state_name)}\b",
                    text,
                    re.MULTILINE,
                ):
                    errors.append(
                        f"{path.relative_to(ROOT)}: duplicate top-level citizen "
                        f"task-runtime storage must not return: {state_name}"
                    )

        for compatibility_name in WORLD_DATA_CITIZEN_TASK_RUNTIME_PROPERTIES:
            for path in scripts:
                if path == world_data_path:
                    continue
                text = path.read_text(encoding="utf-8")
                if re.search(
                    rf"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s+)*"
                    rf"(?:static\s+)?var\s+{re.escape(compatibility_name)}\b",
                    text,
                    re.MULTILINE,
                ):
                    errors.append(
                        f"{path.relative_to(ROOT)}: duplicate WorldData citizen "
                        "task-runtime storage must not return: "
                        f"{compatibility_name}"
                    )

        if (
            "var citizen_task_runtime_state: CityCitizenTaskRuntimeState"
            not in city_root_state_text
        ):
            errors.append(
                "scripts/city/simulation/CitySettlementSimulationState.gd: "
                "missing citizen_task_runtime_state owner"
            )

        for world_data_symbol in WORLD_DATA_CITIZEN_TASK_RUNTIME_PROPERTIES:
            if f"WorldData.{world_data_symbol}" in city_root_state_text:
                errors.append(
                    "scripts/city/simulation/CitySettlementSimulationState.gd: "
                    "extracted citizen task runtime must not be captured/applied "
                    f"through WorldData.{world_data_symbol}"
                )

            dynamic_root_reference = re.search(
                rf"\bWorldData\s*\.\s*(?:get|set|call|callv)\s*\(\s*"
                rf"[\"']{re.escape(world_data_symbol)}[\"']",
                city_root_state_text,
            )
            callable_root_reference = re.search(
                rf"\bCallable\s*\(\s*WorldData\s*,\s*"
                rf"[\"']{re.escape(world_data_symbol)}[\"']\s*\)",
                city_root_state_text,
            )
            if dynamic_root_reference or callable_root_reference:
                errors.append(
                    "scripts/city/simulation/CitySettlementSimulationState.gd: "
                    "dynamic citizen task-runtime workspace copying is forbidden: "
                    f"{world_data_symbol}"
                )

        required_political_task_runtime_surfaces = (
            (
                "state preload",
                r"^const\s+CityCitizenTaskRuntimeStateScript\s*=\s*preload\(",
            ),
            (
                "unbound owner",
                r"^var\s+_unbound_city_citizen_task_runtime_state\b",
            ),
            (
                "typed current-state resolver",
                r"^func\s+get_current_city_citizen_task_runtime_state\s*"
                r"\(\s*\)\s*->\s*CityCitizenTaskRuntimeState\s*:",
            ),
            (
                "founding adoption",
                r"^\s*capital_state\.citizen_task_runtime_state\s*=",
            ),
            (
                "legacy adoption",
                r"^\s*city_state\.citizen_task_runtime_state\s*=",
            ),
        )
        for surface_description, required_pattern in (
            required_political_task_runtime_surfaces
        ):
            if not re.search(
                required_pattern,
                political_state_text,
                re.MULTILINE,
            ):
                errors.append(
                    "scripts/world/simulation/WorldPoliticalState.gd: missing "
                    "citizen task-runtime ownership surface: "
                    f"{surface_description}"
                )
        if political_state_text.count("CityCitizenTaskRuntimeStateScript.new()") < 3:
            errors.append(
                "scripts/world/simulation/WorldPoliticalState.gd: citizen "
                "task-runtime fallback must be created initially, on reset, and "
                "after legacy adoption"
            )
        if not re.search(
            r"^func\s+get_city_citizen_task_runtime_state\s*\(\s*\)\s*:",
            settlement_context_text,
            re.MULTILINE,
        ):
            errors.append(
                "scripts/world/simulation/SettlementSimulationContext.gd: "
                "missing citizen task-runtime context accessor"
            )

        for property_name, (property_type, state_field) in (
            WORLD_DATA_CITIZEN_TASK_RUNTIME_PROPERTIES.items()
        ):
            declaration_matches = re.findall(
                rf"^static\s+var\s+{re.escape(property_name)}\b",
                world_data_text,
                re.MULTILINE,
            )
            property_match = re.search(
                rf"^static\s+var\s+{re.escape(property_name)}:\s*"
                rf"{property_type}:\s*\n"
                rf"(?P<body>.*?)"
                rf"(?=^static\s+var\s+|^const\s+|^#region\b|\Z)",
                world_data_text,
                re.MULTILINE | re.DOTALL,
            )
            if len(declaration_matches) != 1 or property_match is None:
                errors.append(
                    "scripts/world/simulation/WorldData.gd: citizen "
                    "task-runtime compatibility property must be accessor-only: "
                    f"{property_name}"
                )
                continue

            property_body = property_match.group("body")
            resolver_matches = re.findall(
                r"WorldPoliticalState\s*\.\s*"
                r"get_current_city_citizen_task_runtime_state\s*\(\s*\)",
                property_body,
            )
            if (
                len(resolver_matches) != 2
                or not re.search(
                    rf"return\s+state\s*\.\s*{re.escape(state_field)}\b",
                    property_body,
                )
                or not re.search(
                    rf"state\s*\.\s*{re.escape(state_field)}\s*=\s*value\b",
                    property_body,
                )
            ):
                errors.append(
                    "scripts/world/simulation/WorldData.gd: citizen task-runtime "
                    "property must route getter/setter through one owner: "
                    f"{property_name}"
                )

        renderer_path = ROOT / "scripts/city/rendering/CityRenderer.gd"
        validator_path = ROOT / "scripts/city/simulation/CityStateValidator.gd"
        if renderer_path.exists():
            renderer_text = renderer_path.read_text(encoding="utf-8")
            renderer_identity_comparison = re.search(
                r"var\s+citizen_task_runtime_state_changed\s*:=\s*\(.*?"
                r"not\s+is_same\s*\(\s*"
                r"observed_city_citizen_task_runtime_state\s*,\s*"
                r"current_citizen_task_runtime_state\s*\).*?\)",
                renderer_text,
                re.DOTALL,
            )
            renderer_identity_invalidation = re.search(
                r"if\s*\(\s*citizen_task_runtime_state_changed\s*"
                r"or\s*observed_city_citizen_task_version\s*!=\s*"
                r"current_citizen_task_runtime_state\s*\.\s*"
                r"citizen_task_version\s*\)\s*:.*?"
                r"change_flags\s*\[\s*"
                r"[\"']city_citizen_task_runtime_changed[\"']\s*\]",
                renderer_text,
                re.DOTALL,
            )
            if (
                "var observed_city_citizen_task_runtime_state: "
                "CityCitizenTaskRuntimeState" not in renderer_text
                or "get_current_city_citizen_task_runtime_state()"
                not in renderer_text
                or renderer_identity_comparison is None
                or renderer_identity_invalidation is None
            ):
                errors.append(
                    "scripts/city/rendering/CityRenderer.gd: citizen task "
                    "refresh must include runtime-owner identity"
                )
        if validator_path.exists():
            validator_text = validator_path.read_text(encoding="utf-8")
            validator_identity_comparison = re.search(
                r"if\s*\(\s*_cached_citizen_task_runtime_state\s*"
                r"==\s*null\s*or\s*not\s+is_same\s*\(\s*"
                r"_cached_citizen_task_runtime_state\s*,\s*"
                r"WorldPoliticalState\s*\.\s*"
                r"get_current_city_citizen_task_runtime_state\s*\(\s*\)"
                r"\s*\)\s*\)\s*:\s*return\s+false",
                validator_text,
                re.DOTALL,
            )
            validator_cache_assignment = re.search(
                r"_cached_citizen_task_runtime_state\s*=\s*\(\s*"
                r"WorldPoliticalState\s*\.\s*"
                r"get_current_city_citizen_task_runtime_state\s*\(\s*\)"
                r"\s*\)",
                validator_text,
                re.DOTALL,
            )
            if (
                "static var _cached_citizen_task_runtime_state: "
                "CityCitizenTaskRuntimeState" not in validator_text
                or '"citizen_task_runtime_state_instance_id"'
                not in validator_text
                or validator_identity_comparison is None
                or validator_cache_assignment is None
            ):
                errors.append(
                    "scripts/city/simulation/CityStateValidator.gd: validation "
                    "cache must include citizen task-runtime identity"
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
