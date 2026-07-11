extends Node2D
class_name CityRenderer

const CityStateValidator = preload(
	"res://scripts/city/simulation/CityStateValidator.gd"
)

@export_file("*.tscn") var world_scene_path: String = ""
@export var local_tiles_per_world_tile: int = 64
@export var city_tile_size: int = 2

var city_world: WorldData
var city_seed: int = 0
var detail_noise := FastNoiseLite.new()
var fertility_noise := FastNoiseLite.new()
var resource_noise := FastNoiseLite.new()
var biome_warp_noise := FastNoiseLite.new()
var coast_noise := FastNoiseLite.new()
var biome_edge_noise := FastNoiseLite.new()
var camera: Camera2D
var ui_layer: CanvasLayer
var ui_root: Control

var back_button: Button
var resource_bar: Control
var resource_boxes: Array[Panel] = []
var city_view_mode: int = MapVisuals.ViewMode.BIOME
var city_maps_button: Button
var city_map_mode_buttons: Array[Button] = []
var city_map_menu_open: bool = false
var resource_icons: Array[ColorRect] = []
var resource_amount_labels: Array[Label] = []
var build_option_button: Button
var build_option_icon: Panel
var city_terrain_texture: ImageTexture
var city_texture_cache := MapTextureCache.new()
var debug_panel_ui: DebugPanel
var debug_panel_position: Vector2 = Vector2.ZERO
var debug_panel_padding: Vector2 = Vector2(12.0, 10.0)
var debug_panel_min_size: Vector2 = Vector2(430.0, 170.0)
var citizen_debug_button: Button
var citizen_debug_panel: Panel
var citizen_debug_title_label: Label
var citizen_debug_body_label: Label
var is_citizen_debug_panel_open: bool = false

const CITIZEN_DEBUG_BUTTON_POSITION: Vector2 = Vector2(270.0, 28.0)
const CITIZEN_DEBUG_BUTTON_SIZE: Vector2 = Vector2(145.0, 26.0)
const CITIZEN_DEBUG_PANEL_MARGIN: float = 10.0
const CITIZEN_DEBUG_PANEL_SIZE: Vector2 = Vector2(540.0, 300.0)
const DEFAULT_CITY_OBJECT_FRAME_COLOR: Color = Color(0.32, 0.30, 0.24, 0.95)
const DEFAULT_CITY_OBJECT_FILL_COLOR: Color = Color(0.86, 0.84, 0.76, 0.55)
const DEFAULT_CITY_OBJECT_FRAME_THICKNESS: float = 0.35
var is_road_placement_active: bool = false
var is_road_dragging: bool = false
var road_preview_tiles: Array = []
var road_preview_lookup: Dictionary = {}
var bottom_button_one: Button
var bottom_button_two: Button
var bottom_button_three: Button
var bottom_button_four: Button
var bottom_button_five: Button
var road_drag_start_tile: Vector2i = Vector2i(-1, -1)
var road_drag_current_tile: Vector2i = Vector2i(-1, -1)
var city_object_option_buttons: Dictionary = {}
var city_object_option_icons: Dictionary = {}
var road_cursor_icon: Panel
var hovered_city_tile: Vector2i = Vector2i(-1, -1)
var previous_hovered_city_tile: Vector2i = Vector2i(-1, -1)
var hover_tile_outline: Panel
var selected_city_object_id: int = -1

var observed_city_object_version: int = -1
var observed_city_container_version: int = -1
var observed_city_public_storage_version: int = -1
var observed_city_citizen_version: int = -1
var observed_city_assignment_version: int = -1
var observed_city_workplace_version: int = -1
var observed_city_tile_data_version: int = -1
var workplace_zone_preview_render_cache: Dictionary = {}
var selected_workplace_zone_render_cache: Dictionary = {}
var active_city_object_placement: Dictionary = {}
var object_info_panel: Panel
var object_info_title_label: Label
var object_info_body_label: Label
var object_info_storage_title_label: Label
var object_info_storage_icons: Array[ColorRect] = []
var object_info_storage_amount_labels: Array[Label] = []
var object_selection_box_panel: Panel
var is_object_selection_dragging: bool = false
var object_selection_drag_start_screen: Vector2 = Vector2.ZERO
var object_selection_drag_current_screen: Vector2 = Vector2.ZERO
var object_selection_drag_start_world: Vector2 = Vector2.ZERO
var object_selection_drag_current_world: Vector2 = Vector2.ZERO
const DEBUG_CITY_OBJECT_NAME_TARGET_FONT_SIZE: int = 11
const DEBUG_CITY_OBJECT_NAME_MIN_FONT_SIZE: int = 6
const DEBUG_CITY_OBJECT_NAME_TEXT_COLOR: Color = Color(0.82, 0.94, 1.0, 1.0)
const DEBUG_CITY_OBJECT_NAME_SHADOW_COLOR: Color = Color(0.0, 0.0, 0.0, 0.85)
const DEBUG_CITY_OBJECT_NAME_BACKGROUND_COLOR: Color = Color(0.0, 0.0, 0.0, 0.55)
const DEBUG_CITY_OBJECT_NAME_PADDING: Vector2 = Vector2(4.0, 2.0)
const DEBUG_CITY_OBJECT_NAME_MAX_WIDTH_RATIO: float = 0.82
const DEBUG_CITY_OBJECT_NAME_MAX_HEIGHT_RATIO: float = 0.45
const OBJECT_SELECTION_DRAG_THRESHOLD_PIXELS: float = 4.0
const SELECTED_OBJECT_BORDER_TILE_FRACTION: float = 0.02
const CURSOR_LOOK_FILL_COLOR: Color = Color(1.0, 1.0, 1.0, 0.08)
const CURSOR_LOOK_BORDER_COLOR: Color = Color(1.0, 1.0, 1.0, 0.58)
const CURSOR_LOOK_GRID_COLOR: Color = Color(1.0, 1.0, 1.0, 0.22)
const SELECTED_OBJECT_HIGHLIGHT_COLOR: Color = Color(0.0, 0.85, 1.0, 1.0)
const WORKPLACE_ZONE_TEXTURE_TARGET_PIXELS_PER_TILE: int = 12
const WORKPLACE_ZONE_TEXTURE_MAXIMUM_DIMENSION: int = 1024
const WORKPLACE_ZONE_TEXTURE_BORDER_PIXELS: int = 1
const WORKPLACE_ZONE_PREVIEW_MAGENTA_FILL_COLOR: Color = (
	Color(1.0, 0.0, 1.0, 0.22)
)
const WORKPLACE_ZONE_PREVIEW_MAGENTA_BORDER_COLOR: Color = (
	Color(1.0, 0.0, 1.0, 0.55)
)
const WORKPLACE_ZONE_PREVIEW_RED_FILL_COLOR: Color = (
	Color(1.0, 0.0, 0.0, 0.20)
)
const WORKPLACE_ZONE_PREVIEW_RED_BORDER_COLOR: Color = (
	Color(1.0, 0.0, 0.0, 0.55)
)
const WORKPLACE_ZONE_SELECTED_RESOURCE_COLOR: Color = (
	Color(1.0, 0.0, 1.0, 0.26)
)
const WORKPLACE_ZONE_SELECTED_BORDER_COLOR: Color = (
	Color(1.0, 0.0, 1.0, 0.58)
)

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	RenderingServer.set_default_clear_color(Color.BLACK)

	setup_city_texture_cache()
	generate_city_world()
	clear_invalid_old_city_foundation_state()
	ensure_city_foundation_object_exists()
	rebuild_city_terrain_texture()
	create_city_camera()
	create_city_ui()
	create_debug_panel()
	connect_simulation_clock_signals()
	SimulationClock.resume_simulation()
	update_debug_panel_text()
	queue_redraw()


func _process(_delta: float) -> void:
	var current_hovered_tile := get_city_tile_under_mouse()

	if current_hovered_tile != hovered_city_tile:
		hovered_city_tile = current_hovered_tile
		update_debug_panel_text()

		var hover_visual_can_change := (
			selected_city_object_id < 0
			or has_active_city_object_placement()
			or is_road_placement_active
			or is_road_dragging
			or is_object_selection_dragging
		)

		if hover_visual_can_change:
			queue_redraw()

	if is_road_placement_active:
		update_road_cursor_icon_position()

	if is_road_dragging:
		update_road_drag_selection()

	var city_objects_changed := false
	var city_containers_changed := false
	var public_storage_changed := false
	var city_citizens_changed := false
	var city_assignments_changed := false
	var city_workplaces_changed := false
	var city_tile_data_changed := false

	if city_world != null:
		if (
			observed_city_tile_data_version
			!= city_world.tile_data_version
		):
			observed_city_tile_data_version = (
				city_world.tile_data_version
			)
			city_tile_data_changed = true
			workplace_zone_preview_render_cache.clear()
			selected_workplace_zone_render_cache.clear()

	if observed_city_object_version != WorldData.city_object_version:
		observed_city_object_version = WorldData.city_object_version
		city_objects_changed = true

	if observed_city_container_version != WorldData.city_container_version:
		observed_city_container_version = WorldData.city_container_version
		city_containers_changed = true

	if (
		observed_city_public_storage_version
		!= WorldData.city_public_storage_version
	):
		observed_city_public_storage_version = (
			WorldData.city_public_storage_version
		)
		public_storage_changed = true

	if observed_city_citizen_version != WorldData.city_citizen_version:
		observed_city_citizen_version = WorldData.city_citizen_version
		city_citizens_changed = true

	if (
		observed_city_assignment_version
		!= WorldData.city_assignment_version
	):
		observed_city_assignment_version = (
			WorldData.city_assignment_version
		)
		city_assignments_changed = true

	if (
		observed_city_workplace_version
		!= WorldData.city_workplace_version
	):
		observed_city_workplace_version = (
			WorldData.city_workplace_version
		)
		city_workplaces_changed = true
	if city_containers_changed or public_storage_changed:
		update_resource_bar_values()

	if (
		city_objects_changed
		or city_containers_changed
		or city_citizens_changed
		or city_assignments_changed
		or city_workplaces_changed
		or city_tile_data_changed
	):
		update_selected_object_panel()

	if city_objects_changed or city_tile_data_changed:
		queue_redraw()

	if (
		city_objects_changed
		or city_citizens_changed
		or city_assignments_changed
		or city_tile_data_changed
	):
		update_debug_panel_text()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event

		var is_debug_toggle_key: bool = (
			key_event.keycode == KEY_QUOTELEFT
			or key_event.physical_keycode == KEY_QUOTELEFT
			or key_event.unicode == 96
			or key_event.unicode == 126
		)

		if is_debug_toggle_key:
			toggle_debug_mode()
			get_viewport().set_input_as_handled()
			return

		if WorldData.debug_mode_enabled:
			var debug_resource := get_debug_stockpile_resource_for_key(key_event)

			if debug_resource != "":
				add_debug_resource_to_selected_stockpile(debug_resource, 10)
				get_viewport().set_input_as_handled()
				return

		var requested_view_mode: int = MapVisuals.get_view_mode_for_keycode(key_event.keycode)

		if requested_view_mode != MapVisuals.INVALID_VIEW_MODE:
			set_city_view_mode(requested_view_mode)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			if is_road_placement_active:
				cancel_road_placement()
				close_build_menu()
				get_viewport().set_input_as_handled()
				return

			if has_active_city_object_placement():
				cancel_active_city_object_placement()
				close_all_city_object_menus()
				get_viewport().set_input_as_handled()
				return

			if city_map_menu_open:
				close_city_map_menu()
				get_viewport().set_input_as_handled()
				return

			if build_option_button != null and build_option_button.visible:
				close_build_menu()
				get_viewport().set_input_as_handled()
				return

			if has_open_city_object_menu():
				close_all_city_object_menus()
				get_viewport().set_input_as_handled()
				return

			if selected_city_object_id != -1:
				clear_selected_city_object()
				get_viewport().set_input_as_handled()
				return

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if has_active_city_object_placement() and event.pressed:
				confirm_active_city_object_placement()
				get_viewport().set_input_as_handled()
				return

			if is_road_placement_active:
				if event.pressed:
					handle_road_left_mouse_pressed()
				else:
					handle_road_left_mouse_released()

				get_viewport().set_input_as_handled()
				return

			if event.pressed:
				start_object_selection_drag(event.position)
			else:
				finish_object_selection_drag(event.position)

			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion:
		if is_object_selection_dragging:
			update_object_selection_drag(event.position)
			get_viewport().set_input_as_handled()
			return

func connect_simulation_clock_signals() -> void:
	var time_changed_callable := Callable(
		self,
		"on_simulation_time_changed"
	)

	if not SimulationClock.time_changed.is_connected(time_changed_callable):
		SimulationClock.time_changed.connect(time_changed_callable)


func on_simulation_time_changed(
	_day: int,
	_hour: int,
	_minute: int
) -> void:
	if debug_panel_ui == null:
		return

	debug_panel_ui.refresh()

func get_debug_stockpile_resource_for_key(key_event: InputEventKey) -> String:
	if key_event.keycode == KEY_H or key_event.physical_keycode == KEY_H:
		return WorldData.RESOURCE_FISH

	if key_event.keycode == KEY_J or key_event.physical_keycode == KEY_J:
		return WorldData.RESOURCE_COAL

	if key_event.keycode == KEY_K or key_event.physical_keycode == KEY_K:
		return WorldData.RESOURCE_IRON

	if key_event.keycode == KEY_L or key_event.physical_keycode == KEY_L:
		return WorldData.RESOURCE_GOLD

	return ""


func add_debug_resource_to_selected_stockpile(resource: String, amount_delta: int) -> void:
	if not WorldData.debug_mode_enabled:
		return

	if selected_city_object_id < 0:
		print("Debug storage add blocked: select a public storage object first.")
		return

	var city_object := get_city_object_by_id(selected_city_object_id)

	if city_object.is_empty():
		print("Debug storage add blocked: selected object not found.")
		return

	if not WorldData.city_object_counts_as_public_city_storage(city_object):
		print("Debug storage add blocked: selected object is not public city storage.")
		return

	if not WorldData.can_city_object_store_resource(city_object, resource):
		print("Debug storage add blocked: selected storage cannot store resource: ", resource)
		return

	var accepted_amount := WorldData.add_resource_to_city_object_storage(
		selected_city_object_id,
		resource,
		amount_delta
	)

	if accepted_amount <= 0:
		print("Debug storage add blocked: selected storage is full for resource: ", resource)
		return

	update_resource_bar_values()
	update_selected_object_panel()
	update_debug_panel_text()

	print(
		"Debug added +",
		accepted_amount,
		" ",
		resource,
		" to public storage object #",
		selected_city_object_id
	)

func generate_city_world() -> void:
	if WorldData.has_active_city_save():
		city_world = WorldData.official_city_world
		city_seed = WorldData.official_city_seed
		print("Loaded existing city world.")
		return

	if not WorldData.has_city_start_region():
		push_error("No selected world region was stored before entering the city screen.")
		return

	var region_size: int = WorldData.city_start_region_size
	var city_width: int = region_size * local_tiles_per_world_tile
	var city_height: int = region_size * local_tiles_per_world_tile

	city_seed = get_city_seed()

	setup_city_noise()

	city_world = WorldData.new()
	city_world.setup(city_width, city_height, city_seed)

	for y in range(city_world.height):
		var row: Array = city_world.tiles[y]

		for x in range(city_world.width):
			var tile: Dictionary = row[x]
			var profile: Dictionary = get_city_source_profile(x, y, region_size)

			copy_city_profile_into_tile(tile, profile, x, y)

			row[x] = tile

	city_world.mark_tile_data_changed()
	WorldData.store_city_world_save(city_world, city_seed)
	print("Stored official city world.")

