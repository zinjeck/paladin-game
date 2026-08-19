extends RefCounted
class_name CityCitizenSpatialSystem

# Derived citizen occupancy behavior for an explicitly supplied settlement.
# Citizen records remain authoritative for positions; this system maintains the
# spatial index and its version atomically. Legacy no-target calls are confined
# to the unbound compatibility owner and never follow presentation selection.

static func get_current_state() -> CityCitizenSpatialState:
	return CityCitizenUnboundCompatibility.get_city_state().citizen_spatial_state


static var city_citizen_ids_by_tile: Dictionary:
	get:
		return get_current_state().citizen_ids_by_tile
	set(value):
		get_current_state().citizen_ids_by_tile = value


static var city_citizen_spatial_version: int:
	get:
		return get_current_state().citizen_spatial_version
	set(value):
		get_current_state().citizen_spatial_version = value


static func get_city_citizen_spatial_version() -> int:
	return get_city_citizen_spatial_version_for_city_state(
		CityCitizenUnboundCompatibility.get_city_state()
	)


static func reset_city_citizen_spatial_state() -> void:
	reset_city_citizen_spatial_state_for_city_state(
		CityCitizenUnboundCompatibility.get_city_state()
	)


static func mark_city_citizen_spatial_changed() -> void:
	mark_city_citizen_spatial_changed_for_city_state(
		CityCitizenUnboundCompatibility.get_city_state()
	)


static func add_city_citizen_to_spatial_index(
	citizen_id: int,
	tile_position: Vector2i
) -> bool:
	return add_city_citizen_to_spatial_index_for_city_state(
		CityCitizenUnboundCompatibility.get_city_state(),
		citizen_id,
		tile_position
	)


static func remove_city_citizen_from_spatial_index(
	citizen_id: int,
	tile_position: Vector2i
) -> bool:
	return remove_city_citizen_from_spatial_index_for_city_state(
		CityCitizenUnboundCompatibility.get_city_state(),
		citizen_id,
		tile_position
	)


static func register_city_citizen_spatial_index_entry(
	citizen: Dictionary
) -> bool:
	return register_city_citizen_spatial_index_entry_for_city_state(
		CityCitizenUnboundCompatibility.get_city_state(),
		citizen
	)


static func rebuild_city_citizen_spatial_index() -> bool:
	return rebuild_city_citizen_spatial_index_for_city_state(
		CityCitizenUnboundCompatibility.get_city_state()
	)


static func get_city_citizen_ids_at_tile(
	tile_position: Vector2i
) -> Array:
	return get_city_citizen_ids_at_tile_for_city_state(
		CityCitizenUnboundCompatibility.get_city_state(),
		tile_position
	)


static func has_living_city_citizen_at_tile(
	tile_position: Vector2i
) -> bool:
	return has_living_city_citizen_at_tile_for_city_state(
		CityCitizenUnboundCompatibility.get_city_state(),
		tile_position
	)


static func ensure_city_citizen_spatial_state(
	city_world: WorldData
) -> int:
	return ensure_city_citizen_spatial_state_for_city_state(
		CityCitizenUnboundCompatibility.get_city_state(),
		city_world
	)


static func get_city_citizen_tile_position(
	citizen_id: int
) -> Vector2i:
	return get_city_citizen_tile_position_for_city_state(
		CityCitizenUnboundCompatibility.get_city_state(),
		citizen_id
	)


static func set_city_citizen_tile_position(
	city_world: WorldData,
	citizen_id: int,
	tile_position: Vector2i
) -> bool:
	return set_city_citizen_tile_position_for_city_state(
		CityCitizenUnboundCompatibility.get_city_state(),
		city_world,
		citizen_id,
		tile_position
	)


static func get_living_city_citizen_ids_in_tiles(
	raw_tiles: Array
) -> Array[int]:
	return get_living_city_citizen_ids_in_tiles_for_city_state(
		CityCitizenUnboundCompatibility.get_city_state(),
		raw_tiles
	)


static func get_starting_city_citizen_spawn_tiles(
	city_world: WorldData
) -> Array:
	return get_starting_city_citizen_spawn_tiles_for_city_state(
		CityCitizenUnboundCompatibility.get_city_state(),
		city_world
	)


# Explicit settlement-state API used by the simulation pipeline. These variants
# operate only on the supplied owner and never consult presentation selection.
static func get_city_citizen_spatial_version_for_city_state(
	city_state: CitySettlementSimulationState
) -> int:
	return city_state.citizen_spatial_state.citizen_spatial_version


static func reset_city_citizen_spatial_state_for_city_state(
	city_state: CitySettlementSimulationState
) -> void:
	city_state.citizen_spatial_state.citizen_ids_by_tile.clear()
	mark_city_citizen_spatial_changed_for_city_state(city_state)


static func mark_city_citizen_spatial_changed_for_city_state(
	city_state: CitySettlementSimulationState
) -> void:
	city_state.citizen_spatial_state.citizen_spatial_version += 1


