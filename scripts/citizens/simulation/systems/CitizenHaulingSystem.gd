extends RefCounted
class_name CitizenHaulingSystem

# File responsibility: Haul task construction, routing, reservation use, pickup, delivery, and recovery.
# Navigation regions are organizational only; they do not define runtime ownership.

const CityNavigationSystemScript = preload(
	"res://scripts/city/simulation/systems/CityNavigationSystem.gd"
)
const CityResourceMatcherScript = preload(
	"res://scripts/city/simulation/systems/CityResourceMatcher.gd"
)

const EXACT_DESTINATION_HEURISTIC_WEIGHT: int = 1
const BLOCKED_HAUL_RETRY_DELAY_MINUTES: int = 30

# This system executes an already-decided haul. It does not decide whether a
# citizen ought to haul, produce resources, render markers, or expose UI.
# Endpoint dispatch is intentionally centralized so future ground piles or
# other container kinds can be added without rewriting the state machine.


static func city_citizen_is_hauling(citizen_id: int) -> bool:
	if (
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(
			citizen_id
		) > 0
	):
		return true

	return (
		str(
			CityCitizenTaskRuntimeSystem.get_city_citizen_current_haul(
				citizen_id
			).get(
				"phase",
				CityCitizens.CITY_CITIZEN_HAUL_PHASE_NONE
			)
		)
		!= CityCitizens.CITY_CITIZEN_HAUL_PHASE_NONE
	)


# Higher-priority interruptions must never strand physical haul cargo. Cargo is
# atomically converted into one mono-resource ground pile per carried resource,
# reservations and movement are released, and the interrupted task is cleared.
#region Priority Interrupt Cargo Handling

static func drop_citizen_haul_cargo_for_priority_interrupt(
	city_world: WorldData,
	citizen_id: int,
	requesting_source: String = (
		CityCitizens.CITY_CITIZEN_TASK_SOURCE_PLAYER
	)
) -> bool:
	if city_world == null or citizen_id <= 0:
		return false

	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)

	if citizen.is_empty() or not bool(citizen.get("alive", false)):
		return false

	var cargo_resources := (
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_resources(citizen_id)
	)
	var cargo_amount := (
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id)
	)
	var drop_tile := CityCitizens.INVALID_CITY_TILE_POSITION
	var added_placements_by_resource: Dictionary = {}

	if cargo_amount > 0:
		var raw_current_tile = citizen.get(
			"city_tile_position",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)

		if not raw_current_tile is Vector2i:
			return false

		drop_tile = _find_nearest_valid_ground_pile_drop_tile(
			city_world,
			citizen_id,
			raw_current_tile
		)

		if drop_tile == CityCitizens.INVALID_CITY_TILE_POSITION:
			return false

		var resource_names: Array = cargo_resources.keys()
		resource_names.sort()

		for raw_resource in resource_names:
			var resource := str(raw_resource)
			var amount := maxi(
				int(cargo_resources.get(resource, 0)),
				0
			)

			if amount <= 0:
				continue

			var add_result := (
				CityLogisticsSystem.add_resource_to_city_ground_piles_with_result({
					"tile_position": drop_tile,
					"resource": resource,
					"amount_delta": amount,
				})
			)
			var added_amount := int(
				add_result.get("added_amount", 0)
			)

			if added_amount != amount:
				_rollback_interrupted_cargo_ground_piles(
					added_placements_by_resource
				)
				return false

			added_placements_by_resource[resource] = (
				add_result.get("placements", [])
			)

		if CityCitizenInventorySystem.set_city_citizen_haul_cargo_resources(
			citizen_id,
			{}
		) != 0:
			_rollback_interrupted_cargo_ground_piles(
				added_placements_by_resource
			)
			return false

	if not CityCitizenTaskRuntimeSystem.clear_city_citizen_task(
		citizen_id,
		requesting_source
	):
		if cargo_amount > 0:
			var restored_total := (
				CityCitizenInventorySystem.set_city_citizen_haul_cargo_resources(
					citizen_id,
					cargo_resources
				)
			)
			_rollback_interrupted_cargo_ground_piles(
				added_placements_by_resource
			)

			if restored_total != cargo_amount:
				push_error(
					"Failed to restore interrupted haul cargo after task "
					+ "clear rejection."
				)

		return false

	CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)
	CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(
		citizen_id,
		CityCitizens.make_city_citizen_haul()
	)
	return true


static func _find_nearest_valid_ground_pile_drop_tile(
	city_world: WorldData,
	citizen_id: int,
	origin_tile: Vector2i
) -> Vector2i:
	if CityLogisticsSystem.can_city_ground_pile_exist_at_tile(
		city_world,
		origin_tile
	):
		return origin_tile

	var maximum_radius := maxi(city_world.width, city_world.height)
	var city_wide_expansion_limit := maxi(
		city_world.width * city_world.height,
		1
	)

	for radius in range(1, maximum_radius + 1):
		var candidate_tiles: Array = []

		for offset_y in range(-radius, radius + 1):
			var offset_x_magnitude := radius - absi(offset_y)
			var candidate_x_offsets := [offset_x_magnitude]

			if offset_x_magnitude > 0:
				candidate_x_offsets.append(-offset_x_magnitude)

			for offset_x in candidate_x_offsets:
				var candidate_tile := (
					origin_tile + Vector2i(offset_x, offset_y)
				)

				if not CityLogisticsSystem.can_city_ground_pile_exist_at_tile(
					city_world,
					candidate_tile
				):
					continue

				candidate_tiles.append(candidate_tile)

		if candidate_tiles.is_empty():
			continue

		var path_result := (
			CityNavigationSystemScript.find_path_to_any_city_tile({
				"city_world": city_world,
				"start_tile": origin_tile,
				"destination_tiles": candidate_tiles,
				"max_expanded_nodes": city_wide_expansion_limit,
				"citizen_id": citizen_id,
				"heuristic_weight": EXACT_DESTINATION_HEURISTIC_WEIGHT
			})
		)

		if not bool(path_result.get("success", false)):
			continue

		var raw_destination_tile = path_result.get(
			"destination_tile",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)

		if raw_destination_tile is Vector2i:
			return raw_destination_tile

	return CityCitizens.INVALID_CITY_TILE_POSITION


static func _rollback_interrupted_cargo_ground_piles(
	placements_by_resource: Dictionary
) -> void:
	for raw_resource in placements_by_resource.keys():
		var resource := str(raw_resource)
		var placements = placements_by_resource.get(
			raw_resource,
			[]
		)

		if not CityLogisticsSystem.rollback_city_ground_pile_additions(
			resource,
			placements
		):
			push_error(
				"Interrupted cargo ground-pile rollback failed for "
				+ resource
				+ "."
			)


#endregion

#region Haul Task Request Construction

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
			CityCitizens.CITY_CITIZEN_HAUL_REASON_NONE
		)
	)
	var source_access_purpose := str(
		values.get(
			"source_access_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var destination_access_purpose := str(
		values.get(
			"destination_access_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE
		)
	)
	var task_source := str(
		values.get(
			"task_source",
			CityCitizens.CITY_CITIZEN_TASK_SOURCE_SCHEDULE
		)
	)
	var task_priority := int(values.get("task_priority", 0))
	var raw_current_tile = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if (
		citizen_id <= 0
		or not bool(citizen.get("alive", false))
		or not raw_current_tile is Vector2i
		or not CityResourceCatalog.is_city_resource_type(resource)
		or reason == CityCitizens.CITY_CITIZEN_HAUL_REASON_NONE
		or source_access_purpose
		== CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		or destination_access_purpose
		== CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		or task_priority
		<= CityCitizens.CITY_CITIZEN_TASK_PRIORITY_NONE
		or not CityCitizens.is_valid_city_citizen_task_source(
			task_source
		)
		or task_source == CityCitizens.CITY_CITIZEN_TASK_SOURCE_NONE
		or not CityCitizens.is_valid_city_citizen_haul_endpoint(
			source
		)
		or not CityCitizens.is_valid_city_citizen_haul_endpoint(
			requester
		)
	):
		return {}

	var current_tile: Vector2i = raw_current_tile
	var cargo_resources := (
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_resources(
			citizen_id
		)
	)
	var cargo_amount := (
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id)
	)
	var destination_result: Dictionary = {}
	var initial_phase: String = (
		CityCitizens.CITY_CITIZEN_HAUL_PHASE_PENDING_SOURCE
	)
	var source_tile: Vector2i = CityCitizens.INVALID_CITY_TILE_POSITION
	var selection_path: Array = []

	if cargo_amount > 0:
		requested_amount = maxi(requested_amount, cargo_amount)
		initial_phase = (
			CityCitizens.CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION
		)
		destination_result = CityResourceMatcherScript.find_nearest_eligible_destination_for_resources({
			"city_world": city_world,
			"start_tile": current_tile,
			"citizen_id": citizen_id,
			"resources": cargo_resources,
			"destination_access_purpose": (
				destination_access_purpose
			),
			"requested_amount": cargo_amount,
		})
	else:
		if not CityLogisticsSystem.city_haul_endpoint_can_provide_resource({
			"endpoint": source,
			"resource": resource,
			"withdrawal_purpose": source_access_purpose,
			"require_unreserved_amount": true,
		}):
			return {}

		var remaining_capacity := (
			CityCitizenInventorySystem.get_city_citizen_available_haul_capacity(
				citizen_id
			)
		)
		var source_amount := (
			CityLogisticsSystem.get_city_haul_endpoint_unreserved_resource_amount(
				source,
				resource
			)
		)

		requested_amount = mini(
			requested_amount,
			mini(remaining_capacity, source_amount)
		)

		if requested_amount <= 0:
			return {}

		var source_access_tiles := CityResourceMatcherScript.get_haul_endpoint_access_tiles(
			city_world,
			source
		)

		if source_access_tiles.is_empty():
			return {}

		var source_path_result := (
			CityNavigationSystemScript.find_path_to_any_city_tile({
				"city_world": city_world,
				"start_tile": current_tile,
				"destination_tiles": source_access_tiles,
				"max_expanded_nodes": CityNavigationSystemScript.get_city_wide_path_expansion_limit(city_world),
				"citizen_id": citizen_id,
				"heuristic_weight": EXACT_DESTINATION_HEURISTIC_WEIGHT
			})
		)

		if not bool(source_path_result.get("success", false)):
			return {}

		var raw_source_path = source_path_result.get("path", [])

		if not raw_source_path is Array:
			return {}

		var raw_source_tile = source_path_result.get(
			"destination_tile",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)

		if not raw_source_tile is Vector2i:
			return {}

		selection_path = raw_source_path.duplicate()
		source_tile = raw_source_tile
		destination_result = CityResourceMatcherScript.find_nearest_eligible_destination({
			"city_world": city_world,
			"start_tile": source_tile,
			"citizen_id": citizen_id,
			"resource_type": resource,
			"destination_access_purpose": (
				destination_access_purpose
			),
			"requested_amount": requested_amount,
		})

		# No resource is removed unless a reachable destination currently has
		# room. The worker may proceed to their next scheduled activity.
		if destination_result.is_empty():
			return {}

		requested_amount = mini(
			requested_amount,
			maxi(
				int(
					destination_result.get(
						"available_amount",
						0
					)
				),
				0
			)
		)

		if requested_amount <= 0:
			return {}

	var destination := (
		CityCitizens.make_city_citizen_haul_endpoint()
	)
	var destination_tile: Vector2i = (
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if not destination_result.is_empty():
		destination = destination_result.get(
			"endpoint",
			destination
		)
		destination_tile = destination_result.get(
			"destination_tile",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)
	elif cargo_amount > 0:
		initial_phase = CityCitizens.CITY_CITIZEN_HAUL_PHASE_BLOCKED

	var source_endpoint_id := int(source.get("id", -1))

	if source_endpoint_id <= 0:
		return {}

	return {
		"kind": CityCitizens.CITY_CITIZEN_TASK_KIND_HAUL,
		"source": task_source,
		"priority": task_priority,
		"target_object_id": source_endpoint_id,
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
			"allow_ground_pile_pickup_chaining": (
				reason
				== CityCitizens.CITY_CITIZEN_HAUL_REASON_GROUND_PILE_CLEANUP
			),
		}),
		"selection_path": selection_path,
	}


