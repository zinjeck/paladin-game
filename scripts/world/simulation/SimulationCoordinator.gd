extends Node

const SIMULATION_SYSTEM_CITIZEN_DECISIONS := "citizen_decisions"
const SIMULATION_SYSTEM_CITIZEN_NEEDS := "citizen_needs"
const SIMULATION_SYSTEM_EMPLOYMENT := "employment"
const SIMULATION_SYSTEM_CITIZEN_MOVEMENT := "citizen_movement"
const SIMULATION_SYSTEM_CITIZEN_TASKS := "citizen_tasks"
const SIMULATION_SYSTEM_WORKPLACE_PRODUCTION := "workplace_production"

const SETTLEMENT_SIMULATION_TIER_NONE := "none"
const SETTLEMENT_SIMULATION_TIER_FULL_DETAIL := "full_detail"
const SETTLEMENT_SIMULATION_TIER_INACTIVE_RETAINED := "inactive_retained"
const SETTLEMENT_SIMULATION_TIER_MEDIUM_RESOLUTION_FUTURE := (
	"medium_resolution_future"
)
const SETTLEMENT_SIMULATION_TIER_AGGREGATE_FUTURE := "aggregate_future"

const SLOW_TICK_WARNING_USEC: int = 16_000
const SAMPLE_WINDOW_SIZE: int = 120

const MONITORED_SYSTEM_KEYS: Array[String] = [
	SIMULATION_SYSTEM_CITIZEN_NEEDS,
	SIMULATION_SYSTEM_EMPLOYMENT,
	SIMULATION_SYSTEM_CITIZEN_DECISIONS,
	SIMULATION_SYSTEM_CITIZEN_MOVEMENT,
	SIMULATION_SYSTEM_CITIZEN_TASKS,
	SIMULATION_SYSTEM_WORKPLACE_PRODUCTION,
]

const SYSTEM_DISPLAY_NAMES: Dictionary = {
	SIMULATION_SYSTEM_CITIZEN_NEEDS: "Needs",
	SIMULATION_SYSTEM_EMPLOYMENT: "Employment",
	SIMULATION_SYSTEM_CITIZEN_DECISIONS: "Decisions",
	SIMULATION_SYSTEM_CITIZEN_MOVEMENT: "Movement",
	SIMULATION_SYSTEM_CITIZEN_TASKS: "Tasks",
	SIMULATION_SYSTEM_WORKPLACE_PRODUCTION: "Production",
}

var last_tick_index: int = 0
var last_tick_duration_usec: int = 0
var maximum_tick_duration_usec: int = 0

var processed_tick_count: int = 0
var slow_tick_count: int = 0

var tick_duration_samples_usec: Array[int] = []
var system_statistics: Dictionary = {}
var current_system_durations_usec: Dictionary = {}

var last_slow_tick_index: int = 0
var last_slow_tick_duration_usec: int = 0
var last_slow_tick_system_key: String = ""
var last_slow_tick_system_duration_usec: int = 0

var detailed_simulation_settlement_id: int = (
	SettlementData.INVALID_SETTLEMENT_ID
)
var pending_inactive_minutes_by_settlement_id: Dictionary = {}
var full_detail_minutes_by_settlement_id: Dictionary = {}
var last_full_detail_tick_by_settlement_id: Dictionary = {}
var last_policy_tick_index: int = 0
var last_policy_minutes_advanced: int = 0


func _ready() -> void:
	reset_performance_statistics()
	reset_settlement_simulation_policy()

	var tick_callable := Callable(self, "on_simulation_tick")

	if not SimulationClock.simulation_tick.is_connected(tick_callable):
		SimulationClock.simulation_tick.connect(tick_callable)

	var registry_reset_callable := Callable(
		self,
		"reset_settlement_simulation_policy"
	)
	if not WorldPoliticalState.settlement_registry_reset.is_connected(
		registry_reset_callable
	):
		WorldPoliticalState.settlement_registry_reset.connect(
			registry_reset_callable
		)


func select_detailed_simulation_settlement(settlement_id: int) -> bool:
	var settlement_context = WorldPoliticalState.get_settlement_context(
		settlement_id
	)
	if (
		settlement_context == null
		or not settlement_context.supports_city_simulation()
	):
		return false

	detailed_simulation_settlement_id = settlement_id
	_ensure_settlement_elapsed_ledger_entry(settlement_id)
	return true


func clear_detailed_simulation_settlement() -> void:
	detailed_simulation_settlement_id = SettlementData.INVALID_SETTLEMENT_ID


