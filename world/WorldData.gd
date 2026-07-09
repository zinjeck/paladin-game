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
static var city_resource_amounts: Dictionary = {}
static var city_objects: Array = []
static var city_storage_version: int = 0
static var city_occupied_tiles: Dictionary = {}
static var next_city_object_id: int = 1

const CITY_OBJECT_CITY_CENTER := "city_center"
const CITY_OBJECT_HOUSE := "house"
const CITY_OBJECT_STOCKPILE := "stockpile"
const CITY_OBJECT_PLACEHOLDER_BUILDING := "placeholder_building"
const CITY_OBJECT_ROAD := "road"
const CITY_OBJECT_PLACEMENT_EFFECT_NONE := "none"
const CITY_OBJECT_PLACEMENT_EFFECT_FOUND_CITY := "found_city"
static func ensure_city_object_definitions_ready() -> void:
	if city_object_definitions.is_empty():
		setup_city_object_definitions()

static func setup_city_object_definitions() -> void:
	city_object_definitions.clear()

	city_object_definitions[CITY_OBJECT_CITY_CENTER] = make_city_object_definition({
		"type": CITY_OBJECT_CITY_CENTER,
		"display_name": "City Keep",
		"size": Vector2i(2, 6),
		"button_slot": 1,
		"requires_city": false,
		"requires_no_city": true,
		"repeat_after_place": false,
		"placement_effect": CITY_OBJECT_PLACEMENT_EFFECT_FOUND_CITY,
		"frame_color": Color(0.32, 0.30, 0.24, 0.95),
		"fill_color": Color(0.86, 0.84, 0.76, 0.55),
		"frame_thickness": 0.35
	})

	city_object_definitions[CITY_OBJECT_HOUSE] = make_city_object_definition({
		"type": CITY_OBJECT_HOUSE,
		"display_name": "House",
		"size": Vector2i(3, 3),
		"button_slot": 3,
		"requires_city": true,
		"requires_no_city": false,
		"repeat_after_place": true,
		"placement_effect": CITY_OBJECT_PLACEMENT_EFFECT_NONE,
		"frame_color": Color(0.32, 0.30, 0.24, 0.95),
		"fill_color": Color(0.86, 0.84, 0.76, 0.55),
		"frame_thickness": 0.30
	})

	city_object_definitions[CITY_OBJECT_STOCKPILE] = make_city_object_definition({
		"type": CITY_OBJECT_STOCKPILE,
		"display_name": "Stockpile",
		"size": Vector2i(2, 2),
		"button_slot": 4,
		"requires_city": true,
		"requires_no_city": false,
		"repeat_after_place": true,
		"placement_effect": CITY_OBJECT_PLACEMENT_EFFECT_NONE,
		"frame_color": Color(0.46, 0.30, 0.12, 0.95),
		"fill_color": Color(0.82, 0.64, 0.32, 0.55),
		"frame_thickness": 0.30,
		"storage_resources": [
			RESOURCE_FISH,
			RESOURCE_COAL,
			RESOURCE_IRON,
			RESOURCE_GOLD
		],
		"storage_capacity_per_resource": 100
	})

static func make_city_object_definition(values: Dictionary) -> Dictionary:
	var object_type: String = str(values.get("type", ""))
	var storage_resources: Array[String] = []
	var raw_storage_resources = values.get("storage_resources", [])

	if raw_storage_resources is Array:
		for resource in raw_storage_resources:
			storage_resources.append(str(resource))
	if object_type.is_empty():
		push_error("City object definition is missing a type.")
		return {}

	return {
		"type": object_type,
		"display_name": str(values.get("display_name", object_type.capitalize())),
		"size": values.get("size", Vector2i.ONE),
		"button_slot": int(values.get("button_slot", 0)),
		"requires_city": bool(values.get("requires_city", false)),
		"requires_no_city": bool(values.get("requires_no_city", false)),
		"repeat_after_place": bool(values.get("repeat_after_place", false)),
		"placement_effect": str(values.get("placement_effect", CITY_OBJECT_PLACEMENT_EFFECT_NONE)),
		"frame_color": values.get("frame_color", Color(0.32, 0.30, 0.24, 0.95)),
		"fill_color": values.get("fill_color", Color(0.86, 0.84, 0.76, 0.55)),
		"frame_thickness": float(values.get("frame_thickness", 0.30)),
		"storage_resources": storage_resources,
		"storage_capacity_per_resource": int(values.get("storage_capacity_per_resource", 0))
	}

