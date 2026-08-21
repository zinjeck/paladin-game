extends RefCounted
class_name MapTextureCache

# Map modes are prepared atomically as one complete set of independent
# ImageTextures. One tile traversal computes every mode, every GPU upload is
# completed before publication, and switching modes remains a cache-only
# texture swap. No later gameplay frame performs map-mode generation work.

var owner: Node
var label: String = "Map"
var mode_textures: Dictionary = {}
var prepared_source_instance_id: int = 0
var prepared_source_tile_data_version: int = -1

var color_provider: Callable
var all_colors_provider: Callable
var modes_provider: Callable
var mode_name_provider: Callable
var has_valid_saved_cache_provider: Callable
var saved_cache_getter: Callable
var saved_cache_storer: Callable
var standard_biome_resource_blend: float = 0.0


func setup(values: Dictionary) -> void:
	if not _has_valid_setup_values(values):
		return

	owner = values["owner"]
	label = str(values["label"])
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


func setup_standard_map_visuals(values: Dictionary) -> void:
	standard_biome_resource_blend = clampf(
		float(values.get("biome_resource_blend", 0.0)),
		0.0,
		1.0
	)
	var setup_values := values.duplicate(false)
	setup_values.erase("biome_resource_blend")
	setup_values["color_provider"] = Callable(
		self,
		"_get_standard_tile_color"
	)
	setup_values["all_colors_provider"] = Callable(
		self,
		"_populate_standard_tile_colors"
	)
	setup_values["modes_provider"] = Callable(
		self,
		"_get_standard_view_modes"
	)
	setup_values["mode_name_provider"] = Callable(
		self,
		"_get_standard_view_mode_name"
	)
	setup(setup_values)


func _get_standard_tile_color(tile: Dictionary, mode: int) -> Color:
	return MapVisuals.get_tile_color_for_mode(
		tile,
		mode,
		standard_biome_resource_blend
	)


func _populate_standard_tile_colors(
	tile: Dictionary,
	output_colors: Array[Color]
) -> void:
	MapVisuals.populate_all_tile_colors(
		tile,
		output_colors,
		standard_biome_resource_blend
	)


func _get_standard_view_modes() -> Array[int]:
	return MapVisuals.get_all_view_modes()


func _get_standard_view_mode_name(mode: int) -> String:
	return MapVisuals.get_view_mode_name(mode)


