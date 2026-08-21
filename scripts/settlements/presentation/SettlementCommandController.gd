extends RefCounted
class_name SettlementCommandController

# Owns transient player-command interaction and presentation for one exact
# settlement binding. Pointer coordinates are supplied by the caller, and the
# only gameplay mutations in this component are explicit command commits to
# the state carried by that binding.

const CityWorkSystemScript = preload(
	"res://scripts/city/simulation/systems/CityWorkSystem.gd"
)
const CityRenderLayerScript = preload(
	"res://scripts/city/rendering/CityRenderLayer.gd"
)
const SettlementPresentationBindingScript = preload(
	"res://scripts/settlements/presentation/SettlementPresentationBinding.gd"
)

const INVALID_TILE := Vector2i(-1, -1)
const COMMAND_TYPE_NONE := CityWorkSystemScript.CITY_PLAYER_COMMAND_TYPE_NONE
const COMMAND_TYPE_CHOP_TREE := (
	CityWorkSystemScript.CITY_PLAYER_COMMAND_TYPE_CHOP_TREE
)
const COMMAND_TYPE_COLLECT_ROCK := (
	CityWorkSystemScript.CITY_PLAYER_COMMAND_TYPE_COLLECT_ROCK
)
const COMMIT_STATUS_COMMITTED := "committed"
const COMMIT_STATUS_NO_OP := "no_op"
const COMMIT_STATUS_INVALID_BINDING := "invalid_binding"

const DRAG_THRESHOLD_PIXELS := 4.0
const DARKEN_COLOR := Color(0.0, 0.0, 0.0, 0.72)
const HIGHLIGHT_FILL := Color(1.0, 0.78, 0.12, 0.28)
const HIGHLIGHT_BORDER := Color(1.0, 0.88, 0.28, 0.95)
const CLAIMED_BORDER := Color(0.2, 1.0, 0.65, 1.0)
const PREVIEW_FILL := Color(0.0, 0.85, 1.0, 0.24)
const PREVIEW_BORDER := Color(0.2, 0.95, 1.0, 0.95)
const REMOVE_PREVIEW_FILL := Color(1.0, 0.16, 0.16, 0.24)
const REMOVE_PREVIEW_BORDER := Color(1.0, 0.3, 0.3, 0.95)

var presentation_binding: SettlementPresentationBindingScript
var highest_accepted_binding_generation: int = 0
var local_tile_size: int = 1

var menu_open: bool = false
var is_cancel_mode_active: bool = false
var active_command_type: String = COMMAND_TYPE_NONE
var is_dragging: bool = false
var drag_removing: bool = false
var drag_start_screen: Vector2 = Vector2.ZERO
var drag_current_screen: Vector2 = Vector2.ZERO
var drag_start_world: Vector2 = Vector2.ZERO
var drag_current_world: Vector2 = Vector2.ZERO
var drag_preview_tiles: Array[Vector2i] = []

var selection_box_panel: Panel
var cancel_cursor_icon: Label


func can_bind_settlement_presentation(
	binding: SettlementPresentationBindingScript,
	tile_size: int
) -> bool:
	if (
		binding == null
		or not binding.is_valid()
		or not binding.supports_backend_capability(
			SettlementPresentationBindingScript.CAPABILITY_CITY_DETAIL
		)
		or tile_size <= 0
	):
		return false
	if binding.generation > highest_accepted_binding_generation:
		return true

	return (
		binding.generation == highest_accepted_binding_generation
		and tile_size == local_tile_size
		and is_bound_to_settlement_presentation(binding)
	)


func bind_settlement_presentation(
	binding: SettlementPresentationBindingScript,
	tile_size: int
) -> bool:
	if not can_bind_settlement_presentation(binding, tile_size):
		return false
	if (
		is_bound_to_settlement_presentation(binding)
		and tile_size == local_tile_size
	):
		return true

	presentation_binding = binding
	local_tile_size = tile_size
	highest_accepted_binding_generation = binding.generation
	_clear_interaction_state()
	return true


func is_bound_to_settlement_presentation(
	binding: SettlementPresentationBindingScript
) -> bool:
	return (
		binding != null
		and presentation_binding != null
		and presentation_binding.matches_binding(binding)
		and binding.generation == highest_accepted_binding_generation
		and local_tile_size > 0
	)


