extends RefCounted
class_name CityObjectSystem

const CITY_TOPOLOGY_MUTATION_FAILURE_NONE := "none"
const CITY_TOPOLOGY_MUTATION_FAILURE_INVALID_REQUEST := "invalid_request"
const CITY_TOPOLOGY_MUTATION_FAILURE_TILE_BLOCKED := "tile_blocked"
const CITY_TOPOLOGY_MUTATION_FAILURE_FOOTPRINT_OCCUPIED := "footprint_occupied"

# File responsibility: Authoritative completed-city-object behavior/API for
# one active CITY settlement. CityObjectState remains the data-only owner of
# the registry, ID index, footprint occupancy, next local ID, and version.


static func get_current_state() -> CityObjectState:
	return WorldPoliticalState.get_current_city_object_state()


static func _state() -> CityObjectState:
	return get_current_state()


static func get_city_objects() -> Array:
	# Some still-unextracted systems mutate object records in place. Preserve
	# that established authoritative-reference behavior until those domains are
	# migrated; callers needing isolation must use the snapshot APIs below.
	return _state().objects


static func get_city_object_snapshot() -> Array:
	return _state().objects.duplicate(true)


static func get_city_object_by_id(object_id: int) -> Dictionary:
	var object_index := get_city_object_index_by_id(object_id)

	if object_index < 0:
		return {}

	var raw_city_object = _state().objects[object_index]

	if not raw_city_object is Dictionary:
		return {}

	return raw_city_object


static func get_city_object_by_id_snapshot(object_id: int) -> Dictionary:
	var city_object := get_city_object_by_id(object_id)

	if city_object.is_empty():
		return {}

	return city_object.duplicate(true)


static func write_city_object_at_index(
	object_index: int,
	city_object: Dictionary
) -> bool:
	var state := _state()

	if (
		city_object.is_empty()
		or object_index < 0
		or object_index >= state.objects.size()
	):
		return false

	var raw_existing = state.objects[object_index]

	if not raw_existing is Dictionary:
		return false

	var object_id := int(city_object.get("id", -1))

	if (
		object_id <= 0
		or int(raw_existing.get("id", -1)) != object_id
		or int(state.object_index_by_id.get(object_id, -1)) != object_index
	):
		return false

	# This API updates embedded storage/production/assignment metadata without
	# representing a topology mutation. The owning domain must bump its own
	# focused version; object_version deliberately remains unchanged.
	state.objects[object_index] = city_object
	return true


static func get_city_object_index_snapshot() -> Dictionary:
	return _state().object_index_by_id.duplicate()


static func get_city_occupied_tiles_snapshot() -> Dictionary:
	return _state().occupied_tiles.duplicate()


static func get_next_city_object_id() -> int:
	return _state().next_object_id


static func get_city_object_version() -> int:
	return _state().object_version


static func mark_city_objects_changed() -> void:
	_state().object_version += 1


static func rebuild_city_object_index() -> void:
	var state := _state()
	state.object_index_by_id.clear()

	for object_index in range(state.objects.size()):
		var raw_city_object = state.objects[object_index]

		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object
		var object_id := int(city_object.get("id", -1))

		if object_id <= 0:
			continue

		if state.object_index_by_id.has(object_id):
			push_error(
				"Duplicate city object ID while rebuilding index: "
				+ str(object_id)
			)
			continue

		state.object_index_by_id[object_id] = object_index


static func rebuild_city_object_occupancy() -> void:
	var state := _state()
	var previous_occupancy := state.occupied_tiles.duplicate()
	state.occupied_tiles.clear()

	for raw_city_object in state.objects:
		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object
		var object_id := int(city_object.get("id", -1))

		if object_id <= 0:
			continue

		for raw_tile in get_city_object_footprint_tiles(city_object):
			if not raw_tile is Vector2i:
				continue

			var tile_position: Vector2i = raw_tile
			var occupying_id := int(state.occupied_tiles.get(tile_position, -1))

			if occupying_id > 0 and occupying_id != object_id:
				push_error(
					"Conflicting city-object occupancy at "
					+ str(tile_position)
					+ " for object IDs "
					+ str(occupying_id)
					+ " and "
					+ str(object_id)
				)
				continue

			state.occupied_tiles[tile_position] = object_id

	if state.occupied_tiles != previous_occupancy:
		mark_city_objects_changed()


