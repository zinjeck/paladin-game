extends RefCounted
class_name CitizenDecisionSystem

const CityNavigationSystemScript = preload(
	"res://scripts/city/simulation/systems/CityNavigationSystem.gd"
)
const CitizenHaulingSystemScript = preload(
	"res://scripts/citizens/simulation/systems/CitizenHaulingSystem.gd"
)

# Temporary shared schedule for the first autonomous work pass.
# These constants are intentionally centralized so the schedule can later be
# replaced by workplace, profession, household, or policy-driven schedules.
const WORK_SHIFT_START_MINUTE_OF_DAY: int = 8 * 60
const WORK_SHIFT_END_MINUTE_OF_DAY: int = 17 * 60
const SCHEDULED_WORK_TASK_PRIORITY: int = 100
const OUTSTANDING_CARGO_HAUL_TASK_PRIORITY: int = 150
const SCHEDULED_OUTPUT_HAUL_TASK_PRIORITY: int = 75
const SCHEDULED_RETURN_HOME_TASK_PRIORITY: int = 50
const SCHEDULE_PHASE_WORK_SHIFT := "work_shift"
const SCHEDULE_PHASE_OFF_SHIFT := "off_shift"
const SCHEDULE_ACTIVITY_OUTSTANDING_OBLIGATION := (
	"outstanding_obligation"
)
const SCHEDULE_ACTIVITY_ASSIGNED_WORK := "assigned_work"
const SCHEDULE_ACTIVITY_ASSIGNED_HOME := "assigned_home"

# Rules are evaluated in order. The first rule that returns a task request
# wins, so obligations can precede ordinary schedule destinations.
const DEFAULT_SCHEDULE_ACTIVITY_RULES := {
	SCHEDULE_PHASE_WORK_SHIFT: [
		SCHEDULE_ACTIVITY_OUTSTANDING_OBLIGATION,
		SCHEDULE_ACTIVITY_ASSIGNED_WORK,
	],
	SCHEDULE_PHASE_OFF_SHIFT: [
		SCHEDULE_ACTIVITY_OUTSTANDING_OBLIGATION,
		SCHEDULE_ACTIVITY_ASSIGNED_HOME,
	],
}
const MAX_DECISIONS_PER_TICK: int = 32
const MAX_RECOVERY_SCANS_PER_TICK: int = 64

# Idle locomotion is deliberately local and sparse. It gives citizens visible
# life without turning the absence of a task into an expensive journey.
const IDLE_STAND_CHANCE_PERCENT: int = 55
const IDLE_MINIMUM_WAIT_MINUTES: int = 10
const IDLE_MAXIMUM_WAIT_MINUTES: int = 30
const IDLE_ANCHOR_RADIUS_TILES: int = 4
const IDLE_MAXIMUM_DESTINATION_DISTANCE: int = 4
const IDLE_MAXIMUM_PATH_STEPS: int = 6
const IDLE_MAXIMUM_EXPANDED_NODES: int = 96
const MAX_IDLE_SCANS_PER_TICK: int = 64
const MAX_IDLE_PATH_REQUESTS_PER_TICK: int = 1

static var _pending_decision_ids: Array[int] = []
static var _pending_decision_id_lookup: Dictionary = {}
static var _runtime_initialized: bool = false
static var _work_shift_was_active: bool = false
static var _observed_assignment_version: int = -1
static var _recovery_scan_cursor: int = 0
static var _idle_scan_cursor: int = 0
static var _idle_anchor_tile_by_citizen_id: Dictionary = {}
static var _next_idle_decision_minute_by_citizen_id: Dictionary = {}
static var _idle_choice_sequence_by_citizen_id: Dictionary = {}

