extends RefCounted
class_name CityCitizenMovementRuntimeSystem

const CityCitizensScript = preload(
	"res://scripts/citizens/simulation/CityCitizens.gd"
)

# Authoritative movement-order, mover-registry, atomic commit, and transient
# visual-event behavior for an explicitly supplied settlement. Tick/repath
# computation remains in CitizenMovementSystem.

static func _get_compatibility_city_state() -> CitySettlementSimulationState:
	return CityCitizenUnboundCompatibility.get_city_state()


static func get_current_state() -> CityCitizenMovementRuntimeState:
	return _get_compatibility_city_state().citizen_movement_runtime_state


static func _get_runtime_state(
	city_state = null
) -> CityCitizenMovementRuntimeState:
	if city_state is CitySettlementSimulationState:
		return city_state.citizen_movement_runtime_state
	return _get_compatibility_city_state().citizen_movement_runtime_state


static func _get_registry_state(
	city_state = null
) -> CityCitizenRegistryState:
	if city_state is CitySettlementSimulationState:
		return city_state.citizen_registry_state
	return _get_compatibility_city_state().citizen_registry_state


static func _get_city_world(city_state = null):
	if city_state is CitySettlementSimulationState:
		return city_state.city_world
	return _get_compatibility_city_state().city_world


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
	return _get_runtime_state().citizen_movement_version


static func get_city_citizen_movement_version_for_city_state(
	city_state: CitySettlementSimulationState
) -> int:
	return _get_runtime_state(city_state).citizen_movement_version


static func reset_city_citizen_movement_runtime_state() -> void:
	_reset_city_citizen_movement_runtime_state(
		_get_compatibility_city_state()
	)


static func reset_city_citizen_movement_runtime_state_for_city_state(
	city_state: CitySettlementSimulationState
) -> void:
	_reset_city_citizen_movement_runtime_state(city_state)


static func _reset_city_citizen_movement_runtime_state(city_state) -> void:
	var runtime_state := _get_runtime_state(city_state)
	runtime_state.active_mover_ids.clear()
	runtime_state.active_mover_id_lookup.clear()
	runtime_state.citizen_movement_visual_events.clear()
	runtime_state.citizen_movement_visual_tick_index = -1
	_mark_city_citizen_movement_changed(city_state)


static func mark_city_citizen_movement_changed() -> void:
	_mark_city_citizen_movement_changed(_get_compatibility_city_state())


static func mark_city_citizen_movement_changed_for_city_state(
	city_state: CitySettlementSimulationState
) -> void:
	_mark_city_citizen_movement_changed(city_state)


static func _mark_city_citizen_movement_changed(city_state) -> void:
	_get_runtime_state(city_state).citizen_movement_version += 1

static func _add_city_active_mover_id(
	citizen_id: int,
	city_state = null
) -> bool:
	var runtime_state := _get_runtime_state(city_state)
	var active_ids := runtime_state.active_mover_ids
	var active_lookup := runtime_state.active_mover_id_lookup
	if citizen_id <= 0:
		return false

	var insertion_index := active_ids.bsearch(citizen_id)
	var array_has_id := (
		insertion_index < active_ids.size()
		and active_ids[insertion_index] == citizen_id
	)
	var lookup_is_valid := (
		active_lookup.has(citizen_id)
		and bool(active_lookup[citizen_id])
	)
	var array_has_duplicate := (
		array_has_id
		and insertion_index + 1 < active_ids.size()
		and active_ids[insertion_index + 1] == citizen_id
	)

	if array_has_id and not array_has_duplicate:
		if lookup_is_valid:
			return false
		active_lookup[citizen_id] = true
		return true

	if not array_has_id:
		active_ids.insert(insertion_index, citizen_id)
		active_lookup[citizen_id] = true
		return true

	# Repair duplicate mover entries in place; this branch is corruption
	# handling, not part of the healthy movement hot path.
	while active_ids.has(citizen_id):
		active_ids.erase(citizen_id)

	active_ids.insert(
		active_ids.bsearch(citizen_id),
		citizen_id
	)
	active_lookup[citizen_id] = true
	return true

