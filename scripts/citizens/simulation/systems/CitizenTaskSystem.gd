extends RefCounted
class_name CitizenTaskSystem

const CityNavigationSystemScript = preload(
	"res://scripts/city/simulation/systems/CityNavigationSystem.gd"
)
const CityActivityLocationResolverScript = preload(
	"res://scripts/city/simulation/systems/CityActivityLocationResolver.gd"
)
const CitizenHaulingSystemScript = preload(
	"res://scripts/citizens/simulation/systems/CitizenHaulingSystem.gd"
)
const MAX_TASK_PATH_REQUESTS_PER_TICK: int = 1
const MAX_WORK_PATH_EXPANDED_NODES: int = 10_000
const BLOCKED_WORK_TASK_RETRY_DELAY_MINUTES: int = 30
const MAX_RETURN_HOME_PATH_EXPANDED_NODES: int = 10_000
const BLOCKED_RETURN_HOME_TASK_RETRY_DELAY_MINUTES: int = 30
const WORK_ACTIVITY_DWELL_REQUIRED_KEYS := [
	"citizen_id",
	"workplace_id",
	"target_tile",
	"previous_target_tile",
	"choice_sequence",
	"dwell_min_minutes",
	"dwell_max_minutes",
	"relocation_count",
	"maximum_relocations_per_task",
]

static var _work_activity_claim_counts: Dictionary = {}


static func run_tick(
	tick_index: int,
	minutes_advanced: int
) -> void:
	_work_activity_claim_counts.clear()

	if minutes_advanced <= 0:
		return

	var city_world: WorldData = WorldData.official_city_world

	if city_world == null:
		return

	var active_task_ids := (
		WorldData.get_city_active_task_ids_snapshot()
	)

	if active_task_ids.is_empty():
		return

	_work_activity_claim_counts = (
		_build_work_activity_claim_counts(
			active_task_ids
		)
	)

	var path_requests_remaining := (
		MAX_TASK_PATH_REQUESTS_PER_TICK
	)

	for citizen_id in active_task_ids:
		var citizen := WorldData.get_city_citizen_by_id(
			citizen_id
		)

		if citizen.is_empty():
			continue

		if not bool(citizen.get("alive", false)):
			_clear_invalid_task(citizen_id)
			continue

		var current_task := (
			WorldData.get_city_citizen_current_task(
				citizen_id
			)
		)

		match str(current_task.get("kind", "")):
			WorldData.CITY_CITIZEN_TASK_KIND_WORK:
				path_requests_remaining = (
					_advance_work_task(
						city_world,
						citizen_id,
						citizen,
						current_task,
						path_requests_remaining,
						tick_index
					)
				)

			WorldData.CITY_CITIZEN_TASK_KIND_HAUL:
				path_requests_remaining = (
					CitizenHaulingSystemScript.advance_haul_task(
						city_world,
						citizen_id,
						citizen,
						current_task,
						path_requests_remaining
					)
				)

			WorldData.CITY_CITIZEN_TASK_KIND_RETURN_HOME:
				path_requests_remaining = (
					_advance_return_home_task(
						city_world,
						citizen_id,
						citizen,
						current_task,
						path_requests_remaining
					)
				)

			WorldData.CITY_CITIZEN_TASK_KIND_NONE:
				_clear_invalid_task(citizen_id)

			_:
				_clear_invalid_task(citizen_id)

