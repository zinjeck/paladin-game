extends RefCounted
class_name CityDebugPresentation

# Diagnostics plus two deliberately explicit debug-command adapters for one
# exactly bound settlement presentation. The helper never discovers authority
# through the globally selected settlement, and its command entry points require
# the caller to supply the same immutable binding token before gameplay changes.

const CityStateValidator = preload(
	"res://scripts/city/simulation/CityStateValidator.gd"
)
const CityNavigationSystemScript = preload(
	"res://scripts/city/simulation/systems/CityNavigationSystem.gd"
)
const CityRenderLayerScript = preload(
	"res://scripts/city/rendering/CityRenderLayer.gd"
)

const CITY_SELECTION_KIND_CITIZEN := "citizen"
const PANEL_POSITION := Vector2.ZERO
const PANEL_PADDING := Vector2(12.0, 10.0)
const PANEL_MINIMUM_SIZE := Vector2(430.0, 170.0)
const DEBUG_CITY_OBJECT_NAME_TARGET_FONT_SIZE: int = 11
const DEBUG_CITY_OBJECT_NAME_MIN_FONT_SIZE: int = 6
const DEBUG_CITY_OBJECT_NAME_TEXT_COLOR: Color = Color(0.82, 0.94, 1.0, 1.0)
const DEBUG_CITY_OBJECT_NAME_SHADOW_COLOR: Color = Color(0.0, 0.0, 0.0, 0.85)
const DEBUG_CITY_OBJECT_NAME_BACKGROUND_COLOR: Color = Color(0.0, 0.0, 0.0, 0.55)
const DEBUG_CITY_OBJECT_NAME_PADDING: Vector2 = Vector2(4.0, 2.0)
const DEBUG_CITY_OBJECT_NAME_MAX_WIDTH_RATIO: float = 0.82
const DEBUG_CITY_OBJECT_NAME_MAX_HEIGHT_RATIO: float = 0.45
const DEBUG_NAVIGATION_PATH_FILL_COLOR := Color(1.0, 0.82, 0.0, 0.34)
const DEBUG_NAVIGATION_PATH_LINE_COLOR := Color(1.0, 0.95, 0.20, 0.92)
const DEBUG_SELECTED_TILE_HIGHLIGHT_COLOR := Color(0.0, 1.0, 1.0, 1.0)
const DEBUG_COMMAND_STATUS_SUCCESS := "success"
const DEBUG_COMMAND_STATUS_DISABLED := "debug_mode_disabled"
const DEBUG_COMMAND_STATUS_INVALID_BINDING := "invalid_binding"
const DEBUG_COMMAND_STATUS_NO_SELECTION := "no_selection"
const DEBUG_COMMAND_STATUS_OBJECT_MISSING := "object_missing"
const DEBUG_COMMAND_STATUS_NOT_PUBLIC_STORAGE := "not_public_storage"
const DEBUG_COMMAND_STATUS_UNSUPPORTED_RESOURCE := "unsupported_resource"
const DEBUG_COMMAND_STATUS_INVALID_AMOUNT := "invalid_amount"
const DEBUG_COMMAND_STATUS_STORAGE_FULL := "storage_full"
const DEBUG_COMMAND_STATUS_PATH_NOT_READY := "path_not_ready"
const DEBUG_COMMAND_STATUS_CITIZEN_MISSING := "citizen_missing"
const DEBUG_COMMAND_STATUS_CITIZEN_NOT_ALIVE := "citizen_not_alive"
const DEBUG_COMMAND_STATUS_INVALID_POSITION := "invalid_position"
const DEBUG_COMMAND_STATUS_STALE_PATH := "stale_path"
const DEBUG_COMMAND_STATUS_AUTHORITATIVE_REJECTION := "authoritative_rejection"

var presentation_binding: CityPresentationBinding
var citizen_debug_panel := CitizenDebugPanel.new()
var debug_panel_ui: DebugPanel
var binding_generation: int = 0
var highest_accepted_binding_generation: int = 0
var local_tile_size: int = 0
var refresh_pending: bool = false
var navigation_path: Array = []
var navigation_status: String = CityNavigationSystemScript.PATH_STATUS_NOT_REQUESTED
var navigation_start_tile: Vector2i = CityCitizens.INVALID_CITY_TILE_POSITION
var navigation_destination_tile: Vector2i = CityCitizens.INVALID_CITY_TILE_POSITION
var navigation_candidate_count: int = 0
var navigation_expanded_nodes: int = 0
var navigation_path_cost: int = 0
var navigation_duration_usec: int = 0
var selected_tile: Vector2i = CityCitizens.INVALID_CITY_TILE_POSITION
var view_values: Dictionary = {}


func can_bind_settlement_presentation(
	binding: CityPresentationBinding,
	debug_panel: CitizenDebugPanel = null
) -> bool:
	if binding == null or not binding.is_valid():
		return false
	var target_debug_panel := (
		debug_panel if debug_panel != null else citizen_debug_panel
	)
	if target_debug_panel == null:
		return false
	if is_bound_to_settlement_presentation(binding):
		return target_debug_panel.is_bound_to_settlement_presentation(binding)
	if binding.generation <= highest_accepted_binding_generation:
		return false
	return target_debug_panel.can_bind_settlement_presentation(binding)


func bind_settlement_presentation(
	binding: CityPresentationBinding,
	debug_panel: CitizenDebugPanel = null
) -> bool:
	if not can_bind_settlement_presentation(binding, debug_panel):
		return false
	var target_debug_panel := (
		debug_panel if debug_panel != null else citizen_debug_panel
	)
	if is_bound_to_settlement_presentation(binding):
		return target_debug_panel.is_bound_to_settlement_presentation(binding)
	if not target_debug_panel.bind_settlement_presentation(binding):
		return false
	presentation_binding = binding
	citizen_debug_panel = target_debug_panel
	binding_generation = binding.generation
	highest_accepted_binding_generation = binding.generation
	clear_presentation_state()
	return true


