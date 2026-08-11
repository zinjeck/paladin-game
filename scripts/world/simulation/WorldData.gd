extends RefCounted
class_name WorldData

# File responsibility: Authoritative world and city state, mutation APIs, indexes, and session-level caches.
# Navigation regions are organizational only; they do not define runtime ownership.

const CityCitizensScript = preload(
	"res://scripts/citizens/simulation/CityCitizens.gd"
)
const CultureDataScript = preload(
	"res://scripts/world/simulation/CultureData.gd"
)
const CityResourceCatalogScript = preload(
	"res://scripts/city/data/CityResourceCatalog.gd"
)
const CityObjectCatalogScript = preload(
	"res://scripts/city/data/CityObjectCatalog.gd"
)
const MapTextureCacheStateScript = preload(
	"res://scripts/map/visuals/MapTextureCacheState.gd"
)
const MapCameraSessionStateScript = preload(
	"res://scripts/map/MapCameraSessionState.gd"
)

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

const RESOURCE_NONE := CityResourceCatalogScript.RESOURCE_NONE
const RESOURCE_IRON := CityResourceCatalogScript.RESOURCE_IRON
const RESOURCE_COAL := CityResourceCatalogScript.RESOURCE_COAL
const RESOURCE_GOLD := CityResourceCatalogScript.RESOURCE_GOLD
const RESOURCE_FISH := CityResourceCatalogScript.RESOURCE_FISH
const RESOURCE_MEAT := CityResourceCatalogScript.RESOURCE_MEAT
const RESOURCE_LUMBER := CityResourceCatalogScript.RESOURCE_LUMBER
const RESOURCE_STONE := CityResourceCatalogScript.RESOURCE_STONE

const CITY_SURFACE_FEATURE_NONE := "none"
const CITY_SURFACE_FEATURE_TREE := "tree"
const CITY_SURFACE_FEATURE_ROCK := "rock"

var width: int
var height: int
var seed: int
var tiles := []
var tile_data_version: int = 0
var city_surface_feature_change_version: int = 0
var pending_city_surface_feature_changes: Array[Dictionary] = []
# City generation records its initial natural-feature positions while it is
# already traversing the map. The renderer may consume these immutable lists
# instead of immediately rescanning every tile. Any later tile-data version
# invalidates them automatically.
var prepared_city_tree_tiles: Array[Vector2i] = []
var prepared_city_rock_tiles: Array[Vector2i] = []
var prepared_city_feature_tile_data_version: int = -1

static var city_start_world_seed: int = 0
static var city_start_region_center: Vector2i = Vector2i(-1, -1)
static var city_start_region_top_left: Vector2i = Vector2i(-1, -1)
static var city_start_region_size: int = 0
static var city_start_tiles: Array = []
static var city_return_world_scene_path: String = ""
static var save_locked: bool = false
static var player_city_foundation_top_left: Vector2i = Vector2i(-1, -1)
static var player_city_foundation_size: Vector2i = Vector2i.ZERO
static var official_world = null
static var official_city_world = null
static var official_city_seed: int = 0
static var player_city_founded: bool = false
static var player_city_data: Dictionary = {}
static var debug_mode_enabled: bool = false

const INVALID_CULTURE_ID: int = CultureDataScript.INVALID_CULTURE_ID
const MAX_FOUNDING_NAME_LENGTH: int = 40
static var cultures: Array = []
static var culture_index_by_id: Dictionary = {}
static var next_culture_id: int = 1
static var official_city_name: String = ""
static var official_founding_culture_id: int = INVALID_CULTURE_ID


static var official_selected_region_center: Vector2i = Vector2i(-1, -1)
static var official_selected_region_top_left: Vector2i = Vector2i(-1, -1)
static var official_region_size: int = 0

static var official_world_scene_path: String = ""
static var official_city_scene_path: String = ""

const STARTING_CITY_POPULATION := 8
const CITY_CITIZEN_SEX_MALE := (
	CityCitizensScript.CITY_CITIZEN_SEX_MALE
)
const CITY_CITIZEN_SEX_FEMALE := (
	CityCitizensScript.CITY_CITIZEN_SEX_FEMALE
)
const STARTING_CITY_MALE_POPULATION: int = 4
const STARTING_CITY_FEMALE_POPULATION: int = 4
const CITY_CITIZEN_STATE_IDLE := (
	CityCitizensScript.CITY_CITIZEN_STATE_IDLE
)
const CITY_CITIZEN_TASK_KIND_NONE: String = (
	CityCitizensScript.CITY_CITIZEN_TASK_KIND_NONE
)
const CITY_CITIZEN_TASK_KIND_WORK: String = (
	CityCitizensScript.CITY_CITIZEN_TASK_KIND_WORK
)
const CITY_CITIZEN_TASK_KIND_HAUL: String = (
	CityCitizensScript.CITY_CITIZEN_TASK_KIND_HAUL
)
const CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD: String = (
	CityCitizensScript.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD
)
const CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND: String = (
	CityCitizensScript.CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND
)
const CITY_CITIZEN_TASK_KIND_CONSTRUCTION: String = (
	CityCitizensScript.CITY_CITIZEN_TASK_KIND_CONSTRUCTION
)
const CITY_CITIZEN_TASK_KIND_RETURN_HOME: String = (
	CityCitizensScript.CITY_CITIZEN_TASK_KIND_RETURN_HOME
)
const CITY_CITIZEN_TASK_SOURCE_NONE: String = (
	CityCitizensScript.CITY_CITIZEN_TASK_SOURCE_NONE
)
const CITY_CITIZEN_TASK_SOURCE_PLAYER: String = (
	CityCitizensScript.CITY_CITIZEN_TASK_SOURCE_PLAYER
)
const CITY_CITIZEN_TASK_SOURCE_SCHEDULE: String = (
	CityCitizensScript.CITY_CITIZEN_TASK_SOURCE_SCHEDULE
)
const CITY_CITIZEN_TASK_SOURCE_AUTONOMY: String = (
	CityCitizensScript.CITY_CITIZEN_TASK_SOURCE_AUTONOMY
)
const CITY_CITIZEN_TASK_PHASE_NONE: String = (
	CityCitizensScript.CITY_CITIZEN_TASK_PHASE_NONE
)
const CITY_CITIZEN_TASK_PHASE_PENDING: String = (
	CityCitizensScript.CITY_CITIZEN_TASK_PHASE_PENDING
)
const CITY_CITIZEN_TASK_PHASE_TRAVELING: String = (
	CityCitizensScript.CITY_CITIZEN_TASK_PHASE_TRAVELING
)
const CITY_CITIZEN_TASK_PHASE_PERFORMING: String = (
	CityCitizensScript.CITY_CITIZEN_TASK_PHASE_PERFORMING
)
const CITY_CITIZEN_TASK_PHASE_BLOCKED: String = (
	CityCitizensScript.CITY_CITIZEN_TASK_PHASE_BLOCKED
)
const CITY_CITIZEN_TASK_PRIORITY_NONE: int = (
	CityCitizensScript.CITY_CITIZEN_TASK_PRIORITY_NONE
)
const INVALID_CITY_CITIZEN_TASK_START_WORLD_MINUTE: int = (
	CityCitizensScript.INVALID_CITY_CITIZEN_TASK_START_WORLD_MINUTE
)
const INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE: int = (
	CityCitizensScript.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
)