func get_city_source_profile(city_x: int, city_y: int, region_size: int) -> Dictionary:
	var source_fx: float = ((float(city_x) + 0.5) / float(city_world.width)) * float(region_size) - 0.5
	var source_fy: float = ((float(city_y) + 0.5) / float(city_world.height)) * float(region_size) - 0.5

	var warp_strength := 0.62

	source_fx += biome_warp_noise.get_noise_2d(city_x, city_y) * warp_strength
	source_fy += biome_warp_noise.get_noise_2d(city_x + 9173, city_y - 4289) * warp_strength

	source_fx = clamp(source_fx, 0.0, float(region_size - 1))
	source_fy = clamp(source_fy, 0.0, float(region_size - 1))

	var x0: int = int(floor(source_fx))
	var y0: int = int(floor(source_fy))
	var x1: int = min(x0 + 1, region_size - 1)
	var y1: int = min(y0 + 1, region_size - 1)

	var tx: float = source_fx - float(x0)
	var ty: float = source_fy - float(y0)

	var w00: float = (1.0 - tx) * (1.0 - ty)
	var w10: float = tx * (1.0 - ty)
	var w01: float = (1.0 - tx) * ty
	var w11: float = tx * ty

	var profile := {
		"elevation": 0.0,
		"temperature": 0.0,
		"precipitation": 0.0,
		"fertility": 0.0,
		"fertility_weight": 0.0,
		"water_weight": 0.0,
		"ocean_weight": 0.0,
		"river_weight": 0.0,
		"mountain_weight": 0.0,
		"biome_weights": {},
		"resource_weights": {}
	}

	accumulate_city_source_sample(profile, WorldData.city_start_tiles[y0][x0], w00)
	accumulate_city_source_sample(profile, WorldData.city_start_tiles[y0][x1], w10)
	accumulate_city_source_sample(profile, WorldData.city_start_tiles[y1][x0], w01)
	accumulate_city_source_sample(profile, WorldData.city_start_tiles[y1][x1], w11)

	if float(profile["fertility_weight"]) > 0.0:
		profile["fertility"] = float(profile["fertility"]) / float(profile["fertility_weight"])
	else:
		profile["fertility"] = -1.0

	return profile


func accumulate_city_source_sample(profile: Dictionary, source_tile: Dictionary, weight: float) -> void:
	if weight <= 0.0:
		return

	var source_biome: String = str(source_tile["biome"])
	var source_resource: String = str(source_tile["resource"])
	var source_terrain: String = str(source_tile["terrain"])

	profile["elevation"] = float(profile["elevation"]) + float(source_tile["elevation"]) * weight
	profile["temperature"] = float(profile["temperature"]) + float(source_tile["temperature"]) * weight
	profile["precipitation"] = float(profile["precipitation"]) + float(source_tile["precipitation"]) * weight

	var source_fertility: float = float(source_tile["fertility"])

	if source_fertility >= 0.0:
		profile["fertility"] = float(profile["fertility"]) + source_fertility * weight
		profile["fertility_weight"] = float(profile["fertility_weight"]) + weight

	add_weight_to_dictionary(profile["biome_weights"], source_biome, weight)
	add_weight_to_dictionary(profile["resource_weights"], source_resource, weight)

	if source_terrain == WorldData.TERRAIN_WATER:
		profile["water_weight"] = float(profile["water_weight"]) + weight

	if source_biome == WorldData.BIOME_OCEAN:
		profile["ocean_weight"] = float(profile["ocean_weight"]) + weight

	if source_biome == WorldData.BIOME_RIVER:
		profile["river_weight"] = float(profile["river_weight"]) + weight

	if source_biome == WorldData.BIOME_MOUNTAIN:
		profile["mountain_weight"] = float(profile["mountain_weight"]) + weight


func add_weight_to_dictionary(weights: Dictionary, key: String, amount: float) -> void:
	if not weights.has(key):
		weights[key] = 0.0

	weights[key] = float(weights[key]) + amount

func get_city_seed() -> int:
	var center: Vector2i = WorldData.city_start_region_center

	var seed_value: int = int(WorldData.city_start_world_seed)
	seed_value += int(center.x * 73856093)
	seed_value += int(center.y * 19349663)
	seed_value += int(WorldData.city_start_region_size * 83492791)

	return seed_value

func copy_city_profile_into_tile(tile: Dictionary, profile: Dictionary, city_x: int, city_y: int) -> void:
	var local_detail: float = detail_noise.get_noise_2d(city_x, city_y) * 0.030
	var local_fertility_detail: float = fertility_noise.get_noise_2d(city_x, city_y) * 7.0

	var water_weight: float = float(profile["water_weight"])
	var ocean_weight: float = float(profile["ocean_weight"])
	var river_weight: float = float(profile["river_weight"])

	var coastline_threshold: float = 0.50 + coast_noise.get_noise_2d(city_x, city_y) * 0.18
	var river_threshold: float = 0.40 + coast_noise.get_noise_2d(city_x + 5000, city_y - 5000) * 0.10

	var becomes_river: bool = river_weight > river_threshold
	var becomes_water: bool = water_weight > coastline_threshold or becomes_river

	tile["elevation"] = float(profile["elevation"]) + local_detail
	tile["temperature"] = float(profile["temperature"])
	tile["precipitation"] = float(profile["precipitation"])

	if becomes_water:
		tile["terrain"] = WorldData.TERRAIN_WATER
		tile["is_land"] = false
		tile["fertility"] = -1.0

		if becomes_river and river_weight >= ocean_weight:
			tile["biome"] = WorldData.BIOME_RIVER
		else:
			tile["biome"] = WorldData.BIOME_OCEAN

	else:
		var land_biome: String = get_dominant_land_biome(profile["biome_weights"], city_x, city_y)

		tile["biome"] = land_biome
		tile["is_land"] = true

		if land_biome == WorldData.BIOME_MOUNTAIN:
			tile["terrain"] = WorldData.TERRAIN_MOUNTAIN
		else:
			tile["terrain"] = WorldData.TERRAIN_LAND

		var profile_fertility: float = float(profile["fertility"])

		if profile_fertility >= 0.0:
			tile["fertility"] = clamp(profile_fertility + local_fertility_detail, 0.0, 100.0)
		else:
			tile["fertility"] = 0.0

	tile["resource"] = get_city_resource_from_profile(profile, city_x, city_y, str(tile["biome"]), str(tile["terrain"]))


func get_dominant_land_biome(biome_weights: Dictionary, city_x: int, city_y: int) -> String:
	var best_biome := WorldData.BIOME_PLAIN
	var best_score := -99999.0

	for biome_key in biome_weights.keys():
		var biome := str(biome_key)

		if biome == WorldData.BIOME_OCEAN:
			continue

		if biome == WorldData.BIOME_RIVER:
			continue

		var score: float = float(biome_weights[biome_key])
		score += get_biome_boundary_bias(biome, city_x, city_y)

		if score > best_score:
			best_score = score
			best_biome = biome

	return best_biome


func get_biome_boundary_bias(biome: String, city_x: int, city_y: int) -> float:
	var offset: int = get_biome_noise_offset(biome)
	var noise_value: float = biome_edge_noise.get_noise_2d(city_x + offset, city_y - offset)

	return noise_value * 0.075

func get_biome_noise_offset(biome: String) -> int:
	match biome:
		WorldData.BIOME_MOUNTAIN:
			return 1000

		WorldData.BIOME_HILLS:
			return 2000

		WorldData.BIOME_DESERT:
			return 3000

		WorldData.BIOME_PLAIN:
			return 4000

		WorldData.BIOME_FOREST:
			return 5000

		WorldData.BIOME_TUNDRA:
			return 6000

		WorldData.BIOME_TAIGA:
			return 7000

		WorldData.BIOME_JUNGLE:
			return 8000

	return 9000

func setup_city_noise() -> void:
	detail_noise.seed = city_seed
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail_noise.frequency = 0.055
	detail_noise.fractal_octaves = 4
	detail_noise.fractal_gain = 0.50
	detail_noise.fractal_lacunarity = 2.0

	fertility_noise.seed = city_seed + 4111
	fertility_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	fertility_noise.frequency = 0.075
	fertility_noise.fractal_octaves = 3
	fertility_noise.fractal_gain = 0.55
	fertility_noise.fractal_lacunarity = 2.0

	resource_noise.seed = city_seed + 9221
	resource_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	resource_noise.frequency = 0.105
	resource_noise.fractal_octaves = 3
	resource_noise.fractal_gain = 0.50
	resource_noise.fractal_lacunarity = 2.0

	biome_warp_noise.seed = city_seed + 1771
	biome_warp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	biome_warp_noise.frequency = 0.026
	biome_warp_noise.fractal_octaves = 3
	biome_warp_noise.fractal_gain = 0.52
	biome_warp_noise.fractal_lacunarity = 2.0

	coast_noise.seed = city_seed + 2887
	coast_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	coast_noise.frequency = 0.060
	coast_noise.fractal_octaves = 4
	coast_noise.fractal_gain = 0.52
	coast_noise.fractal_lacunarity = 2.0

	biome_edge_noise.seed = city_seed + 6397
	biome_edge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	biome_edge_noise.frequency = 0.050
	biome_edge_noise.fractal_octaves = 3
	biome_edge_noise.fractal_gain = 0.50
	biome_edge_noise.fractal_lacunarity = 2.0

func get_city_resource_from_profile(
	profile: Dictionary,
	city_x: int,
	city_y: int,
	biome: String,
	terrain: String
) -> String:
	var resource_weights: Dictionary = profile["resource_weights"]

	var best_resource := WorldData.RESOURCE_NONE
	var best_weight := 0.0

	for resource_key in resource_weights.keys():
		var resource := str(resource_key)

		if resource == WorldData.RESOURCE_NONE:
			continue

		var weight: float = float(resource_weights[resource_key])

		if weight > best_weight:
			best_weight = weight
			best_resource = resource

	if best_resource == WorldData.RESOURCE_NONE:
		return WorldData.RESOURCE_NONE

	if best_resource == WorldData.RESOURCE_FISH and terrain != WorldData.TERRAIN_WATER:
		return WorldData.RESOURCE_NONE

	if best_resource == WorldData.RESOURCE_GOLD:
		if biome != WorldData.BIOME_HILLS and biome != WorldData.BIOME_MOUNTAIN:
			return WorldData.RESOURCE_NONE

	if best_resource != WorldData.RESOURCE_FISH and terrain == WorldData.TERRAIN_WATER:
		return WorldData.RESOURCE_NONE

	var noise_value: float = (resource_noise.get_noise_2d(city_x, city_y) + 1.0) * 0.5
	var spawn_chance: float = clamp(best_weight * 0.55, 0.025, 0.42)

	if noise_value > 1.0 - spawn_chance:
		return best_resource

	return WorldData.RESOURCE_NONE

func create_city_camera() -> void:
	if city_world == null:
		return

	camera = StrategyCamera2D.new()
	camera.max_zoom = 80.0
	camera.zoom_speed = 0.10

	add_child(camera)

	camera.configure_for_map(
		city_world.width,
		city_world.height,
		city_tile_size,
		not WorldData.has_city_camera_state
	)

	if WorldData.has_city_camera_state:
		camera.position = WorldData.city_camera_position
		camera.zoom = WorldData.city_camera_zoom
		camera.clamp_camera_to_map_bounds()

	camera.make_current()

func store_current_city_camera_state() -> void:
	if camera == null:
		return

	WorldData.city_camera_position = camera.position
	WorldData.city_camera_zoom = camera.zoom
	WorldData.has_city_camera_state = true

func create_city_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 100
	add_child(ui_layer)

	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(ui_root)

	create_bottom_city_buttons()
	create_city_object_option_button(WorldData.CITY_OBJECT_CITY_CENTER)
	create_build_option_button()
	create_city_object_option_button(WorldData.CITY_OBJECT_HOUSE)
	create_city_object_option_button(WorldData.CITY_OBJECT_STOCKPILE)
	create_city_object_option_button(WorldData.CITY_OBJECT_FISHING_GROUNDS)
	create_resource_bar()
	create_city_maps_menu()
	create_object_info_panel()
	create_object_selection_box_visual()
	create_back_button()
	create_road_cursor_icon()

	get_viewport().size_changed.connect(update_city_ui_layout)
	update_city_ui_layout()
	update_resource_bar_values()
	update_city_object_button_states()
	update_build_button_state()

func create_road_cursor_icon() -> void:
	road_cursor_icon = Panel.new()
	road_cursor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	road_cursor_icon.visible = false

	var road_style := create_flat_ui_style(
		Color(0.34, 0.34, 0.34, 0.92),
		Color(0.16, 0.16, 0.16, 1.0),
		1
	)

	road_cursor_icon.add_theme_stylebox_override("panel", road_style)
	ui_root.add_child(road_cursor_icon)

func update_road_cursor_icon_position() -> void:
	if road_cursor_icon == null:
		return

	var icon_size := Vector2(12.0, 12.0)
	var mouse_position := get_viewport().get_mouse_position()

	road_cursor_icon.size = icon_size
	road_cursor_icon.position = mouse_position + Vector2(10.0, 10.0)
	road_cursor_icon.move_to_front()

func set_road_option_selected(is_selected: bool) -> void:
	if build_option_icon == null:
		return

	var fill_color := Color(0.55, 0.55, 0.55, 1.0)
	var border_color := Color(0.18, 0.18, 0.18, 1.0)

	if is_selected:
		fill_color = Color(0.34, 0.34, 0.34, 1.0)
		border_color = Color(0.95, 0.95, 0.95, 1.0)

	var icon_style := create_flat_ui_style(
		fill_color,
		border_color,
		1
	)

	build_option_icon.add_theme_stylebox_override("panel", icon_style)

func update_build_button_state() -> void:
	var can_build := WorldData.can_build_in_city()

	if bottom_button_two != null:
		bottom_button_two.disabled = not can_build
		bottom_button_two.text = "2"

	if build_option_button != null:
		build_option_button.disabled = not can_build

		if not can_build:
			build_option_button.visible = false


func is_placing_city_object_type(object_type: String) -> bool:
	if not has_active_city_object_placement():
		return false

	return str(active_city_object_placement.get("type", "")) == object_type

func create_bottom_city_buttons() -> void:
	bottom_button_one = Button.new()
	bottom_button_one.text = "1"
	bottom_button_one.focus_mode = Control.FOCUS_NONE
	bottom_button_one.custom_minimum_size = Vector2(58.0, 58.0)
	bottom_button_one.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(bottom_button_one)
	bottom_button_one.pressed.connect(on_city_object_menu_button_pressed.bind(WorldData.CITY_OBJECT_CITY_CENTER))

	bottom_button_two = Button.new()
	bottom_button_two.text = "2"
	bottom_button_two.focus_mode = Control.FOCUS_NONE
	bottom_button_two.custom_minimum_size = Vector2(58.0, 58.0)
	bottom_button_two.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(bottom_button_two)
	bottom_button_two.pressed.connect(on_build_menu_button_pressed)

	bottom_button_three = Button.new()
	bottom_button_three.text = "3"
	bottom_button_three.focus_mode = Control.FOCUS_NONE
	bottom_button_three.custom_minimum_size = Vector2(58.0, 58.0)
	bottom_button_three.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(bottom_button_three)
	bottom_button_three.pressed.connect(on_city_object_menu_button_pressed.bind(WorldData.CITY_OBJECT_HOUSE))

	bottom_button_four = Button.new()
	bottom_button_four.text = "4"
	bottom_button_four.focus_mode = Control.FOCUS_NONE
	bottom_button_four.custom_minimum_size = Vector2(58.0, 58.0)
	bottom_button_four.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(bottom_button_four)
	bottom_button_four.pressed.connect(on_city_object_menu_button_pressed.bind(WorldData.CITY_OBJECT_STOCKPILE))

	bottom_button_five = Button.new()
	bottom_button_five.text = "5"
	bottom_button_five.focus_mode = Control.FOCUS_NONE
	bottom_button_five.custom_minimum_size = Vector2(58.0, 58.0)
	bottom_button_five.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(bottom_button_five)
	bottom_button_five.pressed.connect(on_city_object_menu_button_pressed.bind(WorldData.CITY_OBJECT_FISHING_GROUNDS))

func create_city_object_option_button(object_type: String) -> void:
	var definition := WorldData.get_city_object_definition(object_type)

	if definition.is_empty():
		push_error("Missing city object definition for: " + object_type)
		return

	var option_button := Button.new()
	option_button.text = ""
	option_button.focus_mode = Control.FOCUS_NONE
	option_button.custom_minimum_size = Vector2(58.0, 58.0)
	option_button.mouse_filter = Control.MOUSE_FILTER_STOP
	option_button.visible = false

	ui_root.add_child(option_button)
	option_button.pressed.connect(on_city_object_option_button_pressed.bind(object_type))

	var icon := Panel.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var visual_style := WorldData.get_city_object_visual_style_for_type(object_type)

	var icon_style := create_flat_ui_style(
		Color(
			float(visual_style["fill_color"].r),
			float(visual_style["fill_color"].g),
			float(visual_style["fill_color"].b),
			1.0
		),
		Color(
			float(visual_style["frame_color"].r),
			float(visual_style["frame_color"].g),
			float(visual_style["frame_color"].b),
			1.0
		),
		1
	)

	icon.add_theme_stylebox_override("panel", icon_style)
	option_button.add_child(icon)

	city_object_option_buttons[object_type] = option_button
	city_object_option_icons[object_type] = icon