static func get_city_object_definition(object_type: String) -> Dictionary:
	ensure_city_object_definitions_ready()

	if city_object_definitions.has(object_type):
		return city_object_definitions[object_type]

	return {}


static func get_city_object_display_name_for_type(object_type: String) -> String:
	var definition := get_city_object_definition(object_type)

	if definition.is_empty():
		return object_type.capitalize()

	return str(definition.get("display_name", object_type.capitalize()))


static func get_city_object_size_for_type(object_type: String) -> Vector2i:
	var definition := get_city_object_definition(object_type)

	if definition.is_empty():
		return Vector2i.ONE

	return definition["size"]


static func get_city_object_visual_style_for_type(object_type: String) -> Dictionary:
	var definition := get_city_object_definition(object_type)

	if definition.is_empty():
		return {
			"frame_color": Color(0.32, 0.30, 0.24, 0.95),
			"fill_color": Color(0.86, 0.84, 0.76, 0.55),
			"frame_thickness": 0.30
		}

	return {
		"frame_color": definition["frame_color"],
		"fill_color": definition["fill_color"],
		"frame_thickness": definition["frame_thickness"]
	}


static func can_use_city_object_definition(object_type: String) -> bool:
	var definition := get_city_object_definition(object_type)

	if definition.is_empty():
		return false

	if bool(definition.get("requires_city", false)) and not can_build_in_city():
		return false

	if bool(definition.get("requires_no_city", false)) and has_player_city():
		return false

	return true

static var city_object_definitions: Dictionary = {}

func setup(new_width: int, new_height: int, new_seed: int):
	width = new_width
	height = new_height
	seed = new_seed
	tiles.clear()

	for y in range(height):
		var row := []
#THE TILE DICTIONARY \/ \/ \/ \/ \/
		for x in range(width):
			row.append(make_default_tile())

		tiles.append(row)

func make_default_tile() -> Dictionary:
	return {
		"fertility": -1.0,
		"elevation": 0.0,
		"temperature": 0.0,
		"precipitation": 0.0,
		"terrain": TERRAIN_WATER,
		"biome": BIOME_OCEAN,
		"resource": RESOURCE_NONE,
		"is_land": false
	}

func get_tile(x: int, y: int) -> Dictionary:
	if not is_in_bounds(x, y):
		return make_default_tile()

	return tiles[y][x]

func is_in_bounds(x: int, y: int) -> bool:
	if x < 0 or y < 0:
		return false

	if x >= width or y >= height:
		return false

	return true

func set_tile(x: int, y: int, data: Dictionary) -> void:
	if not is_in_bounds(x, y):
		return

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

static func get_total_stored_city_resource_amount(resource: String) -> int:
	var total := 0

	for city_object in city_objects:
		if not city_object is Dictionary:
			continue

		total += get_city_object_stored_resource_amount(city_object, resource)

	return total

static func reset_player_city_state() -> void:
	player_city_founded = false
	player_city_data.clear()
	player_city_foundation_top_left = Vector2i(-1, -1)
	player_city_foundation_size = Vector2i.ZERO
	city_resource_amounts.clear()
	reset_city_object_state()

static func reset_city_object_state() -> void:
	city_objects.clear()
	city_occupied_tiles.clear()
	next_city_object_id = 1
	city_storage_version += 1

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

	var starting_storage := make_empty_city_object_storage_for_type(object_type)

	if not starting_storage.is_empty():
		city_object["stored_resources"] = starting_storage

	next_city_object_id += 1

	city_objects.append(city_object)
	occupy_city_object_tiles(city_object)

	return city_object

