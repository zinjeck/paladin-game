extends Node

# TEMPORARY FREEZE DIAGNOSTIC.
# Remove this autoload and the thin SimulationClock hooks after the freeze is
# identified. It never changes simulation state except for briefly enabling the
# coordinator's existing internal timing path during simulation_tick delivery;
# the prior debug flag is restored before time_changed is emitted.

const ENABLED: bool = true
const PROFILE_VERSION: int = 1
const OUTPUT_FILE_NAME := "paladin_simulation_profile.txt"

const SLOW_FRAME_WARNING_USEC: int = 25_000
const SLOW_TICK_WARNING_USEC: int = 16_000
const MAX_CAPTURED_FRAMES: int = 120_000
const MAX_CAPTURED_TICKS: int = 40_000
const PROCESS_PRIORITY_EARLY: int = -10_000

const SYSTEM_KEYS: Array[String] = [
	"citizen_needs",
	"employment",
	"citizen_decisions",
	"citizen_movement",
	"citizen_tasks",
	"workplace_production",
]

var output_path: String = ""

var _run_start_usec: int = 0
var _frame_index: int = 0
var _current_frame: Dictionary = {}
var _captured_frames: Array[Dictionary] = []
var _captured_ticks: Array[Dictionary] = []
var _tick_records_by_index: Dictionary = {}

var _frame_duration_samples_usec: Array[int] = []
var _tick_pipeline_samples_usec: Array[int] = []
var _coordinator_samples_usec: Array[int] = []
var _system_samples_usec: Dictionary = {}

var _debug_mode_before_tick: bool = false
var _forced_debug_for_current_tick: bool = false
var _tail_callback_connected: bool = false
var _dumped: bool = false


func _ready() -> void:
	process_priority = PROCESS_PRIORITY_EARLY
	_run_start_usec = Time.get_ticks_usec()

	for system_key in SYSTEM_KEYS:
		_system_samples_usec[system_key] = []

	_prepare_output_file()
	_connect_profile_callbacks()
	print("PALADIN SIMULATION PROFILER ENABLED")
	print("Profile output: ", output_path)


func _process(delta: float) -> void:
	if not ENABLED:
		return

	var now_usec := Time.get_ticks_usec()

	if not _current_frame.is_empty():
		_current_frame["engine_delta_usec"] = maxi(
			int(round(delta * 1_000_000.0)),
			0
		)
		_finalize_current_frame(now_usec)

	_frame_index += 1
	_current_frame = {
		"frame_index": _frame_index,
		"start_usec": now_usec,
		"clock_process_usec": 0,
		"ticks_processed": 0,
		"tick_indices": [],
		"accumulator_before_usec": 0,
		"accumulator_after_usec": 0,
		"backlog_ticks": 0,
		"backlog_limit_hits": 0,
	}


func _exit_tree() -> void:
	if not ENABLED or _dumped:
		return

	if not _current_frame.is_empty():
		_finalize_current_frame(Time.get_ticks_usec())

	dump_profile()


func is_enabled() -> bool:
	return ENABLED


func record_clock_process(
	duration_usec: int,
	ticks_processed: int,
	accumulator_before_seconds: float,
	accumulator_after_seconds: float,
	backlog_ticks: int,
	backlog_limit_hits: int
) -> void:
	if not ENABLED:
		return
	if _current_frame.is_empty():
		return

	_current_frame["clock_process_usec"] = maxi(duration_usec, 0)
	_current_frame["ticks_processed"] = maxi(ticks_processed, 0)
	_current_frame["accumulator_before_usec"] = maxi(
		int(round(accumulator_before_seconds * 1_000_000.0)),
		0
	)
	_current_frame["accumulator_after_usec"] = maxi(
		int(round(accumulator_after_seconds * 1_000_000.0)),
		0
	)
	_current_frame["backlog_ticks"] = maxi(backlog_ticks, 0)
	_current_frame["backlog_limit_hits"] = maxi(backlog_limit_hits, 0)


