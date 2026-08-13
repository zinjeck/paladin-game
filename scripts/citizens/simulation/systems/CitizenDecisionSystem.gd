extends RefCounted
class_name CitizenDecisionSystem

# File responsibility: Bounded citizen intent selection for commands, needs, schedules, hauling, and idling.
# Navigation regions are organizational only; they do not define runtime ownership.

const CityNavigationSystemScript = preload(
	"res://scripts/city/simulation/systems/CityNavigationSystem.gd"
)
const CitizenHaulingSystemScript = preload(
	"res://scripts/citizens/simulation/systems/CitizenHaulingSystem.gd"
)
const CityConstructionSystemScript = preload(
	"res://scripts/city/simulation/systems/CityConstructionSystem.gd"
)
const CityWorkSystemScript = preload(
	"res://scripts/city/simulation/systems/CityWorkSystem.gd"
)
const CityResourceMatcherScript = preload(
	"res://scripts/city/simulation/systems/CityResourceMatcher.gd"
)

# Temporary shared schedule for the first autonomous work pass.
# These constants are intentionally centralized so the schedule can later be
# replaced by workplace, profession, household, or policy-driven schedules.
const WORK_SHIFT_START_MINUTE_OF_DAY: int = 8 * 60
const WORK_SHIFT_END_MINUTE_OF_DAY: int = 17 * 60
const CRITICAL_FOOD_TASK_PRIORITY: int = 140
const NORMAL_FOOD_TASK_PRIORITY: int = 85
const SCHEDULED_WORK_TASK_PRIORITY: int = 100
const OUTSTANDING_CARGO_HAUL_TASK_PRIORITY: int = 150
const SCHEDULED_OUTPUT_HAUL_TASK_PRIORITY: int = 75
const SCHEDULED_HOME_FOOD_DELIVERY_TASK_PRIORITY: int = 65
const SCHEDULED_RETURN_HOME_TASK_PRIORITY: int = 50
const AUTONOMOUS_GROUND_PILE_HAUL_TASK_PRIORITY: int = 90
const AUTONOMOUS_WORKPLACE_OUTPUT_HAUL_TASK_PRIORITY: int = 70
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
		SCHEDULE_ACTIVITY_ASSIGNED_HOME,
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
const IDLE_STAND_CHANCE_PERCENT: int = 35
const IDLE_MINIMUM_WAIT_MINUTES: int = 5
const IDLE_MAXIMUM_WAIT_MINUTES: int = 15
const IDLE_ANCHOR_RADIUS_TILES: int = 4
const IDLE_MAXIMUM_DESTINATION_DISTANCE: int = 4
const IDLE_MAXIMUM_PATH_STEPS: int = 6
const IDLE_MAXIMUM_EXPANDED_NODES: int = 96
const MAX_IDLE_SCANS_PER_TICK: int = 64
const MAX_IDLE_PATH_REQUESTS_PER_TICK: int = 1
const MAX_AUTONOMOUS_HAUL_ASSIGNMENTS_PER_TICK: int = 2
const MAX_AUTONOMOUS_HAUL_CANDIDATES_PER_TICK: int = 32
const MAX_AUTONOMOUS_HAUL_TASK_BUILD_ATTEMPTS_PER_TICK: int = 4
const AUTONOMOUS_HAUL_EXACT_HEURISTIC_WEIGHT: int = 1
# Each successful assignment invalidates the remaining pass-local route witnesses.
# Dispatch at most two citizens per tick so a populated work board cannot
# multiply exact city-wide path searches into a single-frame burst. At 3x this
# still dispatches more than seven citizens per real-time second and preserves
# the established two-citizen road-assignment contract.
const MAX_PLAYER_COMMAND_ASSIGNMENTS_PER_TICK: int = 2
const MAX_FOOD_TASK_ASSIGNMENTS_PER_TICK: int = 4
const MAX_FOOD_SOURCE_PATH_REQUESTS_PER_TICK: int = 8
const HOME_FOOD_SOURCE_MAX_EXTRA_TILES: int = 4

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
static var _autonomous_haul_scan_cursor: int = 0
static var _critical_food_scan_cursor: int = 0
static var _normal_food_scan_cursor: int = 0

#region Decision Tick Entry Point

static func run_tick(
	_tick_index: int,
	minutes_advanced: int
) -> void:
	if minutes_advanced <= 0:
		return

	if (
		WorldPoliticalState.get_current_city_world() == null
		or not WorldData.player_city_founded
		or CityCitizenRegistrySystem.get_current_state().citizens.is_empty()
	):
		reset_runtime_state()
		return

	var work_shift_is_active := is_work_shift_active()
	var schedule_phase := _get_schedule_phase(
		work_shift_is_active
	)

	# Newly produced output first expands the oldest compatible pre-pickup load.
	# Only the remainder is visible to autonomous task matching below.
	CityLogisticsSystem.expand_pending_city_haul_reservations()

	# Player designations outrank every scheduled or autonomous activity for
	# unemployed citizens. Invalid targets are pruned before workers claim them.
	CityWorkSystem.prune_invalid_city_player_commands()
	CityWorkSystem.repair_stale_city_player_command_claims()
	CityConstructionSystemScript.refresh_all_city_construction_sites()
	var runtime_work_candidate_cache := (
		CityWorkSystemScript.synchronize_player_work_board()
	)
	_process_player_commands(runtime_work_candidate_cache)
	_process_food_needs(true)

	if not _runtime_initialized:
		_runtime_initialized = true
		_work_shift_was_active = work_shift_is_active
		_observed_assignment_version = (
			CityAssignmentSystem.get_city_assignment_version()
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
		!= CityAssignmentSystem.get_city_assignment_version()
	):
		_observed_assignment_version = (
			CityAssignmentSystem.get_city_assignment_version()
		)
		_idle_anchor_tile_by_citizen_id.clear()
		_next_idle_decision_minute_by_citizen_id.clear()

		_queue_all_eligible_scheduled_tasks(
			schedule_phase
		)

	_queue_bounded_recovery_candidates(
		schedule_phase
	)

	# Resolve real schedule obligations first, but defer the two home-bound
	# activities: pantry provisioning and return_home. This keeps assigned work
	# and outstanding physical cargo ahead of ordinary hunger and logistics.
	_process_decision_queue(
		schedule_phase,
		SCHEDULED_HOME_FOOD_DELIVERY_TASK_PRIORITY
	)
	_process_food_needs(false)

	# Autonomous logistics then outrank the deferred home-bound schedule. A
	# citizen who just delivered one load can therefore claim the next valid
	# ground-pile or workplace-output trip immediately instead of walking home
	# between loads. If no reachable haul can use remaining public container
	# space, the final schedule pass below sends the citizen home in this tick.
	_process_bounded_autonomous_hauling(schedule_phase)

	# The assignment count is deliberately bounded, so a single decision tick
	# may not dispatch every load the city still needs. Keep the deferred home
	# queue intact while unreserved, deliverable logistics work remains. Further
	# haulers are assigned on following ticks; citizens are released home only
	# once existing haulers can absorb the remainder or public storage is full.
	if not _has_unassigned_autonomous_haul_work():
		_process_decision_queue(schedule_phase)

	_process_bounded_idle_behaviors(
		work_shift_is_active
	)

