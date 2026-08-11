extends Node
class_name CityObjectPanelAnchor

# Keeps completed-object information panels attached to their selected world
# object while the camera pans or zooms. The panels remain in the UI CanvasLayer
# at a readable pixel size; only their attachment point is transformed through
# the city canvas, matching the construction-progress panel's behavior.
#
# World-attached panel groups are laid out against the visible viewport every
# frame. Secondary panels prefer the right, flip directly left when needed,
# and move with the primary panel only when neither side fits at the requested
# anchor. Extremely narrow viewports fall back to a vertical arrangement.

const SELECTION_KIND_OBJECT := "object"
const PANEL_SIDE_GAP: float = 10.0
const WORKPLACE_DETAILS_GAP: float = 8.0
const VIEWPORT_MARGIN: float = 8.0

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

	if object_type == CityObjectCatalog.CITY_OBJECT_ROAD:
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
	var desired_primary_position := Vector2(
		right_middle_screen.x + PANEL_SIDE_GAP,
		right_middle_screen.y
		- object_info_panel.size.y * 0.5
	)

	object_info_panel.scale = Vector2.ONE
	object_info_panel.position = desired_primary_position
	_prepare_workplace_details_panel(object_info_panel)
	_layout_viewport_safe_panel_group(
		object_info_panel,
		desired_primary_position
	)
	object_info_panel.move_to_front()
	was_world_attached = true

	var raw_details_panel = renderer.get("workplace_details_panel")

	if raw_details_panel is Control:
		var details_panel := raw_details_panel as Control

		if details_panel.visible:
			details_panel.move_to_front()


func _prepare_workplace_details_panel(
	object_info_panel: Control
) -> void:
	var raw_details_panel = renderer.get("workplace_details_panel")

	if not raw_details_panel is Control:
		return

	var details_panel := raw_details_panel as Control
	details_panel.scale = Vector2.ONE

	# The renderer remains responsible for refreshing panel content and size.
	# This anchor owns only final viewport-safe placement.
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


func _layout_viewport_safe_panel_group(
	object_info_panel: Control,
	desired_primary_position: Vector2
) -> void:
	var viewport_size := _get_viewport_size()

	if not _viewport_can_contain_panel(
		viewport_size,
		object_info_panel.size
	):
		# Headless tests and transient zero-sized viewports cannot satisfy an
		# on-screen constraint. Preserve the historical attachment coordinates
		# until a real drawable viewport exists.
		object_info_panel.position = desired_primary_position
		return

	var raw_details_panel = renderer.get("workplace_details_panel")

	if not raw_details_panel is Control:
		object_info_panel.position = _clamp_panel_position(
			desired_primary_position,
			object_info_panel.size,
			viewport_size
		)
		return

	var details_panel := raw_details_panel as Control

	if not details_panel.visible:
		object_info_panel.position = _clamp_panel_position(
			desired_primary_position,
			object_info_panel.size,
			viewport_size
		)
		return

	if not _viewport_can_contain_panel(viewport_size, details_panel.size):
		object_info_panel.position = desired_primary_position
		return

	var available_width := maxf(
		viewport_size.x - VIEWPORT_MARGIN * 2.0,
		0.0
	)
	var combined_width := (
		object_info_panel.size.x
		+ WORKPLACE_DETAILS_GAP
		+ details_panel.size.x
	)

	if combined_width <= available_width:
		_layout_horizontal_panel_group(
			object_info_panel,
			details_panel,
			desired_primary_position,
			viewport_size
		)
		return

	_layout_vertical_panel_group(
		object_info_panel,
		details_panel,
		desired_primary_position,
		viewport_size
	)