func get_bottom_button_for_slot(button_slot: int) -> Button:
	match button_slot:
		1:
			return bottom_button_one
		2:
			return bottom_button_two
		3:
			return bottom_button_three
		4:
			return bottom_button_four
		5:
			return bottom_button_five

	return null

func layout_city_object_option_button(object_type: String, _viewport_size: Vector2) -> void:
	if not city_object_option_buttons.has(object_type):
		return

	var definition := WorldData.get_city_object_definition(object_type)

	if definition.is_empty():
		return

	var button_slot: int = int(definition.get("button_slot", 0))
	var bottom_button := get_bottom_button_for_slot(button_slot)

	if bottom_button == null:
		return

	var option_button: Button = city_object_option_buttons[object_type]
	var button_size := 58.0
	var gap := 6.0

	option_button.position = Vector2(
		bottom_button.position.x,
		bottom_button.position.y - button_size - gap
	)

	option_button.size = Vector2(button_size, button_size)

	if city_object_option_icons.has(object_type):
		var icon: Panel = city_object_option_icons[object_type]
		var size_tiles: Vector2i = definition["size"]
		var largest_side: float = float(max(size_tiles.x, size_tiles.y))
		var max_icon_size := 30.0

		var icon_size := Vector2(
			float(size_tiles.x) / largest_side * max_icon_size,
			float(size_tiles.y) / largest_side * max_icon_size
		)

		icon.position = (Vector2(button_size, button_size) - icon_size) * 0.5
		icon.size = icon_size


func layout_all_city_object_option_buttons(viewport_size: Vector2) -> void:
	for object_type in city_object_option_buttons.keys():
		layout_city_object_option_button(str(object_type), viewport_size)

func create_back_button() -> void:
	back_button = Button.new()
	back_button.text = "Back"
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.custom_minimum_size = Vector2(68.0, 50.0)
	back_button.mouse_filter = Control.MOUSE_FILTER_STOP

	var normal_style := create_flat_ui_style(
		Color(0.85, 0.05, 0.03, 0.95),
		Color(0.35, 0.00, 0.00, 1.0),
		2
	)

	var hover_style := create_flat_ui_style(
		Color(1.0, 0.10, 0.08, 0.95),
		Color(0.45, 0.00, 0.00, 1.0),
		2
	)

	var pressed_style := create_flat_ui_style(
		Color(0.60, 0.02, 0.02, 0.95),
		Color(0.20, 0.00, 0.00, 1.0),
		2
	)

	back_button.add_theme_stylebox_override("normal", normal_style)
	back_button.add_theme_stylebox_override("hover", hover_style)
	back_button.add_theme_stylebox_override("pressed", pressed_style)
	back_button.add_theme_color_override("font_color", Color.WHITE)
	back_button.add_theme_color_override("font_hover_color", Color.WHITE)
	back_button.add_theme_color_override("font_pressed_color", Color.WHITE)

	ui_root.add_child(back_button)

	back_button.pressed.connect(on_back_button_pressed)

func can_build_here() -> bool:
	return WorldData.can_build_in_city()

func create_resource_bar() -> void:
	resource_bar = Control.new()
	resource_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(resource_bar)

	resource_boxes.clear()
	resource_icons.clear()
	resource_amount_labels.clear()

	var resource_order := get_city_resource_order()

	for i in range(resource_order.size()):
		var resource: String = resource_order[i]

		var box := Panel.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var box_style := create_flat_ui_style(
			Color(0.08, 0.08, 0.08, 0.82),
			Color(0.85, 0.85, 0.85, 0.95),
			1
		)

		box.add_theme_stylebox_override("panel", box_style)
		resource_bar.add_child(box)
		resource_boxes.append(box)

		var icon := ColorRect.new()
		icon.color = get_resource_color(resource)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(icon)
		resource_icons.append(icon)

		var amount_label := Label.new()
		amount_label.text = "0"
		amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		amount_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		amount_label.add_theme_color_override("font_color", Color.WHITE)
		amount_label.add_theme_font_size_override("font_size", 12)
		box.add_child(amount_label)
		resource_amount_labels.append(amount_label)

func get_city_resource_order() -> Array[String]:
	return [
		WorldData.RESOURCE_FISH,
		WorldData.RESOURCE_COAL,
		WorldData.RESOURCE_IRON,
		WorldData.RESOURCE_GOLD
	]

func update_resource_bar_values() -> void:
	var resource_order := get_city_resource_order()

	for i in range(resource_amount_labels.size()):
		if i >= resource_order.size():
			continue

		var resource: String = resource_order[i]
		var amount := (
			WorldData.get_total_stored_city_resource_amount(
				resource
			)
		)
		var capacity := (
			WorldData.get_total_city_resource_storage_capacity(
				resource
			)
		)

		resource_amount_labels[i].text = str(amount) + "/" + str(capacity)

func create_city_maps_menu() -> void:
	city_maps_button = Button.new()
	city_maps_button.text = "Maps"
	city_maps_button.focus_mode = Control.FOCUS_NONE
	city_maps_button.mouse_filter = Control.MOUSE_FILTER_STOP
	city_maps_button.custom_minimum_size = Vector2(52.0, 52.0)

	ui_root.add_child(city_maps_button)
	city_maps_button.pressed.connect(on_city_maps_button_pressed)

	city_map_mode_buttons.clear()

	for i in range(MapVisuals.get_all_view_modes().size()):
		var mode_button := Button.new()
		mode_button.text = str(i + 1)
		mode_button.focus_mode = Control.FOCUS_NONE
		mode_button.mouse_filter = Control.MOUSE_FILTER_STOP
		mode_button.custom_minimum_size = Vector2(52.0, 52.0)
		mode_button.visible = false
		mode_button.tooltip_text = get_city_map_mode_name(get_city_map_mode_for_index(i))

		ui_root.add_child(mode_button)
		city_map_mode_buttons.append(mode_button)

		mode_button.pressed.connect(
			on_city_map_mode_button_pressed.bind(get_city_map_mode_for_index(i))
		)

	update_city_maps_button_visual()
	update_city_map_mode_button_visuals()


func layout_city_maps_menu(viewport_size: Vector2) -> void:
	if city_maps_button == null:
		return

	var button_size := 52.0
	var resource_box_width := 52.0
	var resource_box_height := 50.0
	var gold_index := get_city_resource_order().find(WorldData.RESOURCE_GOLD)

	if gold_index < 0:
		gold_index = 3

	var gold_box_x := viewport_size.x - resource_box_width * 4.0 + float(gold_index) * resource_box_width
	var gold_box_y := 0.0

	city_maps_button.position = Vector2(gold_box_x, gold_box_y + resource_box_height)
	city_maps_button.size = Vector2(button_size, button_size)

	var popup_x := city_maps_button.position.x + button_size
	var popup_y := city_maps_button.position.y

	var popup_width := button_size * float(city_map_mode_buttons.size())

	if popup_x + popup_width > viewport_size.x:
		popup_x = city_maps_button.position.x - popup_width

	for i in range(city_map_mode_buttons.size()):
		var mode_button := city_map_mode_buttons[i]
		mode_button.position = Vector2(popup_x + float(i) * button_size, popup_y)
		mode_button.size = Vector2(button_size, button_size)

	city_maps_button.move_to_front()

	if city_map_menu_open:
		for mode_button in city_map_mode_buttons:
			mode_button.move_to_front()


func on_city_maps_button_pressed() -> void:
	set_city_map_menu_open(not city_map_menu_open)


func set_city_map_menu_open(is_open: bool) -> void:
	city_map_menu_open = is_open

	for mode_button in city_map_mode_buttons:
		mode_button.visible = city_map_menu_open

	update_city_maps_button_visual()
	update_city_map_mode_button_visuals()
	layout_city_maps_menu(get_viewport_rect().size)


func close_city_map_menu() -> void:
	if not city_map_menu_open:
		return

	set_city_map_menu_open(false)


func update_city_maps_button_visual() -> void:
	if city_maps_button == null:
		return

	if city_map_menu_open:
		city_maps_button.text = "Close"
		apply_square_button_style(
			city_maps_button,
			Color(0.75, 0.04, 0.03, 0.96),
			Color(0.25, 0.0, 0.0, 1.0),
			Color.WHITE
		)
	else:
		city_maps_button.text = "Maps"
		apply_square_button_style(
			city_maps_button,
			Color(0.55, 0.38, 0.14, 0.96),
			Color(0.24, 0.15, 0.04, 1.0),
			Color.WHITE
		)


func update_city_map_mode_button_visuals() -> void:
	for i in range(city_map_mode_buttons.size()):
		var mode_button := city_map_mode_buttons[i]
		var mode := get_city_map_mode_for_index(i)

		if mode == city_view_mode:
			apply_square_button_style(
				mode_button,
				Color(0.0, 0.85, 1.0, 0.95),
				Color(0.0, 0.22, 0.32, 1.0),
				Color.BLACK
			)
		else:
			apply_square_button_style(
				mode_button,
				Color(0.08, 0.08, 0.08, 0.90),
				Color(0.85, 0.85, 0.85, 0.85),
				Color.WHITE
			)


func apply_square_button_style(
	button: Button,
	fill_color: Color,
	border_color: Color,
	font_color: Color
) -> void:
	var normal_style := create_flat_ui_style(fill_color, border_color, 1)
	var hover_style := create_flat_ui_style(fill_color.lightened(0.15), border_color.lightened(0.15), 1)
	var pressed_style := create_flat_ui_style(fill_color.darkened(0.18), border_color, 1)

	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_stylebox_override("focus", normal_style)

	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_hover_color", font_color)
	button.add_theme_color_override("font_pressed_color", font_color)
	button.add_theme_font_size_override("font_size", 14)

func _exit_tree() -> void:
	if city_texture_cache != null:
		city_texture_cache.cancel_warmup()

func on_city_map_mode_button_pressed(mode: int) -> void:
	set_city_view_mode(mode)


func set_city_view_mode(mode: int) -> void:
	if city_view_mode == mode:
		return

	city_view_mode = mode

	print("City map mode: ", get_city_map_mode_name(city_view_mode))

	if city_texture_cache != null:
		city_texture_cache.cancel_warmup()

	apply_cached_city_map_mode_texture()
	start_city_texture_warmup()

	update_city_map_mode_button_visuals()
	queue_redraw()

func get_city_map_mode_for_index(index: int) -> int:
	return MapVisuals.get_view_mode_for_index(index)


func get_city_map_mode_name(mode: int) -> String:
	return MapVisuals.get_view_mode_name(mode)


func get_all_city_view_modes() -> Array[int]:
	return MapVisuals.get_all_view_modes()

func create_flat_ui_style(fill_color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()

	style.bg_color = fill_color
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_right = border_width
	style.border_width_top = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0

	return style

func update_city_ui_layout() -> void:
	if ui_root == null:
		return

	var viewport_size: Vector2 = get_viewport_rect().size

	layout_bottom_buttons(viewport_size)
	layout_all_city_object_option_buttons(viewport_size)
	layout_build_option_button(viewport_size)
	layout_resource_bar(viewport_size)
	layout_object_info_panel(viewport_size)
	layout_city_maps_menu(viewport_size)
	layout_back_button(viewport_size)
func close_city_object_menu(object_type: String) -> void:
	if city_object_option_buttons.has(object_type):
		var option_button: Button = city_object_option_buttons[object_type]
		option_button.visible = false


func close_all_city_object_menus() -> void:
	for object_type in city_object_option_buttons.keys():
		close_city_object_menu(str(object_type))


func has_open_city_object_menu() -> bool:
	for object_type in city_object_option_buttons.keys():
		var option_button: Button = city_object_option_buttons[object_type]

		if option_button.visible:
			return true

	return false


func on_city_object_menu_button_pressed(object_type: String) -> void:
	if not WorldData.can_use_city_object_definition(object_type):
		print("City object menu blocked: ", object_type)
		update_city_object_button_states()
		return

	if not city_object_option_buttons.has(object_type):
		return

	close_city_map_menu()
	close_build_menu()
	cancel_road_placement()

	var option_button: Button = city_object_option_buttons[object_type]
	var should_open := not option_button.visible

	close_all_city_object_menus()

	if not should_open:
		cancel_active_city_object_placement()
		return

	cancel_active_city_object_placement()

	option_button.visible = true
	layout_city_object_option_button(object_type, get_viewport_rect().size)
	option_button.move_to_front()

	update_city_object_button_states()

func on_city_object_option_button_pressed(object_type: String) -> void:
	if not WorldData.can_use_city_object_definition(object_type):
		print("City object placement blocked: ", object_type)
		update_city_object_button_states()
		return

	if is_placing_city_object_type(object_type):
		cancel_active_city_object_placement()
	else:
		start_city_object_placement_from_definition(object_type)

func start_city_object_placement_from_definition(object_type: String) -> void:
	var definition := WorldData.get_city_object_definition(object_type)

	if definition.is_empty():
		push_error("Cannot start placement. Missing city object definition: " + object_type)
		return

	if not WorldData.can_use_city_object_definition(object_type):
		print("Cannot place locked city object: ", object_type)
		update_city_object_button_states()
		return

	close_build_menu()
	cancel_road_placement()

	var size_tiles: Vector2i = definition["size"]
	var repeat_after_place: bool = bool(definition.get("repeat_after_place", false))

	start_city_object_placement(
		object_type,
		size_tiles,
		"player",
		repeat_after_place
	)

	set_city_object_option_selected(object_type, true)
	queue_redraw()

	print("City object placement started: ", object_type)


func cancel_active_city_object_placement() -> void:
	if not has_active_city_object_placement():
		return

	var object_type: String = str(active_city_object_placement.get("type", ""))

	clear_city_object_placement()

	if object_type != "":
		set_city_object_option_selected(object_type, false)

	queue_redraw()

	print("City object placement canceled: ", object_type)


func set_city_object_option_selected(object_type: String, is_selected: bool) -> void:
	if not city_object_option_icons.has(object_type):
		return

	var icon: Panel = city_object_option_icons[object_type]
	var visual_style := WorldData.get_city_object_visual_style_for_type(object_type)

	var fill_color: Color = visual_style["fill_color"]
	var border_color: Color = visual_style["frame_color"]

	fill_color = Color(fill_color.r, fill_color.g, fill_color.b, 1.0)
	border_color = Color(border_color.r, border_color.g, border_color.b, 1.0)

	if is_selected:
		border_color = Color(0.0, 0.85, 1.0, 1.0)

	var icon_style := create_flat_ui_style(
		fill_color,
		border_color,
		1
	)

	icon.add_theme_stylebox_override("panel", icon_style)

func update_city_object_button_states() -> void:
	var city_object_main_buttons := {
		WorldData.CITY_OBJECT_CITY_CENTER: bottom_button_one,
		WorldData.CITY_OBJECT_HOUSE: bottom_button_three,
		WorldData.CITY_OBJECT_STOCKPILE: bottom_button_four,
		WorldData.CITY_OBJECT_FISHING_GROUNDS: bottom_button_five
	}

	for object_type in city_object_main_buttons.keys():
		var object_type_string := str(object_type)
		var definition := WorldData.get_city_object_definition(object_type_string)
		var main_button: Button = city_object_main_buttons[object_type_string]

		if definition.is_empty() or main_button == null:
			continue

		main_button.disabled = not WorldData.can_use_city_object_definition(object_type_string)
		main_button.text = str(int(definition.get("button_slot", 0)))

	for object_type in city_object_option_buttons.keys():
		var object_type_string := str(object_type)
		var option_button: Button = city_object_option_buttons[object_type_string]
		var can_use := WorldData.can_use_city_object_definition(object_type_string)

		option_button.disabled = not can_use

		if not can_use:
			option_button.visible = false
			set_city_object_option_selected(object_type_string, false)

func create_object_info_panel() -> void:
	object_info_panel = Panel.new()
	object_info_panel.visible = false
	object_info_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var panel_style := create_flat_ui_style(
		Color(0.16, 0.16, 0.16, 0.94),
		Color(0.42, 0.42, 0.42, 1.0),
		1
	)

	object_info_panel.add_theme_stylebox_override("panel", panel_style)
	ui_root.add_child(object_info_panel)

	object_info_title_label = Label.new()
	object_info_title_label.text = "City Keep"
	object_info_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	object_info_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	object_info_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	object_info_title_label.add_theme_color_override("font_color", Color(0.88, 0.96, 1.0, 1.0))
	object_info_title_label.add_theme_font_size_override("font_size", 18)
	object_info_panel.add_child(object_info_title_label)

	object_info_body_label = Label.new()
	object_info_body_label.text = ""
	object_info_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	object_info_body_label.add_theme_color_override("font_color", Color(0.82, 0.82, 0.82, 1.0))
	object_info_body_label.add_theme_font_size_override("font_size", 13)
	object_info_panel.add_child(object_info_body_label)
	create_object_info_storage_rows()

func create_object_info_storage_rows() -> void:
	object_info_storage_title_label = Label.new()
	object_info_storage_title_label.text = "Storage"
	object_info_storage_title_label.visible = false
	object_info_storage_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	object_info_storage_title_label.add_theme_color_override("font_color", Color(0.88, 0.96, 1.0, 1.0))
	object_info_storage_title_label.add_theme_font_size_override("font_size", 15)
	object_info_panel.add_child(object_info_storage_title_label)

	object_info_storage_icons.clear()
	object_info_storage_amount_labels.clear()

	for i in range(4):
		var icon := ColorRect.new()
		icon.visible = false
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		object_info_panel.add_child(icon)
		object_info_storage_icons.append(icon)

		var amount_label := Label.new()
		amount_label.visible = false
		amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		amount_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92, 1.0))
		amount_label.add_theme_font_size_override("font_size", 13)
		object_info_panel.add_child(amount_label)
		object_info_storage_amount_labels.append(amount_label)

