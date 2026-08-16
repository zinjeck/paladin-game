extends RefCounted
class_name CityCitizenMovementPresentation

# Cosmetic, centralized movement interpolation. This helper reads WorldData but
# never mutates authoritative citizen positions or the spatial index. Visual
# routes retain individual path corners so diagonal-to-cardinal turns cannot cut
# across blocked geometry.

const POSITION_EPSILON: float = 0.0001

var presentation_binding: CityPresentationBinding
var bound_city_state: CitySettlementSimulationState
var movement_snapshot_by_citizen_id: Dictionary = {}
var visual_position_by_citizen_id: Dictionary = {}
var transition_by_citizen_id: Dictionary = {}
var tracked_mover_id_lookup: Dictionary = {}


func bind_city_presentation(binding: CityPresentationBinding) -> bool:
	if binding == null or not binding.is_valid():
		return false
	presentation_binding = binding
	initialize(binding.city_state)
	return true


func is_bound_to_city_presentation(
	binding: CityPresentationBinding
) -> bool:
	return (
		presentation_binding != null
		and presentation_binding.matches_binding(binding)
		and is_same(bound_city_state, binding.city_state)
	)


func initialize(city_state: CitySettlementSimulationState) -> void:
	bound_city_state = city_state
	movement_snapshot_by_citizen_id.clear()
	visual_position_by_citizen_id.clear()
	transition_by_citizen_id.clear()
	tracked_mover_id_lookup.clear()
	refresh_mover_tracking()


func synchronize(animate_position_changes: bool) -> void:
	if bound_city_state == null:
		return

	var candidate_citizen_id_lookup: Dictionary = {}

	for raw_citizen_id in tracked_mover_id_lookup.keys():
		if typeof(raw_citizen_id) == TYPE_INT:
			candidate_citizen_id_lookup[raw_citizen_id] = true

	for raw_citizen_id in transition_by_citizen_id.keys():
		if typeof(raw_citizen_id) == TYPE_INT:
			candidate_citizen_id_lookup[raw_citizen_id] = true

	for citizen_id in CityCitizenMovementRuntimeSystem.get_city_active_mover_ids_snapshot_for_city_state(
		bound_city_state
	):
		candidate_citizen_id_lookup[citizen_id] = true

	var candidate_citizen_ids: Array = (
		candidate_citizen_id_lookup.keys()
	)
	candidate_citizen_ids.sort()

	for raw_citizen_id in candidate_citizen_ids:
		var citizen_id := int(raw_citizen_id)
		var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
			bound_city_state,
			citizen_id
		)

		if (
			citizen.is_empty()
			or not bool(citizen.get("alive", false))
		):
			erase_citizen(citizen_id)
			continue

		_synchronize_citizen_position(
			citizen,
			animate_position_changes
		)