static func rebuild_city_object_registry_indexes() -> void:
	rebuild_city_object_index()
	rebuild_city_object_occupancy()


static func _register_city_object_index(
	city_object: Dictionary,
	object_index: int
) -> bool:
	if city_object.is_empty():
		return false

	var state := _state()

	if object_index < 0 or object_index >= state.objects.size():
		push_error(
			"Cannot register city object index outside the object array: "
			+ str(object_index)
		)
		return false

	var object_id := int(city_object.get("id", -1))

	if object_id <= 0:
		push_error("Cannot register city object without a valid ID.")
		return false

	if state.object_index_by_id.has(object_id):
		var existing_index := int(state.object_index_by_id[object_id])

		if existing_index != object_index:
			push_error(
				"Duplicate city object ID detected: "
				+ str(object_id)
			)
			return false

	state.object_index_by_id[object_id] = object_index
	return true


static func _get_valid_indexed_city_object_index(object_id: int) -> int:
	var state := _state()

	if not state.object_index_by_id.has(object_id):
		return -1

	var object_index := int(state.object_index_by_id[object_id])

	if object_index < 0 or object_index >= state.objects.size():
		return -1

	var raw_city_object = state.objects[object_index]

	if not raw_city_object is Dictionary:
		return -1

	if int(raw_city_object.get("id", -1)) != object_id:
		return -1

	return object_index


static func _find_authoritative_city_object_index(object_id: int) -> int:
	var state := _state()

	for object_index in range(state.objects.size()):
		var raw_city_object = state.objects[object_index]

		if (
			raw_city_object is Dictionary
			and int(raw_city_object.get("id", -1)) == object_id
		):
			return object_index

	return -1


static func get_city_object_index_by_id(object_id: int) -> int:
	if object_id <= 0:
		return -1

	var object_index := _get_valid_indexed_city_object_index(object_id)

	if object_index >= 0:
		return object_index

	# The object array is authoritative. Scan a failed lookup before deciding
	# whether repair is needed: healthy misses stay read-only, while missing keys
	# and full-size wrong-key indexes are rebuilt from the source records.
	var authoritative_index := _find_authoritative_city_object_index(object_id)

	if authoritative_index < 0:
		if _state().object_index_by_id.has(object_id):
			rebuild_city_object_index()

		return -1

	rebuild_city_object_index()
	return _get_valid_indexed_city_object_index(object_id)


static func get_city_object_id_at_tile(tile_position: Vector2i) -> int:
	var object_id := int(_state().occupied_tiles.get(tile_position, -1))

	if object_id <= 0:
		return -1

	return object_id


static func has_city_object_at_tile(tile_position: Vector2i) -> bool:
	return get_city_object_id_at_tile(tile_position) > 0


static func get_city_object_at_tile(tile_position: Vector2i) -> Dictionary:
	var object_id := get_city_object_id_at_tile(tile_position)

	if object_id <= 0:
		return {}

	return get_city_object_by_id(object_id)


static func has_city_object_type(object_type: String) -> bool:
	for raw_city_object in _state().objects:
		if not raw_city_object is Dictionary:
			continue

		if str(raw_city_object.get("type", "")) == object_type:
			return true

	return false


static func make_rectangle_city_object_footprint_tiles(
	top_left: Vector2i,
	size_tiles: Vector2i
) -> Array:
	var footprint_tiles := []

	if size_tiles.x <= 0 or size_tiles.y <= 0:
		return footprint_tiles

	for y in range(top_left.y, top_left.y + size_tiles.y):
		for x in range(top_left.x, top_left.x + size_tiles.x):
			footprint_tiles.append(Vector2i(x, y))

	return footprint_tiles