func bind_city_presentation(
	binding: CityPresentationBinding,
	debug_panel: CitizenDebugPanel = null
) -> bool:
	return bind_settlement_presentation(binding, debug_panel)


func is_bound_to_settlement_presentation(
	binding: CityPresentationBinding
) -> bool:
	return (
		presentation_binding != null
		and presentation_binding.matches_binding(binding)
		and binding_generation == binding.generation
		and citizen_debug_panel != null
		and citizen_debug_panel.is_bound_to_settlement_presentation(binding)
	)


func is_bound_to_city_presentation(
	binding: CityPresentationBinding
) -> bool:
	return is_bound_to_settlement_presentation(binding)


func reset() -> void:
	presentation_binding = null
	binding_generation = 0
	if citizen_debug_panel != null:
		citizen_debug_panel.reset()
	clear_presentation_state()


func _get_bound_city_state() -> CitySettlementSimulationState:
	if (
		presentation_binding == null
		or not presentation_binding.is_valid()
		or presentation_binding.generation != binding_generation
	):
		return null
	return presentation_binding.city_state


func configure_ui(parent: Node, tile_size: int) -> bool:
	if (
		parent == null
		or tile_size <= 0
		or presentation_binding == null
		or not presentation_binding.is_valid()
		or citizen_debug_panel == null
	):
		return false
	local_tile_size = tile_size
	if debug_panel_ui != null:
		return true
	debug_panel_ui = DebugPanel.new()
	debug_panel_ui.setup({
		"parent": parent,
		"canvas_layer_index": 120,
		"panel_position": PANEL_POSITION,
		"padding": PANEL_PADDING,
		"minimum_size": PANEL_MINIMUM_SIZE,
		"initial_text": "DEBUG INFO",
		"text_provider": Callable(self, "get_panel_text_current"),
	})
	citizen_debug_panel.setup({
		"debug_panel": debug_panel_ui,
		"presentation_binding": presentation_binding,
		"text_provider": Callable(citizen_debug_panel, "get_debug_list_text"),
	})
	return debug_panel_ui.panel != null


func clear_presentation_state() -> void:
	clear_selected_tile()
	clear_navigation_result()
	view_values.clear()
	refresh_pending = false


func request_refresh() -> void:
	refresh_pending = true


func clear_refresh_request() -> void:
	refresh_pending = false


func update_view_values(values: Dictionary) -> void:
	view_values = values.duplicate()


func refresh(values: Dictionary = {}) -> void:
	if not values.is_empty():
		update_view_values(values)
	refresh_pending = false
	if debug_panel_ui != null:
		debug_panel_ui.refresh()
	if citizen_debug_panel != null:
		citizen_debug_panel.refresh()


func toggle_enabled() -> bool:
	if debug_panel_ui == null:
		return WorldData.debug_mode_enabled
	var is_enabled := debug_panel_ui.toggle_enabled()
	if citizen_debug_panel != null:
		citizen_debug_panel.refresh()
	if is_enabled and presentation_binding != null:
		CityStateValidator.validate_for_settlement(
			presentation_binding.settlement_context,
			true,
			true
		)
		debug_panel_ui.refresh()
	return is_enabled


func get_panel_text_current() -> String:
	return get_panel_text(_make_current_presentation_values())


func get_navigation_text_current() -> String:
	return get_navigation_text(_make_current_presentation_values())


func get_simulation_text_current() -> String:
	return get_simulation_text(_make_current_presentation_values())


func _make_current_presentation_values() -> Dictionary:
	var values := view_values.duplicate()
	values.merge({
		"debug_selected_city_tile": selected_tile,
		"has_debug_selected_city_tile": has_selected_tile(),
		"navigation_status": navigation_status,
		"navigation_start_tile": navigation_start_tile,
		"navigation_destination_tile": navigation_destination_tile,
		"navigation_candidate_count": navigation_candidate_count,
		"navigation_expanded_nodes": navigation_expanded_nodes,
		"navigation_path_cost": navigation_path_cost,
		"navigation_duration_usec": navigation_duration_usec,
	}, true)
	return values


func has_selected_tile() -> bool:
	return (
		presentation_binding != null
		and presentation_binding.is_valid()
		and selected_tile != CityCitizens.INVALID_CITY_TILE_POSITION
		and presentation_binding.world.is_in_bounds(
			selected_tile.x,
			selected_tile.y
		)
	)


func set_selected_tile(tile_position: Vector2i) -> bool:
	if (
		not WorldData.debug_mode_enabled
		or presentation_binding == null
		or not presentation_binding.is_valid()
		or not presentation_binding.world.is_in_bounds(
			tile_position.x,
			tile_position.y
		)
		or selected_tile == tile_position
	):
		return false
	selected_tile = tile_position
	clear_navigation_result()
	request_refresh()
	return true


func clear_selected_tile() -> bool:
	var changed := selected_tile != CityCitizens.INVALID_CITY_TILE_POSITION
	selected_tile = CityCitizens.INVALID_CITY_TILE_POSITION
	clear_navigation_result()
	if changed:
		request_refresh()
	return changed


func clear_navigation_result() -> void:
	navigation_path.clear()
	navigation_status = CityNavigationSystemScript.PATH_STATUS_NOT_REQUESTED
	navigation_start_tile = CityCitizens.INVALID_CITY_TILE_POSITION
	navigation_destination_tile = CityCitizens.INVALID_CITY_TILE_POSITION
	navigation_candidate_count = 0
	navigation_expanded_nodes = 0
	navigation_path_cost = 0
	navigation_duration_usec = 0


func is_interaction_state_clear() -> bool:
	return not has_selected_tile() and navigation_path.is_empty()