static func make_directed_haul_task_request(
	values: Dictionary
) -> Dictionary:
	var raw_city_world = values.get("city_world")
	var raw_citizen = values.get("citizen", {})
	var raw_source = values.get("source", {})
	var raw_destination = values.get("destination", {})
	var raw_requester = values.get("requester", {})

	if (
		not raw_city_world is WorldData
		or not raw_citizen is Dictionary
		or not raw_source is Dictionary
		or not raw_destination is Dictionary
		or not raw_requester is Dictionary
	):
		return {}

	var city_world: WorldData = raw_city_world
	var citizen: Dictionary = raw_citizen
	var source := CityCitizens.make_city_citizen_haul_endpoint(
		raw_source
	)
	var destination := CityCitizens.make_city_citizen_haul_endpoint(
		raw_destination
	)
	var requester := CityCitizens.make_city_citizen_haul_endpoint(
		raw_requester
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
			CityCitizens.CITY_CITIZEN_HAUL_REASON_NONE
		)
	)
	var source_access_purpose := str(
		values.get(
			"source_access_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var destination_access_purpose := str(
		values.get(
			"destination_access_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var task_source := str(
		values.get(
			"task_source",
			CityCitizens.CITY_CITIZEN_TASK_SOURCE_AUTONOMY
		)
	)
	var task_priority := int(values.get("task_priority", 0))
	var raw_current_tile = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if (
		citizen_id <= 0
		or not bool(citizen.get("alive", false))
		or not raw_current_tile is Vector2i
		or CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id) > 0
		or not CityResourceCatalog.is_city_resource_type(resource)
		or requested_amount <= 0
		or reason == CityCitizens.CITY_CITIZEN_HAUL_REASON_NONE
		or source_access_purpose
		== CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		or destination_access_purpose
		== CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		or task_priority <= CityCitizens.CITY_CITIZEN_TASK_PRIORITY_NONE
		or not CityCitizens.is_valid_city_citizen_task_source(task_source)
		or task_source == CityCitizens.CITY_CITIZEN_TASK_SOURCE_NONE
		or not CityCitizens.is_valid_city_citizen_haul_endpoint(source)
		or not CityCitizens.is_valid_city_citizen_haul_endpoint(
			destination
		)
		or not CityCitizens.is_valid_city_citizen_haul_endpoint(requester)
		or not CityLogisticsSystem.city_haul_endpoint_can_provide_resource({
			"endpoint": source,
			"resource": resource,
			"withdrawal_purpose": source_access_purpose,
			"require_unreserved_amount": true,
		})
		or not CityLogisticsSystem.city_haul_endpoint_can_accept_resource({
			"endpoint": destination,
			"resource": resource,
			"deposit_purpose": destination_access_purpose,
			"require_unreserved_space": true,
		})
	):
		return {}

	requested_amount = mini(
		requested_amount,
		mini(
			CityCitizenInventorySystem.get_city_citizen_available_haul_capacity(
				citizen_id
			),
			mini(
				CityLogisticsSystem.get_city_haul_endpoint_unreserved_resource_amount(
					source,
					resource
				),
				CityLogisticsSystem.get_city_haul_endpoint_unreserved_destination_space(
					destination
				)
			)
		)
	)

	if requested_amount <= 0:
		return {}

	var current_tile: Vector2i = raw_current_tile
	var source_access_tiles := CityResourceMatcherScript.get_haul_endpoint_access_tiles(
		city_world,
		source
	)

	if source_access_tiles.is_empty():
		return {}

	var source_path_result := (
		CityNavigationSystemScript.find_path_to_any_city_tile({
			"city_world": city_world,
			"start_tile": current_tile,
			"destination_tiles": source_access_tiles,
			"max_expanded_nodes": CityNavigationSystemScript.get_city_wide_path_expansion_limit(city_world),
			"citizen_id": citizen_id,
			"heuristic_weight": EXACT_DESTINATION_HEURISTIC_WEIGHT
		})
	)

	if not bool(source_path_result.get("success", false)):
		return {}

	var raw_source_path = source_path_result.get("path", [])

	if not raw_source_path is Array:
		return {}

	var raw_source_tile = source_path_result.get(
		"destination_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if not raw_source_tile is Vector2i:
		return {}

	var source_tile: Vector2i = raw_source_tile
	var destination_result := CityResourceMatcherScript.make_destination_result_for_endpoint({
		"city_world": city_world,
		"start_tile": source_tile,
		"citizen_id": citizen_id,
		"resource_type": resource,
		"destination": destination,
		"destination_access_purpose": destination_access_purpose,
		"requested_amount": requested_amount,
	})

	if destination_result.is_empty():
		return {}

	requested_amount = mini(
		requested_amount,
		maxi(
			int(destination_result.get("available_amount", 0)),
			0
		)
	)

	if requested_amount <= 0:
		return {}

	return {
		"kind": CityCitizens.CITY_CITIZEN_TASK_KIND_HAUL,
		"source": task_source,
		"priority": task_priority,
		"target_object_id": int(source.get("id", -1)),
		"player_locked": false,
		"haul": CityCitizens.make_city_citizen_haul({
			"source": source,
			"destination": destination,
			"resource_type": resource,
			"requested_amount": requested_amount,
			"reason": reason,
			"requester": requester,
			"source_access_purpose": source_access_purpose,
			"destination_access_purpose": destination_access_purpose,
			"phase": CityCitizens.CITY_CITIZEN_HAUL_PHASE_PENDING_SOURCE,
			"source_tile": source_tile,
			"destination_tile": destination_result.get(
				"destination_tile",
				CityCitizens.INVALID_CITY_TILE_POSITION
			),
		}),
		"selection_path_cost": (
			int(source_path_result.get("path_cost", 0))
			+ int(destination_result.get("path_cost", 0))
		),
		"selection_path": raw_source_path.duplicate(),
	}


#endregion

#region Haul Task State Machine

static func advance_haul_task(
	city_world: WorldData,
	values: Dictionary
) -> int:
	var citizen_id := int(values.get("citizen_id", -1))
	var citizen: Dictionary = values.get("citizen", {})
	var current_task: Dictionary = values.get("current_task", {})
	var path_requests_remaining := maxi(
		int(values.get("path_requests_remaining", 0)),
		0
	)
	if (
		city_world == null
		or citizen_id <= 0
		or citizen.is_empty()
		or str(current_task.get("kind", ""))
		!= CityCitizens.CITY_CITIZEN_TASK_KIND_HAUL
	):
		return path_requests_remaining

	var haul := CityCitizenTaskRuntimeSystem.get_city_citizen_current_haul(
		citizen_id
	)
	var cargo_amount := (
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id)
	)
	var haul_resource := str(
		haul.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var haul_phase := str(
		haul.get(
			"phase",
			CityCitizens.CITY_CITIZEN_HAUL_PHASE_NONE
		)
	)

	if not CityResourceCatalog.is_city_resource_type(haul_resource):
		_finish_haul_without_pickup(citizen_id, current_task)
		return path_requests_remaining

	if cargo_amount > 0:
		var reservation_id := int(
			haul.get(
				"reservation_id",
				CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
			)
		)
		var reservation := CityLogisticsSystem.get_city_haul_reservation(
			reservation_id
		)
		var has_reserved_next_source := (
			bool(
				haul.get(
					"allow_ground_pile_pickup_chaining",
					false
				)
			)
			and not reservation.is_empty()
			and int(
				reservation.get("source_reserved_amount", 0)
			) > 0
		)

		if (
			(
				haul_phase
				== CityCitizens.CITY_CITIZEN_HAUL_PHASE_PENDING_SOURCE
				or haul_phase
				== CityCitizens.CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_SOURCE
				or haul_phase
				== CityCitizens.CITY_CITIZEN_HAUL_PHASE_PICKING_UP
			)
			and not has_reserved_next_source
		):
			CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)
			haul["phase"] = (
				CityCitizens.CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION
			)
			CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(
				citizen_id,
				haul
			)
			haul_phase = (
				CityCitizens.CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION
			)
	elif (
		haul_phase
		== CityCitizens.CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION
		or haul_phase
		== CityCitizens.CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_DESTINATION
		or haul_phase == CityCitizens.CITY_CITIZEN_HAUL_PHASE_DEPOSITING
		or haul_phase == CityCitizens.CITY_CITIZEN_HAUL_PHASE_RETARGETING
	):
		_finish_haul_without_pickup(citizen_id, current_task)
		return path_requests_remaining

	if haul_phase == CityCitizens.CITY_CITIZEN_HAUL_PHASE_BLOCKED:
		if not _prepare_blocked_haul_retry(
			citizen_id,
			current_task,
			cargo_amount > 0
		):
			return path_requests_remaining

		haul = CityCitizenTaskRuntimeSystem.get_city_citizen_current_haul(
			citizen_id
		)
		haul_phase = str(
			haul.get(
				"phase",
				CityCitizens.CITY_CITIZEN_HAUL_PHASE_NONE
			)
		)
		citizen = CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
		current_task = CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(
			citizen_id
		)

	values["citizen_id"] = citizen_id
	values["citizen"] = citizen
	values["current_task"] = current_task
	values["haul"] = haul
	values["path_requests_remaining"] = path_requests_remaining

	match haul_phase:
		CityCitizens.CITY_CITIZEN_HAUL_PHASE_PENDING_SOURCE:
			return _advance_pending_source(
				city_world,
				values
			)

		CityCitizens.CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_SOURCE:
			return _advance_traveling_to_source(
				city_world,
				values
			)

		CityCitizens.CITY_CITIZEN_HAUL_PHASE_PICKING_UP:
			return _attempt_pickup(
				city_world,
				values
			)

		CityCitizens.CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION:
			return _advance_pending_destination(
				city_world,
				values
			)

		CityCitizens.CITY_CITIZEN_HAUL_PHASE_RETARGETING:
			return _advance_pending_destination(
				city_world,
				values
			)

		CityCitizens.CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_DESTINATION:
			return _advance_traveling_to_destination(
				city_world,
				values
			)

		CityCitizens.CITY_CITIZEN_HAUL_PHASE_DEPOSITING:
			return _deposit_and_retarget(
				city_world,
				values
			)

		_:
			_set_haul_blocked(citizen_id, haul)

	return path_requests_remaining


static func _advance_pending_source(
	city_world: WorldData,
	values: Dictionary
) -> int:
	var citizen_id := int(values.get("citizen_id", -1))
	var citizen: Dictionary = values.get("citizen", {})
	var current_task: Dictionary = values.get("current_task", {})
	var haul: Dictionary = values.get("haul", {})
	var path_requests_remaining := maxi(
		int(values.get("path_requests_remaining", 0)),
		0
	)
	var source: Dictionary = haul.get("source", {})
	var resource := str(
		haul.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var source_access_purpose := str(
		haul.get(
			"source_access_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var reservation_id := int(
		haul.get(
			"reservation_id",
			CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
		)
	)
	var reservation := CityLogisticsSystem.get_city_haul_reservation(
		reservation_id
	)

	if (
		reservation.is_empty()
		or int(reservation.get("citizen_id", -1)) != citizen_id
		or not CityLogisticsSystem.city_citizen_haul_endpoints_match(
			reservation.get("source", {}),
			source
		)
		or int(
			reservation.get("source_reserved_amount", 0)
		) <= 0
	):
		if CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id) > 0:
			haul["phase"] = (
				CityCitizens.CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION
			)
			CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, haul)
			return _advance_pending_destination(
				city_world,
				values
			)

		_finish_haul_without_pickup(citizen_id, current_task)
		return path_requests_remaining

	if not CityLogisticsSystem.city_haul_endpoint_can_provide_resource({
		"endpoint": source,
		"resource": resource,
		"withdrawal_purpose": source_access_purpose,
		"require_unreserved_amount": true,
		"excluding_reservation_id": reservation_id,
	}):
		if CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id) > 0:
			haul["phase"] = (
				CityCitizens.CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION
			)
			CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, haul)
			return _advance_pending_destination(
				city_world,
				values
			)

		_finish_haul_without_pickup(citizen_id, current_task)
		return path_requests_remaining

	if (
		CityCitizenInventorySystem.get_city_citizen_available_haul_capacity(
			citizen_id
		) <= 0
	):
		haul["phase"] = (
			CityCitizens.CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION
		)
		CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, haul)
		return _advance_pending_destination(city_world, values)

	var raw_current_tile = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var source_access_tiles := CityResourceMatcherScript.get_haul_endpoint_access_tiles(
		city_world,
		source
	)

	if not raw_current_tile is Vector2i or source_access_tiles.is_empty():
		_set_haul_blocked(citizen_id, haul)
		return path_requests_remaining

	var current_tile: Vector2i = raw_current_tile

	if source_access_tiles.has(current_tile):
		CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)
		haul["phase"] = CityCitizens.CITY_CITIZEN_HAUL_PHASE_PICKING_UP
		haul["source_tile"] = current_tile
		CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, haul)
		CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
			citizen_id,
			CityCitizens.CITY_CITIZEN_TASK_PHASE_PERFORMING
		)
		# Loading completes on the next task pass, after the citizen has
		# visibly reached the source access tile.
		return path_requests_remaining

	if path_requests_remaining <= 0:
		return path_requests_remaining

	path_requests_remaining -= 1
	var path_result := (
		CityNavigationSystemScript.find_path_to_any_city_tile({
			"city_world": city_world,
			"start_tile": current_tile,
			"destination_tiles": source_access_tiles,
			"max_expanded_nodes": CityNavigationSystemScript.get_city_wide_path_expansion_limit(city_world),
			"citizen_id": citizen_id,
			"heuristic_weight": CityNavigationSystem.HEURISTIC_WEIGHT
		})
	)

	if not bool(path_result.get("success", false)):
		_set_haul_blocked(citizen_id, haul)
		return path_requests_remaining

	var raw_path = path_result.get("path", [])
	var raw_destination_tile = path_result.get(
		"destination_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if not raw_path is Array or not raw_destination_tile is Vector2i:
		_set_haul_blocked(citizen_id, haul)
		return path_requests_remaining

	var movement_path: Array = raw_path
	var source_tile: Vector2i = raw_destination_tile

	haul["phase"] = (
		CityCitizens.CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_SOURCE
	)
	haul["source_tile"] = source_tile
	CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, haul)
	CityCitizenTaskRuntimeSystem.set_city_citizen_task_activity_state({
		"citizen_id": citizen_id,
		"target_tile": source_tile,
	})

	if movement_path.size() <= 1:
		haul["phase"] = CityCitizens.CITY_CITIZEN_HAUL_PHASE_PICKING_UP
		CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, haul)
		CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
			citizen_id,
			CityCitizens.CITY_CITIZEN_TASK_PHASE_PERFORMING
		)
		return path_requests_remaining

	if not CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order(
		citizen_id,
		movement_path
	):
		_set_haul_blocked(citizen_id, haul)
		return path_requests_remaining

	CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
		citizen_id,
		CityCitizens.CITY_CITIZEN_TASK_PHASE_TRAVELING
	)
	return path_requests_remaining