func _has_valid_setup_values(values: Dictionary) -> bool:
	var required_keys: Array[String] = [
		"owner",
		"label",
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


func rebuild(source_world: WorldData, active_mode: int) -> Texture2D:
	if source_world == null:
		clear()
		return null

	load_saved_cache_if_valid(source_world)

	if not prepare_all_textures(source_world):
		push_error(label + " map texture set could not be prepared.")
		return null

	if WorldData.debug_mode_enabled:
		print(
			label + " independent map textures ready; active mode: ",
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
		_discard_textures_for_different_source(source_world)
		return

	if not saved_cache_getter.is_valid():
		clear()
		return

	var saved_cache = saved_cache_getter.call()

	if typeof(saved_cache) != TYPE_DICTIONARY:
		clear()
		return

	var all_modes := _get_unique_modes()

	if not _has_complete_texture_set(saved_cache, all_modes):
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

	if _has_complete_texture_set(mode_textures, all_modes):
		return true

	var source_tile_data_version := source_world.tile_data_version
	var prepared_textures := _build_independent_mode_textures(
		source_world,
		all_modes
	)

	if source_world.tile_data_version != source_tile_data_version:
		push_error(
			label
			+ " map source changed while its atomic atlas was being prepared."
		)
		return false

	if not _has_complete_texture_set(prepared_textures, all_modes):
		return false

	mode_textures = prepared_textures
	prepared_source_instance_id = source_world.get_instance_id()
	prepared_source_tile_data_version = source_tile_data_version
	store_cache(source_world)
	return true


func install_prepared_atlas(
	source_world: WorldData,
	atlas_data: Dictionary
) -> bool:
	if source_world == null or atlas_data.is_empty():
		return false
	if int(atlas_data.get("tile_data_version", -1)) != source_world.tile_data_version:
		return false
	if (
		int(atlas_data.get("visual_version", -1))
		!= MapVisuals.MAP_VISUAL_CACHE_VERSION
	):
		return false

	var raw_modes = atlas_data.get("modes", [])
	var raw_bytes = atlas_data.get("rgba8", PackedByteArray())

	if not raw_modes is Array or not raw_bytes is PackedByteArray:
		return false

	var modes: Array[int] = []

	for raw_mode in raw_modes:
		modes.append(int(raw_mode))

	var prepared_textures := create_mode_textures_from_rgba8(
		raw_bytes,
		int(atlas_data.get("width", 0)),
		int(atlas_data.get("height", 0)),
		modes
	)

	if not _has_complete_texture_set(prepared_textures, _get_unique_modes()):
		return false

	mode_textures = prepared_textures
	prepared_source_instance_id = source_world.get_instance_id()
	prepared_source_tile_data_version = source_world.tile_data_version
	store_cache(source_world)
	return true



func get_texture_for_mode(
	source_world: WorldData,
	mode: int
) -> Texture2D:
	if source_world == null:
		return null

	if not prepare_all_textures(source_world):
		return null

	return _get_cached_texture(mode)


func is_mode_ready(
	source_world: WorldData,
	mode: int
) -> bool:
	if source_world == null:
		return false
	if (
		prepared_source_instance_id != source_world.get_instance_id()
		or prepared_source_tile_data_version != source_world.tile_data_version
	):
		return false

	return _get_cached_texture(mode) != null



func _build_independent_mode_textures(
	source_world: WorldData,
	all_modes: Array[int]
) -> Dictionary:
	var mode_images: Array[Image] = []

	for _mode in all_modes:
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

			for mode_index in range(all_modes.size()):
				var mode_int := all_modes[mode_index]
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

	var textures: Dictionary = {}

	for mode_index in range(all_modes.size()):
		var mode_texture := ImageTexture.create_from_image(
			mode_images[mode_index]
		)

		if mode_texture == null:
			return {}

		textures[all_modes[mode_index]] = mode_texture

	return textures


static func create_mode_textures_from_rgba8(
	atlas_data: PackedByteArray,
	map_width: int,
	map_height: int,
	modes: Array[int]
) -> Dictionary:
	if map_width <= 0 or map_height <= 0 or modes.is_empty():
		return {}

	var expected_size := map_width * modes.size() * map_height * 4

	if atlas_data.size() != expected_size:
		push_error(
			"Map atlas byte size mismatch. Expected "
			+ str(expected_size)
			+ ", received "
			+ str(atlas_data.size())
			+ "."
		)
		return {}

	var atlas_image := Image.create_from_data(
		map_width * modes.size(),
		map_height,
		false,
		Image.FORMAT_RGBA8,
		atlas_data
	)
	return create_mode_textures_from_atlas_image(
		atlas_image,
		map_width,
		map_height,
		modes
	)


static func create_mode_textures_from_atlas_image(
	atlas_image: Image,
	map_width: int,
	map_height: int,
	modes: Array[int]
) -> Dictionary:
	if atlas_image == null:
		return {}
	if map_width <= 0 or map_height <= 0 or modes.is_empty():
		return {}
	if atlas_image.get_width() != map_width * modes.size():
		return {}
	if atlas_image.get_height() != map_height:
		return {}

	var textures: Dictionary = {}

	for mode_index in range(modes.size()):
		var mode_image := atlas_image.get_region(Rect2i(
			mode_index * map_width,
			0,
			map_width,
			map_height
		))
		var mode_texture := ImageTexture.create_from_image(mode_image)

		if mode_texture == null:
			return {}

		textures[modes[mode_index]] = mode_texture

	return textures


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


func _has_complete_texture_set(
	texture_cache: Dictionary,
	all_modes: Array[int] = []
) -> bool:
	if all_modes.is_empty():
		all_modes = _get_unique_modes()

	if all_modes.is_empty():
		return false

	for mode_int in all_modes:
		if not texture_cache.has(mode_int):
			return false
		if not texture_cache[mode_int] is ImageTexture:
			return false

	return true


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