func reset_settlement_simulation_policy() -> void:
	clear_detailed_simulation_settlement()
	pending_inactive_minutes_by_settlement_id.clear()
	full_detail_minutes_by_settlement_id.clear()
	last_full_detail_tick_by_settlement_id.clear()
	last_policy_tick_index = 0
	last_policy_minutes_advanced = 0


func get_detailed_simulation_settlement_id() -> int:
	return detailed_simulation_settlement_id


func get_settlement_simulation_tier(settlement_id: int) -> String:
	var settlement_context = WorldPoliticalState.get_settlement_context(
		settlement_id
	)
	if (
		settlement_context == null
		or not settlement_context.supports_city_simulation()
	):
		return SETTLEMENT_SIMULATION_TIER_NONE
	if settlement_id == detailed_simulation_settlement_id:
		return SETTLEMENT_SIMULATION_TIER_FULL_DETAIL
	return SETTLEMENT_SIMULATION_TIER_INACTIVE_RETAINED


func get_pending_inactive_minutes(settlement_id: int) -> int:
	return maxi(
		int(pending_inactive_minutes_by_settlement_id.get(settlement_id, 0)),
		0
	)


func consume_pending_inactive_minutes(
	settlement_id: int,
	maximum_minutes: int = -1
) -> int:
	var pending_minutes := get_pending_inactive_minutes(settlement_id)
	if pending_minutes <= 0:
		return 0
	var consumed_minutes := pending_minutes
	if maximum_minutes >= 0:
		consumed_minutes = mini(pending_minutes, maximum_minutes)
	pending_inactive_minutes_by_settlement_id[settlement_id] = (
		pending_minutes - consumed_minutes
	)
	return consumed_minutes


func get_settlement_simulation_policy_snapshot(
	settlement_id: int
) -> Dictionary:
	return {
		"settlement_id": settlement_id,
		"tier": get_settlement_simulation_tier(settlement_id),
		"pending_inactive_minutes": get_pending_inactive_minutes(
			settlement_id
		),
		"full_detail_minutes": maxi(
			int(full_detail_minutes_by_settlement_id.get(settlement_id, 0)),
			0
		),
		"last_full_detail_tick": int(
			last_full_detail_tick_by_settlement_id.get(settlement_id, 0)
		),
		"last_policy_tick": last_policy_tick_index,
		"last_policy_minutes_advanced": last_policy_minutes_advanced,
	}


func _ensure_settlement_elapsed_ledger_entry(settlement_id: int) -> void:
	if not pending_inactive_minutes_by_settlement_id.has(settlement_id):
		pending_inactive_minutes_by_settlement_id[settlement_id] = 0
	if not full_detail_minutes_by_settlement_id.has(settlement_id):
		full_detail_minutes_by_settlement_id[settlement_id] = 0
	if not last_full_detail_tick_by_settlement_id.has(settlement_id):
		last_full_detail_tick_by_settlement_id[settlement_id] = 0


func _record_settlement_elapsed_time_policy(
	tick_index: int,
	minutes_advanced: int
) -> void:
	var safe_minutes := maxi(minutes_advanced, 0)
	last_policy_tick_index = tick_index
	last_policy_minutes_advanced = safe_minutes

	for settlement in WorldPoliticalState.get_settlement_snapshot():
		var settlement_id := int(
			settlement.get("id", SettlementData.INVALID_SETTLEMENT_ID)
		)
		var settlement_context = WorldPoliticalState.get_settlement_context(
			settlement_id
		)
		if (
			settlement_context == null
			or not settlement_context.supports_city_simulation()
		):
			continue

		_ensure_settlement_elapsed_ledger_entry(settlement_id)
		if settlement_id == detailed_simulation_settlement_id:
			full_detail_minutes_by_settlement_id[settlement_id] = (
				int(full_detail_minutes_by_settlement_id[settlement_id])
				+ safe_minutes
			)
			last_full_detail_tick_by_settlement_id[settlement_id] = tick_index
		else:
			pending_inactive_minutes_by_settlement_id[settlement_id] = (
				int(pending_inactive_minutes_by_settlement_id[settlement_id])
				+ safe_minutes
			)


func on_simulation_tick(
	tick_index: int,
	minutes_advanced: int
) -> void:
	var tick_start_usec := Time.get_ticks_usec()
	var should_sample_systems := WorldData.debug_mode_enabled
	var duration_recorder := Callable()

	current_system_durations_usec.clear()

	if should_sample_systems:
		duration_recorder = Callable(
			self,
			"_record_current_system_duration"
		)

	run_simulation_systems(
		tick_index,
		minutes_advanced,
		duration_recorder
	)

	last_tick_duration_usec = (
		Time.get_ticks_usec()
		- tick_start_usec
	)

	last_tick_index = tick_index
	processed_tick_count += 1

	if last_tick_duration_usec > maximum_tick_duration_usec:
		maximum_tick_duration_usec = last_tick_duration_usec

	if should_sample_systems:
		_append_duration_sample(
			tick_duration_samples_usec,
			last_tick_duration_usec
		)
		_record_current_system_samples()

	if last_tick_duration_usec >= SLOW_TICK_WARNING_USEC:
		slow_tick_count += 1
		_capture_last_slow_tick()