static func _remove_city_active_mover_id(
	citizen_id: int,
	city_state = null
) -> bool:
	var runtime_state := _get_runtime_state(city_state)
	var changed := runtime_state.active_mover_id_lookup.erase(citizen_id)

	while runtime_state.active_mover_ids.has(citizen_id):
		runtime_state.active_mover_ids.erase(citizen_id)
		changed = true

	return changed

static func rebuild_city_active_mover_registry() -> bool:
	return _rebuild_city_active_mover_registry(
		_get_compatibility_city_state()
	)


static func rebuild_city_active_mover_registry_for_city_state(
	city_state: CitySettlementSimulationState
) -> bool:
	return _rebuild_city_active_mover_registry(city_state)


static func _rebuild_city_active_mover_registry(city_state) -> bool:
	var runtime_state := _get_runtime_state(city_state)
	var registry_state := _get_registry_state(city_state)
	var previous_active_ids := runtime_state.active_mover_ids.duplicate()
	var previous_active_lookup := runtime_state.active_mover_id_lookup.duplicate()
	var expected_active_ids: Array[int] = []
	var expected_active_lookup: Dictionary = {}

	for raw_citizen in registry_state.citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if not bool(citizen.get("alive", false)):
			continue

		if (
			str(citizen.get("movement_state", ""))
			!= CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_MOVING
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
	runtime_state.active_mover_ids.clear()
	runtime_state.active_mover_id_lookup.clear()
	runtime_state.active_mover_ids.append_array(expected_active_ids)
	runtime_state.active_mover_id_lookup.merge(expected_active_lookup)
	if registry_changed:
		_mark_city_citizen_movement_changed(city_state)

	return registry_changed

static func get_city_active_mover_ids_snapshot() -> Array[int]:
	return _get_runtime_state().active_mover_ids.duplicate()


static func get_city_active_mover_ids_snapshot_for_city_state(
	city_state: CitySettlementSimulationState
) -> Array[int]:
	return _get_runtime_state(city_state).active_mover_ids.duplicate()

static func begin_city_citizen_movement_visual_tick(
	tick_index: int
) -> void:
	_begin_city_citizen_movement_visual_tick(
		_get_compatibility_city_state(),
		tick_index
	)


static func begin_city_citizen_movement_visual_tick_for_city_state(
	city_state: CitySettlementSimulationState,
	tick_index: int
) -> void:
	_begin_city_citizen_movement_visual_tick(city_state, tick_index)


static func _begin_city_citizen_movement_visual_tick(
	city_state,
	tick_index: int
) -> void:
	var runtime_state := _get_runtime_state(city_state)
	runtime_state.citizen_movement_visual_events.clear()
	runtime_state.citizen_movement_visual_tick_index = tick_index

static func clear_city_citizen_movement_visual_events() -> void:
	_clear_city_citizen_movement_visual_events(
		_get_compatibility_city_state()
	)


static func clear_city_citizen_movement_visual_events_for_city_state(
	city_state: CitySettlementSimulationState
) -> void:
	_clear_city_citizen_movement_visual_events(city_state)


static func _clear_city_citizen_movement_visual_events(city_state) -> void:
	var runtime_state := _get_runtime_state(city_state)
	runtime_state.citizen_movement_visual_events.clear()
	runtime_state.citizen_movement_visual_tick_index = -1

static func take_city_citizen_movement_visual_events(
	expected_tick_index: int
) -> Array:
	return _take_city_citizen_movement_visual_events(
		_get_compatibility_city_state(),
		expected_tick_index
	)


static func take_city_citizen_movement_visual_events_for_city_state(
	city_state: CitySettlementSimulationState,
	expected_tick_index: int
) -> Array:
	return _take_city_citizen_movement_visual_events(
		city_state,
		expected_tick_index
	)


static func _take_city_citizen_movement_visual_events(
	city_state,
	expected_tick_index: int
) -> Array:
	var runtime_state := _get_runtime_state(city_state)
	if runtime_state.citizen_movement_visual_tick_index != expected_tick_index:
		_clear_city_citizen_movement_visual_events(city_state)
		return []

	# Transfer ownership instead of deep-copying every route and corner.
	var events := runtime_state.citizen_movement_visual_events
	runtime_state.citizen_movement_visual_events = []
	runtime_state.citizen_movement_visual_tick_index = -1
	return events

static func ensure_city_citizen_movement_state() -> int:
	return _ensure_city_citizen_movement_state(
		_get_compatibility_city_state()
	)


static func ensure_city_citizen_movement_state_for_city_state(
	city_state: CitySettlementSimulationState
) -> int:
	return _ensure_city_citizen_movement_state(city_state)


static func _ensure_city_citizen_movement_state(city_state) -> int:
	var registry_state := _get_registry_state(city_state)
	var runtime_state := _get_runtime_state(city_state)
	if registry_state.citizens.is_empty():
		_rebuild_city_active_mover_registry(city_state)
		return 0

	var migrated_count := 0

	for citizen_index in range(registry_state.citizens.size()):
		var raw_citizen = registry_state.citizens[citizen_index]

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

		CityCitizens.reset_city_citizen_movement_state(
			citizen
		)
		registry_state.citizens[citizen_index] = citizen
		migrated_count += 1

	var movement_version_before_rebuild := runtime_state.citizen_movement_version
	_rebuild_city_active_mover_registry(city_state)

	if (
		migrated_count > 0
		and runtime_state.citizen_movement_version
		== movement_version_before_rebuild
	):
		_mark_city_citizen_movement_changed(city_state)

	return migrated_count

static func _get_clean_city_citizen_movement_path(
	city_world: WorldData,
	raw_path: Array,
	citizen_id: int = -1,
	city_state = null
) -> Array:
	var movement_path := []

	if city_world == null:
		return movement_path

	if raw_path.is_empty():
		return movement_path

	var previous_tile := CityCitizens.INVALID_CITY_TILE_POSITION

	for raw_path_tile in raw_path:
		if not raw_path_tile is Vector2i:
			return []

		var path_tile: Vector2i = raw_path_tile

		var tile_is_walkable := (
			CityNavigationSystem.is_city_tile_walkable_for_citizen(
				city_world,
				path_tile,
				citizen_id
			)
			if city_state == null
			else CityNavigationSystem.is_city_tile_walkable_for_citizen_for_city_state(
				city_state,
				city_world,
				path_tile,
				citizen_id
			)
		)
		if not tile_is_walkable:
			return []

		if previous_tile != CityCitizens.INVALID_CITY_TILE_POSITION:
			var step_cost := (
				CityNavigationSystem.get_city_citizen_movement_step_cost(
					previous_tile,
					path_tile
				)
				if city_state == null
				else CityNavigationSystem.get_city_citizen_movement_step_cost_for_city_state(
					city_state,
					previous_tile,
					path_tile
				)
			)
			if step_cost <= 0:
				return []

			var can_traverse := (
				CityNavigationSystem.can_city_citizen_traverse_step(
					city_world,
					previous_tile,
					path_tile,
					citizen_id
				)
				if city_state == null
				else CityNavigationSystem.can_city_citizen_traverse_step_for_city_state(
					city_state,
					city_world,
					previous_tile,
					path_tile,
					citizen_id
				)
			)
			if not can_traverse:
				return []

		movement_path.append(path_tile)
		previous_tile = path_tile

	return movement_path

static func cancel_city_citizen_movement(
	citizen_id: int
) -> bool:
	return _cancel_city_citizen_movement(
		_get_compatibility_city_state(),
		citizen_id
	)


static func cancel_city_citizen_movement_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> bool:
	return _cancel_city_citizen_movement(city_state, citizen_id)


static func _cancel_city_citizen_movement(
	city_state,
	citizen_id: int
) -> bool:
	var registry_state := _get_registry_state(city_state)
	var citizen_index := -1
	if registry_state.citizen_index_by_id.has(citizen_id):
		citizen_index = int(registry_state.citizen_index_by_id[citizen_id])

	if citizen_index < 0:
		return false

	var raw_citizen = registry_state.citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return false

	var citizen: Dictionary = raw_citizen

	CityCitizens.reset_city_citizen_movement_state(
		citizen,
		true
	)
	registry_state.citizens[citizen_index] = citizen

	_remove_city_active_mover_id(citizen_id, city_state)
	_mark_city_citizen_movement_changed(city_state)

	return true

static func assign_city_citizen_movement_order(
	citizen_id: int,
	raw_path: Array
) -> bool:
	return _assign_city_citizen_movement_order(
		_get_compatibility_city_state(),
		citizen_id,
		raw_path
	)


static func assign_city_citizen_movement_order_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	raw_path: Array
) -> bool:
	return _assign_city_citizen_movement_order(
		city_state,
		citizen_id,
		raw_path
	)