func reset_presentation() -> void:
	presentation_binding = null
	local_tile_size = 1
	_clear_interaction_state()
	# Preserve the generation high-water mark so delayed bindings cannot revive
	# interaction state from a settlement that has already been left.


func clear_interaction_state() -> void:
	_clear_interaction_state()


func is_interaction_state_clear() -> bool:
	return (
		not menu_open
		and not is_tool_active()
		and not is_dragging
		and not drag_removing
		and drag_start_screen == Vector2.ZERO
		and drag_current_screen == Vector2.ZERO
		and drag_start_world == Vector2.ZERO
		and drag_current_world == Vector2.ZERO
		and drag_preview_tiles.is_empty()
		and (selection_box_panel == null or not selection_box_panel.visible)
		and (cancel_cursor_icon == null or not cancel_cursor_icon.visible)
	)


func open_menu() -> bool:
	if not _has_valid_binding():
		return false
	menu_open = true
	return true


func select_command_type(command_type: String) -> bool:
	if (
		not _has_valid_binding()
		or not CityWorkSystemScript.is_valid_city_player_command_type(
			command_type
		)
	):
		return false

	is_cancel_mode_active = false
	if cancel_cursor_icon != null:
		cancel_cursor_icon.visible = false
	active_command_type = (
		COMMAND_TYPE_NONE
		if active_command_type == command_type
		else command_type
	)
	cancel_drag()
	return true


func toggle_cancel_mode() -> bool:
	if not _has_valid_binding():
		return false

	active_command_type = COMMAND_TYPE_NONE
	is_cancel_mode_active = not is_cancel_mode_active
	cancel_drag()
	if cancel_cursor_icon != null:
		cancel_cursor_icon.visible = is_cancel_mode_active
	return true


func deactivate_tool() -> void:
	active_command_type = COMMAND_TYPE_NONE
	is_cancel_mode_active = false
	cancel_drag()
	if cancel_cursor_icon != null:
		cancel_cursor_icon.visible = false


func close_menu() -> void:
	menu_open = false
	deactivate_tool()


func is_command_mode_active() -> bool:
	return CityWorkSystemScript.is_valid_city_player_command_type(
		active_command_type
	)


func is_tool_active() -> bool:
	return is_command_mode_active() or is_cancel_mode_active


func update_command_button_visuals(
	cancel_button: Button,
	chop_trees_button: Button,
	collect_rocks_button: Button
) -> void:
	if cancel_button != null:
		cancel_button.set_pressed_no_signal(is_cancel_mode_active)
	if chop_trees_button != null:
		chop_trees_button.set_pressed_no_signal(
			active_command_type
			== CityWorkSystemScript.CITY_PLAYER_COMMAND_TYPE_CHOP_TREE
		)
	if collect_rocks_button != null:
		collect_rocks_button.set_pressed_no_signal(
			active_command_type
			== CityWorkSystemScript.CITY_PLAYER_COMMAND_TYPE_COLLECT_ROCK
		)


func create_cancel_cursor_visual(ui_parent: Node) -> Label:
	if cancel_cursor_icon != null:
		return cancel_cursor_icon
	if ui_parent == null:
		return null

	cancel_cursor_icon = Label.new()
	cancel_cursor_icon.text = "X"
	cancel_cursor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cancel_cursor_icon.visible = false
	cancel_cursor_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cancel_cursor_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cancel_cursor_icon.add_theme_font_size_override("font_size", 18)
	cancel_cursor_icon.add_theme_color_override(
		"font_color",
		Color(1.0, 0.12, 0.12, 1.0)
	)
	cancel_cursor_icon.add_theme_color_override(
		"font_outline_color",
		Color(0.15, 0.0, 0.0, 1.0)
	)
	cancel_cursor_icon.add_theme_constant_override("outline_size", 2)
	ui_parent.add_child(cancel_cursor_icon)
	return cancel_cursor_icon


func update_cancel_cursor_visual(pointer_screen_position: Vector2) -> void:
	if cancel_cursor_icon == null:
		return
	var icon_size := Vector2(18.0, 18.0)
	cancel_cursor_icon.size = icon_size
	cancel_cursor_icon.position = pointer_screen_position + Vector2(10.0, 8.0)
	cancel_cursor_icon.move_to_front()