static func get_city_object_footprint_tiles(city_object: Dictionary) -> Array:
	var footprint_tiles := []

	if city_object.is_empty():
		return footprint_tiles

	if city_object.has("footprint_tiles"):
		var raw_footprint_tiles = city_object.get("footprint_tiles", [])

		if raw_footprint_tiles is Array:
			for tile_position in raw_footprint_tiles:
				if tile_position is Vector2i:
					footprint_tiles.append(tile_position)

			return footprint_tiles

	if city_object.has("tiles"):
		var raw_tiles = city_object.get("tiles", [])

		if raw_tiles is Array:
			for tile_position in raw_tiles:
				if tile_position is Vector2i:
					footprint_tiles.append(tile_position)

			return footprint_tiles

	if city_object.has("top_left") and city_object.has("size"):
		var top_left: Vector2i = city_object.get(
			"top_left",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)
		var size_tiles: Vector2i = city_object.get("size", Vector2i.ZERO)
		return make_rectangle_city_object_footprint_tiles(top_left, size_tiles)

	return footprint_tiles


static func occupy_city_object_tiles(city_object: Dictionary) -> bool:
	var object_id := int(city_object.get("id", -1))

	if object_id <= 0:
		return false

	var footprint_tiles := get_city_object_footprint_tiles(city_object)

	if footprint_tiles.is_empty():
		return false

	for raw_tile in footprint_tiles:
		if not raw_tile is Vector2i:
			return false

		var occupying_id := int(_state().occupied_tiles.get(raw_tile, -1))

		if occupying_id > 0 and occupying_id != object_id:
			return false

	for tile_position in footprint_tiles:
		_state().occupied_tiles[tile_position] = object_id

	return true


static func release_city_object_tiles(city_object: Dictionary) -> void:
	var object_id := int(city_object.get("id", -1))

	if object_id <= 0:
		return

	for raw_tile in get_city_object_footprint_tiles(city_object):
		if not raw_tile is Vector2i:
			continue

		if int(_state().occupied_tiles.get(raw_tile, -1)) == object_id:
			_state().occupied_tiles.erase(raw_tile)


static func city_object_type_preserves_citizen_walkability(
	object_type: String
) -> bool:
	return object_type == CityObjectCatalog.CITY_OBJECT_ROAD


static func get_city_object_topology_blocking_citizen_ids(
	object_type: String,
	footprint_tiles: Array
) -> Array[int]:
	if city_object_type_preserves_citizen_walkability(object_type):
		return []

	return CityCitizenSpatialSystem.get_living_city_citizen_ids_in_tiles(footprint_tiles)


