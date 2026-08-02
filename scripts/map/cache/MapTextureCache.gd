extends RefCounted
class_name MapTextureCache

# Prepares the active map mode immediately, then builds every remaining mode
# incrementally. Scene entry therefore pays for one visible texture instead of
# every possible map overlay. A complete set is published to the session cache
# only after the source version remains stable for the whole warmup.

var owner: Node
var label: String = "Map"
var rows_per_frame: int = 16
var mode_textures: Dictionary = {}
var warmup_running: bool = false
var prepared_source_instance_id: int = 0
var prepared_source_tile_data_version: int = -1

var color_provider: Callable
var all_colors_provider: Callable
var modes_provider: Callable
var mode_name_provider: Callable
var has_valid_saved_cache_provider: Callable
var saved_cache_getter: Callable
var saved_cache_storer: Callable

var _warmup_source: WorldData
var _warmup_source_instance_id: int = 0
var _warmup_source_tile_data_version: int = -1
var _warmup_modes: Array[int] = []
var _warmup_images: Array[Image] = []
var _warmup_next_row: int = 0
var _warmup_all_modes: Array[int] = []
var _warmup_colors: Array[Color] = []


func setup(values: Dictionary) -> void:
	if not _has_valid_setup_values(values):
		return

	owner = values["owner"]
	label = str(values["label"])
	rows_per_frame = maxi(1, int(values["rows_per_frame"]))
	color_provider = values["color_provider"]
	all_colors_provider = values.get(
		"all_colors_provider",
		Callable()
	)
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

	if (
		values.has("all_colors_provider")
		and typeof(values["all_colors_provider"]) != TYPE_CALLABLE
	):
		push_error(
			"MapTextureCache.setup all_colors_provider must be Callable."
		)
		return false

	return true


func clear() -> void:
	cancel_warmup()
	mode_textures.clear()
	prepared_source_instance_id = 0
	prepared_source_tile_data_version = -1


func dispose() -> void:
	clear()
	owner = null
	color_provider = Callable()
	all_colors_provider = Callable()
	modes_provider = Callable()
	mode_name_provider = Callable()
	has_valid_saved_cache_provider = Callable()
	saved_cache_getter = Callable()
	saved_cache_storer = Callable()


func rebuild(source_world: WorldData, active_mode: int) -> ImageTexture:
	if source_world == null:
		clear()
		return null

	cancel_warmup()
	load_saved_cache_if_valid(source_world)
	_discard_textures_for_different_source(source_world)

	if not is_mode_ready(source_world, active_mode):
		var active_texture := build_texture_for_mode(
			source_world,
			active_mode
		)

		if active_texture == null:
			push_error(
				label
				+ " active map texture could not be prepared: "
				+ get_mode_name(active_mode)
			)
			return null

		mode_textures[active_mode] = active_texture
		prepared_source_instance_id = source_world.get_instance_id()
		prepared_source_tile_data_version = source_world.tile_data_version

	start_warmup(source_world)

	if WorldData.debug_mode_enabled:
		print(
			label + " active map texture ready; warming remaining modes: ",
			get_mode_name(active_mode)
		)

	return _get_cached_texture(active_mode)


func load_saved_cache_if_valid(source_world: WorldData) -> void:
	if source_world == null:
		clear()
		return

	if not has_valid_saved_cache_provider.is_valid():
		clear()
		return

	if not bool(has_valid_saved_cache_provider.call(source_world)):
		clear()
		return

	if not saved_cache_getter.is_valid():
		clear()
		return

	var saved_cache = saved_cache_getter.call()

	if typeof(saved_cache) != TYPE_DICTIONARY:
		clear()
		return

	mode_textures = saved_cache.duplicate(false)
	prepared_source_instance_id = source_world.get_instance_id()
	prepared_source_tile_data_version = source_world.tile_data_version


func prepare_all_textures(source_world: WorldData) -> bool:
	if source_world == null:
		return false
	if source_world.width <= 0 or source_world.height <= 0:
		return false

	_discard_textures_for_different_source(source_world)
	var all_modes := _get_unique_modes()

	if all_modes.is_empty():
		return false

	for mode in all_modes:
		if is_mode_ready(source_world, mode):
			continue

		var texture := build_texture_for_mode(source_world, mode)

		if texture == null:
			return false

		mode_textures[mode] = texture

	prepared_source_instance_id = source_world.get_instance_id()
	prepared_source_tile_data_version = source_world.tile_data_version
	cancel_warmup()

	if not _has_complete_texture_set(mode_textures, all_modes):
		return false

	store_cache(source_world)
	return true


