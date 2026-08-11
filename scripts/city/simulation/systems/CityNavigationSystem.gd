extends RefCounted
class_name CityNavigationSystem

const PATH_STATUS_NOT_REQUESTED := "not_requested"
const PATH_STATUS_SUCCESS := "success"
const PATH_STATUS_INVALID_WORLD := "invalid_world"
const PATH_STATUS_INVALID_START := "invalid_start"
const PATH_STATUS_NO_DESTINATIONS := "no_valid_destinations"
const PATH_STATUS_UNREACHABLE := "unreachable"
const PATH_STATUS_SEARCH_LIMIT_REACHED := (
	"search_limit_reached"
)
const PATH_STATUS_RECONSTRUCTION_FAILED := (
	"reconstruction_failed"
)

const DEFAULT_MAX_EXPANDED_NODES: int = 10_000
const MAXIMUM_PATH_COST: int = 1_000_000_000
const EXACT_DESTINATION_HEURISTIC_LIMIT: int = 8

# Roads change traversal time, so ordinary pathfinding uses an admissible
# weight-one heuristic and optimizes exact estimated travel time.
const HEURISTIC_WEIGHT: int = 1

static func get_current_state() -> CityNavigationState:
	return WorldPoliticalState.get_current_city_navigation_state()


static func reset_city_navigation_state() -> void:
	get_current_state().object_access_tile_cache.clear()


static func _sort_city_tiles_y_then_x(
	tile_a: Vector2i,
	tile_b: Vector2i
) -> bool:
	if tile_a.y == tile_b.y:
		return tile_a.x < tile_b.x

	return tile_a.y < tile_b.y


static func get_city_object_access_tiles(
	city_world: WorldData,
	city_object: Dictionary
) -> Array:
	var access_tiles := []

	if city_world == null or city_object.is_empty():
		return access_tiles

	var footprint_tiles := CityObjectSystem.get_city_object_footprint_tiles(
		city_object
	)
	var object_id := int(city_object.get("id", -1))
	var footprint_hash_value := int(hash(footprint_tiles))
	var cache := get_current_state().object_access_tile_cache

	if object_id > 0:
		var raw_cache_entry = cache.get(object_id, {})
		if raw_cache_entry is Dictionary:
			var cache_entry: Dictionary = raw_cache_entry
			if (
				int(cache_entry.get("world_instance_id", -1))
				== int(city_world.get_instance_id())
				and int(cache_entry.get("tile_data_version", -1))
				== city_world.tile_data_version
				and int(cache_entry.get("city_object_version", -1))
				== CityObjectSystem.get_city_object_version()
				and int(cache_entry.get("footprint_hash", -1))
				== footprint_hash_value
			):
				var raw_cached_tiles = cache_entry.get("access_tiles", [])
				if raw_cached_tiles is Array:
					return raw_cached_tiles.duplicate()

	var footprint_lookup: Dictionary = {}
	for raw_footprint_tile in footprint_tiles:
		if raw_footprint_tile is Vector2i:
			footprint_lookup[raw_footprint_tile] = true

	var access_tile_lookup: Dictionary = {}
	for raw_footprint_tile in footprint_tiles:
		if not raw_footprint_tile is Vector2i:
			continue
		var footprint_tile: Vector2i = raw_footprint_tile
		for offset in WorldData.CITY_CARDINAL_TILE_OFFSETS:
			var candidate_tile: Vector2i = footprint_tile + offset
			if footprint_lookup.has(candidate_tile):
				continue
			if access_tile_lookup.has(candidate_tile):
				continue
			if not is_city_tile_walkable_for_citizen(city_world, candidate_tile):
				continue
			access_tile_lookup[candidate_tile] = true
			access_tiles.append(candidate_tile)

	access_tiles.sort_custom(_sort_city_tiles_y_then_x)

	if object_id > 0:
		cache[object_id] = {
			"world_instance_id": int(city_world.get_instance_id()),
			"tile_data_version": city_world.tile_data_version,
			"city_object_version": CityObjectSystem.get_city_object_version(),
			"footprint_hash": footprint_hash_value,
			"access_tiles": access_tiles.duplicate(),
		}

	return access_tiles


const HEAP_TILE_INDEX: int = 0
const HEAP_TOTAL_COST_INDEX: int = 1
const HEAP_HEURISTIC_INDEX: int = 2
const HEAP_TRAVEL_COST_INDEX: int = 3