static func validate_city_object_topology_mutation(
	values: Dictionary
) -> Dictionary:
	var result := {
		"success": false,
		"failure_reason": CityObjectSystem.CITY_TOPOLOGY_MUTATION_FAILURE_INVALID_REQUEST,
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
		or CityObjectCatalog.get_city_object_definition(object_type).is_empty()
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
			str(tile.get("terrain", WorldData.TERRAIN_WATER)) in [
				WorldData.TERRAIN_WATER,
				WorldData.TERRAIN_MOUNTAIN,
			]
			or not bool(tile.get("is_land", false))
		):
			return result

		var occupied_object_id := get_city_object_id_at_tile(tile_position)

		if (
			occupied_object_id > 0
			and occupied_object_id != allowed_occupied_object_id
		):
			result["failure_reason"] = (
				CityObjectSystem.CITY_TOPOLOGY_MUTATION_FAILURE_TILE_BLOCKED
			)
			return result

		var construction_site_id := int(
			CityConstructionSystem.get_current_state().construction_site_id_by_tile.get(
				tile_position,
				-1
			)
		)

		if (
			construction_site_id > 0
			and construction_site_id != allowed_construction_site_id
		):
			result["failure_reason"] = (
				CityObjectSystem.CITY_TOPOLOGY_MUTATION_FAILURE_TILE_BLOCKED
			)
			return result

		if CityLogisticsSystem.has_city_ground_pile_at_tile(tile_position):
			result["failure_reason"] = (
				CityObjectSystem.CITY_TOPOLOGY_MUTATION_FAILURE_TILE_BLOCKED
			)
			return result

		footprint_lookup[tile_position] = true
		footprint_tiles.append(tile_position)

	var blocking_citizen_ids := get_city_object_topology_blocking_citizen_ids(
		object_type,
		footprint_tiles
	)

	if not blocking_citizen_ids.is_empty():
		result["failure_reason"] = (
			CityObjectSystem.CITY_TOPOLOGY_MUTATION_FAILURE_FOOTPRINT_OCCUPIED
		)
		result["blocking_citizen_ids"] = blocking_citizen_ids
		return result

	result["success"] = true
	result["failure_reason"] = CityObjectSystem.CITY_TOPOLOGY_MUTATION_FAILURE_NONE
	result["footprint_tiles"] = footprint_tiles
	return result


static func can_place_city_object(
	city_world: WorldData,
	top_left: Vector2i,
	size_tiles: Vector2i,
	object_type: String = ""
) -> bool:
	if city_world == null:
		return false

	if size_tiles.x <= 0 or size_tiles.y <= 0:
		return false

	if top_left.x < 0 or top_left.y < 0:
		return false

	if (
		top_left.x + size_tiles.x > city_world.width
		or top_left.y + size_tiles.y > city_world.height
	):
		return false

	for y in range(top_left.y, top_left.y + size_tiles.y):
		for x in range(top_left.x, top_left.x + size_tiles.x):
			var tile_position := Vector2i(x, y)

			if has_city_object_at_tile(tile_position):
				return false

			if CityConstructionSystem.get_current_state().construction_site_id_by_tile.has(
				tile_position
			):
				return false

			if CityLogisticsSystem.has_city_ground_pile_at_tile(tile_position):
				return false

			if CityCitizenSpatialSystem.has_living_city_citizen_at_tile(tile_position):
				return false

			var tile: Dictionary = city_world.get_tile(x, y)

			if str(tile.get("terrain", "")) in [
				WorldData.TERRAIN_WATER,
				WorldData.TERRAIN_MOUNTAIN,
			]:
				return false

	if (
		object_type == CityObjectCatalog.CITY_OBJECT_CITY_CENTER
		and not city_object_placement_has_walkable_access_tile(
			city_world,
			top_left,
			size_tiles
		)
	):
		return false

	return true


static func city_object_placement_has_walkable_access_tile(
	city_world: WorldData,
	top_left: Vector2i,
	size_tiles: Vector2i
) -> bool:
	if city_world == null:
		return false

	var footprint_lookup: Dictionary = {}

	for y in range(top_left.y, top_left.y + size_tiles.y):
		for x in range(top_left.x, top_left.x + size_tiles.x):
			footprint_lookup[Vector2i(x, y)] = true

	for raw_footprint_tile in footprint_lookup:
		if not raw_footprint_tile is Vector2i:
			continue

		var footprint_tile: Vector2i = raw_footprint_tile

		for offset in CityNavigationSystem.CITY_CARDINAL_TILE_OFFSETS:
			var candidate_tile: Vector2i = footprint_tile + Vector2i(offset)

			if footprint_lookup.has(candidate_tile):
				continue

			if CityNavigationSystem.is_city_tile_walkable_for_citizen(
				city_world,
				candidate_tile
			):
				return true

	return false


static func city_object_supports_citizen_interior(
	city_object: Dictionary
) -> bool:
	var definition := CityObjectCatalog.get_city_object_definition_from_object(city_object)

	if definition.is_empty():
		return false

	return bool(definition.get("supports_citizen_interior", false))


