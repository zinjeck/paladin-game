extends RefCounted
class_name CitizenMovementSystem

const CityNavigationSystemScript = preload(
	"res://scripts/city/simulation/systems/CityNavigationSystem.gd"
)

const MAX_REPATH_REQUESTS_PER_TICK: int = 4
const MAX_REPATH_EXPANDED_NODES: int = 10_000

static func run_tick(
	tick_index: int,
	minutes_advanced: int
) -> void:
	var city_state := CityCitizenUnboundCompatibility.get_city_state()
	run_tick_for_city_state(city_state, tick_index, minutes_advanced)


static func _make_legacy_city_state_view() -> CitySettlementSimulationState:
	return CityCitizenUnboundCompatibility.get_city_state()


static func run_tick_for_city_state(
	city_state: CitySettlementSimulationState,
	tick_index: int,
	minutes_advanced: int
) -> void:
	CityCitizenMovementRuntimeSystem.begin_city_citizen_movement_visual_tick_for_city_state(
		city_state,
		tick_index
	)

	if minutes_advanced <= 0:
		return

	var city_world: WorldData = city_state.city_world

	if city_world == null:
		return

	var active_mover_ids := (
		CityCitizenMovementRuntimeSystem
		.get_city_active_mover_ids_snapshot_for_city_state(city_state)
	)

	if active_mover_ids.is_empty():
		return

	var next_active_mover_ids: Array[int] = []
	var tick_context := {
		"city_world": city_world,
		"minutes_advanced": minutes_advanced,
		"citizen_updates": [],
		"next_active_mover_ids": next_active_mover_ids,
		"repath_requests_remaining": MAX_REPATH_REQUESTS_PER_TICK,
	}

	for citizen_id in active_mover_ids:
		_advance_active_mover(city_state, {
			"tick_context": tick_context,
			"citizen_id": int(citizen_id),
		})

	var commit_result := CityCitizenMovementRuntimeSystem.commit_city_citizen_movement_tick_for_city_state(
		city_state,
		city_world,
		tick_context.get("citizen_updates", []),
		next_active_mover_ids
	)

	if not bool(commit_result.get("success", false)):
		push_error("Citizen movement tick could not be committed.")
		return

	var rejected_updates: Array = commit_result.get(
		"rejected_updates",
		[]
	)

	if not rejected_updates.is_empty():
		push_warning(
			"Quarantined "
				+ str(rejected_updates.size())
				+ " invalid citizen movement update(s) without "
				+ "blocking valid movers: "
				+ str(rejected_updates)
		)


static func _advance_active_mover(
	city_state: CitySettlementSimulationState,
	values: Dictionary
) -> void:
	var tick_context: Dictionary = values.get("tick_context", {})
	var citizen_id := int(values.get("citizen_id", -1))
	var registry_state := city_state.citizen_registry_state
	var citizen_index := -1
	if registry_state.citizen_index_by_id.has(citizen_id):
		citizen_index = int(registry_state.citizen_index_by_id[citizen_id])

	if citizen_index < 0:
		return

	var raw_citizen = registry_state.citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return

	var citizen: Dictionary = raw_citizen.duplicate(true)
	var raw_current_tile = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if not raw_current_tile is Vector2i:
		push_error(
			"Cannot advance citizen "
				+ str(citizen_id)
				+ ": authoritative position is invalid."
		)
		return

	var mover_context := {
		"tick_context": tick_context,
		"citizen_id": citizen_id,
		"citizen": citizen,
		"current_tile": raw_current_tile,
		"traversed_tiles": [raw_current_tile],
	}

	if not bool(citizen.get("alive", false)):
		CityCitizens.reset_city_citizen_movement_state(citizen, true)
		_append_active_mover_update(city_state, mover_context)
		return

	if (
		str(citizen.get("movement_state", ""))
		!= CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_MOVING
	):
		return

	if not _prepare_active_mover_path(city_state, mover_context):
		_append_active_mover_update(city_state, mover_context)
		return

	_advance_active_mover_path(city_state, mover_context)
	_finalize_active_mover(city_state, mover_context)


