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
static var city_citizens: Array = []
static var next_city_citizen_id: int = 1
static var city_citizen_first_name_pool: Array = [
	"Arlen",
	"Tovan",
	"Calen",
	"Ronan",
	"Darian",
	"Kael",
	"Bren",
	"Orin",
	"Levon",
	"Theron",
	"Jarek",
	"Corin",
	"Malric",
	"Edrin",
	"Tomas",
	"Varon",
	"Lucan",
	"Alric",
	"Fenric",
	"Soren",
	"Mira",
	"Elia",
	"Sera",
	"Nira",
	"Liora",
	"Kaela",
	"Maris",
	"Elara",
	"Vessa",
	"Talia",
	"Rina",
	"Anya",
	"Selene",
	"Maera",
	"Isolde",
	"Lyra",
	"Vela",
	"Seris",
	"Amara",
	"Coralie"
]

const STARTING_CITY_POPULATION := 8
const DEFAULT_CITIZEN_CARRY_CAPACITY := 10
const DEFAULT_CITIZEN_HUNGER := 100
const DEFAULT_CITIZEN_HAPPINESS := 70
const CITY_CITIZEN_STATE_IDLE := "idle"
const CITY_OBJECT_CITY_CENTER := "city_center"
const CITY_OBJECT_HOUSE := "house"
const CITY_OBJECT_STOCKPILE := "stockpile"
const CITY_OBJECT_FISHING_GROUNDS := "fishing_grounds"
const CITY_OBJECT_PLACEHOLDER_BUILDING := "placeholder_building"
const CITY_OBJECT_ROAD := "road"
const CITY_OBJECT_PLACEMENT_EFFECT_NONE := "none"
const CITY_OBJECT_PLACEMENT_EFFECT_FOUND_CITY := "found_city"
const CITY_OBJECT_SHAPE_RECTANGLE := "rectangle"
const CITY_OBJECT_SHAPE_TILE_AREA := "tile_area"
const WORKPLACE_KIND_NONE := "none"
const WORKPLACE_KIND_GATHERING := "gathering"
const CONTAINER_TYPE_NONE := "none"
const CONTAINER_TYPE_PUBLIC_CITY_STORAGE := "public_city_storage"
const CONTAINER_TYPE_PRIVATE_HOME_STORAGE := "private_home_storage"
const CONTAINER_TYPE_WORKPLACE_STORAGE := "workplace_storage"
const CONTAINER_TYPE_PERSONAL_INVENTORY := "personal_inventory"
const CONTAINER_TYPE_GROUND_PILE := "ground_pile"
static func ensure_city_object_definitions_ready() -> void:
	if city_object_definitions.is_empty():
		setup_city_object_definitions()

