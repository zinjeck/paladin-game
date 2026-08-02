extends Node2D

enum RegionCursorState {
	SINGLE_TILE,
	REGION_PLACE,
	REGION_SELECTED
}

var view_mode: int = MapVisuals.ViewMode.BIOME
var world_map_texture: Texture2D
var world_map_sprite: Sprite2D
var world_texture_cache := MapTextureCache.new()

const MapTextureCacheStateScript = preload(
	"res://scripts/map/visuals/MapTextureCacheState.gd"
)
const MapCameraSessionStateScript = preload(
	"res://scripts/map/MapCameraSessionState.gd"
)
const WORLD_CURSOR_LOOK_FILL_COLOR: Color = Color(1.0, 1.0, 1.0, 0.08)
const WORLD_CURSOR_LOOK_BORDER_COLOR: Color = Color(1.0, 1.0, 1.0, 0.58)
const WORLD_CURSOR_LOOK_GRID_COLOR: Color = Color(1.0, 1.0, 1.0, 0.20)
var settings := MapSettings.new()
var world: WorldData
var generator := WorldGenerator.new()
@export_file("*.tscn") var main_menu_scene_path: String = "res://scenes/MainMenu.tscn"
@export_file("*.tscn") var city_scene_path: String = "res://scenes/CityScreen.tscn"

var world_start_layer: CanvasLayer
var world_start_background: ColorRect
var world_start_color: Color = Color(0.72, 0.62, 0.45, 1.0)

var world_ui_layer: CanvasLayer
var bottom_button_bar: HBoxContainer
var back_button: Button
var generate_world_button: Button
var play_button: Button

var select_region_button: Button
var select_region_button_size: Vector2 = Vector2(190.0, 38.0)
var select_region_button_top_margin: float = 14.0

var bottom_button_size: Vector2 = Vector2(170.0, 42.0)
var bottom_button_spacing: float = 14.0
var bottom_button_bottom_margin: float = 18.0

var abyss_color: Color = Color.BLACK
var abyss_padding_pixels: float = 20000.0

var hovered_tile := Vector2i(-1, -1)
var hovered_tile_border_color := Color(0.0, 0.55, 1.0, 1.0)
var hovered_tile_border_width := 0.5
var hover_border_line: Line2D

var region_cursor_state: int = RegionCursorState.SINGLE_TILE

var region_size_tiles: int = 9
var region_half_size: int = 4
var region_ocean_ratio_limit: float = 0.90

var selected_region_center := Vector2i(-1, -1)
var selected_region_top_left := Vector2i(-1, -1)

var region_cursor_line: Line2D
var selected_region_line: Line2D
var city_name_world_label: Label

var region_cursor_valid_color := Color(1.0, 0.0, 1.0, 0.95)
var region_cursor_invalid_color := Color(1.0, 0.0, 0.0, 0.95)
var selected_region_border_color := Color(0.0, 1.0, 1.0, 1.0)

var region_cursor_border_width: float = 1.25
var selected_region_border_width: float = 2.0

var debug_panel_ui: DebugPanel
var debug_panel_position: Vector2 = Vector2.ZERO
var debug_panel_padding: Vector2 = Vector2(12.0, 10.0)
var debug_panel_min_size: Vector2 = Vector2(260.0, 80.0)

var founding_modal_overlay: Control
var founding_ui_layer: CanvasLayer
var founding_panel: PanelContainer
var founding_city_name_line_edit: LineEdit
var founding_culture_name_line_edit: LineEdit
var founding_panel_back_button: Button
var founding_panel_save_button: Button
var founding_blocked_camera: Camera2D
var founding_camera_process_was_enabled: bool = false
var founding_camera_input_was_enabled: bool = false

var founding_panel_open: bool = false
var draft_city_name: String = ""
var draft_culture_name: String = ""
var saved_city_name: String = ""
var saved_culture_name: String = ""
var has_provisional_founding_identity: bool = false

var founding_panel_size: Vector2 = Vector2(680.0, 500.0)
var founding_panel_button_size: Vector2 = Vector2(150.0, 44.0)
var founding_name_label_width: float = 155.0
var founding_customization_space_height: float = 250.0
var city_name_world_label_size: Vector2 = Vector2(480.0, 34.0)
var city_name_world_label_screen_gap: float = 8.0
var session_view_active: bool = true
var city_transition_pending: bool = false

func _ready():
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_to_group("world_renderer")

	RenderingServer.set_default_clear_color(abyss_color)

	setup_world_texture_cache()
	create_world_map_sprite()
	create_hover_border_line()
	create_region_selection_lines()
	create_city_name_world_label()
	create_debug_panel()
	connect_simulation_clock_signals()
	create_world_start_background()
	create_world_bottom_buttons()
	create_select_region_button()
	create_founding_panel()

	if WorldData.has_active_world_save():
		SimulationClock.resume_simulation()
		load_locked_world_save()
	else:
		SimulationClock.suspend_simulation()
		world = null
		print("World screen loaded. Press Generate World.")

func _process(_delta):
	update_hovered_tile()
	update_city_name_world_label_transform()

func _exit_tree() -> void:
	set_founding_camera_input_blocked(false)

	if world_texture_cache != null:
		world_texture_cache.dispose()


func set_session_view_active(is_active: bool) -> void:
	session_view_active = is_active
	visible = is_active
	process_mode = (
		Node.PROCESS_MODE_INHERIT
		if is_active
		else Node.PROCESS_MODE_DISABLED
	)
	_set_descendant_canvas_layers_visible(self, is_active)

	var world_camera: Camera2D = null

	if get_parent() != null:
		world_camera = get_parent().get_node_or_null("Camera2D") as Camera2D

	if world_camera != null:
		world_camera.enabled = is_active

		if is_active:
			world_camera.make_current()

	if is_active:
		update_debug_panel_text()


func _set_descendant_canvas_layers_visible(root: Node, is_visible: bool) -> void:
	for child in root.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = is_visible

		_set_descendant_canvas_layers_visible(child, is_visible)



func set_city_transition_pending(is_pending: bool) -> void:
	city_transition_pending = is_pending

	if play_button == null:
		return

	if is_pending:
		play_button.text = "Preparing City..."
		play_button.disabled = true
		return

	refresh_founding_ui_state()

	if WorldData.has_active_world_save():
		play_button.text = "City"


func get_game_session_controller() -> Node:
	var current: Node = self

	while current != null:
		if current.is_in_group("game_session"):
			return current

		current = current.get_parent()

	return null