func replace_navigation_path_for_characterization(path: Array) -> void:
	navigation_path.clear()
	for raw_tile in path:
		if raw_tile is Vector2i:
			navigation_path.append(raw_tile)


func get_navigation_path_snapshot() -> Array:
	return navigation_path.duplicate()


func get_first_living_citizen() -> Dictionary:
	var city_state := _get_bound_city_state()
	if city_state == null:
		return {}
	for raw_citizen in city_state.citizen_registry_state.citizens:
		if not raw_citizen is Dictionary:
			continue
		var citizen: Dictionary = raw_citizen
		if not bool(citizen.get("alive", false)):
			continue
		if not citizen.get(
			"city_tile_position",
			CityCitizens.INVALID_CITY_TILE_POSITION
		) is Vector2i:
			continue
		return citizen
	return {}


func get_navigation_source_citizen(selected_citizen_id: int) -> Dictionary:
	var city_state := _get_bound_city_state()
	if city_state == null:
		return {}
	if selected_citizen_id >= 0:
		var selected_citizen := (
			CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
				city_state,
				selected_citizen_id
			)
		)
		if (
			not selected_citizen.is_empty()
			and bool(selected_citizen.get("alive", false))
		):
			return selected_citizen
	return get_first_living_citizen()


func request_navigation(
	selected_citizen_id: int,
	hovered_tile: Vector2i
) -> Dictionary:
	clear_navigation_result()
	var city_state := _get_bound_city_state()
	if city_state == null or presentation_binding.world == null:
		navigation_status = CityNavigationSystemScript.PATH_STATUS_INVALID_WORLD
		request_refresh()
		return _get_navigation_result_snapshot()

	var citizen := get_navigation_source_citizen(selected_citizen_id)
	if citizen.is_empty():
		navigation_status = CityNavigationSystemScript.PATH_STATUS_INVALID_START
		request_refresh()
		return _get_navigation_result_snapshot()

	var raw_start_tile = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	if not raw_start_tile is Vector2i:
		navigation_status = CityNavigationSystemScript.PATH_STATUS_INVALID_START
		request_refresh()
		return _get_navigation_result_snapshot()

	var start_tile: Vector2i = raw_start_tile
	var target_tile := selected_tile if has_selected_tile() else hovered_tile
	if target_tile == Vector2i(-1, -1):
		navigation_status = CityNavigationSystemScript.PATH_STATUS_NO_DESTINATIONS
		request_refresh()
		return _get_navigation_result_snapshot()

	var destination_tiles := []
	var target_object := CityObjectSystem.get_city_object_at_tile_for_city_state(
		city_state,
		target_tile
	)
	if (
		not target_object.is_empty()
		and str(target_object.get("type", ""))
		!= CityObjectCatalog.CITY_OBJECT_ROAD
	):
		destination_tiles = (
			CityNavigationSystem.get_city_object_access_tiles_for_city_state(
				city_state,
				presentation_binding.world,
				target_object
			)
		)
	else:
		destination_tiles.append(target_tile)

	var result := (
		CityNavigationSystemScript.find_path_to_any_city_tile_for_city_state(
			city_state,
			{
				"start_tile": start_tile,
				"destination_tiles": destination_tiles,
			}
		)
	)
	navigation_status = str(result.get(
		"status",
		CityNavigationSystemScript.PATH_STATUS_UNREACHABLE
	))
	navigation_start_tile = start_tile
	navigation_destination_tile = result.get(
		"destination_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	navigation_candidate_count = int(result.get("destination_candidate_count", 0))
	navigation_expanded_nodes = int(result.get("expanded_node_count", 0))
	navigation_path_cost = int(result.get("path_cost", 0))
	navigation_duration_usec = int(result.get("duration_usec", 0))
	var raw_path = result.get("path", [])
	if raw_path is Array:
		replace_navigation_path_for_characterization(raw_path)
	request_refresh()
	print(
		"Navigation test: ",
		navigation_status,
		" | Start: ",
		navigation_start_tile,
		" | Destination: ",
		navigation_destination_tile,
		" | Path cost: ",
		format_navigation_path_cost(navigation_path_cost),
		" | Expanded: ",
		navigation_expanded_nodes,
		" | Time: ",
		navigation_duration_usec,
		" usec"
	)
	return _get_navigation_result_snapshot()


func _get_navigation_result_snapshot() -> Dictionary:
	return {
		"status": navigation_status,
		"start_tile": navigation_start_tile,
		"destination_tile": navigation_destination_tile,
		"candidate_count": navigation_candidate_count,
		"expanded_nodes": navigation_expanded_nodes,
		"path_cost": navigation_path_cost,
		"duration_usec": navigation_duration_usec,
		"path": get_navigation_path_snapshot(),
	}


func has_assignable_navigation_path() -> bool:
	return (
		navigation_status == CityNavigationSystemScript.PATH_STATUS_SUCCESS
		and not navigation_path.is_empty()
	)


func execute_add_resource_to_selected_public_storage(
	expected_binding: CityPresentationBinding,
	selected_object_id: int,
	resource: String,
	amount_delta: int
) -> Dictionary:
	if not WorldData.debug_mode_enabled:
		return _make_debug_command_rejection(
			DEBUG_COMMAND_STATUS_DISABLED,
			"Debug storage add blocked: debug mode is disabled."
		)
	var city_state := _get_city_state_for_debug_command(expected_binding)
	if city_state == null:
		return _make_debug_command_rejection(
			DEBUG_COMMAND_STATUS_INVALID_BINDING,
			"Debug storage add blocked: settlement binding is stale or invalid."
		)
	if selected_object_id < 0:
		return _make_debug_command_rejection(
			DEBUG_COMMAND_STATUS_NO_SELECTION,
			"Debug storage add blocked: select a public storage object first."
		)
	if amount_delta <= 0:
		return _make_debug_command_rejection(
			DEBUG_COMMAND_STATUS_INVALID_AMOUNT,
			"Debug storage add blocked: amount must be positive."
		)

	var city_object := CityObjectSystem.get_city_object_by_id_for_city_state(
		city_state,
		selected_object_id
	)
	if city_object.is_empty():
		return _make_debug_command_rejection(
			DEBUG_COMMAND_STATUS_OBJECT_MISSING,
			"Debug storage add blocked: selected object not found."
		)
	if not CityResourceContainerSystem.city_object_counts_as_public_city_storage(
		city_object
	):
		return _make_debug_command_rejection(
			DEBUG_COMMAND_STATUS_NOT_PUBLIC_STORAGE,
			"Debug storage add blocked: selected object is not public storage."
		)
	if not CityResourceContainerSystem.can_city_object_store_resource(
		city_object,
		resource
	):
		return _make_debug_command_rejection(
			DEBUG_COMMAND_STATUS_UNSUPPORTED_RESOURCE,
			(
				"Debug storage add blocked: selected storage cannot store resource: "
				+ resource
			)
		)

	var accepted_amount := (
		CityResourceContainerSystem.add_resource_to_city_object_storage_for_city_state(
			city_state,
			selected_object_id,
			resource,
			amount_delta
		)
	)
	if accepted_amount <= 0:
		return _make_debug_command_rejection(
			DEBUG_COMMAND_STATUS_STORAGE_FULL,
			(
				"Debug storage add blocked: selected storage is full for resource: "
				+ resource
			)
		)

	request_refresh()
	return _make_debug_command_success(
		(
			"Debug added +" + str(accepted_amount) + " " + resource
			+ " to public storage object #" + str(selected_object_id)
		),
		{
			"accepted_amount": accepted_amount,
			"object_id": selected_object_id,
			"resource": resource,
		}
	)


func execute_assign_navigation_path_to_selected_citizen(
	expected_binding: CityPresentationBinding,
	selected_citizen_id: int
) -> Dictionary:
	if not WorldData.debug_mode_enabled:
		return _make_debug_command_rejection(
			DEBUG_COMMAND_STATUS_DISABLED,
			"Movement rejected: debug mode is disabled."
		)
	var city_state := _get_city_state_for_debug_command(expected_binding)
	if city_state == null:
		return _make_debug_command_rejection(
			DEBUG_COMMAND_STATUS_INVALID_BINDING,
			"Movement rejected: settlement binding is stale or invalid."
		)
	if selected_citizen_id < 0:
		return _make_debug_command_rejection(
			DEBUG_COMMAND_STATUS_NO_SELECTION,
			"Movement rejected: select a citizen first."
		)
	if not has_assignable_navigation_path():
		return _make_debug_command_rejection(
			DEBUG_COMMAND_STATUS_PATH_NOT_READY,
			"Movement rejected: press P to create a valid path."
		)

	var requested_path := get_navigation_path_snapshot()
	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
		city_state,
		selected_citizen_id
	)
	if citizen.is_empty():
		return _make_debug_command_rejection(
			DEBUG_COMMAND_STATUS_CITIZEN_MISSING,
			"Movement rejected: selected citizen is missing."
		)
	if not bool(citizen.get("alive", false)):
		return _make_debug_command_rejection(
			DEBUG_COMMAND_STATUS_CITIZEN_NOT_ALIVE,
			"Movement rejected: selected citizen is not alive."
		)

	var current_position = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	if not current_position is Vector2i:
		return _make_debug_command_rejection(
			DEBUG_COMMAND_STATUS_INVALID_POSITION,
			"Movement rejected: citizen position is invalid."
		)
	if (
		navigation_start_tile != current_position
		or requested_path[0] != current_position
	):
		return _make_debug_command_rejection(
			DEBUG_COMMAND_STATUS_STALE_PATH,
			"Movement rejected: path is stale. Press P again."
		)
	if not CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order_for_city_state(
		city_state,
		selected_citizen_id,
		requested_path
	):
		return _make_debug_command_rejection(
			DEBUG_COMMAND_STATUS_AUTHORITATIVE_REJECTION,
			"Movement rejected: authoritative path validation failed."
		)

	var active_mover_ids := (
		CityCitizenMovementRuntimeSystem
		.get_city_active_mover_ids_snapshot_for_city_state(city_state)
	)
	request_refresh()
	return _make_debug_command_success(
		(
			"Movement order assigned to citizen #" + str(selected_citizen_id)
			+ " | Steps: " + str(maxi(requested_path.size() - 1, 0))
			+ " | Active movers: " + str(active_mover_ids)
		),
		{
			"active_mover_ids": active_mover_ids,
			"citizen_id": selected_citizen_id,
			"steps": maxi(requested_path.size() - 1, 0),
		}
	)