const CITY_TOPOLOGY_MUTATION_FAILURE_NONE := "none"
const CITY_TOPOLOGY_MUTATION_FAILURE_INVALID_REQUEST := (
	"invalid_request"
)
const CITY_TOPOLOGY_MUTATION_FAILURE_TILE_BLOCKED := "tile_blocked"
const CITY_TOPOLOGY_MUTATION_FAILURE_FOOTPRINT_OCCUPIED := (
	"footprint_occupied"
)
const CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE: String = (
	CityCitizensScript.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
)
const CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER: String = (
	CityCitizensScript
	.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER
)
const CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE: String = (
	CityCitizensScript.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE
)
const CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_TILE: String = (
	CityCitizensScript.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_TILE
)
const CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE: String = (
	CityCitizensScript
	.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE
)
const CITY_CITIZEN_HAUL_REASON_NONE: String = (
	CityCitizensScript.CITY_CITIZEN_HAUL_REASON_NONE
)
const CITY_CITIZEN_HAUL_REASON_WORKPLACE_OUTPUT_BEFORE_HOME: String = (
	CityCitizensScript
	.CITY_CITIZEN_HAUL_REASON_WORKPLACE_OUTPUT_BEFORE_HOME
)
const CITY_CITIZEN_HAUL_REASON_AUTONOMOUS_WORKPLACE_OUTPUT: String = (
	CityCitizensScript
	.CITY_CITIZEN_HAUL_REASON_AUTONOMOUS_WORKPLACE_OUTPUT
)
const CITY_CITIZEN_HAUL_REASON_GROUND_PILE_CLEANUP: String = (
	CityCitizensScript.CITY_CITIZEN_HAUL_REASON_GROUND_PILE_CLEANUP
)
const CITY_CITIZEN_HAUL_REASON_SCHEDULED_HOME_FOOD_DELIVERY: String = (
	CityCitizensScript
	.CITY_CITIZEN_HAUL_REASON_SCHEDULED_HOME_FOOD_DELIVERY
)
const CITY_CITIZEN_HAUL_REASON_AUTONOMOUS_HOME_FOOD_DELIVERY: String = (
	CityCitizensScript
	.CITY_CITIZEN_HAUL_REASON_AUTONOMOUS_HOME_FOOD_DELIVERY
)
const CITY_CITIZEN_HAUL_REASON_OUTSTANDING_CARGO: String = (
	CityCitizensScript.CITY_CITIZEN_HAUL_REASON_OUTSTANDING_CARGO
)
const CITY_CITIZEN_HAUL_REASON_CONSTRUCTION_DELIVERY: String = (
	CityCitizensScript.CITY_CITIZEN_HAUL_REASON_CONSTRUCTION_DELIVERY
)
const INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID: int = (
	CityCitizensScript.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
)
const CITY_CITIZEN_HAUL_PHASE_NONE: String = (
	CityCitizensScript.CITY_CITIZEN_HAUL_PHASE_NONE
)
const CITY_CITIZEN_HAUL_PHASE_PENDING_SOURCE: String = (
	CityCitizensScript.CITY_CITIZEN_HAUL_PHASE_PENDING_SOURCE
)
const CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_SOURCE: String = (
	CityCitizensScript.CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_SOURCE
)
const CITY_CITIZEN_HAUL_PHASE_PICKING_UP: String = (
	CityCitizensScript.CITY_CITIZEN_HAUL_PHASE_PICKING_UP
)
const CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION: String = (
	CityCitizensScript.CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION
)
const CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_DESTINATION: String = (
	CityCitizensScript
	.CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_DESTINATION
)
const CITY_CITIZEN_HAUL_PHASE_DEPOSITING: String = (
	CityCitizensScript.CITY_CITIZEN_HAUL_PHASE_DEPOSITING
)
const CITY_CITIZEN_HAUL_PHASE_RETARGETING: String = (
	CityCitizensScript.CITY_CITIZEN_HAUL_PHASE_RETARGETING
)
const CITY_CITIZEN_HAUL_PHASE_BLOCKED: String = (
	CityCitizensScript.CITY_CITIZEN_HAUL_PHASE_BLOCKED
)
const INVALID_CITY_TILE_POSITION := (
	CityCitizensScript.INVALID_CITY_TILE_POSITION
)
const CITY_CITIZEN_MOVEMENT_STATE_IDLE := (
	CityCitizensScript.CITY_CITIZEN_MOVEMENT_STATE_IDLE
)
const CITY_CITIZEN_MOVEMENT_STATE_MOVING := (
	CityCitizensScript.CITY_CITIZEN_MOVEMENT_STATE_MOVING
)
const CITY_CITIZEN_MOVEMENT_STATE_BLOCKED := (
	CityCitizensScript.CITY_CITIZEN_MOVEMENT_STATE_BLOCKED
)
const CITY_CITIZEN_MOVEMENT_FAILURE_NONE := (
	CityCitizensScript.CITY_CITIZEN_MOVEMENT_FAILURE_NONE
)
const CITY_CITIZEN_MOVEMENT_FAILURE_INVALID_PATH := (
	CityCitizensScript.CITY_CITIZEN_MOVEMENT_FAILURE_INVALID_PATH
)
const CITY_CITIZEN_MOVEMENT_FAILURE_NEXT_TILE_BLOCKED := (
	CityCitizensScript.CITY_CITIZEN_MOVEMENT_FAILURE_NEXT_TILE_BLOCKED
)
const CITY_CITIZEN_MOVEMENT_FAILURE_REPATH_FAILED := (
	CityCitizensScript.CITY_CITIZEN_MOVEMENT_FAILURE_REPATH_FAILED
)
const CITY_CITIZEN_CARDINAL_MOVEMENT_COST := (
	CityCitizensScript.CITY_CITIZEN_CARDINAL_MOVEMENT_COST
)
const CITY_CITIZEN_DIAGONAL_MOVEMENT_COST := (
	CityCitizensScript.CITY_CITIZEN_DIAGONAL_MOVEMENT_COST
)
const CITY_ROAD_MOVEMENT_SPEED_MULTIPLIER := (
	CityCitizensScript.CITY_ROAD_MOVEMENT_SPEED_MULTIPLIER
)
const CITY_CITIZEN_ROAD_CARDINAL_MOVEMENT_COST := (
	CityCitizensScript.CITY_CITIZEN_ROAD_CARDINAL_MOVEMENT_COST
)
const CITY_CITIZEN_ROAD_DIAGONAL_MOVEMENT_COST := (
	CityCitizensScript.CITY_CITIZEN_ROAD_DIAGONAL_MOVEMENT_COST
)
const CITY_CITIZEN_MOVEMENT_PROGRESS_PER_TILE := (
	CityCitizensScript.CITY_CITIZEN_MOVEMENT_PROGRESS_PER_TILE
)
const DEFAULT_CITIZEN_MOVEMENT_SPEED_PER_MINUTE := (
	CityCitizensScript.DEFAULT_CITIZEN_MOVEMENT_SPEED_PER_MINUTE
)
const MAX_CITIZEN_MOVEMENT_REPATH_ATTEMPTS := (
	CityCitizensScript.MAX_CITIZEN_MOVEMENT_REPATH_ATTEMPTS
)
const CITY_CARDINAL_TILE_OFFSETS := [
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(0, 1)
]
const CITY_OBJECT_CITY_CENTER := CityObjectCatalogScript.CITY_OBJECT_CITY_CENTER
const CITY_OBJECT_HOUSE := CityObjectCatalogScript.CITY_OBJECT_HOUSE
const CITY_OBJECT_STOCKPILE := CityObjectCatalogScript.CITY_OBJECT_STOCKPILE
const CITY_OBJECT_FISHING_GROUNDS := CityObjectCatalogScript.CITY_OBJECT_FISHING_GROUNDS
const CITY_OBJECT_PLACEHOLDER_BUILDING := CityObjectCatalogScript.CITY_OBJECT_PLACEHOLDER_BUILDING
const CITY_OBJECT_ROAD := CityObjectCatalogScript.CITY_OBJECT_ROAD
const CITY_OBJECT_PLACEMENT_EFFECT_NONE := CityObjectCatalogScript.CITY_OBJECT_PLACEMENT_EFFECT_NONE
const CITY_OBJECT_PLACEMENT_EFFECT_FOUND_CITY := CityObjectCatalogScript.CITY_OBJECT_PLACEMENT_EFFECT_FOUND_CITY
const CITY_OBJECT_SHAPE_RECTANGLE := CityObjectCatalogScript.CITY_OBJECT_SHAPE_RECTANGLE
const CITY_OBJECT_SHAPE_TILE_AREA := CityObjectCatalogScript.CITY_OBJECT_SHAPE_TILE_AREA
const WORKPLACE_KIND_NONE := CityObjectCatalogScript.WORKPLACE_KIND_NONE
const WORKPLACE_KIND_GATHERING := CityObjectCatalogScript.WORKPLACE_KIND_GATHERING

const WORKPLACE_ANCHOR_MODE_FOOTPRINT_CENTER := CityObjectCatalogScript.WORKPLACE_ANCHOR_MODE_FOOTPRINT_CENTER
const WORKPLACE_ANCHOR_MODE_EXPLICIT_POINT := CityObjectCatalogScript.WORKPLACE_ANCHOR_MODE_EXPLICIT_POINT
const WORKPLACE_ANCHOR_MODE_EXPLICIT_TILE := CityObjectCatalogScript.WORKPLACE_ANCHOR_MODE_EXPLICIT_TILE

const WORKPLACE_RESOURCE_SOURCE_MODE_NONE := CityObjectCatalogScript.WORKPLACE_RESOURCE_SOURCE_MODE_NONE
const WORKPLACE_RESOURCE_SOURCE_MODE_RADIUS := CityObjectCatalogScript.WORKPLACE_RESOURCE_SOURCE_MODE_RADIUS
const WORKPLACE_RESOURCE_SOURCE_MODE_FOOTPRINT_REACH := CityObjectCatalogScript.WORKPLACE_RESOURCE_SOURCE_MODE_FOOTPRINT_REACH
const WORKPLACE_RESOURCE_SOURCE_MODE_LINKED_TILES := CityObjectCatalogScript.WORKPLACE_RESOURCE_SOURCE_MODE_LINKED_TILES
const WORKPLACE_RESOURCE_SOURCE_MODE_LINKED_OBJECTS := CityObjectCatalogScript.WORKPLACE_RESOURCE_SOURCE_MODE_LINKED_OBJECTS
const WORKPLACE_RESOURCE_SOURCE_MODE_STORED_INPUTS := CityObjectCatalogScript.WORKPLACE_RESOURCE_SOURCE_MODE_STORED_INPUTS
const WORKPLACE_RESOURCE_SOURCE_MODE_EXPLICIT_WORK_POINTS := CityObjectCatalogScript.WORKPLACE_RESOURCE_SOURCE_MODE_EXPLICIT_WORK_POINTS

const WORKPLACE_WORK_LOCATION_MODE_NONE := CityObjectCatalogScript.WORKPLACE_WORK_LOCATION_MODE_NONE
const WORKPLACE_WORK_LOCATION_MODE_RESOURCE_SOURCE_TILES := CityObjectCatalogScript.WORKPLACE_WORK_LOCATION_MODE_RESOURCE_SOURCE_TILES
const WORKPLACE_WORK_LOCATION_MODE_LINKED_TILES := CityObjectCatalogScript.WORKPLACE_WORK_LOCATION_MODE_LINKED_TILES
const WORKPLACE_WORK_LOCATION_MODE_WORKSTATIONS := CityObjectCatalogScript.WORKPLACE_WORK_LOCATION_MODE_WORKSTATIONS
const WORKPLACE_WORK_LOCATION_MODE_EXPLICIT_POINTS := CityObjectCatalogScript.WORKPLACE_WORK_LOCATION_MODE_EXPLICIT_POINTS
const WORKPLACE_WORK_LOCATION_MODE_FOOTPRINT := CityObjectCatalogScript.WORKPLACE_WORK_LOCATION_MODE_FOOTPRINT
const WORKPLACE_WORK_LOCATION_ZONE_SOURCE_RESOURCE_SOURCE := CityObjectCatalogScript.WORKPLACE_WORK_LOCATION_ZONE_SOURCE_RESOURCE_SOURCE
const WORKPLACE_WORK_LOCATION_TILE_REQUIREMENT_WALKABLE := CityObjectCatalogScript.WORKPLACE_WORK_LOCATION_TILE_REQUIREMENT_WALKABLE
const WORKPLACE_WORK_LOCATION_ADJACENCY_NONE := CityObjectCatalogScript.WORKPLACE_WORK_LOCATION_ADJACENCY_NONE
const WORKPLACE_WORK_LOCATION_ADJACENCY_CARDINAL_TERRAIN := CityObjectCatalogScript.WORKPLACE_WORK_LOCATION_ADJACENCY_CARDINAL_TERRAIN

