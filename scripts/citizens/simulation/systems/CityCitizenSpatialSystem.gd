extends RefCounted
class_name CityCitizenSpatialSystem

# Derived citizen occupancy behavior for the active settlement. Citizen records
# remain authoritative for positions; this system maintains the spatial index
# and its version atomically.

static func get_current_state() -> CityCitizenSpatialState:
	return WorldPoliticalState.get_current_city_citizen_spatial_state()


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
	return city_citizen_spatial_version


static func reset_city_citizen_spatial_state() -> void:
	city_citizen_ids_by_tile.clear()
	mark_city_citizen_spatial_changed()


static func mark_city_citizen_spatial_changed() -> void:
	city_citizen_spatial_version += 1

static func add_city_citizen_to_spatial_index(
	citizen_id: int,
	tile_position: Vector2i
) -> bool:
	if citizen_id <= 0:
		return false

	if tile_position == WorldData.INVALID_CITY_TILE_POSITION:
		return false

	var citizen_ids: Array = []
	var raw_citizen_ids = city_citizen_ids_by_tile.get(
		tile_position,
		[]
	)

	if raw_citizen_ids is Array:
		citizen_ids = raw_citizen_ids

	if citizen_ids.has(citizen_id):
		return false

	citizen_ids.insert(
		citizen_ids.bsearch(citizen_id),
		citizen_id
	)

	city_citizen_ids_by_tile[tile_position] = (
		citizen_ids
	)
	return true

static func remove_city_citizen_from_spatial_index(
	citizen_id: int,
	tile_position: Vector2i
) -> bool:
	if not city_citizen_ids_by_tile.has(
		tile_position
	):
		return false

	var raw_citizen_ids = city_citizen_ids_by_tile[
		tile_position
	]

	if not raw_citizen_ids is Array:
		city_citizen_ids_by_tile.erase(
			tile_position
		)
		return true

	var citizen_ids: Array = raw_citizen_ids
	var contained_citizen := false

	while citizen_ids.has(citizen_id):
		contained_citizen = true
		citizen_ids.erase(citizen_id)

	if citizen_ids.is_empty():
		city_citizen_ids_by_tile.erase(
			tile_position
		)
		return true

	if not contained_citizen:
		return false

	city_citizen_ids_by_tile[tile_position] = (
		citizen_ids
	)
	return true

static func register_city_citizen_spatial_index_entry(
	citizen: Dictionary
) -> bool:
	if citizen.is_empty():
		return false
	if not bool(citizen.get("alive", false)):
		return false

	var citizen_id := int(
		citizen.get("id", -1)
	)
	var raw_position = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not raw_position is Vector2i:
		return false

	return add_city_citizen_to_spatial_index(
		citizen_id,
		raw_position
	)

static func rebuild_city_citizen_spatial_index() -> bool:
	var previous_index := city_citizen_ids_by_tile.duplicate(true)
	city_citizen_ids_by_tile.clear()

	for raw_citizen in CityCitizenRegistrySystem.get_current_state().citizens:
		if not raw_citizen is Dictionary:
			continue

		register_city_citizen_spatial_index_entry(
			raw_citizen
		)

	if previous_index == city_citizen_ids_by_tile:
		return false

	mark_city_citizen_spatial_changed()
	return true

static func get_city_citizen_ids_at_tile(
	tile_position: Vector2i
) -> Array:
	var raw_citizen_ids = city_citizen_ids_by_tile.get(
		tile_position,
		[]
	)

	if not raw_citizen_ids is Array:
		return []

	return raw_citizen_ids.duplicate()

static func has_living_city_citizen_at_tile(
	tile_position: Vector2i
) -> bool:
	var raw_citizen_ids = city_citizen_ids_by_tile.get(
		tile_position,
		[]
	)

	if not raw_citizen_ids is Array:
		return false

	for raw_citizen_id in raw_citizen_ids:
		if typeof(raw_citizen_id) != TYPE_INT:
			continue

		var citizen_id: int = raw_citizen_id
		var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(
			citizen_id
		)

		if citizen.is_empty():
			continue

		if not bool(citizen.get("alive", false)):
			continue

		if (
			citizen.get(
				"city_tile_position",
				WorldData.INVALID_CITY_TILE_POSITION
			)
			!= tile_position
		):
			continue

		return true

	return false