static func _assign_city_citizen_movement_order(
	city_state,
	citizen_id: int,
	raw_path: Array
) -> bool:
	var city_world: WorldData = _get_city_world(city_state)

	if city_world == null:
		return false

	var registry_state := _get_registry_state(city_state)
	var citizen_index := -1
	if registry_state.citizen_index_by_id.has(citizen_id):
		citizen_index = int(registry_state.citizen_index_by_id[citizen_id])

	if citizen_index < 0:
		return false

	var raw_citizen = registry_state.citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return false

	var citizen: Dictionary = raw_citizen

	if not bool(citizen.get("alive", false)):
		return false

	var current_position = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if not current_position is Vector2i:
		return false

	var movement_path := _get_clean_city_citizen_movement_path(
		city_world,
		raw_path,
		citizen_id,
		city_state
	)

	if movement_path.is_empty():
		return false

	if movement_path[0] != current_position:
		return false

	if movement_path.size() == 1:
		_cancel_city_citizen_movement(city_state, citizen_id)
		return true

	var movement_speed := int(
		citizen.get(
			"movement_speed_basis_points_per_minute",
			CityCitizens.DEFAULT_CITIZEN_MOVEMENT_SPEED_PER_MINUTE
		)
	)

	if movement_speed <= 0:
		movement_speed = (
			CityCitizens.DEFAULT_CITIZEN_MOVEMENT_SPEED_PER_MINUTE
		)

	citizen["movement_state"] = (
		CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_MOVING
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
		CityCitizens.CITY_CITIZEN_MOVEMENT_FAILURE_NONE
	)

	registry_state.citizens[citizen_index] = citizen

	_add_city_active_mover_id(citizen_id, city_state)
	_mark_city_citizen_movement_changed(city_state)

	return true

