extends RefCounted
class_name MapTextureCache

var owner: Node
var label: String = "Map"
var rows_per_frame: int = 16
var mode_textures: Dictionary = {}
var warmup_running: bool = false
var warmup_source_world: WorldData
var warmup_source_instance_id: int = 0
var warmup_source_tile_data_version: int = -1
var warmup_modes: Array = []
var warmup_mode_index: int = 0
var warmup_next_row: int = 0
var warmup_delay_frames: int = 0
var warmup_image: Image

var color_provider: Callable
var modes_provider: Callable
var mode_name_provider: Callable
var has_valid_saved_cache_provider: Callable
var saved_cache_getter: Callable
var saved_cache_storer: Callable


func setup(values: Dictionary) -> void:
	if not _has_valid_setup_values(values):
		return

	owner = values["owner"]
	label = str(values["label"])
	rows_per_frame = maxi(1, int(values["rows_per_frame"]))
	color_provider = values["color_provider"]
	modes_provider = values["modes_provider"]
	mode_name_provider = values["mode_name_provider"]
	has_valid_saved_cache_provider = (
		values["has_valid_saved_cache_provider"]
	)
	saved_cache_getter = values["saved_cache_getter"]
	saved_cache_storer = values["saved_cache_storer"]


func _has_valid_setup_values(values: Dictionary) -> bool:
	var required_keys: Array[String] = [
		"owner",
		"label",
		"rows_per_frame",
		"color_provider",
		"modes_provider",
		"mode_name_provider",
		"has_valid_saved_cache_provider",
		"saved_cache_getter",
		"saved_cache_storer",
	]

	for key in required_keys:
		if not values.has(key):
			push_error(
				"MapTextureCache.setup is missing required key: "
				+ key
			)
			return false

	if not values["owner"] is Node:
		push_error("MapTextureCache.setup owner must be a Node.")
		return false

	var callable_keys: Array[String] = [
		"color_provider",
		"modes_provider",
		"mode_name_provider",
		"has_valid_saved_cache_provider",
		"saved_cache_getter",
		"saved_cache_storer",
	]

	for key in callable_keys:
		if typeof(values[key]) != TYPE_CALLABLE:
			push_error(
				"MapTextureCache.setup "
				+ key
				+ " must be Callable."
			)
			return false

	return true


func clear() -> void:
	cancel_warmup()
	mode_textures.clear()


func dispose() -> void:
	clear()
	owner = null
	color_provider = Callable()
	modes_provider = Callable()
	mode_name_provider = Callable()
	has_valid_saved_cache_provider = Callable()
	saved_cache_getter = Callable()
	saved_cache_storer = Callable()


func cancel_warmup() -> void:
	warmup_running = false
	warmup_source_world = null
	warmup_source_instance_id = 0
	warmup_source_tile_data_version = -1
	warmup_modes.clear()
	warmup_mode_index = 0
	warmup_next_row = 0
	warmup_delay_frames = 0
	warmup_image = null


func rebuild(source_world: WorldData, active_mode: int) -> ImageTexture:
	if source_world == null:
		clear()
		return null

	cancel_warmup()
	load_saved_cache_if_valid(source_world)
	ensure_texture_for_mode(source_world, active_mode)
	store_cache(source_world)
	start_warmup(source_world)

	if WorldData.debug_mode_enabled:
		print(
			label + " map texture ready: ",
			get_mode_name(active_mode)
		)

	return get_texture_for_mode(source_world, active_mode)


func load_saved_cache_if_valid(source_world: WorldData) -> void:
	if source_world == null:
		mode_textures.clear()
		return

	if not has_valid_saved_cache_provider.is_valid():
		mode_textures.clear()
		return

	if not bool(has_valid_saved_cache_provider.call(source_world)):
		mode_textures.clear()
		return

	if not saved_cache_getter.is_valid():
		mode_textures.clear()
		return

	var saved_cache = saved_cache_getter.call()

	if typeof(saved_cache) == TYPE_DICTIONARY:
		mode_textures = saved_cache.duplicate(false)
	else:
		mode_textures.clear()


func ensure_texture_for_mode(source_world: WorldData, mode: int) -> void:
	if source_world == null:
		return

	if mode_textures.has(mode):
		return

	mode_textures[mode] = build_texture_for_mode(source_world, mode)
	store_cache(source_world)


func rebuild_all(source_world: WorldData) -> void:
	cancel_warmup()
	mode_textures.clear()

	if source_world == null:
		return

	for mode in get_all_modes():
		mode_textures[int(mode)] = build_texture_for_mode(source_world, int(mode))

	store_cache(source_world)