static func _advance_traveling_to_source(
	city_world: WorldData,
	values: Dictionary
) -> int:
	var citizen_id := int(values.get("citizen_id", -1))
	var citizen: Dictionary = values.get("citizen", {})
	var current_task: Dictionary = values.get("current_task", {})
	var haul: Dictionary = values.get("haul", {})
	var path_requests_remaining := maxi(
		int(values.get("path_requests_remaining", 0)),
		0
	)
	var movement_state := str(
		citizen.get(
			"movement_state",
			CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_IDLE
		)
	)

	if movement_state == CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_MOVING:
		return path_requests_remaining

	if movement_state == CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_BLOCKED:
		_set_haul_blocked(citizen_id, haul)
		return path_requests_remaining

	var raw_current_tile = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var source: Dictionary = haul.get("source", {})
	var source_access_tiles := CityResourceMatcherScript.get_haul_endpoint_access_tiles(
		city_world,
		source
	)

	if (
		raw_current_tile is Vector2i
		and source_access_tiles.has(raw_current_tile)
	):
		haul["phase"] = CityCitizens.CITY_CITIZEN_HAUL_PHASE_PICKING_UP
		haul["source_tile"] = raw_current_tile
		CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, haul)
		CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
			citizen_id,
			CityCitizens.CITY_CITIZEN_TASK_PHASE_PERFORMING
		)
		return path_requests_remaining

	haul["phase"] = CityCitizens.CITY_CITIZEN_HAUL_PHASE_PENDING_SOURCE
	CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, haul)
	CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
		citizen_id,
		CityCitizens.CITY_CITIZEN_TASK_PHASE_PENDING
	)
	return _advance_pending_source(
		city_world,
		values
	)


