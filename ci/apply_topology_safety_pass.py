#!/usr/bin/env python3
"""Apply the topology-safe construction finalization pass.

This transformer is intentionally temporary. It performs exact, asserted edits
on the dedicated feature branch so large GDScript files do not have to be
replaced through the contents API by hand.
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one exact match, found {count}")
    return text.replace(old, new, 1)


def regex_replace_once(
    text: str,
    pattern: str,
    replacement: str,
    label: str,
) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f"{label}: expected one regex match, found {count}")
    return updated


def patch_world_data() -> None:
    path = "scripts/world/simulation/WorldData.gd"
    text = read(path)

    text = replace_once(
        text,
        'const CITY_CONSTRUCTION_PHASE_LABOR := "labor"\n'
        'const CITY_CONSTRUCTION_TARGET_NEW := "new"',
        'const CITY_CONSTRUCTION_PHASE_LABOR := "labor"\n'
        'const CITY_CONSTRUCTION_FINALIZATION_STATE_NONE := "none"\n'
        'const CITY_CONSTRUCTION_FINALIZATION_STATE_AWAITING_CLEARANCE := (\n'
        '\t"awaiting_clearance"\n'
        ')\n'
        'const CITY_TOPOLOGY_MUTATION_FAILURE_NONE := "none"\n'
        'const CITY_TOPOLOGY_MUTATION_FAILURE_INVALID_REQUEST := (\n'
        '\t"invalid_request"\n'
        ')\n'
        'const CITY_TOPOLOGY_MUTATION_FAILURE_TILE_BLOCKED := "tile_blocked"\n'
        'const CITY_TOPOLOGY_MUTATION_FAILURE_FOOTPRINT_OCCUPIED := (\n'
        '\t"footprint_occupied"\n'
        ')\n'
        'const CITY_CONSTRUCTION_TARGET_NEW := "new"',
        "WorldData topology constants",
    )

    topology_helpers = r'''static func city_object_type_preserves_citizen_walkability(
	object_type: String
) -> bool:
	# Roads alter movement cost but remain publicly traversable. Every current
	# building type replaces open ground with controlled or blocked occupancy.
	# Keeping this policy centralized makes future bridges, floors, gates, and
	# similar topology types opt in deliberately instead of acquiring exceptions
	# throughout construction and movement code.
	return object_type == CITY_OBJECT_ROAD


static func get_living_city_citizen_ids_in_tiles(
	raw_tiles: Array
) -> Array[int]:
	var tile_lookup: Dictionary = {}

	for raw_tile in raw_tiles:
		if raw_tile is Vector2i:
			tile_lookup[raw_tile] = true

	var citizen_ids: Array[int] = []

	for raw_citizen in city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if not bool(citizen.get("alive", false)):
			continue

		var raw_tile = citizen.get(
			"city_tile_position",
			INVALID_CITY_TILE_POSITION
		)

		if not raw_tile is Vector2i or not tile_lookup.has(raw_tile):
			continue

		var citizen_id := int(citizen.get("id", -1))

		if citizen_id > 0:
			citizen_ids.append(citizen_id)

	citizen_ids.sort()
	return citizen_ids


static func get_city_object_topology_blocking_citizen_ids(
	object_type: String,
	footprint_tiles: Array
) -> Array[int]:
	if city_object_type_preserves_citizen_walkability(object_type):
		return []

	return get_living_city_citizen_ids_in_tiles(footprint_tiles)


static func validate_city_object_topology_mutation(
	values: Dictionary
) -> Dictionary:
	var result := {
		"success": false,
		"failure_reason": CITY_TOPOLOGY_MUTATION_FAILURE_INVALID_REQUEST,
		"blocking_citizen_ids": [],
	}
	var city_world: WorldData = values.get("city_world")
	var object_type := str(values.get("object_type", ""))
	var raw_footprint_tiles = values.get("footprint_tiles", [])
	var allowed_construction_site_id := int(
		values.get("allowed_construction_site_id", -1)
	)
	var allowed_occupied_object_id := int(
		values.get("allowed_occupied_object_id", -1)
	)

	if (
		city_world == null
		or get_city_object_definition(object_type).is_empty()
		or not raw_footprint_tiles is Array
		or raw_footprint_tiles.is_empty()
	):
		return result

	var footprint_tiles: Array[Vector2i] = []
	var footprint_lookup: Dictionary = {}

	for raw_tile in raw_footprint_tiles:
		if not raw_tile is Vector2i:
			return result

		var tile_position: Vector2i = raw_tile

		if footprint_lookup.has(tile_position):
			continue

		if not city_world.is_in_bounds(tile_position.x, tile_position.y):
			return result

		var tile: Dictionary = city_world.get_tile(
			tile_position.x,
			tile_position.y
		)

		if (
			str(tile.get("terrain", TERRAIN_WATER)) in [
				TERRAIN_WATER,
				TERRAIN_MOUNTAIN,
			]
			or not bool(tile.get("is_land", false))
		):
			return result

		var occupied_object_id := int(
			city_occupied_tiles.get(tile_position, -1)
		)

		if (
			occupied_object_id > 0
			and occupied_object_id != allowed_occupied_object_id
		):
			result["failure_reason"] = (
				CITY_TOPOLOGY_MUTATION_FAILURE_TILE_BLOCKED
			)
			return result

		var construction_site_id := int(
			city_construction_site_id_by_tile.get(tile_position, -1)
		)

		if (
			construction_site_id > 0
			and construction_site_id != allowed_construction_site_id
		):
			result["failure_reason"] = (
				CITY_TOPOLOGY_MUTATION_FAILURE_TILE_BLOCKED
			)
			return result

		if has_city_ground_pile_at_tile(tile_position):
			result["failure_reason"] = (
				CITY_TOPOLOGY_MUTATION_FAILURE_TILE_BLOCKED
			)
			return result

		footprint_lookup[tile_position] = true
		footprint_tiles.append(tile_position)

	var blocking_citizen_ids := (
		get_city_object_topology_blocking_citizen_ids(
			object_type,
			footprint_tiles
		)
	)

	if not blocking_citizen_ids.is_empty():
		result["failure_reason"] = (
			CITY_TOPOLOGY_MUTATION_FAILURE_FOOTPRINT_OCCUPIED
		)
		result["blocking_citizen_ids"] = blocking_citizen_ids
		return result

	result["success"] = true
	result["failure_reason"] = CITY_TOPOLOGY_MUTATION_FAILURE_NONE
	result["footprint_tiles"] = footprint_tiles
	return result


'''
    text = replace_once(
        text,
        "static func can_place_city_object(\n",
        topology_helpers + "static func can_place_city_object(\n",
        "WorldData topology helpers",
    )

    text = replace_once(
        text,
        "\tvar footprint_tiles := make_rectangle_city_object_footprint_tiles(top_left, size_tiles)\n\n"
        "\tcity_object[\"shape_mode\"] = shape_mode",
        "\tvar footprint_tiles := make_rectangle_city_object_footprint_tiles(top_left, size_tiles)\n"
        "\tvar topology_validation := validate_city_object_topology_mutation({\n"
        "\t\t\"city_world\": city_world,\n"
        "\t\t\"object_type\": object_type,\n"
        "\t\t\"footprint_tiles\": footprint_tiles,\n"
        "\t\t\"allowed_construction_site_id\": int(\n"
        "\t\t\tvalues.get(\"allowed_construction_site_id\", -1)\n"
        "\t\t),\n"
        "\t\t\"allowed_occupied_object_id\": int(\n"
        "\t\t\tvalues.get(\"allowed_occupied_object_id\", -1)\n"
        "\t\t),\n"
        "\t})\n\n"
        "\tif not bool(topology_validation.get(\"success\", false)):\n"
        "\t\tpush_warning(\n"
        "\t\t\t\"Rejected city-object topology mutation for \"\n"
        "\t\t\t\t+ object_type\n"
        "\t\t\t\t+ \". Reason: \"\n"
        "\t\t\t\t+ str(topology_validation.get(\"failure_reason\", \"\"))\n"
        "\t\t\t\t+ \". Blocking citizens: \"\n"
        "\t\t\t\t+ str(topology_validation.get(\"blocking_citizen_ids\", []))\n"
        "\t\t)\n"
        "\t\treturn {}\n\n"
        "\tcity_object[\"shape_mode\"] = shape_mode",
        "WorldData add_city_object topology gate",
    )

    text = replace_once(
        text,
        "static func add_city_road_object(\n"
        "\ttile_positions: Array,\n"
        "\tobject_owner: String = \"player\",\n"
        "\tcity_world: WorldData = null\n"
        ") -> Dictionary:",
        "static func add_city_road_object(\n"
        "\ttile_positions: Array,\n"
        "\tobject_owner: String = \"player\",\n"
        "\tcity_world: WorldData = null,\n"
        "\tallowed_construction_site_id: int = -1\n"
        ") -> Dictionary:",
        "WorldData road topology signature",
    )

    text = replace_once(
        text,
        "\tif feature_world == null:\n"
        "\t\tfeature_world = official_city_world\n\n"
        "\tclear_city_surface_features_at_tiles(\n"
        "\t\tfeature_world,\n"
        "\t\tclean_tiles\n"
        "\t)",
        "\tif feature_world == null:\n"
        "\t\tfeature_world = official_city_world\n\n"
        "\tvar topology_validation := validate_city_object_topology_mutation({\n"
        "\t\t\"city_world\": feature_world,\n"
        "\t\t\"object_type\": CITY_OBJECT_ROAD,\n"
        "\t\t\"footprint_tiles\": clean_tiles,\n"
        "\t\t\"allowed_construction_site_id\": allowed_construction_site_id,\n"
        "\t})\n\n"
        "\tif not bool(topology_validation.get(\"success\", false)):\n"
        "\t\treturn {}\n\n"
        "\tclear_city_surface_features_at_tiles(\n"
        "\t\tfeature_world,\n"
        "\t\tclean_tiles\n"
        "\t)",
        "WorldData road topology gate",
    )

    old_walkability = r'''	if (
		citizen_id <= 0
		or not city_object_supports_citizen_interior(
			occupying_object
		)
	):
		return false

	var citizen := get_city_citizen_by_id(citizen_id)

	if (
		citizen.is_empty()
		or not bool(citizen.get("alive", false))
	):
		return false

	var current_position = citizen.get(
		"city_tile_position",
		INVALID_CITY_TILE_POSITION
	)

	# Existing occupants retain interior traversal long enough to reach an
	# allowed exit. This prevents reassignment or policy changes from trapping
	# a citizen inside a building.
	if (
		current_position is Vector2i
		and int(city_occupied_tiles.get(current_position, -1))
		== object_id
	):
		return true

	return city_citizen_can_access_object_interior(
		citizen_id,
		occupying_object
	)'''
    new_walkability = r'''	if citizen_id <= 0:
		return false

	var citizen := get_city_citizen_by_id(citizen_id)

	if (
		citizen.is_empty()
		or not bool(citizen.get("alive", false))
	):
		return false

	var current_position = citizen.get(
		"city_tile_position",
		INVALID_CITY_TILE_POSITION
	)

	# Recovery invariant: a citizen already caught inside an occupied footprint
	# may traverse that same footprint long enough to leave it. Normal topology
	# mutations are prevented from creating this state; this path exists for old
	# saves and defensive recovery only, and never authorizes re-entry.
	if (
		current_position is Vector2i
		and int(city_occupied_tiles.get(current_position, -1))
		== object_id
	):
		return true

	if not city_object_supports_citizen_interior(occupying_object):
		return false

	return city_citizen_can_access_object_interior(
		citizen_id,
		occupying_object
	)'''
    text = replace_once(
        text,
        old_walkability,
        new_walkability,
        "WorldData legacy occupant escape",
    )

    movement_block = r'''static func commit_city_citizen_movement_tick(
	city_world: WorldData,
	raw_citizen_updates: Array,
	raw_next_active_mover_ids: Array[int]
) -> Dictionary:
	var result := {
		"success": false,
		"updated_citizen_count": 0,
		"moved_citizen_count": 0,
		"rejected_update_count": 0,
		"rejected_updates": [],
	}

	if city_world == null:
		return result

	var update_normalization := _normalize_city_citizen_movement_updates(
		city_world,
		raw_citizen_updates
	)
	var clean_updates: Array = update_normalization.get("updates", [])
	var clean_update_by_id: Dictionary = update_normalization.get(
		"update_by_id",
		{}
	)
	var rejected_updates: Array = update_normalization.get(
		"rejected_updates",
		[]
	)
	var rejected_id_lookup: Dictionary = {}

	for raw_rejection in rejected_updates:
		if not raw_rejection is Dictionary:
			continue

		var rejected_id := int(raw_rejection.get("citizen_id", -1))

		if rejected_id > 0:
			rejected_id_lookup[rejected_id] = true

	var active_normalization := _normalize_next_active_mover_ids(
		raw_next_active_mover_ids,
		clean_update_by_id,
		rejected_id_lookup
	)
	var clean_next_active_ids: Array[int] = active_normalization.get(
		"active_ids",
		[]
	)
	rejected_updates.append_array(
		active_normalization.get("rejected_updates", [])
	)

	var application_result := _apply_city_citizen_movement_updates(
		clean_updates
	)
	var moved_citizen_count := int(
		application_result.get("moved_citizen_count", 0)
	)
	var quarantined_count := (
		_quarantine_rejected_city_citizen_movement_updates(
			rejected_updates
		)
	)
	var active_registry_changed := (
		city_active_mover_ids != clean_next_active_ids
	)

	_replace_city_active_mover_registry(clean_next_active_ids)

	if (
		not clean_updates.is_empty()
		or quarantined_count > 0
		or active_registry_changed
	):
		_mark_city_citizen_movement_changed()

	if moved_citizen_count > 0:
		_mark_city_citizen_spatial_changed()

	city_citizen_movement_visual_events = application_result.get(
		"movement_visual_events",
		[]
	)
	result["success"] = true
	result["updated_citizen_count"] = clean_updates.size()
	result["moved_citizen_count"] = moved_citizen_count
	result["rejected_update_count"] = rejected_updates.size()
	result["rejected_updates"] = rejected_updates
	return result


static func _make_city_citizen_movement_rejection(
	citizen_id: int,
	reason: String,
	final_tile = INVALID_CITY_TILE_POSITION,
	quarantine: bool = true
) -> Dictionary:
	var rejection := {
		"citizen_id": citizen_id,
		"reason": reason,
		"quarantine": quarantine,
	}

	if final_tile is Vector2i:
		rejection["final_tile"] = final_tile
		rejection["occupying_object_id"] = int(
			city_occupied_tiles.get(final_tile, -1)
		)

	return rejection


static func _normalize_city_citizen_movement_updates(
	city_world: WorldData,
	raw_citizen_updates: Array
) -> Dictionary:
	var clean_updates: Array = []
	var clean_update_by_id: Dictionary = {}
	var rejected_updates: Array = []

	for raw_update in raw_citizen_updates:
		if not raw_update is Dictionary:
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					-1,
					"update_is_not_dictionary",
					INVALID_CITY_TILE_POSITION,
					false
				)
			)
			continue

		var update: Dictionary = raw_update
		var citizen_id := int(update.get("citizen_id", -1))
		var raw_updated_citizen = update.get("citizen", {})
		var raw_final_tile = update.get(
			"final_tile",
			INVALID_CITY_TILE_POSITION
		)
		var raw_traversed_tiles = update.get("traversed_tiles", [])

		if citizen_id <= 0:
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"invalid_citizen_id",
					raw_final_tile,
					false
				)
			)
			continue

		if clean_update_by_id.has(citizen_id):
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"duplicate_update",
					raw_final_tile,
					false
				)
			)
			continue

		if not raw_updated_citizen is Dictionary:
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"updated_citizen_is_not_dictionary",
					raw_final_tile
				)
			)
			continue

		if not raw_final_tile is Vector2i:
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"final_tile_is_not_vector"
				)
			)
			continue

		if not raw_traversed_tiles is Array:
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"traversed_tiles_is_not_array",
					raw_final_tile
				)
			)
			continue

		if not is_city_tile_walkable_for_citizen(
			city_world,
			raw_final_tile,
			citizen_id
		):
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"final_tile_not_walkable",
					raw_final_tile
				)
			)
			continue

		var citizen_index := get_city_citizen_index_by_id(citizen_id)

		if citizen_index < 0:
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"citizen_not_found",
					raw_final_tile,
					false
				)
			)
			continue

		var updated_citizen: Dictionary = raw_updated_citizen

		if int(updated_citizen.get("id", -1)) != citizen_id:
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"updated_citizen_id_mismatch",
					raw_final_tile
				)
			)
			continue

		var existing_citizen = city_citizens[citizen_index]

		if not existing_citizen is Dictionary:
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"authoritative_citizen_is_not_dictionary",
					raw_final_tile,
					false
				)
			)
			continue

		if not (
			existing_citizen.get(
				"city_tile_position",
				INVALID_CITY_TILE_POSITION
			)
			is Vector2i
		):
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"authoritative_position_invalid",
					raw_final_tile
				)
			)
			continue

		var clean_update := {
			"citizen_id": citizen_id,
			"citizen_index": citizen_index,
			"citizen": updated_citizen,
			"final_tile": raw_final_tile,
			"traversed_tiles": raw_traversed_tiles,
		}
		clean_updates.append(clean_update)
		clean_update_by_id[citizen_id] = clean_update

	return {
		"updates": clean_updates,
		"update_by_id": clean_update_by_id,
		"rejected_updates": rejected_updates,
	}


static func _normalize_next_active_mover_ids(
	raw_next_active_mover_ids: Array[int],
	clean_update_by_id: Dictionary,
	rejected_id_lookup: Dictionary
) -> Dictionary:
	var clean_next_active_ids: Array[int] = []
	var clean_next_active_lookup: Dictionary = {}
	var rejected_updates: Array = []

	for citizen_id in raw_next_active_mover_ids:
		if rejected_id_lookup.has(citizen_id):
			continue

		if citizen_id <= 0 or clean_next_active_lookup.has(citizen_id):
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"invalid_or_duplicate_active_mover",
					INVALID_CITY_TILE_POSITION,
					false
				)
			)
			continue

		var proposed_citizen := get_city_citizen_by_id(citizen_id)

		if clean_update_by_id.has(citizen_id):
			var proposed_update: Dictionary = clean_update_by_id[citizen_id]
			proposed_citizen = proposed_update.get("citizen", {})

		if proposed_citizen.is_empty():
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"active_mover_citizen_missing",
					INVALID_CITY_TILE_POSITION,
					false
				)
			)
			continue

		if not bool(proposed_citizen.get("alive", false)):
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"active_mover_not_alive",
					INVALID_CITY_TILE_POSITION,
					false
				)
			)
			continue

		if (
			str(proposed_citizen.get("movement_state", ""))
			!= CITY_CITIZEN_MOVEMENT_STATE_MOVING
		):
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"active_registry_entry_not_moving",
					INVALID_CITY_TILE_POSITION,
					false
				)
			)
			continue

		clean_next_active_ids.append(citizen_id)
		clean_next_active_lookup[citizen_id] = true

	clean_next_active_ids.sort()
	return {
		"active_ids": clean_next_active_ids,
		"rejected_updates": rejected_updates,
	}


static func _quarantine_rejected_city_citizen_movement_updates(
	rejected_updates: Array
) -> int:
	var quarantined_ids: Dictionary = {}

	for raw_rejection in rejected_updates:
		if not raw_rejection is Dictionary:
			continue

		var rejection: Dictionary = raw_rejection
		var citizen_id := int(rejection.get("citizen_id", -1))

		if (
			citizen_id <= 0
			or not bool(rejection.get("quarantine", true))
			or quarantined_ids.has(citizen_id)
		):
			continue

		var citizen_index := get_city_citizen_index_by_id(citizen_id)

		if citizen_index < 0:
			continue

		var raw_citizen = city_citizens[citizen_index]

		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		CityCitizensScript.reset_city_citizen_movement_state(citizen, true)
		citizen["movement_state"] = CITY_CITIZEN_MOVEMENT_STATE_BLOCKED
		citizen["movement_failure_reason"] = (
			CITY_CITIZEN_MOVEMENT_FAILURE_INVALID_PATH
		)
		city_citizens[citizen_index] = citizen
		quarantined_ids[citizen_id] = true

	return quarantined_ids.size()


'''
    text = regex_replace_once(
        text,
        r"static func commit_city_citizen_movement_tick\(.*?\nstatic func _apply_city_citizen_movement_updates\(",
        movement_block + "static func _apply_city_citizen_movement_updates(",
        "WorldData movement fault containment",
    )

    write(path, text)


def patch_movement_system() -> None:
    path = "scripts/citizens/simulation/systems/CitizenMovementSystem.gd"
    text = read(path)
    text = replace_once(
        text,
        "\tif not bool(commit_result.get(\"success\", false)):\n"
        "\t\tpush_error(\"Citizen movement tick could not be committed.\")",
        "\tif not bool(commit_result.get(\"success\", false)):\n"
        "\t\tpush_error(\"Citizen movement tick could not be committed.\")\n"
        "\t\treturn\n\n"
        "\tvar rejected_updates: Array = commit_result.get(\n"
        "\t\t\"rejected_updates\",\n"
        "\t\t[]\n"
        "\t)\n\n"
        "\tif not rejected_updates.is_empty():\n"
        "\t\tpush_warning(\n"
        "\t\t\t\"Quarantined \"\n"
        "\t\t\t\t+ str(rejected_updates.size())\n"
        "\t\t\t\t+ \" invalid citizen movement update(s) without \"\n"
        "\t\t\t\t+ \"blocking valid movers: \"\n"
        "\t\t\t\t+ str(rejected_updates)\n"
        "\t\t)",
        "CitizenMovementSystem rejection diagnostics",
    )
    write(path, text)


def patch_construction_system() -> None:
    path = "scripts/city/simulation/systems/CityConstructionSystem.gd"
    text = read(path)

    text = replace_once(
        text,
        'const PLAYER_WORK_KIND_LABOR := "construction_labor"\n',
        'const PLAYER_WORK_KIND_LABOR := "construction_labor"\n'
        'const FINALIZATION_STATE_NONE := (\n'
        '\tWorldData.CITY_CONSTRUCTION_FINALIZATION_STATE_NONE\n'
        ')\n'
        'const FINALIZATION_STATE_AWAITING_CLEARANCE := (\n'
        '\tWorldData.CITY_CONSTRUCTION_FINALIZATION_STATE_AWAITING_CLEARANCE\n'
        ')\n',
        "Construction finalization constants",
    )

    text = replace_once(
        text,
        '\t\t"completed_labor_minutes": 0,\n'
        '\t\t"maximum_workers": maxi(',
        '\t\t"completed_labor_minutes": 0,\n'
        '\t\t"finalization_state": FINALIZATION_STATE_NONE,\n'
        '\t\t"maximum_workers": maxi(',
        "Construction site finalization state",
    )

    text = replace_once(
        text,
        "\tvar site := WorldData.get_city_construction_site_by_id(site_id)\n"
        "\tif site.is_empty():\n"
        "\t\treturn false\n\n"
        "\t_reserve_needed_footprint_materials(site_id)",
        "\tvar site := WorldData.get_city_construction_site_by_id(site_id)\n"
        "\tif site.is_empty():\n"
        "\t\treturn false\n\n"
        "\tif (\n"
        "\t\tstr(site.get(\"finalization_state\", FINALIZATION_STATE_NONE))\n"
        "\t\t== FINALIZATION_STATE_AWAITING_CLEARANCE\n"
        "\t):\n"
        "\t\t_advance_city_construction_finalization(site_id)\n"
        "\t\treturn true\n\n"
        "\t_reserve_needed_footprint_materials(site_id)",
        "Construction refresh pending finalization",
    )

    text = replace_once(
        text,
        "\t\tor int(citizen.get(\"job_object_id\", -1)) > 0\n"
        "\t\tor site.is_empty()\n"
        "\t):",
        "\t\tor int(citizen.get(\"job_object_id\", -1)) > 0\n"
        "\t\tor site.is_empty()\n"
        "\t\tor str(\n"
        "\t\t\tsite.get(\"finalization_state\", FINALIZATION_STATE_NONE)\n"
        "\t\t) != FINALIZATION_STATE_NONE\n"
        "\t):",
        "Construction candidate finalization exclusion",
    )

    text = replace_once(
        text,
        "\t\tsite.is_empty()\n"
        "\t\tor str(site.get(\"phase\", \"\"))\n"
        "\t\t!= WorldData.CITY_CONSTRUCTION_PHASE_LABOR",
        "\t\tsite.is_empty()\n"
        "\t\tor str(\n"
        "\t\t\tsite.get(\"finalization_state\", FINALIZATION_STATE_NONE)\n"
        "\t\t) != FINALIZATION_STATE_NONE\n"
        "\t\tor str(site.get(\"phase\", \"\"))\n"
        "\t\t!= WorldData.CITY_CONSTRUCTION_PHASE_LABOR",
        "Construction labor finalization exclusion",
    )

    completion_block = r'''static func complete_city_construction_site(
	site_id: int
) -> Dictionary:
	var site := WorldData.get_city_construction_site_by_id(site_id)

	if site.is_empty():
		return {}

	if (
		str(site.get("finalization_state", FINALIZATION_STATE_NONE))
		== FINALIZATION_STATE_AWAITING_CLEARANCE
	):
		return _advance_city_construction_finalization(site_id)

	refresh_city_construction_site(site_id)
	site = WorldData.get_city_construction_site_by_id(site_id)

	if (
		site.is_empty()
		or str(site.get("target_kind", ""))
		!= WorldData.CITY_CONSTRUCTION_TARGET_NEW
		or str(site.get("phase", ""))
		!= WorldData.CITY_CONSTRUCTION_PHASE_LABOR
		or int(site.get("completed_labor_minutes", 0))
		< int(site.get("required_labor_minutes", 1))
		or not city_construction_site_has_all_materials(site_id)
	):
		return {}

	if not _release_site_delivery_tasks(site_id):
		return {}

	refresh_city_construction_site(site_id)
	site = WorldData.get_city_construction_site_by_id(site_id)

	if (
		site.is_empty()
		or str(site.get("phase", ""))
		!= WorldData.CITY_CONSTRUCTION_PHASE_LABOR
		or not city_construction_site_has_all_materials(site_id)
	):
		return {}

	# Labor completion is not the same operation as changing navigation. First
	# close the work claims and enter a durable finalization state. The site then
	# owns clearance and retries until the authoritative footprint is safe.
	_clear_site_labor_tasks(site_id)
	site = WorldData.get_city_construction_site_by_id(site_id)

	if site.is_empty():
		return {}

	site["finalization_state"] = FINALIZATION_STATE_AWAITING_CLEARANCE

	if not update_city_construction_site(site):
		return {}

	return _advance_city_construction_finalization(site_id)


static func _advance_city_construction_finalization(
	site_id: int
) -> Dictionary:
	var site := WorldData.get_city_construction_site_by_id(site_id)
	var city_world: WorldData = WorldData.official_city_world

	if (
		site.is_empty()
		or city_world == null
		or str(site.get("finalization_state", FINALIZATION_STATE_NONE))
		!= FINALIZATION_STATE_AWAITING_CLEARANCE
	):
		return {}

	var object_type := str(site.get("object_type", ""))
	var footprint_tiles: Array = site.get("footprint_tiles", [])
	var blocking_citizen_ids := (
		WorldData.get_city_object_topology_blocking_citizen_ids(
			object_type,
			footprint_tiles
		)
	)

	if not blocking_citizen_ids.is_empty():
		_evacuate_city_construction_footprint(
			site,
			blocking_citizen_ids
		)
		return {}

	# Resources remain physical and reserved until this exact point. If the
	# authoritative topology gate rejects the object for any late change, the
	# materials are restored and the durable site remains available to retry.
	var consumed_materials := _consume_site_materials(site)
	var raw_material_recipe = site.get("material_recipe", {})

	if (
		consumed_materials.is_empty()
		and raw_material_recipe is Dictionary
		and not raw_material_recipe.is_empty()
	):
		return {}

	var completed_object: Dictionary = {}

	if (
		str(site.get("shape_mode", ""))
		== WorldData.CITY_OBJECT_SHAPE_TILE_AREA
	):
		completed_object = WorldData.add_city_road_object(
			footprint_tiles,
			str(site.get("owner", "player")),
			city_world,
			site_id
		)
	else:
		completed_object = WorldData.add_city_object({
			"object_type": object_type,
			"top_left": site.get(
				"top_left",
				WorldData.INVALID_CITY_TILE_POSITION
			),
			"size_tiles": site.get("size", Vector2i.ZERO),
			"object_owner": str(site.get("owner", "player")),
			"city_world": city_world,
			"allowed_construction_site_id": site_id,
		})

	if completed_object.is_empty():
		_restore_site_materials(site, consumed_materials)
		return {}

	_release_site_clearing_commands(site_id)
	remove_city_construction_site_record(site_id)
	return completed_object


static func _evacuate_city_construction_footprint(
	site: Dictionary,
	citizen_ids: Array[int]
) -> void:
	var city_world: WorldData = WorldData.official_city_world

	if city_world == null or site.is_empty():
		return

	var footprint_tiles: Array = site.get("footprint_tiles", [])
	var destination_tiles := _build_external_work_positions(
		city_world,
		footprint_tiles
	)

	if destination_tiles.is_empty():
		push_warning(
			"Construction site "
				+ str(site.get("id", -1))
				+ " is ready to finalize but has no reachable exterior "
				+ "clearance tile."
		)
		return

	for citizen_id in citizen_ids:
		var citizen := WorldData.get_city_citizen_by_id(citizen_id)
		var raw_current_tile = citizen.get(
			"city_tile_position",
			WorldData.INVALID_CITY_TILE_POSITION
		)

		if (
			citizen.is_empty()
			or not bool(citizen.get("alive", false))
			or not raw_current_tile is Vector2i
			or not footprint_tiles.has(raw_current_tile)
		):
			continue

		var raw_destination = citizen.get(
			"movement_destination_tile",
			WorldData.INVALID_CITY_TILE_POSITION
		)

		if (
			str(citizen.get("movement_state", ""))
			== WorldData.CITY_CITIZEN_MOVEMENT_STATE_MOVING
			and raw_destination is Vector2i
			and not footprint_tiles.has(raw_destination)
		):
			continue

		var path_result := (
			CityNavigationSystemScript.find_path_to_any_city_tile({
				"city_world": city_world,
				"start_tile": raw_current_tile,
				"destination_tiles": destination_tiles,
				"max_expanded_nodes": (
					CityNavigationSystemScript
					.get_city_wide_path_expansion_limit(city_world)
				),
				"citizen_id": citizen_id,
				"heuristic_weight": EXACT_PATH_HEURISTIC_WEIGHT,
			})
		)

		if not bool(path_result.get("success", false)):
			push_warning(
				"Could not route citizen "
					+ str(citizen_id)
					+ " out of finalizing construction site "
					+ str(site.get("id", -1))
			)
			continue

		WorldData.cancel_city_citizen_movement(citizen_id)

		if not WorldData.assign_city_citizen_movement_order(
			citizen_id,
			path_result.get("path", [])
		):
			push_warning(
				"Could not install topology-clearance movement for citizen "
					+ str(citizen_id)
			)


'''
    text = regex_replace_once(
        text,
        r"static func complete_city_construction_site\(.*?\nstatic func _consume_site_materials\(",
        completion_block + "static func _consume_site_materials(",
        "Construction staged finalization",
    )

    write(path, text)


def patch_ci_version() -> None:
    path = ".github/workflows/godot-ci.yml"
    text = read(path)
    if "4.4.1" not in text:
        raise RuntimeError("Godot CI no longer contains the expected 4.4.1 version")
    text = text.replace("4.4.1", "4.7.1")
    write(path, text)


def write_tests() -> None:
    test_script = r'''extends Node

const CityConstructionSystemScript = preload(
	"res://scripts/city/simulation/systems/CityConstructionSystem.gd"
)
const CitizenMovementSystemScript = preload(
	"res://scripts/citizens/simulation/systems/CitizenMovementSystem.gd"
)

const TEST_WORLD_SIZE := Vector2i(32, 24)
const TEST_WORLD_SEED: int = 92_417

var failure_count: int = 0
var test_primary_culture_id: int = -1


func _ready() -> void:
	_test_low_level_topology_gate_is_generic()
	_test_construction_waits_for_footprint_clearance()
	_test_one_bad_mover_does_not_freeze_the_batch()
	_test_legacy_occupant_can_escape_but_not_reenter()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City topology safety tests failed: " + str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City topology safety tests passed.")
	get_tree().quit(0)


func _test_low_level_topology_gate_is_generic() -> void:
	print("Topology test: generic authoritative placement gate")

	for object_type in [
		WorldData.CITY_OBJECT_HOUSE,
		WorldData.CITY_OBJECT_STOCKPILE,
		WorldData.CITY_OBJECT_FISHING_GROUNDS,
	]:
		var city_world := _reset_fixture()
		var top_left := Vector2i(10, 8)
		var citizen := _add_citizen(top_left)
		var created_object := WorldData.add_city_object({
			"object_type": object_type,
			"top_left": top_left,
			"size_tiles": WorldData.get_city_object_size_for_type(
				object_type
			),
			"object_owner": "player",
			"city_world": city_world,
		})

		_expect(
			created_object.is_empty(),
			"The low-level topology gate must reject "
				+ object_type
				+ " while a living citizen occupies its footprint."
		)
		_expect(
			WorldData.get_city_object_at_tile(top_left).is_empty()
			and citizen.get("city_tile_position") == top_left,
			"Rejected topology mutations must leave both object and citizen state untouched."
		)

	var road_world := _reset_fixture()
	var road_tile := Vector2i(10, 8)
	var road_citizen := _add_citizen(road_tile)
	var road := WorldData.add_city_road_object(
		[road_tile],
		"player",
		road_world
	)
	_expect(
		not road.is_empty()
		and WorldData.is_city_tile_walkable_for_citizen(
			road_world,
			road_tile,
			int(road_citizen.get("id", -1))
		),
		"A road may complete beneath a citizen because it preserves walkability."
	)


func _test_construction_waits_for_footprint_clearance() -> void:
	print("Topology test: staged construction finalization")
	var city_world := _reset_fixture()
	var top_left := Vector2i(12, 8)
	var fishery_size := WorldData.get_city_object_size_for_type(
		WorldData.CITY_OBJECT_FISHING_GROUNDS
	)
	var site := CityConstructionSystemScript.create_rectangular_site({
		"object_type": WorldData.CITY_OBJECT_FISHING_GROUNDS,
		"top_left": top_left,
		"size_tiles": fishery_size,
		"object_owner": "player",
		"city_world": city_world,
	})
	var site_id := int(site.get("id", -1))
	_expect(site_id > 0, "The fixture must create a Fishing Grounds site.")

	if site_id <= 0:
		return

	_expect(
		CityConstructionSystemScript.add_resource_to_city_construction_site(
			site_id,
			WorldData.RESOURCE_LUMBER,
			10
		) == 10
		and CityConstructionSystemScript.add_resource_to_city_construction_site(
			site_id,
			WorldData.RESOURCE_STONE,
			4
		) == 4,
		"The finalization fixture must contain the complete physical recipe."
	)
	CityConstructionSystemScript.refresh_city_construction_site(site_id)
	site = WorldData.get_city_construction_site_by_id(site_id)
	site["completed_labor_minutes"] = int(
		site.get("required_labor_minutes", 1)
	)
	_expect(
		CityConstructionSystemScript.update_city_construction_site(site),
		"The fixture must mark labor complete."
	)

	var trapped_tile := top_left + Vector2i.ONE
	var trapped_citizen := _add_citizen(trapped_tile)
	var trapped_id := int(trapped_citizen.get("id", -1))
	var unrelated_citizen := _add_citizen(Vector2i(3, 3))
	var unrelated_id := int(unrelated_citizen.get("id", -1))
	var unrelated_path := [
		Vector2i(3, 3),
		Vector2i(4, 3),
		Vector2i(5, 3),
		Vector2i(6, 3),
		Vector2i(7, 3),
	]
	_expect(
		WorldData.assign_city_citizen_movement_order(
			unrelated_id,
			unrelated_path
		),
		"The fixture must start an unrelated mover."
	)

	var immediate_completion := (
		CityConstructionSystemScript.complete_city_construction_site(site_id)
	)
	var pending_site := WorldData.get_city_construction_site_by_id(site_id)
	var trapped_after_request := WorldData.get_city_citizen_by_id(trapped_id)

	_expect(
		immediate_completion.is_empty()
		and not pending_site.is_empty()
		and str(
			pending_site.get(
				"finalization_state",
				WorldData.CITY_CONSTRUCTION_FINALIZATION_STATE_NONE
			)
		) == WorldData.CITY_CONSTRUCTION_FINALIZATION_STATE_AWAITING_CLEARANCE,
		"Completed labor must enter durable clearance instead of creating a building over a citizen."
	)
	_expect(
		trapped_after_request.get("city_tile_position") == trapped_tile
		and str(trapped_after_request.get("movement_state", ""))
		== WorldData.CITY_CITIZEN_MOVEMENT_STATE_MOVING,
		"Clearance must give the citizen a real route without teleporting them."
	)
	_expect(
		CityConstructionSystemScript
		.get_city_construction_site_reserved_resource_amount(
			site_id,
			WorldData.RESOURCE_LUMBER
		) == 10
		and CityConstructionSystemScript
		.get_city_construction_site_reserved_resource_amount(
			site_id,
			WorldData.RESOURCE_STONE
		) == 4,
		"Materials must remain physical and reserved while clearance is pending."
	)

	for tick_index in range(1, 48):
		CitizenMovementSystemScript.run_tick(tick_index, 2)
		CityConstructionSystemScript.refresh_all_city_construction_sites()

		if WorldData.get_city_construction_site_by_id(site_id).is_empty():
			break

	var completed_fishery := WorldData.get_city_object_at_tile(top_left)
	var trapped_after_completion := WorldData.get_city_citizen_by_id(trapped_id)
	var unrelated_after_completion := WorldData.get_city_citizen_by_id(
		unrelated_id
	)
	var footprint_tiles := WorldData.make_rectangle_city_object_footprint_tiles(
		top_left,
		fishery_size
	)

	_expect(
		WorldData.get_city_construction_site_by_id(site_id).is_empty()
		and str(completed_fishery.get("type", ""))
		== WorldData.CITY_OBJECT_FISHING_GROUNDS,
		"The Fishing Grounds must finalize once its footprint is physically clear."
	)
	_expect(
		not footprint_tiles.has(
			trapped_after_completion.get(
				"city_tile_position",
				WorldData.INVALID_CITY_TILE_POSITION
			)
		),
		"The displaced citizen must finish outside the completed footprint."
	)
	_expect(
		unrelated_after_completion.get("city_tile_position")
		!= Vector2i(3, 3),
		"An unrelated citizen must keep moving while clearance occurs."
	)


func _test_one_bad_mover_does_not_freeze_the_batch() -> void:
	print("Topology test: movement fault containment")
	var city_world := _reset_fixture()
	var valid_citizen := _add_citizen(Vector2i(4, 4))
	var invalid_citizen := _add_citizen(Vector2i(8, 4))
	var valid_id := int(valid_citizen.get("id", -1))
	var invalid_id := int(invalid_citizen.get("id", -1))
	var valid_update: Dictionary = valid_citizen.duplicate(true)
	var invalid_update: Dictionary = invalid_citizen.duplicate(true)
	var commit_result := WorldData.commit_city_citizen_movement_tick(
		city_world,
		[
			{
				"citizen_id": valid_id,
				"citizen": valid_update,
				"final_tile": Vector2i(5, 4),
				"traversed_tiles": [Vector2i(4, 4), Vector2i(5, 4)],
			},
			{
				"citizen_id": invalid_id,
				"citizen": invalid_update,
				"final_tile": Vector2i(-1, -1),
				"traversed_tiles": [Vector2i(8, 4)],
			},
		],
		[]
	)

	_expect(
		bool(commit_result.get("success", false))
		and int(commit_result.get("updated_citizen_count", 0)) == 1
		and int(commit_result.get("rejected_update_count", 0)) == 1,
		"The movement transaction must commit valid citizens and quarantine only the bad update."
	)
	_expect(
		WorldData.get_city_citizen_tile_position(valid_id) == Vector2i(5, 4)
		and WorldData.get_city_citizen_tile_position(invalid_id) == Vector2i(8, 4),
		"A rejected mover must not roll back a valid mover or move itself illegally."
	)
	_expect(
		str(
			WorldData.get_city_citizen_by_id(invalid_id).get(
				"movement_state",
				""
			)
		) == WorldData.CITY_CITIZEN_MOVEMENT_STATE_BLOCKED,
		"The bad mover must enter an explicit recoverable quarantine state."
	)


func _test_legacy_occupant_can_escape_but_not_reenter() -> void:
	print("Topology test: defensive legacy escape")
	var city_world := _reset_fixture()
	var top_left := Vector2i(12, 8)
	var fishery := WorldData.add_city_object({
		"object_type": WorldData.CITY_OBJECT_FISHING_GROUNDS,
		"top_left": top_left,
		"size_tiles": WorldData.get_city_object_size_for_type(
			WorldData.CITY_OBJECT_FISHING_GROUNDS
		),
		"object_owner": "player",
		"city_world": city_world,
	})
	var trapped := _add_citizen(Vector2i(5, 5))
	var outsider := _add_citizen(Vector2i(6, 5))
	var trapped_id := int(trapped.get("id", -1))
	var trapped_tile := top_left + Vector2i.ONE
	trapped["city_tile_position"] = trapped_tile
	WorldData.rebuild_city_citizen_spatial_index()

	_expect(
		not fishery.is_empty()
		and WorldData.is_city_tile_walkable_for_citizen(
			city_world,
			trapped_tile,
			trapped_id
		),
		"A citizen already inside corrupted legacy topology must be allowed to start escaping."
	)
	_expect(
		not WorldData.is_city_tile_walkable_for_citizen(
			city_world,
			trapped_tile,
			int(outsider.get("id", -1))
		),
		"The recovery rule must not let an outside citizen enter the blocked building."
	)


func _reset_fixture() -> WorldData:
	WorldData.reset_runtime_session_state()
	SimulationClock.start_new_game()
	var city_world := WorldData.new()
	city_world.setup(TEST_WORLD_SIZE.x, TEST_WORLD_SIZE.y, TEST_WORLD_SEED)

	for y in range(city_world.height):
		for x in range(city_world.width):
			var tile := city_world.get_tile(x, y)
			tile["terrain"] = WorldData.TERRAIN_LAND
			tile["biome"] = WorldData.BIOME_PLAIN
			tile["is_land"] = true
			tile["fertility"] = 50.0
			tile.erase("surface_feature")

	city_world.mark_tile_data_changed()
	WorldData.store_city_world_save(city_world, TEST_WORLD_SEED)
	var primary_culture := WorldData.create_culture(
		"Topology Safety Test Culture"
	)
	test_primary_culture_id = int(primary_culture.get("id", -1))
	WorldData.official_city_name = "Topology Safety Test City"
	WorldData.official_founding_culture_id = test_primary_culture_id
	WorldData.player_city_founded = true
	WorldData.player_city_data = {
		"id": 1,
		"name": "Topology Safety Test City",
		"primary_culture_id": test_primary_culture_id,
		"city_world_seed": TEST_WORLD_SEED,
		"city_map_size": TEST_WORLD_SIZE,
		"can_build": true,
		"founded": true,
	}
	return city_world


func _add_citizen(tile_position: Vector2i) -> Dictionary:
	return WorldData.add_city_citizen(
		"",
		tile_position,
		WorldData.CITY_CITIZEN_SEX_FEMALE,
		test_primary_culture_id
	)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error(message)
'''

    # Correct facade calls in the generated test. Construction storage queries
    # live on WorldData, while creation/refresh operations live on the system.
    test_script = test_script.replace(
        "CityConstructionSystemScript\n\t\t.get_city_construction_site_reserved_resource_amount",
        "WorldData\n\t\t.get_city_construction_site_reserved_resource_amount",
    )

    write("scripts/city/simulation/CityTopologySafetyTest.gd", test_script)
    write(
        "scripts/city/simulation/CityTopologySafetyTest.tscn",
        '[gd_scene load_steps=2 format=3]\n\n'
        '[ext_resource type="Script" '
        'path="res://scripts/city/simulation/CityTopologySafetyTest.gd" '
        'id="1_test"]\n\n'
        '[node name="CityTopologySafetyTest" type="Node"]\n'
        'script = ExtResource("1_test")\n',
    )


def main() -> None:
    patch_world_data()
    patch_movement_system()
    patch_construction_system()
    patch_ci_version()
    write_tests()
    print("Topology safety pass applied.")


if __name__ == "__main__":
    main()