static func _prepare_active_mover_path(
	city_state: CitySettlementSimulationState,
	context: Dictionary
) -> bool:
	var citizen: Dictionary = context.get("citizen", {})
	var current_tile: Vector2i = context.get(
		"current_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var raw_path = citizen.get("movement_path", [])
	var raw_path_index = citizen.get("movement_path_index", 0)
	var raw_progress = citizen.get("movement_progress_basis_points", 0)
	var raw_speed = citizen.get(
		"movement_speed_basis_points_per_minute",
		CityCitizens.DEFAULT_CITIZEN_MOVEMENT_SPEED_PER_MINUTE
	)
	var raw_repath_attempt_count = citizen.get(
		"movement_repath_attempt_count",
		0
	)
	var raw_destination = citizen.get(
		"movement_destination_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var basic_state_is_valid := (
		raw_path is Array
		and typeof(raw_path_index) == TYPE_INT
		and typeof(raw_progress) == TYPE_INT
		and typeof(raw_speed) == TYPE_INT
		and typeof(raw_repath_attempt_count) == TYPE_INT
		and raw_destination is Vector2i
	)

	if not basic_state_is_valid:
		_stop_citizen_for_invalid_path(city_state, citizen, raw_destination)
		return false

	var movement_path: Array = raw_path
	var movement_path_index: int = raw_path_index
	var movement_progress: int = raw_progress
	var movement_speed: int = raw_speed
	var repath_attempt_count: int = raw_repath_attempt_count
	var movement_destination: Vector2i = raw_destination
	var current_step_cost := 0

	if (
		movement_path_index >= 1
		and movement_path_index < movement_path.size()
		and movement_path[movement_path_index - 1] is Vector2i
		and movement_path[movement_path_index] is Vector2i
	):
		current_step_cost = CityNavigationSystem.get_city_citizen_movement_step_cost_for_city_state(
			city_state,
			movement_path[movement_path_index - 1],
			movement_path[movement_path_index]
		)

	var path_state_is_valid: bool = (
		movement_path.size() >= 2
		and movement_path_index >= 1
		and movement_path_index < movement_path.size()
		and current_step_cost > 0
		and movement_progress >= 0
		# A road may complete beneath an already-moving citizen and halve the
		# current step cost between ticks. Let the normal advancement loop consume
		# that now-sufficient progress instead of invalidating the path.
		and movement_speed > 0
		and repath_attempt_count >= 0
		and repath_attempt_count
		<= CityCitizens.MAX_CITIZEN_MOVEMENT_REPATH_ATTEMPTS
		and movement_path[movement_path_index - 1] == current_tile
		and movement_path.back() == movement_destination
	)

	if not path_state_is_valid:
		_stop_citizen_for_invalid_path(
			city_state,
			citizen,
			movement_destination
		)
		return false

	var tick_context: Dictionary = context.get("tick_context", {})
	context["movement_path"] = movement_path
	context["movement_path_index"] = movement_path_index
	context["movement_progress"] = (
		movement_progress
		+ int(tick_context.get("minutes_advanced", 0)) * movement_speed
	)
	context["repath_attempt_count"] = repath_attempt_count
	context["movement_destination"] = movement_destination
	context["movement_was_blocked"] = false
	context["movement_repath_was_deferred"] = false
	return true


static func _advance_active_mover_path(
	city_state: CitySettlementSimulationState,
	context: Dictionary
) -> void:
	var tick_context: Dictionary = context.get("tick_context", {})
	var city_world: WorldData = tick_context.get("city_world")
	var citizen_id := int(context.get("citizen_id", -1))
	var citizen: Dictionary = context.get("citizen", {})
	var current_tile: Vector2i = context.get(
		"current_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var traversed_tiles: Array = context.get("traversed_tiles", [])
	var movement_path: Array = context.get("movement_path", [])
	var movement_path_index := int(context.get("movement_path_index", 0))
	var movement_progress := int(context.get("movement_progress", 0))
	var repath_attempt_count := int(context.get("repath_attempt_count", 0))
	var movement_destination: Vector2i = context.get(
		"movement_destination",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var movement_was_blocked := false
	var movement_repath_was_deferred := false

	while movement_path_index < movement_path.size():
		var raw_next_tile = movement_path[movement_path_index]

		if not raw_next_tile is Vector2i:
			_set_citizen_movement_blocked(
				city_state,
				citizen,
				movement_destination,
				CityCitizens.CITY_CITIZEN_MOVEMENT_FAILURE_INVALID_PATH
			)
			movement_was_blocked = true
			break

		var next_tile: Vector2i = raw_next_tile
		var step_cost := CityNavigationSystem.get_city_citizen_movement_step_cost_for_city_state(
			city_state,
			current_tile,
			next_tile
		)

		if step_cost <= 0:
			_set_citizen_movement_blocked(
				city_state,
				citizen,
				movement_destination,
				CityCitizens.CITY_CITIZEN_MOVEMENT_FAILURE_INVALID_PATH
			)
			movement_was_blocked = true
			break

		if not CityNavigationSystem.can_city_citizen_traverse_step_for_city_state(
			city_state,
			city_world,
			current_tile,
			next_tile,
			citizen_id
		):
			if (
				repath_attempt_count
				>= CityCitizens.MAX_CITIZEN_MOVEMENT_REPATH_ATTEMPTS
			):
				_set_citizen_movement_blocked(
					city_state,
					citizen,
					movement_destination,
					CityCitizens.CITY_CITIZEN_MOVEMENT_FAILURE_REPATH_FAILED
				)
				movement_was_blocked = true
				break

			var repath_requests_remaining := int(
				tick_context.get("repath_requests_remaining", 0)
			)

			if repath_requests_remaining <= 0:
				movement_progress = 0
				movement_repath_was_deferred = true
				break

			repath_requests_remaining -= 1
			tick_context["repath_requests_remaining"] = repath_requests_remaining
			repath_attempt_count += 1
			citizen["movement_repath_attempt_count"] = repath_attempt_count

			var repath_path := _find_bounded_repath(city_state, {
				"city_world": city_world,
				"start_tile": current_tile,
				"destination_tile": movement_destination,
				"citizen_id": citizen_id,
			})

			if repath_path.is_empty():
				_set_citizen_movement_blocked(
					city_state,
					citizen,
					movement_destination,
					CityCitizens.CITY_CITIZEN_MOVEMENT_FAILURE_REPATH_FAILED
				)
				movement_was_blocked = true
				break

			movement_path = repath_path
			movement_path_index = 1

			if movement_path.size() == 1:
				break

			continue

		if movement_progress < step_cost:
			break

		movement_progress -= step_cost
		current_tile = next_tile
		traversed_tiles.append(current_tile)
		movement_path_index += 1

	context["current_tile"] = current_tile
	context["movement_path"] = movement_path
	context["movement_path_index"] = movement_path_index
	context["movement_progress"] = movement_progress
	context["repath_attempt_count"] = repath_attempt_count
	context["movement_was_blocked"] = movement_was_blocked
	context["movement_repath_was_deferred"] = movement_repath_was_deferred


static func _finalize_active_mover(
	city_state: CitySettlementSimulationState,
	context: Dictionary
) -> void:
	var tick_context: Dictionary = context.get("tick_context", {})
	var citizen_id := int(context.get("citizen_id", -1))
	var citizen: Dictionary = context.get("citizen", {})
	var movement_path: Array = context.get("movement_path", [])
	var movement_path_index := int(context.get("movement_path_index", 0))
	var movement_progress := int(context.get("movement_progress", 0))
	var repath_attempt_count := int(context.get("repath_attempt_count", 0))
	var next_active_mover_ids: Array = tick_context.get(
		"next_active_mover_ids",
		[]
	)

	if bool(context.get("movement_repath_was_deferred", false)):
		citizen["movement_path"] = movement_path.duplicate()
		citizen["movement_path_index"] = movement_path_index
		citizen["movement_progress_basis_points"] = 0
		citizen["movement_repath_attempt_count"] = repath_attempt_count
		citizen["movement_failure_reason"] = (
			CityCitizens.CITY_CITIZEN_MOVEMENT_FAILURE_NONE
		)
		next_active_mover_ids.append(citizen_id)
		_append_active_mover_update(city_state, context)
		return

	if bool(context.get("movement_was_blocked", false)):
		_append_active_mover_update(city_state, context)
		return

	if movement_path_index >= movement_path.size():
		CityCitizens.reset_city_citizen_movement_state(citizen, true)
		_append_active_mover_update(city_state, context)
		return

	citizen["movement_path"] = movement_path.duplicate()
	citizen["movement_path_index"] = movement_path_index
	citizen["movement_progress_basis_points"] = movement_progress
	citizen["movement_repath_attempt_count"] = repath_attempt_count
	citizen["movement_failure_reason"] = (
		CityCitizens.CITY_CITIZEN_MOVEMENT_FAILURE_NONE
	)
	next_active_mover_ids.append(citizen_id)
	_append_active_mover_update(city_state, context)


static func _append_active_mover_update(
	city_state: CitySettlementSimulationState,
	context: Dictionary
) -> void:
	var tick_context: Dictionary = context.get("tick_context", {})
	_append_citizen_update(city_state, {
		"citizen_updates": tick_context.get("citizen_updates", []),
		"citizen_id": int(context.get("citizen_id", -1)),
		"citizen": context.get("citizen", {}),
		"final_tile": context.get(
			"current_tile",
			CityCitizens.INVALID_CITY_TILE_POSITION
		),
		"traversed_tiles": context.get("traversed_tiles", []),
	})


static func _find_bounded_repath(
	city_state: CitySettlementSimulationState,
	values: Dictionary
) -> Array:
	var city_world: WorldData = values.get("city_world")
	var start_tile: Vector2i = values.get(
		"start_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var destination_tile: Vector2i = values.get(
		"destination_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var citizen_id := int(values.get("citizen_id", -1))
	var result := (
		CityNavigationSystemScript.find_path_to_any_city_tile_for_city_state(
			city_state,
			{
			"city_world": city_world,
			"start_tile": start_tile,
			"destination_tiles": [destination_tile],
			"max_expanded_nodes": MAX_REPATH_EXPANDED_NODES,
			"citizen_id": citizen_id,
			"heuristic_weight": CityNavigationSystem.HEURISTIC_WEIGHT
			}
		)
	)

	if not bool(result.get("success", false)):
		return []

	var raw_path = result.get("path", [])

	if not raw_path is Array:
		return []

	var repath_path: Array = raw_path

	if repath_path.is_empty():
		return []

	if repath_path[0] != start_tile:
		return []

	if repath_path.back() != destination_tile:
		return []

	return repath_path.duplicate()

static func _append_citizen_update(
	_city_state: CitySettlementSimulationState,
	values: Dictionary
) -> void:
	var citizen_updates: Array = values.get("citizen_updates", [])
	var citizen_id := int(values.get("citizen_id", -1))
	var citizen: Dictionary = values.get("citizen", {})
	var final_tile: Vector2i = values.get(
		"final_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var traversed_tiles: Array = values.get("traversed_tiles", [])
	citizen_updates.append({
		"citizen_id": citizen_id,
		"citizen": citizen,
		"final_tile": final_tile,
		"traversed_tiles": traversed_tiles.duplicate()
	})


static func _stop_citizen_for_invalid_path(
	_city_state: CitySettlementSimulationState,
	citizen: Dictionary,
	raw_destination
) -> void:
	if (
		raw_destination is Vector2i
		and raw_destination
		!= CityCitizens.INVALID_CITY_TILE_POSITION
	):
		_set_citizen_movement_blocked(
			_city_state,
			citizen,
			raw_destination,
			CityCitizens.CITY_CITIZEN_MOVEMENT_FAILURE_INVALID_PATH
		)
		return

	CityCitizens.reset_city_citizen_movement_state(
		citizen,
		true
	)


static func _set_citizen_movement_blocked(
	_city_state: CitySettlementSimulationState,
	citizen: Dictionary,
	destination_tile: Vector2i,
	failure_reason: String
) -> void:
	var raw_repath_attempt_count = citizen.get(
		"movement_repath_attempt_count",
		0
	)
	var repath_attempt_count: int = 0

	if typeof(raw_repath_attempt_count) == TYPE_INT:
		repath_attempt_count = clampi(
			int(raw_repath_attempt_count),
			0,
			CityCitizens.MAX_CITIZEN_MOVEMENT_REPATH_ATTEMPTS
		)

	citizen["movement_state"] = (
		CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_BLOCKED
	)
	citizen["movement_path"] = []
	citizen["movement_path_index"] = 0
	citizen["movement_progress_basis_points"] = 0
	citizen["movement_destination_tile"] = destination_tile
	citizen["movement_repath_attempt_count"] = (
		repath_attempt_count
	)
	citizen["movement_failure_reason"] = failure_reason