static func _attempt_pickup(
	city_world: WorldData,
	values: Dictionary
) -> int:
	var citizen_id := int(values.get("citizen_id", -1))
	var citizen: Dictionary = values.get("citizen", {})
	var current_task: Dictionary = values.get("current_task", {})
	var haul: Dictionary = values.get("haul", {})
	var path_requests_remaining := maxi(
		int(values.get("path_requests_remaining", 0)),
		0
	)
	var raw_current_tile = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var source: Dictionary = haul.get("source", {})
	var source_access_tiles := CityResourceMatcherScript.get_haul_endpoint_access_tiles(
		city_world,
		source
	)

	if (
		not raw_current_tile is Vector2i
		or not source_access_tiles.has(raw_current_tile)
	):
		haul["phase"] = CityCitizens.CITY_CITIZEN_HAUL_PHASE_PENDING_SOURCE
		CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, haul)
		return path_requests_remaining

	var resource := str(
		haul.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var source_access_purpose := str(
		haul.get(
			"source_access_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var reservation_id := int(
		haul.get(
			"reservation_id",
			CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
		)
	)
	var reservation := CityLogisticsSystem.get_city_haul_reservation(
		reservation_id
	)

	if (
		reservation.is_empty()
		or int(reservation.get("citizen_id", -1)) != citizen_id
		or not CityLogisticsSystem.city_citizen_haul_endpoints_match(
			reservation.get("source", {}),
			source
		)
		or str(
			reservation.get("resource_type", WorldData.RESOURCE_NONE)
		) != resource
	):
		_finish_haul_without_pickup(citizen_id, current_task)
		return path_requests_remaining

	if not CityLogisticsSystem.city_haul_endpoint_can_provide_resource({
		"endpoint": source,
		"resource": resource,
		"withdrawal_purpose": source_access_purpose,
		"require_unreserved_amount": true,
		"excluding_reservation_id": reservation_id,
	}):
		if CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id) > 0:
			haul["phase"] = (
				CityCitizens.CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION
			)
			CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, haul)
			return _advance_pending_destination(
				city_world,
				values
			)

		_finish_haul_without_pickup(citizen_id, current_task)
		return path_requests_remaining

	var amount_to_pick_up := mini(
		maxi(int(haul.get("requested_amount", 0)), 0),
		mini(
			maxi(
				int(
					reservation.get(
						"source_reserved_amount",
						0
					)
				),
				0
			),
			mini(
				CityLogisticsSystem.get_city_haul_endpoint_unreserved_resource_amount(
					source,
					resource,
					reservation_id
				),
				CityCitizenInventorySystem.get_city_citizen_available_haul_capacity(
					citizen_id
				)
			)
		)
	)

	amount_to_pick_up = mini(
		amount_to_pick_up,
		CityLogisticsSystem.get_city_haul_reservation_destination_resource_amount(
			reservation_id,
			resource
		)
	)

	if amount_to_pick_up <= 0:
		if CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id) > 0:
			haul["phase"] = (
				CityCitizens.CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION
			)
			CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, haul)
			return _advance_pending_destination(
				city_world,
				values
			)

		_finish_haul_without_pickup(citizen_id, current_task)
		return path_requests_remaining

	var picked_up_amount := _pickup_from_endpoint({
		"citizen_id": citizen_id,
		"endpoint": source,
		"resource_type": resource,
		"requested_amount": amount_to_pick_up,
		"withdrawal_purpose": source_access_purpose,
		"reservation_id": reservation_id,
	})

	if picked_up_amount <= 0:
		if CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id) > 0:
			haul["phase"] = (
				CityCitizens.CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION
			)
			CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, haul)
			return _advance_pending_destination(
				city_world,
				values
			)

		_finish_haul_without_pickup(citizen_id, current_task)
		return path_requests_remaining

	haul["pickup_stop_count"] = maxi(
		int(haul.get("pickup_stop_count", 0)),
		0
	) + 1

	values["haul"] = haul
	values["path_requests_remaining"] = path_requests_remaining
	return _continue_after_successful_pickup(city_world, values)


static func _continue_after_successful_pickup(
	city_world: WorldData,
	values: Dictionary
) -> int:
	var citizen_id := int(values.get("citizen_id", -1))
	var citizen: Dictionary = values.get("citizen", {})
	var current_task: Dictionary = values.get("current_task", {})
	var haul: Dictionary = values.get("haul", {})
	var path_requests_remaining := maxi(
		int(values.get("path_requests_remaining", 0)),
		0
	)
	var raw_current_tile = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var reservation_id := int(
		haul.get(
			"reservation_id",
			CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
		)
	)

	# Pickup is the hard-commitment boundary. Before extending an autonomous
	# pickup chain, let the configurable demand scorer decide whether cargo now
	# in hand should satisfy a stronger live demand instead. The current storage
	# route is scored as if it were adjacent, so only a genuinely higher policy
	# priority can interrupt efficient batch collection.
	var reservation := CityLogisticsSystem.get_city_haul_reservation(reservation_id)
	var current_destination_result: Dictionary = {}

	if (
		not reservation.is_empty()
		and int(reservation.get("destination_reserved_amount", 0)) > 0
	):
		current_destination_result = {
			"endpoint": reservation.get("destination", {}),
			"available_amount": int(
				reservation.get("destination_reserved_amount", 0)
			),
			"path_cost": 0,
		}

	var cargo_resources_after_pickup := (
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_resources(citizen_id)
	)
	var cargo_amount_after_pickup := (
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id)
	)
	var immediate_routing_result := (
		_try_route_cargo_to_best_resource_demand(
			city_world,
			{
				"citizen_id": citizen_id,
				"start_tile": raw_current_tile,
				"cargo_resources": cargo_resources_after_pickup,
				"cargo_amount": cargo_amount_after_pickup,
				"haul": haul,
				"current_destination_result": current_destination_result,
				"current_destination_access_purpose": str(
					haul.get(
						"destination_access_purpose",
						CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
					)
				),
				"current_destination_is_reserved": (
					not current_destination_result.is_empty()
				),
				"reservation_id": reservation_id,
				"path_requests_remaining": path_requests_remaining,
			}
		)
	)
	path_requests_remaining = int(
		immediate_routing_result.get(
			"path_requests_remaining",
			path_requests_remaining
		)
	)

	if bool(immediate_routing_result.get("routed", false)):
		var routed_haul = immediate_routing_result.get("haul", haul)
		var routed_destination_result = immediate_routing_result.get(
			"destination_result",
			{}
		)

		if routed_haul is Dictionary and routed_destination_result is Dictionary:
			haul = routed_haul
			haul["phase"] = (
				CityCitizens.CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION
			)
			CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, haul)
			CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
				citizen_id,
				CityCitizens.CITY_CITIZEN_TASK_PHASE_PENDING
			)
			values["haul"] = haul
			values["destination_result"] = routed_destination_result
			values["path_requests_remaining"] = path_requests_remaining
			return _begin_destination_with_result(city_world, values)

	if (
		bool(
			haul.get(
				"allow_ground_pile_pickup_chaining",
				false
			)
		)
		and CityCitizenInventorySystem.get_city_citizen_available_haul_capacity(
			citizen_id
		) > 0
	):
		var chain_result := _begin_next_ground_pile_pickup({
			"city_world": city_world,
			"citizen_id": citizen_id,
			"current_task": current_task,
			"haul": haul,
			"current_tile": raw_current_tile,
			"path_requests_remaining": path_requests_remaining,
		})
		path_requests_remaining = int(
			chain_result.get(
				"path_requests_remaining",
				path_requests_remaining
			)
		)

		if bool(chain_result.get("started", false)):
			return path_requests_remaining

	reservation = CityLogisticsSystem.get_city_haul_reservation(reservation_id)
	haul["destination"] = reservation.get(
		"destination",
		CityCitizens.make_city_citizen_haul_endpoint()
	)
	haul["phase"] = (
		CityCitizens.CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION
	)
	CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, haul)
	CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
		citizen_id,
		CityCitizens.CITY_CITIZEN_TASK_PHASE_PENDING
	)
	values["citizen"] = CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
	values["haul"] = haul
	values["path_requests_remaining"] = path_requests_remaining
	return _advance_pending_destination(city_world, values)


#endregion

#region Ground Pile Pickup Chaining