const WORKPLACE_MOVEMENT_MODE_NONE := CityObjectCatalogScript.WORKPLACE_MOVEMENT_MODE_NONE
const WORKPLACE_MOVEMENT_MODE_MOVE_BETWEEN_WORK_POINTS := CityObjectCatalogScript.WORKPLACE_MOVEMENT_MODE_MOVE_BETWEEN_WORK_POINTS
const WORKPLACE_MOVEMENT_MODE_STATION_BASED := CityObjectCatalogScript.WORKPLACE_MOVEMENT_MODE_STATION_BASED
const WORKPLACE_MOVEMENT_MODE_REMAIN_AT_STATION := CityObjectCatalogScript.WORKPLACE_MOVEMENT_MODE_REMAIN_AT_STATION
const WORKPLACE_MOVEMENT_MODE_LINKED_TILE_TASKS := CityObjectCatalogScript.WORKPLACE_MOVEMENT_MODE_LINKED_TILE_TASKS

const WORKPLACE_BREAK_LOCATION_MODE_NONE := CityObjectCatalogScript.WORKPLACE_BREAK_LOCATION_MODE_NONE
const WORKPLACE_BREAK_LOCATION_MODE_FOOTPRINT := CityObjectCatalogScript.WORKPLACE_BREAK_LOCATION_MODE_FOOTPRINT
const WORKPLACE_BREAK_LOCATION_MODE_FOOTPRINT_RADIUS := CityObjectCatalogScript.WORKPLACE_BREAK_LOCATION_MODE_FOOTPRINT_RADIUS
const WORKPLACE_BREAK_LOCATION_MODE_LINKED_AREA := CityObjectCatalogScript.WORKPLACE_BREAK_LOCATION_MODE_LINKED_AREA
const WORKPLACE_BREAK_LOCATION_MODE_EXPLICIT_TILES := CityObjectCatalogScript.WORKPLACE_BREAK_LOCATION_MODE_EXPLICIT_TILES
const WORKPLACE_BREAK_LOCATION_MODE_WORK_AREA := CityObjectCatalogScript.WORKPLACE_BREAK_LOCATION_MODE_WORK_AREA
const WORKPLACE_BREAK_LOCATION_MODE_INTERIOR := CityObjectCatalogScript.WORKPLACE_BREAK_LOCATION_MODE_INTERIOR

const WORKPLACE_OVERFLOW_MODE_NONE := CityObjectCatalogScript.WORKPLACE_OVERFLOW_MODE_NONE
const WORKPLACE_OVERFLOW_MODE_FOOTPRINT_RADIUS := CityObjectCatalogScript.WORKPLACE_OVERFLOW_MODE_FOOTPRINT_RADIUS
const WORKPLACE_OVERFLOW_MODE_EXPLICIT_TILES := CityObjectCatalogScript.WORKPLACE_OVERFLOW_MODE_EXPLICIT_TILES
const WORKPLACE_OVERFLOW_MODE_LINKED_AREA := CityObjectCatalogScript.WORKPLACE_OVERFLOW_MODE_LINKED_AREA

const PRODUCTIVITY_BASIS_POINTS_SCALE := CityObjectCatalogScript.PRODUCTIVITY_BASIS_POINTS_SCALE
const DEFAULT_WORKPLACE_SITE_PRODUCTIVITY_BASIS_POINTS := CityObjectCatalogScript.DEFAULT_WORKPLACE_SITE_PRODUCTIVITY_BASIS_POINTS

const WORKPLACE_PRODUCTION_STATUS_INACTIVE := CityObjectCatalogScript.WORKPLACE_PRODUCTION_STATUS_INACTIVE
const WORKPLACE_PRODUCTION_STATUS_IDLE_NO_WORKERS := CityObjectCatalogScript.WORKPLACE_PRODUCTION_STATUS_IDLE_NO_WORKERS
const WORKPLACE_PRODUCTION_STATUS_WORKING := CityObjectCatalogScript.WORKPLACE_PRODUCTION_STATUS_WORKING
const WORKPLACE_PRODUCTION_STATUS_BLOCKED_OUTPUT_FULL := CityObjectCatalogScript.WORKPLACE_PRODUCTION_STATUS_BLOCKED_OUTPUT_FULL
const WORKPLACE_PRODUCTION_STATUS_BLOCKED_MISSING_INPUT := CityObjectCatalogScript.WORKPLACE_PRODUCTION_STATUS_BLOCKED_MISSING_INPUT
const WORKPLACE_PRODUCTION_STATUS_BLOCKED_NO_RESOURCE_SOURCE := CityObjectCatalogScript.WORKPLACE_PRODUCTION_STATUS_BLOCKED_NO_RESOURCE_SOURCE
const CITY_WORKPLACE_PRODUCTION_STATE_KEYS := CityObjectCatalogScript.CITY_WORKPLACE_PRODUCTION_STATE_KEYS

const CONTAINER_TYPE_NONE := CityObjectCatalogScript.CONTAINER_TYPE_NONE
const CONTAINER_TYPE_PUBLIC_CITY_STORAGE := CityObjectCatalogScript.CONTAINER_TYPE_PUBLIC_CITY_STORAGE
const CONTAINER_TYPE_PRIVATE_HOME_STORAGE := CityObjectCatalogScript.CONTAINER_TYPE_PRIVATE_HOME_STORAGE
const CONTAINER_TYPE_WORKPLACE_STORAGE := CityObjectCatalogScript.CONTAINER_TYPE_WORKPLACE_STORAGE
const CONTAINER_TYPE_PERSONAL_INVENTORY := CityObjectCatalogScript.CONTAINER_TYPE_PERSONAL_INVENTORY
const CONTAINER_TYPE_GROUND_PILE := CityObjectCatalogScript.CONTAINER_TYPE_GROUND_PILE

const CONTAINER_ACCESS_COUNTS_TOWARD_CITY_OWNED_TOTALS := CityObjectCatalogScript.CONTAINER_ACCESS_COUNTS_TOWARD_CITY_OWNED_TOTALS
const CONTAINER_ACCESS_PUBLICLY_USABLE := CityObjectCatalogScript.CONTAINER_ACCESS_PUBLICLY_USABLE
const CONTAINER_ACCESS_HAUL_DEPOSIT_PURPOSES := CityObjectCatalogScript.CONTAINER_ACCESS_HAUL_DEPOSIT_PURPOSES
const CONTAINER_ACCESS_HAUL_WITHDRAWAL_PURPOSES := CityObjectCatalogScript.CONTAINER_ACCESS_HAUL_WITHDRAWAL_PURPOSES
const CONTAINER_ACCESS_DIRECT_WITHDRAWAL_PURPOSES := CityObjectCatalogScript.CONTAINER_ACCESS_DIRECT_WITHDRAWAL_PURPOSES
const CONTAINER_HAUL_PURPOSE_NONE := CityObjectCatalogScript.CONTAINER_HAUL_PURPOSE_NONE
const CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE := CityObjectCatalogScript.CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE
const CONTAINER_HAUL_PURPOSE_HOME_DELIVERY := CityObjectCatalogScript.CONTAINER_HAUL_PURPOSE_HOME_DELIVERY
const CONTAINER_HAUL_PURPOSE_WORKPLACE_OUTPUT := CityObjectCatalogScript.CONTAINER_HAUL_PURPOSE_WORKPLACE_OUTPUT
const CONTAINER_HAUL_PURPOSE_GROUND_PILE_CLEANUP := CityObjectCatalogScript.CONTAINER_HAUL_PURPOSE_GROUND_PILE_CLEANUP
const CONTAINER_HAUL_PURPOSE_CONSTRUCTION: String = (
	CityObjectCatalogScript.CONTAINER_HAUL_PURPOSE_CONSTRUCTION
)
const CONTAINER_HAUL_PURPOSE_HOUSEHOLD_FOOD_SOURCE: String = (
	CityObjectCatalogScript.CONTAINER_HAUL_PURPOSE_HOUSEHOLD_FOOD_SOURCE
)
const CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_NONE := CityObjectCatalogScript.CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_NONE
const CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_PERSONAL_FOOD := CityObjectCatalogScript.CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_PERSONAL_FOOD

const PUBLIC_CITY_STORAGE_TIER_NONE: int = CityObjectCatalogScript.PUBLIC_CITY_STORAGE_TIER_NONE
const PUBLIC_CITY_STORAGE_TIER_STOCKPILE: int = CityObjectCatalogScript.PUBLIC_CITY_STORAGE_TIER_STOCKPILE
const PUBLIC_CITY_STORAGE_TIER_CITY_KEEP: int = CityObjectCatalogScript.PUBLIC_CITY_STORAGE_TIER_CITY_KEEP

const CITY_OBJECT_INTERIOR_ACCESS_NONE := CityObjectCatalogScript.CITY_OBJECT_INTERIOR_ACCESS_NONE
const CITY_OBJECT_INTERIOR_ACCESS_RESIDENTS := CityObjectCatalogScript.CITY_OBJECT_INTERIOR_ACCESS_RESIDENTS
const CITY_OBJECT_INTERIOR_ACCESS_ASSIGNED_WORKERS := CityObjectCatalogScript.CITY_OBJECT_INTERIOR_ACCESS_ASSIGNED_WORKERS
const CITY_OBJECT_INTERIOR_ACCESS_TASK_TARGET := CityObjectCatalogScript.CITY_OBJECT_INTERIOR_ACCESS_TASK_TARGET
const CITY_OBJECT_INTERIOR_ACCESS_PUBLIC := CityObjectCatalogScript.CITY_OBJECT_INTERIOR_ACCESS_PUBLIC