func _get_city_state_for_debug_command(
	expected_binding: CityPresentationBinding
) -> CitySettlementSimulationState:
	if (
		expected_binding == null
		or not is_bound_to_settlement_presentation(expected_binding)
	):
		return null
	return _get_bound_city_state()


func _make_debug_command_success(
	message: String,
	details: Dictionary = {}
) -> Dictionary:
	return _make_debug_command_result(
		true,
		DEBUG_COMMAND_STATUS_SUCCESS,
		message,
		details
	)


func _make_debug_command_rejection(
	status: String,
	message: String
) -> Dictionary:
	return _make_debug_command_result(false, status, message)


func _make_debug_command_result(
	success: bool,
	status: String,
	message: String,
	details: Dictionary = {}
) -> Dictionary:
	var result := details.duplicate()
	result["success"] = success
	result["changed"] = success
	result["status"] = status
	result["message"] = message
	if success and presentation_binding != null:
		result["settlement_id"] = presentation_binding.settlement_id
		result["binding_generation"] = presentation_binding.generation
	return result


func draw_background(draw_target: CanvasItem) -> void:
	if not WorldData.debug_mode_enabled or navigation_path.is_empty():
		return
	var path_points := PackedVector2Array()
	var tile_size_vector := Vector2(float(local_tile_size), float(local_tile_size))
	for raw_path_tile in navigation_path:
		if not raw_path_tile is Vector2i:
			continue
		var path_tile: Vector2i = raw_path_tile
		var tile_top_left := Vector2(
			float(path_tile.x * local_tile_size),
			float(path_tile.y * local_tile_size)
		)
		draw_target.draw_rect(
			Rect2(tile_top_left, tile_size_vector),
			DEBUG_NAVIGATION_PATH_FILL_COLOR,
			true
		)
		path_points.append(tile_top_left + tile_size_vector * 0.5)
	if path_points.size() >= 2:
		draw_target.draw_polyline(
			path_points,
			DEBUG_NAVIGATION_PATH_LINE_COLOR,
			maxf(float(local_tile_size) * 0.18, 0.25),
			false
		)


