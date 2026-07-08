extends RefCounted
class_name WorldData

const TERRAIN_WATER := "water"
const TERRAIN_LAND := "land"
const TERRAIN_MOUNTAIN := "mountain"

const BIOME_OCEAN := "ocean"
const BIOME_MOUNTAIN := "mountain"
const BIOME_HILLS := "hills"
const BIOME_DESERT := "desert"
const BIOME_PLAIN := "plain"
const BIOME_FOREST := "forest"
const BIOME_TUNDRA:= "tundra"
const BIOME_TAIGA := "taiga"
const BIOME_JUNGLE := "jungle"
const BIOME_RIVER := "river"

const RESOURCE_NONE := "none"
const RESOURCE_IRON := "iron"
const RESOURCE_COAL := "coal"
const RESOURCE_GOLD := "gold"
const RESOURCE_FISH := "fish"

var width: int
var height: int
var seed: int
var tiles := []

static var city_start_world_seed: int = 0
static var city_start_region_center: Vector2i = Vector2i(-1, -1)
static var city_start_region_top_left: Vector2i = Vector2i(-1, -1)
static var city_start_region_size: int = 0
static var city_start_tiles: Array = []
static var city_return_world_scene_path: String = ""
static var save_locked: bool = false
static var has_world_camera_state: bool = false
static var world_camera_position: Vector2 = Vector2.ZERO
static var world_camera_zoom: Vector2 = Vector2.ONE
static var city_resource_amounts: Dictionary = {}
static var world_map_mode_texture_cache: Dictionary = {}
static var world_map_texture_cache_seed: int = -1
static var world_map_texture_cache_size: Vector2i = Vector2i.ZERO
static var world_map_texture_cache_visual_version: int = -1
static var city_map_texture_cache_visual_version: int = -1
static var city_map_mode_texture_cache: Dictionary = {}
static var city_map_texture_cache_seed: int = -1
static var city_map_texture_cache_size: Vector2i = Vector2i.ZERO
static var player_city_foundation_top_left: Vector2i = Vector2i(-1, -1)
static var player_city_foundation_size: Vector2i = Vector2i.ZERO
static var has_city_camera_state: bool = false
static var city_camera_position: Vector2 = Vector2.ZERO
static var city_camera_zoom: Vector2 = Vector2.ONE
static var official_world = null
static var official_city_world = null
static var official_city_seed: int = 0
static var player_city_founded: bool = false
static var player_city_data: Dictionary = {}
static var debug_mode_enabled: bool = false
static var official_selected_region_center: Vector2i = Vector2i(-1, -1)
static var official_selected_region_top_left: Vector2i = Vector2i(-1, -1)
static var official_region_size: int = 0

static var official_world_scene_path: String = ""
static var official_city_scene_path: String = ""
static var city_objects: Array = []
static var city_occupied_tiles: Dictionary = {}
static var next_city_object_id: int = 1

const CITY_OBJECT_CITY_CENTER := "city_center"
const CITY_OBJECT_HOUSE := "house"
const CITY_OBJECT_PLACEHOLDER_BUILDING := "placeholder_building"
const CITY_OBJECT_ROAD := "road"

func setup(new_width: int, new_height: int, new_seed: int):
	width = new_width
	height = new_height
	seed = new_seed
	tiles.clear()

	for y in range(height):
		var row := []
#THE TILE DICTIONARY \/ \/ \/ \/ \/
		for x in range(width):
			row.append({
				"fertility": -1.0,
				"elevation": 0.0,
				"temperature": 0.0,
				"precipitation": 0.0,
				"terrain": TERRAIN_WATER,
				"biome": BIOME_OCEAN,
				"resource": RESOURCE_NONE,
				"is_land": false
			})

		tiles.append(row)


func get_tile(x: int, y: int) -> Dictionary:
	return tiles[y][x]


func set_tile(x: int, y: int, data: Dictionary):
	tiles[y][x] = data

static func store_city_start_region(
	source_world: WorldData,
	region_top_left: Vector2i,
	region_center: Vector2i,
	region_size: int
) -> void:
	city_start_world_seed = source_world.seed
	city_start_region_center = region_center
	city_start_region_top_left = region_top_left
	city_start_region_size = region_size
	city_start_tiles.clear()

	for y_offset in range(region_size):
		var row := []

		for x_offset in range(region_size):
			var tile_x: int = region_top_left.x + x_offset
			var tile_y: int = region_top_left.y + y_offset

			var source_tile: Dictionary = source_world.get_tile(tile_x, tile_y).duplicate(true)

			source_tile["source_world_x"] = tile_x
			source_tile["source_world_y"] = tile_y

			row.append(source_tile)

		city_start_tiles.append(row)