const CITY_OBJECT_ENTRY_MODE_ANY_BOUNDARY := CityObjectCatalogScript.CITY_OBJECT_ENTRY_MODE_ANY_BOUNDARY
const CITY_OBJECT_ENTRY_MODE_EXPLICIT_TILES := CityObjectCatalogScript.CITY_OBJECT_ENTRY_MODE_EXPLICIT_TILES

#region City Object Definitions and Workplace Policies

static func ensure_city_object_definitions_ready() -> void:
	CityObjectCatalogScript.ensure_city_object_definitions_ready()

static func setup_city_object_definitions() -> void:
	CityObjectCatalogScript.setup_city_object_definitions()

static func make_city_object_definition(values: Dictionary) -> Dictionary:
	return CityObjectCatalogScript.make_city_object_definition(values)

static func _get_recipe_output_resource_types(
	production_recipe: Dictionary
) -> Array[String]:
	return (
		CityObjectCatalogScript
		._get_recipe_output_resource_types(production_recipe)
	)

static func get_city_object_definition(object_type: String) -> Dictionary:
	return CityObjectCatalogScript.get_city_object_definition(object_type)


static func get_city_object_definition_from_object(
	city_object: Dictionary
) -> Dictionary:
	if city_object.is_empty():
		return {}

	return get_city_object_definition(str(city_object.get("type", "")))


# Workplace policies are shared, immutable definition data.
# Callers must treat the returned dictionaries as read-only.
static func _get_city_object_definition_dictionary(
	city_object: Dictionary,
	definition_field: String
) -> Dictionary:
	return (
		CityObjectCatalogScript
		._get_city_object_definition_dictionary(
			city_object,
			definition_field
		)
	)


static func get_city_object_production_recipe(
	city_object: Dictionary
) -> Dictionary:
	return _get_city_object_definition_dictionary(
		city_object,
		"production_recipe"
	)


static func get_city_object_resource_source_policy(
	city_object: Dictionary
) -> Dictionary:
	return _get_city_object_definition_dictionary(
		city_object,
		"resource_source_policy"
	)


static func get_city_object_work_location_policy(
	city_object: Dictionary
) -> Dictionary:
	return _get_city_object_definition_dictionary(
		city_object,
		"work_location_policy"
	)


static func get_city_object_work_movement_policy(
	city_object: Dictionary
) -> Dictionary:
	return _get_city_object_definition_dictionary(
		city_object,
		"work_movement_policy"
	)


static func get_city_object_break_location_policy(
	city_object: Dictionary
) -> Dictionary:
	return _get_city_object_definition_dictionary(
		city_object,
		"break_location_policy"
	)


static func get_city_object_overflow_policy(
	city_object: Dictionary
) -> Dictionary:
	return _get_city_object_definition_dictionary(
		city_object,
		"overflow_policy"
	)


static func get_city_object_production_progress_work_units(
	city_object: Dictionary
) -> int:
	return (
		CityObjectCatalogScript
		.get_city_object_production_progress_work_units(city_object)
	)


static func get_city_object_production_status(
	city_object: Dictionary
) -> String:
	return (
		CityObjectCatalogScript
		.get_city_object_production_status(city_object)
	)


static func get_city_object_productive_worker_count(
	city_object: Dictionary
) -> int:
	return (
		CityObjectCatalogScript
		.get_city_object_productive_worker_count(city_object)
	)


static func get_city_object_site_productivity_basis_points(
	city_object: Dictionary
) -> int:
	return (
		CityObjectCatalogScript
		.get_city_object_site_productivity_basis_points(city_object)
	)


static func is_valid_workplace_anchor_mode(mode: String) -> bool:
	return CityObjectCatalogScript.is_valid_workplace_anchor_mode(mode)


static func is_valid_workplace_resource_source_mode(mode: String) -> bool:
	return (
		CityObjectCatalogScript
		.is_valid_workplace_resource_source_mode(mode)
	)


static func is_valid_workplace_work_location_mode(mode: String) -> bool:
	return (
		CityObjectCatalogScript
		.is_valid_workplace_work_location_mode(mode)
	)


static func is_valid_workplace_movement_mode(mode: String) -> bool:
	return CityObjectCatalogScript.is_valid_workplace_movement_mode(mode)


static func is_valid_workplace_break_location_mode(mode: String) -> bool:
	return (
		CityObjectCatalogScript
		.is_valid_workplace_break_location_mode(mode)
	)


static func is_valid_workplace_overflow_mode(mode: String) -> bool:
	return CityObjectCatalogScript.is_valid_workplace_overflow_mode(mode)


static func is_valid_city_workplace_production_status(
	production_status: String
) -> bool:
	return (
		CityObjectCatalogScript
		.is_valid_city_workplace_production_status(production_status)
	)


static func set_city_workplace_production_state(
	values: Dictionary
) -> bool:
	for raw_key in CITY_WORKPLACE_PRODUCTION_STATE_KEYS:
		var key := str(raw_key)

		if not values.has(key):
			push_error(
				"Workplace production state is missing key: "
				+ key
			)
			return false

	var object_id := int(values["object_id"])
	var progress_work_units := int(values["progress_work_units"])
	var production_status := str(values["production_status"])
	var productive_worker_count := int(
		values["productive_worker_count"]
	)
	var site_productivity_basis_points := int(
		values["site_productivity_basis_points"]
	)
	var object_index := CityObjectSystem.get_city_object_index_by_id(object_id)

	if object_index < 0:
		return false

	var raw_city_object = CityObjectSystem.get_city_objects()[object_index]

	if not raw_city_object is Dictionary:
		return false

	var city_object: Dictionary = raw_city_object

	if not city_object_is_workplace(city_object):
		return false

	var recipe := get_city_object_production_recipe(city_object)

	if recipe.is_empty():
		return false

	var safe_progress := maxi(progress_work_units, 0)
	var work_units_per_batch := int(
		recipe.get("work_units_per_batch", 0)
	)

	if work_units_per_batch > 0:
		safe_progress = mini(
			safe_progress,
			work_units_per_batch - 1
	)
	else:
		safe_progress = 0

	var safe_status := production_status

	if not is_valid_city_workplace_production_status(safe_status):
		safe_status = WORKPLACE_PRODUCTION_STATUS_INACTIVE

	var safe_productive_worker_count := maxi(
		productive_worker_count,
		0
	)
	var safe_site_productivity := maxi(
		site_productivity_basis_points,
		0
	)

	var state_changed := (
		get_city_object_production_progress_work_units(city_object)
		!= safe_progress
		or get_city_object_production_status(city_object)
		!= safe_status
		or get_city_object_productive_worker_count(city_object)
		!= safe_productive_worker_count
		or get_city_object_site_productivity_basis_points(city_object)
		!= safe_site_productivity
	)

	if not state_changed:
		return false

	city_object["production_progress_work_units"] = safe_progress
	city_object["production_status"] = safe_status
	city_object["productive_worker_count"] = (
		safe_productive_worker_count
	)
	city_object["site_productivity_basis_points"] = (
		safe_site_productivity
	)

	if not CityObjectSystem.write_city_object_at_index(
		object_index,
		city_object
	):
		return false
	CityEmploymentSystem.mark_city_workplaces_changed()

	return true

static func get_city_object_display_name_for_type(object_type: String) -> String:
	return (
		CityObjectCatalogScript
		.get_city_object_display_name_for_type(object_type)
	)


static func get_city_object_size_for_type(object_type: String) -> Vector2i:
	return CityObjectCatalogScript.get_city_object_size_for_type(object_type)


static func get_city_object_visual_style_for_type(object_type: String) -> Dictionary:
	return (
		CityObjectCatalogScript
		.get_city_object_visual_style_for_type(object_type)
	)


static func can_use_city_object_definition(object_type: String) -> bool:
	var definition := get_city_object_definition(object_type)

	if definition.is_empty():
		return false

	if bool(definition.get("requires_city", false)) and not can_build_in_city():
		return false

	if bool(definition.get("requires_no_city", false)) and has_player_city():
		return false

	return true

static var city_object_definitions: Dictionary = (
	CityObjectCatalogScript.get_city_object_definitions()
)

#endregion

#region World Grid and Tile State

func setup(new_width: int, new_height: int, new_seed: int):
	width = new_width
	height = new_height
	seed = new_seed
	tiles.clear()
	tile_data_version = 0
	city_surface_feature_change_version = 0
	pending_city_surface_feature_changes.clear()
	_invalidate_prepared_city_feature_tiles()

	for y in range(height):
		var row := []
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
	tile_data_version += 1
	_invalidate_prepared_city_feature_tiles()


func mark_tile_data_changed() -> void:
	tile_data_version += 1
	_invalidate_prepared_city_feature_tiles()


func _invalidate_prepared_city_feature_tiles() -> void:
	prepared_city_tree_tiles.clear()
	prepared_city_rock_tiles.clear()
	prepared_city_feature_tile_data_version = -1


func mark_city_surface_feature_changed(
	tile_position: Vector2i,
	previous_feature: String,
	current_feature: String
) -> void:
	if previous_feature == current_feature:
		return

	pending_city_surface_feature_changes.append({
		"tile_position": tile_position,
		"previous_feature": previous_feature,
		"current_feature": current_feature,
	})
	city_surface_feature_change_version += 1


func consume_city_surface_feature_changes() -> Array[Dictionary]:
	var changes: Array[Dictionary] = []

	for change in pending_city_surface_feature_changes:
		changes.append(change.duplicate(true))

	pending_city_surface_feature_changes.clear()
	return changes


#endregion

#region Session Save and City Foundation State


static func normalize_official_city_name(city_name: String) -> String:
	return city_name.strip_edges()


