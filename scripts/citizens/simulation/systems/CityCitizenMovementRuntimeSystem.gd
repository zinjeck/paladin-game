extends RefCounted
class_name CityCitizenMovementRuntimeSystem

const CityCitizensScript = preload(
	"res://scripts/citizens/simulation/CityCitizens.gd"
)

# Authoritative movement-order, mover-registry, atomic commit, and transient
# visual-event behavior for the active settlement. Tick/repath computation
# remains in CitizenMovementSystem.

static func get_current_state() -> CityCitizenMovementRuntimeState:
	return WorldPoliticalState.get_current_city_citizen_movement_runtime_state()


static var city_active_mover_ids: Array[int]:
	get:
		return get_current_state().active_mover_ids
	set(value):
		get_current_state().active_mover_ids = value


static var city_active_mover_id_lookup: Dictionary:
	get:
		return get_current_state().active_mover_id_lookup
	set(value):
		get_current_state().active_mover_id_lookup = value


static var city_citizen_movement_visual_events: Array:
	get:
		return get_current_state().citizen_movement_visual_events
	set(value):
		get_current_state().citizen_movement_visual_events = value


static var city_citizen_movement_visual_tick_index: int:
	get:
		return get_current_state().citizen_movement_visual_tick_index
	set(value):
		get_current_state().citizen_movement_visual_tick_index = value


static var city_citizen_movement_version: int:
	get:
		return get_current_state().citizen_movement_version
	set(value):
		get_current_state().citizen_movement_version = value


static func get_city_citizen_movement_version() -> int:
	return city_citizen_movement_version


static func reset_city_citizen_movement_runtime_state() -> void:
	city_active_mover_ids.clear()
	city_active_mover_id_lookup.clear()
	city_citizen_movement_visual_events.clear()
	city_citizen_movement_visual_tick_index = -1
	mark_city_citizen_movement_changed()


static func mark_city_citizen_movement_changed() -> void:
	city_citizen_movement_version += 1

static func _add_city_active_mover_id(
	citizen_id: int
) -> bool:
	if citizen_id <= 0:
		return false

	var insertion_index := city_active_mover_ids.bsearch(citizen_id)
	var array_has_id := (
		insertion_index < city_active_mover_ids.size()
		and city_active_mover_ids[insertion_index] == citizen_id
	)
	var lookup_is_valid := (
		city_active_mover_id_lookup.has(citizen_id)
		and bool(city_active_mover_id_lookup[citizen_id])
	)
	var array_has_duplicate := (
		array_has_id
		and insertion_index + 1 < city_active_mover_ids.size()
		and city_active_mover_ids[insertion_index + 1] == citizen_id
	)

	if array_has_id and not array_has_duplicate:
		if lookup_is_valid:
			return false
		city_active_mover_id_lookup[citizen_id] = true
		return true

	if not array_has_id:
		city_active_mover_ids.insert(insertion_index, citizen_id)
		city_active_mover_id_lookup[citizen_id] = true
		return true

	# Repair duplicate mover entries in place; this branch is corruption
	# handling, not part of the healthy movement hot path.
	while city_active_mover_ids.has(citizen_id):
		city_active_mover_ids.erase(citizen_id)

	city_active_mover_ids.insert(
		city_active_mover_ids.bsearch(citizen_id),
		citizen_id
	)
	city_active_mover_id_lookup[citizen_id] = true
	return true

static func _remove_city_active_mover_id(
	citizen_id: int
) -> bool:
	var changed := city_active_mover_id_lookup.erase(citizen_id)

	while city_active_mover_ids.has(citizen_id):
		city_active_mover_ids.erase(citizen_id)
		changed = true

	return changed

static func rebuild_city_active_mover_registry() -> bool:
	var previous_active_ids := city_active_mover_ids.duplicate()
	var previous_active_lookup := city_active_mover_id_lookup.duplicate()
	var expected_active_ids: Array[int] = []
	var expected_active_lookup: Dictionary = {}

	for raw_citizen in CityCitizenRegistrySystem.get_current_state().citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if not bool(citizen.get("alive", false)):
			continue

		if (
			str(citizen.get("movement_state", ""))
			!= WorldData.CITY_CITIZEN_MOVEMENT_STATE_MOVING
		):
			continue

		var citizen_id := int(citizen.get("id", -1))

		if citizen_id <= 0:
			continue

		if expected_active_lookup.has(citizen_id):
			continue

		expected_active_ids.append(citizen_id)
		expected_active_lookup[citizen_id] = true

	expected_active_ids.sort()

	var registry_changed := (
		previous_active_ids != expected_active_ids
		or previous_active_lookup != expected_active_lookup
	)
	city_active_mover_ids.clear()
	city_active_mover_id_lookup.clear()
	city_active_mover_ids.append_array(expected_active_ids)
	city_active_mover_id_lookup.merge(expected_active_lookup)
	if registry_changed:
		mark_city_citizen_movement_changed()

	return registry_changed