static func has_city_start_region() -> bool:
	if city_start_region_size <= 0:
		return false

	if city_start_tiles.size() != city_start_region_size:
		return false

	return true

static func lock_world_save(
	source_world: WorldData,
	region_top_left: Vector2i,
	region_center: Vector2i,
	region_size: int,
	world_scene_path: String,
	city_scene_path: String
) -> void:
	save_locked = true

	official_world = source_world
	official_selected_region_center = region_center
	official_selected_region_top_left = region_top_left
	official_region_size = region_size

	official_world_scene_path = world_scene_path
	official_city_scene_path = city_scene_path

	store_city_start_region(
		source_world,
		region_top_left,
		region_center,
		region_size
	)


static func has_active_world_save() -> bool:
	return save_locked and official_world != null


static func has_active_city_save() -> bool:
	return official_city_world != null


static func store_city_world_save(city_world: WorldData, city_seed: int) -> void:
	official_city_world = city_world
	official_city_seed = city_seed
	clear_city_map_texture_cache()
	
static func found_player_city(
	city_name: String,
	city_world_seed: int,
	city_map_size: Vector2i,
	foundation_top_left: Vector2i = Vector2i(-1, -1),
	foundation_size: Vector2i = Vector2i.ZERO
) -> void:
	if player_city_founded:
		return

	player_city_founded = true
	player_city_foundation_top_left = foundation_top_left
	player_city_foundation_size = foundation_size

	player_city_data = {
		"id": 1,
		"name": city_name,
		"city_world_seed": city_world_seed,
		"city_map_size": city_map_size,
		"foundation_top_left": foundation_top_left,
		"foundation_size": foundation_size,
		"can_build": true,
		"founded": true
	}

static func has_player_city_foundation() -> bool:
	return (
		player_city_founded
		and player_city_foundation_top_left != Vector2i(-1, -1)
		and player_city_foundation_size.x > 0
		and player_city_foundation_size.y > 0
	)

static func has_player_city() -> bool:
	return player_city_founded


static func can_build_in_city() -> bool:
	if not player_city_founded:
		return false

	if not player_city_data.has("can_build"):
		return false

	return bool(player_city_data["can_build"])

static func ensure_city_resource_amounts() -> void:
	if city_resource_amounts.is_empty():
		city_resource_amounts = {
			RESOURCE_FISH: 0,
			RESOURCE_COAL: 0,
			RESOURCE_IRON: 0,
			RESOURCE_GOLD: 0
		}


static func get_city_resource_amount(resource: String) -> int:
	ensure_city_resource_amounts()

	if not city_resource_amounts.has(resource):
		city_resource_amounts[resource] = 0

	return int(city_resource_amounts[resource])

static func reset_player_city_state() -> void:
	player_city_founded = false
	player_city_data.clear()
	player_city_foundation_top_left = Vector2i(-1, -1)
	player_city_foundation_size = Vector2i.ZERO
	reset_city_object_state()

static func reset_city_object_state() -> void:
	city_objects.clear()
	city_occupied_tiles.clear()
	next_city_object_id = 1


static func can_place_city_object(
	city_world: WorldData,
	top_left: Vector2i,
	size_tiles: Vector2i
) -> bool:
	if city_world == null:
		return false

	if size_tiles.x <= 0 or size_tiles.y <= 0:
		return false

	if top_left.x < 0 or top_left.y < 0:
		return false

	if top_left.x + size_tiles.x > city_world.width:
		return false

	if top_left.y + size_tiles.y > city_world.height:
		return false

	for y in range(top_left.y, top_left.y + size_tiles.y):
		for x in range(top_left.x, top_left.x + size_tiles.x):
			var tile_position := Vector2i(x, y)

			if city_occupied_tiles.has(tile_position):
				return false

			var tile: Dictionary = city_world.get_tile(x, y)

			if tile["terrain"] == TERRAIN_WATER:
				return false

			if tile["terrain"] == TERRAIN_MOUNTAIN:
				return false

	return true


static func add_city_object(
	object_type: String,
	top_left: Vector2i,
	size_tiles: Vector2i,
	owner: String = "player"
) -> Dictionary:
	var city_object := {
		"id": next_city_object_id,
		"type": object_type,
		"top_left": top_left,
		"size": size_tiles,
		"owner": owner
	}

	next_city_object_id += 1

	city_objects.append(city_object)
	occupy_city_object_tiles(city_object)

	return city_object