func run_simulation_systems(
	tick_index: int,
	minutes_advanced: int,
	duration_recorder: Callable = Callable()
) -> void:
	_record_settlement_elapsed_time_policy(
		tick_index,
		minutes_advanced
	)
	var settlement_context = WorldPoliticalState.get_settlement_context(
		detailed_simulation_settlement_id
	)
	if settlement_context == null:
		return

	run_settlement_simulation_systems(
		settlement_context,
		tick_index,
		minutes_advanced,
		duration_recorder
	)


func run_settlement_simulation_systems(
	settlement_context: SettlementSimulationContext,
	tick_index: int,
	minutes_advanced: int,
	duration_recorder: Callable = Callable()
) -> void:
	if (
		settlement_context == null
		or not WorldPoliticalState.is_registered_settlement_context(
			settlement_context
		)
		or not settlement_context.supports_city_simulation()
	):
		return
	var city_state = settlement_context.get_city_simulation_state()
	if not city_state is CitySettlementSimulationState:
		return
	_run_city_settlement_simulation_systems(
		city_state,
		tick_index,
		minutes_advanced,
		duration_recorder
	)


func _run_city_settlement_simulation_systems(
	city_state: CitySettlementSimulationState,
	tick_index: int,
	minutes_advanced: int,
	duration_recorder: Callable = Callable()
) -> void:

	# Simulation execution and profiling share one ordered city-settlement
	# pipeline. Every root receives the same explicit settlement target while
	# active_settlement_id remains exclusively a presentation selection.
	var should_record_durations := duration_recorder.is_valid()
	var system_start_usec := 0

	if should_record_durations:
		system_start_usec = Time.get_ticks_usec()

	# Embedded citizen inventory/cargo, scalar needs, and bidirectional
	# assignments have no duplicate state owner. Normalize supported records at
	# the headless simulation boundary so correctness never depends on a renderer.
	CityCitizenInventorySystem.ensure_city_citizen_inventory_state_for_city_state(
		city_state
	)
	CitizenNeedsSystem.ensure_city_citizen_need_state_for_city_state(city_state)
	CityAssignmentSystem.ensure_city_citizen_assignment_state_for_city_state(
		city_state
	)
	CitizenNeedsSystem.run_tick_for_city_state(
		city_state,
		tick_index,
		minutes_advanced
	)

	if should_record_durations:
		duration_recorder.call(
			SIMULATION_SYSTEM_CITIZEN_NEEDS,
			Time.get_ticks_usec() - system_start_usec
		)
		system_start_usec = Time.get_ticks_usec()

	CityEmploymentSystem.run_tick_for_city_state(
		city_state,
		tick_index,
		minutes_advanced
	)

	if should_record_durations:
		duration_recorder.call(
			SIMULATION_SYSTEM_EMPLOYMENT,
			Time.get_ticks_usec() - system_start_usec
		)
		system_start_usec = Time.get_ticks_usec()

	CitizenDecisionSystem.run_tick_for_city_state(
		city_state,
		tick_index,
		minutes_advanced
	)

	if should_record_durations:
		duration_recorder.call(
			SIMULATION_SYSTEM_CITIZEN_DECISIONS,
			Time.get_ticks_usec() - system_start_usec
		)
		system_start_usec = Time.get_ticks_usec()

	CitizenMovementSystem.run_tick_for_city_state(
		city_state,
		tick_index,
		minutes_advanced
	)

	if should_record_durations:
		duration_recorder.call(
			SIMULATION_SYSTEM_CITIZEN_MOVEMENT,
			Time.get_ticks_usec() - system_start_usec
		)
		system_start_usec = Time.get_ticks_usec()

	CitizenTaskSystem.run_tick_for_city_state(
		city_state,
		tick_index,
		minutes_advanced
	)

	if should_record_durations:
		duration_recorder.call(
			SIMULATION_SYSTEM_CITIZEN_TASKS,
			Time.get_ticks_usec() - system_start_usec
		)
		system_start_usec = Time.get_ticks_usec()

	WorkplaceProductionSystem.run_tick_for_city_state(
		city_state,
		tick_index,
		minutes_advanced
	)

	if should_record_durations:
		duration_recorder.call(
			SIMULATION_SYSTEM_WORKPLACE_PRODUCTION,
			Time.get_ticks_usec() - system_start_usec
		)