func create_drag_selection_box_visual(ui_parent: Node) -> Panel:
	if selection_box_panel != null:
		return selection_box_panel
	if ui_parent == null:
		return null

	selection_box_panel = Panel.new()
	selection_box_panel.visible = false
	selection_box_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_parent.add_child(selection_box_panel)
	return selection_box_panel


func update_drag_selection_box_visual() -> void:
	if selection_box_panel == null:
		return

	var drag_distance := drag_start_screen.distance_to(drag_current_screen)
	if not is_dragging or drag_distance < DRAG_THRESHOLD_PIXELS:
		selection_box_panel.visible = false
		return

	var fill_color := PREVIEW_FILL
	var border_color := PREVIEW_BORDER
	if drag_removing:
		fill_color = REMOVE_PREVIEW_FILL
		border_color = REMOVE_PREVIEW_BORDER
	selection_box_panel.add_theme_stylebox_override(
		"panel",
		_create_flat_style(fill_color, border_color)
	)
	var screen_rect := _rect_between_points(
		drag_start_screen,
		drag_current_screen
	)
	selection_box_panel.visible = true
	selection_box_panel.position = screen_rect.position
	selection_box_panel.size = screen_rect.size
	selection_box_panel.move_to_front()


func begin_drag(
	screen_position: Vector2,
	world_position: Vector2,
	removing: bool
) -> bool:
	if (
		not _has_valid_binding()
		or not is_tool_active()
		or removing != is_cancel_mode_active
	):
		return false

	is_dragging = true
	drag_removing = removing
	drag_start_screen = screen_position
	drag_current_screen = screen_position
	drag_start_world = world_position
	drag_current_world = world_position
	refresh_drag_preview()
	update_drag_selection_box_visual()
	return true


func update_drag(
	screen_position: Vector2,
	world_position: Vector2
) -> bool:
	if not is_dragging or not _has_valid_binding():
		return false
	drag_current_screen = screen_position
	drag_current_world = world_position
	refresh_drag_preview()
	update_drag_selection_box_visual()
	return true


func finish_drag(
	screen_position: Vector2,
	world_position: Vector2
) -> Dictionary:
	if not is_dragging:
		return {
			"status": COMMIT_STATUS_NO_OP,
			"affected_count": 0,
		}
	if not _has_valid_binding():
		_clear_drag_state()
		return {
			"status": COMMIT_STATUS_INVALID_BINDING,
			"affected_count": 0,
		}

	drag_current_screen = screen_position
	drag_current_world = world_position
	refresh_drag_preview()
	var commit_tiles := drag_preview_tiles.duplicate()
	var state := _get_bound_state()
	var affected_count := 0
	if not commit_tiles.is_empty():
		if drag_removing:
			affected_count = (
				CityWorkSystemScript.cancel_player_targets_at_tiles_for_city_state(
					state,
					commit_tiles
				)
			)
		else:
			affected_count = (
				CityWorkSystemScript.add_city_player_command_targets_for_city_state(
					state,
					active_command_type,
					commit_tiles
				)
			)
	_clear_drag_state()
	return {
		"status": (
			COMMIT_STATUS_COMMITTED
			if affected_count > 0
			else COMMIT_STATUS_NO_OP
		),
		"affected_count": affected_count,
	}


func cancel_drag() -> bool:
	var changed := (
		is_dragging
		or drag_removing
		or not drag_preview_tiles.is_empty()
		or drag_start_screen != Vector2.ZERO
		or drag_current_screen != Vector2.ZERO
		or drag_start_world != Vector2.ZERO
		or drag_current_world != Vector2.ZERO
	)
	_clear_drag_state()
	return changed


func refresh_drag_preview() -> void:
	drag_preview_tiles.clear()
	if not is_dragging or not _has_valid_binding():
		return

	var drag_tiles := get_tiles_in_drag_world_rect()
	var state := _get_bound_state()
	if drag_removing:
		drag_preview_tiles = (
			CityWorkSystemScript.get_cancel_preview_tiles_for_city_state(
				state,
				drag_tiles
			)
		)
		return

	for tile_position in drag_tiles:
		if CityWorkSystemScript.can_designate_city_player_command_at_tile_for_city_state(
			state,
			active_command_type,
			tile_position
		):
			drag_preview_tiles.append(tile_position)