static func is_valid_founding_name(name: String) -> bool:
	var normalized_name := name.strip_edges()

	return (
		not normalized_name.is_empty()
		and normalized_name.length() <= MAX_FOUNDING_NAME_LENGTH
	)


static func get_culture_index_by_id(culture_id: int) -> int:
	if culture_id <= 0 or not culture_index_by_id.has(culture_id):
		return -1

	var culture_index := int(culture_index_by_id[culture_id])

	if culture_index < 0 or culture_index >= cultures.size():
		return -1

	var raw_culture = cultures[culture_index]

	if not raw_culture is Dictionary:
		return -1

	var culture: Dictionary = raw_culture

	if (
		int(culture.get("id", INVALID_CULTURE_ID)) != culture_id
		or not CultureDataScript.is_valid_culture_record(culture)
	):
		return -1

	return culture_index


static func has_culture_id(culture_id: int) -> bool:
	return get_culture_index_by_id(culture_id) >= 0


static func is_valid_culture_id(culture_id: int) -> bool:
	return has_culture_id(culture_id)


static func get_culture_by_id(culture_id: int) -> Dictionary:
	var culture_index := get_culture_index_by_id(culture_id)

	if culture_index < 0:
		return {}

	return cultures[culture_index].duplicate(true)


static func get_culture_name_by_id(culture_id: int) -> String:
	var culture := get_culture_by_id(culture_id)

	if culture.is_empty():
		return ""

	return str(culture.get("name", ""))


static func get_culture_snapshot() -> Array:
	var culture_snapshot: Array = []

	for raw_culture in cultures:
		if not raw_culture is Dictionary:
			continue

		culture_snapshot.append(raw_culture.duplicate(true))

	return culture_snapshot


static func create_culture(culture_name: String) -> Dictionary:
	var culture := CultureDataScript.make_culture({
		"id": next_culture_id,
		"name": culture_name,
	})

	if culture.is_empty():
		return {}

	var culture_id := int(culture["id"])

	if culture_index_by_id.has(culture_id):
		push_error(
			"Cannot create culture because ID "
			+ str(culture_id)
			+ " is already registered."
		)
		return {}

	cultures.append(culture)
	culture_index_by_id[culture_id] = cultures.size() - 1
	next_culture_id += 1

	return culture.duplicate(true)


static func reset_founding_identity_state() -> void:
	official_city_name = ""
	official_founding_culture_id = INVALID_CULTURE_ID
	cultures.clear()
	culture_index_by_id.clear()
	next_culture_id = 1


static func get_official_city_name() -> String:
	return official_city_name


static func get_official_founding_culture_id() -> int:
	return official_founding_culture_id


static func get_official_founding_culture() -> Dictionary:
	return get_culture_by_id(official_founding_culture_id)


static func get_official_founding_culture_name() -> String:
	return get_culture_name_by_id(official_founding_culture_id)


static func has_official_founding_identity() -> bool:
	return (
		is_valid_founding_name(official_city_name)
		and official_city_name
		== normalize_official_city_name(official_city_name)
		and has_culture_id(official_founding_culture_id)
	)


static func _make_city_start_region_tiles(
	source_world: WorldData,
	region_top_left: Vector2i,
	region_size: int
) -> Array:
	if source_world == null or region_size <= 0:
		return []

	var region_bottom_right := (
		region_top_left
		+ Vector2i(region_size - 1, region_size - 1)
	)

	if (
		not source_world.is_in_bounds(
			region_top_left.x,
			region_top_left.y
		)
		or not source_world.is_in_bounds(
			region_bottom_right.x,
			region_bottom_right.y
		)
	):
		return []

	var region_tiles: Array = []

	for y_offset in range(region_size):
		var row: Array = []

		for x_offset in range(region_size):
			var tile_x: int = region_top_left.x + x_offset
			var tile_y: int = region_top_left.y + y_offset
			var source_tile := (
				source_world.get_tile(tile_x, tile_y).duplicate(true)
			)

			source_tile["source_world_x"] = tile_x
			source_tile["source_world_y"] = tile_y
			row.append(source_tile)

		region_tiles.append(row)

	return region_tiles


static func store_city_start_region(
	source_world: WorldData,
	region_top_left: Vector2i,
	region_center: Vector2i,
	region_size: int
) -> bool:
	var region_tiles := _make_city_start_region_tiles(
		source_world,
		region_top_left,
		region_size
	)

	if region_tiles.is_empty():
		return false

	city_start_world_seed = source_world.seed
	city_start_region_center = region_center
	city_start_region_top_left = region_top_left
	city_start_region_size = region_size
	city_start_tiles = region_tiles
	return true


static func has_city_start_region() -> bool:
	if city_start_region_size <= 0:
		return false

	if city_start_tiles.size() != city_start_region_size:
		return false

	return true

static func lock_world_save(values: Dictionary) -> bool:
	var required_keys: Array[String] = [
		"source_world",
		"region_top_left",
		"region_center",
		"region_size",
		"world_scene_path",
		"city_scene_path",
		"city_name",
		"culture_name",
	]

	for key in required_keys:
		if not values.has(key):
			push_error(
				"WorldData.lock_world_save is missing required key: "
				+ key
			)
			return false

	if not values["source_world"] is WorldData:
		push_error(
			"WorldData.lock_world_save source_world must be WorldData."
		)
		return false

	if not values["region_top_left"] is Vector2i:
		push_error(
			"WorldData.lock_world_save region_top_left must be Vector2i."
		)
		return false

	if not values["region_center"] is Vector2i:
		push_error(
			"WorldData.lock_world_save region_center must be Vector2i."
		)
		return false

	if not values["region_size"] is int:
		push_error(
			"WorldData.lock_world_save region_size must be an integer."
		)
		return false

	if not values["world_scene_path"] is String:
		push_error(
			"WorldData.lock_world_save world_scene_path must be a String."
		)
		return false

	if not values["city_scene_path"] is String:
		push_error(
			"WorldData.lock_world_save city_scene_path must be a String."
		)
		return false

	if not values["city_name"] is String:
		push_error(
			"WorldData.lock_world_save city_name must be a String."
		)
		return false

	if not values["culture_name"] is String:
		push_error(
			"WorldData.lock_world_save culture_name must be a String."
		)
		return false

	var source_world: WorldData = values["source_world"]
	var region_top_left: Vector2i = values["region_top_left"]
	var region_center: Vector2i = values["region_center"]
	var region_size: int = values["region_size"]
	var world_scene_path: String = values["world_scene_path"]
	var city_scene_path: String = values["city_scene_path"]
	var raw_city_name: String = values["city_name"]
	var raw_culture_name: String = values["culture_name"]
	var city_name := normalize_official_city_name(raw_city_name)
	var culture_name := CultureDataScript.normalize_culture_name(
		raw_culture_name
	)

	if region_size <= 0:
		push_error("WorldData.lock_world_save region_size must be positive.")
		return false

	var expected_region_center := (
		region_top_left
		+ Vector2i(int(region_size / 2), int(region_size / 2))
	)

	if region_center != expected_region_center:
		push_error(
			"WorldData.lock_world_save region_center is inconsistent "
			+ "with region_top_left and region_size."
		)
		return false

	if world_scene_path.strip_edges().is_empty():
		push_error(
			"WorldData.lock_world_save world_scene_path must not be blank."
		)
		return false

	if city_scene_path.strip_edges().is_empty():
		push_error(
			"WorldData.lock_world_save city_scene_path must not be blank."
		)
		return false

	if not is_valid_founding_name(city_name):
		push_error(
			"WorldData.lock_world_save city_name must contain 1 to "
			+ str(MAX_FOUNDING_NAME_LENGTH)
			+ " visible characters."
		)
		return false

	if not is_valid_founding_name(culture_name):
		push_error(
			"WorldData.lock_world_save culture_name must contain 1 to "
			+ str(MAX_FOUNDING_NAME_LENGTH)
			+ " visible characters."
		)
		return false

	var prepared_region_tiles := _make_city_start_region_tiles(
		source_world,
		region_top_left,
		region_size
	)

	if prepared_region_tiles.is_empty():
		push_error(
			"WorldData.lock_world_save selected region is outside the world."
		)
		return false

	if save_locked:
		return (
			has_active_world_save()
			and official_world == source_world
			and official_selected_region_center == region_center
			and official_selected_region_top_left == region_top_left
			and official_region_size == region_size
			and official_world_scene_path == world_scene_path
			and official_city_scene_path == city_scene_path
			and official_city_name == city_name
			and get_official_founding_culture_name() == culture_name
		)

	var founding_culture := create_culture(culture_name)

	if founding_culture.is_empty():
		return false

	official_world = source_world
	official_selected_region_center = region_center
	official_selected_region_top_left = region_top_left
	official_region_size = region_size
	official_world_scene_path = world_scene_path
	official_city_scene_path = city_scene_path
	official_city_name = city_name
	official_founding_culture_id = int(founding_culture["id"])

	city_start_world_seed = source_world.seed
	city_start_region_center = region_center
	city_start_region_top_left = region_top_left
	city_start_region_size = region_size
	city_start_tiles = prepared_region_tiles

	save_locked = true
	return true


static func has_active_world_save() -> bool:
	return save_locked and official_world != null


static func has_active_city_save() -> bool:
	return official_city_world != null


static func store_city_world_save(city_world: WorldData, city_seed: int) -> void:
	WorkplaceProductionSystem.clear_resource_source_evaluation_cache()
	official_city_world = city_world
	official_city_seed = city_seed
	MapTextureCacheStateScript.clear_city_cache()