static func _begin_next_ground_pile_pickup(
	values: Dictionary
) -> Dictionary:
	var raw_city_world = values.get("city_world")
	var raw_current_task = values.get("current_task", {})
	var raw_haul = values.get("haul", {})
	var raw_current_tile = values.get(
		"current_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var path_requests_remaining := int(
		values.get("path_requests_remaining", 0)
	)

	if (
		not raw_city_world is WorldData
		or not raw_current_task is Dictionary
		or not raw_haul is Dictionary
		or not raw_current_tile is Vector2i
		or path_requests_remaining <= 0
	):
		return {
			"started": false,
			"path_requests_remaining": path_requests_remaining,
		}

	var city_world: WorldData = raw_city_world
	var current_task: Dictionary = raw_current_task
	var haul: Dictionary = raw_haul
	var current_tile: Vector2i = raw_current_tile
	var citizen_id := int(values.get("citizen_id", -1))
	var reservation_id := int(
		haul.get(
			"reservation_id",
			CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
		)
	)
	var reservation := CityLogisticsSystem.get_city_haul_reservation(
		reservation_id
	)
	var destination: Dictionary = reservation.get("destination", {})
	var destination_access_purpose := str(
		reservation.get(
			"destination_access_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var remaining_capacity := (
		CityCitizenInventorySystem.get_city_citizen_available_haul_capacity(
			citizen_id
		)
	)
	var additional_destination_space := (
		CityLogisticsSystem.get_city_haul_endpoint_unreserved_destination_space(
			destination
		)
	)

	if (
		citizen_id <= 0
		or reservation.is_empty()
		or remaining_capacity <= 0
		or additional_destination_space <= 0
	):
		return {
			"started": false,
			"path_requests_remaining": path_requests_remaining,
		}

	var candidates_by_access_tile: Dictionary = {}
	var candidate_access_tiles: Array = []

	# One ground-pile scan and one multi-target path request choose the nearest
	# reachable next pickup. No city-tile scan or per-pile pathfinding occurs.
	for raw_ground_pile in CityLogisticsSystem.get_city_ground_pile_snapshot():
		if not raw_ground_pile is Dictionary:
			continue

		var ground_pile: Dictionary = raw_ground_pile
		var ground_pile_id := int(ground_pile.get("id", -1))
		var resource := str(
			ground_pile.get(
				"resource_type",
				WorldData.RESOURCE_NONE
			)
		)
		var source := CityLogisticsSystem.make_city_ground_pile_haul_endpoint(
			ground_pile_id
		)

		if (
			ground_pile_id <= 0
			or not CityResourceCatalog.is_city_resource_type(resource)
			or not CityLogisticsSystem.city_haul_endpoint_can_provide_resource({
				"endpoint": source,
				"resource": resource,
				"withdrawal_purpose": CityObjectCatalog.CONTAINER_HAUL_PURPOSE_GROUND_PILE_CLEANUP,
				"require_unreserved_amount": true,
			})
			or not CityLogisticsSystem.city_haul_endpoint_can_accept_resource({
				"endpoint": destination,
				"resource": resource,
				"deposit_purpose": destination_access_purpose,
				"require_unreserved_space": true,
				"excluding_reservation_id": reservation_id,
			})
		):
			continue

		var pickup_amount := mini(
			remaining_capacity,
			mini(
				additional_destination_space,
				CityLogisticsSystem.get_city_haul_endpoint_unreserved_resource_amount(
					source,
					resource
				)
			)
		)

		if pickup_amount <= 0:
			continue

		for access_tile in CityResourceMatcherScript.get_haul_endpoint_access_tiles(
			city_world,
			source
		):
			if not candidates_by_access_tile.has(access_tile):
				candidates_by_access_tile[access_tile] = []
				candidate_access_tiles.append(access_tile)

			var candidates: Array = candidates_by_access_tile[access_tile]
			candidates.append({
				"source": source,
				"resource_type": resource,
				"pickup_amount": pickup_amount,
				"ground_pile_id": ground_pile_id,
			})
			candidates_by_access_tile[access_tile] = candidates

	if candidate_access_tiles.is_empty():
		return {
			"started": false,
			"path_requests_remaining": path_requests_remaining,
		}

	path_requests_remaining -= 1
	var path_result := (
		CityNavigationSystemScript.find_path_to_any_city_tile({
			"city_world": city_world,
			"start_tile": current_tile,
			"destination_tiles": candidate_access_tiles,
			"max_expanded_nodes": CityNavigationSystemScript.get_city_wide_path_expansion_limit(city_world),
			"citizen_id": citizen_id,
			"heuristic_weight": EXACT_DESTINATION_HEURISTIC_WEIGHT
		})
	)

	if not bool(path_result.get("success", false)):
		return {
			"started": false,
			"path_requests_remaining": path_requests_remaining,
		}

	var raw_source_tile = path_result.get(
		"destination_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var raw_path = path_result.get("path", [])

	if not raw_source_tile is Vector2i or not raw_path is Array:
		return {
			"started": false,
			"path_requests_remaining": path_requests_remaining,
		}

	var source_tile: Vector2i = raw_source_tile
	var raw_candidates = candidates_by_access_tile.get(
		source_tile,
		[]
	)

	if not raw_candidates is Array or raw_candidates.is_empty():
		return {
			"started": false,
			"path_requests_remaining": path_requests_remaining,
		}

	var candidates: Array = raw_candidates
	candidates.sort_custom(
		func(candidate_a: Dictionary, candidate_b: Dictionary) -> bool:
			var amount_a := int(candidate_a.get("pickup_amount", 0))
			var amount_b := int(candidate_b.get("pickup_amount", 0))

			if amount_a != amount_b:
				return amount_a > amount_b

			return int(candidate_a.get("ground_pile_id", -1)) < int(
				candidate_b.get("ground_pile_id", -1)
			)
	)
	var selected: Dictionary = candidates[0]
	var source: Dictionary = selected.get("source", {})
	var resource := str(
		selected.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var reserved_amount := (
		CityLogisticsSystem.retarget_city_haul_reservation_source({
			"reservation_id": reservation_id,
			"source": source,
			"resource": resource,
			"requested_amount": int(selected.get("pickup_amount", 0)),
			"source_access_purpose": (
				CityObjectCatalog.CONTAINER_HAUL_PURPOSE_GROUND_PILE_CLEANUP
			),
		})
	)

	if reserved_amount <= 0:
		return {
			"started": false,
			"path_requests_remaining": path_requests_remaining,
		}

	haul["source"] = source
	haul["resource_type"] = resource
	haul["requested_amount"] = reserved_amount
	haul["source_access_purpose"] = (
		CityObjectCatalog.CONTAINER_HAUL_PURPOSE_GROUND_PILE_CLEANUP
	)
	haul["source_tile"] = source_tile
	CityCitizenTaskRuntimeSystem.set_city_citizen_task_target_object_id(
		citizen_id,
		int(source.get("id", -1))
	)
	CityCitizenTaskRuntimeSystem.set_city_citizen_task_activity_state({
		"citizen_id": citizen_id,
		"target_tile": source_tile,
	})

	var movement_path: Array = raw_path

	if movement_path.size() <= 1:
		haul["phase"] = CityCitizens.CITY_CITIZEN_HAUL_PHASE_PICKING_UP
		CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, haul)
		CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
			citizen_id,
			CityCitizens.CITY_CITIZEN_TASK_PHASE_PERFORMING
		)
	else:
		haul["phase"] = (
			CityCitizens.CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_SOURCE
		)
		CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, haul)

		if not CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order(
			citizen_id,
			movement_path
		):
			_set_haul_blocked(citizen_id, haul)
			return {
				"started": true,
				"path_requests_remaining": path_requests_remaining,
			}

		CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
			citizen_id,
			CityCitizens.CITY_CITIZEN_TASK_PHASE_TRAVELING
		)

	return {
		"started": true,
		"path_requests_remaining": path_requests_remaining,
	}


#endregion

#region Cargo Demand Routing

