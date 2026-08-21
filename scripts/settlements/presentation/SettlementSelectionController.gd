extends RefCounted
class_name SettlementSelectionController

const SettlementPresentationBindingScript = preload(
	"res://scripts/settlements/presentation/SettlementPresentationBinding.gd"
)

# Owns transient selection and hover presentation for one exact settlement
# binding. Pointer positions are supplied by the caller so this component never
# discovers a globally active/presented settlement or depends on a renderer.

const CityRenderLayerScript = preload(
	"res://scripts/city/rendering/CityRenderLayer.gd"
)

const INVALID_TILE := Vector2i(-1, -1)
const SELECTION_KIND_NONE := "none"
const SELECTION_KIND_OBJECT := "object"
const SELECTION_KIND_CITIZEN := "citizen"
const SELECTION_KIND_CONSTRUCTION_SITE := "construction_site"
const SELECTION_DRAG_THRESHOLD_PIXELS := 4.0
const HOVER_FILL_COLOR := Color(1.0, 1.0, 1.0, 0.08)
const HOVER_BORDER_COLOR := Color(1.0, 1.0, 1.0, 0.58)
const SELECTED_ENTITY_HIGHLIGHT_COLOR := Color(0.0, 0.85, 1.0, 1.0)

var presentation_binding: SettlementPresentationBindingScript
var highest_accepted_binding_generation: int = 0
var local_tile_size: int = 1

var hovered_settlement_tile: Vector2i = INVALID_TILE
var selected_settlement_entity_kind: String = SELECTION_KIND_NONE
var selected_settlement_entity_id: int = -1

var selection_box_panel: Panel
var is_selection_dragging: bool = false
var selection_drag_start_screen: Vector2 = Vector2.ZERO
var selection_drag_current_screen: Vector2 = Vector2.ZERO
var selection_drag_start_world: Vector2 = Vector2.ZERO
var selection_drag_current_world: Vector2 = Vector2.ZERO


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
	# Keep the high-water mark so a delayed pre-reset bind cannot revive stale
	# settlement selection state.


func clear_interaction_state() -> Dictionary:
	var transition := _create_selection_transition()
	_clear_interaction_state()
	transition["current_kind"] = selected_settlement_entity_kind
	transition["current_id"] = selected_settlement_entity_id
	transition["changed"] = (
		str(transition["previous_kind"]) != selected_settlement_entity_kind
		or int(transition["previous_id"]) != selected_settlement_entity_id
	)
	return transition


func is_interaction_state_clear() -> bool:
	return (
		not has_selected_settlement_entity()
		and hovered_settlement_tile == INVALID_TILE
		and not is_selection_dragging
		and selection_drag_start_screen == Vector2.ZERO
		and selection_drag_current_screen == Vector2.ZERO
		and selection_drag_start_world == Vector2.ZERO
		and selection_drag_current_world == Vector2.ZERO
		and (selection_box_panel == null or not selection_box_panel.visible)
	)


func create_selection_box_visual(ui_parent: Node) -> Panel:
	if selection_box_panel != null:
		return selection_box_panel
	if ui_parent == null:
		return null

	selection_box_panel = Panel.new()
	selection_box_panel.visible = false
	selection_box_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var box_style := StyleBoxFlat.new()
	box_style.bg_color = HOVER_FILL_COLOR
	box_style.border_color = HOVER_BORDER_COLOR
	box_style.border_width_left = 1
	box_style.border_width_right = 1
	box_style.border_width_top = 1
	box_style.border_width_bottom = 1
	selection_box_panel.add_theme_stylebox_override("panel", box_style)
	ui_parent.add_child(selection_box_panel)
	return selection_box_panel


func update_selection_box_visual() -> void:
	if selection_box_panel == null:
		return

	var drag_distance := selection_drag_start_screen.distance_to(
		selection_drag_current_screen
	)
	if not is_selection_dragging or drag_distance < SELECTION_DRAG_THRESHOLD_PIXELS:
		selection_box_panel.visible = false
		return

	var screen_rect := _rect_between_points(
		selection_drag_start_screen,
		selection_drag_current_screen
	)
	selection_box_panel.visible = true
	selection_box_panel.position = screen_rect.position
	selection_box_panel.size = screen_rect.size
	selection_box_panel.move_to_front()


