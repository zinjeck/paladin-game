extends RefCounted
class_name SettlementPlacementController

# Owns transient object and road placement for one exact settlement
# presentation binding. Preview, cancellation, reset, and rebind operations
# only mutate this presentation-local state. Authoritative commits are routed
# through explicit settlement/state APIs and never discover an active city.

const CityConstructionSystemScript = preload(
	"res://scripts/city/simulation/systems/CityConstructionSystem.gd"
)
const CityRenderLayerScript = preload(
	"res://scripts/city/rendering/CityRenderLayer.gd"
)
const SettlementPresentationBindingScript = preload(
	"res://scripts/settlements/presentation/SettlementPresentationBinding.gd"
)

const INVALID_TILE := Vector2i(-1, -1)
const COMMIT_STATUS_COMMITTED := "committed"
const COMMIT_STATUS_INVALID_BINDING := "invalid_binding"
const COMMIT_STATUS_INVALID_POINTER := "invalid_pointer"
const COMMIT_STATUS_UNAVAILABLE := "unavailable"
const COMMIT_STATUS_INVALID_LOCATION := "invalid_location"
const COMMIT_STATUS_FAILED := "failed"
const COMMIT_STATUS_EMPTY_PREVIEW := "empty_preview"

const ROAD_PREVIEW_FILL_COLOR := Color(1.0, 1.0, 1.0, 0.08)
const ROAD_PREVIEW_BORDER_COLOR := Color(1.0, 1.0, 1.0, 0.58)

var presentation_binding: SettlementPresentationBindingScript
var highest_accepted_binding_generation: int = 0
var local_tile_size: int = 1

var active_object_placement: Dictionary = {}
var is_road_placement_active: bool = false
var is_road_dragging: bool = false
var road_preview_tiles: Array = []
var road_preview_lookup: Dictionary = {}
var road_drag_start_tile: Vector2i = INVALID_TILE
var road_drag_current_tile: Vector2i = INVALID_TILE


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
	# highest_accepted_binding_generation intentionally remains monotonic.


func is_interaction_state_clear() -> bool:
	return (
		active_object_placement.is_empty()
		and not is_road_placement_active
		and not is_road_dragging
		and road_preview_tiles.is_empty()
		and road_preview_lookup.is_empty()
		and road_drag_start_tile == INVALID_TILE
		and road_drag_current_tile == INVALID_TILE
	)


func clear_interaction_state() -> void:
	_clear_interaction_state()


func start_object_placement(
	object_type: String,
	size_tiles: Vector2i,
	object_owner: String = "player",
	repeat_after_place: bool = false
) -> bool:
	if (
		not _has_valid_binding()
		or object_type.is_empty()
		or size_tiles.x <= 0
		or size_tiles.y <= 0
	):
		return false

	active_object_placement = {
		"type": object_type,
		"size": size_tiles,
		"owner": object_owner,
		"repeat_after_place": repeat_after_place,
	}
	return true


func clear_object_placement() -> String:
	var object_type := get_active_object_type()
	active_object_placement.clear()
	return object_type


func cancel_active_object_placement() -> String:
	return clear_object_placement()


func has_active_object_placement() -> bool:
	return not active_object_placement.is_empty()


func get_active_object_type() -> String:
	return str(active_object_placement.get("type", ""))


func is_placing_object_type(object_type: String) -> bool:
	return (
		has_active_object_placement()
		and get_active_object_type() == object_type
	)


func active_object_placement_uses_environmental_source() -> bool:
	if not has_active_object_placement():
		return false

	var policy := CityObjectCatalog.get_city_object_resource_source_policy(
		active_object_placement
	)
	return (
		str(policy.get("mode", ""))
		== CityObjectCatalog.WORKPLACE_RESOURCE_SOURCE_MODE_FOOTPRINT_REACH
	)


func is_uncommitted_placement_preview_active() -> bool:
	return has_active_object_placement() or is_road_placement_active


func get_object_top_left_tile(
	center_tile: Vector2i,
	size_tiles: Vector2i
) -> Vector2i:
	var world := _get_bound_world()
	if (
		world == null
		or center_tile == INVALID_TILE
		or not world.is_in_bounds(center_tile.x, center_tile.y)
		or size_tiles.x <= 0
		or size_tiles.y <= 0
		or size_tiles.x > world.width
		or size_tiles.y > world.height
	):
		return INVALID_TILE

	var top_left := Vector2i(
		center_tile.x - int(size_tiles.x / 2),
		center_tile.y - int(size_tiles.y / 2)
	)
	top_left.x = clampi(top_left.x, 0, world.width - size_tiles.x)
	top_left.y = clampi(top_left.y, 0, world.height - size_tiles.y)
	return top_left