func _layout_horizontal_panel_group(
	object_info_panel: Control,
	details_panel: Control,
	desired_primary_position: Vector2,
	viewport_size: Vector2
) -> void:
	var primary_size := object_info_panel.size
	var details_size := details_panel.size
	var right_edge := viewport_size.x - VIEWPORT_MARGIN
	var common_y := _clamp_axis_position(
		desired_primary_position.y,
		maxf(primary_size.y, details_size.y),
		viewport_size.y
	)
	var primary_x := _clamp_axis_position(
		desired_primary_position.x,
		primary_size.x,
		viewport_size.x
	)
	var right_details_x := (
		primary_x + primary_size.x + WORKPLACE_DETAILS_GAP
	)

	if right_details_x + details_size.x <= right_edge:
		object_info_panel.position = Vector2(primary_x, common_y)
		details_panel.position = Vector2(right_details_x, common_y)
		return

	var left_details_x := (
		primary_x - WORKPLACE_DETAILS_GAP - details_size.x
	)

	if left_details_x >= VIEWPORT_MARGIN:
		# This is the normal edge behavior: the sidecar flips directly to the
		# left while the primary panel remains attached to its world object.
		object_info_panel.position = Vector2(primary_x, common_y)
		details_panel.position = Vector2(left_details_x, common_y)
		return

	# The primary anchor is too central for either unchanged side to fit. Build
	# both legal group arrangements and choose the one that moves the primary
	# panel the shortest distance from its requested attachment point.
	var right_primary_x := clampf(
		desired_primary_position.x,
		VIEWPORT_MARGIN,
		right_edge
		- primary_size.x
		- WORKPLACE_DETAILS_GAP
		- details_size.x
	)
	var left_group_x := clampf(
		desired_primary_position.x
		- details_size.x
		- WORKPLACE_DETAILS_GAP,
		VIEWPORT_MARGIN,
		right_edge
		- details_size.x
		- WORKPLACE_DETAILS_GAP
		- primary_size.x
	)
	var left_primary_x := (
		left_group_x + details_size.x + WORKPLACE_DETAILS_GAP
	)
	var right_movement := absf(
		right_primary_x - desired_primary_position.x
	)
	var left_movement := absf(
		left_primary_x - desired_primary_position.x
	)

	if left_movement < right_movement:
		details_panel.position = Vector2(left_group_x, common_y)
		object_info_panel.position = Vector2(left_primary_x, common_y)
	else:
		object_info_panel.position = Vector2(right_primary_x, common_y)
		details_panel.position = Vector2(
			right_primary_x
			+ primary_size.x
			+ WORKPLACE_DETAILS_GAP,
			common_y
		)


func _layout_vertical_panel_group(
	object_info_panel: Control,
	details_panel: Control,
	desired_primary_position: Vector2,
	viewport_size: Vector2
) -> void:
	var primary_size := object_info_panel.size
	var details_size := details_panel.size
	var available_height := maxf(
		viewport_size.y - VIEWPORT_MARGIN * 2.0,
		0.0
	)
	var combined_height := (
		primary_size.y + WORKPLACE_DETAILS_GAP + details_size.y
	)
	var primary_x := _clamp_axis_position(
		desired_primary_position.x,
		primary_size.x,
		viewport_size.x
	)
	var details_x := _clamp_axis_position(
		desired_primary_position.x,
		details_size.x,
		viewport_size.x
	)

	if combined_height <= available_height:
		var group_y := clampf(
			desired_primary_position.y,
			VIEWPORT_MARGIN,
			viewport_size.y - VIEWPORT_MARGIN - combined_height
		)
		object_info_panel.position = Vector2(primary_x, group_y)
		details_panel.position = Vector2(
			details_x,
			group_y + primary_size.y + WORKPLACE_DETAILS_GAP
		)
		return

	# Both panels are still clamped independently when no non-overlapping group
	# can fit. This final safety net keeps every individually displayable panel
	# inside the viewport rather than letting either disappear off-screen.
	object_info_panel.position = _clamp_panel_position(
		desired_primary_position,
		primary_size,
		viewport_size
	)
	details_panel.position = _clamp_panel_position(
		desired_primary_position,
		details_size,
		viewport_size
	)


func _viewport_can_contain_panel(
	viewport_size: Vector2,
	panel_size: Vector2
) -> bool:
	return (
		viewport_size.x >= panel_size.x + VIEWPORT_MARGIN * 2.0
		and viewport_size.y >= panel_size.y + VIEWPORT_MARGIN * 2.0
	)


func _clamp_panel_position(
	desired_position: Vector2,
	panel_size: Vector2,
	viewport_size: Vector2
) -> Vector2:
	return Vector2(
		_clamp_axis_position(
			desired_position.x,
			panel_size.x,
			viewport_size.x
		),
		_clamp_axis_position(
			desired_position.y,
			panel_size.y,
			viewport_size.y
		)
	)


func _clamp_axis_position(
	desired_position: float,
	panel_extent: float,
	viewport_extent: float
) -> float:
	var minimum_position := VIEWPORT_MARGIN
	var maximum_position := (
		viewport_extent - VIEWPORT_MARGIN - panel_extent
	)

	if maximum_position < minimum_position:
		return desired_position

	return clampf(
		desired_position,
		minimum_position,
		maximum_position
	)


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