static func occupy_city_object_tiles(city_object: Dictionary) -> void:
	var top_left: Vector2i = city_object["top_left"]
	var size_tiles: Vector2i = city_object["size"]
	var object_id: int = int(city_object["id"])

	for y in range(top_left.y, top_left.y + size_tiles.y):
		for x in range(top_left.x, top_left.x + size_tiles.x):
			city_occupied_tiles[Vector2i(x, y)] = object_id


static func get_city_object_at_tile(tile_position: Vector2i) -> Dictionary:
	if not city_occupied_tiles.has(tile_position):
		return {}

	var object_id: int = int(city_occupied_tiles[tile_position])

	for city_object in city_objects:
		if int(city_object["id"]) == object_id:
			return city_object

	return {}


static func has_city_object_type(object_type: String) -> bool:
	for city_object in city_objects:
		if str(city_object["type"]) == object_type:
			return true

	return false

static func can_place_city_road_tile(city_world: WorldData, tile_position: Vector2i) -> bool:
	if city_world == null:
		return false

	if tile_position.x < 0 or tile_position.y < 0:
		return false

	if tile_position.x >= city_world.width or tile_position.y >= city_world.height:
		return false

	if city_occupied_tiles.has(tile_position):
		return false

	var tile: Dictionary = city_world.get_tile(tile_position.x, tile_position.y)

	if tile["terrain"] == TERRAIN_WATER:
		return false

	if tile["terrain"] == TERRAIN_MOUNTAIN:
		return false

	return true


static func add_city_road_object(tile_positions: Array, owner: String = "player") -> Dictionary:
	var clean_tiles: Array = []

	for tile_position in tile_positions:
		if not tile_position is Vector2i:
			continue

		if city_occupied_tiles.has(tile_position):
			continue

		clean_tiles.append(tile_position)

	if clean_tiles.is_empty():
		return {}

	var city_object := {
		"id": next_city_object_id,
		"type": CITY_OBJECT_ROAD,
		"tiles": clean_tiles,
		"owner": owner
	}

	next_city_object_id += 1
	city_objects.append(city_object)

	for tile_position in clean_tiles:
		city_occupied_tiles[tile_position] = int(city_object["id"])

	return city_object
static func has_valid_world_map_texture_cache(source_world) -> bool:
	if source_world == null:
		return false

	if world_map_mode_texture_cache.is_empty():
		return false

	if world_map_texture_cache_seed != source_world.seed:
		return false

	if world_map_texture_cache_size != Vector2i(source_world.width, source_world.height):
		return false
	
	if world_map_texture_cache_visual_version != MapVisuals.MAP_VISUAL_CACHE_VERSION:
		return false

	return true

static func store_world_map_texture_cache(source_world, texture_cache: Dictionary) -> void:
	if source_world == null:
		return

	world_map_texture_cache_seed = source_world.seed
	world_map_texture_cache_size = Vector2i(source_world.width, source_world.height)
	world_map_mode_texture_cache = texture_cache.duplicate(false)
	world_map_texture_cache_visual_version = MapVisuals.MAP_VISUAL_CACHE_VERSION

static func get_world_map_texture_cache() -> Dictionary:
	return world_map_mode_texture_cache.duplicate(false)


static func clear_world_map_texture_cache() -> void:
	world_map_mode_texture_cache.clear()
	world_map_texture_cache_seed = -1
	world_map_texture_cache_size = Vector2i.ZERO


static func has_valid_city_map_texture_cache(source_city_world, source_city_seed: int) -> bool:
	if source_city_world == null:
		return false

	if city_map_mode_texture_cache.is_empty():
		return false

	if city_map_texture_cache_seed != source_city_seed:
		return false

	if city_map_texture_cache_size != Vector2i(source_city_world.width, source_city_world.height):
		return false
		
	if city_map_texture_cache_visual_version != MapVisuals.MAP_VISUAL_CACHE_VERSION:
		return false
		
	return true


static func store_city_map_texture_cache(
	source_city_world,
	source_city_seed: int,
	texture_cache: Dictionary
) -> void:
	if source_city_world == null:
		return

	city_map_texture_cache_seed = source_city_seed
	city_map_texture_cache_size = Vector2i(source_city_world.width, source_city_world.height)
	city_map_mode_texture_cache = texture_cache.duplicate(false)
	city_map_texture_cache_visual_version = MapVisuals.MAP_VISUAL_CACHE_VERSION

static func get_city_map_texture_cache() -> Dictionary:
	return city_map_mode_texture_cache.duplicate(false)


static func clear_city_map_texture_cache() -> void:
	city_map_mode_texture_cache.clear()
	city_map_texture_cache_seed = -1
	city_map_texture_cache_size = Vector2i.ZERO


static func clear_visual_texture_caches() -> void:
	clear_world_map_texture_cache()
	clear_city_map_texture_cache()