func get_texture_for_mode(source_world: WorldData, mode: int) -> ImageTexture:
	if source_world == null:
		return null

	ensure_texture_for_mode(source_world, mode)

	if not mode_textures.has(mode):
		return null

	return mode_textures[mode] as ImageTexture


func build_texture_for_mode(source_world: WorldData, mode: int) -> ImageTexture:
	var image := Image.create(source_world.width, source_world.height, false, Image.FORMAT_RGBA8)

	for y in range(source_world.height):
		var row: Array = source_world.tiles[y]

		for x in range(source_world.width):
			var tile: Dictionary = row[x]
			image.set_pixel(x, y, get_tile_color(tile, mode))

	return ImageTexture.create_from_image(image)


func start_warmup(source_world: WorldData) -> void:
	if source_world == null:
		return

	if warmup_running:
		if (
			source_world == warmup_source_world
			and source_world.get_instance_id()
			== warmup_source_instance_id
			and source_world.tile_data_version
			== warmup_source_tile_data_version
		):
			return

		cancel_warmup()

	warmup_running = true
	warmup_source_world = source_world
	warmup_source_instance_id = source_world.get_instance_id()
	warmup_source_tile_data_version = (
		source_world.tile_data_version
	)
	warmup_modes = get_all_modes().duplicate()
	warmup_mode_index = 0
	warmup_next_row = 0
	warmup_delay_frames = 2
	warmup_image = null


func process_warmup() -> void:
	if not warmup_running:
		return

	if not is_warmup_still_valid(warmup_source_world):
		cancel_warmup()
		return

	if warmup_delay_frames > 0:
		warmup_delay_frames -= 1
		return

	while warmup_mode_index < warmup_modes.size():
		var cached_mode := int(warmup_modes[warmup_mode_index])

		if not mode_textures.has(cached_mode):
			break

		warmup_mode_index += 1

	if warmup_mode_index >= warmup_modes.size():
		finish_warmup()
		return

	var mode_int := int(warmup_modes[warmup_mode_index])

	if warmup_image == null:
		warmup_image = Image.create(
			warmup_source_world.width,
			warmup_source_world.height,
			false,
			Image.FORMAT_RGBA8
		)

	var end_row := mini(
		warmup_next_row + rows_per_frame,
		warmup_source_world.height
	)

	for y in range(warmup_next_row, end_row):
		var row: Array = warmup_source_world.tiles[y]

		for x in range(warmup_source_world.width):
			var tile: Dictionary = row[x]
			warmup_image.set_pixel(
				x,
				y,
				get_tile_color(tile, mode_int)
			)

	warmup_next_row = end_row

	if warmup_next_row < warmup_source_world.height:
		return

	mode_textures[mode_int] = ImageTexture.create_from_image(
		warmup_image
	)
	store_cache(warmup_source_world)

	if WorldData.debug_mode_enabled:
		print(
			"Warmed " + label.to_lower() + " map texture: ",
			get_mode_name(mode_int)
		)

	warmup_mode_index += 1
	warmup_next_row = 0
	warmup_image = null


func finish_warmup() -> void:
	if WorldData.debug_mode_enabled:
		print(label + " map texture warmup complete.")

	warmup_running = false
	warmup_source_world = null
	warmup_source_instance_id = 0
	warmup_source_tile_data_version = -1
	warmup_modes.clear()
	warmup_mode_index = 0
	warmup_next_row = 0
	warmup_delay_frames = 0
	warmup_image = null


func is_warmup_still_valid(source_world: WorldData) -> bool:
	if not warmup_running:
		return false

	if owner == null:
		return false

	if not owner.is_inside_tree():
		return false

	if source_world == null:
		return false

	if source_world != warmup_source_world:
		return false

	if source_world.get_instance_id() != warmup_source_instance_id:
		return false

	if (
		source_world.tile_data_version
		!= warmup_source_tile_data_version
	):
		return false

	return true

func get_tile_color(tile: Dictionary, mode: int) -> Color:
	if not color_provider.is_valid():
		return Color(1.0, 0.0, 1.0, 1.0)

	return color_provider.call(tile, mode) as Color


func get_all_modes() -> Array:
	if not modes_provider.is_valid():
		return []

	var modes = modes_provider.call()

	if typeof(modes) == TYPE_ARRAY:
		return modes

	return []


func get_mode_name(mode: int) -> String:
	if not mode_name_provider.is_valid():
		return str(mode)

	return str(mode_name_provider.call(mode))


func store_cache(source_world: WorldData) -> void:
	if source_world == null:
		return

	if not saved_cache_storer.is_valid():
		return

	saved_cache_storer.call(source_world, mode_textures)