func ensure_texture_for_mode(source_world: WorldData, mode: int) -> void:
	if source_world == null:
		return

	_discard_textures_for_different_source(source_world)

	if is_mode_ready(source_world, mode):
		return

	var texture := build_texture_for_mode(source_world, mode)

	if texture == null:
		return

	mode_textures[mode] = texture
	prepared_source_instance_id = source_world.get_instance_id()
	prepared_source_tile_data_version = source_world.tile_data_version
	start_warmup(source_world)


func rebuild_all(source_world: WorldData) -> void:
	clear()
	prepare_all_textures(source_world)


func get_texture_for_mode(
	source_world: WorldData,
	mode: int
) -> ImageTexture:
	if source_world == null:
		return null

	_discard_textures_for_different_source(source_world)

	if not is_mode_ready(source_world, mode):
		ensure_texture_for_mode(source_world, mode)

	return _get_cached_texture(mode)


func is_mode_ready(source_world: WorldData, mode: int) -> bool:
	if source_world == null:
		return false

	if (
		prepared_source_instance_id != source_world.get_instance_id()
		or prepared_source_tile_data_version
		!= source_world.tile_data_version
	):
		return false

	return _get_cached_texture(mode) != null


func build_texture_for_mode(
	source_world: WorldData,
	mode: int
) -> ImageTexture:
	if source_world == null:
		return null
	if source_world.width <= 0 or source_world.height <= 0:
		return null

	var source_tile_data_version := source_world.tile_data_version
	var image := Image.create(
		source_world.width,
		source_world.height,
		false,
		Image.FORMAT_RGBA8
	)

	for y in range(source_world.height):
		var row: Array = source_world.tiles[y]

		for x in range(source_world.width):
			var tile: Dictionary = row[x]
			image.set_pixel(x, y, get_tile_color(tile, mode))

	if source_world.tile_data_version != source_tile_data_version:
		return null

	return ImageTexture.create_from_image(image)


func _get_unique_modes() -> Array[int]:
	var unique_modes: Array[int] = []
	var seen_modes: Dictionary = {}

	for raw_mode in get_all_modes():
		var mode_int := int(raw_mode)

		if seen_modes.has(mode_int):
			continue

		seen_modes[mode_int] = true
		unique_modes.append(mode_int)

	return unique_modes


func _get_missing_modes(
	texture_cache: Dictionary,
	all_modes: Array[int]
) -> Array[int]:
	var missing_modes: Array[int] = []

	for mode_int in all_modes:
		if (
			not texture_cache.has(mode_int)
			or not texture_cache[mode_int] is ImageTexture
		):
			missing_modes.append(mode_int)

	return missing_modes


func _has_complete_texture_set(
	texture_cache: Dictionary,
	all_modes: Array[int] = []
) -> bool:
	if all_modes.is_empty():
		all_modes = _get_unique_modes()

	if all_modes.is_empty():
		return false

	return _get_missing_modes(texture_cache, all_modes).is_empty()


func _get_mode_color_buffer_size(all_modes: Array[int]) -> int:
	var buffer_size := 0

	for mode_int in all_modes:
		buffer_size = maxi(buffer_size, mode_int + 1)

	return buffer_size


func _discard_textures_for_different_source(
	source_world: WorldData
) -> void:
	if (
		prepared_source_instance_id == source_world.get_instance_id()
		and prepared_source_tile_data_version
		== source_world.tile_data_version
	):
		return

	cancel_warmup()
	mode_textures.clear()
	prepared_source_instance_id = source_world.get_instance_id()
	prepared_source_tile_data_version = source_world.tile_data_version


func _get_cached_texture(mode: int) -> ImageTexture:
	if not mode_textures.has(mode):
		return null

	var raw_texture = mode_textures[mode]

	if not raw_texture is ImageTexture:
		return null

	return raw_texture as ImageTexture