func layout_object_info_panel(viewport_size: Vector2) -> void:
	if object_info_panel == null:
		return

	var panel_width := 240.0
	var panel_height := minf(600.0, viewport_size.y)
	var desired_panel_y := viewport_size.y * 0.10
	var maximum_panel_y := maxf(
		0.0,
		viewport_size.y - panel_height
	)
	var panel_y := minf(
		maxf(desired_panel_y, 0.0),
		maximum_panel_y
	)

	object_info_panel.position = Vector2(
		0.0,
		panel_y
	)
	object_info_panel.size = Vector2(
		panel_width,
		panel_height
	)

	if object_info_title_label != null:
		object_info_title_label.position = Vector2(0.0, 10.0)
		object_info_title_label.size = Vector2(
			panel_width,
			32.0
		)

	if object_info_body_label != null:
		object_info_body_label.position = Vector2(14.0, 56.0)
		object_info_body_label.size = Vector2(
			panel_width - 28.0,
			370.0
		)

	layout_object_info_storage_rows(panel_width)

func layout_object_info_storage_rows(panel_width: float) -> void:
	if object_info_storage_title_label != null:
		object_info_storage_title_label.position = Vector2(14.0, 436.0)
		object_info_storage_title_label.size = Vector2(panel_width - 28.0, 24.0)

	var row_start_y := 468.0
	var row_height := 28.0
	var icon_size := 16.0

	for i in range(object_info_storage_icons.size()):
		var row_y := row_start_y + float(i) * row_height

		var icon := object_info_storage_icons[i]
		icon.position = Vector2(18.0, row_y + 4.0)
		icon.size = Vector2(icon_size, icon_size)

		if i < object_info_storage_amount_labels.size():
			var amount_label := object_info_storage_amount_labels[i]
			amount_label.position = Vector2(44.0, row_y)
			amount_label.size = Vector2(panel_width - 58.0, row_height)

func get_container_type_display_name(container_type: String) -> String:
	match container_type:
		WorldData.CONTAINER_TYPE_PUBLIC_CITY_STORAGE:
			return "Public city storage"
		WorldData.CONTAINER_TYPE_PRIVATE_HOME_STORAGE:
			return "Private home storage"
		WorldData.CONTAINER_TYPE_WORKPLACE_STORAGE:
			return "Workplace storage"
		WorldData.CONTAINER_TYPE_PERSONAL_INVENTORY:
			return "Personal inventory"
		WorldData.CONTAINER_TYPE_GROUND_PILE:
			return "Ground pile"
		_:
			return "None"


func get_storage_panel_title_for_object(city_object: Dictionary) -> String:
	var container_type := WorldData.get_city_object_container_type(city_object)

	match container_type:
		WorldData.CONTAINER_TYPE_PUBLIC_CITY_STORAGE:
			return "Public Storage"
		WorldData.CONTAINER_TYPE_PRIVATE_HOME_STORAGE:
			return "Private Storage"
		WorldData.CONTAINER_TYPE_WORKPLACE_STORAGE:
			return "Workplace Storage"
		WorldData.CONTAINER_TYPE_PERSONAL_INVENTORY:
			return "Personal Inventory"
		WorldData.CONTAINER_TYPE_GROUND_PILE:
			return "Ground Pile"
		_:
			return "Storage"

func get_workplace_production_status_display_name(
	production_status: String
) -> String:
	match production_status:
		WorldData.WORKPLACE_PRODUCTION_STATUS_WORKING:
			return "Working"
		WorldData.WORKPLACE_PRODUCTION_STATUS_IDLE_NO_WORKERS:
			return "Idle - No Workers"
		WorldData.WORKPLACE_PRODUCTION_STATUS_BLOCKED_OUTPUT_FULL:
			return "Blocked - Output Storage Full"
		WorldData.WORKPLACE_PRODUCTION_STATUS_BLOCKED_MISSING_INPUT:
			return "Blocked - Missing Input"
		WorldData.WORKPLACE_PRODUCTION_STATUS_BLOCKED_NO_RESOURCE_SOURCE:
			return "Blocked - No Resource Source"
		WorldData.WORKPLACE_PRODUCTION_STATUS_INACTIVE:
			return "Inactive"
		_:
			return production_status.capitalize()


func format_compact_production_number(value: float) -> String:
	var nearest_integer := int(round(value))

	if is_equal_approx(value, float(nearest_integer)):
		return str(nearest_integer)

	return "%.2f" % value

func update_selected_object_panel() -> void:
	if object_info_panel == null:
		return

	if selected_city_object_id < 0:
		object_info_panel.visible = false
		hide_object_info_storage_display()
		return

	var city_object: Dictionary = get_city_object_by_id(selected_city_object_id)

	if city_object.is_empty():
		object_info_panel.visible = false
		hide_object_info_storage_display()
		return

	object_info_panel.visible = true

	var object_type: String = str(city_object["type"])

	if object_type == WorldData.CITY_OBJECT_CITY_CENTER:
		object_info_title_label.text = "City Keep"
	else:
		object_info_title_label.text = get_city_object_display_name(city_object)

	var top_left: Vector2i = city_object.get("top_left", Vector2i(-1, -1))
	var size_tiles: Vector2i = city_object.get("size", Vector2i.ZERO)

	var container_type := WorldData.get_city_object_container_type(city_object)
	var container_text := get_container_type_display_name(container_type)

	var body_lines: Array = [
		"Object: " + get_city_object_display_name(city_object)
	]

	if object_type == WorldData.CITY_OBJECT_CITY_CENTER:
		body_lines.append("Population: " + str(WorldData.get_city_population_count()))
		body_lines.append(
			"Housed: "
			+ str(WorldData.get_city_housed_citizen_count())
			+ " / "
			+ str(WorldData.get_total_city_resident_capacity())
		)
		body_lines.append("Unemployed: " + str(WorldData.get_city_unemployed_citizen_count()))
	elif object_type == WorldData.CITY_OBJECT_HOUSE:
		body_lines.append(
			"Residents: "
			+ str(WorldData.get_city_object_resident_count(city_object))
			+ " / "
			+ str(WorldData.get_city_object_resident_capacity(city_object))
		)

		var resident_names := WorldData.get_city_object_resident_names(city_object)

		for resident_name in resident_names:
			body_lines.append("- " + str(resident_name))
	
	elif WorldData.city_object_is_workplace(city_object):
		var production_status := (
			WorldData.get_city_object_production_status(
				city_object
			)
		)

		body_lines.append(
			"Status: "
			+ get_workplace_production_status_display_name(
				production_status
			)
		)

		body_lines.append(
			"Workers: "
			+ str(
				WorldData.get_city_object_worker_count(
					city_object
				)
			)
			+ " / "
			+ str(
				WorldData.get_city_object_worker_capacity(
					city_object
				)
			)
		)

		body_lines.append(
			"Productive: "
			+ str(
				WorldData.get_city_object_productive_worker_count(
					city_object
				)
			)
		)

		var worker_names := (
			WorldData.get_city_object_worker_names(
				city_object
			)
		)

		for worker_name in worker_names:
			body_lines.append("- " + str(worker_name))

		var output_resource := (
			WorldData.get_city_object_output_resource(
				city_object
			)
		)

		if output_resource != WorldData.RESOURCE_NONE:
			body_lines.append(
				"Output: "
				+ output_resource.capitalize()
			)

		var production_recipe := (
			WorldData.get_city_object_production_recipe(
				city_object
			)
		)
		var work_units_per_batch := int(
			production_recipe.get(
				"work_units_per_batch",
				0
			)
		)
		var progress_work_units := (
			WorldData.get_city_object_production_progress_work_units(
				city_object
			)
		)

		if work_units_per_batch > 0:
			body_lines.append(
				"Progress: "
				+ str(progress_work_units)
				+ " / "
				+ str(work_units_per_batch)
			)

		if output_resource != WorldData.RESOURCE_NONE:
			var output_per_hour := (
				WorkplaceProductionSystem.get_estimated_output_per_hour(
					city_object,
					output_resource
				)
			)

			body_lines.append(
				"Rate: "
				+ format_compact_production_number(
					output_per_hour
				)
				+ " "
				+ output_resource
				+ "/hour"
			)
		var source_evaluation := (
			WorkplaceProductionSystem.get_resource_source_evaluation(
				city_object,
				city_world
			)
		)

		if bool(
			source_evaluation.get(
				"uses_environmental_source",
				false
			)
		):
			var source_resource := str(
				source_evaluation.get(
					"resource_type",
					WorldData.RESOURCE_NONE
				)
			)
			var resource_tile_count := int(
				source_evaluation.get(
					"resource_tile_count",
					0
				)
			)
			var zone_tile_count := int(
				source_evaluation.get(
					"zone_tile_count",
					0
				)
			)
			var density_percentage := (
				float(
					source_evaluation.get(
						"density_basis_points",
						0
					)
				)
				/ 100.0
			)
			var source_target := int(
				source_evaluation.get(
					"source_tiles_for_full_productivity",
					0
				)
			)
			var reach_tiles := int(
				source_evaluation.get(
					"reach_tiles",
					0
				)
			)

			body_lines.append(
				source_resource.capitalize()
				+ " Source: "
				+ str(resource_tile_count)
				+ " / "
				+ str(zone_tile_count)
				+ " zone tiles"
			)

			body_lines.append(
				"Density: "
				+ format_compact_production_number(
					density_percentage
				)
				+ "% | Target: "
				+ str(source_target)
				+ " | Reach: "
				+ str(reach_tiles)
			)

		var site_productivity_percentage := (
			float(
				WorkplaceProductionSystem.get_current_site_productivity_basis_points(
					city_object,
					city_world
				)
			)
			/ 100.0
		)

		body_lines.append(
			"Site Productivity: "
			+ format_compact_production_number(
				site_productivity_percentage
			)
			+ "%"
		)
		body_lines.append(
			"Site Productivity: "
			+ format_compact_production_number(
				site_productivity_percentage
			)
			+ "%"
		)

	body_lines.append("Owner: " + str(city_object.get("owner", "none")))
	body_lines.append("Container: " + container_text)
	body_lines.append("Position: " + str(top_left.x) + ", " + str(top_left.y))
	body_lines.append("Size: " + str(size_tiles.x) + " x " + str(size_tiles.y))

	var body_text := ""

	for line_index in range(body_lines.size()):
		if line_index > 0:
			body_text += "\n"

		body_text += str(body_lines[line_index])

	object_info_body_label.text = body_text
	
	update_object_info_storage_display(city_object)

func update_object_info_storage_display(city_object: Dictionary) -> void:
	var storage_resources := WorldData.get_city_object_storage_resources(city_object)

	if storage_resources.is_empty():
		hide_object_info_storage_display()
		return

	if object_info_storage_title_label != null:
		object_info_storage_title_label.text = get_storage_panel_title_for_object(city_object)
		object_info_storage_title_label.visible = true

	for i in range(object_info_storage_icons.size()):
		if i >= storage_resources.size():
			object_info_storage_icons[i].visible = false

			if i < object_info_storage_amount_labels.size():
				object_info_storage_amount_labels[i].visible = false

			continue

		var resource: String = storage_resources[i]
		var amount := WorldData.get_city_object_stored_resource_amount(city_object, resource)
		var capacity := WorldData.get_city_object_storage_capacity_for_resource(city_object, resource)

		var icon := object_info_storage_icons[i]
		icon.visible = true
		icon.color = get_resource_color(resource)

		if i < object_info_storage_amount_labels.size():
			var amount_label := object_info_storage_amount_labels[i]
			amount_label.visible = true
			amount_label.text = resource.capitalize() + ": " + str(amount) + " / " + str(capacity)


func hide_object_info_storage_display() -> void:
	if object_info_storage_title_label != null:
		object_info_storage_title_label.visible = false

	for icon in object_info_storage_icons:
		icon.visible = false

	for amount_label in object_info_storage_amount_labels:
		amount_label.visible = false

func create_object_selection_box_visual() -> void:
	object_selection_box_panel = Panel.new()
	object_selection_box_panel.visible = false
	object_selection_box_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var box_style := create_flat_ui_style(
		CURSOR_LOOK_FILL_COLOR,
		CURSOR_LOOK_BORDER_COLOR,
		1
	)

	object_selection_box_panel.add_theme_stylebox_override("panel", box_style)
	ui_root.add_child(object_selection_box_panel)


func update_object_selection_box_visual() -> void:
	if object_selection_box_panel == null:
		return

	var drag_distance: float = object_selection_drag_start_screen.distance_to(object_selection_drag_current_screen)

	if not is_object_selection_dragging or drag_distance < OBJECT_SELECTION_DRAG_THRESHOLD_PIXELS:
		object_selection_box_panel.visible = false
		return

	var min_x: float = minf(object_selection_drag_start_screen.x, object_selection_drag_current_screen.x)
	var min_y: float = minf(object_selection_drag_start_screen.y, object_selection_drag_current_screen.y)
	var max_x: float = maxf(object_selection_drag_start_screen.x, object_selection_drag_current_screen.x)
	var max_y: float = maxf(object_selection_drag_start_screen.y, object_selection_drag_current_screen.y)

	object_selection_box_panel.visible = true
	object_selection_box_panel.position = Vector2(min_x, min_y)
	object_selection_box_panel.size = Vector2(max_x - min_x, max_y - min_y)
	object_selection_box_panel.move_to_front()

func layout_bottom_buttons(viewport_size: Vector2) -> void:
	if (
		bottom_button_one == null
		or bottom_button_two == null
		or bottom_button_three == null
		or bottom_button_four == null
		or bottom_button_five == null
	):
		return

	var button_size := 58.0
	var gap := 0.0

	var total_width := button_size * 5.0 + gap * 4.0
	var start_x := viewport_size.x * 0.5 - total_width * 0.5
	var y := viewport_size.y - button_size

	bottom_button_one.position = Vector2(start_x, y)
	bottom_button_one.size = Vector2(button_size, button_size)

	bottom_button_two.position = Vector2(start_x + button_size + gap, y)
	bottom_button_two.size = Vector2(button_size, button_size)

	bottom_button_three.position = Vector2(start_x + (button_size + gap) * 2.0, y)
	bottom_button_three.size = Vector2(button_size, button_size)

	bottom_button_four.position = Vector2(start_x + (button_size + gap) * 3.0, y)
	bottom_button_four.size = Vector2(button_size, button_size)

	bottom_button_five.position = Vector2(start_x + (button_size + gap) * 4.0, y)
	bottom_button_five.size = Vector2(button_size, button_size)