func synchronize_committed_tick(raw_events: Array) -> bool:
	var visual_state_changed := false

	for raw_event in raw_events:
		if not raw_event is Dictionary:
			continue

		var event: Dictionary = raw_event
		var citizen_id := int(event.get("citizen_id", -1))
		var raw_before_citizen = event.get("before", {})
		var raw_after_citizen = event.get("after", {})

		if citizen_id <= 0:
			continue

		if (
			not raw_before_citizen is Dictionary
			or not raw_after_citizen is Dictionary
		):
			continue

		var before_snapshot := _make_movement_snapshot(
			raw_before_citizen
		)
		var after_snapshot := _make_movement_snapshot(
			raw_after_citizen
		)

		if before_snapshot.is_empty() or after_snapshot.is_empty():
			continue

		if (
			int(raw_before_citizen.get("id", -1)) != citizen_id
			or int(raw_after_citizen.get("id", -1)) != citizen_id
		):
			continue

		if not movement_snapshot_by_citizen_id.has(citizen_id):
			movement_snapshot_by_citizen_id[citizen_id] = (
				before_snapshot
			)
			visual_position_by_citizen_id[citizen_id] = (
				before_snapshot["position"]
			)
			tracked_mover_id_lookup[citizen_id] = true
			visual_state_changed = true
		else:
			var raw_previous_snapshot = (
				movement_snapshot_by_citizen_id[citizen_id]
			)

			if raw_previous_snapshot is Dictionary:
				var previous_snapshot: Dictionary = (
					raw_previous_snapshot
				)

				if not visual_position_by_citizen_id.has(citizen_id):
					visual_position_by_citizen_id[citizen_id] = (
						previous_snapshot["position"]
					)
					visual_state_changed = true

				var bridge_points := (
					_build_snapshot_extension_points(
						previous_snapshot,
						before_snapshot
					)
				)

				if not bridge_points.is_empty():
					_queue_transition_extension(
						citizen_id,
						before_snapshot,
						bridge_points
					)
					visual_state_changed = true
			else:
				movement_snapshot_by_citizen_id[citizen_id] = (
					before_snapshot
				)
				visual_position_by_citizen_id[citizen_id] = (
					before_snapshot["position"]
				)
				transition_by_citizen_id.erase(citizen_id)
				visual_state_changed = true

		var exact_trace_points: Array = []
		var raw_traversed_tiles = event.get("traversed_tiles", [])

		if raw_traversed_tiles is Array:
			var trace_start_index := 1

			if not raw_traversed_tiles.is_empty():
				var raw_trace_origin = raw_traversed_tiles[0]
				var raw_before_position = before_snapshot.get("position")
				var expected_before_target = before_snapshot.get(
					"movement_visual_step_target_tile",
					CityCitizens.INVALID_CITY_TILE_POSITION
				)
				var actual_first_target = (
					CityCitizens.INVALID_CITY_TILE_POSITION
				)

				if (
					raw_traversed_tiles.size() >= 2
					and raw_traversed_tiles[1] is Vector2i
				):
					actual_first_target = raw_traversed_tiles[1]
				else:
					actual_first_target = after_snapshot.get(
						"movement_visual_step_target_tile",
						CityCitizens.INVALID_CITY_TILE_POSITION
					)

				# A same-tick repath can turn while the previous snapshot is
				# partway through its old segment. Return visually to the
				# authoritative tile before following the replacement path.
				if (
					raw_trace_origin is Vector2i
					and raw_before_position is Vector2
					and expected_before_target is Vector2i
					and actual_first_target is Vector2i
					and expected_before_target != actual_first_target
					and raw_before_position.distance_to(
						Vector2(raw_trace_origin)
					) > POSITION_EPSILON
				):
					trace_start_index = 0

			for trace_index in range(
				trace_start_index,
				raw_traversed_tiles.size()
			):
				var raw_trace_tile = raw_traversed_tiles[trace_index]

				if raw_trace_tile is Vector2i:
					_append_unique_waypoint(
						exact_trace_points,
						Vector2(raw_trace_tile)
					)

		var raw_after_position = after_snapshot.get("position")

		if raw_after_position is Vector2:
			_append_unique_waypoint(
				exact_trace_points,
				raw_after_position
			)

		movement_snapshot_by_citizen_id[citizen_id] = after_snapshot
		tracked_mover_id_lookup[citizen_id] = true

		if not exact_trace_points.is_empty():
			_queue_transition_extension(
				citizen_id,
				after_snapshot,
				exact_trace_points
			)
			visual_state_changed = true

		_release_mover_if_inactive(citizen_id)

	return visual_state_changed


func track_mover(citizen_id: int) -> void:
	if bound_city_state == null:
		return

	if citizen_id <= 0:
		return

	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
		bound_city_state,
		citizen_id
	)

	if (
		citizen.is_empty()
		or not bool(citizen.get("alive", false))
	):
		erase_citizen(citizen_id)
		return

	var snapshot := _make_movement_snapshot(citizen)

	if snapshot.is_empty():
		erase_citizen(citizen_id)
		return

	if not movement_snapshot_by_citizen_id.has(citizen_id):
		movement_snapshot_by_citizen_id[citizen_id] = snapshot
		visual_position_by_citizen_id[citizen_id] = snapshot["position"]

	tracked_mover_id_lookup[citizen_id] = true