static func get_city_object_citizen_interior_access_mode(
	city_object: Dictionary
) -> String:
	var definition := CityObjectCatalog.get_city_object_definition_from_object(city_object)

	if definition.is_empty():
		return CityObjectCatalog.CITY_OBJECT_INTERIOR_ACCESS_NONE

	return str(
		definition.get(
			"citizen_interior_access_mode",
			CityObjectCatalog.CITY_OBJECT_INTERIOR_ACCESS_NONE
		)
	)


static func get_city_object_citizen_entry_policy(
	city_object: Dictionary
) -> Dictionary:
	return WorldData._get_city_object_definition_dictionary(
		city_object,
		"citizen_entry_policy"
	)


static func get_city_object_citizen_entry_tiles(
	city_object: Dictionary
) -> Array[Vector2i]:
	var entry_tiles: Array[Vector2i] = []
	var raw_entry_tiles = city_object.get("citizen_entry_tiles", [])

	if not raw_entry_tiles is Array:
		return entry_tiles

	for raw_entry_tile in raw_entry_tiles:
		if raw_entry_tile is Vector2i:
			entry_tiles.append(raw_entry_tile)

	entry_tiles.sort_custom(_sort_city_tiles_y_then_x)
	return entry_tiles


static func city_object_boundary_tile_allows_entry(
	city_object: Dictionary,
	boundary_tile: Vector2i
) -> bool:
	if not city_object_supports_citizen_interior(city_object):
		return true

	var entry_policy := get_city_object_citizen_entry_policy(city_object)
	var entry_mode := str(
		entry_policy.get(
			"mode",
			CityObjectCatalog.CITY_OBJECT_ENTRY_MODE_ANY_BOUNDARY
		)
	)

	match entry_mode:
		CityObjectCatalog.CITY_OBJECT_ENTRY_MODE_ANY_BOUNDARY:
			return get_city_object_footprint_tiles(city_object).has(boundary_tile)

		CityObjectCatalog.CITY_OBJECT_ENTRY_MODE_EXPLICIT_TILES:
			return get_city_object_citizen_entry_tiles(city_object).has(boundary_tile)

	return false


static func is_completed_city_road_tile(tile_position: Vector2i) -> bool:
	var city_object := get_city_object_at_tile(tile_position)

	return (
		not city_object.is_empty()
		and str(city_object.get("type", "")) == CityObjectCatalog.CITY_OBJECT_ROAD
	)


static func register_completed_city_object(values: Dictionary) -> Dictionary:
	var object_type := str(values.get("object_type", ""))
	var definition := CityObjectCatalog.get_city_object_definition(object_type)

	if definition.is_empty():
		return {}

	var shape_mode := str(
		definition.get(
			"shape_mode",
			CityObjectCatalog.CITY_OBJECT_SHAPE_RECTANGLE
		)
	)

	if shape_mode == CityObjectCatalog.CITY_OBJECT_SHAPE_TILE_AREA:
		return _register_completed_road(values)

	return _register_completed_rectangle(values, definition, shape_mode)


static func add_city_object(values: Dictionary) -> Dictionary:
	return register_completed_city_object(values)


static func add_city_road_object(
	tile_positions: Array,
	object_owner: String = "player",
	city_world: WorldData = null,
	allowed_construction_site_id: int = -1
) -> Dictionary:
	return register_completed_city_object({
		"object_type": CityObjectCatalog.CITY_OBJECT_ROAD,
		"footprint_tiles": tile_positions,
		"object_owner": object_owner,
		"city_world": city_world,
		"allowed_construction_site_id": allowed_construction_site_id,
	})