func get_active_object_placement_preview(
	center_tile: Vector2i
) -> Dictionary:
	if not has_active_object_placement() or not _has_valid_binding():
		return {}

	var size_tiles: Vector2i = active_object_placement.get(
		"size",
		Vector2i.ZERO
	)
	var top_left := get_object_top_left_tile(center_tile, size_tiles)
	if top_left == INVALID_TILE:
		return {}

	return {
		"type": get_active_object_type(),
		"top_left": top_left,
		"size": size_tiles,
		"owner": str(active_object_placement.get("owner", "player")),
	}


func can_place_active_object_preview(center_tile: Vector2i) -> bool:
	var preview_object := get_active_object_placement_preview(center_tile)
	if preview_object.is_empty():
		return false

	var state := _get_bound_state()
	var world := _get_bound_world()
	var object_type := str(preview_object.get("type", ""))
	var top_left: Vector2i = preview_object.get("top_left", INVALID_TILE)
	var size_tiles: Vector2i = preview_object.get("size", Vector2i.ZERO)
	if CityConstructionSystem.city_object_type_uses_construction(object_type):
		return CityConstructionSystem.can_place_city_object_construction_for_city_state(
			state,
			world,
			top_left,
			size_tiles,
			object_type
		)

	return CityObjectSystem.can_place_city_object_for_city_state(
		state,
		world,
		top_left,
		size_tiles,
		object_type
	)


func commit_active_object_placement(center_tile: Vector2i) -> Dictionary:
	if not _has_valid_binding():
		return {"status": COMMIT_STATUS_INVALID_BINDING}

	var preview_object := get_active_object_placement_preview(center_tile)
	if preview_object.is_empty():
		return {"status": COMMIT_STATUS_INVALID_POINTER}

	var object_type := str(preview_object.get("type", ""))
	var state := _get_bound_state()
	if not CityObjectSystem.can_use_city_object_definition_for_city_state(
		state,
		object_type
	):
		clear_object_placement()
		return {
			"status": COMMIT_STATUS_UNAVAILABLE,
			"object_type": object_type,
			"placement_cleared": true,
		}

	var top_left: Vector2i = preview_object.get("top_left", INVALID_TILE)
	var size_tiles: Vector2i = preview_object.get("size", Vector2i.ZERO)
	var object_owner := str(preview_object.get("owner", "player"))
	var uses_construction := (
		CityConstructionSystem.city_object_type_uses_construction(object_type)
	)
	if not can_place_active_object_preview(center_tile):
		return {
			"status": COMMIT_STATUS_INVALID_LOCATION,
			"object_type": object_type,
			"uses_construction": uses_construction,
		}

	var placement_result: Dictionary
	if uses_construction:
		placement_result = (
			CityConstructionSystemScript.create_rectangular_site_for_city_state(
				state,
				{
					"object_type": object_type,
					"top_left": top_left,
					"size_tiles": size_tiles,
					"object_owner": object_owner,
					"city_world": _get_bound_world(),
				}
			)
		)
	else:
		placement_result = (
			CityObjectSystem.place_immediate_settlement_object_for_context(
				presentation_binding.settlement_context,
				{
					"object_type": object_type,
					"top_left": top_left,
					"size_tiles": size_tiles,
					"object_owner": object_owner,
					"settlement_world": _get_bound_world(),
					"settlement_seed": _get_bound_seed(),
				}
			)
		)

	if placement_result.is_empty():
		return {
			"status": COMMIT_STATUS_FAILED,
			"object_type": object_type,
			"uses_construction": uses_construction,
		}

	var repeat_after_place := bool(
		active_object_placement.get("repeat_after_place", false)
	)
	if not repeat_after_place:
		clear_object_placement()

	return {
		"status": COMMIT_STATUS_COMMITTED,
		"object_type": object_type,
		"uses_construction": uses_construction,
		"repeat_after_place": repeat_after_place,
		"placement_cleared": not repeat_after_place,
		"placement_result": placement_result,
	}


func start_road_placement() -> bool:
	var state := _get_bound_state()
	if state == null or not state.can_build_city_objects():
		return false

	clear_object_placement()
	is_road_placement_active = true
	_reset_road_drag_and_preview()
	return true


func cancel_road_placement() -> bool:
	var had_interaction := (
		is_road_placement_active
		or is_road_dragging
		or not road_preview_tiles.is_empty()
		or not road_preview_lookup.is_empty()
	)
	is_road_placement_active = false
	_reset_road_drag_and_preview()
	return had_interaction


func handle_road_left_mouse_pressed(tile_position: Vector2i) -> String:
	if not is_road_placement_active:
		return "ignored"
	if not road_preview_tiles.is_empty() and not is_road_dragging:
		return "confirm"
	return "drag_started" if start_road_drag_selection(tile_position) else "ignored"


func handle_road_left_mouse_released() -> bool:
	if not is_road_dragging:
		return false
	is_road_dragging = false
	return true


func start_road_drag_selection(tile_position: Vector2i) -> bool:
	if not is_road_placement_active or not _is_valid_bound_tile(tile_position):
		return false

	is_road_dragging = true
	road_drag_start_tile = tile_position
	road_drag_current_tile = tile_position
	rebuild_road_preview_rectangle(
		road_drag_start_tile,
		road_drag_current_tile
	)
	return true