static func run_tick(
	_tick_index: int,
	minutes_advanced: int
) -> void:
	if minutes_advanced <= 0:
		return

	if (
		WorldData.official_city_world == null
		or not WorldData.player_city_founded
		or WorldData.city_citizens.is_empty()
	):
		reset_runtime_state()
		return

	var work_shift_is_active := is_work_shift_active()
	var schedule_phase := _get_schedule_phase(
		work_shift_is_active
	)

	if not _runtime_initialized:
		_runtime_initialized = true
		_work_shift_was_active = work_shift_is_active
		_observed_assignment_version = (
			WorldData.city_assignment_version
		)

		_clear_schedule_sourced_tasks()
		_queue_all_eligible_scheduled_tasks(
			schedule_phase
		)
	elif work_shift_is_active != _work_shift_was_active:
		_work_shift_was_active = work_shift_is_active
		_clear_schedule_sourced_tasks()
		_queue_all_eligible_scheduled_tasks(
			schedule_phase
		)

	if (
		_observed_assignment_version
		!= WorldData.city_assignment_version
	):
		_observed_assignment_version = (
			WorldData.city_assignment_version
		)

		_queue_all_eligible_scheduled_tasks(
			schedule_phase
		)

	_queue_bounded_recovery_candidates(
		schedule_phase
	)
	_process_decision_queue(schedule_phase)

	_process_bounded_idle_behaviors(
		work_shift_is_active
	)

static func reset_runtime_state() -> void:
	_clear_decision_queue()
	_runtime_initialized = false
	_work_shift_was_active = false
	_observed_assignment_version = -1
	_recovery_scan_cursor = 0
	_idle_scan_cursor = 0
	_idle_anchor_tile_by_citizen_id.clear()
	_next_idle_decision_minute_by_citizen_id.clear()
	_idle_choice_sequence_by_citizen_id.clear()


static func is_work_shift_active() -> bool:
	var minute_of_day := (
		SimulationClock.get_world_hour() * 60
		+ SimulationClock.get_world_minute()
	)

	return (
		minute_of_day >= WORK_SHIFT_START_MINUTE_OF_DAY
		and minute_of_day < WORK_SHIFT_END_MINUTE_OF_DAY
	)

static func _get_schedule_phase(
	work_shift_is_active: bool
) -> String:
	if work_shift_is_active:
		return SCHEDULE_PHASE_WORK_SHIFT

	return SCHEDULE_PHASE_OFF_SHIFT


static func _queue_all_eligible_scheduled_tasks(
	schedule_phase: String
) -> void:
	for raw_citizen in WorldData.city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if not _citizen_needs_scheduled_task(
			citizen,
			schedule_phase
		):
			continue

		_queue_citizen_id(
			int(citizen.get("id", -1))
		)

	_pending_decision_ids.sort()


static func _queue_bounded_recovery_candidates(
	schedule_phase: String
) -> void:
	var citizen_count := WorldData.city_citizens.size()

	if citizen_count <= 0:
		_recovery_scan_cursor = 0
		return

	var scan_count := mini(
		citizen_count,
		MAX_RECOVERY_SCANS_PER_TICK
	)

	for _scan_index in range(scan_count):
		var citizen_index := (
			_recovery_scan_cursor % citizen_count
		)
		_recovery_scan_cursor = (
			(_recovery_scan_cursor + 1) % citizen_count
		)

		var raw_citizen = WorldData.city_citizens[
			citizen_index
		]

		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if not _citizen_needs_scheduled_task(
			citizen,
			schedule_phase
		):
			continue

		_queue_citizen_id(
			int(citizen.get("id", -1))
		)

	_pending_decision_ids.sort()

static func _citizen_needs_scheduled_work_task(
	citizen: Dictionary
) -> bool:
	if not bool(citizen.get("alive", false)):
		return false

	var workplace_id := int(
		citizen.get("job_object_id", -1)
	)

	if workplace_id <= 0:
		return false

	var workplace := WorldData.get_city_object_by_id(
		workplace_id
	)

	if (
		workplace.is_empty()
		or not WorldData.city_object_is_workplace(workplace)
	):
		return false

	var raw_current_task = citizen.get("current_task", {})

	if not raw_current_task is Dictionary:
		return false

	var current_task: Dictionary = raw_current_task

	return (
		str(current_task.get("kind", ""))
		== WorldData.CITY_CITIZEN_TASK_KIND_NONE
	)


static func _citizen_needs_scheduled_return_home_task(
	citizen: Dictionary
) -> bool:
	if not bool(citizen.get("alive", false)):
		return false

	var home_id := int(
		citizen.get("home_object_id", -1)
	)

	if home_id <= 0:
		return false

	var home := WorldData.get_city_object_by_id(home_id)
	var citizen_id := int(citizen.get("id", -1))

	if (
		home.is_empty()
		or WorldData.get_city_object_resident_capacity(home) <= 0
		or not WorldData.city_object_supports_citizen_interior(home)
		or not WorldData.get_city_object_resident_ids(
			home
		).has(citizen_id)
		or not WorldData.city_citizen_can_access_object_interior(
			citizen_id,
			home
		)
	):
		return false

	if _citizen_has_satisfied_home_arrival(citizen, home):
		return false

	var raw_current_task = citizen.get("current_task", {})

	if not raw_current_task is Dictionary:
		return false

	var current_task: Dictionary = raw_current_task

	return (
		str(current_task.get("kind", ""))
		== WorldData.CITY_CITIZEN_TASK_KIND_NONE
	)


