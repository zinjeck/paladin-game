extends Node

const SIMULATION_SYSTEM_CITIZEN_DECISIONS := "citizen_decisions"
const SIMULATION_SYSTEM_CITIZEN_NEEDS := "citizen_needs"
const SIMULATION_SYSTEM_EMPLOYMENT := "employment"
const SIMULATION_SYSTEM_CITIZEN_MOVEMENT := "citizen_movement"
const SIMULATION_SYSTEM_CITIZEN_TASKS := "citizen_tasks"
const SIMULATION_SYSTEM_WORKPLACE_PRODUCTION := "workplace_production"

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


func _ready() -> void:
	reset_performance_statistics()

	var tick_callable := Callable(self, "on_simulation_tick")

	if not SimulationClock.simulation_tick.is_connected(tick_callable):
		SimulationClock.simulation_tick.connect(tick_callable)


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
	var settlement_context = (
		WorldPoliticalState.get_active_settlement_context()
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
	settlement_context,
	tick_index: int,
	minutes_advanced: int,
	duration_recorder: Callable = Callable()
) -> void:
	if (
		settlement_context == null
		or not settlement_context.has_method("supports_city_simulation")
		or not settlement_context.supports_city_simulation()
	):
		return

	# Simulation execution and profiling share one ordered city-settlement
	# pipeline. The systems still read the legacy WorldData city backend during
	# this migration pass, but invocation now has an explicit settlement owner.
	var should_record_durations := duration_recorder.is_valid()
	var system_start_usec := 0

	if should_record_durations:
		system_start_usec = Time.get_ticks_usec()

	CitizenNeedsSystem.run_tick(tick_index, minutes_advanced)

	if should_record_durations:
		duration_recorder.call(
			SIMULATION_SYSTEM_CITIZEN_NEEDS,
			Time.get_ticks_usec() - system_start_usec
		)
		system_start_usec = Time.get_ticks_usec()

	CityEmploymentSystem.run_tick(tick_index, minutes_advanced)

	if should_record_durations:
		duration_recorder.call(
			SIMULATION_SYSTEM_EMPLOYMENT,
			Time.get_ticks_usec() - system_start_usec
		)
		system_start_usec = Time.get_ticks_usec()

	CitizenDecisionSystem.run_tick(tick_index, minutes_advanced)

	if should_record_durations:
		duration_recorder.call(
			SIMULATION_SYSTEM_CITIZEN_DECISIONS,
			Time.get_ticks_usec() - system_start_usec
		)
		system_start_usec = Time.get_ticks_usec()

	CitizenMovementSystem.run_tick(tick_index, minutes_advanced)

	if should_record_durations:
		duration_recorder.call(
			SIMULATION_SYSTEM_CITIZEN_MOVEMENT,
			Time.get_ticks_usec() - system_start_usec
		)
		system_start_usec = Time.get_ticks_usec()

	CitizenTaskSystem.run_tick(tick_index, minutes_advanced)

	if should_record_durations:
		duration_recorder.call(
			SIMULATION_SYSTEM_CITIZEN_TASKS,
			Time.get_ticks_usec() - system_start_usec
		)
		system_start_usec = Time.get_ticks_usec()

	WorkplaceProductionSystem.run_tick(tick_index, minutes_advanced)

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
	var workplace_count := 0
	var working_workplace_count := 0
	var blocked_workplace_count := 0

	for raw_city_object in CityObjectSystem.get_city_objects():
		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object

		if not WorldData.city_object_is_workplace(city_object):
			continue

		workplace_count += 1

		var production_status := (
			WorldData.get_city_object_production_status(
				city_object
			)
		)

		if (
			production_status
			== WorldData.WORKPLACE_PRODUCTION_STATUS_WORKING
		):
			working_workplace_count += 1
		elif production_status.begins_with("blocked_"):
			blocked_workplace_count += 1

	return (
		"Load: Citizens "
		+ str(WorldData.city_citizens.size())
		+ " | Active Tasks "
		+ str(WorldData.city_active_task_ids.size())
		+ " | Movers "
		+ str(WorldData.city_active_mover_ids.size())
		+ "\n"
		+ "City: Objects "
		+ str(CityObjectSystem.get_city_objects().size())
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