func layout_resource_bar(viewport_size: Vector2) -> void:
	if resource_bar == null:
		return

	var box_width := 52.0
	var box_height := 50.0
	var box_count := 4
	var total_width := box_width * float(box_count)

	resource_bar.position = Vector2(viewport_size.x - total_width, 0.0)
	resource_bar.size = Vector2(total_width, box_height)

	for i in range(resource_boxes.size()):
		var box := resource_boxes[i]
		box.position = Vector2(float(i) * box_width, 0.0)
		box.size = Vector2(box_width, box_height)

		if i < resource_icons.size():
			var icon := resource_icons[i]
			icon.position = Vector2(box_width * 0.5 - 8.0, 7.0)
			icon.size = Vector2(16.0, 16.0)

		if i < resource_amount_labels.size():
			var label := resource_amount_labels[i]
			label.position = Vector2(0.0, 25.0)
			label.size = Vector2(box_width, 20.0)


func layout_back_button(viewport_size: Vector2) -> void:
	if back_button == null:
		return

	var button_size := Vector2(68.0, 50.0)

	back_button.position = Vector2(
		viewport_size.x - button_size.x - 12.0,
		viewport_size.y - button_size.y - 12.0
	)

	back_button.size = button_size

func on_back_button_pressed() -> void:
	store_current_city_camera_state()
	
	var return_path := WorldData.official_world_scene_path

	if return_path.is_empty():
		return_path = WorldData.city_return_world_scene_path

	if return_path.is_empty():
		return_path = world_scene_path

	if return_path.is_empty():
		push_error("World scene path is empty.")
		return

	var error: Error = get_tree().change_scene_to_file(return_path)

	if error != OK:
		push_error("Could not load world scene: " + return_path)

func get_city_tile_color(tile: Dictionary) -> Color:
	return get_city_tile_color_for_mode(tile, city_view_mode)


func get_city_tile_color_for_mode(tile: Dictionary, mode: int) -> Color:
	return MapVisuals.get_tile_color_for_mode(tile, mode, 0.45)

func get_biome_color(tile: Dictionary) -> Color:
	return MapVisuals.get_biome_color(tile)

func get_resource_color(resource: String) -> Color:
	return MapVisuals.get_resource_color(resource)

func create_build_option_button() -> void:
	build_option_button = Button.new()
	build_option_button.text = ""
	build_option_button.focus_mode = Control.FOCUS_NONE
	build_option_button.custom_minimum_size = Vector2(58.0, 58.0)
	build_option_button.mouse_filter = Control.MOUSE_FILTER_STOP
	build_option_button.visible = false

	ui_root.add_child(build_option_button)
	build_option_button.pressed.connect(on_build_option_button_pressed)

	build_option_icon = Panel.new()
	build_option_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon_style := create_flat_ui_style(
		Color(0.55, 0.55, 0.55, 1.0),
		Color(0.18, 0.18, 0.18, 1.0),
		1
	)

	build_option_icon.add_theme_stylebox_override("panel", icon_style)
	build_option_button.add_child(build_option_icon)

func layout_build_option_button(_viewport_size: Vector2) -> void:
	if build_option_button == null or bottom_button_two == null:
		return

	var button_size := 58.0
	var gap := 6.0

	build_option_button.position = Vector2(
		bottom_button_two.position.x,
		bottom_button_two.position.y - button_size - gap
	)

	build_option_button.size = Vector2(button_size, button_size)

	if build_option_icon != null:
		build_option_icon.position = Vector2(21.0, 21.0)
		build_option_icon.size = Vector2(16.0, 16.0)

func close_build_menu() -> void:
	if build_option_button != null:
		build_option_button.visible = false

func on_build_menu_button_pressed() -> void:
	if not WorldData.can_build_in_city():
		print("Build menu blocked: found a city first.")
		update_build_button_state()
		return

	if build_option_button == null:
		return

	close_city_map_menu()

	var should_open := not build_option_button.visible

	close_all_city_object_menus()
	cancel_active_city_object_placement()

	if should_open:
		build_option_button.visible = true
		layout_build_option_button(get_viewport_rect().size)
		build_option_button.move_to_front()
	else:
		cancel_road_placement()
		build_option_button.visible = false

	update_build_button_state()

func on_build_option_button_pressed() -> void:
	if is_road_placement_active:
		cancel_road_placement()
	else:
		start_road_placement()

func start_road_placement() -> void:
	if not WorldData.can_build_in_city():
		print("Road placement blocked: found a city first.")
		update_build_button_state()
		return

	close_all_city_object_menus()
	cancel_active_city_object_placement()

	is_road_placement_active = true
	is_road_dragging = false
	road_preview_tiles.clear()
	road_preview_lookup.clear()
	road_drag_start_tile = Vector2i(-1, -1)
	road_drag_current_tile = Vector2i(-1, -1)

	if road_cursor_icon != null:
		road_cursor_icon.visible = true
		update_road_cursor_icon_position()

	set_road_option_selected(true)

	update_build_button_state()
	queue_redraw()

	print("Road placement started. Drag a selection box, then left-click again to confirm.")

func cancel_road_placement() -> void:
	if not is_road_placement_active and not is_road_dragging and road_preview_tiles.is_empty():
		return

	is_road_placement_active = false
	is_road_dragging = false
	road_preview_tiles.clear()
	road_preview_lookup.clear()
	road_drag_start_tile = Vector2i(-1, -1)
	road_drag_current_tile = Vector2i(-1, -1)

	if road_cursor_icon != null:
		road_cursor_icon.visible = false

	set_road_option_selected(false)

	queue_redraw()

	print("Road placement canceled.")

func cancel_build_placement() -> void:
	cancel_road_placement()

func confirm_active_city_object_placement() -> void:
	if city_world == null:
		return

	var preview_object := get_active_city_object_placement_preview()

	if preview_object.is_empty():
		print("Cannot place object: invalid mouse position.")
		return

	var object_type: String = str(preview_object.get("type", ""))
	var top_left: Vector2i = preview_object["top_left"]
	var size_tiles: Vector2i = preview_object["size"]
	var object_owner: String = str(preview_object.get("owner", "player"))
	var repeat_after_place: bool = bool(active_city_object_placement.get("repeat_after_place", false))

	if not WorldData.can_place_city_object(city_world, top_left, size_tiles):
		print("Cannot place object here.")
		return

	var placed_object := WorldData.add_city_object(
		object_type,
		top_left,
		size_tiles,
		object_owner
	)

	after_city_object_placed(placed_object)

	if not repeat_after_place:
		clear_city_object_placement()
		set_city_object_option_selected(object_type, false)

	update_city_object_button_states()
	update_build_button_state()
	update_debug_panel_text()

	print("Placed city object: ", placed_object)

	queue_redraw()

func after_city_object_placed(city_object: Dictionary) -> void:
	if city_object.is_empty():
		return

	var object_type: String = str(city_object.get("type", ""))
	var definition := WorldData.get_city_object_definition(object_type)

	if definition.is_empty():
		return

	var placement_effect: String = str(definition.get("placement_effect", WorldData.CITY_OBJECT_PLACEMENT_EFFECT_NONE))

	match placement_effect:
		WorldData.CITY_OBJECT_PLACEMENT_EFFECT_FOUND_CITY:
			after_city_center_placed(city_object)

func after_city_center_placed(city_object: Dictionary) -> void:
	if WorldData.has_player_city():
		return

	var top_left: Vector2i = city_object.get("top_left", Vector2i(-1, -1))
	var size_tiles: Vector2i = city_object.get("size", Vector2i.ZERO)

	WorldData.found_player_city(
		"First City",
		city_seed,
		Vector2i(city_world.width, city_world.height),
		top_left,
		size_tiles
	)

	update_city_object_button_states()
	update_build_button_state()

	print("Founded city at: ", top_left)
	print("City data: ", WorldData.player_city_data)

func start_object_selection_drag(screen_position: Vector2) -> void:
	is_object_selection_dragging = true

	object_selection_drag_start_screen = screen_position
	object_selection_drag_current_screen = screen_position

	object_selection_drag_start_world = get_global_mouse_position()
	object_selection_drag_current_world = object_selection_drag_start_world

	update_object_selection_box_visual()
	queue_redraw()

func update_object_selection_drag(screen_position: Vector2) -> void:
	if not is_object_selection_dragging:
		return

	object_selection_drag_current_screen = screen_position
	object_selection_drag_current_world = get_global_mouse_position()

	update_object_selection_box_visual()
	queue_redraw()

func finish_object_selection_drag(screen_position: Vector2) -> void:
	if not is_object_selection_dragging:
		return

	is_object_selection_dragging = false

	object_selection_drag_current_screen = screen_position
	object_selection_drag_current_world = get_global_mouse_position()

	if object_selection_box_panel != null:
		object_selection_box_panel.visible = false

	var drag_distance := object_selection_drag_start_screen.distance_to(object_selection_drag_current_screen)

	if drag_distance < OBJECT_SELECTION_DRAG_THRESHOLD_PIXELS:
		select_city_object_under_mouse()
	else:
		select_city_object_in_drag_rect()

	queue_redraw()


func select_city_object_under_mouse() -> void:
	var tile_position := get_city_tile_under_mouse()

	if tile_position == Vector2i(-1, -1):
		clear_selected_city_object()
		return

	var city_object := WorldData.get_city_object_at_tile(tile_position)

	if not is_city_object_selectable(city_object):
		clear_selected_city_object()
		return

	set_selected_city_object(int(city_object["id"]))


func select_city_object_in_drag_rect() -> void:
	var drag_rect := get_object_selection_world_rect()
	var best_object_id := -1
	var best_area := -1.0

	for city_object in WorldData.city_objects:
		if not is_city_object_selectable(city_object):
			continue

		var object_rect := get_city_object_world_rect(city_object)

		if not drag_rect.intersects(object_rect, true):
			continue

		var object_area := object_rect.size.x * object_rect.size.y

		if best_object_id == -1 or object_area > best_area:
			best_object_id = int(city_object["id"])
			best_area = object_area

	if best_object_id == -1:
		clear_selected_city_object()
		return

	set_selected_city_object(best_object_id)


func get_object_selection_world_rect() -> Rect2:
	var min_x: float = minf(object_selection_drag_start_world.x, object_selection_drag_current_world.x)
	var min_y: float = minf(object_selection_drag_start_world.y, object_selection_drag_current_world.y)
	var max_x: float = maxf(object_selection_drag_start_world.x, object_selection_drag_current_world.x)
	var max_y: float = maxf(object_selection_drag_start_world.y, object_selection_drag_current_world.y)

	return Rect2(
		Vector2(min_x, min_y),
		Vector2(max_x - min_x, max_y - min_y)
	)
	
func set_selected_city_object(object_id: int) -> void:
	if selected_city_object_id == object_id:
		update_selected_object_panel()
		return

	selected_city_object_id = object_id
	update_selected_object_panel()
	update_debug_panel_text()
	queue_redraw()

func clear_selected_city_object() -> void:
	if selected_city_object_id == -1:
		update_selected_object_panel()
		return

	selected_city_object_id = -1
	update_selected_object_panel()
	update_debug_panel_text()
	queue_redraw()

func is_city_object_selectable(city_object: Dictionary) -> bool:
	if city_object.is_empty():
		return false

	var object_type: String = str(city_object["type"])

	if object_type == WorldData.CITY_OBJECT_ROAD:
		return false

	return true

func get_city_object_by_id(object_id) -> Dictionary:
	if object_id == null:
		return {}

	if typeof(object_id) != TYPE_INT:
		return {}

	var safe_object_id := int(object_id)

	if safe_object_id < 0:
		return {}

	return WorldData.get_city_object_by_id(safe_object_id)

func get_city_object_display_name(city_object: Dictionary) -> String:
	if city_object.is_empty():
		return "Unknown"

	var object_type: String = str(city_object.get("type", ""))

	return WorldData.get_city_object_display_name_for_type(object_type)

func get_city_object_world_rect(city_object: Dictionary) -> Rect2:
	if city_object.is_empty():
		return Rect2()

	if not city_object.has("top_left") or not city_object.has("size"):
		return Rect2()

	var top_left: Vector2i = city_object["top_left"]
	var size_tiles: Vector2i = city_object["size"]

	return Rect2(
		Vector2(
			float(top_left.x * city_tile_size),
			float(top_left.y * city_tile_size)
		),
		Vector2(
			float(size_tiles.x * city_tile_size),
			float(size_tiles.y * city_tile_size)
		)
	)

func handle_road_left_mouse_pressed() -> void:
	if road_preview_tiles.size() > 0 and not is_road_dragging:
		confirm_road_preview()
		return

	start_road_drag_selection()

func handle_road_left_mouse_released() -> void:
	if not is_road_dragging:
		return

	is_road_dragging = false

	print("Road preview ready. Left-click again to confirm, or right-click to cancel.")

func start_road_drag_selection() -> void:
	var start_tile := get_city_tile_from_mouse()

	if start_tile == Vector2i(-1, -1):
		return

	is_road_dragging = true
	road_drag_start_tile = start_tile
	road_drag_current_tile = start_tile

	rebuild_road_preview_rectangle(road_drag_start_tile, road_drag_current_tile)

	queue_redraw()

func update_road_drag_selection() -> void:
	if not is_road_dragging:
		return

	var current_tile := get_city_tile_from_mouse()

	if current_tile == Vector2i(-1, -1):
		return

	if current_tile == road_drag_current_tile:
		return

	road_drag_current_tile = current_tile

	rebuild_road_preview_rectangle(road_drag_start_tile, road_drag_current_tile)

	queue_redraw()

func rebuild_road_preview_rectangle(start_tile: Vector2i, end_tile: Vector2i) -> void:
	road_preview_tiles.clear()
	road_preview_lookup.clear()

	if start_tile == Vector2i(-1, -1) or end_tile == Vector2i(-1, -1):
		return

	var min_x: int = min(start_tile.x, end_tile.x)
	var max_x: int = max(start_tile.x, end_tile.x)
	var min_y: int = min(start_tile.y, end_tile.y)
	var max_y: int = max(start_tile.y, end_tile.y)

	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var tile_position := Vector2i(x, y)

			if road_preview_lookup.has(tile_position):
				continue

			if not WorldData.can_place_city_road_tile(city_world, tile_position):
				continue

			road_preview_lookup[tile_position] = true
			road_preview_tiles.append(tile_position)

func add_road_preview_tile(tile_position: Vector2i) -> void:
	if road_preview_lookup.has(tile_position):
		return

	if not WorldData.can_place_city_road_tile(city_world, tile_position):
		return

	road_preview_lookup[tile_position] = true
	road_preview_tiles.append(tile_position)

func get_city_tile_from_mouse() -> Vector2i:
	if city_world == null:
		return Vector2i(-1, -1)

	var mouse_world_position: Vector2 = get_global_mouse_position()

	var tile_position := Vector2i(
		int(floor(mouse_world_position.x / float(city_tile_size))),
		int(floor(mouse_world_position.y / float(city_tile_size)))
	)

	if tile_position.x < 0 or tile_position.y < 0:
		return Vector2i(-1, -1)

	if tile_position.x >= city_world.width or tile_position.y >= city_world.height:
		return Vector2i(-1, -1)

	return tile_position

func confirm_road_preview() -> void:
	if road_preview_tiles.is_empty():
		print("No road tiles selected.")
		return

	var placed_tile_count := road_preview_tiles.size()
	var road_object := WorldData.add_city_road_object(road_preview_tiles, "player")

	if road_object.is_empty():
		print("No valid road tiles could be placed.")
		road_preview_tiles.clear()
		road_preview_lookup.clear()
		queue_redraw()
		return

	print("Placed road with ", placed_tile_count, " tiles.")

	is_road_placement_active = true
	is_road_dragging = false
	road_preview_tiles.clear()
	road_preview_lookup.clear()
	road_drag_start_tile = Vector2i(-1, -1)
	road_drag_current_tile = Vector2i(-1, -1)

	if build_option_button != null:
		build_option_button.visible = true

	if road_cursor_icon != null:
		road_cursor_icon.visible = true
		update_road_cursor_icon_position()

	set_road_option_selected(true)

	queue_redraw()