static func _advance_work_task(
	city_world: WorldData,
	citizen_id: int,
	citizen: Dictionary,
	current_task: Dictionary,
	path_requests_remaining: int,
	tick_index: int
) -> int:
	var workplace_id := int(
		current_task.get("target_object_id", -1)
	)
	var workplace := WorldData.get_city_object_by_id(
		workplace_id
	)

	if (
		workplace_id <= 0
		or workplace.is_empty()
		or not WorldData.city_object_is_workplace(workplace)
		or int(citizen.get("job_object_id", -1)) != workplace_id
	):
		_clear_invalid_task(citizen_id)
		return path_requests_remaining
	var movement_policy := (
		WorldData.get_city_object_work_movement_policy(
			workplace
		)
	)
	var workplace_movement_mode := str(
		movement_policy.get(
			"mode",
			WorldData.WORKPLACE_MOVEMENT_MODE_NONE
		)
	)
	var dwell_min_minutes := maxi(
		int(movement_policy.get("dwell_min_minutes", 0)),
		0
	)
	var dwell_max_minutes := maxi(
		int(
			movement_policy.get(
				"dwell_max_minutes",
				dwell_min_minutes
			)
		),
		dwell_min_minutes
	)
	var maximum_relocations_per_task := maxi(
		int(
			movement_policy.get(
				"maximum_relocations_per_task",
				0
			)
		),
		0
	)
	var minimum_relocation_distance := maxi(
		int(
			movement_policy.get(
				"minimum_relocation_distance",
				0
			)
		),
		0
	)
	var avoid_previous_target := bool(
		movement_policy.get(
			"avoid_previous_target",
			false
		)
	)
	var activity_tiles := (
		CityActivityLocationResolverScript
		.get_work_activity_tiles(
			city_world,
			workplace
		)
	)
	var preferred_activity_tiles := (
		_get_preferred_work_activity_tiles(
			activity_tiles,
			citizen_id
		)
	)
	var raw_current_tile = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not raw_current_tile is Vector2i:
		_set_work_task_blocked(citizen_id)
		return path_requests_remaining

	var current_tile: Vector2i = raw_current_tile
	var task_phase := str(
		current_task.get(
			"phase",
			WorldData.CITY_CITIZEN_TASK_PHASE_NONE
		)
	)
	var relocation_count := maxi(
		int(current_task.get("relocation_count", 0)),
		0
	)
	var movement_state := str(
		citizen.get(
			"movement_state",
			WorldData.CITY_CITIZEN_MOVEMENT_STATE_IDLE
		)
	)

	match task_phase:
		WorldData.CITY_CITIZEN_TASK_PHASE_PENDING:
			if activity_tiles.is_empty():
				_set_work_task_blocked(citizen_id)
				return path_requests_remaining

			if preferred_activity_tiles.has(current_tile):
				if (
					movement_state
					!= WorldData.CITY_CITIZEN_MOVEMENT_STATE_IDLE
				):
					WorldData.cancel_city_citizen_movement(
						citizen_id
					)

				if not _begin_work_activity_dwell({
					"citizen_id": citizen_id,
					"workplace_id": workplace_id,
					"target_tile": current_tile,
					"previous_target_tile": current_task.get(
						"previous_target_tile",
						WorldData.INVALID_CITY_TILE_POSITION
					),
					"choice_sequence": tick_index,
					"dwell_min_minutes": dwell_min_minutes,
					"dwell_max_minutes": dwell_max_minutes,
					"relocation_count": relocation_count,
					"maximum_relocations_per_task": (
						maximum_relocations_per_task
					),
				}):
					_set_work_task_blocked(citizen_id)

				return path_requests_remaining

			if (
				movement_state
				== WorldData.CITY_CITIZEN_MOVEMENT_STATE_MOVING
			):
				return path_requests_remaining

			if (
				movement_state
				== WorldData.CITY_CITIZEN_MOVEMENT_STATE_BLOCKED
			):
				_set_work_task_blocked(citizen_id)
				return path_requests_remaining

			if path_requests_remaining <= 0:
				return path_requests_remaining

			path_requests_remaining -= 1

			var path_result := (
				CityNavigationSystemScript
				.find_path_to_any_city_tile(
					city_world,
					current_tile,
					preferred_activity_tiles,
					MAX_WORK_PATH_EXPANDED_NODES,
					citizen_id
				)
			)

			if not bool(path_result.get("success", false)):
				_set_work_task_blocked(citizen_id)
				push_warning(
					"Citizen "
					+ str(citizen_id)
					+ " could not reach workplace "
					+ str(workplace_id)
					+ ": "
					+ str(path_result.get("status", "unknown"))
				)
				return path_requests_remaining

			var raw_path = path_result.get("path", [])

			if not raw_path is Array:
				_set_work_task_blocked(citizen_id)
				return path_requests_remaining

			var movement_path: Array = raw_path
			var raw_selected_destination = path_result.get(
				"destination_tile",
				WorldData.INVALID_CITY_TILE_POSITION
			)

			if not raw_selected_destination is Vector2i:
				_set_work_task_blocked(citizen_id)
				return path_requests_remaining

			var selected_destination: Vector2i = (
				raw_selected_destination
			)

			if not preferred_activity_tiles.has(
				selected_destination
			):
				_set_work_task_blocked(citizen_id)
				return path_requests_remaining

			if not _set_work_task_activity_state({
				"citizen_id": citizen_id,
				"target_tile": selected_destination,
			}):
				_set_work_task_blocked(citizen_id)
				return path_requests_remaining

			if movement_path.size() <= 1:
				WorldData.set_city_citizen_task_phase(
					citizen_id,
					WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING
				)
				return path_requests_remaining

			if not WorldData.assign_city_citizen_movement_order(
				citizen_id,
				movement_path
			):
				_set_work_task_blocked(citizen_id)
				return path_requests_remaining

			WorldData.set_city_citizen_task_phase(
				citizen_id,
				WorldData.CITY_CITIZEN_TASK_PHASE_TRAVELING
			)

		WorldData.CITY_CITIZEN_TASK_PHASE_TRAVELING:
			if (
				movement_state
				== WorldData.CITY_CITIZEN_MOVEMENT_STATE_BLOCKED
			):
				_set_work_task_blocked(citizen_id)
			elif (
				movement_state
				== WorldData.CITY_CITIZEN_MOVEMENT_STATE_IDLE
			):
				var target_tile: Vector2i = current_task.get(
					"target_tile",
					WorldData.INVALID_CITY_TILE_POSITION
				)

				if (
					activity_tiles.has(current_tile)
					and current_tile == target_tile
				):
					var previous_target_tile: Vector2i = (
						current_task.get(
							"previous_target_tile",
							WorldData.INVALID_CITY_TILE_POSITION
						)
					)

					if not _begin_work_activity_dwell({
						"citizen_id": citizen_id,
						"workplace_id": workplace_id,
						"target_tile": current_tile,
						"previous_target_tile": previous_target_tile,
						"choice_sequence": tick_index,
						"dwell_min_minutes": dwell_min_minutes,
						"dwell_max_minutes": dwell_max_minutes,
						"relocation_count": relocation_count,
						"maximum_relocations_per_task": (
							maximum_relocations_per_task
						),
					}):
						_set_work_task_blocked(citizen_id)
				else:
					_set_work_task_blocked(citizen_id)

		WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING:
			if not WorldData.is_city_citizen_attending_workplace(
				citizen_id,
				workplace_id,
				city_world
			):
				_set_work_task_blocked(citizen_id)
				return path_requests_remaining

			if (
				workplace_movement_mode
				!= WorldData.WORKPLACE_MOVEMENT_MODE_MOVE_BETWEEN_WORK_POINTS
			):
				return path_requests_remaining

			if relocation_count >= maximum_relocations_per_task:
				return path_requests_remaining

			var next_action_world_minute := int(
				current_task.get(
					"next_action_world_minute",
					WorldData
					.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
				)
			)

			if (
				next_action_world_minute
				== WorldData
				.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
			):
				if not _begin_work_activity_dwell({
					"citizen_id": citizen_id,
					"workplace_id": workplace_id,
					"target_tile": current_tile,
					"previous_target_tile": current_task.get(
						"previous_target_tile",
						WorldData.INVALID_CITY_TILE_POSITION
					),
					"choice_sequence": tick_index,
					"dwell_min_minutes": dwell_min_minutes,
					"dwell_max_minutes": dwell_max_minutes,
					"relocation_count": relocation_count,
					"maximum_relocations_per_task": (
						maximum_relocations_per_task
					),
				}):
					_set_work_task_blocked(citizen_id)

				return path_requests_remaining

			if (
				SimulationClock.absolute_world_minutes
				< next_action_world_minute
			):
				return path_requests_remaining

			if path_requests_remaining <= 0:
				return path_requests_remaining

			var previous_target_tile: Vector2i = (
				current_task.get(
					"previous_target_tile",
					WorldData.INVALID_CITY_TILE_POSITION
				)
			)
			var departing_tile := current_tile
			var relocation_candidate_tiles: Array[Vector2i] = []

			for candidate_tile in preferred_activity_tiles:
				if candidate_tile == current_tile:
					continue

				relocation_candidate_tiles.append(
					candidate_tile
				)

			if relocation_candidate_tiles.is_empty():
				relocation_candidate_tiles = (
					activity_tiles.duplicate()
				)

			var new_target_tile := (
				CityActivityLocationResolverScript
				.choose_work_activity_tile({
					"activity_tiles": relocation_candidate_tiles,
					"current_tile": current_tile,
					"previous_target_tile": previous_target_tile,
					"citizen_id": citizen_id,
					"workplace_id": workplace_id,
					"choice_sequence": tick_index,
					"minimum_relocation_distance": (
						minimum_relocation_distance
					),
					"avoid_previous_target": avoid_previous_target,
				})
			)

			if (
				new_target_tile
				== WorldData.INVALID_CITY_TILE_POSITION
			):
				_set_work_task_blocked(citizen_id)
				return path_requests_remaining

			if new_target_tile == current_tile:
				if not _begin_work_activity_dwell({
					"citizen_id": citizen_id,
					"workplace_id": workplace_id,
					"target_tile": current_tile,
					"previous_target_tile": previous_target_tile,
					"choice_sequence": tick_index,
					"dwell_min_minutes": dwell_min_minutes,
					"dwell_max_minutes": dwell_max_minutes,
					"relocation_count": relocation_count + 1,
					"maximum_relocations_per_task": (
						maximum_relocations_per_task
					),
				}):
					_set_work_task_blocked(citizen_id)

				return path_requests_remaining

			path_requests_remaining -= 1

			var relocation_path_result := (
				CityNavigationSystemScript
				.find_path_to_any_city_tile(
					city_world,
					current_tile,
					[new_target_tile],
					MAX_WORK_PATH_EXPANDED_NODES,
					citizen_id
				)
			)

			if not bool(
				relocation_path_result.get("success", false)
			):
				if not _begin_work_activity_dwell({
					"citizen_id": citizen_id,
					"workplace_id": workplace_id,
					"target_tile": current_tile,
					"previous_target_tile": previous_target_tile,
					"choice_sequence": tick_index,
					"dwell_min_minutes": dwell_min_minutes,
					"dwell_max_minutes": dwell_max_minutes,
					"relocation_count": relocation_count,
					"maximum_relocations_per_task": (
						maximum_relocations_per_task
					),
				}):
					_set_work_task_blocked(citizen_id)

				return path_requests_remaining

			var raw_relocation_path = (
				relocation_path_result.get("path", [])
			)

			if not raw_relocation_path is Array:
				_set_work_task_blocked(citizen_id)
				return path_requests_remaining

			var relocation_path: Array = raw_relocation_path

			if relocation_path.size() <= 1:
				if not _begin_work_activity_dwell({
					"citizen_id": citizen_id,
					"workplace_id": workplace_id,
					"target_tile": current_tile,
					"previous_target_tile": previous_target_tile,
					"choice_sequence": tick_index,
					"dwell_min_minutes": dwell_min_minutes,
					"dwell_max_minutes": dwell_max_minutes,
					"relocation_count": relocation_count + 1,
					"maximum_relocations_per_task": (
						maximum_relocations_per_task
					),
				}):
					_set_work_task_blocked(citizen_id)

				return path_requests_remaining

			if not _set_work_task_activity_state({
				"citizen_id": citizen_id,
				"target_tile": new_target_tile,
				"previous_target_tile": departing_tile,
				"next_action_world_minute": (
					WorldData
					.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
				),
				"relocation_count": relocation_count + 1,
			}):
				_set_work_task_blocked(citizen_id)
				return path_requests_remaining

			if not WorldData.assign_city_citizen_movement_order(
				citizen_id,
				relocation_path
			):
				_set_work_task_blocked(citizen_id)
				return path_requests_remaining

			WorldData.set_city_citizen_task_phase(
				citizen_id,
				WorldData.CITY_CITIZEN_TASK_PHASE_TRAVELING
			)

		WorldData.CITY_CITIZEN_TASK_PHASE_BLOCKED:
			_retry_blocked_work_task_if_due(
				citizen_id,
				current_task,
				relocation_count
			)

		_:
			_set_work_task_blocked(citizen_id)

	return path_requests_remaining