func begin_selection_drag(
	screen_position: Vector2,
	world_position: Vector2
) -> bool:
	if not _has_valid_binding():
		return false
	is_selection_dragging = true
	selection_drag_start_screen = screen_position
	selection_drag_current_screen = screen_position
	selection_drag_start_world = world_position
	selection_drag_current_world = world_position
	update_selection_box_visual()
	return true


func update_selection_drag(
	screen_position: Vector2,
	world_position: Vector2
) -> bool:
	if not is_selection_dragging or not _has_valid_binding():
		return false
	selection_drag_current_screen = screen_position
	selection_drag_current_world = world_position
	update_selection_box_visual()
	return true


func finish_selection_drag(
	screen_position: Vector2,
	world_position: Vector2,
	citizen_movement_presentation: CityCitizenMovementPresentation = null
) -> Dictionary:
	if not is_selection_dragging or not _has_valid_binding():
		return {"completed": false}

	is_selection_dragging = false
	selection_drag_current_screen = screen_position
	selection_drag_current_world = world_position
	update_selection_box_visual()

	var drag_distance := selection_drag_start_screen.distance_to(
		selection_drag_current_screen
	)
	var result: Dictionary
	if drag_distance < SELECTION_DRAG_THRESHOLD_PIXELS:
		result = select_settlement_entity_at_world_point(
			world_position,
			citizen_movement_presentation
		)
		result["was_click"] = true
	else:
		result = select_settlement_object_in_world_rect(
			get_selection_world_rect()
		)
		result["was_click"] = false
	result["completed"] = true
	return result


func cancel_selection_drag() -> bool:
	var had_drag := is_selection_dragging
	is_selection_dragging = false
	selection_drag_start_screen = Vector2.ZERO
	selection_drag_current_screen = Vector2.ZERO
	selection_drag_start_world = Vector2.ZERO
	selection_drag_current_world = Vector2.ZERO
	update_selection_box_visual()
	return had_drag


func get_selection_world_rect() -> Rect2:
	return _rect_between_points(
		selection_drag_start_world,
		selection_drag_current_world
	)


func update_hovered_settlement_tile(tile_position: Vector2i) -> bool:
	var next_tile := tile_position
	var world := _get_bound_world()
	if (
		world == null
		or not world.is_in_bounds(tile_position.x, tile_position.y)
	):
		next_tile = INVALID_TILE
	if next_tile == hovered_settlement_tile:
		return false
	hovered_settlement_tile = next_tile
	return true


func world_position_to_settlement_tile(world_position: Vector2) -> Vector2i:
	var world := _get_bound_world()
	if world == null or local_tile_size <= 0:
		return INVALID_TILE

	var tile_position := Vector2i(
		int(floor(world_position.x / float(local_tile_size))),
		int(floor(world_position.y / float(local_tile_size)))
	)
	if not world.is_in_bounds(tile_position.x, tile_position.y):
		return INVALID_TILE
	return tile_position


func has_selected_settlement_entity() -> bool:
	return (
		selected_settlement_entity_kind != SELECTION_KIND_NONE
		and selected_settlement_entity_id >= 0
	)


func get_selected_settlement_object_id() -> int:
	if selected_settlement_entity_kind == SELECTION_KIND_OBJECT:
		return selected_settlement_entity_id
	return -1


func get_selected_settlement_citizen_id() -> int:
	if selected_settlement_entity_kind == SELECTION_KIND_CITIZEN:
		return selected_settlement_entity_id
	return -1


func get_selected_settlement_construction_site_id() -> int:
	if selected_settlement_entity_kind == SELECTION_KIND_CONSTRUCTION_SITE:
		return selected_settlement_entity_id
	return -1


func set_selected_settlement_entity(
	selection_kind: String,
	entity_id: int
) -> Dictionary:
	var transition := _create_selection_transition()
	if entity_id < 0 or not _is_selectable_entity(selection_kind, entity_id):
		selected_settlement_entity_kind = SELECTION_KIND_NONE
		selected_settlement_entity_id = -1
	else:
		selected_settlement_entity_kind = selection_kind
		selected_settlement_entity_id = entity_id
	return _complete_selection_transition(transition)