static func commit_city_citizen_movement_tick(
	city_world: WorldData,
	raw_citizen_updates: Array,
	raw_next_active_mover_ids: Array[int]
) -> Dictionary:
	return _commit_city_citizen_movement_tick(
		_get_compatibility_city_state(),
		city_world,
		raw_citizen_updates,
		raw_next_active_mover_ids
	)


static func commit_city_citizen_movement_tick_for_city_state(
	city_state: CitySettlementSimulationState,
	city_world: WorldData,
	raw_citizen_updates: Array,
	raw_next_active_mover_ids: Array[int]
) -> Dictionary:
	return _commit_city_citizen_movement_tick(
		city_state,
		city_world,
		raw_citizen_updates,
		raw_next_active_mover_ids
	)


static func _commit_city_citizen_movement_tick(
	city_state,
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
		city_state,
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
		city_state,
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
		city_state,
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
			city_state,
			rejected_updates
		)
	)
	var active_registry_changed := (
		_replace_city_active_mover_registry(city_state, clean_next_active_ids)
	)

	if (
		not clean_updates.is_empty()
		or quarantined_count > 0
		or active_registry_changed
	):
		_mark_city_citizen_movement_changed(city_state)

	if spatial_index_changed:
		if city_state == null:
			CityCitizenSpatialSystem.mark_city_citizen_spatial_changed()
		else:
			CityCitizenSpatialSystem.mark_city_citizen_spatial_changed_for_city_state(
				city_state
			)

	_get_runtime_state(city_state).citizen_movement_visual_events = application_result.get(
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
	city_state,
	citizen_id: int,
	reason: String,
	final_tile = CityCitizens.INVALID_CITY_TILE_POSITION,
	quarantine: bool = true
) -> Dictionary:
	var rejection := {
		"citizen_id": citizen_id,
		"reason": reason,
		"quarantine": quarantine,
	}

	if final_tile is Vector2i:
		rejection["final_tile"] = final_tile
		if city_state == null:
			rejection["occupying_object_id"] = int(
				CityObjectSystem.get_city_object_id_at_tile(final_tile)
			)
		else:
			rejection["occupying_object_id"] = int(
				CityObjectSystem.get_city_object_id_at_tile_for_city_state(
					city_state,
					final_tile
				)
			)

	return rejection