const NEIGHBOR_OFFSETS := [
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, -1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(1, 1)
]

static func city_citizen_can_access_object_interior(
	citizen_id: int,
	city_object: Dictionary
) -> bool:
	if (
		citizen_id <= 0
		or city_object.is_empty()
		or not CityObjectSystem.city_object_supports_citizen_interior(city_object)
	):
		return false

	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)

	if (
		citizen.is_empty()
		or not bool(citizen.get("alive", false))
	):
		return false

	var object_id := int(city_object.get("id", -1))

	if object_id <= 0:
		return false

	var access_mode := (
		CityObjectSystem.get_city_object_citizen_interior_access_mode(
			city_object
		)
	)

	match access_mode:
		WorldData.CITY_OBJECT_INTERIOR_ACCESS_RESIDENTS:
			return (
				int(citizen.get("home_object_id", -1))
				== object_id
				and CityAssignmentSystem.get_city_object_resident_ids(
					city_object
				).has(citizen_id)
			)

		WorldData.CITY_OBJECT_INTERIOR_ACCESS_ASSIGNED_WORKERS:
			return (
				int(citizen.get("job_object_id", -1))
				== object_id
				and CityEmploymentSystem.get_city_object_worker_ids(
					city_object
				).has(citizen_id)
			)

		WorldData.CITY_OBJECT_INTERIOR_ACCESS_TASK_TARGET:
			var raw_current_task = citizen.get("current_task", {})
			var current_task: Dictionary = (
				raw_current_task
				if raw_current_task is Dictionary
				else {}
			)
			var task_kind := str(
				current_task.get(
					"kind",
					WorldData.CITY_CITIZEN_TASK_KIND_NONE
				)
			)

			# A ground-pile ID lives in a separate namespace and can equal an
			# unrelated city-object ID. For hauling, authorize only city-object
			# endpoints instead of treating the legacy numeric task target as an
			# object reference.
			if task_kind == WorldData.CITY_CITIZEN_TASK_KIND_HAUL:
				var raw_haul = citizen.get("current_haul", {})
				var haul: Dictionary = (
					raw_haul
					if raw_haul is Dictionary
					else {}
				)

				for endpoint_field in ["source", "destination"]:
					var raw_endpoint = haul.get(endpoint_field, {})

					if not raw_endpoint is Dictionary:
						continue

					var endpoint: Dictionary = raw_endpoint

					if (
						str(
							endpoint.get(
								"kind",
								WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
							)
						)
						== WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER
						and int(endpoint.get("id", -1)) == object_id
					):
						return true

				return false

			return (
				int(current_task.get("target_object_id", -1))
				== object_id
			)

		WorldData.CITY_OBJECT_INTERIOR_ACCESS_PUBLIC:
			return true

	return false

static func get_city_citizen_movement_step_cost(
	from_tile: Vector2i,
	to_tile: Vector2i
) -> int:
	var delta_x := absi(to_tile.x - from_tile.x)
	var delta_y := absi(to_tile.y - from_tile.y)

	if delta_x > 1 or delta_y > 1:
		return 0

	if delta_x == 0 and delta_y == 0:
		return 0

	var destination_is_road := CityObjectSystem.is_completed_city_road_tile(
		to_tile
	)

	if delta_x == 1 and delta_y == 1:
		if destination_is_road:
			return WorldData.CITY_CITIZEN_ROAD_DIAGONAL_MOVEMENT_COST

		return WorldData.CITY_CITIZEN_DIAGONAL_MOVEMENT_COST

	if destination_is_road:
		return WorldData.CITY_CITIZEN_ROAD_CARDINAL_MOVEMENT_COST

	return WorldData.CITY_CITIZEN_CARDINAL_MOVEMENT_COST