static func _try_route_cargo_to_best_resource_demand(
	city_world: WorldData,
	values: Dictionary
) -> Dictionary:
	var citizen_id := int(values.get("citizen_id", -1))
	var start_tile: Vector2i = values.get(
		"start_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var cargo_resources: Dictionary = values.get("cargo_resources", {})
	var cargo_amount := maxi(int(values.get("cargo_amount", 0)), 0)
	var haul: Dictionary = values.get("haul", {})
	var current_destination_result: Dictionary = values.get(
		"current_destination_result",
		{}
	)
	var current_destination_access_purpose := str(
		values.get(
			"current_destination_access_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var current_destination_is_reserved := bool(
		values.get("current_destination_is_reserved", false)
	)
	var reservation_id := int(
		values.get(
			"reservation_id",
			CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
		)
	)
	var path_requests_remaining := maxi(
		int(values.get("path_requests_remaining", 0)),
		0
	)
	var match_result := (
		CityResourceMatcherScript.find_best_cargo_resource_demand({
			"city_world": city_world,
			"start_tile": start_tile,
			"citizen_id": citizen_id,
			"resources": cargo_resources,
			"max_path_requests": path_requests_remaining,
		})
	)
	path_requests_remaining = maxi(
		path_requests_remaining
		- int(match_result.get("path_requests_used", 0)),
		0
	)
	var result := {
		"routed": false,
		"path_requests_remaining": path_requests_remaining,
	}
	var demand_candidate = match_result.get("candidate", {})

	if not demand_candidate is Dictionary or demand_candidate.is_empty():
		return result

	var demand_endpoint = demand_candidate.get("endpoint", {})

	if not demand_endpoint is Dictionary:
		return result

	var candidate_destination_access_purpose := str(
		demand_candidate.get(
			"destination_access_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var candidate_reason := str(
		demand_candidate.get(
			"reason",
			CityCitizens.CITY_CITIZEN_HAUL_REASON_NONE
		)
	)
	var raw_candidate_requester = demand_candidate.get(
		"requester",
		demand_endpoint
	)
	var candidate_requester: Dictionary = demand_endpoint

	if raw_candidate_requester is Dictionary:
		candidate_requester = raw_candidate_requester

	if (
		candidate_destination_access_purpose
		== CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		or candidate_reason
		== CityCitizens.CITY_CITIZEN_HAUL_REASON_NONE
	):
		return result

	var current_score := -2147483648

	if not current_destination_result.is_empty():
		var current_endpoint = current_destination_result.get(
			"endpoint",
			{}
		)

		if current_endpoint is Dictionary:
			# An already reserved delivery to this exact demand is a hard
			# commitment. Do not churn it through its own preemption path.
			if CityLogisticsSystem.city_citizen_haul_endpoints_match(
				current_endpoint,
				demand_endpoint
			):
				return result

			var fulfillment_amount := mini(
				cargo_amount,
				maxi(
					int(
						current_destination_result.get(
							"available_amount",
							0
						)
					),
					0
				)
			)
			current_score = (
				CityResourceMatcherScript.score_resource_destination({
					"category": (
						CityResourceMatcherScript
						.get_resource_demand_category_for_destination(
							current_endpoint,
							current_destination_access_purpose
						)
					),
					"order_priority_rank": (
						CityResourceMatcherScript
						.get_resource_demand_order_priority_rank_for_destination(
							current_endpoint
						)
					),
					"path_cost": int(
						current_destination_result.get(
							"path_cost",
							0
						)
					),
					"fulfillment_amount": fulfillment_amount,
					"cargo_ready": true,
					"existing_commitment": (
						current_destination_is_reserved
					),
				})
			)

	if int(demand_candidate.get("score", 0)) <= current_score:
		return result

	var preemption_amounts = demand_candidate.get(
		"soft_preemption_amounts",
		{}
	)

	if not preemption_amounts is Dictionary:
		return result

	# Cargo in hand outranks promises to collect cargo. Soft reservations are
	# reduced only by the amount this load replaces, preserving useful remainder
	# assignments instead of cancelling an entire delivery unnecessarily.
	for raw_resource in preemption_amounts.keys():
		var resource := str(raw_resource)
		var required_amount := maxi(
			int(preemption_amounts.get(raw_resource, 0)),
			0
		)

		if required_amount <= 0:
			continue

		var preemption_result := (
			CityLogisticsSystem.preempt_soft_city_haul_reservations_for_destination_resource(
				demand_endpoint,
				resource,
				required_amount,
				citizen_id
			)
		)

		if (
			int(preemption_result.get("released_amount", 0))
			< required_amount
		):
			return result

	var requested_amount := mini(
		cargo_amount,
		maxi(
			int(demand_candidate.get("available_amount", 0)),
			0
		)
	)

	if requested_amount <= 0:
		return result

	var reservation := CityLogisticsSystem.get_city_haul_reservation(
		reservation_id
	)
	var reserved_amount := 0

	if (
		not reservation.is_empty()
		and int(reservation.get("citizen_id", -1)) == citizen_id
	):
		reserved_amount = (
			CityLogisticsSystem.retarget_city_haul_destination_reservation(
				reservation_id,
				demand_endpoint,
				requested_amount,
				candidate_destination_access_purpose
			)
		)
	else:
		var primary_resource := (
			CityCitizenInventorySystem.get_city_citizen_haul_cargo_resource(
				citizen_id
			)
		)
		reservation = CityLogisticsSystem.create_city_haul_reservation({
			"citizen_id": citizen_id,
			"source": haul.get("source", {}),
			"destination": demand_endpoint,
			"resource_type": primary_resource,
			"requested_amount": requested_amount,
			"source_access_purpose": str(
				haul.get(
					"source_access_purpose",
					CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
				)
			),
			"destination_access_purpose": (
				candidate_destination_access_purpose
			),
		})

		if not reservation.is_empty():
			reservation_id = int(reservation.get("id", -1))
			reserved_amount = int(
				reservation.get(
					"destination_reserved_amount",
					0
				)
			)

	if reserved_amount <= 0:
		return result

	reservation = CityLogisticsSystem.get_city_haul_reservation(reservation_id)

	if reservation.is_empty():
		return result

	var routed_result: Dictionary = demand_candidate.duplicate(true) as Dictionary
	routed_result["available_amount"] = reserved_amount
	var routed_haul := haul.duplicate(true)
	routed_haul["reservation_id"] = reservation_id
	routed_haul["destination"] = reservation.get(
		"destination",
		demand_endpoint
	)
	routed_haul["destination_access_purpose"] = (
		candidate_destination_access_purpose
	)
	routed_haul["reason"] = candidate_reason
	routed_haul["requester"] = candidate_requester
	routed_haul["requested_amount"] = reserved_amount
	routed_haul["destination_tile"] = routed_result.get(
		"destination_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	result["routed"] = true
	result["destination_result"] = routed_result
	result["destination_access_purpose"] = (
		candidate_destination_access_purpose
	)
	result["reservation_id"] = reservation_id
	result["reservation"] = reservation
	result["haul"] = routed_haul
	return result


#endregion

#region Destination Travel and Delivery

static func _advance_pending_destination(
	city_world: WorldData,
	values: Dictionary
) -> int:
	var citizen_id := int(values.get("citizen_id", -1))
	var citizen: Dictionary = values.get("citizen", {})
	var current_task: Dictionary = values.get("current_task", {})
	var haul: Dictionary = values.get("haul", {})
	var path_requests_remaining := maxi(
		int(values.get("path_requests_remaining", 0)),
		0
	)
	var cargo_resources := (
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_resources(
			citizen_id
		)
	)
	var cargo_amount := (
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id)
	)

	if cargo_amount <= 0 or cargo_resources.is_empty():
		_complete_haul(citizen_id, current_task)
		return path_requests_remaining

	var raw_current_tile = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if not raw_current_tile is Vector2i:
		_set_haul_blocked(citizen_id, haul)
		return path_requests_remaining

	if path_requests_remaining <= 0:
		return path_requests_remaining

	path_requests_remaining -= 1
	var destination_access_purpose := str(
		haul.get(
			"destination_access_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var reservation_id := int(
		haul.get(
			"reservation_id",
			CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
		)
	)
	var reservation := CityLogisticsSystem.get_city_haul_reservation(
		reservation_id
	)
	var destination_result: Dictionary = {}
	var destination_reservation_is_active := false

	if (
		not reservation.is_empty()
		and int(reservation.get("citizen_id", -1)) == citizen_id
		and int(
			reservation.get("destination_reserved_amount", 0)
		) > 0
	):
		var reserved_resources := (
			CityLogisticsSystem.get_city_haul_reservation_destination_resources(
				reservation_id
			)
		)
		destination_result = (
			CityResourceMatcherScript.make_destination_result_for_endpoint_resources({
				"city_world": city_world,
				"start_tile": raw_current_tile,
				"citizen_id": citizen_id,
				"resources": reserved_resources,
				"destination": reservation.get("destination", {}),
				"destination_access_purpose": (
					destination_access_purpose
				),
				"reservation_id": reservation_id,
				"requested_amount": int(
					reservation.get(
						"destination_reserved_amount",
						0
					)
				),
			})
		)
		destination_reservation_is_active = (
			not destination_result.is_empty()
		)

		if destination_result.is_empty():
			CityLogisticsSystem.release_city_haul_destination_reservation(
				reservation_id
			)
			reservation = CityLogisticsSystem.get_city_haul_reservation(
				reservation_id
			)
			destination_reservation_is_active = false

	if destination_result.is_empty():
		if (
			destination_access_purpose
			== CityObjectCatalog.CONTAINER_HAUL_PURPOSE_HOME_DELIVERY
			and cargo_resources.size() == 1
		):
			var home_resource := str(cargo_resources.keys()[0])
			destination_result = CityResourceMatcherScript.make_destination_result_for_endpoint({
				"city_world": city_world,
				"start_tile": raw_current_tile,
				"citizen_id": citizen_id,
				"resource_type": home_resource,
				"destination": haul.get("requester", {}),
				"destination_access_purpose": destination_access_purpose,
				"requested_amount": cargo_amount,
			})
		else:
			destination_result = CityResourceMatcherScript.find_nearest_eligible_destination_for_resources({
				"city_world": city_world,
				"start_tile": raw_current_tile,
				"citizen_id": citizen_id,
				"resources": cargo_resources,
				"destination_access_purpose": (
					destination_access_purpose
				),
				"reservation_id": reservation_id,
				"requested_amount": cargo_amount,
			})

	var command_routing_result := (
		_try_route_cargo_to_best_resource_demand(
			city_world,
			{
				"citizen_id": citizen_id,
				"start_tile": raw_current_tile,
				"cargo_resources": cargo_resources,
				"cargo_amount": cargo_amount,
				"haul": haul,
				"current_destination_result": destination_result,
				"current_destination_access_purpose": (
					destination_access_purpose
				),
				"current_destination_is_reserved": (
					destination_reservation_is_active
				),
				"reservation_id": reservation_id,
				"path_requests_remaining": path_requests_remaining,
			}
		)
	)
	path_requests_remaining = int(
		command_routing_result.get(
			"path_requests_remaining",
			path_requests_remaining
		)
	)

	if bool(command_routing_result.get("routed", false)):
		destination_result = command_routing_result.get(
			"destination_result",
			{}
		)
		destination_access_purpose = str(
			command_routing_result.get(
				"destination_access_purpose",
				destination_access_purpose
			)
		)
		reservation_id = int(
			command_routing_result.get(
				"reservation_id",
				reservation_id
			)
		)
		var raw_routed_reservation = command_routing_result.get(
			"reservation",
			{}
		)
		var raw_routed_haul = command_routing_result.get(
			"haul",
			haul
		)

		if raw_routed_reservation is Dictionary:
			reservation = raw_routed_reservation

		if raw_routed_haul is Dictionary:
			haul = raw_routed_haul

		destination_reservation_is_active = true

	if destination_result.is_empty():
		# Cargo is already physical. If every eligible container is full or no
		# destination is reachable, spill it back into mono-resource ground piles
		# instead of leaving the citizen blocked while carrying it indefinitely.
		if drop_citizen_haul_cargo_for_priority_interrupt(
			city_world,
			citizen_id,
			str(
				current_task.get(
					"source",
					CityCitizens.CITY_CITIZEN_TASK_SOURCE_PLAYER
				)
			)
		):
			return path_requests_remaining

		_set_haul_blocked(citizen_id, haul)
		return path_requests_remaining

	if destination_reservation_is_active:
		pass
	elif (
		reservation.is_empty()
		or int(reservation.get("citizen_id", -1)) != citizen_id
	):
		var primary_resource := (
			CityCitizenInventorySystem.get_city_citizen_haul_cargo_resource(citizen_id)
		)
		reservation = CityLogisticsSystem.create_city_haul_reservation({
			"citizen_id": citizen_id,
			"source": haul.get("source", {}),
			"destination": destination_result.get("endpoint", {}),
			"resource_type": primary_resource,
			"requested_amount": cargo_amount,
			"source_access_purpose": str(
				haul.get(
					"source_access_purpose",
					CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
				)
			),
			"destination_access_purpose": (
				destination_access_purpose
			),
		})

		if reservation.is_empty():
			_set_haul_blocked(citizen_id, haul)
			return path_requests_remaining

		reservation_id = int(reservation.get("id", -1))
		haul["reservation_id"] = reservation_id
	else:
		var reserved_amount := (
			CityLogisticsSystem.reserve_city_haul_destination(
				reservation_id,
				destination_result.get("endpoint", {}),
				cargo_amount
			)
		)

		if reserved_amount <= 0:
			_set_haul_blocked(citizen_id, haul)
			return path_requests_remaining

	reservation = CityLogisticsSystem.get_city_haul_reservation(reservation_id)
	haul["destination"] = reservation.get(
		"destination",
		CityCitizens.make_city_citizen_haul_endpoint()
	)
	CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, haul)

	values["haul"] = haul
	values["destination_result"] = destination_result
	values["path_requests_remaining"] = path_requests_remaining
	return _begin_destination_with_result(city_world, values)


static func _begin_destination_with_result(
	city_world: WorldData,
	values: Dictionary
) -> int:
	var citizen_id := int(values.get("citizen_id", -1))
	var current_task: Dictionary = values.get("current_task", {})
	var haul: Dictionary = values.get("haul", {})
	var destination_result: Dictionary = values.get(
		"destination_result",
		{}
	)
	var path_requests_remaining := maxi(
		int(values.get("path_requests_remaining", 0)),
		0
	)
	var raw_path = destination_result.get("path", [])
	var raw_destination_tile = destination_result.get(
		"destination_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
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
	CityCitizenTaskRuntimeSystem.set_city_citizen_task_activity_state({
		"citizen_id": citizen_id,
		"target_tile": destination_tile,
	})

	if movement_path.size() <= 1:
		haul["phase"] = CityCitizens.CITY_CITIZEN_HAUL_PHASE_DEPOSITING
		CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, haul)
		CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
			citizen_id,
			CityCitizens.CITY_CITIZEN_TASK_PHASE_PERFORMING
		)
		# Unloading completes on the next task pass, after the citizen has
		# visibly reached the destination access tile.
		return path_requests_remaining

	haul["phase"] = (
		CityCitizens.CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_DESTINATION
	)
	CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, haul)

	if not CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order(
		citizen_id,
		movement_path
	):
		_set_haul_blocked(citizen_id, haul)
		return path_requests_remaining

	CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
		citizen_id,
		CityCitizens.CITY_CITIZEN_TASK_PHASE_TRAVELING
	)
	return path_requests_remaining