func draw_interaction(draw_target: CanvasItem) -> void:
	if not WorldData.debug_mode_enabled:
		return
	draw_selected_tile_highlight(draw_target)
	draw_city_object_names(draw_target)


func draw_selected_tile_highlight(draw_target: CanvasItem) -> void:
	if not WorldData.debug_mode_enabled or not has_selected_tile():
		return
	var tile_rect := Rect2(
		Vector2(
			float(selected_tile.x * local_tile_size),
			float(selected_tile.y * local_tile_size)
		),
		Vector2.ONE * float(local_tile_size)
	)
	CityRenderLayerScript.draw_screen_constant_inset_rect_border({
		"draw_target": draw_target,
		"rect": tile_rect,
		"border_color": DEBUG_SELECTED_TILE_HIGHLIGHT_COLOR,
		"inset_amount": 0.0,
		"border_width_pixels": 2.0,
		"viewport": draw_target.get_viewport(),
	})


func draw_city_object_names(draw_target: CanvasItem) -> void:
	if not WorldData.debug_mode_enabled:
		return
	var city_state := _get_bound_city_state()
	var font: Font = ThemeDB.fallback_font
	if city_state == null or font == null:
		return
	var pixels_per_world_unit := _get_pixels_per_world_unit(draw_target)
	if pixels_per_world_unit <= 0.0:
		return
	var world_units_per_screen_pixel := 1.0 / pixels_per_world_unit
	for city_object in CityObjectSystem.get_city_objects_for_city_state(city_state):
		if (
			city_object.is_empty()
			or str(city_object.get("type", ""))
			== CityObjectCatalog.CITY_OBJECT_ROAD
		):
			continue
		var rect := _get_city_object_world_rect(city_object)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var object_name := CityObjectCatalog.get_city_object_display_name_for_type(
			str(city_object.get("type", ""))
		)
		if object_name.is_empty():
			continue
		_draw_centered_city_object_name({
			"draw_target": draw_target,
			"label_center": _get_city_object_label_center(city_object, rect),
			"object_screen_size": rect.size * pixels_per_world_unit,
			"object_name": object_name,
			"font": font,
			"world_units_per_screen_pixel": world_units_per_screen_pixel,
		})