static func _normalize_city_citizen_movement_updates(
	city_state,
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
					city_state,
					-1,
					"update_is_not_dictionary",
					CityCitizens.INVALID_CITY_TILE_POSITION,
					false
				)
			)
			continue

		var update: Dictionary = raw_update
		var citizen_id := int(update.get("citizen_id", -1))
		var raw_updated_citizen = update.get("citizen", {})
		var raw_final_tile = update.get(
			"final_tile",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)
		var raw_traversed_tiles = update.get("traversed_tiles", [])

		if citizen_id <= 0:
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					city_state,
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
					city_state,
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
					city_state,
					citizen_id,
					"updated_citizen_is_not_dictionary",
					raw_final_tile
				)
			)
			continue

		if not raw_final_tile is Vector2i:
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					city_state,
					citizen_id,
					"final_tile_is_not_vector"
				)
			)
			continue

		if not raw_traversed_tiles is Array:
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					city_state,
					citizen_id,
					"traversed_tiles_is_not_array",
					raw_final_tile
				)
			)
			continue

		var registry_state := _get_registry_state(city_state)
		var citizen_index := -1
		if registry_state.citizen_index_by_id.has(citizen_id):
			citizen_index = int(registry_state.citizen_index_by_id[citizen_id])

		if citizen_index < 0:
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					city_state,
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
					city_state,
					citizen_id,
					"updated_citizen_id_mismatch",
					raw_final_tile
				)
			)
			continue

		var existing_citizen = registry_state.citizens[citizen_index]

		if not existing_citizen is Dictionary:
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					city_state,
					citizen_id,
					"authoritative_citizen_is_not_dictionary",
					raw_final_tile,
					false
				)
			)
			continue

		var authoritative_position = existing_citizen.get(
			"city_tile_position",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)

		if not authoritative_position is Vector2i:
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					city_state,
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
					city_state,
					citizen_id,
					"non_living_movement_relocation",
					raw_final_tile
				)
			)
			continue

		var final_tile_is_walkable := (
			CityNavigationSystem.is_city_tile_walkable_for_citizen(
				city_world,
				raw_final_tile,
				citizen_id
			)
			if city_state == null
			else CityNavigationSystem.is_city_tile_walkable_for_citizen_for_city_state(
				city_state,
				city_world,
				raw_final_tile,
				citizen_id
			)
		)
		if not is_non_living_same_tile_cleanup and not final_tile_is_walkable:
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					city_state,
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
	city_state,
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
					city_state,
					citizen_id,
					"invalid_or_duplicate_active_mover",
					CityCitizens.INVALID_CITY_TILE_POSITION,
					false
				)
			)
			continue

		var proposed_citizen: Dictionary = {}
		var registry_state := _get_registry_state(city_state)
		if registry_state.citizen_index_by_id.has(citizen_id):
			var citizen_index := int(
				registry_state.citizen_index_by_id[citizen_id]
			)
			if citizen_index >= 0 and citizen_index < registry_state.citizens.size():
				var raw_citizen = registry_state.citizens[citizen_index]
				if raw_citizen is Dictionary:
					proposed_citizen = raw_citizen

		if clean_update_by_id.has(citizen_id):
			var proposed_update: Dictionary = clean_update_by_id[citizen_id]
			proposed_citizen = proposed_update.get("citizen", {})

		if proposed_citizen.is_empty():
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					city_state,
					citizen_id,
					"active_mover_citizen_missing",
					CityCitizens.INVALID_CITY_TILE_POSITION,
					false
				)
			)
			continue

		if not bool(proposed_citizen.get("alive", false)):
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					city_state,
					citizen_id,
					"active_mover_not_alive",
					CityCitizens.INVALID_CITY_TILE_POSITION,
					false
				)
			)
			continue

		if (
			str(proposed_citizen.get("movement_state", ""))
			!= CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_MOVING
		):
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					city_state,
					citizen_id,
					"active_registry_entry_not_moving",
					CityCitizens.INVALID_CITY_TILE_POSITION,
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
	city_state,
	rejected_updates: Array
) -> int:
	var registry_state := _get_registry_state(city_state)
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

		var citizen_index := -1
		if registry_state.citizen_index_by_id.has(citizen_id):
			citizen_index = int(registry_state.citizen_index_by_id[citizen_id])

		if citizen_index < 0:
			continue

		var raw_citizen = registry_state.citizens[citizen_index]

		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		CityCitizens.reset_city_citizen_movement_state(citizen, true)
		citizen["movement_state"] = CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_BLOCKED
		citizen["movement_failure_reason"] = (
			CityCitizens.CITY_CITIZEN_MOVEMENT_FAILURE_INVALID_PATH
		)
		registry_state.citizens[citizen_index] = citizen
		quarantined_ids[citizen_id] = true

	return quarantined_ids.size()