static func found_player_city(values: Dictionary) -> void:
	if player_city_founded:
		return

	if not has_active_world_save():
		push_error(
			"Cannot found the player city before the world save is locked."
		)
		return

	if not has_official_founding_identity():
		push_error(
			"Cannot found the player city without a committed city name "
			+ "and founding culture."
		)
		return

	var required_keys: Array[String] = [
		"city_world_seed",
		"city_map_size",
	]

	for key in required_keys:
		if not values.has(key):
			push_error(
				"WorldData.found_player_city is missing required key: "
				+ key
			)
			return

	if not values["city_map_size"] is Vector2i:
		push_error(
			"WorldData.found_player_city city_map_size must be Vector2i."
		)
		return

	var foundation_top_left_value = values.get(
		"foundation_top_left",
		Vector2i(-1, -1)
	)
	var foundation_size_value = values.get(
		"foundation_size",
		Vector2i.ZERO
	)

	if not foundation_top_left_value is Vector2i:
		push_error(
			"WorldData.found_player_city foundation_top_left must be Vector2i."
		)
		return

	if not foundation_size_value is Vector2i:
		push_error(
			"WorldData.found_player_city foundation_size must be Vector2i."
		)
		return

	var city_world_seed := int(values["city_world_seed"])
	var city_map_size: Vector2i = values["city_map_size"]
	var foundation_top_left: Vector2i = foundation_top_left_value
	var foundation_size: Vector2i = foundation_size_value
	var primary_culture_id := official_founding_culture_id

	player_city_founded = true
	player_city_foundation_top_left = foundation_top_left
	player_city_foundation_size = foundation_size

	player_city_data = {
		"id": 1,
		"name": official_city_name,
		"primary_culture_id": primary_culture_id,
		"city_world_seed": city_world_seed,
		"city_map_size": city_map_size,
		"foundation_top_left": foundation_top_left,
		"foundation_size": foundation_size,
		"can_build": true,
		"founded": true
	}

	initialize_starting_city_population()

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

#endregion

#region Resource and Surface Feature Metadata

static func get_city_resource_types() -> Array[String]:
	return CityResourceCatalogScript.get_city_resource_types()


static func is_city_resource_type(resource: String) -> bool:
	return CityResourceCatalogScript.is_city_resource_type(resource)


static func get_city_surface_feature(tile: Dictionary) -> String:
	return str(
		tile.get(
			"surface_feature",
			CITY_SURFACE_FEATURE_NONE
		)
	)


static func is_city_surface_feature(surface_feature: String) -> bool:
	return (
		surface_feature == CITY_SURFACE_FEATURE_TREE
		or surface_feature == CITY_SURFACE_FEATURE_ROCK
	)


static func get_city_surface_feature_resource_type(
	surface_feature: String
) -> String:
	match surface_feature:
		CITY_SURFACE_FEATURE_TREE:
			return RESOURCE_LUMBER

		CITY_SURFACE_FEATURE_ROCK:
			return RESOURCE_STONE

	return RESOURCE_NONE


static func clear_city_surface_features_at_tiles(
	city_world: WorldData,
	raw_tile_positions: Array
) -> int:
	if city_world == null:
		return 0

	var cleared_count := 0
	var visited_tiles: Dictionary = {}

	for raw_tile_position in raw_tile_positions:
		if not raw_tile_position is Vector2i:
			continue

		var tile_position: Vector2i = raw_tile_position

		if visited_tiles.has(tile_position):
			continue

		visited_tiles[tile_position] = true

		if not city_world.is_in_bounds(
			tile_position.x,
			tile_position.y
		):
			continue

		var tile: Dictionary = city_world.get_tile(
			tile_position.x,
			tile_position.y
		)
		var surface_feature := get_city_surface_feature(tile)

		if not is_city_surface_feature(surface_feature):
			continue

		tile.erase("surface_feature")
		city_world.mark_city_surface_feature_changed(
			tile_position,
			surface_feature,
			CITY_SURFACE_FEATURE_NONE
		)
		cleared_count += 1

	return cleared_count

#endregion

#region Citizen and Haul Endpoint Factories

static func reset_city_citizen_state() -> void:
	CityLogisticsSystem.reset_city_haul_reservation_state()
	CityCitizenRegistrySystem.reset_city_citizen_registry_state()
	CityCitizenSpatialSystem.reset_city_citizen_spatial_state()
	CityCitizenMovementRuntimeSystem.reset_city_citizen_movement_runtime_state()
	CityCitizenTaskRuntimeSystem.reset_city_citizen_task_runtime_state()
	CitizenDecisionSystem.reset_runtime_state()
	CityAssignmentSystem.mark_city_assignments_changed()

#endregion

#region Haul Reservations and Endpoint Accounting

static func commit_city_haul_source_reservation(
	reservation_id: int,
	picked_up_amount: int
) -> bool:
	var reservation := CityLogisticsSystem.get_city_haul_reservation(reservation_id)

	if reservation.is_empty():
		return false

	var old_source_amount := maxi(
		int(reservation.get("source_reserved_amount", 0)),
		0
	)
	var committed_amount := mini(
		maxi(picked_up_amount, 0),
		old_source_amount
	)
	var source: Dictionary = reservation.get("source", {})
	var destination: Dictionary = reservation.get("destination", {})
	var resource := str(
		reservation.get("resource_type", RESOURCE_NONE)
	)
	var destination_resources := (
		CityLogisticsSystem.get_city_haul_reservation_destination_resources(
			reservation_id
		)
	)
	var unpicked_amount := old_source_amount - committed_amount

	CityLogisticsSystem._change_city_haul_reserved_source_amount(
		source,
		resource,
		-old_source_amount
	)

	if unpicked_amount > 0:
		var reserved_for_resource := maxi(
			int(destination_resources.get(resource, 0)),
			0
		)
		var final_resource_reservation := maxi(
			reserved_for_resource - unpicked_amount,
			0
		)

		if final_resource_reservation > 0:
			destination_resources[resource] = (
				final_resource_reservation
			)
		else:
			destination_resources.erase(resource)

		CityLogisticsSystem._change_city_haul_reserved_destination_amount(
			destination,
			-unpicked_amount
		)

	reservation["source_reserved_amount"] = 0
	reservation["destination_reserved_resources"] = destination_resources
	reservation["destination_reserved_amount"] = (
		CityLogisticsSystem._get_city_haul_resource_manifest_total(
			destination_resources
		)
	)
	CityLogisticsSystem.get_current_state().haul_reservations[reservation_id] = reservation
	CityLogisticsSystem._mark_city_haul_reservations_changed()
	return committed_amount > 0


static func release_city_haul_destination_reservation(
	reservation_id: int
) -> bool:
	var reservation := CityLogisticsSystem.get_city_haul_reservation(reservation_id)

	if reservation.is_empty():
		return false

	var destination: Dictionary = reservation.get(
		"destination",
		{}
	)
	var old_destination_amount := maxi(
		int(
			reservation.get(
				"destination_reserved_amount",
				0
			)
		),
		0
	)

	CityLogisticsSystem._change_city_haul_reserved_destination_amount(
		destination,
		-old_destination_amount
	)
	reservation["destination"] = (
		CityCitizensScript.make_city_citizen_haul_endpoint()
	)
	reservation["destination_reserved_amount"] = 0
	reservation["destination_reserved_resources"] = {}
	CityLogisticsSystem.get_current_state().haul_reservations[reservation_id] = reservation
	CityLogisticsSystem._mark_city_haul_reservations_changed()
	return true


static func retarget_city_haul_destination_reservation(
	reservation_id: int,
	destination: Dictionary,
	requested_amount: int,
	destination_access_purpose: String
) -> int:
	var reservation := CityLogisticsSystem.get_city_haul_reservation(reservation_id)

	if (
		reservation.is_empty()
		or requested_amount <= 0
		or destination_access_purpose
		== CONTAINER_HAUL_PURPOSE_NONE
		or int(reservation.get("source_reserved_amount", 0)) > 0
	):
		return 0

	var citizen_id := int(reservation.get("citizen_id", -1))

	# Destination reassignment is a safe-boundary operation for physical cargo.
	# Pre-pickup claims use the separate soft-reservation transfer path.
	if (
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(
			citizen_id
		) <= 0
	):
		return 0

	var normalized_destination := (
		CityCitizensScript.make_city_citizen_haul_endpoint(
			destination
		)
	)

	if not CityCitizensScript.is_valid_city_citizen_haul_endpoint(
		normalized_destination
	):
		return 0

	var old_destination: Dictionary = reservation.get(
		"destination",
		CityCitizensScript.make_city_citizen_haul_endpoint()
	)
	var old_destination_amount := maxi(
		int(reservation.get("destination_reserved_amount", 0)),
		0
	)
	var old_destination_resources := (
		CityLogisticsSystem.get_city_haul_reservation_destination_resources(
			reservation_id
		)
	)
	var old_destination_access_purpose := str(
		reservation.get(
			"destination_access_purpose",
			CONTAINER_HAUL_PURPOSE_NONE
		)
	)

	if old_destination_amount > 0:
		CityLogisticsSystem._change_city_haul_reserved_destination_amount(
			old_destination,
			-old_destination_amount
		)

	reservation["destination"] = (
		CityCitizensScript.make_city_citizen_haul_endpoint()
	)
	reservation["destination_reserved_amount"] = 0
	reservation["destination_reserved_resources"] = {}
	reservation["destination_access_purpose"] = (
		destination_access_purpose
	)
	CityLogisticsSystem.get_current_state().haul_reservations[reservation_id] = reservation

	var reserved_amount := reserve_city_haul_destination(
		reservation_id,
		normalized_destination,
		requested_amount
	)

	if reserved_amount > 0:
		var retargeted_reservation := CityLogisticsSystem.get_city_haul_reservation(
			reservation_id
		)
		retargeted_reservation["last_retargeted_world_minute"] = (
			SimulationClock.absolute_world_minutes
		)
		CityLogisticsSystem.get_current_state().haul_reservations[reservation_id] = (
			retargeted_reservation
		)
		CityLogisticsSystem._mark_city_haul_reservations_changed()
		return reserved_amount

	# Retargeting is atomic from the caller's perspective. If the new demand
	# vanished between scoring and reservation, restore the prior hard claim.
	reservation = CityLogisticsSystem.get_city_haul_reservation(reservation_id)
	reservation["destination"] = old_destination
	reservation["destination_reserved_amount"] = (
		old_destination_amount
	)
	reservation["destination_reserved_resources"] = (
		old_destination_resources
	)
	reservation["destination_access_purpose"] = (
		old_destination_access_purpose
	)
	CityLogisticsSystem.get_current_state().haul_reservations[reservation_id] = reservation

	if old_destination_amount > 0:
		CityLogisticsSystem._change_city_haul_reserved_destination_amount(
			old_destination,
			old_destination_amount
		)

	CityLogisticsSystem._mark_city_haul_reservations_changed()
	return 0