func update_road_drag_selection(tile_position: Vector2i) -> bool:
	if (
		not is_road_dragging
		or not _is_valid_bound_tile(tile_position)
		or tile_position == road_drag_current_tile
	):
		return false

	road_drag_current_tile = tile_position
	rebuild_road_preview_rectangle(
		road_drag_start_tile,
		road_drag_current_tile
	)
	return true


func rebuild_road_preview_rectangle(
	start_tile: Vector2i,
	end_tile: Vector2i
) -> void:
	road_preview_tiles.clear()
	road_preview_lookup.clear()
	if (
		not _has_valid_binding()
		or start_tile == INVALID_TILE
		or end_tile == INVALID_TILE
	):
		return

	var state := _get_bound_state()
	var world := _get_bound_world()
	var min_x := mini(start_tile.x, end_tile.x)
	var max_x := maxi(start_tile.x, end_tile.x)
	var min_y := mini(start_tile.y, end_tile.y)
	var max_y := maxi(start_tile.y, end_tile.y)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var tile_position := Vector2i(x, y)
			if road_preview_lookup.has(tile_position):
				continue
			if not CityConstructionSystem.can_place_city_road_tile_for_city_state(
				state,
				world,
				tile_position
			):
				continue
			road_preview_lookup[tile_position] = true
			road_preview_tiles.append(tile_position)


func confirm_road_preview() -> Dictionary:
	if not _has_valid_binding():
		return {"status": COMMIT_STATUS_INVALID_BINDING}
	if road_preview_tiles.is_empty():
		return {"status": COMMIT_STATUS_EMPTY_PREVIEW}

	var state := _get_bound_state()
	if not CityObjectSystem.can_use_city_object_definition_for_city_state(
		state,
		CityObjectCatalog.CITY_OBJECT_ROAD
	):
		cancel_road_placement()
		return {
			"status": COMMIT_STATUS_UNAVAILABLE,
			"placement_cleared": true,
		}

	var construction_sites := (
		CityConstructionSystemScript.create_road_sites_for_city_state(
			state,
			road_preview_tiles,
			"player",
			_get_bound_world()
		)
	)
	if construction_sites.is_empty():
		road_preview_tiles.clear()
		road_preview_lookup.clear()
		return {"status": COMMIT_STATUS_FAILED}

	is_road_placement_active = true
	_reset_road_drag_and_preview()
	return {
		"status": COMMIT_STATUS_COMMITTED,
		"placed_tile_count": construction_sites.size(),
		"construction_sites": construction_sites,
	}


func draw_road_preview(draw_target: CanvasItem) -> void:
	if (
		draw_target == null
		or not is_road_placement_active
		or road_preview_tiles.is_empty()
	):
		return

	var border_width := float(local_tile_size) * 0.06
	for tile_position in road_preview_tiles:
		if not tile_position is Vector2i:
			continue
		var rect := _get_tile_world_rect(tile_position)
		draw_target.draw_rect(rect, ROAD_PREVIEW_FILL_COLOR, true)
		CityRenderLayerScript.draw_inner_box_border({
			"draw_target": draw_target,
			"rect": rect,
			"border_color": ROAD_PREVIEW_BORDER_COLOR,
			"border_width": border_width,
		})


func draw_active_object_placement_preview(
	draw_target: CanvasItem,
	center_tile: Vector2i,
	has_workplace_zone: bool,
	draw_object_visual: Callable
) -> void:
	if draw_target == null or not draw_object_visual.is_valid():
		return

	var preview_object := get_active_object_placement_preview(center_tile)
	if preview_object.is_empty():
		return

	draw_object_visual.call(
		draw_target,
		preview_object,
		0.65 if has_workplace_zone else 0.45,
		can_place_active_object_preview(center_tile)
	)


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


func _get_bound_seed() -> int:
	if not _has_valid_binding():
		return 0
	var capability_seed = presentation_binding.get_backend_capability(
		SettlementPresentationBindingScript.CAPABILITY_DETERMINISTIC_SEED
	)
	return int(capability_seed) if capability_seed is int else 0


func _is_valid_bound_tile(tile_position: Vector2i) -> bool:
	var world := _get_bound_world()
	return (
		world != null
		and tile_position != INVALID_TILE
		and world.is_in_bounds(tile_position.x, tile_position.y)
	)


func _get_tile_world_rect(tile_position: Vector2i) -> Rect2:
	return Rect2(
		Vector2(tile_position) * float(local_tile_size),
		Vector2.ONE * float(local_tile_size)
	)


func _reset_road_drag_and_preview() -> void:
	is_road_dragging = false
	road_preview_tiles.clear()
	road_preview_lookup.clear()
	road_drag_start_tile = INVALID_TILE
	road_drag_current_tile = INVALID_TILE


func _clear_interaction_state() -> void:
	active_object_placement.clear()
	is_road_placement_active = false
	_reset_road_drag_and_preview()