func setup_city_texture_cache() -> void:
	city_texture_cache.setup(
		self,
		"City",
		16,
		Callable(self, "get_city_tile_color_for_mode"),
		Callable(self, "get_all_city_view_modes"),
		Callable(self, "get_city_map_mode_name"),
		Callable(self, "has_valid_saved_city_map_texture_cache"),
		Callable(self, "get_saved_city_map_texture_cache"),
		Callable(self, "store_saved_city_map_texture_cache")
	)


func has_valid_saved_city_map_texture_cache(source_world: WorldData) -> bool:
	return WorldData.has_valid_city_map_texture_cache(source_world, city_seed)


func get_saved_city_map_texture_cache() -> Dictionary:
	return WorldData.get_city_map_texture_cache()


func store_saved_city_map_texture_cache(source_world: WorldData, texture_cache: Dictionary) -> void:
	WorldData.store_city_map_texture_cache(source_world, city_seed, texture_cache)

func rebuild_city_terrain_texture() -> void:
	if city_texture_cache == null:
		setup_city_texture_cache()

	city_terrain_texture = city_texture_cache.rebuild(city_world, city_view_mode)


func ensure_city_map_texture_for_mode(mode: int) -> void:
	if city_texture_cache == null:
		setup_city_texture_cache()

	city_texture_cache.ensure_texture_for_mode(city_world, mode)


func rebuild_all_city_map_mode_textures() -> void:
	if city_texture_cache == null:
		setup_city_texture_cache()

	city_texture_cache.rebuild_all(city_world)


func build_city_map_mode_texture(mode: int) -> ImageTexture:
	if city_texture_cache == null:
		setup_city_texture_cache()

	return city_texture_cache.build_texture_for_mode(city_world, mode)


func apply_cached_city_map_mode_texture() -> void:
	if city_texture_cache == null:
		setup_city_texture_cache()

	city_terrain_texture = city_texture_cache.get_texture_for_mode(city_world, city_view_mode)


func start_city_texture_warmup() -> void:
	if city_texture_cache == null:
		setup_city_texture_cache()

	city_texture_cache.start_warmup(city_world)

func _draw() -> void:
	if city_world == null:
		return

	if city_terrain_texture != null:
		draw_texture_rect(
			city_terrain_texture,
			Rect2(
				0.0,
				0.0,
				float(city_world.width * city_tile_size),
				float(city_world.height * city_tile_size)
			),
			false
		)

	draw_city_objects()
	draw_city_roads()
	draw_selected_city_object_highlight()
	draw_hovered_city_tile_highlight()
	draw_city_object_debug_names()
	draw_active_city_object_placement_preview()
	draw_road_preview()


func draw_city_object_debug_names() -> void:
	if not WorldData.debug_mode_enabled:
		return

	var font: Font = ThemeDB.fallback_font

	if font == null:
		return

	var pixels_per_world_unit := get_debug_pixels_per_world_unit()

	if pixels_per_world_unit <= 0.0:
		return

	var world_units_per_screen_pixel := 1.0 / pixels_per_world_unit

	for city_object in WorldData.city_objects:
		if city_object.is_empty():
			continue

		var object_type: String = str(city_object.get("type", ""))

		if object_type == WorldData.CITY_OBJECT_ROAD:
			continue

		var rect: Rect2 = get_city_object_world_rect(city_object)

		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue

		var object_name := get_city_object_display_name(city_object)

		if object_name == "":
			continue

		var label_center := get_city_object_debug_label_center(city_object, rect)
		var object_screen_size := rect.size * pixels_per_world_unit

		draw_centered_city_object_debug_name(
			label_center,
			object_screen_size,
			object_name,
			font,
			world_units_per_screen_pixel
		)

func draw_centered_city_object_debug_name(
	label_center: Vector2,
	object_screen_size: Vector2,
	object_name: String,
	font: Font,
	world_units_per_screen_pixel: float
) -> void:
	var font_size := get_debug_city_object_name_font_size(
		object_name,
		object_screen_size,
		font
	)

	if font_size < DEBUG_CITY_OBJECT_NAME_MIN_FONT_SIZE:
		return

	var text_size := font.get_string_size(
		object_name,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size
	)

	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)

	var background_rect := Rect2(
		-text_size * 0.5 - DEBUG_CITY_OBJECT_NAME_PADDING,
		text_size + DEBUG_CITY_OBJECT_NAME_PADDING * 2.0
	)

	var text_position := Vector2(
		-text_size.x * 0.5,
		(ascent - descent) * 0.5
	)

	draw_set_transform(
		label_center,
		0.0,
		Vector2(world_units_per_screen_pixel, world_units_per_screen_pixel)
	)

	draw_rect(
		background_rect,
		DEBUG_CITY_OBJECT_NAME_BACKGROUND_COLOR,
		true
	)

	draw_string(
		font,
		text_position + Vector2(1.0, 1.0),
		object_name,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		DEBUG_CITY_OBJECT_NAME_SHADOW_COLOR
	)

	draw_string(
		font,
		text_position,
		object_name,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		DEBUG_CITY_OBJECT_NAME_TEXT_COLOR
	)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func get_debug_pixels_per_world_unit() -> float:
	var canvas_transform := get_canvas_transform()
	var canvas_scale := canvas_transform.get_scale()

	var x_scale: float = abs(canvas_scale.x)
	var y_scale: float = abs(canvas_scale.y)

	if x_scale <= 0.0 or y_scale <= 0.0:
		return 1.0

	return (x_scale + y_scale) * 0.5


func get_debug_city_object_name_font_size(
	object_name: String,
	object_screen_size: Vector2,
	font: Font
) -> int:
	var target_font_size := DEBUG_CITY_OBJECT_NAME_TARGET_FONT_SIZE

	var text_size := font.get_string_size(
		object_name,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		target_font_size
	)

	var max_label_size := Vector2(
		object_screen_size.x * DEBUG_CITY_OBJECT_NAME_MAX_WIDTH_RATIO,
		object_screen_size.y * DEBUG_CITY_OBJECT_NAME_MAX_HEIGHT_RATIO
	)

	var padded_text_size := text_size + DEBUG_CITY_OBJECT_NAME_PADDING * 2.0

	if padded_text_size.x <= 0.0 or padded_text_size.y <= 0.0:
		return target_font_size

	var width_fit := max_label_size.x / padded_text_size.x
	var height_fit := max_label_size.y / padded_text_size.y
	var fit_scale: float = min(1.0, width_fit, height_fit)

	var fitted_font_size := int(floor(float(target_font_size) * fit_scale))

	if fitted_font_size < DEBUG_CITY_OBJECT_NAME_MIN_FONT_SIZE:
		return 0

	return fitted_font_size


func get_city_object_debug_label_center(city_object: Dictionary, fallback_rect: Rect2) -> Vector2:
	var footprint_tiles := get_city_object_debug_footprint_tiles(city_object)

	if not footprint_tiles.is_empty():
		var total := Vector2.ZERO
		var count := 0

		for tile_value in footprint_tiles:
			if tile_value is Vector2i:
				var tile: Vector2i = tile_value
				total += Vector2(
					(float(tile.x) + 0.5) * float(city_tile_size),
					(float(tile.y) + 0.5) * float(city_tile_size)
				)
				count += 1

		if count > 0:
			return total / float(count)

	return fallback_rect.position + fallback_rect.size * 0.5


func get_city_object_debug_footprint_tiles(city_object: Dictionary) -> Array:
	if city_object.has("footprint_tiles"):
		return city_object["footprint_tiles"]

	if city_object.has("tiles"):
		return city_object["tiles"]

	return []

func make_city_object_visual_style(
	frame_color: Color,
	fill_color: Color,
	frame_thickness: float
) -> Dictionary:
	return {
		"frame_color": frame_color,
		"fill_color": fill_color,
		"frame_thickness": frame_thickness
	}


func get_city_object_visual_style(object_type: String) -> Dictionary:
	return WorldData.get_city_object_visual_style_for_type(object_type)

func with_alpha_multiplier(color: Color, alpha_multiplier: float) -> Color:
	return Color(
		color.r,
		color.g,
		color.b,
		color.a * alpha_multiplier
	)


func draw_city_object_visual(
	city_object: Dictionary,
	alpha_multiplier: float = 1.0,
	is_valid_preview: bool = true
) -> void:
	if city_object.is_empty():
		return

	var object_type: String = str(city_object.get("type", ""))

	if object_type == WorldData.CITY_OBJECT_ROAD:
		return

	var rect: Rect2 = get_city_object_world_rect(city_object)

	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var style := get_city_object_visual_style(object_type)

	var frame_color: Color = style["frame_color"]
	var fill_color: Color = style["fill_color"]
	var frame_thickness: float = float(style["frame_thickness"])

	if not is_valid_preview:
		frame_color = Color(1.0, 0.0, 0.0, 0.95)
		fill_color = Color(1.0, 0.05, 0.05, 0.35)

	frame_color = with_alpha_multiplier(frame_color, alpha_multiplier)
	fill_color = with_alpha_multiplier(fill_color, alpha_multiplier)

	draw_framed_city_object_rect(
		rect,
		frame_color,
		fill_color,
		frame_thickness
	)


func draw_city_objects() -> void:
	for city_object in WorldData.city_objects:
		if city_object.is_empty():
			continue

		var object_type: String = str(city_object.get("type", ""))

		if object_type == WorldData.CITY_OBJECT_ROAD:
			continue

		draw_city_object_visual(
			city_object,
			1.0,
			true
		)

func start_city_object_placement(
	object_type: String,
	size_tiles: Vector2i,
	object_owner: String = "player",
	repeat_after_place: bool = false
) -> void:
	active_city_object_placement = {
		"type": object_type,
		"size": size_tiles,
		"owner": object_owner,
		"repeat_after_place": repeat_after_place
	}

func clear_city_object_placement() -> void:
	active_city_object_placement.clear()


func has_active_city_object_placement() -> bool:
	return not active_city_object_placement.is_empty()


func get_city_object_top_left_tile_from_mouse(size_tiles: Vector2i) -> Vector2i:
	if city_world == null:
		return Vector2i(-1, -1)

	if size_tiles.x <= 0 or size_tiles.y <= 0:
		return Vector2i(-1, -1)

	var center_tile := get_city_tile_under_mouse()

	if center_tile == Vector2i(-1, -1):
		return Vector2i(-1, -1)

	var top_left := Vector2i(
		center_tile.x - int(size_tiles.x / 2),
		center_tile.y - int(size_tiles.y / 2)
	)

	top_left.x = clamp(top_left.x, 0, city_world.width - size_tiles.x)
	top_left.y = clamp(top_left.y, 0, city_world.height - size_tiles.y)

	return top_left


func get_active_city_object_placement_preview() -> Dictionary:
	if not has_active_city_object_placement():
		return {}

	var size_tiles: Vector2i = active_city_object_placement.get("size", Vector2i.ZERO)
	var top_left := get_city_object_top_left_tile_from_mouse(size_tiles)

	if top_left == Vector2i(-1, -1):
		return {}

	return {
		"type": str(active_city_object_placement.get("type", "")),
		"top_left": top_left,
		"size": size_tiles,
		"owner": str(active_city_object_placement.get("owner", "player"))
	}

func get_cached_workplace_zone_overlay(
	city_object: Dictionary,
	preview_mode: bool
) -> Dictionary:
	var object_id := int(city_object.get("id", -1))
	var object_type := str(city_object.get("type", ""))
	var top_left: Vector2i = city_object.get(
		"top_left",
		Vector2i(-1, -1)
	)
	var size_tiles: Vector2i = city_object.get(
		"size",
		Vector2i.ZERO
	)
	var footprint_tiles := (
		WorldData.get_city_object_footprint_tiles(
			city_object
		)
	)
	var footprint_hash_value := int(
		hash(footprint_tiles)
	)
	var tile_data_version := -1

	if city_world != null:
		tile_data_version = city_world.tile_data_version

	var active_cache: Dictionary

	if preview_mode:
		active_cache = workplace_zone_preview_render_cache
	else:
		active_cache = selected_workplace_zone_render_cache

	if workplace_zone_render_cache_matches(
		active_cache,
		preview_mode,
		object_id,
		object_type,
		top_left,
		size_tiles,
		footprint_hash_value,
		tile_data_version
	):
		return active_cache

	var new_cache := {
		"preview_mode": preview_mode,
		"object_id": object_id,
		"object_type": object_type,
		"top_left": top_left,
		"size": size_tiles,
		"footprint_hash": footprint_hash_value,
		"tile_data_version": tile_data_version,
		"has_zone": false,
		"texture": null,
		"world_rect": Rect2()
	}

	var source_evaluation := (
		WorkplaceProductionSystem.get_resource_source_evaluation(
			city_object,
			city_world
		)
	)

	if bool(
		source_evaluation.get(
			"uses_environmental_source",
			false
		)
	):
		new_cache["has_zone"] = true

		var texture_data := (
			build_workplace_zone_overlay_texture(
				source_evaluation,
				preview_mode
			)
		)

		if not texture_data.is_empty():
			new_cache["texture"] = texture_data.get(
				"texture",
				null
			)
			new_cache["world_rect"] = texture_data.get(
				"world_rect",
				Rect2()
			)

	if preview_mode:
		workplace_zone_preview_render_cache = new_cache
	else:
		selected_workplace_zone_render_cache = new_cache

	return new_cache


func workplace_zone_render_cache_matches(
	render_cache: Dictionary,
	preview_mode: bool,
	object_id: int,
	object_type: String,
	top_left: Vector2i,
	size_tiles: Vector2i,
	footprint_hash_value: int,
	tile_data_version: int
) -> bool:
	if render_cache.is_empty():
		return false

	return (
		bool(render_cache.get("preview_mode", false))
		== preview_mode
		and int(render_cache.get("object_id", -2))
		== object_id
		and str(render_cache.get("object_type", ""))
		== object_type
		and render_cache.get(
			"top_left",
			Vector2i(-2, -2)
		)
		== top_left
		and render_cache.get(
			"size",
			Vector2i.ZERO
		)
		== size_tiles
		and int(render_cache.get("footprint_hash", -1))
		== footprint_hash_value
		and int(render_cache.get("tile_data_version", -2))
		== tile_data_version
	)


func build_workplace_zone_overlay_texture(
	source_evaluation: Dictionary,
	preview_mode: bool
) -> Dictionary:
	var zone_tiles: Array = source_evaluation.get(
		"zone_tiles",
		[]
	)

	if zone_tiles.is_empty():
		return {}

	var has_bounds := false
	var minimum_tile := Vector2i.ZERO
	var maximum_tile := Vector2i.ZERO

	for raw_zone_tile in zone_tiles:
		if not raw_zone_tile is Vector2i:
			continue

		var zone_tile: Vector2i = raw_zone_tile

		if not has_bounds:
			minimum_tile = zone_tile
			maximum_tile = zone_tile
			has_bounds = true
			continue

		minimum_tile.x = mini(
			minimum_tile.x,
			zone_tile.x
		)
		minimum_tile.y = mini(
			minimum_tile.y,
			zone_tile.y
		)
		maximum_tile.x = maxi(
			maximum_tile.x,
			zone_tile.x
		)
		maximum_tile.y = maxi(
			maximum_tile.y,
			zone_tile.y
		)

	if not has_bounds:
		return {}

	var width_tiles := (
		maximum_tile.x - minimum_tile.x + 1
	)
	var height_tiles := (
		maximum_tile.y - minimum_tile.y + 1
	)
	var maximum_dimension_tiles := maxi(
		width_tiles,
		height_tiles
	)
	var pixels_per_tile := clampi(
		int(
			floor(
				float(
					WORKPLACE_ZONE_TEXTURE_MAXIMUM_DIMENSION
				)
				/ float(maximum_dimension_tiles)
			)
		),
		1,
		WORKPLACE_ZONE_TEXTURE_TARGET_PIXELS_PER_TILE
	)
	var image_width := width_tiles * pixels_per_tile
	var image_height := height_tiles * pixels_per_tile
	var overlay_image := Image.create(
		image_width,
		image_height,
		false,
		Image.FORMAT_RGBA8
	)

	overlay_image.fill(
		Color(0.0, 0.0, 0.0, 0.0)
	)

	var resource_tile_lookup: Dictionary = (
		source_evaluation.get(
			"resource_tile_lookup",
			{}
		)
	)

	if preview_mode:
		for raw_zone_tile in zone_tiles:
			if not raw_zone_tile is Vector2i:
				continue

			var zone_tile: Vector2i = raw_zone_tile

			paint_workplace_zone_preview_tile(
				overlay_image,
				zone_tile,
				minimum_tile,
				pixels_per_tile,
				resource_tile_lookup.has(zone_tile)
			)
	else:
		var resource_tiles: Array = source_evaluation.get(
			"resource_tiles",
			[]
		)

		for raw_resource_tile in resource_tiles:
			if not raw_resource_tile is Vector2i:
				continue

			var resource_tile: Vector2i = (
				raw_resource_tile
			)
			var resource_rect := (
				get_workplace_zone_texture_tile_rect(
					resource_tile,
					minimum_tile,
					pixels_per_tile
				)
			)

			overlay_image.fill_rect(
				resource_rect,
				WORKPLACE_ZONE_SELECTED_RESOURCE_COLOR
			)

		var zone_tile_lookup: Dictionary = (
			source_evaluation.get(
				"zone_tile_lookup",
				{}
			)
		)

		for raw_zone_tile in zone_tiles:
			if not raw_zone_tile is Vector2i:
				continue

			var zone_tile: Vector2i = raw_zone_tile
			var tile_rect := (
				get_workplace_zone_texture_tile_rect(
					zone_tile,
					minimum_tile,
					pixels_per_tile
				)
			)

			paint_workplace_zone_texture_border(
				overlay_image,
				tile_rect,
				WORKPLACE_ZONE_SELECTED_BORDER_COLOR,
				not zone_tile_lookup.has(
					zone_tile + Vector2i(0, -1)
				),
				not zone_tile_lookup.has(
					zone_tile + Vector2i(0, 1)
				),
				not zone_tile_lookup.has(
					zone_tile + Vector2i(-1, 0)
				),
				not zone_tile_lookup.has(
					zone_tile + Vector2i(1, 0)
				)
			)

	var overlay_texture := ImageTexture.create_from_image(
		overlay_image
	)
	var world_rect := Rect2(
		Vector2(
			float(minimum_tile.x * city_tile_size),
			float(minimum_tile.y * city_tile_size)
		),
		Vector2(
			float(width_tiles * city_tile_size),
			float(height_tiles * city_tile_size)
		)
	)

	return {
		"texture": overlay_texture,
		"world_rect": world_rect
	}