static func get_city_active_mover_ids_snapshot() -> Array[int]:
	return city_active_mover_ids.duplicate()

static func begin_city_citizen_movement_visual_tick(
	tick_index: int
) -> void:
	city_citizen_movement_visual_events.clear()
	city_citizen_movement_visual_tick_index = tick_index

static func clear_city_citizen_movement_visual_events() -> void:
	city_citizen_movement_visual_events.clear()
	city_citizen_movement_visual_tick_index = -1

static func take_city_citizen_movement_visual_events(
	expected_tick_index: int
) -> Array:
	if city_citizen_movement_visual_tick_index != expected_tick_index:
		clear_city_citizen_movement_visual_events()
		return []

	# Transfer ownership instead of deep-copying every route and corner.
	var events := city_citizen_movement_visual_events
	city_citizen_movement_visual_events = []
	city_citizen_movement_visual_tick_index = -1
	return events

static func ensure_city_citizen_movement_state() -> int:
	if CityCitizenRegistrySystem.get_current_state().citizens.is_empty():
		rebuild_city_active_mover_registry()
		return 0

	var migrated_count := 0

	for citizen_index in range(CityCitizenRegistrySystem.get_current_state().citizens.size()):
		var raw_citizen = CityCitizenRegistrySystem.get_current_state().citizens[citizen_index]

		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if (
			CityCitizensScript
			.has_complete_city_citizen_movement_state(
				citizen
			)
		):
			continue

		CityCitizensScript.reset_city_citizen_movement_state(
			citizen
		)
		CityCitizenRegistrySystem.get_current_state().citizens[citizen_index] = citizen
		migrated_count += 1

	var movement_version_before_rebuild := city_citizen_movement_version
	rebuild_city_active_mover_registry()

	if (
		migrated_count > 0
		and city_citizen_movement_version
		== movement_version_before_rebuild
	):
		mark_city_citizen_movement_changed()

	return migrated_count

static func _get_clean_city_citizen_movement_path(
	city_world: WorldData,
	raw_path: Array,
	citizen_id: int = -1
) -> Array:
	var movement_path := []

	if city_world == null:
		return movement_path

	if raw_path.is_empty():
		return movement_path

	var previous_tile := WorldData.INVALID_CITY_TILE_POSITION

	for raw_path_tile in raw_path:
		if not raw_path_tile is Vector2i:
			return []

		var path_tile: Vector2i = raw_path_tile

		if not CityNavigationSystem.is_city_tile_walkable_for_citizen(
			city_world,
			path_tile,
			citizen_id
		):
			return []

		if previous_tile != WorldData.INVALID_CITY_TILE_POSITION:
			if CityNavigationSystem.get_city_citizen_movement_step_cost(
				previous_tile,
				path_tile
			) <= 0:
				return []

			if not CityNavigationSystem.can_city_citizen_traverse_step(
				city_world,
				previous_tile,
				path_tile,
				citizen_id
			):
				return []

		movement_path.append(path_tile)
		previous_tile = path_tile

	return movement_path

static func cancel_city_citizen_movement(
	citizen_id: int
) -> bool:
	var citizen_index := CityCitizenRegistrySystem.get_city_citizen_index_by_id(
		citizen_id
	)

	if citizen_index < 0:
		return false

	var raw_citizen = CityCitizenRegistrySystem.get_current_state().citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return false

	var citizen: Dictionary = raw_citizen

	CityCitizensScript.reset_city_citizen_movement_state(
		citizen,
		true
	)
	CityCitizenRegistrySystem.get_current_state().citizens[citizen_index] = citizen

	_remove_city_active_mover_id(citizen_id)
	mark_city_citizen_movement_changed()

	return true