func reset_performance_statistics() -> void:
	last_tick_index = 0
	last_tick_duration_usec = 0
	maximum_tick_duration_usec = 0
	processed_tick_count = 0
	slow_tick_count = 0
	tick_duration_samples_usec.clear()
	current_system_durations_usec.clear()
	system_statistics.clear()

	for system_key in MONITORED_SYSTEM_KEYS:
		system_statistics[system_key] = {
			"last_duration_usec": 0,
			"maximum_duration_usec": 0,
			"samples_usec": [],
		}

	last_slow_tick_index = 0
	last_slow_tick_duration_usec = 0
	last_slow_tick_system_key = ""
	last_slow_tick_system_duration_usec = 0


func _record_current_system_duration(
	system_key: String,
	duration_usec: int
) -> void:
	if not MONITORED_SYSTEM_KEYS.has(system_key):
		return

	current_system_durations_usec[system_key] = maxi(
		duration_usec,
		0
	)


func _record_current_system_samples() -> void:
	for system_key in MONITORED_SYSTEM_KEYS:
		var duration_usec := int(
			current_system_durations_usec.get(
				system_key,
				0
			)
		)
		var raw_statistics = system_statistics.get(
			system_key,
			{}
		)

		if not raw_statistics is Dictionary:
			continue

		var statistics: Dictionary = raw_statistics
		statistics["last_duration_usec"] = duration_usec
		statistics["maximum_duration_usec"] = maxi(
			int(
				statistics.get(
					"maximum_duration_usec",
					0
				)
			),
			duration_usec
		)

		var raw_samples = statistics.get(
			"samples_usec",
			[]
		)

		if raw_samples is Array:
			_append_duration_sample(
				raw_samples,
				duration_usec
			)
			statistics["samples_usec"] = raw_samples

		system_statistics[system_key] = statistics


func _append_duration_sample(
	samples: Array,
	duration_usec: int
) -> void:
	samples.append(maxi(duration_usec, 0))

	while samples.size() > SAMPLE_WINDOW_SIZE:
		samples.pop_front()


func _capture_last_slow_tick() -> void:
	last_slow_tick_index = last_tick_index
	last_slow_tick_duration_usec = last_tick_duration_usec

	var slowest_system := _get_slowest_current_system()
	last_slow_tick_system_key = str(
		slowest_system.get("system_key", "")
	)
	last_slow_tick_system_duration_usec = int(
		slowest_system.get("duration_usec", 0)
	)


func _get_slowest_current_system() -> Dictionary:
	var slowest_system_key := ""
	var slowest_duration_usec := 0

	for system_key in MONITORED_SYSTEM_KEYS:
		var duration_usec := int(
			current_system_durations_usec.get(
				system_key,
				0
			)
		)

		if duration_usec <= slowest_duration_usec:
			continue

		slowest_system_key = system_key
		slowest_duration_usec = duration_usec

	return {
		"system_key": slowest_system_key,
		"duration_usec": slowest_duration_usec,
	}


func _get_average_duration_usec(samples: Array) -> float:
	if samples.is_empty():
		return 0.0

	var total_usec := 0

	for raw_sample in samples:
		total_usec += int(raw_sample)

	return float(total_usec) / float(samples.size())


func _get_percentile_duration_usec(
	samples: Array,
	percentile: float
) -> int:
	if samples.is_empty():
		return 0

	var sorted_samples := samples.duplicate()
	sorted_samples.sort()

	var sample_index := clampi(
		int(
			ceil(
				float(sorted_samples.size())
				* clampf(percentile, 0.0, 1.0)
			)
		) - 1,
		0,
		sorted_samples.size() - 1
	)

	return int(sorted_samples[sample_index])


func _format_timing_line(
	display_name: String,
	last_duration_usec: int,
	samples: Array,
	maximum_duration_usec: int
) -> String:
	return (
		display_name
		+ ": "
		+ "%.3f" % _usec_to_msec(last_duration_usec)
		+ " / "
		+ "%.3f" % _usec_to_msec(
			_get_average_duration_usec(samples)
		)
		+ " / "
		+ "%.3f" % _usec_to_msec(
			_get_percentile_duration_usec(
				samples,
				0.95
			)
		)
		+ " / "
		+ "%.3f" % _usec_to_msec(maximum_duration_usec)
	)