func refresh_mover_tracking() -> void:
	if bound_city_state == null:
		return

	for citizen_id in CityCitizenMovementRuntimeSystem.get_city_active_mover_ids_snapshot_for_city_state(
		bound_city_state
	):
		track_mover(citizen_id)

	for raw_citizen_id in tracked_mover_id_lookup.keys():
		if typeof(raw_citizen_id) != TYPE_INT:
			movement_snapshot_by_citizen_id.erase(raw_citizen_id)
			visual_position_by_citizen_id.erase(raw_citizen_id)
			transition_by_citizen_id.erase(raw_citizen_id)
			tracked_mover_id_lookup.erase(raw_citizen_id)
			continue

		_release_mover_if_inactive(int(raw_citizen_id))


func update(delta: float) -> bool:
	if transition_by_citizen_id.is_empty():
		return false

	if not SimulationClock.simulation_active:
		return false

	if SimulationClock.simulation_paused:
		return false

	if delta <= 0.0:
		return false

	var simulation_speed: float = maxf(
		SimulationClock.speed_multiplier,
		0.0
	)

	if simulation_speed <= 0.0:
		return false

	var world_minutes_per_real_second: float = (
		float(SimulationClock.minutes_per_tick)
		/ maxf(
			SimulationClock.real_seconds_per_tick,
			0.001
		)
	)
	var visual_state_changed: bool = false

	for raw_citizen_id in transition_by_citizen_id.keys():
		if typeof(raw_citizen_id) != TYPE_INT:
			transition_by_citizen_id.erase(raw_citizen_id)
			visual_state_changed = true
			continue

		var citizen_id := int(raw_citizen_id)
		var raw_transition = transition_by_citizen_id[citizen_id]

		if not raw_transition is Dictionary:
			transition_by_citizen_id.erase(citizen_id)
			_release_mover_if_inactive(citizen_id)
			visual_state_changed = true
			continue

		var transition: Dictionary = raw_transition
		var raw_waypoints = transition.get("waypoints", [])

		if not raw_waypoints is Array:
			transition_by_citizen_id.erase(citizen_id)
			_release_mover_if_inactive(citizen_id)
			visual_state_changed = true
			continue

		var waypoints: Array = raw_waypoints
		var current_position: Vector2 = visual_position_by_citizen_id.get(
			citizen_id,
			Vector2(-1.0, -1.0)
		)
		var movement_speed: float = maxf(
			float(
				transition.get(
					"movement_speed_basis_points_per_minute",
					CityCitizens.DEFAULT_CITIZEN_MOVEMENT_SPEED_PER_MINUTE
				)
			),
			1.0
		)
		var movement_budget: float = (
			delta
			* simulation_speed
			* movement_speed
			* world_minutes_per_real_second
		)

		while movement_budget > 0.0 and not waypoints.is_empty():
			var raw_target = waypoints[0]

			if not raw_target is Vector2:
				waypoints.pop_front()
				continue

			var target: Vector2 = raw_target
			var segment_distance := current_position.distance_to(target)

			if segment_distance <= POSITION_EPSILON:
				current_position = target
				waypoints.pop_front()
				continue

			var movement_cost_per_world_unit := (
				_get_segment_movement_cost_per_world_unit(
					current_position,
					target
				)
			)
			var segment_cost := (
				segment_distance * movement_cost_per_world_unit
			)

			if movement_budget >= segment_cost:
				current_position = target
				movement_budget -= segment_cost
				waypoints.pop_front()
			else:
				var distance_to_advance := (
					movement_budget / movement_cost_per_world_unit
				)
				current_position = current_position.move_toward(
					target,
					distance_to_advance
				)
				movement_budget = 0.0

		visual_position_by_citizen_id[citizen_id] = current_position

		if waypoints.is_empty():
			transition_by_citizen_id.erase(citizen_id)
			_release_mover_if_inactive(citizen_id)
		else:
			transition["waypoints"] = waypoints
			transition_by_citizen_id[citizen_id] = transition

		visual_state_changed = true

	return visual_state_changed


