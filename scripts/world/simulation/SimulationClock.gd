extends Node

signal simulation_tick(tick_index: int, minutes_advanced: int)
signal time_changed(day: int, hour: int, minute: int)
signal active_changed(is_active: bool)
signal pause_changed(is_paused: bool)
signal speed_changed(new_speed_multiplier: float)

const MINUTES_PER_HOUR: int = 60
const HOURS_PER_DAY: int = 24
const MINUTES_PER_DAY: int = MINUTES_PER_HOUR * HOURS_PER_DAY

const DEFAULT_START_DAY: int = 1
const DEFAULT_START_HOUR: int = 6
const DEFAULT_START_MINUTE: int = 0

const DEFAULT_MINUTES_PER_TICK: int = 2
const DEFAULT_REAL_SECONDS_PER_TICK: float = 0.8333333333
const DEFAULT_SPEED_MULTIPLIER: float = 1.0

const MAX_TICKS_PER_FRAME: int = 8
const MAX_SPEED_MULTIPLIER: float = 16.0

var absolute_world_minutes: int = 0
var tick_index: int = 0

var minutes_per_tick: int = DEFAULT_MINUTES_PER_TICK
var real_seconds_per_tick: float = DEFAULT_REAL_SECONDS_PER_TICK
var speed_multiplier: float = DEFAULT_SPEED_MULTIPLIER

var simulation_active: bool = false
var simulation_paused: bool = false

var backlog_limit_hit_count: int = 0

var _real_time_accumulator: float = 0.0


func _ready() -> void:
	reset_clock_state()


func _process(delta: float) -> void:
	if not simulation_active:
		return

	if simulation_paused:
		return

	if delta <= 0.0:
		return

	if speed_multiplier <= 0.0:
		return

	if real_seconds_per_tick <= 0.0:
		return

	_real_time_accumulator += delta * speed_multiplier

	var ticks_processed_this_frame := 0

	while (
		_real_time_accumulator >= real_seconds_per_tick
		and ticks_processed_this_frame < MAX_TICKS_PER_FRAME
	):
		_real_time_accumulator -= real_seconds_per_tick
		advance_one_simulation_tick()
		ticks_processed_this_frame += 1

	if (
		ticks_processed_this_frame >= MAX_TICKS_PER_FRAME
		and _real_time_accumulator >= real_seconds_per_tick
	):
		backlog_limit_hit_count += 1


func start_new_game(
	start_day: int = DEFAULT_START_DAY,
	start_hour: int = DEFAULT_START_HOUR,
	start_minute: int = DEFAULT_START_MINUTE
) -> void:
	var safe_day := maxi(start_day, 1)
	var safe_hour := clampi(start_hour, 0, HOURS_PER_DAY - 1)
	var safe_minute := clampi(start_minute, 0, MINUTES_PER_HOUR - 1)

	absolute_world_minutes = (
		(safe_day - 1) * MINUTES_PER_DAY
		+ safe_hour * MINUTES_PER_HOUR
		+ safe_minute
	)

	tick_index = 0
	minutes_per_tick = DEFAULT_MINUTES_PER_TICK
	real_seconds_per_tick = DEFAULT_REAL_SECONDS_PER_TICK
	speed_multiplier = DEFAULT_SPEED_MULTIPLIER

	simulation_active = true
	simulation_paused = false

	backlog_limit_hit_count = 0
	_real_time_accumulator = 0.0

	active_changed.emit(simulation_active)
	pause_changed.emit(simulation_paused)
	speed_changed.emit(speed_multiplier)
	emit_time_changed()


func reset_clock_state() -> void:
	absolute_world_minutes = (
		(DEFAULT_START_DAY - 1) * MINUTES_PER_DAY
		+ DEFAULT_START_HOUR * MINUTES_PER_HOUR
		+ DEFAULT_START_MINUTE
	)

	tick_index = 0
	minutes_per_tick = DEFAULT_MINUTES_PER_TICK
	real_seconds_per_tick = DEFAULT_REAL_SECONDS_PER_TICK
	speed_multiplier = DEFAULT_SPEED_MULTIPLIER

	simulation_active = false
	simulation_paused = false

	backlog_limit_hit_count = 0
	_real_time_accumulator = 0.0


func suspend_simulation() -> void:
	if not simulation_active:
		return

	simulation_active = false
	active_changed.emit(false)


func resume_simulation() -> void:
	if simulation_active:
		return

	simulation_active = true
	active_changed.emit(true)
	emit_time_changed()


func set_simulation_paused(should_pause: bool) -> void:
	if simulation_paused == should_pause:
		return

	simulation_paused = should_pause
	pause_changed.emit(simulation_paused)


func toggle_simulation_paused() -> void:
	set_simulation_paused(not simulation_paused)


func set_speed_multiplier(new_speed_multiplier: float) -> void:
	var safe_speed := clampf(
		new_speed_multiplier,
		0.0,
		MAX_SPEED_MULTIPLIER
	)

	if is_equal_approx(speed_multiplier, safe_speed):
		return

	speed_multiplier = safe_speed
	speed_changed.emit(speed_multiplier)


func set_tick_configuration(
	new_minutes_per_tick: int,
	new_real_seconds_per_tick: float
) -> void:
	minutes_per_tick = maxi(new_minutes_per_tick, 1)
	real_seconds_per_tick = maxf(new_real_seconds_per_tick, 0.001)
	_real_time_accumulator = 0.0


func advance_one_simulation_tick() -> void:
	absolute_world_minutes += minutes_per_tick
	tick_index += 1

	simulation_tick.emit(tick_index, minutes_per_tick)
	emit_time_changed()


func advance_debug_ticks(tick_amount: int) -> void:
	var safe_tick_amount := maxi(tick_amount, 0)

	for _tick_number in range(safe_tick_amount):
		advance_one_simulation_tick()


func emit_time_changed() -> void:
	time_changed.emit(
		get_world_day(),
		get_world_hour(),
		get_world_minute()
	)


func get_world_day() -> int:
	return int(absolute_world_minutes / MINUTES_PER_DAY) + 1


func get_world_hour() -> int:
	return (
		int(absolute_world_minutes / MINUTES_PER_HOUR)
		% HOURS_PER_DAY
	)


func get_world_minute() -> int:
	return absolute_world_minutes % MINUTES_PER_HOUR


func get_accumulated_backlog_ticks() -> int:
	if real_seconds_per_tick <= 0.0:
		return 0

	return int(_real_time_accumulator / real_seconds_per_tick)


func get_time_display_text() -> String:
	return (
		"Day " + str(get_world_day())
		+ ", "
		+ str(get_world_hour()).pad_zeros(2)
		+ ":"
		+ str(get_world_minute()).pad_zeros(2)
	)


func get_clock_state_text() -> String:
	if not simulation_active:
		return "Inactive"

	if simulation_paused:
		return "Paused"

	return "Running"


func get_debug_text() -> String:
	return (
		"World Time: " + get_time_display_text() + "\n"
		+ "Clock: " + get_clock_state_text() + "\n"
		+ "Tick: " + str(tick_index) + "\n"
		+ "Minutes/Tick: " + str(minutes_per_tick) + "\n"
		+ "Speed: " + str(speed_multiplier) + "x\n"
		+ "Tick Backlog: " + str(get_accumulated_backlog_ticks()) + "\n"
		+ "Backlog Limit Hits: " + str(backlog_limit_hit_count)
	)