static func _register_completed_rectangle(
	values: Dictionary,
	definition: Dictionary,
	shape_mode: String
) -> Dictionary:
	var object_type := str(values.get("object_type", ""))
	var top_left: Vector2i = values.get(
		"top_left",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var size_tiles: Vector2i = values.get("size_tiles", Vector2i.ZERO)
	var object_owner := str(values.get("object_owner", "player"))
	var city_world: WorldData = values.get("city_world")
	var footprint_tiles := make_rectangle_city_object_footprint_tiles(
		top_left,
		size_tiles
	)
	var topology_validation := validate_city_object_topology_mutation({
		"city_world": city_world,
		"object_type": object_type,
		"footprint_tiles": footprint_tiles,
		"allowed_construction_site_id": int(
			values.get("allowed_construction_site_id", -1)
		),
		"allowed_occupied_object_id": int(
			values.get("allowed_occupied_object_id", -1)
		),
	})

	if not bool(topology_validation.get("success", false)):
		push_warning(
			"Rejected city-object topology mutation for "
			+ object_type
			+ ". Reason: "
			+ str(topology_validation.get("failure_reason", ""))
			+ ". Blocking citizens: "
			+ str(topology_validation.get("blocking_citizen_ids", []))
		)
		return {}

	var city_object := {
		"type": object_type,
		"top_left": top_left,
		"size": size_tiles,
		"owner": object_owner,
		"shape_mode": shape_mode,
		"footprint_tiles": footprint_tiles,
	}
	var resident_capacity := int(definition.get("resident_capacity", 0))

	if resident_capacity > 0:
		city_object["resident_capacity"] = resident_capacity
		city_object["resident_ids"] = []

	if bool(definition.get("is_workplace", false)):
		city_object["is_workplace"] = true
		city_object["workplace_kind"] = str(
			definition.get("workplace_kind", CityObjectCatalog.WORKPLACE_KIND_NONE)
		)
		city_object["worker_capacity"] = int(
			definition.get("worker_capacity", 0)
		)
		city_object["assigned_worker_ids"] = []
		city_object["output_resource"] = str(
			definition.get("output_resource", WorldData.RESOURCE_NONE)
		)

		var production_recipe = definition.get("production_recipe", {})

		if production_recipe is Dictionary and not production_recipe.is_empty():
			city_object["production_progress_work_units"] = 0
			city_object["production_status"] = (
				CityObjectCatalog.WORKPLACE_PRODUCTION_STATUS_IDLE_NO_WORKERS
			)
			city_object["productive_worker_count"] = 0
			city_object["site_productivity_basis_points"] = (
				CityObjectCatalog.DEFAULT_WORKPLACE_SITE_PRODUCTIVITY_BASIS_POINTS
			)

	var raw_allowed_storage_resources = definition.get("storage_resources", [])
	var has_resource_storage: bool = (
		raw_allowed_storage_resources is Array
		and not raw_allowed_storage_resources.is_empty()
	)

	if has_resource_storage:
		city_object["stored_resources"] = (
			CityResourceContainerSystem.make_empty_city_object_storage_for_type(object_type)
		)

	if not _can_append_completed_city_object(city_object):
		return {}

	var feature_world := city_world

	if feature_world == null:
		feature_world = WorldPoliticalState.get_current_city_world()

	WorldData.clear_city_surface_features_at_tiles(feature_world, footprint_tiles)

	if not _append_completed_city_object(city_object, true):
		return {}

	if object_type == CityObjectCatalog.CITY_OBJECT_HOUSE:
		CityAssignmentSystem.assign_homeless_citizens_to_available_housing()

	return city_object


static func _register_completed_road(values: Dictionary) -> Dictionary:
	var raw_tiles = values.get("footprint_tiles", [])

	if not raw_tiles is Array:
		return {}

	var clean_tiles: Array = []

	for raw_tile in raw_tiles:
		if not raw_tile is Vector2i:
			continue

		var tile_position: Vector2i = raw_tile

		if has_city_object_at_tile(tile_position):
			continue

		if CityLogisticsSystem.has_city_ground_pile_at_tile(tile_position):
			continue

		clean_tiles.append(tile_position)

	if clean_tiles.size() != 1:
		return {}

	var city_world: WorldData = values.get("city_world")

	if city_world == null:
		city_world = WorldPoliticalState.get_current_city_world()

	var topology_validation := validate_city_object_topology_mutation({
		"city_world": city_world,
		"object_type": CityObjectCatalog.CITY_OBJECT_ROAD,
		"footprint_tiles": clean_tiles,
		"allowed_construction_site_id": int(
			values.get("allowed_construction_site_id", -1)
		),
	})

	if not bool(topology_validation.get("success", false)):
		return {}

	var city_object := {
		"type": CityObjectCatalog.CITY_OBJECT_ROAD,
		"tiles": clean_tiles,
		"owner": str(values.get("object_owner", "player")),
	}

	if not _can_append_completed_city_object(city_object):
		return {}

	WorldData.clear_city_surface_features_at_tiles(city_world, clean_tiles)

	if not _append_completed_city_object(city_object, true):
		return {}

	return city_object


static func _can_append_completed_city_object(
	city_object: Dictionary
) -> bool:
	if city_object.is_empty():
		return false

	var state := _state()

	if (
		state.next_object_id <= 0
		or get_city_object_index_by_id(state.next_object_id) >= 0
	):
		return false

	var footprint_tiles := get_city_object_footprint_tiles(city_object)

	if footprint_tiles.is_empty():
		return false

	var tile_lookup: Dictionary = {}

	for raw_tile in footprint_tiles:
		if not raw_tile is Vector2i or tile_lookup.has(raw_tile):
			return false

		if has_city_object_at_tile(raw_tile):
			return false

		tile_lookup[raw_tile] = true

	return true


static func _append_completed_city_object(
	city_object: Dictionary,
	preflight_complete: bool = false
) -> bool:
	if not preflight_complete and not _can_append_completed_city_object(city_object):
		return false

	var state := _state()
	var object_id := state.next_object_id

	if object_id <= 0:
		push_error("Cannot allocate a non-positive city object ID.")
		return false

	city_object["id"] = object_id
	state.next_object_id += 1
	state.objects.append(city_object)

	var object_index := state.objects.size() - 1

	if not _register_city_object_index(city_object, object_index):
		state.objects.remove_at(object_index)
		state.next_object_id = object_id
		city_object.erase("id")
		return false

	if not occupy_city_object_tiles(city_object):
		state.object_index_by_id.erase(object_id)
		state.objects.remove_at(object_index)
		state.next_object_id = object_id
		city_object.erase("id")
		return false

	mark_city_objects_changed()

	if CityObjectCatalog.city_object_is_workplace(city_object):
		CityEmploymentSystem.mark_city_workplaces_changed()

	if city_object.has("stored_resources"):
		CityResourceAccountingSystem.mark_city_container_changed(city_object)

	return true


static func reset_city_object_state() -> void:
	_state().objects.clear()
	_state().object_index_by_id.clear()
	_state().occupied_tiles.clear()
	_state().next_object_id = 1

	mark_city_objects_changed()


static func _sort_city_tiles_y_then_x(
	tile_a: Vector2i,
	tile_b: Vector2i
) -> bool:
	if tile_a.y == tile_b.y:
		return tile_a.x < tile_b.x

	return tile_a.y < tile_b.y

static func can_use_city_object_definition(object_type: String) -> bool:
	var definition := CityObjectCatalog.get_city_object_definition(object_type)

	if definition.is_empty():
		return false

	if bool(definition.get("requires_city", false)) and not WorldData.can_build_in_city():
		return false

	if bool(definition.get("requires_no_city", false)) and WorldData.has_player_city():
		return false

	return true

static var city_object_definitions: Dictionary = (
	CityObjectCatalogScript.get_city_object_definitions()
)

#endregion

#region World Grid and Tile State