static func _advance_traveling_to_destination(
	city_world: WorldData,
	values: Dictionary
) -> int:
	var citizen_id := int(values.get("citizen_id", -1))
	var citizen: Dictionary = values.get("citizen", {})
	var current_task: Dictionary = values.get("current_task", {})
	var haul: Dictionary = values.get("haul", {})
	var path_requests_remaining := maxi(
		int(values.get("path_requests_remaining", 0)),
		0
	)
	var movement_state := str(
		citizen.get(
			"movement_state",
			CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_IDLE
		)
	)

	if movement_state == CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_MOVING:
		return path_requests_remaining

	if movement_state == CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_BLOCKED:
		CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)
		CityLogisticsSystem.release_city_haul_destination_reservation(
			int(
				haul.get(
					"reservation_id",
					CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
				)
			)
		)
		haul["phase"] = CityCitizens.CITY_CITIZEN_HAUL_PHASE_RETARGETING
		haul["destination"] = (
			CityCitizens.make_city_citizen_haul_endpoint()
		)
		haul["destination_tile"] = CityCitizens.INVALID_CITY_TILE_POSITION
		CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, haul)
		values["citizen"] = CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
		values["haul"] = haul
		return _advance_pending_destination(city_world, values)

	var raw_current_tile = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var destination: Dictionary = haul.get("destination", {})
	var destination_access_tiles := CityResourceMatcherScript.get_haul_endpoint_access_tiles(
		city_world,
		destination
	)

	if (
		raw_current_tile is Vector2i
		and destination_access_tiles.has(raw_current_tile)
	):
		haul["phase"] = CityCitizens.CITY_CITIZEN_HAUL_PHASE_DEPOSITING
		haul["destination_tile"] = raw_current_tile
		CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, haul)
		CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
			citizen_id,
			CityCitizens.CITY_CITIZEN_TASK_PHASE_PERFORMING
		)
		return path_requests_remaining

	haul["phase"] = CityCitizens.CITY_CITIZEN_HAUL_PHASE_RETARGETING
	CityLogisticsSystem.release_city_haul_destination_reservation(
		int(
			haul.get(
				"reservation_id",
				CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
			)
		)
	)
	haul["destination"] = (
		CityCitizens.make_city_citizen_haul_endpoint()
	)
	haul["destination_tile"] = CityCitizens.INVALID_CITY_TILE_POSITION
	CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, haul)
	return _advance_pending_destination(
		city_world,
		values
	)


static func _deposit_and_retarget(
	city_world: WorldData,
	values: Dictionary
) -> int:
	var citizen_id := int(values.get("citizen_id", -1))
	var current_task: Dictionary = values.get("current_task", {})
	var haul: Dictionary = values.get("haul", {})
	var path_requests_remaining := maxi(
		int(values.get("path_requests_remaining", 0)),
		0
	)
	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
	var raw_current_tile = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var destination := CityCitizens.make_city_citizen_haul_endpoint()
	var raw_destination = haul.get("destination", {})

	if raw_destination is Dictionary:
		destination = CityCitizens.make_city_citizen_haul_endpoint(
			raw_destination
		)

	var destination_access_tiles := CityResourceMatcherScript.get_haul_endpoint_access_tiles(
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
		CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)
		CityLogisticsSystem.release_city_haul_destination_reservation(
			int(
				haul.get(
					"reservation_id",
					CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
				)
			)
		)
		haul["phase"] = CityCitizens.CITY_CITIZEN_HAUL_PHASE_RETARGETING
		haul["destination"] = (
			CityCitizens.make_city_citizen_haul_endpoint()
		)
		haul["destination_tile"] = CityCitizens.INVALID_CITY_TILE_POSITION
		CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, haul)
		CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
			citizen_id,
			CityCitizens.CITY_CITIZEN_TASK_PHASE_PENDING
		)
		values["citizen"] = CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
		values["haul"] = haul
		return _advance_pending_destination(city_world, values)

	var cargo_resources := (
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_resources(
			citizen_id
		)
	)

	if cargo_resources.is_empty():
		_complete_haul(citizen_id, current_task)
		return path_requests_remaining

	var reservation_id := int(
		haul.get(
			"reservation_id",
			CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
		)
	)
	var resource_names: Array = cargo_resources.keys()
	resource_names.sort()

	for raw_resource in resource_names:
		var resource := str(raw_resource)
		var cargo_amount := (
			CityCitizenInventorySystem.get_city_citizen_haul_cargo_resource_amount(
				citizen_id,
				resource
			)
		)

		if cargo_amount <= 0:
			continue

		_deposit_to_endpoint({
			"citizen_id": citizen_id,
			"endpoint": destination,
			"resource_type": resource,
			"requested_amount": cargo_amount,
			"deposit_purpose": str(
				haul.get(
					"destination_access_purpose",
					CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
				)
			),
			"reservation_id": reservation_id,
		})

	if CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id) <= 0:
		_complete_haul(citizen_id, current_task)
		return path_requests_remaining

	# A partially filled or externally changed container may accept only part of
	# a mixed manifest. The physical remainder keeps its exact resource amounts
	# and is routed to the next eligible public container.
	haul["phase"] = CityCitizens.CITY_CITIZEN_HAUL_PHASE_RETARGETING
	CityLogisticsSystem.release_city_haul_destination_reservation(
		reservation_id
	)
	haul["destination"] = (
		CityCitizens.make_city_citizen_haul_endpoint()
	)
	haul["destination_tile"] = CityCitizens.INVALID_CITY_TILE_POSITION
	CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, haul)
	CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
		citizen_id,
		CityCitizens.CITY_CITIZEN_TASK_PHASE_PENDING
	)
	values["citizen"] = CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
	values["haul"] = haul
	return _advance_pending_destination(city_world, values)


#endregion

#region Endpoint Resource Transfers