func get_visual_tile_position(citizen: Dictionary) -> Vector2:
	var raw_authoritative_tile = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if not raw_authoritative_tile is Vector2i:
		return Vector2(-1.0, -1.0)

	var authoritative_tile: Vector2i = raw_authoritative_tile
	var fallback_position := Vector2(
		float(authoritative_tile.x),
		float(authoritative_tile.y)
	)
	var citizen_id := int(citizen.get("id", -1))

	if not visual_position_by_citizen_id.has(citizen_id):
		return fallback_position

	var raw_visual_position = visual_position_by_citizen_id[citizen_id]

	if not raw_visual_position is Vector2:
		return fallback_position

	return raw_visual_position


func get_transitioning_citizen_ids_snapshot() -> Array[int]:
	var citizen_ids: Array[int] = []

	for raw_citizen_id in visual_position_by_citizen_id.keys():
		if typeof(raw_citizen_id) != TYPE_INT:
			continue

		citizen_ids.append(int(raw_citizen_id))

	citizen_ids.sort()
	return citizen_ids


func _get_segment_movement_cost_per_world_unit(
	from_position: Vector2,
	to_position: Vector2
) -> float:
	var delta := to_position - from_position
	var direction := Vector2i(
		int(signf(delta.x)),
		int(signf(delta.y))
	)

	if direction == Vector2i.ZERO:
		return maxf(
			float(CityCitizens.CITY_CITIZEN_CARDINAL_MOVEMENT_COST),
			1.0
		)

	var target_tile := Vector2i(
		_get_segment_destination_coordinate(to_position.x, direction.x),
		_get_segment_destination_coordinate(to_position.y, direction.y)
	)
	var source_tile := target_tile - direction
	var step_cost := 0
	if bound_city_state != null:
		step_cost = (
			CityNavigationSystem
			.get_city_citizen_movement_step_cost_for_city_state(
				bound_city_state,
				source_tile,
				target_tile
			)
		)

	if step_cost <= 0:
		step_cost = (
			CityCitizens.CITY_CITIZEN_DIAGONAL_MOVEMENT_COST
			if direction.x != 0 and direction.y != 0
			else CityCitizens.CITY_CITIZEN_CARDINAL_MOVEMENT_COST
		)

	var full_step_distance := Vector2(direction).length()

	return maxf(
		float(step_cost) / maxf(full_step_distance, 1.0),
		1.0
	)


func _get_segment_destination_coordinate(
	coordinate: float,
	direction: int
) -> int:
	if is_equal_approx(coordinate, roundf(coordinate)):
		return roundi(coordinate)

	if direction > 0:
		return ceili(coordinate)

	if direction < 0:
		return floori(coordinate)

	return roundi(coordinate)