static func reserve_city_haul_destination(
	reservation_id: int,
	destination: Dictionary,
	requested_amount: int
) -> int:
	var reservation := CityLogisticsSystem.get_city_haul_reservation(reservation_id)

	if reservation.is_empty() or requested_amount <= 0:
		return 0

	if int(
		reservation.get("destination_reserved_amount", 0)
	) > 0:
		return 0

	var normalized_destination := (
		CityCitizensScript.make_city_citizen_haul_endpoint(
			destination
		)
	)
	var citizen_id := int(reservation.get("citizen_id", -1))
	var cargo_resources := (
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_resources(
			citizen_id
		)
	)
	var cargo_amount := (
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(
			citizen_id
		)
	)
	var resources_to_reserve: Dictionary = {}

	if cargo_amount > 0:
		resources_to_reserve = CityLogisticsSystem._normalize_city_haul_resource_manifest(
			cargo_resources,
			requested_amount
		)
	else:
		var resource := str(
			reservation.get("resource_type", RESOURCE_NONE)
		)

		if is_city_resource_type(resource):
			resources_to_reserve[resource] = requested_amount

	var destination_access_purpose := str(
		reservation.get(
			"destination_access_purpose",
			CONTAINER_HAUL_PURPOSE_NONE
		)
	)

	for resource in resources_to_reserve.keys():
		if not CityLogisticsSystem.city_haul_endpoint_can_accept_resource({
			"endpoint": normalized_destination,
			"resource": str(resource),
			"deposit_purpose": destination_access_purpose,
			"require_unreserved_space": true,
			"excluding_reservation_id": reservation_id,
		}):
			return 0

	if (
		str(
			normalized_destination.get(
				"kind",
				CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
			)
		)
		== CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE
	):
		for resource in resources_to_reserve.keys():
			var resource_space := (
				CityLogisticsSystem.get_city_haul_endpoint_unreserved_destination_resource_space(
					normalized_destination,
					str(resource),
					reservation_id
				)
			)
			var capped_amount := mini(
				int(resources_to_reserve.get(resource, 0)),
				resource_space
			)

			if capped_amount > 0:
				resources_to_reserve[resource] = capped_amount
			else:
				resources_to_reserve.erase(resource)

	var reservable_total := mini(
		CityLogisticsSystem._get_city_haul_resource_manifest_total(resources_to_reserve),
		CityLogisticsSystem.get_city_haul_endpoint_unreserved_destination_space(
			normalized_destination,
			reservation_id
		)
	)
	resources_to_reserve = CityLogisticsSystem._normalize_city_haul_resource_manifest(
		resources_to_reserve,
		reservable_total
	)
	var reserved_amount := (
		CityLogisticsSystem._get_city_haul_resource_manifest_total(
			resources_to_reserve
		)
	)

	if reserved_amount <= 0:
		return 0

	reservation["destination"] = normalized_destination
	reservation["destination_reserved_amount"] = reserved_amount
	reservation["destination_reserved_resources"] = resources_to_reserve
	CityLogisticsSystem.get_current_state().haul_reservations[reservation_id] = reservation
	CityLogisticsSystem._change_city_haul_reserved_destination_amount(
		normalized_destination,
		reserved_amount
	)
	CityLogisticsSystem._mark_city_haul_reservations_changed()
	return reserved_amount


static func commit_city_haul_destination_reservation(
	reservation_id: int,
	resource: String,
	deposited_amount: int
) -> bool:
	var reservation := CityLogisticsSystem.get_city_haul_reservation(reservation_id)

	if reservation.is_empty():
		return false

	var destination: Dictionary = reservation.get(
		"destination",
		{}
	)
	var destination_resources := (
		CityLogisticsSystem.get_city_haul_reservation_destination_resources(
			reservation_id
		)
	)
	var old_resource_amount := maxi(
		int(destination_resources.get(resource, 0)),
		0
	)
	var committed_amount := mini(
		maxi(deposited_amount, 0),
		old_resource_amount
	)

	if committed_amount <= 0:
		return false

	var remaining_resource_amount := (
		old_resource_amount - committed_amount
	)

	if remaining_resource_amount > 0:
		destination_resources[resource] = remaining_resource_amount
	else:
		destination_resources.erase(resource)

	CityLogisticsSystem._change_city_haul_reserved_destination_amount(
		destination,
		-committed_amount
	)
	var remaining_reserved_amount := (
		CityLogisticsSystem._get_city_haul_resource_manifest_total(
			destination_resources
		)
	)
	reservation["destination_reserved_amount"] = (
		remaining_reserved_amount
	)
	reservation["destination_reserved_resources"] = (
		destination_resources
	)

	if remaining_reserved_amount <= 0:
		reservation["destination"] = (
			CityCitizensScript.make_city_citizen_haul_endpoint()
		)

	CityLogisticsSystem.get_current_state().haul_reservations[reservation_id] = reservation
	CityLogisticsSystem._mark_city_haul_reservations_changed()
	return true


#endregion

#region Citizen Identity and Population Creation

static func get_city_citizen_name_seed() -> int:
	var name_seed := int(official_city_seed)

	if name_seed == 0:
		name_seed = int(city_start_world_seed)

	if name_seed == 0:
		name_seed = 12345

	return name_seed


static func get_city_citizen_count_by_sex(
	citizen_sex: String
) -> int:
	var normalized_sex := (
		CityCitizensScript.normalize_city_citizen_sex(
			citizen_sex
		)
	)

	if not CityCitizensScript.is_valid_city_citizen_sex(
		normalized_sex
	):
		return 0

	var citizen_count := 0

	for raw_citizen in CityCitizenRegistrySystem.get_current_state().citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if (
			CityCitizensScript.normalize_city_citizen_sex(
				str(citizen.get("sex", ""))
			)
			!= normalized_sex
		):
			continue

		citizen_count += 1

	return citizen_count


static func make_random_city_citizen_first_name(
	citizen_sex: String,
	citizen_number: int = -1
) -> String:
	var resolved_citizen_number := citizen_number

	if resolved_citizen_number <= 0:
		resolved_citizen_number = CityCitizenRegistrySystem.get_current_state().next_citizen_id

	return CityCitizensScript.make_random_city_citizen_first_name(
		citizen_sex,
		resolved_citizen_number,
		get_city_citizen_name_seed(),
		CityCitizenRegistrySystem.get_current_state().citizens
	)


static func resolve_city_citizen_culture_id(
	requested_culture_id: int = INVALID_CULTURE_ID
) -> int:
	if has_culture_id(requested_culture_id):
		return requested_culture_id

	if requested_culture_id != INVALID_CULTURE_ID:
		return INVALID_CULTURE_ID

	if not player_city_founded:
		return INVALID_CULTURE_ID

	var primary_culture_value = player_city_data.get(
		"primary_culture_id",
		INVALID_CULTURE_ID
	)

	if not primary_culture_value is int:
		return INVALID_CULTURE_ID

	var primary_culture_id: int = primary_culture_value

	if not has_culture_id(primary_culture_id):
		return INVALID_CULTURE_ID

	return primary_culture_id


static func make_city_citizen(
	display_name: String = "",
	initial_city_tile_position: Vector2i = (
		INVALID_CITY_TILE_POSITION
	),
	citizen_sex: String = "",
	culture_id: int = INVALID_CULTURE_ID
) -> Dictionary:
	var resolved_culture_id := resolve_city_citizen_culture_id(culture_id)

	if not has_culture_id(resolved_culture_id):
		push_error(
			"Cannot create a city citizen without a valid culture ID."
		)
		return {}

	var citizen := CityCitizensScript.make_city_citizen({
		"id": CityCitizenRegistrySystem.get_current_state().next_citizen_id,
		"display_name": display_name,
		"sex": citizen_sex,
		"culture_id": resolved_culture_id,
		"city_tile_position": initial_city_tile_position,
		"name_seed": get_city_citizen_name_seed(),
		"existing_citizens": CityCitizenRegistrySystem.get_current_state().citizens
	})

	if citizen.is_empty():
		return {}

	CityCitizenRegistrySystem.get_current_state().next_citizen_id += 1
	return citizen

static func add_city_citizen(
	display_name: String = "",
	initial_city_tile_position: Vector2i = (
		INVALID_CITY_TILE_POSITION
	),
	citizen_sex: String = "",
	culture_id: int = INVALID_CULTURE_ID
) -> Dictionary:
	var citizen := make_city_citizen(
		display_name,
		initial_city_tile_position,
		citizen_sex,
		culture_id
	)

	if citizen.is_empty():
		return {}

	CityCitizenRegistrySystem.get_current_state().citizens.append(citizen)

	var citizen_index := CityCitizenRegistrySystem.get_current_state().citizens.size() - 1

	CityCitizenRegistrySystem.register_city_citizen_index(
		citizen,
		citizen_index
	)

	CityCitizenSpatialSystem.register_city_citizen_spatial_index_entry(
		citizen
	)

	CityCitizenRegistrySystem.mark_city_citizens_changed()
	CityCitizenSpatialSystem.mark_city_citizen_spatial_changed()

	return citizen