func get_tiles_in_drag_world_rect() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var world := _get_bound_world()
	if world == null or local_tile_size <= 0:
		return result

	var min_world_x := minf(drag_start_world.x, drag_current_world.x)
	var min_world_y := minf(drag_start_world.y, drag_current_world.y)
	var max_world_x := maxf(drag_start_world.x, drag_current_world.x)
	var max_world_y := maxf(drag_start_world.y, drag_current_world.y)
	var tile_size_float := float(local_tile_size)
	var world_width := float(world.width) * tile_size_float
	var world_height := float(world.height) * tile_size_float
	if (
		max_world_x < 0.0
		or max_world_y < 0.0
		or min_world_x >= world_width
		or min_world_y >= world_height
	):
		return result

	var min_tile_x := clampi(
		int(floor(min_world_x / tile_size_float)),
		0,
		world.width - 1
	)
	var min_tile_y := clampi(
		int(floor(min_world_y / tile_size_float)),
		0,
		world.height - 1
	)
	var max_tile_x := clampi(
		int(floor(max_world_x / tile_size_float)),
		0,
		world.width - 1
	)
	var max_tile_y := clampi(
		int(floor(max_world_y / tile_size_float)),
		0,
		world.height - 1
	)
	for tile_y in range(min_tile_y, max_tile_y + 1):
		for tile_x in range(min_tile_x, max_tile_x + 1):
			result.append(Vector2i(tile_x, tile_y))
	return result


func draw_overlay(
	draw_target: CanvasItem,
	hovered_tile: Vector2i,
	natural_feature_texture: Texture2D = null,
	tree_multimesh: MultiMesh = null,
	rock_multimesh: MultiMesh = null
) -> void:
	if draw_target == null or not _has_valid_binding():
		return
	if is_cancel_mode_active:
		_draw_cancel_overlay(draw_target, hovered_tile)
		return
	if not is_command_mode_active():
		return

	var world := _get_bound_world()
	var state := _get_bound_state()
	var world_rect := Rect2(
		Vector2.ZERO,
		Vector2(
			float(world.width * local_tile_size),
			float(world.height * local_tile_size)
		)
	)
	draw_target.draw_rect(world_rect, DARKEN_COLOR, true)
	var command_snapshot := (
		CityWorkSystemScript.get_city_player_command_snapshot_for_city_state(
			state
		)
	)
	for raw_command in command_snapshot:
		if not raw_command is Dictionary:
			continue
		var command: Dictionary = raw_command
		if str(command.get("type", "")) != active_command_type:
			continue
		var raw_tile = command.get("tile_position", INVALID_TILE)
		if raw_tile is Vector2i:
			draw_target.draw_rect(
				get_tile_world_rect(raw_tile),
				HIGHLIGHT_FILL,
				true
			)

	_draw_active_command_features(
		draw_target,
		natural_feature_texture,
		tree_multimesh,
		rock_multimesh
	)
	for raw_command in command_snapshot:
		if not raw_command is Dictionary:
			continue
		var command: Dictionary = raw_command
		if str(command.get("type", "")) != active_command_type:
			continue
		var raw_tile = command.get("tile_position", INVALID_TILE)
		if not raw_tile is Vector2i:
			continue
		var border_color := HIGHLIGHT_BORDER
		if int(command.get("claimed_citizen_id", -1)) > 0:
			border_color = CLAIMED_BORDER
		_draw_tile_border(draw_target, get_tile_world_rect(raw_tile), border_color)

	var preview_fill := REMOVE_PREVIEW_FILL if drag_removing else PREVIEW_FILL
	var preview_border := (
		REMOVE_PREVIEW_BORDER if drag_removing else PREVIEW_BORDER
	)
	for tile_position in drag_preview_tiles:
		var tile_rect := get_tile_world_rect(tile_position)
		draw_target.draw_rect(tile_rect, preview_fill, true)
		_draw_tile_border(draw_target, tile_rect, preview_border)


func get_tile_world_rect(tile_position: Vector2i) -> Rect2:
	return Rect2(
		Vector2(tile_position) * float(local_tile_size),
		Vector2.ONE * float(local_tile_size)
	)


