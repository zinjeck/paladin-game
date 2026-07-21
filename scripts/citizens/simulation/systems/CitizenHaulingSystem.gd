extends RefCounted
class_name CitizenHaulingSystem

const CityNavigationSystemScript = preload(
	"res://scripts/city/simulation/systems/CityNavigationSystem.gd"
)

const EXACT_DESTINATION_HEURISTIC_WEIGHT: int = 1
const BLOCKED_HAUL_RETRY_DELAY_MINUTES: int = 30

# This system executes an already-decided haul. It does not decide whether a
# citizen ought to haul, produce resources, render markers, or expose UI.
# Endpoint dispatch is intentionally centralized so future ground piles or
# other container kinds can be added without rewriting the state machine.


static func make_public_storage_haul_task_request(
	values: Dictionary
) -> Dictionary:
	var raw_city_world = values.get("city_world")
	var raw_citizen = values.get("citizen", {})
	var raw_source = values.get("source", {})
	var raw_requester = values.get("requester", {})

	if not raw_city_world is WorldData:
		return {}

	if not raw_citizen is Dictionary:
		return {}

	if not raw_source is Dictionary:
		return {}

	if not raw_requester is Dictionary:
		return {}

	var city_world: WorldData = raw_city_world
	var citizen: Dictionary = raw_citizen
	var source: Dictionary = (
		CityCitizens.make_city_citizen_haul_endpoint(
			raw_source
		)
	)
	var requester: Dictionary = (
		CityCitizens.make_city_citizen_haul_endpoint(
			raw_requester
		)
	)
	var citizen_id := int(citizen.get("id", -1))
	var resource := str(
		values.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var requested_amount := maxi(
		int(values.get("requested_amount", 0)),
		0
	)
	var reason := str(
		values.get(
			"reason",
			WorldData.CITY_CITIZEN_HAUL_REASON_NONE
		)
	)
	var source_access_purpose := str(
		values.get(
			"source_access_purpose",
			WorldData.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var destination_access_purpose := str(
		values.get(
			"destination_access_purpose",
			WorldData.CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE
		)
	)
	var task_source := str(
		values.get(
			"task_source",
			WorldData.CITY_CITIZEN_TASK_SOURCE_SCHEDULE
		)
	)
	var task_priority := int(values.get("task_priority", 0))
	var raw_current_tile = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if (
		citizen_id <= 0
		or not bool(citizen.get("alive", false))
		or not raw_current_tile is Vector2i
		or not WorldData.get_city_resource_types().has(resource)
		or reason == WorldData.CITY_CITIZEN_HAUL_REASON_NONE
		or source_access_purpose
		== WorldData.CONTAINER_HAUL_PURPOSE_NONE
		or destination_access_purpose
		== WorldData.CONTAINER_HAUL_PURPOSE_NONE
		or task_priority
		<= WorldData.CITY_CITIZEN_TASK_PRIORITY_NONE
		or not WorldData.is_valid_city_citizen_task_source(
			task_source
		)
		or task_source == WorldData.CITY_CITIZEN_TASK_SOURCE_NONE
		or not CityCitizens.is_valid_city_citizen_haul_endpoint(
			source
		)
		or not CityCitizens.is_valid_city_citizen_haul_endpoint(
			requester
		)
	):
		return {}

	var current_tile: Vector2i = raw_current_tile
	var cargo := WorldData.get_city_citizen_haul_cargo(
		citizen_id
	)
	var cargo_amount := maxi(
		int(cargo.get("amount", 0)),
		0
	)
	var destination_result: Dictionary = {}
	var initial_phase: String = (
		WorldData.CITY_CITIZEN_HAUL_PHASE_PENDING_SOURCE
	)
	var source_tile: Vector2i = WorldData.INVALID_CITY_TILE_POSITION

	if cargo_amount > 0:
		var cargo_resource := str(
			cargo.get("resource_type", WorldData.RESOURCE_NONE)
		)

		if cargo_resource != resource:
			return {}

		requested_amount = maxi(requested_amount, cargo_amount)
		initial_phase = (
			WorldData.CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION
		)
		destination_result = find_nearest_eligible_destination({
			"city_world": city_world,
			"start_tile": current_tile,
			"citizen_id": citizen_id,
			"resource_type": resource,
			"destination_access_purpose": (
				destination_access_purpose
			),
		})
	else:
		var source_object := _get_endpoint_object(source)

		if not WorldData.city_object_can_provide_haul_resource(
			source_object,
			resource,
			source_access_purpose
		):
			return {}

		var remaining_capacity := (
			WorldData.get_city_citizen_available_haul_capacity(
				citizen_id
			)
		)
		var source_amount := (
			WorldData.get_city_object_stored_resource_amount(
				source_object,
				resource
			)
		)

		requested_amount = mini(
			requested_amount,
			mini(remaining_capacity, source_amount)
		)

		if requested_amount <= 0:
			return {}

		var source_access_tiles := _get_endpoint_access_tiles(
			city_world,
			source
		)

		if source_access_tiles.is_empty():
			return {}

		var source_path_result := (
			CityNavigationSystemScript.find_path_to_any_city_tile(
				city_world,
				current_tile,
				source_access_tiles,
				_get_city_wide_path_expansion_limit(city_world),
				citizen_id,
				EXACT_DESTINATION_HEURISTIC_WEIGHT
			)
		)

		if not bool(source_path_result.get("success", false)):
			return {}

		var raw_source_tile = source_path_result.get(
			"destination_tile",
			WorldData.INVALID_CITY_TILE_POSITION
		)

		if not raw_source_tile is Vector2i:
			return {}

		source_tile = raw_source_tile
		destination_result = find_nearest_eligible_destination({
			"city_world": city_world,
			"start_tile": source_tile,
			"citizen_id": citizen_id,
			"resource_type": resource,
			"destination_access_purpose": (
				destination_access_purpose
			),
		})

		# No resource is removed unless a reachable destination currently has
		# room. The worker may proceed to their next scheduled activity.
		if destination_result.is_empty():
			return {}

	var destination := (
		CityCitizens.make_city_citizen_haul_endpoint()
	)
	var destination_tile: Vector2i = (
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not destination_result.is_empty():
		destination = destination_result.get(
			"endpoint",
			destination
		)
		destination_tile = destination_result.get(
			"destination_tile",
			WorldData.INVALID_CITY_TILE_POSITION
		)
	elif cargo_amount > 0:
		var existing_haul := (
			WorldData.get_city_citizen_current_haul(citizen_id)
		)
		var raw_existing_destination = existing_haul.get(
			"destination",
			{}
		)

		if raw_existing_destination is Dictionary:
			destination = (
				CityCitizens.make_city_citizen_haul_endpoint(
					raw_existing_destination
				)
			)

		initial_phase = WorldData.CITY_CITIZEN_HAUL_PHASE_BLOCKED

	var source_object_id := int(source.get("id", -1))

	if source_object_id <= 0:
		return {}

	return {
		"kind": WorldData.CITY_CITIZEN_TASK_KIND_HAUL,
		"source": task_source,
		"priority": task_priority,
		"target_object_id": source_object_id,
		"player_locked": false,
		"haul": CityCitizens.make_city_citizen_haul({
			"source": source,
			"destination": destination,
			"resource_type": resource,
			"requested_amount": requested_amount,
			"reason": reason,
			"requester": requester,
			"source_access_purpose": source_access_purpose,
			"destination_access_purpose": (
				destination_access_purpose
			),
			"phase": initial_phase,
			"source_tile": source_tile,
			"destination_tile": destination_tile,
		}),
	}


static func find_nearest_eligible_destination(
	values: Dictionary
) -> Dictionary:
	var raw_city_world = values.get("city_world")
	var raw_start_tile = values.get(
		"start_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not raw_city_world is WorldData:
		return {}

	if not raw_start_tile is Vector2i:
		return {}

	var city_world: WorldData = raw_city_world
	var start_tile: Vector2i = raw_start_tile
	var citizen_id := int(values.get("citizen_id", -1))
	var resource := str(
		values.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var destination_access_purpose := str(
		values.get(
			"destination_access_purpose",
			WorldData.CONTAINER_HAUL_PURPOSE_NONE
		)
	)

	if (
		citizen_id <= 0
		or not WorldData.get_city_resource_types().has(resource)
		or destination_access_purpose
		== WorldData.CONTAINER_HAUL_PURPOSE_NONE
	):
		return {}

	var endpoint_ids_by_access_tile: Dictionary = {}
	var destination_tiles: Array = []

	# This is the replaceable destination-eligibility policy boundary. The
	# current policy deliberately scans every compatible public container in
	# the city; later radii, priorities, filters, and preferences belong here.
	for raw_city_object in WorldData.city_objects:
		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object

		if not WorldData.city_object_can_accept_haul_resource(
			city_object,
			resource,
			destination_access_purpose,
			true
		):
			continue

		var object_id := int(city_object.get("id", -1))

		if object_id <= 0:
			continue

		var endpoint := WorldData.make_city_citizen_haul_endpoint(
			object_id
		)

		for access_tile in _get_endpoint_access_tiles(
			city_world,
			endpoint
		):
			if not endpoint_ids_by_access_tile.has(access_tile):
				endpoint_ids_by_access_tile[access_tile] = []
				destination_tiles.append(access_tile)

			var endpoint_ids: Array = (
				endpoint_ids_by_access_tile[access_tile]
			)
			endpoint_ids.append(object_id)
			endpoint_ids_by_access_tile[access_tile] = endpoint_ids

	if destination_tiles.is_empty():
		return {}

	var path_result := (
		CityNavigationSystemScript.find_path_to_any_city_tile(
			city_world,
			start_tile,
			destination_tiles,
			_get_city_wide_path_expansion_limit(city_world),
			citizen_id,
			EXACT_DESTINATION_HEURISTIC_WEIGHT
		)
	)

	if not bool(path_result.get("success", false)):
		return {}

	var raw_destination_tile = path_result.get(
		"destination_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var raw_path = path_result.get("path", [])

	if not raw_destination_tile is Vector2i:
		return {}

	if not raw_path is Array:
		return {}

	var destination_tile: Vector2i = raw_destination_tile
	var raw_endpoint_ids = endpoint_ids_by_access_tile.get(
		destination_tile,
		[]
	)

	if not raw_endpoint_ids is Array:
		return {}

	var endpoint_ids: Array = raw_endpoint_ids
	endpoint_ids.sort()

	for raw_endpoint_id in endpoint_ids:
		var endpoint_id := int(raw_endpoint_id)
		var city_object := WorldData.get_city_object_by_id(
			endpoint_id
		)

		if not WorldData.city_object_can_accept_haul_resource(
			city_object,
			resource,
			destination_access_purpose,
			true
		):
			continue

		return {
			"endpoint": WorldData.make_city_citizen_haul_endpoint(
				endpoint_id
			),
			"destination_tile": destination_tile,
			"path": raw_path.duplicate(),
			"path_cost": int(path_result.get("path_cost", 0)),
		}

	return {}


static func advance_haul_task(
	city_world: WorldData,
	citizen_id: int,
	citizen: Dictionary,
	current_task: Dictionary,
	path_requests_remaining: int
) -> int:
	if (
		city_world == null
		or citizen_id <= 0
		or citizen.is_empty()
		or str(current_task.get("kind", ""))
		!= WorldData.CITY_CITIZEN_TASK_KIND_HAUL
	):
		return path_requests_remaining

	var haul := WorldData.get_city_citizen_current_haul(
		citizen_id
	)
	var cargo := WorldData.get_city_citizen_haul_cargo(
		citizen_id
	)
	var cargo_amount := maxi(
		int(cargo.get("amount", 0)),
		0
	)
	var haul_resource := str(
		haul.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var haul_phase := str(
		haul.get(
			"phase",
			WorldData.CITY_CITIZEN_HAUL_PHASE_NONE
		)
	)

	if not WorldData.get_city_resource_types().has(haul_resource):
		_finish_haul_without_pickup(citizen_id, current_task)
		return path_requests_remaining

	if cargo_amount > 0:
		if str(
			cargo.get("resource_type", WorldData.RESOURCE_NONE)
		) != haul_resource:
			_set_haul_blocked(citizen_id, haul)
			return path_requests_remaining

		if (
			haul_phase
			== WorldData.CITY_CITIZEN_HAUL_PHASE_PENDING_SOURCE
			or haul_phase
			== WorldData.CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_SOURCE
			or haul_phase
			== WorldData.CITY_CITIZEN_HAUL_PHASE_PICKING_UP
		):
			WorldData.cancel_city_citizen_movement(citizen_id)
			haul["phase"] = (
				WorldData.CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION
			)
			WorldData.set_city_citizen_current_haul(
				citizen_id,
				haul
			)
			haul_phase = (
				WorldData.CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION
			)
	elif (
		haul_phase
		== WorldData.CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION
		or haul_phase
		== WorldData.CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_DESTINATION
		or haul_phase == WorldData.CITY_CITIZEN_HAUL_PHASE_DEPOSITING
		or haul_phase == WorldData.CITY_CITIZEN_HAUL_PHASE_RETARGETING
	):
		_finish_haul_without_pickup(citizen_id, current_task)
		return path_requests_remaining

	if haul_phase == WorldData.CITY_CITIZEN_HAUL_PHASE_BLOCKED:
		if not _prepare_blocked_haul_retry(
			citizen_id,
			current_task,
			cargo_amount > 0
		):
			return path_requests_remaining

		haul = WorldData.get_city_citizen_current_haul(
			citizen_id
		)
		haul_phase = str(
			haul.get(
				"phase",
				WorldData.CITY_CITIZEN_HAUL_PHASE_NONE
			)
		)
		citizen = WorldData.get_city_citizen_by_id(citizen_id)
		current_task = WorldData.get_city_citizen_current_task(
			citizen_id
		)

	match haul_phase:
		WorldData.CITY_CITIZEN_HAUL_PHASE_PENDING_SOURCE:
			return _advance_pending_source(
				city_world,
				citizen_id,
				citizen,
				current_task,
				haul,
				path_requests_remaining
			)

		WorldData.CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_SOURCE:
			return _advance_traveling_to_source(
				city_world,
				citizen_id,
				citizen,
				current_task,
				haul,
				path_requests_remaining
			)

		WorldData.CITY_CITIZEN_HAUL_PHASE_PICKING_UP:
			return _attempt_pickup(
				city_world,
				citizen_id,
				citizen,
				current_task,
				haul,
				path_requests_remaining
			)

		WorldData.CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION:
			return _advance_pending_destination(
				city_world,
				citizen_id,
				citizen,
				current_task,
				haul,
				path_requests_remaining
			)

		WorldData.CITY_CITIZEN_HAUL_PHASE_RETARGETING:
			return _advance_pending_destination(
				city_world,
				citizen_id,
				citizen,
				current_task,
				haul,
				path_requests_remaining
			)

		WorldData.CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_DESTINATION:
			return _advance_traveling_to_destination(
				city_world,
				citizen_id,
				citizen,
				current_task,
				haul,
				path_requests_remaining
			)

		WorldData.CITY_CITIZEN_HAUL_PHASE_DEPOSITING:
			return _deposit_and_retarget(
				city_world,
				citizen_id,
				current_task,
				haul,
				path_requests_remaining
			)

		_:
			_set_haul_blocked(citizen_id, haul)

	return path_requests_remaining


static func _advance_pending_source(
	city_world: WorldData,
	citizen_id: int,
	citizen: Dictionary,
	current_task: Dictionary,
	haul: Dictionary,
	path_requests_remaining: int
) -> int:
	var source: Dictionary = haul.get("source", {})
	var resource := str(
		haul.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var source_access_purpose := str(
		haul.get(
			"source_access_purpose",
			WorldData.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var source_object := _get_endpoint_object(source)

	if not WorldData.city_object_can_provide_haul_resource(
		source_object,
		resource,
		source_access_purpose
	):
		_finish_haul_without_pickup(citizen_id, current_task)
		return path_requests_remaining

	if (
		WorldData.get_city_citizen_available_haul_capacity(
			citizen_id
		) <= 0
	):
		_finish_haul_without_pickup(citizen_id, current_task)
		return path_requests_remaining

	var raw_current_tile = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var source_access_tiles := _get_endpoint_access_tiles(
		city_world,
		source
	)

	if not raw_current_tile is Vector2i or source_access_tiles.is_empty():
		_set_haul_blocked(citizen_id, haul)
		return path_requests_remaining

	var current_tile: Vector2i = raw_current_tile

	if source_access_tiles.has(current_tile):
		WorldData.cancel_city_citizen_movement(citizen_id)
		haul["phase"] = WorldData.CITY_CITIZEN_HAUL_PHASE_PICKING_UP
		haul["source_tile"] = current_tile
		WorldData.set_city_citizen_current_haul(citizen_id, haul)
		WorldData.set_city_citizen_task_phase(
			citizen_id,
			WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING
		)
		return _attempt_pickup(
			city_world,
			citizen_id,
			WorldData.get_city_citizen_by_id(citizen_id),
			current_task,
			haul,
			path_requests_remaining
		)

	if path_requests_remaining <= 0:
		return path_requests_remaining

	path_requests_remaining -= 1
	var path_result := (
		CityNavigationSystemScript.find_path_to_any_city_tile(
			city_world,
			current_tile,
			source_access_tiles,
			_get_city_wide_path_expansion_limit(city_world),
			citizen_id
		)
	)

	if not bool(path_result.get("success", false)):
		_set_haul_blocked(citizen_id, haul)
		return path_requests_remaining

	var raw_path = path_result.get("path", [])
	var raw_destination_tile = path_result.get(
		"destination_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not raw_path is Array or not raw_destination_tile is Vector2i:
		_set_haul_blocked(citizen_id, haul)
		return path_requests_remaining

	var movement_path: Array = raw_path
	var source_tile: Vector2i = raw_destination_tile

	haul["phase"] = (
		WorldData.CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_SOURCE
	)
	haul["source_tile"] = source_tile
	WorldData.set_city_citizen_current_haul(citizen_id, haul)
	WorldData.set_city_citizen_task_activity_state({
		"citizen_id": citizen_id,
		"target_tile": source_tile,
	})

	if movement_path.size() <= 1:
		haul["phase"] = WorldData.CITY_CITIZEN_HAUL_PHASE_PICKING_UP
		WorldData.set_city_citizen_current_haul(citizen_id, haul)
		WorldData.set_city_citizen_task_phase(
			citizen_id,
			WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING
		)
		return path_requests_remaining

	if not WorldData.assign_city_citizen_movement_order(
		citizen_id,
		movement_path
	):
		_set_haul_blocked(citizen_id, haul)
		return path_requests_remaining

	WorldData.set_city_citizen_task_phase(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_PHASE_TRAVELING
	)
	return path_requests_remaining


static func _advance_traveling_to_source(
	city_world: WorldData,
	citizen_id: int,
	citizen: Dictionary,
	current_task: Dictionary,
	haul: Dictionary,
	path_requests_remaining: int
) -> int:
	var movement_state := str(
		citizen.get(
			"movement_state",
			WorldData.CITY_CITIZEN_MOVEMENT_STATE_IDLE
		)
	)

	if movement_state == WorldData.CITY_CITIZEN_MOVEMENT_STATE_MOVING:
		return path_requests_remaining

	if movement_state == WorldData.CITY_CITIZEN_MOVEMENT_STATE_BLOCKED:
		_set_haul_blocked(citizen_id, haul)
		return path_requests_remaining

	var raw_current_tile = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var source: Dictionary = haul.get("source", {})
	var source_access_tiles := _get_endpoint_access_tiles(
		city_world,
		source
	)

	if (
		raw_current_tile is Vector2i
		and source_access_tiles.has(raw_current_tile)
	):
		haul["phase"] = WorldData.CITY_CITIZEN_HAUL_PHASE_PICKING_UP
		haul["source_tile"] = raw_current_tile
		WorldData.set_city_citizen_current_haul(citizen_id, haul)
		WorldData.set_city_citizen_task_phase(
			citizen_id,
			WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING
		)
		return _attempt_pickup(
			city_world,
			citizen_id,
			citizen,
			current_task,
			haul,
			path_requests_remaining
		)

	haul["phase"] = WorldData.CITY_CITIZEN_HAUL_PHASE_PENDING_SOURCE
	WorldData.set_city_citizen_current_haul(citizen_id, haul)
	WorldData.set_city_citizen_task_phase(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_PHASE_PENDING
	)
	return _advance_pending_source(
		city_world,
		citizen_id,
		citizen,
		current_task,
		haul,
		path_requests_remaining
	)


static func _attempt_pickup(
	city_world: WorldData,
	citizen_id: int,
	citizen: Dictionary,
	current_task: Dictionary,
	haul: Dictionary,
	path_requests_remaining: int
) -> int:
	if WorldData.get_city_citizen_haul_cargo_amount(citizen_id) > 0:
		haul["phase"] = (
			WorldData.CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION
		)
		WorldData.set_city_citizen_current_haul(citizen_id, haul)
		return _advance_pending_destination(
			city_world,
			citizen_id,
			citizen,
			current_task,
			haul,
			path_requests_remaining
		)

	var raw_current_tile = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var source: Dictionary = haul.get("source", {})
	var source_access_tiles := _get_endpoint_access_tiles(
		city_world,
		source
	)

	if (
		not raw_current_tile is Vector2i
		or not source_access_tiles.has(raw_current_tile)
	):
		haul["phase"] = WorldData.CITY_CITIZEN_HAUL_PHASE_PENDING_SOURCE
		WorldData.set_city_citizen_current_haul(citizen_id, haul)
		return path_requests_remaining

	var resource := str(
		haul.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var source_access_purpose := str(
		haul.get(
			"source_access_purpose",
			WorldData.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var source_object := _get_endpoint_object(source)

	if not WorldData.city_object_can_provide_haul_resource(
		source_object,
		resource,
		source_access_purpose
	):
		_finish_haul_without_pickup(citizen_id, current_task)
		return path_requests_remaining

	var amount_to_pick_up := mini(
		maxi(int(haul.get("requested_amount", 0)), 0),
		mini(
			WorldData.get_city_object_stored_resource_amount(
				source_object,
				resource
			),
			WorldData.get_city_citizen_available_haul_capacity(
				citizen_id
			)
		)
	)

	if amount_to_pick_up <= 0:
		_finish_haul_without_pickup(citizen_id, current_task)
		return path_requests_remaining

	# Recheck reachable room at the exact pickup moment. Without reservations,
	# another citizen may have filled the originally selected destination.
	if path_requests_remaining <= 0:
		return path_requests_remaining

	path_requests_remaining -= 1
	var destination_result := find_nearest_eligible_destination({
		"city_world": city_world,
		"start_tile": raw_current_tile,
		"citizen_id": citizen_id,
		"resource_type": resource,
		"destination_access_purpose": str(
			haul.get(
				"destination_access_purpose",
				WorldData.CONTAINER_HAUL_PURPOSE_NONE
			)
		),
	})

	if destination_result.is_empty():
		_finish_haul_without_pickup(citizen_id, current_task)
		return path_requests_remaining

	var picked_up_amount := _pickup_from_endpoint(
		citizen_id,
		source,
		resource,
		amount_to_pick_up,
		source_access_purpose
	)

	if picked_up_amount <= 0:
		_finish_haul_without_pickup(citizen_id, current_task)
		return path_requests_remaining

	haul["destination"] = destination_result.get(
		"endpoint",
		CityCitizens.make_city_citizen_haul_endpoint()
	)
	haul["destination_tile"] = destination_result.get(
		"destination_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	haul["phase"] = (
		WorldData.CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION
	)
	WorldData.set_city_citizen_current_haul(citizen_id, haul)

	return _begin_destination_with_result(
		city_world,
		citizen_id,
		current_task,
		haul,
		destination_result,
		path_requests_remaining
	)


static func _advance_pending_destination(
	city_world: WorldData,
	citizen_id: int,
	citizen: Dictionary,
	current_task: Dictionary,
	haul: Dictionary,
	path_requests_remaining: int
) -> int:
	var cargo := WorldData.get_city_citizen_haul_cargo(
		citizen_id
	)
	var cargo_amount := maxi(
		int(cargo.get("amount", 0)),
		0
	)

	if cargo_amount <= 0:
		_complete_haul(citizen_id, current_task)
		return path_requests_remaining

	var raw_current_tile = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not raw_current_tile is Vector2i:
		_set_haul_blocked(citizen_id, haul)
		return path_requests_remaining

	if path_requests_remaining <= 0:
		return path_requests_remaining

	path_requests_remaining -= 1
	var destination_result := find_nearest_eligible_destination({
		"city_world": city_world,
		"start_tile": raw_current_tile,
		"citizen_id": citizen_id,
		"resource_type": str(
			cargo.get("resource_type", WorldData.RESOURCE_NONE)
		),
		"destination_access_purpose": str(
			haul.get(
				"destination_access_purpose",
				WorldData.CONTAINER_HAUL_PURPOSE_NONE
			)
		),
	})

	if destination_result.is_empty():
		_set_haul_blocked(citizen_id, haul)
		return path_requests_remaining

	return _begin_destination_with_result(
		city_world,
		citizen_id,
		current_task,
		haul,
		destination_result,
		path_requests_remaining
	)


static func _begin_destination_with_result(
	city_world: WorldData,
	citizen_id: int,
	current_task: Dictionary,
	haul: Dictionary,
	destination_result: Dictionary,
	path_requests_remaining: int
) -> int:
	var raw_path = destination_result.get("path", [])
	var raw_destination_tile = destination_result.get(
		"destination_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var raw_destination = destination_result.get(
		"endpoint",
		{}
	)

	if (
		not raw_path is Array
		or not raw_destination_tile is Vector2i
		or not raw_destination is Dictionary
	):
		_set_haul_blocked(citizen_id, haul)
		return path_requests_remaining

	var movement_path: Array = raw_path
	var destination_tile: Vector2i = raw_destination_tile

	haul["destination"] = (
		CityCitizens.make_city_citizen_haul_endpoint(
			raw_destination
		)
	)
	haul["destination_tile"] = destination_tile
	WorldData.set_city_citizen_task_activity_state({
		"citizen_id": citizen_id,
		"target_tile": destination_tile,
	})

	if movement_path.size() <= 1:
		haul["phase"] = WorldData.CITY_CITIZEN_HAUL_PHASE_DEPOSITING
		WorldData.set_city_citizen_current_haul(citizen_id, haul)
		WorldData.set_city_citizen_task_phase(
			citizen_id,
			WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING
		)
		return _deposit_and_retarget(
			city_world,
			citizen_id,
			current_task,
			haul,
			path_requests_remaining
		)

	haul["phase"] = (
		WorldData.CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_DESTINATION
	)
	WorldData.set_city_citizen_current_haul(citizen_id, haul)

	if not WorldData.assign_city_citizen_movement_order(
		citizen_id,
		movement_path
	):
		_set_haul_blocked(citizen_id, haul)
		return path_requests_remaining

	WorldData.set_city_citizen_task_phase(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_PHASE_TRAVELING
	)
	return path_requests_remaining


static func _advance_traveling_to_destination(
	city_world: WorldData,
	citizen_id: int,
	citizen: Dictionary,
	current_task: Dictionary,
	haul: Dictionary,
	path_requests_remaining: int
) -> int:
	var movement_state := str(
		citizen.get(
			"movement_state",
			WorldData.CITY_CITIZEN_MOVEMENT_STATE_IDLE
		)
	)

	if movement_state == WorldData.CITY_CITIZEN_MOVEMENT_STATE_MOVING:
		return path_requests_remaining

	if movement_state == WorldData.CITY_CITIZEN_MOVEMENT_STATE_BLOCKED:
		WorldData.cancel_city_citizen_movement(citizen_id)
		haul["phase"] = WorldData.CITY_CITIZEN_HAUL_PHASE_RETARGETING
		haul["destination_tile"] = WorldData.INVALID_CITY_TILE_POSITION
		WorldData.set_city_citizen_current_haul(citizen_id, haul)
		return _advance_pending_destination(
			city_world,
			citizen_id,
			WorldData.get_city_citizen_by_id(citizen_id),
			current_task,
			haul,
			path_requests_remaining
		)

	var raw_current_tile = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var destination: Dictionary = haul.get("destination", {})
	var destination_access_tiles := _get_endpoint_access_tiles(
		city_world,
		destination
	)

	if (
		raw_current_tile is Vector2i
		and destination_access_tiles.has(raw_current_tile)
	):
		haul["phase"] = WorldData.CITY_CITIZEN_HAUL_PHASE_DEPOSITING
		haul["destination_tile"] = raw_current_tile
		WorldData.set_city_citizen_current_haul(citizen_id, haul)
		WorldData.set_city_citizen_task_phase(
			citizen_id,
			WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING
		)
		return _deposit_and_retarget(
			city_world,
			citizen_id,
			current_task,
			haul,
			path_requests_remaining
		)

	haul["phase"] = WorldData.CITY_CITIZEN_HAUL_PHASE_RETARGETING
	haul["destination_tile"] = WorldData.INVALID_CITY_TILE_POSITION
	WorldData.set_city_citizen_current_haul(citizen_id, haul)
	return _advance_pending_destination(
		city_world,
		citizen_id,
		citizen,
		current_task,
		haul,
		path_requests_remaining
	)


static func _deposit_and_retarget(
	city_world: WorldData,
	citizen_id: int,
	current_task: Dictionary,
	haul: Dictionary,
	path_requests_remaining: int
) -> int:
	var citizen := WorldData.get_city_citizen_by_id(citizen_id)
	var raw_current_tile = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var destination := CityCitizens.make_city_citizen_haul_endpoint()
	var raw_destination = haul.get("destination", {})

	if raw_destination is Dictionary:
		destination = CityCitizens.make_city_citizen_haul_endpoint(
			raw_destination
		)

	var destination_access_tiles := _get_endpoint_access_tiles(
		city_world,
		destination
	)

	if (
		not raw_current_tile is Vector2i
		or destination_access_tiles.is_empty()
	):
		_set_haul_blocked(citizen_id, haul)
		return path_requests_remaining

	if not destination_access_tiles.has(raw_current_tile):
		WorldData.cancel_city_citizen_movement(citizen_id)
		haul["phase"] = WorldData.CITY_CITIZEN_HAUL_PHASE_RETARGETING
		haul["destination_tile"] = WorldData.INVALID_CITY_TILE_POSITION
		WorldData.set_city_citizen_current_haul(citizen_id, haul)
		WorldData.set_city_citizen_task_phase(
			citizen_id,
			WorldData.CITY_CITIZEN_TASK_PHASE_PENDING
		)
		return _advance_pending_destination(
			city_world,
			citizen_id,
			WorldData.get_city_citizen_by_id(citizen_id),
			current_task,
			haul,
			path_requests_remaining
		)

	var cargo := WorldData.get_city_citizen_haul_cargo(
		citizen_id
	)
	var cargo_amount := maxi(
		int(cargo.get("amount", 0)),
		0
	)

	if cargo_amount <= 0:
		_complete_haul(citizen_id, current_task)
		return path_requests_remaining

	_deposit_to_endpoint(
		citizen_id,
		destination,
		str(cargo.get("resource_type", WorldData.RESOURCE_NONE)),
		cargo_amount,
		str(
			haul.get(
				"destination_access_purpose",
				WorldData.CONTAINER_HAUL_PURPOSE_NONE
			)
		)
	)

	if WorldData.get_city_citizen_haul_cargo_amount(citizen_id) <= 0:
		_complete_haul(citizen_id, current_task)
		return path_requests_remaining

	# A destination may have filled while the citizen was walking. Anything
	# that fit stays deposited; the remainder remains cargo and is retargeted.
	haul["phase"] = WorldData.CITY_CITIZEN_HAUL_PHASE_RETARGETING
	haul["destination_tile"] = WorldData.INVALID_CITY_TILE_POSITION
	WorldData.set_city_citizen_current_haul(citizen_id, haul)
	WorldData.set_city_citizen_task_phase(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_PHASE_PENDING
	)
	return _advance_pending_destination(
		city_world,
		citizen_id,
		WorldData.get_city_citizen_by_id(citizen_id),
		current_task,
		haul,
		path_requests_remaining
	)


static func _pickup_from_endpoint(
	citizen_id: int,
	endpoint: Dictionary,
	resource: String,
	requested_amount: int,
	withdrawal_purpose: String
) -> int:
	var city_object := _get_endpoint_object(endpoint)

	if not WorldData.city_object_can_provide_haul_resource(
		city_object,
		resource,
		withdrawal_purpose
	):
		return 0

	var amount_to_remove := mini(
		requested_amount,
		mini(
			WorldData.get_city_object_stored_resource_amount(
				city_object,
				resource
			),
			WorldData.get_city_citizen_available_haul_capacity(
				citizen_id
			)
		)
	)

	if amount_to_remove <= 0:
		return 0

	var object_id := int(city_object.get("id", -1))
	var removed_amount := (
		WorldData.remove_resource_from_city_object_storage(
			object_id,
			resource,
			amount_to_remove
		)
	)

	if removed_amount <= 0:
		return 0

	var final_cargo_amount := WorldData.set_city_citizen_haul_cargo(
		citizen_id,
		resource,
		removed_amount
	)

	if final_cargo_amount == removed_amount:
		return removed_amount

	# This rollback should be unreachable after prevalidation, but it keeps a
	# failed cross-container mutation conservative rather than deleting goods.
	WorldData.set_city_citizen_haul_cargo(
		citizen_id,
		resource,
		0
	)
	var restored_amount := WorldData.add_resource_to_city_object_storage(
		object_id,
		resource,
		removed_amount
	)

	if restored_amount != removed_amount:
		push_error(
			"Atomic haul pickup rollback failed for resource "
			+ resource
			+ "."
		)

	return 0


static func _deposit_to_endpoint(
	citizen_id: int,
	endpoint: Dictionary,
	resource: String,
	requested_amount: int,
	deposit_purpose: String
) -> int:
	var city_object := _get_endpoint_object(endpoint)

	if not WorldData.city_object_can_accept_haul_resource(
		city_object,
		resource,
		deposit_purpose,
		false
	):
		return 0

	var cargo_amount := (
		WorldData.get_city_citizen_haul_cargo_amount(citizen_id)
	)
	var amount_to_deposit := mini(
		requested_amount,
		cargo_amount
	)

	if amount_to_deposit <= 0:
		return 0

	var object_id := int(city_object.get("id", -1))
	var accepted_amount := WorldData.add_resource_to_city_object_storage(
		object_id,
		resource,
		amount_to_deposit
	)

	if accepted_amount <= 0:
		return 0

	var expected_remaining := cargo_amount - accepted_amount
	var final_remaining := WorldData.set_city_citizen_haul_cargo(
		citizen_id,
		resource,
		expected_remaining
	)

	if final_remaining == expected_remaining:
		return accepted_amount

	var removed_from_destination := (
		WorldData.remove_resource_from_city_object_storage(
			object_id,
			resource,
			accepted_amount
		)
	)
	WorldData.set_city_citizen_haul_cargo(
		citizen_id,
		resource,
		cargo_amount
	)

	if removed_from_destination != accepted_amount:
		push_error(
			"Atomic haul deposit rollback failed for resource "
			+ resource
			+ "."
		)

	return 0


static func _complete_haul(
	citizen_id: int,
	current_task: Dictionary
) -> void:
	if WorldData.get_city_citizen_haul_cargo_amount(citizen_id) > 0:
		return

	WorldData.cancel_city_citizen_movement(citizen_id)
	WorldData.set_city_citizen_current_haul(
		citizen_id,
		CityCitizens.make_city_citizen_haul()
	)
	WorldData.clear_city_citizen_task(
		citizen_id,
		str(
			current_task.get(
				"source",
				WorldData.CITY_CITIZEN_TASK_SOURCE_NONE
			)
		)
	)


static func _finish_haul_without_pickup(
	citizen_id: int,
	current_task: Dictionary
) -> void:
	if WorldData.get_city_citizen_haul_cargo_amount(citizen_id) > 0:
		return

	_complete_haul(citizen_id, current_task)


static func _set_haul_blocked(
	citizen_id: int,
	haul: Dictionary
) -> void:
	WorldData.cancel_city_citizen_movement(citizen_id)
	haul["phase"] = WorldData.CITY_CITIZEN_HAUL_PHASE_BLOCKED
	WorldData.set_city_citizen_current_haul(citizen_id, haul)
	WorldData.set_city_citizen_task_activity_state({
		"citizen_id": citizen_id,
		"target_tile": WorldData.INVALID_CITY_TILE_POSITION,
		"previous_target_tile": WorldData.INVALID_CITY_TILE_POSITION,
		"next_action_world_minute": (
			SimulationClock.absolute_world_minutes
			+ BLOCKED_HAUL_RETRY_DELAY_MINUTES
		),
		"relocation_count": 0,
	})
	WorldData.set_city_citizen_task_phase(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_PHASE_BLOCKED
	)


static func _prepare_blocked_haul_retry(
	citizen_id: int,
	current_task: Dictionary,
	has_cargo: bool
) -> bool:
	var retry_world_minute := int(
		current_task.get(
			"next_action_world_minute",
			WorldData.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
		)
	)

	if (
		retry_world_minute
		== WorldData.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
	):
		_set_haul_blocked(
			citizen_id,
			WorldData.get_city_citizen_current_haul(citizen_id)
		)
		return false

	if SimulationClock.absolute_world_minutes < retry_world_minute:
		return false

	WorldData.cancel_city_citizen_movement(citizen_id)
	var haul := WorldData.get_city_citizen_current_haul(
		citizen_id
	)

	if has_cargo:
		haul["phase"] = WorldData.CITY_CITIZEN_HAUL_PHASE_RETARGETING
		haul["destination_tile"] = WorldData.INVALID_CITY_TILE_POSITION
	else:
		haul["phase"] = WorldData.CITY_CITIZEN_HAUL_PHASE_PENDING_SOURCE
		haul["source_tile"] = WorldData.INVALID_CITY_TILE_POSITION

	WorldData.set_city_citizen_current_haul(citizen_id, haul)
	WorldData.set_city_citizen_task_activity_state({
		"citizen_id": citizen_id,
		"target_tile": WorldData.INVALID_CITY_TILE_POSITION,
		"previous_target_tile": WorldData.INVALID_CITY_TILE_POSITION,
		"next_action_world_minute": (
			WorldData.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
		),
		"relocation_count": 0,
	})
	WorldData.set_city_citizen_task_phase(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_PHASE_PENDING
	)
	return true


static func _get_endpoint_object(
	endpoint: Dictionary
) -> Dictionary:
	if (
		str(
			endpoint.get(
				"kind",
				WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
			)
		)
		!= WorldData
		.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER
	):
		return {}

	return WorldData.get_city_object_by_id(
		int(endpoint.get("id", -1))
	)


static func _get_city_wide_path_expansion_limit(
	city_world: WorldData
) -> int:
	if city_world == null:
		return 1

	# A full-map upper bound keeps reachability independent of distance. Each
	# city tile can be closed at most once by the navigation search.
	return maxi(city_world.width * city_world.height, 1)


static func _get_endpoint_access_tiles(
	city_world: WorldData,
	endpoint: Dictionary
) -> Array:
	var city_object := _get_endpoint_object(endpoint)

	if city_object.is_empty():
		return []

	return WorldData.get_city_object_access_tiles(
		city_world,
		city_object
	)