func build_city_preparation_request() -> Dictionary:
	if world == null or not has_selected_region():
		return {}

	var region_tiles: Array = []

	for local_y in range(region_size_tiles):
		var row: Array = []

		for local_x in range(region_size_tiles):
			var world_x := selected_region_top_left.x + local_x
			var world_y := selected_region_top_left.y + local_y

			if not world.is_in_bounds(world_x, world_y):
				return {}

			row.append(world.get_tile(world_x, world_y).duplicate(true))

		region_tiles.append(row)

	var local_tiles_per_world_tile := (
		CityWorldGenerator.DEFAULT_LOCAL_TILES_PER_WORLD_TILE
	)
	var city_seed := CityWorldGenerator.calculate_city_seed_for_region(
		world.seed,
		selected_region_center,
		region_size_tiles
	)
	var signature := "%s:%s:%s:%s:%s:%s:%s" % [
		world.seed,
		world.tile_data_version,
		selected_region_top_left.x,
		selected_region_top_left.y,
		region_size_tiles,
		local_tiles_per_world_tile,
		city_seed,
	]

	return {
		"signature": signature,
		"region_tiles": region_tiles,
		"region_size": region_size_tiles,
		"local_tiles_per_world_tile": local_tiles_per_world_tile,
		"city_seed": city_seed,
	}


func request_city_preparation() -> void:
	var session := get_game_session_controller()

	if session == null or not session.has_method("prepare_city_view"):
		return

	var request := build_city_preparation_request()

	if request.is_empty():
		return

	session.call("prepare_city_view", request)


func cancel_city_preparation() -> void:
	var session := get_game_session_controller()

	if session != null and session.has_method("cancel_city_preparation"):
		session.call("cancel_city_preparation")

func create_world_map_sprite() -> void:
	world_map_sprite = Sprite2D.new()
	world_map_sprite.name = "WorldMapSprite"
	world_map_sprite.centered = false
	world_map_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	world_map_sprite.z_index = -100
	add_child(world_map_sprite)


func refresh_world_map_sprite() -> void:
	if world_map_sprite == null:
		return

	world_map_sprite.texture = world_map_texture
	world_map_sprite.scale = Vector2.ONE * float(settings.tile_size)
	world_map_sprite.visible = world != null and world_map_texture != null


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
	if not session_view_active:
		return

	update_debug_panel_text()

func setup_world_texture_cache() -> void:
	world_texture_cache.setup({
		"owner": self,
		"label": "World",
		"color_provider": Callable(
			self,
			"get_tile_color_for_mode"
		),
		"all_colors_provider": Callable(
			self,
			"populate_all_world_tile_colors"
		),
		"modes_provider": Callable(
			self,
			"get_all_world_view_modes"
		),
		"mode_name_provider": Callable(
			self,
			"get_world_view_mode_name_for_mode"
		),
		"has_valid_saved_cache_provider": Callable(
			self,
			"has_valid_saved_world_map_texture_cache"
		),
		"saved_cache_getter": Callable(
			self,
			"get_saved_world_map_texture_cache"
		),
		"saved_cache_storer": Callable(
			self,
			"store_saved_world_map_texture_cache"
		),
	})


func has_valid_saved_world_map_texture_cache(source_world: WorldData) -> bool:
	return MapTextureCacheStateScript.has_valid_world_cache(source_world)


func get_saved_world_map_texture_cache() -> Dictionary:
	return MapTextureCacheStateScript.get_world_cache()


func store_saved_world_map_texture_cache(source_world: WorldData, texture_cache: Dictionary) -> void:
	MapTextureCacheStateScript.store_world_cache(source_world, texture_cache)

func load_locked_world_save() -> void:
	world = WorldData.official_world
	close_founding_panel()
	clear_provisional_founding_identity()

	selected_region_center = WorldData.official_selected_region_center
	selected_region_top_left = WorldData.official_selected_region_top_left

	if WorldData.official_region_size > 0:
		region_size_tiles = WorldData.official_region_size
		region_half_size = int(region_size_tiles / 2)

	region_cursor_state = RegionCursorState.REGION_SELECTED

	if world_start_background != null:
		world_start_background.visible = false

	if select_region_button != null:
		select_region_button.visible = true

	update_selected_region_line()
	update_cursor_visuals()
	set_world_locked_ui()
	refresh_city_name_world_label()

	if has_method("update_debug_panel_text"):
		call("update_debug_panel_text")

	print("Loaded locked official world seed: ", world.seed)

	rebuild_world_map_textures()
	configure_world_camera()

func create_hover_border_line():
	hover_border_line = Line2D.new()
	hover_border_line.default_color = hovered_tile_border_color
	hover_border_line.width = hovered_tile_border_width
	hover_border_line.closed = true
	hover_border_line.visible = false
	hover_border_line.z_index = 100

	add_child(hover_border_line)

func create_region_selection_lines() -> void:
	region_cursor_line = Line2D.new()
	region_cursor_line.width = region_cursor_border_width
	region_cursor_line.default_color = region_cursor_valid_color
	region_cursor_line.closed = true
	region_cursor_line.visible = false
	region_cursor_line.z_index = 101
	add_child(region_cursor_line)

	selected_region_line = Line2D.new()
	selected_region_line.width = selected_region_border_width
	selected_region_line.default_color = selected_region_border_color
	selected_region_line.closed = true
	selected_region_line.visible = false
	selected_region_line.z_index = 102
	add_child(selected_region_line)


func create_city_name_world_label() -> void:
	city_name_world_label = Label.new()
	city_name_world_label.name = "CityNameWorldLabel"
	city_name_world_label.visible = false
	city_name_world_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	city_name_world_label.focus_mode = Control.FOCUS_NONE
	city_name_world_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	city_name_world_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	city_name_world_label.size = city_name_world_label_size
	city_name_world_label.z_index = 110

	city_name_world_label.add_theme_color_override(
		"font_color",
		Color(0.96, 0.98, 1.0, 1.0)
	)
	city_name_world_label.add_theme_color_override(
		"font_outline_color",
		Color(0.02, 0.02, 0.04, 0.98)
	)
	city_name_world_label.add_theme_constant_override("outline_size", 4)
	city_name_world_label.add_theme_font_size_override("font_size", 20)

	add_child(city_name_world_label)

func create_debug_panel() -> void:
	debug_panel_ui = DebugPanel.new()
	debug_panel_ui.setup({
		"parent": self,
		"canvas_layer_index": 100,
		"panel_position": debug_panel_position,
		"padding": debug_panel_padding,
		"minimum_size": debug_panel_min_size,
		"initial_text": "DEBUG MENU",
		"text_provider": Callable(
			self,
			"get_hovered_tile_debug_text"
		),
	})

func toggle_debug_mode() -> void:
	if debug_panel_ui == null:
		return

	var is_enabled := debug_panel_ui.toggle_enabled()

	if is_enabled:
		print("Debug mode: ON")
	else:
		print("Debug mode: OFF")

func update_debug_panel_text() -> void:
	if debug_panel_ui == null:
		return

	debug_panel_ui.refresh()