func _synchronize_citizen_position(
	citizen: Dictionary,
	animate_position_change: bool
) -> void:
	var citizen_id := int(citizen.get("id", -1))

	if citizen_id <= 0:
		return

	var current_snapshot := _make_movement_snapshot(citizen)

	if current_snapshot.is_empty():
		erase_citizen(citizen_id)
		return

	if not movement_snapshot_by_citizen_id.has(citizen_id):
		movement_snapshot_by_citizen_id[citizen_id] = current_snapshot
		visual_position_by_citizen_id[citizen_id] = (
			current_snapshot["position"]
		)
		tracked_mover_id_lookup[citizen_id] = true
		transition_by_citizen_id.erase(citizen_id)
		_release_mover_if_inactive(citizen_id)
		return

	var raw_previous_snapshot = (
		movement_snapshot_by_citizen_id[citizen_id]
	)

	if not raw_previous_snapshot is Dictionary:
		movement_snapshot_by_citizen_id[citizen_id] = current_snapshot
		visual_position_by_citizen_id[citizen_id] = (
			current_snapshot["position"]
		)
		transition_by_citizen_id.erase(citizen_id)
		_release_mover_if_inactive(citizen_id)
		return

	var previous_snapshot: Dictionary = raw_previous_snapshot
	movement_snapshot_by_citizen_id[citizen_id] = current_snapshot

	if not animate_position_change:
		visual_position_by_citizen_id[citizen_id] = (
			current_snapshot["position"]
		)
		transition_by_citizen_id.erase(citizen_id)
		_release_mover_if_inactive(citizen_id)
		return

	var extension_points := _build_snapshot_extension_points(
		previous_snapshot,
		current_snapshot
	)

	if extension_points.is_empty():
		_release_mover_if_inactive(citizen_id)
		return

	if not visual_position_by_citizen_id.has(citizen_id):
		visual_position_by_citizen_id[citizen_id] = (
			previous_snapshot["position"]
		)

	_queue_transition_extension(
		citizen_id,
		current_snapshot,
		extension_points
	)


func _queue_transition_extension(
	citizen_id: int,
	current_snapshot: Dictionary,
	extension_points: Array
) -> void:
	var transition: Dictionary = transition_by_citizen_id.get(
		citizen_id,
		{
			"waypoints": [],
			"movement_speed_basis_points_per_minute": (
				CityCitizens.DEFAULT_CITIZEN_MOVEMENT_SPEED_PER_MINUTE
			)
		}
	)
	var raw_waypoints = transition.get("waypoints", [])
	var waypoints: Array = []

	if raw_waypoints is Array:
		waypoints = raw_waypoints

	for raw_point in extension_points:
		if not raw_point is Vector2:
			continue

		_append_unique_waypoint(waypoints, raw_point)

	if waypoints.is_empty():
		transition_by_citizen_id.erase(citizen_id)
		_release_mover_if_inactive(citizen_id)
		return

	transition["waypoints"] = waypoints
	transition["movement_speed_basis_points_per_minute"] = maxi(
		int(current_snapshot.get(
			"movement_speed_basis_points_per_minute",
			CityCitizens.DEFAULT_CITIZEN_MOVEMENT_SPEED_PER_MINUTE
		)),
		1
	)
	transition_by_citizen_id[citizen_id] = transition
	tracked_mover_id_lookup[citizen_id] = true


func _make_movement_snapshot(citizen: Dictionary) -> Dictionary:
	var raw_authoritative_tile = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if not raw_authoritative_tile is Vector2i:
		return {}

	var authoritative_tile: Vector2i = raw_authoritative_tile
	var movement_state := str(citizen.get("movement_state", ""))
	var raw_path = citizen.get("movement_path", [])
	var movement_path: Array = []

	if raw_path is Array:
		movement_path = raw_path.duplicate()

	var movement_path_index := int(citizen.get("movement_path_index", 0))
	var movement_progress := int(citizen.get(
		"movement_progress_basis_points",
		0
	))
	var position := Vector2(
		float(authoritative_tile.x),
		float(authoritative_tile.y)
	)
	var visual_step_target_tile = citizen.get(
		"movement_visual_step_target_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if (
		movement_state == CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_MOVING
		and movement_path_index >= 1
		and movement_path_index < movement_path.size()
		and movement_path[movement_path_index - 1] is Vector2i
		and movement_path[movement_path_index] is Vector2i
	):
		var from_tile: Vector2i = movement_path[movement_path_index - 1]
		var to_tile: Vector2i = movement_path[movement_path_index]
		var step_cost := 0
		if bound_city_state != null:
			step_cost = (
				CityNavigationSystem
				.get_city_citizen_movement_step_cost_for_city_state(
					bound_city_state,
					from_tile,
					to_tile
				)
			)

		if step_cost > 0:
			visual_step_target_tile = to_tile
			var segment_progress := clampf(
				float(movement_progress) / float(step_cost),
				0.0,
				1.0
			)
			position = Vector2(from_tile).lerp(
				Vector2(to_tile),
				segment_progress
			)

	var raw_visual_position = citizen.get(
		"movement_visual_position",
		null
	)

	if raw_visual_position is Vector2:
		position = raw_visual_position

	return {
		"authoritative_tile": authoritative_tile,
		"movement_state": movement_state,
		"movement_path": movement_path,
		"movement_path_index": movement_path_index,
		"movement_progress_basis_points": movement_progress,
		"movement_speed_basis_points_per_minute": int(citizen.get(
			"movement_speed_basis_points_per_minute",
			CityCitizens.DEFAULT_CITIZEN_MOVEMENT_SPEED_PER_MINUTE
		)),
		"movement_visual_step_target_tile": visual_step_target_tile,
		"position": position
	}