func _draw_centered_city_object_name(values: Dictionary) -> void:
	var draw_target: CanvasItem = values.get("draw_target")
	var font: Font = values.get("font")
	var object_name := str(values.get("object_name", ""))
	var font_size := _get_city_object_name_font_size(
		object_name,
		values.get("object_screen_size", Vector2.ZERO),
		font
	)
	if draw_target == null or font == null or font_size < DEBUG_CITY_OBJECT_NAME_MIN_FONT_SIZE:
		return
	var text_size := font.get_string_size(
		object_name,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size
	)
	var text_position := Vector2(
		-text_size.x * 0.5,
		(font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	)
	draw_target.draw_set_transform(
		values.get("label_center", Vector2.ZERO),
		0.0,
		Vector2.ONE * float(values.get("world_units_per_screen_pixel", 1.0))
	)
	draw_target.draw_rect(
		Rect2(
			-text_size * 0.5 - DEBUG_CITY_OBJECT_NAME_PADDING,
			text_size + DEBUG_CITY_OBJECT_NAME_PADDING * 2.0
		),
		DEBUG_CITY_OBJECT_NAME_BACKGROUND_COLOR,
		true
	)
	draw_target.draw_string(
		font,
		text_position + Vector2.ONE,
		object_name,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		DEBUG_CITY_OBJECT_NAME_SHADOW_COLOR
	)
	draw_target.draw_string(
		font,
		text_position,
		object_name,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		DEBUG_CITY_OBJECT_NAME_TEXT_COLOR
	)
	draw_target.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _get_pixels_per_world_unit(draw_target: CanvasItem) -> float:
	var canvas_scale := draw_target.get_canvas_transform().get_scale()
	var x_scale: float = abs(canvas_scale.x)
	var y_scale: float = abs(canvas_scale.y)
	if x_scale <= 0.0 or y_scale <= 0.0:
		return 1.0
	return (x_scale + y_scale) * 0.5


func _get_city_object_name_font_size(
	object_name: String,
	object_screen_size: Vector2,
	font: Font
) -> int:
	var text_size := font.get_string_size(
		object_name,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		DEBUG_CITY_OBJECT_NAME_TARGET_FONT_SIZE
	)
	var max_label_size := Vector2(
		object_screen_size.x * DEBUG_CITY_OBJECT_NAME_MAX_WIDTH_RATIO,
		object_screen_size.y * DEBUG_CITY_OBJECT_NAME_MAX_HEIGHT_RATIO
	)
	var padded_text_size := text_size + DEBUG_CITY_OBJECT_NAME_PADDING * 2.0
	if padded_text_size.x <= 0.0 or padded_text_size.y <= 0.0:
		return DEBUG_CITY_OBJECT_NAME_TARGET_FONT_SIZE
	var fit_scale: float = min(
		1.0,
		max_label_size.x / padded_text_size.x,
		max_label_size.y / padded_text_size.y
	)
	var fitted_font_size := int(floor(
		float(DEBUG_CITY_OBJECT_NAME_TARGET_FONT_SIZE) * fit_scale
	))
	return fitted_font_size if fitted_font_size >= DEBUG_CITY_OBJECT_NAME_MIN_FONT_SIZE else 0


func _get_city_object_label_center(
	city_object: Dictionary,
	fallback_rect: Rect2
) -> Vector2:
	var footprint_tiles := _get_city_object_footprint_tiles(city_object)
	if not footprint_tiles.is_empty():
		var total := Vector2.ZERO
		var count := 0
		for tile_value in footprint_tiles:
			if tile_value is Vector2i:
				total += Vector2(tile_value) * float(local_tile_size)
				total += Vector2.ONE * float(local_tile_size) * 0.5
				count += 1
		if count > 0:
			return total / float(count)
	return fallback_rect.get_center()


func _get_city_object_world_rect(city_object: Dictionary) -> Rect2:
	if city_object.has("top_left") and city_object.has("size"):
		var top_left: Vector2i = city_object["top_left"]
		var size_tiles: Vector2i = city_object["size"]
		return Rect2(
			Vector2(top_left) * float(local_tile_size),
			Vector2(size_tiles) * float(local_tile_size)
		)
	var footprint_tiles := _get_city_object_footprint_tiles(city_object)
	if footprint_tiles.is_empty():
		return Rect2()
	var min_tile := Vector2i(2_147_483_647, 2_147_483_647)
	var max_tile := Vector2i(-2_147_483_648, -2_147_483_648)
	for raw_tile in footprint_tiles:
		if raw_tile is Vector2i:
			min_tile.x = mini(min_tile.x, raw_tile.x)
			min_tile.y = mini(min_tile.y, raw_tile.y)
			max_tile.x = maxi(max_tile.x, raw_tile.x)
			max_tile.y = maxi(max_tile.y, raw_tile.y)
	if min_tile.x > max_tile.x or min_tile.y > max_tile.y:
		return Rect2()
	return Rect2(
		Vector2(min_tile) * float(local_tile_size),
		Vector2(max_tile - min_tile + Vector2i.ONE) * float(local_tile_size)
	)


static func _get_city_object_footprint_tiles(city_object: Dictionary) -> Array:
	if city_object.has("footprint_tiles") and city_object["footprint_tiles"] is Array:
		return city_object["footprint_tiles"]
	if city_object.has("tiles") and city_object["tiles"] is Array:
		return city_object["tiles"]
	return []


func get_navigation_text(values: Dictionary) -> String:
	var navigation_status := str(values.get(
		"navigation_status",
		CityNavigationSystemScript.PATH_STATUS_NOT_REQUESTED
	))
	if navigation_status == CityNavigationSystemScript.PATH_STATUS_NOT_REQUESTED:
		return "Navigation Test: select or hover a tile/building and press P"

	return (
		"Navigation Test: " + navigation_status
		+ " | Start: " + str(values.get(
			"navigation_start_tile",
			CityCitizens.INVALID_CITY_TILE_POSITION
		))
		+ " | End: " + str(values.get(
			"navigation_destination_tile",
			CityCitizens.INVALID_CITY_TILE_POSITION
		))
		+ "\nPath Distance: "
		+ format_navigation_path_cost(int(values.get("navigation_path_cost", 0)))
		+ " | Candidates: " + str(int(values.get("navigation_candidate_count", 0)))
		+ " | Expanded: " + str(int(values.get("navigation_expanded_nodes", 0)))
		+ " | Cost: %.3f ms" % (
			float(int(values.get("navigation_duration_usec", 0))) / 1000.0
		)
	)


static func format_navigation_path_cost(path_cost: int) -> String:
	return "%.3f tiles" % (
		float(maxi(path_cost, 0))
		/ float(CityCitizens.CITY_CITIZEN_CARDINAL_MOVEMENT_COST)
	)


func get_simulation_text(values: Dictionary) -> String:
	if presentation_binding == null or not presentation_binding.is_valid():
		return "City validation: no bound settlement"
	return (
		SimulationClock.get_debug_text()
		+ "\n" + SimulationCoordinator.get_debug_text()
		+ "\n" + CityStateValidator.get_summary_text_for_settlement(
			presentation_binding.settlement_context
		)
		+ "\n" + get_navigation_text(values)
	)


func get_panel_text(values: Dictionary) -> String:
	if presentation_binding == null or not presentation_binding.is_valid():
		return "DEBUG INFO\nCity presentation: not bound"
	var city_state := presentation_binding.city_state
	var city_world := presentation_binding.city_world
	var base_text := (
		"DEBUG INFO\n" + get_simulation_text(values)
		+ "\n\nScene: City"
		+ "\nSettlement: #" + str(presentation_binding.settlement_id)
		+ "\nView: " + str(values.get("city_view_name", "Unknown"))
		+ "\nSeed: " + str(presentation_binding.city_seed)
		+ "\nResources (secured/loose/physical): "
		+ get_resource_conservation_text()
		+ "\n\n"
	)
	var hovered_tile: Vector2i = values.get("hovered_city_tile", Vector2i(-1, -1))
	var selected_debug_tile: Vector2i = values.get(
		"debug_selected_city_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var inspected_tile := hovered_tile
	var inspector_source := "Cursor hover"
	if bool(values.get("has_debug_selected_city_tile", false)):
		inspected_tile = selected_debug_tile
		inspector_source = "Debug selection"
	var cursor_text := (
		str(hovered_tile.x) + ", " + str(hovered_tile.y)
		if hovered_tile != Vector2i(-1, -1)
		else "Outside city"
	)
	if inspected_tile == Vector2i(-1, -1):
		return (
			base_text + "Cursor: " + cursor_text
			+ "\nInspector: " + inspector_source
			+ "\nTile: none\n\n" + get_selection_text(values)
		)

	var tile: Dictionary = city_world.get_tile_for_internal_read(
		inspected_tile.x,
		inspected_tile.y
	)
	var fertility := float(tile.get("fertility", -1.0))
	var fertility_text := "%.1f" % fertility if fertility >= 0.0 else "N/A"
	var city_object := CityObjectSystem.get_city_object_at_tile_for_city_state(
		city_state,
		inspected_tile
	)
	return (
		base_text
		+ "Cursor: " + cursor_text
		+ "\nInspector: " + inspector_source
		+ "\nTile: " + str(inspected_tile.x) + ", " + str(inspected_tile.y)
		+ "\nTerrain: " + str(tile.get("terrain", "unknown"))
		+ "\nBiome: " + str(tile.get("biome", "unknown"))
		+ "\nResource: " + str(tile.get("resource", "none"))
		+ "\n\nElevation: %.3f" % float(tile.get("elevation", 0.0))
		+ "\nTemperature: %.3f" % float(tile.get("temperature", 0.0))
		+ "\nPrecipitation: %.3f" % float(tile.get("precipitation", 0.0))
		+ "\nFertility: " + fertility_text
		+ "\n\nLand: " + DebugPanel.bool_to_yes_no(bool(tile.get("is_land", false)))
		+ "\nWalkable: " + DebugPanel.bool_to_yes_no(
			CityNavigationSystem.is_city_tile_walkable_for_citizen_for_city_state(
				city_state,
				city_world,
				inspected_tile
			)
		)
		+ "\nBuildable 1x1: " + DebugPanel.bool_to_yes_no(
			CityObjectSystem.can_place_city_object_for_city_state(
				city_state,
				city_world,
				inspected_tile,
				Vector2i.ONE
			)
		)
		+ "\nRoad placeable: " + DebugPanel.bool_to_yes_no(
			CityConstructionSystem.can_place_city_road_tile_for_city_state(
				city_state,
				city_world,
				inspected_tile
			)
		)
		+ "\n\n" + get_object_text(city_object)
		+ get_ground_pile_text(inspected_tile)
		+ get_tile_citizen_text({
			"tile_position": inspected_tile,
			"debug_selected_city_tile": selected_debug_tile,
			"has_debug_selected_city_tile": bool(
				values.get("has_debug_selected_city_tile", false)
			),
		})
		+ "\n" + get_selection_text(values)
	)


func get_object_text(city_object: Dictionary) -> String:
	if city_object.is_empty():
		return "Object on tile: none\nWorkplace: No\n"
	var top_left: Vector2i = city_object.get("top_left", Vector2i(-1, -1))
	var size_tiles: Vector2i = city_object.get("size", Vector2i.ZERO)
	var object_id_text := str(city_object.get("id", "N/A"))
	var container_type := CityResourceContainerSystem.get_city_object_container_type(
		city_object
	)
	return (
		"Object on tile: " + _get_city_object_display_name(city_object)
		+ "\nObject type: " + str(city_object.get("type", "unknown"))
		+ "\nObject id: " + object_id_text
		+ "\nWorkplace: " + DebugPanel.bool_to_yes_no(
			CityObjectCatalog.city_object_is_workplace(city_object)
		)
		+ "\nOwner: " + str(city_object.get("owner", "none"))
		+ "\nContainer: " + _get_container_type_display_name(container_type)
		+ "\nObject pos: " + str(top_left.x) + ", " + str(top_left.y)
		+ "\nObject size: " + str(size_tiles.x) + " x " + str(size_tiles.y)
		+ "\n"
	)


func get_ground_pile_text(tile_position: Vector2i) -> String:
	var city_state := presentation_binding.city_state
	var ground_piles: Array[Dictionary] = []
	for raw_ground_pile in city_state.logistics_state.ground_piles:
		if (
			raw_ground_pile is Dictionary
			and raw_ground_pile.get(
				"tile_position",
				CityCitizens.INVALID_CITY_TILE_POSITION
			) == tile_position
		):
			ground_piles.append(raw_ground_pile)
	if ground_piles.is_empty():
		return "Ground piles: none\n"
	ground_piles.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("id", -1)) < int(b.get("id", -1))
	)
	var descriptions: Array[String] = []
	for ground_pile in ground_piles:
		var pile_id := int(ground_pile.get("id", -1))
		var resource := str(ground_pile.get(
			"resource_type",
			WorldData.RESOURCE_NONE
		))
		var source := CityLogisticsSystem.make_city_ground_pile_haul_endpoint(pile_id)
		var reserved_amount := CityLogisticsSystem.get_city_haul_endpoint_source_reserved_amount_for_city_state(
			city_state,
			source,
			resource
		)
		descriptions.append(
			"#" + str(pile_id) + " " + resource + " "
			+ str(maxi(int(ground_pile.get("amount", 0)), 0))
			+ " (reserved " + str(reserved_amount) + ")"
		)
	return "Ground piles: " + ", ".join(descriptions) + "\n"