func record_tick_pipeline(
	tick_index: int,
	minutes_advanced: int,
	pipeline_duration_usec: int,
	simulation_signal_duration_usec: int,
	time_changed_signal_duration_usec: int
) -> void:
	if not ENABLED:
		return

	var tick_record := _get_or_create_tick_record(tick_index)
	tick_record["minutes_advanced"] = minutes_advanced
	tick_record["pipeline_usec"] = maxi(pipeline_duration_usec, 0)
	tick_record["simulation_signal_usec"] = maxi(
		simulation_signal_duration_usec,
		0
	)
	tick_record["time_changed_signal_usec"] = maxi(
		time_changed_signal_duration_usec,
		0
	)
	tick_record["pipeline_overhead_usec"] = maxi(
		pipeline_duration_usec
		- simulation_signal_duration_usec
		- time_changed_signal_duration_usec,
		0
	)
	tick_record["frame_index"] = _frame_index
	_tick_records_by_index[tick_index] = tick_record

	_append_sample(
		_tick_pipeline_samples_usec,
		pipeline_duration_usec,
		MAX_CAPTURED_TICKS
	)

	if not _current_frame.is_empty():
		var tick_indices: Array = _current_frame.get("tick_indices", [])
		tick_indices.append(tick_index)
		_current_frame["tick_indices"] = tick_indices

	_capture_completed_tick(tick_index)

	if pipeline_duration_usec >= SLOW_TICK_WARNING_USEC:
		print(
			"SIM_PROFILE SLOW_TICK #",
			tick_index,
			" pipeline=",
			_format_msec(pipeline_duration_usec),
			"ms simulation_signal=",
			_format_msec(simulation_signal_duration_usec),
			"ms time_changed=",
			_format_msec(time_changed_signal_duration_usec),
			"ms"
		)


func dump_profile() -> void:
	if _dumped:
		return

	_dumped = true
	var lines: Array[String] = []
	lines.append(
		"PALADIN_SIMULATION_PROFILE\tversion="
		+ str(PROFILE_VERSION)
	)
	lines.append(
		"META\tgenerated_unix="
		+ str(Time.get_unix_time_from_system())
		+ "\tengine="
		+ str(Engine.get_version_info().get("string", "unknown"))
		+ "\tproject="
		+ str(ProjectSettings.get_setting("application/config/name", "Paladin"))
	)
	lines.append(
		"META\tcolumns use microseconds unless their name ends in _count, _index, _bytes, or _name"
	)

	for frame_record in _captured_frames:
		lines.append(_format_frame_record(frame_record))

	for tick_record in _captured_ticks:
		lines.append(_format_tick_record(tick_record))

	_append_summary_lines(lines)

	var file := FileAccess.open(output_path, FileAccess.WRITE)

	if file == null:
		push_error(
			"Simulation profiler could not write: "
			+ output_path
		)
		return

	for line in lines:
		file.store_line(line)

	file.close()
	print(
		"PALADIN SIMULATION PROFILE SAVED: ",
		output_path,
		" frames=",
		_captured_frames.size(),
		" ticks=",
		_captured_ticks.size()
	)


func _connect_profile_callbacks() -> void:
	var head_callable := Callable(
		self,
		"_on_simulation_tick_profile_head"
	)

	if not SimulationClock.simulation_tick.is_connected(head_callable):
		SimulationClock.simulation_tick.connect(head_callable)

	call_deferred("_connect_tail_callback")


func _connect_tail_callback() -> void:
	if _tail_callback_connected:
		return

	var tail_callable := Callable(
		self,
		"_on_simulation_tick_profile_tail"
	)

	if not SimulationClock.simulation_tick.is_connected(tail_callable):
		SimulationClock.simulation_tick.connect(tail_callable)

	_tail_callback_connected = true


func _on_simulation_tick_profile_head(
	tick_index: int,
	minutes_advanced: int
) -> void:
	if not ENABLED:
		return

	_debug_mode_before_tick = WorldData.debug_mode_enabled
	_forced_debug_for_current_tick = not _debug_mode_before_tick

	if _forced_debug_for_current_tick:
		WorldData.debug_mode_enabled = true

	var tick_record := _get_or_create_tick_record(tick_index)
	tick_record["tick_index"] = tick_index
	tick_record["minutes_advanced"] = minutes_advanced
	tick_record["tick_head_usec"] = Time.get_ticks_usec()
	tick_record["absolute_world_minutes"] = (
		SimulationClock.absolute_world_minutes
	)
	tick_record["speed_multiplier"] = (
		SimulationClock.speed_multiplier
	)
	tick_record["scene_name"] = _get_active_view_name()
	tick_record["citizen_count"] = WorldData.city_citizens.size()
	tick_record["city_object_count"] = WorldData.city_objects.size()
	tick_record["active_task_count"] = (
		WorldData.city_active_task_ids.size()
	)
	tick_record["active_mover_count"] = (
		WorldData.city_active_mover_ids.size()
	)
	tick_record["ground_pile_count"] = (
		WorldData.city_ground_piles.size()
	)
	tick_record["construction_site_count"] = (
		WorldData.city_construction_sites.size()
	)
	_tick_records_by_index[tick_index] = tick_record


