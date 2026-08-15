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
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if os.environ.get("GITHUB_ACTIONS", "").lower() == "true":
    LOG_DIR = ROOT / "ci-logs"
else:
    local_info_root = Path(
        os.environ.get("PALADIN_INFO_DIR", str(ROOT.parent / "Paladin_Info"))
    )
    LOG_DIR = local_info_root / "ci-logs"
LOG_DIR.mkdir(parents=True, exist_ok=True)
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
    "release_city_construction_site_materials",
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

WORLD_DATA_FORBIDDEN_CITY_WORKSPACE_SYMBOLS = (
    "official_city_world",
    "official_city_seed",
    "player_city_data",
)

RETIRED_CITY_WORKSPACE_BRIDGE_SYMBOLS = (
    "capture_from_world_data",
    "apply_to_world_data",
    "capture_active_settlement_state",
    "_capture_active_city_workspace",
    "_apply_active_city_workspace",
    "is_bound_to_world_data_workspace",
)

WORLD_DATA_FORBIDDEN_CITY_WORKSPACE_SYMBOLS = (
    "official_city_world",
    "official_city_seed",
    "player_city_data",
)

RETIRED_CITY_WORKSPACE_BRIDGE_SYMBOLS = (
    "capture_from_world_data",
    "apply_to_world_data",
    "capture_active_settlement_state",
    "_capture_active_city_workspace",
    "_apply_active_city_workspace",
    "is_bound_to_world_data_workspace",
)

WORLD_DATA_FORBIDDEN_CITY_WORKSPACE_SYMBOLS = (
    "official_city_world",
    "official_city_seed",
    "player_city_data",
)

RETIRED_CITY_WORKSPACE_BRIDGE_SYMBOLS = (
    "capture_from_world_data",
    "apply_to_world_data",
    "capture_active_settlement_state",
    "_capture_active_city_workspace",
    "_apply_active_city_workspace",
    "is_bound_to_world_data_workspace",
)

RETIRED_LEGACY_CITY_BACKEND_SYMBOLS = (
    "BACKEND_LEGACY_CITY_WORLD_DATA",
    "legacy_city_world_data",
)

WORLD_DATA_FINAL_FORBIDDEN_CITY_SYMBOLS = (
    "CityCitizensScript",
    "CityObjectCatalogScript",
    "STARTING_CITY_POPULATION",
    "CITY_CITIZEN_TASK_KIND_NONE",
    "CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE",
    "INVALID_CITY_TILE_POSITION",
    "CITY_OBJECT_CITY_CENTER",
    "CONTAINER_TYPE_PUBLIC_CITY_STORAGE",
    "WORKPLACE_PRODUCTION_STATUS_WORKING",
    "CITY_CARDINAL_TILE_OFFSETS",
    "CITY_TOPOLOGY_MUTATION_FAILURE_NONE",
    "get_city_object_definition",
    "get_city_object_resident_capacity",
    "city_object_is_workplace",
    "set_city_workplace_production_state",
    "commit_city_haul_source_reservation",
    "reserve_city_haul_destination",
    "add_city_citizen",
    "initialize_starting_city_population",
    "ensure_city_citizen_demographic_state",
    "get_starting_city_citizen_spawn_tiles",
    "get_city_resource_types",
    "is_city_resource_type",
)

