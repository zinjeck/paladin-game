extends RefCounted
class_name DebugPanel

var canvas_layer: CanvasLayer
var panel: Panel
var label: Label

var panel_padding: Vector2 = Vector2(12.0, 10.0)
var panel_min_size: Vector2 = Vector2(260.0, 80.0)
var text_provider: Callable


func setup(
	parent: Node,
	canvas_layer_index: int,
	panel_position: Vector2,
	padding: Vector2,
	minimum_size: Vector2,
	initial_text: String,
	provider: Callable
) -> void:
	panel_padding = padding
	panel_min_size = minimum_size
	text_provider = provider

	canvas_layer = CanvasLayer.new()
	canvas_layer.layer = canvas_layer_index
	parent.add_child(canvas_layer)

	panel = Panel.new()
	panel.position = panel_position
	panel.visible = WorldData.debug_mode_enabled
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

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
	label.text = initial_text

	panel.add_child(label)
	fit_to_text()
	refresh()


func set_enabled(is_enabled: bool) -> void:
	WorldData.debug_mode_enabled = is_enabled

	if panel != null:
		panel.visible = WorldData.debug_mode_enabled

	refresh()


func toggle_enabled() -> bool:
	set_enabled(not WorldData.debug_mode_enabled)
	return WorldData.debug_mode_enabled


func refresh() -> void:
	if panel != null:
		panel.visible = WorldData.debug_mode_enabled

	if not WorldData.debug_mode_enabled:
		return

	if label == null:
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
	var next_panel_size: Vector2 = label_size + panel_padding * 2.0

	if next_panel_size.x < panel_min_size.x:
		next_panel_size.x = panel_min_size.x

	if next_panel_size.y < panel_min_size.y:
		next_panel_size.y = panel_min_size.y

	panel.size = next_panel_size
	label.position = panel_padding
	label.size = label_size


static func bool_to_yes_no(value: bool) -> String:
	if value:
		return "Yes"

	return "No"