func set_selected_settlement_object(object_id: int) -> Dictionary:
	return set_selected_settlement_entity(SELECTION_KIND_OBJECT, object_id)


func set_selected_settlement_citizen(citizen_id: int) -> Dictionary:
	return set_selected_settlement_entity(SELECTION_KIND_CITIZEN, citizen_id)


func set_selected_settlement_construction_site(site_id: int) -> Dictionary:
	return set_selected_settlement_entity(
		SELECTION_KIND_CONSTRUCTION_SITE,
		site_id
	)


func clear_selected_settlement_entity() -> Dictionary:
	var transition := _create_selection_transition()
	selected_settlement_entity_kind = SELECTION_KIND_NONE
	selected_settlement_entity_id = -1
	return _complete_selection_transition(transition)


func select_settlement_entity_at_world_point(
	world_position: Vector2,
	citizen_movement_presentation: CityCitizenMovementPresentation = null
) -> Dictionary:
	var tile_position := world_position_to_settlement_tile(world_position)
	if tile_position == INVALID_TILE:
		var invalid_result := clear_selected_settlement_entity()
		invalid_result["tile_valid"] = false
		invalid_result["empty_target"] = false
		return invalid_result

	var citizen_ids := get_selectable_settlement_citizen_ids_at_world_point(
		tile_position,
		world_position,
		citizen_movement_presentation
	)
	if not citizen_ids.is_empty():
		var next_citizen_id := int(citizen_ids[0])
		if selected_settlement_entity_kind == SELECTION_KIND_CITIZEN:
			var current_index := citizen_ids.find(selected_settlement_entity_id)
			if current_index >= 0:
				next_citizen_id = int(
					citizen_ids[(current_index + 1) % citizen_ids.size()]
				)
		var citizen_result := set_selected_settlement_citizen(next_citizen_id)
		citizen_result["tile_valid"] = true
		citizen_result["empty_target"] = false
		return citizen_result

	var state := _get_bound_state()
	var construction_site := (
		CityConstructionSystem.get_city_construction_site_at_tile_for_city_state(
			state,
			tile_position
		)
	)
	if is_settlement_construction_site_selectable(construction_site):
		var site_result := set_selected_settlement_construction_site(
			int(construction_site.get("id", -1))
		)
		site_result["tile_valid"] = true
		site_result["empty_target"] = false
		return site_result

	var settlement_object := (
		CityObjectSystem.get_city_object_at_tile_for_city_state(
			state,
			tile_position
		)
	)
	if is_settlement_object_selectable(settlement_object):
		var object_result := set_selected_settlement_object(
			int(settlement_object.get("id", -1))
		)
		object_result["tile_valid"] = true
		object_result["empty_target"] = false
		return object_result

	var empty_result := clear_selected_settlement_entity()
	empty_result["tile_valid"] = true
	empty_result["empty_target"] = true
	empty_result["tile_position"] = tile_position
	return empty_result


func select_settlement_object_in_world_rect(world_rect: Rect2) -> Dictionary:
	var best_object_id := -1
	var best_area := -1.0
	var state := _get_bound_state()
	if state != null:
		for settlement_object in CityObjectSystem.get_city_objects_for_city_state(state):
			if not is_settlement_object_selectable(settlement_object):
				continue
			var object_rect := get_settlement_object_world_rect(settlement_object)
			if not world_rect.intersects(object_rect, true):
				continue
			var object_area := object_rect.size.x * object_rect.size.y
			if best_object_id == -1 or object_area > best_area:
				best_object_id = int(settlement_object.get("id", -1))
				best_area = object_area

	if best_object_id < 0:
		return clear_selected_settlement_entity()
	return set_selected_settlement_object(best_object_id)