func get_resource_conservation_text() -> String:
	var city_state := presentation_binding.city_state
	var owned := CityResourceAccountingSystem.get_total_owned_city_resource_amounts_for_city_state(
		city_state
	)
	var descriptions: Array[String] = []
	for resource in CityResourceCatalog.get_city_resource_types():
		var loose_amount := 0
		for raw_ground_pile in city_state.logistics_state.ground_piles:
			if (
				raw_ground_pile is Dictionary
				and str(raw_ground_pile.get(
					"resource_type",
					WorldData.RESOURCE_NONE
				)) == resource
			):
				loose_amount += maxi(int(raw_ground_pile.get("amount", 0)), 0)
		descriptions.append(
			resource + " " + str(maxi(int(owned.get(resource, 0)), 0))
			+ "/" + str(loose_amount)
			+ "/" + str(
				CityResourceAccountingSystem.get_total_physical_city_resource_amount_for_city_state(
					city_state,
					resource
				)
			)
		)
	return ", ".join(descriptions)


func get_tile_citizen_text(values: Dictionary) -> String:
	var city_state := presentation_binding.city_state
	var tile_position: Vector2i = values.get(
		"tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var standing_ids := CityCitizenSpatialSystem.get_city_citizen_ids_at_tile_for_city_state(
		city_state,
		tile_position
	)
	var claiming_ids: Array[int] = []
	var claim_text := "select a debug tile"
	if (
		bool(values.get("has_debug_selected_city_tile", false))
		and tile_position == values.get(
			"debug_selected_city_tile",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)
	):
		for citizen_id in CityCitizenTaskRuntimeSystem.get_city_active_task_ids_snapshot_for_city_state(
			city_state
		):
			var current_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task_for_city_state(
				city_state,
				citizen_id
			)
			if current_task.get(
				"target_tile",
				CityCitizens.INVALID_CITY_TILE_POSITION
			) == tile_position:
				claiming_ids.append(citizen_id)
		claim_text = str(claiming_ids)
	return (
		"Citizen IDs standing here: " + str(standing_ids)
		+ "\nCitizen task claims: " + claim_text + "\n"
	)