func get_workplace_zone_texture_tile_rect(
	tile_position: Vector2i,
	minimum_tile: Vector2i,
	pixels_per_tile: int
) -> Rect2i:
	return Rect2i(
		(tile_position.x - minimum_tile.x)
			* pixels_per_tile,
		(tile_position.y - minimum_tile.y)
			* pixels_per_tile,
		pixels_per_tile,
		pixels_per_tile
	)


func paint_workplace_zone_preview_tile(
	overlay_image: Image,
	tile_position: Vector2i,
	minimum_tile: Vector2i,
	pixels_per_tile: int,
	has_resource: bool
) -> void:
	var tile_rect := (
		get_workplace_zone_texture_tile_rect(
			tile_position,
			minimum_tile,
			pixels_per_tile
		)
	)
	var fill_color := (
		WORKPLACE_ZONE_PREVIEW_RED_FILL_COLOR
	)
	var border_color := (
		WORKPLACE_ZONE_PREVIEW_RED_BORDER_COLOR
	)

	if has_resource:
		fill_color = (
			WORKPLACE_ZONE_PREVIEW_MAGENTA_FILL_COLOR
		)
		border_color = (
			WORKPLACE_ZONE_PREVIEW_MAGENTA_BORDER_COLOR
		)

	overlay_image.fill_rect(
		tile_rect,
		fill_color
	)

	paint_workplace_zone_texture_border(
		overlay_image,
		tile_rect,
		border_color,
		true,
		true,
		true,
		true
	)


func paint_workplace_zone_texture_border(
	overlay_image: Image,
	tile_rect: Rect2i,
	border_color: Color,
	draw_top: bool,
	draw_bottom: bool,
	draw_left: bool,
	draw_right: bool
) -> void:
	var border_width := clampi(
		WORKPLACE_ZONE_TEXTURE_BORDER_PIXELS,
		1,
		mini(tile_rect.size.x, tile_rect.size.y)
	)

	if draw_top:
		overlay_image.fill_rect(
			Rect2i(
				tile_rect.position,
				Vector2i(
					tile_rect.size.x,
					border_width
				)
			),
			border_color
		)

	if draw_bottom:
		overlay_image.fill_rect(
			Rect2i(
				Vector2i(
					tile_rect.position.x,
					tile_rect.position.y
						+ tile_rect.size.y
						- border_width
				),
				Vector2i(
					tile_rect.size.x,
					border_width
				)
			),
			border_color
		)

	if draw_left:
		overlay_image.fill_rect(
			Rect2i(
				tile_rect.position,
				Vector2i(
					border_width,
					tile_rect.size.y
				)
			),
			border_color
		)

	if draw_right:
		overlay_image.fill_rect(
			Rect2i(
				Vector2i(
					tile_rect.position.x
						+ tile_rect.size.x
						- border_width,
					tile_rect.position.y
				),
				Vector2i(
					border_width,
					tile_rect.size.y
				)
			),
			border_color
		)


func draw_cached_workplace_zone_overlay(
	render_cache: Dictionary
) -> void:
	var raw_texture = render_cache.get(
		"texture",
		null
	)

	if not raw_texture is Texture2D:
		return

	var overlay_texture := raw_texture as Texture2D
	var world_rect: Rect2 = render_cache.get(
		"world_rect",
		Rect2()
	)

	if (
		world_rect.size.x <= 0.0
		or world_rect.size.y <= 0.0
	):
		return

	draw_texture_rect(
		overlay_texture,
		world_rect,
		false
	)


func draw_workplace_resource_zone_preview(
	preview_object: Dictionary
) -> bool:
	var render_cache := get_cached_workplace_zone_overlay(
		preview_object,
		true
	)

	if not bool(render_cache.get("has_zone", false)):
		return false

	draw_cached_workplace_zone_overlay(
		render_cache
	)

	return true


func draw_selected_workplace_resource_zone(
	city_object: Dictionary
) -> bool:
	var render_cache := get_cached_workplace_zone_overlay(
		city_object,
		false
	)

	if not bool(render_cache.get("has_zone", false)):
		return false

	draw_cached_workplace_zone_overlay(
		render_cache
	)

	return true


func draw_city_object_placement_outline(
	preview_object: Dictionary,
	can_place: bool
) -> void:
	var object_rect := get_city_object_world_rect(
		preview_object
	)

	if (
		object_rect.size.x <= 0.0
		or object_rect.size.y <= 0.0
	):
		return

	var border_color := (
		WORKPLACE_ZONE_PREVIEW_RED_BORDER_COLOR
	)

	if can_place:
		var object_type := str(
			preview_object.get("type", "")
		)
		var style := get_city_object_visual_style(
			object_type
		)
		var frame_color: Color = style["frame_color"]

		border_color = Color(
			frame_color.r,
			frame_color.g,
			frame_color.b,
			WORKPLACE_ZONE_PREVIEW_MAGENTA_BORDER_COLOR.a
		)

	draw_screen_constant_inset_rect_border(
		object_rect,
		border_color,
		0.0,
		2.0
	)

func draw_active_city_object_placement_preview() -> void:
	var preview_object := (
		get_active_city_object_placement_preview()
	)

	if preview_object.is_empty():
		return

	var top_left: Vector2i = preview_object["top_left"]
	var size_tiles: Vector2i = preview_object["size"]

	var can_place := WorldData.can_place_city_object(
		city_world,
		top_left,
		size_tiles
	)

	if draw_workplace_resource_zone_preview(
		preview_object
	):
		# The cached zone texture supplies the transparent footprint.
		# Only the building outline is added, preventing stacked opacity.
		draw_city_object_placement_outline(
			preview_object,
			can_place
		)
		return

	draw_city_object_visual(
		preview_object,
		0.45,
		can_place
	)

func get_screen_constant_world_width(pixel_width: float) -> float:
	var active_camera := get_viewport().get_camera_2d()

	if active_camera == null:
		return pixel_width

	var zoom_x: float = maxf(active_camera.zoom.x, 0.001)

	return pixel_width / zoom_x

func draw_screen_constant_inset_rect_border(
	rect: Rect2,
	border_color: Color,
	inset_amount: float,
	border_width_pixels: float
) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var border_width: float = get_screen_constant_world_width(border_width_pixels)

	var max_x_inset: float = maxf(0.0, rect.size.x * 0.5 - 0.01)
	var max_y_inset: float = maxf(0.0, rect.size.y * 0.5 - 0.01)
	var safe_inset: float = minf(inset_amount, minf(max_x_inset, max_y_inset))

	var max_x_width: float = maxf(0.01, rect.size.x - safe_inset * 2.0)
	var max_y_width: float = maxf(0.01, rect.size.y - safe_inset * 2.0)
	var safe_width: float = minf(border_width, minf(max_x_width, max_y_width))

	var inner := rect.grow(-safe_inset)

	draw_rect(
		Rect2(inner.position, Vector2(inner.size.x, safe_width)),
		border_color,
		true
	)

	draw_rect(
		Rect2(
			Vector2(inner.position.x, inner.position.y + inner.size.y - safe_width),
			Vector2(inner.size.x, safe_width)
		),
		border_color,
		true
	)

	draw_rect(
		Rect2(inner.position, Vector2(safe_width, inner.size.y)),
		border_color,
		true
	)

	draw_rect(
		Rect2(
			Vector2(inner.position.x + inner.size.x - safe_width, inner.position.y),
			Vector2(safe_width, inner.size.y)
		),
		border_color,
		true
	)

func draw_selected_city_object_highlight() -> void:
	if selected_city_object_id == null:
		return

	if int(selected_city_object_id) < 0:
		return

	var city_object: Dictionary = get_city_object_by_id(
		selected_city_object_id
	)

	if not is_city_object_selectable(city_object):
		return

	if draw_selected_workplace_resource_zone(
		city_object
	):
		return

	var object_rect: Rect2 = get_city_object_world_rect(
		city_object
	)

	if (
		object_rect.size.x <= 0.0
		or object_rect.size.y <= 0.0
	):
		return

	draw_screen_constant_inset_rect_border(
		object_rect,
		SELECTED_OBJECT_HIGHLIGHT_COLOR,
		0.0,
		2.0
	)

func draw_framed_city_object_rect(
	rect: Rect2,
	frame_color: Color,
	fill_color: Color,
	frame_thickness: float
) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var max_x_thickness: float = maxf(0.01, rect.size.x * 0.5 - 0.01)
	var max_y_thickness: float = maxf(0.01, rect.size.y * 0.5 - 0.01)
	var safe_thickness: float = minf(frame_thickness, minf(max_x_thickness, max_y_thickness))

	draw_rect(rect, frame_color, true)

	var inner_rect := rect.grow(-safe_thickness)

	if inner_rect.size.x <= 0.0 or inner_rect.size.y <= 0.0:
		return

	draw_rect(inner_rect, fill_color, true)


func draw_inset_rect_border(
	rect: Rect2,
	border_color: Color,
	inset_amount: float = 0.35,
	border_width: float = 0.45
) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var safe_inset: float = min(
		inset_amount,
		max(0.0, rect.size.x * 0.5 - 0.01),
		max(0.0, rect.size.y * 0.5 - 0.01)
	)

	var safe_width: float = min(
		border_width,
		max(0.01, rect.size.x - safe_inset * 2.0),
		max(0.01, rect.size.y - safe_inset * 2.0)
	)

	var inner := rect.grow(-safe_inset)

	draw_rect(
		Rect2(inner.position, Vector2(inner.size.x, safe_width)),
		border_color,
		true
	)

	draw_rect(
		Rect2(
			Vector2(inner.position.x, inner.position.y + inner.size.y - safe_width),
			Vector2(inner.size.x, safe_width)
		),
		border_color,
		true
	)

	draw_rect(
		Rect2(inner.position, Vector2(safe_width, inner.size.y)),
		border_color,
		true
	)

	draw_rect(
		Rect2(
			Vector2(inner.position.x + inner.size.x - safe_width, inner.position.y),
			Vector2(safe_width, inner.size.y)
		),
		border_color,
		true
	)

func draw_inner_tile_fraction_rect_border(
	rect: Rect2,
	border_color: Color,
	tile_fraction: float
) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var border_width: float = float(city_tile_size) * tile_fraction

	border_width = minf(
		border_width,
		minf(rect.size.x * 0.5, rect.size.y * 0.5)
	)

	border_width = maxf(border_width, 0.01)

	draw_rect(
		Rect2(
			rect.position,
			Vector2(rect.size.x, border_width)
		),
		border_color,
		true
	)

	draw_rect(
		Rect2(
			Vector2(rect.position.x, rect.position.y + rect.size.y - border_width),
			Vector2(rect.size.x, border_width)
		),
		border_color,
		true
	)

	draw_rect(
		Rect2(
			rect.position,
			Vector2(border_width, rect.size.y)
		),
		border_color,
		true
	)

	draw_rect(
		Rect2(
			Vector2(rect.position.x + rect.size.x - border_width, rect.position.y),
			Vector2(border_width, rect.size.y)
		),
		border_color,
		true
	)

func draw_city_roads() -> void:
	for city_object in WorldData.city_objects:
		var object_type: String = str(city_object["type"])

		if object_type != WorldData.CITY_OBJECT_ROAD:
			continue

		if not city_object.has("tiles"):
			continue

		var road_tiles: Array = city_object["tiles"]

		for tile_position in road_tiles:
			if not tile_position is Vector2i:
				continue

			var rect := Rect2(
				float(tile_position.x * city_tile_size),
				float(tile_position.y * city_tile_size),
				float(city_tile_size),
				float(city_tile_size)
			)

			draw_rect(rect, Color(0.34, 0.34, 0.34, 0.95), true)

func draw_road_preview() -> void:
	if not is_road_placement_active:
		return

	if road_preview_tiles.is_empty():
		return

	var border_width: float = float(city_tile_size) * 0.06

	for tile_position in road_preview_tiles:
		if not tile_position is Vector2i:
			continue

		var rect := Rect2(
			float(tile_position.x * city_tile_size),
			float(tile_position.y * city_tile_size),
			float(city_tile_size),
			float(city_tile_size)
		)

		draw_rect(
			rect,
			CURSOR_LOOK_FILL_COLOR,
			true
		)

		draw_inner_box_border(
			rect,
			CURSOR_LOOK_BORDER_COLOR,
			border_width
		)

func draw_hovered_city_tile_highlight() -> void:
	if hovered_city_tile == Vector2i(-1, -1):
		return
		
	if is_object_selection_dragging:
		return
		
	if selected_city_object_id != null and int(selected_city_object_id) >= 0:
		return

	var rect := Rect2(
		float(hovered_city_tile.x * city_tile_size),
		float(hovered_city_tile.y * city_tile_size),
		float(city_tile_size),
		float(city_tile_size)
	)

	var border_width: float = float(city_tile_size) * 0.08

	draw_inner_box_border(
		rect,
		CURSOR_LOOK_BORDER_COLOR,
		border_width
	)

func draw_inner_box_border(rect: Rect2, border_color: Color, border_width: float) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var safe_width: float = minf(
		border_width,
		minf(rect.size.x * 0.5, rect.size.y * 0.5)
	)

	safe_width = maxf(safe_width, 0.01)

	draw_rect(
		Rect2(rect.position, Vector2(rect.size.x, safe_width)),
		border_color,
		true
	)

	draw_rect(
		Rect2(
			Vector2(rect.position.x, rect.position.y + rect.size.y - safe_width),
			Vector2(rect.size.x, safe_width)
		),
		border_color,
		true
	)

	draw_rect(
		Rect2(rect.position, Vector2(safe_width, rect.size.y)),
		border_color,
		true
	)

	draw_rect(
		Rect2(
			Vector2(rect.position.x + rect.size.x - safe_width, rect.position.y),
			Vector2(safe_width, rect.size.y)
		),
		border_color,
		true
	)


func ensure_city_foundation_object_exists() -> void:
	if not WorldData.has_player_city_foundation():
		return

	if WorldData.has_city_object_type(WorldData.CITY_OBJECT_CITY_CENTER):
		return

	var top_left: Vector2i = WorldData.player_city_foundation_top_left
	var size_tiles: Vector2i = WorldData.player_city_foundation_size

	if not WorldData.can_place_city_object(city_world, top_left, size_tiles):
		print("Could not recover city foundation object.")
		return

	var foundation_object := WorldData.add_city_object(
		WorldData.CITY_OBJECT_CITY_CENTER,
		top_left,
		size_tiles,
		"player"
	)

	print("Recovered city foundation object: ", foundation_object)

