extends RefCounted
class_name MapTextureCacheState

# Owns session-level rendered map texture caches. This state is presentation
# infrastructure and is intentionally separated from authoritative WorldData.

static var world_mode_textures: Dictionary = {}
static var world_seed: int = -1
static var world_size: Vector2i = Vector2i.ZERO
static var world_tile_data_version: int = -1
static var world_visual_version: int = -1

static var city_mode_textures: Dictionary = {}
static var city_seed: int = -1
static var city_size: Vector2i = Vector2i.ZERO
static var city_tile_data_version: int = -1
static var city_visual_version: int = -1


static func _has_complete_mode_texture_cache(texture_cache: Dictionary) -> bool:
	for mode in MapVisuals.get_all_view_modes():
		var mode_int := int(mode)

		if not texture_cache.has(mode_int):
			return false

		if not texture_cache[mode_int] is ImageTexture:
			return false

	return true


#region World Map Cache

static func has_valid_world_cache(source_world) -> bool:
	if source_world == null:
		return false

	if not _has_complete_mode_texture_cache(world_mode_textures):
		return false

	if world_seed != source_world.seed:
		return false

	if world_size != Vector2i(source_world.width, source_world.height):
		return false

	if world_tile_data_version != int(source_world.tile_data_version):
		return false

	if world_visual_version != MapVisuals.MAP_VISUAL_CACHE_VERSION:
		return false

	return true


static func store_world_cache(source_world, texture_cache: Dictionary) -> void:
	if source_world == null:
		return
	if not _has_complete_mode_texture_cache(texture_cache):
		push_error("Cannot store an incomplete world map texture cache.")
		return

	world_seed = source_world.seed
	world_size = Vector2i(source_world.width, source_world.height)
	world_tile_data_version = int(source_world.tile_data_version)
	world_mode_textures = texture_cache.duplicate(false)
	world_visual_version = MapVisuals.MAP_VISUAL_CACHE_VERSION


static func get_world_cache() -> Dictionary:
	return world_mode_textures.duplicate(false)


static func clear_world_cache() -> void:
	world_mode_textures.clear()
	world_seed = -1
	world_size = Vector2i.ZERO
	world_tile_data_version = -1
	world_visual_version = -1

#endregion


#region City Map Cache

static func has_valid_city_cache(source_city_world, source_city_seed: int) -> bool:
	if source_city_world == null:
		return false

	if not _has_complete_mode_texture_cache(city_mode_textures):
		return false

	if city_seed != source_city_seed:
		return false

	if city_size != Vector2i(source_city_world.width, source_city_world.height):
		return false

	if city_tile_data_version != int(source_city_world.tile_data_version):
		return false

	if city_visual_version != MapVisuals.MAP_VISUAL_CACHE_VERSION:
		return false

	return true


static func store_city_cache(
	source_city_world,
	source_city_seed: int,
	texture_cache: Dictionary
) -> void:
	if source_city_world == null:
		return
	if not _has_complete_mode_texture_cache(texture_cache):
		push_error("Cannot store an incomplete city map texture cache.")
		return

	city_seed = source_city_seed
	city_size = Vector2i(source_city_world.width, source_city_world.height)
	city_tile_data_version = int(source_city_world.tile_data_version)
	city_mode_textures = texture_cache.duplicate(false)
	city_visual_version = MapVisuals.MAP_VISUAL_CACHE_VERSION


static func get_city_cache() -> Dictionary:
	return city_mode_textures.duplicate(false)


static func clear_city_cache() -> void:
	city_mode_textures.clear()
	city_seed = -1
	city_size = Vector2i.ZERO
	city_tile_data_version = -1
	city_visual_version = -1

#endregion