func get_hovered_tile_debug_text() -> String:
	var simulation_text := get_simulation_debug_text()
	if world == null:
		return (
			"DEBUG MODE\n"
			+ simulation_text
			+ "\n\n"
			+ "World: not generated"
		)

	if hovered_tile.x < 0 or hovered_tile.y < 0:
		return (
			"DEBUG MENU\n"
			+ simulation_text
			+ "\n\n"
			+ "View: " + get_view_mode_name() + "\n"
			+ "Seed: " + str(world.seed) + "\n"
			+ "\n"
			+ "Cursor: Abyss\n"
			+ "Tile: none\n"
		)

	var tile: Dictionary = world.get_tile(hovered_tile.x, hovered_tile.y)

	var elevation: float = float(tile["elevation"])
	var temperature: float = float(tile["temperature"])
	var precipitation: float = float(tile["precipitation"])
	var fertility: float = float(tile["fertility"])
	var terrain: String = str(tile["terrain"])
	var biome: String = str(tile["biome"])
	var resource: String = str(tile["resource"])
	var is_land: bool = bool(tile["is_land"])
	var is_river: bool = biome == WorldData.BIOME_RIVER
	var is_coastal: bool = is_tile_coastal(hovered_tile.x, hovered_tile.y)

	var fertility_text: String = "N/A"
	if fertility >= 0.0:
		fertility_text = "%.1f" % fertility

	return (
		"DEBUG INFO\n"
		+ simulation_text
		+ "\n\n"
		+ "View: " + get_view_mode_name() + "\n"
		+ "Seed: " + str(world.seed) + "\n"
		+ "\n"
		+ "Tile: " + str(hovered_tile.x) + ", " + str(hovered_tile.y) + "\n"
		+ "Terrain: " + terrain + "\n"
		+ "Biome: " + biome + "\n"
		+ "Resource: " + resource + "\n"
		+ "\n"
		+ "Elevation: " + "%.3f" % elevation + "\n"
		+ "Temperature: " + "%.3f" % temperature + "\n"
		+ "Precipitation: " + "%.3f" % precipitation + "\n"
		+ "Fertility: " + fertility_text + "\n"
		+ "\n"
		+ "Land: " + DebugPanel.bool_to_yes_no(is_land) + "\n"
		+ "River: " + DebugPanel.bool_to_yes_no(is_river) + "\n"
		+ "Coastal: " + DebugPanel.bool_to_yes_no(is_coastal)
	)

func get_simulation_debug_text() -> String:
	return (
		SimulationClock.get_debug_text()
		+ "\n"
		+ SimulationCoordinator.get_debug_text()
	)

func get_view_mode_name() -> String:
	return MapVisuals.get_view_mode_name(view_mode)

func is_tile_coastal(tile_x: int, tile_y: int) -> bool:
	if world == null:
		return false

	var tile: Dictionary = world.get_tile(tile_x, tile_y)

	if str(tile["terrain"]) == WorldData.TERRAIN_WATER:
		return false

	var directions: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1)
	]

	for direction: Vector2i in directions:
		var neighbor_x: int = tile_x + direction.x
		var neighbor_y: int = tile_y + direction.y

		if neighbor_x < 0 or neighbor_y < 0 or neighbor_x >= world.width or neighbor_y >= world.height:
			continue

		var neighbor: Dictionary = world.get_tile(neighbor_x, neighbor_y)

		if str(neighbor["terrain"]) == WorldData.TERRAIN_WATER:
			return true

	return false

func update_hovered_tile() -> void:
	if world == null:
		hide_all_cursor_lines()
		return
	if founding_panel_open:
		if hover_border_line != null:
			hover_border_line.visible = false
		if region_cursor_line != null:
			region_cursor_line.visible = false
		return

	var new_hovered_tile: Vector2i = get_mouse_tile()

	if new_hovered_tile == hovered_tile:
		return

	hovered_tile = new_hovered_tile
	update_cursor_visuals()

	if has_method("update_debug_panel_text"):
		call("update_debug_panel_text")

func get_mouse_tile() -> Vector2i:
	var mouse_world_position: Vector2 = get_global_mouse_position()

	var tile_x: int = int(floor(mouse_world_position.x / float(settings.tile_size)))
	var tile_y: int = int(floor(mouse_world_position.y / float(settings.tile_size)))

	if tile_x < 0 or tile_y < 0:
		return Vector2i(-1, -1)

	if world != null:
		if tile_x >= world.width or tile_y >= world.height:
			return Vector2i(-1, -1)

	return Vector2i(tile_x, tile_y)

func update_hover_border_line() -> void:
	if hover_border_line == null:
		return

	if region_cursor_state == RegionCursorState.REGION_PLACE:
		hover_border_line.visible = false
		return

	if hovered_tile.x < 0 or hovered_tile.y < 0:
		hover_border_line.visible = false
		return

	var x: float = float(hovered_tile.x * settings.tile_size)
	var y: float = float(hovered_tile.y * settings.tile_size)
	var s: float = float(settings.tile_size)

	set_line_to_rect(
		hover_border_line,
		Rect2(Vector2(x, y), Vector2(s, s))
	)

	hover_border_line.default_color = hovered_tile_border_color
	hover_border_line.width = hovered_tile_border_width
	hover_border_line.visible = true

func update_cursor_visuals() -> void:
	if founding_panel_open:
		if hover_border_line != null:
			hover_border_line.visible = false
		if region_cursor_line != null:
			region_cursor_line.visible = false
		return

	if region_cursor_state == RegionCursorState.REGION_PLACE:
		if hover_border_line != null:
			hover_border_line.visible = false

		update_region_cursor_line()
	else:
		if region_cursor_line != null:
			region_cursor_line.visible = false

		update_hover_border_line()


func update_region_cursor_line() -> void:
	if region_cursor_line == null:
		return

	if hovered_tile.x < 0 or hovered_tile.y < 0:
		region_cursor_line.visible = false
		return

	var region_top_left: Vector2i = get_region_top_left_from_center(hovered_tile)
	var region_rect: Rect2 = get_region_rect(region_top_left)

	var valid_region: bool = is_region_valid(region_top_left)

	if valid_region:
		region_cursor_line.default_color = region_cursor_valid_color
	else:
		region_cursor_line.default_color = region_cursor_invalid_color

	region_cursor_line.width = region_cursor_border_width
	set_line_to_rect(region_cursor_line, region_rect)
	region_cursor_line.visible = true


func update_selected_region_line() -> void:
	if selected_region_line == null:
		return

	if selected_region_top_left.x < 0 or selected_region_top_left.y < 0:
		selected_region_line.visible = false
		refresh_city_name_world_label()
		return

	var region_rect: Rect2 = get_region_rect(selected_region_top_left)

	selected_region_line.default_color = selected_region_border_color
	selected_region_line.width = selected_region_border_width
	set_line_to_rect(selected_region_line, region_rect)
	selected_region_line.visible = true
	update_city_name_world_label_transform()