func get_selectable_settlement_citizen_ids_at_world_point(
	tile_position: Vector2i,
	world_position: Vector2,
	citizen_movement_presentation: CityCitizenMovementPresentation = null
) -> Array:
	var selectable_citizen_ids := []
	var state := _get_bound_state()
	if state == null:
		return selectable_citizen_ids

	var candidate_lookup: Dictionary = {}
	for raw_citizen_id in (
		CityCitizenSpatialSystem.get_city_citizen_ids_at_tile_for_city_state(
			state,
			tile_position
		)
	):
		if typeof(raw_citizen_id) == TYPE_INT:
			candidate_lookup[raw_citizen_id] = true

	if _movement_presentation_matches_binding(citizen_movement_presentation):
		for raw_citizen_id in (
			citizen_movement_presentation
			.get_transitioning_citizen_ids_snapshot()
		):
			if typeof(raw_citizen_id) == TYPE_INT:
				candidate_lookup[raw_citizen_id] = true

	var candidate_ids: Array = candidate_lookup.keys()
	candidate_ids.sort()
	for raw_citizen_id in candidate_ids:
		var citizen_id := int(raw_citizen_id)
		var citizen := (
			CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
				state,
				citizen_id
			)
		)
		if citizen.is_empty() or not bool(citizen.get("alive", false)):
			continue
		var citizen_rect := _get_citizen_world_rect(
			citizen,
			citizen_movement_presentation
		)
		if citizen_rect.has_point(world_position):
			selectable_citizen_ids.append(citizen_id)

	selectable_citizen_ids.sort()
	return selectable_citizen_ids


func get_settlement_object_by_id(object_id) -> Dictionary:
	if typeof(object_id) != TYPE_INT or int(object_id) < 0:
		return {}
	var state := _get_bound_state()
	if state == null:
		return {}
	return CityObjectSystem.get_city_object_by_id_for_city_state(
		state,
		int(object_id)
	)


func is_settlement_object_selectable(settlement_object: Dictionary) -> bool:
	return not settlement_object.is_empty()


func is_settlement_construction_site_selectable(
	construction_site: Dictionary
) -> bool:
	return not construction_site.is_empty()


func get_settlement_object_world_rect(
	settlement_object: Dictionary
) -> Rect2:
	if settlement_object.is_empty():
		return Rect2()
	if settlement_object.has("top_left") and settlement_object.has("size"):
		var top_left: Vector2i = settlement_object["top_left"]
		var size_tiles: Vector2i = settlement_object["size"]
		return Rect2(
			Vector2(top_left * local_tile_size),
			Vector2(size_tiles * local_tile_size)
		)
	return get_settlement_tile_collection_world_rect(
		CityObjectSystem.get_city_object_footprint_tiles(settlement_object)
	)


func get_settlement_tile_collection_world_rect(raw_tiles: Array) -> Rect2:
	var has_tile := false
	var minimum_tile := Vector2i.ZERO
	var maximum_tile := Vector2i.ZERO
	for raw_tile in raw_tiles:
		if not raw_tile is Vector2i:
			continue
		var tile_position: Vector2i = raw_tile
		if not has_tile:
			minimum_tile = tile_position
			maximum_tile = tile_position
			has_tile = true
			continue
		minimum_tile.x = mini(minimum_tile.x, tile_position.x)
		minimum_tile.y = mini(minimum_tile.y, tile_position.y)
		maximum_tile.x = maxi(maximum_tile.x, tile_position.x)
		maximum_tile.y = maxi(maximum_tile.y, tile_position.y)

	if not has_tile:
		return Rect2()
	return Rect2(
		Vector2(minimum_tile * local_tile_size),
		Vector2((maximum_tile - minimum_tile + Vector2i.ONE) * local_tile_size)
	)


func get_settlement_tile_world_rect(tile_position: Vector2i) -> Rect2:
	return Rect2(
		Vector2(tile_position * local_tile_size),
		Vector2(local_tile_size, local_tile_size)
	)


func get_hover_highlight_tiles(
	tile_position: Vector2i,
	is_road_placement_active: bool = false
) -> Array[Vector2i]:
	var fallback_tiles: Array[Vector2i] = []
	var world := _get_bound_world()
	if (
		world == null
		or not world.is_in_bounds(tile_position.x, tile_position.y)
	):
		return fallback_tiles
	fallback_tiles.append(tile_position)
	if is_road_placement_active:
		return fallback_tiles

	var state := _get_bound_state()
	var construction_site := (
		CityConstructionSystem.get_city_construction_site_at_tile_for_city_state(
			state,
			tile_position
		)
	)
	if not construction_site.is_empty():
		if (
			str(construction_site.get("object_type", ""))
			== CityObjectCatalog.CITY_OBJECT_ROAD
		):
			return fallback_tiles
		var construction_tiles := normalize_hover_footprint_tiles(
			construction_site.get("footprint_tiles", [])
		)
		if not construction_tiles.is_empty():
			return construction_tiles

	var settlement_object := (
		CityObjectSystem.get_city_object_at_tile_for_city_state(
			state,
			tile_position
		)
	)
	if not is_settlement_object_selectable(settlement_object):
		return fallback_tiles
	var object_tiles := normalize_hover_footprint_tiles(
		CityObjectSystem.get_city_object_footprint_tiles(settlement_object)
	)
	if object_tiles.is_empty():
		return fallback_tiles
	return object_tiles