static func _advance_return_home_task(
	city_world: WorldData,
	citizen_id: int,
	citizen: Dictionary,
	current_task: Dictionary,
	path_requests_remaining: int
) -> int:
	var home_id := int(
		current_task.get("target_object_id", -1)
	)
	var home := WorldData.get_city_object_by_id(home_id)
	var resident_ids := (
		WorldData.get_city_object_resident_ids(home)
	)

	if (
		home_id <= 0
		or home.is_empty()
		or WorldData.get_city_object_resident_capacity(home) <= 0
		or not WorldData.city_object_supports_citizen_interior(home)
		or int(citizen.get("home_object_id", -1)) != home_id
		or not resident_ids.has(citizen_id)
		or not WorldData.city_citizen_can_access_object_interior(
			citizen_id,
			home
		)
	):
		_clear_invalid_task(citizen_id)
		return path_requests_remaining

	var home_tiles := (
		CityActivityLocationResolverScript
		.get_object_interior_activity_tiles(
			city_world,
			home,
			citizen_id
		)
	)
	var raw_current_tile = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not raw_current_tile is Vector2i or home_tiles.is_empty():
		_set_return_home_task_blocked(citizen_id)
		return path_requests_remaining

	resident_ids.sort()
	var resident_index := resident_ids.find(citizen_id)

	if resident_index < 0:
		_clear_invalid_task(citizen_id)
		return path_requests_remaining

	var assigned_home_tile: Vector2i = home_tiles[
		resident_index % home_tiles.size()
	]
	var current_tile: Vector2i = raw_current_tile
	var task_phase := str(
		current_task.get(
			"phase",
			WorldData.CITY_CITIZEN_TASK_PHASE_NONE
		)
	)
	var movement_state := str(
		citizen.get(
			"movement_state",
			WorldData.CITY_CITIZEN_MOVEMENT_STATE_IDLE
		)
	)

	if task_phase == WorldData.CITY_CITIZEN_TASK_PHASE_BLOCKED:
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
			_set_return_home_task_blocked(citizen_id)
			return path_requests_remaining

		if SimulationClock.absolute_world_minutes < retry_world_minute:
			return path_requests_remaining

		WorldData.cancel_city_citizen_movement(citizen_id)

		if not WorldData.set_city_citizen_task_activity_state({
			"citizen_id": citizen_id,
			"target_tile": WorldData.INVALID_CITY_TILE_POSITION,
			"previous_target_tile": (
				WorldData.INVALID_CITY_TILE_POSITION
			),
			"next_action_world_minute": (
				WorldData.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
			),
			"relocation_count": 0,
		}):
			_set_return_home_task_blocked(citizen_id)
			return path_requests_remaining

		if not WorldData.set_city_citizen_task_phase(
			citizen_id,
			WorldData.CITY_CITIZEN_TASK_PHASE_PENDING
		):
			_set_return_home_task_blocked(citizen_id)
			return path_requests_remaining

		task_phase = WorldData.CITY_CITIZEN_TASK_PHASE_PENDING
		movement_state = WorldData.CITY_CITIZEN_MOVEMENT_STATE_IDLE
	elif (
		task_phase != WorldData.CITY_CITIZEN_TASK_PHASE_PENDING
		and task_phase != WorldData.CITY_CITIZEN_TASK_PHASE_TRAVELING
		and task_phase != WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING
	):
		_set_return_home_task_blocked(citizen_id)
		return path_requests_remaining

	if (
		movement_state == WorldData.CITY_CITIZEN_MOVEMENT_STATE_MOVING
		and task_phase != WorldData.CITY_CITIZEN_TASK_PHASE_TRAVELING
	):
		WorldData.cancel_city_citizen_movement(citizen_id)
		movement_state = WorldData.CITY_CITIZEN_MOVEMENT_STATE_IDLE

	if (
		current_tile == assigned_home_tile
		and movement_state != WorldData.CITY_CITIZEN_MOVEMENT_STATE_MOVING
	):
		if not _complete_return_home_task(citizen_id):
			_set_return_home_task_blocked(citizen_id)

		return path_requests_remaining

	if (
		task_phase == WorldData.CITY_CITIZEN_TASK_PHASE_TRAVELING
		and movement_state == WorldData.CITY_CITIZEN_MOVEMENT_STATE_MOVING
	):
		return path_requests_remaining

	if movement_state == WorldData.CITY_CITIZEN_MOVEMENT_STATE_BLOCKED:
		_set_return_home_task_blocked(citizen_id)
		return path_requests_remaining

	if path_requests_remaining <= 0:
		return path_requests_remaining

	path_requests_remaining -= 1

	var path_result := (
		CityNavigationSystemScript.find_path_to_any_city_tile(
			city_world,
			current_tile,
			[assigned_home_tile],
			MAX_RETURN_HOME_PATH_EXPANDED_NODES,
			citizen_id
		)
	)

	if not bool(path_result.get("success", false)):
		_set_return_home_task_blocked(citizen_id)
		return path_requests_remaining

	var raw_path = path_result.get("path", [])
	var raw_destination_tile = path_result.get(
		"destination_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if (
		not raw_path is Array
		or not raw_destination_tile is Vector2i
		or raw_destination_tile != assigned_home_tile
	):
		_set_return_home_task_blocked(citizen_id)
		return path_requests_remaining

	var movement_path: Array = raw_path

	if not WorldData.set_city_citizen_task_activity_state({
		"citizen_id": citizen_id,
		"target_tile": assigned_home_tile,
	}):
		_set_return_home_task_blocked(citizen_id)
		return path_requests_remaining

	if movement_path.size() <= 1:
		if not _complete_return_home_task(citizen_id):
			_set_return_home_task_blocked(citizen_id)

		return path_requests_remaining

	if not WorldData.assign_city_citizen_movement_order(
		citizen_id,
		movement_path
	):
		_set_return_home_task_blocked(citizen_id)
		return path_requests_remaining

	WorldData.set_city_citizen_task_phase(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_PHASE_TRAVELING
	)

	return path_requests_remaining