#endregion

#region Player Command Assignment

static func _process_player_commands(
	runtime_candidate_by_order_by_citizen_id: Dictionary = {}
) -> void:
	var assigned_count := 0

	for raw_citizen in CityCitizenRegistrySystem.get_current_state().citizens:
		if assigned_count >= MAX_PLAYER_COMMAND_ASSIGNMENTS_PER_TICK:
			return

		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_id := int(citizen.get("id", -1))

		if (
			citizen_id <= 0
			or not bool(citizen.get("alive", false))
			or int(citizen.get("job_object_id", -1)) > 0
		):
			continue

		var raw_current_task = citizen.get("current_task", {})

		if raw_current_task is Dictionary:
			var current_task: Dictionary = raw_current_task

			if (
				str(current_task.get("source", ""))
				== CityCitizens.CITY_CITIZEN_TASK_SOURCE_PLAYER
			):
				continue

		var raw_precomputed_candidates = (
			runtime_candidate_by_order_by_citizen_id.get(
				citizen_id,
				{}
			)
		)
		var precomputed_candidates: Dictionary = (
			raw_precomputed_candidates
			if raw_precomputed_candidates is Dictionary
			else {}
		)
		runtime_candidate_by_order_by_citizen_id.erase(citizen_id)
		var player_work := (
			CityWorkSystemScript.get_best_player_job_for_citizen(
				citizen_id,
				precomputed_candidates
			)
		)

		if player_work.is_empty():
			continue

		if not CitizenTaskSystem.prepare_unemployed_citizen_for_player_command(
			citizen_id
		):
			continue

		if not CityWorkSystemScript.assign_player_job(
			citizen_id,
			player_work
		):
			continue

		_clear_idle_activity_runtime(citizen_id)
		assigned_count += 1
		# Assignment mutates claims and capacity. Any unused witnesses were
		# measured before that mutation and must not be reused by later citizens.
		runtime_candidate_by_order_by_citizen_id.clear()
#endregion

#region Food Need Assignment

static func _process_food_needs(critical_only: bool) -> void:
	var candidates: Array = []

	for raw_citizen in CityCitizenRegistrySystem.get_current_state().citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_id := int(citizen.get("id", -1))

		if (
			citizen_id <= 0
			or not bool(citizen.get("alive", false))
			or not CitizenNeedsSystem.citizen_should_seek_food(citizen_id)
		):
			continue

		var is_critical := CitizenNeedsSystem.citizen_has_critical_food_need(
			citizen_id
		)

		if is_critical != critical_only:
			continue

		var current_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(citizen_id)
		var current_task_kind := str(
			current_task.get("kind", CityCitizens.CITY_CITIZEN_TASK_KIND_NONE)
		)

		if current_task_kind == CityCitizens.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD:
			continue

		candidates.append({
			"citizen_id": citizen_id,
			"hunger": CitizenNeedsSystem.get_city_citizen_hunger(citizen_id),
		})

	candidates.sort_custom(_sort_food_need_candidates)

	if candidates.is_empty():
		return

	var start_index := _take_food_scan_start_index(
		critical_only,
		candidates.size()
	)
	var assigned_count := 0
	var path_requests_remaining := MAX_FOOD_SOURCE_PATH_REQUESTS_PER_TICK

	for offset in range(candidates.size()):
		if (
			assigned_count >= MAX_FOOD_TASK_ASSIGNMENTS_PER_TICK
			or path_requests_remaining <= 0
		):
			return

		var raw_candidate = candidates[
			(start_index + offset) % candidates.size()
		]

		if not raw_candidate is Dictionary:
			continue

		var citizen_id := int(raw_candidate.get("citizen_id", -1))
		var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
		var available_food_capacity := (
			CityCitizenInventorySystem.get_city_citizen_personal_inventory_free_space(citizen_id)
			if critical_only
			else CityCitizenInventorySystem.get_city_citizen_inventory_free_space(citizen_id)
		)
		var food_result := _find_best_food_source_for_citizen(
			citizen,
			path_requests_remaining,
			available_food_capacity
		)
		path_requests_remaining -= int(food_result.get("path_requests_used", 0))

		if food_result.is_empty() or int(food_result.get("object_id", -1)) <= 0:
			continue

		var current_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(citizen_id)
		var current_task_kind := str(
			current_task.get(
				"kind",
				CityCitizens.CITY_CITIZEN_TASK_KIND_NONE
			)
		)

		# A food opportunity is proven before any current activity is released.
		# Normal hunger waits for the next safe physical boundary; critical
		# hunger releases through the task's real ownership boundary.
		if current_task_kind != CityCitizens.CITY_CITIZEN_TASK_KIND_NONE:
			var prepared_for_food := false

			if critical_only:
				prepared_for_food = (
					_prepare_citizen_for_critical_food_interrupt(
						citizen_id,
						current_task
					)
				)
			else:
				prepared_for_food = (
					CitizenTaskSystem
					.prepare_citizen_for_normal_food_interrupt(
						citizen_id
					)
				)

			if not prepared_for_food:
				continue

		var task_request := {
			"kind": CityCitizens.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD,
			"source": CityCitizens.CITY_CITIZEN_TASK_SOURCE_AUTONOMY,
			"priority": (
				CRITICAL_FOOD_TASK_PRIORITY
				if critical_only
				else NORMAL_FOOD_TASK_PRIORITY
			),
			"target_object_id": int(food_result.get("object_id", -1)),
			"target_tile": food_result.get(
				"target_tile",
				CityCitizens.INVALID_CITY_TILE_POSITION
			),
			"food_resource_type": str(
				food_result.get("resource_type", WorldData.RESOURCE_NONE)
			),
			"food_requested_amount": int(
				food_result.get("requested_amount", 0)
			),
			"food_source_endpoint_kind": str(
				food_result.get(
					"source_kind",
					CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER
				)
			),
			"food_source_access_purpose": (
				CityObjectCatalog.CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_PERSONAL_FOOD
			),
			"player_locked": false,
		}

		if not CityCitizenTaskRuntimeSystem.assign_city_citizen_task(citizen_id, task_request):
			continue

		CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)
		_clear_idle_activity_runtime(citizen_id)
		assigned_count += 1


static func _prepare_citizen_for_critical_food_interrupt(
	citizen_id: int,
	current_task: Dictionary
) -> bool:
	var task_source := str(
		current_task.get(
			"source",
			CityCitizens.CITY_CITIZEN_TASK_SOURCE_NONE
		)
	)

	if task_source != CityCitizens.CITY_CITIZEN_TASK_SOURCE_SCHEDULE:
		return (
			CitizenTaskSystem
			.prepare_citizen_for_critical_food_interrupt(citizen_id)
		)

	var task_kind := str(
		current_task.get(
			"kind",
			CityCitizens.CITY_CITIZEN_TASK_KIND_NONE
		)
	)
	var released := false

	# Schedule-owned hauling may carry physical resources. Use the existing
	# no-loss interrupt gateway with the schedule source instead of pretending
	# the task belongs to autonomy.
	if task_kind == CityCitizens.CITY_CITIZEN_TASK_KIND_HAUL:
		released = (
			CitizenHaulingSystemScript
			.drop_citizen_haul_cargo_for_priority_interrupt(
				WorldPoliticalState.get_current_city_world(),
				citizen_id,
				CityCitizens.CITY_CITIZEN_TASK_SOURCE_SCHEDULE
			)
		)
	else:
		released = CityCitizenTaskRuntimeSystem.clear_city_citizen_task(
			citizen_id,
			CityCitizens.CITY_CITIZEN_TASK_SOURCE_SCHEDULE
		)

	if released:
		CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)
		_clear_idle_activity_runtime(citizen_id)

	return released