func get_selection_text(values: Dictionary) -> String:
	var city_state := presentation_binding.city_state
	var selected_entity_kind := str(values.get("selected_city_entity_kind", "none"))
	var selected_entity_id := int(values.get("selected_city_entity_id", -1))
	if selected_entity_kind == "none" or selected_entity_id < 0:
		return "Selected entity: none\n"

	if selected_entity_kind == CITY_SELECTION_KIND_CITIZEN:
		var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
			city_state,
			selected_entity_id
		)
		if citizen.is_empty():
			return "Selected citizen: missing\n"
		var current_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task_for_city_state(
			city_state,
			selected_entity_id
		)
		var task_target = current_task.get(
			"target_tile",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)
		var destination = citizen.get(
			"movement_destination_tile",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)
		var task_target_text := (
			str(task_target)
			if task_target is Vector2i and task_target != CityCitizens.INVALID_CITY_TILE_POSITION
			else "none"
		)
		var destination_text := (
			str(destination)
			if destination is Vector2i and destination != CityCitizens.INVALID_CITY_TILE_POSITION
			else "none"
		)
		var failure_text := str(citizen.get(
			"movement_failure_reason",
			CityCitizens.CITY_CITIZEN_MOVEMENT_FAILURE_NONE
		))
		if (
			str(current_task.get("phase", ""))
			== CityCitizens.CITY_CITIZEN_TASK_PHASE_BLOCKED
			and failure_text == CityCitizens.CITY_CITIZEN_MOVEMENT_FAILURE_NONE
		):
			failure_text = "task_blocked (specific cause is not recorded yet)"
		return (
			"Selected citizen: " + str(citizen.get("name", "Unknown"))
			+ "\nSelected id: " + str(selected_entity_id)
			+ "\nTask: " + citizen_debug_panel.get_task_text(citizen)
			+ "\nTask target: " + task_target_text
			+ " | Destination: " + destination_text
			+ "\nWorkplace: " + citizen_debug_panel.get_job_text(citizen)
			+ "\nSchedule: Work "
			+ format_minute_of_day(CitizenDecisionSystem.WORK_SHIFT_START_MINUTE_OF_DAY)
			+ "-" + format_minute_of_day(CitizenDecisionSystem.WORK_SHIFT_END_MINUTE_OF_DAY)
			+ " | Active: " + DebugPanel.bool_to_yes_no(
				CitizenDecisionSystem.is_work_shift_active()
			)
			+ "\nFailure: " + failure_text + "\n"
		)

	var selected_object := CityObjectSystem.get_city_object_by_id_for_city_state(
		city_state,
		int(values.get("selected_city_object_id", -1))
	)
	if selected_object.is_empty():
		return "Selected object: missing\n"
	return (
		"Selected object: " + _get_city_object_display_name(selected_object)
		+ "\nSelected id: " + str(selected_entity_id) + "\n"
	)


static func format_minute_of_day(minute_of_day: int) -> String:
	var safe_minute := clampi(
		minute_of_day,
		0,
		SimulationClock.MINUTES_PER_DAY - 1
	)
	return (
		str(int(safe_minute / SimulationClock.MINUTES_PER_HOUR)).pad_zeros(2)
		+ ":"
		+ str(safe_minute % SimulationClock.MINUTES_PER_HOUR).pad_zeros(2)
	)


static func _get_city_object_display_name(city_object: Dictionary) -> String:
	if city_object.is_empty():
		return "Unknown"
	return CityObjectCatalog.get_city_object_display_name_for_type(
		str(city_object.get("type", ""))
	)


static func _get_container_type_display_name(container_type: String) -> String:
	match container_type:
		CityObjectCatalog.CONTAINER_TYPE_PUBLIC_CITY_STORAGE:
			return "Public city storage"
		CityObjectCatalog.CONTAINER_TYPE_PRIVATE_HOME_STORAGE:
			return "Private home storage"
		CityObjectCatalog.CONTAINER_TYPE_WORKPLACE_STORAGE:
			return "Workplace output buffer"
		CityObjectCatalog.CONTAINER_TYPE_PERSONAL_INVENTORY:
			return "Personal inventory"
		CityObjectCatalog.CONTAINER_TYPE_GROUND_PILE:
			return "Ground pile"
	return "None"