func _on_simulation_tick_profile_tail(
	tick_index: int,
	_minutes_advanced: int
) -> void:
	if not ENABLED:
		return

	var tick_record := _get_or_create_tick_record(tick_index)
	var coordinator_duration_usec := int(
		SimulationCoordinator.last_tick_duration_usec
	)
	var system_durations: Dictionary = (
		SimulationCoordinator.current_system_durations_usec.duplicate()
	)

	tick_record["coordinator_usec"] = coordinator_duration_usec
	tick_record["coordinator_unattributed_usec"] = (
		maxi(
			coordinator_duration_usec
			- _sum_system_durations(system_durations),
			0
		)
	)
	tick_record["system_durations_usec"] = system_durations
	tick_record["tick_tail_usec"] = Time.get_ticks_usec()
	_tick_records_by_index[tick_index] = tick_record

	_append_sample(
		_coordinator_samples_usec,
		coordinator_duration_usec,
		MAX_CAPTURED_TICKS
	)

	for system_key in SYSTEM_KEYS:
		var system_samples: Array = _system_samples_usec.get(
			system_key,
			[]
		)
		_append_sample(
			system_samples,
			int(system_durations.get(system_key, 0)),
			MAX_CAPTURED_TICKS
		)
		_system_samples_usec[system_key] = system_samples

	if _forced_debug_for_current_tick:
		WorldData.debug_mode_enabled = _debug_mode_before_tick

	_forced_debug_for_current_tick = false


func _get_or_create_tick_record(tick_index: int) -> Dictionary:
	var raw_record = _tick_records_by_index.get(
		tick_index,
		{}
	)

	if raw_record is Dictionary:
		return raw_record

	return {}


func _capture_completed_tick(tick_index: int) -> void:
	var raw_record = _tick_records_by_index.get(
		tick_index,
		{}
	)

	if not raw_record is Dictionary:
		return

	var tick_record: Dictionary = raw_record
	_add_runtime_monitors(tick_record)

	if _captured_ticks.size() >= MAX_CAPTURED_TICKS:
		_captured_ticks.pop_front()

	_captured_ticks.append(tick_record.duplicate(true))
	_tick_records_by_index.erase(tick_index)


func _finalize_current_frame(now_usec: int) -> void:
	var frame_record := _current_frame.duplicate(true)
	var start_usec := int(
		frame_record.get("start_usec", now_usec)
	)
	var frame_duration_usec := maxi(
		now_usec - start_usec,
		0
	)

	frame_record["frame_duration_usec"] = frame_duration_usec
	frame_record["run_elapsed_usec"] = maxi(
		now_usec - _run_start_usec,
		0
	)
	frame_record["tick_index"] = SimulationClock.tick_index
	frame_record["clock_active"] = (
		1 if SimulationClock.simulation_active else 0
	)
	frame_record["clock_paused"] = (
		1 if SimulationClock.simulation_paused else 0
	)
	frame_record["speed_multiplier"] = (
		SimulationClock.speed_multiplier
	)
	frame_record["scene_name"] = _get_active_view_name()
	frame_record["citizen_count"] = WorldData.city_citizens.size()
	frame_record["city_object_count"] = WorldData.city_objects.size()
	frame_record["active_task_count"] = (
		WorldData.city_active_task_ids.size()
	)
	frame_record["active_mover_count"] = (
		WorldData.city_active_mover_ids.size()
	)
	frame_record["city_citizen_version"] = (
		WorldData.city_citizen_version
	)
	frame_record["city_task_version"] = (
		WorldData.city_citizen_task_version
	)
	frame_record["city_movement_version"] = (
		WorldData.city_citizen_movement_version
	)
	frame_record["city_object_version"] = (
		WorldData.city_object_version
	)
	frame_record["city_container_version"] = (
		WorldData.city_container_version
	)
	frame_record["city_ground_pile_version"] = (
		WorldData.city_ground_pile_version
	)
	frame_record["city_command_version"] = (
		WorldData.city_player_command_version
	)
	frame_record["city_construction_version"] = (
		WorldData.city_construction_version
	)
	_add_runtime_monitors(frame_record)

	_append_sample(
		_frame_duration_samples_usec,
		frame_duration_usec,
		MAX_CAPTURED_FRAMES
	)

	if _captured_frames.size() >= MAX_CAPTURED_FRAMES:
		_captured_frames.pop_front()

	_captured_frames.append(frame_record)

	if frame_duration_usec >= SLOW_FRAME_WARNING_USEC:
		print(
			"SIM_PROFILE SLOW_FRAME #",
			frame_record.get("frame_index", -1),
			" duration=",
			_format_msec(frame_duration_usec),
			"ms tick=",
			frame_record.get("tick_index", -1),
			" ticks_this_frame=",
			frame_record.get("ticks_processed", 0),
			" scene=",
			frame_record.get("scene_name", "unknown")
		)

	_current_frame.clear()