static func initialize_starting_city_population() -> int:
	if not player_city_founded:
		push_error(
			"Cannot initialize the starting population "
			+ "before the city is founded."
		)
		return 0

	if not CityCitizenRegistrySystem.get_current_state().citizens.is_empty():
		return 0

	if (
		STARTING_CITY_MALE_POPULATION
		+ STARTING_CITY_FEMALE_POPULATION
		!= STARTING_CITY_POPULATION
	):
		push_error(
			"Starting male and female population counts "
			+ "do not equal STARTING_CITY_POPULATION."
		)
		return 0

	if not CityCitizensScript.city_citizen_name_pools_are_ready():
		push_error(
			"Cannot initialize citizens because the "
			+ "male/female name pools are incomplete, "
			+ "duplicated, or still contain "
			+ "unassigned names."
		)
		return 0

	var primary_culture_value = player_city_data.get(
		"primary_culture_id",
		INVALID_CULTURE_ID
	)

	if not primary_culture_value is int:
		push_error(
			"Cannot initialize starting citizens because the city's "
			+ "primary culture ID is not an integer."
		)
		return 0

	var primary_culture_id: int = primary_culture_value

	if not has_culture_id(primary_culture_id):
		push_error(
			"Cannot initialize starting citizens because the city's "
			+ "primary culture does not exist."
		)
		return 0

	var city_world: WorldData = official_city_world

	if city_world == null:
		push_error(
			"Cannot initialize starting citizens "
			+ "without an official city world."
		)
		return 0

	var spawn_tiles := (
		get_starting_city_citizen_spawn_tiles(
			city_world
		)
	)

	if spawn_tiles.is_empty():
		push_error(
			"Cannot initialize starting citizens: "
			+ "the City Keep has no walkable access tiles."
		)
		return 0

	var created_count := 0
	var created_male_count := 0
	var created_female_count := 0

	for citizen_number in range(
		STARTING_CITY_POPULATION
	):
		var citizen_sex := (
			CITY_CITIZEN_SEX_FEMALE
		)

		if (
			citizen_number
			< STARTING_CITY_MALE_POPULATION
		):
			citizen_sex = CITY_CITIZEN_SEX_MALE

		var spawn_tile: Vector2i = spawn_tiles[
			citizen_number % spawn_tiles.size()
		]

		var citizen := add_city_citizen(
			"",
			spawn_tile,
			citizen_sex,
			primary_culture_id
		)

		if citizen.is_empty():
			continue

		if (
			citizen_sex
			== CITY_CITIZEN_SEX_MALE
		):
			created_male_count += 1
		else:
			created_female_count += 1

		created_count += 1

	if (
		created_male_count
		!= STARTING_CITY_MALE_POPULATION
		or created_female_count
		!= STARTING_CITY_FEMALE_POPULATION
	):
		push_error(
			"Starting population sex balance failed. "
			+ "Created "
			+ str(created_male_count)
			+ " male and "
			+ str(created_female_count)
			+ " female citizens."
		)

	return created_count

static func ensure_city_citizen_demographic_state() -> int:
	if CityCitizenRegistrySystem.get_current_state().citizens.is_empty():
		return 0

	if not CityCitizensScript.city_citizen_name_pools_are_ready():
		push_error(
			"Cannot migrate citizen demographics "
			+ "until the name pools are valid."
		)
		return 0

	var male_count := get_city_citizen_count_by_sex(
		CITY_CITIZEN_SEX_MALE
	)
	var female_count := get_city_citizen_count_by_sex(
		CITY_CITIZEN_SEX_FEMALE
	)
	var migrated_count := 0

	for citizen_index in range(
		CityCitizenRegistrySystem.get_current_state().citizens.size()
	):
		var raw_citizen = CityCitizenRegistrySystem.get_current_state().citizens[
			citizen_index
		]

		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var existing_sex := (
			CityCitizensScript.normalize_city_citizen_sex(
				str(citizen.get("sex", ""))
			)
		)

		if CityCitizensScript.is_valid_city_citizen_sex(
			existing_sex
		):
			continue

		var assigned_sex := (
			CITY_CITIZEN_SEX_MALE
		)

		if male_count > female_count:
			assigned_sex = (
				CITY_CITIZEN_SEX_FEMALE
			)

		var existing_name := str(
			citizen.get("name", "")
		).strip_edges()
		var assigned_name_pool := (
			CityCitizensScript.get_city_citizen_name_pool_for_sex(
				assigned_sex
			)
		)

		if not assigned_name_pool.has(
			existing_name
		):
			existing_name = (
				make_random_city_citizen_first_name(
					assigned_sex,
					int(citizen.get("id", -1))
				)
			)

		if existing_name.is_empty():
			push_error(
				"Could not migrate demographic state "
				+ "for citizen "
				+ str(citizen.get("id", -1))
				+ "."
			)
			continue

		citizen["sex"] = assigned_sex
		citizen["name"] = existing_name
		CityCitizenRegistrySystem.get_current_state().citizens[citizen_index] = citizen

		if assigned_sex == CITY_CITIZEN_SEX_MALE:
			male_count += 1
		else:
			female_count += 1

		migrated_count += 1

	if migrated_count > 0:
		CityCitizenRegistrySystem.mark_city_citizens_changed()

	return migrated_count


#endregion

#region Population, Housing, and Workplace Queries


static func get_city_citizen_culture_id(citizen_id: int) -> int:
	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)

	if citizen.is_empty():
		return INVALID_CULTURE_ID

	var culture_id_value = citizen.get(
		"culture_id",
		INVALID_CULTURE_ID
	)

	if not culture_id_value is int:
		return INVALID_CULTURE_ID

	var culture_id: int = culture_id_value

	if not has_culture_id(culture_id):
		return INVALID_CULTURE_ID

	return culture_id


static func get_city_citizen_culture(citizen_id: int) -> Dictionary:
	return get_culture_by_id(get_city_citizen_culture_id(citizen_id))


static func get_city_citizen_culture_name(citizen_id: int) -> String:
	return get_culture_name_by_id(
		get_city_citizen_culture_id(citizen_id)
	)


static func get_city_object_resident_capacity(city_object: Dictionary) -> int:
	if city_object.is_empty():
		return 0

	if city_object.has("resident_capacity"):
		return int(city_object.get("resident_capacity", 0))

	var definition := get_city_object_definition_from_object(city_object)
	return int(definition.get("resident_capacity", 0))


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
	var output_resources := get_city_object_output_resources(
		city_object
	)

	if not output_resources.is_empty():
		return output_resources[0]

	if city_object.is_empty():
		return RESOURCE_NONE

	if city_object.has("output_resource"):
		return str(city_object.get("output_resource", RESOURCE_NONE))

	var definition := get_city_object_definition_from_object(city_object)
	return str(definition.get("output_resource", RESOURCE_NONE))


static func get_city_object_output_resources(
	city_object: Dictionary
) -> Array[String]:
	return _get_recipe_output_resource_types(
		get_city_object_production_recipe(city_object)
	)


#endregion

#region City Reset and Placement State

static func reset_player_city_state() -> void:
	player_city_founded = false
	player_city_data.clear()
	player_city_foundation_top_left = Vector2i(-1, -1)
	player_city_foundation_size = Vector2i.ZERO
	WorldPoliticalState.reset_extracted_city_state()
	CityLogisticsSystem.reset_city_haul_reservation_state()
	CityLogisticsSystem.reset_city_ground_pile_state()
	CityConstructionSystem.reset_city_construction_state()
	CityNavigationSystem.reset_city_navigation_state()
	CityObjectSystem.reset_city_object_state()
	CityEmploymentSystem.mark_city_workplaces_changed()

	CityResourceAccountingSystem.reset_city_resource_accounting_state()

	# Houses and workplaces no longer exist, so assignment observers must
	# invalidate any relationship displays.
	CityAssignmentSystem.mark_city_assignments_changed()
	reset_city_citizen_state()

#endregion

#region City Object Placement and Traversal


static func get_starting_city_citizen_spawn_tiles(
	city_world: WorldData
) -> Array:
	for raw_city_object in CityObjectSystem.get_city_objects():
		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object

		if (
			str(city_object.get("type", ""))
			!= CITY_OBJECT_CITY_CENTER
		):
			continue

		return CityNavigationSystem.get_city_object_access_tiles(
			city_world,
			city_object
		)

	return []


#endregion

#region Simulation Tick and Session Reset

static func reset_runtime_session_state(clear_debug: bool = false) -> void:
	reset_world_session_state()
	reset_city_session_state()
	reset_player_city_state()
	clear_visual_texture_caches()

	if clear_debug:
		debug_mode_enabled = false

	# This entry point starts a wholly new runtime session. Clear compatibility
	# state first while the current settlement still resolves, then discard every
	# active and inactive settlement-owned state together.
	WorldPoliticalState.reset_state()

static func reset_world_session_state() -> void:
	save_locked = false
	official_world = null
	official_selected_region_center = Vector2i(-1, -1)
	official_selected_region_top_left = Vector2i(-1, -1)
	official_region_size = 0
	official_world_scene_path = ""
	official_city_scene_path = ""
	city_return_world_scene_path = ""

	reset_founding_identity_state()
	reset_city_start_region_state()
	reset_world_camera_state()
	MapTextureCacheStateScript.clear_world_cache()


static func reset_city_session_state() -> void:
	official_city_world = null
	official_city_seed = 0

	reset_city_camera_state()
	MapTextureCacheStateScript.clear_city_cache()


static func reset_city_start_region_state() -> void:
	city_start_world_seed = 0
	city_start_region_center = Vector2i(-1, -1)
	city_start_region_top_left = Vector2i(-1, -1)
	city_start_region_size = 0
	city_start_tiles.clear()


static func reset_world_camera_state() -> void:
	MapCameraSessionStateScript.reset_world_camera()


static func reset_city_camera_state() -> void:
	MapCameraSessionStateScript.reset_city_camera()

static func clear_visual_texture_caches() -> void:
	MapTextureCacheStateScript.clear_world_cache()
	MapTextureCacheStateScript.clear_city_cache()

#endregion