static func _complete_return_home_task(
	citizen_id: int
) -> bool:
	var current_task := (
		WorldData.get_city_citizen_current_task(citizen_id)
	)
	var task_source := str(
		current_task.get(
			"source",
			WorldData.CITY_CITIZEN_TASK_SOURCE_NONE
		)
	)

	if task_source == WorldData.CITY_CITIZEN_TASK_SOURCE_NONE:
		return false

	WorldData.cancel_city_citizen_movement(citizen_id)

	return WorldData.clear_city_citizen_task(
		citizen_id,
		task_source
	)


static func _set_return_home_task_blocked(
	citizen_id: int
) -> void:
	var current_task := (
		WorldData.get_city_citizen_current_task(citizen_id)
	)
	var target_tile = current_task.get(
		"target_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not target_tile is Vector2i:
		target_tile = WorldData.INVALID_CITY_TILE_POSITION

	WorldData.cancel_city_citizen_movement(citizen_id)
	WorldData.set_city_citizen_task_activity_state({
		"citizen_id": citizen_id,
		"target_tile": target_tile,
		"previous_target_tile": (
			WorldData.INVALID_CITY_TILE_POSITION
		),
		"next_action_world_minute": (
			SimulationClock.absolute_world_minutes
			+ BLOCKED_RETURN_HOME_TASK_RETRY_DELAY_MINUTES
		),
		"relocation_count": 0,
	})
	WorldData.set_city_citizen_task_phase(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_PHASE_BLOCKED
	)


static func _build_work_activity_claim_counts(
	active_task_ids: Array[int]
) -> Dictionary:
	var claim_counts: Dictionary = {}

	for citizen_id in active_task_ids:
		var citizen := WorldData.get_city_citizen_by_id(
			citizen_id
		)

		if (
			citizen.is_empty()
			or not bool(citizen.get("alive", false))
		):
			continue

		var current_task := (
			WorldData.get_city_citizen_current_task(
				citizen_id
			)
		)

		if (
			str(current_task.get("kind", ""))
			!= WorldData.CITY_CITIZEN_TASK_KIND_WORK
		):
			continue

		var task_phase := str(
			current_task.get(
				"phase",
				WorldData.CITY_CITIZEN_TASK_PHASE_NONE
			)
		)

		if (
			task_phase != WorldData.CITY_CITIZEN_TASK_PHASE_PENDING
			and task_phase != WorldData.CITY_CITIZEN_TASK_PHASE_TRAVELING
			and task_phase != WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING
		):
			continue

		var raw_target_tile = current_task.get(
			"target_tile",
			WorldData.INVALID_CITY_TILE_POSITION
		)

		if not raw_target_tile is Vector2i:
			continue

		var target_tile: Vector2i = raw_target_tile

		if target_tile == WorldData.INVALID_CITY_TILE_POSITION:
			continue

		claim_counts[target_tile] = (
			int(claim_counts.get(target_tile, 0))
			+ 1
		)

	return claim_counts


static func _get_preferred_work_activity_tiles(
	activity_tiles: Array[Vector2i],
	citizen_id: int
) -> Array[Vector2i]:
	var unclaimed_tiles: Array[Vector2i] = []
	var current_task := (
		WorldData.get_city_citizen_current_task(
			citizen_id
		)
	)
	var own_target_tile = current_task.get(
		"target_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	for candidate_tile in activity_tiles:
		var other_claim_count := int(
			_work_activity_claim_counts.get(
				candidate_tile,
				0
			)
		)

		if (
			own_target_tile is Vector2i
			and candidate_tile == own_target_tile
		):
			other_claim_count = maxi(
				other_claim_count - 1,
				0
			)

		if other_claim_count <= 0:
			unclaimed_tiles.append(candidate_tile)

	if not unclaimed_tiles.is_empty():
		return unclaimed_tiles

	return activity_tiles.duplicate()


static func _set_work_task_activity_state(
	values: Dictionary
) -> bool:
	if not values.has("citizen_id") or not values.has("target_tile"):
		push_error(
			"Work task activity state requires citizen_id and target_tile."
		)
		return false

	var raw_target_tile = values["target_tile"]
	var raw_previous_target_tile = values.get(
		"previous_target_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not raw_target_tile is Vector2i:
		push_error("Work task activity target_tile must be Vector2i.")
		return false

	if not raw_previous_target_tile is Vector2i:
		push_error(
			"Work task activity previous_target_tile must be Vector2i."
		)
		return false

	var citizen_id := int(values["citizen_id"])
	var target_tile: Vector2i = raw_target_tile
	var previous_target_tile: Vector2i = raw_previous_target_tile
	var next_action_world_minute := int(
		values.get(
			"next_action_world_minute",
			WorldData
			.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
		)
	)
	var relocation_count := int(
		values.get("relocation_count", -1)
	)
	var current_task := (
		WorldData.get_city_citizen_current_task(
			citizen_id
		)
	)
	var raw_old_target_tile = current_task.get(
		"target_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var old_target_tile := WorldData.INVALID_CITY_TILE_POSITION

	if raw_old_target_tile is Vector2i:
		old_target_tile = raw_old_target_tile

	if not WorldData.set_city_citizen_task_activity_state({
		"citizen_id": citizen_id,
		"target_tile": target_tile,
		"previous_target_tile": previous_target_tile,
		"next_action_world_minute": next_action_world_minute,
		"relocation_count": relocation_count,
	}):
		return false

	_replace_work_activity_claim(
		old_target_tile,
		target_tile
	)
	return true


static func _replace_work_activity_claim(
	old_target_tile: Vector2i,
	new_target_tile: Vector2i
) -> void:
	if old_target_tile == new_target_tile:
		return

	if old_target_tile != WorldData.INVALID_CITY_TILE_POSITION:
		var old_claim_count := int(
			_work_activity_claim_counts.get(
				old_target_tile,
				0
			)
		)

		if old_claim_count <= 1:
			_work_activity_claim_counts.erase(
				old_target_tile
			)
		else:
			_work_activity_claim_counts[old_target_tile] = (
				old_claim_count - 1
			)

	if new_target_tile != WorldData.INVALID_CITY_TILE_POSITION:
		_work_activity_claim_counts[new_target_tile] = (
			int(
				_work_activity_claim_counts.get(
					new_target_tile,
					0
				)
			)
			+ 1
		)

static func _get_deterministic_dwell_minutes(
	values: Dictionary
) -> int:
	var citizen_id := int(values["citizen_id"])
	var workplace_id := int(values["workplace_id"])
	var choice_sequence := int(values["choice_sequence"])
	var minimum_minutes := int(values["dwell_min_minutes"])
	var maximum_minutes := int(values["dwell_max_minutes"])

	if maximum_minutes <= minimum_minutes:
		return minimum_minutes

	var range_size := maximum_minutes - minimum_minutes + 1
	var deterministic_value := citizen_id * 73_856_093
	deterministic_value ^= workplace_id * 19_349_663
	deterministic_value ^= choice_sequence * 83_492_791
	deterministic_value &= 0x7fffffff

	return (
		minimum_minutes
		+ posmod(deterministic_value, range_size)
	)


static func _begin_work_activity_dwell(
	values: Dictionary
) -> bool:
	if not _has_valid_work_activity_dwell_values(values):
		return false

	var citizen_id := int(values["citizen_id"])
	var target_tile: Vector2i = values["target_tile"]
	var previous_target_tile: Vector2i = (
		values["previous_target_tile"]
	)
	var relocation_count := int(values["relocation_count"])
	var maximum_relocations_per_task := int(
		values["maximum_relocations_per_task"]
	)
	var next_action_world_minute := (
		WorldData.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
	)

	if relocation_count < maximum_relocations_per_task:
		var dwell_minutes := _get_deterministic_dwell_minutes(
			values
		)
		next_action_world_minute = (
			SimulationClock.absolute_world_minutes
			+ dwell_minutes
		)

	if not _set_work_task_activity_state({
		"citizen_id": citizen_id,
		"target_tile": target_tile,
		"previous_target_tile": previous_target_tile,
		"next_action_world_minute": next_action_world_minute,
		"relocation_count": relocation_count,
	}):
		return false

	return WorldData.set_city_citizen_task_phase(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING
	)


static func _has_valid_work_activity_dwell_values(
	values: Dictionary
) -> bool:
	for raw_key in WORK_ACTIVITY_DWELL_REQUIRED_KEYS:
		var key := str(raw_key)

		if not values.has(key):
			push_error(
				"Work activity dwell request is missing key: "
				+ key
			)
			return false

	if not values["target_tile"] is Vector2i:
		push_error(
			"Work activity dwell target_tile must be Vector2i."
		)
		return false

	if not values["previous_target_tile"] is Vector2i:
		push_error(
			"Work activity dwell previous_target_tile must be Vector2i."
		)
		return false

	return true

static func _retry_blocked_work_task_if_due(
	citizen_id: int,
	current_task: Dictionary,
	relocation_count: int
) -> void:
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
		_set_work_task_blocked(citizen_id)
		return

	if SimulationClock.absolute_world_minutes < retry_world_minute:
		return

	WorldData.cancel_city_citizen_movement(citizen_id)

	if not _set_work_task_activity_state({
		"citizen_id": citizen_id,
		"target_tile": WorldData.INVALID_CITY_TILE_POSITION,
		"previous_target_tile": (
			WorldData.INVALID_CITY_TILE_POSITION
		),
		"next_action_world_minute": (
			WorldData.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
		),
		"relocation_count": relocation_count,
	}):
		_set_work_task_blocked(citizen_id)
		return

	if not WorldData.set_city_citizen_task_phase(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_PHASE_PENDING
	):
		_set_work_task_blocked(citizen_id)


static func _set_work_task_blocked(citizen_id: int) -> void:
	var current_task := (
		WorldData.get_city_citizen_current_task(
			citizen_id
		)
	)
	var target_tile := WorldData.INVALID_CITY_TILE_POSITION
	var previous_target_tile := (
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var raw_target_tile = current_task.get(
		"target_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var raw_previous_target_tile = current_task.get(
		"previous_target_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if raw_target_tile is Vector2i:
		target_tile = raw_target_tile

	if raw_previous_target_tile is Vector2i:
		previous_target_tile = raw_previous_target_tile

	var relocation_count := maxi(
		int(current_task.get("relocation_count", 0)),
		0
	)
	var retry_world_minute := (
		SimulationClock.absolute_world_minutes
		+ BLOCKED_WORK_TASK_RETRY_DELAY_MINUTES
	)

	WorldData.cancel_city_citizen_movement(citizen_id)
	_set_work_task_activity_state({
		"citizen_id": citizen_id,
		"target_tile": target_tile,
		"previous_target_tile": previous_target_tile,
		"next_action_world_minute": retry_world_minute,
		"relocation_count": relocation_count,
	})
	WorldData.set_city_citizen_task_phase(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_PHASE_BLOCKED
	)

static func _clear_invalid_task(citizen_id: int) -> void:
	WorldData.clear_city_citizen_task(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER
	)
	WorldData.cancel_city_citizen_movement(citizen_id)