func _add_runtime_monitors(record: Dictionary) -> void:
	record["fps"] = Performance.get_monitor(
		Performance.TIME_FPS
	)
	record["process_time_usec"] = int(round(
		Performance.get_monitor(
			Performance.TIME_PROCESS
		) * 1_000_000.0
	))
	record["physics_process_time_usec"] = int(round(
		Performance.get_monitor(
			Performance.TIME_PHYSICS_PROCESS
		) * 1_000_000.0
	))
	record["navigation_process_time_usec"] = int(round(
		Performance.get_monitor(
			Performance.TIME_NAVIGATION_PROCESS
		) * 1_000_000.0
	))
	record["memory_static_bytes"] = int(
		Performance.get_monitor(
			Performance.MEMORY_STATIC
		)
	)
	record["memory_static_max_bytes"] = int(
		Performance.get_monitor(
			Performance.MEMORY_STATIC_MAX
		)
	)
	record["engine_object_count"] = int(
		Performance.get_monitor(
			Performance.OBJECT_COUNT
		)
	)
	record["resource_count"] = int(
		Performance.get_monitor(
			Performance.OBJECT_RESOURCE_COUNT
		)
	)
	record["node_count"] = int(
		Performance.get_monitor(
			Performance.OBJECT_NODE_COUNT
		)
	)
	record["orphan_node_count"] = int(
		Performance.get_monitor(
			Performance.OBJECT_ORPHAN_NODE_COUNT
		)
	)
	record["render_objects"] = int(
		Performance.get_monitor(
			Performance.RENDER_TOTAL_OBJECTS_IN_FRAME
		)
	)
	record["render_primitives"] = int(
		Performance.get_monitor(
			Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME
		)
	)
	record["draw_calls"] = int(
		Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME
		)
	)
	record["video_memory_bytes"] = int(
		Performance.get_monitor(
			Performance.RENDER_VIDEO_MEM_USED
		)
	)


func _prepare_output_file() -> void:
	var documents_directory := OS.get_system_dir(
		OS.SYSTEM_DIR_DOCUMENTS
	)

	if documents_directory.is_empty():
		output_path = ProjectSettings.globalize_path(
			"user://" + OUTPUT_FILE_NAME
		)
	else:
		output_path = documents_directory.path_join(
			OUTPUT_FILE_NAME
		)

	var file := FileAccess.open(output_path, FileAccess.WRITE)

	if file == null:
		output_path = ProjectSettings.globalize_path(
			"user://" + OUTPUT_FILE_NAME
		)
		file = FileAccess.open(output_path, FileAccess.WRITE)

	if file == null:
		push_error(
			"Simulation profiler could not initialize its output file."
		)
		return

	file.store_line(
		"Profiler active. Close Paladin normally to finalize this file."
	)
	file.close()