static func _citizen_has_satisfied_home_arrival(
	citizen: Dictionary,
	home: Dictionary
) -> bool:
	var home_tiles := WorldData.get_city_object_footprint_tiles(
		home
	)
	var raw_current_tile = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if (
		raw_current_tile is Vector2i
		and home_tiles.has(raw_current_tile)
	):
		return true

	var citizen_id := int(citizen.get("id", -1))
	var raw_anchor_tile = _idle_anchor_tile_by_citizen_id.get(
		citizen_id,
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if (
		not raw_current_tile is Vector2i
		or not raw_anchor_tile is Vector2i
		or not home_tiles.has(raw_anchor_tile)
	):
		return false

	var current_tile: Vector2i = raw_current_tile
	var anchor_tile: Vector2i = raw_anchor_tile
	var distance_from_home_anchor := (
		absi(current_tile.x - anchor_tile.x)
		+ absi(current_tile.y - anchor_tile.y)
	)

	return distance_from_home_anchor <= IDLE_ANCHOR_RADIUS_TILES

static func _citizen_needs_scheduled_task(
	citizen: Dictionary,
	schedule_phase: String
) -> bool:
	if not bool(citizen.get("alive", false)):
		return false

	var raw_current_task = citizen.get("current_task", {})

	if not raw_current_task is Dictionary:
		return false

	var current_task: Dictionary = raw_current_task

	if (
		str(current_task.get("kind", ""))
		!= WorldData.CITY_CITIZEN_TASK_KIND_NONE
	):
		return false

	return not _get_next_scheduled_task_request(
		citizen,
		schedule_phase
	).is_empty()


static func _get_next_scheduled_task_request(
	citizen: Dictionary,
	schedule_phase: String
) -> Dictionary:
	var raw_activity_rules = DEFAULT_SCHEDULE_ACTIVITY_RULES.get(
		schedule_phase,
		[]
	)

	if not raw_activity_rules is Array:
		return {}

	var activity_rules: Array = raw_activity_rules

	for raw_rule in activity_rules:
		var activity_rule := str(raw_rule)
		var task_request := (
			_get_scheduled_activity_task_request(
				citizen,
				activity_rule
			)
		)

		if not task_request.is_empty():
			return task_request

	return {}


static func _get_scheduled_activity_task_request(
	citizen: Dictionary,
	activity_rule: String
) -> Dictionary:
	match activity_rule:
		SCHEDULE_ACTIVITY_OUTSTANDING_OBLIGATION:
			return _get_outstanding_obligation_task_request(
				citizen
			)
		SCHEDULE_ACTIVITY_ASSIGNED_WORK:
			return _get_assigned_work_task_request(citizen)
		SCHEDULE_ACTIVITY_ASSIGNED_HOME:
			return _get_assigned_home_task_request(citizen)

	return {}


static func _get_outstanding_obligation_task_request(
	citizen: Dictionary
) -> Dictionary:
	var citizen_id := int(citizen.get("id", -1))

	if citizen_id <= 0:
		return {}

	var cargo := WorldData.get_city_citizen_haul_cargo(
		citizen_id
	)
	var cargo_amount := maxi(
		int(cargo.get("amount", 0)),
		0
	)
	var current_haul := WorldData.get_city_citizen_current_haul(
		citizen_id
	)

	if cargo_amount > 0:
		var raw_source = current_haul.get("source", {})
		var raw_requester = current_haul.get("requester", {})

		if not raw_source is Dictionary:
			return {}

		if not raw_requester is Dictionary:
			return {}

		var reason := str(
			current_haul.get(
				"reason",
				WorldData.CITY_CITIZEN_HAUL_REASON_OUTSTANDING_CARGO
			)
		)

		if reason == WorldData.CITY_CITIZEN_HAUL_REASON_NONE:
			reason = (
				WorldData.CITY_CITIZEN_HAUL_REASON_OUTSTANDING_CARGO
			)

		return (
			CitizenHaulingSystemScript
			.make_public_storage_haul_task_request({
				"city_world": WorldData.official_city_world,
				"citizen": citizen,
				"source": raw_source,
				"resource_type": str(
					cargo.get(
						"resource_type",
						WorldData.RESOURCE_NONE
					)
				),
				"requested_amount": cargo_amount,
				"reason": reason,
				"requester": raw_requester,
				"source_access_purpose": str(
					current_haul.get(
						"source_access_purpose",
						WorldData
						.CONTAINER_HAUL_PURPOSE_WORKPLACE_OUTPUT
					)
				),
				"destination_access_purpose": (
					WorldData.CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE
				),
				"task_source": (
					WorldData.CITY_CITIZEN_TASK_SOURCE_SCHEDULE
				),
				"task_priority": (
					OUTSTANDING_CARGO_HAUL_TASK_PRIORITY
				),
			})
		)

	# Off-shift workers keep taking workplace-output trips until the buffer is
	# empty or no reachable public storage has room, then return home. Existing
	# cargo remains an obligation at any time.
	if is_work_shift_active():
		return {}

	var home_id := int(citizen.get("home_object_id", -1))
	var home := WorldData.get_city_object_by_id(home_id)

	if (
		home_id > 0
		and not home.is_empty()
		and _citizen_has_satisfied_home_arrival(citizen, home)
	):
		return {}

	var workplace_id := int(
		citizen.get("job_object_id", -1)
	)
	var workplace := WorldData.get_city_object_by_id(
		workplace_id
	)

	if (
		workplace_id <= 0
		or workplace.is_empty()
		or not WorldData.city_object_is_workplace(workplace)
	):
		return {}

	var remaining_carry_capacity := (
		WorldData.get_city_citizen_available_haul_capacity(
			citizen_id
		)
	)

	if remaining_carry_capacity <= 0:
		return {}

	var source := WorldData.make_city_citizen_haul_endpoint(
		workplace_id
	)

	for resource in WorldData.get_city_object_output_resources(
		workplace
	):
		var stored_amount := (
			WorldData.get_city_object_stored_resource_amount(
				workplace,
				resource
			)
		)
		var requested_amount := mini(
			stored_amount,
			remaining_carry_capacity
		)

		if requested_amount <= 0:
			continue

		var task_request := (
			CitizenHaulingSystemScript
			.make_public_storage_haul_task_request({
				"city_world": WorldData.official_city_world,
				"citizen": citizen,
				"source": source,
				"resource_type": resource,
				"requested_amount": requested_amount,
				"reason": (
					WorldData
					.CITY_CITIZEN_HAUL_REASON_WORKPLACE_OUTPUT_BEFORE_HOME
				),
				"requester": source,
				"source_access_purpose": (
					WorldData
					.CONTAINER_HAUL_PURPOSE_WORKPLACE_OUTPUT
				),
				"destination_access_purpose": (
					WorldData.CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE
				),
				"task_source": (
					WorldData.CITY_CITIZEN_TASK_SOURCE_SCHEDULE
				),
				"task_priority": (
					SCHEDULED_OUTPUT_HAUL_TASK_PRIORITY
				),
			})
		)

		if not task_request.is_empty():
			return task_request

	return {}


static func _get_assigned_work_task_request(
	citizen: Dictionary
) -> Dictionary:
	if not _citizen_needs_scheduled_work_task(citizen):
		return {}

	return {
		"kind": WorldData.CITY_CITIZEN_TASK_KIND_WORK,
		"source": (
			WorldData.CITY_CITIZEN_TASK_SOURCE_SCHEDULE
		),
		"priority": SCHEDULED_WORK_TASK_PRIORITY,
		"target_object_id": int(
			citizen.get("job_object_id", -1)
		),
		"player_locked": false
	}


static func _get_assigned_home_task_request(
	citizen: Dictionary
) -> Dictionary:
	if not _citizen_needs_scheduled_return_home_task(citizen):
		return {}

	return {
		"kind": WorldData.CITY_CITIZEN_TASK_KIND_RETURN_HOME,
		"source": (
			WorldData.CITY_CITIZEN_TASK_SOURCE_SCHEDULE
		),
		"priority": SCHEDULED_RETURN_HOME_TASK_PRIORITY,
		"target_object_id": int(
			citizen.get("home_object_id", -1)
		),
		"player_locked": false
	}

static func _queue_citizen_id(citizen_id: int) -> void:
	if citizen_id <= 0:
		return

	if _pending_decision_id_lookup.has(citizen_id):
		return

	_pending_decision_ids.append(citizen_id)
	_pending_decision_id_lookup[citizen_id] = true


static func _process_decision_queue(
	schedule_phase: String
) -> void:
	var processed_count := 0

	while (
		processed_count < MAX_DECISIONS_PER_TICK
		and not _pending_decision_ids.is_empty()
	):
		var citizen_id: int = _pending_decision_ids.pop_front()
		_pending_decision_id_lookup.erase(citizen_id)
		processed_count += 1

		var citizen := WorldData.get_city_citizen_by_id(
			citizen_id
		)

		if not _citizen_needs_scheduled_task(
			citizen,
			schedule_phase
		):
			continue

		var task_request := _get_next_scheduled_task_request(
			citizen,
			schedule_phase
		)

		if task_request.is_empty():
			continue

		var task_was_assigned := (
			WorldData.assign_city_citizen_task(
				citizen_id,
				task_request
			)
		)

		if not task_was_assigned:
			continue

		_clear_idle_activity_runtime(citizen_id)

		if (
			str(citizen.get("movement_state", ""))
			!= WorldData.CITY_CITIZEN_MOVEMENT_STATE_IDLE
		):
			WorldData.cancel_city_citizen_movement(
				citizen_id
			)
static func _clear_schedule_sourced_tasks() -> void:
	_clear_decision_queue()

	for raw_citizen in WorldData.city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var raw_current_task = citizen.get("current_task", {})

		if not raw_current_task is Dictionary:
			continue

		var current_task: Dictionary = raw_current_task

		if (
			str(current_task.get("source", ""))
			!= WorldData.CITY_CITIZEN_TASK_SOURCE_SCHEDULE
		):
			continue

		# A schedule transition must not strand or erase physical cargo. Hauls
		# finish independently, then the next schedule decision can run.
		if (
			str(current_task.get("kind", ""))
			== WorldData.CITY_CITIZEN_TASK_KIND_HAUL
		):
			continue

		var citizen_id := int(citizen.get("id", -1))

		if citizen_id <= 0:
			continue

		if WorldData.clear_city_citizen_task(
			citizen_id,
			WorldData.CITY_CITIZEN_TASK_SOURCE_SCHEDULE
		):
			WorldData.cancel_city_citizen_movement(
				citizen_id
			)
			_clear_idle_activity_runtime(citizen_id)

static func _clear_decision_queue() -> void:
	_pending_decision_ids.clear()
	_pending_decision_id_lookup.clear()


static func _process_bounded_idle_behaviors(
	work_shift_is_active: bool
) -> void:
	var citizen_count := WorldData.city_citizens.size()

	if citizen_count <= 0:
		_idle_scan_cursor = 0
		return

	var city_world: WorldData = WorldData.official_city_world

	if city_world == null:
		return

	var scan_count := mini(
		citizen_count,
		MAX_IDLE_SCANS_PER_TICK
	)
	var path_requests_remaining := (
		MAX_IDLE_PATH_REQUESTS_PER_TICK
	)

	for _scan_index in range(scan_count):
		var citizen_index := _idle_scan_cursor % citizen_count
		_idle_scan_cursor = (
			(_idle_scan_cursor + 1) % citizen_count
		)

		var raw_citizen = WorldData.city_citizens[
			citizen_index
		]

		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_id := int(citizen.get("id", -1))

		if citizen_id <= 0:
			continue

		if not _citizen_is_available_for_idle_behavior(
			citizen,
			work_shift_is_active
		):
			_clear_idle_activity_runtime(citizen_id)
			continue

		var raw_current_tile = citizen.get(
			"city_tile_position",
			WorldData.INVALID_CITY_TILE_POSITION
		)

		if not raw_current_tile is Vector2i:
			_clear_idle_activity_runtime(citizen_id)
			continue

		var current_tile: Vector2i = raw_current_tile

		if not WorldData.is_city_tile_walkable_for_citizen(
			city_world,
			current_tile,
			citizen_id
		):
			_clear_idle_activity_runtime(citizen_id)
			continue

		var movement_state := str(
			citizen.get(
				"movement_state",
				WorldData.CITY_CITIZEN_MOVEMENT_STATE_IDLE
			)
		)

		if (
			movement_state
			== WorldData.CITY_CITIZEN_MOVEMENT_STATE_MOVING
		):
			continue

		if (
			movement_state
			== WorldData.CITY_CITIZEN_MOVEMENT_STATE_BLOCKED
		):
			WorldData.cancel_city_citizen_movement(citizen_id)
			_idle_anchor_tile_by_citizen_id[citizen_id] = (
				current_tile
			)
			_schedule_next_idle_decision(citizen_id)
			continue

		var anchor_tile := _get_idle_anchor_tile(
			citizen_id,
			current_tile
		)

		if not _next_idle_decision_minute_by_citizen_id.has(
			citizen_id
		):
			_schedule_next_idle_decision(citizen_id)
			continue

		var next_decision_minute := int(
			_next_idle_decision_minute_by_citizen_id.get(
				citizen_id,
				SimulationClock.absolute_world_minutes
			)
		)

		if (
			SimulationClock.absolute_world_minutes
			< next_decision_minute
		):
			continue

		var choice_sequence := (
			_advance_idle_choice_sequence(citizen_id)
		)
		_next_idle_decision_minute_by_citizen_id.erase(
			citizen_id
		)

		if _idle_choice_is_to_remain_still(
			citizen_id,
			choice_sequence
		):
			_schedule_next_idle_decision(citizen_id)
			continue

		if path_requests_remaining <= 0:
			_schedule_next_idle_decision(citizen_id)
			continue

		path_requests_remaining -= 1

		var wander_was_assigned := _try_assign_idle_wander(
			city_world,
			citizen_id,
			current_tile,
			anchor_tile,
			choice_sequence
		)

		if not wander_was_assigned:
			_schedule_next_idle_decision(citizen_id)


static func _citizen_is_available_for_idle_behavior(
	citizen: Dictionary,
	work_shift_is_active: bool
) -> bool:
	if not bool(citizen.get("alive", false)):
		return false

	if (
		str(citizen.get("state", ""))
		!= WorldData.CITY_CITIZEN_STATE_IDLE
	):
		return false

	var raw_current_task = citizen.get("current_task", {})

	if not raw_current_task is Dictionary:
		return false

	var current_task: Dictionary = raw_current_task

	if (
		str(current_task.get("kind", ""))
		!= WorldData.CITY_CITIZEN_TASK_KIND_NONE
	):
		return false

	if (
		WorldData.get_city_citizen_haul_cargo_amount(
			int(citizen.get("id", -1))
		) > 0
	):
		return false

	if not work_shift_is_active:
		return true

	var workplace_id := int(
		citizen.get("job_object_id", -1)
	)

	if workplace_id <= 0:
		return true

	var workplace := WorldData.get_city_object_by_id(
		workplace_id
	)

	return (
		workplace.is_empty()
		or not WorldData.city_object_is_workplace(workplace)
	)


static func _clear_idle_activity_runtime(citizen_id: int) -> void:
	_idle_anchor_tile_by_citizen_id.erase(citizen_id)
	_next_idle_decision_minute_by_citizen_id.erase(citizen_id)


static func _schedule_next_idle_decision(citizen_id: int) -> void:
	var choice_sequence := int(
		_idle_choice_sequence_by_citizen_id.get(
			citizen_id,
			0
		)
	)
	var wait_range := (
		IDLE_MAXIMUM_WAIT_MINUTES
		- IDLE_MINIMUM_WAIT_MINUTES
		+ 1
	)
	var deterministic_value := _get_idle_deterministic_value(
		citizen_id,
		choice_sequence,
		17
	)
	var wait_minutes := (
		IDLE_MINIMUM_WAIT_MINUTES
		+ posmod(deterministic_value, wait_range)
	)

	_next_idle_decision_minute_by_citizen_id[citizen_id] = (
		SimulationClock.absolute_world_minutes
		+ wait_minutes
	)


static func _advance_idle_choice_sequence(citizen_id: int) -> int:
	var next_sequence := (
		int(
			_idle_choice_sequence_by_citizen_id.get(
				citizen_id,
				0
			)
		)
		+ 1
	)
	_idle_choice_sequence_by_citizen_id[citizen_id] = next_sequence
	return next_sequence


static func _idle_choice_is_to_remain_still(
	citizen_id: int,
	choice_sequence: int
) -> bool:
	var deterministic_value := _get_idle_deterministic_value(
		citizen_id,
		choice_sequence,
		31
	)

	return (
		posmod(deterministic_value, 100)
		< IDLE_STAND_CHANCE_PERCENT
	)


static func _get_idle_anchor_tile(
	citizen_id: int,
	current_tile: Vector2i
) -> Vector2i:
	var raw_anchor_tile = _idle_anchor_tile_by_citizen_id.get(
		citizen_id,
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if raw_anchor_tile is Vector2i:
		var anchor_tile: Vector2i = raw_anchor_tile
		var distance_from_anchor := (
			absi(current_tile.x - anchor_tile.x)
			+ absi(current_tile.y - anchor_tile.y)
		)

		if distance_from_anchor <= IDLE_ANCHOR_RADIUS_TILES:
			return anchor_tile

	_idle_anchor_tile_by_citizen_id[citizen_id] = current_tile
	return current_tile


static func _try_assign_idle_wander(
	city_world: WorldData,
	citizen_id: int,
	current_tile: Vector2i,
	anchor_tile: Vector2i,
	choice_sequence: int
) -> bool:
	var candidate_tiles := _get_idle_wander_candidate_tiles(
		city_world,
		citizen_id,
		current_tile,
		anchor_tile
	)

	if candidate_tiles.is_empty():
		return false

	var deterministic_value := _get_idle_deterministic_value(
		citizen_id,
		choice_sequence,
		47
	)
	var selected_index := posmod(
		deterministic_value,
		candidate_tiles.size()
	)
	var selected_tile: Vector2i = candidate_tiles[selected_index]
	var path_result := (
		CityNavigationSystemScript.find_path_to_any_city_tile(
			city_world,
			current_tile,
			[selected_tile],
			IDLE_MAXIMUM_EXPANDED_NODES,
			citizen_id
		)
	)

	if not bool(path_result.get("success", false)):
		return false

	var raw_path = path_result.get("path", [])

	if not raw_path is Array:
		return false

	var movement_path: Array = raw_path
	var path_step_count := maxi(movement_path.size() - 1, 0)

	if (
		path_step_count <= 0
		or path_step_count > IDLE_MAXIMUM_PATH_STEPS
	):
		return false

	return WorldData.assign_city_citizen_movement_order(
		citizen_id,
		movement_path
	)


static func _get_idle_wander_candidate_tiles(
	city_world: WorldData,
	citizen_id: int,
	current_tile: Vector2i,
	anchor_tile: Vector2i
) -> Array[Vector2i]:
	var candidate_tiles: Array[Vector2i] = []

	for offset_y in range(
		-IDLE_ANCHOR_RADIUS_TILES,
		IDLE_ANCHOR_RADIUS_TILES + 1
	):
		for offset_x in range(
			-IDLE_ANCHOR_RADIUS_TILES,
			IDLE_ANCHOR_RADIUS_TILES + 1
		):
			var anchor_distance := (
				absi(offset_x) + absi(offset_y)
			)

			if (
				anchor_distance <= 0
				or anchor_distance > IDLE_ANCHOR_RADIUS_TILES
			):
				continue

			var candidate_tile := (
				anchor_tile + Vector2i(offset_x, offset_y)
			)
			var destination_distance := (
				absi(candidate_tile.x - current_tile.x)
				+ absi(candidate_tile.y - current_tile.y)
			)

			if (
				destination_distance <= 0
				or destination_distance
				> IDLE_MAXIMUM_DESTINATION_DISTANCE
			):
				continue

			if not WorldData.is_city_tile_walkable_for_citizen(
				city_world,
				candidate_tile,
				citizen_id
			):
				continue

			if WorldData.has_living_city_citizen_at_tile(
				candidate_tile
			):
				continue

			candidate_tiles.append(candidate_tile)

	return candidate_tiles


static func _get_idle_deterministic_value(
	citizen_id: int,
	choice_sequence: int,
	salt: int
) -> int:
	var deterministic_value := citizen_id * 73_856_093
	deterministic_value ^= choice_sequence * 19_349_663
	deterministic_value ^= salt * 83_492_791
	deterministic_value &= 0x7fffffff
	return deterministic_value