static func setup_city_object_definitions() -> void:
	city_object_definitions.clear()

	city_object_definitions[CITY_OBJECT_CITY_CENTER] = make_city_object_definition({
		"type": CITY_OBJECT_CITY_CENTER,
		"display_name": "City Keep",
		"container_type": CONTAINER_TYPE_NONE,
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
		"container_type": CONTAINER_TYPE_PRIVATE_HOME_STORAGE,
		"resident_capacity": 4,
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
		"container_type": CONTAINER_TYPE_PUBLIC_CITY_STORAGE,
		"counts_as_public_city_storage": true,
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

	city_object_definitions[CITY_OBJECT_FISHING_GROUNDS] = make_city_object_definition({
		"type": CITY_OBJECT_FISHING_GROUNDS,
		"display_name": "Fishing Grounds",
		"container_type": CONTAINER_TYPE_WORKPLACE_STORAGE,
		"counts_as_public_city_storage": false,
		"shape_mode": CITY_OBJECT_SHAPE_RECTANGLE,
		"size": Vector2i(4, 4),
		"button_slot": 5,
		"requires_city": true,
		"requires_no_city": false,
		"repeat_after_place": true,
		"placement_effect": CITY_OBJECT_PLACEMENT_EFFECT_NONE,
		"frame_color": Color(0.06, 0.34, 0.40, 0.95),
		"fill_color": Color(0.18, 0.62, 0.70, 0.48),
		"frame_thickness": 0.30,
		"is_workplace": true,
		"workplace_kind": WORKPLACE_KIND_GATHERING,
		"worker_capacity": 4,
		"output_resource": RESOURCE_FISH,
		"storage_resources": [
			RESOURCE_FISH
		],
		"storage_capacity_per_resource": 50
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

	var container_type: String = str(values.get("container_type", CONTAINER_TYPE_NONE))
	var counts_as_public_city_storage := bool(values.get(
		"counts_as_public_city_storage",
		container_type == CONTAINER_TYPE_PUBLIC_CITY_STORAGE
	))
	var shape_mode: String = str(values.get("shape_mode", CITY_OBJECT_SHAPE_RECTANGLE))
	var is_workplace := bool(values.get("is_workplace", false))

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
				"container_type": container_type,
		"counts_as_public_city_storage": counts_as_public_city_storage,
		"shape_mode": shape_mode,
		"storage_resources": storage_resources,
		"storage_capacity_per_resource": int(values.get("storage_capacity_per_resource", 0)),
		"resident_capacity": int(values.get("resident_capacity", 0)),
		"is_workplace": is_workplace,
		"workplace_kind": str(values.get("workplace_kind", WORKPLACE_KIND_NONE)),
		"worker_capacity": int(values.get("worker_capacity", 0)),
		"output_resource": str(values.get("output_resource", RESOURCE_NONE))
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

	ensure_starting_city_population()

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

static func get_city_resource_types() -> Array[String]:
	return [
		RESOURCE_FISH,
		RESOURCE_COAL,
		RESOURCE_IRON,
		RESOURCE_GOLD
	]


static func ensure_city_resource_amounts() -> void:
	if city_resource_amounts.is_empty():
		for resource in get_city_resource_types():
			city_resource_amounts[resource] = 0


static func get_city_resource_amount(resource: String) -> int:
	ensure_city_resource_amounts()

	if not city_resource_amounts.has(resource):
		city_resource_amounts[resource] = 0

	return int(city_resource_amounts[resource])


static func get_total_public_city_resource_amount(resource: String) -> int:
	var total := 0

	for city_object in city_objects:
		if not city_object is Dictionary:
			continue

		if not city_object_counts_as_public_city_storage(city_object):
			continue

		total += get_city_object_stored_resource_amount(city_object, resource)

	return total


static func get_total_public_city_resource_storage_capacity(resource: String) -> int:
	var total_capacity := 0

	for city_object in city_objects:
		if not city_object is Dictionary:
			continue

		if not city_object_counts_as_public_city_storage(city_object):
			continue

		if not can_city_object_store_resource(city_object, resource):
			continue

		total_capacity += get_city_object_storage_capacity_for_resource(city_object, resource)

	return total_capacity


static func get_total_stored_city_resource_amount(resource: String) -> int:
	return get_total_public_city_resource_amount(resource)


static func get_total_city_resource_storage_capacity(resource: String) -> int:
	return get_total_public_city_resource_storage_capacity(resource)


static func reset_city_citizen_state() -> void:
	city_citizens.clear()
	next_city_citizen_id = 1


static func make_empty_citizen_inventory() -> Dictionary:
	return make_empty_resource_container(get_city_resource_types())

static func get_city_citizen_name_seed() -> int:
	var name_seed := int(official_city_seed)

	if name_seed == 0:
		name_seed = int(city_start_world_seed)

	if name_seed == 0:
		name_seed = 12345

	return name_seed


static func get_used_city_citizen_name_counts() -> Dictionary:
	var used_name_counts := {}

	for citizen in city_citizens:
		if not citizen is Dictionary:
			continue

		var citizen_name := str(citizen.get("name", "")).strip_edges()

		if citizen_name.is_empty():
			continue

		used_name_counts[citizen_name] = int(used_name_counts.get(citizen_name, 0)) + 1

	return used_name_counts


static func make_random_city_citizen_first_name() -> String:
	if city_citizen_first_name_pool.is_empty():
		return ""

	var used_name_counts := get_used_city_citizen_name_counts()
	var available_names := []

	for raw_name in city_citizen_first_name_pool:
		var candidate_name := str(raw_name).strip_edges()

		if candidate_name.is_empty():
			continue

		if used_name_counts.has(candidate_name):
			continue

		available_names.append(candidate_name)

	var candidate_pool := available_names

	if candidate_pool.is_empty():
		candidate_pool = city_citizen_first_name_pool

	if candidate_pool.is_empty():
		return ""

	var rng := RandomNumberGenerator.new()
	var seed_value := get_city_citizen_name_seed()
	var citizen_number := next_city_citizen_id
	var population_number := city_citizens.size()

	rng.seed = int(abs(seed_value * 1000003 + citizen_number * 9176 + population_number * 6113 + 1337))

	var random_index := rng.randi_range(0, candidate_pool.size() - 1)

	return str(candidate_pool[random_index]).strip_edges()

static func make_city_citizen(display_name: String = "") -> Dictionary:
	var citizen_name := display_name.strip_edges()

	if citizen_name.is_empty():
		citizen_name = make_random_city_citizen_first_name()

	if citizen_name.is_empty():
		citizen_name = "Citizen " + str(next_city_citizen_id)

	var citizen := {
		"id": next_city_citizen_id,
		"name": citizen_name,
		"alive": true,
		"hunger": DEFAULT_CITIZEN_HUNGER,
		"happiness": DEFAULT_CITIZEN_HAPPINESS,
		"home_object_id": -1,
		"job_object_id": -1,
		"state": CITY_CITIZEN_STATE_IDLE,
		"carry_capacity": DEFAULT_CITIZEN_CARRY_CAPACITY,
		"inventory": make_empty_citizen_inventory()
	}

	next_city_citizen_id += 1
	return citizen


static func add_city_citizen(display_name: String = "") -> Dictionary:
	var citizen := make_city_citizen(display_name)
	city_citizens.append(citizen)
	return citizen


static func ensure_starting_city_population() -> void:
	if not city_citizens.is_empty():
		return

	for _index in range(STARTING_CITY_POPULATION):
		add_city_citizen()


static func get_city_population_count() -> int:
	ensure_starting_city_population()
	return city_citizens.size()


static func get_city_housed_citizen_count() -> int:
	ensure_starting_city_population()

	var housed_count := 0

	for citizen in city_citizens:
		if not citizen is Dictionary:
			continue

		if int(citizen.get("home_object_id", -1)) >= 0:
			housed_count += 1

	return housed_count


static func get_city_unemployed_citizen_count() -> int:
	ensure_starting_city_population()

	var unemployed_count := 0

	for citizen in city_citizens:
		if not citizen is Dictionary:
			continue

		if not bool(citizen.get("alive", true)):
			continue

		if int(citizen.get("job_object_id", -1)) < 0:
			unemployed_count += 1

	return unemployed_count

static func get_city_citizen_by_id(citizen_id: int) -> Dictionary:
	ensure_starting_city_population()

	for citizen in city_citizens:
		if not citizen is Dictionary:
			continue

		if int(citizen.get("id", -1)) == citizen_id:
			return citizen

	return {}


static func get_city_citizen_display_name(citizen_id: int) -> String:
	var citizen := get_city_citizen_by_id(citizen_id)

	if citizen.is_empty():
		return "Citizen " + str(citizen_id)

	return str(citizen.get("name", "Citizen " + str(citizen_id)))


static func get_city_citizen_snapshot() -> Array:
	ensure_starting_city_population()

	var citizen_snapshot := []

	for citizen in city_citizens:
		if not citizen is Dictionary:
			continue

		citizen_snapshot.append(citizen.duplicate(true))

	return citizen_snapshot

static func get_city_object_resident_capacity(city_object: Dictionary) -> int:
	if city_object.is_empty():
		return 0

	if city_object.has("resident_capacity"):
		return int(city_object.get("resident_capacity", 0))

	var definition := get_city_object_definition_from_object(city_object)
	return int(definition.get("resident_capacity", 0))


static func get_city_object_resident_count(city_object: Dictionary) -> int:
	if city_object.is_empty():
		return 0

	if city_object.has("resident_ids"):
		var resident_ids = city_object.get("resident_ids", [])

		if resident_ids is Array:
			return resident_ids.size()

	var object_id := int(city_object.get("id", -1))

	if object_id < 0:
		return 0

	ensure_starting_city_population()

	var resident_count := 0

	for citizen in city_citizens:
		if not citizen is Dictionary:
			continue

		if int(citizen.get("home_object_id", -1)) == object_id:
			resident_count += 1

	return resident_count

static func get_city_object_resident_ids(city_object: Dictionary) -> Array:
	var resident_ids := []

	if city_object.is_empty():
		return resident_ids

	if city_object.has("resident_ids"):
		var raw_resident_ids = city_object.get("resident_ids", [])

		if raw_resident_ids is Array:
			for resident_id in raw_resident_ids:
				resident_ids.append(int(resident_id))

			return resident_ids

	var object_id := int(city_object.get("id", -1))

	if object_id < 0:
		return resident_ids

	ensure_starting_city_population()

	for citizen in city_citizens:
		if not citizen is Dictionary:
			continue

		if int(citizen.get("home_object_id", -1)) != object_id:
			continue

		var citizen_id := int(citizen.get("id", -1))

		if citizen_id < 0:
			continue

		resident_ids.append(citizen_id)

	return resident_ids

static func get_city_object_resident_names(city_object: Dictionary) -> Array:
	var resident_names := []
	var resident_ids := get_city_object_resident_ids(city_object)

	for resident_id in resident_ids:
		resident_names.append(get_city_citizen_display_name(int(resident_id)))

	return resident_names

static func get_total_city_resident_capacity() -> int:
	var total_capacity := 0

	for city_object in city_objects:
		if not city_object is Dictionary:
			continue

		total_capacity += get_city_object_resident_capacity(city_object)

	return total_capacity

static func city_object_is_workplace(city_object: Dictionary) -> bool:
	if city_object.is_empty():
		return false

	if bool(city_object.get("is_workplace", false)):
		return true

	var definition := get_city_object_definition_from_object(city_object)

	if definition.is_empty():
		return false

	return bool(definition.get("is_workplace", false))


static func get_city_object_worker_capacity(city_object: Dictionary) -> int:
	if city_object.is_empty():
		return 0

	if city_object.has("worker_capacity"):
		return int(city_object.get("worker_capacity", 0))

	var definition := get_city_object_definition_from_object(city_object)
	return int(definition.get("worker_capacity", 0))


static func get_city_object_output_resource(city_object: Dictionary) -> String:
	if city_object.is_empty():
		return RESOURCE_NONE

	if city_object.has("output_resource"):
		return str(city_object.get("output_resource", RESOURCE_NONE))

	var definition := get_city_object_definition_from_object(city_object)
	return str(definition.get("output_resource", RESOURCE_NONE))


static func get_city_object_worker_ids(city_object: Dictionary) -> Array:
	var worker_ids := []

	if city_object.is_empty():
		return worker_ids

	if city_object.has("assigned_worker_ids"):
		var raw_worker_ids = city_object.get("assigned_worker_ids", [])

		if raw_worker_ids is Array:
			for worker_id in raw_worker_ids:
				worker_ids.append(int(worker_id))

			return worker_ids

	var object_id := int(city_object.get("id", -1))

	if object_id < 0:
		return worker_ids

	ensure_starting_city_population()

	for citizen in city_citizens:
		if not citizen is Dictionary:
			continue

		if int(citizen.get("job_object_id", -1)) != object_id:
			continue

		var citizen_id := int(citizen.get("id", -1))

		if citizen_id < 0:
			continue

		worker_ids.append(citizen_id)

	return worker_ids


static func get_city_object_worker_count(city_object: Dictionary) -> int:
	return get_city_object_worker_ids(city_object).size()


static func get_city_object_worker_names(city_object: Dictionary) -> Array:
	var worker_names := []
	var worker_ids := get_city_object_worker_ids(city_object)

	for worker_id in worker_ids:
		worker_names.append(get_city_citizen_display_name(int(worker_id)))

	return worker_names


static func get_first_unemployed_city_citizen_index() -> int:
	ensure_starting_city_population()

	for citizen_index in range(city_citizens.size()):
		var raw_citizen = city_citizens[citizen_index]

		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if not bool(citizen.get("alive", true)):
			continue

		if int(citizen.get("job_object_id", -1)) >= 0:
			continue

		return citizen_index

	return -1


static func assign_unemployed_citizens_to_available_workplaces() -> int:
	ensure_starting_city_population()

	var assigned_count := 0

	for object_index in range(city_objects.size()):
		var raw_city_object = city_objects[object_index]

		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object

		if not city_object_is_workplace(city_object):
			continue

		var workplace_id := int(city_object.get("id", -1))

		if workplace_id < 0:
			continue

		var worker_capacity := get_city_object_worker_capacity(city_object)

		if worker_capacity <= 0:
			continue

		var assigned_worker_ids: Array = []

		for citizen in city_citizens:
			if not citizen is Dictionary:
				continue

			if int(citizen.get("job_object_id", -1)) != workplace_id:
				continue

			var citizen_id := int(citizen.get("id", -1))

			if citizen_id < 0:
				continue

			if assigned_worker_ids.has(citizen_id):
				continue

			if assigned_worker_ids.size() >= worker_capacity:
				break

			assigned_worker_ids.append(citizen_id)

		while assigned_worker_ids.size() < worker_capacity:
			var unemployed_citizen_index := get_first_unemployed_city_citizen_index()

			if unemployed_citizen_index < 0:
				break

			var raw_citizen = city_citizens[unemployed_citizen_index]

			if not raw_citizen is Dictionary:
				break

			var citizen: Dictionary = raw_citizen
			var citizen_id := int(citizen.get("id", -1))

			if citizen_id < 0:
				break

			citizen["job_object_id"] = workplace_id
			city_citizens[unemployed_citizen_index] = citizen

			if not assigned_worker_ids.has(citizen_id):
				assigned_worker_ids.append(citizen_id)
				assigned_count += 1

		city_object["assigned_worker_ids"] = assigned_worker_ids
		city_objects[object_index] = city_object

	return assigned_count

static func get_first_homeless_city_citizen_index() -> int:
	ensure_starting_city_population()

	for citizen_index in range(city_citizens.size()):
		var raw_citizen = city_citizens[citizen_index]

		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if not bool(citizen.get("alive", true)):
			continue

		if int(citizen.get("home_object_id", -1)) >= 0:
			continue

		return citizen_index

	return -1

static func assign_homeless_citizens_to_available_housing() -> int:
	ensure_starting_city_population()

	var assigned_count := 0

	for object_index in range(city_objects.size()):
		var raw_city_object = city_objects[object_index]

		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object
		var object_type := str(city_object.get("type", ""))

		if object_type != CITY_OBJECT_HOUSE:
			continue

		var house_id := int(city_object.get("id", -1))

		if house_id < 0:
			continue

		var resident_capacity := get_city_object_resident_capacity(city_object)

		if resident_capacity <= 0:
			continue

		var resident_ids: Array = []

		for citizen in city_citizens:
			if not citizen is Dictionary:
				continue

			if int(citizen.get("home_object_id", -1)) != house_id:
				continue

			var citizen_id := int(citizen.get("id", -1))

			if citizen_id < 0:
				continue

			if resident_ids.has(citizen_id):
				continue

			if resident_ids.size() >= resident_capacity:
				break

			resident_ids.append(citizen_id)

		while resident_ids.size() < resident_capacity:
			var homeless_citizen_index := get_first_homeless_city_citizen_index()

			if homeless_citizen_index < 0:
				break

			var raw_citizen = city_citizens[homeless_citizen_index]

			if not raw_citizen is Dictionary:
				break

			var citizen: Dictionary = raw_citizen
			var citizen_id := int(citizen.get("id", -1))

			if citizen_id < 0:
				break

			citizen["home_object_id"] = house_id
			city_citizens[homeless_citizen_index] = citizen

			if not resident_ids.has(citizen_id):
				resident_ids.append(citizen_id)
				assigned_count += 1

		city_object["resident_ids"] = resident_ids
		city_objects[object_index] = city_object

	return assigned_count

static func reset_player_city_state() -> void:
	player_city_founded = false
	player_city_data.clear()
	player_city_foundation_top_left = Vector2i(-1, -1)
	player_city_foundation_size = Vector2i.ZERO
	city_resource_amounts.clear()
	reset_city_object_state()
	reset_city_citizen_state()

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

static func make_rectangle_city_object_footprint_tiles(
	top_left: Vector2i,
	size_tiles: Vector2i
) -> Array:
	var footprint_tiles := []

	if size_tiles.x <= 0 or size_tiles.y <= 0:
		return footprint_tiles

	for y in range(top_left.y, top_left.y + size_tiles.y):
		for x in range(top_left.x, top_left.x + size_tiles.x):
			footprint_tiles.append(Vector2i(x, y))

	return footprint_tiles


static func get_city_object_footprint_tiles(city_object: Dictionary) -> Array:
	var footprint_tiles := []

	if city_object.is_empty():
		return footprint_tiles

	if city_object.has("footprint_tiles"):
		var raw_footprint_tiles = city_object.get("footprint_tiles", [])

		if raw_footprint_tiles is Array:
			for tile_position in raw_footprint_tiles:
				if tile_position is Vector2i:
					footprint_tiles.append(tile_position)

			return footprint_tiles

	if city_object.has("tiles"):
		var raw_tiles = city_object.get("tiles", [])

		if raw_tiles is Array:
			for tile_position in raw_tiles:
				if tile_position is Vector2i:
					footprint_tiles.append(tile_position)

			return footprint_tiles

	if city_object.has("top_left") and city_object.has("size"):
		var top_left: Vector2i = city_object.get("top_left", Vector2i(-1, -1))
		var size_tiles: Vector2i = city_object.get("size", Vector2i.ZERO)
		return make_rectangle_city_object_footprint_tiles(top_left, size_tiles)

	return footprint_tiles

static func add_city_object(
	object_type: String,
	top_left: Vector2i,
	size_tiles: Vector2i,
	object_owner: String = "player"
) -> Dictionary:
	var city_object := {
		"id": next_city_object_id,
		"type": object_type,
		"top_left": top_left,
		"size": size_tiles,
		"owner": object_owner
	}

	var definition := get_city_object_definition(object_type)
	var shape_mode := str(definition.get("shape_mode", CITY_OBJECT_SHAPE_RECTANGLE))
	var footprint_tiles := make_rectangle_city_object_footprint_tiles(top_left, size_tiles)

	city_object["shape_mode"] = shape_mode
	city_object["footprint_tiles"] = footprint_tiles

	var resident_capacity := int(definition.get("resident_capacity", 0))

	if resident_capacity > 0:
		city_object["resident_capacity"] = resident_capacity
		city_object["resident_ids"] = []

	if bool(definition.get("is_workplace", false)):
		city_object["is_workplace"] = true
		city_object["workplace_kind"] = str(definition.get("workplace_kind", WORKPLACE_KIND_NONE))
		city_object["worker_capacity"] = int(definition.get("worker_capacity", 0))
		city_object["assigned_worker_ids"] = []
		city_object["output_resource"] = str(definition.get("output_resource", RESOURCE_NONE))

	var starting_storage := make_empty_city_object_storage_for_type(object_type)

	if not starting_storage.is_empty():
		city_object["stored_resources"] = starting_storage

	next_city_object_id += 1

	city_objects.append(city_object)
	occupy_city_object_tiles(city_object)

	var should_refresh_city_ui := false

	if not starting_storage.is_empty():
		should_refresh_city_ui = true

	if object_type == CITY_OBJECT_HOUSE:
		assign_homeless_citizens_to_available_housing()
		should_refresh_city_ui = true

	if city_object_is_workplace(city_object):
		assign_unemployed_citizens_to_available_workplaces()
		should_refresh_city_ui = true

	if should_refresh_city_ui:
		city_storage_version += 1

	return city_object

static func make_empty_resource_container(resource_list: Array) -> Dictionary:
	var stored_resources := {}

	for resource in resource_list:
		stored_resources[str(resource)] = 0

	return stored_resources


static func make_empty_city_object_storage_for_type(object_type: String) -> Dictionary:
	var definition := get_city_object_definition(object_type)

	if definition.is_empty():
		return {}

	var storage_resources: Array = definition.get("storage_resources", [])

	if storage_resources.is_empty():
		return {}

	return make_empty_resource_container(storage_resources)


static func get_city_object_definition_from_object(city_object: Dictionary) -> Dictionary:
	if city_object.is_empty():
		return {}

	return get_city_object_definition(str(city_object.get("type", "")))


static func get_city_object_container_type(city_object: Dictionary) -> String:
	var definition := get_city_object_definition_from_object(city_object)

	if definition.is_empty():
		return CONTAINER_TYPE_NONE

	return str(definition.get("container_type", CONTAINER_TYPE_NONE))


static func city_object_counts_as_public_city_storage(city_object: Dictionary) -> bool:
	var definition := get_city_object_definition_from_object(city_object)

	if definition.is_empty():
		return false

	return bool(definition.get("counts_as_public_city_storage", false))


static func get_city_object_storage_resources(city_object: Dictionary) -> Array[String]:
	var definition := get_city_object_definition_from_object(city_object)

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
	var definition := get_city_object_definition_from_object(city_object)

	if definition.is_empty():
		return 0

	return int(definition.get("storage_capacity_per_resource", 0))


static func get_city_object_storage_capacity_for_resource(city_object: Dictionary, resource: String) -> int:
	if not can_city_object_store_resource(city_object, resource):
		return 0

	return get_city_object_storage_capacity_per_resource(city_object)


static func get_city_object_stored_resource_amount(city_object: Dictionary, resource: String) -> int:
	if city_object.is_empty():
		return 0

	if not can_city_object_store_resource(city_object, resource):
		return 0

	var stored_resources = city_object.get("stored_resources", {})

	if not stored_resources is Dictionary:
		return 0

	return int(stored_resources.get(resource, 0))


static func get_city_object_resource_free_space(city_object: Dictionary, resource: String) -> int:
	var capacity := get_city_object_storage_capacity_for_resource(city_object, resource)

	if capacity <= 0:
		return 0

	var amount := get_city_object_stored_resource_amount(city_object, resource)
	return max(0, capacity - amount)


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
		var capacity: int = get_city_object_storage_capacity_for_resource(city_object, resource)

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


static func add_resource_to_city_object_storage(
	object_id: int,
	resource: String,
	amount_delta: int
) -> int:
	if amount_delta <= 0:
		return 0

	for i in range(city_objects.size()):
		var city_object: Dictionary = city_objects[i]

		if int(city_object.get("id", -1)) != object_id:
			continue

		if not can_city_object_store_resource(city_object, resource):
			return 0

		var free_space := get_city_object_resource_free_space(city_object, resource)

		if free_space <= 0:
			return 0

		var accepted_amount: int = min(amount_delta, free_space)
		var current_amount := get_city_object_stored_resource_amount(city_object, resource)

		set_city_object_stored_resource_amount(
			object_id,
			resource,
			current_amount + accepted_amount
		)

		return accepted_amount

	return 0

static func occupy_city_object_tiles(city_object: Dictionary) -> void:
	var object_id: int = int(city_object.get("id", -1))

	if object_id < 0:
		return

	var footprint_tiles := get_city_object_footprint_tiles(city_object)

	for tile_position in footprint_tiles:
		if not tile_position is Vector2i:
			continue

		city_occupied_tiles[tile_position] = object_id

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


static func add_city_road_object(tile_positions: Array, object_owner: String = "player") -> Dictionary:
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
		"owner": object_owner
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