func normalize_hover_footprint_tiles(raw_tiles: Array) -> Array[Vector2i]:
	var tile_lookup: Dictionary = {}
	var world := _get_bound_world()
	for raw_tile in raw_tiles:
		if not raw_tile is Vector2i:
			continue
		var tile_position: Vector2i = raw_tile
		if (
			world != null
			and not world.is_in_bounds(tile_position.x, tile_position.y)
		):
			continue
		tile_lookup[tile_position] = true

	var footprint_tiles: Array[Vector2i] = []
	for raw_tile in tile_lookup.keys():
		if raw_tile is Vector2i:
			footprint_tiles.append(raw_tile)
	footprint_tiles.sort_custom(_sort_tiles_y_then_x)
	return footprint_tiles


func draw_selected_settlement_citizen_highlight(
	draw_target: CanvasItem,
	viewport: Viewport,
	citizen_movement_presentation: CityCitizenMovementPresentation = null
) -> void:
	var citizen_id := get_selected_settlement_citizen_id()
	var state := _get_bound_state()
	if citizen_id < 0 or state == null:
		return
	var citizen := (
		CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
			state,
			citizen_id
		)
	)
	if citizen.is_empty() or not bool(citizen.get("alive", false)):
		return
	_draw_selected_world_rect(
		draw_target,
		viewport,
		_get_citizen_world_rect(citizen, citizen_movement_presentation)
	)


func draw_selected_settlement_object_highlight(
	draw_target: CanvasItem,
	viewport: Viewport
) -> void:
	var settlement_object := get_settlement_object_by_id(
		get_selected_settlement_object_id()
	)
	if not is_settlement_object_selectable(settlement_object):
		return
	_draw_selected_world_rect(
		draw_target,
		viewport,
		get_settlement_object_world_rect(settlement_object)
	)


func draw_selected_settlement_construction_site_highlight(
	draw_target: CanvasItem,
	viewport: Viewport
) -> void:
	var site_id := get_selected_settlement_construction_site_id()
	var state := _get_bound_state()
	if site_id <= 0 or state == null:
		return
	var site := (
		CityConstructionSystem.get_city_construction_site_by_id_for_city_state(
			state,
			site_id
		)
	)
	if not is_settlement_construction_site_selectable(site):
		return
	_draw_selected_world_rect(
		draw_target,
		viewport,
		get_settlement_tile_collection_world_rect(
			site.get("footprint_tiles", [])
		)
	)


func draw_hovered_settlement_tile_highlight(
	draw_target: CanvasItem,
	values: Dictionary
) -> void:
	if (
		bool(values.get("has_active_object_placement", false))
		or bool(values.get("is_player_command_mode_active", false))
		or hovered_settlement_tile == INVALID_TILE
		or is_selection_dragging
	):
		return
	var debug_selected_tile: Vector2i = values.get(
		"debug_selected_tile",
		INVALID_TILE
	)
	if (
		bool(values.get("debug_mode_enabled", false))
		and hovered_settlement_tile == debug_selected_tile
	):
		return
	var road_placement_active := bool(
		values.get("is_road_placement_active", false)
	)
	if has_selected_settlement_entity() and not road_placement_active:
		return

	CityRenderLayerScript.draw_tile_footprint_border({
		"draw_target": draw_target,
		"footprint_tiles": get_hover_highlight_tiles(
			hovered_settlement_tile,
			road_placement_active
		),
		"border_color": HOVER_BORDER_COLOR,
		"border_width": float(local_tile_size) * 0.08,
		"tile_size": local_tile_size,
	})


