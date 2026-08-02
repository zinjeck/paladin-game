extends CanvasLayer
class_name SimulationSpeedControls

# Owns the compact, session-wide simulation playback controls. The control
# remains above whichever persistent map view is active and writes directly to
# SimulationClock, so pause and speed state cannot diverge between scenes.

const BUTTON_SIDE: float = 36.0
const BUTTON_COUNT: int = 4
const TOP_MARGIN: float = 8.0

const PANEL_FILL_COLOR := Color(0.31, 0.31, 0.31, 0.97)
const BORDER_COLOR := Color(0.15, 0.15, 0.15, 1.0)
const ACTIVE_BORDER_COLOR := Color(0.88, 0.08, 0.06, 1.0)
const TEXT_COLOR := Color(0.95, 0.95, 0.95, 1.0)

var ui_root: Control
var button_row: HBoxContainer
var pause_button: Button
var speed_one_button: Button
var speed_two_button: Button
var speed_three_button: Button
var buttons: Array[Button] = []


func _ready() -> void:
	layer = 105
	_create_ui()
	_connect_clock_signals()
	refresh_selection()


func _exit_tree() -> void:
	_disconnect_clock_signals()


func select_pause() -> void:
	SimulationClock.set_simulation_paused(true)
	refresh_selection()


func select_speed(speed_multiplier: float) -> void:
	if not _is_supported_speed(speed_multiplier):
		push_error(
			"Unsupported simulation control speed: "
			+ str(speed_multiplier)
		)
		return

	SimulationClock.set_speed_multiplier(speed_multiplier)
	SimulationClock.set_simulation_paused(false)
	refresh_selection()


func refresh_selection() -> void:
	if pause_button == null:
		return

	var is_paused := SimulationClock.simulation_paused
	_apply_button_style(pause_button, is_paused)
	_apply_button_style(
		speed_one_button,
		not is_paused
		and is_equal_approx(SimulationClock.speed_multiplier, 1.0)
	)
	_apply_button_style(
		speed_two_button,
		not is_paused
		and is_equal_approx(SimulationClock.speed_multiplier, 2.0)
	)
	_apply_button_style(
		speed_three_button,
		not is_paused
		and is_equal_approx(SimulationClock.speed_multiplier, 3.0)
	)


func get_selected_mode_name() -> String:
	if SimulationClock.simulation_paused:
		return "pause"

	if is_equal_approx(SimulationClock.speed_multiplier, 1.0):
		return "1x"
	if is_equal_approx(SimulationClock.speed_multiplier, 2.0):
		return "2x"
	if is_equal_approx(SimulationClock.speed_multiplier, 3.0):
		return "3x"

	return "custom"


func _create_ui() -> void:
	ui_root = Control.new()
	ui_root.name = "SimulationSpeedControlRoot"
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui_root)
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	button_row = HBoxContainer.new()
	button_row.name = "SimulationSpeedButtonRow"
	button_row.mouse_filter = Control.MOUSE_FILTER_PASS
	button_row.anchor_left = 0.5
	button_row.anchor_right = 0.5
	button_row.anchor_top = 0.0
	button_row.anchor_bottom = 0.0
	button_row.offset_left = -BUTTON_SIDE * float(BUTTON_COUNT) * 0.5
	button_row.offset_right = BUTTON_SIDE * float(BUTTON_COUNT) * 0.5
	button_row.offset_top = TOP_MARGIN
	button_row.offset_bottom = TOP_MARGIN + BUTTON_SIDE
	button_row.add_theme_constant_override("separation", 0)
	ui_root.add_child(button_row)

	pause_button = _create_button("PauseButton", "")
	_create_pause_icon(pause_button)
	speed_one_button = _create_button("SpeedOneButton", "1x")
	speed_two_button = _create_button("SpeedTwoButton", "2x")
	speed_three_button = _create_button("SpeedThreeButton", "3x")

	pause_button.tooltip_text = "Pause simulation"
	speed_one_button.tooltip_text = "Normal simulation speed"
	speed_two_button.tooltip_text = "Double simulation speed"
	speed_three_button.tooltip_text = "Triple simulation speed"

	pause_button.pressed.connect(select_pause)
	speed_one_button.pressed.connect(select_speed.bind(1.0))
	speed_two_button.pressed.connect(select_speed.bind(2.0))
	speed_three_button.pressed.connect(select_speed.bind(3.0))


func _create_button(button_name: String, button_text: String) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = button_text
	button.custom_minimum_size = Vector2(BUTTON_SIDE, BUTTON_SIDE)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", TEXT_COLOR)
	button.add_theme_color_override("font_pressed_color", TEXT_COLOR)
	button_row.add_child(button)
	buttons.append(button)
	return button


func _create_pause_icon(button: Button) -> void:
	var icon_root := Control.new()
	icon_root.name = "PauseIcon"
	icon_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon_root)
	icon_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_create_pause_bar(icon_root, 0.36, 0.44)
	_create_pause_bar(icon_root, 0.56, 0.64)


func _create_pause_bar(
	icon_root: Control,
	left_anchor: float,
	right_anchor: float
) -> void:
	var bar := ColorRect.new()
	bar.color = TEXT_COLOR
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.anchor_left = left_anchor
	bar.anchor_right = right_anchor
	bar.anchor_top = 0.28
	bar.anchor_bottom = 0.72
	icon_root.add_child(bar)


func _apply_button_style(button: Button, is_selected: bool) -> void:
	if button == null:
		return

	var border_color := BORDER_COLOR
	var border_width := 1

	if is_selected:
		border_color = ACTIVE_BORDER_COLOR
		border_width = 2

	var normal_style := _make_style(
		PANEL_FILL_COLOR,
		border_color,
		border_width
	)
	var hover_style := _make_style(
		PANEL_FILL_COLOR.lightened(0.08),
		border_color,
		border_width
	)
	var pressed_style := _make_style(
		PANEL_FILL_COLOR.darkened(0.10),
		border_color,
		border_width
	)

	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_stylebox_override("focus", normal_style)


func _make_style(
	fill_color: Color,
	border_color: Color,
	border_width: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(0)
	return style


func _connect_clock_signals() -> void:
	var pause_callable := Callable(self, "_on_clock_pause_changed")
	var speed_callable := Callable(self, "_on_clock_speed_changed")

	if not SimulationClock.pause_changed.is_connected(pause_callable):
		SimulationClock.pause_changed.connect(pause_callable)

	if not SimulationClock.speed_changed.is_connected(speed_callable):
		SimulationClock.speed_changed.connect(speed_callable)


func _disconnect_clock_signals() -> void:
	var pause_callable := Callable(self, "_on_clock_pause_changed")
	var speed_callable := Callable(self, "_on_clock_speed_changed")

	if SimulationClock.pause_changed.is_connected(pause_callable):
		SimulationClock.pause_changed.disconnect(pause_callable)

	if SimulationClock.speed_changed.is_connected(speed_callable):
		SimulationClock.speed_changed.disconnect(speed_callable)


func _on_clock_pause_changed(_is_paused: bool) -> void:
	refresh_selection()


func _on_clock_speed_changed(_speed_multiplier: float) -> void:
	refresh_selection()


func _is_supported_speed(speed_multiplier: float) -> bool:
	return (
		is_equal_approx(speed_multiplier, 1.0)
		or is_equal_approx(speed_multiplier, 2.0)
		or is_equal_approx(speed_multiplier, 3.0)
	)