static func _take_food_scan_start_index(
	critical_only: bool,
	candidate_count: int
) -> int:
	if candidate_count <= 0:
		return 0

	if critical_only:
		var start_index := posmod(
			_critical_food_scan_cursor,
			candidate_count
		)
		_critical_food_scan_cursor = posmod(
			start_index + 1,
			candidate_count
		)
		return start_index

	var start_index := posmod(
		_normal_food_scan_cursor,
		candidate_count
	)
	_normal_food_scan_cursor = posmod(
		start_index + 1,
		candidate_count
	)
	return start_index


static func _sort_food_need_candidates(a: Dictionary, b: Dictionary) -> bool:
	var hunger_a := int(a.get("hunger", CityCitizens.MAX_CITIZEN_HUNGER))
	var hunger_b := int(b.get("hunger", CityCitizens.MAX_CITIZEN_HUNGER))

	if hunger_a != hunger_b:
		return hunger_a < hunger_b

	return int(a.get("citizen_id", -1)) < int(b.get("citizen_id", -1))


static func _find_best_food_source_for_citizen(
	citizen: Dictionary,
	maximum_path_requests: int,
	available_food_capacity: int
) -> Dictionary:
	var citizen_id := int(citizen.get("id", -1))

	if (
		citizen_id <= 0
		or maximum_path_requests <= 0
		or available_food_capacity <= 0
	):
		return {}

	var desired_nutrition := CitizenNeedsSystem.get_citizen_food_need_nutrition(
		citizen_id
	)

	if desired_nutrition <= 0:
		return {}

	return CityResourceMatcherScript.find_best_survival_food_source(
		citizen,
		desired_nutrition,
		available_food_capacity,
		maximum_path_requests
	)


#endregion

#region Schedule State and Scheduled Tasks

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
	_autonomous_haul_scan_cursor = 0
	_critical_food_scan_cursor = 0
	_normal_food_scan_cursor = 0


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
	for raw_citizen in CityCitizenRegistrySystem.get_current_state().citizens:
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
	var citizen_count := CityCitizenRegistrySystem.get_current_state().citizens.size()

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

		var raw_citizen = CityCitizenRegistrySystem.get_current_state().citizens[
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

	var workplace := CityObjectSystem.get_city_object_by_id(
		workplace_id
	)

	if (
		workplace.is_empty()
		or not CityObjectCatalog.city_object_is_workplace(workplace)
	):
		return false

	var raw_current_task = citizen.get("current_task", {})

	if not raw_current_task is Dictionary:
		return false

	var current_task: Dictionary = raw_current_task

	return (
		str(current_task.get("kind", ""))
		== CityCitizens.CITY_CITIZEN_TASK_KIND_NONE
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

	var home := CityObjectSystem.get_city_object_by_id(home_id)
	var citizen_id := int(citizen.get("id", -1))

	if (
		home.is_empty()
		or CityObjectCatalog.get_city_object_resident_capacity(home) <= 0
		or not CityObjectSystem.city_object_supports_citizen_interior(home)
		or not CityAssignmentSystem.get_city_object_resident_ids(
			home
		).has(citizen_id)
		or not CityNavigationSystem.city_citizen_can_access_object_interior(
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
		== CityCitizens.CITY_CITIZEN_TASK_KIND_NONE
	)


static func _citizen_has_satisfied_home_arrival(
	citizen: Dictionary,
	home: Dictionary
) -> bool:
	var home_tiles := CityObjectSystem.get_city_object_footprint_tiles(
		home
	)
	var raw_current_tile = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if (
		raw_current_tile is Vector2i
		and home_tiles.has(raw_current_tile)
	):
		return true

	var citizen_id := int(citizen.get("id", -1))
	var raw_anchor_tile = _idle_anchor_tile_by_citizen_id.get(
		citizen_id,
		CityCitizens.INVALID_CITY_TILE_POSITION
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
		!= CityCitizens.CITY_CITIZEN_TASK_KIND_NONE
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

	var cargo := CityCitizenInventorySystem.get_city_citizen_haul_cargo(
		citizen_id
	)
	var cargo_amount := maxi(
		int(cargo.get("amount", 0)),
		0
	)
	var current_haul := CityCitizenTaskRuntimeSystem.get_city_citizen_current_haul(
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
				CityCitizens.CITY_CITIZEN_HAUL_REASON_OUTSTANDING_CARGO
			)
		)

		if reason == CityCitizens.CITY_CITIZEN_HAUL_REASON_NONE:
			reason = (
				CityCitizens.CITY_CITIZEN_HAUL_REASON_OUTSTANDING_CARGO
			)

		return (
			CitizenHaulingSystemScript
			.make_public_storage_haul_task_request({
				"city_world": WorldPoliticalState.get_current_city_world(),
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
						CityObjectCatalog.CONTAINER_HAUL_PURPOSE_WORKPLACE_OUTPUT
					)
				),
				"destination_access_purpose": (
					CityObjectCatalog.CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE
				),
				"task_source": (
					CityCitizens.CITY_CITIZEN_TASK_SOURCE_SCHEDULE
				),
				"task_priority": (
					OUTSTANDING_CARGO_HAUL_TASK_PRIORITY
				),
			})
		)

	# A carried load is the atomic obligation above. Once it is settled, normal
	# food seeking (31--70) outranks every new scheduled or logistical
	# activity once the carried load reaches its safe delivery boundary.
	if CitizenNeedsSystem.citizen_should_seek_food(citizen_id):
		return {}

	# Employed citizens work through the shift. Unemployed residents may still
	# provision their own household before settling into home-centered idling.
	if (
		is_work_shift_active()
		and int(citizen.get("job_object_id", -1)) > 0
	):
		return {}

	var home_id := int(citizen.get("home_object_id", -1))
	var home := CityObjectSystem.get_city_object_by_id(home_id)
	var has_satisfied_home_arrival := (
		home_id > 0
		and not home.is_empty()
		and _citizen_has_satisfied_home_arrival(citizen, home)
	)

	var workplace_id := int(
		citizen.get("job_object_id", -1)
	)
	var workplace := CityObjectSystem.get_city_object_by_id(
		workplace_id
	)

	var remaining_carry_capacity := (
		CityCitizenInventorySystem.get_city_citizen_available_haul_capacity(
			citizen_id
		)
	)

	if (
		not has_satisfied_home_arrival
		and remaining_carry_capacity > 0
		and workplace_id > 0
		and not workplace.is_empty()
		and CityObjectCatalog.city_object_is_workplace(workplace)
	):
		var source := CityLogisticsSystem.make_city_citizen_haul_endpoint(
			workplace_id
		)

		for resource in CityObjectCatalog.get_city_object_output_resources(
			workplace
		):
			var stored_amount := (
				CityResourceContainerSystem.get_city_object_stored_resource_amount(
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
					"city_world": WorldPoliticalState.get_current_city_world(),
					"citizen": citizen,
					"source": source,
					"resource_type": resource,
					"requested_amount": requested_amount,
					"reason": (
						CityCitizens.CITY_CITIZEN_HAUL_REASON_WORKPLACE_OUTPUT_BEFORE_HOME
					),
					"requester": source,
					"source_access_purpose": (
						CityObjectCatalog.CONTAINER_HAUL_PURPOSE_WORKPLACE_OUTPUT
					),
					"destination_access_purpose": (
						CityObjectCatalog.CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE
					),
					"task_source": (
						CityCitizens.CITY_CITIZEN_TASK_SOURCE_SCHEDULE
					),
					"task_priority": (
						SCHEDULED_OUTPUT_HAUL_TASK_PRIORITY
					),
			})
			)

			if not task_request.is_empty():
				return task_request

	return _get_scheduled_home_food_delivery_task_request(citizen)


