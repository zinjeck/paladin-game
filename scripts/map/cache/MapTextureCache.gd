extends RefCounted
class_name MapTextureCache

# Builds every missing map-mode texture before returning from rebuild(). The
# former per-frame warmup entry points remain as compatibility shims while
# renderer callers migrate away from them, but they never schedule later work.

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


func setup(values: Dictionary) -> void:
	if not _has_valid_setup_values(values):
		return

	owner = values["owner"]
	label = str(values["label"])
	# Retained for setup compatibility. Synchronous preparation does not use a
	# per-frame row budget.
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

	if not prepare_all_textures(source_world):
		push_error(label + " map textures could not be prepared.")
		return null

	if WorldData.debug_mode_enabled:
		print(
			label + " map textures ready; active mode: ",
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

	var missing_modes := _get_missing_modes(mode_textures, all_modes)

	if missing_modes.is_empty():
		return _has_complete_texture_set(mode_textures, all_modes)

	var source_tile_data_version := source_world.tile_data_version
	var built_textures := _build_textures_for_modes(
		source_world,
		missing_modes,
		all_modes
	)

	if source_world.tile_data_version != source_tile_data_version:
		push_error(
			label
			+ " map source changed while textures were being prepared."
		)
		return false

	if built_textures.size() != missing_modes.size():
		return false

	# Publish only after every missing image has become a valid texture. This
	# prevents a scene transition or saved cache from observing a partial set.
	var prepared_textures := mode_textures.duplicate(false)

	for mode in missing_modes:
		var mode_int := int(mode)
		var raw_texture = built_textures.get(mode_int)

		if not raw_texture is ImageTexture:
			return false

		prepared_textures[mode_int] = raw_texture

	if not _has_complete_texture_set(prepared_textures, all_modes):
		return false

	mode_textures = prepared_textures
	prepared_source_instance_id = source_world.get_instance_id()
	prepared_source_tile_data_version = source_tile_data_version
	store_cache(source_world)
	return true


func ensure_texture_for_mode(source_world: WorldData, _mode: int) -> void:
	# Compatibility API: satisfying any request now prepares the complete set.
	prepare_all_textures(source_world)


func rebuild_all(source_world: WorldData) -> void:
	clear()
	prepare_all_textures(source_world)


func get_texture_for_mode(
	source_world: WorldData,
	mode: int
) -> ImageTexture:
	if source_world == null:
		return null

	if not prepare_all_textures(source_world):
		return null

	return _get_cached_texture(mode)


func build_texture_for_mode(
	source_world: WorldData,
	mode: int
) -> ImageTexture:
	if source_world == null:
		return null

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

	return ImageTexture.create_from_image(image)


func _build_textures_for_modes(
	source_world: WorldData,
	modes_to_build: Array[int],
	all_modes: Array[int]
) -> Dictionary:
	var mode_images: Array[Image] = []

	for _mode in modes_to_build:
		mode_images.append(
			Image.create(
				source_world.width,
				source_world.height,
				false,
				Image.FORMAT_RGBA8
			)
		)

	var reusable_colors: Array[Color] = []
	reusable_colors.resize(_get_mode_color_buffer_size(all_modes))
	var use_all_colors_provider := all_colors_provider.is_valid()

	for y in range(source_world.height):
		var row: Array = source_world.tiles[y]

		for x in range(source_world.width):
			var tile: Dictionary = row[x]

			if use_all_colors_provider:
				all_colors_provider.call(tile, reusable_colors)

			for mode_index in range(modes_to_build.size()):
				var mode_int := int(modes_to_build[mode_index])
				var tile_color := Color.MAGENTA

				if (
					use_all_colors_provider
					and mode_int >= 0
					and mode_int < reusable_colors.size()
				):
					tile_color = reusable_colors[mode_int]
				else:
					tile_color = get_tile_color(tile, mode_int)

				mode_images[mode_index].set_pixel(
					x,
					y,
					tile_color
				)

	var built_textures: Dictionary = {}

	for mode_index in range(modes_to_build.size()):
		var mode_int := int(modes_to_build[mode_index])
		var texture := ImageTexture.create_from_image(
			mode_images[mode_index]
		)

		if texture == null:
			return {}

		built_textures[mode_int] = texture

	return built_textures


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
	if mode_textures.is_empty():
		return

	if (
		prepared_source_instance_id == source_world.get_instance_id()
		and prepared_source_tile_data_version
		== source_world.tile_data_version
	):
		return

	mode_textures.clear()
	prepared_source_instance_id = 0
	prepared_source_tile_data_version = -1


func _get_cached_texture(mode: int) -> ImageTexture:
	if not mode_textures.has(mode):
		return null

	var raw_texture = mode_textures[mode]

	if not raw_texture is ImageTexture:
		return null

	return raw_texture as ImageTexture


# Compatibility shims for renderer code that still calls the retired staggered
# warmup API. start_warmup performs a synchronous completeness check and no
# method below retains a source world or schedules future work.
func start_warmup(source_world: WorldData) -> void:
	warmup_running = false
	prepare_all_textures(source_world)


func process_warmup() -> void:
	warmup_running = false


func cancel_warmup() -> void:
	warmup_running = false


func finish_warmup() -> void:
	warmup_running = false


func is_warmup_still_valid(_source_world: WorldData) -> bool:
	return false


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