WORLD_DATA_FORBIDDEN_CITY_NAVIGATION_SYMBOLS = (
    "city_object_access_tile_cache",
    "get_city_object_access_tiles",
    "_sort_city_tiles_y_then_x",
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
    "get_total_physical_city_resource_amount",
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
    "restore_city_resource_accounting_snapshot_for_city_state",
    "get_total_public_city_resource_amount",
    "get_total_public_city_resource_storage_capacity",
    "get_total_stored_city_resource_amount",
    "get_total_physical_city_resource_amount",
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
    "starting_population_initialized": ("bool", "false"),
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

# Pass 8 makes the focused citizen systems the only public behavior gateways.
# The state classes remain data-only owners, while WorldPoliticalState remains
# the one low-level resolver behind each system's typed get_current_state API.
CITIZEN_BEHAVIOR_SYSTEMS = {
    "registry": {
        "path": "scripts/citizens/simulation/systems/CityCitizenRegistrySystem.gd",
        "class_name": "CityCitizenRegistrySystem",
        "state_type": "CityCitizenRegistryState",
        "resolver": "get_current_city_citizen_registry_state",
        "properties": tuple(WORLD_DATA_CITIZEN_REGISTRY_PROPERTIES),
        "functions": (
            "get_city_citizens",
            "get_city_citizen_version",
            "get_next_city_citizen_id",
            "reset_city_citizen_registry_state",
            "mark_city_citizens_changed",
            "rebuild_city_citizen_index",
            "register_city_citizen_index",
            "get_city_citizen_index_by_id",
            "get_city_population_count",
            "get_city_citizen_by_id",
            "get_city_citizen_snapshot",
            "get_city_citizen_display_name",
        ),
        "retired_world_data_names": (
            "_mark_city_citizens_changed",
            "_register_city_citizen_index",
        ),
    },
    "spatial": {
        "path": "scripts/citizens/simulation/systems/CityCitizenSpatialSystem.gd",
        "class_name": "CityCitizenSpatialSystem",
        "state_type": "CityCitizenSpatialState",
        "resolver": "get_current_city_citizen_spatial_state",
        "properties": tuple(WORLD_DATA_CITIZEN_SPATIAL_PROPERTIES),
        "functions": (
            "get_city_citizen_spatial_version",
            "reset_city_citizen_spatial_state",
            "mark_city_citizen_spatial_changed",
            "add_city_citizen_to_spatial_index",
            "remove_city_citizen_from_spatial_index",
            "register_city_citizen_spatial_index_entry",
            "rebuild_city_citizen_spatial_index",
            "get_city_citizen_ids_at_tile",
            "has_living_city_citizen_at_tile",
            "ensure_city_citizen_spatial_state",
            "get_city_citizen_tile_position",
            "set_city_citizen_tile_position",
            "get_living_city_citizen_ids_in_tiles",
        ),
        "retired_world_data_names": (
            "_mark_city_citizen_spatial_changed",
            "_add_city_citizen_to_spatial_index",
            "_remove_city_citizen_from_spatial_index",
            "_register_city_citizen_spatial_index_entry",
        ),
    },
    "movement": {
        "path": (
            "scripts/citizens/simulation/systems/"
            "CityCitizenMovementRuntimeSystem.gd"
        ),
        "class_name": "CityCitizenMovementRuntimeSystem",
        "state_type": "CityCitizenMovementRuntimeState",
        "resolver": "get_current_city_citizen_movement_runtime_state",
        "properties": tuple(WORLD_DATA_CITIZEN_MOVEMENT_RUNTIME_PROPERTIES),
        "functions": (
            "get_city_citizen_movement_version",
            "reset_city_citizen_movement_runtime_state",
            "mark_city_citizen_movement_changed",
            "_add_city_active_mover_id",
            "_remove_city_active_mover_id",
            "rebuild_city_active_mover_registry",
            "get_city_active_mover_ids_snapshot",
            "begin_city_citizen_movement_visual_tick",
            "clear_city_citizen_movement_visual_events",
            "take_city_citizen_movement_visual_events",
            "ensure_city_citizen_movement_state",
            "_get_clean_city_citizen_movement_path",
            "cancel_city_citizen_movement",
            "assign_city_citizen_movement_order",
            "commit_city_citizen_movement_tick",
            "_make_city_citizen_movement_rejection",
            "_normalize_city_citizen_movement_updates",
            "_normalize_next_active_mover_ids",
            "_quarantine_rejected_city_citizen_movement_updates",
            "_apply_city_citizen_movement_updates",
            "_replace_city_active_mover_registry",
            "_make_city_citizen_movement_visual_event",
            "_make_city_citizen_movement_visual_snapshot",
            "_get_clean_city_citizen_movement_visual_trace",
        ),
        "retired_world_data_names": ("_mark_city_citizen_movement_changed",),
    },
    "task": {
        "path": (
            "scripts/citizens/simulation/systems/"
            "CityCitizenTaskRuntimeSystem.gd"
        ),
        "class_name": "CityCitizenTaskRuntimeSystem",
        "state_type": "CityCitizenTaskRuntimeState",
        "resolver": "get_current_city_citizen_task_runtime_state",
        "properties": tuple(WORLD_DATA_CITIZEN_TASK_RUNTIME_PROPERTIES),
        "functions": (
            "get_city_citizen_task_version",
            "reset_city_citizen_task_runtime_state",
            "mark_city_citizen_task_changed",
            "_add_city_active_task_id",
            "_remove_city_active_task_id",
            "_remove_all_city_active_task_array_entries",
            "rebuild_city_active_task_registry",
            "get_city_active_task_ids_snapshot",
            "get_city_citizen_current_haul",
            "set_city_citizen_current_haul",
            "get_city_food_task_reserved_endpoint_amount",
            "ensure_city_citizen_task_state",
            "get_city_citizen_current_task",
            "assign_city_citizen_task",
            "_make_city_citizen_task_assignment_context",
            "_prepare_city_citizen_task_assignment",
            "_prepare_city_work_task_assignment",
            "_prepare_city_food_task_assignment",
            "_prepare_city_player_command_task_assignment",
            "_prepare_city_haul_task_assignment",
            "_prepare_city_return_home_task_assignment",
            "_commit_city_citizen_task_assignment",
            "set_city_citizen_task_phase",
            "set_city_citizen_task_target_object_id",
            "set_city_citizen_task_activity_state",
            "clear_city_citizen_task",
        ),
        "retired_world_data_names": ("_mark_city_citizen_task_changed",),
    },
}

CITIZEN_NAVIGATION_MOVED_FUNCTIONS = (
    "city_citizen_can_access_object_interior",
    "get_city_citizen_movement_step_cost",
    "can_city_citizen_traverse_step",
    "_city_citizen_can_cross_object_boundary",
    "is_city_tile_walkable_for_citizen",
)

CITIZEN_SCHEMA_MOVED_FUNCTIONS = (
    "normalize_city_citizen_sex",
    "is_valid_city_citizen_sex",
    "get_city_citizen_sex_types",
    "get_city_citizen_sex_display_name",
    "get_city_citizen_name_pool_for_sex",
    "city_citizen_name_pools_are_ready",
    "get_used_city_citizen_name_counts",
    "is_valid_city_citizen_task_kind",
    "is_valid_city_citizen_task_source",
    "is_valid_city_citizen_task_phase",
    "is_valid_city_citizen_movement_state",
    "is_valid_city_citizen_movement_failure",
)

CITIZEN_SCHEMA_WORLD_DATA_RETIRED_PROPERTIES = (
    "city_citizen_male_name_pool",
    "city_citizen_female_name_pool",
    "city_citizen_unassigned_name_pool",
)

DEFERRED_CITIZEN_ROOT_FIELDS = {}

# Pass 9 keeps physical inventory and scalar needs embedded in the authoritative
# citizen record, but gives every query and mutation a focused, stateless
# behavior owner. These lists are deliberately explicit: adding a new public
# boundary is a reviewed architecture change rather than an accidental return
# to WorldData.
PASS9_CITIZEN_INVENTORY_SYSTEM_PATH = (
    "scripts/citizens/simulation/systems/CityCitizenInventorySystem.gd"
)
PASS9_CITIZEN_INVENTORY_SYSTEM_FUNCTIONS = (
    "ensure_city_citizen_inventory_state",
    "get_city_citizen_carry_capacity",
    "set_city_citizen_carry_capacity",
    "get_city_citizen_inventory",
    "get_city_citizen_inventory_resource_amount",
    "get_city_citizen_inventory_used_capacity",
    "get_city_citizen_personal_inventory_free_space",
    "get_city_citizen_inventory_free_space",
    "set_city_citizen_inventory_resource_amount",
    "add_resource_to_city_citizen_inventory",
    "remove_resource_from_city_citizen_inventory",
    "get_city_citizen_haul_cargo",
    "get_city_citizen_haul_cargo_resources",
    "get_city_citizen_haul_cargo_resource_amount",
    "get_city_citizen_haul_cargo_resource",
    "get_city_citizen_haul_cargo_amount",
    "get_city_citizen_total_carried_amount",
    "get_city_citizen_record_carried_resource_amount",
    "get_city_citizen_available_haul_capacity",
    "set_city_citizen_haul_cargo_resources",
    "change_city_citizen_haul_cargo_resource",
    "set_city_citizen_haul_cargo",
)
PASS9_CITIZEN_INVENTORY_PRIMITIVE_MUTATORS = (
    "ensure_city_citizen_inventory_state",
    "set_city_citizen_carry_capacity",
    "set_city_citizen_inventory_resource_amount",
    "set_city_citizen_haul_cargo_resources",
)

PASS9_CITIZEN_NEEDS_SYSTEM_PATH = (
    "scripts/citizens/simulation/systems/CitizenNeedsSystem.gd"
)
PASS9_CITIZEN_NEEDS_SYSTEM_FUNCTIONS = (
    "ensure_city_citizen_need_state",
    "get_city_citizen_hunger",
    "set_city_citizen_hunger_state",
    "get_city_citizen_happiness",
    "set_city_citizen_happiness",
    "_city_citizen_can_directly_withdraw_food",
    "_get_city_citizen_direct_food_withdrawal_target_tiles",
    "city_citizen_can_withdraw_food_from_endpoint",
    "get_city_citizen_food_endpoint_target_tiles",
    "get_city_food_endpoint_unreserved_amount",
    "transfer_city_food_endpoint_to_citizen_inventory",
    "run_tick",
    "get_single_food_allocation_nutrition_cap",
    "get_citizen_food_need_nutrition",
    "get_citizen_next_food_allocation_nutrition",
    "citizen_should_seek_food",
    "citizen_has_critical_food_need",
    "eat_personal_food_if_hungry",
)
PASS9_CITIZEN_NEEDS_PRIMITIVE_MUTATORS = (
    "ensure_city_citizen_need_state",
    "set_city_citizen_hunger_state",
    "set_city_citizen_happiness",
)

PASS9_CITIZEN_HAULING_SYSTEM_PATH = (
    "scripts/citizens/simulation/systems/CitizenHaulingSystem.gd"
)
PASS9_CITIZEN_HAULING_SYSTEM_FUNCTIONS = (
    "city_citizen_is_hauling",
)

PASS9_RETIRED_WORLD_DATA_CITIZEN_INVENTORY_NEEDS_SYMBOLS = (
    "make_empty_citizen_inventory",
    *PASS9_CITIZEN_INVENTORY_SYSTEM_FUNCTIONS,
    "ensure_city_citizen_need_state",
    "get_city_citizen_hunger",
    "set_city_citizen_hunger_state",
    "get_city_citizen_happiness",
    "set_city_citizen_happiness",
    "city_citizen_can_directly_withdraw_resource",
    "get_city_citizen_direct_withdrawal_target_tiles",
    "city_citizen_can_withdraw_food_from_endpoint",
    "get_city_citizen_food_endpoint_target_tiles",
    "get_city_food_endpoint_unreserved_amount",
    "transfer_city_food_endpoint_to_citizen_inventory",
    "transfer_city_object_resource_to_citizen_inventory",
    "CITY_FOOD_HUNGER_RESTORE_BY_RESOURCE",
    "get_city_food_resource_types",
    "get_city_food_hunger_restore",
    "DEFAULT_CITIZEN_CARRY_CAPACITY",
    "DEFAULT_CITIZEN_HUNGER",
    "MAX_CITIZEN_HUNGER",
    "CITIZEN_HUNGER_LOSS_PER_DAY",
    "CITIZEN_HUNGER_DECAY_DENOMINATOR_MINUTES",
    "CITIZEN_FOOD_SEEK_TRIGGER_HUNGER",
    "CITIZEN_FOOD_CARRY_TRIGGER_HUNGER",
    "CITIZEN_CRITICAL_FOOD_SEEK_TRIGGER_HUNGER",
    "CITIZEN_EAT_TARGET_HUNGER",
    "DEFAULT_CITIZEN_HAPPINESS",
    "HOUSEHOLD_FOOD_TARGET_DAY_NUMERATOR",
    "HOUSEHOLD_FOOD_TARGET_DAY_DENOMINATOR",
    "PUBLIC_FOOD_RESERVE_TARGET_DAY_NUMERATOR",
    "PUBLIC_FOOD_RESERVE_TARGET_DAY_DENOMINATOR",
    *PASS9_CITIZEN_HAULING_SYSTEM_FUNCTIONS,
)

PASS9_CITIZEN_INVENTORY_FIELDS = (
    "inventory",
    "carry_capacity",
    "haul_cargo",
)
PASS9_CITIZEN_NEEDS_FIELDS = (
    "hunger",
    "hunger_decay_remainder",
    "happiness",
)

# Bootstrap coverage is the only approved place to corrupt embedded citizen
# fields directly. All ordinary tests must exercise the same focused APIs as
# production. Keep this allowlist path-exact and intentionally small.
PASS9_CITIZEN_STATE_CORRUPTION_FIXTURE_PATHS = {
    "scripts/city/simulation/CityCitizenInventoryNeedsBootstrapTest.gd",
}

PASS9_REQUIRED_TEST_FUNCTIONS = {
    "scripts/city/simulation/CityCitizenInventoryNeedsBootstrapTest.gd": (
        "_test_real_founding_records_and_clean_ensures",
        "_test_lossless_legacy_repair_and_identity",
        "_test_headless_simulation_bootstrap_and_canonical_setters",
        "_test_malformed_carried_state_quarantine",
        "_test_validator_rejects_uninterpretable_embedded_state",
    ),
    "scripts/city/simulation/CityCitizenInventoryNeedsIsolationTest.gd": (
        "_test_equal_version_city_isolation",
    ),
    "scripts/city/simulation/CityFoodAllocationFairnessTest.gd": (
        "_test_current_source_allocates_one_immediate_meal",
        "_test_hungry_citizens_reserve_before_household_stocking",
    ),
    "scripts/city/simulation/CityEmploymentFoodDeadlockTest.gd": (
        "_test_hunger_waits_for_real_food_opportunity",
        "_test_starving_food_workers_keep_survival_schedule",
        "_test_starving_worker_recovers_and_returns_to_work",
        "_test_starving_residents_keep_return_home_schedule",
    ),
    "scripts/city/simulation/CityUnifiedBoundaryTest.gd": (
        "_test_public_storage_keep_fallback",
        "_test_critical_hunger_interrupts_cargo_safely",
    ),
    "scripts/city/simulation/CityUnifiedWorkSystemTest.gd": (
        "_test_food_replenishment_cycle_and_whole_item_consumption",
        "_test_household_and_public_food_reserve_targets",
        "_test_normal_home_food_preference_allowance",
        "_test_survival_food_fallback_and_reservation_accounting",
    ),
}

PASS9_REQUIRED_TEST_CALLS = {
    "scripts/city/simulation/CityCitizenInventoryNeedsBootstrapTest.gd": {
        "_test_real_founding_records_and_clean_ensures": (
            "found_player_city",
            "ensure_city_citizen_inventory_state",
            "ensure_city_citizen_need_state",
        ),
        "_test_lossless_legacy_repair_and_identity": (
            "ensure_city_citizen_inventory_state",
            "ensure_city_citizen_need_state",
        ),
        "_test_headless_simulation_bootstrap_and_canonical_setters": (
            "run_settlement_simulation_systems",
            "set_city_citizen_inventory_resource_amount",
            "set_city_citizen_hunger_state",
        ),
        "_test_malformed_carried_state_quarantine": (
            "ensure_city_citizen_inventory_state",
            "get_city_citizen_inventory_free_space",
            "transfer_city_food_endpoint_to_citizen_inventory",
        ),
        "_test_validator_rejects_uninterpretable_embedded_state": (
            "_validate_citizen_inventories",
            "_validate_city_citizen_need_state",
            "_errors_contain",
        ),
    },
    "scripts/city/simulation/CityCitizenInventoryNeedsIsolationTest.gd": {
        "_test_equal_version_city_isolation": (
            "set_active_settlement",
            "_active_city_matches",
            "is_same",
        ),
    },
    "scripts/city/simulation/CityFoodAllocationFairnessTest.gd": {
        "_test_current_source_allocates_one_immediate_meal": (
            "run_tick",
            "get_city_object_stored_resource_amount",
        ),
        "_test_hungry_citizens_reserve_before_household_stocking": (
            "_process_food_needs",
            "get_city_public_food_surplus_nutrition",
            "_get_scheduled_home_food_delivery_task_request",
        ),
    },
    "scripts/city/simulation/CityEmploymentFoodDeadlockTest.gd": {
        "_test_hunger_waits_for_real_food_opportunity": (
            "_process_player_commands",
            "_process_food_needs",
        ),
        "_test_starving_food_workers_keep_survival_schedule": (
            "_get_assigned_work_task_request",
            "_process_food_needs",
        ),
        "_test_starving_worker_recovers_and_returns_to_work": (
            "run_tick",
            "get_city_citizen_hunger",
            "get_city_object_stored_resource_amount",
        ),
        "_test_starving_residents_keep_return_home_schedule": (
            "_get_assigned_home_task_request",
            "_process_food_needs",
        ),
    },
    "scripts/city/simulation/CityUnifiedBoundaryTest.gd": {
        "_test_public_storage_keep_fallback": (
            "validate",
            "get_total_physical_city_resource_amount",
            "get_city_citizen_haul_cargo_amount",
        ),
        "_test_critical_hunger_interrupts_cargo_safely": (
            "run_tick",
            "get_total_physical_city_resource_amount",
            "get_city_citizen_haul_cargo_amount",
        ),
    },
    "scripts/city/simulation/CityUnifiedWorkSystemTest.gd": {
        "_test_food_replenishment_cycle_and_whole_item_consumption": (
            "eat_personal_food_if_hungry",
            "citizen_has_critical_food_need",
        ),
        "_test_household_and_public_food_reserve_targets": (
            "get_city_home_food_target_nutrition",
            "get_city_public_food_reserve_target_nutrition",
            "find_best_household_food_source",
        ),
        "_test_normal_home_food_preference_allowance": (
            "_choose_normal_survival_food_result",
        ),
        "_test_survival_food_fallback_and_reservation_accounting": (
            "find_best_survival_food_source",
            "_assign_food_match",
            "get_city_food_endpoint_unreserved_amount",
        ),
    },
}

PASS9_FOCUSED_QUERY_CONSUMERS = {
    "scripts/ui/city/CityInformationPanel.gd": (
        "get_city_citizen_hunger",
        "get_city_citizen_happiness",
    ),
    "scripts/ui/debug/CitizenDebugPanel.gd": (
        "get_city_citizen_hunger",
        "get_city_citizen_happiness",
        "get_city_citizen_carry_capacity",
        "get_city_citizen_inventory_used_capacity",
        "get_city_citizen_haul_cargo_amount",
        "get_city_citizen_haul_cargo_resources",
        "city_citizen_is_hauling",
    ),
    "scripts/city/rendering/CityRenderer.gd": (
        "get_city_citizen_hunger",
        "get_city_citizen_carry_capacity",
        "get_city_citizen_inventory",
        "get_city_citizen_inventory_used_capacity",
        "get_city_citizen_haul_cargo_amount",
        "get_city_citizen_haul_cargo_resources",
        "city_citizen_is_hauling",
    ),
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


def gdscript_function_body(text: str, function_name: str) -> str | None:
    """Return one top-level GDScript function body, excluding its signature."""

    lines = text.splitlines()
    start_index: int | None = None

    for index, line in enumerate(lines):
        match = FUNC_LINE_RE.match(line)
        if match and match.group(1) == function_name:
            start_index = index + 1
            break

    if start_index is None:
        return None

    end_index = len(lines)
    for index in range(start_index, len(lines)):
        if FUNC_LINE_RE.match(lines[index]):
            end_index = index
            break

    return "\n".join(lines[start_index:end_index])


def gdscript_without_line_comments(text: str) -> str:
    """Remove GDScript line comments while preserving quoted string content."""

    cleaned_lines: list[str] = []
    for line in text.splitlines(keepends=True):
        quote: str | None = None
        escaped = False
        comment_start: int | None = None

        for index, character in enumerate(line):
            if quote is not None:
                if escaped:
                    escaped = False
                elif character == "\\":
                    escaped = True
                elif character == quote:
                    quote = None
                continue

            if character in {'"', "'"}:
                quote = character
            elif character == "#":
                comment_start = index
                break

        if comment_start is None:
            cleaned_lines.append(line)
            continue

        newline = "\n" if line.endswith("\n") else ""
        cleaned_lines.append(line[:comment_start].rstrip() + newline)

    return "".join(cleaned_lines)


def gdscript_masked_code(text: str) -> str:
    """Mask comments and string bodies, leaving executable token layout intact."""

    comment_free = gdscript_without_line_comments(text)
    masked: list[str] = []
    quote: str | None = None
    escaped = False

    for character in comment_free:
        if quote is not None:
            if character == "\n":
                masked.append("\n")
                escaped = False
                continue
            if escaped:
                masked.append(" ")
                escaped = False
                continue
            if character == "\\":
                masked.append(" ")
                escaped = True
                continue
            if character == quote:
                masked.append(character)
                quote = None
            else:
                masked.append(" ")
            continue

        if character in {'"', "'"}:
            quote = character
            masked.append(character)
        else:
            masked.append(character)

    return "".join(masked)


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
        for symbol in WORLD_DATA_FINAL_FORBIDDEN_CITY_SYMBOLS:
            if symbol in {"CityCitizensScript", "CityObjectCatalogScript"}:
                forbidden = symbol in world_data_text
            else:
                forbidden = bool(re.search(
                    rf"^\s*(?:(?:static\s+)?(?:const|var)\s+{re.escape(symbol)}\b|(?:static\s+)?func\s+{re.escape(symbol)}\s*\()",
                    world_data_text,
                    re.MULTILINE,
                ))
            if forbidden:
                errors.append(
                    "scripts/world/simulation/WorldData.gd: Pass 14 final boundary "
                    f"forbids city-only declaration: {symbol}"
                )
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


        for symbol in WORLD_DATA_FORBIDDEN_CITY_WORKSPACE_SYMBOLS:
            declaration_patterns = (
                rf"^\s*static\s+var\s+{re.escape(symbol)}\b",
                rf"^\s*var\s+{re.escape(symbol)}\b",
            )
            if any(re.search(pattern, world_data_text, re.MULTILINE) for pattern in declaration_patterns):
                errors.append(
                    "scripts/world/simulation/WorldData.gd: retired Pass 12 city workspace field must not return: " + symbol
                )

        for path in scripts:
            relative = str(path.relative_to(ROOT))
            source_text = path.read_text(encoding="utf-8")
            for symbol in WORLD_DATA_FORBIDDEN_CITY_WORKSPACE_SYMBOLS:
                if re.search(rf"\bWorldData\s*\.\s*{re.escape(symbol)}\b", source_text):
                    errors.append(f"{relative}: retired WorldData city workspace reference remains: WorldData.{symbol}")
            for symbol in RETIRED_CITY_WORKSPACE_BRIDGE_SYMBOLS:
                if re.search(rf"(?:func\s+)?{re.escape(symbol)}\b", source_text):
                    errors.append(f"{relative}: retired Pass 12 capture/apply bridge symbol remains: {symbol}")

        for symbol in WORLD_DATA_FORBIDDEN_CITY_WORKSPACE_SYMBOLS:
            declaration_patterns = (
                rf"^\s*static\s+var\s+{re.escape(symbol)}\b",
                rf"^\s*var\s+{re.escape(symbol)}\b",
            )
            if any(re.search(pattern, world_data_text, re.MULTILINE) for pattern in declaration_patterns):
                errors.append(
                    "scripts/world/simulation/WorldData.gd: retired Pass 12 city workspace field must not return: " + symbol
                )

        for path in scripts:
            relative = str(path.relative_to(ROOT))
            source_text = path.read_text(encoding="utf-8")
            for symbol in WORLD_DATA_FORBIDDEN_CITY_WORKSPACE_SYMBOLS:
                if re.search(rf"\bWorldData\s*\.\s*{re.escape(symbol)}\b", source_text):
                    errors.append(f"{relative}: retired WorldData city workspace reference remains: WorldData.{symbol}")
            for symbol in RETIRED_CITY_WORKSPACE_BRIDGE_SYMBOLS:
                if re.search(rf"(?:func\s+)?{re.escape(symbol)}\b", source_text):
                    errors.append(f"{relative}: retired Pass 12 capture/apply bridge symbol remains: {symbol}")

        for symbol in WORLD_DATA_FORBIDDEN_CITY_WORKSPACE_SYMBOLS:
            declaration_patterns = (
                rf"^\s*static\s+var\s+{re.escape(symbol)}\b",
                rf"^\s*var\s+{re.escape(symbol)}\b",
            )
            if any(re.search(pattern, world_data_text, re.MULTILINE) for pattern in declaration_patterns):
                errors.append(
                    "scripts/world/simulation/WorldData.gd: retired Pass 12 city workspace field must not return: " + symbol
                )

        for path in scripts:
            relative = str(path.relative_to(ROOT))
            source_text = path.read_text(encoding="utf-8")
            for symbol in WORLD_DATA_FORBIDDEN_CITY_WORKSPACE_SYMBOLS:
                if re.search(rf"\bWorldData\s*\.\s*{re.escape(symbol)}\b", source_text):
                    errors.append(f"{relative}: retired WorldData city workspace reference remains: WorldData.{symbol}")
            for symbol in RETIRED_CITY_WORKSPACE_BRIDGE_SYMBOLS:
                if re.search(rf"(?:func\s+)?{re.escape(symbol)}\b", source_text):
                    errors.append(f"{relative}: retired Pass 12 capture/apply bridge symbol remains: {symbol}")

        for path in scripts:
            relative = str(path.relative_to(ROOT))
            source_text = path.read_text(encoding="utf-8")
            for symbol in RETIRED_LEGACY_CITY_BACKEND_SYMBOLS:
                if symbol in source_text:
                    errors.append(
                        f"{relative}: retired Pass 13 legacy city backend symbol remains: {symbol}"
                    )

        for symbol in WORLD_DATA_FORBIDDEN_CITY_NAVIGATION_SYMBOLS:
            declaration_patterns = (
                rf"^\s*static\s+var\s+{re.escape(symbol)}\b",
                rf"^\s*(?:static\s+)?func\s+{re.escape(symbol)}\s*\(",
            )
            if any(
                re.search(pattern, world_data_text, re.MULTILINE)
                for pattern in declaration_patterns
            ):
                errors.append(
                    "scripts/world/simulation/WorldData.gd: extracted city-navigation "
                    f"cache/behavior must not return to WorldData: {symbol}"
                )

        navigation_state_path = (
            ROOT / "scripts/city/simulation/CityNavigationState.gd"
        )
        navigation_system_path = (
            ROOT / "scripts/city/simulation/systems/CityNavigationSystem.gd"
        )
        political_state_path = (
            ROOT / "scripts/world/simulation/WorldPoliticalState.gd"
        )
        settlement_state_path_for_navigation = (
            ROOT / "scripts/city/simulation/CitySettlementSimulationState.gd"
        )
        if not navigation_state_path.exists():
            errors.append(
                "scripts/city/simulation/CityNavigationState.gd: missing navigation cache state owner"
            )
        elif (
            navigation_system_path.exists()
            and political_state_path.exists()
            and settlement_state_path_for_navigation.exists()
        ):
            navigation_state_text = navigation_state_path.read_text(encoding="utf-8")
            navigation_system_text = navigation_system_path.read_text(encoding="utf-8")
            political_state_text = political_state_path.read_text(encoding="utf-8")
            settlement_navigation_text = settlement_state_path_for_navigation.read_text(encoding="utf-8")
            declared_navigation_fields = set(
                re.findall(
                    r"^var\s+([A-Za-z_][A-Za-z0-9_]*)\b",
                    navigation_state_text,
                    re.MULTILINE,
                )
            )
            expected_navigation_fields = {
                "object_access_tile_cache",
                "base_land_component_world",
                "base_land_component_world_size",
                "base_land_component_tile_data_version",
                "base_land_component_seed_tile",
                "base_land_component_membership",
                "base_land_component_boundary_indices",
            }
            if declared_navigation_fields != expected_navigation_fields:
                errors.append(
                    "scripts/city/simulation/CityNavigationState.gd: must own "
                    "exactly the focused access-tile and base-land component "
                    "cache fields"
                )
            if FUNC_RE.search(navigation_state_text):
                errors.append(
                    "scripts/city/simulation/CityNavigationState.gd: must remain data-only; navigation behavior belongs in CityNavigationSystem"
                )
            required_navigation_surfaces = (
                "static func get_current_state() -> CityNavigationState:",
                "static func reset_city_navigation_state() -> void:",
                "static func get_city_object_access_tiles(",
            )
            for surface in required_navigation_surfaces:
                if surface not in navigation_system_text:
                    errors.append(
                        "scripts/city/simulation/systems/CityNavigationSystem.gd: missing required navigation-cache API: "
                        + surface
                    )
            if "var navigation_state: CityNavigationState" not in settlement_navigation_text:
                errors.append(
                    "scripts/city/simulation/CitySettlementSimulationState.gd: missing navigation_state owner"
                )
            if "object_access_tile_cache = WorldData" in settlement_navigation_text or "WorldData.city_object_access_tile_cache" in settlement_navigation_text:
                errors.append(
                    "scripts/city/simulation/CitySettlementSimulationState.gd: navigation cache must not participate in capture/apply"
                )
            if "var _unbound_city_navigation_state" not in political_state_text:
                errors.append(
                    "scripts/world/simulation/WorldPoliticalState.gd: missing pre-context CityNavigationState owner"
                )
            if "func get_current_city_navigation_state() -> CityNavigationState:" not in political_state_text:
                errors.append(
                    "scripts/world/simulation/WorldPoliticalState.gd: missing typed current CityNavigationState resolver"
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

        for path in scripts:
            if path == world_data_path:
                continue
            relative = str(path.relative_to(ROOT))
            source_text = path.read_text(encoding="utf-8")
            for symbol in WORLD_DATA_FORBIDDEN_CITY_NAVIGATION_SYMBOLS:
                legacy_pattern = rf"WorldData\s*\.\s*{re.escape(symbol)}\b"
                if re.search(legacy_pattern, source_text):
                    errors.append(
                        f"{relative}: legacy WorldData city-navigation reference remains: "
                        f"WorldData.{symbol}"
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
        legacy_completion_call_count = construction_system_text.count(
            "CityObjectSystem.register_completed_city_object_from_construction_site("
        )
        explicit_completion_call_count = construction_system_text.count(
            "CityObjectSystem.register_completed_city_object_from_construction_site_for_city_state("
        )
        unrestricted_completion_call_count = construction_system_text.count(
            "CityObjectSystem.register_completed_city_object("
        )
        if (
            legacy_completion_call_count != 1
            or explicit_completion_call_count != 1
            or unrestricted_completion_call_count != 0
        ):
            errors.append(
                "scripts/city/simulation/systems/CityConstructionSystem.gd: "
                "construction finalization must use each authoritative "
                "construction-site completion API exactly once and must not "
                "call unrestricted registration; found legacy="
                f"{legacy_completion_call_count}, explicit="
                f"{explicit_completion_call_count}, unrestricted="
                f"{unrestricted_completion_call_count}"
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
            expected_object_initializers = (
                2
                if "register_completed_city_object_for_city_state" in text
                else 1
            )
            if (
                path == city_object_system_path
                and (
                    stored_resource_write_count != expected_object_initializers
                    or "CityResourceContainerSystem.make_empty_city_object_storage_for_type"
                    not in text
                )
            ):
                errors.append(
                    f"{relative}: CityObjectSystem may initialize stored_resources "
                    "exactly once through CityResourceContainerSystem"
                )
            elif (
                not path.name.endswith("Test.gd")
                and path != city_object_system_path
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
                "exactly citizens, citizen_index_by_id, next_citizen_id, "
                "citizen_version, and starting_population_initialized"
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
        if political_state_text.count("CityCitizenRegistryStateScript.new()") < 2:
            errors.append(
                "scripts/world/simulation/WorldPoliticalState.gd: citizen "
                "registry fallback must be created initially and on reset"
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

        for property_name in WORLD_DATA_CITIZEN_REGISTRY_PROPERTIES:
            if re.search(
                rf"^static\s+var\s+{re.escape(property_name)}\b",
                world_data_text,
                re.MULTILINE,
            ):
                errors.append(
                    "scripts/world/simulation/WorldData.gd: retired citizen "
                    "registry compatibility property must not return: "
                    f"{property_name}"
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
                if path in {
                    world_data_path,
                    ROOT
                    / "scripts/citizens/simulation/systems/"
                    "CityCitizenSpatialSystem.gd",
                }:
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
        if political_state_text.count("CityCitizenSpatialStateScript.new()") < 2:
            errors.append(
                "scripts/world/simulation/WorldPoliticalState.gd: citizen "
                "spatial fallback must be created initially and on reset"
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

        for property_name in WORLD_DATA_CITIZEN_SPATIAL_PROPERTIES:
            if re.search(
                rf"^static\s+var\s+{re.escape(property_name)}\b",
                world_data_text,
                re.MULTILINE,
            ):
                errors.append(
                    "scripts/world/simulation/WorldData.gd: retired citizen "
                    "spatial compatibility property must not return: "
                    f"{property_name}"
                )

        renderer_path = ROOT / "scripts/city/rendering/CityRenderer.gd"
        validator_path = ROOT / "scripts/city/simulation/CityStateValidator.gd"
        if renderer_path.exists():
            renderer_text = renderer_path.read_text(encoding="utf-8")
            if (
                "var observed_city_citizen_spatial_state: "
                "CityCitizenSpatialState" not in renderer_text
                or "citizen_spatial_state_changed" not in renderer_text
                or "CityCitizenSpatialSystem.get_current_state()"
                not in renderer_text
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
                if path in {
                    world_data_path,
                    ROOT
                    / "scripts/citizens/simulation/systems/"
                    "CityCitizenMovementRuntimeSystem.gd",
                }:
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
            < 2
        ):
            errors.append(
                "scripts/world/simulation/WorldPoliticalState.gd: citizen "
                "movement-runtime fallback must be created initially and on reset"
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

        for property_name in WORLD_DATA_CITIZEN_MOVEMENT_RUNTIME_PROPERTIES:
            if re.search(
                rf"^static\s+var\s+{re.escape(property_name)}\b",
                world_data_text,
                re.MULTILINE,
            ):
                errors.append(
                    "scripts/world/simulation/WorldData.gd: retired citizen "
                    "movement-runtime compatibility property must not return: "
                    f"{property_name}"
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
                or "CityCitizenMovementRuntimeSystem.get_current_state()"
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
                if path in {
                    world_data_path,
                    ROOT
                    / "scripts/citizens/simulation/systems/"
                    "CityCitizenTaskRuntimeSystem.gd",
                }:
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
        if political_state_text.count("CityCitizenTaskRuntimeStateScript.new()") < 2:
            errors.append(
                "scripts/world/simulation/WorldPoliticalState.gd: citizen "
                "task-runtime fallback must be created initially and on reset"
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

        for property_name in WORLD_DATA_CITIZEN_TASK_RUNTIME_PROPERTIES:
            if re.search(
                rf"^static\s+var\s+{re.escape(property_name)}\b",
                world_data_text,
                re.MULTILINE,
            ):
                errors.append(
                    "scripts/world/simulation/WorldData.gd: retired citizen "
                    "task-runtime compatibility property must not return: "
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
                or "CityCitizenTaskRuntimeSystem.get_current_state()"
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
                r"CityCitizenTaskRuntimeSystem\s*\.\s*"
                r"get_current_state\s*\(\s*\)"
                r"\s*\)\s*\)\s*:\s*return\s+false",
                validator_text,
                re.DOTALL,
            )
            validator_cache_assignment = re.search(
                r"_cached_citizen_task_runtime_state\s*=\s*\(\s*"
                r"CityCitizenTaskRuntimeSystem\s*\.\s*"
                r"get_current_state\s*\(\s*\)"
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

    # Pass 8: focused citizen behavior APIs must be permanent boundaries.
    # Direct state resolution is intentionally private to WorldPoliticalState
    # and each matching focused system. Add an explicit path here if a future,
    # short-lived migration bridge is ever approved; the default is no bridge.
    citizen_state_resolver_bridge_paths: set[Path] = set()
    citizen_system_paths: dict[str, Path] = {}
    moved_world_data_symbols: set[str] = set(CITIZEN_NAVIGATION_MOVED_FUNCTIONS)
    moved_world_data_symbols.update(CITIZEN_SCHEMA_MOVED_FUNCTIONS)
    compatibility_properties: set[str] = set(
        CITIZEN_SCHEMA_WORLD_DATA_RETIRED_PROPERTIES
    )

    for domain_name, config in CITIZEN_BEHAVIOR_SYSTEMS.items():
        system_path = ROOT / str(config["path"])
        citizen_system_paths[domain_name] = system_path
        required_functions = set(config["functions"])
        moved_world_data_symbols.update(required_functions)
        moved_world_data_symbols.update(config["retired_world_data_names"])
        compatibility_properties.update(config["properties"])

        if not system_path.exists():
            errors.append(
                f"{config['path']}: missing Pass 8 citizen {domain_name} "
                "behavior gateway"
            )
            continue

        system_text = system_path.read_text(encoding="utf-8")
        if not re.search(
            rf"^class_name\s+{re.escape(str(config['class_name']))}\s*$",
            system_text,
            re.MULTILINE,
        ):
            errors.append(
                f"{config['path']}: missing {config['class_name']} class_name"
            )

        typed_accessor_pattern = (
            r"^static\s+func\s+get_current_state\s*\(\s*\)\s*->\s*"
            rf"{re.escape(str(config['state_type']))}\s*:"
        )
        if not re.search(typed_accessor_pattern, system_text, re.MULTILINE):
            errors.append(
                f"{config['path']}: missing typed get_current_state() -> "
                f"{config['state_type']} gateway"
            )

        resolver = str(config["resolver"])
        if not re.search(
            rf"return\s+WorldPoliticalState\s*\.\s*"
            rf"{re.escape(resolver)}\s*\(\s*\)",
            system_text,
        ):
            errors.append(
                f"{config['path']}: get_current_state must route through "
                f"WorldPoliticalState.{resolver}()"
            )

        declared_functions = set(FUNC_RE.findall(system_text))
        missing_functions = sorted(required_functions - declared_functions)
        if missing_functions:
            errors.append(
                f"{config['path']}: missing focused citizen behavior: "
                + ", ".join(missing_functions)
            )

        allowed_property_owner = system_path
        for property_name in config["properties"]:
            if not re.search(
                rf"^static\s+var\s+{re.escape(str(property_name))}\b",
                system_text,
                re.MULTILINE,
            ):
                errors.append(
                    f"{config['path']}: missing focused state property "
                    f"{property_name}"
                )
            for path in scripts:
                if path == allowed_property_owner:
                    continue
                text = path.read_text(encoding="utf-8")
                if re.search(
                    rf"^(?:static\s+)?var\s+"
                    rf"{re.escape(str(property_name))}\b",
                    text,
                    re.MULTILINE,
                ):
                    errors.append(
                        f"{path.relative_to(ROOT)}: citizen compatibility "
                        f"property is private to {config['class_name']}: "
                        f"{property_name}"
                    )

    navigation_path = (
        ROOT / "scripts/city/simulation/systems/CityNavigationSystem.gd"
    )
    if not navigation_path.exists():
        errors.append(
            "scripts/city/simulation/systems/CityNavigationSystem.gd: "
            "missing citizen navigation behavior owner"
        )
    else:
        navigation_functions = set(
            FUNC_RE.findall(navigation_path.read_text(encoding="utf-8"))
        )
        missing_navigation_functions = sorted(
            set(CITIZEN_NAVIGATION_MOVED_FUNCTIONS) - navigation_functions
        )
        if missing_navigation_functions:
            errors.append(
                "scripts/city/simulation/systems/CityNavigationSystem.gd: "
                "missing focused citizen navigation behavior: "
                + ", ".join(missing_navigation_functions)
            )

    citizen_schema_path = (
        ROOT / "scripts/citizens/simulation/CityCitizens.gd"
    )
    if not citizen_schema_path.exists():
        errors.append(
            "scripts/citizens/simulation/CityCitizens.gd: missing citizen "
            "schema behavior owner"
        )
    else:
        citizen_schema_text = citizen_schema_path.read_text(encoding="utf-8")
        schema_functions = set(FUNC_RE.findall(citizen_schema_text))
        missing_schema_functions = sorted(
            set(CITIZEN_SCHEMA_MOVED_FUNCTIONS) - schema_functions
        )
        if missing_schema_functions:
            errors.append(
                "scripts/citizens/simulation/CityCitizens.gd: missing focused "
                "citizen schema behavior: "
                + ", ".join(missing_schema_functions)
            )
        for property_name in CITIZEN_SCHEMA_WORLD_DATA_RETIRED_PROPERTIES:
            if not re.search(
                rf"^static\s+var\s+{re.escape(property_name)}\b",
                citizen_schema_text,
                re.MULTILINE,
            ):
                errors.append(
                    "scripts/citizens/simulation/CityCitizens.gd: missing "
                    f"authoritative citizen schema property {property_name}"
                )
            for path in scripts:
                if path == citizen_schema_path:
                    continue
                text = path.read_text(encoding="utf-8")
                if re.search(
                    rf"^static\s+var\s+{re.escape(property_name)}\b",
                    text,
                    re.MULTILINE,
                ):
                    errors.append(
                        f"{path.relative_to(ROOT)}: citizen name-pool alias "
                        "must not return outside CityCitizens: "
                        f"{property_name}"
                    )

    citizen_api_symbols = moved_world_data_symbols | compatibility_properties
    citizen_api_symbol_alternation = "|".join(
        re.escape(symbol)
        for symbol in sorted(citizen_api_symbols, key=len, reverse=True)
    )

    if world_data_path.exists():
        world_data_text = world_data_path.read_text(encoding="utf-8")
        for symbol in sorted(citizen_api_symbols):
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
                    "scripts/world/simulation/WorldData.gd: moved citizen "
                    f"behavior/property must not return: {symbol}"
                )

    for path in scripts:
        text = path.read_text(encoding="utf-8")
        relative = path.relative_to(ROOT).as_posix()

        direct_symbols = set(
            re.findall(
                rf"\bWorldData\s*\.\s*"
                rf"({citizen_api_symbol_alternation})\b",
                text,
            )
        )
        dynamic_symbols = set(
            re.findall(
                rf"\bWorldData\s*\[\s*[\"']"
                rf"({citizen_api_symbol_alternation})[\"']\s*\]",
                text,
            )
        )
        dynamic_symbols.update(
            re.findall(
                rf"\bWorldData\s*\.\s*"
                rf"(?:get|set|call|callv|call_deferred|has_method)\s*\(\s*"
                rf"[\"']({citizen_api_symbol_alternation})[\"']",
                text,
            )
        )
        dynamic_symbols.update(
            re.findall(
                rf"\bCallable\s*\(\s*WorldData\s*,\s*"
                rf"[\"']({citizen_api_symbol_alternation})[\"']\s*\)",
                text,
            )
        )
        for symbol in sorted(direct_symbols):
            errors.append(
                f"{relative}: legacy WorldData citizen API reference "
                f"remains: WorldData.{symbol}"
            )
        for symbol in sorted(dynamic_symbols):
            errors.append(
                f"{relative}: dynamic legacy WorldData citizen API "
                f"reference remains: {symbol}"
            )

        for domain_name, config in CITIZEN_BEHAVIOR_SYSTEMS.items():
            resolver = str(config["resolver"])
            allowed_resolver_paths = {
                political_state_path,
                citizen_system_paths[domain_name],
                *citizen_state_resolver_bridge_paths,
            }
            if path in allowed_resolver_paths:
                continue

            direct_resolver = re.search(
                rf"\bWorldPoliticalState\s*\.\s*{re.escape(resolver)}"
                rf"\s*\(\s*\)",
                text,
            )
            dynamic_resolver = re.search(
                rf"\bWorldPoliticalState\s*\.\s*"
                rf"(?:call|callv|call_deferred|get|has_method)\s*\(\s*"
                rf"[\"']{re.escape(resolver)}[\"']",
                text,
            )
            callable_resolver = re.search(
                rf"\bCallable\s*\(\s*WorldPoliticalState\s*,\s*"
                rf"[\"']{re.escape(resolver)}[\"']\s*\)",
                text,
            )
            if direct_resolver or dynamic_resolver or callable_resolver:
                errors.append(
                    f"{relative}: {resolver} is private; use "
                    f"{config['class_name']}.get_current_state()"
                )

    renderer_path = ROOT / "scripts/city/rendering/CityRenderer.gd"
    validator_path = ROOT / "scripts/city/simulation/CityStateValidator.gd"
    for consumer_path, consumer_name in (
        (renderer_path, "renderer"),
        (validator_path, "validator"),
    ):
        if not consumer_path.exists():
            continue
        consumer_text = consumer_path.read_text(encoding="utf-8")
        for config in CITIZEN_BEHAVIOR_SYSTEMS.values():
            focused_accessor = f"{config['class_name']}.get_current_state()"
            if focused_accessor not in consumer_text:
                errors.append(
                    f"{consumer_path.relative_to(ROOT)}: citizen {consumer_name} "
                    f"must resolve {config['state_type']} through "
                    f"{focused_accessor}"
                )

    boundary_test_path = (
        ROOT / "scripts/city/simulation/CityCitizenBehaviorApiBoundaryTest.gd"
    )
    boundary_scene_path = boundary_test_path.with_suffix(".tscn")
    for required_path in (boundary_test_path, boundary_scene_path):
        if not required_path.exists():
            errors.append(
                f"{required_path.relative_to(ROOT)}: missing permanent Pass 8 "
                "citizen behavior API boundary coverage"
            )

    # Pass 9: citizen-carried resources and scalar needs remain embedded in the
    # registry-owned citizen Dictionary, while focused stateless systems own all
    # behavior. WorldData compatibility wrappers and cross-system raw writes
    # would recreate split authority, so reject both direct and reflective forms.
    pass9_system_configs = (
        (
            PASS9_CITIZEN_INVENTORY_SYSTEM_PATH,
            "CityCitizenInventorySystem",
            PASS9_CITIZEN_INVENTORY_SYSTEM_FUNCTIONS,
            PASS9_CITIZEN_INVENTORY_PRIMITIVE_MUTATORS,
            True,
        ),
        (
            PASS9_CITIZEN_NEEDS_SYSTEM_PATH,
            "CitizenNeedsSystem",
            PASS9_CITIZEN_NEEDS_SYSTEM_FUNCTIONS,
            PASS9_CITIZEN_NEEDS_PRIMITIVE_MUTATORS,
            True,
        ),
        (
            PASS9_CITIZEN_HAULING_SYSTEM_PATH,
            "CitizenHaulingSystem",
            PASS9_CITIZEN_HAULING_SYSTEM_FUNCTIONS,
            (),
            False,
        ),
    )

    for (
        system_relative,
        class_name,
        required_functions,
        primitive_mutators,
        requires_registry_routing,
    ) in pass9_system_configs:
        system_path = ROOT / system_relative

        if not system_path.exists():
            errors.append(
                f"{system_relative}: missing permanent Pass 9 focused owner"
            )
            continue

        system_text = system_path.read_text(encoding="utf-8")

        if not re.search(
            rf"^class_name\s+{re.escape(class_name)}\s*$",
            system_text,
            re.MULTILINE,
        ):
            errors.append(
                f"{system_relative}: missing {class_name} class_name"
            )

        mutable_top_level_names = re.findall(
            r"^(?:static\s+)?var\s+([A-Za-z_][A-Za-z0-9_]*)\b",
            system_text,
            re.MULTILINE,
        )
        if mutable_top_level_names:
            errors.append(
                f"{system_relative}: Pass 9 focused owner must remain stateless; "
                "top-level mutable fields are forbidden: "
                + ", ".join(sorted(set(mutable_top_level_names)))
            )

        missing_static_functions = [
            function_name
            for function_name in required_functions
            if not re.search(
                rf"^static\s+func\s+{re.escape(function_name)}\s*\(",
                system_text,
                re.MULTILINE,
            )
        ]
        if missing_static_functions:
            errors.append(
                f"{system_relative}: missing focused static citizen behavior: "
                + ", ".join(sorted(missing_static_functions))
            )

        if (
            requires_registry_routing
            and "CityCitizenRegistrySystem.get_current_state()"
            not in system_text
        ):
            errors.append(
                f"{system_relative}: embedded citizen state must route through "
                "CityCitizenRegistrySystem.get_current_state()"
            )

        for function_name in primitive_mutators:
            function_body = gdscript_function_body(system_text, function_name)

            if function_body is None:
                continue
            publication_bodies = [function_body]
            for delegated_name in re.findall(
                r"\b(_[A-Za-z_][A-Za-z0-9_]*)\s*\(", function_body
            ):
                delegated_body = gdscript_function_body(
                    system_text, delegated_name
                )
                if delegated_body is not None:
                    publication_bodies.append(delegated_body)
            publication_text = "\n".join(publication_bodies)
            publication_markers = (
                "CityCitizenRegistrySystem.mark_city_citizens_changed()",
                "registry_state.citizen_version += 1",
                "_mark_city_citizens_changed(",
            )
            if not any(
                marker in publication_text for marker in publication_markers
            ):
                errors.append(
                    f"{system_relative}: primitive mutator {function_name} "
                    "must publish citizen-registry version changes"
                )

    simulation_coordinator_relative = (
        "scripts/world/simulation/SimulationCoordinator.gd"
    )
    simulation_coordinator_path = ROOT / simulation_coordinator_relative
    if simulation_coordinator_path.exists():
        simulation_coordinator_text = simulation_coordinator_path.read_text(
            encoding="utf-8"
        )
        simulation_bootstrap_body = gdscript_function_body(
            simulation_coordinator_text,
            "_run_city_settlement_simulation_systems",
        )
        required_simulation_bootstrap_calls = (
            "CityCitizenInventorySystem.ensure_city_citizen_inventory_state_for_city_state(",
            "CitizenNeedsSystem.ensure_city_citizen_need_state_for_city_state(",
            "CityAssignmentSystem.ensure_city_citizen_assignment_state_for_city_state(",
        )
        if simulation_bootstrap_body is None or any(
            call not in simulation_bootstrap_body
            for call in required_simulation_bootstrap_calls
        ):
            errors.append(
                f"{simulation_coordinator_relative}: headless settlement "
                "simulation must repair embedded inventory/cargo and need state "
                "without a renderer"
            )

        required_explicit_tick_calls = (
            "CitizenNeedsSystem.run_tick_for_city_state(",
            "CityEmploymentSystem.run_tick_for_city_state(",
            "CitizenDecisionSystem.run_tick_for_city_state(",
            "CitizenMovementSystem.run_tick_for_city_state(",
            "CitizenTaskSystem.run_tick_for_city_state(",
            "WorkplaceProductionSystem.run_tick_for_city_state(",
        )
        if simulation_bootstrap_body is None or any(
            call not in simulation_bootstrap_body
            for call in required_explicit_tick_calls
        ):
            errors.append(
                f"{simulation_coordinator_relative}: Pass 4 settlement ticks "
                "must thread one explicit CitySettlementSimulationState through "
                "all six simulation roots"
            )

    pass4_context_relative = (
        "scripts/world/simulation/SettlementSimulationContext.gd"
    )
    pass4_context_path = ROOT / pass4_context_relative
    if (
        not pass4_context_path.exists()
        or "func get_city_simulation_state()" not in pass4_context_path.read_text(
            encoding="utf-8"
        )
    ):
        errors.append(
            f"{pass4_context_relative}: Pass 4 requires an explicit city-state "
            "selection surface"
        )

    pass4_political_relative = (
        "scripts/world/simulation/WorldPoliticalState.gd"
    )
    pass4_political_path = ROOT / pass4_political_relative
    if pass4_political_path.exists():
        pass4_political_text = pass4_political_path.read_text(encoding="utf-8")
        if "func get_settlement_context(settlement_id: int)" not in pass4_political_text:
            errors.append(
                f"{pass4_political_relative}: Pass 4 requires context lookup by "
                "settlement identity without changing presentation selection"
            )
        forbidden_context_stack_tokens = (
            "settlement_simulation_context_stack",
            "begin_settlement_simulation",
            "end_settlement_simulation",
            "get_current_settlement_simulation_context",
        )
        for token in forbidden_context_stack_tokens:
            if token in pass4_political_text:
                errors.append(
                    f"{pass4_political_relative}: Pass 4 forbids hidden global "
                    f"simulation-target routing ({token})"
                )

    for pass4_test_relative in (
        "scripts/world/simulation/ExplicitSettlementSimulationContextTest.gd",
        "scripts/world/simulation/ExplicitSettlementSimulationContextTest.tscn",
    ):
        if not (ROOT / pass4_test_relative).exists():
            errors.append(
                f"{pass4_test_relative}: missing Pass 4 explicit-context "
                "regression coverage"
            )

    pass5_state_relative = (
        "scripts/city/simulation/CitySettlementSimulationState.gd"
    )
    pass5_state_path = ROOT / pass5_state_relative
    if pass5_state_path.exists():
        pass5_state_text = pass5_state_path.read_text(encoding="utf-8")
        for required_method in (
            "func is_city_founded()",
            "func can_build_city_objects()",
            "func get_primary_culture_id()",
            "func has_city_foundation_footprint()",
        ):
            if required_method not in pass5_state_text:
                errors.append(
                    f"{pass5_state_relative}: Pass 5 missing settlement-local "
                    f"gameplay fact reader {required_method}"
                )

    pass5_tick_roots = (
        (
            "scripts/citizens/simulation/systems/CitizenDecisionSystem.gd",
            "run_tick_for_city_state",
        ),
        (
            "scripts/citizens/simulation/systems/CitizenNeedsSystem.gd",
            "_run_tick",
        ),
        (
            "scripts/city/simulation/systems/WorkplaceProductionSystem.gd",
            "run_tick_for_city_state",
        ),
    )
    for pass5_root_relative, function_name in pass5_tick_roots:
        pass5_root_path = ROOT / pass5_root_relative
        if not pass5_root_path.exists():
            continue
        pass5_root_text = pass5_root_path.read_text(encoding="utf-8")
        pass5_root_body = gdscript_function_body(
            pass5_root_text,
            function_name,
        )
        if pass5_root_body is None:
            continue
        for forbidden_global_gate in (
            "WorldData.player_city_founded",
            "WorldData.has_player_city()",
        ):
            if forbidden_global_gate in pass5_root_body:
                errors.append(
                    f"{pass5_root_relative}: Pass 5 explicit target "
                    f"{function_name} must not depend on player-capital gate "
                    f"{forbidden_global_gate}"
                )

    pass5_registry_state_relative = (
        "scripts/city/simulation/CityCitizenRegistryState.gd"
    )
    pass5_registry_state_path = ROOT / pass5_registry_state_relative
    if (
        not pass5_registry_state_path.exists()
        or "var starting_population_initialized: bool = false"
        not in pass5_registry_state_path.read_text(encoding="utf-8")
    ):
        errors.append(
            f"{pass5_registry_state_relative}: Pass 5 requires a durable "
            "settlement-local starting-population completion marker"
        )

    pass5_registry_relative = (
        "scripts/citizens/simulation/systems/CityCitizenRegistrySystem.gd"
    )
    pass5_registry_path = ROOT / pass5_registry_relative
    if pass5_registry_path.exists():
        pass5_registry_text = pass5_registry_path.read_text(encoding="utf-8")
        for required_api in (
            "resolve_city_citizen_culture_id_for_city_state",
            "make_city_citizen_for_city_state",
            "add_city_citizen_for_city_state",
            "initialize_starting_city_population_for_city_state",
        ):
            if not re.search(
                rf"^static\s+func\s+{re.escape(required_api)}\s*\(",
                pass5_registry_text,
                re.MULTILINE,
            ):
                errors.append(
                    f"{pass5_registry_relative}: Pass 5 missing explicit "
                    f"settlement-local citizen API {required_api}"
                )

    pass5_object_relative = (
        "scripts/city/simulation/systems/CityObjectSystem.gd"
    )
    pass5_object_path = ROOT / pass5_object_relative
    if (
        not pass5_object_path.exists()
        or "can_use_city_object_definition_for_city_state"
        not in pass5_object_path.read_text(encoding="utf-8")
    ):
        errors.append(
            f"{pass5_object_relative}: Pass 5 requires explicit local build "
            "eligibility"
        )

    pass5_local_gameplay_files = (
        "scripts/city/rendering/CityRenderer.gd",
        "scripts/ui/city/CityInformationPanel.gd",
        "scripts/city/simulation/systems/CityObjectSystem.gd",
        "scripts/city/simulation/validators/CityObjectStateValidator.gd",
        "scripts/city/simulation/validators/CityCitizenStateValidator.gd",
    )
    for pass5_local_relative in pass5_local_gameplay_files:
        pass5_local_path = ROOT / pass5_local_relative
        if not pass5_local_path.exists():
            continue
        pass5_local_text = pass5_local_path.read_text(encoding="utf-8")
        for forbidden_player_fact in (
            "WorldData.player_city_founded",
            "WorldData.has_player_city()",
            "WorldData.has_player_city_foundation()",
            "WorldData.can_build_in_city()",
        ):
            if forbidden_player_fact in pass5_local_text:
                errors.append(
                    f"{pass5_local_relative}: Pass 5 settlement-local gameplay "
                    f"must not use player-capital fact {forbidden_player_fact}"
                )

    if pass4_political_path.exists():
        pass5_political_text = pass4_political_path.read_text(encoding="utf-8")
        if "func found_city_settlement(" not in pass5_political_text:
            errors.append(
                f"{pass4_political_relative}: Pass 5 requires target-specific "
                "settlement foundation"
            )
        if '"is_player_polity": polity_id == player_polity_id' not in pass5_political_text:
            errors.append(
                f"{pass4_political_relative}: Pass 5 settlement contexts must "
                "distinguish a polity capital from the player capital"
            )
        active_context_body = gdscript_function_body(
            pass5_political_text,
            "get_active_settlement_context",
        )
        if (
            active_context_body is not None
            and "synchronize_foundation_with_world_data" in active_context_body
        ):
            errors.append(
                f"{pass4_political_relative}: Pass 5 active-context lookup "
                "must not trigger player-foundation synchronization"
            )

    pass5_world_data_relative = "scripts/world/simulation/WorldData.gd"
    pass5_world_data_path = ROOT / pass5_world_data_relative
    if pass5_world_data_path.exists():
        pass5_world_data_text = pass5_world_data_path.read_text(encoding="utf-8")
        player_foundation_body = gdscript_function_body(
            pass5_world_data_text,
            "found_player_city",
        )
        if (
            player_foundation_body is None
            or "WorldPoliticalState.found_city_settlement(" not in player_foundation_body
            or "WorldPoliticalState.replace_current_city_runtime_data(" in player_foundation_body
        ):
            errors.append(
                f"{pass5_world_data_relative}: Pass 5 player founding must "
                "delegate to the exact player-capital settlement transaction"
            )

    for pass5_test_relative in (
        "scripts/world/simulation/SettlementLocalGameplayTest.gd",
        "scripts/world/simulation/SettlementLocalGameplayTest.tscn",
    ):
        if not (ROOT / pass5_test_relative).exists():
            errors.append(
                f"{pass5_test_relative}: missing Pass 5 settlement-local "
                "gameplay regression coverage"
            )

    # Pass 6: the current employment framework is automatic-only. Staffing
    # follows each workplace's hard capacity, explicit settlement APIs reject
    # cross-owner IDs without mutation, and job repair retires obsolete Work
    # tasks/movement after committing the canonical relationship change.
    pass6_employment_relative = (
        "scripts/citizens/simulation/systems/CityEmploymentSystem.gd"
    )
    pass6_employment_path = ROOT / pass6_employment_relative
    if pass6_employment_path.exists():
        pass6_employment_text = pass6_employment_path.read_text(encoding="utf-8")
        pass6_required_employment_apis = (
            "run_tick_for_city_state",
            "reconcile_automatic_workplaces_for_city_state",
            "assign_citizen_to_workplace_for_city_state",
            "remove_citizen_job_for_city_state",
            "set_workplace_desired_worker_count_for_city_state",
        )
        for required_api in pass6_required_employment_apis:
            if not re.search(
                rf"^static\s+func\s+{re.escape(required_api)}\s*\(",
                pass6_employment_text,
                re.MULTILINE,
            ):
                errors.append(
                    f"{pass6_employment_relative}: Pass 6 missing explicit "
                    f"settlement employment API {required_api}"
                )

        valid_mode_body = gdscript_function_body(
            pass6_employment_text,
            "is_valid_staffing_mode",
        )
        if (
            valid_mode_body is None
            or "STAFFING_MODE_AUTOMATIC" not in valid_mode_body
            or "STAFFING_MODE_MANUAL" in valid_mode_body
        ):
            errors.append(
                f"{pass6_employment_relative}: Pass 6 gameplay staffing must "
                "remain automatic-only"
            )

        staffing_normalization_body = gdscript_function_body(
            pass6_employment_text,
            "_ensure_workplace_staffing_state",
        )
        if (
            staffing_normalization_body is None
            or "STAFFING_MODE_AUTOMATIC" not in staffing_normalization_body
            or "worker_capacity" not in staffing_normalization_body
        ):
            errors.append(
                f"{pass6_employment_relative}: Pass 6 workplace normalization "
                "must target current hard capacity"
            )

        reconciliation_body = gdscript_function_body(
            pass6_employment_text,
            "_reconcile_automatic_workplaces",
        )
        if (
            reconciliation_body is None
            or "worker_ids.pop_back()" not in reconciliation_body
            or "remove_city_citizen_job_for_city_state(" not in reconciliation_body
        ):
            errors.append(
                f"{pass6_employment_relative}: Pass 6 automatic reconciliation "
                "must deterministically trim surplus workers before refill"
            )

    pass6_assignment_relative = (
        "scripts/citizens/simulation/systems/CityAssignmentSystem.gd"
    )
    pass6_assignment_path = ROOT / pass6_assignment_relative
    if pass6_assignment_path.exists():
        pass6_assignment_text = pass6_assignment_path.read_text(encoding="utf-8")
        assignment_repair_body = gdscript_function_body(
            pass6_assignment_text,
            "_ensure_city_citizen_assignment_state",
        )
        assignment_mutation_body = gdscript_function_body(
            pass6_assignment_text,
            "_assign_city_citizen_job",
        )
        if (
            assignment_repair_body is None
            or "clear_return_home_task" not in assignment_repair_body
            or "clear_work_task" not in assignment_repair_body
            or "registry_state.citizens[citizen_index] = citizen"
            not in assignment_repair_body
        ):
            errors.append(
                f"{pass6_assignment_relative}: Pass 6 relationship repair must "
                "commit canonical links before clearing obsolete behavior"
            )
        if (
            assignment_mutation_body is None
            or assignment_mutation_body.count(
                "_clear_city_citizen_work_task_after_job_change("
            ) < 2
        ):
            errors.append(
                f"{pass6_assignment_relative}: Pass 6 job reassignment must "
                "retire stale Work tasks and movement"
            )

    pass6_decision_relative = (
        "scripts/citizens/simulation/systems/CitizenDecisionSystem.gd"
    )
    pass6_decision_path = ROOT / pass6_decision_relative
    if pass6_decision_path.exists():
        pass6_decision_text = pass6_decision_path.read_text(encoding="utf-8")
        autonomous_haul_body = gdscript_function_body(
            pass6_decision_text,
            "_process_bounded_autonomous_hauling_for_city_state",
        )
        decision_queue_body = gdscript_function_body(
            pass6_decision_text,
            "_process_decision_queue_for_city_state",
        )
        if (
            not re.search(
                r"^static\s+func\s+"
                r"_process_bounded_autonomous_hauling_for_city_state\s*\("
                r"[\s\S]*?\)\s*->\s*bool\s*:",
                pass6_decision_text,
                re.MULTILINE,
            )
            or autonomous_haul_body is None
            or "MAX_AUTONOMOUS_HAUL_ASSIGNMENTS_PER_TICK" not in autonomous_haul_body
            or decision_queue_body is None
            or "employed_only" not in decision_queue_body
            or "_has_unassigned_autonomous_haul_work_for_city_state" in pass6_decision_text
        ):
            errors.append(
                f"{pass6_decision_relative}: Pass 6 Return Home deferral must "
                "depend on real bounded haul assignments, not opportunities alone"
            )

    pass6_test_contracts = {
        "scripts/city/simulation/CityAssignmentSystemTest.gd": (
            "_test_automatic_staffing_capacity_and_task_cleanup",
        ),
        "scripts/city/simulation/CityEmploymentFoodDeadlockTest.gd": (
            "_test_off_shift_home_queue_survives_unassignable_haul_work",
            "_test_persistent_workplace_staffing_policy",
        ),
        "scripts/world/simulation/CityEmploymentLifecycleTest.gd": (
            "_test_settlement_local_employment_lifecycle",
            "_test_multi_day_fishery_employment",
        ),
    }
    for pass6_test_relative, required_functions in pass6_test_contracts.items():
        pass6_test_path = ROOT / pass6_test_relative
        pass6_scene_path = pass6_test_path.with_suffix(".tscn")
        for required_path in (pass6_test_path, pass6_scene_path):
            if not required_path.exists():
                errors.append(
                    f"{required_path.relative_to(ROOT)}: missing permanent "
                    "Pass 6 employment regression coverage"
                )
        if not pass6_test_path.exists():
            continue
        pass6_test_text = pass6_test_path.read_text(encoding="utf-8")
        for required_function in required_functions:
            if not re.search(
                rf"^func\s+{re.escape(required_function)}\s*\(",
                pass6_test_text,
                re.MULTILINE,
            ):
                errors.append(
                    f"{pass6_test_relative}: missing Pass 6 regression "
                    f"{required_function}"
                )

    # Pass 7: Logistics is the sole owner of ground-pile release mutation.
    # Construction may retire its own tasks/commands, but material conversion,
    # reservation cleanup, radius/capacity coalescing, indices, and publication
    # must remain behind explicit public Logistics operations.
    pass7_logistics_relative = (
        "scripts/city/simulation/systems/CityLogisticsSystem.gd"
    )
    pass7_construction_relative = (
        "scripts/city/simulation/systems/CityConstructionSystem.gd"
    )
    pass7_logistics_path = ROOT / pass7_logistics_relative
    pass7_construction_path = ROOT / pass7_construction_relative
    if pass7_logistics_path.exists():
        pass7_logistics_text = pass7_logistics_path.read_text(encoding="utf-8")
        for required_api in (
            "release_city_construction_site_materials",
            "release_city_construction_site_materials_for_city_state",
        ):
            if not re.search(
                rf"^static\s+func\s+{re.escape(required_api)}\s*\(",
                pass7_logistics_text,
                re.MULTILINE,
            ):
                errors.append(
                    f"{pass7_logistics_relative}: Pass 7 missing public "
                    f"Logistics owner API {required_api}"
                )

        pass7_release_body = gdscript_function_body(
            pass7_logistics_text,
            "_release_construction_site_materials",
        )
        if (
            pass7_release_body is None
            or "_release_construction_material_reservations(" not in pass7_release_body
            or "_coalesce_released_construction_piles(" not in pass7_release_body
            or "_rebuild_city_ground_pile_index_for_state(" not in pass7_release_body
            or "ground_pile_version += 1" not in pass7_release_body
        ):
            errors.append(
                f"{pass7_logistics_relative}: Pass 7 release must own "
                "reservation cleanup, local coalescing, index rebuild, and "
                "ground-pile publication"
            )

        for constant_name, expected_value in (
            ("CITY_GROUND_PILE_CAPACITY", "20"),
            ("CITY_GROUND_PILE_MERGE_RADIUS_TILES", "2"),
        ):
            if not re.search(
                rf"^const\s+{constant_name}\s*:\s*int\s*=\s*"
                rf"{expected_value}\s*$",
                pass7_logistics_text,
                re.MULTILINE,
            ):
                errors.append(
                    f"{pass7_logistics_relative}: Pass 7 must preserve "
                    f"{constant_name} = {expected_value}"
                )

    if pass7_construction_path.exists():
        pass7_construction_text = pass7_construction_path.read_text(
            encoding="utf-8"
        )
        pass7_cancel_body = gdscript_function_body(
            pass7_construction_text,
            "_cancel_city_construction_site",
        )
        if (
            pass7_cancel_body is None
            or "release_city_construction_site_materials(" not in pass7_cancel_body
            or "release_city_construction_site_materials_for_city_state("
            not in pass7_cancel_body
        ):
            errors.append(
                f"{pass7_construction_relative}: Pass 7 cancellation must "
                "delegate material release to public Logistics APIs"
            )

        forbidden_pass7_construction_patterns = (
            r"^static\s+func\s+release_city_construction_site_materials\s*\(",
            r"^static\s+func\s+_coalesce_ordinary_city_ground_piles\s*\(",
            r"CityLogisticsSystem\._[A-Za-z0-9_]+\s*\(",
            r"(?:get_current_state\(\)|logistics_state)\.ground_piles\s*"
            r"\[[^\]]+\]\s*=",
            r"(?:get_current_state\(\)|logistics_state)\.ground_piles\."
            r"(?:append|remove_at|clear)\s*\(",
        )
        for pattern in forbidden_pass7_construction_patterns:
            if re.search(pattern, pass7_construction_text, re.MULTILINE):
                errors.append(
                    f"{pass7_construction_relative}: Pass 7 forbids direct "
                    "Logistics ground-pile mutation or private API use"
                )
                break

    pass7_test_relative = (
        "scripts/city/simulation/CityConstructionCancellationLogisticsTest.gd"
    )
    pass7_test_path = ROOT / pass7_test_relative
    pass7_scene_path = pass7_test_path.with_suffix(".tscn")
    for required_path in (pass7_test_path, pass7_scene_path):
        if not required_path.exists():
            errors.append(
                f"{required_path.relative_to(ROOT)}: missing permanent "
                "Pass 7 construction/logistics regression coverage"
            )
    if pass7_test_path.exists():
        pass7_test_text = pass7_test_path.read_text(encoding="utf-8")
        for required_function in (
            "_test_partial_cancellation_releases_materials_and_reservations_once",
            "_test_full_cancellation_preserves_radius_capacity_and_local_overflow",
            "_test_explicit_release_preserves_active_settlement_and_ordinary_ids",
        ):
            if not re.search(
                rf"^func\s+{re.escape(required_function)}\s*\(",
                pass7_test_text,
                re.MULTILINE,
            ):
                errors.append(
                    f"{pass7_test_relative}: missing Pass 7 regression "
                    f"{required_function}"
                )

    # Post-Scripts10 PR 8: mutable tile/object state stays behind focused owner
    # APIs. Public tile reads are detached, allocation-free internal reads are
    # read-only, catalog/object records are recursively immutable, and the
    # focused regressions make those boundaries permanent.
    pr8_world_relative = "scripts/world/simulation/WorldData.gd"
    pr8_world_path = ROOT / pr8_world_relative
    if not pr8_world_path.exists():
        errors.append(f"{pr8_world_relative}: missing PR 8 tile owner")
    else:
        pr8_world_text = pr8_world_path.read_text(encoding="utf-8")
        pr8_world_functions = {
            match.group(1) for match in FUNC_RE.finditer(pr8_world_text)
        }
        for required_api in (
            "get_tile",
            "get_tile_for_internal_read",
            "set_tile",
            "set_tile_terrain",
            "set_tile_resource_value",
            "set_tile_surface_feature",
            "remove_tile_surface_feature",
        ):
            if required_api not in pr8_world_functions:
                errors.append(
                    f"{pr8_world_relative}: PR 8 missing tile boundary API "
                    f"{required_api}"
                )

        pr8_public_tile_body = gdscript_function_body(
            pr8_world_text,
            "get_tile",
        ) or ""
        if (
            "get_tile_for_internal_read(" not in pr8_public_tile_body
            or ".duplicate(true)" not in pr8_public_tile_body
        ):
            errors.append(
                f"{pr8_world_relative}: PR 8 public get_tile must return a "
                "recursively detached snapshot"
            )

        pr8_set_tile_body = gdscript_function_body(
            pr8_world_text,
            "set_tile",
        ) or ""
        if (
            "data.duplicate(true)" not in pr8_set_tile_body
            or "tiles[y][x] == replacement_tile" not in pr8_set_tile_body
            or "mark_tile_data_changed()" not in pr8_set_tile_body
        ):
            errors.append(
                f"{pr8_world_relative}: PR 8 set_tile must detach input, "
                "short-circuit equality, and publish broad invalidation"
            )

        for focused_api in (
            "set_tile_terrain",
            "set_tile_resource_value",
        ):
            focused_body = gdscript_function_body(
                pr8_world_text,
                focused_api,
            ) or ""
            if "return set_tile(" not in focused_body:
                errors.append(
                    f"{pr8_world_relative}: PR 8 {focused_api} must route its "
                    "write through set_tile"
                )

        pr8_feature_set_body = gdscript_function_body(
            pr8_world_text,
            "set_tile_surface_feature",
        ) or ""
        pr8_feature_remove_body = gdscript_function_body(
            pr8_world_text,
            "remove_tile_surface_feature",
        ) or ""
        if (
            "mark_city_surface_feature_changed(" not in pr8_feature_set_body
            or "mark_tile_data_changed()" in pr8_feature_set_body
            or "return set_tile_surface_feature(" not in pr8_feature_remove_body
        ):
            errors.append(
                f"{pr8_world_relative}: PR 8 surface-feature writes must use "
                "focused publication and compare-aware owner removal"
            )

        pr8_clear_features_body = gdscript_function_body(
            pr8_world_text,
            "clear_city_surface_features_at_tiles",
        ) or ""
        if "remove_tile_surface_feature(" not in pr8_clear_features_body:
            errors.append(
                f"{pr8_world_relative}: PR 8 bulk feature clearing must route "
                "through the WorldData owner API"
            )

    pr8_work_relative = (
        "scripts/city/simulation/systems/CityWorkSystem.gd"
    )
    pr8_work_path = ROOT / pr8_work_relative
    if pr8_work_path.exists():
        pr8_work_text = pr8_work_path.read_text(encoding="utf-8")
        for completion_function in (
            "complete_city_player_command",
            "complete_city_player_command_for_city_state",
        ):
            completion_body = gdscript_function_body(
                pr8_work_text,
                completion_function,
            ) or ""
            if (
                "remove_tile_surface_feature(" not in completion_body
                or "set_tile_surface_feature(" not in completion_body
            ):
                errors.append(
                    f"{pr8_work_relative}: PR 8 {completion_function} must use "
                    "owner remove/restore APIs"
                )

    pr8_catalog_relative = "scripts/city/data/CityObjectCatalog.gd"
    pr8_catalog_path = ROOT / pr8_catalog_relative
    if not pr8_catalog_path.exists():
        errors.append(f"{pr8_catalog_relative}: missing PR 8 immutable catalog")
    else:
        pr8_catalog_text = pr8_catalog_path.read_text(encoding="utf-8")
        pr8_catalog_freeze_body = gdscript_function_body(
            pr8_catalog_text,
            "_make_variant_read_only_recursive",
        ) or ""
        pr8_catalog_setup_body = gdscript_function_body(
            pr8_catalog_text,
            "_setup_city_object_definitions",
        ) or ""
        pr8_catalog_view_body = gdscript_function_body(
            pr8_catalog_text,
            "get_city_object_definitions",
        ) or ""
        if any(
            token not in pr8_catalog_freeze_body
            for token in (
                "dictionary.make_read_only()",
                "array.make_read_only()",
                "_make_variant_read_only_recursive(",
            )
        ):
            errors.append(
                f"{pr8_catalog_relative}: PR 8 catalog values must be frozen "
                "recursively"
            )
        if pr8_catalog_setup_body.count(
            "_make_variant_read_only_recursive("
        ) < 2:
            errors.append(
                f"{pr8_catalog_relative}: PR 8 setup must freeze definitions "
                "and derived resource lookups"
            )
        if "return _city_object_definitions.duplicate()" not in pr8_catalog_view_body:
            errors.append(
                f"{pr8_catalog_relative}: PR 8 definitions lookup must return "
                "a shallow outer copy over immutable records"
            )

    pr8_object_relative = (
        "scripts/city/simulation/systems/CityObjectSystem.gd"
    )
    pr8_object_path = ROOT / pr8_object_relative
    if not pr8_object_path.exists():
        errors.append(f"{pr8_object_relative}: missing PR 8 object owner")
    else:
        pr8_object_text = pr8_object_path.read_text(encoding="utf-8")
        pr8_object_functions = {
            match.group(1) for match in FUNC_RE.finditer(pr8_object_text)
        }
        for required_api in (
            "get_city_objects",
            "get_city_objects_for_city_state",
            "get_city_object_by_id",
            "get_city_object_by_id_for_city_state",
            "get_city_object_at_tile",
            "get_city_object_at_tile_for_city_state",
            "patch_city_object_assignment_fields",
            "patch_city_object_assignment_fields_for_city_state",
            "patch_city_object_workplace_fields",
            "patch_city_object_workplace_fields_for_city_state",
            "patch_city_object_storage_fields",
            "patch_city_object_storage_fields_for_city_state",
            "write_city_object_at_index",
            "write_city_object_at_index_for_city_state",
        ):
            if required_api not in pr8_object_functions:
                errors.append(
                    f"{pr8_object_relative}: PR 8 missing immutable/COW object "
                    f"boundary {required_api}"
                )

        pr8_record_freeze_body = gdscript_function_body(
            pr8_object_text,
            "_make_read_only_city_object_record",
        ) or ""
        pr8_object_recursive_freeze_body = gdscript_function_body(
            pr8_object_text,
            "_make_variant_read_only_recursive",
        ) or ""
        pr8_patch_body = gdscript_function_body(
            pr8_object_text,
            "_patch_city_object_fields_at_index",
        ) or ""
        pr8_compatibility_body = gdscript_function_body(
            pr8_object_text,
            "_write_compatible_city_object_record",
        ) or ""
        if (
            "city_object.duplicate(true)" not in pr8_record_freeze_body
            or "_make_variant_read_only_recursive(" not in pr8_record_freeze_body
            or "dictionary.make_read_only()"
            not in pr8_object_recursive_freeze_body
            or "array.make_read_only()" not in pr8_object_recursive_freeze_body
            or "existing.duplicate(true)" not in pr8_patch_body
            or "_make_read_only_city_object_record(updated)" not in pr8_patch_body
        ):
            errors.append(
                f"{pr8_object_relative}: PR 8 object commits must be detached, "
                "copy-on-write, and recursively read-only"
            )
        if any(
            token not in pr8_compatibility_body
            for token in (
                "_get_city_object_changed_fields(",
                "field_domain.is_empty()",
                "mutation_domain != field_domain",
                "_patch_city_object_fields_at_index(",
            )
        ):
            errors.append(
                f"{pr8_object_relative}: PR 8 compatibility writes must reject "
                "topology/unknown and cross-domain record replacement"
            )
        for registry_function in (
            "get_city_objects",
            "get_city_objects_for_city_state",
        ):
            registry_body = gdscript_function_body(
                pr8_object_text,
                registry_function,
            ) or ""
            if (
                "_ensure_city_object_records_are_read_only(" not in registry_body
                or ".objects.duplicate()" not in registry_body
            ):
                errors.append(
                    f"{pr8_object_relative}: PR 8 {registry_function} must "
                    "return a shallow outer copy over read-only records"
                )
        for by_id_function in (
            "get_city_object_by_id",
            "get_city_object_by_id_for_city_state",
        ):
            by_id_body = gdscript_function_body(
                pr8_object_text,
                by_id_function,
            ) or ""
            if "_ensure_city_object_record_is_read_only(" not in by_id_body:
                errors.append(
                    f"{pr8_object_relative}: PR 8 {by_id_function} must return "
                    "the authoritative recursively read-only record"
                )
        for at_tile_function, required_reader in (
            ("get_city_object_at_tile", "get_city_object_by_id("),
            (
                "get_city_object_at_tile_for_city_state",
                "get_city_object_by_id_for_city_state(",
            ),
        ):
            at_tile_body = gdscript_function_body(
                pr8_object_text,
                at_tile_function,
            ) or ""
            if required_reader not in at_tile_body:
                errors.append(
                    f"{pr8_object_relative}: PR 8 {at_tile_function} must "
                    "delegate to the read-only by-ID boundary"
                )
        if pr8_object_text.count(
            "var stored_city_object := _make_read_only_city_object_record(city_object)"
        ) < 2:
            errors.append(
                f"{pr8_object_relative}: PR 8 active and explicit registration "
                "must publish recursively read-only records"
            )

    pr8_focused_owner_contracts = (
        (
            "scripts/citizens/simulation/systems/CityAssignmentSystem.gd",
            "_set_city_object_resident_capacity",
            (
                "patch_city_object_assignment_fields(",
                "patch_city_object_assignment_fields_for_city_state(",
            ),
        ),
        (
            "scripts/citizens/simulation/systems/CityEmploymentSystem.gd",
            "_set_city_workplace_worker_capacity",
            (
                "patch_city_object_workplace_fields(",
                "patch_city_object_workplace_fields_for_city_state(",
            ),
        ),
        (
            "scripts/city/simulation/systems/CityResourceContainerSystem.gd",
            "",
            (
                "patch_city_object_storage_fields(",
                "patch_city_object_storage_fields_for_city_state(",
            ),
        ),
    )
    for owner_relative, owner_function, required_calls in pr8_focused_owner_contracts:
        owner_path = ROOT / owner_relative
        if not owner_path.exists():
            continue
        owner_text = owner_path.read_text(encoding="utf-8")
        owner_scope = (
            gdscript_function_body(owner_text, owner_function) or ""
            if owner_function
            else owner_text
        )
        if any(call not in owner_scope for call in required_calls):
            errors.append(
                f"{owner_relative}: PR 8 focused owner routing is incomplete"
            )

    pr8_tile_owner_write_paths = {
        "scripts/world/simulation/WorldData.gd",
        "scripts/world/generation/WorldGenerator.gd",
        "scripts/city/generation/CityWorldGenerator.gd",
    }
    pr8_assignment_operator = r"(?:\+=|-=|\*=|/=|(?<![=!<>])=(?!=))"
    pr8_mutating_method = r"(?:erase|clear|merge|assign|append|remove_at|set)"

    def pr8_alias_is_mutated(function_body: str, alias: str) -> bool:
        mutation_pattern = re.compile(
            rf"^\s*{re.escape(alias)}\s*(?:"
            rf"\[[^\n]+\]\s*{pr8_assignment_operator}|"
            rf"\.{pr8_mutating_method}\s*\()",
            re.MULTILINE,
        )
        return mutation_pattern.search(function_body) is not None

    for path in scripts:
        relative = path.relative_to(ROOT).as_posix()
        if relative.endswith("Test.gd"):
            continue
        text = path.read_text(encoding="utf-8")
        masked_text = gdscript_masked_code(text)

        if relative not in pr8_tile_owner_write_paths:
            if re.search(
                rf"\.tiles\s*\[[^\n]+\]\s*{pr8_assignment_operator}",
                masked_text,
            ):
                errors.append(
                    f"{relative}: PR 8 forbids direct runtime tiles writes "
                    "outside WorldData and the two generators"
                )

        if (
            relative != pr8_object_relative
            and re.search(
                r"\bCityObjectSystem\.write_city_object_at_index"
                r"(?:_for_city_state)?\s*\(",
                masked_text,
            )
        ):
            errors.append(
                f"{relative}: PR 8 forbids external generic city-object record "
                "replacement; use a focused owner API"
            )

        for function_name in set(FUNC_RE.findall(text)):
            raw_body = gdscript_function_body(text, function_name) or ""
            masked_body = gdscript_masked_code(raw_body)

            if relative not in pr8_tile_owner_write_paths:
                tile_alias_pattern = re.compile(
                    r"^\s*(?:var\s+)?(?P<alias>[A-Za-z_]\w*)"
                    r"(?:\s*:\s*[^=:\n]+)?\s*(?::=|=)\s*[^\n]*"
                    r"\.tiles\s*\[",
                    re.MULTILINE,
                )
                if any(
                    pr8_alias_is_mutated(masked_body, match.group("alias"))
                    for match in tile_alias_pattern.finditer(masked_body)
                ):
                    errors.append(
                        f"{relative}: PR 8 forbids aliased runtime tiles "
                        f"mutation in {function_name}"
                    )

            for accessor in ("get_tile", "get_tile_for_internal_read"):
                accessor_alias_pattern = re.compile(
                    r"^\s*(?:var\s+)?(?P<alias>[A-Za-z_]\w*)"
                    r"(?:\s*:\s*[^=:\n]+)?\s*(?::=|=)\s*[^\n]*\b"
                    + re.escape(accessor)
                    + r"\s*\(",
                    re.MULTILINE,
                )
                mutated_aliases = [
                    match.group("alias")
                    for match in accessor_alias_pattern.finditer(masked_body)
                    if pr8_alias_is_mutated(
                        masked_body,
                        match.group("alias"),
                    )
                ]
                direct_mutation_pattern = re.compile(
                    rf"\b{re.escape(accessor)}\s*\([^\n]*\)\s*(?:"
                    rf"\[[^\n]+\]\s*{pr8_assignment_operator}|"
                    rf"\.{pr8_mutating_method}\s*\()"
                )
                if mutated_aliases or direct_mutation_pattern.search(masked_body):
                    errors.append(
                        f"{relative}: PR 8 forbids production {accessor} "
                        f"reference mutation in {function_name}"
                    )

    pr8_test_contracts = (
        (
            "scripts/city/simulation/CityWorldDataBoundaryTest.gd",
            "_ready",
            "_test_tile_owner_mutation_boundary",
            (
                "set_tile(",
                "set_tile_terrain(",
                "set_tile_resource_value(",
                "set_tile_surface_feature(",
                "remove_tile_surface_feature(",
                "prepared_city_feature_tile_data_version",
            ),
        ),
        (
            "scripts/city/simulation/CityWorldDataBoundaryTest.gd",
            "_ready",
            "_test_catalog_recursive_readonly_boundary",
            ("get_city_object_definitions(", "is_read_only()"),
        ),
        (
            "scripts/city/simulation/CityWorldDataBoundaryTest.gd",
            "_ready",
            "_test_environmental_resource_cache_invalidation",
            (
                "get_resource_source_evaluation(",
                "set_tile_resource_value(",
            ),
        ),
        (
            "scripts/city/simulation/CityObjectSystemTest.gd",
            "_ready",
            "_test_snapshots_do_not_alias_authoritative_state",
            (
                "get_city_objects(",
                "get_city_objects_for_city_state(",
                "get_city_object_at_tile_for_city_state(",
                "is_read_only()",
                "write_city_object_at_index(",
                "write_city_object_at_index_for_city_state(",
                "add_resource_to_city_object_storage(",
            ),
        ),
        (
            "scripts/city/rendering/CityRendererRefactorSmokeTest.gd",
            "_run_smoke_test",
            "_test_city_natural_features",
            (
                "remove_tile_surface_feature(",
                "set_tile_surface_feature(",
                "session_prepared_city_payload",
                "city_surface_feature_change_version",
                "rebuild_city_natural_feature_multimeshes()",
            ),
        ),
    )
    for test_relative, caller_name, test_name, required_tokens in pr8_test_contracts:
        test_path = ROOT / test_relative
        if not test_path.exists():
            errors.append(
                f"{test_relative}: missing permanent PR 8 regression coverage"
            )
            continue
        test_text = test_path.read_text(encoding="utf-8")
        test_body = gdscript_function_body(test_text, test_name)
        caller_body = gdscript_masked_code(
            gdscript_function_body(test_text, caller_name) or ""
        )
        if test_body is None:
            errors.append(
                f"{test_relative}: missing permanent PR 8 regression {test_name}"
            )
            continue
        if not re.search(
            rf"^\s*{re.escape(test_name)}\s*\(",
            caller_body,
            re.MULTILINE,
        ):
            errors.append(
                f"{test_relative}: PR 8 regression is not invoked by "
                f"{caller_name}: {test_name}"
            )
        if any(token not in test_body for token in required_tokens):
            errors.append(
                f"{test_relative}: PR 8 regression is missing a required "
                f"boundary assertion: {test_name}"
            )

    # Post-Scripts10 PR 9: detailed settlement switching is one presentation
    # transaction. GameSession alone selects the target; CityRenderer clears
    # settlement-bound interaction state and rebuilds every retained cache
    # without resetting either settlement's gameplay owners.
    pr9_session_relative = "scripts/session/GameSession.gd"
    pr9_renderer_relative = "scripts/city/rendering/CityRenderer.gd"
    pr9_test_relative = "scripts/session/SettlementPresentationRebindTest.gd"
    pr9_scene_relative = "scripts/session/SettlementPresentationRebindTest.tscn"
    pr9_session_path = ROOT / pr9_session_relative
    pr9_renderer_path = ROOT / pr9_renderer_relative
    pr9_test_path = ROOT / pr9_test_relative
    pr9_scene_path = ROOT / pr9_scene_relative

    if not pr9_session_path.exists():
        errors.append(f"{pr9_session_relative}: missing PR 9 presentation owner")
    else:
        pr9_session_text = pr9_session_path.read_text(encoding="utf-8")
        pr9_switch_body = gdscript_function_body(
            pr9_session_text,
            "show_settlement_city_view",
        ) or ""
        for required_token in (
            "cancel_city_preparation()",
            "SimulationClock.set_simulation_paused(true)",
            "WorldPoliticalState.set_active_settlement(settlement_id)",
            '"rebind_city_presentation"',
            '"validate_city_presentation_binding"',
            "SimulationClock.set_speed_multiplier(simulation_speed_before)",
            "SimulationClock.set_simulation_paused(simulation_was_paused)",
        ):
            if required_token not in pr9_switch_body:
                errors.append(
                    f"{pr9_session_relative}: PR 9 settlement switch is missing "
                    f"transaction step {required_token}"
                )
        for forbidden_reset in (
            "reset_runtime_session_state(",
            "reset_city_simulation_runtime_state(",
            "reset_player_city_state(",
        ):
            if forbidden_reset in pr9_switch_body:
                errors.append(
                    f"{pr9_session_relative}: PR 9 presentation switching must "
                    f"not invoke gameplay reset {forbidden_reset}"
                )

    if not pr9_renderer_path.exists():
        errors.append(f"{pr9_renderer_relative}: missing PR 9 renderer rebind")
    else:
        pr9_renderer_text = pr9_renderer_path.read_text(encoding="utf-8")
        pr9_renderer_functions = {
            match.group(1) for match in FUNC_RE.finditer(pr9_renderer_text)
        }
        for required_api in (
            "can_rebind_city_presentation",
            "rebind_city_presentation",
            "validate_city_presentation_binding",
            "_clear_city_presentation_interactions",
            "_reset_city_presentation_observers",
            "_capture_bound_city_presentation_versions",
            "_configure_city_camera_for_bound_settlement",
            "_finish_city_presentation_rebind",
        ):
            if required_api not in pr9_renderer_functions:
                errors.append(
                    f"{pr9_renderer_relative}: PR 9 missing presentation rebind "
                    f"boundary {required_api}"
                )

        pr9_rebind_body = gdscript_function_body(
            pr9_renderer_text,
            "rebind_city_presentation",
        ) or ""
        for required_token in (
            "_set_city_render_layers_visible(false)",
            "_clear_city_presentation_interactions()",
            "_reset_city_presentation_observers()",
            "workplace_zone_overlay_cache.invalidate_all()",
            "city_citizen_movement_presentation.initialize()",
            "rebuild_city_terrain_texture()",
            "rebuild_city_natural_feature_multimeshes()",
            "_configure_city_camera_for_bound_settlement()",
            "_capture_bound_city_presentation_versions(target_state)",
            "city_information_ui.refresh_all()",
            "_request_all_city_render_layers_redraw_even_if_hidden()",
        ):
            if required_token not in pr9_rebind_body:
                errors.append(
                    f"{pr9_renderer_relative}: PR 9 renderer rebind is missing "
                    f"presentation step {required_token}"
                )
        if "WorldPoliticalState.set_active_settlement(" in pr9_renderer_text:
            errors.append(
                f"{pr9_renderer_relative}: PR 9 renderer must not select its own "
                "settlement; GameSession owns the transaction"
            )
        for forbidden_reset in (
            "reset_runtime_session_state(",
            "reset_city_simulation_runtime_state(",
            "reset_player_city_state(",
        ):
            if forbidden_reset in pr9_rebind_body:
                errors.append(
                    f"{pr9_renderer_relative}: PR 9 rebind must not invoke "
                    f"gameplay reset {forbidden_reset}"
                )

    for required_path in (pr9_test_path, pr9_scene_path):
        if not required_path.exists():
            errors.append(
                f"{required_path.relative_to(ROOT)}: missing permanent PR 9 "
                "A/B/A presentation regression"
            )
    if pr9_test_path.exists():
        pr9_test_text = pr9_test_path.read_text(encoding="utf-8")
        pr9_ready_body = gdscript_function_body(pr9_test_text, "_ready") or ""
        pr9_test_name = "_test_atomic_settlement_presentation_rebind"
        pr9_test_body = gdscript_function_body(
            pr9_test_text,
            pr9_test_name,
        ) or ""
        if pr9_test_name + "()" not in pr9_ready_body:
            errors.append(
                f"{pr9_test_relative}: PR 9 A/B/A regression is not invoked"
            )
        for required_token in (
            "show_settlement_city_view(city_b_id)",
            "show_settlement_city_view(city_a_id)",
            "city_tree_multimesh_index_by_tile",
            "city_rock_multimesh_index_by_tile",
            "city_information_ui.city_name_label.text",
            "city_presentation_rebind_pending",
            "_capture_gameplay_snapshot(state_a)",
            "_capture_gameplay_snapshot(state_b)",
            "_gameplay_identities_match(state_a",
            "_gameplay_identities_match(state_b",
        ):
            if required_token not in pr9_test_body:
                errors.append(
                    f"{pr9_test_relative}: PR 9 regression is missing required "
                    f"A/B/A assertion {required_token}"
                )

    # Post-Scripts10 PR 10: exactly one explicitly selected settlement receives
    # the current full-detail simulation pipeline. Presentation selection must
    # remain independent, while inactive settlements retain their state and
    # accrue explicit elapsed-time debt for a future catch-up policy.
    pr10_coordinator_relative = (
        "scripts/world/simulation/SimulationCoordinator.gd"
    )
    pr10_session_relative = "scripts/session/GameSession.gd"
    pr10_test_relative = (
        "scripts/world/simulation/InactiveSettlementSimulationPolicyTest.gd"
    )
    pr10_scene_relative = (
        "scripts/world/simulation/InactiveSettlementSimulationPolicyTest.tscn"
    )
    pr10_long_run_relative = (
        "scripts/city/simulation/CityUnifiedLongRunTest.gd"
    )
    pr10_coordinator_path = ROOT / pr10_coordinator_relative
    pr10_session_path = ROOT / pr10_session_relative
    pr10_test_path = ROOT / pr10_test_relative
    pr10_scene_path = ROOT / pr10_scene_relative
    pr10_long_run_path = ROOT / pr10_long_run_relative

    if not pr10_coordinator_path.exists():
        errors.append(
            f"{pr10_coordinator_relative}: missing PR 10 simulation policy owner"
        )
    else:
        pr10_coordinator_text = pr10_coordinator_path.read_text(encoding="utf-8")
        pr10_coordinator_functions = {
            match.group(1) for match in FUNC_RE.finditer(pr10_coordinator_text)
        }
        for required_api in (
            "select_detailed_simulation_settlement",
            "clear_detailed_simulation_settlement",
            "reset_settlement_simulation_policy",
            "get_detailed_simulation_settlement_id",
            "get_settlement_simulation_tier",
            "get_pending_inactive_minutes",
            "consume_pending_inactive_minutes",
            "get_settlement_simulation_policy_snapshot",
            "_record_settlement_elapsed_time_policy",
        ):
            if required_api not in pr10_coordinator_functions:
                errors.append(
                    f"{pr10_coordinator_relative}: PR 10 missing explicit "
                    f"simulation policy boundary {required_api}"
                )
        for required_token in (
            "SETTLEMENT_SIMULATION_TIER_FULL_DETAIL",
            "SETTLEMENT_SIMULATION_TIER_INACTIVE_RETAINED",
            "MEDIUM_RESOLUTION_FUTURE",
            "AGGREGATE_FUTURE",
            "pending_inactive_minutes_by_settlement_id",
            "full_detail_minutes_by_settlement_id",
            "last_full_detail_tick_by_settlement_id",
            "settlement_registry_reset",
        ):
            if required_token not in pr10_coordinator_text:
                errors.append(
                    f"{pr10_coordinator_relative}: PR 10 policy is missing "
                    f"required tier/ledger token {required_token}"
                )
        pr10_run_body = gdscript_function_body(
            pr10_coordinator_text,
            "run_simulation_systems",
        ) or ""
        for required_token in (
            "_record_settlement_elapsed_time_policy(",
            "get_settlement_context(",
            "detailed_simulation_settlement_id",
            "run_settlement_simulation_systems(",
        ):
            if required_token not in pr10_run_body:
                errors.append(
                    f"{pr10_coordinator_relative}: PR 10 clock entry is missing "
                    f"explicit target step {required_token}"
                )
        for forbidden_token in (
            "get_active_settlement_context(",
            "active_settlement_id",
            "set_active_settlement(",
        ):
            if forbidden_token in pr10_run_body:
                errors.append(
                    f"{pr10_coordinator_relative}: PR 10 clock entry must not "
                    f"discover or swap the presentation target via {forbidden_token}"
                )

    if not pr10_session_path.exists():
        errors.append(f"{pr10_session_relative}: missing PR 10 target selection")
    else:
        pr10_session_text = pr10_session_path.read_text(encoding="utf-8")
        for function_name, required_token in (
            (
                "show_settlement_city_view",
                "select_detailed_simulation_settlement(settlement_id)",
            ),
            (
                "_prepare_first_city_entry",
                "_select_first_city_detailed_simulation_target()",
            ),
        ):
            function_body = gdscript_function_body(
                pr10_session_text,
                function_name,
            ) or ""
            if required_token not in function_body:
                errors.append(
                    f"{pr10_session_relative}: PR 10 {function_name} must "
                    "select the exact detailed simulation target"
                )

        pr10_first_target_body = gdscript_function_body(
            pr10_session_text,
            "_select_first_city_detailed_simulation_target",
        ) or ""
        if "select_detailed_simulation_settlement(" not in pr10_first_target_body:
            errors.append(
                f"{pr10_session_relative}: PR 10 first-entry target seam must "
                "delegate to the coordinator's explicit selection policy"
            )

    for required_path in (pr10_test_path, pr10_scene_path):
        if not required_path.exists():
            errors.append(
                f"{required_path.relative_to(ROOT)}: missing permanent PR 10 "
                "inactive-settlement policy regression"
            )
    if pr10_test_path.exists():
        pr10_test_text = pr10_test_path.read_text(encoding="utf-8")
        pr10_ready_body = gdscript_function_body(pr10_test_text, "_ready") or ""
        pr10_test_name = "_test_inactive_settlement_simulation_policy"
        pr10_test_body = gdscript_function_body(
            pr10_test_text,
            pr10_test_name,
        ) or ""
        if pr10_test_name + "()" not in pr10_ready_body:
            errors.append(
                f"{pr10_test_relative}: PR 10 regression is not invoked"
            )
        for required_token in (
            "select_detailed_simulation_settlement(",
            "city_a_id",
            "set_active_settlement(city_b_id)",
            "get_pending_inactive_minutes(city_b_id)",
            "consume_pending_inactive_minutes(city_b_id, 7)",
            "select_detailed_simulation_settlement(city_b_id)",
            "clear_detailed_simulation_settlement()",
            "_capture_gameplay(state_a)",
            "_capture_gameplay(state_b)",
            "_identities_match(state_a",
            "_identities_match(state_b",
        ):
            if required_token not in pr10_test_body:
                errors.append(
                    f"{pr10_test_relative}: PR 10 regression is missing "
                    f"required policy assertion {required_token}"
                )

    if not pr10_long_run_path.exists():
        errors.append(
            f"{pr10_long_run_relative}: missing PR 10 long-run compatibility"
        )
    elif "select_detailed_simulation_settlement(" not in (
        pr10_long_run_path.read_text(encoding="utf-8")
    ):
        errors.append(
            f"{pr10_long_run_relative}: PR 10 clock-driven regression must "
            "select its detailed settlement explicitly"
        )

    matcher_relative = "scripts/city/simulation/systems/CityResourceMatcher.gd"
    matcher_path = ROOT / matcher_relative
    if matcher_path.exists():
        matcher_text = matcher_path.read_text(encoding="utf-8")
        matcher_policy_constants = {
            "HOUSEHOLD_FOOD_TARGET_DAY_NUMERATOR": "1",
            "HOUSEHOLD_FOOD_TARGET_DAY_DENOMINATOR": "1",
            "PUBLIC_FOOD_RESERVE_TARGET_DAY_NUMERATOR": "1",
            "PUBLIC_FOOD_RESERVE_TARGET_DAY_DENOMINATOR": "2",
        }
        for constant_name, expected_value in matcher_policy_constants.items():
            if not re.search(
                rf"^const\s+{re.escape(constant_name)}\s*:\s*int\s*=\s*"
                rf"{re.escape(expected_value)}\s*$",
                matcher_text,
                re.MULTILINE,
            ):
                errors.append(
                    f"{matcher_relative}: missing Pass 9 food policy constant "
                    f"{constant_name} = {expected_value}"
                )

    pass9_world_data_symbols = sorted(
        set(PASS9_RETIRED_WORLD_DATA_CITIZEN_INVENTORY_NEEDS_SYMBOLS)
    )
    pass9_world_data_symbol_alternation = "|".join(
        re.escape(symbol)
        for symbol in sorted(
            pass9_world_data_symbols,
            key=len,
            reverse=True,
        )
    )

    if world_data_path.exists():
        world_data_text = world_data_path.read_text(encoding="utf-8")

        for symbol in pass9_world_data_symbols:
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
                    "scripts/world/simulation/WorldData.gd: Pass 9 citizen "
                    "inventory/needs declaration must not return: "
                    f"{symbol}"
                )

    for path in scripts:
        text = path.read_text(encoding="utf-8")
        relative = path.relative_to(ROOT).as_posix()
        comment_free_text = gdscript_without_line_comments(text)
        masked_code = gdscript_masked_code(text)
        world_data_receiver = r"WorldData(?:Script)?"
        gdscript_string_literal_prefix = r"&?"
        world_data_alias_patterns = (
            re.compile(
                r"^\s*(?:const|var)\s+([A-Za-z_][A-Za-z0-9_]*)"
                r"(?:\s*:\s*[A-Za-z_][^=\n]*)?\s*(?::=|=)\s*"
                r"(?:preload|load)\s*\(\s*[\"']"
                r"res://scripts/world/simulation/WorldData\.gd[\"']\s*\)",
                re.MULTILINE,
            ),
            re.compile(
                r"^\s*(?:const|var)\s+([A-Za-z_][A-Za-z0-9_]*)"
                r"(?:\s*:\s*[A-Za-z_][^=\n]*)?\s*(?::=|=)\s*"
                r"WorldData(?:Script)?\s*$",
                re.MULTILINE,
            ),
        )
        world_data_aliases: set[str] = set()
        for alias_pattern in world_data_alias_patterns:
            world_data_aliases.update(alias_pattern.findall(comment_free_text))

        if world_data_aliases:
            errors.append(
                f"{relative}: WorldData aliases can bypass retired API guards; "
                "use the global WorldData class directly: "
                + ", ".join(sorted(world_data_aliases))
            )

        reflective_world_data_pattern = re.compile(
            rf"(?:\b{world_data_receiver}\s*\.\s*"
            r"(?:get|set|call|callv|call_deferred|has_method)\s*\("
            rf"|\b{world_data_receiver}\s*\["
            rf"|\bCallable\s*\(\s*{world_data_receiver}\b)"
        )
        direct_symbols = set(
            re.findall(
                rf"\b{world_data_receiver}\s*\.\s*"
                rf"({pass9_world_data_symbol_alternation})\b",
                masked_code,
            )
        )
        dynamic_symbols = set(
            re.findall(
                rf"\b{world_data_receiver}\s*\[\s*"
                rf"{gdscript_string_literal_prefix}[\"']"
                rf"({pass9_world_data_symbol_alternation})[\"']\s*\]",
                comment_free_text,
            )
        )
        dynamic_symbols.update(
            re.findall(
                rf"\b{world_data_receiver}\s*\.\s*"
                rf"(?:get|set|call|callv|call_deferred|has_method)\s*\(\s*"
                rf"{gdscript_string_literal_prefix}[\"']"
                rf"({pass9_world_data_symbol_alternation})[\"']",
                comment_free_text,
            )
        )
        dynamic_symbols.update(
            re.findall(
                rf"\bCallable\s*\(\s*{world_data_receiver}\s*,\s*"
                rf"{gdscript_string_literal_prefix}[\"']"
                rf"({pass9_world_data_symbol_alternation})[\"']\s*\)",
                comment_free_text,
            )
        )

        if (
            reflective_world_data_pattern.search(masked_code)
            and not dynamic_symbols
        ):
            errors.append(
                f"{relative}: reflective or indexed WorldData access is "
                "forbidden because computed names bypass retired API guards"
            )

        for symbol in sorted(direct_symbols):
            errors.append(
                f"{relative}: retired Pass 9 WorldData citizen "
                f"inventory/needs reference remains: WorldData.{symbol}"
            )
        for symbol in sorted(dynamic_symbols):
            errors.append(
                f"{relative}: dynamic retired Pass 9 WorldData citizen "
                f"inventory/needs reference remains: {symbol}"
            )

    citizen_schema_relative = "scripts/citizens/simulation/CityCitizens.gd"
    field_owner_paths: dict[str, set[str]] = {}

    for field_name in PASS9_CITIZEN_INVENTORY_FIELDS:
        field_owner_paths[field_name] = {
            citizen_schema_relative,
            PASS9_CITIZEN_INVENTORY_SYSTEM_PATH,
            *PASS9_CITIZEN_STATE_CORRUPTION_FIXTURE_PATHS,
        }
    for field_name in PASS9_CITIZEN_NEEDS_FIELDS:
        field_owner_paths[field_name] = {
            citizen_schema_relative,
            PASS9_CITIZEN_NEEDS_SYSTEM_PATH,
            *PASS9_CITIZEN_STATE_CORRUPTION_FIXTURE_PATHS,
        }

    embedded_field_alternation = "|".join(
        re.escape(field_name)
        for field_name in (
            *PASS9_CITIZEN_INVENTORY_FIELDS,
            *PASS9_CITIZEN_NEEDS_FIELDS,
        )
    )
    embedded_physical_field_alternation = "|".join(
        re.escape(field_name)
        for field_name in ("inventory", "haul_cargo")
    )
    field_key_bodies = (
        rf"(?:&\s*)?[\"']({embedded_field_alternation})[\"']",
        rf"StringName\s*\(\s*[\"']"
        rf"({embedded_field_alternation})[\"']\s*\)",
    )
    field_write_patterns: list[re.Pattern[str]] = []
    for field_key_body in field_key_bodies:
        field_write_patterns.extend(
            (
                re.compile(
                    rf"\[\s*{field_key_body}\s*\]\s*"
                    r"(?:=|\+=|-=|\*=|/=|%=)"
                ),
                re.compile(
                    rf"\.\s*set\s*\(\s*{field_key_body}\s*,"
                ),
                re.compile(
                    rf"\.\s*erase\s*\(\s*{field_key_body}\s*\)"
                ),
                re.compile(
                    rf"\.\s*get\s*\(\s*{field_key_body}[^)]*\)\s*"
                    r"\[[^\]]+\]\s*(?:=|\+=|-=|\*=|/=|%=)"
                ),
                re.compile(
                    rf"\[\s*{field_key_body}\s*\]\s*"
                    r"(?:\[[^\]]+\]\s*(?:=|\+=|-=|\*=|/=|%=)"
                    r"|\.\s*(?:set|erase|clear|merge|assign)\s*\()"
                ),
                re.compile(
                    rf"\.\s*get\s*\(\s*{field_key_body}[^)]*\)\s*\.\s*"
                    r"(?:set|erase|clear|merge|assign)\s*\("
                ),
            )
        )
    dotted_field_write_pattern = re.compile(
        rf"\.\s*({embedded_field_alternation})\s*"
        r"(?:=|\+=|-=|\*=|/=|%=)"
    )
    field_write_patterns.append(dotted_field_write_pattern)

    protected_field_key_alias_patterns = (
        re.compile(
            rf"^\s*(?:const|var)\s+([A-Za-z_][A-Za-z0-9_]*)"
            rf"(?:\s*:\s*[^=\n]+)?\s*(?::=|=)\s*(?:&\s*)?[\"']"
            rf"({embedded_field_alternation})[\"']\s*$",
            re.MULTILINE,
        ),
        re.compile(
            rf"^\s*(?:const|var)\s+([A-Za-z_][A-Za-z0-9_]*)"
            rf"(?:\s*:\s*[^=\n]+)?\s*(?::=|=)\s*StringName\s*\(\s*[\"']"
            rf"({embedded_field_alternation})[\"']\s*\)\s*$",
            re.MULTILINE,
        ),
    )

    pass9_ledger_domain = r"(?:inventory|haul_?cargo|cargo|carry|hunger|happiness|needs?)"
    pass9_ledger_scope = r"(?:citizen|resident|population)"
    pass9_ledger_name_patterns = (
        re.compile(
            rf"^(?:city_)?{pass9_ledger_scope}.*{pass9_ledger_domain}"
            r"(?:_by_.+|_(?:ledger|lookup|cache|state|amounts?))$"
        ),
        re.compile(
            rf"^{pass9_ledger_domain}.*(?:_by_.*{pass9_ledger_scope}.*"
            rf"|_(?:ledger|lookup|cache|state|amounts?).*{pass9_ledger_scope}.*)$"
        ),
        re.compile(
            rf"^(?:city_)?{pass9_ledger_scope}_{pass9_ledger_domain}s?$"
        ),
    )
    top_level_mutable_container_pattern = re.compile(
        r"^(?:static\s+)?var\s+([A-Za-z_][A-Za-z0-9_]*)([^\n]*)$",
        re.MULTILINE,
    )

    for path in scripts:
        if path.name.endswith("Test.gd"):
            continue

        relative = path.relative_to(ROOT).as_posix()
        text = gdscript_without_line_comments(path.read_text(encoding="utf-8"))

        for declaration_match in top_level_mutable_container_pattern.finditer(text):
            ledger_name = declaration_match.group(1)
            declaration_tail = declaration_match.group(2)
            is_mutable_container = bool(
                re.search(r"\b(?:Array|Dictionary)\b", declaration_tail)
                or re.search(r"(?:=|:=)\s*[\[{]", declaration_tail)
            )
            is_pass9_ledger_name = any(
                pattern.fullmatch(ledger_name)
                for pattern in pass9_ledger_name_patterns
            )

            if not is_mutable_container or not is_pass9_ledger_name:
                continue

            line_number = text.count("\n", 0, declaration_match.start()) + 1
            errors.append(
                f"{relative}:{line_number}: top-level mutable Pass 9 citizen "
                f"ledger is forbidden: {ledger_name}"
            )

    for path in scripts:
        relative = path.relative_to(ROOT).as_posix()
        text = path.read_text(encoding="utf-8")
        comment_free_text = gdscript_without_line_comments(text)

        for write_pattern in field_write_patterns:
            for match in write_pattern.finditer(comment_free_text):
                field_name = match.group(1)

                if relative in field_owner_paths[field_name]:
                    continue

                line_number = comment_free_text.count("\n", 0, match.start()) + 1
                errors.append(
                    f"{relative}:{line_number}: direct write to embedded citizen "
                    f"field {field_name} is private to its focused Pass 9 owner"
                )

        protected_field_key_aliases: dict[str, str] = {}
        for alias_pattern in protected_field_key_alias_patterns:
            for alias_name, field_name in alias_pattern.findall(comment_free_text):
                protected_field_key_aliases[alias_name] = field_name

        for alias_name, field_name in protected_field_key_aliases.items():
            alias_write_patterns = (
                re.compile(
                    rf"\[\s*{re.escape(alias_name)}\s*\]\s*"
                    r"(?:=|\+=|-=|\*=|/=|%=)"
                ),
                re.compile(
                    rf"\.\s*set\s*\(\s*{re.escape(alias_name)}\s*,"
                ),
                re.compile(
                    rf"\.\s*erase\s*\(\s*{re.escape(alias_name)}\s*\)"
                ),
            )
            if relative in field_owner_paths[field_name]:
                continue

            for alias_write_pattern in alias_write_patterns:
                for match in alias_write_pattern.finditer(comment_free_text):
                    line_number = (
                        comment_free_text.count("\n", 0, match.start()) + 1
                    )
                    errors.append(
                        f"{relative}:{line_number}: indirect write through "
                        f"protected field key {alias_name} ({field_name})"
                    )

        if relative not in (
            field_owner_paths["inventory"] | field_owner_paths["haul_cargo"]
        ):
            for function_name in FUNC_RE.findall(comment_free_text):
                function_body = gdscript_function_body(
                    comment_free_text,
                    function_name,
                )
                if function_body is None:
                    continue

                alias_assignments = list(
                    re.finditer(
                        r"^\s*(?:var\s+)?([A-Za-z_][A-Za-z0-9_]*)"
                        r"(?:\s*:\s*[^=\n]+)?\s*(?::=|=)\s*(.+)$",
                        function_body,
                        re.MULTILINE,
                    )
                )
                nested_aliases: set[str] = set()

                for assignment in alias_assignments:
                    alias_name = assignment.group(1)
                    assignment_value = assignment.group(2)
                    if ".duplicate(" in assignment_value:
                        continue
                    if not (
                        "citizen" in assignment_value
                        or "citizens[" in assignment_value
                    ):
                        continue
                    if re.search(
                        rf"(?:\.\s*get\s*\(\s*(?:&\s*)?[\"']"
                        rf"(?:{embedded_physical_field_alternation})[\"']"
                        rf"|\[\s*(?:&\s*)?[\"']"
                        rf"(?:{embedded_physical_field_alternation})[\"']\s*\])",
                        assignment_value,
                    ):
                        nested_aliases.add(alias_name)

                aliases_changed = True
                while aliases_changed:
                    aliases_changed = False
                    for assignment in alias_assignments:
                        alias_name = assignment.group(1)
                        assignment_value = assignment.group(2).strip()
                        if (
                            alias_name not in nested_aliases
                            and assignment_value in nested_aliases
                        ):
                            nested_aliases.add(alias_name)
                            aliases_changed = True

                for alias_name in sorted(nested_aliases):
                    alias_mutation_pattern = re.compile(
                        rf"\b{re.escape(alias_name)}\s*(?:"
                        r"\[[^\]]+\]\s*(?:=|\+=|-=|\*=|/=|%=)"
                        r"|\.\s*(?:set|erase|clear|merge|assign)\s*\()"
                    )
                    if alias_mutation_pattern.search(function_body):
                        errors.append(
                            f"{relative}: {function_name} mutates aliased "
                            f"citizen inventory/cargo outside its focused owner"
                        )

        required_query_calls = PASS9_FOCUSED_QUERY_CONSUMERS.get(relative)
        if required_query_calls is not None:
            masked_code = gdscript_masked_code(text)
            missing_query_calls = [
                call_name
                for call_name in required_query_calls
                if not re.search(
                    rf"\b{re.escape(call_name)}\s*\(",
                    masked_code,
                )
            ]
            if missing_query_calls:
                errors.append(
                    f"{relative}: focused Pass 9 query migration is missing: "
                    + ", ".join(sorted(missing_query_calls))
                )

            ui_raw_field_patterns: list[re.Pattern[str]] = []
            for field_key_body in field_key_bodies:
                ui_raw_field_patterns.extend(
                    (
                        re.compile(rf"\.\s*get\s*\(\s*{field_key_body}"),
                        re.compile(rf"\[\s*{field_key_body}\s*\]"),
                    )
                )
            ui_raw_field_patterns.append(
                re.compile(rf"\.\s*({embedded_field_alternation})\b")
            )
            raw_query_fields = sorted(
                {
                    match.group(1)
                    for pattern in ui_raw_field_patterns
                    for match in pattern.finditer(comment_free_text)
                }
            )
            if raw_query_fields:
                errors.append(
                    f"{relative}: UI/rendering must query focused Pass 9 "
                    "owners instead of raw citizen fields: "
                    + ", ".join(raw_query_fields)
                )

    # Preserve the focused behavioral contract as well as its implementation:
    # bootstrap repair, equal-version A/B/A isolation, fair scarce-food access,
    # interruption safety, starvation recovery, and return-to-work all remain
    # mandatory headless scenes in the repository-wide runner.
    for test_relative, required_test_functions in (
        PASS9_REQUIRED_TEST_FUNCTIONS.items()
    ):
        test_path = ROOT / test_relative
        test_scene_path = test_path.with_suffix(".tscn")

        for required_path in (test_path, test_scene_path):
            if not required_path.exists():
                errors.append(
                    f"{required_path.relative_to(ROOT)}: missing permanent "
                    "Pass 9 citizen inventory/needs coverage"
                )

        if not test_path.exists():
            continue

        test_text = test_path.read_text(encoding="utf-8")
        test_functions = set(FUNC_RE.findall(test_text))
        missing_test_functions = sorted(
            set(required_test_functions) - test_functions
        )
        if missing_test_functions:
            errors.append(
                f"{test_relative}: missing permanent Pass 9 regression: "
                + ", ".join(missing_test_functions)
            )

        ready_body = gdscript_function_body(test_text, "_ready") or ""
        masked_ready_body = gdscript_masked_code(ready_body)
        uninvoked_test_functions = sorted(
            function_name
            for function_name in required_test_functions
            if not re.search(
                rf"^\s*{re.escape(function_name)}\s*\(",
                masked_ready_body,
                re.MULTILINE,
            )
        )
        if uninvoked_test_functions:
            errors.append(
                f"{test_relative}: Pass 9 regressions are not invoked by _ready: "
                + ", ".join(uninvoked_test_functions)
            )

        required_call_contracts = PASS9_REQUIRED_TEST_CALLS.get(
            test_relative,
            {},
        )
        for function_name in required_test_functions:
            function_body = gdscript_function_body(test_text, function_name)
            if function_body is None:
                continue

            masked_function_body = gdscript_masked_code(function_body)
            if not re.search(r"\b_expect\s*\(", masked_function_body):
                errors.append(
                    f"{test_relative}: Pass 9 regression {function_name} "
                    "must contain executable expectations"
                )

            missing_contract_calls = sorted(
                call_name
                for call_name in required_call_contracts.get(function_name, ())
                if not re.search(
                    rf"\b{re.escape(call_name)}\s*\(",
                    masked_function_body,
                )
            )
            if missing_contract_calls:
                errors.append(
                    f"{test_relative}: Pass 9 regression {function_name} "
                    "is missing contract calls: "
                    + ", ".join(missing_contract_calls)
                )

        if test_scene_path.exists():
            scene_text = test_scene_path.read_text(encoding="utf-8")
            expected_resource_path = f"res://{test_relative}"
            expected_script_ids: set[str] = set()
            for raw_line in scene_text.splitlines():
                if not raw_line.startswith("[ext_resource "):
                    continue
                if 'type="Script"' not in raw_line:
                    continue

                path_match = re.search(r'\bpath="([^"]+)"', raw_line)
                id_match = re.search(r'\bid="([^"]+)"', raw_line)
                if (
                    path_match is not None
                    and id_match is not None
                    and path_match.group(1) == expected_resource_path
                ):
                    expected_script_ids.add(id_match.group(1))

            root_node_match = re.search(
                r"^\[node\b[^\]]*\]\s*(.*?)(?=^\[|\Z)",
                scene_text,
                re.MULTILINE | re.DOTALL,
            )
            root_script_id: str | None = None
            if root_node_match is not None:
                root_script_match = re.search(
                    r'^script\s*=\s*ExtResource\("([^"]+)"\)\s*$',
                    root_node_match.group(1),
                    re.MULTILINE,
                )
                if root_script_match is not None:
                    root_script_id = root_script_match.group(1)

            if root_script_id not in expected_script_ids:
                errors.append(
                    f"{test_scene_path.relative_to(ROOT)}: Pass 9 scene must bind "
                    f"{expected_resource_path} on its root node"
                )


    # Pass 10: housing and employment relationships remain physically embedded
    # in citizen/object records, but all ordinary bidirectional mutation now
    # crosses one atomic assignment boundary. The two focused data-only states
    # own invalidation only, never a shadow resident/worker ledger.
    pass10_assignment_state_path = (
        ROOT / "scripts/city/simulation/CityAssignmentState.gd"
    )
    pass10_workplace_state_path = (
        ROOT / "scripts/city/simulation/CityWorkplaceState.gd"
    )
    pass10_assignment_system_path = (
        ROOT / "scripts/citizens/simulation/systems/CityAssignmentSystem.gd"
    )
    pass10_employment_system_path = (
        ROOT / "scripts/citizens/simulation/systems/CityEmploymentSystem.gd"
    )
    pass10_political_state_path = (
        ROOT / "scripts/world/simulation/WorldPoliticalState.gd"
    )
    pass10_root_state_path = (
        ROOT / "scripts/city/simulation/CitySettlementSimulationState.gd"
    )
    pass10_required_paths = (
        pass10_assignment_state_path,
        pass10_workplace_state_path,
        pass10_assignment_system_path,
        pass10_employment_system_path,
        pass10_political_state_path,
        pass10_root_state_path,
    )
    for required_path in pass10_required_paths:
        if not required_path.exists():
            errors.append(
                f"{required_path.relative_to(ROOT)}: missing permanent Pass 10 "
                "assignment/housing/employment owner"
            )

    if all(path.exists() for path in pass10_required_paths):
        assignment_state_text = pass10_assignment_state_path.read_text(
            encoding="utf-8"
        )
        workplace_state_text = pass10_workplace_state_path.read_text(
            encoding="utf-8"
        )
        assignment_system_text = pass10_assignment_system_path.read_text(
            encoding="utf-8"
        )
        employment_system_text = pass10_employment_system_path.read_text(
            encoding="utf-8"
        )
        political_state_text = pass10_political_state_path.read_text(
            encoding="utf-8"
        )
        root_state_text = pass10_root_state_path.read_text(encoding="utf-8")

        pass10_state_specs = (
            (
                pass10_assignment_state_path,
                assignment_state_text,
                "CityAssignmentState",
                "assignment_version",
            ),
            (
                pass10_workplace_state_path,
                workplace_state_text,
                "CityWorkplaceState",
                "workplace_version",
            ),
        )
        relationship_ledger_fields = (
            "home_object_id",
            "job_object_id",
            "resident_ids",
            "assigned_worker_ids",
            "residents_by_object_id",
            "workers_by_object_id",
        )
        for state_path, state_text, class_name, version_field in pass10_state_specs:
            relative = str(state_path.relative_to(ROOT))
            declared_fields = set(
                re.findall(
                    r"^var\s+([A-Za-z_][A-Za-z0-9_]*)\b",
                    state_text,
                    re.MULTILINE,
                )
            )
            if declared_fields != {version_field}:
                errors.append(
                    f"{relative}: {class_name} must own only {version_field}; "
                    "relationship records stay on citizens and city objects"
                )
            if not re.search(
                rf"^var\s+{re.escape(version_field)}:\s*int\s*=\s*0\s*$",
                state_text,
                re.MULTILINE,
            ):
                errors.append(
                    f"{relative}: missing typed zero default for {version_field}"
                )
            if FUNC_RE.search(state_text):
                errors.append(
                    f"{relative}: {class_name} must remain data-only"
                )
            for field_name in relationship_ledger_fields:
                if re.search(
                    rf"^var\s+{re.escape(field_name)}\b",
                    state_text,
                    re.MULTILINE,
                ):
                    errors.append(
                        f"{relative}: duplicate relationship ledger is forbidden: "
                        f"{field_name}"
                    )

        required_root_surfaces = (
            "var assignment_state: CityAssignmentState = CityAssignmentState.new()",
            "var workplace_state: CityWorkplaceState = CityWorkplaceState.new()",
        )
        for required_surface in required_root_surfaces:
            if required_surface not in root_state_text:
                errors.append(
                    "scripts/city/simulation/CitySettlementSimulationState.gd: "
                    f"missing Pass 10 owner surface: {required_surface}"
                )
        for retired_root_field in ("assignment_version", "workplace_version"):
            if re.search(
                rf"^var\s+{re.escape(retired_root_field)}\b",
                root_state_text,
                re.MULTILINE,
            ):
                errors.append(
                    "scripts/city/simulation/CitySettlementSimulationState.gd: "
                    f"{retired_root_field} must live in its focused state"
                )
            if f"WorldData.city_{retired_root_field}" in root_state_text:
                errors.append(
                    "scripts/city/simulation/CitySettlementSimulationState.gd: "
                    f"{retired_root_field} must not use capture/apply workspace copying"
                )

        required_political_surfaces = (
            "CityAssignmentStateScript = preload(",
            "CityWorkplaceStateScript = preload(",
            "_unbound_city_assignment_state",
            "_unbound_city_workplace_state",
            "capital_state.assignment_state = unbound_assignment_state_to_adopt",
            "capital_state.workplace_state = unbound_workplace_state_to_adopt",
            "func get_current_city_assignment_state() -> CityAssignmentState:",
            "func get_current_city_workplace_state() -> CityWorkplaceState:",
        )
        for required_surface in required_political_surfaces:
            if required_surface not in political_state_text:
                errors.append(
                    "scripts/world/simulation/WorldPoliticalState.gd: missing "
                    f"Pass 10 settlement-local plumbing: {required_surface}"
                )

        required_assignment_functions = (
            "get_current_state",
            "get_city_assignment_version",
            "mark_city_assignments_changed",
            "ensure_city_citizen_assignment_state",
            "get_city_housed_citizen_count",
            "get_city_unemployed_citizen_count",
            "get_city_object_resident_ids",
            "get_city_object_worker_ids",
            "assign_homeless_citizens_to_available_housing",
            "assign_city_citizen_home",
            "remove_city_citizen_home",
            "assign_city_citizen_job",
            "remove_city_citizen_job",
        )
        assignment_functions = {match.group(1) for match in FUNC_RE.finditer(assignment_system_text)}
        missing_assignment_functions = sorted(
            set(required_assignment_functions) - assignment_functions
        )
        if missing_assignment_functions:
            errors.append(
                "scripts/citizens/simulation/systems/CityAssignmentSystem.gd: "
                "missing focused Pass 10 APIs: "
                + ", ".join(missing_assignment_functions)
            )
        if (
            "static func get_current_state() -> CityAssignmentState:"
            not in assignment_system_text
            or "WorldPoliticalState.get_current_city_assignment_state()"
            not in assignment_system_text
        ):
            errors.append(
                "scripts/citizens/simulation/systems/CityAssignmentSystem.gd: "
                "missing typed settlement-local state resolver"
            )

        required_employment_functions = (
            "get_current_state",
            "get_city_workplace_version",
            "mark_city_workplaces_changed",
            "ensure_workplace_staffing_state",
            "reconcile_automatic_workplaces",
            "is_city_citizen_attending_workplace",
            "get_city_object_attending_worker_ids",
        )
        employment_functions = {match.group(1) for match in FUNC_RE.finditer(employment_system_text)}
        missing_employment_functions = sorted(
            set(required_employment_functions) - employment_functions
        )
        if missing_employment_functions:
            errors.append(
                "scripts/citizens/simulation/systems/CityEmploymentSystem.gd: "
                "missing focused Pass 10 employment APIs: "
                + ", ".join(missing_employment_functions)
            )
        if (
            "static func get_current_state() -> CityWorkplaceState:"
            not in employment_system_text
            or "WorldPoliticalState.get_current_city_workplace_state()"
            not in employment_system_text
        ):
            errors.append(
                "scripts/citizens/simulation/systems/CityEmploymentSystem.gd: "
                "missing typed settlement-local workplace-state resolver"
            )

        pass10_retired_world_data_symbols = (
            "city_assignment_version",
            "city_workplace_version",
            "_mark_city_assignments_changed",
            "_mark_city_workplaces_changed",
            "get_city_housed_citizen_count",
            "get_city_unemployed_citizen_count",
            "get_city_object_resident_count",
            "get_city_object_resident_ids",
            "get_city_object_resident_names",
            "get_total_city_resident_capacity",
            "get_city_object_worker_count",
            "get_city_object_worker_ids",
            "get_city_object_worker_names",
            "is_city_citizen_attending_workplace",
            "get_city_object_attending_worker_ids",
            "get_city_object_attending_worker_count",
            "assign_homeless_citizens_to_available_housing",
            "assign_unemployed_citizens_to_available_workplaces",
            "assign_city_citizen_home",
            "remove_city_citizen_home",
            "assign_city_citizen_job",
            "remove_city_citizen_job",
        )
        if world_data_path.exists():
            world_data_text = world_data_path.read_text(encoding="utf-8")
            for symbol in pass10_retired_world_data_symbols:
                declaration_patterns = (
                    rf"^\s*static\s+var\s+{re.escape(symbol)}\b",
                    rf"^\s*(?:static\s+)?func\s+{re.escape(symbol)}\s*\(",
                )
                if any(
                    re.search(pattern, world_data_text, re.MULTILINE)
                    for pattern in declaration_patterns
                ):
                    errors.append(
                        "scripts/world/simulation/WorldData.gd: retired Pass 10 "
                        f"assignment/employment declaration returned: {symbol}"
                    )

            for path in scripts:
                text = path.read_text(encoding="utf-8")
                relative = str(path.relative_to(ROOT))
                for symbol in pass10_retired_world_data_symbols:
                    direct_reference = re.search(
                        rf"\bWorldData\s*\.\s*{re.escape(symbol)}\b",
                        text,
                    )
                    dynamic_reference = re.search(
                        rf"\bWorldData\s*\.\s*(?:get|set|call|callv|has_method)"
                        rf"\s*\(\s*[\"']{re.escape(symbol)}[\"']",
                        text,
                    )
                    callable_reference = re.search(
                        rf"\bCallable\s*\(\s*WorldData\s*,\s*"
                        rf"[\"']{re.escape(symbol)}[\"']\s*\)",
                        text,
                    )
                    if direct_reference or dynamic_reference or callable_reference:
                        errors.append(
                            f"{relative}: legacy WorldData Pass 10 reference remains: "
                            f"{symbol}"
                        )

        # Only the focused mutation owner, completed-object initialization, and
        # the explicit corruption fixture may write relationship fields directly.
        direct_relationship_write_allowlist = {
            "scripts/citizens/simulation/systems/CityAssignmentSystem.gd",
            "scripts/city/simulation/systems/CityObjectSystem.gd",
            "scripts/city/simulation/CityAssignmentSystemTest.gd",
        }
        for path in scripts:
            relative = path.relative_to(ROOT).as_posix()
            if relative in direct_relationship_write_allowlist:
                continue
            masked_text = gdscript_masked_code(path.read_text(encoding="utf-8"))
            for field_name in (
                "home_object_id",
                "job_object_id",
                "resident_ids",
                "assigned_worker_ids",
            ):
                if re.search(
                    rf"\[\s*[\"']{re.escape(field_name)}[\"']\s*\]\s*=",
                    masked_text,
                ):
                    errors.append(
                        f"{relative}: direct {field_name} mutation bypasses "
                        "CityAssignmentSystem"
                    )

        private_resolvers = (
            (
                "get_current_city_assignment_state",
                {
                    "scripts/world/simulation/WorldPoliticalState.gd",
                    "scripts/citizens/simulation/systems/CityAssignmentSystem.gd",
                },
            ),
            (
                "get_current_city_workplace_state",
                {
                    "scripts/world/simulation/WorldPoliticalState.gd",
                    "scripts/citizens/simulation/systems/CityEmploymentSystem.gd",
                },
            ),
        )
        for resolver, allowed_paths in private_resolvers:
            for path in scripts:
                relative = path.relative_to(ROOT).as_posix()
                if relative in allowed_paths:
                    continue
                text = path.read_text(encoding="utf-8")
                if re.search(
                    rf"\bWorldPoliticalState\s*\.\s*{re.escape(resolver)}\s*\(",
                    text,
                ):
                    errors.append(
                        f"{relative}: {resolver} is private; use the focused "
                        "system get_current_state() accessor"
                    )

        simulation_coordinator_path = (
            ROOT / "scripts/world/simulation/SimulationCoordinator.gd"
        )
        if simulation_coordinator_path.exists():
            coordinator_text = simulation_coordinator_path.read_text(
                encoding="utf-8"
            )
            if (
                "CityAssignmentSystem.ensure_city_citizen_assignment_state_for_city_state("
                not in coordinator_text
            ):
                errors.append(
                    "scripts/world/simulation/SimulationCoordinator.gd: headless "
                    "city simulation must normalize bidirectional assignments"
                )

        renderer_text = renderer_path.read_text(encoding="utf-8") if renderer_path.exists() else ""
        validator_text = validator_path.read_text(encoding="utf-8") if validator_path.exists() else ""
        for required_surface in (
            "var observed_city_assignment_state: CityAssignmentState",
            "var observed_city_workplace_state: CityWorkplaceState",
            "CityAssignmentSystem.get_current_state()",
            "CityEmploymentSystem.get_current_state()",
            "not is_same(",
        ):
            if required_surface not in renderer_text:
                errors.append(
                    "scripts/city/rendering/CityRenderer.gd: missing identity-aware "
                    f"Pass 10 invalidation surface: {required_surface}"
                )
        for required_surface in (
            "static var _cached_assignment_state: CityAssignmentState",
            "static var _cached_workplace_state: CityWorkplaceState",
            '"assignment_state_instance_id"',
            '"workplace_state_instance_id"',
            "CityAssignmentSystem.get_current_state()",
            "CityEmploymentSystem.get_current_state()",
            "not is_same(",
        ):
            if required_surface not in validator_text:
                errors.append(
                    "scripts/city/simulation/CityStateValidator.gd: missing "
                    f"identity-aware Pass 10 cache surface: {required_surface}"
                )

    pass10_test_contracts = {
        "scripts/city/simulation/CityAssignmentSystemTest.gd": (
            "_test_bidirectional_repair_capacity_and_idempotence",
            "_test_atomic_mutation_and_removed_building_reassignment",
        ),
        "scripts/city/simulation/CityAssignmentStateIsolationTest.gd": (
            "_test_equal_version_assignment_and_workplace_isolation",
        ),
    }
    for test_relative, required_functions in pass10_test_contracts.items():
        test_path = ROOT / test_relative
        test_scene_path = test_path.with_suffix(".tscn")
        for required_path in (test_path, test_scene_path):
            if not required_path.exists():
                errors.append(
                    f"{required_path.relative_to(ROOT)}: missing permanent Pass 10 "
                    "regression coverage"
                )
        if not test_path.exists():
            continue

        test_text = test_path.read_text(encoding="utf-8")
        test_functions = {match.group(1) for match in FUNC_RE.finditer(test_text)}
        missing_functions = sorted(set(required_functions) - test_functions)
        if missing_functions:
            errors.append(
                f"{test_relative}: missing permanent Pass 10 regression: "
                + ", ".join(missing_functions)
            )
        ready_body = gdscript_function_body(test_text, "_ready") or ""
        masked_ready_body = gdscript_masked_code(ready_body)
        for function_name in required_functions:
            if not re.search(
                rf"^\s*{re.escape(function_name)}\s*\(",
                masked_ready_body,
                re.MULTILINE,
            ):
                errors.append(
                    f"{test_relative}: Pass 10 regression is not invoked by "
                    f"_ready: {function_name}"
                )

        if test_scene_path.exists():
            scene_text = test_scene_path.read_text(encoding="utf-8")
            expected_resource_path = f"res://{test_relative}"
            if expected_resource_path not in scene_text or "script = ExtResource" not in scene_text:
                errors.append(
                    f"{test_scene_path.relative_to(ROOT)}: Pass 10 scene must "
                    f"bind {expected_resource_path} on its root node"
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