static func assign_city_citizen_movement_order(
	citizen_id: int,
	raw_path: Array
) -> bool:
	var city_world: WorldData = WorldData.official_city_world

	if city_world == null:
		return false

	var citizen_index := CityCitizenRegistrySystem.get_city_citizen_index_by_id(
		citizen_id
	)

	if citizen_index < 0:
		return false

	var raw_citizen = CityCitizenRegistrySystem.get_current_state().citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return false

	var citizen: Dictionary = raw_citizen

	if not bool(citizen.get("alive", false)):
		return false

	var current_position = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not current_position is Vector2i:
		return false

	var movement_path := _get_clean_city_citizen_movement_path(
		city_world,
		raw_path,
		citizen_id
	)

	if movement_path.is_empty():
		return false

	if movement_path[0] != current_position:
		return false

	if movement_path.size() == 1:
		cancel_city_citizen_movement(citizen_id)
		return true

	var movement_speed := int(
		citizen.get(
			"movement_speed_basis_points_per_minute",
			WorldData.DEFAULT_CITIZEN_MOVEMENT_SPEED_PER_MINUTE
		)
	)

	if movement_speed <= 0:
		movement_speed = (
			WorldData.DEFAULT_CITIZEN_MOVEMENT_SPEED_PER_MINUTE
		)

	citizen["movement_state"] = (
		WorldData.CITY_CITIZEN_MOVEMENT_STATE_MOVING
	)
	citizen["movement_path"] = movement_path.duplicate()
	citizen["movement_path_index"] = 1
	citizen["movement_progress_basis_points"] = 0
	citizen["movement_destination_tile"] = (
		movement_path.back()
	)
	citizen["movement_speed_basis_points_per_minute"] = (
		movement_speed
	)
	citizen["movement_repath_attempt_count"] = 0
	citizen["movement_failure_reason"] = (
		WorldData.CITY_CITIZEN_MOVEMENT_FAILURE_NONE
	)

	CityCitizenRegistrySystem.get_current_state().citizens[citizen_index] = citizen

	_add_city_active_mover_id(citizen_id)
	mark_city_citizen_movement_changed()

	return true

static func commit_city_citizen_movement_tick(
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
	var spatial_index_changed := bool(
		application_result.get("spatial_index_changed", false)
	)
	var quarantined_count := (
		_quarantine_rejected_city_citizen_movement_updates(
			rejected_updates
		)
	)
	var active_registry_changed := (
		_replace_city_active_mover_registry(clean_next_active_ids)
	)

	if (
		not clean_updates.is_empty()
		or quarantined_count > 0
		or active_registry_changed
	):
		mark_city_citizen_movement_changed()

	if spatial_index_changed:
		CityCitizenSpatialSystem.mark_city_citizen_spatial_changed()

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
	final_tile = WorldData.INVALID_CITY_TILE_POSITION,
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
			CityObjectSystem.get_city_object_id_at_tile(final_tile)
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
					WorldData.INVALID_CITY_TILE_POSITION,
					false
				)
			)
			continue

		var update: Dictionary = raw_update
		var citizen_id := int(update.get("citizen_id", -1))
		var raw_updated_citizen = update.get("citizen", {})
		var raw_final_tile = update.get(
			"final_tile",
			WorldData.INVALID_CITY_TILE_POSITION
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

		var citizen_index := CityCitizenRegistrySystem.get_city_citizen_index_by_id(citizen_id)

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

		var existing_citizen = CityCitizenRegistrySystem.get_current_state().citizens[citizen_index]

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

		var authoritative_position = existing_citizen.get(
			"city_tile_position",
			WorldData.INVALID_CITY_TILE_POSITION
		)

		if not authoritative_position is Vector2i:
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"authoritative_position_invalid",
					raw_final_tile
				)
			)
			continue

		# A dead active mover still emits one same-tile update so its movement
		# state and spatial membership can be retired. The tile may have become
		# non-walkable since the citizen was placed, so that cleanup must not be
		# blocked by the normal destination gate.
		var is_non_living_same_tile_cleanup: bool = (
			not bool(existing_citizen.get("alive", false))
			and not bool(updated_citizen.get("alive", false))
			and raw_final_tile == authoritative_position
		)
		var includes_non_living_citizen: bool = (
			not bool(existing_citizen.get("alive", false))
			or not bool(updated_citizen.get("alive", false))
		)

		if includes_non_living_citizen and not is_non_living_same_tile_cleanup:
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"non_living_movement_relocation",
					raw_final_tile
				)
			)
			continue

		if (
			not is_non_living_same_tile_cleanup
			and not CityNavigationSystem.is_city_tile_walkable_for_citizen(
				city_world,
				raw_final_tile,
				citizen_id
			)
		):
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"final_tile_not_walkable",
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
					WorldData.INVALID_CITY_TILE_POSITION,
					false
				)
			)
			continue

		var proposed_citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)

		if clean_update_by_id.has(citizen_id):
			var proposed_update: Dictionary = clean_update_by_id[citizen_id]
			proposed_citizen = proposed_update.get("citizen", {})

		if proposed_citizen.is_empty():
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"active_mover_citizen_missing",
					WorldData.INVALID_CITY_TILE_POSITION,
					false
				)
			)
			continue

		if not bool(proposed_citizen.get("alive", false)):
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"active_mover_not_alive",
					WorldData.INVALID_CITY_TILE_POSITION,
					false
				)
			)
			continue

		if (
			str(proposed_citizen.get("movement_state", ""))
			!= WorldData.CITY_CITIZEN_MOVEMENT_STATE_MOVING
		):
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"active_registry_entry_not_moving",
					WorldData.INVALID_CITY_TILE_POSITION,
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

		var citizen_index := CityCitizenRegistrySystem.get_city_citizen_index_by_id(citizen_id)

		if citizen_index < 0:
			continue

		var raw_citizen = CityCitizenRegistrySystem.get_current_state().citizens[citizen_index]

		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		CityCitizensScript.reset_city_citizen_movement_state(citizen, true)
		citizen["movement_state"] = WorldData.CITY_CITIZEN_MOVEMENT_STATE_BLOCKED
		citizen["movement_failure_reason"] = (
			WorldData.CITY_CITIZEN_MOVEMENT_FAILURE_INVALID_PATH
		)
		CityCitizenRegistrySystem.get_current_state().citizens[citizen_index] = citizen
		quarantined_ids[citizen_id] = true

	return quarantined_ids.size()

