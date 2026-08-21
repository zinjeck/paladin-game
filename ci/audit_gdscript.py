#!/usr/bin/env python3
"""Repository-wide structural audit for Paladin's Godot source.

Godot remains the source of truth for parsing. This script adds fast checks that
are easy to miss in runtime smoke tests and emits maintainability metrics for
all scripts on every pull request.
"""

from __future__ import annotations

import collections
import hashlib
import importlib.util
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
CITY_RENDERER_TOP_LEVEL_FIELD_RE = re.compile(
    r"^(?:(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?)\s+)*"
    r"(?:static\s+)?var\s+([A-Za-z_][A-Za-z0-9_]*)\b",
    re.MULTILINE,
)

CITY_RENDERER_DECOMPOSITION_OWNERS = (
    "CityRenderer",
    "SettlementPresentationBinding",
    "CityPresentationBinding",
    "CityPresentationInvalidationTracker",
    "Camera",
    "MapTextureCache",
    "SettlementNaturalFeaturePresenter",
    "SettlementInfrastructurePresenter",
    "CityCitizenMovementPresentation",
    "SettlementPlacementController",
    "SettlementSelectionController",
    "SettlementCommandController",
    "SettlementUiController",
    "CityInformationPanel",
    "CityObjectPanelAnchor",
    "CityDebugPresentation",
    "CityWorkplaceZoneOverlayCache",
    "CityRenderLayer",
)

# Pass 11 retires comments that still describe the pre-explicit-ownership
# architecture as current. Keep this list deliberately narrow: terms such as
# "current task", save-schema compatibility, and defensive legacy-data repair
# remain legitimate when they do not imply gameplay authority.
FORBIDDEN_STALE_CITY_OWNERSHIP_COMMENT_PATTERNS = (
    re.compile(r"\breads\s+WorldData\s+but\b", re.IGNORECASE),
    re.compile(r"\bthrough\s+the\s+active\s+settlement\s+context\b", re.IGNORECASE),
    re.compile(r"\bone\s+active\s+CITY\s+settlement\b", re.IGNORECASE),
    re.compile(r"\bcan\s+migrate\s+away\s+from\s+WorldData\b", re.IGNORECASE),
    re.compile(r"\blegacy\s+WorldData\s+workspace\b", re.IGNORECASE),
    re.compile(
        r"\bfalling\s+back\s+to\s+the\s+global\s+player-capital\s+mirrors\b",
        re.IGNORECASE,
    ),
)

# Proven-zero-caller Pass 11 declarations stay retired. These are path-specific
# tombstones, not a blanket ban on similarly named concepts in other domains.
PASS11_RETIRED_PRODUCTION_DECLARATIONS = {
    "scripts/citizens/simulation/CityCitizens.gd": (
        "CITY_CITIZEN_MOVEMENT_PROGRESS_PER_TILE",
    ),
    "scripts/citizens/simulation/systems/CitizenNeedsSystem.gd": (
        "CITIZEN_FOOD_CARRY_TRIGGER_HUNGER",
    ),
    "scripts/citizens/simulation/systems/CitizenDecisionSystem.gd": (
        "_take_food_scan_start_index_for_decision_state",
        "_reset_decision_runtime_state",
        "_queue_citizen_id_for_decision_state",
        "_clear_decision_queue_for_decision_state",
    ),
    "scripts/session/CityPreparationService.gd": (
        "get_latest_generation",
        "take_completed_payload",
        "has_completed_payload",
        "take_failure",
        "is_preparing_signature",
    ),
    "scripts/city/simulation/systems/CityConstructionSystem.gd": (
        "CitizenNeedsSystemScript",
    ),
    "scripts/city/simulation/systems/CityLogisticsSystem.gd": (
        "CityCitizensScript",
    ),
}

PASS11_RETIRED_PRODUCTION_SOURCE_PATTERNS = {
    "scripts/city/simulation/systems/WorkplaceProductionSystem.gd": (
        (
            "write-only workplace evaluation radius_tiles alias",
            re.compile(
                r"\bevaluation\s*\[\s*[\"']radius_tiles[\"']\s*\]\s*="
            ),
        ),
    ),
}

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
    # Focused presenter coverage uses three local CanvasItem spies. Production
    # redraw ownership remains limited to CityRenderLayer and the information UI.
    "scripts/settlements/presentation/SettlementInfrastructurePresenterTest.gd": 3,
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
    "get_state_for_city_state",
    "get_city_container_version_for_city_state",
    "get_city_public_storage_version_for_city_state",
    "mark_city_container_changed_for_city_state",
    "reset_city_resource_accounting_state_for_city_state",
    "restore_city_resource_accounting_snapshot_for_city_state",
    "get_total_public_city_resource_amount_for_city_state",
    "get_total_public_city_resource_storage_capacity_for_city_state",
    "get_total_stored_city_resource_amount_for_city_state",
    "get_total_physical_city_resource_amount_for_city_state",
    "get_total_owned_city_resource_amount_for_city_state",
    "get_total_owned_city_resource_amounts_for_city_state",
    "get_total_city_resource_storage_capacity_for_city_state",
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
    "get_city_object_unreserved_storage_free_space_for_city_state",
    "get_city_object_storage_capacity_for_resource",
    "get_city_object_stored_resource_amount",
    "get_city_object_resource_free_space",
    "set_city_object_stored_resource_amount_for_city_state",
    "add_resource_to_city_object_storage_for_city_state",
    "add_resource_bundle_to_city_object_storage_for_city_state",
    "remove_resource_from_city_object_storage_for_city_state",
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