func _get_system_timing_lines() -> String:
	var lines: Array[String] = []

	for system_key in MONITORED_SYSTEM_KEYS:
		var raw_statistics = system_statistics.get(
			system_key,
			{}
		)

		if not raw_statistics is Dictionary:
			continue

		var statistics: Dictionary = raw_statistics
		var raw_samples = statistics.get("samples_usec", [])
		var samples: Array = []

		if raw_samples is Array:
			samples = raw_samples

		lines.append(
			_format_timing_line(
				str(
					SYSTEM_DISPLAY_NAMES.get(
						system_key,
						system_key
					)
				),
				int(
					statistics.get(
						"last_duration_usec",
						0
					)
				),
				samples,
				int(
					statistics.get(
						"maximum_duration_usec",
						0
					)
				)
			)
		)

	return "\n".join(lines)


func _get_workload_debug_text() -> String:
	var city_state = WorldPoliticalState.get_city_simulation_state(
		detailed_simulation_settlement_id
	)
	if not city_state is CitySettlementSimulationState:
		return "Load: no detailed simulation target"

	var workplace_count := 0
	var working_workplace_count := 0
	var blocked_workplace_count := 0

	for raw_city_object in CityObjectSystem.get_city_objects_for_city_state(
		city_state
	):
		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object

		if not CityObjectCatalog.city_object_is_workplace(city_object):
			continue

		workplace_count += 1

		var production_status := (
			CityObjectCatalog.get_city_object_production_status(
				city_object
			)
		)

		if (
			production_status
			== CityObjectCatalog.WORKPLACE_PRODUCTION_STATUS_WORKING
		):
			working_workplace_count += 1
		elif production_status.begins_with("blocked_"):
			blocked_workplace_count += 1

	return (
		"Load: Citizens "
		+ str(city_state.citizen_registry_state.citizens.size())
		+ " | Active Tasks "
		+ str(city_state.citizen_task_runtime_state.active_task_ids.size())
		+ " | Movers "
		+ str(city_state.citizen_movement_runtime_state.active_mover_ids.size())
		+ "\n"
		+ "City: Objects "
		+ str(city_state.object_state.objects.size())
		+ " | Workplaces "
		+ str(workplace_count)
		+ " | Working "
		+ str(working_workplace_count)
		+ " | Blocked "
		+ str(blocked_workplace_count)
	)


func _get_last_slow_tick_text() -> String:
	if last_slow_tick_index <= 0:
		return "Last Slow Tick: none"

	var text := (
		"Last Slow Tick: #"
		+ str(last_slow_tick_index)
		+ " | "
		+ "%.3f ms" % _usec_to_msec(
			last_slow_tick_duration_usec
		)
	)

	if not last_slow_tick_system_key.is_empty():
		text += (
			" | Slowest "
			+ str(
				SYSTEM_DISPLAY_NAMES.get(
					last_slow_tick_system_key,
					last_slow_tick_system_key
				)
			)
			+ " "
			+ "%.3f ms" % _usec_to_msec(
				last_slow_tick_system_duration_usec
			)
		)

	return text


func _usec_to_msec(duration_usec) -> float:
	return float(duration_usec) / 1000.0


func get_last_tick_duration_msec() -> float:
	return _usec_to_msec(last_tick_duration_usec)


func get_maximum_tick_duration_msec() -> float:
	return _usec_to_msec(maximum_tick_duration_usec)


func get_debug_text() -> String:
	var policy_text := (
		"Policy: detailed #"
		+ str(detailed_simulation_settlement_id)
		+ " | Tier "
		+ get_settlement_simulation_tier(
			detailed_simulation_settlement_id
		)
		+ " | Pending inactive min "
		+ str(get_pending_inactive_minutes(
			detailed_simulation_settlement_id
		))
	)
	return (
		"SIMULATION MONITOR\n"
		+ "Timing ms: last / avg / p95 / max ("
		+ str(tick_duration_samples_usec.size())
		+ "/"
		+ str(SAMPLE_WINDOW_SIZE)
		+ ")\n"
		+ _format_timing_line(
			"Total",
			last_tick_duration_usec,
			tick_duration_samples_usec,
			maximum_tick_duration_usec
		)
		+ "\n"
		+ _get_system_timing_lines()
		+ "\n"
		+ policy_text
		+ "\n"
		+ "Ticks: "
		+ str(processed_tick_count)
		+ " | Slow >= "
		+ "%.3f ms" % _usec_to_msec(
			SLOW_TICK_WARNING_USEC
		)
		+ ": "
		+ str(slow_tick_count)
		+ "\n"
		+ _get_workload_debug_text()
		+ "\n"
		+ _get_last_slow_tick_text()
	)