func _is_selectable_entity(selection_kind: String, entity_id: int) -> bool:
	var state := _get_bound_state()
	if state == null:
		return false
	if selection_kind == SELECTION_KIND_OBJECT:
		return is_settlement_object_selectable(
			CityObjectSystem.get_city_object_by_id_for_city_state(state, entity_id)
		)
	if selection_kind == SELECTION_KIND_CITIZEN:
		var citizen := (
			CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
				state,
				entity_id
			)
		)
		return not citizen.is_empty() and bool(citizen.get("alive", false))
	if selection_kind == SELECTION_KIND_CONSTRUCTION_SITE:
		return is_settlement_construction_site_selectable(
			CityConstructionSystem.get_city_construction_site_by_id_for_city_state(
				state,
				entity_id
			)
		)
	return false


func _get_citizen_world_rect(
	citizen: Dictionary,
	citizen_movement_presentation: CityCitizenMovementPresentation
) -> Rect2:
	if _movement_presentation_matches_binding(citizen_movement_presentation):
		return citizen_movement_presentation.get_citizen_world_rect(citizen)

	var tile_position = citizen.get("city_tile_position", INVALID_TILE)
	if not tile_position is Vector2i or tile_position == INVALID_TILE:
		return Rect2()
	var marker_size := maxf(float(local_tile_size) * 0.34, 0.5)
	var tile_center := Vector2(
		(float(tile_position.x) + 0.5) * float(local_tile_size),
		(float(tile_position.y) + 0.5) * float(local_tile_size)
	)
	return Rect2(
		tile_center - Vector2(marker_size, marker_size) * 0.5,
		Vector2(marker_size, marker_size)
	)


func _movement_presentation_matches_binding(
	citizen_movement_presentation: CityCitizenMovementPresentation
) -> bool:
	return (
		citizen_movement_presentation != null
		and presentation_binding != null
		and citizen_movement_presentation
		.is_bound_to_settlement_presentation(presentation_binding)
	)


func _draw_selected_world_rect(
	draw_target: CanvasItem,
	viewport: Viewport,
	world_rect: Rect2
) -> void:
	if world_rect.size.x <= 0.0 or world_rect.size.y <= 0.0:
		return
	CityRenderLayerScript.draw_screen_constant_inset_rect_border({
		"draw_target": draw_target,
		"rect": world_rect,
		"border_color": SELECTED_ENTITY_HIGHLIGHT_COLOR,
		"inset_amount": 0.0,
		"border_width_pixels": 2.0,
		"viewport": viewport,
	})


func _create_selection_transition() -> Dictionary:
	return {
		"previous_kind": selected_settlement_entity_kind,
		"previous_id": selected_settlement_entity_id,
		"current_kind": selected_settlement_entity_kind,
		"current_id": selected_settlement_entity_id,
		"changed": false,
	}


func _complete_selection_transition(transition: Dictionary) -> Dictionary:
	transition["current_kind"] = selected_settlement_entity_kind
	transition["current_id"] = selected_settlement_entity_id
	transition["changed"] = (
		str(transition.get("previous_kind", SELECTION_KIND_NONE))
		!= selected_settlement_entity_kind
		or int(transition.get("previous_id", -1))
		!= selected_settlement_entity_id
	)
	return transition


func _rect_between_points(a: Vector2, b: Vector2) -> Rect2:
	var minimum := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var maximum := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	return Rect2(minimum, maximum - minimum)


func _sort_tiles_y_then_x(a: Vector2i, b: Vector2i) -> bool:
	if a.y == b.y:
		return a.x < b.x
	return a.y < b.y


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


func _has_valid_binding() -> bool:
	return (
		presentation_binding != null
		and presentation_binding.is_valid()
		and presentation_binding.generation == highest_accepted_binding_generation
		and local_tile_size > 0
	)


func _clear_interaction_state() -> void:
	hovered_settlement_tile = INVALID_TILE
	selected_settlement_entity_kind = SELECTION_KIND_NONE
	selected_settlement_entity_id = -1
	is_selection_dragging = false
	selection_drag_start_screen = Vector2.ZERO
	selection_drag_current_screen = Vector2.ZERO
	selection_drag_start_world = Vector2.ZERO
	selection_drag_current_world = Vector2.ZERO
	if selection_box_panel != null:
		selection_box_panel.visible = false