func refresh_city_name_world_label() -> void:
	if city_name_world_label == null:
		return

	var display_name := ""

	if WorldData.has_active_world_save():
		display_name = WorldData.get_official_city_name().strip_edges()
	elif has_valid_provisional_founding_identity():
		display_name = saved_city_name.strip_edges()

	city_name_world_label.text = display_name
	city_name_world_label.visible = (
		has_selected_region()
		and not display_name.is_empty()
	)

	update_city_name_world_label_transform()


func update_city_name_world_label_transform() -> void:
	if city_name_world_label == null:
		return
	if not city_name_world_label.visible:
		return
	if not has_selected_region():
		city_name_world_label.visible = false
		return

	var active_camera := get_viewport().get_camera_2d()
	var camera_zoom := Vector2.ONE

	if active_camera != null:
		camera_zoom = Vector2(
			maxf(active_camera.zoom.x, 0.001),
			maxf(active_camera.zoom.y, 0.001)
		)

	var inverse_zoom := Vector2(
		1.0 / camera_zoom.x,
		1.0 / camera_zoom.y
	)
	var region_rect := get_region_rect(selected_region_top_left)
	var scaled_label_size := city_name_world_label_size * inverse_zoom
	var scaled_gap := city_name_world_label_screen_gap * inverse_zoom.y

	city_name_world_label.size = city_name_world_label_size
	city_name_world_label.scale = inverse_zoom
	city_name_world_label.position = Vector2(
		region_rect.get_center().x - scaled_label_size.x * 0.5,
		region_rect.position.y - scaled_label_size.y - scaled_gap
	)


func hide_all_cursor_lines() -> void:
	if hover_border_line != null:
		hover_border_line.visible = false

	if region_cursor_line != null:
		region_cursor_line.visible = false

	if selected_region_line != null:
		selected_region_line.visible = false


func set_line_to_rect(line: Line2D, rect: Rect2) -> void:
	line.points = PackedVector2Array([
		rect.position,
		Vector2(rect.position.x + rect.size.x, rect.position.y),
		Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y),
		Vector2(rect.position.x, rect.position.y + rect.size.y)
	])

func get_region_top_left_from_center(center_tile: Vector2i) -> Vector2i:
	return Vector2i(
		center_tile.x - region_half_size,
		center_tile.y - region_half_size
	)


func get_region_rect(region_top_left: Vector2i) -> Rect2:
	var x: float = float(region_top_left.x * settings.tile_size)
	var y: float = float(region_top_left.y * settings.tile_size)
	var size_pixels: float = float(region_size_tiles * settings.tile_size)

	return Rect2(
		Vector2(x, y),
		Vector2(size_pixels, size_pixels)
	)


func is_region_inside_world(region_top_left: Vector2i) -> bool:
	if world == null:
		return false

	if region_top_left.x < 0 or region_top_left.y < 0:
		return false

	if region_top_left.x + region_size_tiles > world.width:
		return false

	if region_top_left.y + region_size_tiles > world.height:
		return false

	return true


func is_region_valid(region_top_left: Vector2i) -> bool:
	if not is_region_inside_world(region_top_left):
		return false

	var ocean_ratio: float = get_region_ocean_ratio(region_top_left)

	return ocean_ratio <= region_ocean_ratio_limit

func has_selected_region() -> bool:
	return selected_region_top_left.x >= 0 and selected_region_top_left.y >= 0

func get_region_ocean_ratio(region_top_left: Vector2i) -> float:
	var ocean_tiles: int = count_region_ocean_tiles(region_top_left)
	var total_tiles: int = region_size_tiles * region_size_tiles

	if total_tiles <= 0:
		return 1.0

	return float(ocean_tiles) / float(total_tiles)


func count_region_ocean_tiles(region_top_left: Vector2i) -> int:
	var ocean_tiles: int = 0

	for y_offset in range(region_size_tiles):
		for x_offset in range(region_size_tiles):
			var tile_x: int = region_top_left.x + x_offset
			var tile_y: int = region_top_left.y + y_offset

			var tile: Dictionary = world.get_tile(tile_x, tile_y)

			if is_ocean_region_tile(tile):
				ocean_tiles += 1

	return ocean_tiles


func is_ocean_region_tile(tile: Dictionary) -> bool:
	var biome: String = str(tile["biome"])

	if biome == WorldData.BIOME_OCEAN:
		return true

	return false

func _input(event):
	if founding_panel_open:
		return

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
			return

		var requested_view_mode: int = MapVisuals.get_view_mode_for_keycode(key_event.keycode)

		if requested_view_mode != MapVisuals.INVALID_VIEW_MODE:
			set_world_view_mode(requested_view_mode)
			get_viewport().set_input_as_handled()
			return

func set_world_view_mode(new_view_mode: int) -> void:
	if view_mode == new_view_mode:
		return
	if (
		world_texture_cache == null
		or not world_texture_cache.is_mode_ready(world, new_view_mode)
	):
		return

	view_mode = new_view_mode

	print("View: ", get_view_mode_name())

	apply_cached_world_map_texture()

	update_debug_panel_text()

func get_all_world_view_modes() -> Array[int]:
	return MapVisuals.get_all_view_modes()

func get_tile_color(tile: Dictionary) -> Color:
	return get_tile_color_for_mode(tile, view_mode)


func get_tile_color_for_mode(tile: Dictionary, mode: int) -> Color:
	return MapVisuals.get_tile_color_for_mode(tile, mode, 0.0)


func populate_all_world_tile_colors(
	tile: Dictionary,
	output_colors: Array[Color]
) -> void:
	MapVisuals.populate_all_tile_colors(tile, output_colors, 0.0)


func rebuild_world_map_textures() -> void:
	if world_texture_cache == null:
		setup_world_texture_cache()

	world_map_texture = world_texture_cache.rebuild(world, view_mode)
	refresh_world_map_sprite()



func apply_cached_world_map_texture() -> void:
	if world_texture_cache == null:
		setup_world_texture_cache()

	world_map_texture = world_texture_cache.get_texture_for_mode(world, view_mode)
	refresh_world_map_sprite()

func get_world_view_mode_name_for_mode(mode: int) -> String:
	return MapVisuals.get_view_mode_name(mode)

func get_biome_color(tile: Dictionary) -> Color:
	return MapVisuals.get_biome_color(tile)

func get_resource_color(resource: String) -> Color:
	return MapVisuals.get_resource_color(resource)