func clear_invalid_old_city_foundation_state() -> void:
	if not WorldData.player_city_founded:
		return

	if WorldData.has_player_city_foundation():
		return

	print("Clearing old city-founded state with no placed foundation.")
	WorldData.reset_player_city_state()

func get_city_tile_under_mouse() -> Vector2i:
	if city_world == null:
		return Vector2i(-1, -1)

	var mouse_world_position: Vector2 = get_global_mouse_position()

	var tile_x := int(floor(mouse_world_position.x / float(city_tile_size)))
	var tile_y := int(floor(mouse_world_position.y / float(city_tile_size)))

	if tile_x < 0 or tile_y < 0 or tile_x >= city_world.width or tile_y >= city_world.height:
		return Vector2i(-1, -1)

	return Vector2i(tile_x, tile_y)


func update_hovered_city_tile() -> void:
	previous_hovered_city_tile = hovered_city_tile
	hovered_city_tile = get_city_tile_under_mouse()

func create_city_tile_hover_visual() -> void:
	hover_tile_outline = Panel.new()
	hover_tile_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_tile_outline.visible = false

	var style := create_flat_ui_style(
		Color(0.0, 0.0, 0.0, 0.0),
		Color(0.0, 1.0, 1.0, 0.95),
		1
	)

	hover_tile_outline.add_theme_stylebox_override("panel", style)
	ui_root.add_child(hover_tile_outline)

func city_world_position_to_screen(world_position: Vector2) -> Vector2:
	if camera == null:
		return world_position

	var viewport_size: Vector2 = get_viewport_rect().size

	return Vector2(
		(world_position.x - camera.position.x) * camera.zoom.x + viewport_size.x * 0.5,
		(world_position.y - camera.position.y) * camera.zoom.y + viewport_size.y * 0.5
	)


func city_tile_rect_to_screen_rect(top_left_tile: Vector2i, size_tiles: Vector2i) -> Rect2:
	var world_top_left := Vector2(
		float(top_left_tile.x * city_tile_size),
		float(top_left_tile.y * city_tile_size)
	)

	var world_bottom_right := Vector2(
		float((top_left_tile.x + size_tiles.x) * city_tile_size),
		float((top_left_tile.y + size_tiles.y) * city_tile_size)
	)

	var screen_top_left := city_world_position_to_screen(world_top_left)
	var screen_bottom_right := city_world_position_to_screen(world_bottom_right)

	return Rect2(screen_top_left, screen_bottom_right - screen_top_left)

func update_city_hover_visual() -> void:
	if hover_tile_outline == null:
		return

	if hovered_city_tile == Vector2i(-1, -1):
		hover_tile_outline.visible = false
		return

	if has_active_city_object_placement():
		hover_tile_outline.visible = false
		return

	var rect := city_tile_rect_to_screen_rect(
		hovered_city_tile,
		Vector2i(1, 1)
	)

	hover_tile_outline.visible = true
	hover_tile_outline.position = rect.position
	hover_tile_outline.size = rect.size
	hover_tile_outline.move_to_front()

func update_debug_panel_text() -> void:
	if debug_panel_ui == null:
		return

	debug_panel_ui.refresh()
	update_citizen_debug_ui()

func create_debug_panel() -> void:
	debug_panel_ui = DebugPanel.new()
	debug_panel_ui.setup(
		self,
		120,
		debug_panel_position,
		debug_panel_padding,
		debug_panel_min_size,
		"DEBUG INFO",
		Callable(self, "get_city_debug_panel_text")
	)

	var panel_moved_callable := Callable(
		self,
		"on_debug_panel_moved"
	)

	if not debug_panel_ui.panel_moved.is_connected(
		panel_moved_callable
	):
		debug_panel_ui.panel_moved.connect(
			panel_moved_callable
		)

	create_citizen_debug_button()
	create_citizen_debug_list_panel()
	update_citizen_debug_ui()

func on_debug_panel_moved(
	_new_position: Vector2
) -> void:
	layout_citizen_debug_list_panel()

func create_citizen_debug_button() -> void:
	if debug_panel_ui == null:
		return

	if debug_panel_ui.panel == null:
		return

	debug_panel_ui.panel.mouse_filter = Control.MOUSE_FILTER_PASS

	citizen_debug_button = Button.new()
	citizen_debug_button.text = "Citizens"
	citizen_debug_button.position = CITIZEN_DEBUG_BUTTON_POSITION
	citizen_debug_button.size = CITIZEN_DEBUG_BUTTON_SIZE
	citizen_debug_button.focus_mode = Control.FOCUS_NONE
	citizen_debug_button.mouse_filter = Control.MOUSE_FILTER_STOP
	citizen_debug_button.visible = WorldData.debug_mode_enabled
	citizen_debug_button.pressed.connect(Callable(self, "toggle_citizen_debug_list_panel"))

	debug_panel_ui.panel.add_child(citizen_debug_button)


func create_citizen_debug_list_panel() -> void:
	if debug_panel_ui == null:
		return

	if debug_panel_ui.canvas_layer == null:
		return

	citizen_debug_panel = Panel.new()
	citizen_debug_panel.visible = false
	citizen_debug_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.0, 0.0, 0.0, 0.76)
	panel_style.border_color = Color(0.0, 0.55, 1.0, 0.60)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(6)
	citizen_debug_panel.add_theme_stylebox_override("panel", panel_style)

	debug_panel_ui.canvas_layer.add_child(citizen_debug_panel)

	citizen_debug_title_label = Label.new()
	citizen_debug_title_label.text = "CITIZENS"
	citizen_debug_title_label.position = Vector2(12.0, 10.0)
	citizen_debug_title_label.size = Vector2(CITIZEN_DEBUG_PANEL_SIZE.x - 24.0, 24.0)
	citizen_debug_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	citizen_debug_title_label.add_theme_color_override("font_color", Color(0.88, 0.96, 1.0, 1.0))
	citizen_debug_title_label.add_theme_font_size_override("font_size", 15)
	citizen_debug_panel.add_child(citizen_debug_title_label)

	citizen_debug_body_label = Label.new()
	citizen_debug_body_label.text = ""
	citizen_debug_body_label.position = Vector2(12.0, 42.0)
	citizen_debug_body_label.size = Vector2(CITIZEN_DEBUG_PANEL_SIZE.x - 24.0, CITIZEN_DEBUG_PANEL_SIZE.y - 54.0)
	citizen_debug_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	citizen_debug_body_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	citizen_debug_body_label.clip_text = false
	citizen_debug_body_label.add_theme_color_override("font_color", Color(0.82, 0.94, 1.0, 1.0))
	citizen_debug_body_label.add_theme_font_size_override("font_size", 12)
	citizen_debug_panel.add_child(citizen_debug_body_label)

	layout_citizen_debug_list_panel()
	update_citizen_debug_list_text()


func toggle_citizen_debug_list_panel() -> void:
	is_citizen_debug_panel_open = not is_citizen_debug_panel_open
	update_citizen_debug_ui()


func update_citizen_debug_ui() -> void:
	if citizen_debug_button != null:
		citizen_debug_button.visible = WorldData.debug_mode_enabled

		if is_citizen_debug_panel_open:
			citizen_debug_button.text = "Hide Citizens"
		else:
			citizen_debug_button.text = "Citizens"

	if citizen_debug_panel != null:
		citizen_debug_panel.visible = WorldData.debug_mode_enabled and is_citizen_debug_panel_open

		if citizen_debug_panel.visible:
			layout_citizen_debug_list_panel()
			update_citizen_debug_list_text()

func layout_citizen_debug_list_panel() -> void:
	if citizen_debug_panel == null:
		return

	var panel_position := Vector2(
		debug_panel_position.x
		+ debug_panel_min_size.x
		+ CITIZEN_DEBUG_PANEL_MARGIN,
		debug_panel_position.y
	)

	if debug_panel_ui != null and debug_panel_ui.panel != null:
		panel_position = (
			debug_panel_ui.panel.position
			+ Vector2(
				debug_panel_ui.panel.size.x
				+ CITIZEN_DEBUG_PANEL_MARGIN,
				0.0
			)
		)

	citizen_debug_panel.position = panel_position
	citizen_debug_panel.size = CITIZEN_DEBUG_PANEL_SIZE

	if citizen_debug_title_label != null:
		citizen_debug_title_label.position = Vector2(
			12.0,
			10.0
		)

		citizen_debug_title_label.size = Vector2(
			CITIZEN_DEBUG_PANEL_SIZE.x - 24.0,
			24.0
		)

	if citizen_debug_body_label != null:
		citizen_debug_body_label.position = Vector2(
			12.0,
			42.0
		)

		citizen_debug_body_label.size = Vector2(
			CITIZEN_DEBUG_PANEL_SIZE.x - 24.0,
			CITIZEN_DEBUG_PANEL_SIZE.y - 54.0
		)

func update_citizen_debug_list_text() -> void:
	if citizen_debug_body_label == null:
		return

	if not WorldData.debug_mode_enabled:
		return

	if not is_citizen_debug_panel_open:
		return

	citizen_debug_body_label.text = get_citizen_debug_list_text()

func get_simulation_debug_text() -> String:
	return (
		SimulationClock.get_debug_text()
		+ "\n"
		+ SimulationCoordinator.get_debug_text()
		+ "\n"
		+ CityStateValidator.get_summary_text()
	)

func get_citizen_debug_list_text() -> String:
	var citizens := WorldData.get_city_citizen_snapshot()

	if citizens.is_empty():
		return "No citizens."

	var lines := []

	for citizen in citizens:
		if not citizen is Dictionary:
			continue

		lines.append(get_citizen_debug_line(citizen))

	return "\n".join(lines)


func get_citizen_debug_line(citizen: Dictionary) -> String:
	var citizen_id := int(citizen.get("id", -1))
	var citizen_name := str(citizen.get("name", "Citizen " + str(citizen_id)))
	var home_text := get_citizen_debug_home_text(citizen)
	var job_text := get_citizen_debug_job_text(citizen)
	var state_text := str(citizen.get("state", "unknown"))
	var hunger := int(citizen.get("hunger", 0))
	var happiness := int(citizen.get("happiness", 0))
	var inventory_used := get_citizen_debug_inventory_used(citizen)
	var carry_capacity := int(citizen.get("carry_capacity", 0))

	return (
		"#" + str(citizen_id)
		+ " " + citizen_name
		+ " | Home: " + home_text
		+ " | Job: " + job_text
		+ " | " + state_text
		+ " | Hunger " + str(hunger)
		+ " | Happiness " + str(happiness)
		+ " | Inv " + str(inventory_used) + "/" + str(carry_capacity)
	)

func get_citizen_debug_home_text(citizen: Dictionary) -> String:
	var home_object_id := int(citizen.get("home_object_id", -1))

	if home_object_id < 0:
		return "none"

	var home_object := get_city_object_by_id(home_object_id)

	if home_object.is_empty():
		return "missing #" + str(home_object_id)

	return get_city_object_display_name(home_object) + " #" + str(home_object_id)


func get_citizen_debug_job_text(citizen: Dictionary) -> String:
	var job_object_id := int(citizen.get("job_object_id", -1))

	if job_object_id < 0:
		return "none"

	var job_object := get_city_object_by_id(job_object_id)

	if job_object.is_empty():
		return "missing #" + str(job_object_id)

	return get_city_object_display_name(job_object) + " #" + str(job_object_id)


func get_citizen_debug_inventory_used(citizen: Dictionary) -> int:
	var inventory = citizen.get("inventory", {})

	if not inventory is Dictionary:
		return 0

	var total_amount := 0

	for resource in WorldData.get_city_resource_types():
		total_amount += int(inventory.get(resource, 0))

	return total_amount

func toggle_debug_mode() -> void:
	if debug_panel_ui == null:
		return

	var is_enabled := debug_panel_ui.toggle_enabled()
	update_citizen_debug_ui()
	queue_redraw()

	if is_enabled:
		CityStateValidator.validate(true, true)
		debug_panel_ui.refresh()
		print("Debug mode: ON")
	else:
		print("Debug mode: OFF")

func get_city_debug_panel_text() -> String:
	var simulation_text := get_simulation_debug_text()

	if city_world == null:
		return (
			"DEBUG INFO\n"
			+ simulation_text
			+ "\n\n"
			+ "Scene: City\n"
			+ "City world: not generated"
		)

	var base_text := (
		"DEBUG INFO\n"
		+ simulation_text
		+ "\n\n"
		+ "Scene: City\n"
		+ "View: " + get_city_map_mode_name(city_view_mode) + "\n"
		+ "Seed: " + str(city_seed) + "\n"
		+ "\n"
	)

	if hovered_city_tile == Vector2i(-1, -1):
		return (
			base_text
			+ "Cursor: Outside city\n"
			+ "Tile: none\n"
			+ "\n"
			+ get_city_debug_selection_text()
		)

	var tile: Dictionary = city_world.get_tile(hovered_city_tile.x, hovered_city_tile.y)

	var fertility_text := "N/A"
	var fertility: float = float(tile.get("fertility", -1.0))

	if fertility >= 0.0:
		fertility_text = "%.1f" % fertility

	var city_object := WorldData.get_city_object_at_tile(hovered_city_tile)

	var object_text := get_city_debug_object_text(city_object)

	return (
		base_text
		+ "Cursor: City map\n"
		+ "Tile: " + str(hovered_city_tile.x) + ", " + str(hovered_city_tile.y) + "\n"
		+ "Terrain: " + str(tile.get("terrain", "unknown")) + "\n"
		+ "Biome: " + str(tile.get("biome", "unknown")) + "\n"
		+ "Resource: " + str(tile.get("resource", "none")) + "\n"
		+ "\n"
		+ "Elevation: " + "%.3f" % float(tile.get("elevation", 0.0)) + "\n"
		+ "Temperature: " + "%.3f" % float(tile.get("temperature", 0.0)) + "\n"
		+ "Precipitation: " + "%.3f" % float(tile.get("precipitation", 0.0)) + "\n"
		+ "Fertility: " + fertility_text + "\n"
		+ "\n"
		+ "Land: " + DebugPanel.bool_to_yes_no(bool(tile.get("is_land", false))) + "\n"
		+ "Buildable 1x1: " + DebugPanel.bool_to_yes_no(WorldData.can_place_city_object(city_world, hovered_city_tile, Vector2i(1, 1))) + "\n"
		+ "Road placeable: " + DebugPanel.bool_to_yes_no(WorldData.can_place_city_road_tile(city_world, hovered_city_tile)) + "\n"
		+ "\n"
		+ object_text
		+ "\n"
		+ get_city_debug_selection_text()
	)


func get_city_debug_object_text(city_object: Dictionary) -> String:
	if city_object.is_empty():
		return "Object under cursor: none\n"

	var object_type: String = str(city_object.get("type", "unknown"))
	var top_left: Vector2i = city_object.get("top_left", Vector2i(-1, -1))
	var size_tiles: Vector2i = city_object.get("size", Vector2i.ZERO)

	var object_id_text := "N/A"

	if city_object.has("id"):
		object_id_text = str(city_object["id"])

	var container_type := WorldData.get_city_object_container_type(city_object)

	return (
		"Object under cursor: " + get_city_object_display_name(city_object) + "\n"
		+ "Object type: " + object_type + "\n"
		+ "Object id: " + object_id_text + "\n"
		+ "Owner: " + str(city_object.get("owner", "none")) + "\n"
		+ "Container: " + get_container_type_display_name(container_type) + "\n"
		+ "Object pos: " + str(top_left.x) + ", " + str(top_left.y) + "\n"
		+ "Object size: " + str(size_tiles.x) + " x " + str(size_tiles.y) + "\n"
	)


func get_city_debug_selection_text() -> String:
	if selected_city_object_id == null or int(selected_city_object_id) < 0:
		return "Selected object: none\n"

	var selected_object := get_city_object_by_id(selected_city_object_id)

	if selected_object.is_empty():
		return "Selected object: missing\n"

	return (
		"Selected object: " + get_city_object_display_name(selected_object) + "\n"
		+ "Selected id: " + str(selected_city_object_id) + "\n"
	)