func _format_frame_record(record: Dictionary) -> String:
	var tick_indices: Array = record.get("tick_indices", [])
	return (
		"FRAME"
		+ _field("frame_index", record.get("frame_index", -1))
		+ _field("run_elapsed_usec", record.get("run_elapsed_usec", 0))
		+ _field("frame_duration_usec", record.get("frame_duration_usec", 0))
		+ _field("engine_delta_usec", record.get("engine_delta_usec", 0))
		+ _field("fps", record.get("fps", 0))
		+ _field("scene_name", record.get("scene_name", "unknown"))
		+ _field("tick_index", record.get("tick_index", 0))
		+ _field("tick_indices", _join_values(tick_indices))
		+ _field("ticks_processed_count", record.get("ticks_processed", 0))
		+ _field("clock_process_usec", record.get("clock_process_usec", 0))
		+ _field("accumulator_before_usec", record.get("accumulator_before_usec", 0))
		+ _field("accumulator_after_usec", record.get("accumulator_after_usec", 0))
		+ _field("backlog_ticks_count", record.get("backlog_ticks", 0))
		+ _field("backlog_limit_hits_count", record.get("backlog_limit_hits", 0))
		+ _field("clock_active", record.get("clock_active", 0))
		+ _field("clock_paused", record.get("clock_paused", 0))
		+ _field("speed_multiplier", record.get("speed_multiplier", 0.0))
		+ _field("process_time_usec", record.get("process_time_usec", 0))
		+ _field("physics_process_time_usec", record.get("physics_process_time_usec", 0))
		+ _field("navigation_process_time_usec", record.get("navigation_process_time_usec", 0))
		+ _field("memory_static_bytes", record.get("memory_static_bytes", 0))
		+ _field("memory_static_max_bytes", record.get("memory_static_max_bytes", 0))
		+ _field("engine_object_count", record.get("engine_object_count", 0))
		+ _field("resource_count", record.get("resource_count", 0))
		+ _field("node_count", record.get("node_count", 0))
		+ _field("orphan_node_count", record.get("orphan_node_count", 0))
		+ _field("render_objects", record.get("render_objects", 0))
		+ _field("render_primitives", record.get("render_primitives", 0))
		+ _field("draw_calls", record.get("draw_calls", 0))
		+ _field("video_memory_bytes", record.get("video_memory_bytes", 0))
		+ _field("citizen_count", record.get("citizen_count", 0))
		+ _field("city_object_count", record.get("city_object_count", 0))
		+ _field("active_task_count", record.get("active_task_count", 0))
		+ _field("active_mover_count", record.get("active_mover_count", 0))
		+ _field("city_citizen_version", record.get("city_citizen_version", -1))
		+ _field("city_task_version", record.get("city_task_version", -1))
		+ _field("city_movement_version", record.get("city_movement_version", -1))
		+ _field("city_object_version", record.get("city_object_version", -1))
		+ _field("city_container_version", record.get("city_container_version", -1))
		+ _field("city_ground_pile_version", record.get("city_ground_pile_version", -1))
		+ _field("city_command_version", record.get("city_command_version", -1))
		+ _field("city_construction_version", record.get("city_construction_version", -1))
	)


func _format_tick_record(record: Dictionary) -> String:
	var system_durations: Dictionary = record.get(
		"system_durations_usec",
		{}
	)
	var line := (
		"TICK"
		+ _field("tick_index", record.get("tick_index", -1))
		+ _field("frame_index", record.get("frame_index", -1))
		+ _field("absolute_world_minutes", record.get("absolute_world_minutes", 0))
		+ _field("minutes_advanced", record.get("minutes_advanced", 0))
		+ _field("speed_multiplier", record.get("speed_multiplier", 0.0))
		+ _field("scene_name", record.get("scene_name", "unknown"))
		+ _field("pipeline_usec", record.get("pipeline_usec", 0))
		+ _field("simulation_signal_usec", record.get("simulation_signal_usec", 0))
		+ _field("time_changed_signal_usec", record.get("time_changed_signal_usec", 0))
		+ _field("pipeline_overhead_usec", record.get("pipeline_overhead_usec", 0))
		+ _field("coordinator_usec", record.get("coordinator_usec", 0))
		+ _field("coordinator_unattributed_usec", record.get("coordinator_unattributed_usec", 0))
	)

	for system_key in SYSTEM_KEYS:
		line += _field(
			system_key + "_usec",
			system_durations.get(system_key, 0)
		)

	line += (
		_field("citizen_count", record.get("citizen_count", 0))
		+ _field("city_object_count", record.get("city_object_count", 0))
		+ _field("active_task_count", record.get("active_task_count", 0))
		+ _field("active_mover_count", record.get("active_mover_count", 0))
		+ _field("ground_pile_count", record.get("ground_pile_count", 0))
		+ _field("construction_site_count", record.get("construction_site_count", 0))
		+ _field("memory_static_bytes", record.get("memory_static_bytes", 0))
		+ _field("node_count", record.get("node_count", 0))
		+ _field("draw_calls", record.get("draw_calls", 0))
	)

	return line