func create_world_bottom_buttons() -> void:
	world_ui_layer = CanvasLayer.new()
	world_ui_layer.layer = 90
	add_child(world_ui_layer)

	bottom_button_bar = HBoxContainer.new()
	bottom_button_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_button_bar.add_theme_constant_override("separation", int(bottom_button_spacing))

	var total_width: float = bottom_button_size.x * 3.0 + bottom_button_spacing * 2.0
	var total_height: float = bottom_button_size.y

	bottom_button_bar.anchor_left = 0.5
	bottom_button_bar.anchor_right = 0.5
	bottom_button_bar.anchor_top = 1.0
	bottom_button_bar.anchor_bottom = 1.0

	bottom_button_bar.offset_left = -total_width * 0.5
	bottom_button_bar.offset_right = total_width * 0.5
	bottom_button_bar.offset_top = -(total_height + bottom_button_bottom_margin)
	bottom_button_bar.offset_bottom = -bottom_button_bottom_margin

	world_ui_layer.add_child(bottom_button_bar)

	back_button = create_world_action_button(
		"Back",
		Color(1.0, 0.25, 0.25, 0.32),
		Color(1.0, 0.38, 0.38, 0.48),
		Color(1.0, 0.18, 0.18, 0.62)
	)

	generate_world_button = create_world_action_button(
		"Generate World",
		Color(0.15, 0.45, 1.0, 0.32),
		Color(0.25, 0.58, 1.0, 0.48),
		Color(0.08, 0.32, 0.85, 0.62)
	)

	play_button = create_world_action_button(
		"Play",
		Color(0.25, 1.0, 0.35, 0.32),
		Color(0.40, 1.0, 0.48, 0.48),
		Color(0.15, 0.78, 0.24, 0.62)
	)

	bottom_button_bar.add_child(back_button)
	bottom_button_bar.add_child(generate_world_button)
	bottom_button_bar.add_child(play_button)

	back_button.pressed.connect(on_back_button_pressed)
	generate_world_button.pressed.connect(on_generate_world_button_pressed)
	play_button.pressed.connect(on_play_button_pressed)
	
	set_play_button_region_ready(false)

func set_play_button_region_ready(is_ready: bool) -> void:
	if play_button == null:
		return

	play_button.disabled = not is_ready

	if is_ready:
		play_button.add_theme_stylebox_override(
			"normal",
			create_world_button_style(Color(0.25, 1.0, 0.35, 0.32))
		)
		play_button.add_theme_stylebox_override(
			"hover",
			create_world_button_style(Color(0.40, 1.0, 0.48, 0.48))
		)
		play_button.add_theme_stylebox_override(
			"pressed",
			create_world_button_style(Color(0.15, 0.78, 0.24, 0.62))
		)
		play_button.add_theme_color_override("font_color", Color.WHITE)
	else:
		var grey_style: StyleBoxFlat = create_world_button_style(Color(0.35, 0.35, 0.35, 0.30))

		play_button.add_theme_stylebox_override("normal", grey_style)
		play_button.add_theme_stylebox_override("hover", grey_style)
		play_button.add_theme_stylebox_override("pressed", grey_style)
		play_button.add_theme_stylebox_override("disabled", grey_style)

		play_button.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75, 1.0))
		play_button.add_theme_color_override("font_disabled_color", Color(0.75, 0.75, 0.75, 1.0))

func create_world_action_button(
	button_text: String,
	normal_color: Color,
	hover_color: Color,
	pressed_color: Color
) -> Button:
	var button: Button = Button.new()
	button.text = button_text
	button.custom_minimum_size = bottom_button_size
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP

	var normal_style: StyleBoxFlat = create_world_button_style(normal_color)
	var hover_style: StyleBoxFlat = create_world_button_style(hover_color)
	var pressed_style: StyleBoxFlat = create_world_button_style(pressed_color)

	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_stylebox_override("focus", normal_style)

	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_font_size_override("font_size", 18)

	return button