func start_warmup(source_world: WorldData) -> void:
	cancel_warmup()

	if source_world == null:
		return
	if source_world.width <= 0 or source_world.height <= 0:
		return

	_discard_textures_for_different_source(source_world)
	var all_modes := _get_unique_modes()
	var missing_modes := _get_missing_modes(mode_textures, all_modes)

	if missing_modes.is_empty():
		if _has_complete_texture_set(mode_textures, all_modes):
			store_cache(source_world)
		return

	_warmup_source = source_world
	_warmup_source_instance_id = source_world.get_instance_id()
	_warmup_source_tile_data_version = source_world.tile_data_version
	_warmup_modes = missing_modes
	_warmup_all_modes = all_modes
	_warmup_next_row = 0
	_warmup_images.clear()

	for _mode in _warmup_modes:
		_warmup_images.append(
			Image.create(
				source_world.width,
				source_world.height,
				false,
				Image.FORMAT_RGBA8
			)
		)

	_warmup_colors.resize(_get_mode_color_buffer_size(all_modes))
	warmup_running = true


func process_warmup() -> void:
	if not warmup_running:
		return
	if not is_warmup_still_valid(_warmup_source):
		cancel_warmup()
		return

	var source_world := _warmup_source
	var end_row := mini(
		_warmup_next_row + rows_per_frame,
		source_world.height
	)
	var use_all_colors_provider := all_colors_provider.is_valid()

	for y in range(_warmup_next_row, end_row):
		var row: Array = source_world.tiles[y]

		for x in range(source_world.width):
			var tile: Dictionary = row[x]

			if use_all_colors_provider:
				all_colors_provider.call(tile, _warmup_colors)

			for mode_index in range(_warmup_modes.size()):
				var mode_int := _warmup_modes[mode_index]
				var tile_color := Color.MAGENTA

				if (
					use_all_colors_provider
					and mode_int >= 0
					and mode_int < _warmup_colors.size()
				):
					tile_color = _warmup_colors[mode_int]
				else:
					tile_color = get_tile_color(tile, mode_int)

				_warmup_images[mode_index].set_pixel(
					x,
					y,
					tile_color
				)

	_warmup_next_row = end_row

	if _warmup_next_row < source_world.height:
		return

	_publish_completed_warmup()


func _publish_completed_warmup() -> void:
	if not is_warmup_still_valid(_warmup_source):
		cancel_warmup()
		return

	var prepared_textures := mode_textures.duplicate(false)

	for mode_index in range(_warmup_modes.size()):
		var texture := ImageTexture.create_from_image(
			_warmup_images[mode_index]
		)

		if texture == null:
			push_error(label + " map texture warmup could not publish a texture.")
			cancel_warmup()
			return

		prepared_textures[_warmup_modes[mode_index]] = texture

	if not _has_complete_texture_set(
		prepared_textures,
		_warmup_all_modes
	):
		push_error(label + " map texture warmup produced an incomplete cache.")
		cancel_warmup()
		return

	var source_world := _warmup_source
	mode_textures = prepared_textures
	prepared_source_instance_id = _warmup_source_instance_id
	prepared_source_tile_data_version = _warmup_source_tile_data_version
	cancel_warmup()
	store_cache(source_world)

	if WorldData.debug_mode_enabled:
		print(label + " map texture warmup complete.")


func cancel_warmup() -> void:
	warmup_running = false
	_warmup_source = null
	_warmup_source_instance_id = 0
	_warmup_source_tile_data_version = -1
	_warmup_modes.clear()
	_warmup_images.clear()
	_warmup_next_row = 0
	_warmup_all_modes.clear()
	_warmup_colors.clear()


func finish_warmup() -> void:
	while warmup_running:
		process_warmup()


func is_warmup_still_valid(source_world: WorldData) -> bool:
	return (
		warmup_running
		and source_world != null
		and is_instance_valid(source_world)
		and source_world == _warmup_source
		and source_world.get_instance_id() == _warmup_source_instance_id
		and source_world.tile_data_version
		== _warmup_source_tile_data_version
		and owner != null
		and is_instance_valid(owner)
	)


func get_tile_color(tile: Dictionary, mode: int) -> Color:
	if not color_provider.is_valid():
		return Color.MAGENTA

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
	if not _has_complete_texture_set(mode_textures):
		return

	saved_cache_storer.call(source_world, mode_textures)
