extends Node
class_name CityObjectPanelAnchor

# Keeps completed-object information panels attached to their selected world
# object while the camera pans or zooms. The panels remain in the UI CanvasLayer
# at a readable pixel size; only their attachment point is transformed through
# the city canvas, matching the construction-progress panel's behavior.

const SELECTION_KIND_OBJECT := "object"
const PANEL_SIDE_GAP: float = 10.0
const WORKPLACE_DETAILS_GAP: float = 8.0

var renderer: Node
var was_world_attached: bool = false
var road_panel_suppressed: bool = false


func _ready() -> void:
	renderer = get_parent()
	call_deferred("synchronize")


func _process(_delta: float) -> void:
	synchronize()


func synchronize() -> void:
	if renderer == null or not is_instance_valid(renderer):
		return

	var raw_panel = renderer.get("object_info_panel")

	if not raw_panel is Control:
		return

	var object_info_panel := raw_panel as Control
	var selection_kind := str(
		renderer.get("selected_city_entity_kind")
	)
	var selected_entity_id := int(
		renderer.get("selected_city_entity_id")
	)

	if (
		selection_kind != SELECTION_KIND_OBJECT
		or selected_entity_id < 0
	):
		_restore_hud_layout_if_needed(object_info_panel)
		return

	if not renderer.has_method("get_city_object_by_id"):
		_restore_hud_layout_if_needed(object_info_panel)
		return

	var raw_city_object = renderer.call(
		"get_city_object_by_id",
		selected_entity_id
	)

	if not raw_city_object is Dictionary:
		_restore_hud_layout_if_needed(object_info_panel)
		return

	var city_object: Dictionary = raw_city_object

	if city_object.is_empty():
		_restore_hud_layout_if_needed(object_info_panel)
		return

	var object_type := str(city_object.get("type", ""))

	if object_type == WorldData.CITY_OBJECT_ROAD:
		_suppress_road_object_panels(object_info_panel)
		return

	road_panel_suppressed = false
	_attach_panel_to_object(object_info_panel, city_object)


func _attach_panel_to_object(
	object_info_panel: Control,
	city_object: Dictionary
) -> void:
	if not renderer.has_method("get_city_object_world_rect"):
		_restore_hud_layout_if_needed(object_info_panel)
		return

	var raw_world_rect = renderer.call(
		"get_city_object_world_rect",
		city_object
	)

	if not raw_world_rect is Rect2:
		_restore_hud_layout_if_needed(object_info_panel)
		return

	var object_world_rect: Rect2 = raw_world_rect

	if (
		object_world_rect.size.x <= 0.0
		or object_world_rect.size.y <= 0.0
	):
		_restore_hud_layout_if_needed(object_info_panel)
		return

	var canvas_transform := Transform2D.IDENTITY

	if renderer is CanvasItem:
		canvas_transform = (
			(renderer as CanvasItem)
			.get_global_transform_with_canvas()
		)

	var right_middle_screen := canvas_transform * Vector2(
		object_world_rect.end.x,
		object_world_rect.position.y
		+ object_world_rect.size.y * 0.5
	)

	object_info_panel.scale = Vector2.ONE
	object_info_panel.position = Vector2(
		right_middle_screen.x + PANEL_SIDE_GAP,
		right_middle_screen.y
		- object_info_panel.size.y * 0.5
	)
	object_info_panel.move_to_front()
	was_world_attached = true

	_attach_workplace_details_panel(object_info_panel)


func _attach_workplace_details_panel(
	object_info_panel: Control
) -> void:
	var raw_details_panel = renderer.get("workplace_details_panel")

	if not raw_details_panel is Control:
		return

	var details_panel := raw_details_panel as Control
	details_panel.scale = Vector2.ONE

	if renderer.has_method("layout_workplace_details_panel"):
		renderer.call(
			"layout_workplace_details_panel",
			_get_viewport_size()
		)
	else:
		details_panel.position = Vector2(
			object_info_panel.position.x
			+ object_info_panel.size.x
			+ WORKPLACE_DETAILS_GAP,
			object_info_panel.position.y
		)

	if details_panel.visible:
		details_panel.move_to_front()


func _suppress_road_object_panels(
	object_info_panel: Control
) -> void:
	if was_world_attached:
		_restore_screen_space_layout(object_info_panel)

	object_info_panel.visible = false
	var raw_details_panel = renderer.get("workplace_details_panel")

	if raw_details_panel is CanvasItem:
		(raw_details_panel as CanvasItem).visible = false

	if (
		not road_panel_suppressed
		and renderer.has_method("hide_workplace_details_ui")
	):
		renderer.call("hide_workplace_details_ui")

	was_world_attached = false
	road_panel_suppressed = true


func _restore_hud_layout_if_needed(
	object_info_panel: Control
) -> void:
	if not was_world_attached and not road_panel_suppressed:
		return

	_restore_screen_space_layout(object_info_panel)
	was_world_attached = false
	road_panel_suppressed = false


func _restore_screen_space_layout(
	object_info_panel: Control
) -> void:
	object_info_panel.scale = Vector2.ONE
	var raw_details_panel = renderer.get("workplace_details_panel")

	if raw_details_panel is Control:
		(raw_details_panel as Control).scale = Vector2.ONE

	if renderer.has_method("layout_object_info_panel"):
		renderer.call(
			"layout_object_info_panel",
			_get_viewport_size()
		)


func _get_viewport_size() -> Vector2:
	if renderer == null:
		return Vector2.ZERO

	var viewport := renderer.get_viewport()

	if viewport == null:
		return Vector2.ZERO

	return viewport.get_visible_rect().size