func create_world_button_style(background_color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = Color(1.0, 1.0, 1.0, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0

	return style


func on_back_button_pressed() -> void:
	if main_menu_scene_path.is_empty():
		push_error("Main menu scene path is empty.")
		return

	var error: Error = get_tree().change_scene_to_file(main_menu_scene_path)

	if error != OK:
		push_error("Could not load main menu scene: " + main_menu_scene_path)

func create_select_region_button() -> void:
	if world_ui_layer == null:
		return

	select_region_button = Button.new()
	select_region_button.text = "Select Region"
	select_region_button.custom_minimum_size = select_region_button_size
	select_region_button.focus_mode = Control.FOCUS_NONE
	select_region_button.mouse_filter = Control.MOUSE_FILTER_STOP
	select_region_button.visible = false

	select_region_button.anchor_left = 0.5
	select_region_button.anchor_right = 0.5
	select_region_button.anchor_top = 0.0
	select_region_button.anchor_bottom = 0.0

	select_region_button.offset_left = -select_region_button_size.x * 0.5
	select_region_button.offset_right = select_region_button_size.x * 0.5
	select_region_button.offset_top = select_region_button_top_margin
	select_region_button.offset_bottom = select_region_button_top_margin + select_region_button_size.y

	var normal_style: StyleBoxFlat = create_world_button_style(Color(0.05, 0.05, 0.08, 0.35))
	var hover_style: StyleBoxFlat = create_world_button_style(Color(0.25, 0.05, 0.35, 0.55))
	var pressed_style: StyleBoxFlat = create_world_button_style(Color(0.55, 0.0, 0.65, 0.70))

	select_region_button.add_theme_stylebox_override("normal", normal_style)
	select_region_button.add_theme_stylebox_override("hover", hover_style)
	select_region_button.add_theme_stylebox_override("pressed", pressed_style)
	select_region_button.add_theme_stylebox_override("focus", normal_style)

	select_region_button.add_theme_color_override("font_color", Color.WHITE)
	select_region_button.add_theme_color_override("font_hover_color", Color.WHITE)
	select_region_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	select_region_button.add_theme_font_size_override("font_size", 17)

	world_ui_layer.add_child(select_region_button)

	select_region_button.pressed.connect(on_select_region_button_pressed)


func create_founding_panel() -> void:
	if world_ui_layer == null:
		return

	founding_ui_layer = CanvasLayer.new()
	founding_ui_layer.name = "FoundingUILayer"
	founding_ui_layer.layer = 110
	add_child(founding_ui_layer)

	founding_modal_overlay = Control.new()
	founding_modal_overlay.name = "FoundingModalOverlay"
	founding_modal_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	founding_modal_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	founding_modal_overlay.z_index = 200
	founding_modal_overlay.visible = false
	founding_ui_layer.add_child(founding_modal_overlay)

	founding_panel = PanelContainer.new()
	founding_panel.name = "FoundingPanel"
	founding_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	founding_panel.anchor_left = 0.5
	founding_panel.anchor_right = 0.5
	founding_panel.anchor_top = 0.5
	founding_panel.anchor_bottom = 0.5
	founding_panel.offset_left = -founding_panel_size.x * 0.5
	founding_panel.offset_right = founding_panel_size.x * 0.5
	founding_panel.offset_top = -founding_panel_size.y * 0.5
	founding_panel.offset_bottom = founding_panel_size.y * 0.5
	founding_panel.add_theme_stylebox_override(
		"panel",
		create_founding_panel_style()
	)
	founding_modal_overlay.add_child(founding_panel)

	var content_margin := MarginContainer.new()
	content_margin.mouse_filter = Control.MOUSE_FILTER_PASS
	content_margin.add_theme_constant_override("margin_left", 30)
	content_margin.add_theme_constant_override("margin_right", 30)
	content_margin.add_theme_constant_override("margin_top", 26)
	content_margin.add_theme_constant_override("margin_bottom", 26)
	founding_panel.add_child(content_margin)

	var content_column := VBoxContainer.new()
	content_column.mouse_filter = Control.MOUSE_FILTER_PASS
	content_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_column.add_theme_constant_override("separation", 18)
	content_margin.add_child(content_column)

	var city_name_row := HBoxContainer.new()
	city_name_row.custom_minimum_size = Vector2(0.0, 46.0)
	city_name_row.mouse_filter = Control.MOUSE_FILTER_PASS
	city_name_row.add_theme_constant_override("separation", 18)
	content_column.add_child(city_name_row)

	city_name_row.add_child(create_founding_field_label("City Name"))
	founding_city_name_line_edit = create_founding_name_line_edit(
		"Enter a city name"
	)
	founding_city_name_line_edit.name = "FoundingCityNameLineEdit"
	city_name_row.add_child(founding_city_name_line_edit)

	var culture_name_row := HBoxContainer.new()
	culture_name_row.custom_minimum_size = Vector2(0.0, 46.0)
	culture_name_row.mouse_filter = Control.MOUSE_FILTER_PASS
	culture_name_row.add_theme_constant_override("separation", 18)
	content_column.add_child(culture_name_row)

	culture_name_row.add_child(create_founding_field_label("Culture Name"))
	founding_culture_name_line_edit = create_founding_name_line_edit(
		"Enter a culture name"
	)
	founding_culture_name_line_edit.name = "FoundingCultureNameLineEdit"
	culture_name_row.add_child(founding_culture_name_line_edit)

	var reserved_customization_space := Control.new()
	reserved_customization_space.name = "ReservedCultureCustomizationSpace"
	reserved_customization_space.custom_minimum_size = Vector2(
		0.0,
		founding_customization_space_height
	)
	reserved_customization_space.mouse_filter = Control.MOUSE_FILTER_PASS
	reserved_customization_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_column.add_child(reserved_customization_space)

	var button_row := HBoxContainer.new()
	button_row.custom_minimum_size = Vector2(0.0, founding_panel_button_size.y)
	button_row.mouse_filter = Control.MOUSE_FILTER_PASS
	content_column.add_child(button_row)

	founding_panel_back_button = create_world_action_button(
		"Back",
		Color(1.0, 0.25, 0.25, 0.32),
		Color(1.0, 0.38, 0.38, 0.48),
		Color(1.0, 0.18, 0.18, 0.62)
	)
	founding_panel_back_button.name = "FoundingPanelBackButton"
	founding_panel_back_button.custom_minimum_size = founding_panel_button_size
	founding_panel_back_button.focus_mode = Control.FOCUS_ALL
	button_row.add_child(founding_panel_back_button)

	var button_spacer := Control.new()
	button_spacer.mouse_filter = Control.MOUSE_FILTER_PASS
	button_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_row.add_child(button_spacer)

	founding_panel_save_button = create_world_action_button(
		"Save",
		Color(0.25, 1.0, 0.35, 0.32),
		Color(0.40, 1.0, 0.48, 0.48),
		Color(0.15, 0.78, 0.24, 0.62)
	)
	founding_panel_save_button.name = "FoundingPanelSaveButton"
	founding_panel_save_button.custom_minimum_size = founding_panel_button_size
	founding_panel_save_button.focus_mode = Control.FOCUS_ALL
	button_row.add_child(founding_panel_save_button)

	founding_city_name_line_edit.text_changed.connect(
		on_founding_name_text_changed
	)
	founding_culture_name_line_edit.text_changed.connect(
		on_founding_name_text_changed
	)
	founding_city_name_line_edit.text_submitted.connect(
		on_founding_name_text_submitted
	)
	founding_culture_name_line_edit.text_submitted.connect(
		on_founding_name_text_submitted
	)
	founding_panel_back_button.pressed.connect(
		on_founding_panel_back_button_pressed
	)
	founding_panel_save_button.pressed.connect(
		on_founding_panel_save_button_pressed
	)
	founding_modal_overlay.gui_input.connect(
		on_founding_modal_overlay_gui_input
	)
	founding_panel.gui_input.connect(on_founding_panel_gui_input)

	refresh_founding_ui_state()


func create_founding_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.03, 0.055, 0.94)
	style.border_color = Color(0.72, 0.78, 0.94, 0.72)
	style.set_border_width_all(2)
	style.set_corner_radius_all(9)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.72)
	style.shadow_size = 14

	return style


func create_founding_field_label(label_text: String) -> Label:
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(founding_name_label_width, 0.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 1.0))
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_color_override(
		"font_outline_color",
		Color(0.0, 0.0, 0.0, 0.85)
	)
	label.add_theme_font_size_override("font_size", 20)

	return label


func create_founding_name_line_edit(placeholder: String) -> LineEdit:
	var line_edit := LineEdit.new()
	line_edit.placeholder_text = placeholder
	line_edit.max_length = WorldData.MAX_FOUNDING_NAME_LENGTH
	line_edit.custom_minimum_size = Vector2(0.0, 46.0)
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_edit.mouse_filter = Control.MOUSE_FILTER_STOP
	line_edit.focus_mode = Control.FOCUS_ALL
	line_edit.add_theme_font_size_override("font_size", 19)
	line_edit.add_theme_color_override("font_color", Color.WHITE)
	line_edit.add_theme_color_override(
		"font_placeholder_color",
		Color(0.72, 0.74, 0.80, 0.72)
	)
	line_edit.add_theme_stylebox_override(
		"normal",
		create_founding_line_edit_style(Color(0.08, 0.09, 0.14, 0.92))
	)
	line_edit.add_theme_stylebox_override(
		"focus",
		create_founding_line_edit_style(Color(0.12, 0.10, 0.20, 0.96), true)
	)

	return line_edit