static func _apply_city_citizen_movement_updates(
	city_state,
	clean_updates: Array
) -> Dictionary:
	var registry_state := _get_registry_state(city_state)
	var moved_citizen_count := 0
	var spatial_index_changed := false
	var movement_visual_events: Array = []

	for clean_update in clean_updates:
		var citizen_id := int(clean_update.get("citizen_id", -1))
		var citizen_index := int(clean_update.get("citizen_index", -1))
		var updated_citizen: Dictionary = clean_update.get("citizen", {})
		var final_tile: Vector2i = clean_update.get(
			"final_tile",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)
		var existing_citizen: Dictionary = registry_state.citizens[citizen_index]
		var old_tile: Vector2i = existing_citizen.get(
			"city_tile_position",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)
		var movement_visual_event := _make_city_citizen_movement_visual_event({
			"city_state": city_state,
			"before_citizen": existing_citizen,
			"after_citizen": updated_citizen,
			"before_tile": old_tile,
			"after_tile": final_tile,
			"traversed_tiles": clean_update.get("traversed_tiles", []),
		})

		if not movement_visual_event.is_empty():
			movement_visual_events.append(movement_visual_event)

		if old_tile != final_tile:
			var removed_from_old_tile := (
				CityCitizenSpatialSystem.remove_city_citizen_from_spatial_index(
					citizen_id,
					old_tile
				)
				if city_state == null
				else CityCitizenSpatialSystem.remove_city_citizen_from_spatial_index_for_city_state(
					city_state,
					citizen_id,
					old_tile
				)
			)
			if removed_from_old_tile:
				spatial_index_changed = true
			moved_citizen_count += 1
		elif not bool(updated_citizen.get("alive", false)):
			var removed_dead_citizen := (
				CityCitizenSpatialSystem.remove_city_citizen_from_spatial_index(
					citizen_id,
					old_tile
				)
				if city_state == null
				else CityCitizenSpatialSystem.remove_city_citizen_from_spatial_index_for_city_state(
					city_state,
					citizen_id,
					old_tile
				)
			)
			if removed_dead_citizen:
				spatial_index_changed = true

		updated_citizen["city_tile_position"] = final_tile
		registry_state.citizens[citizen_index] = updated_citizen
		var added_to_final_tile := false
		if bool(updated_citizen.get("alive", false)):
			added_to_final_tile = (
				CityCitizenSpatialSystem.add_city_citizen_to_spatial_index(
					citizen_id,
					final_tile
				)
				if city_state == null
				else CityCitizenSpatialSystem.add_city_citizen_to_spatial_index_for_city_state(
					city_state,
					citizen_id,
					final_tile
				)
			)
		if added_to_final_tile:
			spatial_index_changed = true

	return {
		"moved_citizen_count": moved_citizen_count,
		"spatial_index_changed": spatial_index_changed,
		"movement_visual_events": movement_visual_events,
	}