# Citizen behavior systems expose only explicit aggregate-state entry points.
# Presentation selection is never a gameplay-state resolver.
CITIZEN_BEHAVIOR_SYSTEMS = {
    "registry": {
        "path": "scripts/citizens/simulation/systems/CityCitizenRegistrySystem.gd",
        "class_name": "CityCitizenRegistrySystem",
        "state_type": "CityCitizenRegistryState",
        "owner_field": "citizen_registry_state",
        "properties": tuple(WORLD_DATA_CITIZEN_REGISTRY_PROPERTIES),
        "functions": (
            "get_city_citizens_for_city_state",
            "get_city_citizen_version_for_city_state",
            "get_next_city_citizen_id_for_city_state",
            "reset_city_citizen_registry_state_for_city_state",
            "mark_city_citizens_changed_for_city_state",
            "rebuild_city_citizen_index_for_city_state",
            "register_city_citizen_index_for_city_state",
            "get_city_citizen_index_by_id_for_city_state",
            "get_city_population_count_for_city_state",
            "get_city_citizen_by_id_for_city_state",
            "get_city_citizen_snapshot_for_city_state",
            "get_city_citizen_display_name_for_city_state",
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
        "owner_field": "citizen_spatial_state",
        "properties": tuple(WORLD_DATA_CITIZEN_SPATIAL_PROPERTIES),
        "functions": (
            "get_city_citizen_spatial_version_for_city_state",
            "reset_city_citizen_spatial_state_for_city_state",
            "mark_city_citizen_spatial_changed_for_city_state",
            "add_city_citizen_to_spatial_index_for_city_state",
            "remove_city_citizen_from_spatial_index_for_city_state",
            "register_city_citizen_spatial_index_entry_for_city_state",
            "rebuild_city_citizen_spatial_index_for_city_state",
            "get_city_citizen_ids_at_tile_for_city_state",
            "has_living_city_citizen_at_tile_for_city_state",
            "ensure_city_citizen_spatial_state_for_city_state",
            "get_city_citizen_tile_position_for_city_state",
            "set_city_citizen_tile_position_for_city_state",
            "get_living_city_citizen_ids_in_tiles_for_city_state",
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
        "owner_field": "citizen_movement_runtime_state",
        "properties": tuple(WORLD_DATA_CITIZEN_MOVEMENT_RUNTIME_PROPERTIES),
        "functions": (
            "get_city_citizen_movement_version_for_city_state",
            "reset_city_citizen_movement_runtime_state_for_city_state",
            "mark_city_citizen_movement_changed_for_city_state",
            "_add_city_active_mover_id",
            "_remove_city_active_mover_id",
            "rebuild_city_active_mover_registry_for_city_state",
            "get_city_active_mover_ids_snapshot_for_city_state",
            "begin_city_citizen_movement_visual_tick_for_city_state",
            "clear_city_citizen_movement_visual_events_for_city_state",
            "take_city_citizen_movement_visual_events_for_city_state",
            "ensure_city_citizen_movement_state_for_city_state",
            "_get_clean_city_citizen_movement_path",
            "cancel_city_citizen_movement_for_city_state",
            "assign_city_citizen_movement_order_for_city_state",
            "commit_city_citizen_movement_tick_for_city_state",
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
        "owner_field": "citizen_task_runtime_state",
        "properties": tuple(WORLD_DATA_CITIZEN_TASK_RUNTIME_PROPERTIES),
        "functions": (
            "get_city_citizen_task_version_for_city_state",
            "reset_city_citizen_task_runtime_state_for_city_state",
            "mark_city_citizen_task_changed_for_city_state",
            "_add_city_active_task_id",
            "_remove_city_active_task_id",
            "_remove_all_city_active_task_array_entries",
            "rebuild_city_active_task_registry_for_city_state",
            "get_city_active_task_ids_snapshot_for_city_state",
            "get_city_citizen_current_haul_for_city_state",
            "set_city_citizen_current_haul_for_city_state",
            "get_city_food_task_reserved_endpoint_amount_for_city_state",
            "ensure_city_citizen_task_state_for_city_state",
            "get_city_citizen_current_task_for_city_state",
            "assign_city_citizen_task_for_city_state",
            "_make_city_citizen_task_assignment_context",
            "_prepare_city_citizen_task_assignment",
            "_prepare_city_work_task_assignment",
            "_prepare_city_food_task_assignment",
            "_prepare_city_player_command_task_assignment",
            "_prepare_city_haul_task_assignment",
            "_prepare_city_return_home_task_assignment",
            "_commit_city_citizen_task_assignment",
            "set_city_citizen_task_phase_for_city_state",
            "set_city_citizen_task_target_object_id_for_city_state",
            "set_city_citizen_task_activity_state_for_city_state",
            "clear_city_citizen_task_for_city_state",
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
CITIZEN_NAVIGATION_EXPLICIT_FUNCTIONS = (
    "city_citizen_can_access_object_interior_for_city_state",
    "get_city_citizen_movement_step_cost_for_city_state",
    "can_city_citizen_traverse_step_for_city_state",
    "_city_citizen_can_cross_object_boundary",
    "is_city_tile_walkable_for_citizen_for_city_state",
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
PASS9_CITIZEN_INVENTORY_EXPLICIT_FUNCTIONS = (
    "ensure_city_citizen_inventory_state_for_city_state",
    "get_city_citizen_carry_capacity_for_city_state",
    "set_city_citizen_carry_capacity_for_city_state",
    "get_city_citizen_inventory_for_city_state",
    "get_city_citizen_inventory_resource_amount_for_city_state",
    "get_city_citizen_inventory_used_capacity_for_city_state",
    "get_city_citizen_personal_inventory_free_space_for_city_state",
    "get_city_citizen_inventory_free_space_for_city_state",
    "set_city_citizen_inventory_resource_amount_for_city_state",
    "add_resource_to_city_citizen_inventory_for_city_state",
    "remove_resource_from_city_citizen_inventory_for_city_state",
    "get_city_citizen_haul_cargo_for_city_state",
    "get_city_citizen_haul_cargo_resources_for_city_state",
    "get_city_citizen_haul_cargo_resource_amount_for_city_state",
    "get_city_citizen_haul_cargo_resource_for_city_state",
    "get_city_citizen_haul_cargo_amount_for_city_state",
    "get_city_citizen_total_carried_amount_for_city_state",
    # This helper is intentionally record-explicit rather than aggregate-explicit.
    "get_city_citizen_record_carried_resource_amount",
    "get_city_citizen_available_haul_capacity_for_city_state",
    "set_city_citizen_haul_cargo_resources_for_city_state",
    "change_city_citizen_haul_cargo_resource_for_city_state",
    "set_city_citizen_haul_cargo_for_city_state",
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
PASS9_CITIZEN_NEEDS_EXPLICIT_FUNCTIONS = (
    "ensure_city_citizen_need_state_for_city_state",
    "get_city_citizen_hunger_for_city_state",
    "set_city_citizen_hunger_state_for_city_state",
    "get_city_citizen_happiness_for_city_state",
    "set_city_citizen_happiness_for_city_state",
    "_city_citizen_can_directly_withdraw_food",
    "_get_city_citizen_direct_food_withdrawal_target_tiles",
    "city_citizen_can_withdraw_food_from_endpoint_for_city_state",
    "get_city_citizen_food_endpoint_target_tiles_for_city_state",
    "get_city_food_endpoint_unreserved_amount_for_city_state",
    "transfer_city_food_endpoint_to_citizen_inventory_for_city_state",
    "run_tick_for_city_state",
    # This nutrition cap is configuration-only and has no settlement owner.
    "get_single_food_allocation_nutrition_cap",
    "get_citizen_food_need_nutrition_for_city_state",
    "get_citizen_next_food_allocation_nutrition_for_city_state",
    "citizen_should_seek_food_for_city_state",
    "citizen_has_critical_food_need_for_city_state",
    "eat_personal_food_if_hungry_for_city_state",
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
PASS9_CITIZEN_HAULING_EXPLICIT_FUNCTIONS = (
    "city_citizen_is_hauling_for_city_state",
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
            "ensure_city_citizen_inventory_state_for_city_state",
            "ensure_city_citizen_need_state_for_city_state",
        ),
        "_test_lossless_legacy_repair_and_identity": (
            "ensure_city_citizen_inventory_state_for_city_state",
            "ensure_city_citizen_need_state_for_city_state",
        ),
        "_test_headless_simulation_bootstrap_and_canonical_setters": (
            "run_settlement_simulation_systems",
            "set_city_citizen_inventory_resource_amount_for_city_state",
            "set_city_citizen_hunger_state_for_city_state",
        ),
        "_test_malformed_carried_state_quarantine": (
            "ensure_city_citizen_inventory_state_for_city_state",
            "get_city_citizen_inventory_free_space_for_city_state",
            "transfer_city_food_endpoint_to_citizen_inventory_for_city_state",
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
            "run_tick_for_city_state",
            "get_city_object_stored_resource_amount",
        ),
        "_test_hungry_citizens_reserve_before_household_stocking": (
            "_process_food_needs_for_city_state",
            "get_city_public_food_surplus_nutrition_for_city_state",
            "_get_scheduled_home_food_delivery_task_request_for_city_state",
        ),
    },
    "scripts/city/simulation/CityEmploymentFoodDeadlockTest.gd": {
        "_test_hunger_waits_for_real_food_opportunity": (
            "_process_player_commands_for_city_state",
            "_process_food_needs_for_city_state",
        ),
        "_test_starving_food_workers_keep_survival_schedule": (
            "_get_assigned_work_task_request_for_city_state",
            "_process_food_needs_for_city_state",
        ),
        "_test_starving_worker_recovers_and_returns_to_work": (
            "run_tick_for_city_state",
            "get_city_citizen_hunger_for_city_state",
            "get_city_object_stored_resource_amount",
        ),
        "_test_starving_residents_keep_return_home_schedule": (
            "_get_assigned_home_task_request_for_city_state",
            "_process_food_needs_for_city_state",
        ),
    },
    "scripts/city/simulation/CityUnifiedBoundaryTest.gd": {
        "_test_public_storage_keep_fallback": (
            "_validate_fixture_city",
            "get_total_physical_city_resource_amount_for_city_state",
            "get_city_citizen_haul_cargo_amount_for_city_state",
        ),
        "_test_critical_hunger_interrupts_cargo_safely": (
            "run_tick_for_city_state",
            "get_total_physical_city_resource_amount_for_city_state",
            "get_city_citizen_haul_cargo_amount_for_city_state",
        ),
    },
    "scripts/city/simulation/CityUnifiedWorkSystemTest.gd": {
        "_test_food_replenishment_cycle_and_whole_item_consumption": (
            "eat_personal_food_if_hungry_for_city_state",
            "citizen_has_critical_food_need_for_city_state",
        ),
        "_test_household_and_public_food_reserve_targets": (
            "get_city_home_food_target_nutrition_for_city_state",
            "get_city_public_food_reserve_target_nutrition_for_city_state",
            "find_best_household_food_source_for_city_state",
        ),
        "_test_normal_home_food_preference_allowance": (
            "_choose_normal_survival_food_result",
        ),
        "_test_survival_food_fallback_and_reservation_accounting": (
            "find_best_survival_food_source_for_city_state",
            "_assign_food_match",
            "get_city_food_endpoint_unreserved_amount_for_city_state",
        ),
    },
}

PASS9_FOCUSED_QUERY_CONSUMERS = {
    "scripts/ui/city/CityInformationPanel.gd": (
        "get_city_citizen_hunger_for_city_state",
        "get_city_citizen_happiness_for_city_state",
    ),
    "scripts/ui/debug/CitizenDebugPanel.gd": (
        "get_city_citizen_hunger_for_city_state",
        "get_city_citizen_happiness_for_city_state",
        "get_city_citizen_carry_capacity_for_city_state",
        "get_city_citizen_inventory_used_capacity_for_city_state",
        "get_city_citizen_haul_cargo_amount_for_city_state",
        "get_city_citizen_haul_cargo_resources_for_city_state",
        "city_citizen_is_hauling_for_city_state",
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


CITY_STATE_OWNER_FIELD_BY_TYPE = {
    "CityNavigationState": "navigation_state",
    "CityConstructionState": "construction_state",
    "CityObjectState": "object_state",
    "CityResourceAccountingState": "resource_accounting_state",
}


def gdscript_has_explicit_city_state_accessor(
    text: str,
    state_type: str,
) -> bool:
    """Validate the final explicit aggregate-state owner accessor."""

    explicit_signature = re.search(
        r"^static\s+func\s+get_state_for_city_state\s*\(\s*"
        r"city_state\s*:\s*CitySettlementSimulationState\s*\)"
        rf"\s*->\s*{re.escape(state_type)}\s*:",
        text,
        re.MULTILINE,
    )
    explicit_body = gdscript_function_body(text, "get_state_for_city_state")
    owner_field = CITY_STATE_OWNER_FIELD_BY_TYPE.get(state_type)
    if explicit_signature is None or explicit_body is None or owner_field is None:
        return False

    masked_body = gdscript_masked_code(explicit_body)
    if not re.search(
        rf"\breturn\s+city_state\s*\.\s*{re.escape(owner_field)}\b",
        masked_body,
    ):
        return False

    forbidden_authority = (
        r"\bWorldPoliticalState\b",
        r"\bactive_settlement_id\b",
        r"\bget_active_settlement\s*\(",
        r"\bget_active_city_simulation_state\s*\(",
        r"\bget_active_settlement_context\s*\(",
        r"\bget_current_city_",
        r"\bget_current_state\s*\(",
    )
    return not any(
        re.search(pattern, masked_body) for pattern in forbidden_authority
    )


def load_settlement_locality_guard():
    """Load the guard by exact repository path without executing its CLI."""

    guard_path = ROOT / "ci/settlement_locality_guard.py"
    if not guard_path.exists():
        raise FileNotFoundError(guard_path)
    module_name = "_paladin_settlement_locality_guard"
    spec = importlib.util.spec_from_file_location(module_name, guard_path)
    if spec is None or spec.loader is None:
        raise ImportError(f"could not load {guard_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def load_zero_unbound_compatibility_guard():
    """Load the final Pass 9 zero-leak guard without invoking its CLI."""

    guard_path = ROOT / "ci/zero_unbound_compatibility_guard.py"
    if not guard_path.exists():
        raise FileNotFoundError(guard_path)
    module_name = "_paladin_zero_unbound_compatibility_guard"
    spec = importlib.util.spec_from_file_location(module_name, guard_path)
    if spec is None or spec.loader is None:
        raise ImportError(f"could not load {guard_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def markdown_owner_inventory(
    document_text: str,
    section_heading: str,
) -> tuple[list[str], list[str]]:
    """Read the map's mechanically checkable first paragraph per owner."""

    heading_match = re.search(
        rf"^##\s+{re.escape(section_heading)}\s*$",
        document_text,
        re.MULTILINE,
    )
    if heading_match is None:
        return [], []

    section_start = heading_match.end()
    next_heading = re.search(
        r"^##\s+",
        document_text[section_start:],
        re.MULTILINE,
    )
    section_end = (
        section_start + next_heading.start()
        if next_heading is not None
        else len(document_text)
    )
    section_text = document_text[section_start:section_end]
    owner_matches = list(
        re.finditer(
            r"^###\s+`([^`]+)`[^\n]*$",
            section_text,
            re.MULTILINE,
        )
    )
    owners: list[str] = []
    symbols: list[str] = []
    for owner_index, owner_match in enumerate(owner_matches):
        owners.append(owner_match.group(1))
        owner_body_start = owner_match.end()
        owner_body_end = (
            owner_matches[owner_index + 1].start()
            if owner_index + 1 < len(owner_matches)
            else len(section_text)
        )
        owner_body = section_text[owner_body_start:owner_body_end]
        paragraph_lines: list[str] = []
        for line in owner_body.splitlines():
            if not paragraph_lines and not line.strip():
                continue
            if paragraph_lines and not line.strip():
                break
            paragraph_lines.append(line)
        symbols.extend(
            re.findall(
                r"`([A-Za-z_][A-Za-z0-9_]*)`",
                "\n".join(paragraph_lines),
            )
        )
    return owners, symbols


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

        if lower_name.endswith(".gd.uid"):
            script_path = Path(str(path)[:-4])
            if not script_path.exists():
                errors.append(f"{relative}: orphaned GDScript UID companion")

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

        uid_path = Path(str(path) + ".uid")
        if not uid_path.exists():
            errors.append(f"{relative}: missing required .gd.uid companion")

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

        if not path.name.endswith("Test.gd"):
            for comment_line_number, source_line in enumerate(lines, start=1):
                stripped_line = source_line.lstrip()
                if not stripped_line.startswith("#"):
                    continue
                comment_text = stripped_line[1:]
                for stale_pattern in FORBIDDEN_STALE_CITY_OWNERSHIP_COMMENT_PATTERNS:
                    if stale_pattern.search(comment_text) is None:
                        continue
                    errors.append(
                        f"{relative}:{comment_line_number}: "
                        "stale pre-explicit city-ownership comment"
                    )
                    break

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

    for retired_relative, retired_symbols in (
        PASS11_RETIRED_PRODUCTION_DECLARATIONS.items()
    ):
        retired_path = ROOT / retired_relative
        if not retired_path.exists():
            errors.append(f"{retired_relative}: missing Pass 11 production source")
            continue
        retired_text = retired_path.read_text(encoding="utf-8")
        for retired_symbol in retired_symbols:
            if re.search(
                rf"^(?:const|(?:static\s+)?var|(?:static\s+)?func)\s+"
                rf"{re.escape(retired_symbol)}\b",
                retired_text,
                re.MULTILINE,
            ):
                errors.append(
                    f"{retired_relative}: proven-dead Pass 11 declaration "
                    f"must not return: {retired_symbol}"
                )

    for retired_relative, retired_patterns in (
        PASS11_RETIRED_PRODUCTION_SOURCE_PATTERNS.items()
    ):
        retired_path = ROOT / retired_relative
        if not retired_path.exists():
            errors.append(f"{retired_relative}: missing Pass 11 production source")
            continue
        retired_text = retired_path.read_text(encoding="utf-8")
        for retired_label, retired_pattern in retired_patterns:
            if retired_pattern.search(retired_text):
                errors.append(
                    f"{retired_relative}: proven-dead Pass 11 source must not "
                    f"return: {retired_label}"
                )

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
            if not gdscript_has_explicit_city_state_accessor(
                navigation_system_text,
                "CityNavigationState",
            ):
                errors.append(
                    "scripts/city/simulation/systems/CityNavigationSystem.gd: "
                    "get_state_for_city_state must resolve only the explicit "
                    "navigation owner"
                )
            required_navigation_surfaces = (
                "static func reset_city_navigation_state_for_city_state(",
                "static func get_city_object_access_tiles_for_city_state(",
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
        if not gdscript_has_explicit_city_state_accessor(
            construction_system_text,
            "CityConstructionState",
        ):
            errors.append(
                "scripts/city/simulation/systems/CityConstructionSystem.gd: "
                "get_state_for_city_state must resolve only the explicit "
                "construction owner"
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
        if not gdscript_has_explicit_city_state_accessor(
            object_system_text,
            "CityObjectState",
        ):
            errors.append(
                "scripts/city/simulation/systems/CityObjectSystem.gd: "
                "get_state_for_city_state must resolve only the explicit object "
                "owner"
            )

        required_object_system_surfaces = (
            "static func get_city_object_snapshot_for_city_state(",
            "static func get_city_object_index_by_id_for_city_state(",
            "static func get_city_object_by_id_for_city_state(",
            "static func get_city_object_at_tile_for_city_state(",
            "static func register_completed_city_object_for_city_state(",
            "static func reset_city_object_state_for_city_state(",
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
            legacy_completion_call_count != 0
            or explicit_completion_call_count != 1
            or unrestricted_completion_call_count != 0
        ):
            errors.append(
                "scripts/city/simulation/systems/CityConstructionSystem.gd: "
                "construction finalization must use the explicit "
                "construction-site completion API exactly once and must not "
                "call a no-target or unrestricted registration API; found legacy="
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

        if not gdscript_has_explicit_city_state_accessor(
            resource_accounting_system_text,
            "CityResourceAccountingState",
        ):
            errors.append(
                "scripts/city/simulation/systems/CityResourceAccountingSystem.gd: "
                "get_state_for_city_state must resolve only the explicit "
                "resource-accounting owner"
            )

        required_political_accounting_surfaces = (
            "func get_city_resource_accounting_state():",
        )
        for required_surface in required_political_accounting_surfaces:
            if required_surface not in settlement_context_text:
                errors.append(
                    "scripts/world/simulation/SettlementSimulationContext.gd: "
                    "missing resource-accounting context accessor"
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
            expected_object_initializers = 1
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
        invalidation_tracker_path = (
            ROOT / "scripts/city/rendering/CityPresentationInvalidationTracker.gd"
        )
        citizen_presentation_path = (
            ROOT
            / "scripts/citizens/rendering/CityCitizenMovementPresentation.gd"
        )
        validator_path = ROOT / "scripts/city/simulation/CityStateValidator.gd"
        if renderer_path.exists():
            renderer_text = renderer_path.read_text(encoding="utf-8")
            invalidation_tracker_text = (
                invalidation_tracker_path.read_text(encoding="utf-8")
                if invalidation_tracker_path.exists()
                else ""
            )
            citizen_presentation_text = (
                citizen_presentation_path.read_text(encoding="utf-8")
                if citizen_presentation_path.exists()
                else ""
            )
            if (
                "var observed_city_citizen_registry_state: "
                "CityCitizenRegistryState" not in invalidation_tracker_text
                or "registry_owner_changed" not in invalidation_tracker_text
                or 'change_flags["city_citizen_registry_changed"]'
                not in invalidation_tracker_text
                or "city_state.citizen_registry_state"
                not in invalidation_tracker_text
                or "collect_city_state_change_flags" not in renderer_text
                or "city_citizen_movement_presentation.synchronize_for_changes("
                not in renderer_text
                or 'change_flags.get("city_citizen_registry_changed"'
                not in citizen_presentation_text
                or "initialize(bound_city_state)"
                not in citizen_presentation_text
            ):
                errors.append(
                    "scripts/city/rendering/CityRenderer.gd: citizen refresh "
                    "must include registry-state identity"
                )
        if validator_path.exists():
            validator_text = validator_path.read_text(encoding="utf-8")
            if (
                '"citizen_registry_state": city_state.citizen_registry_state'
                not in validator_text
                or 'entry.get("citizen_registry_state")' not in validator_text
                or '"citizen_registry_state_instance_id"' not in validator_text
            ):
                errors.append(
                    "scripts/city/simulation/CityStateValidator.gd: explicit "
                    "validation cache must include citizen-registry identity"
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
        invalidation_tracker_path = (
            ROOT / "scripts/city/rendering/CityPresentationInvalidationTracker.gd"
        )
        validator_path = ROOT / "scripts/city/simulation/CityStateValidator.gd"
        if renderer_path.exists():
            renderer_text = renderer_path.read_text(encoding="utf-8")
            invalidation_tracker_text = (
                invalidation_tracker_path.read_text(encoding="utf-8")
                if invalidation_tracker_path.exists()
                else ""
            )
            if (
                "var observed_city_citizen_spatial_state: "
                "CityCitizenSpatialState" not in invalidation_tracker_text
                or "spatial_owner_changed" not in invalidation_tracker_text
                or "city_state.citizen_spatial_state"
                not in invalidation_tracker_text
                or "collect_city_state_change_flags" not in renderer_text
            ):
                errors.append(
                    "scripts/city/rendering/CityRenderer.gd: citizen spatial "
                    "refresh must include state-owner identity"
                )
        if validator_path.exists():
            validator_text = validator_path.read_text(encoding="utf-8")
            if (
                '"citizen_spatial_state": city_state.citizen_spatial_state'
                not in validator_text
                or 'entry.get("citizen_spatial_state")' not in validator_text
                or '"citizen_spatial_state_instance_id"' not in validator_text
            ):
                errors.append(
                    "scripts/city/simulation/CityStateValidator.gd: explicit "
                    "validation cache must include citizen-spatial identity"
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
        invalidation_tracker_path = (
            ROOT / "scripts/city/rendering/CityPresentationInvalidationTracker.gd"
        )
        validator_path = ROOT / "scripts/city/simulation/CityStateValidator.gd"
        if renderer_path.exists():
            renderer_text = renderer_path.read_text(encoding="utf-8")
            invalidation_tracker_text = (
                invalidation_tracker_path.read_text(encoding="utf-8")
                if invalidation_tracker_path.exists()
                else ""
            )
            if (
                "var observed_city_citizen_movement_runtime_state: "
                "CityCitizenMovementRuntimeState" not in invalidation_tracker_text
                or "movement_owner_changed" not in invalidation_tracker_text
                or "city_state.citizen_movement_runtime_state"
                not in invalidation_tracker_text
                or 'change_flags["city_citizen_movement_runtime_changed"]'
                not in invalidation_tracker_text
                or "collect_city_state_change_flags" not in renderer_text
            ):
                errors.append(
                    "scripts/city/rendering/CityRenderer.gd: citizen "
                    "movement refresh must include runtime-owner identity"
                )
        if validator_path.exists():
            validator_text = validator_path.read_text(encoding="utf-8")
            if (
                '"citizen_movement_runtime_state": city_state.citizen_movement_runtime_state'
                not in validator_text
                or 'entry.get("citizen_movement_runtime_state")' not in validator_text
                or '"citizen_movement_runtime_state_instance_id"'
                not in validator_text
            ):
                errors.append(
                    "scripts/city/simulation/CityStateValidator.gd: explicit "
                    "validation cache must include citizen movement-runtime "
                    "identity"
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
        invalidation_tracker_path = (
            ROOT / "scripts/city/rendering/CityPresentationInvalidationTracker.gd"
        )
        validator_path = ROOT / "scripts/city/simulation/CityStateValidator.gd"
        if renderer_path.exists():
            renderer_text = renderer_path.read_text(encoding="utf-8")
            invalidation_tracker_text = (
                invalidation_tracker_path.read_text(encoding="utf-8")
                if invalidation_tracker_path.exists()
                else ""
            )
            if (
                "var observed_city_citizen_task_runtime_state: "
                "CityCitizenTaskRuntimeState" not in invalidation_tracker_text
                or "task_owner_changed" not in invalidation_tracker_text
                or "city_state.citizen_task_runtime_state"
                not in invalidation_tracker_text
                or 'change_flags["city_citizen_task_runtime_changed"]'
                not in invalidation_tracker_text
                or "collect_city_state_change_flags" not in renderer_text
            ):
                errors.append(
                    "scripts/city/rendering/CityRenderer.gd: citizen task "
                    "refresh must include runtime-owner identity"
                )
        if validator_path.exists():
            validator_text = validator_path.read_text(encoding="utf-8")
            if (
                '"citizen_task_runtime_state": city_state.citizen_task_runtime_state'
                not in validator_text
                or 'entry.get("citizen_task_runtime_state")' not in validator_text
                or '"citizen_task_runtime_state_instance_id"'
                not in validator_text
            ):
                errors.append(
                    "scripts/city/simulation/CityStateValidator.gd: explicit "
                    "validation cache must include citizen task-runtime identity"
                )

    # Pass 9: focused citizen behavior APIs are explicit aggregate-state
    # boundaries. Their retired WorldData spellings remain forbidden.
    moved_world_data_symbols: set[str] = set(CITIZEN_NAVIGATION_MOVED_FUNCTIONS)
    moved_world_data_symbols.update(CITIZEN_SCHEMA_MOVED_FUNCTIONS)
    compatibility_properties: set[str] = set(
        CITIZEN_SCHEMA_WORLD_DATA_RETIRED_PROPERTIES
    )

    for domain_name, config in CITIZEN_BEHAVIOR_SYSTEMS.items():
        system_path = ROOT / str(config["path"])
        required_functions = set(config["functions"])
        moved_world_data_symbols.update(
            function_name.removesuffix("_for_city_state")
            for function_name in required_functions
        )
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

        owner_field = str(config["owner_field"])
        if not re.search(
            rf"\bcity_state\s*\.\s*{re.escape(owner_field)}\b",
            gdscript_masked_code(system_text),
        ):
            errors.append(
                f"{config['path']}: explicit APIs must resolve "
                f"city_state.{owner_field}"
            )

        declared_functions = set(FUNC_RE.findall(system_text))
        missing_functions = sorted(required_functions - declared_functions)
        if missing_functions:
            errors.append(
                f"{config['path']}: missing focused citizen behavior: "
                + ", ".join(missing_functions)
            )

        for property_name in config["properties"]:
            for path in scripts:
                text = path.read_text(encoding="utf-8")
                if re.search(
                    rf"^static\s+var\s+"
                    rf"{re.escape(str(property_name))}\b",
                    text,
                    re.MULTILINE,
                ):
                    errors.append(
                        f"{path.relative_to(ROOT)}: retired static current-state "
                        f"property must not return: "
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
            set(CITIZEN_NAVIGATION_EXPLICIT_FUNCTIONS) - navigation_functions
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
                rf"^const\s+{re.escape(property_name)}\b",
                citizen_schema_text,
                re.MULTILINE,
            ):
                errors.append(
                    "scripts/citizens/simulation/CityCitizens.gd: missing "
                    f"immutable citizen schema property {property_name}"
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

    renderer_path = ROOT / "scripts/city/rendering/CityRenderer.gd"
    invalidation_tracker_path = (
        ROOT / "scripts/city/rendering/CityPresentationInvalidationTracker.gd"
    )
    validator_path = ROOT / "scripts/city/simulation/CityStateValidator.gd"
    renderer_bound_state_surfaces = {
        "CityCitizenRegistryState": "bound_city_state.citizen_registry_state",
        "CityCitizenSpatialState": "bound_city_state.citizen_spatial_state",
        "CityCitizenMovementRuntimeState": (
            "bound_city_state.citizen_movement_runtime_state"
        ),
        "CityCitizenTaskRuntimeState": (
            "bound_city_state.citizen_task_runtime_state"
        ),
    }
    validator_bound_state_surfaces = {
        "CityCitizenRegistryState": "city_state.citizen_registry_state",
        "CityCitizenSpatialState": "city_state.citizen_spatial_state",
        "CityCitizenMovementRuntimeState": (
            "city_state.citizen_movement_runtime_state"
        ),
        "CityCitizenTaskRuntimeState": (
            "city_state.citizen_task_runtime_state"
        ),
    }
    for consumer_path, consumer_name in (
        (renderer_path, "renderer"),
        (validator_path, "validator"),
    ):
        if not consumer_path.exists():
            continue
        consumer_text = consumer_path.read_text(encoding="utf-8")
        for config in CITIZEN_BEHAVIOR_SYSTEMS.values():
            if consumer_name == "renderer":
                required_surface = renderer_bound_state_surfaces[
                    config["state_type"]
                ]
                tracker_surface = required_surface.replace(
                    "bound_city_state.",
                    "city_state.",
                )
                tracker_text = (
                    invalidation_tracker_path.read_text(encoding="utf-8")
                    if invalidation_tracker_path.exists()
                    else ""
                )
            else:
                required_surface = validator_bound_state_surfaces[
                    config["state_type"]
                ]
                tracker_surface = ""
                tracker_text = ""
            if (
                required_surface not in consumer_text
                and (
                    consumer_name != "renderer"
                    or tracker_surface not in tracker_text
                    or "collect_city_state_change_flags" not in consumer_text
                )
            ):
                errors.append(
                    f"{consumer_path.relative_to(ROOT)}: citizen {consumer_name} "
                    f"must resolve {config['state_type']} through "
                    f"{required_surface}"
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
            PASS9_CITIZEN_INVENTORY_EXPLICIT_FUNCTIONS,
            PASS9_CITIZEN_INVENTORY_PRIMITIVE_MUTATORS,
            True,
        ),
        (
            PASS9_CITIZEN_NEEDS_SYSTEM_PATH,
            "CitizenNeedsSystem",
            PASS9_CITIZEN_NEEDS_EXPLICIT_FUNCTIONS,
            PASS9_CITIZEN_NEEDS_PRIMITIVE_MUTATORS,
            True,
        ),
        (
            PASS9_CITIZEN_HAULING_SYSTEM_PATH,
            "CitizenHaulingSystem",
            PASS9_CITIZEN_HAULING_EXPLICIT_FUNCTIONS,
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
            and "city_state.citizen_registry_state" not in system_text
        ):
            errors.append(
                f"{system_relative}: explicit citizen entry points must route "
                "through city_state.citizen_registry_state"
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
    pass4_context_text = (
        pass4_context_path.read_text(encoding="utf-8")
        if pass4_context_path.exists()
        else ""
    )
    if any(
        required_surface not in pass4_context_text
        for required_surface in (
            "func supports_detailed_simulation()",
            "func get_detailed_simulation_state()",
            "func supports_city_simulation()",
            "func get_city_simulation_state()",
        )
    ):
        errors.append(
            f"{pass4_context_relative}: Pass 4 requires a neutral detailed-"
            "simulation capability/state surface with city compatibility"
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

    pass4_context_test_path = ROOT / (
        "scripts/world/simulation/ExplicitSettlementSimulationContextTest.gd"
    )
    if pass4_context_test_path.exists():
        pass4_context_test_text = pass4_context_test_path.read_text(
            encoding="utf-8"
        )
        for required_token in (
            "_test_detailed_simulation_capability_is_settlement_scoped()",
            "supports_detailed_simulation()",
            "get_detailed_simulation_state()",
            "SettlementData.SETTLEMENT_TYPE_VILLAGE",
            "SettlementData.SETTLEMENT_TYPE_OUTPOST",
        ):
            if required_token not in pass4_context_test_text:
                errors.append(
                    "scripts/world/simulation/"
                    "ExplicitSettlementSimulationContextTest.gd: missing "
                    "neutral detailed-settlement rejection assertion "
                    f"{required_token}"
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

        for retired_pass11_api in (
            "set_workplace_desired_worker_count_for_city_state",
            "_set_workplace_desired_worker_count",
        ):
            if gdscript_function_body(
                pass6_employment_text,
                retired_pass11_api,
            ) is not None:
                errors.append(
                    f"{pass6_employment_relative}: Pass 11 removed dead "
                    f"employment compatibility API {retired_pass11_api}"
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
        explicit_completion_body = gdscript_function_body(
            pr8_work_text,
            "complete_city_player_command_for_city_state",
        ) or ""
        if (
            "remove_tile_surface_feature(" not in explicit_completion_body
            or "set_tile_surface_feature(" not in explicit_completion_body
        ):
            errors.append(
                f"{pr8_work_relative}: PR 8 "
                "complete_city_player_command_for_city_state must use owner "
                "remove/restore APIs"
            )

    pr8_catalog_relative = "scripts/city/data/CityObjectCatalog.gd"
    pr8_catalog_path = ROOT / pr8_catalog_relative
    if not pr8_catalog_path.exists():
        errors.append(f"{pr8_catalog_relative}: missing PR 8 immutable catalog")
    else:
        pr8_catalog_text = pr8_catalog_path.read_text(encoding="utf-8")
        stockpile_definition_match = re.search(
            r"^\s*_city_object_definitions\[CITY_OBJECT_STOCKPILE\]\s*=\s*"
            r"\(\s*make_city_object_definition\(\{(?P<body>.*?)^\s*\}\)\s*\)",
            pr8_catalog_text,
            re.MULTILINE | re.DOTALL,
        )
        if stockpile_definition_match is None:
            errors.append(
                f"{pr8_catalog_relative}: Pass 11 could not find the canonical "
                "Stockpile definition"
            )
        else:
            stockpile_size_matches = re.findall(
                r'^\s*"size"\s*:\s*Vector2i\(\s*(-?\d+)\s*,\s*'
                r'(-?\d+)\s*\)\s*,?\s*$',
                stockpile_definition_match.group("body"),
                re.MULTILINE,
            )
            if stockpile_size_matches != [("2", "2")]:
                errors.append(
                    f"{pr8_catalog_relative}: Pass 11 Stockpile footprint must "
                    "remain exactly Vector2i(2, 2); found "
                    f"{stockpile_size_matches}"
                )
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
            "get_city_objects_for_city_state",
            "get_city_object_by_id_for_city_state",
            "get_city_object_at_tile_for_city_state",
            "patch_city_object_assignment_fields_for_city_state",
            "patch_city_object_workplace_fields_for_city_state",
            "patch_city_object_storage_fields_for_city_state",
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
        ) < 1:
            errors.append(
                f"{pr8_object_relative}: PR 8 explicit registration must "
                "publish recursively read-only records"
            )

    pr8_focused_owner_contracts = (
        (
            "scripts/citizens/simulation/systems/CityAssignmentSystem.gd",
            "_set_city_object_resident_capacity",
            (
                "patch_city_object_assignment_fields_for_city_state(",
            ),
        ),
        (
            "scripts/citizens/simulation/systems/CityEmploymentSystem.gd",
            "_set_city_workplace_worker_capacity",
            (
                "patch_city_object_workplace_fields_for_city_state(",
            ),
        ),
        (
            "scripts/city/simulation/systems/CityResourceContainerSystem.gd",
            "",
            (
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
                "get_city_objects_for_city_state(",
                "get_city_object_at_tile_for_city_state(",
                "is_read_only()",
                "write_city_object_at_index_for_city_state(",
                "add_resource_to_city_object_storage_for_city_state(",
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

    # Settlement-locality PR 4: CityRenderer is configured before _ready(),
    # retains one explicit context/state/world binding, and never discovers
    # settlement-local authority through active/current compatibility APIs.
    pr4_renderer_relative = "scripts/city/rendering/CityRenderer.gd"
    pr4_session_relative = "scripts/session/GameSession.gd"
    pr4_test_relative = (
        "scripts/city/rendering/CityRendererExplicitBindingTest.gd"
    )
    pr4_scene_relative = (
        "scripts/city/rendering/CityRendererExplicitBindingTest.tscn"
    )
    pr4_renderer_path = ROOT / pr4_renderer_relative
    pr4_session_path = ROOT / pr4_session_relative
    pr4_test_path = ROOT / pr4_test_relative
    pr4_scene_path = ROOT / pr4_scene_relative
    if pr4_renderer_path.exists():
        pr4_renderer_text = pr4_renderer_path.read_text(encoding="utf-8")
        pr4_renderer_masked = gdscript_masked_code(pr4_renderer_text)
        for required_api in (
            "configure_initial_city_presentation",
            "get_bound_settlement_context",
            "can_rebind_city_presentation",
            "rebind_city_presentation",
            "validate_city_presentation_binding",
        ):
            if not re.search(
                rf"^func\s+{re.escape(required_api)}\s*\(",
                pr4_renderer_text,
                re.MULTILINE,
            ):
                errors.append(
                    f"{pr4_renderer_relative}: missing PR 4 explicit binding "
                    f"API {required_api}"
                )
        for required_surface in (
            "var bound_settlement_context: SettlementSimulationContext",
            "var bound_city_state: CitySettlementSimulationState",
            "var bound_city_settlement_id: int",
            "var city_world: WorldData",
            "var city_seed: int",
        ):
            if required_surface not in pr4_renderer_text:
                errors.append(
                    f"{pr4_renderer_relative}: missing PR 4 binding surface "
                    f"{required_surface}"
                )
        forbidden_renderer_patterns = (
            r"\bWorldPoliticalState\.active_settlement_id\b",
            r"\bWorldPoliticalState\.get_active_city_simulation_state\s*\(",
            r"\bWorldPoliticalState\.get_current_city_",
            r"\.get_current_state\s*\(",
            r"\bCityWorkSystem\.get_current_work_state\s*\(",
            r"\bWorldData\.has_active_city_save\s*\(",
            r"\bWorldData\.store_city_world_save\s*\(",
            r"\bWorldData\.reset_player_city_state\s*\(",
        )
        for pattern in forbidden_renderer_patterns:
            if re.search(pattern, pr4_renderer_masked):
                errors.append(
                    f"{pr4_renderer_relative}: PR 4 renderer still discovers "
                    f"local authority through {pattern}"
                )
        pr4_ready_body = gdscript_function_body(
            pr4_renderer_text,
            "_ready",
        ) or ""
        for forbidden_ready_token in (
            "SimulationClock.resume_simulation(",
            "CitySettlementRuntimeBootstrap",
            "ensure_city_citizen_",
            "reset_city_simulation_runtime_state(",
        ):
            if forbidden_ready_token in pr4_ready_body:
                errors.append(
                    f"{pr4_renderer_relative}: PR 4 _ready() must remain "
                    f"presentation-only; found {forbidden_ready_token}"
                )
    else:
        errors.append(f"{pr4_renderer_relative}: missing PR 4 renderer")

    if pr4_session_path.exists():
        pr4_session_text = pr4_session_path.read_text(encoding="utf-8")
        pr4_ensure_body = gdscript_function_body(
            pr4_session_text,
            "_ensure_city_view",
        ) or ""
        pr4_switch_body = gdscript_function_body(
            pr4_session_text,
            "show_settlement_view",
        ) or ""
        for required_token in (
            '"configure_initial_settlement_presentation"',
            '"configure_initial_city_presentation"',
            "add_child(city_view)",
            "_select_first_city_detailed_simulation_target()",
            "_commit_first_city_entry()",
        ):
            if required_token not in pr4_ensure_body:
                errors.append(
                    f"{pr4_session_relative}: PR 4 first-entry transaction "
                    f"is missing {required_token}"
                )
        if (
            pr4_ensure_body.find("configure_method,")
            > pr4_ensure_body.find("add_child(city_view)")
        ):
            errors.append(
                f"{pr4_session_relative}: renderer must be configured before "
                "it enters the tree"
            )
        for required_token in (
            "_bootstrap_city_context(target_context)",
            "rebind_method,",
            "WorldPoliticalState.set_active_settlement(settlement_id)",
        ):
            if required_token not in pr4_switch_body:
                errors.append(
                    f"{pr4_session_relative}: PR 4 switch transaction is "
                    f"missing {required_token}"
                )
        pr4_bootstrap_index = pr4_switch_body.find(
            "_bootstrap_city_context(target_context)"
        )
        pr4_rebind_index = pr4_switch_body.find(
            "rebind_method,",
            pr4_bootstrap_index + 1,
        )
        pr4_publish_index = pr4_switch_body.find(
            "WorldPoliticalState.set_active_settlement(settlement_id)",
            pr4_rebind_index + 1,
        )
        if not (
            pr4_bootstrap_index >= 0
            and pr4_rebind_index > pr4_bootstrap_index
            and pr4_publish_index > pr4_rebind_index
        ):
            errors.append(
                f"{pr4_session_relative}: PR 4 switch must bootstrap, bind, "
                "then publish global presentation selection"
            )
    else:
        errors.append(f"{pr4_session_relative}: missing PR 4 session owner")

    for required_path in (pr4_test_path, pr4_scene_path):
        if not required_path.exists():
            errors.append(
                f"{required_path.relative_to(ROOT)}: missing permanent PR 4 "
                "explicit renderer-binding coverage"
            )
    if pr4_test_path.exists():
        pr4_test_text = pr4_test_path.read_text(encoding="utf-8")
        for required_token in (
            "set_active_settlement(city_b_id)",
            "bootstrap_and_configure_renderer(",
            "SimulationClock.simulation_paused",
            "run_settlement_simulation_systems(",
            "rebind_city_presentation(context_b)",
            "rebind_city_presentation(context_a)",
            "_capture_gameplay_snapshot(state_a)",
            "_capture_gameplay_snapshot(state_b)",
        ):
            if required_token not in pr4_test_text:
                errors.append(
                    f"{pr4_test_relative}: PR 4 regression is missing "
                    f"required assertion surface {required_token}"
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
            "show_settlement_view",
        ) or ""
        for required_token in (
            "cancel_city_preparation()",
            "SimulationClock.set_simulation_paused(true)",
            "WorldPoliticalState.set_active_settlement(settlement_id)",
            '"rebind_settlement_presentation"',
            '"validate_settlement_presentation_binding"',
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
        pr9_legacy_switch_body = gdscript_function_body(
            pr9_session_text,
            "show_settlement_city_view",
        ) or ""
        if "return show_settlement_view(settlement_id, prepared_payload)" not in (
            pr9_legacy_switch_body
        ):
            errors.append(
                f"{pr9_session_relative}: legacy city-view entry must forward "
                "to the canonical settlement presentation route"
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
            "_bind_city_presentation_references(",
            "rebuild_city_terrain_texture()",
            "rebuild_city_natural_feature_multimeshes()",
            "_configure_city_camera_for_bound_settlement()",
            "_capture_bound_city_presentation_versions(bound_city_state)",
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
            "show_settlement_view(city_b_id)",
            "show_settlement_city_view(city_a_id)",
            "SettlementData.SETTLEMENT_TYPE_VILLAGE",
            "SettlementData.SETTLEMENT_TYPE_OUTPOST",
            "not session.show_settlement_view(village_id)",
            "not session.show_settlement_view(outpost_id)",
            "settlement_natural_feature_presenter.tree_index_by_tile",
            "settlement_natural_feature_presenter.rock_index_by_tile",
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
                "show_settlement_view",
                "select_detailed_simulation_settlement(settlement_id)",
            ),
            (
                "_ensure_city_view",
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

        required_assignment_functions = (
            "get_city_assignment_version_for_city_state",
            "mark_city_assignments_changed_for_city_state",
            "ensure_city_citizen_assignment_state_for_city_state",
            "get_city_housed_citizen_count_for_city_state",
            "get_city_unemployed_citizen_count_for_city_state",
            "get_city_object_resident_ids_for_city_state",
            "get_city_object_worker_ids_for_city_state",
            "assign_homeless_citizens_to_available_housing_for_city_state",
            "assign_city_citizen_home_for_city_state",
            "remove_city_citizen_home_for_city_state",
            "assign_city_citizen_job_for_city_state",
            "remove_city_citizen_job_for_city_state",
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
        if "city_state.assignment_state" not in assignment_system_text:
            errors.append(
                "scripts/citizens/simulation/systems/CityAssignmentSystem.gd: "
                "explicit APIs must resolve city_state.assignment_state"
            )

        required_employment_functions = (
            "get_city_workplace_version_for_city_state",
            "mark_city_workplaces_changed_for_city_state",
            "ensure_workplace_staffing_state_for_city_state",
            "reconcile_automatic_workplaces_for_city_state",
            "is_city_citizen_attending_workplace_for_city_state",
            "get_city_object_attending_worker_ids_for_city_state",
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
        if "city_state.workplace_state" not in employment_system_text:
            errors.append(
                "scripts/citizens/simulation/systems/CityEmploymentSystem.gd: "
                "explicit APIs must resolve city_state.workplace_state"
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
        invalidation_tracker_path = (
            ROOT / "scripts/city/rendering/CityPresentationInvalidationTracker.gd"
        )
        invalidation_tracker_text = (
            invalidation_tracker_path.read_text(encoding="utf-8")
            if invalidation_tracker_path.exists()
            else ""
        )
        validator_text = validator_path.read_text(encoding="utf-8") if validator_path.exists() else ""
        for required_surface in (
            "var observed_city_assignment_state: CityAssignmentState",
            "var observed_city_workplace_state: CityWorkplaceState",
            "city_state.assignment_state",
            "city_state.workplace_state",
            "not is_same(",
        ):
            if required_surface not in invalidation_tracker_text:
                errors.append(
                    "scripts/city/rendering/CityPresentationInvalidationTracker.gd: "
                    "missing identity-aware "
                    f"Pass 10 invalidation surface: {required_surface}"
                )
        if "collect_city_state_change_flags" not in renderer_text:
            errors.append(
                "scripts/city/rendering/CityRenderer.gd: assignment/workplace "
                "invalidation must delegate to CityPresentationInvalidationTracker"
            )
        for required_surface in (
            '"assignment_state": city_state.assignment_state',
            '"workplace_state": city_state.workplace_state',
            'entry.get("assignment_state")',
            'entry.get("workplace_state")',
            '"assignment_state_instance_id"',
            '"workplace_state_instance_id"',
            "not is_same(",
        ):
            if required_surface not in validator_text:
                errors.append(
                    "scripts/city/simulation/CityStateValidator.gd: missing "
                    "explicit identity-aware Pass 10 cache surface: "
                    f"{required_surface}"
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

    # Settlement-local validation must never rediscover authority through the
    # globally selected/current City. The validator coordinator accepts an
    # explicit registered context (or explicit state for headless tests), and
    # every domain validator receives the same target Dictionary first.
    validator_contract_paths = (
        ROOT / "scripts/city/simulation/CityStateValidator.gd",
        ROOT / "scripts/city/simulation/validators/CityCitizenStateValidator.gd",
        ROOT / "scripts/city/simulation/validators/CityLogisticsStateValidator.gd",
        ROOT / "scripts/city/simulation/validators/CityObjectStateValidator.gd",
    )
    validator_forbidden_authority_patterns = (
        r"\bWorldPoliticalState\s*\.\s*active_settlement_id\b",
        r"\bWorldPoliticalState\s*\.\s*get_active_city_simulation_state\s*\(",
        r"\bWorldPoliticalState\s*\.\s*get_current_city_",
        r"\b[A-Z][A-Za-z0-9_]*System(?:Script)?\s*\.\s*get_current_state\s*\(",
        r"\bCityWorkSystem(?:Script)?\s*\.\s*get_current_work_state\s*\(",
    )
    for validator_contract_path in validator_contract_paths:
        if not validator_contract_path.exists():
            errors.append(
                f"{validator_contract_path.relative_to(ROOT)}: missing "
                "settlement-local validator contract"
            )
            continue
        validator_contract_text = validator_contract_path.read_text(
            encoding="utf-8"
        )
        masked_validator_contract_text = gdscript_masked_code(
            validator_contract_text
        )
        for forbidden_pattern in validator_forbidden_authority_patterns:
            if re.search(forbidden_pattern, masked_validator_contract_text):
                errors.append(
                    f"{validator_contract_path.relative_to(ROOT)}: explicit "
                    "validator must not resolve active/current City authority"
                )
                break

    if validator_path.exists():
        explicit_validator_text = validator_path.read_text(encoding="utf-8")
        for required_function in (
            "validate_for_settlement",
            "validate_for_city_state",
            "get_summary_text_for_settlement",
            "get_summary_text_for_city_state",
            "clear_cache_for_settlement",
            "clear_all_validation_caches",
        ):
            if not re.search(
                rf"^static\s+func\s+{required_function}\s*\(",
                explicit_validator_text,
                re.MULTILINE,
            ):
                errors.append(
                    "scripts/city/simulation/CityStateValidator.gd: missing "
                    f"explicit validator API {required_function}"
                )
        for retired_function in ("validate", "get_summary_text"):
            if re.search(
                rf"^static\s+func\s+{retired_function}\s*\(",
                explicit_validator_text,
                re.MULTILINE,
            ):
                errors.append(
                    "scripts/city/simulation/CityStateValidator.gd: retired "
                    f"no-target API must not return: {retired_function}"
                )
        for required_cache_surface in (
            "const MAX_CACHED_SETTLEMENTS",
            "static var _cache_by_settlement_id",
            "static var _cache_recency",
            'entry.get("city_state")',
            'entry.get("city_world")',
            '"city_state_instance_id"',
            '"city_world_instance_id"',
        ):
            if required_cache_surface not in explicit_validator_text:
                errors.append(
                    "scripts/city/simulation/CityStateValidator.gd: missing "
                    "bounded exact-identity cache surface: "
                    f"{required_cache_surface}"
                )

    for domain_validator_path in validator_contract_paths[1:]:
        if not domain_validator_path.exists():
            continue
        domain_validator_text = domain_validator_path.read_text(encoding="utf-8")
        for function_match in FUNC_RE.finditer(domain_validator_text):
            function_name = function_match.group(1)
            explicit_first_parameter = re.search(
                rf"^static\s+func\s+{re.escape(function_name)}\s*\(\s*"
                r"validation_target\s*:\s*Dictionary\s*(?:,|\))",
                domain_validator_text,
                re.MULTILINE,
            )
            if explicit_first_parameter is None:
                errors.append(
                    f"{domain_validator_path.relative_to(ROOT)}: "
                    f"{function_name} must receive validation_target first"
                )

    validator_test_path = (
        ROOT / "scripts/city/simulation/CityStateValidatorExplicitContextTest.gd"
    )
    validator_test_scene_path = validator_test_path.with_suffix(".tscn")
    for required_path in (validator_test_path, validator_test_scene_path):
        if not required_path.exists():
            errors.append(
                f"{required_path.relative_to(ROOT)}: missing explicit validator "
                "A/B cache-isolation coverage"
            )

    # The presentation identity is now settlement-neutral. CityPresentationBinding
    # is an honest capability adapter for the one detailed backend implemented
    # today; it is not the universal identity contract. Every retained helper
    # receives one exact token and has a pure preflight, monotonic commit, and
    # reset that preserves its generation high-water mark.
    neutral_binding_relative = (
        "scripts/settlements/presentation/SettlementPresentationBinding.gd"
    )
    neutral_binding_path = ROOT / neutral_binding_relative
    city_binding_relative = "scripts/city/rendering/CityPresentationBinding.gd"
    city_binding_path = ROOT / city_binding_relative
    presentation_helper_contracts = {
        "scripts/ui/city/CityInformationPanel.gd": "reset_presentation",
        "scripts/ui/debug/CitizenDebugPanel.gd": "reset",
        "scripts/city/rendering/CityDebugPresentation.gd": "reset",
        "scripts/citizens/rendering/CityCitizenMovementPresentation.gd": (
            "reset_presentation"
        ),
        "scripts/city/rendering/CityWorkplaceZoneOverlayCache.gd": (
            "reset_presentation"
        ),
        "scripts/ui/city/CityObjectPanelAnchor.gd": "reset_presentation",
        "scripts/settlements/presentation/SettlementPlacementController.gd": (
            "reset_presentation"
        ),
        "scripts/settlements/presentation/SettlementSelectionController.gd": (
            "reset_presentation"
        ),
        "scripts/settlements/presentation/SettlementCommandController.gd": (
            "reset_presentation"
        ),
        "scripts/settlements/presentation/SettlementUiController.gd": (
            "reset_presentation"
        ),
        "scripts/settlements/presentation/SettlementInfrastructurePresenter.gd": (
            "reset_presentation"
        ),
        "scripts/map/visuals/SettlementNaturalFeaturePresenter.gd": (
            "reset_presentation"
        ),
    }
    presentation_helper_forbidden_patterns = (
        r"\bWorldPoliticalState\s*\.\s*active_settlement_id\b",
        r"\bWorldPoliticalState\s*\.\s*get_active_city_simulation_state\s*\(",
        r"\bWorldPoliticalState\s*\.\s*get_current_city_",
        r"\b[A-Z][A-Za-z0-9_]*System(?:Script)?\s*\.\s*get_current_state\s*\(",
        r"\bCityWorkSystem(?:Script)?\s*\.\s*get_current_work_state\s*\(",
        r"\bCityStateValidator(?:Script)?\s*\.\s*get_summary_text\s*\(",
        r"\bCityStateValidator(?:Script)?\s*\.\s*validate\s*\(",
        r"\bCityCitizenRegistrySystem\s*\.\s*get_city_population_count\s*\(",
        r"\bCityCitizenRegistrySystem\s*\.\s*get_city_citizen_by_id\s*\(",
        r"\bCityCitizenSpatialSystem\s*\.\s*get_city_citizen_ids_at_tile\s*\(",
        r"\bCityCitizenMovementRuntimeSystem\s*\.\s*get_city_active_mover_ids_snapshot\s*\(",
        r"\bCityCitizenTaskRuntimeSystem\s*\.\s*get_city_active_task_ids_snapshot\s*\(",
        r"\bCityCitizenTaskRuntimeSystem\s*\.\s*get_city_citizen_current_(?:task|haul)\s*\(",
        r"\bCitizenNeedsSystem\s*\.\s*get_city_citizen_(?:hunger|happiness)\s*\(",
        r"\bCitizenHaulingSystem\s*\.\s*city_citizen_is_hauling\s*\(",
        r"\bCityCitizenInventorySystem\s*\.\s*get_city_citizen_(?:carry_capacity|inventory_used_capacity|haul_cargo_amount|haul_cargo_resources)\s*\(",
        r"\bCityObjectSystem\s*\.\s*get_city_object_(?:by_id|at_tile)\s*\(",
        r"\bCityConstructionSystem(?:Script)?\s*\.\s*get_city_construction_site_by_id\s*\(",
        r"\bCityLogisticsSystem\s*\.\s*get_city_ground_pile_by_id\s*\(",
        r"\bCityNavigationSystem(?:Script)?\s*\.\s*get_city_citizen_movement_step_cost\s*\(",
    )

    if not neutral_binding_path.exists():
        errors.append(
            f"{neutral_binding_relative}: missing settlement-neutral presentation "
            "identity token"
        )
    else:
        neutral_binding_text = neutral_binding_path.read_text(encoding="utf-8")
        for required_surface in (
            "class_name SettlementPresentationBinding",
            "var settlement_context: SettlementSimulationContext",
            "var settlement_id: int",
            "var polity_id: int",
            "var settlement_type: String",
            "var backend_kind: String",
            "var backend_state:",
            "var generation: int",
            "var highest_accepted_generation: int",
            "CAPABILITY_CITY_DETAIL",
            "CAPABILITY_SETTLEMENT_WORLD",
            "CAPABILITY_DETERMINISTIC_SEED",
            "func can_rebind(",
            "func rebind(",
            "func reset(",
            "func accepts_generation(",
            "func is_valid(",
            "func matches_context(",
            "func matches_binding(",
            "func supports_backend_capability(",
            "func get_backend_capability(",
        ):
            if required_surface not in neutral_binding_text:
                errors.append(
                    f"{neutral_binding_relative}: "
                    f"missing binding surface {required_surface}"
                )
        neutral_can_rebind_body = gdscript_function_body(
            neutral_binding_text,
            "can_rebind",
        ) or ""
        for one_shot_token in (
            "_highest_accepted_generation == 0",
            "_settlement_context == null",
            "binding_generation > 0",
            "WorldPoliticalState.is_registered_settlement_context(context)",
        ):
            if one_shot_token not in neutral_can_rebind_body:
                errors.append(
                    f"{neutral_binding_relative}: immutable one-shot preflight "
                    f"is missing {one_shot_token}"
                )
        neutral_reset_body = gdscript_function_body(
            neutral_binding_text,
            "reset",
        ) or ""
        if re.search(r"_highest_accepted_generation\s*=", neutral_reset_body):
            errors.append(
                f"{neutral_binding_relative}: reset must preserve the token's "
                "one-shot generation high-water mark"
            )

    if not city_binding_path.exists():
        errors.append(f"{city_binding_relative}: missing city-detail adapter")
    else:
        city_binding_text = city_binding_path.read_text(encoding="utf-8")
        for adapter_token in (
            'extends "res://scripts/settlements/presentation/SettlementPresentationBinding.gd"',
            "class_name CityPresentationBinding",
            "context.supports_detailed_simulation()",
            "context.get_detailed_simulation_state()",
            "context.settlement_type != SettlementData.SETTLEMENT_TYPE_CITY",
            "CAPABILITY_CITY_DETAIL",
            "CAPABILITY_SETTLEMENT_WORLD",
            "CAPABILITY_DETERMINISTIC_SEED",
        ):
            if adapter_token not in city_binding_text:
                errors.append(
                    f"{city_binding_relative}: city-detail adapter is missing "
                    f"{adapter_token}"
                )

    for helper_relative, required_functions in presentation_helper_contracts.items():
        helper_path = ROOT / helper_relative
        if not helper_path.exists():
            errors.append(f"{helper_relative}: missing PR 6 presentation helper")
            continue
        helper_text = helper_path.read_text(encoding="utf-8")
        masked_helper_text = gdscript_masked_code(helper_text)
        if not re.search(
            r"^var\s+presentation_binding\s*:\s*(?:SettlementPresentationBindingScript|CityPresentationBinding)\b",
            helper_text,
            re.MULTILINE,
        ):
            errors.append(
                f"{helper_relative}: helper must retain the renderer's exact "
                "settlement presentation token"
            )
        for required_function in (
            "can_bind_settlement_presentation",
            "bind_settlement_presentation",
            "is_bound_to_settlement_presentation",
            required_functions,
        ):
            if not re.search(
                rf"^func\s+{re.escape(required_function)}\s*\(",
                helper_text,
                re.MULTILINE,
            ):
                errors.append(
                    f"{helper_relative}: missing PR 6 helper boundary "
                    f"{required_function}"
                )
        for forbidden_pattern in presentation_helper_forbidden_patterns:
            if re.search(forbidden_pattern, masked_helper_text):
                errors.append(
                    f"{helper_relative}: renderer-owned helper must not "
                    "resolve active/current or no-target City authority"
                )
                break
        preflight_body = gdscript_function_body(
            helper_text,
            "can_bind_settlement_presentation",
        ) or ""
        if re.search(
            r"(?:presentation_binding|highest_accepted_binding_generation)\s*=",
            preflight_body,
        ):
            errors.append(
                f"{helper_relative}: binding preflight must be non-mutating"
            )
        bind_body = gdscript_function_body(
            helper_text,
            "bind_settlement_presentation",
        ) or ""
        if not re.search(
            r"highest_accepted_binding_generation\s*=",
            bind_body,
        ):
            errors.append(
                f"{helper_relative}: successful binding must advance a "
                "generation high-water mark"
            )
        reset_body = gdscript_function_body(helper_text, required_functions) or ""
        if "presentation_binding = null" not in reset_body:
            errors.append(
                f"{helper_relative}: reset must clear the active presentation "
                "token"
            )
        if re.search(
            r"highest_accepted_binding_generation\s*=",
            reset_body,
        ):
            errors.append(
                f"{helper_relative}: reset must preserve the binding "
                "generation high-water mark"
            )

    renderer_binding_path = ROOT / "scripts/city/rendering/CityRenderer.gd"
    if renderer_binding_path.exists():
        renderer_binding_text = renderer_binding_path.read_text(encoding="utf-8")
        renderer_binding_body = gdscript_function_body(
            renderer_binding_text,
            "_bind_city_presentation_helpers",
        ) or ""
        for required_helper in (
            "city_information_ui.bind_settlement_presentation",
            "city_debug_presentation.citizen_debug_panel.bind_settlement_presentation",
            "settlement_entity_panel_presentation.bind_settlement_presentation",
            "city_citizen_movement_presentation.bind_settlement_presentation",
            "settlement_placement_controller.bind_settlement_presentation",
            "settlement_selection_controller.bind_settlement_presentation",
            "settlement_command_controller.bind_settlement_presentation",
            "settlement_ui_controller.bind_settlement_presentation",
            "settlement_infrastructure_presenter.bind_settlement_presentation",
            "workplace_zone_overlay_cache.bind_settlement_presentation",
            "city_debug_presentation.bind_settlement_presentation",
            "settlement_natural_feature_presenter.bind_settlement_presentation",
        ):
            if required_helper not in renderer_binding_body:
                errors.append(
                    "scripts/city/rendering/CityRenderer.gd: PR 6 binding "
                    f"does not configure {required_helper}"
                )
        for required_surface in (
            "var city_presentation_binding: CityPresentationBinding",
            "var city_presentation_binding_generation: int",
            "func get_city_presentation_binding() -> CityPresentationBinding:",
            "func get_settlement_presentation_binding() -> SettlementPresentationBindingScript:",
        ):
            if required_surface not in renderer_binding_text:
                errors.append(
                    "scripts/city/rendering/CityRenderer.gd: missing PR 6 "
                    f"binding-generation surface {required_surface}"
                )
        debug_presentation_text = (
            ROOT / "scripts/city/rendering/CityDebugPresentation.gd"
        ).read_text(encoding="utf-8")
        if "find_path_to_any_city_tile_for_city_state(" not in debug_presentation_text:
            errors.append(
                "scripts/city/rendering/CityDebugPresentation.gd: debug "
                "navigation must use the explicit bound settlement state"
            )
        if "find_path_to_any_city_tile({" in debug_presentation_text:
            errors.append(
                "scripts/city/rendering/CityDebugPresentation.gd: debug "
                "navigation must pass the bound settlement state explicitly"
            )

    camera_state_path = ROOT / "scripts/map/MapCameraSessionState.gd"
    if camera_state_path.exists():
        camera_state_text = camera_state_path.read_text(encoding="utf-8")
        for required_surface in (
            "city_camera_state_by_settlement_id",
            "store_city_camera_for_binding",
            "get_city_camera_for_binding",
            '"city_state_ref": weakref(binding.city_state)',
            '"city_world_ref": weakref(binding.city_world)',
        ):
            if required_surface not in camera_state_text:
                errors.append(
                    "scripts/map/MapCameraSessionState.gd: missing exact "
                    f"settlement camera identity surface {required_surface}"
                )
        for retired_surface in (
            "static var has_city_camera_state",
            "static var city_camera_position",
            "static var city_camera_zoom",
            "static func store_city_camera(",
        ):
            if retired_surface in camera_state_text:
                errors.append(
                    "scripts/map/MapCameraSessionState.gd: unkeyed city "
                    f"camera state must remain retired: {retired_surface}"
                )

    texture_state_path = ROOT / "scripts/map/visuals/MapTextureCacheState.gd"
    if texture_state_path.exists():
        texture_state_text = texture_state_path.read_text(encoding="utf-8")
        for required_surface in (
            "world_source_ref: WeakRef",
            "city_source_ref: WeakRef",
            "weakref(source_world)",
            "weakref(source_city_world)",
            "is_same(cached_world, source_world)",
            "is_same(cached_city_world, source_city_world)",
        ):
            if required_surface not in texture_state_text:
                errors.append(
                    "scripts/map/visuals/MapTextureCacheState.gd: shared "
                    f"texture cache lacks exact source identity {required_surface}"
                )

    helper_test_path = (
        ROOT / "scripts/city/rendering/CityPresentationHelperBindingTest.gd"
    )
    helper_test_scene_path = helper_test_path.with_suffix(".tscn")
    for required_path in (helper_test_path, helper_test_scene_path):
        if not required_path.exists():
            errors.append(
                f"{required_path.relative_to(ROOT)}: missing PR 6 A/B helper "
                "binding regression"
            )
    if helper_test_path.exists():
        helper_test_text = helper_test_path.read_text(encoding="utf-8")
        for required_token in (
            "WorldPoliticalState.set_active_settlement(city_b_id)",
            "information_ui.bind_settlement_presentation(binding_a)",
            "citizen_debug.bind_city_presentation(binding_a)",
            "debug_presentation.bind_city_presentation(",
            "movement_presentation.bind_settlement_presentation(binding_a, 16)",
            "overlay_cache.bind_settlement_presentation(binding_a)",
            "MapCameraSessionStateScript.store_city_camera_for_binding(",
            "MapTextureCacheStateScript.has_valid_city_cache(",
            "replacement_binding_a.rebind(replacement_context_a, 3)",
        ):
            if required_token not in helper_test_text:
                errors.append(
                    "scripts/city/rendering/CityPresentationHelperBindingTest.gd: "
                    f"missing PR 6 collision coverage {required_token}"
                )

    neutral_binding_test_relative = (
        "scripts/settlements/presentation/SettlementPresentationBindingTest.gd"
    )
    neutral_binding_test_path = ROOT / neutral_binding_test_relative
    for required_path in (
        neutral_binding_path.with_suffix(".gd.uid"),
        city_binding_path.with_suffix(".gd.uid"),
        neutral_binding_test_path,
        neutral_binding_test_path.with_suffix(".gd.uid"),
        neutral_binding_test_path.with_suffix(".tscn"),
    ):
        if not required_path.exists():
            errors.append(
                f"{required_path.relative_to(ROOT)}: missing neutral binding "
                "source identity or runnable regression"
            )
    if neutral_binding_test_path.exists():
        neutral_binding_test_text = neutral_binding_test_path.read_text(
            encoding="utf-8"
        )
        for required_test_token in (
            "SettlementData.SETTLEMENT_TYPE_VILLAGE",
            "SettlementData.SETTLEMENT_TYPE_OUTPOST",
            "not city_binding.rebind(village_context, 1)",
            "City-detail consumers must reject a valid token with no city capability.",
            "newer_binding.highest_accepted_generation == 4",
        ):
            if required_test_token not in neutral_binding_test_text:
                errors.append(
                    f"{neutral_binding_test_relative}: missing universal "
                    f"identity/capability regression {required_test_token}"
                )

    # Post-PR-7.6 Pass 8: all active/current settlement-locality scopes are
    # closed, and city-world persistence is explicitly targeted. The final
    # Pass 9 zero-leak gate below additionally rejects every retired unbound or
    # no-target compatibility surface.
    try:
        locality_guard = load_settlement_locality_guard()
        locality_hits = []
        for locality_path in locality_guard.production_scripts():
            locality_relative = locality_path.relative_to(ROOT).as_posix()
            locality_hits.extend(
                locality_guard.scan_text(
                    locality_relative,
                    locality_path.read_text(encoding="utf-8"),
                )
            )
        locality_counts, locality_first_hits = locality_guard.inventory(
            locality_hits
        )
        if locality_counts:
            first_key = sorted(locality_counts)[0]
            first_hit = locality_first_hits[first_key]
            errors.append(
                "ci/settlement_locality_guard.py: post-PR-7.6 Pass 8 requires "
                "zero exact active/current locality scopes; found "
                f"{len(locality_counts)} scopes / {len(locality_hits)} references "
                f"(first: {first_hit.path}:{first_hit.line} "
                f"{first_hit.scope} via {first_hit.token})"
            )

        transitional_name = "CityCitizenUnboundCompatibility"
        for locality_path in locality_guard.production_scripts():
            locality_relative = locality_path.relative_to(ROOT).as_posix()
            locality_text = locality_guard.strip_comments_and_strings(
                locality_path.read_text(encoding="utf-8")
            )
            locality_scopes = locality_guard.function_scope_by_line(
                locality_text
            )
            for line_number, line in enumerate(
                locality_text.splitlines(),
                start=1,
            ):
                if transitional_name not in line:
                    continue
                scope = locality_scopes[line_number - 1]
                if locality_guard.is_explicit_target_scope(scope):
                    errors.append(
                        f"{locality_relative}:{line_number}: explicit-target "
                        f"function {scope} must not use transitional "
                        f"{transitional_name}; Pass 8 allows it only behind "
                        "no-target compatibility gateways"
                    )
    except Exception as error:  # The audit must report a broken ratchet clearly.
        errors.append(
            "ci/settlement_locality_guard.py: could not evaluate the post-PR-7.6 "
            f"Pass 8 zero-scope ratchet: {error}"
        )

    # Post-PR-7.6 Pass 9: the final current/unbound gameplay backend is gone.
    # The dedicated guard scans production, tests, and dev helpers, restricts
    # presentation-selection authority, and fails closed on unexplained mutable
    # production statics.
    try:
        zero_unbound_guard = load_zero_unbound_compatibility_guard()
        if zero_unbound_guard.main() != 0:
            errors.append(
                "ci/zero_unbound_compatibility_guard.py: post-PR-7.6 Pass 9 "
                "zero-leak guard failed"
            )
    except Exception as error:
        errors.append(
            "ci/zero_unbound_compatibility_guard.py: could not evaluate the "
            f"post-PR-7.6 Pass 9 zero-leak guard: {error}"
        )

    pass9_fixture_relative = (
        "scripts/city/simulation/test_support/CitySettlementTestFixture.gd"
    )
    pass9_fixture_path = ROOT / pass9_fixture_relative
    if not pass9_fixture_path.exists():
        errors.append(
            f"{pass9_fixture_relative}: missing reusable Pass 9 registered "
            "settlement fixture"
        )
    else:
        pass9_fixture_text = pass9_fixture_path.read_text(encoding="utf-8")
        for required_token in (
            "class_name CitySettlementTestFixture",
            "static func create(",
            "var fixture = load(",
            "WorldPoliticalState.create_polity(",
            "WorldPoliticalState.create_settlement(",
            "WorldPoliticalState.get_settlement_context(",
            "WorldPoliticalState.is_registered_settlement_context(",
            "func cleanup()",
            "WorldData.reset_runtime_session_state()",
        ):
            if required_token not in pass9_fixture_text:
                errors.append(
                    f"{pass9_fixture_relative}: Pass 9 fixture is missing "
                    f"{required_token}"
                )
        for forbidden_self_reference in (
            "-> CitySettlementTestFixture",
            "CitySettlementTestFixture.new()",
        ):
            if forbidden_self_reference in pass9_fixture_text:
                errors.append(
                    f"{pass9_fixture_relative}: fixture factory must not depend "
                    "on a writable global-class cache; found "
                    f"{forbidden_self_reference}"
                )

    fixture_preload_pattern = re.compile(
        r"\bconst\s+CitySettlementTestFixtureScript\s*=\s*preload\(\s*"
        r'"res://scripts/city/simulation/test_support/'
        r'CitySettlementTestFixture\.gd"\s*\)',
        re.MULTILINE,
    )
    for fixture_caller_path in sorted(ROOT.rglob("*Test.gd")):
        fixture_caller_text = fixture_caller_path.read_text(encoding="utf-8")
        fixture_caller_code = gdscript_masked_code(fixture_caller_text)
        uses_fixture_alias = (
            "CitySettlementTestFixtureScript.create(" in fixture_caller_code
        )
        bare_fixture_reference = re.search(
            r"\bCitySettlementTestFixture\b",
            fixture_caller_code,
        )
        if bare_fixture_reference is not None:
            fixture_caller_relative = fixture_caller_path.relative_to(ROOT)
            errors.append(
                f"{fixture_caller_relative}: tests must not resolve "
                "CitySettlementTestFixture through the global-class cache; "
                "preload CitySettlementTestFixtureScript and call its factory"
            )
        if uses_fixture_alias and fixture_preload_pattern.search(
            fixture_caller_text
        ) is None:
            fixture_caller_relative = fixture_caller_path.relative_to(ROOT)
            errors.append(
                f"{fixture_caller_relative}: fixture factory use requires the "
                "explicit CitySettlementTestFixtureScript preload"
            )

    pass9_regressions = {
        "scripts/city/simulation/CityLegacyBackendRemovalTest.gd": (
            "_test_registered_city_backend_contract",
            "_test_stale_context_rejects_without_mutation",
            "FAILURE_UNREGISTERED_CONTEXT",
            "SimulationCoordinator.run_settlement_simulation_systems(",
            "_capture_all_state_values(stale_state)",
        ),
        "scripts/city/simulation/CityWorkspaceRemovalTest.gd": (
            "_test_explicit_city_runtime_storage",
            "_test_failed_bootstrap_is_atomic_and_retryable",
            "FAILURE_CITY_SEED_MISMATCH",
        ),
        "scripts/city/rendering/CityRendererExplicitBindingTest.gd": (
            "run_settlement_simulation_systems(",
			"CITY_STATE_VALIDATOR.validate_for_settlement(",
            "complete_city_player_command_for_city_state(",
            "_capture_overlap_projection(state_control)",
            "_capture_deterministic_projection(state_control)",
            "_capture_script_variable_values(",
            "_capture_gameplay_snapshot(state_b)",
            "rebind_city_presentation(context_b)",
            "rebind_city_presentation(context_a)",
        ),
        "scripts/session/SettlementPresentationRebindTest.gd": (
            "not session.show_settlement_city_view(city_b_id",
            "A rejected rebind must leave the prior binding retryable",
        ),
        "scripts/world/simulation/ExplicitSettlementSimulationContextTest.gd": (
            "run_settlement_simulation_systems(",
            "_deterministic_projection(state_a)",
            "_deterministic_projection(state_b)",
        ),
        "scripts/world/simulation/CityEmploymentLifecycleTest.gd": (
            "_test_settlement_local_employment_lifecycle",
            "Explicit assignment must reject a foreign-only citizen",
            "_capture_employment_state(state_a) == a_before_foreign_rejections",
            "_capture_employment_state(state_b) == b_before_foreign_rejections",
        ),
    }
    for pass9_relative, required_tokens in pass9_regressions.items():
        pass9_path = ROOT / pass9_relative
        pass9_scene_path = pass9_path.with_suffix(".tscn")
        if not pass9_path.exists() or not pass9_scene_path.exists():
            errors.append(
                f"{pass9_relative}: missing permanent Pass 9 regression or scene"
            )
            continue
        pass9_text = pass9_path.read_text(encoding="utf-8")
        for required_token in required_tokens:
            if required_token not in pass9_text:
                errors.append(
                    f"{pass9_relative}: Pass 9 regression is missing "
                    f"{required_token}"
                )

    pass9_dev_relative = "scripts/dev/DevCityLauncher.gd"
    pass9_dev_path = ROOT / pass9_dev_relative
    if pass9_dev_path.exists():
        pass9_dev_text = pass9_dev_path.read_text(encoding="utf-8")
        for required_token in (
            "GameSession.request_next_session_city_entry()",
            "tree.change_scene_to_file(game_session_scene_path)",
        ):
            if required_token not in pass9_dev_text:
                errors.append(
                    f"{pass9_dev_relative}: Dev City must enter through the "
                    f"registered GameSession path; missing {required_token}"
                )
        if "change_scene_to_file(city_scene_path)" in pass9_dev_text:
            errors.append(
                f"{pass9_dev_relative}: Dev City must not launch CityScreen "
                "without a registered settlement context"
            )
    else:
        errors.append(f"{pass9_dev_relative}: missing Pass 9 Dev City launcher")

    pass9_renderer_relative = "scripts/city/rendering/CityRenderer.gd"
    pass9_renderer_path = ROOT / pass9_renderer_relative
    if pass9_renderer_path.exists():
        pass9_renderer_text = pass9_renderer_path.read_text(encoding="utf-8")
        pass9_ready_body = gdscript_function_body(
            pass9_renderer_text,
            "_ready",
        ) or ""
        for required_token in (
            "_has_valid_bound_city_presentation()",
            "configure_initial_settlement_presentation()",
            "PROCESS_MODE_DISABLED",
            "visible = false",
        ):
            if required_token not in pass9_ready_body:
                errors.append(
                    f"{pass9_renderer_relative}: direct CityScreen launch must "
                    f"fail clearly without fabricating local state; missing {required_token}"
                )

    # Final renderer decomposition: CityRenderer is a bounded scene facade and
    # every retained member is assigned to its implemented responsibility owner.
    # The durable map is exact-source checked so facade centrality cannot regrow
    # unnoticed.
    pass10_map_relative = "docs/CITY_RENDERER_DECOMPOSITION_MAP.md"
    pass10_map_path = ROOT / pass10_map_relative
    pass10_renderer_relative = "scripts/city/rendering/CityRenderer.gd"
    pass10_renderer_path = ROOT / pass10_renderer_relative
    pass10_tracker_relative = (
        "scripts/city/rendering/CityPresentationInvalidationTracker.gd"
    )
    pass10_tracker_path = ROOT / pass10_tracker_relative
    pass10_binding_relative = (
        "scripts/settlements/presentation/SettlementPresentationBinding.gd"
    )
    pass10_binding_path = ROOT / pass10_binding_relative

    if not pass10_map_path.exists():
        errors.append(
            f"{pass10_map_relative}: missing complete Pass 10 renderer "
            "decomposition map"
        )
    elif not pass10_renderer_path.exists():
        errors.append(
            f"{pass10_renderer_relative}: missing Pass 10 facade source"
        )
    else:
        pass10_map_text = pass10_map_path.read_text(encoding="utf-8")
        pass10_renderer_text = pass10_renderer_path.read_text(encoding="utf-8")
        source_fields = {
            match.group(1)
            for match in CITY_RENDERER_TOP_LEVEL_FIELD_RE.finditer(
                pass10_renderer_text
            )
        }
        source_functions = {
            match.group(1) for match in FUNC_RE.finditer(pass10_renderer_text)
        }
        inventory_contracts = (
            (
                "Complete field inventory",
                source_fields,
                "field",
            ),
            (
                "Complete function inventory",
                source_functions,
                "function",
            ),
        )
        for section_heading, source_symbols, symbol_kind in inventory_contracts:
            documented_owners, documented_symbols = markdown_owner_inventory(
                pass10_map_text,
                section_heading,
            )
            if not documented_owners:
                errors.append(
                    f"{pass10_map_relative}: missing mechanically checkable "
                    f"{section_heading}"
                )
                continue

            owner_counts = collections.Counter(documented_owners)
            missing_owners = sorted(
                set(CITY_RENDERER_DECOMPOSITION_OWNERS)
                - set(documented_owners)
            )
            duplicate_owners = sorted(
                owner
                for owner, count in owner_counts.items()
                if count != 1
            )
            if missing_owners or duplicate_owners:
                errors.append(
                    f"{pass10_map_relative}: {section_heading} must contain "
                    "each implemented responsibility owner exactly once; missing="
                    f"{missing_owners}, duplicates={duplicate_owners}"
                )

            symbol_counts = collections.Counter(documented_symbols)
            duplicate_symbols = sorted(
                symbol
                for symbol, count in symbol_counts.items()
                if count != 1
            )
            documented_symbol_set = set(documented_symbols)
            missing_symbols = sorted(source_symbols - documented_symbol_set)
            extra_symbols = sorted(documented_symbol_set - source_symbols)
            if missing_symbols or extra_symbols or duplicate_symbols:
                errors.append(
                    f"{pass10_map_relative}: CityRenderer {symbol_kind} "
                    "inventory is not exact; missing="
                    f"{missing_symbols}, extra={extra_symbols}, "
                    f"duplicates={duplicate_symbols}"
                )

        for required_heading_or_term in (
            "## Confirmed current behavior and timing",
            "## Binding and authority contract",
            "## Current component boundaries",
            "## Characterization matrix",
            "## Decomposition result and remaining facade boundary",
            "## Decomposition durability rules",
            "Confirmed",
            "Implemented owner",
            "Dependencies",
            "Mutable",
            "rebind",
            "reset",
            "characterization",
        ):
            if required_heading_or_term not in pass10_map_text:
                errors.append(
                    f"{pass10_map_relative}: decomposition map is missing "
                    f"required behavior/ownership term {required_heading_or_term}"
                )

        for future_owner in CITY_RENDERER_DECOMPOSITION_OWNERS:
            boundary_row_match = re.search(
                rf"^\|\s*`{re.escape(future_owner)}`[^\n]*$",
                pass10_map_text,
                re.MULTILINE,
            )
            if boundary_row_match is None:
                errors.append(
                    f"{pass10_map_relative}: missing current boundary row for "
                    f"{future_owner}"
                )
                continue
            boundary_row = boundary_row_match.group(0).lower()
            if "rebind" not in boundary_row or not any(
                reset_term in boundary_row for reset_term in ("reset", "clear")
            ):
                errors.append(
                    f"{pass10_map_relative}: {future_owner} needs one clear "
                    "rebind and reset entry-point contract"
                )

        for matrix_behavior in (
            "Initial explicit bind",
            "A -> B -> A",
            "Stale generation rejection",
            "Version invalidation",
            "Terrain cache",
            "Natural features",
            "Citizen draw/movement",
            "Objects, roads, construction, piles, overlays",
            "Building placement",
            "Road drag",
            "Player commands",
            "Selection/hover",
            "Panels and viewport safety",
            "Debug navigation/path",
            "Camera per settlement",
            "Hidden/inactive renderer then reveal",
            "Pure redraw/rebind mutates no gameplay",
            "Pause/speed",
        ):
            if not re.search(
                rf"^\|\s*{re.escape(matrix_behavior)}\b",
                pass10_map_text,
                re.MULTILINE,
            ):
                errors.append(
                    f"{pass10_map_relative}: characterization matrix is "
                    f"missing {matrix_behavior}"
                )

        for stable_api in (
            "rebind_city_presentation",
            "can_rebind_city_presentation",
            "reset",
            "reset_observations",
            "is_bound_to_city_presentation",
            "accepts_generation",
            "capture_current_versions",
            "create_change_flags",
            "collect_city_state_change_flags",
            "collect_city_world_version_change_flags",
        ):
            if stable_api not in pass10_map_text:
                errors.append(
                    f"{pass10_map_relative}: decomposition map is "
                    f"missing stable tracker API {stable_api}"
                )

    # Fail-closed size and centrality budgets. These limits leave a small amount
    # of formatting headroom but make a return to the former 8,383-line god
    # object structurally impossible without an explicit audit update.
    if pass10_renderer_path.exists():
        decomposed_renderer_text = pass10_renderer_path.read_text(encoding="utf-8")
        renderer_line_count = len(decomposed_renderer_text.splitlines())
        renderer_function_count = len(FUNC_RE.findall(decomposed_renderer_text))
        renderer_var_count = len(
            CITY_RENDERER_TOP_LEVEL_FIELD_RE.findall(decomposed_renderer_text)
        )
        renderer_const_count = len(
            re.findall(
                r"^(?:static\s+)?const\s+[A-Za-z_][A-Za-z0-9_]*\b",
                decomposed_renderer_text,
                re.MULTILINE,
            )
        )
        renderer_declaration_count = renderer_var_count + renderer_const_count
        for measured, maximum, metric_name in (
            (renderer_line_count, 2800, "physical lines"),
            (renderer_function_count, 155, "top-level functions"),
            (renderer_declaration_count, 90, "top-level var+const declarations"),
        ):
            if measured > maximum:
                errors.append(
                    f"{pass10_renderer_relative}: decomposition budget exceeded "
                    f"for {metric_name}: {measured} > {maximum}"
                )

        forbidden_gameplay_dependencies = (
            "CityResourceContainerSystem",
            "CityCitizenMovementRuntimeSystem",
            "CityCitizenRegistrySystem",
            "CityObjectSystem",
            "CityConstructionSystem",
            "CityLogisticsSystem",
            "CityWorkSystem",
            "CityAssignmentSystem",
            "CityEmploymentSystem",
            "WorkplaceProductionSystem",
        )
        for forbidden_dependency in forbidden_gameplay_dependencies:
            if re.search(
                rf"\b{re.escape(forbidden_dependency)}(?:Script)?\b",
                gdscript_masked_code(decomposed_renderer_text),
            ):
                errors.append(
                    f"{pass10_renderer_relative}: facade must not regain direct "
                    f"gameplay-system dependency {forbidden_dependency}"
                )
        for forbidden_authoritative_surface in (
            "place_immediate_settlement_object_for_context(",
            "found_city_settlement(",
            "set_active_settlement(",
        ):
            if forbidden_authoritative_surface in gdscript_masked_code(
                decomposed_renderer_text
            ):
                errors.append(
                    f"{pass10_renderer_relative}: facade must not regain "
                    "authoritative gameplay mutation "
                    f"{forbidden_authoritative_surface}"
                )
        if re.search(
            r"\b(?:bound_city_state|city_world)\s*\.\s*"
            r"[A-Za-z_][A-Za-z0-9_]*\s*(?:=|\+=|-=|\*=|/=)",
            gdscript_masked_code(decomposed_renderer_text),
        ):
            errors.append(
                f"{pass10_renderer_relative}: facade must not assign into the "
                "bound gameplay state or world"
            )

        renderer_helper_recovery_body = gdscript_function_body(
            decomposed_renderer_text,
            "_recover_city_presentation_binding_after_failed_commit",
        ) or ""
        for recovery_token in (
            "failed_generation",
            "rollback_generation := city_presentation_binding_generation + 1",
            "_can_bind_city_presentation_helpers(rollback_binding)",
            "_bind_city_presentation_helpers(rollback_binding)",
            "city_presentation_invalidation_tracker.rebind_city_presentation(",
            "_publish_city_presentation_binding(",
        ):
            if recovery_token not in renderer_helper_recovery_body:
                errors.append(
                    f"{pass10_renderer_relative}: failed-helper recovery is "
                    f"missing {recovery_token}"
                )

    required_component_sources = (
        "scripts/settlements/presentation/SettlementPresentationBinding.gd",
        "scripts/settlements/presentation/SettlementPlacementController.gd",
        "scripts/settlements/presentation/SettlementSelectionController.gd",
        "scripts/settlements/presentation/SettlementCommandController.gd",
        "scripts/settlements/presentation/SettlementInfrastructurePresenter.gd",
        "scripts/settlements/presentation/SettlementUiController.gd",
        "scripts/map/visuals/SettlementNaturalFeaturePresenter.gd",
        "scripts/citizens/rendering/CityCitizenMovementPresentation.gd",
        "scripts/ui/city/CityObjectPanelAnchor.gd",
        "scripts/city/rendering/CityDebugPresentation.gd",
    )
    for component_relative in required_component_sources:
        component_path = ROOT / component_relative
        for required_path in (
            component_path,
            component_path.with_suffix(".gd.uid"),
        ):
            if not required_path.exists():
                errors.append(
                    f"{required_path.relative_to(ROOT)}: missing extracted "
                    "presentation component identity"
                )

    required_component_tests = (
        "scripts/settlements/presentation/SettlementPresentationBindingTest.gd",
        "scripts/settlements/presentation/SettlementSelectionControllerTest.gd",
        "scripts/settlements/presentation/SettlementCommandControllerTest.gd",
        "scripts/settlements/presentation/SettlementInfrastructurePresenterTest.gd",
        "scripts/settlements/presentation/SettlementUiControllerTest.gd",
        "scripts/citizens/rendering/CityCitizenMovementPresentationTest.gd",
        "scripts/ui/city/CityObjectPanelAnchorTest.gd",
    )
    for test_relative in required_component_tests:
        test_path = ROOT / test_relative
        for required_path in (
            test_path,
            test_path.with_suffix(".gd.uid"),
            test_path.with_suffix(".tscn"),
        ):
            if not required_path.exists():
                errors.append(
                    f"{required_path.relative_to(ROOT)}: missing runnable "
                    "extracted-component regression"
                )

    # Settlement-named production components are reusable boundaries. They may
    # request explicit backend capabilities, but may never receive the facade,
    # discover a presentation target, or branch on settlement type.
    settlement_component_paths = [
        ROOT / relative
        for relative in required_component_sources
        if Path(relative).name.startswith("Settlement")
        and Path(relative).name != "SettlementPresentationBinding.gd"
    ]
    settlement_component_forbidden_patterns = (
        r"\bCityRenderer\b",
        r"\bWorldPoliticalState\s*\.\s*(?:active_settlement_id|get_active_settlement|get_active_settlement_context|get_current_settlement|get_presented_settlement)",
        r"\b(?:active|current|presented)_settlement(?:_id|_context)?\b",
        r"\bsettlement_type\s*(?:==|!=|\bin\b)",
        r"\bmatch\s+[^\n]*settlement_type\b",
    )
    for component_path in settlement_component_paths:
        if not component_path.exists():
            continue
        component_text = gdscript_masked_code(
            component_path.read_text(encoding="utf-8")
        )
        for forbidden_pattern in settlement_component_forbidden_patterns:
            if re.search(forbidden_pattern, component_text):
                errors.append(
                    f"{component_path.relative_to(ROOT)}: settlement-neutral "
                    "component must not reference CityRenderer, discover a "
                    "presentation target, or branch on settlement type"
                )
                break

    ui_controller_relative = (
        "scripts/settlements/presentation/SettlementUiController.gd"
    )
    ui_controller_path = ROOT / ui_controller_relative
    expected_ui_actions = {
        "is_map_mode_ready",
        "apply_map_mode",
        "back",
        "present_ui_change",
    }
    if ui_controller_path.exists():
        ui_controller_text = ui_controller_path.read_text(encoding="utf-8")
        required_actions_match = re.search(
            r"const\s+REQUIRED_ACTIONS[^=]*=\s*\[(.*?)\]",
            ui_controller_text,
            re.DOTALL,
        )
        declared_ui_actions = (
            set(re.findall(r'"([A-Za-z_][A-Za-z0-9_]*)"', required_actions_match.group(1)))
            if required_actions_match is not None
            else set()
        )
        if declared_ui_actions != expected_ui_actions:
            errors.append(
                f"{ui_controller_relative}: UI facade must expose exactly four "
                f"callbacks; found {sorted(declared_ui_actions)}"
            )
    if pass10_renderer_path.exists():
        create_ui_body = gdscript_function_body(
            pass10_renderer_path.read_text(encoding="utf-8"),
            "create_city_ui",
        ) or ""
        wired_ui_actions = set(
            re.findall(
                r'"([A-Za-z_][A-Za-z0-9_]*)"\s*:\s*Callable\s*\(',
                create_ui_body,
            )
        )
        if wired_ui_actions != expected_ui_actions:
            errors.append(
                f"{pass10_renderer_relative}: UI facade must wire exactly four "
                f"callbacks; found {sorted(wired_ui_actions)}"
            )

    helper_failure_test_relative = (
        "scripts/city/rendering/CityRendererInteractionCharacterizationTest.gd"
    )
    helper_failure_test_path = ROOT / helper_failure_test_relative
    if helper_failure_test_path.exists():
        helper_failure_test_text = helper_failure_test_path.read_text(
            encoding="utf-8"
        )
        for failure_regression_token in (
            "class CharacterizationUiController:",
            "fail_next_bind_after_preflight",
            "helper_rollback_binding.generation == binding_generation + 2",
            "renderer.validate_city_presentation_binding(city_a_context)",
            "a_identities_before_helper_failure",
            "b_identities_before_helper_failure",
        ):
            if failure_regression_token not in helper_failure_test_text:
                errors.append(
                    f"{helper_failure_test_relative}: missing fault-injected "
                    f"partial helper commit regression {failure_regression_token}"
                )

    pass10_change_flags = (
        "city_objects_changed",
        "city_containers_changed",
        "public_storage_changed",
        "city_citizens_changed",
        "city_citizen_registry_changed",
        "city_citizen_spatial_changed",
        "city_citizen_movement_changed",
        "city_citizen_movement_runtime_changed",
        "city_citizen_task_changed",
        "city_citizen_task_runtime_changed",
        "city_ground_piles_changed",
        "city_player_commands_changed",
        "city_haul_reservations_changed",
        "city_construction_changed",
        "city_assignments_changed",
        "city_workplaces_changed",
        "city_tile_data_changed",
        "city_surface_features_changed",
    )
    pass10_tracker_fields = {
        "presentation_binding",
        "binding_generation",
        "highest_accepted_binding_generation",
        "observed_city_object_state",
        "observed_city_object_version",
        "observed_city_resource_accounting_state",
        "observed_city_container_version",
        "observed_city_public_storage_version",
        "observed_city_citizen_registry_state",
        "observed_city_citizen_version",
        "observed_city_citizen_spatial_state",
        "observed_city_citizen_spatial_version",
        "observed_city_citizen_movement_runtime_state",
        "observed_city_citizen_movement_version",
        "observed_city_citizen_task_runtime_state",
        "observed_city_citizen_task_version",
        "observed_city_logistics_state",
        "observed_city_ground_pile_version",
        "observed_city_haul_reservation_version",
        "observed_city_work_state",
        "observed_city_player_command_version",
        "observed_city_construction_state",
        "observed_city_construction_version",
        "observed_city_assignment_state",
        "observed_city_assignment_version",
        "observed_city_workplace_state",
        "observed_city_workplace_version",
        "observed_city_tile_data_version",
        "observed_city_surface_feature_change_version",
    }
    if not pass10_tracker_path.exists():
        errors.append(
            f"{pass10_tracker_relative}: missing low-risk Pass 10 invalidation "
            "tracker"
        )
    else:
        pass10_tracker_text = pass10_tracker_path.read_text(encoding="utf-8")
        pass10_tracker_masked = gdscript_masked_code(pass10_tracker_text)
        tracker_declared_fields = {
            match.group(1)
            for match in CITY_RENDERER_TOP_LEVEL_FIELD_RE.finditer(
                pass10_tracker_text
            )
        }
        if tracker_declared_fields != pass10_tracker_fields:
            errors.append(
                f"{pass10_tracker_relative}: tracker must retain only binding, "
                "exact owner, and version observations; missing="
                f"{sorted(pass10_tracker_fields - tracker_declared_fields)}, "
                f"extra={sorted(tracker_declared_fields - pass10_tracker_fields)}"
            )
        if re.search(r"^static\s+var\b", pass10_tracker_text, re.MULTILINE):
            errors.append(
                f"{pass10_tracker_relative}: presentation observations must "
                "not become process-global mutable state"
            )

        tracker_functions = {
            match.group(1) for match in FUNC_RE.finditer(pass10_tracker_text)
        }
        for tracker_api in (
            "rebind_city_presentation",
            "can_rebind_city_presentation",
            "reset",
            "reset_observations",
            "is_bound_to_city_presentation",
            "accepts_generation",
            "capture_current_versions",
            "create_change_flags",
            "collect_city_state_change_flags",
            "collect_city_world_version_change_flags",
        ):
            if tracker_api not in tracker_functions:
                errors.append(
                    f"{pass10_tracker_relative}: missing narrow tracker API "
                    f"{tracker_api}"
                )

        create_flags_body = gdscript_function_body(
            pass10_tracker_text,
            "create_change_flags",
        ) or ""
        for change_flag in pass10_change_flags:
            if f'"{change_flag}": false' not in create_flags_body:
                errors.append(
                    f"{pass10_tracker_relative}: stable change-flag schema "
                    f"is missing {change_flag}"
                )

        if re.search(
            r"\b(?:city_state|city_world)\s*\.\s*[A-Za-z_][A-Za-z0-9_]*"
            r"\s*(?:=|\+=|-=|\*=|/=)",
            pass10_tracker_masked,
        ):
            errors.append(
                f"{pass10_tracker_relative}: invalidation polling must never "
                "mutate gameplay state or its world"
            )
        for forbidden_tracker_token in (
            "WorldPoliticalState.active_settlement_id",
            "get_current_city_",
            "get_active_city_simulation_state",
            "consume_city_surface_feature_changes",
            "queue_redraw",
            "request_redraw",
            "rebuild_city_",
        ):
            if forbidden_tracker_token in pass10_tracker_masked:
                errors.append(
                    f"{pass10_tracker_relative}: non-authoritative tracker "
                    f"must not own side effect {forbidden_tracker_token}"
                )

    if not pass10_binding_path.exists():
        errors.append(f"{pass10_binding_relative}: missing presentation binding")
    else:
        pass10_binding_text = pass10_binding_path.read_text(encoding="utf-8")
        for binding_api in (
            "rebind",
            "reset",
            "accepts_generation",
            "is_valid",
        ):
            if gdscript_function_body(pass10_binding_text, binding_api) is None:
                errors.append(
                    f"{pass10_binding_relative}: missing transactional Pass 10 "
                    f"binding API {binding_api}"
                )
        binding_rebind_body = gdscript_function_body(
            pass10_binding_text,
            "can_rebind",
        ) or ""
        for binding_rebind_token in (
            "_highest_accepted_generation == 0",
            "binding_generation > 0",
            "WorldPoliticalState.is_registered_settlement_context(context)",
        ):
            if binding_rebind_token not in binding_rebind_body:
                errors.append(
                    f"{pass10_binding_relative}: one-shot binding preflight must "
                    "reject reused/unregistered targets transactionally; missing "
                    f"{binding_rebind_token}"
                )

    if pass10_renderer_path.exists():
        pass10_renderer_text = pass10_renderer_path.read_text(encoding="utf-8")
        if (
            "var city_presentation_invalidation_tracker"
            not in pass10_renderer_text
        ):
            errors.append(
                f"{pass10_renderer_relative}: facade must retain the isolated "
                "invalidation tracker"
            )
        renderer_tracker_routes = {
            "_bind_city_presentation_references": "rebind_city_presentation",
            "_reset_city_presentation_observers": "reset_observations",
            "_capture_bound_city_presentation_versions": (
                "capture_current_versions"
            ),
            "_collect_city_world_change_flags": (
                "collect_city_world_version_change_flags"
            ),
            "_collect_world_data_change_flags": "collect_city_state_change_flags",
        }
        for renderer_function, tracker_function in renderer_tracker_routes.items():
            renderer_body = gdscript_function_body(
                pass10_renderer_text,
                renderer_function,
            ) or ""
            if not re.search(
                rf"\bcity_presentation_invalidation_tracker\s*\.\s*"
                rf"{re.escape(tracker_function)}\s*\(",
                renderer_body,
            ):
                errors.append(
                    f"{pass10_renderer_relative}: {renderer_function} must "
                    f"delegate through tracker.{tracker_function}"
                )

        citizen_presentation_relative = (
            "scripts/citizens/rendering/CityCitizenMovementPresentation.gd"
        )
        citizen_presentation_path = ROOT / citizen_presentation_relative
        if not citizen_presentation_path.exists():
            errors.append(
                f"{citizen_presentation_relative}: missing settlement-bound "
                "citizen presentation owner"
            )
        else:
            citizen_presentation_text = citizen_presentation_path.read_text(
                encoding="utf-8"
            )
            for required_field in (
                "var local_tile_size:",
                "var highest_accepted_binding_generation:",
                "var synchronized_movement_version:",
                "var _citizen_draw_buffer:",
                "var _citizen_rect_draw_buffer:",
            ):
                if required_field not in citizen_presentation_text:
                    errors.append(
                        f"{citizen_presentation_relative}: extracted citizen "
                        f"presentation field is missing: {required_field}"
                    )
            for required_function in (
                "bind_settlement_presentation",
                "can_bind_settlement_presentation",
                "is_bound_to_settlement_presentation",
                "reset_presentation",
                "synchronize_for_changes",
                "consume_committed_tick",
                "discard_pending_visual_events",
                "get_citizen_world_rect",
                "draw_citizens",
            ):
                if gdscript_function_body(
                    citizen_presentation_text,
                    required_function,
                ) is None:
                    errors.append(
                        f"{citizen_presentation_relative}: extracted citizen "
                        f"presentation API is missing: {required_function}"
                    )

            citizen_bind_body = gdscript_function_body(
                citizen_presentation_text,
                "bind_settlement_presentation",
            )
            citizen_can_bind_body = gdscript_function_body(
                citizen_presentation_text,
                "can_bind_settlement_presentation",
            )
            citizen_initialize_body = gdscript_function_body(
                citizen_presentation_text,
                "initialize",
            )
            citizen_reset_body = gdscript_function_body(
                citizen_presentation_text,
                "reset_presentation",
            )
            if (
                citizen_bind_body is not None
                and "highest_accepted_binding_generation = binding.generation"
                not in citizen_bind_body
            ):
                errors.append(
                    f"{citizen_presentation_relative}: binding must advance "
                    "the accepted-generation high-water mark"
                )
            if (
                citizen_can_bind_body is not None
                and "binding.generation > highest_accepted_binding_generation"
                not in citizen_can_bind_body
            ):
                errors.append(
                    f"{citizen_presentation_relative}: binding preflight must "
                    "reject stale generations before mutation"
                )
            for lifecycle_name, lifecycle_body in (
                ("initialize", citizen_initialize_body),
                ("reset_presentation", citizen_reset_body),
            ):
                if (
                    lifecycle_body is not None
                    and re.search(
                        r"highest_accepted_binding_generation\s*=",
                        lifecycle_body,
                    )
                ):
                    errors.append(
                        f"{citizen_presentation_relative}: {lifecycle_name} "
                        "must preserve the accepted-generation high-water mark"
                    )

        for retired_renderer_citizen_member in (
            "var synchronized_city_citizen_movement_version:",
            "var city_citizen_draw_buffer:",
            "var city_citizen_rect_draw_buffer:",
            "func _synchronize_city_citizen_movement(",
            "func get_city_citizen_world_rect(",
            "func draw_city_citizens(",
            "func draw_city_citizen_haul_cargo_marker(",
        ):
            if retired_renderer_citizen_member in pass10_renderer_text:
                errors.append(
                    f"{pass10_renderer_relative}: extracted citizen member "
                    "must not return to the facade: "
                    f"{retired_renderer_citizen_member}"
                )

    pass10_test_contracts = {
        "scripts/city/rendering/CityPresentationInvalidationTrackerTest.gd": {
            "ready": (
                "_test_binding_generation_transaction",
                "_test_all_version_and_owner_invalidation_paths",
            ),
            "tokens": (
                "tracker.can_rebind_city_presentation(",
                "tracker.collect_city_state_change_flags(",
                "tracker.collect_city_world_version_change_flags(",
                "_replace_all_observed_owners_at_equal_versions(",
                "not tracker.collect_city_state_change_flags(1, stale_flags)",
                "tracker.reset()",
                "_capture_gameplay_snapshot(city_b_state) == city_b_before",
            ),
        },
        "scripts/city/rendering/CityRendererInteractionCharacterizationTest.gd": {
            "ready": ("_test_registered_renderer_interaction_controllers",),
            "tokens": (
                "confirm_active_city_object_placement()",
                "cancel_active_city_object_placement()",
                "start_road_drag_selection()",
                "update_road_drag_selection()",
                "confirm_road_preview()",
                "cancel_road_placement()",
                "start_city_player_command_drag(",
                "finish_city_player_command_drag(",
                "cancel_city_player_command_drag()",
                "start_object_selection_drag(",
                "finish_object_selection_drag(",
                "_update_city_hover_state()",
                "_clear_city_presentation_interactions()",
                "WorldPoliticalState.active_settlement_id == presented_city_id",
                "SimulationClock.simulation_paused",
                "SimulationClock.speed_multiplier",
                "_capture_gameplay_snapshot(city_state) == before_reset",
                "identities_before_cancel",
                "identities_before_selection",
                "identities_before_reset",
                "city_b_identities_before_rebind",
                "renderer.city_presentation_draw_count > 0",
                "renderer.city_presentation_total_draw_duration_usec",
                "renderer.city_presentation_last_draw_layer",
                "renderer.rebind_city_presentation(city_b_context)",
                "renderer.city_last_rebind_duration_usec >= 0",
                "PASS10_TIMING_BASELINE",
            ),
        },
    }
    for pass10_test_relative, test_contract in pass10_test_contracts.items():
        pass10_test_path = ROOT / pass10_test_relative
        pass10_scene_path = pass10_test_path.with_suffix(".tscn")
        if not pass10_test_path.exists() or not pass10_scene_path.exists():
            errors.append(
                f"{pass10_test_relative}: missing permanent Pass 10 "
                "characterization test or runnable scene"
            )
            continue
        pass10_test_text = pass10_test_path.read_text(encoding="utf-8")
        pass10_ready_body = gdscript_function_body(
            pass10_test_text,
            "_ready",
        ) or ""
        for ready_function in test_contract["ready"]:
            if gdscript_function_body(pass10_test_text, ready_function) is None:
                errors.append(
                    f"{pass10_test_relative}: missing Pass 10 regression "
                    f"{ready_function}"
                )
            if f"{ready_function}()" not in pass10_ready_body:
                errors.append(
                    f"{pass10_test_relative}: {ready_function} is not invoked "
                    "by _ready"
                )
        for required_test_token in test_contract["tokens"]:
            if required_test_token not in pass10_test_text:
                errors.append(
                    f"{pass10_test_relative}: characterization is missing "
                    f"{required_test_token}"
                )
        pass10_scene_text = pass10_scene_path.read_text(encoding="utf-8")
        if (
            f"res://{pass10_test_relative}" not in pass10_scene_text
            or "script = ExtResource" not in pass10_scene_text
        ):
            errors.append(
                f"{pass10_scene_path.relative_to(ROOT)}: scene must bind its "
                "Pass 10 test script on the root"
            )

    pass10_existing_characterization = {
        "scripts/city/rendering/CityRendererExplicitBindingTest.gd": (
            "bootstrap_and_configure_renderer(",
            "Presentation-only _ready() must preserve every gameplay value",
            "Constructing CityRenderer must not resume, reset, or advance",
        ),
        "scripts/session/SettlementPresentationRebindTest.gd": (
            "show_settlement_city_view",
            "A/B/A must restore City A presentation",
            "Retained render layers must stay hidden",
            "Each settlement must retain its own presentation-only camera state",
        ),
        "scripts/city/rendering/CityRendererRefactorSmokeTest.gd": (
            "_test_city_map_texture_cache",
            "_test_focused_layer_invalidation",
            "_test_settlement_natural_feature_presenter_binding",
            "_test_city_natural_features",
            "_test_universal_construction_core",
        ),
        "scripts/city/rendering/CityPresentationHelperBindingTest.gd": (
            "_test_exact_texture_cache_source_identity",
            "A and B must store independent presentation-only camera states",
            "Settlement-neutral helpers must reject stale A after accepting",
            "reset_information_ui.reset_presentation()",
            "reset_overlay_cache.reset_presentation()",
            "reset_guard_debug_presentation.reset()",
            "reset_movement_presentation.reset_presentation()",
            "highest_accepted_binding_generation == 1",
        ),
        "scripts/ui/city/CityPanelViewportSafetyTest.gd": (
            "_test_secondary_panel_flips_left_at_right_edge",
            "_test_panel_group_reclamps_after_anchor_and_size_changes",
        ),
    }
    for characterization_relative, characterization_tokens in (
        pass10_existing_characterization.items()
    ):
        characterization_path = ROOT / characterization_relative
        characterization_scene_path = characterization_path.with_suffix(".tscn")
        if not characterization_path.exists() or not characterization_scene_path.exists():
            errors.append(
                f"{characterization_relative}: missing required renderer "
                "characterization source or runnable scene"
            )
            continue
        characterization_text = characterization_path.read_text(encoding="utf-8")
        for characterization_token in characterization_tokens:
            if characterization_token not in characterization_text:
                errors.append(
                    f"{characterization_relative}: existing Pass 10 matrix "
                    f"coverage is missing {characterization_token}"
                )

    pass8_storage_owners = (
        (
            "scripts/world/simulation/WorldData.gd",
            True,
            "WorldData",
        ),
        (
            "scripts/world/simulation/WorldPoliticalState.gd",
            False,
            None,
        ),
    )
    for storage_relative, is_static_owner, city_world_type in pass8_storage_owners:
        storage_path = ROOT / storage_relative
        if not storage_path.exists():
            errors.append(
                f"{storage_relative}: missing post-PR-7.6 Pass 8 explicit "
                "settlement world-storage owner"
            )
            continue
        storage_text = storage_path.read_text(encoding="utf-8")
        static_prefix = r"static\s+" if is_static_owner else ""
        city_world_parameter = r"city_world"
        if city_world_type is not None:
            city_world_parameter += rf"\s*:\s*{re.escape(city_world_type)}"
        required_storage_signatures = {
            "has_city_world_for_settlement": (
                rf"^{static_prefix}func\s+has_city_world_for_settlement\s*\(\s*"
                r"settlement_id\s*:\s*int\s*\)\s*->\s*bool\s*:"
            ),
            "store_city_world_for_settlement": (
                rf"^{static_prefix}func\s+store_city_world_for_settlement\s*\(\s*"
                r"settlement_id\s*:\s*int\s*,\s*"
                rf"{city_world_parameter}\s*,\s*"
                r"city_seed\s*:\s*int\s*\)\s*->\s*bool\s*:"
            ),
            "clear_city_world_for_settlement": (
                rf"^{static_prefix}func\s+clear_city_world_for_settlement\s*\(\s*"
                r"settlement_id\s*:\s*int\s*\)\s*->\s*bool\s*:"
            ),
        }
        for storage_function, signature_pattern in required_storage_signatures.items():
            if not re.search(signature_pattern, storage_text, re.MULTILINE):
                errors.append(
                    f"{storage_relative}: missing typed explicit settlement "
                    f"world-storage API {storage_function}"
                )
                continue
            storage_body = gdscript_function_body(
                storage_text,
                storage_function,
            ) or ""
            masked_storage_body = gdscript_masked_code(storage_body)
            uses_explicit_settlement_id = re.search(
                r"(?:\(|,)\s*settlement_id\s*(?:,|\))",
                masked_storage_body,
            )
            uses_presentation_authority = re.search(
                r"\b(?:active_settlement_id|get_presented_settlement_id|"
                r"get_active_settlement|get_active_city_simulation_state)\b|"
                r"\bget_current_city_",
                masked_storage_body,
            )
            if uses_explicit_settlement_id is None or uses_presentation_authority:
                errors.append(
                    f"{storage_relative}: {storage_function} must use only its "
                    "explicit settlement_id, never presentation/current authority"
                )

    pass8_storage_test_relative = (
        "scripts/world/simulation/ExplicitSettlementSimulationContextTest.gd"
    )
    pass8_storage_test_path = ROOT / pass8_storage_test_relative
    pass8_storage_test_name = (
        "_test_explicit_city_world_storage_ignores_visual_selection"
    )
    if not pass8_storage_test_path.exists():
        errors.append(
            f"{pass8_storage_test_relative}: missing Pass 8 explicit city-world "
            "storage isolation regression"
        )
    else:
        pass8_storage_test_text = pass8_storage_test_path.read_text(
            encoding="utf-8"
        )
        pass8_storage_test_body = gdscript_function_body(
            pass8_storage_test_text,
            pass8_storage_test_name,
        )
        ready_body = gdscript_function_body(
            pass8_storage_test_text,
            "_ready",
        ) or ""
        if pass8_storage_test_body is None:
            errors.append(
                f"{pass8_storage_test_relative}: missing permanent Pass 8 "
                f"regression {pass8_storage_test_name}"
            )
        else:
            for required_storage_test_token in (
                "WorldPoliticalState.set_active_settlement(city_b_id)",
                "WorldData.store_city_world_for_settlement(",
                "WorldData.clear_city_world_for_settlement(city_a_id)",
                "is_same(state_b.city_world, b_world_before)",
                "_city_identities_match(state_b, b_identities)",
            ):
                if required_storage_test_token not in pass8_storage_test_body:
                    errors.append(
                        f"{pass8_storage_test_relative}: Pass 8 storage "
                        "regression is missing required isolation assertion "
                        f"{required_storage_test_token}"
                    )
        if f"{pass8_storage_test_name}()" not in ready_body:
            errors.append(
                f"{pass8_storage_test_relative}: Pass 8 storage regression is "
                "not invoked by _ready"
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