static func can_city_citizen_traverse_step(
	city_world: WorldData,
	from_tile: Vector2i,
	to_tile: Vector2i,
	citizen_id: int = -1
) -> bool:
	var step_cost := get_city_citizen_movement_step_cost(
		from_tile,
		to_tile
	)

	if step_cost <= 0:
		return false

	if not is_city_tile_walkable_for_citizen(
		city_world,
		to_tile,
		citizen_id
	):
		return false

	var delta_x := absi(to_tile.x - from_tile.x)
	var delta_y := absi(to_tile.y - from_tile.y)

	if delta_x == 1 and delta_y == 1:
		var horizontal_side_tile := Vector2i(
			to_tile.x,
			from_tile.y
		)
		var vertical_side_tile := Vector2i(
			from_tile.x,
			to_tile.y
		)

		if not is_city_tile_walkable_for_citizen(
			city_world,
			horizontal_side_tile,
			citizen_id
		):
			return false

		if not _city_citizen_can_cross_object_boundary(
			from_tile,
			horizontal_side_tile,
			citizen_id
		):
			return false

		if not is_city_tile_walkable_for_citizen(
			city_world,
			vertical_side_tile,
			citizen_id
		):
			return false

		if not _city_citizen_can_cross_object_boundary(
			from_tile,
			vertical_side_tile,
			citizen_id
		):
			return false

	return _city_citizen_can_cross_object_boundary(
		from_tile,
		to_tile,
		citizen_id
	)

static func _city_citizen_can_cross_object_boundary(
	from_tile: Vector2i,
	to_tile: Vector2i,
	citizen_id: int
) -> bool:
	var from_object_id := int(
		CityObjectSystem.get_city_object_id_at_tile(from_tile)
	)
	var to_object_id := int(
		CityObjectSystem.get_city_object_id_at_tile(to_tile)
	)

	if from_object_id == to_object_id:
		return true

	if from_object_id > 0:
		var from_object := CityObjectSystem.get_city_object_by_id(
			from_object_id
		)

		if (
			CityObjectSystem.city_object_supports_citizen_interior(from_object)
			and not CityObjectSystem.city_object_boundary_tile_allows_entry(
				from_object,
				from_tile
			)
		):
			return false

	if to_object_id > 0:
		var to_object := CityObjectSystem.get_city_object_by_id(to_object_id)

		if CityObjectSystem.city_object_supports_citizen_interior(to_object):
			if not city_citizen_can_access_object_interior(
				citizen_id,
				to_object
			):
				return false

			if not CityObjectSystem.city_object_boundary_tile_allows_entry(
				to_object,
				to_tile
			):
				return false

	return true

static func is_city_tile_walkable_for_citizen(
	city_world: WorldData,
	tile_position: Vector2i,
	citizen_id: int = -1
) -> bool:
	if city_world == null:
		return false

	if not city_world.is_in_bounds(
		tile_position.x,
		tile_position.y
	):
		return false

	var tile: Dictionary = city_world.get_tile(
		tile_position.x,
		tile_position.y
	)

	if str(tile.get("terrain", "")) != WorldData.TERRAIN_LAND:
		return false

	if not CityObjectSystem.has_city_object_at_tile(tile_position):
		return true

	var object_id := int(
		CityObjectSystem.get_city_object_id_at_tile(tile_position)
	)
	var occupying_object := CityObjectSystem.get_city_object_by_id(object_id)

	if occupying_object.is_empty():
		return false

	if (
		str(occupying_object.get("type", ""))
		== WorldData.CITY_OBJECT_ROAD
	):
		return true

	if citizen_id <= 0:
		return false

	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)

	if (
		citizen.is_empty()
		or not bool(citizen.get("alive", false))
	):
		return false

	var current_position = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	# Recovery invariant: a citizen already caught inside an occupied footprint
	# may traverse that same footprint long enough to leave it. Normal topology
	# mutations are prevented from creating this state; this path exists for old
	# saves and defensive recovery only, and never authorizes re-entry.
	if (
		current_position is Vector2i
		and CityObjectSystem.get_city_object_id_at_tile(current_position)
		== object_id
	):
		return true

	if not CityObjectSystem.city_object_supports_citizen_interior(occupying_object):
		return false

	return city_citizen_can_access_object_interior(
		citizen_id,
		occupying_object
	)