func _draw_cancel_overlay(
	draw_target: CanvasItem,
	hovered_tile: Vector2i
) -> void:
	var state := _get_bound_state()
	for raw_command in CityWorkSystemScript.get_city_player_command_snapshot_for_city_state(
		state
	):
		if not raw_command is Dictionary:
			continue
		var raw_tile = raw_command.get("tile_position", INVALID_TILE)
		if not raw_tile is Vector2i:
			continue
		var command_tile_rect := get_tile_world_rect(raw_tile)
		draw_target.draw_rect(command_tile_rect, REMOVE_PREVIEW_FILL, true)
		_draw_tile_border(
			draw_target,
			command_tile_rect,
			REMOVE_PREVIEW_BORDER
		)

	var cancel_preview_tiles := drag_preview_tiles
	if not is_dragging:
		cancel_preview_tiles = (
			CityWorkSystemScript.get_cancel_preview_tiles_for_city_state(
				state,
				[hovered_tile]
			)
		)
	for tile_position in cancel_preview_tiles:
		var tile_rect := get_tile_world_rect(tile_position)
		draw_target.draw_rect(tile_rect, REMOVE_PREVIEW_FILL, true)
		_draw_tile_border(draw_target, tile_rect, REMOVE_PREVIEW_BORDER)


func _draw_active_command_features(
	draw_target: CanvasItem,
	natural_feature_texture: Texture2D,
	tree_multimesh: MultiMesh,
	rock_multimesh: MultiMesh
) -> void:
	if natural_feature_texture == null:
		return
	if (
		active_command_type
		== CityWorkSystemScript.CITY_PLAYER_COMMAND_TYPE_CHOP_TREE
		and tree_multimesh != null
		and tree_multimesh.instance_count > 0
	):
		draw_target.draw_multimesh(tree_multimesh, natural_feature_texture)
	elif (
		active_command_type
		== CityWorkSystemScript.CITY_PLAYER_COMMAND_TYPE_COLLECT_ROCK
		and rock_multimesh != null
		and rock_multimesh.instance_count > 0
	):
		draw_target.draw_multimesh(rock_multimesh, natural_feature_texture)


func _draw_tile_border(
	draw_target: CanvasItem,
	tile_rect: Rect2,
	border_color: Color
) -> void:
	CityRenderLayerScript.draw_inner_box_border({
		"draw_target": draw_target,
		"rect": tile_rect,
		"border_color": border_color,
		"border_width": float(local_tile_size) * 0.08,
	})


func _clear_interaction_state() -> void:
	menu_open = false
	active_command_type = COMMAND_TYPE_NONE
	is_cancel_mode_active = false
	_clear_drag_state()
	if cancel_cursor_icon != null:
		cancel_cursor_icon.visible = false


func _clear_drag_state() -> void:
	is_dragging = false
	drag_removing = false
	drag_start_screen = Vector2.ZERO
	drag_current_screen = Vector2.ZERO
	drag_start_world = Vector2.ZERO
	drag_current_world = Vector2.ZERO
	drag_preview_tiles.clear()
	if selection_box_panel != null:
		selection_box_panel.visible = false


func _has_valid_binding() -> bool:
	return (
		presentation_binding != null
		and presentation_binding.is_valid()
		and presentation_binding.generation
		== highest_accepted_binding_generation
		and local_tile_size > 0
	)


func _get_bound_state() -> CitySettlementSimulationState:
	if not _has_valid_binding():
		return null
	var capability_state = presentation_binding.get_backend_capability(
		SettlementPresentationBindingScript.CAPABILITY_CITY_DETAIL
	)
	return (
		capability_state
		if capability_state is CitySettlementSimulationState
		else null
	)


func _get_bound_world() -> WorldData:
	if not _has_valid_binding():
		return null
	var capability_world = presentation_binding.get_backend_capability(
		SettlementPresentationBindingScript.CAPABILITY_SETTLEMENT_WORLD
	)
	return capability_world if capability_world is WorldData else null


func _create_flat_style(
	fill_color: Color,
	border_color: Color
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	return style


func _rect_between_points(a: Vector2, b: Vector2) -> Rect2:
	var min_position := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var max_position := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	return Rect2(min_position, max_position - min_position)
