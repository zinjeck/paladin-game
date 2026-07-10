extends Node2D

enum RegionCursorState {
	SINGLE_TILE,
	REGION_PLACE,
	REGION_SELECTED
}

var view_mode: int = MapVisuals.ViewMode.BIOME
var world_map_texture: ImageTexture
var world_texture_cache := MapTextureCache.new()

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

var region_cursor_valid_color := Color(1.0, 0.0, 1.0, 0.95)
var region_cursor_invalid_color := Color(1.0, 0.0, 0.0, 0.95)
var selected_region_border_color := Color(0.0, 1.0, 1.0, 1.0)

var region_cursor_border_width: float = 1.25
var selected_region_border_width: float = 2.0

var debug_panel_ui: DebugPanel
var debug_panel_position: Vector2 = Vector2.ZERO
var debug_panel_padding: Vector2 = Vector2(12.0, 10.0)
var debug_panel_min_size: Vector2 = Vector2(260.0, 80.0)

func _ready():
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_to_group("world_renderer")

	RenderingServer.set_default_clear_color(abyss_color)

	setup_world_texture_cache()
	create_hover_border_line()
	create_region_selection_lines()
	create_debug_panel()
	create_world_start_background()
	create_world_bottom_buttons()
	create_select_region_button()

	if WorldData.has_active_world_save():
		load_locked_world_save()
	else:
		world = null
		print("World screen loaded. Press Generate World.")
		queue_redraw()

func _draw():
	if world == null:
		return

	draw_abyss_background()
	draw_world_map_texture()


func _process(_delta):
	update_hovered_tile()

func _exit_tree() -> void:
	if world_texture_cache != null:
		world_texture_cache.cancel_warmup()

func setup_world_texture_cache() -> void:
	world_texture_cache.setup(
		self,
		"World",
		24,
		Callable(self, "get_tile_color_for_mode"),
		Callable(self, "get_all_world_view_modes"),
		Callable(self, "get_world_view_mode_name_for_mode"),
		Callable(self, "has_valid_saved_world_map_texture_cache"),
		Callable(self, "get_saved_world_map_texture_cache"),
		Callable(self, "store_saved_world_map_texture_cache")
	)


func has_valid_saved_world_map_texture_cache(source_world: WorldData) -> bool:
	return WorldData.has_valid_world_map_texture_cache(source_world)


func get_saved_world_map_texture_cache() -> Dictionary:
	return WorldData.get_world_map_texture_cache()


func store_saved_world_map_texture_cache(source_world: WorldData, texture_cache: Dictionary) -> void:
	WorldData.store_world_map_texture_cache(source_world, texture_cache)

func load_locked_world_save() -> void:
	world = WorldData.official_world

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

	if has_method("update_debug_panel_text"):
		call("update_debug_panel_text")

	print("Loaded locked official world seed: ", world.seed)

	rebuild_world_map_textures()
	configure_world_camera()
	queue_redraw()

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