static func add_city_citizen_to_spatial_index_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	tile_position: Vector2i
) -> bool:
	if citizen_id <= 0:
		return false
	if tile_position == CityCitizens.INVALID_CITY_TILE_POSITION:
		return false

	var spatial_state := city_state.citizen_spatial_state
	var citizen_ids: Array = []
	var raw_citizen_ids = spatial_state.citizen_ids_by_tile.get(
		tile_position,
		[]
	)
	if raw_citizen_ids is Array:
		citizen_ids = raw_citizen_ids
	if citizen_ids.has(citizen_id):
		return false

	citizen_ids.insert(citizen_ids.bsearch(citizen_id), citizen_id)
	spatial_state.citizen_ids_by_tile[tile_position] = citizen_ids
	return true


static func remove_city_citizen_from_spatial_index_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	tile_position: Vector2i
) -> bool:
	var spatial_state := city_state.citizen_spatial_state
	if not spatial_state.citizen_ids_by_tile.has(tile_position):
		return false

	var raw_citizen_ids = spatial_state.citizen_ids_by_tile[tile_position]
	if not raw_citizen_ids is Array:
		spatial_state.citizen_ids_by_tile.erase(tile_position)
		return true

	var citizen_ids: Array = raw_citizen_ids
	var contained_citizen := false
	while citizen_ids.has(citizen_id):
		contained_citizen = true
		citizen_ids.erase(citizen_id)

	if citizen_ids.is_empty():
		spatial_state.citizen_ids_by_tile.erase(tile_position)
		return true
	if not contained_citizen:
		return false

	spatial_state.citizen_ids_by_tile[tile_position] = citizen_ids
	return true


static func register_city_citizen_spatial_index_entry_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen: Dictionary
) -> bool:
	if citizen.is_empty() or not bool(citizen.get("alive", false)):
		return false

	var raw_position = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	if not raw_position is Vector2i:
		return false

	return add_city_citizen_to_spatial_index_for_city_state(
		city_state,
		int(citizen.get("id", -1)),
		raw_position
	)


static func rebuild_city_citizen_spatial_index_for_city_state(
	city_state: CitySettlementSimulationState
) -> bool:
	var spatial_state := city_state.citizen_spatial_state
	var previous_index := spatial_state.citizen_ids_by_tile.duplicate(true)
	spatial_state.citizen_ids_by_tile.clear()

	for raw_citizen in city_state.citizen_registry_state.citizens:
		if raw_citizen is Dictionary:
			register_city_citizen_spatial_index_entry_for_city_state(
				city_state,
				raw_citizen
			)

	if previous_index == spatial_state.citizen_ids_by_tile:
		return false
	mark_city_citizen_spatial_changed_for_city_state(city_state)
	return true


static func get_city_citizen_ids_at_tile_for_city_state(
	city_state: CitySettlementSimulationState,
	tile_position: Vector2i
) -> Array:
	var raw_citizen_ids = (
		city_state.citizen_spatial_state.citizen_ids_by_tile.get(
			tile_position,
			[]
		)
	)
	if not raw_citizen_ids is Array:
		return []
	return raw_citizen_ids.duplicate()


static func has_living_city_citizen_at_tile_for_city_state(
	city_state: CitySettlementSimulationState,
	tile_position: Vector2i
) -> bool:
	var raw_citizen_ids = (
		city_state.citizen_spatial_state.citizen_ids_by_tile.get(
			tile_position,
			[]
		)
	)
	if not raw_citizen_ids is Array:
		return false

	var registry_state := city_state.citizen_registry_state
	for raw_citizen_id in raw_citizen_ids:
		if typeof(raw_citizen_id) != TYPE_INT:
			continue
		var citizen_id: int = raw_citizen_id
		if not registry_state.citizen_index_by_id.has(citizen_id):
			continue
		var citizen_index := int(
			registry_state.citizen_index_by_id[citizen_id]
		)
		if citizen_index < 0 or citizen_index >= registry_state.citizens.size():
			continue
		var raw_citizen = registry_state.citizens[citizen_index]
		if not raw_citizen is Dictionary:
			continue
		var citizen: Dictionary = raw_citizen
		if (
			bool(citizen.get("alive", false))
			and citizen.get(
				"city_tile_position",
				CityCitizens.INVALID_CITY_TILE_POSITION
			) == tile_position
		):
			return true
	return false


