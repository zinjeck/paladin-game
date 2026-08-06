extends RefCounted
class_name DebugPanel

signal panel_moved(new_position: Vector2)
signal minimized_changed(is_minimized: bool)

# Every DebugPanel instance observes the same enable sequence. When tilde turns
# debug mode on, active and later-reactivated panels all begin minimized rather
# than exposing an expensive full diagnostic panel immediately.
static var _debug_enable_sequence: int = 0

var canvas_layer: CanvasLayer
var panel: Panel
var label: Label
var minimize_button: Button
var panel_padding: Vector2 = Vector2(12.0, 10.0)
var panel_min_size: Vector2 = Vector2(260.0, 80.0)
var text_provider: Callable

const MINIMUM_GRABBABLE_WIDTH: float = 72.0
const MINIMUM_GRABBABLE_HEIGHT: float = 24.0
const MINIMIZE_BUTTON_SIZE: Vector2 = Vector2(26.0, 24.0)
const HEADER_ACCESSORY_GAP: float = 6.0
var is_minimized: bool = false
var _observed_debug_enable_sequence: int = -1
var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _base_position: Vector2 = Vector2.ZERO
var _expanded_size: Vector2 = Vector2.ZERO

func setup(values: Dictionary) -> void:
	if not _has_valid_setup_values(values):
		return

	var parent: Node = values["parent"]
	var canvas_layer_index := int(values["canvas_layer_index"])
	var panel_position: Vector2 = values["panel_position"]

	panel_padding = values["padding"]
	panel_min_size = values["minimum_size"]
	text_provider = values["text_provider"]

	canvas_layer = CanvasLayer.new()
	canvas_layer.layer = canvas_layer_index
	parent.add_child(canvas_layer)

	panel = Panel.new()
	
	_base_position = panel_position
	panel.position = _base_position
	panel.visible = WorldData.debug_mode_enabled
	panel.clip_contents = true
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.mouse_default_cursor_shape = Control.CURSOR_MOVE
	panel.gui_input.connect(Callable(self, "_on_panel_gui_input"))

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.0, 0.0, 0.0, 0.68)
	panel_style.border_color = Color(0.0, 0.55, 1.0, 0.55)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(6)

	panel.add_theme_stylebox_override("panel", panel_style)
	canvas_layer.add_child(panel)

	label = Label.new()
	label.position = panel_padding
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_text = false
	label.add_theme_color_override("font_color", Color(0.82, 0.94, 1.0, 1.0))
	label.add_theme_font_size_override("font_size", 13)
	label.text = str(values["initial_text"])

	panel.add_child(label)
	_create_minimize_button()
	fit_to_text()
	refresh()


func _has_valid_setup_values(values: Dictionary) -> bool:
	var required_keys: Array[String] = [
		"parent",
		"canvas_layer_index",
		"panel_position",
		"padding",
		"minimum_size",
		"initial_text",
		"text_provider",
	]

	for key in required_keys:
		if not values.has(key):
			push_error(
				"DebugPanel.setup is missing required key: "
				+ key
			)
			return false

	if not values["parent"] is Node:
		push_error("DebugPanel.setup parent must be a Node.")
		return false

	if not values["panel_position"] is Vector2:
		push_error("DebugPanel.setup panel_position must be Vector2.")
		return false

	if not values["padding"] is Vector2:
		push_error("DebugPanel.setup padding must be Vector2.")
		return false

	if not values["minimum_size"] is Vector2:
		push_error("DebugPanel.setup minimum_size must be Vector2.")
		return false

	if typeof(values["text_provider"]) != TYPE_CALLABLE:
		push_error("DebugPanel.setup text_provider must be Callable.")
		return false

	return true


func set_enabled(is_enabled: bool) -> void:
	var was_enabled := WorldData.debug_mode_enabled
	WorldData.debug_mode_enabled = is_enabled

	if is_enabled and not was_enabled:
		_debug_enable_sequence += 1

	if not is_enabled:
		_is_dragging = false

	refresh()


func toggle_enabled() -> bool:
	set_enabled(not WorldData.debug_mode_enabled)
	return WorldData.debug_mode_enabled


func refresh() -> void:
	if panel != null:
		panel.visible = WorldData.debug_mode_enabled

	if not WorldData.debug_mode_enabled:
		return

	# A panel may have been inactive when another map view handled the tilde key.
	# The shared sequence makes it observe that enable event when it next refreshes.
	if _observed_debug_enable_sequence != _debug_enable_sequence:
		_observed_debug_enable_sequence = _debug_enable_sequence
		set_minimized(true)

	if label == null:
		return

	# Minimized panels do not display their text. Avoid rebuilding expensive
	# validator and resource-conservation diagnostics until expansion.
	if is_minimized:
		return

	if text_provider.is_valid():
		label.text = str(text_provider.call())

	fit_to_text()


func fit_to_text() -> void:
	if panel == null:
		return

	if label == null:
		return

	var label_size: Vector2 = label.get_combined_minimum_size()
	var next_panel_size: Vector2 = (
		label_size
		+ panel_padding * 2.0
	)

	if next_panel_size.x < panel_min_size.x:
		next_panel_size.x = panel_min_size.x

	if next_panel_size.y < panel_min_size.y:
		next_panel_size.y = panel_min_size.y

	if is_minimized:
		panel.size = Vector2(
			maxf(
				_expanded_size.x,
				panel_min_size.x
			),
			MINIMIZE_BUTTON_SIZE.y
		)
		_layout_minimize_button()
		return

	panel.size = next_panel_size
	_expanded_size = next_panel_size
	label.position = panel_padding
	label.size = label_size
	_layout_minimize_button()