func _build_snapshot_extension_points(
	previous_snapshot: Dictionary,
	current_snapshot: Dictionary
) -> Array:
	var points: Array = []
	var previous_position: Vector2 = previous_snapshot.get(
		"position",
		Vector2(-1.0, -1.0)
	)
	var current_position: Vector2 = current_snapshot.get(
		"position",
		previous_position
	)

	if previous_position.distance_to(current_position) <= POSITION_EPSILON:
		return points

	var previous_path: Array = previous_snapshot.get("movement_path", [])
	var current_path: Array = current_snapshot.get("movement_path", [])
	var previous_index := int(previous_snapshot.get(
		"movement_path_index",
		0
	))
	var current_index := int(current_snapshot.get(
		"movement_path_index",
		0
	))
	var current_state := str(current_snapshot.get("movement_state", ""))

	if (
		_paths_match(previous_path, current_path)
		and previous_index >= 1
		and current_index >= previous_index
	):
		for path_index in range(previous_index, current_index):
			if path_index >= previous_path.size():
				break

			var raw_path_tile = previous_path[path_index]

			if raw_path_tile is Vector2i:
				_append_unique_waypoint(points, Vector2(raw_path_tile))

		_append_unique_waypoint(points, current_position)
		return points

	if (
		current_state != CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_MOVING
		and previous_index >= 1
		and previous_index < previous_path.size()
		and not previous_path.is_empty()
		and previous_path.back()
		== current_snapshot.get(
			"authoritative_tile",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)
	):
		for path_index in range(previous_index, previous_path.size()):
			var raw_path_tile = previous_path[path_index]

			if raw_path_tile is Vector2i:
				_append_unique_waypoint(points, Vector2(raw_path_tile))

		return points

	var current_authoritative_tile = current_snapshot.get(
		"authoritative_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if current_authoritative_tile is Vector2i:
		_append_unique_waypoint(
			points,
			Vector2(current_authoritative_tile)
		)

	_append_unique_waypoint(points, current_position)
	return points


func _paths_match(path_a: Array, path_b: Array) -> bool:
	if path_a.size() != path_b.size():
		return false

	for path_index in range(path_a.size()):
		if path_a[path_index] != path_b[path_index]:
			return false

	return true


func _append_unique_waypoint(
	waypoints: Array,
	point: Vector2
) -> void:
	if not waypoints.is_empty():
		var raw_last_point = waypoints.back()

		if (
			raw_last_point is Vector2
			and raw_last_point.distance_to(point) <= POSITION_EPSILON
		):
			return

	waypoints.append(point)


func erase_citizen(citizen_id: int) -> void:
	movement_snapshot_by_citizen_id.erase(citizen_id)
	visual_position_by_citizen_id.erase(citizen_id)
	transition_by_citizen_id.erase(citizen_id)
	tracked_mover_id_lookup.erase(citizen_id)


func _release_mover_if_inactive(citizen_id: int) -> void:
	if (
		bound_city_state != null
		and bound_city_state.citizen_movement_runtime_state.active_mover_id_lookup.has(
			citizen_id
		)
	):
		return

	if transition_by_citizen_id.has(citizen_id):
		return

	erase_citizen(citizen_id)