static func _pickup_from_endpoint(values: Dictionary) -> int:
	var citizen_id := int(values.get("citizen_id", -1))
	var endpoint: Dictionary = values.get("endpoint", {})
	var resource := str(
		values.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var requested_amount := maxi(
		int(values.get("requested_amount", 0)),
		0
	)
	var withdrawal_purpose := str(
		values.get(
			"withdrawal_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var reservation_id := int(
		values.get(
			"reservation_id",
			CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
		)
	)
	var reservation := CityLogisticsSystem.get_city_haul_reservation(
		reservation_id
	)

	if (
		reservation.is_empty()
		or int(reservation.get("citizen_id", -1)) != citizen_id
		or not CityLogisticsSystem.city_citizen_haul_endpoints_match(
			reservation.get("source", {}),
			endpoint
		)
		or str(
			reservation.get("resource_type", WorldData.RESOURCE_NONE)
		) != resource
		or not CityLogisticsSystem.city_haul_endpoint_can_provide_resource({
			"endpoint": endpoint,
			"resource": resource,
			"withdrawal_purpose": withdrawal_purpose,
			"require_unreserved_amount": true,
			"excluding_reservation_id": reservation_id,
		})
	):
		return 0

	var amount_to_remove := mini(
		requested_amount,
		mini(
			maxi(
				int(
					reservation.get(
						"source_reserved_amount",
						0
					)
				),
				0
			),
			mini(
				CityLogisticsSystem.get_city_haul_endpoint_unreserved_resource_amount(
					endpoint,
					resource,
					reservation_id
				),
				CityCitizenInventorySystem.get_city_citizen_available_haul_capacity(
					citizen_id
				)
			)
		)
	)

	amount_to_remove = mini(
		amount_to_remove,
		CityLogisticsSystem.get_city_haul_reservation_destination_resource_amount(
			reservation_id,
			resource
		)
	)

	if amount_to_remove <= 0:
		return 0

	var old_cargo_amount := (
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_resource_amount(
			citizen_id,
			resource
		)
	)
	var final_cargo_amount := (
		CityCitizenInventorySystem.change_city_citizen_haul_cargo_resource(
			citizen_id,
			resource,
			amount_to_remove
		)
	)

	if final_cargo_amount != old_cargo_amount + amount_to_remove:
		return 0

	var removed_amount := _remove_resource_from_endpoint({
		"endpoint": endpoint,
		"resource_type": resource,
		"requested_amount": amount_to_remove,
		"reservation_id": reservation_id,
	})

	if removed_amount != amount_to_remove:
		CityCitizenInventorySystem.change_city_citizen_haul_cargo_resource(
			citizen_id,
			resource,
			-(amount_to_remove - maxi(removed_amount, 0))
		)

	if not CityLogisticsSystem.commit_city_haul_source_reservation(
		reservation_id,
		removed_amount
	):
		push_error(
			"Failed to commit haul source reservation "
			+ str(reservation_id)
			+ "."
		)

	return maxi(removed_amount, 0)


static func _remove_resource_from_endpoint(values: Dictionary) -> int:
	var endpoint: Dictionary = values.get("endpoint", {})
	var resource := str(
		values.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var requested_amount := maxi(
		int(values.get("requested_amount", 0)),
		0
	)
	var reservation_id := int(
		values.get(
			"reservation_id",
			CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
		)
	)
	var endpoint_kind := str(
		endpoint.get(
			"kind",
			CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
		)
	)
	var endpoint_id := int(endpoint.get("id", -1))

	match endpoint_kind:
		CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER:
			return CityResourceContainerSystem.remove_resource_from_city_object_storage(
				endpoint_id,
				resource,
				requested_amount,
				reservation_id
			)

		CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE:
			return CityLogisticsSystem.remove_resource_from_city_ground_pile(
				endpoint_id,
				resource,
				requested_amount,
				reservation_id
			)

	return 0


static func _deposit_to_endpoint(values: Dictionary) -> int:
	var citizen_id := int(values.get("citizen_id", -1))
	var endpoint: Dictionary = values.get("endpoint", {})
	var resource := str(
		values.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var requested_amount := maxi(
		int(values.get("requested_amount", 0)),
		0
	)
	var deposit_purpose := str(
		values.get(
			"deposit_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var reservation_id := int(
		values.get(
			"reservation_id",
			CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
		)
	)
	var reservation := CityLogisticsSystem.get_city_haul_reservation(
		reservation_id
	)
	var reserved_resource_amount := (
		CityLogisticsSystem.get_city_haul_reservation_destination_resource_amount(
			reservation_id,
			resource
		)
	)

	if (
		reservation.is_empty()
		or int(reservation.get("citizen_id", -1)) != citizen_id
		or not CityLogisticsSystem.city_citizen_haul_endpoints_match(
			reservation.get("destination", {}),
			endpoint
		)
		or reserved_resource_amount <= 0
		or not CityLogisticsSystem.city_haul_endpoint_can_accept_resource({
			"endpoint": endpoint,
			"resource": resource,
			"deposit_purpose": deposit_purpose,
			"require_unreserved_space": true,
			"excluding_reservation_id": reservation_id,
		})
	):
		return 0

	var cargo_amount := (
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_resource_amount(
			citizen_id,
			resource
		)
	)
	var amount_to_deposit := mini(
		requested_amount,
		mini(cargo_amount, reserved_resource_amount)
	)

	if amount_to_deposit <= 0:
		return 0

	var object_id := int(endpoint.get("id", -1))
	var endpoint_kind := str(
		endpoint.get(
			"kind",
			CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
		)
	)
	var accepted_amount := 0
	var ground_drop_placements: Array = []

	if (
		endpoint_kind
		== CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE
	):
		accepted_amount = (
			CityConstructionSystem.add_resource_to_city_construction_site(
				object_id,
				resource,
				amount_to_deposit
			)
		)
	elif (
		endpoint_kind
		== CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_TILE
	):
		var raw_ground_tile = endpoint.get(
			"tile_position",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)
		var raw_excluded_pile_ids = endpoint.get(
			"excluded_ground_pile_ids",
			[]
		)
		var excluded_pile_ids: Array[int] = []

		if raw_excluded_pile_ids is Array:
			for raw_id in raw_excluded_pile_ids:
				excluded_pile_ids.append(int(raw_id))

		if raw_ground_tile is Vector2i:
			var add_result := (
				CityLogisticsSystem.add_resource_to_city_ground_piles_with_result({
					"tile_position": raw_ground_tile,
					"resource": resource,
					"amount_delta": amount_to_deposit,
					"construction_site_id": -1,
					"excluded_ground_pile_ids": excluded_pile_ids,
				})
			)
			accepted_amount = int(add_result.get("added_amount", 0))
			ground_drop_placements = add_result.get("placements", [])
	else:
		accepted_amount = CityResourceContainerSystem.add_resource_to_city_object_storage(
			object_id,
			resource,
			amount_to_deposit,
			reservation_id
		)

	if accepted_amount <= 0:
		return 0

	var final_resource_amount := (
		CityCitizenInventorySystem.change_city_citizen_haul_cargo_resource(
			citizen_id,
			resource,
			-accepted_amount
		)
	)
	var expected_remaining := cargo_amount - accepted_amount

	if final_resource_amount == expected_remaining:
		if not CityLogisticsSystem.commit_city_haul_destination_reservation(
			reservation_id,
			resource,
			accepted_amount
		):
			push_error(
				"Failed to commit haul destination reservation "
				+ str(reservation_id)
				+ "."
			)
		return accepted_amount

	var removed_from_destination := 0

	if (
		endpoint_kind
		== CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE
	):
		removed_from_destination = (
			CityConstructionSystem.remove_resource_from_city_construction_site(
				object_id,
				resource,
				accepted_amount
			)
		)
	elif (
		endpoint_kind
		== CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_TILE
	):
		if CityLogisticsSystem.rollback_city_ground_pile_additions(
			resource,
			ground_drop_placements
		):
			removed_from_destination = accepted_amount
	else:
		removed_from_destination = (
			CityResourceContainerSystem.remove_resource_from_city_object_storage(
				object_id,
				resource,
				accepted_amount
			)
		)
	CityCitizenInventorySystem.change_city_citizen_haul_cargo_resource(
		citizen_id,
		resource,
		accepted_amount
	)

	if removed_from_destination != accepted_amount:
		push_error(
			"Atomic mixed haul deposit rollback failed for resource "
			+ resource
			+ "."
		)

	return 0


#endregion

#region Haul Completion, Blocking, and Retry

static func _complete_haul(
	citizen_id: int,
	current_task: Dictionary
) -> void:
	if CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id) > 0:
		return

	CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)
	CityLogisticsSystem.release_city_haul_reservation_for_citizen(citizen_id)
	CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(
		citizen_id,
		CityCitizens.make_city_citizen_haul()
	)
	CityCitizenTaskRuntimeSystem.clear_city_citizen_task(
		citizen_id,
		str(
			current_task.get(
				"source",
				CityCitizens.CITY_CITIZEN_TASK_SOURCE_NONE
			)
		)
	)


static func _finish_haul_without_pickup(
	citizen_id: int,
	current_task: Dictionary
) -> void:
	if CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id) > 0:
		return

	_complete_haul(citizen_id, current_task)


static func _set_haul_blocked(
	citizen_id: int,
	haul: Dictionary
) -> void:
	CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)
	CityLogisticsSystem.release_city_haul_reservation_for_citizen(citizen_id)
	haul["reservation_id"] = (
		CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	)
	haul["destination"] = (
		CityCitizens.make_city_citizen_haul_endpoint()
	)
	haul["destination_tile"] = CityCitizens.INVALID_CITY_TILE_POSITION

	# Before pickup there is no physical obligation to retain. Releasing the
	# claim lets a different citizen try immediately instead of locking goods
	# and capacity for a blocked retry window.
	if CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id) <= 0:
		var current_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(
			citizen_id
		)
		CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, haul)
		CityCitizenTaskRuntimeSystem.clear_city_citizen_task(
			citizen_id,
			str(
				current_task.get(
					"source",
					CityCitizens.CITY_CITIZEN_TASK_SOURCE_PLAYER
				)
			)
		)
		return

	haul["phase"] = CityCitizens.CITY_CITIZEN_HAUL_PHASE_BLOCKED
	CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, haul)
	CityCitizenTaskRuntimeSystem.set_city_citizen_task_activity_state({
		"citizen_id": citizen_id,
		"target_tile": CityCitizens.INVALID_CITY_TILE_POSITION,
		"previous_target_tile": CityCitizens.INVALID_CITY_TILE_POSITION,
		"next_action_world_minute": (
			SimulationClock.absolute_world_minutes
			+ BLOCKED_HAUL_RETRY_DELAY_MINUTES
		),
		"relocation_count": 0,
	})
	CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
		citizen_id,
		CityCitizens.CITY_CITIZEN_TASK_PHASE_BLOCKED
	)


static func _prepare_blocked_haul_retry(
	citizen_id: int,
	current_task: Dictionary,
	has_cargo: bool
) -> bool:
	var retry_world_minute := int(
		current_task.get(
			"next_action_world_minute",
			CityCitizens.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
		)
	)

	if (
		retry_world_minute
		== CityCitizens.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
	):
		_set_haul_blocked(
			citizen_id,
			CityCitizenTaskRuntimeSystem.get_city_citizen_current_haul(citizen_id)
		)
		return false

	if SimulationClock.absolute_world_minutes < retry_world_minute:
		return false

	CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)
	var haul := CityCitizenTaskRuntimeSystem.get_city_citizen_current_haul(
		citizen_id
	)

	if has_cargo:
		haul["phase"] = CityCitizens.CITY_CITIZEN_HAUL_PHASE_RETARGETING
		haul["destination_tile"] = CityCitizens.INVALID_CITY_TILE_POSITION
	else:
		haul["phase"] = CityCitizens.CITY_CITIZEN_HAUL_PHASE_PENDING_SOURCE
		haul["source_tile"] = CityCitizens.INVALID_CITY_TILE_POSITION

	CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, haul)
	CityCitizenTaskRuntimeSystem.set_city_citizen_task_activity_state({
		"citizen_id": citizen_id,
		"target_tile": CityCitizens.INVALID_CITY_TILE_POSITION,
		"previous_target_tile": CityCitizens.INVALID_CITY_TILE_POSITION,
		"next_action_world_minute": (
			CityCitizens.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
		),
		"relocation_count": 0,
	})
	CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
		citizen_id,
		CityCitizens.CITY_CITIZEN_TASK_PHASE_PENDING
	)
	return true


#endregion

#region Endpoint and Path Helpers



#endregion
