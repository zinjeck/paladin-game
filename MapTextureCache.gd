extends RefCounted
class_name MapTextureCache

var owner: Node
var label: String = "Map"
var rows_per_frame: int = 16
var mode_textures: Dictionary = {}
var warmup_running: bool = false
var warmup_token: int = 0

var color_provider: Callable
var modes_provider: Callable
var mode_name_provider: Callable
var has_valid_saved_cache_provider: Callable
var saved_cache_getter: Callable
var saved_cache_storer: Callable


func setup(
	owner_node: Node,
	cache_label: String,
	warmup_rows_per_frame: int,
	get_color_for_mode: Callable,
	get_all_modes_callable: Callable,
	get_mode_name_callable: Callable,
	has_valid_saved_cache: Callable,
	get_saved_cache: Callable,
	store_saved_cache: Callable
) -> void:
	owner = owner_node
	label = cache_label
	rows_per_frame = max(1, warmup_rows_per_frame)
	color_provider = get_color_for_mode
	modes_provider = get_all_modes_callable
	mode_name_provider = get_mode_name_callable
	has_valid_saved_cache_provider = has_valid_saved_cache
	saved_cache_getter = get_saved_cache
	saved_cache_storer = store_saved_cache


func clear() -> void:
	cancel_warmup()
	mode_textures.clear()


func cancel_warmup() -> void:
	warmup_token += 1
	warmup_running = false


func rebuild(source_world: WorldData, active_mode: int) -> ImageTexture:
	if source_world == null:
		clear()
		return null

	load_saved_cache_if_valid(source_world)
	ensure_texture_for_mode(source_world, active_mode)
	store_cache(source_world)
	start_warmup(source_world)

	print(label + " map texture ready: ", get_mode_name(active_mode))

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
		return

	warmup_token += 1
	warm_texture_cache_async(source_world, warmup_token)


func warm_texture_cache_async(source_world: WorldData, token: int) -> void:
	warmup_running = true

	if not is_warmup_still_valid(source_world, token):
		return

	await owner.get_tree().process_frame

	if not is_warmup_still_valid(source_world, token):
		return

	await owner.get_tree().process_frame

	for mode in get_all_modes():
		var mode_int := int(mode)

		if not is_warmup_still_valid(source_world, token):
			return

		if mode_textures.has(mode_int):
			continue

		var image := Image.create(source_world.width, source_world.height, false, Image.FORMAT_RGBA8)

		for y in range(source_world.height):
			var row: Array = source_world.tiles[y]

			for x in range(source_world.width):
				var tile: Dictionary = row[x]
				image.set_pixel(x, y, get_tile_color(tile, mode_int))

			if y % rows_per_frame == 0:
				await owner.get_tree().process_frame

				if not is_warmup_still_valid(source_world, token):
					return

		mode_textures[mode_int] = ImageTexture.create_from_image(image)
		store_cache(source_world)

		print("Warmed " + label.to_lower() + " map texture: ", get_mode_name(mode_int))

	warmup_running = false
	print(label + " map texture warmup complete.")


func is_warmup_still_valid(source_world: WorldData, token: int) -> bool:
	if token != warmup_token:
		warmup_running = false
		return false

	if owner == null:
		warmup_running = false
		return false

	if not owner.is_inside_tree():
		warmup_running = false
		return false

	if source_world == null:
		warmup_running = false
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