static func _replace_city_active_mover_registry(
	city_state,
	clean_next_active_ids: Array[int]
) -> bool:
	var runtime_state := _get_runtime_state(city_state)
	var expected_lookup: Dictionary = {}
	for citizen_id in clean_next_active_ids:
		expected_lookup[citizen_id] = true

	var registry_changed := (
		runtime_state.active_mover_ids != clean_next_active_ids
		or runtime_state.active_mover_id_lookup != expected_lookup
	)
	runtime_state.active_mover_ids.clear()
	runtime_state.active_mover_id_lookup.clear()

	for citizen_id in clean_next_active_ids:
		runtime_state.active_mover_ids.append(citizen_id)
		runtime_state.active_mover_id_lookup[citizen_id] = true

	return registry_changed

static func _make_city_citizen_movement_visual_event(
	values: Dictionary
) -> Dictionary:
	var city_state = values.get("city_state")
	var before_citizen: Dictionary = values.get("before_citizen", {})
	var after_citizen: Dictionary = values.get("after_citizen", {})
	var before_tile: Vector2i = values.get(
		"before_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var after_tile: Vector2i = values.get(
		"after_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
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
			city_state,
			before_citizen,
			before_tile
		),
		"after": _make_city_citizen_movement_visual_snapshot(
			city_state,
			after_citizen,
			after_tile
		),
		"traversed_tiles": (
			_get_clean_city_citizen_movement_visual_trace(
				city_state,
				before_tile,
				after_tile,
				raw_traversed_tiles
			)
		)
	}

static func _make_city_citizen_movement_visual_snapshot(
	city_state,
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
	var visual_step_target_tile := CityCitizens.INVALID_CITY_TILE_POSITION

	if (
		movement_state == CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_MOVING
		and raw_path is Array
		and movement_path_index >= 1
		and movement_path_index < raw_path.size()
		and raw_path[movement_path_index - 1] is Vector2i
		and raw_path[movement_path_index] is Vector2i
	):
		var from_tile: Vector2i = raw_path[movement_path_index - 1]
		var to_tile: Vector2i = raw_path[movement_path_index]
		var step_cost := (
			CityNavigationSystem.get_city_citizen_movement_step_cost(
				from_tile,
				to_tile
			)
			if city_state == null
			else CityNavigationSystem.get_city_citizen_movement_step_cost_for_city_state(
				city_state,
				from_tile,
				to_tile
			)
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
			CityCitizens.DEFAULT_CITIZEN_MOVEMENT_SPEED_PER_MINUTE
		))
	}

static func _get_clean_city_citizen_movement_visual_trace(
	city_state,
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

			var step_cost := (
				CityNavigationSystem.get_city_citizen_movement_step_cost(
					clean_tiles.back(),
					tile
				)
				if city_state == null
				else CityNavigationSystem.get_city_citizen_movement_step_cost_for_city_state(
					city_state,
					clean_tiles.back(),
					tile
				)
			)
			if step_cost <= 0:
				break

			clean_tiles.append(tile)

	var final_step_cost := (
		CityNavigationSystem.get_city_citizen_movement_step_cost(
			clean_tiles.back(),
			after_tile
		)
		if city_state == null
		else CityNavigationSystem.get_city_citizen_movement_step_cost_for_city_state(
			city_state,
			clean_tiles.back(),
			after_tile
		)
	)
	if clean_tiles.back() != after_tile and final_step_cost > 0:
		clean_tiles.append(after_tile)

	return clean_tiles