func create_debug_panel() -> void:
	debug_panel_ui = DebugPanel.new()
	debug_panel_ui.setup(
		self,
		100,
		debug_panel_position,
		debug_panel_padding,
		debug_panel_min_size,
		"DEBUG MENU",
		Callable(self, "get_hovered_tile_debug_text")
	)

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
	if world == null:
		return "DEBUG MODE\nWorld: not generated"

	if hovered_tile.x < 0 or hovered_tile.y < 0:
		return (
			"DEBUG MENU\n"
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
		return

	var region_rect: Rect2 = get_region_rect(selected_region_top_left)

	selected_region_line.default_color = selected_region_border_color
	selected_region_line.width = selected_region_border_width
	set_line_to_rect(selected_region_line, region_rect)
	selected_region_line.visible = true


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

	view_mode = new_view_mode

	print("View: ", get_view_mode_name())

	if world_texture_cache != null:
		world_texture_cache.cancel_warmup()

	apply_cached_world_map_texture()
	start_world_texture_warmup()

	update_debug_panel_text()
	queue_redraw()

func get_all_world_view_modes() -> Array[int]:
	return MapVisuals.get_all_view_modes()

func draw_world_map_texture() -> void:
	if world_map_texture == null:
		return

	var map_rect := Rect2(
		Vector2.ZERO,
		Vector2(
			float(world.width * settings.tile_size),
			float(world.height * settings.tile_size)
		)
	)

	draw_texture_rect(world_map_texture, map_rect, false)

func draw_world_inner_box_border(rect: Rect2, border_color: Color, border_width: float) -> void:
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

func draw_abyss_background() -> void:
	var map_width: float = float(world.width * settings.tile_size)
	var map_height: float = float(world.height * settings.tile_size)

	var abyss_rect: Rect2 = Rect2(
		Vector2(-abyss_padding_pixels, -abyss_padding_pixels),
		Vector2(
			map_width + abyss_padding_pixels * 2.0,
			map_height + abyss_padding_pixels * 2.0
		)
	)

	draw_rect(
		abyss_rect,
		abyss_color,
		true
	)

func get_tile_color(tile: Dictionary) -> Color:
	return get_tile_color_for_mode(tile, view_mode)


func get_tile_color_for_mode(tile: Dictionary, mode: int) -> Color:
	return MapVisuals.get_tile_color_for_mode(tile, mode, 0.0)

func rebuild_world_map_textures() -> void:
	if world_texture_cache == null:
		setup_world_texture_cache()

	world_map_texture = world_texture_cache.rebuild(world, view_mode)


func ensure_world_map_texture_for_mode(mode: int) -> void:
	if world_texture_cache == null:
		setup_world_texture_cache()

	world_texture_cache.ensure_texture_for_mode(world, mode)


func start_world_texture_warmup() -> void:
	if world_texture_cache == null:
		setup_world_texture_cache()

	world_texture_cache.start_warmup(world)


func build_world_map_texture_for_mode(mode: int) -> ImageTexture:
	if world_texture_cache == null:
		setup_world_texture_cache()

	return world_texture_cache.build_texture_for_mode(world, mode)


func apply_cached_world_map_texture() -> void:
	if world_texture_cache == null:
		setup_world_texture_cache()

	world_map_texture = world_texture_cache.get_texture_for_mode(world, view_mode)

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


func on_select_region_button_pressed() -> void:
	if WorldData.has_active_world_save():
		print("Selection blocked: this save already has an official starting region.")
		return
	
	if world == null:
		return

	region_cursor_state = RegionCursorState.REGION_PLACE
	update_cursor_visuals()

	print("Region selection mode enabled.")

func on_generate_world_button_pressed() -> void:
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
	print("Generated world seed: ", world.seed)

	if world_start_background != null:
		world_start_background.visible = false

	if select_region_button != null:
		select_region_button.visible = true

	set_play_button_region_ready(false)

	if has_method("update_debug_panel_text"):
		call("update_debug_panel_text")

	rebuild_world_map_textures()
	configure_world_camera()
	queue_redraw()

func on_play_button_pressed() -> void:
	if WorldData.has_active_world_save():
		change_to_city_screen()
		return

	if world == null:
		print("Play blocked: no world generated.")
		return

	if not has_selected_region():
		print("Play blocked: select a starting region first.")
		return

	if city_scene_path.is_empty():
		push_error("City scene path is empty.")
		return

	var current_world_scene_path := ""

	if get_tree().current_scene != null:
		current_world_scene_path = get_tree().current_scene.scene_file_path

	WorldData.lock_world_save(
		world,
		selected_region_top_left,
		selected_region_center,
		region_size_tiles,
		current_world_scene_path,
		city_scene_path
	)

	set_world_locked_ui()

	print("Official world locked.")
	print("World seed: ", world.seed)
	print("Starting region center: ", selected_region_center)
	print("Starting region top-left: ", selected_region_top_left)

	change_to_city_screen()

func change_to_city_screen() -> void:
	store_current_world_camera_state()
	
	var target_city_scene_path := WorldData.official_city_scene_path

	if target_city_scene_path.is_empty():
		target_city_scene_path = city_scene_path

	if target_city_scene_path.is_empty():
		push_error("City scene path is empty.")
		return

	var error: Error = get_tree().change_scene_to_file(target_city_scene_path)

	if error != OK:
		push_error("Could not load city scene: " + target_city_scene_path)

func set_world_locked_ui() -> void:
	set_button_locked_disabled(generate_world_button)
	set_button_locked_disabled(select_region_button)

	set_play_button_region_ready(true)

	if play_button != null:
		play_button.text = "City"


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

	if event is InputEventMouseButton and event.pressed:
		var mouse_event: InputEventMouseButton = event

		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			handle_left_mouse_click()

		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			handle_right_mouse_click()

func handle_left_mouse_click() -> void:
	if WorldData.has_active_world_save():
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

	region_cursor_state = RegionCursorState.REGION_SELECTED

	if region_cursor_line != null:
		region_cursor_line.visible = false

	update_selected_region_line()
	update_cursor_visuals()
	set_play_button_region_ready(true)

	print("Selected region centered at tile: ", selected_region_center)


func handle_right_mouse_click() -> void:
	if WorldData.has_active_world_save():
		return
	
	if has_selected_region():
		clear_selected_region()

		region_cursor_state = RegionCursorState.REGION_PLACE
		update_cursor_visuals()
		set_play_button_region_ready(false)

		print("Region deselected. Region cursor restored.")
		return

	if region_cursor_state == RegionCursorState.REGION_PLACE:
		region_cursor_state = RegionCursorState.SINGLE_TILE

		if region_cursor_line != null:
			region_cursor_line.visible = false

		update_cursor_visuals()
		set_play_button_region_ready(false)

		print("Region selection cancelled.")

func clear_selected_region() -> void:
	selected_region_center = Vector2i(-1, -1)
	selected_region_top_left = Vector2i(-1, -1)

	if selected_region_line != null:
		selected_region_line.visible = false

func configure_world_camera() -> void:
	var current_camera: Camera2D = get_viewport().get_camera_2d()

	if current_camera == null:
		return

	if current_camera.has_method("configure_for_map"):
		current_camera.call("configure_for_map", world.width, world.height, settings.tile_size, false)

	if WorldData.has_world_camera_state:
		current_camera.position = WorldData.world_camera_position
		current_camera.zoom = WorldData.world_camera_zoom

	if current_camera.has_method("clamp_camera_to_map_bounds"):
		current_camera.call("clamp_camera_to_map_bounds")


func store_current_world_camera_state() -> void:
	var current_camera: Camera2D = get_viewport().get_camera_2d()

	if current_camera == null:
		return

	WorldData.world_camera_position = current_camera.position
	WorldData.world_camera_zoom = current_camera.zoom
	WorldData.has_world_camera_state = true
