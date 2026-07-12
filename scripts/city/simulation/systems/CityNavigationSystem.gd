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

const DEFAULT_MAX_EXPANDED_NODES: int = 50_000
const MAXIMUM_PATH_COST: int = 1_000_000_000

const HEAP_TILE_INDEX: int = 0
const HEAP_TOTAL_COST_INDEX: int = 1
const HEAP_HEURISTIC_INDEX: int = 2
const HEAP_TRAVEL_COST_INDEX: int = 3

const CARDINAL_NEIGHBOR_OFFSETS := [
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(0, 1)
]


static func find_path_to_any_city_tile(
	city_world: WorldData,
	start_tile: Vector2i,
	raw_destination_tiles: Array,
	max_expanded_nodes: int = (
		DEFAULT_MAX_EXPANDED_NODES
	)
) -> Dictionary:
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

	if not WorldData.is_city_tile_walkable_for_citizen(
		city_world,
		start_tile
	):
		result["status"] = PATH_STATUS_INVALID_START

		return _finish_result(
			result,
			search_start_usec
		)

	var destination_tiles := (
		_get_clean_destination_tiles(
			city_world,
			raw_destination_tiles
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

	var start_heuristic := (
		_get_minimum_manhattan_distance(
			start_tile,
			destination_tiles
		)
	)

	_push_open_heap_entry(
		open_heap,
		start_tile,
		0,
		start_heuristic
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

		for offset in CARDINAL_NEIGHBOR_OFFSETS:
			var neighbor_tile: Vector2i = (
				current_tile + offset
			)

			if closed_tile_lookup.has(neighbor_tile):
				continue

			if not (
				WorldData
				.is_city_tile_walkable_for_citizen(
					city_world,
					neighbor_tile
				)
			):
				continue

			var proposed_travel_cost := (
				current_travel_cost + 1
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

			var neighbor_heuristic := (
				_get_minimum_manhattan_distance(
					neighbor_tile,
					destination_tiles
				)
			)

			_push_open_heap_entry(
				open_heap,
				neighbor_tile,
				proposed_travel_cost,
				neighbor_heuristic
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
	raw_destination_tiles: Array
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

		if not WorldData.is_city_tile_walkable_for_citizen(
			city_world,
			destination_tile
		):
			continue

		destination_lookup[destination_tile] = true
		destination_tiles.append(destination_tile)

	destination_tiles.sort_custom(
		_sort_city_tiles_y_then_x
	)

	return destination_tiles


static func _sort_city_tiles_y_then_x(
	tile_a: Vector2i,
	tile_b: Vector2i
) -> bool:
	if tile_a.y == tile_b.y:
		return tile_a.x < tile_b.x

	return tile_a.y < tile_b.y


static func _get_minimum_manhattan_distance(
	tile_position: Vector2i,
	destination_tiles: Array
) -> int:
	var minimum_distance := MAXIMUM_PATH_COST

	for destination_tile in destination_tiles:
		var distance := (
			absi(
				destination_tile.x
				- tile_position.x
			)
			+ absi(
				destination_tile.y
				- tile_position.y
			)
		)

		minimum_distance = mini(
			minimum_distance,
			distance
		)

	return minimum_distance


static func _push_open_heap_entry(
	open_heap: Array,
	tile_position: Vector2i,
	travel_cost: int,
	heuristic: int
) -> void:
	var entry := [
		tile_position,
		travel_cost + heuristic,
		heuristic,
		travel_cost
	]

	open_heap.append(entry)

	var heap_index := open_heap.size() - 1

	while heap_index > 0:
		var parent_index := int(
			(heap_index - 1) / 2
		)

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


static func _finish_result(
	result: Dictionary,
	search_start_usec: int
) -> Dictionary:
	result["duration_usec"] = (
		Time.get_ticks_usec()
		- search_start_usec
	)

	return result