static func ensure_city_citizen_spatial_state(
	city_world: WorldData
) -> int:
	if city_world == null:
		return 0

	if CityCitizenRegistrySystem.get_current_state().citizens.is_empty():
		if not city_citizen_ids_by_tile.is_empty():
			city_citizen_ids_by_tile.clear()
			mark_city_citizen_spatial_changed()
		return 0

	var citizens_missing_position := []

	for citizen_index in range(
		CityCitizenRegistrySystem.get_current_state().citizens.size()
	):
		var raw_citizen = CityCitizenRegistrySystem.get_current_state().citizens[
			citizen_index
		]

		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if not bool(citizen.get("alive", false)):
			continue

		if citizen.has("city_tile_position"):
			continue

		citizens_missing_position.append(
			citizen_index
		)

	var initialized_count := 0

	if not citizens_missing_position.is_empty():
		var spawn_tiles := (
			WorldData.get_starting_city_citizen_spawn_tiles(
				city_world
			)
		)

		if spawn_tiles.is_empty():
			rebuild_city_citizen_spatial_index()

			push_error(
				"Cannot initialize legacy citizen positions: "
				+ "the City Keep has no walkable access tiles."
			)

			return 0

		for raw_citizen_index in (
			citizens_missing_position
		):
			var citizen_index: int = (
				raw_citizen_index
			)
			var raw_citizen = CityCitizenRegistrySystem.get_current_state().citizens[
				citizen_index
			]

			if not raw_citizen is Dictionary:
				continue

			var citizen: Dictionary = raw_citizen
			var spawn_tile: Vector2i = spawn_tiles[
				citizen_index % spawn_tiles.size()
			]

			citizen["city_tile_position"] = (
				spawn_tile
			)
			CityCitizenRegistrySystem.get_current_state().citizens[citizen_index] = (
				citizen
			)
			initialized_count += 1

	var spatial_version_before_rebuild := city_citizen_spatial_version
	rebuild_city_citizen_spatial_index()

	if (
		initialized_count > 0
		and city_citizen_spatial_version == spatial_version_before_rebuild
	):
		mark_city_citizen_spatial_changed()

	return initialized_count

static func get_city_citizen_tile_position(
	citizen_id: int
) -> Vector2i:
	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(
		citizen_id
	)

	if citizen.is_empty():
		return WorldData.INVALID_CITY_TILE_POSITION

	var raw_position = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not raw_position is Vector2i:
		return WorldData.INVALID_CITY_TILE_POSITION

	return raw_position

static func set_city_citizen_tile_position(
	city_world: WorldData,
	citizen_id: int,
	tile_position: Vector2i
) -> bool:
	if not CityNavigationSystem.is_city_tile_walkable_for_citizen(
		city_world,
		tile_position,
		citizen_id
	):
		return false

	var citizen_index := (
		CityCitizenRegistrySystem.get_city_citizen_index_by_id(
			citizen_id
		)
	)

	if citizen_index < 0:
		return false

	var raw_citizen = CityCitizenRegistrySystem.get_current_state().citizens[
		citizen_index
	]

	if not raw_citizen is Dictionary:
		return false

	var citizen: Dictionary = raw_citizen
	if not bool(citizen.get("alive", false)):
		return false
	var current_position = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if current_position == tile_position:
		if add_city_citizen_to_spatial_index(citizen_id, tile_position):
			mark_city_citizen_spatial_changed()
		return true

	if current_position is Vector2i:
		remove_city_citizen_from_spatial_index(
			citizen_id,
			current_position
		)

	citizen["city_tile_position"] = tile_position
	CityCitizenRegistrySystem.get_current_state().citizens[citizen_index] = citizen

	add_city_citizen_to_spatial_index(
		citizen_id,
		tile_position
	)

	mark_city_citizen_spatial_changed()

	return true

static func get_living_city_citizen_ids_in_tiles(
	raw_tiles: Array
) -> Array[int]:
	var tile_lookup: Dictionary = {}

	for raw_tile in raw_tiles:
		if raw_tile is Vector2i:
			tile_lookup[raw_tile] = true

	var citizen_ids: Array[int] = []

	for raw_citizen in CityCitizenRegistrySystem.get_current_state().citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if not bool(citizen.get("alive", false)):
			continue

		var raw_tile = citizen.get(
			"city_tile_position",
			WorldData.INVALID_CITY_TILE_POSITION
		)

		if not raw_tile is Vector2i or not tile_lookup.has(raw_tile):
			continue

		var citizen_id := int(citizen.get("id", -1))

		if citizen_id > 0:
			citizen_ids.append(citizen_id)

	citizen_ids.sort()
	return citizen_ids