func create_founding_line_edit_style(
	background_color: Color,
	is_focused: bool = false
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = (
		Color(0.82, 0.58, 1.0, 0.95)
		if is_focused
		else Color(0.72, 0.78, 0.94, 0.62)
	)
	style.set_border_width_all(2 if is_focused else 1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0

	return style


func on_founding_name_text_changed(_new_text: String) -> void:
	if founding_city_name_line_edit == null:
		return
	if founding_culture_name_line_edit == null:
		return

	draft_city_name = founding_city_name_line_edit.text
	draft_culture_name = founding_culture_name_line_edit.text
	refresh_founding_ui_state()


func on_founding_name_text_submitted(_submitted_text: String) -> void:
	if not founding_panel_open:
		return
	if not are_founding_draft_names_valid():
		return

	on_founding_panel_save_button_pressed()


func on_founding_modal_overlay_gui_input(event: InputEvent) -> void:
	if event is InputEventMouse and founding_modal_overlay != null:
		founding_modal_overlay.accept_event()


func on_founding_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouse and founding_panel != null:
		founding_panel.accept_event()


func open_founding_panel() -> void:
	if WorldData.has_active_world_save():
		return
	if not has_selected_region():
		return
	if founding_modal_overlay == null:
		return

	if has_valid_provisional_founding_identity():
		draft_city_name = saved_city_name
		draft_culture_name = saved_culture_name

	founding_city_name_line_edit.text = draft_city_name
	founding_culture_name_line_edit.text = draft_culture_name
	founding_city_name_line_edit.caret_column = draft_city_name.length()
	founding_culture_name_line_edit.caret_column = draft_culture_name.length()

	founding_panel_open = true
	founding_modal_overlay.visible = true
	set_founding_camera_input_blocked(true)
	update_cursor_visuals()
	refresh_founding_ui_state()
	call_deferred("grab_founding_city_name_focus_if_open")


func grab_founding_city_name_focus_if_open() -> void:
	if not founding_panel_open:
		return
	if founding_city_name_line_edit == null:
		return
	if not founding_city_name_line_edit.is_inside_tree():
		return

	founding_city_name_line_edit.grab_focus()


func close_founding_panel() -> void:
	founding_panel_open = false
	set_founding_camera_input_blocked(false)

	if founding_modal_overlay != null:
		founding_modal_overlay.visible = false

	if founding_city_name_line_edit != null:
		founding_city_name_line_edit.release_focus()

	if founding_culture_name_line_edit != null:
		founding_culture_name_line_edit.release_focus()


func set_founding_camera_input_blocked(is_blocked: bool) -> void:
	if is_blocked:
		if founding_blocked_camera != null:
			return

		var active_camera := get_viewport().get_camera_2d()

		if active_camera == null:
			return

		founding_blocked_camera = active_camera
		founding_camera_process_was_enabled = active_camera.is_processing()
		founding_camera_input_was_enabled = active_camera.is_processing_input()
		active_camera.set_process(false)
		active_camera.set_process_input(false)
		return

	if founding_blocked_camera == null:
		return

	if is_instance_valid(founding_blocked_camera):
		founding_blocked_camera.set_process(
			founding_camera_process_was_enabled
		)
		founding_blocked_camera.set_process_input(
			founding_camera_input_was_enabled
		)

	founding_blocked_camera = null
	founding_camera_process_was_enabled = false
	founding_camera_input_was_enabled = false


func on_founding_panel_back_button_pressed() -> void:
	if WorldData.has_active_world_save():
		return
	if not founding_panel_open:
		return

	clear_selected_region()
	region_cursor_state = RegionCursorState.REGION_PLACE
	update_cursor_visuals()
	refresh_founding_ui_state()

	print("Founding cancelled. Region cursor restored.")


func on_founding_panel_save_button_pressed() -> void:
	if WorldData.has_active_world_save():
		return
	if not founding_panel_open:
		return

	draft_city_name = founding_city_name_line_edit.text
	draft_culture_name = founding_culture_name_line_edit.text

	if not are_founding_draft_names_valid():
		refresh_founding_ui_state()
		return

	saved_city_name = draft_city_name.strip_edges()
	saved_culture_name = draft_culture_name.strip_edges()
	draft_city_name = saved_city_name
	draft_culture_name = saved_culture_name
	has_provisional_founding_identity = true

	founding_city_name_line_edit.text = saved_city_name
	founding_culture_name_line_edit.text = saved_culture_name

	close_founding_panel()
	update_cursor_visuals()
	refresh_founding_ui_state()

	print("Founding identity saved for city: ", saved_city_name)
	request_city_preparation()


func clear_provisional_founding_identity() -> void:
	draft_city_name = ""
	draft_culture_name = ""
	saved_city_name = ""
	saved_culture_name = ""
	has_provisional_founding_identity = false

	if founding_city_name_line_edit != null:
		founding_city_name_line_edit.text = ""

	if founding_culture_name_line_edit != null:
		founding_culture_name_line_edit.text = ""


func are_founding_draft_names_valid() -> bool:
	return (
		not draft_city_name.strip_edges().is_empty()
		and not draft_culture_name.strip_edges().is_empty()
	)


func has_valid_provisional_founding_identity() -> bool:
	return (
		has_provisional_founding_identity
		and not saved_city_name.strip_edges().is_empty()
		and not saved_culture_name.strip_edges().is_empty()
	)


func is_provisional_founding_play_ready() -> bool:
	return (
		world != null
		and has_selected_region()
		and is_region_valid(selected_region_top_left)
		and not founding_panel_open
		and has_valid_provisional_founding_identity()
	)


func refresh_founding_ui_state() -> void:
	if founding_panel_save_button != null:
		founding_panel_save_button.disabled = (
			not are_founding_draft_names_valid()
		)

	if WorldData.has_active_world_save():
		set_play_button_region_ready(true)
	else:
		set_play_button_region_ready(is_provisional_founding_play_ready())

	if select_region_button != null and not WorldData.has_active_world_save():
		select_region_button.disabled = has_selected_region()

	refresh_city_name_world_label()


func on_select_region_button_pressed() -> void:
	if WorldData.has_active_world_save():
		print("Selection blocked: this save already has an official starting region.")
		return
	
	if world == null:
		return
	if has_selected_region() or founding_panel_open:
		return

	region_cursor_state = RegionCursorState.REGION_PLACE
	update_cursor_visuals()
	refresh_founding_ui_state()

	print("Region selection mode enabled.")

func on_generate_world_button_pressed() -> void:
	cancel_city_preparation()

	if WorldData.has_active_world_save():
		print("Generate blocked: this save already has an official world.")
		return
	
	hovered_tile = Vector2i(-1, -1)
	region_cursor_state = RegionCursorState.SINGLE_TILE
	clear_selected_region()

	if hover_border_line != null:
		hover_border_line.visible = false

	if region_cursor_line != null:
		region_cursor_line.visible = false

	WorldData.clear_visual_texture_caches()

	world = generator.generate_world()

	SimulationClock.start_new_game()
	SimulationCoordinator.reset_performance_statistics()

	print("Generated world seed: ", world.seed)

	if world_start_background != null:
		world_start_background.visible = false

	if select_region_button != null:
		select_region_button.visible = true

	refresh_founding_ui_state()

	if has_method("update_debug_panel_text"):
		call("update_debug_panel_text")

	rebuild_world_map_textures()
	configure_world_camera()

func on_play_button_pressed() -> void:
	if WorldData.has_active_world_save():
		change_to_city_screen()
		return

	if world == null:
		print("Play blocked: no world generated.")
		return

	if not is_provisional_founding_play_ready():
		print(
			"Play blocked: select a valid region and save both founding names first."
		)
		return

	if city_scene_path.is_empty():
		push_error("City scene path is empty.")
		return

	var current_world_scene_path := ""

	if get_tree().current_scene != null:
		current_world_scene_path = get_tree().current_scene.scene_file_path

	var lock_succeeded := WorldData.lock_world_save({
		"source_world": world,
		"region_top_left": selected_region_top_left,
		"region_center": selected_region_center,
		"region_size": region_size_tiles,
		"world_scene_path": current_world_scene_path,
		"city_scene_path": city_scene_path,
		"city_name": saved_city_name,
		"culture_name": saved_culture_name,
	})

	if not lock_succeeded:
		push_error("Could not commit the world founding identity.")
		refresh_founding_ui_state()
		return

	clear_provisional_founding_identity()
	set_world_locked_ui()
	refresh_city_name_world_label()

	print("Official world locked.")
	print("World seed: ", world.seed)
	print("Starting region center: ", selected_region_center)
	print("Starting region top-left: ", selected_region_top_left)

	change_to_city_screen()

func change_to_city_screen() -> void:
	store_current_world_camera_state()
	var session := get_game_session_controller()

	if session == null or not session.has_method("show_city_view"):
		push_error(
			"World-to-city switching requires the persistent GameSession."
		)
		return

	session.call("show_city_view", build_city_preparation_request())


func set_world_locked_ui() -> void:
	close_founding_panel()
	set_button_locked_disabled(generate_world_button)
	set_button_locked_disabled(select_region_button)

	set_play_button_region_ready(true)

	if play_button != null:
		play_button.text = "City"

	refresh_city_name_world_label()


func set_button_locked_disabled(button: Button) -> void:
	if button == null:
		return

	button.disabled = true

	var grey_style: StyleBoxFlat = create_world_button_style(Color(0.35, 0.35, 0.35, 0.30))

	button.add_theme_stylebox_override("normal", grey_style)
	button.add_theme_stylebox_override("hover", grey_style)
	button.add_theme_stylebox_override("pressed", grey_style)
	button.add_theme_stylebox_override("disabled", grey_style)
	button.add_theme_stylebox_override("focus", grey_style)

	button.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75, 1.0))
	button.add_theme_color_override("font_hover_color", Color(0.75, 0.75, 0.75, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.75, 0.75, 0.75, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(0.75, 0.75, 0.75, 1.0))

func create_world_start_background() -> void:
	world_start_layer = CanvasLayer.new()
	world_start_layer.layer = 80
	add_child(world_start_layer)

	world_start_background = ColorRect.new()
	world_start_background.color = world_start_color
	world_start_background.mouse_filter = Control.MOUSE_FILTER_IGNORE

	world_start_background.anchor_left = 0.0
	world_start_background.anchor_top = 0.0
	world_start_background.anchor_right = 1.0
	world_start_background.anchor_bottom = 1.0

	world_start_background.offset_left = 0.0
	world_start_background.offset_top = 0.0
	world_start_background.offset_right = 0.0
	world_start_background.offset_bottom = 0.0

	world_start_layer.add_child(world_start_background)

func _unhandled_input(event: InputEvent) -> void:
	if world == null:
		return
	if founding_panel_open:
		return

	if event is InputEventMouseButton and event.pressed:
		var mouse_event: InputEventMouseButton = event

		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			handle_left_mouse_click()

		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			handle_right_mouse_click()

func handle_left_mouse_click() -> void:
	if WorldData.has_active_world_save():
		return
	if founding_panel_open:
		return

	if region_cursor_state == RegionCursorState.REGION_SELECTED:
		if (
			has_selected_region()
			and has_valid_provisional_founding_identity()
			and get_region_rect(selected_region_top_left).has_point(
				get_global_mouse_position()
			)
		):
			open_founding_panel()
		return

	if region_cursor_state != RegionCursorState.REGION_PLACE:
		return

	if hovered_tile.x < 0 or hovered_tile.y < 0:
		return

	var region_top_left: Vector2i = get_region_top_left_from_center(hovered_tile)

	if not is_region_valid(region_top_left):
		print("Invalid region: too much ocean/river or outside map.")
		return

	selected_region_center = hovered_tile
	selected_region_top_left = region_top_left
	clear_provisional_founding_identity()

	region_cursor_state = RegionCursorState.REGION_SELECTED

	if region_cursor_line != null:
		region_cursor_line.visible = false

	update_selected_region_line()
	update_cursor_visuals()
	open_founding_panel()
	refresh_founding_ui_state()

	print("Selected region centered at tile: ", selected_region_center)


func handle_right_mouse_click() -> void:
	if WorldData.has_active_world_save():
		return
	if founding_panel_open:
		return
	
	if has_selected_region():
		clear_selected_region()

		region_cursor_state = RegionCursorState.REGION_PLACE
		update_cursor_visuals()
		refresh_founding_ui_state()

		print("Region deselected. Region cursor restored.")
		return

	if region_cursor_state == RegionCursorState.REGION_PLACE:
		region_cursor_state = RegionCursorState.SINGLE_TILE

		if region_cursor_line != null:
			region_cursor_line.visible = false

		update_cursor_visuals()
		refresh_founding_ui_state()

		print("Region selection cancelled.")

func clear_selected_region() -> void:
	close_founding_panel()
	selected_region_center = Vector2i(-1, -1)
	selected_region_top_left = Vector2i(-1, -1)
	clear_provisional_founding_identity()

	if selected_region_line != null:
		selected_region_line.visible = false

	refresh_founding_ui_state()

func configure_world_camera() -> void:
	var current_camera: Camera2D = get_viewport().get_camera_2d()

	if current_camera == null:
		return

	if current_camera.has_method("configure_for_map"):
		current_camera.call("configure_for_map", world.width, world.height, settings.tile_size, false)

	if MapCameraSessionStateScript.has_world_camera_state:
		current_camera.position = MapCameraSessionStateScript.world_camera_position
		current_camera.zoom = MapCameraSessionStateScript.world_camera_zoom

	if current_camera.has_method("clamp_camera_to_map_bounds"):
		current_camera.call("clamp_camera_to_map_bounds")


func store_current_world_camera_state() -> void:
	var current_camera: Camera2D = get_viewport().get_camera_2d()

	if current_camera == null:
		return

	MapCameraSessionStateScript.store_world_camera(
		current_camera.position,
		current_camera.zoom
	)