static func find_path_to_any_city_tile(values: Dictionary) -> Dictionary:
	var city_world: WorldData = values.get("city_world")
	var start_tile: Vector2i = values.get(
		"start_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var raw_destination_tiles: Array = values.get("destination_tiles", [])
	var max_expanded_nodes := maxi(
		int(values.get("max_expanded_nodes", DEFAULT_MAX_EXPANDED_NODES)),
		1
	)
	var citizen_id := int(values.get("citizen_id", -1))
	var heuristic_weight := maxi(
		int(values.get("heuristic_weight", HEURISTIC_WEIGHT)),
		1
	)
	var search_start_usec := Time.get_ticks_usec()

	var result := {
		"success": false,
		"status": PATH_STATUS_INVALID_WORLD,
		"path": [],
		"start_tile": start_tile,
		"destination_tile": (
			WorldData.INVALID_CITY_TILE_POSITION
		),
		"destination_candidate_count": 0,
		"expanded_node_count": 0,
		"path_cost": 0,
		"duration_usec": 0
	}

	if city_world == null:
		return _finish_result(
			result,
			search_start_usec
		)

	if not CityNavigationSystem.is_city_tile_walkable_for_citizen(
		city_world,
		start_tile,
		citizen_id
	):
		result["status"] = PATH_STATUS_INVALID_START

		return _finish_result(
			result,
			search_start_usec
		)

	var destination_tiles := (
		_get_clean_destination_tiles(
			city_world,
			raw_destination_tiles,
			citizen_id
		)
	)

	result["destination_candidate_count"] = (
		destination_tiles.size()
	)

	if destination_tiles.is_empty():
		result["status"] = PATH_STATUS_NO_DESTINATIONS

		return _finish_result(
			result,
			search_start_usec
		)

	var destination_lookup: Dictionary = {}

	for destination_tile in destination_tiles:
		destination_lookup[destination_tile] = true

	if destination_lookup.has(start_tile):
		result["success"] = true
		result["status"] = PATH_STATUS_SUCCESS
		result["path"] = [start_tile]
		result["destination_tile"] = start_tile

		return _finish_result(
			result,
			search_start_usec
		)

	var open_heap: Array = []
	var travel_cost_by_tile: Dictionary = {
		start_tile: 0
	}
	var previous_tile_by_tile: Dictionary = {}
	var closed_tile_lookup: Dictionary = {}

	var destination_heuristic := (
		_make_destination_heuristic(destination_tiles)
	)
	var start_heuristic := _get_destination_heuristic(
		start_tile,
		destination_heuristic
	)
	var safe_heuristic_weight := maxi(
		heuristic_weight,
		1
	)

	_push_open_heap_entry(
		open_heap,
		start_tile,
		0,
		start_heuristic,
		safe_heuristic_weight
	)

	var expanded_node_count := 0
	var safe_max_expanded_nodes := maxi(
		max_expanded_nodes,
		1
	)

	while not open_heap.is_empty():
		if (
			expanded_node_count
			>= safe_max_expanded_nodes
		):
			result["status"] = (
				PATH_STATUS_SEARCH_LIMIT_REACHED
			)
			result["expanded_node_count"] = (
				expanded_node_count
			)

			return _finish_result(
				result,
				search_start_usec
			)

		var current_entry := (
			_pop_open_heap_entry(
				open_heap
			)
		)

		if current_entry.is_empty():
			break

		var current_tile: Vector2i = (
			current_entry[HEAP_TILE_INDEX]
		)
		var current_travel_cost := int(
			current_entry[
				HEAP_TRAVEL_COST_INDEX
			]
		)

		if closed_tile_lookup.has(current_tile):
			continue

		if (
			current_travel_cost
			!= int(
				travel_cost_by_tile.get(
					current_tile,
					MAXIMUM_PATH_COST
				)
			)
		):
			continue

		closed_tile_lookup[current_tile] = true
		expanded_node_count += 1

		if destination_lookup.has(current_tile):
			var path := _reconstruct_path(
				previous_tile_by_tile,
				start_tile,
				current_tile
			)

			if path.is_empty():
				result["status"] = (
					PATH_STATUS_RECONSTRUCTION_FAILED
				)
			else:
				result["success"] = true
				result["status"] = (
					PATH_STATUS_SUCCESS
				)
				result["path"] = path
				result["destination_tile"] = (
					current_tile
				)
				result["path_cost"] = (
					current_travel_cost
				)

			result["expanded_node_count"] = (
				expanded_node_count
			)

			return _finish_result(
				result,
				search_start_usec
			)

		for offset in NEIGHBOR_OFFSETS:
			var neighbor_tile: Vector2i = (
				current_tile + offset
			)

			if closed_tile_lookup.has(neighbor_tile):
				continue

			if not CityNavigationSystem.can_city_citizen_traverse_step(
				city_world,
				current_tile,
				neighbor_tile,
				citizen_id
			):
				continue

			var step_cost := (
				CityNavigationSystem.get_city_citizen_movement_step_cost(
					current_tile,
					neighbor_tile
				)
			)

			if step_cost <= 0:
				continue

			var proposed_travel_cost := (
				current_travel_cost + step_cost
			)
			var known_travel_cost := int(
				travel_cost_by_tile.get(
					neighbor_tile,
					MAXIMUM_PATH_COST
				)
			)

			if (
				proposed_travel_cost
				>= known_travel_cost
			):
				continue

			travel_cost_by_tile[neighbor_tile] = (
				proposed_travel_cost
			)
			previous_tile_by_tile[neighbor_tile] = (
				current_tile
			)

			var neighbor_heuristic := _get_destination_heuristic(
				neighbor_tile,
				destination_heuristic
			)

			_push_open_heap_entry(
				open_heap,
				neighbor_tile,
				proposed_travel_cost,
				neighbor_heuristic,
				safe_heuristic_weight
			)

	result["status"] = PATH_STATUS_UNREACHABLE
	result["expanded_node_count"] = (
		expanded_node_count
	)

	return _finish_result(
		result,
		search_start_usec
	)


static func _get_clean_destination_tiles(
	city_world: WorldData,
	raw_destination_tiles: Array,
	citizen_id: int
) -> Array:
	var destination_tiles := []
	var destination_lookup: Dictionary = {}

	for raw_destination_tile in raw_destination_tiles:
		if not raw_destination_tile is Vector2i:
			continue

		var destination_tile: Vector2i = (
			raw_destination_tile
		)

		if destination_lookup.has(destination_tile):
			continue

		if not CityNavigationSystem.is_city_tile_walkable_for_citizen(
			city_world,
			destination_tile,
			citizen_id
		):
			continue

		destination_lookup[destination_tile] = true
		destination_tiles.append(destination_tile)

	destination_tiles.sort_custom(
		CityObjectSystem._sort_city_tiles_y_then_x
	)

	return destination_tiles


static func _make_destination_heuristic(
	destination_tiles: Array
) -> Dictionary:
	if destination_tiles.size() <= EXACT_DESTINATION_HEURISTIC_LIMIT:
		return {
			"use_exact": true,
			"destination_tiles": destination_tiles,
		}

	var first_tile: Vector2i = destination_tiles[0]
	var minimum_x := first_tile.x
	var maximum_x := first_tile.x
	var minimum_y := first_tile.y
	var maximum_y := first_tile.y

	for destination_tile in destination_tiles:
		minimum_x = mini(minimum_x, destination_tile.x)
		maximum_x = maxi(maximum_x, destination_tile.x)
		minimum_y = mini(minimum_y, destination_tile.y)
		maximum_y = maxi(maximum_y, destination_tile.y)

	return {
		"use_exact": false,
		"minimum_x": minimum_x,
		"maximum_x": maximum_x,
		"minimum_y": minimum_y,
		"maximum_y": maximum_y,
	}


static func _get_destination_heuristic(
	tile_position: Vector2i,
	heuristic: Dictionary
) -> int:
	if bool(heuristic.get("use_exact", false)):
		return _get_minimum_octile_distance(
			tile_position,
			heuristic.get("destination_tiles", [])
		)

	var delta_x := 0
	var delta_y := 0
	var minimum_x := int(heuristic.get("minimum_x", tile_position.x))
	var maximum_x := int(heuristic.get("maximum_x", tile_position.x))
	var minimum_y := int(heuristic.get("minimum_y", tile_position.y))
	var maximum_y := int(heuristic.get("maximum_y", tile_position.y))

	if tile_position.x < minimum_x:
		delta_x = minimum_x - tile_position.x
	elif tile_position.x > maximum_x:
		delta_x = tile_position.x - maximum_x

	if tile_position.y < minimum_y:
		delta_y = minimum_y - tile_position.y
	elif tile_position.y > maximum_y:
		delta_y = tile_position.y - maximum_y

	return _get_octile_road_cost(delta_x, delta_y)


static func _get_minimum_octile_distance(
	tile_position: Vector2i,
	destination_tiles: Array
) -> int:
	var minimum_distance := MAXIMUM_PATH_COST

	for destination_tile in destination_tiles:
		minimum_distance = mini(
			minimum_distance,
			_get_octile_road_cost(
				absi(destination_tile.x - tile_position.x),
				absi(destination_tile.y - tile_position.y)
			)
		)

	return minimum_distance


static func _get_octile_road_cost(delta_x: int, delta_y: int) -> int:
	var diagonal_steps := mini(delta_x, delta_y)
	var straight_steps := maxi(delta_x, delta_y) - diagonal_steps
	# Completed roads are the fastest possible terrain. Using road costs keeps
	# both the exact and bounding-box heuristics admissible.
	return (
		diagonal_steps
		* WorldData.CITY_CITIZEN_ROAD_DIAGONAL_MOVEMENT_COST
		+ straight_steps
		* WorldData.CITY_CITIZEN_ROAD_CARDINAL_MOVEMENT_COST
	)


static func _push_open_heap_entry(
	open_heap: Array,
	tile_position: Vector2i,
	travel_cost: int,
	heuristic: int,
	heuristic_weight: int
) -> void:
	# Direct arguments avoid allocating a Dictionary for every open-set push.
	var entry := [
		tile_position,
		travel_cost + heuristic * heuristic_weight,
		heuristic,
		travel_cost,
	]

	open_heap.append(entry)

	var heap_index := open_heap.size() - 1

	while heap_index > 0:
		var parent_index := int((heap_index - 1) / 2)

		if not _heap_entry_precedes(
			open_heap[heap_index],
			open_heap[parent_index]
		):
			break

		var temporary_entry = open_heap[parent_index]
		open_heap[parent_index] = open_heap[heap_index]
		open_heap[heap_index] = temporary_entry
		heap_index = parent_index


static func _pop_open_heap_entry(
	open_heap: Array
) -> Array:
	if open_heap.is_empty():
		return []

	var root_entry: Array = open_heap[0]
	var final_entry = open_heap.pop_back()

	if open_heap.is_empty():
		return root_entry

	open_heap[0] = final_entry

	var heap_index := 0

	while true:
		var left_index := heap_index * 2 + 1
		var right_index := left_index + 1

		if left_index >= open_heap.size():
			break

		var preferred_child_index := left_index

		if (
			right_index < open_heap.size()
			and _heap_entry_precedes(
				open_heap[right_index],
				open_heap[left_index]
			)
		):
			preferred_child_index = right_index

		if not _heap_entry_precedes(
			open_heap[preferred_child_index],
			open_heap[heap_index]
		):
			break

		var temporary_entry = open_heap[heap_index]
		open_heap[heap_index] = (
			open_heap[preferred_child_index]
		)
		open_heap[preferred_child_index] = (
			temporary_entry
		)
		heap_index = preferred_child_index

	return root_entry


static func _heap_entry_precedes(
	entry_a: Array,
	entry_b: Array
) -> bool:
	var total_cost_a := int(
		entry_a[HEAP_TOTAL_COST_INDEX]
	)
	var total_cost_b := int(
		entry_b[HEAP_TOTAL_COST_INDEX]
	)

	if total_cost_a != total_cost_b:
		return total_cost_a < total_cost_b

	var heuristic_a := int(
		entry_a[HEAP_HEURISTIC_INDEX]
	)
	var heuristic_b := int(
		entry_b[HEAP_HEURISTIC_INDEX]
	)

	if heuristic_a != heuristic_b:
		return heuristic_a < heuristic_b

	var tile_a: Vector2i = entry_a[HEAP_TILE_INDEX]
	var tile_b: Vector2i = entry_b[HEAP_TILE_INDEX]

	if tile_a.y != tile_b.y:
		return tile_a.y < tile_b.y

	return tile_a.x < tile_b.x


static func _reconstruct_path(
	previous_tile_by_tile: Dictionary,
	start_tile: Vector2i,
	destination_tile: Vector2i
) -> Array:
	var path := [destination_tile]
	var current_tile := destination_tile

	while current_tile != start_tile:
		if not previous_tile_by_tile.has(
			current_tile
		):
			return []

		current_tile = previous_tile_by_tile[
			current_tile
		]
		path.append(current_tile)

	path.reverse()
	return path


static func get_city_wide_path_expansion_limit(
	city_world: WorldData
) -> int:
	if city_world == null:
		return 1

	return maxi(city_world.width * city_world.height, 1)


static func _finish_result(
	result: Dictionary,
	search_start_usec: int
) -> Dictionary:
	result["duration_usec"] = (
		Time.get_ticks_usec()
		- search_start_usec
	)

	return result