static func _apply_city_citizen_movement_updates(
	clean_updates: Array
) -> Dictionary:
	var moved_citizen_count := 0
	var spatial_index_changed := false
	var movement_visual_events: Array = []

	for clean_update in clean_updates:
		var citizen_id := int(clean_update.get("citizen_id", -1))
		var citizen_index := int(clean_update.get("citizen_index", -1))
		var updated_citizen: Dictionary = clean_update.get("citizen", {})
		var final_tile: Vector2i = clean_update.get(
			"final_tile",
			WorldData.INVALID_CITY_TILE_POSITION
		)
		var existing_citizen: Dictionary = CityCitizenRegistrySystem.get_current_state().citizens[citizen_index]
		var old_tile: Vector2i = existing_citizen.get(
			"city_tile_position",
			WorldData.INVALID_CITY_TILE_POSITION
		)
		var movement_visual_event := _make_city_citizen_movement_visual_event({
			"before_citizen": existing_citizen,
			"after_citizen": updated_citizen,
			"before_tile": old_tile,
			"after_tile": final_tile,
			"traversed_tiles": clean_update.get("traversed_tiles", []),
		})

		if not movement_visual_event.is_empty():
			movement_visual_events.append(movement_visual_event)

		if old_tile != final_tile:
			if CityCitizenSpatialSystem.remove_city_citizen_from_spatial_index(citizen_id, old_tile):
				spatial_index_changed = true
			moved_citizen_count += 1
		elif not bool(updated_citizen.get("alive", false)):
			if CityCitizenSpatialSystem.remove_city_citizen_from_spatial_index(citizen_id, old_tile):
				spatial_index_changed = true

		updated_citizen["city_tile_position"] = final_tile
		CityCitizenRegistrySystem.get_current_state().citizens[citizen_index] = updated_citizen
		if (
			bool(updated_citizen.get("alive", false))
			and CityCitizenSpatialSystem.add_city_citizen_to_spatial_index(citizen_id, final_tile)
		):
			spatial_index_changed = true

	return {
		"moved_citizen_count": moved_citizen_count,
		"spatial_index_changed": spatial_index_changed,
		"movement_visual_events": movement_visual_events,
	}