func _append_summary_lines(lines: Array[String]) -> void:
	lines.append(
		_format_summary(
			"frame_duration",
			_frame_duration_samples_usec
		)
	)
	lines.append(
		_format_summary(
			"tick_pipeline",
			_tick_pipeline_samples_usec
		)
	)
	lines.append(
		_format_summary(
			"simulation_coordinator",
			_coordinator_samples_usec
		)
	)

	for system_key in SYSTEM_KEYS:
		var samples: Array = _system_samples_usec.get(
			system_key,
			[]
		)
		lines.append(
			_format_summary(
				system_key,
				samples
			)
		)

	var slow_frames_with_ticks := 0
	var slow_frames_without_ticks := 0

	for frame_record in _captured_frames:
		if int(frame_record.get("frame_duration_usec", 0)) < SLOW_FRAME_WARNING_USEC:
			continue

		if int(frame_record.get("ticks_processed", 0)) > 0:
			slow_frames_with_ticks += 1
		else:
			slow_frames_without_ticks += 1

	lines.append(
		"SUMMARY"
		+ _field("metric", "slow_frame_correlation")
		+ _field("with_ticks_count", slow_frames_with_ticks)
		+ _field("without_ticks_count", slow_frames_without_ticks)
		+ _field("slow_frame_threshold_usec", SLOW_FRAME_WARNING_USEC)
		+ _field("slow_tick_threshold_usec", SLOW_TICK_WARNING_USEC)
	)


func _format_summary(
	metric_name: String,
	samples: Array
) -> String:
	return (
		"SUMMARY"
		+ _field("metric", metric_name)
		+ _field("sample_count", samples.size())
		+ _field("average_usec", int(round(_average(samples))))
		+ _field("p50_usec", _percentile(samples, 0.50))
		+ _field("p95_usec", _percentile(samples, 0.95))
		+ _field("p99_usec", _percentile(samples, 0.99))
		+ _field("maximum_usec", _maximum(samples))
	)


func _get_active_view_name() -> String:
	var session := get_tree().get_first_node_in_group(
		"game_session"
	)

	if session != null:
		var active_view = session.get("active_view")

		if active_view is Node:
			return str((active_view as Node).name)

	if get_tree().current_scene != null:
		return str(get_tree().current_scene.name)

	return "unknown"


func _join_values(values: Array) -> String:
	var text_values: PackedStringArray = []

	for value in values:
		text_values.append(str(value))

	return ",".join(text_values)


func _sum_system_durations(
	system_durations: Dictionary
) -> int:
	var total_usec := 0

	for system_key in SYSTEM_KEYS:
		total_usec += int(
			system_durations.get(system_key, 0)
		)

	return total_usec


func _append_sample(
	samples: Array,
	value_usec: int,
	maximum_size: int
) -> void:
	samples.append(maxi(value_usec, 0))

	while samples.size() > maximum_size:
		samples.pop_front()


func _average(samples: Array) -> float:
	if samples.is_empty():
		return 0.0

	var total := 0.0

	for raw_value in samples:
		total += float(raw_value)

	return total / float(samples.size())


func _percentile(
	samples: Array,
	percentile: float
) -> int:
	if samples.is_empty():
		return 0

	var sorted_samples := samples.duplicate()
	sorted_samples.sort()
	var index := clampi(
		int(ceil(
			float(sorted_samples.size())
			* clampf(percentile, 0.0, 1.0)
		)) - 1,
		0,
		sorted_samples.size() - 1
	)
	return int(sorted_samples[index])


func _maximum(samples: Array) -> int:
	var maximum_value := 0

	for raw_value in samples:
		maximum_value = maxi(
			maximum_value,
			int(raw_value)
		)

	return maximum_value


func _field(
	field_name: String,
	value
) -> String:
	return "\t" + field_name + "=" + str(value)


func _format_msec(duration_usec: int) -> String:
	return "%.3f" % (
		float(maxi(duration_usec, 0))
		/ 1000.0
	)