static func ensure_city_citizen_spatial_state_for_city_state(
	city_state: CitySettlementSimulationState,
	city_world: WorldData
) -> int:
	if city_world == null:
		return 0

	var registry_state := city_state.citizen_registry_state
	var spatial_state := city_state.citizen_spatial_state
	if registry_state.citizens.is_empty():
		if not spatial_state.citizen_ids_by_tile.is_empty():
			spatial_state.citizen_ids_by_tile.clear()
			mark_city_citizen_spatial_changed_for_city_state(city_state)
		return 0

	var citizens_missing_position: Array = []
	for citizen_index in range(registry_state.citizens.size()):
		var raw_citizen = registry_state.citizens[citizen_index]
		if (
			raw_citizen is Dictionary
			and bool(raw_citizen.get("alive", false))
			and not raw_citizen.has("city_tile_position")
		):
			citizens_missing_position.append(citizen_index)

	var initialized_count := 0
	if not citizens_missing_position.is_empty():
		var spawn_tiles := get_starting_city_citizen_spawn_tiles_for_city_state(
			city_state,
			city_world
		)
		if spawn_tiles.is_empty():
			rebuild_city_citizen_spatial_index_for_city_state(city_state)
			push_error(
				"Cannot initialize legacy citizen positions: "
				+ "the City Keep has no walkable access tiles."
			)
			return 0

		for raw_citizen_index in citizens_missing_position:
			var citizen_index: int = raw_citizen_index
			var raw_citizen = registry_state.citizens[citizen_index]
			if not raw_citizen is Dictionary:
				continue
			var citizen: Dictionary = raw_citizen
			citizen["city_tile_position"] = spawn_tiles[
				citizen_index % spawn_tiles.size()
			]
			registry_state.citizens[citizen_index] = citizen
			initialized_count += 1

	var version_before := spatial_state.citizen_spatial_version
	rebuild_city_citizen_spatial_index_for_city_state(city_state)
	if (
		initialized_count > 0
		and spatial_state.citizen_spatial_version == version_before
	):
		mark_city_citizen_spatial_changed_for_city_state(city_state)
	return initialized_count


static func get_city_citizen_tile_position_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> Vector2i:
	var registry_state := city_state.citizen_registry_state
	if not registry_state.citizen_index_by_id.has(citizen_id):
		return CityCitizens.INVALID_CITY_TILE_POSITION
	var citizen_index := int(registry_state.citizen_index_by_id[citizen_id])
	if citizen_index < 0 or citizen_index >= registry_state.citizens.size():
		return CityCitizens.INVALID_CITY_TILE_POSITION
	var raw_citizen = registry_state.citizens[citizen_index]
	if not raw_citizen is Dictionary:
		return CityCitizens.INVALID_CITY_TILE_POSITION
	var raw_position = raw_citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	if not raw_position is Vector2i:
		return CityCitizens.INVALID_CITY_TILE_POSITION
	return raw_position


static func set_city_citizen_tile_position_for_city_state(
	city_state: CitySettlementSimulationState,
	city_world: WorldData,
	citizen_id: int,
	tile_position: Vector2i
) -> bool:
	if not CityNavigationSystem.is_city_tile_walkable_for_citizen_for_city_state(
		city_state,
		city_world,
		tile_position,
		citizen_id
	):
		return false

	var registry_state := city_state.citizen_registry_state
	if not registry_state.citizen_index_by_id.has(citizen_id):
		return false
	var citizen_index := int(registry_state.citizen_index_by_id[citizen_id])
	if citizen_index < 0 or citizen_index >= registry_state.citizens.size():
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
	if current_position == tile_position:
		if add_city_citizen_to_spatial_index_for_city_state(
			city_state,
			citizen_id,
			tile_position
		):
			mark_city_citizen_spatial_changed_for_city_state(city_state)
		return true
	if current_position is Vector2i:
		remove_city_citizen_from_spatial_index_for_city_state(
			city_state,
			citizen_id,
			current_position
		)

	citizen["city_tile_position"] = tile_position
	registry_state.citizens[citizen_index] = citizen
	add_city_citizen_to_spatial_index_for_city_state(
		city_state,
		citizen_id,
		tile_position
	)
	mark_city_citizen_spatial_changed_for_city_state(city_state)
	return true


static func get_living_city_citizen_ids_in_tiles_for_city_state(
	city_state: CitySettlementSimulationState,
	raw_tiles: Array
) -> Array[int]:
	var tile_lookup: Dictionary = {}
	for raw_tile in raw_tiles:
		if raw_tile is Vector2i:
			tile_lookup[raw_tile] = true

	var citizen_ids: Array[int] = []
	for raw_citizen in city_state.citizen_registry_state.citizens:
		if not raw_citizen is Dictionary:
			continue
		var citizen: Dictionary = raw_citizen
		var raw_tile = citizen.get(
			"city_tile_position",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)
		if (
			not bool(citizen.get("alive", false))
			or not raw_tile is Vector2i
			or not tile_lookup.has(raw_tile)
		):
			continue
		var citizen_id := int(citizen.get("id", -1))
		if citizen_id > 0:
			citizen_ids.append(citizen_id)
	citizen_ids.sort()
	return citizen_ids


static func get_starting_city_citizen_spawn_tiles_for_city_state(
	city_state: CitySettlementSimulationState,
	city_world: WorldData
) -> Array:
	for raw_city_object in city_state.object_state.objects:
		if not raw_city_object is Dictionary:
			continue
		var city_object: Dictionary = raw_city_object
		if (
			str(city_object.get("type", ""))
			!= CityObjectCatalog.CITY_OBJECT_CITY_CENTER
		):
			continue
		return CityNavigationSystem.get_city_object_access_tiles_for_city_state(
			city_state,
			city_world,
			city_object
		)
	return []


#endregion

#region Simulation Tick and Session Reset