static func _replace_city_active_mover_registry(
	clean_next_active_ids: Array[int]
) -> bool:
	var expected_lookup: Dictionary = {}
	for citizen_id in clean_next_active_ids:
		expected_lookup[citizen_id] = true

	var registry_changed := (
		city_active_mover_ids != clean_next_active_ids
		or city_active_mover_id_lookup != expected_lookup
	)
	city_active_mover_ids.clear()
	city_active_mover_id_lookup.clear()

	for citizen_id in clean_next_active_ids:
		city_active_mover_ids.append(citizen_id)
		city_active_mover_id_lookup[citizen_id] = true

	return registry_changed

static func _make_city_citizen_movement_visual_event(
	values: Dictionary
) -> Dictionary:
	var before_citizen: Dictionary = values.get("before_citizen", {})
	var after_citizen: Dictionary = values.get("after_citizen", {})
	var before_tile: Vector2i = values.get(
		"before_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var after_tile: Vector2i = values.get(
		"after_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var raw_traversed_tiles = values.get("traversed_tiles", [])
	var citizen_id := int(before_citizen.get("id", -1))

	if citizen_id <= 0:
		return {}

	if int(after_citizen.get("id", -1)) != citizen_id:
		return {}

	return {
		"citizen_id": citizen_id,
		"before": _make_city_citizen_movement_visual_snapshot(
			before_citizen,
			before_tile
		),
		"after": _make_city_citizen_movement_visual_snapshot(
			after_citizen,
			after_tile
		),
		"traversed_tiles": (
			_get_clean_city_citizen_movement_visual_trace(
				before_tile,
				after_tile,
				raw_traversed_tiles
			)
		)
	}

static func _make_city_citizen_movement_visual_snapshot(
	citizen: Dictionary,
	tile_position: Vector2i
) -> Dictionary:
	var raw_path = citizen.get("movement_path", [])
	var movement_path_index := int(citizen.get(
		"movement_path_index",
		0
	))
	var movement_progress := int(citizen.get(
		"movement_progress_basis_points",
		0
	))
	var movement_state := str(citizen.get("movement_state", ""))
	var visual_position := Vector2(tile_position)
	var visual_step_target_tile := WorldData.INVALID_CITY_TILE_POSITION

	if (
		movement_state == WorldData.CITY_CITIZEN_MOVEMENT_STATE_MOVING
		and raw_path is Array
		and movement_path_index >= 1
		and movement_path_index < raw_path.size()
		and raw_path[movement_path_index - 1] is Vector2i
		and raw_path[movement_path_index] is Vector2i
	):
		var from_tile: Vector2i = raw_path[movement_path_index - 1]
		var to_tile: Vector2i = raw_path[movement_path_index]
		var step_cost := CityNavigationSystem.get_city_citizen_movement_step_cost(
			from_tile,
			to_tile
		)

		if step_cost > 0:
			visual_step_target_tile = to_tile
			visual_position = Vector2(from_tile).lerp(
				Vector2(to_tile),
				clampf(
					float(movement_progress) / float(step_cost),
					0.0,
					1.0
				)
			)

	return {
		"id": int(citizen.get("id", -1)),
		"alive": bool(citizen.get("alive", false)),
		"city_tile_position": tile_position,
		"movement_state": movement_state,
		"movement_visual_position": visual_position,
		"movement_visual_step_target_tile": visual_step_target_tile,
		"movement_speed_basis_points_per_minute": int(citizen.get(
			"movement_speed_basis_points_per_minute",
			WorldData.DEFAULT_CITIZEN_MOVEMENT_SPEED_PER_MINUTE
		))
	}

static func _get_clean_city_citizen_movement_visual_trace(
	before_tile: Vector2i,
	after_tile: Vector2i,
	raw_traversed_tiles
) -> Array[Vector2i]:
	var clean_tiles: Array[Vector2i] = [before_tile]

	if raw_traversed_tiles is Array:
		for raw_tile in raw_traversed_tiles:
			if not raw_tile is Vector2i:
				continue

			var tile: Vector2i = raw_tile

			if tile == clean_tiles.back():
				continue

			if (
				CityNavigationSystem.get_city_citizen_movement_step_cost(
					clean_tiles.back(),
					tile
				)
				<= 0
			):
				break

			clean_tiles.append(tile)

	if (
		clean_tiles.back() != after_tile
		and CityNavigationSystem.get_city_citizen_movement_step_cost(
			clean_tiles.back(),
			after_tile
		) > 0
	):
		clean_tiles.append(after_tile)

	return clean_tiles