static func make_empty_city_object_storage_for_type(object_type: String) -> Dictionary:
	var definition := get_city_object_definition(object_type)

	if definition.is_empty():
		return {}

	var storage_resources: Array = definition.get("storage_resources", [])

	if storage_resources.is_empty():
		return {}

	var stored_resources := {}

	for resource in storage_resources:
		stored_resources[str(resource)] = 0

	return stored_resources


static func get_city_object_storage_resources(city_object: Dictionary) -> Array[String]:
	if city_object.is_empty():
		return []

	var object_type: String = str(city_object.get("type", ""))
	var definition := get_city_object_definition(object_type)

	if definition.is_empty():
		return []

	var result: Array[String] = []
	var storage_resources: Array = definition.get("storage_resources", [])

	for resource in storage_resources:
		result.append(str(resource))

	return result


static func can_city_object_store_resource(city_object: Dictionary, resource: String) -> bool:
	var storage_resources := get_city_object_storage_resources(city_object)
	return storage_resources.has(resource)


static func get_city_object_storage_capacity_per_resource(city_object: Dictionary) -> int:
	if city_object.is_empty():
		return 0

	var object_type: String = str(city_object.get("type", ""))
	var definition := get_city_object_definition(object_type)

	if definition.is_empty():
		return 0

	return int(definition.get("storage_capacity_per_resource", 0))


static func get_city_object_stored_resource_amount(city_object: Dictionary, resource: String) -> int:
	if city_object.is_empty():
		return 0

	if not can_city_object_store_resource(city_object, resource):
		return 0

	var stored_resources = city_object.get("stored_resources", {})

	if not stored_resources is Dictionary:
		return 0

	return int(stored_resources.get(resource, 0))


static func set_city_object_stored_resource_amount(
	object_id: int,
	resource: String,
	amount: int
) -> void:
	for i in range(city_objects.size()):
		var city_object: Dictionary = city_objects[i]

		if int(city_object.get("id", -1)) != object_id:
			continue

		if not can_city_object_store_resource(city_object, resource):
			return

		var stored_resources = city_object.get("stored_resources", {})

		if not stored_resources is Dictionary or stored_resources.is_empty():
			stored_resources = make_empty_city_object_storage_for_type(str(city_object.get("type", "")))

		var safe_amount: int = max(0, amount)
		var capacity: int = get_city_object_storage_capacity_per_resource(city_object)

		if capacity > 0:
			safe_amount = min(safe_amount, capacity)

		var old_amount := int(stored_resources.get(resource, 0))

		if old_amount == safe_amount:
			return

		stored_resources[resource] = safe_amount
		city_object["stored_resources"] = stored_resources
		city_objects[i] = city_object

		city_storage_version += 1
		return

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


static func reset_runtime_session_state(clear_debug: bool = false) -> void:
	reset_world_session_state()
	reset_city_session_state()
	reset_player_city_state()
	clear_visual_texture_caches()

	if clear_debug:
		debug_mode_enabled = false


static func reset_world_session_state() -> void:
	save_locked = false
	official_world = null
	official_selected_region_center = Vector2i(-1, -1)
	official_selected_region_top_left = Vector2i(-1, -1)
	official_region_size = 0
	official_world_scene_path = ""
	official_city_scene_path = ""
	city_return_world_scene_path = ""

	reset_city_start_region_state()
	reset_world_camera_state()
	clear_world_map_texture_cache()


static func reset_city_session_state() -> void:
	official_city_world = null
	official_city_seed = 0

	reset_city_camera_state()
	clear_city_map_texture_cache()


static func reset_city_start_region_state() -> void:
	city_start_world_seed = 0
	city_start_region_center = Vector2i(-1, -1)
	city_start_region_top_left = Vector2i(-1, -1)
	city_start_region_size = 0
	city_start_tiles.clear()


static func reset_world_camera_state() -> void:
	has_world_camera_state = false
	world_camera_position = Vector2.ZERO
	world_camera_zoom = Vector2.ONE


static func reset_city_camera_state() -> void:
	has_city_camera_state = false
	city_camera_position = Vector2.ZERO
	city_camera_zoom = Vector2.ONE


static func clear_visual_texture_caches() -> void:
	clear_world_map_texture_cache()
	clear_city_map_texture_cache()