static func _get_scheduled_home_food_delivery_task_request(
	citizen: Dictionary
) -> Dictionary:
	var citizen_id := int(citizen.get("id", -1))
	var home_id := int(citizen.get("home_object_id", -1))
	var home := CityObjectSystem.get_city_object_by_id(home_id)
	var raw_current_tile = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if (
		citizen_id <= 0
		or CitizenNeedsSystem.citizen_should_seek_food(citizen_id)
		or home_id <= 0
		or not raw_current_tile is Vector2i
		or not CityResourceMatcher.city_object_is_household_home(home)
		or CityResourceMatcher.get_city_home_unfulfilled_food_nutrition(home) <= 0
	):
		return {}

	var remaining_carry_capacity := (
		CityCitizenInventorySystem.get_city_citizen_available_haul_capacity(citizen_id)
	)

	if remaining_carry_capacity <= 0:
		return {}

	var destination := CityLogisticsSystem.make_city_citizen_haul_endpoint(
		home_id
	)
	var current_tile: Vector2i = raw_current_tile

	for resource in CityResourceCatalog.get_city_food_resource_types():
		var requested_amount := mini(
			remaining_carry_capacity,
			CityResourceMatcher.get_city_home_requested_food_units(
				home,
				resource
			)
		)

		if requested_amount <= 0:
			continue

		var source_result := (
			CityResourceMatcherScript.find_best_household_food_source(
				citizen,
				resource,
				requested_amount
			)
		)

		if source_result.is_empty():
			continue

		requested_amount = mini(
			requested_amount,
			maxi(
				int(source_result.get("available_amount", 0)),
				0
			)
		)

		if requested_amount <= 0:
			continue

		var task_request := (
			CitizenHaulingSystemScript.make_directed_haul_task_request({
				"city_world": WorldPoliticalState.get_current_city_world(),
				"citizen": citizen,
				"source": source_result.get("endpoint", {}),
				"destination": destination,
				"resource_type": resource,
				"requested_amount": requested_amount,
				"reason": (
					CityCitizens.CITY_CITIZEN_HAUL_REASON_SCHEDULED_HOME_FOOD_DELIVERY
				),
				"requester": destination,
				"source_access_purpose": (
					str(
						source_result.get(
							"source_access_purpose",
							CityObjectCatalog.CONTAINER_HAUL_PURPOSE_HOME_DELIVERY
						)
					)
				),
				"destination_access_purpose": (
					CityObjectCatalog.CONTAINER_HAUL_PURPOSE_HOME_DELIVERY
				),
				"task_source": (
					CityCitizens.CITY_CITIZEN_TASK_SOURCE_SCHEDULE
				),
				"task_priority": (
					SCHEDULED_HOME_FOOD_DELIVERY_TASK_PRIORITY
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

	# Hunger alone cannot suppress the work that may create the settlement's
	# first meal. The food pass preempts this request only after matching a real,
	# reachable source for this citizen.
	return {
		"kind": CityCitizens.CITY_CITIZEN_TASK_KIND_WORK,
		"source": (
			CityCitizens.CITY_CITIZEN_TASK_SOURCE_SCHEDULE
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

	# A hungry citizen with no obtainable food still has a valid home schedule.
	# A matched meal may interrupt this task through the normal or critical food
	# boundary, but hunger by itself must not strand the citizen near work.
	return {
		"kind": CityCitizens.CITY_CITIZEN_TASK_KIND_RETURN_HOME,
		"source": (
			CityCitizens.CITY_CITIZEN_TASK_SOURCE_SCHEDULE
		),
		"priority": SCHEDULED_RETURN_HOME_TASK_PRIORITY,
		"target_object_id": int(
			citizen.get("home_object_id", -1)
		),
		"player_locked": false
	}

#endregion

#region Decision Queue Processing

static func _queue_citizen_id(citizen_id: int) -> void:
	if citizen_id <= 0:
		return

	if _pending_decision_id_lookup.has(citizen_id):
		return

	_pending_decision_ids.append(citizen_id)
	_pending_decision_id_lookup[citizen_id] = true


static func _process_decision_queue(
	schedule_phase: String,
	minimum_priority_exclusive: int = (
		CityCitizens.CITY_CITIZEN_TASK_PRIORITY_NONE
	)
) -> void:
	var processed_count := 0
	var deferred_citizen_ids: Array[int] = []

	while (
		processed_count < MAX_DECISIONS_PER_TICK
		and not _pending_decision_ids.is_empty()
	):
		var citizen_id: int = _pending_decision_ids.pop_front()
		_pending_decision_id_lookup.erase(citizen_id)
		processed_count += 1

		var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(
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

		if (
			int(
				task_request.get(
					"priority",
					CityCitizens.CITY_CITIZEN_TASK_PRIORITY_NONE
				)
			)
			<= minimum_priority_exclusive
		):
			deferred_citizen_ids.append(citizen_id)
			continue

		var task_was_assigned := (
			CityCitizenTaskRuntimeSystem.assign_city_citizen_task(
				citizen_id,
				task_request
			)
		)

		if not task_was_assigned:
			continue

		_clear_idle_activity_runtime(citizen_id)

		if (
			str(citizen.get("movement_state", ""))
			!= CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_IDLE
		):
			CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(
				citizen_id
			)

	for citizen_id in deferred_citizen_ids:
		_queue_citizen_id(citizen_id)


static func _clear_schedule_sourced_tasks() -> void:
	_clear_decision_queue()

	for raw_citizen in CityCitizenRegistrySystem.get_current_state().citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var raw_current_task = citizen.get("current_task", {})

		if not raw_current_task is Dictionary:
			continue

		var current_task: Dictionary = raw_current_task

		if (
			str(current_task.get("source", ""))
			!= CityCitizens.CITY_CITIZEN_TASK_SOURCE_SCHEDULE
		):
			continue

		# A schedule transition must not strand or erase physical cargo. Hauls
		# finish independently, then the next schedule decision can run.
		if (
			str(current_task.get("kind", ""))
			== CityCitizens.CITY_CITIZEN_TASK_KIND_HAUL
		):
			continue

		var citizen_id := int(citizen.get("id", -1))

		if citizen_id <= 0:
			continue

		if CityCitizenTaskRuntimeSystem.clear_city_citizen_task(
			citizen_id,
			CityCitizens.CITY_CITIZEN_TASK_SOURCE_SCHEDULE
		):
			CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(
				citizen_id
			)
			_clear_idle_activity_runtime(citizen_id)

static func _clear_decision_queue() -> void:
	_pending_decision_ids.clear()
	_pending_decision_id_lookup.clear()


#endregion

#region Autonomous Hauling

static func _process_bounded_autonomous_hauling(
	schedule_phase: String
) -> void:
	var city_world: WorldData = WorldPoliticalState.get_current_city_world()

	if city_world == null:
		return

	var assigned_count := 0

	while assigned_count < MAX_AUTONOMOUS_HAUL_ASSIGNMENTS_PER_TICK:
		var candidates := _get_bounded_autonomous_haul_candidates(
			schedule_phase
		)

		if candidates.is_empty():
			return

		# Loose ground resources are considered before protected workplace
		# buffers. If no pile is deliverable, citizens may still perform a
		# different valid workplace-output haul rather than idling.
		if _try_assign_best_autonomous_haul(
			city_world,
			candidates,
			_get_ground_pile_haul_opportunities()
		):
			assigned_count += 1
			continue

		if _try_assign_best_autonomous_haul(
			city_world,
			candidates,
			_get_workplace_output_haul_opportunities()
		):
			assigned_count += 1
			continue

		return


static func _get_bounded_autonomous_haul_candidates(
	schedule_phase: String
) -> Array:
	var candidates: Array = []
	var citizen_count := CityCitizenRegistrySystem.get_current_state().citizens.size()

	if citizen_count <= 0:
		_autonomous_haul_scan_cursor = 0
		return candidates

	var scanned_count := 0

	while (
		scanned_count < citizen_count
		and candidates.size()
		< MAX_AUTONOMOUS_HAUL_CANDIDATES_PER_TICK
	):
		var citizen_index := (
			_autonomous_haul_scan_cursor % citizen_count
		)
		_autonomous_haul_scan_cursor = (
			(_autonomous_haul_scan_cursor + 1) % citizen_count
		)
		scanned_count += 1

		var raw_citizen = CityCitizenRegistrySystem.get_current_state().citizens[citizen_index]

		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if not _citizen_is_available_for_autonomous_hauling(
			citizen,
			schedule_phase
		):
			continue

		candidates.append(citizen.duplicate(true))

	return candidates


static func _citizen_is_available_for_autonomous_hauling(
	citizen: Dictionary,
	schedule_phase: String
) -> bool:
	if not bool(citizen.get("alive", false)):
		return false

	if int(citizen.get("job_object_id", -1)) > 0:
		return false

	if (
		str(citizen.get("state", ""))
		!= CityCitizens.CITY_CITIZEN_STATE_IDLE
	):
		return false

	var raw_current_task = citizen.get("current_task", {})

	if not raw_current_task is Dictionary:
		return false

	if (
		str(raw_current_task.get("kind", ""))
		!= CityCitizens.CITY_CITIZEN_TASK_KIND_NONE
	):
		return false

	var citizen_id := int(citizen.get("id", -1))

	if (
		citizen_id <= 0
		or CitizenNeedsSystem.citizen_should_seek_food(citizen_id)
		or CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id) > 0
		or not citizen.get("city_tile_position") is Vector2i
	):
		return false

	# Real obligations still outrank autonomous work, but low-priority
	# home-bound plans do not. The autonomous matcher runs before the deferred
	# home queue, so allowing these candidates is what lets an unemployed
	# citizen take the next valid load immediately after completing the previous
	# one. The home queue is released only after no additional hauler is needed.
	var scheduled_task_request := _get_next_scheduled_task_request(
		citizen,
		schedule_phase
	)

	if scheduled_task_request.is_empty():
		return true

	return int(
		scheduled_task_request.get(
			"priority",
			CityCitizens.CITY_CITIZEN_TASK_PRIORITY_NONE
		)
	) < AUTONOMOUS_WORKPLACE_OUTPUT_HAUL_TASK_PRIORITY


static func _has_unassigned_autonomous_haul_work() -> bool:
	# These opportunity builders already account for source reservations,
	# resource-specific destination capacity, public-storage tiers, and the open
	# carrying capacity of active ground-pile pickup chains. A non-empty result
	# therefore means another unemployed hauler is still useful.
	if not _get_ground_pile_haul_opportunities().is_empty():
		return true

	return not _get_workplace_output_haul_opportunities().is_empty()


static func _get_ground_pile_haul_opportunities() -> Array:
	var opportunities: Array = []
	var deliverable_resource_lookup: Dictionary = {}
	var total_unreserved_ground_amount := 0

	for raw_ground_pile in CityLogisticsSystem.get_city_ground_pile_snapshot():
		if not raw_ground_pile is Dictionary:
			continue

		var ground_pile: Dictionary = raw_ground_pile
		var ground_pile_id := int(ground_pile.get("id", -1))
		var resource := str(
			ground_pile.get("resource_type", WorldData.RESOURCE_NONE)
		)
		var source := CityLogisticsSystem.make_city_ground_pile_haul_endpoint(
			ground_pile_id
		)

		if not deliverable_resource_lookup.has(resource):
			deliverable_resource_lookup[resource] = (
				_resource_has_unreserved_public_storage_destination(
					resource
				)
			)

		if (
			not bool(deliverable_resource_lookup[resource])
			or not CityLogisticsSystem.city_haul_endpoint_can_provide_resource({
				"endpoint": source,
				"resource": resource,
				"withdrawal_purpose": CityObjectCatalog.CONTAINER_HAUL_PURPOSE_GROUND_PILE_CLEANUP,
				"require_unreserved_amount": true,
			})
		):
			continue

		var unreserved_amount := (
			CityLogisticsSystem.get_city_haul_endpoint_unreserved_resource_amount(
				source,
				resource
			)
		)

		if unreserved_amount <= 0:
			continue

		total_unreserved_ground_amount += unreserved_amount
		opportunities.append({
			"source": source,
			"requester": source,
			"resource_type": resource,
			"reason": (
				CityCitizens.CITY_CITIZEN_HAUL_REASON_GROUND_PILE_CLEANUP
			),
			"source_access_purpose": (
				CityObjectCatalog.CONTAINER_HAUL_PURPOSE_GROUND_PILE_CLEANUP
			),
			"task_priority": (
				AUTONOMOUS_GROUND_PILE_HAUL_TASK_PRIORITY
			),
		})

	# Existing ground-pile haulers should be allowed to fill their remaining
	# physical capacity before another citizen reserves a tiny pile. This keeps
	# dispatch proportional to the number of full loads instead of the number of
	# piles, while still adding another hauler whenever the current workers cannot
	# absorb all unreserved loose resources.
	if (
		total_unreserved_ground_amount > 0
		and _get_active_ground_pile_chain_capacity()
		>= total_unreserved_ground_amount
	):
		return []

	return opportunities


static func _get_active_ground_pile_chain_capacity() -> int:
	var open_carry_capacity := 0

	for raw_citizen in CityCitizenRegistrySystem.get_current_state().citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_id := int(citizen.get("id", -1))
		var current_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(
			citizen_id
		)
		var haul := CityCitizenTaskRuntimeSystem.get_city_citizen_current_haul(citizen_id)

		if (
			citizen_id <= 0
			or str(current_task.get("kind", ""))
			!= CityCitizens.CITY_CITIZEN_TASK_KIND_HAUL
			or not bool(
				haul.get(
					"allow_ground_pile_pickup_chaining",
					false
				)
			)
			or str(haul.get("reason", ""))
			!= CityCitizens.CITY_CITIZEN_HAUL_REASON_GROUND_PILE_CLEANUP
		):
			continue

		var haul_phase := str(
			haul.get(
				"phase",
				CityCitizens.CITY_CITIZEN_HAUL_PHASE_NONE
			)
		)

		if haul_phase not in [
			CityCitizens.CITY_CITIZEN_HAUL_PHASE_PENDING_SOURCE,
			CityCitizens.CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_SOURCE,
			CityCitizens.CITY_CITIZEN_HAUL_PHASE_PICKING_UP,
		]:
			continue

		var reservation_id := int(
			haul.get(
				"reservation_id",
				CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
			)
		)
		var reservation := CityLogisticsSystem.get_city_haul_reservation(
			reservation_id
		)

		if reservation.is_empty():
			continue

		open_carry_capacity += maxi(
			CityCitizenInventorySystem.get_city_citizen_available_haul_capacity(citizen_id)
			- maxi(
				int(reservation.get("source_reserved_amount", 0)),
				0
			),
			0
		)

	if open_carry_capacity <= 0:
		return 0

	return mini(
		open_carry_capacity,
		_get_total_unreserved_public_storage_space()
	)


static func _get_total_unreserved_public_storage_space() -> int:
	var total_space := 0

	for raw_city_object in CityObjectSystem.get_city_objects():
		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object

		if (
			CityResourceContainerSystem.get_city_object_public_storage_tier(city_object)
			== CityObjectCatalog.PUBLIC_CITY_STORAGE_TIER_NONE
		):
			continue

		var destination := CityLogisticsSystem.make_city_citizen_haul_endpoint(
			int(city_object.get("id", -1))
		)
		total_space += (
			CityLogisticsSystem.get_city_haul_endpoint_unreserved_destination_space(
				destination
			)
		)

	return total_space


static func _get_workplace_output_haul_opportunities() -> Array:
	var opportunities: Array = []
	var deliverable_resource_lookup: Dictionary = {}

	for raw_city_object in CityObjectSystem.get_city_objects():
		if not raw_city_object is Dictionary:
			continue

		var workplace: Dictionary = raw_city_object

		if not CityObjectCatalog.city_object_is_workplace(workplace):
			continue

		var workplace_id := int(workplace.get("id", -1))
		var source := CityLogisticsSystem.make_city_citizen_haul_endpoint(
			workplace_id
		)

		for resource in CityObjectCatalog.get_city_object_output_resources(
			workplace
		):
			if not deliverable_resource_lookup.has(resource):
				deliverable_resource_lookup[resource] = (
					_resource_has_unreserved_public_storage_destination(
						resource
					)
				)

			if (
				not bool(deliverable_resource_lookup[resource])
				or not CityLogisticsSystem.city_haul_endpoint_can_provide_resource({
					"endpoint": source,
					"resource": resource,
					"withdrawal_purpose": CityObjectCatalog.CONTAINER_HAUL_PURPOSE_WORKPLACE_OUTPUT,
					"require_unreserved_amount": true,
				})
			):
				continue

			opportunities.append({
				"source": source,
				"requester": source,
				"resource_type": resource,
				"reason": (
					CityCitizens.CITY_CITIZEN_HAUL_REASON_AUTONOMOUS_WORKPLACE_OUTPUT
				),
				"source_access_purpose": (
					CityObjectCatalog.CONTAINER_HAUL_PURPOSE_WORKPLACE_OUTPUT
				),
				"task_priority": (
					AUTONOMOUS_WORKPLACE_OUTPUT_HAUL_TASK_PRIORITY
				),
			})

	return opportunities


static func _resource_has_unreserved_public_storage_destination(
	resource: String
) -> bool:
	for storage_tier in CityResourceContainerSystem.get_public_city_storage_tiers():
		for raw_city_object in CityObjectSystem.get_city_objects():
			if not raw_city_object is Dictionary:
				continue

			var city_object: Dictionary = raw_city_object

			if (
				CityResourceContainerSystem.get_city_object_public_storage_tier(city_object)
				!= storage_tier
			):
				continue

			var destination := CityLogisticsSystem.make_city_citizen_haul_endpoint(
				int(city_object.get("id", -1))
			)

			if CityLogisticsSystem.city_haul_endpoint_can_accept_resource({
				"endpoint": destination,
				"resource": resource,
				"deposit_purpose": CityObjectCatalog.CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE,
				"require_unreserved_space": true,
			}):
				return true

	return false


static func _try_assign_best_autonomous_haul(
	city_world: WorldData,
	candidates: Array,
	opportunities: Array
) -> bool:
	if candidates.is_empty() or opportunities.is_empty():
		return false

	var source_index := _build_autonomous_haul_source_index(
		city_world,
		opportunities
	)
	var source_tiles: Array = source_index.get("source_tiles", [])

	if source_tiles.is_empty():
		return false

	var matches := _build_autonomous_haul_matches({
		"city_world": city_world,
		"candidates": candidates,
		"opportunities": opportunities,
		"source_tiles": source_tiles,
		"opportunity_indices_by_tile": source_index.get(
			"opportunity_indices_by_tile",
			{}
		),
	})
	matches.sort_custom(_sort_autonomous_haul_matches)
	var build_attempt_count := 0

	for raw_match in matches:
		if (
			build_attempt_count
			>= MAX_AUTONOMOUS_HAUL_TASK_BUILD_ATTEMPTS_PER_TICK
		):
			break

		if not raw_match is Dictionary:
			continue

		var attempt_result := _try_assign_autonomous_haul_match({
			"city_world": city_world,
			"match": raw_match,
			"opportunities": opportunities,
		})

		if bool(attempt_result.get("attempted_build", false)):
			build_attempt_count += 1

		if bool(attempt_result.get("assigned", false)):
			return true

	return false


static func _build_autonomous_haul_source_index(
	city_world: WorldData,
	opportunities: Array
) -> Dictionary:
	var opportunity_indices_by_tile: Dictionary = {}
	var source_tiles: Array = []

	for opportunity_index in range(opportunities.size()):
		var raw_opportunity = opportunities[opportunity_index]

		if not raw_opportunity is Dictionary:
			continue

		var opportunity: Dictionary = raw_opportunity
		var raw_source = opportunity.get("source", {})

		if not raw_source is Dictionary:
			continue

		for access_tile in CityResourceMatcherScript.get_haul_endpoint_access_tiles(
			city_world,
			raw_source
		):
			if not opportunity_indices_by_tile.has(access_tile):
				opportunity_indices_by_tile[access_tile] = []
				source_tiles.append(access_tile)

			var tile_opportunity_indices: Array = (
				opportunity_indices_by_tile[access_tile]
			)
			tile_opportunity_indices.append(opportunity_index)
			opportunity_indices_by_tile[access_tile] = (
				tile_opportunity_indices
			)

	return {
		"source_tiles": source_tiles,
		"opportunity_indices_by_tile": opportunity_indices_by_tile,
	}


static func _build_autonomous_haul_matches(
	values: Dictionary
) -> Array:
	var city_world: WorldData = values.get("city_world")
	var candidates: Array = values.get("candidates", [])
	var opportunities: Array = values.get("opportunities", [])
	var source_tiles: Array = values.get("source_tiles", [])
	var opportunity_indices_by_tile: Dictionary = values.get(
		"opportunity_indices_by_tile",
		{}
	)
	var matches: Array = []
	var city_wide_expansion_limit := maxi(
		city_world.width * city_world.height,
		1
	)

	# Each candidate performs one exact search to every source tile. Taking the
	# cheapest result across citizens gives a global closest match within this
	# bounded candidate window rather than letting citizen iteration order win.
	for raw_citizen in candidates:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_id := int(citizen.get("id", -1))
		var raw_current_tile = citizen.get(
			"city_tile_position",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)

		if citizen_id <= 0 or not raw_current_tile is Vector2i:
			continue

		var path_result := (
			CityNavigationSystemScript.find_path_to_any_city_tile({
				"city_world": city_world,
				"start_tile": raw_current_tile,
				"destination_tiles": source_tiles,
				"max_expanded_nodes": city_wide_expansion_limit,
				"citizen_id": citizen_id,
				"heuristic_weight": AUTONOMOUS_HAUL_EXACT_HEURISTIC_WEIGHT
			})
		)

		if not bool(path_result.get("success", false)):
			continue

		var source_tile = path_result.get(
			"destination_tile",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)

		if not source_tile is Vector2i:
			continue

		var raw_indices = opportunity_indices_by_tile.get(source_tile, [])

		if not raw_indices is Array:
			continue

		for raw_opportunity_index in raw_indices:
			var opportunity_index := int(raw_opportunity_index)
			var source_tier := 0

			if (
				opportunity_index >= 0
				and opportunity_index < opportunities.size()
				and opportunities[opportunity_index] is Dictionary
			):
				source_tier = int(
					(opportunities[opportunity_index] as Dictionary).get(
						"source_tier",
						0
					)
				)

			matches.append({
				"citizen_id": citizen_id,
				"opportunity_index": opportunity_index,
				"path_cost": int(path_result.get("path_cost", 0)),
				"source_tier": source_tier,
			})

	return matches


static func _try_assign_autonomous_haul_match(
	values: Dictionary
) -> Dictionary:
	var city_world: WorldData = values.get("city_world")
	var match_data: Dictionary = values.get("match", {})
	var opportunities: Array = values.get("opportunities", [])
	var citizen_id := int(match_data.get("citizen_id", -1))
	var opportunity_index := int(
		match_data.get("opportunity_index", -1)
	)

	if opportunity_index < 0 or opportunity_index >= opportunities.size():
		return {"attempted_build": false, "assigned": false}

	var raw_opportunity = opportunities[opportunity_index]

	if not raw_opportunity is Dictionary:
		return {"attempted_build": false, "assigned": false}

	var opportunity: Dictionary = raw_opportunity
	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
	var source: Dictionary = opportunity.get("source", {})
	var resource := str(
		opportunity.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var source_access_purpose := str(
		opportunity.get(
			"source_access_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var raw_destination = opportunity.get("destination", {})
	var has_fixed_destination := (
		raw_destination is Dictionary
		and CityCitizens.is_valid_city_citizen_haul_endpoint(
			raw_destination
		)
	)
	var destination: Dictionary = {}

	if has_fixed_destination:
		destination = (raw_destination as Dictionary).duplicate(true)

	var destination_access_purpose := str(
		opportunity.get(
			"destination_access_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE
		)
	)

	if (
		citizen.is_empty()
		or int(citizen.get("job_object_id", -1)) > 0
		or not CityLogisticsSystem.city_haul_endpoint_can_provide_resource({
			"endpoint": source,
			"resource": resource,
			"withdrawal_purpose": source_access_purpose,
			"require_unreserved_amount": true,
		})
	):
		return {"attempted_build": false, "assigned": false}

	if (
		has_fixed_destination
		and not CityLogisticsSystem.city_haul_endpoint_can_accept_resource({
			"endpoint": destination,
			"resource": resource,
			"deposit_purpose": destination_access_purpose,
			"require_unreserved_space": true,
		})
	):
		return {"attempted_build": false, "assigned": false}

	var requested_amount := mini(
		CityCitizenInventorySystem.get_city_citizen_available_haul_capacity(citizen_id),
		CityLogisticsSystem.get_city_haul_endpoint_unreserved_resource_amount(
			source,
			resource
		)
	)
	requested_amount = mini(
		requested_amount,
		maxi(int(opportunity.get("requested_amount", requested_amount)), 0)
	)

	if has_fixed_destination:
		requested_amount = mini(
			requested_amount,
			CityLogisticsSystem.get_city_haul_endpoint_unreserved_destination_space(
				destination
			)
		)

	if requested_amount <= 0:
		return {"attempted_build": false, "assigned": false}

	var request_values := {
		"city_world": city_world,
		"citizen": citizen,
		"source": source,
		"resource_type": resource,
		"requested_amount": requested_amount,
		"reason": str(
			opportunity.get(
				"reason",
				CityCitizens.CITY_CITIZEN_HAUL_REASON_NONE
			)
		),
		"requester": opportunity.get("requester", source),
		"source_access_purpose": source_access_purpose,
		"destination_access_purpose": destination_access_purpose,
		"task_source": CityCitizens.CITY_CITIZEN_TASK_SOURCE_AUTONOMY,
		"task_priority": int(opportunity.get("task_priority", 0)),
	}
	var task_request: Dictionary = {}

	if has_fixed_destination:
		request_values["destination"] = destination
		task_request = (
			CitizenHaulingSystemScript.make_directed_haul_task_request(
				request_values
			)
		)
	else:
		task_request = (
			CitizenHaulingSystemScript.make_public_storage_haul_task_request(
				request_values
			)
		)

	if task_request.is_empty():
		return {"attempted_build": true, "assigned": false}

	if not CityCitizenTaskRuntimeSystem.assign_city_citizen_task(citizen_id, task_request):
		return {"attempted_build": true, "assigned": false}

	CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)
	_clear_idle_activity_runtime(citizen_id)
	return {"attempted_build": true, "assigned": true}


static func _sort_autonomous_haul_matches(
	match_a: Dictionary,
	match_b: Dictionary
) -> bool:
	var source_tier_a := int(match_a.get("source_tier", 0))
	var source_tier_b := int(match_b.get("source_tier", 0))

	if source_tier_a != source_tier_b:
		return source_tier_a < source_tier_b

	var path_cost_a := int(match_a.get("path_cost", 0))
	var path_cost_b := int(match_b.get("path_cost", 0))

	if path_cost_a != path_cost_b:
		return path_cost_a < path_cost_b

	var citizen_id_a := int(match_a.get("citizen_id", -1))
	var citizen_id_b := int(match_b.get("citizen_id", -1))

	if citizen_id_a != citizen_id_b:
		return citizen_id_a < citizen_id_b

	return int(match_a.get("opportunity_index", -1)) < int(
		match_b.get("opportunity_index", -1)
	)


#endregion

#region Idle Behavior

static func _process_bounded_idle_behaviors(
	work_shift_is_active: bool
) -> void:
	var citizen_count := CityCitizenRegistrySystem.get_current_state().citizens.size()

	if citizen_count <= 0:
		_idle_scan_cursor = 0
		return

	var city_world: WorldData = WorldPoliticalState.get_current_city_world()

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

		var raw_citizen = CityCitizenRegistrySystem.get_current_state().citizens[
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
			CityCitizens.INVALID_CITY_TILE_POSITION
		)

		if not raw_current_tile is Vector2i:
			_clear_idle_activity_runtime(citizen_id)
			continue

		var current_tile: Vector2i = raw_current_tile

		if not CityNavigationSystem.is_city_tile_walkable_for_citizen(
			city_world,
			current_tile,
			citizen_id
		):
			_clear_idle_activity_runtime(citizen_id)
			continue

		var movement_state := str(
			citizen.get(
				"movement_state",
				CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_IDLE
			)
		)

		if (
			movement_state
			== CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_MOVING
		):
			continue

		if (
			movement_state
			== CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_BLOCKED
		):
			CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)
			_idle_anchor_tile_by_citizen_id.erase(citizen_id)
			_schedule_next_idle_decision(citizen_id)
			continue

		var anchor_tile := _get_idle_anchor_tile(
			citizen,
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

		var wander_was_assigned := _try_assign_idle_wander({
			"city_world": city_world,
			"citizen_id": citizen_id,
			"current_tile": current_tile,
			"anchor_tile": anchor_tile,
			"choice_sequence": choice_sequence,
		})

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
		!= CityCitizens.CITY_CITIZEN_STATE_IDLE
	):
		return false

	var raw_current_task = citizen.get("current_task", {})

	if not raw_current_task is Dictionary:
		return false

	var current_task: Dictionary = raw_current_task

	if (
		str(current_task.get("kind", ""))
		!= CityCitizens.CITY_CITIZEN_TASK_KIND_NONE
	):
		return false

	if (
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(
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

	var workplace := CityObjectSystem.get_city_object_by_id(
		workplace_id
	)

	return (
		workplace.is_empty()
		or not CityObjectCatalog.city_object_is_workplace(workplace)
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
	citizen: Dictionary,
	current_tile: Vector2i
) -> Vector2i:
	var citizen_id := int(citizen.get("id", -1))
	var life_anchor := _get_citizen_life_anchor_tile(citizen)

	if life_anchor != CityCitizens.INVALID_CITY_TILE_POSITION:
		var distance_from_life_anchor := (
			absi(current_tile.x - life_anchor.x)
			+ absi(current_tile.y - life_anchor.y)
		)

		# A destination can be both local to the citizen and inside the life-
		# anchor radius only while these two search radii overlap. Homeless
		# workers can finish a shift far from the Keep; anchoring them to that
		# distant civic point would otherwise leave them with no candidates and
		# visually frozen until the next work shift.
		if (
			distance_from_life_anchor
			<= IDLE_ANCHOR_RADIUS_TILES
			+ IDLE_MAXIMUM_DESTINATION_DISTANCE
		):
			_idle_anchor_tile_by_citizen_id[citizen_id] = life_anchor
			return life_anchor

	var raw_anchor_tile = _idle_anchor_tile_by_citizen_id.get(
		citizen_id,
		CityCitizens.INVALID_CITY_TILE_POSITION
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


static func _get_citizen_life_anchor_tile(citizen: Dictionary) -> Vector2i:
	var citizen_id := int(citizen.get("id", -1))
	var home := CityObjectSystem.get_city_object_by_id(
		int(citizen.get("home_object_id", -1))
	)

	if (
		CityResourceMatcher.city_object_is_household_home(home)
		and CityAssignmentSystem.get_city_object_resident_ids(home).has(citizen_id)
	):
		var home_tiles := CityObjectSystem.get_city_object_footprint_tiles(home)
		var resident_ids := CityAssignmentSystem.get_city_object_resident_ids(home)
		resident_ids.sort()
		var resident_index := resident_ids.find(citizen_id)

		if not home_tiles.is_empty() and resident_index >= 0:
			var raw_home_anchor = home_tiles[
				resident_index % home_tiles.size()
			]

			if raw_home_anchor is Vector2i:
				return raw_home_anchor

	# Homeless citizens retain a civic center instead of anchoring to a random
	# roadside tile. City Keep access tiles remain legal without an interior task.
	for raw_city_object in CityObjectSystem.get_city_objects():
		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object

		if str(city_object.get("type", "")) != CityObjectCatalog.CITY_OBJECT_CITY_CENTER:
			continue

		var access_tiles := CityNavigationSystem.get_city_object_access_tiles(
			WorldPoliticalState.get_current_city_world(),
			city_object
		)

		if not access_tiles.is_empty():
			var raw_civic_anchor = access_tiles[
				posmod(citizen_id, access_tiles.size())
			]

			if raw_civic_anchor is Vector2i:
				return raw_civic_anchor

	return CityCitizens.INVALID_CITY_TILE_POSITION


static func _try_assign_idle_wander(values: Dictionary) -> bool:
	var city_world: WorldData = values.get("city_world")
	var citizen_id := int(values.get("citizen_id", -1))
	var current_tile: Vector2i = values.get(
		"current_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var anchor_tile: Vector2i = values.get(
		"anchor_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var choice_sequence := int(values.get("choice_sequence", 0))
	var candidate_tiles := _get_idle_wander_candidate_tiles({
		"city_world": city_world,
		"citizen_id": citizen_id,
		"current_tile": current_tile,
		"anchor_tile": anchor_tile,
	})

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
		CityNavigationSystemScript.find_path_to_any_city_tile({
			"city_world": city_world,
			"start_tile": current_tile,
			"destination_tiles": [selected_tile],
			"max_expanded_nodes": IDLE_MAXIMUM_EXPANDED_NODES,
			"citizen_id": citizen_id,
			"heuristic_weight": CityNavigationSystem.HEURISTIC_WEIGHT
		})
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

	return CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order(
		citizen_id,
		movement_path
	)


static func _get_idle_wander_candidate_tiles(
	values: Dictionary
) -> Array[Vector2i]:
	var city_world: WorldData = values.get("city_world")
	var citizen_id := int(values.get("citizen_id", -1))
	var current_tile: Vector2i = values.get(
		"current_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var anchor_tile: Vector2i = values.get(
		"anchor_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
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

			if not CityNavigationSystem.is_city_tile_walkable_for_citizen(
				city_world,
				candidate_tile,
				citizen_id
			):
				continue

			if CityCitizenSpatialSystem.has_living_city_citizen_at_tile(
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

#endregion