func set_minimized(
	should_minimize: bool
) -> void:
	if panel == null:
		return

	if is_minimized == should_minimize:
		return

	_is_dragging = false

	if should_minimize:
		_expanded_size = panel.size

	is_minimized = should_minimize
	label.visible = not is_minimized

	if minimize_button != null:
		if is_minimized:
			minimize_button.text = "+"
			minimize_button.tooltip_text = (
				"Expand debug panel"
			)
		else:
			minimize_button.text = "-"
			minimize_button.tooltip_text = (
				"Minimize debug panel"
			)

	if is_minimized:
		fit_to_text()
	else:
		refresh()

	minimized_changed.emit(is_minimized)


func _create_minimize_button() -> void:
	if panel == null:
		return

	minimize_button = Button.new()
	minimize_button.text = "-"
	minimize_button.size = MINIMIZE_BUTTON_SIZE
	minimize_button.focus_mode = Control.FOCUS_NONE
	minimize_button.mouse_filter = (
		Control.MOUSE_FILTER_STOP
	)
	minimize_button.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
	)
	minimize_button.tooltip_text = (
		"Minimize debug panel"
	)
	minimize_button.add_theme_font_size_override(
		"font_size",
		15
	)
	minimize_button.add_theme_color_override(
		"font_color",
		Color(0.82, 0.94, 1.0, 1.0)
	)

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(
		0.03,
		0.12,
		0.20,
		0.92
	)
	normal_style.border_color = Color(
		0.0,
		0.55,
		1.0,
		0.70
	)
	normal_style.set_border_width_all(1)
	normal_style.set_corner_radius_all(4)

	var hover_style := (
		normal_style.duplicate()
		as StyleBoxFlat
	)
	hover_style.bg_color = Color(
		0.04,
		0.24,
		0.38,
		0.96
	)

	var pressed_style := (
		normal_style.duplicate()
		as StyleBoxFlat
	)
	pressed_style.bg_color = Color(
		0.0,
		0.36,
		0.58,
		1.0
	)

	minimize_button.add_theme_stylebox_override(
		"normal",
		normal_style
	)
	minimize_button.add_theme_stylebox_override(
		"hover",
		hover_style
	)
	minimize_button.add_theme_stylebox_override(
		"pressed",
		pressed_style
	)
	minimize_button.add_theme_stylebox_override(
		"focus",
		hover_style
	)

	minimize_button.pressed.connect(
		Callable(
			self,
			"_on_minimize_button_pressed"
		)
	)

	panel.add_child(minimize_button)


func _layout_minimize_button() -> void:
	if (
		panel == null
		or minimize_button == null
	):
		return

	minimize_button.position = Vector2(
		panel.size.x
		- MINIMIZE_BUTTON_SIZE.x,
		0.0
	)
	minimize_button.size = (
		MINIMIZE_BUTTON_SIZE
	)
	minimize_button.move_to_front()


func get_header_accessory_rect() -> Rect2:
	if panel == null:
		return Rect2()

	var right_edge := (
		panel.size.x
		- MINIMIZE_BUTTON_SIZE.x
		- HEADER_ACCESSORY_GAP
	)
	var left_edge := panel_padding.x

	return Rect2(
		Vector2(left_edge, 0.0),
		Vector2(
			maxf(right_edge - left_edge, 0.0),
			MINIMIZE_BUTTON_SIZE.y
		)
	)


func get_content_rect() -> Rect2:
	if panel == null:
		return Rect2()

	var content_position := Vector2(
		panel_padding.x,
		MINIMIZE_BUTTON_SIZE.y
		+ panel_padding.y
	)

	return Rect2(
		content_position,
		Vector2(
			maxf(
				panel.size.x
				- panel_padding.x * 2.0,
				0.0
			),
			maxf(
				panel.size.y
				- content_position.y
				- panel_padding.y,
				0.0
			)
		)
	)


func _on_minimize_button_pressed() -> void:
	set_minimized(not is_minimized)

func _on_panel_gui_input(event: InputEvent) -> void:
	if panel == null:
		return

	if event is InputEventMouseButton:
		var mouse_button_event: InputEventMouseButton = event

		if mouse_button_event.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_button_event.pressed:
			_is_dragging = true
			_drag_offset = mouse_button_event.position
		else:
			_is_dragging = false
			_restore_to_base_if_ungrabbable()

		panel.accept_event()
		return

	if event is InputEventMouseMotion and _is_dragging:
		var mouse_motion_event: InputEventMouseMotion = event

		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_is_dragging = false
			return

		_set_panel_position(
			mouse_motion_event.global_position - _drag_offset
		)

		panel.accept_event()

func _set_panel_position(requested_position: Vector2) -> void:
	if panel == null:
		return

	if panel.position == requested_position:
		return

	panel.position = requested_position
	panel_moved.emit(panel.position)

func _restore_to_base_if_ungrabbable() -> void:
	if panel == null:
		return

	var viewport := panel.get_viewport()

	if viewport == null:
		return

	var viewport_rect := viewport.get_visible_rect()
	var panel_rect := Rect2(
		panel.position,
		panel.size
	)

	var visible_panel_rect := panel_rect.intersection(
		viewport_rect
	)

	var has_enough_visible_width := (
		visible_panel_rect.size.x
		>= MINIMUM_GRABBABLE_WIDTH
	)

	var has_enough_visible_height := (
		visible_panel_rect.size.y
		>= MINIMUM_GRABBABLE_HEIGHT
	)

	if (
		has_enough_visible_width
		and has_enough_visible_height
	):
		return

	_set_panel_position(_base_position)

static func bool_to_yes_no(value: bool) -> String:
	if value:
		return "Yes"

	return "No"
