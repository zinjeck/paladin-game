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

# Food values are data, not decision-system special cases. Future edible
# resources can join this table without changing household delivery or eating.
const CITY_FOOD_HUNGER_RESTORE_BY_RESOURCE := (
	CityResourceCatalogScript.CITY_FOOD_HUNGER_RESTORE_BY_RESOURCE
)
# Homes target one full citizen-day of food per resident. Public storage keeps
# a separate half-day emergency floor before ordinary pantry replenishment may
# draw from shared stores. Integer ratios avoid simulation drift from floats.
const HOUSEHOLD_FOOD_TARGET_DAY_NUMERATOR: int = 1
const HOUSEHOLD_FOOD_TARGET_DAY_DENOMINATOR: int = 1
const PUBLIC_FOOD_RESERVE_TARGET_DAY_NUMERATOR: int = 1
const PUBLIC_FOOD_RESERVE_TARGET_DAY_DENOMINATOR: int = 2

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

# Citizen core-registry ownership is settlement-local. These compatibility
# properties retain the historical WorldData behavior API during this
# ownership-only pass while routing the four mutable registry fields to the
# active City's CityCitizenRegistryState.
static var city_citizens: Array:
	get:
		var state := (
			WorldPoliticalState.get_current_city_citizen_registry_state()
		)
		return state.citizens
	set(value):
		var state := (
			WorldPoliticalState.get_current_city_citizen_registry_state()
		)
		state.citizens = value

static var city_citizen_index_by_id: Dictionary:
	get:
		var state := (
			WorldPoliticalState.get_current_city_citizen_registry_state()
		)
		return state.citizen_index_by_id
	set(value):
		var state := (
			WorldPoliticalState.get_current_city_citizen_registry_state()
		)
		state.citizen_index_by_id = value

# Physical ground-pile and haul-reservation ownership lives in
# CityLogisticsState/CityLogisticsSystem for the active settlement. Citizen
# spatial, movement, and task runtime fields remain in the legacy workspace
# until their separate extraction passes.
static var city_citizen_ids_by_tile: Dictionary = {}
static var city_active_mover_ids: Array[int] = []
static var city_active_mover_id_lookup: Dictionary = {}
# Transient, non-saved movement deltas consumed by the city presentation after
# each simulation tick. This preserves exact traversed corners across batched
# ticks and repaths without making cosmetic interpolation authoritative.
static var city_citizen_movement_visual_events: Array = []
static var city_citizen_movement_visual_tick_index: int = -1
static var city_active_task_ids: Array[int] = []
static var city_active_task_id_lookup: Dictionary = {}
static var city_object_access_tile_cache: Dictionary = {}
static var next_city_citizen_id: int:
	get:
		var state := (
			WorldPoliticalState.get_current_city_citizen_registry_state()
		)
		return state.next_citizen_id
	set(value):
		var state := (
			WorldPoliticalState.get_current_city_citizen_registry_state()
		)
		state.next_citizen_id = value

# Related citizen/assignment versions still awaiting focused extraction.
#
# These let observers refresh only the parts of the city that actually
# changed instead of treating every mutation as a generic storage change.
static var city_citizen_version: int:
	get:
		var state := (
			WorldPoliticalState.get_current_city_citizen_registry_state()
		)
		return state.citizen_version
	set(value):
		var state := (
			WorldPoliticalState.get_current_city_citizen_registry_state()
		)
		state.citizen_version = value
static var city_citizen_spatial_version: int = 0
static var city_citizen_movement_version: int = 0
static var city_citizen_task_version: int = 0
static var city_assignment_version: int = 0
static var city_workplace_version: int = 0
static var city_citizen_male_name_pool: Array[String] = (
	CityCitizensScript.city_citizen_male_name_pool
)
static var city_citizen_female_name_pool: Array[String] = (
	CityCitizensScript.city_citizen_female_name_pool
)
static var city_citizen_unassigned_name_pool: Array[String] = (
	CityCitizensScript.city_citizen_unassigned_name_pool
)

const STARTING_CITY_POPULATION := 8
const CITY_CITIZEN_SEX_MALE := (
	CityCitizensScript.CITY_CITIZEN_SEX_MALE
)
const CITY_CITIZEN_SEX_FEMALE := (
	CityCitizensScript.CITY_CITIZEN_SEX_FEMALE
)
const STARTING_CITY_MALE_POPULATION: int = 4
const STARTING_CITY_FEMALE_POPULATION: int = 4
const DEFAULT_CITIZEN_CARRY_CAPACITY := (
	CityCitizensScript.DEFAULT_CITIZEN_CARRY_CAPACITY
)
const DEFAULT_CITIZEN_HUNGER := (
	CityCitizensScript.DEFAULT_CITIZEN_HUNGER
)
const MAX_CITIZEN_HUNGER := (
	CityCitizensScript.MAX_CITIZEN_HUNGER
)
const CITIZEN_HUNGER_LOSS_PER_DAY := (
	CityCitizensScript.CITIZEN_HUNGER_LOSS_PER_DAY
)
const CITIZEN_HUNGER_DECAY_DENOMINATOR_MINUTES := (
	CityCitizensScript.CITIZEN_HUNGER_DECAY_DENOMINATOR_MINUTES
)
const CITIZEN_FOOD_SEEK_TRIGGER_HUNGER := (
	CityCitizensScript.CITIZEN_FOOD_SEEK_TRIGGER_HUNGER
)
const CITIZEN_FOOD_CARRY_TRIGGER_HUNGER := (
	CityCitizensScript.CITIZEN_FOOD_CARRY_TRIGGER_HUNGER
)
const CITIZEN_CRITICAL_FOOD_SEEK_TRIGGER_HUNGER := (
	CityCitizensScript.CITIZEN_CRITICAL_FOOD_SEEK_TRIGGER_HUNGER
)
const CITIZEN_EAT_TARGET_HUNGER := (
	CityCitizensScript.CITIZEN_EAT_TARGET_HUNGER
)
const DEFAULT_CITIZEN_HAPPINESS := (
	CityCitizensScript.DEFAULT_CITIZEN_HAPPINESS
)
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
	_mark_city_workplaces_changed()

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


static func get_city_food_resource_types() -> Array[String]:
	return CityResourceCatalogScript.get_city_food_resource_types()


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

#region Food Resource Accounting Primitives

static func get_city_food_hunger_restore(resource: String) -> int:
	return CityResourceCatalogScript.get_city_food_hunger_restore(resource)

static func get_city_food_task_reserved_endpoint_amount(
	endpoint_kind: String,
	endpoint_id: int,
	resource: String,
	excluding_citizen_id: int = -1
) -> int:
	if (
		endpoint_id <= 0
		or get_city_food_hunger_restore(resource) <= 0
		or not [
			CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER,
			CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE,
		].has(endpoint_kind)
	):
		return 0

	var reserved_amount := 0

	for raw_citizen in city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_id := int(citizen.get("id", -1))
		var raw_task = citizen.get("current_task", {})

		if citizen_id == excluding_citizen_id or not raw_task is Dictionary:
			continue

		var task: Dictionary = raw_task
		var task_endpoint_kind := str(
			task.get(
				"food_source_endpoint_kind",
				CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER
			)
		)

		if (
			str(task.get("kind", CITY_CITIZEN_TASK_KIND_NONE))
			!= CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD
			or task_endpoint_kind != endpoint_kind
			or int(task.get("target_object_id", -1)) != endpoint_id
			or str(task.get("food_resource_type", RESOURCE_NONE)) != resource
		):
			continue

		reserved_amount += maxi(
			int(task.get("food_requested_amount", 0)),
			0
		)

	return reserved_amount

#endregion

#region Change Versions and Runtime Indexes

static func _mark_city_citizens_changed() -> void:
	city_citizen_version += 1

static func _mark_city_citizen_spatial_changed() -> void:
	city_citizen_spatial_version += 1

static func _mark_city_citizen_movement_changed() -> void:
	city_citizen_movement_version += 1

static func _mark_city_citizen_task_changed() -> void:
	city_citizen_task_version += 1

static func _mark_city_assignments_changed() -> void:
	city_assignment_version += 1

static func _mark_city_workplaces_changed() -> void:
	city_workplace_version += 1


static func rebuild_city_citizen_index() -> void:
	city_citizen_index_by_id.clear()

	for citizen_index in range(city_citizens.size()):
		var raw_citizen = city_citizens[citizen_index]

		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_id := int(citizen.get("id", -1))

		if citizen_id < 0:
			continue

		if city_citizen_index_by_id.has(citizen_id):
			push_error(
				"Duplicate city citizen ID while rebuilding index: "
				+ str(citizen_id)
			)
			continue

		city_citizen_index_by_id[citizen_id] = citizen_index

static func _add_city_active_mover_id(
	citizen_id: int
) -> void:
	if citizen_id <= 0:
		return

	if city_active_mover_id_lookup.has(citizen_id):
		return

	city_active_mover_ids.insert(
		city_active_mover_ids.bsearch(citizen_id),
		citizen_id
	)
	city_active_mover_id_lookup[citizen_id] = true


static func _remove_city_active_mover_id(
	citizen_id: int
) -> void:
	city_active_mover_id_lookup.erase(citizen_id)
	city_active_mover_ids.erase(citizen_id)


static func rebuild_city_active_mover_registry() -> void:
	city_active_mover_ids.clear()
	city_active_mover_id_lookup.clear()

	for raw_citizen in city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if not bool(citizen.get("alive", false)):
			continue

		if (
			str(citizen.get("movement_state", ""))
			!= CITY_CITIZEN_MOVEMENT_STATE_MOVING
		):
			continue

		var citizen_id := int(citizen.get("id", -1))

		if citizen_id <= 0:
			continue

		_add_city_active_mover_id(citizen_id)


static func get_city_active_mover_ids_snapshot() -> Array[int]:
	return city_active_mover_ids.duplicate()


static func begin_city_citizen_movement_visual_tick(
	tick_index: int
) -> void:
	city_citizen_movement_visual_events.clear()
	city_citizen_movement_visual_tick_index = tick_index


static func clear_city_citizen_movement_visual_events() -> void:
	city_citizen_movement_visual_events.clear()
	city_citizen_movement_visual_tick_index = -1


static func take_city_citizen_movement_visual_events(
	expected_tick_index: int
) -> Array:
	if city_citizen_movement_visual_tick_index != expected_tick_index:
		clear_city_citizen_movement_visual_events()
		return []

	# Transfer ownership instead of deep-copying every route and corner.
	var events := city_citizen_movement_visual_events
	city_citizen_movement_visual_events = []
	city_citizen_movement_visual_tick_index = -1
	return events


static func _add_city_active_task_id(
	citizen_id: int
) -> void:
	if citizen_id <= 0:
		return

	if city_active_task_id_lookup.has(citizen_id):
		return

	city_active_task_ids.insert(
		city_active_task_ids.bsearch(citizen_id),
		citizen_id
	)
	city_active_task_id_lookup[citizen_id] = true


static func _remove_city_active_task_id(
	citizen_id: int
) -> void:
	city_active_task_id_lookup.erase(citizen_id)
	city_active_task_ids.erase(citizen_id)


static func rebuild_city_active_task_registry() -> void:
	city_active_task_ids.clear()
	city_active_task_id_lookup.clear()

	for raw_citizen in city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if not bool(citizen.get("alive", false)):
			continue

		var raw_current_task = citizen.get("current_task", {})

		if not raw_current_task is Dictionary:
			continue

		var current_task: Dictionary = raw_current_task

		if (
			str(current_task.get("kind", ""))
			== CITY_CITIZEN_TASK_KIND_NONE
		):
			continue

		var citizen_id := int(citizen.get("id", -1))

		if citizen_id <= 0:
			continue

		_add_city_active_task_id(citizen_id)


static func get_city_active_task_ids_snapshot() -> Array[int]:
	return city_active_task_ids.duplicate()

static func _add_city_citizen_to_spatial_index(
	citizen_id: int,
	tile_position: Vector2i
) -> void:
	if citizen_id <= 0:
		return

	if tile_position == INVALID_CITY_TILE_POSITION:
		return

	var citizen_ids: Array = []
	var raw_citizen_ids = city_citizen_ids_by_tile.get(
		tile_position,
		[]
	)

	if raw_citizen_ids is Array:
		citizen_ids = raw_citizen_ids

	if citizen_ids.has(citizen_id):
		return

	citizen_ids.insert(
		citizen_ids.bsearch(citizen_id),
		citizen_id
	)

	city_citizen_ids_by_tile[tile_position] = (
		citizen_ids
	)


static func _remove_city_citizen_from_spatial_index(
	citizen_id: int,
	tile_position: Vector2i
) -> void:
	if not city_citizen_ids_by_tile.has(
		tile_position
	):
		return

	var raw_citizen_ids = city_citizen_ids_by_tile[
		tile_position
	]

	if not raw_citizen_ids is Array:
		city_citizen_ids_by_tile.erase(
			tile_position
		)
		return

	var citizen_ids: Array = raw_citizen_ids
	citizen_ids.erase(citizen_id)

	if citizen_ids.is_empty():
		city_citizen_ids_by_tile.erase(
			tile_position
		)
		return

	city_citizen_ids_by_tile[tile_position] = (
		citizen_ids
	)


static func _register_city_citizen_spatial_index_entry(
	citizen: Dictionary
) -> void:
	if citizen.is_empty():
		return

	var citizen_id := int(
		citizen.get("id", -1)
	)
	var raw_position = citizen.get(
		"city_tile_position",
		INVALID_CITY_TILE_POSITION
	)

	if not raw_position is Vector2i:
		return

	_add_city_citizen_to_spatial_index(
		citizen_id,
		raw_position
	)


static func rebuild_city_citizen_spatial_index() -> void:
	city_citizen_ids_by_tile.clear()

	for raw_citizen in city_citizens:
		if not raw_citizen is Dictionary:
			continue

		_register_city_citizen_spatial_index_entry(
			raw_citizen
		)


static func get_city_citizen_ids_at_tile(
	tile_position: Vector2i
) -> Array:
	var raw_citizen_ids = city_citizen_ids_by_tile.get(
		tile_position,
		[]
	)

	if not raw_citizen_ids is Array:
		return []

	return raw_citizen_ids.duplicate()


static func has_living_city_citizen_at_tile(
	tile_position: Vector2i
) -> bool:
	var raw_citizen_ids = city_citizen_ids_by_tile.get(
		tile_position,
		[]
	)

	if not raw_citizen_ids is Array:
		return false

	for raw_citizen_id in raw_citizen_ids:
		if typeof(raw_citizen_id) != TYPE_INT:
			continue

		var citizen_id: int = raw_citizen_id
		var citizen := get_city_citizen_by_id(
			citizen_id
		)

		if citizen.is_empty():
			continue

		if not bool(citizen.get("alive", false)):
			continue

		if (
			citizen.get(
				"city_tile_position",
				INVALID_CITY_TILE_POSITION
			)
			!= tile_position
		):
			continue

		return true

	return false

static func rebuild_city_entity_indexes() -> void:
	CityObjectSystem.rebuild_city_object_index()
	rebuild_city_citizen_index()
	rebuild_city_citizen_spatial_index()
	rebuild_city_active_mover_registry()

static func _register_city_citizen_index(
	citizen: Dictionary,
	citizen_index: int
) -> void:
	if citizen.is_empty():
		return

	if citizen_index < 0 or citizen_index >= city_citizens.size():
		push_error(
			"Cannot register city citizen index outside the citizen array: "
			+ str(citizen_index)
		)
		return

	var citizen_id := int(citizen.get("id", -1))

	if citizen_id < 0:
		push_error("Cannot register city citizen without a valid ID.")
		return

	if city_citizen_index_by_id.has(citizen_id):
		var existing_index := int(city_citizen_index_by_id[citizen_id])

		if existing_index != citizen_index:
			push_error(
				"Duplicate city citizen ID detected: "
				+ str(citizen_id)
			)
			return

	city_citizen_index_by_id[citizen_id] = citizen_index


static func get_city_citizen_index_by_id(citizen_id: int) -> int:
	if citizen_id < 0:
		return -1

	if not city_citizen_index_by_id.has(citizen_id):
		return -1

	var citizen_index := int(city_citizen_index_by_id[citizen_id])

	if citizen_index < 0 or citizen_index >= city_citizens.size():
		push_error(
			"Stale city citizen index for citizen ID "
			+ str(citizen_id)
		)

		city_citizen_index_by_id.erase(citizen_id)
		return -1

	var raw_citizen = city_citizens[citizen_index]

	if not raw_citizen is Dictionary:
		push_error(
			"City citizen index points to non-Dictionary data for citizen ID "
			+ str(citizen_id)
		)

		city_citizen_index_by_id.erase(citizen_id)
		return -1

	var citizen: Dictionary = raw_citizen
	var indexed_citizen_id := int(citizen.get("id", -1))

	if indexed_citizen_id != citizen_id:
		push_error(
			"City citizen index mismatch for requested ID "
			+ str(citizen_id)
			+ ". Indexed citizen contains ID "
			+ str(indexed_citizen_id)
		)

		city_citizen_index_by_id.erase(citizen_id)
		return -1

	return citizen_index


#endregion


#region Citizen and Haul Endpoint Factories

static func reset_city_citizen_state() -> void:
	CityLogisticsSystem.reset_city_haul_reservation_state()
	city_citizens.clear()
	city_citizen_index_by_id.clear()
	city_citizen_ids_by_tile.clear()
	city_active_mover_ids.clear()
	city_active_mover_id_lookup.clear()
	city_citizen_movement_visual_events.clear()
	city_citizen_movement_visual_tick_index = -1
	city_active_task_ids.clear()
	city_active_task_id_lookup.clear()
	next_city_citizen_id = 1
	CitizenDecisionSystem.reset_runtime_state()

	_mark_city_citizens_changed()
	_mark_city_citizen_spatial_changed()
	_mark_city_citizen_movement_changed()
	_mark_city_citizen_task_changed()
	_mark_city_assignments_changed()

static func make_empty_citizen_inventory() -> Dictionary:
	return CityResourceContainerSystem.make_empty_resource_container()


#endregion

#region Ground Pile State

static func get_total_physical_city_resource_amount(
	resource: String
) -> int:
	var total_amount := CityLogisticsSystem.get_total_city_ground_pile_resource_amount(
		resource
	)

	# Conservation includes every physical object container, even private homes
	# and other storage excluded from the player-facing secured city total.
	for raw_city_object in CityObjectSystem.get_city_objects():
		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object
		total_amount += CityResourceContainerSystem.get_city_object_stored_resource_amount(
			city_object,
			resource
		)

	# Citizen inventory and in-transit haul cargo are physical resources, but
	# neither counts as secured city property while a citizen carries it.
	for raw_citizen in city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if not bool(citizen.get("alive", false)):
			continue

		total_amount += CityResourceContainerSystem.get_resource_container_resource_amount(
			CityResourceContainerSystem.make_sparse_resource_container(
				citizen.get("inventory", {})
			),
			resource
		)

		var cargo := CityCitizensScript.make_city_citizen_haul_cargo(
			citizen.get("haul_cargo", {})
		)
		var cargo_resources: Dictionary = cargo.get("resources", {})
		total_amount += maxi(
			int(cargo_resources.get(resource, 0)),
			0
		)

	return total_amount


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
	if get_city_citizen_haul_cargo_amount(citizen_id) <= 0:
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
	var cargo_resources := get_city_citizen_haul_cargo_resources(
		citizen_id
	)
	var cargo_amount := get_city_citizen_haul_cargo_amount(citizen_id)
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

#region Citizen Haul Cargo

static func get_city_citizen_current_haul(
	citizen_id: int
) -> Dictionary:
	var citizen := get_city_citizen_by_id(citizen_id)

	if citizen.is_empty():
		return CityCitizensScript.make_city_citizen_haul()

	var raw_haul = citizen.get("current_haul", {})

	if not raw_haul is Dictionary:
		return CityCitizensScript.make_city_citizen_haul()

	return CityCitizensScript.make_city_citizen_haul(
		raw_haul
	)


static func set_city_citizen_current_haul(
	citizen_id: int,
	haul_values: Dictionary
) -> bool:
	var citizen_index := get_city_citizen_index_by_id(
		citizen_id
	)

	if citizen_index < 0:
		return false

	var raw_citizen = city_citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return false

	var normalized_haul := (
		CityCitizensScript.make_city_citizen_haul(
			haul_values
		)
	)
	var haul_phase := str(
		normalized_haul.get(
			"phase",
			CITY_CITIZEN_HAUL_PHASE_NONE
		)
	)

	if not CityCitizensScript.is_valid_city_citizen_haul_phase(
		haul_phase
	):
		return false

	if not normalized_haul.get("source_tile") is Vector2i:
		return false

	if not normalized_haul.get("destination_tile") is Vector2i:
		return false

	var citizen: Dictionary = raw_citizen
	var raw_existing_haul = citizen.get("current_haul", {})

	if (
		raw_existing_haul is Dictionary
		and raw_existing_haul == normalized_haul
	):
		return true

	citizen["current_haul"] = normalized_haul
	city_citizens[citizen_index] = citizen
	_mark_city_citizen_task_changed()
	return true


static func get_city_citizen_haul_cargo(
	citizen_id: int
) -> Dictionary:
	var citizen := get_city_citizen_by_id(citizen_id)

	if citizen.is_empty():
		return CityCitizensScript.make_city_citizen_haul_cargo()

	var raw_cargo = citizen.get("haul_cargo", {})

	if not raw_cargo is Dictionary:
		return CityCitizensScript.make_city_citizen_haul_cargo()

	return CityCitizensScript.make_city_citizen_haul_cargo(
		raw_cargo
	)


static func get_city_citizen_haul_cargo_resources(
	citizen_id: int
) -> Dictionary:
	var cargo := get_city_citizen_haul_cargo(citizen_id)
	var raw_resources = cargo.get("resources", {})

	if not raw_resources is Dictionary:
		return {}

	return raw_resources.duplicate(true)


static func get_city_citizen_haul_cargo_resource_amount(
	citizen_id: int,
	resource: String
) -> int:
	if not is_city_resource_type(resource):
		return 0

	return maxi(
		int(
			get_city_citizen_haul_cargo_resources(citizen_id).get(
				resource,
				0
			)
		),
		0
	)


static func get_city_citizen_haul_cargo_resource(
	citizen_id: int
) -> String:
	return str(
		get_city_citizen_haul_cargo(citizen_id).get(
			"resource_type",
			RESOURCE_NONE
		)
	)


static func get_city_citizen_haul_cargo_amount(
	citizen_id: int
) -> int:
	return maxi(
		int(
			get_city_citizen_haul_cargo(citizen_id).get(
				"amount",
				0
			)
		),
		0
	)


static func get_city_citizen_total_carried_amount(
	citizen_id: int
) -> int:
	return (
		get_city_citizen_inventory_used_capacity(citizen_id)
		+ get_city_citizen_haul_cargo_amount(citizen_id)
	)


static func get_city_citizen_available_haul_capacity(
	citizen_id: int
) -> int:
	var citizen := get_city_citizen_by_id(citizen_id)

	if citizen.is_empty():
		return 0

	var carry_capacity := maxi(
		int(citizen.get("carry_capacity", 0)),
		0
	)

	return maxi(
		carry_capacity
		- get_city_citizen_total_carried_amount(citizen_id),
		0
	)


static func set_city_citizen_haul_cargo_resources(
	citizen_id: int,
	requested_resources: Dictionary
) -> int:
	var citizen_index := get_city_citizen_index_by_id(citizen_id)

	if citizen_index < 0:
		return 0

	var raw_citizen = city_citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return 0

	var citizen: Dictionary = raw_citizen
	var normalized_resources: Dictionary = {}
	var requested_total := 0

	for raw_resource in requested_resources.keys():
		if typeof(raw_resource) != TYPE_STRING:
			continue

		var resource: String = raw_resource
		var amount := maxi(
			int(requested_resources.get(raw_resource, 0)),
			0
		)

		if amount <= 0 or not is_city_resource_type(resource):
			continue

		normalized_resources[resource] = amount
		requested_total += amount

	var carry_capacity := maxi(
		int(citizen.get("carry_capacity", 0)),
		0
	)
	var maximum_cargo_amount := maxi(
		carry_capacity
		- get_city_citizen_inventory_used_capacity(citizen_id),
		0
	)

	if requested_total > maximum_cargo_amount:
		return get_city_citizen_haul_cargo_amount(citizen_id)

	var final_cargo := (
		CityCitizensScript.make_city_citizen_haul_cargo({
			"resources": normalized_resources,
		})
	)
	var raw_existing_cargo = citizen.get("haul_cargo", {})

	if (
		raw_existing_cargo is Dictionary
		and CityCitizensScript.make_city_citizen_haul_cargo(
			raw_existing_cargo
		) == final_cargo
	):
		return requested_total

	citizen["haul_cargo"] = final_cargo
	city_citizens[citizen_index] = citizen
	_mark_city_citizens_changed()
	return requested_total


static func change_city_citizen_haul_cargo_resource(
	citizen_id: int,
	resource: String,
	amount_delta: int
) -> int:
	if not is_city_resource_type(resource):
		return 0

	var resources := get_city_citizen_haul_cargo_resources(citizen_id)
	var old_amount := maxi(int(resources.get(resource, 0)), 0)
	var final_amount := old_amount + amount_delta

	if final_amount > 0:
		resources[resource] = final_amount
	else:
		resources.erase(resource)
		final_amount = 0

	var expected_total := 0

	for raw_amount in resources.values():
		expected_total += maxi(int(raw_amount), 0)

	if set_city_citizen_haul_cargo_resources(
		citizen_id,
		resources
	) != expected_total:
		return old_amount

	return final_amount


static func set_city_citizen_haul_cargo(
	citizen_id: int,
	resource: String,
	amount: int
) -> int:
	var requested_amount := maxi(amount, 0)
	var resources: Dictionary = {}

	if requested_amount > 0:
		if not is_city_resource_type(resource):
			return get_city_citizen_haul_cargo_amount(citizen_id)

		resources[resource] = requested_amount

	var final_total := set_city_citizen_haul_cargo_resources(
		citizen_id,
		resources
	)

	if requested_amount <= 0:
		return 0

	if final_total != requested_amount:
		return get_city_citizen_haul_cargo_resource_amount(
			citizen_id,
			resource
		)

	return requested_amount


static func city_citizen_is_hauling(
	citizen_id: int
) -> bool:
	if get_city_citizen_haul_cargo_amount(citizen_id) > 0:
		return true

	return (
		str(
			get_city_citizen_current_haul(citizen_id).get(
				"phase",
				CITY_CITIZEN_HAUL_PHASE_NONE
			)
		)
		!= CITY_CITIZEN_HAUL_PHASE_NONE
	)


#endregion

#region Citizen Inventory

static func get_city_citizen_inventory(
	citizen_id: int
) -> Dictionary:
	var citizen := get_city_citizen_by_id(citizen_id)

	if citizen.is_empty():
		return {}

	return CityResourceContainerSystem.make_sparse_resource_container(
		citizen.get("inventory", {})
	)


static func get_city_citizen_inventory_resource_amount(
	citizen_id: int,
	resource: String
) -> int:
	if not is_city_resource_type(resource):
		return 0

	return CityResourceContainerSystem.get_resource_container_resource_amount(
		get_city_citizen_inventory(citizen_id),
		resource
	)


static func get_city_citizen_inventory_used_capacity(
	citizen_id: int
) -> int:
	return CityResourceContainerSystem.get_resource_container_total_amount(
		get_city_citizen_inventory(citizen_id)
	)


static func get_city_citizen_personal_inventory_free_space(
	citizen_id: int
) -> int:
	var citizen := get_city_citizen_by_id(citizen_id)

	if citizen.is_empty():
		return 0

	return maxi(
		maxi(int(citizen.get("carry_capacity", 0)), 0)
		- get_city_citizen_inventory_used_capacity(citizen_id),
		0
	)


static func get_city_citizen_inventory_free_space(
	citizen_id: int
) -> int:
	var citizen := get_city_citizen_by_id(citizen_id)

	if citizen.is_empty():
		return 0

	var carry_capacity := maxi(
		int(citizen.get("carry_capacity", 0)),
		0
	)

	return maxi(
		carry_capacity
		- get_city_citizen_inventory_used_capacity(citizen_id)
		- get_city_citizen_haul_cargo_amount(citizen_id),
		0
	)


static func set_city_citizen_inventory_resource_amount(
	citizen_id: int,
	resource: String,
	amount: int
) -> int:
	if not is_city_resource_type(resource):
		return 0

	var citizen_index := get_city_citizen_index_by_id(
		citizen_id
	)

	if citizen_index < 0:
		return 0

	var raw_citizen = city_citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return 0

	var citizen: Dictionary = raw_citizen
	var raw_inventory = citizen.get("inventory", {})
	var inventory := CityResourceContainerSystem.make_sparse_resource_container(
		raw_inventory
	)
	var old_amount := CityResourceContainerSystem.get_resource_container_resource_amount(
		inventory,
		resource
	)
	var total_without_resource := maxi(
		CityResourceContainerSystem.get_resource_container_total_amount(inventory)
		- old_amount,
		0
	)
	var carry_capacity := maxi(
		int(citizen.get("carry_capacity", 0)),
		0
	)
	var haul_cargo_amount := get_city_citizen_haul_cargo_amount(
		citizen_id
	)
	var safe_amount := mini(
		maxi(amount, 0),
		maxi(
			carry_capacity
			- haul_cargo_amount
			- total_without_resource,
			0
		)
	)

	if safe_amount > 0:
		inventory[resource] = safe_amount
	else:
		inventory.erase(resource)

	if (
		raw_inventory is Dictionary
		and raw_inventory == inventory
	):
		return safe_amount

	citizen["inventory"] = inventory
	city_citizens[citizen_index] = citizen
	_mark_city_citizens_changed()

	return safe_amount


static func add_resource_to_city_citizen_inventory(
	citizen_id: int,
	resource: String,
	amount_delta: int
) -> int:
	if amount_delta <= 0:
		return 0

	var current_amount := (
		get_city_citizen_inventory_resource_amount(
			citizen_id,
			resource
		)
	)
	var final_amount := (
		set_city_citizen_inventory_resource_amount(
			citizen_id,
			resource,
			current_amount + amount_delta
		)
	)

	return maxi(final_amount - current_amount, 0)


static func remove_resource_from_city_citizen_inventory(
	citizen_id: int,
	resource: String,
	requested_amount: int
) -> int:
	if requested_amount <= 0:
		return 0

	var current_amount := (
		get_city_citizen_inventory_resource_amount(
			citizen_id,
			resource
		)
	)
	var amount_to_remove := mini(
		requested_amount,
		current_amount
	)

	if amount_to_remove <= 0:
		return 0

	var final_amount := (
		set_city_citizen_inventory_resource_amount(
			citizen_id,
			resource,
			current_amount - amount_to_remove
		)
	)

	return maxi(current_amount - final_amount, 0)

#endregion

#region Citizen Identity and Population Creation

static func get_city_citizen_name_seed() -> int:
	var name_seed := int(official_city_seed)

	if name_seed == 0:
		name_seed = int(city_start_world_seed)

	if name_seed == 0:
		name_seed = 12345

	return name_seed

static func normalize_city_citizen_sex(
	citizen_sex: String
) -> String:
	return CityCitizensScript.normalize_city_citizen_sex(
		citizen_sex
	)


static func is_valid_city_citizen_sex(
	citizen_sex: String
) -> bool:
	return CityCitizensScript.is_valid_city_citizen_sex(
		citizen_sex
	)


static func get_city_citizen_sex_types() -> Array[String]:
	return CityCitizensScript.get_city_citizen_sex_types()


static func get_city_citizen_sex_display_name(
	citizen_sex: String
) -> String:
	return CityCitizensScript.get_city_citizen_sex_display_name(
		citizen_sex
	)


static func get_city_citizen_name_pool_for_sex(
	citizen_sex: String
) -> Array[String]:
	return CityCitizensScript.get_city_citizen_name_pool_for_sex(
		citizen_sex
	)


static func city_citizen_name_pools_are_ready() -> bool:
	return CityCitizensScript.city_citizen_name_pools_are_ready()

static func get_city_citizen_count_by_sex(
	citizen_sex: String
) -> int:
	var normalized_sex := (
		normalize_city_citizen_sex(
			citizen_sex
		)
	)

	if not is_valid_city_citizen_sex(
		normalized_sex
	):
		return 0

	var citizen_count := 0

	for raw_citizen in city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if (
			normalize_city_citizen_sex(
				str(citizen.get("sex", ""))
			)
			!= normalized_sex
		):
			continue

		citizen_count += 1

	return citizen_count

static func get_used_city_citizen_name_counts() -> Dictionary:
	return CityCitizensScript.get_used_city_citizen_name_counts(
		city_citizens
	)


static func make_random_city_citizen_first_name(
	citizen_sex: String,
	citizen_number: int = -1
) -> String:
	var resolved_citizen_number := citizen_number

	if resolved_citizen_number <= 0:
		resolved_citizen_number = next_city_citizen_id

	return CityCitizensScript.make_random_city_citizen_first_name(
		citizen_sex,
		resolved_citizen_number,
		get_city_citizen_name_seed(),
		city_citizens
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
		"id": next_city_citizen_id,
		"display_name": display_name,
		"sex": citizen_sex,
		"culture_id": resolved_culture_id,
		"city_tile_position": initial_city_tile_position,
		"inventory": make_empty_citizen_inventory(),
		"name_seed": get_city_citizen_name_seed(),
		"existing_citizens": city_citizens
	})

	if citizen.is_empty():
		return {}

	next_city_citizen_id += 1
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

	city_citizens.append(citizen)

	var citizen_index := city_citizens.size() - 1

	_register_city_citizen_index(
		citizen,
		citizen_index
	)

	_register_city_citizen_spatial_index_entry(
		citizen
	)

	_mark_city_citizens_changed()
	_mark_city_citizen_spatial_changed()

	return citizen

static func initialize_starting_city_population() -> int:
	if not player_city_founded:
		push_error(
			"Cannot initialize the starting population "
			+ "before the city is founded."
		)
		return 0

	if not city_citizens.is_empty():
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

	if not city_citizen_name_pools_are_ready():
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
	if city_citizens.is_empty():
		return 0

	if not city_citizen_name_pools_are_ready():
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
		city_citizens.size()
	):
		var raw_citizen = city_citizens[
			citizen_index
		]

		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var existing_sex := (
			normalize_city_citizen_sex(
				str(citizen.get("sex", ""))
			)
		)

		if is_valid_city_citizen_sex(
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
			get_city_citizen_name_pool_for_sex(
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
		city_citizens[citizen_index] = citizen

		if assigned_sex == CITY_CITIZEN_SEX_MALE:
			male_count += 1
		else:
			female_count += 1

		migrated_count += 1

	if migrated_count > 0:
		_mark_city_citizens_changed()

	return migrated_count


#endregion

#region Citizen Needs

static func ensure_city_citizen_need_state() -> int:
	var migrated_count := 0

	for citizen_index in range(city_citizens.size()):
		var raw_citizen = city_citizens[citizen_index]

		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if (
			CityCitizensScript.has_complete_city_citizen_need_state(citizen)
			and int(citizen.get("hunger", -1)) >= 0
			and int(citizen.get("hunger", -1)) <= MAX_CITIZEN_HUNGER
			and int(citizen.get("hunger_decay_remainder", -1)) >= 0
			and int(citizen.get("hunger_decay_remainder", -1))
			< CITIZEN_HUNGER_DECAY_DENOMINATOR_MINUTES
			and int(citizen.get("happiness", -1)) >= 0
			and int(citizen.get("happiness", -1)) <= 100
		):
			continue

		var normalized_citizen := citizen.duplicate(true)

		CityCitizensScript.normalize_city_citizen_need_state(
			normalized_citizen
		)
		city_citizens[citizen_index] = normalized_citizen
		migrated_count += 1

	if migrated_count > 0:
		_mark_city_citizens_changed()

	return migrated_count


static func get_city_citizen_hunger(citizen_id: int) -> int:
	var citizen := get_city_citizen_by_id(citizen_id)
	if citizen.is_empty():
		return 0

	return clampi(
		int(citizen.get("hunger", DEFAULT_CITIZEN_HUNGER)),
		0,
		MAX_CITIZEN_HUNGER
	)


static func set_city_citizen_hunger_state(
	citizen_id: int,
	hunger: int,
	hunger_decay_remainder: int
) -> bool:
	var citizen_index := get_city_citizen_index_by_id(citizen_id)

	if citizen_index < 0:
		return false

	var raw_citizen = city_citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return false

	var citizen: Dictionary = raw_citizen
	var safe_hunger := clampi(hunger, 0, MAX_CITIZEN_HUNGER)
	var safe_remainder := clampi(
		hunger_decay_remainder,
		0,
		CITIZEN_HUNGER_DECAY_DENOMINATOR_MINUTES - 1
	)

	if (
		int(citizen.get("hunger", DEFAULT_CITIZEN_HUNGER))
		== safe_hunger
		and int(citizen.get("hunger_decay_remainder", 0))
		== safe_remainder
	):
		return true

	citizen["hunger"] = safe_hunger
	citizen["hunger_decay_remainder"] = safe_remainder
	city_citizens[citizen_index] = citizen
	_mark_city_citizens_changed()
	return true

#endregion

#region Citizen Task State

static func is_valid_city_citizen_task_kind(
	task_kind: String
) -> bool:
	return CityCitizensScript.is_valid_city_citizen_task_kind(
		task_kind
	)


static func is_valid_city_citizen_task_source(
	task_source: String
) -> bool:
	return CityCitizensScript.is_valid_city_citizen_task_source(
		task_source
	)


static func is_valid_city_citizen_task_phase(
	task_phase: String
) -> bool:
	return CityCitizensScript.is_valid_city_citizen_task_phase(
		task_phase
	)


static func ensure_city_citizen_task_state() -> int:
	if city_citizens.is_empty():
		city_active_task_ids.clear()
		city_active_task_id_lookup.clear()
		return 0

	var migrated_count := 0

	for citizen_index in range(city_citizens.size()):
		var raw_citizen = city_citizens[citizen_index]

		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_was_migrated := false

		if (
			not CityCitizensScript
			.has_complete_city_citizen_task_state(citizen)
		):
			var raw_current_task = citizen.get("current_task", {})

			if raw_current_task is Dictionary:
				citizen["current_task"] = (
					CityCitizensScript.make_city_citizen_task(
						raw_current_task
					)
				)
			else:
				CityCitizensScript.reset_city_citizen_task_state(citizen)

			citizen_was_migrated = true

		if (
			not CityCitizensScript
			.has_complete_city_citizen_haul_state(citizen)
		):
			var raw_current_haul = citizen.get("current_haul", {})
			var raw_haul_cargo = citizen.get("haul_cargo", {})

			if (
				raw_current_haul is Dictionary
				and raw_haul_cargo is Dictionary
			):
				citizen["current_haul"] = (
					CityCitizensScript.make_city_citizen_haul(
						raw_current_haul
					)
				)
				citizen["haul_cargo"] = (
					CityCitizensScript.make_city_citizen_haul_cargo(
						raw_haul_cargo
					)
				)
			else:
				CityCitizensScript.reset_city_citizen_haul_state(
					citizen,
					true
				)
			citizen_was_migrated = true

		if not citizen_was_migrated:
			continue

		city_citizens[citizen_index] = citizen
		migrated_count += 1

	rebuild_city_active_task_registry()

	if migrated_count > 0:
		_mark_city_citizen_task_changed()

	return migrated_count

static func get_city_citizen_current_task(
	citizen_id: int
) -> Dictionary:
	var citizen := get_city_citizen_by_id(citizen_id)
	if citizen.is_empty():
		return {}

	var raw_current_task = citizen.get("current_task", {})

	if not raw_current_task is Dictionary:
		return {}

	return raw_current_task.duplicate(true)


static func assign_city_citizen_task(
	citizen_id: int,
	task_values: Dictionary
) -> bool:
	var assignment := _make_city_citizen_task_assignment_context(
		citizen_id,
		task_values
	)

	if assignment.is_empty():
		return false

	if not _prepare_city_citizen_task_assignment(assignment):
		return false

	return _commit_city_citizen_task_assignment(assignment)


static func _make_city_citizen_task_assignment_context(
	citizen_id: int,
	task_values: Dictionary
) -> Dictionary:
	var citizen_index := get_city_citizen_index_by_id(citizen_id)

	if citizen_index < 0:
		return {}

	var raw_citizen = city_citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return {}

	var citizen: Dictionary = raw_citizen

	if not bool(citizen.get("alive", false)):
		return {}

	var raw_task_kind = task_values.get("kind")
	var raw_task_source = task_values.get("source")
	var raw_task_priority = task_values.get("priority")
	var raw_target_object_id = task_values.get("target_object_id")
	var raw_work_order_id = task_values.get("work_order_id", -1)
	var raw_job_id = task_values.get("job_id", "")
	var raw_player_locked = task_values.get("player_locked", false)

	if typeof(raw_task_kind) != TYPE_STRING:
		return {}

	if typeof(raw_task_source) != TYPE_STRING:
		return {}

	if typeof(raw_task_priority) != TYPE_INT:
		return {}

	if typeof(raw_target_object_id) != TYPE_INT:
		return {}

	if typeof(raw_work_order_id) != TYPE_INT:
		return {}

	if typeof(raw_job_id) != TYPE_STRING:
		return {}

	if typeof(raw_player_locked) != TYPE_BOOL:
		return {}

	var task_kind: String = raw_task_kind
	var task_source: String = raw_task_source
	var task_priority: int = raw_task_priority
	var target_object_id: int = raw_target_object_id
	var work_order_id: int = raw_work_order_id
	var job_id: String = raw_job_id
	var player_locked: bool = raw_player_locked

	if (
		not is_valid_city_citizen_task_kind(task_kind)
		or task_kind == CITY_CITIZEN_TASK_KIND_NONE
	):
		return {}

	if (
		not is_valid_city_citizen_task_source(task_source)
		or task_source == CITY_CITIZEN_TASK_SOURCE_NONE
	):
		return {}

	if task_priority <= CITY_CITIZEN_TASK_PRIORITY_NONE:
		return {}

	if target_object_id <= 0:
		return {}

	if (
		player_locked
		and task_source != CITY_CITIZEN_TASK_SOURCE_PLAYER
	):
		return {}

	# Employment is already a standing player directive. Direct commands and
	# autonomous logistics require unemployment, but biological food seeking is
	# allowed to interrupt employed citizens at critical hunger.
	if (
		(
			task_source == CITY_CITIZEN_TASK_SOURCE_PLAYER
			or task_source == CITY_CITIZEN_TASK_SOURCE_AUTONOMY
		)
		and int(citizen.get("job_object_id", -1)) > 0
		and task_kind != CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD
	):
		return {}

	var raw_existing_task = citizen.get("current_task", {})

	if raw_existing_task is Dictionary:
		var existing_task: Dictionary = raw_existing_task

		if (
			bool(existing_task.get("player_locked", false))
			and task_source != CITY_CITIZEN_TASK_SOURCE_PLAYER
		):
			return {}

		# Replacements must pass through the appropriate cancellation or player-
		# interruption gateway first. That path owns reservation release and cargo
		# preservation, so assigning over an active task can never leak a claim.
		if (
			str(existing_task.get("kind", CITY_CITIZEN_TASK_KIND_NONE))
			!= CITY_CITIZEN_TASK_KIND_NONE
		):
			return {}

	var haul_cargo_amount := maxi(
		int(get_city_citizen_haul_cargo(citizen_id).get("amount", 0)),
		0
	)

	if (
		haul_cargo_amount > 0
		and task_kind != CITY_CITIZEN_TASK_KIND_HAUL
	):
		return {}

	return {
		"citizen_id": citizen_id,
		"citizen_index": citizen_index,
		"citizen": citizen,
		"task_values": task_values,
		"task_kind": task_kind,
		"task_source": task_source,
		"task_priority": task_priority,
		"target_object_id": target_object_id,
		"work_order_id": work_order_id,
		"job_id": job_id,
		"player_locked": player_locked,
		"haul_cargo_amount": haul_cargo_amount,
		"assigned_haul": CityCitizensScript.make_city_citizen_haul(),
		"assigned_target_tile": INVALID_CITY_TILE_POSITION,
		"assigned_food_resource": RESOURCE_NONE,
		"assigned_food_requested_amount": 0,
		"assigned_food_endpoint_kind": CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE,
		"assigned_food_access_purpose": CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_NONE,
	}


static func _prepare_city_citizen_task_assignment(
	assignment: Dictionary
) -> bool:
	match str(assignment.get("task_kind", CITY_CITIZEN_TASK_KIND_NONE)):
		CITY_CITIZEN_TASK_KIND_WORK:
			return _prepare_city_work_task_assignment(assignment)

		CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD:
			return _prepare_city_food_task_assignment(assignment)

		CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND:
			return _prepare_city_player_command_task_assignment(assignment)

		CITY_CITIZEN_TASK_KIND_CONSTRUCTION:
			return CityConstructionSystem.prepare_city_construction_task_assignment(assignment)

		CITY_CITIZEN_TASK_KIND_HAUL:
			return _prepare_city_haul_task_assignment(assignment)

		CITY_CITIZEN_TASK_KIND_RETURN_HOME:
			return _prepare_city_return_home_task_assignment(assignment)

		_:
			return false


static func _prepare_city_work_task_assignment(
	assignment: Dictionary
) -> bool:
	var citizen: Dictionary = assignment.get("citizen", {})
	var target_object_id := int(assignment.get("target_object_id", -1))
	var workplace := CityObjectSystem.get_city_object_by_id(target_object_id)

	if workplace.is_empty() or not city_object_is_workplace(workplace):
		return false

	return int(citizen.get("job_object_id", -1)) == target_object_id


static func _prepare_city_food_task_assignment(
	assignment: Dictionary
) -> bool:
	var citizen_id := int(assignment.get("citizen_id", -1))
	var target_object_id := int(assignment.get("target_object_id", -1))
	var task_values: Dictionary = assignment.get("task_values", {})
	var food_resource := str(
		task_values.get("food_resource_type", RESOURCE_NONE)
	)
	var food_endpoint_kind := str(
		task_values.get(
			"food_source_endpoint_kind",
			CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER
		)
	)
	var food_endpoint := {
		"kind": food_endpoint_kind,
		"id": target_object_id,
	}
	var food_requested_amount := maxi(
		int(task_values.get("food_requested_amount", 0)),
		0
	)
	var food_access_purpose := str(
		task_values.get(
			"food_source_access_purpose",
			CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_NONE
		)
	)
	var raw_food_target_tile = task_values.get(
		"target_tile",
		INVALID_CITY_TILE_POSITION
	)
	var hunger_restore := get_city_food_hunger_restore(food_resource)
	var personal_food_nutrition := (
		CityResourceContainerSystem.get_food_nutrition_in_resource_container(
			get_city_citizen_inventory(citizen_id)
		)
	)
	var desired_nutrition := maxi(
		CITIZEN_EAT_TARGET_HUNGER
		- get_city_citizen_hunger(citizen_id)
		- personal_food_nutrition,
		0
	)

	if (
		hunger_restore <= 0
		or food_requested_amount <= 0
		or desired_nutrition <= 0
		or food_access_purpose
		!= CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_PERSONAL_FOOD
		or not raw_food_target_tile is Vector2i
		or not CityCitizensScript.is_valid_city_citizen_haul_endpoint(
			food_endpoint
		)
		or not get_city_citizen_food_endpoint_target_tiles(
			citizen_id,
			food_endpoint
		).has(raw_food_target_tile)
		or not city_citizen_can_withdraw_food_from_endpoint(
			citizen_id,
			food_endpoint,
			food_resource
		)
	):
		return false

	var assigned_amount := mini(
		food_requested_amount,
		mini(
			get_city_food_endpoint_unreserved_amount(
				citizen_id,
				food_endpoint,
				food_resource,
				citizen_id
			),
			mini(
				get_city_citizen_inventory_free_space(citizen_id),
				ceili(float(desired_nutrition) / float(hunger_restore))
			)
		)
	)

	if assigned_amount <= 0:
		return false

	assignment["assigned_target_tile"] = raw_food_target_tile
	assignment["assigned_food_resource"] = food_resource
	assignment["assigned_food_requested_amount"] = assigned_amount
	assignment["assigned_food_endpoint_kind"] = food_endpoint_kind
	assignment["assigned_food_access_purpose"] = food_access_purpose
	return true


static func _prepare_city_player_command_task_assignment(
	assignment: Dictionary
) -> bool:
	var citizen_id := int(assignment.get("citizen_id", -1))
	var target_object_id := int(assignment.get("target_object_id", -1))
	var task_source := str(assignment.get("task_source", ""))
	var command := WorldPoliticalState.get_current_city_work_state().get_player_command_by_id(target_object_id)

	if (
		task_source != CITY_CITIZEN_TASK_SOURCE_PLAYER
		or command.is_empty()
		or int(command.get("claimed_citizen_id", -1)) != citizen_id
		or not WorldPoliticalState.get_current_city_work_state().is_player_command_target_valid(
			command,
			official_city_world,
			INVALID_CITY_TILE_POSITION
		)
	):
		return false

	var raw_command_tile = command.get(
		"tile_position",
		INVALID_CITY_TILE_POSITION
	)

	if not raw_command_tile is Vector2i:
		return false

	assignment["assigned_target_tile"] = raw_command_tile
	return true


static func _prepare_city_haul_task_assignment(
	assignment: Dictionary
) -> bool:
	var citizen_id := int(assignment.get("citizen_id", -1))
	var target_object_id := int(assignment.get("target_object_id", -1))
	var task_values: Dictionary = assignment.get("task_values", {})
	var haul_cargo_amount := maxi(
		int(assignment.get("haul_cargo_amount", 0)),
		0
	)
	var raw_haul = task_values.get("haul", {})

	if not raw_haul is Dictionary:
		return false

	var assigned_haul := CityCitizensScript.make_city_citizen_haul(raw_haul)
	var haul_phase := str(
		assigned_haul.get("phase", CITY_CITIZEN_HAUL_PHASE_NONE)
	)
	var haul_resource := str(
		assigned_haul.get("resource_type", RESOURCE_NONE)
	)
	var haul_source: Dictionary = assigned_haul.get("source", {})
	var haul_destination: Dictionary = assigned_haul.get("destination", {})
	var haul_requester: Dictionary = assigned_haul.get("requester", {})
	var source_endpoint_id := int(haul_source.get("id", -1))

	if (
		not CityCitizensScript.is_valid_city_citizen_haul_phase(haul_phase)
		or haul_phase == CITY_CITIZEN_HAUL_PHASE_NONE
		or not is_city_resource_type(haul_resource)
		or int(assigned_haul.get("requested_amount", 0)) <= 0
		or str(
			assigned_haul.get("reason", CITY_CITIZEN_HAUL_REASON_NONE)
		) == CITY_CITIZEN_HAUL_REASON_NONE
		or str(
			assigned_haul.get(
				"source_access_purpose",
				CONTAINER_HAUL_PURPOSE_NONE
			)
		) == CONTAINER_HAUL_PURPOSE_NONE
		or str(
			assigned_haul.get(
				"destination_access_purpose",
				CONTAINER_HAUL_PURPOSE_NONE
			)
		) == CONTAINER_HAUL_PURPOSE_NONE
		or not assigned_haul.get("source_tile") is Vector2i
		or not assigned_haul.get("destination_tile") is Vector2i
	):
		return false

	if not CityCitizensScript.is_valid_city_citizen_haul_endpoint(haul_source):
		return false

	if not CityCitizensScript.is_valid_city_citizen_haul_endpoint(haul_requester):
		return false

	if source_endpoint_id != target_object_id:
		return false

	if haul_cargo_amount <= 0:
		if not CityCitizensScript.is_valid_city_citizen_haul_endpoint(
			haul_destination
		):
			return false

		var source_access_purpose := str(
			assigned_haul.get(
				"source_access_purpose",
				CONTAINER_HAUL_PURPOSE_NONE
			)
		)

		if not CityLogisticsSystem.city_haul_endpoint_can_provide_resource({
			"endpoint": haul_source,
			"resource": haul_resource,
			"withdrawal_purpose": source_access_purpose,
			"require_unreserved_amount": true,
		}):
			return false
	else:
		var cargo_resources := get_city_citizen_haul_cargo_resources(citizen_id)

		if cargo_resources.is_empty():
			return false

	if not CityCitizensScript.is_valid_city_citizen_haul_endpoint(
		haul_destination,
		haul_cargo_amount > 0
	):
		return false

	if (
		str(
			haul_destination.get(
				"kind",
				CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
			)
		)
		!= CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
	):
		var destination_access_purpose := str(
			assigned_haul.get(
				"destination_access_purpose",
				CONTAINER_HAUL_PURPOSE_NONE
			)
		)
		var destination_resources: Dictionary = {
			haul_resource: int(assigned_haul.get("requested_amount", 0))
		}

		if haul_cargo_amount > 0:
			destination_resources = get_city_citizen_haul_cargo_resources(
				citizen_id
			)

		for destination_resource in destination_resources.keys():
			if not CityLogisticsSystem.city_haul_endpoint_can_accept_resource({
				"endpoint": haul_destination,
				"resource": str(destination_resource),
				"deposit_purpose": destination_access_purpose,
				"require_unreserved_space": true,
			}):
				return false

		var reservation := CityLogisticsSystem.create_city_haul_reservation({
			"citizen_id": citizen_id,
			"source": haul_source,
			"destination": haul_destination,
			"resource_type": haul_resource,
			"requested_amount": int(
				assigned_haul.get("requested_amount", 0)
			),
			"source_access_purpose": str(
				assigned_haul.get(
					"source_access_purpose",
					CONTAINER_HAUL_PURPOSE_NONE
				)
			),
			"destination_access_purpose": destination_access_purpose,
		})

		if reservation.is_empty():
			return false

		assigned_haul["reservation_id"] = int(reservation.get("id", -1))

		if haul_cargo_amount <= 0:
			assigned_haul["requested_amount"] = int(
				reservation.get("source_reserved_amount", 0)
			)
		else:
			assigned_haul["requested_amount"] = haul_cargo_amount

	assignment["assigned_haul"] = assigned_haul
	return true


static func _prepare_city_return_home_task_assignment(
	assignment: Dictionary
) -> bool:
	var citizen_id := int(assignment.get("citizen_id", -1))
	var citizen: Dictionary = assignment.get("citizen", {})
	var target_object_id := int(assignment.get("target_object_id", -1))
	var home := CityObjectSystem.get_city_object_by_id(target_object_id)

	if (
		home.is_empty()
		or get_city_object_resident_capacity(home) <= 0
		or not CityObjectSystem.city_object_supports_citizen_interior(home)
	):
		return false

	if int(citizen.get("home_object_id", -1)) != target_object_id:
		return false

	if not get_city_object_resident_ids(home).has(citizen_id):
		return false

	return city_citizen_can_access_object_interior(citizen_id, home)


static func _commit_city_citizen_task_assignment(
	assignment: Dictionary
) -> bool:
	var citizen_id := int(assignment.get("citizen_id", -1))
	var citizen_index := int(assignment.get("citizen_index", -1))
	var citizen: Dictionary = assignment.get("citizen", {})
	var task_kind := str(assignment.get("task_kind", ""))
	var current_task := CityCitizensScript.make_city_citizen_task({
		"kind": task_kind,
		"source": str(assignment.get("task_source", "")),
		"phase": CITY_CITIZEN_TASK_PHASE_PENDING,
		"priority": int(assignment.get("task_priority", 0)),
		"target_object_id": int(assignment.get("target_object_id", -1)),
		"work_order_id": int(assignment.get("work_order_id", -1)),
		"job_id": str(assignment.get("job_id", "")),
		"start_world_minute": SimulationClock.absolute_world_minutes,
		"target_tile": assignment.get(
			"assigned_target_tile",
			INVALID_CITY_TILE_POSITION
		),
		"player_locked": bool(assignment.get("player_locked", false)),
		"food_resource_type": str(
			assignment.get("assigned_food_resource", RESOURCE_NONE)
		),
		"food_requested_amount": int(
			assignment.get("assigned_food_requested_amount", 0)
		),
		"food_source_endpoint_kind": str(
			assignment.get(
				"assigned_food_endpoint_kind",
				CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
			)
		),
		"food_source_access_purpose": str(
			assignment.get(
				"assigned_food_access_purpose",
				CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_NONE
			)
		),
	})

	citizen["current_task"] = current_task

	if task_kind == CITY_CITIZEN_TASK_KIND_HAUL:
		citizen["current_haul"] = assignment.get(
			"assigned_haul",
			CityCitizensScript.make_city_citizen_haul()
		)
	else:
		CityCitizensScript.reset_city_citizen_haul_state(citizen)

	city_citizens[citizen_index] = citizen
	_add_city_active_task_id(citizen_id)
	_mark_city_citizen_task_changed()
	return true


static func set_city_citizen_task_phase(
	citizen_id: int,
	task_phase: String
) -> bool:
	if (
		not is_valid_city_citizen_task_phase(task_phase)
		or task_phase == CITY_CITIZEN_TASK_PHASE_NONE
	):
		return false

	var citizen_index := get_city_citizen_index_by_id(
		citizen_id
	)

	if citizen_index < 0:
		return false

	var raw_citizen = city_citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return false

	var citizen: Dictionary = raw_citizen
	var raw_current_task = citizen.get("current_task", {})

	if not raw_current_task is Dictionary:
		return false

	var current_task: Dictionary = (
		raw_current_task.duplicate(true)
	)

	if (
		str(current_task.get("kind", ""))
		== CITY_CITIZEN_TASK_KIND_NONE
	):
		return false

	if str(current_task.get("phase", "")) == task_phase:
		return true

	current_task["phase"] = task_phase
	citizen["current_task"] = current_task
	city_citizens[citizen_index] = citizen
	_mark_city_citizen_task_changed()

	return true

static func set_city_citizen_task_target_object_id(
	citizen_id: int,
	target_object_id: int
) -> bool:
	if target_object_id <= 0:
		return false

	var citizen_index := get_city_citizen_index_by_id(citizen_id)

	if citizen_index < 0:
		return false

	var raw_citizen = city_citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return false

	var citizen: Dictionary = raw_citizen
	var raw_current_task = citizen.get("current_task", {})

	if not raw_current_task is Dictionary:
		return false

	var current_task: Dictionary = raw_current_task.duplicate(true)

	if (
		str(current_task.get("kind", ""))
		!= CITY_CITIZEN_TASK_KIND_HAUL
	):
		return false

	if int(current_task.get("target_object_id", -1)) == target_object_id:
		return true

	current_task["target_object_id"] = target_object_id
	citizen["current_task"] = current_task
	city_citizens[citizen_index] = citizen
	_mark_city_citizen_task_changed()
	return true


static func set_city_citizen_task_activity_state(
	values: Dictionary
) -> bool:
	if not values.has("citizen_id") or not values.has("target_tile"):
		push_error(
			"Citizen task activity state requires citizen_id and target_tile."
		)
		return false

	var raw_target_tile = values["target_tile"]
	var raw_previous_target_tile = values.get(
		"previous_target_tile",
		INVALID_CITY_TILE_POSITION
	)

	if not raw_target_tile is Vector2i:
		push_error(
			"Citizen task activity target_tile must be Vector2i."
		)
		return false

	if not raw_previous_target_tile is Vector2i:
		push_error(
			"Citizen task activity previous_target_tile must be Vector2i."
		)
		return false

	var citizen_id := int(values["citizen_id"])
	var target_tile: Vector2i = raw_target_tile
	var previous_target_tile: Vector2i = raw_previous_target_tile
	var next_action_world_minute := int(
		values.get(
			"next_action_world_minute",
			INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
		)
	)
	var relocation_count := int(
		values.get("relocation_count", -1)
	)
	var citizen_index := get_city_citizen_index_by_id(
		citizen_id
	)

	if citizen_index < 0:
		return false

	var raw_citizen = city_citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return false

	var citizen: Dictionary = raw_citizen
	var raw_current_task = citizen.get(
		"current_task",
		{}
	)

	if not raw_current_task is Dictionary:
		return false

	var current_task: Dictionary = (
		raw_current_task.duplicate(true)
	)

	if (
		str(current_task.get("kind", ""))
		== CITY_CITIZEN_TASK_KIND_NONE
	):
		return false
	var stored_relocation_count := maxi(
		int(current_task.get("relocation_count", 0)),
		0
	)
	var resolved_relocation_count := relocation_count

	if resolved_relocation_count < 0:
		resolved_relocation_count = stored_relocation_count
	if (
		current_task.get(
			"target_tile",
			INVALID_CITY_TILE_POSITION
		) == target_tile
		and current_task.get(
			"previous_target_tile",
			INVALID_CITY_TILE_POSITION
		) == previous_target_tile
		and int(
			current_task.get(
				"next_action_world_minute",
				INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
			)
		) == next_action_world_minute
		and stored_relocation_count == resolved_relocation_count
	):
		return true

	current_task["target_tile"] = target_tile
	current_task["previous_target_tile"] = (
		previous_target_tile
	)
	current_task["next_action_world_minute"] = (
		next_action_world_minute
	)
	current_task["relocation_count"] = (
		resolved_relocation_count
	)

	citizen["current_task"] = current_task
	city_citizens[citizen_index] = citizen
	_mark_city_citizen_task_changed()

	return true

static func clear_city_citizen_task(
	citizen_id: int,
	requesting_source: String = CITY_CITIZEN_TASK_SOURCE_NONE
) -> bool:
	if not is_valid_city_citizen_task_source(
		requesting_source
	):
		return false

	var citizen_index := get_city_citizen_index_by_id(
		citizen_id
	)

	if citizen_index < 0:
		return false

	var raw_citizen = city_citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return false

	var citizen: Dictionary = raw_citizen
	var raw_current_task = citizen.get("current_task", {})

	if raw_current_task is Dictionary:
		var current_task: Dictionary = raw_current_task

		if (
			bool(current_task.get("player_locked", false))
			and requesting_source
			!= CITY_CITIZEN_TASK_SOURCE_PLAYER
		):
			return false

	var empty_task := CityCitizensScript.make_city_citizen_task()
	var active_reservation_id := (
		CityLogisticsSystem.get_city_haul_reservation_id_for_citizen(citizen_id)
	)

	if active_reservation_id > 0:
		CityLogisticsSystem.release_city_haul_reservation(active_reservation_id)

	if (
		raw_current_task is Dictionary
		and raw_current_task == empty_task
	):
		return true

	var current_task_kind := CITY_CITIZEN_TASK_KIND_NONE

	if raw_current_task is Dictionary:
		current_task_kind = str(
			raw_current_task.get(
				"kind",
				CITY_CITIZEN_TASK_KIND_NONE
			)
		)

	if current_task_kind == CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND:
		WorldPoliticalState.get_current_city_work_state().release_player_command_claim(
			int(raw_current_task.get("target_object_id", -1)),
			citizen_id
		)

	if current_task_kind == CITY_CITIZEN_TASK_KIND_HAUL:
		var raw_cargo = citizen.get("haul_cargo", {})
		var cargo := CityCitizensScript.make_city_citizen_haul_cargo()

		if raw_cargo is Dictionary:
			cargo = (
				CityCitizensScript.make_city_citizen_haul_cargo(
					raw_cargo
				)
			)

		if int(cargo.get("amount", 0)) > 0:
			var raw_haul = citizen.get("current_haul", {})
			var current_haul := (
				CityCitizensScript.make_city_citizen_haul()
			)

			if raw_haul is Dictionary:
				current_haul = (
					CityCitizensScript.make_city_citizen_haul(
						raw_haul
					)
				)

			current_haul["phase"] = (
				CITY_CITIZEN_HAUL_PHASE_RETARGETING
			)
			current_haul["reservation_id"] = (
				INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
			)
			current_haul["destination_tile"] = (
				INVALID_CITY_TILE_POSITION
			)
			citizen["current_haul"] = current_haul
		else:
			CityCitizensScript.reset_city_citizen_haul_state(
				citizen
			)

	citizen["current_task"] = empty_task
	city_citizens[citizen_index] = citizen
	_remove_city_active_task_id(citizen_id)
	_mark_city_citizen_task_changed()

	return true

#endregion

#region Citizen Movement and Spatial State

static func is_valid_city_citizen_movement_state(
	movement_state: String
) -> bool:
	return CityCitizensScript.is_valid_city_citizen_movement_state(
		movement_state
	)


static func is_valid_city_citizen_movement_failure(
	failure_reason: String
) -> bool:
	return CityCitizensScript.is_valid_city_citizen_movement_failure(
		failure_reason
	)


static func ensure_city_citizen_movement_state() -> int:
	if city_citizens.is_empty():
		city_active_mover_ids.clear()
		city_active_mover_id_lookup.clear()
		return 0

	var migrated_count := 0

	for citizen_index in range(city_citizens.size()):
		var raw_citizen = city_citizens[citizen_index]

		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if (
			CityCitizensScript
			.has_complete_city_citizen_movement_state(
				citizen
			)
		):
			continue

		CityCitizensScript.reset_city_citizen_movement_state(
			citizen
		)
		city_citizens[citizen_index] = citizen
		migrated_count += 1

	rebuild_city_active_mover_registry()

	if migrated_count > 0:
		_mark_city_citizen_movement_changed()

	return migrated_count

static func ensure_city_citizen_spatial_state(
	city_world: WorldData
) -> int:
	if city_world == null:
		return 0

	if city_citizens.is_empty():
		city_citizen_ids_by_tile.clear()
		return 0

	var citizens_missing_position := []

	for citizen_index in range(
		city_citizens.size()
	):
		var raw_citizen = city_citizens[
			citizen_index
		]

		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if citizen.has("city_tile_position"):
			continue

		citizens_missing_position.append(
			citizen_index
		)

	var initialized_count := 0

	if not citizens_missing_position.is_empty():
		var spawn_tiles := (
			get_starting_city_citizen_spawn_tiles(
				city_world
			)
		)

		if spawn_tiles.is_empty():
			rebuild_city_citizen_spatial_index()

			push_error(
				"Cannot initialize legacy citizen positions: "
				+ "the City Keep has no walkable access tiles."
			)

			return 0

		for raw_citizen_index in (
			citizens_missing_position
		):
			var citizen_index: int = (
				raw_citizen_index
			)
			var raw_citizen = city_citizens[
				citizen_index
			]

			if not raw_citizen is Dictionary:
				continue

			var citizen: Dictionary = raw_citizen
			var spawn_tile: Vector2i = spawn_tiles[
				citizen_index % spawn_tiles.size()
			]

			citizen["city_tile_position"] = (
				spawn_tile
			)
			city_citizens[citizen_index] = (
				citizen
			)
			initialized_count += 1

	rebuild_city_citizen_spatial_index()

	if initialized_count > 0:
		_mark_city_citizen_spatial_changed()

	return initialized_count

static func get_city_citizen_tile_position(
	citizen_id: int
) -> Vector2i:
	var citizen := get_city_citizen_by_id(
		citizen_id
	)

	if citizen.is_empty():
		return INVALID_CITY_TILE_POSITION

	var raw_position = citizen.get(
		"city_tile_position",
		INVALID_CITY_TILE_POSITION
	)

	if not raw_position is Vector2i:
		return INVALID_CITY_TILE_POSITION

	return raw_position


static func set_city_citizen_tile_position(
	city_world: WorldData,
	citizen_id: int,
	tile_position: Vector2i
) -> bool:
	if not is_city_tile_walkable_for_citizen(
		city_world,
		tile_position,
		citizen_id
	):
		return false

	var citizen_index := (
		get_city_citizen_index_by_id(
			citizen_id
		)
	)

	if citizen_index < 0:
		return false

	var raw_citizen = city_citizens[
		citizen_index
	]

	if not raw_citizen is Dictionary:
		return false

	var citizen: Dictionary = raw_citizen
	var current_position = citizen.get(
		"city_tile_position",
		INVALID_CITY_TILE_POSITION
	)

	if current_position == tile_position:
		return true

	if current_position is Vector2i:
		_remove_city_citizen_from_spatial_index(
			citizen_id,
			current_position
		)

	citizen["city_tile_position"] = tile_position
	city_citizens[citizen_index] = citizen

	_add_city_citizen_to_spatial_index(
		citizen_id,
		tile_position
	)

	_mark_city_citizen_spatial_changed()

	return true

static func _get_clean_city_citizen_movement_path(
	city_world: WorldData,
	raw_path: Array,
	citizen_id: int = -1
) -> Array:
	var movement_path := []

	if city_world == null:
		return movement_path

	if raw_path.is_empty():
		return movement_path

	var previous_tile := INVALID_CITY_TILE_POSITION

	for raw_path_tile in raw_path:
		if not raw_path_tile is Vector2i:
			return []

		var path_tile: Vector2i = raw_path_tile

		if not is_city_tile_walkable_for_citizen(
			city_world,
			path_tile,
			citizen_id
		):
			return []

		if previous_tile != INVALID_CITY_TILE_POSITION:
			if get_city_citizen_movement_step_cost(
				previous_tile,
				path_tile
			) <= 0:
				return []

			if not can_city_citizen_traverse_step(
				city_world,
				previous_tile,
				path_tile,
				citizen_id
			):
				return []

		movement_path.append(path_tile)
		previous_tile = path_tile

	return movement_path

static func cancel_city_citizen_movement(
	citizen_id: int
) -> bool:
	var citizen_index := get_city_citizen_index_by_id(
		citizen_id
	)

	if citizen_index < 0:
		return false

	var raw_citizen = city_citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return false

	var citizen: Dictionary = raw_citizen

	CityCitizensScript.reset_city_citizen_movement_state(
		citizen,
		true
	)
	city_citizens[citizen_index] = citizen

	_remove_city_active_mover_id(citizen_id)
	_mark_city_citizen_movement_changed()

	return true


static func assign_city_citizen_movement_order(
	citizen_id: int,
	raw_path: Array
) -> bool:
	var city_world: WorldData = official_city_world

	if city_world == null:
		return false

	var citizen_index := get_city_citizen_index_by_id(
		citizen_id
	)

	if citizen_index < 0:
		return false

	var raw_citizen = city_citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return false

	var citizen: Dictionary = raw_citizen

	if not bool(citizen.get("alive", false)):
		return false

	var current_position = citizen.get(
		"city_tile_position",
		INVALID_CITY_TILE_POSITION
	)

	if not current_position is Vector2i:
		return false

	var movement_path := _get_clean_city_citizen_movement_path(
		city_world,
		raw_path,
		citizen_id
	)

	if movement_path.is_empty():
		return false

	if movement_path[0] != current_position:
		return false

	if movement_path.size() == 1:
		cancel_city_citizen_movement(citizen_id)
		return true

	var movement_speed := int(
		citizen.get(
			"movement_speed_basis_points_per_minute",
			DEFAULT_CITIZEN_MOVEMENT_SPEED_PER_MINUTE
		)
	)

	if movement_speed <= 0:
		movement_speed = (
			DEFAULT_CITIZEN_MOVEMENT_SPEED_PER_MINUTE
		)

	citizen["movement_state"] = (
		CITY_CITIZEN_MOVEMENT_STATE_MOVING
	)
	citizen["movement_path"] = movement_path.duplicate()
	citizen["movement_path_index"] = 1
	citizen["movement_progress_basis_points"] = 0
	citizen["movement_destination_tile"] = (
		movement_path.back()
	)
	citizen["movement_speed_basis_points_per_minute"] = (
		movement_speed
	)
	citizen["movement_repath_attempt_count"] = 0
	citizen["movement_failure_reason"] = (
		CITY_CITIZEN_MOVEMENT_FAILURE_NONE
	)

	city_citizens[citizen_index] = citizen

	_add_city_active_mover_id(citizen_id)
	_mark_city_citizen_movement_changed()

	return true

static func commit_city_citizen_movement_tick(
	city_world: WorldData,
	raw_citizen_updates: Array,
	raw_next_active_mover_ids: Array[int]
) -> Dictionary:
	var result := {
		"success": false,
		"updated_citizen_count": 0,
		"moved_citizen_count": 0,
		"rejected_update_count": 0,
		"rejected_updates": [],
	}

	if city_world == null:
		return result

	var update_normalization := _normalize_city_citizen_movement_updates(
		city_world,
		raw_citizen_updates
	)
	var clean_updates: Array = update_normalization.get("updates", [])
	var clean_update_by_id: Dictionary = update_normalization.get(
		"update_by_id",
		{}
	)
	var rejected_updates: Array = update_normalization.get(
		"rejected_updates",
		[]
	)
	var rejected_id_lookup: Dictionary = {}

	for raw_rejection in rejected_updates:
		if not raw_rejection is Dictionary:
			continue

		var rejected_id := int(raw_rejection.get("citizen_id", -1))

		if rejected_id > 0:
			rejected_id_lookup[rejected_id] = true

	var active_normalization := _normalize_next_active_mover_ids(
		raw_next_active_mover_ids,
		clean_update_by_id,
		rejected_id_lookup
	)
	var clean_next_active_ids: Array[int] = active_normalization.get(
		"active_ids",
		[]
	)
	rejected_updates.append_array(
		active_normalization.get("rejected_updates", [])
	)

	var application_result := _apply_city_citizen_movement_updates(
		clean_updates
	)
	var moved_citizen_count := int(
		application_result.get("moved_citizen_count", 0)
	)
	var quarantined_count := (
		_quarantine_rejected_city_citizen_movement_updates(
			rejected_updates
		)
	)
	var active_registry_changed := (
		city_active_mover_ids != clean_next_active_ids
	)

	_replace_city_active_mover_registry(clean_next_active_ids)

	if (
		not clean_updates.is_empty()
		or quarantined_count > 0
		or active_registry_changed
	):
		_mark_city_citizen_movement_changed()

	if moved_citizen_count > 0:
		_mark_city_citizen_spatial_changed()

	city_citizen_movement_visual_events = application_result.get(
		"movement_visual_events",
		[]
	)
	result["success"] = true
	result["updated_citizen_count"] = clean_updates.size()
	result["moved_citizen_count"] = moved_citizen_count
	result["rejected_update_count"] = rejected_updates.size()
	result["rejected_updates"] = rejected_updates
	return result


static func _make_city_citizen_movement_rejection(
	citizen_id: int,
	reason: String,
	final_tile = INVALID_CITY_TILE_POSITION,
	quarantine: bool = true
) -> Dictionary:
	var rejection := {
		"citizen_id": citizen_id,
		"reason": reason,
		"quarantine": quarantine,
	}

	if final_tile is Vector2i:
		rejection["final_tile"] = final_tile
		rejection["occupying_object_id"] = int(
			CityObjectSystem.get_city_object_id_at_tile(final_tile)
		)

	return rejection


static func _normalize_city_citizen_movement_updates(
	city_world: WorldData,
	raw_citizen_updates: Array
) -> Dictionary:
	var clean_updates: Array = []
	var clean_update_by_id: Dictionary = {}
	var rejected_updates: Array = []

	for raw_update in raw_citizen_updates:
		if not raw_update is Dictionary:
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					-1,
					"update_is_not_dictionary",
					INVALID_CITY_TILE_POSITION,
					false
				)
			)
			continue

		var update: Dictionary = raw_update
		var citizen_id := int(update.get("citizen_id", -1))
		var raw_updated_citizen = update.get("citizen", {})
		var raw_final_tile = update.get(
			"final_tile",
			INVALID_CITY_TILE_POSITION
		)
		var raw_traversed_tiles = update.get("traversed_tiles", [])

		if citizen_id <= 0:
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"invalid_citizen_id",
					raw_final_tile,
					false
				)
			)
			continue

		if clean_update_by_id.has(citizen_id):
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"duplicate_update",
					raw_final_tile,
					false
				)
			)
			continue

		if not raw_updated_citizen is Dictionary:
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"updated_citizen_is_not_dictionary",
					raw_final_tile
				)
			)
			continue

		if not raw_final_tile is Vector2i:
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"final_tile_is_not_vector"
				)
			)
			continue

		if not raw_traversed_tiles is Array:
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"traversed_tiles_is_not_array",
					raw_final_tile
				)
			)
			continue

		if not is_city_tile_walkable_for_citizen(
			city_world,
			raw_final_tile,
			citizen_id
		):
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"final_tile_not_walkable",
					raw_final_tile
				)
			)
			continue

		var citizen_index := get_city_citizen_index_by_id(citizen_id)

		if citizen_index < 0:
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"citizen_not_found",
					raw_final_tile,
					false
				)
			)
			continue

		var updated_citizen: Dictionary = raw_updated_citizen

		if int(updated_citizen.get("id", -1)) != citizen_id:
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"updated_citizen_id_mismatch",
					raw_final_tile
				)
			)
			continue

		var existing_citizen = city_citizens[citizen_index]

		if not existing_citizen is Dictionary:
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"authoritative_citizen_is_not_dictionary",
					raw_final_tile,
					false
				)
			)
			continue

		if not (
			existing_citizen.get(
				"city_tile_position",
				INVALID_CITY_TILE_POSITION
			)
			is Vector2i
		):
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"authoritative_position_invalid",
					raw_final_tile
				)
			)
			continue

		var clean_update := {
			"citizen_id": citizen_id,
			"citizen_index": citizen_index,
			"citizen": updated_citizen,
			"final_tile": raw_final_tile,
			"traversed_tiles": raw_traversed_tiles,
		}
		clean_updates.append(clean_update)
		clean_update_by_id[citizen_id] = clean_update

	return {
		"updates": clean_updates,
		"update_by_id": clean_update_by_id,
		"rejected_updates": rejected_updates,
	}


static func _normalize_next_active_mover_ids(
	raw_next_active_mover_ids: Array[int],
	clean_update_by_id: Dictionary,
	rejected_id_lookup: Dictionary
) -> Dictionary:
	var clean_next_active_ids: Array[int] = []
	var clean_next_active_lookup: Dictionary = {}
	var rejected_updates: Array = []

	for citizen_id in raw_next_active_mover_ids:
		if rejected_id_lookup.has(citizen_id):
			continue

		if citizen_id <= 0 or clean_next_active_lookup.has(citizen_id):
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"invalid_or_duplicate_active_mover",
					INVALID_CITY_TILE_POSITION,
					false
				)
			)
			continue

		var proposed_citizen := get_city_citizen_by_id(citizen_id)

		if clean_update_by_id.has(citizen_id):
			var proposed_update: Dictionary = clean_update_by_id[citizen_id]
			proposed_citizen = proposed_update.get("citizen", {})

		if proposed_citizen.is_empty():
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"active_mover_citizen_missing",
					INVALID_CITY_TILE_POSITION,
					false
				)
			)
			continue

		if not bool(proposed_citizen.get("alive", false)):
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"active_mover_not_alive",
					INVALID_CITY_TILE_POSITION,
					false
				)
			)
			continue

		if (
			str(proposed_citizen.get("movement_state", ""))
			!= CITY_CITIZEN_MOVEMENT_STATE_MOVING
		):
			rejected_updates.append(
				_make_city_citizen_movement_rejection(
					citizen_id,
					"active_registry_entry_not_moving",
					INVALID_CITY_TILE_POSITION,
					false
				)
			)
			continue

		clean_next_active_ids.append(citizen_id)
		clean_next_active_lookup[citizen_id] = true

	clean_next_active_ids.sort()
	return {
		"active_ids": clean_next_active_ids,
		"rejected_updates": rejected_updates,
	}


static func _quarantine_rejected_city_citizen_movement_updates(
	rejected_updates: Array
) -> int:
	var quarantined_ids: Dictionary = {}

	for raw_rejection in rejected_updates:
		if not raw_rejection is Dictionary:
			continue

		var rejection: Dictionary = raw_rejection
		var citizen_id := int(rejection.get("citizen_id", -1))

		if (
			citizen_id <= 0
			or not bool(rejection.get("quarantine", true))
			or quarantined_ids.has(citizen_id)
		):
			continue

		var citizen_index := get_city_citizen_index_by_id(citizen_id)

		if citizen_index < 0:
			continue

		var raw_citizen = city_citizens[citizen_index]

		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		CityCitizensScript.reset_city_citizen_movement_state(citizen, true)
		citizen["movement_state"] = CITY_CITIZEN_MOVEMENT_STATE_BLOCKED
		citizen["movement_failure_reason"] = (
			CITY_CITIZEN_MOVEMENT_FAILURE_INVALID_PATH
		)
		city_citizens[citizen_index] = citizen
		quarantined_ids[citizen_id] = true

	return quarantined_ids.size()


static func _apply_city_citizen_movement_updates(
	clean_updates: Array
) -> Dictionary:
	var moved_citizen_count := 0
	var movement_visual_events: Array = []

	for clean_update in clean_updates:
		var citizen_id := int(clean_update.get("citizen_id", -1))
		var citizen_index := int(clean_update.get("citizen_index", -1))
		var updated_citizen: Dictionary = clean_update.get("citizen", {})
		var final_tile: Vector2i = clean_update.get(
			"final_tile",
			INVALID_CITY_TILE_POSITION
		)
		var existing_citizen: Dictionary = city_citizens[citizen_index]
		var old_tile: Vector2i = existing_citizen.get(
			"city_tile_position",
			INVALID_CITY_TILE_POSITION
		)
		var movement_visual_event := _make_city_citizen_movement_visual_event({
			"before_citizen": existing_citizen,
			"after_citizen": updated_citizen,
			"before_tile": old_tile,
			"after_tile": final_tile,
			"traversed_tiles": clean_update.get("traversed_tiles", []),
		})

		if not movement_visual_event.is_empty():
			movement_visual_events.append(movement_visual_event)

		if old_tile != final_tile:
			_remove_city_citizen_from_spatial_index(citizen_id, old_tile)
			moved_citizen_count += 1

		updated_citizen["city_tile_position"] = final_tile
		city_citizens[citizen_index] = updated_citizen
		_add_city_citizen_to_spatial_index(citizen_id, final_tile)

	return {
		"moved_citizen_count": moved_citizen_count,
		"movement_visual_events": movement_visual_events,
	}


static func _replace_city_active_mover_registry(
	clean_next_active_ids: Array[int]
) -> void:
	city_active_mover_ids.clear()
	city_active_mover_id_lookup.clear()

	for citizen_id in clean_next_active_ids:
		city_active_mover_ids.append(citizen_id)
		city_active_mover_id_lookup[citizen_id] = true


static func _make_city_citizen_movement_visual_event(
	values: Dictionary
) -> Dictionary:
	var before_citizen: Dictionary = values.get("before_citizen", {})
	var after_citizen: Dictionary = values.get("after_citizen", {})
	var before_tile: Vector2i = values.get(
		"before_tile",
		INVALID_CITY_TILE_POSITION
	)
	var after_tile: Vector2i = values.get(
		"after_tile",
		INVALID_CITY_TILE_POSITION
	)
	var raw_traversed_tiles = values.get("traversed_tiles", [])
	var citizen_id := int(before_citizen.get("id", -1))

	if citizen_id <= 0:
		return {}

	if int(after_citizen.get("id", -1)) != citizen_id:
		return {}

	return {
		"citizen_id": citizen_id,
		"before": _make_city_citizen_movement_visual_snapshot(
			before_citizen,
			before_tile
		),
		"after": _make_city_citizen_movement_visual_snapshot(
			after_citizen,
			after_tile
		),
		"traversed_tiles": (
			_get_clean_city_citizen_movement_visual_trace(
				before_tile,
				after_tile,
				raw_traversed_tiles
			)
		)
	}


static func _make_city_citizen_movement_visual_snapshot(
	citizen: Dictionary,
	tile_position: Vector2i
) -> Dictionary:
	var raw_path = citizen.get("movement_path", [])
	var movement_path_index := int(citizen.get(
		"movement_path_index",
		0
	))
	var movement_progress := int(citizen.get(
		"movement_progress_basis_points",
		0
	))
	var movement_state := str(citizen.get("movement_state", ""))
	var visual_position := Vector2(tile_position)
	var visual_step_target_tile := INVALID_CITY_TILE_POSITION

	if (
		movement_state == CITY_CITIZEN_MOVEMENT_STATE_MOVING
		and raw_path is Array
		and movement_path_index >= 1
		and movement_path_index < raw_path.size()
		and raw_path[movement_path_index - 1] is Vector2i
		and raw_path[movement_path_index] is Vector2i
	):
		var from_tile: Vector2i = raw_path[movement_path_index - 1]
		var to_tile: Vector2i = raw_path[movement_path_index]
		var step_cost := get_city_citizen_movement_step_cost(
			from_tile,
			to_tile
		)

		if step_cost > 0:
			visual_step_target_tile = to_tile
			visual_position = Vector2(from_tile).lerp(
				Vector2(to_tile),
				clampf(
					float(movement_progress) / float(step_cost),
					0.0,
					1.0
				)
			)

	return {
		"id": int(citizen.get("id", -1)),
		"alive": bool(citizen.get("alive", false)),
		"city_tile_position": tile_position,
		"movement_state": movement_state,
		"movement_visual_position": visual_position,
		"movement_visual_step_target_tile": visual_step_target_tile,
		"movement_speed_basis_points_per_minute": int(citizen.get(
			"movement_speed_basis_points_per_minute",
			DEFAULT_CITIZEN_MOVEMENT_SPEED_PER_MINUTE
		))
	}


static func _get_clean_city_citizen_movement_visual_trace(
	before_tile: Vector2i,
	after_tile: Vector2i,
	raw_traversed_tiles
) -> Array[Vector2i]:
	var clean_tiles: Array[Vector2i] = [before_tile]

	if raw_traversed_tiles is Array:
		for raw_tile in raw_traversed_tiles:
			if not raw_tile is Vector2i:
				continue

			var tile: Vector2i = raw_tile

			if tile == clean_tiles.back():
				continue

			if (
				get_city_citizen_movement_step_cost(
					clean_tiles.back(),
					tile
				)
				<= 0
			):
				break

			clean_tiles.append(tile)

	if (
		clean_tiles.back() != after_tile
		and get_city_citizen_movement_step_cost(
			clean_tiles.back(),
			after_tile
		) > 0
	):
		clean_tiles.append(after_tile)

	return clean_tiles


#endregion

#region Population, Housing, and Workplace Queries

static func get_city_population_count() -> int:
	return city_citizens.size()

static func get_city_housed_citizen_count() -> int:

	var housed_count := 0

	for citizen in city_citizens:
		if not citizen is Dictionary:
			continue

		if int(citizen.get("home_object_id", -1)) >= 0:
			housed_count += 1

	return housed_count


static func get_city_unemployed_citizen_count() -> int:

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

	var citizen_index := get_city_citizen_index_by_id(citizen_id)

	if citizen_index < 0:
		return {}

	var raw_citizen = city_citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return {}

	return raw_citizen


static func get_city_citizen_culture_id(citizen_id: int) -> int:
	var citizen := get_city_citizen_by_id(citizen_id)

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


static func get_city_citizen_display_name(citizen_id: int) -> String:
	var citizen := get_city_citizen_by_id(citizen_id)

	if citizen.is_empty():
		return "Citizen " + str(citizen_id)

	return str(citizen.get("name", "Citizen " + str(citizen_id)))


static func get_city_citizen_snapshot() -> Array:

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

	for city_object in CityObjectSystem.get_city_objects():
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

static func _city_citizen_matches_workplace_attendance(
	citizen: Dictionary,
	workplace_id: int,
	access_tiles: Array
) -> bool:
	if citizen.is_empty():
		return false

	if not bool(citizen.get("alive", false)):
		return false

	if int(citizen.get("job_object_id", -1)) != workplace_id:
		return false

	var raw_current_task = citizen.get("current_task", {})

	if not raw_current_task is Dictionary:
		return false

	var current_task: Dictionary = raw_current_task

	if (
		str(current_task.get("kind", ""))
		!= CITY_CITIZEN_TASK_KIND_WORK
	):
		return false

	if (
		str(current_task.get("phase", ""))
		!= CITY_CITIZEN_TASK_PHASE_PERFORMING
	):
		return false

	if (
		int(current_task.get("target_object_id", -1))
		!= workplace_id
	):
		return false

	if (
		str(citizen.get("movement_state", ""))
		!= CITY_CITIZEN_MOVEMENT_STATE_IDLE
	):
		return false

	var raw_tile_position = citizen.get(
		"city_tile_position",
		INVALID_CITY_TILE_POSITION
	)

	if not raw_tile_position is Vector2i:
		return false

	var citizen_tile: Vector2i = raw_tile_position
	var raw_target_tile = current_task.get(
		"target_tile",
		INVALID_CITY_TILE_POSITION
	)

	if raw_target_tile is Vector2i:
		var target_tile: Vector2i = raw_target_tile

		if target_tile != INVALID_CITY_TILE_POSITION:
			return citizen_tile == target_tile

	return access_tiles.has(citizen_tile)

static func is_city_citizen_attending_workplace(
	citizen_id: int,
	workplace_id: int,
	source_world = null
) -> bool:
	if citizen_id <= 0 or workplace_id <= 0:
		return false

	var workplace := CityObjectSystem.get_city_object_by_id(workplace_id)

	if (
		workplace.is_empty()
		or not city_object_is_workplace(workplace)
	):
		return false

	var city_world: WorldData = source_world

	if city_world == null:
		city_world = official_city_world

	if city_world == null:
		return false

	var access_tiles := get_city_object_access_tiles(
		city_world,
		workplace
	)

	return _city_citizen_matches_workplace_attendance(
		get_city_citizen_by_id(citizen_id),
		workplace_id,
		access_tiles
	)

static func get_city_object_attending_worker_ids(
	city_object: Dictionary,
	source_world = null
) -> Array[int]:
	var attending_worker_ids: Array[int] = []

	if (
		city_object.is_empty()
		or not city_object_is_workplace(city_object)
	):
		return attending_worker_ids

	var workplace_id := int(city_object.get("id", -1))
	var worker_capacity := get_city_object_worker_capacity(
		city_object
	)

	if workplace_id <= 0 or worker_capacity <= 0:
		return attending_worker_ids

	var city_world: WorldData = source_world

	if city_world == null:
		city_world = official_city_world

	if city_world == null:
		return attending_worker_ids

	var access_tiles := get_city_object_access_tiles(
		city_world,
		city_object
	)

	if access_tiles.is_empty():
		return attending_worker_ids

	var counted_worker_ids: Dictionary = {}

	for raw_worker_id in get_city_object_worker_ids(
		city_object
	):
		var worker_id := int(raw_worker_id)

		if worker_id <= 0:
			continue

		if counted_worker_ids.has(worker_id):
			continue

		counted_worker_ids[worker_id] = true

		if not _city_citizen_matches_workplace_attendance(
			get_city_citizen_by_id(worker_id),
			workplace_id,
			access_tiles
		):
			continue

		attending_worker_ids.append(worker_id)

	attending_worker_ids.sort()

	if attending_worker_ids.size() > worker_capacity:
		attending_worker_ids.resize(worker_capacity)

	return attending_worker_ids


static func get_city_object_attending_worker_count(
	city_object: Dictionary,
	source_world = null
) -> int:
	if (
		city_object.is_empty()
		or not city_object_is_workplace(city_object)
	):
		return 0

	var workplace_id := int(city_object.get("id", -1))
	var worker_capacity := get_city_object_worker_capacity(
		city_object
	)

	if workplace_id <= 0 or worker_capacity <= 0:
		return 0

	var city_world: WorldData = source_world

	if city_world == null:
		city_world = official_city_world

	if city_world == null:
		return 0

	var access_tiles := get_city_object_access_tiles(
		city_world,
		city_object
	)

	if access_tiles.is_empty():
		return 0

	var counted_worker_ids: Dictionary = {}
	var attending_worker_count := 0

	for raw_worker_id in get_city_object_worker_ids(
		city_object
	):
		var worker_id := int(raw_worker_id)

		if worker_id <= 0 or counted_worker_ids.has(worker_id):
			continue

		counted_worker_ids[worker_id] = true

		if not _city_citizen_matches_workplace_attendance(
			get_city_citizen_by_id(worker_id),
			workplace_id,
			access_tiles
		):
			continue

		attending_worker_count += 1

		if attending_worker_count >= worker_capacity:
			break

	return attending_worker_count

static func get_city_object_worker_count(city_object: Dictionary) -> int:
	if city_object.is_empty():
		return 0

	if city_object.has("assigned_worker_ids"):
		var raw_worker_ids = city_object.get(
			"assigned_worker_ids",
			[]
		)

		if raw_worker_ids is Array:
			return raw_worker_ids.size()

	var object_id := int(city_object.get("id", -1))
	var worker_count := 0

	if object_id < 0:
		return worker_count

	for raw_citizen in city_citizens:
		if not raw_citizen is Dictionary:
			continue

		if (
			int(raw_citizen.get("job_object_id", -1))
			== object_id
		):
			if int(raw_citizen.get("id", -1)) < 0:
				continue

			worker_count += 1

	return worker_count

static func get_first_unemployed_city_citizen_index() -> int:

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

	var assigned_count := 0

	for object_index in range(CityObjectSystem.get_city_objects().size()):
		var raw_city_object = CityObjectSystem.get_city_objects()[object_index]

		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object

		if not city_object_is_workplace(city_object):
			continue

		var workplace_id := int(
			city_object.get("id", -1)
		)

		if workplace_id < 0:
			continue

		var worker_capacity := get_city_object_worker_capacity(
			city_object
		)

		if worker_capacity <= 0:
			continue

		while true:
			var current_workplace := CityObjectSystem.get_city_object_by_id(
				workplace_id
			)

			if current_workplace.is_empty():
				break

			if (
				get_city_object_worker_count(current_workplace)
				>= worker_capacity
			):
				break

			var unemployed_citizen_index := (
				get_first_unemployed_city_citizen_index()
			)

			if unemployed_citizen_index < 0:
				break

			var raw_citizen = city_citizens[
				unemployed_citizen_index
			]

			if not raw_citizen is Dictionary:
				break

			var citizen: Dictionary = raw_citizen
			var citizen_id := int(
				citizen.get("id", -1)
			)

			if citizen_id < 0:
				break

			if not assign_city_citizen_job(
				citizen_id,
				workplace_id
			):
				push_error(
					"Failed to assign unemployed citizen "
					+ str(citizen_id)
					+ " to workplace "
					+ str(workplace_id)
				)

				break

			assigned_count += 1

	return assigned_count

static func get_first_homeless_city_citizen_index() -> int:

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

	var assigned_count := 0

	for object_index in range(CityObjectSystem.get_city_objects().size()):
		var raw_city_object = CityObjectSystem.get_city_objects()[object_index]

		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object
		var house_id := int(city_object.get("id", -1))

		if house_id < 0:
			continue

		var resident_capacity := (
			get_city_object_resident_capacity(city_object)
		)

		if resident_capacity <= 0:
			continue

		while true:
			var current_house := CityObjectSystem.get_city_object_by_id(
				house_id
			)

			if current_house.is_empty():
				break

			if (
				get_city_object_resident_count(current_house)
				>= resident_capacity
			):
				break

			var homeless_citizen_index := (
				get_first_homeless_city_citizen_index()
			)

			if homeless_citizen_index < 0:
				break

			var raw_citizen = city_citizens[
				homeless_citizen_index
			]

			if not raw_citizen is Dictionary:
				break

			var citizen: Dictionary = raw_citizen
			var citizen_id := int(
				citizen.get("id", -1)
			)

			if citizen_id < 0:
				break

			if not assign_city_citizen_home(
				citizen_id,
				house_id
			):
				push_error(
					"Failed to assign homeless citizen "
					+ str(citizen_id)
					+ " to housing object "
					+ str(house_id)
				)

				break

			assigned_count += 1

	return assigned_count

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
	city_object_access_tile_cache.clear()
	CityObjectSystem.reset_city_object_state()
	_mark_city_workplaces_changed()

	CityResourceAccountingSystem.reset_city_resource_accounting_state()

	# Houses and workplaces no longer exist, so assignment observers must
	# invalidate any relationship displays.
	_mark_city_assignments_changed()
	reset_city_citizen_state()

#endregion

#region City Object Placement and Traversal

static func get_living_city_citizen_ids_in_tiles(
	raw_tiles: Array
) -> Array[int]:
	var tile_lookup: Dictionary = {}

	for raw_tile in raw_tiles:
		if raw_tile is Vector2i:
			tile_lookup[raw_tile] = true

	var citizen_ids: Array[int] = []

	for raw_citizen in city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if not bool(citizen.get("alive", false)):
			continue

		var raw_tile = citizen.get(
			"city_tile_position",
			INVALID_CITY_TILE_POSITION
		)

		if not raw_tile is Vector2i or not tile_lookup.has(raw_tile):
			continue

		var citizen_id := int(citizen.get("id", -1))

		if citizen_id > 0:
			citizen_ids.append(citizen_id)

	citizen_ids.sort()
	return citizen_ids


static func city_citizen_can_access_object_interior(
	citizen_id: int,
	city_object: Dictionary
) -> bool:
	if (
		citizen_id <= 0
		or city_object.is_empty()
		or not CityObjectSystem.city_object_supports_citizen_interior(city_object)
	):
		return false

	var citizen := get_city_citizen_by_id(citizen_id)

	if (
		citizen.is_empty()
		or not bool(citizen.get("alive", false))
	):
		return false

	var object_id := int(city_object.get("id", -1))

	if object_id <= 0:
		return false

	var access_mode := (
		CityObjectSystem.get_city_object_citizen_interior_access_mode(
			city_object
		)
	)

	match access_mode:
		CITY_OBJECT_INTERIOR_ACCESS_RESIDENTS:
			return (
				int(citizen.get("home_object_id", -1))
				== object_id
				and get_city_object_resident_ids(
					city_object
				).has(citizen_id)
			)

		CITY_OBJECT_INTERIOR_ACCESS_ASSIGNED_WORKERS:
			return (
				int(citizen.get("job_object_id", -1))
				== object_id
				and get_city_object_worker_ids(
					city_object
				).has(citizen_id)
			)

		CITY_OBJECT_INTERIOR_ACCESS_TASK_TARGET:
			var current_task := get_city_citizen_current_task(
				citizen_id
			)
			var task_kind := str(
				current_task.get(
					"kind",
					CITY_CITIZEN_TASK_KIND_NONE
				)
			)

			# A ground-pile ID lives in a separate namespace and can equal an
			# unrelated city-object ID. For hauling, authorize only city-object
			# endpoints instead of treating the legacy numeric task target as an
			# object reference.
			if task_kind == CITY_CITIZEN_TASK_KIND_HAUL:
				var haul := get_city_citizen_current_haul(citizen_id)

				for endpoint_field in ["source", "destination"]:
					var raw_endpoint = haul.get(endpoint_field, {})

					if not raw_endpoint is Dictionary:
						continue

					var endpoint: Dictionary = raw_endpoint

					if (
						str(
							endpoint.get(
								"kind",
								CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
							)
						)
						== CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER
						and int(endpoint.get("id", -1)) == object_id
					):
						return true

				return false

			return (
				int(current_task.get("target_object_id", -1))
				== object_id
			)

		CITY_OBJECT_INTERIOR_ACCESS_PUBLIC:
			return true

	return false


static func get_city_citizen_movement_step_cost(
	from_tile: Vector2i,
	to_tile: Vector2i
) -> int:
	var delta_x := absi(to_tile.x - from_tile.x)
	var delta_y := absi(to_tile.y - from_tile.y)

	if delta_x > 1 or delta_y > 1:
		return 0

	if delta_x == 0 and delta_y == 0:
		return 0

	var destination_is_road := CityObjectSystem.is_completed_city_road_tile(
		to_tile
	)

	if delta_x == 1 and delta_y == 1:
		if destination_is_road:
			return CITY_CITIZEN_ROAD_DIAGONAL_MOVEMENT_COST

		return CITY_CITIZEN_DIAGONAL_MOVEMENT_COST

	if destination_is_road:
		return CITY_CITIZEN_ROAD_CARDINAL_MOVEMENT_COST

	return CITY_CITIZEN_CARDINAL_MOVEMENT_COST


static func can_city_citizen_traverse_step(
	city_world: WorldData,
	from_tile: Vector2i,
	to_tile: Vector2i,
	citizen_id: int = -1
) -> bool:
	var step_cost := get_city_citizen_movement_step_cost(
		from_tile,
		to_tile
	)

	if step_cost <= 0:
		return false

	if not is_city_tile_walkable_for_citizen(
		city_world,
		to_tile,
		citizen_id
	):
		return false

	var delta_x := absi(to_tile.x - from_tile.x)
	var delta_y := absi(to_tile.y - from_tile.y)

	if delta_x == 1 and delta_y == 1:
		var horizontal_side_tile := Vector2i(
			to_tile.x,
			from_tile.y
		)
		var vertical_side_tile := Vector2i(
			from_tile.x,
			to_tile.y
		)

		if not is_city_tile_walkable_for_citizen(
			city_world,
			horizontal_side_tile,
			citizen_id
		):
			return false

		if not _city_citizen_can_cross_object_boundary(
			from_tile,
			horizontal_side_tile,
			citizen_id
		):
			return false

		if not is_city_tile_walkable_for_citizen(
			city_world,
			vertical_side_tile,
			citizen_id
		):
			return false

		if not _city_citizen_can_cross_object_boundary(
			from_tile,
			vertical_side_tile,
			citizen_id
		):
			return false

	return _city_citizen_can_cross_object_boundary(
		from_tile,
		to_tile,
		citizen_id
	)


static func _city_citizen_can_cross_object_boundary(
	from_tile: Vector2i,
	to_tile: Vector2i,
	citizen_id: int
) -> bool:
	var from_object_id := int(
		CityObjectSystem.get_city_object_id_at_tile(from_tile)
	)
	var to_object_id := int(
		CityObjectSystem.get_city_object_id_at_tile(to_tile)
	)

	if from_object_id == to_object_id:
		return true

	if from_object_id > 0:
		var from_object := CityObjectSystem.get_city_object_by_id(
			from_object_id
		)

		if (
			CityObjectSystem.city_object_supports_citizen_interior(from_object)
			and not CityObjectSystem.city_object_boundary_tile_allows_entry(
				from_object,
				from_tile
			)
		):
			return false

	if to_object_id > 0:
		var to_object := CityObjectSystem.get_city_object_by_id(to_object_id)

		if CityObjectSystem.city_object_supports_citizen_interior(to_object):
			if not city_citizen_can_access_object_interior(
				citizen_id,
				to_object
			):
				return false

			if not CityObjectSystem.city_object_boundary_tile_allows_entry(
				to_object,
				to_tile
			):
				return false

	return true

static func is_city_tile_walkable_for_citizen(
	city_world: WorldData,
	tile_position: Vector2i,
	citizen_id: int = -1
) -> bool:
	if city_world == null:
		return false

	if not city_world.is_in_bounds(
		tile_position.x,
		tile_position.y
	):
		return false

	var tile: Dictionary = city_world.get_tile(
		tile_position.x,
		tile_position.y
	)

	if str(tile.get("terrain", "")) != TERRAIN_LAND:
		return false

	if not CityObjectSystem.has_city_object_at_tile(tile_position):
		return true

	var object_id := int(
		CityObjectSystem.get_city_object_id_at_tile(tile_position)
	)
	var occupying_object := CityObjectSystem.get_city_object_by_id(object_id)

	if occupying_object.is_empty():
		return false

	if (
		str(occupying_object.get("type", ""))
		== CITY_OBJECT_ROAD
	):
		return true

	if citizen_id <= 0:
		return false

	var citizen := get_city_citizen_by_id(citizen_id)

	if (
		citizen.is_empty()
		or not bool(citizen.get("alive", false))
	):
		return false

	var current_position = citizen.get(
		"city_tile_position",
		INVALID_CITY_TILE_POSITION
	)

	# Recovery invariant: a citizen already caught inside an occupied footprint
	# may traverse that same footprint long enough to leave it. Normal topology
	# mutations are prevented from creating this state; this path exists for old
	# saves and defensive recovery only, and never authorizes re-entry.
	if (
		current_position is Vector2i
		and CityObjectSystem.get_city_object_id_at_tile(current_position)
		== object_id
	):
		return true

	if not CityObjectSystem.city_object_supports_citizen_interior(occupying_object):
		return false

	return city_citizen_can_access_object_interior(
		citizen_id,
		occupying_object
	)

static func _sort_city_tiles_y_then_x(
	tile_a: Vector2i,
	tile_b: Vector2i
) -> bool:
	if tile_a.y == tile_b.y:
		return tile_a.x < tile_b.x

	return tile_a.y < tile_b.y


static func get_city_object_access_tiles(
	city_world: WorldData,
	city_object: Dictionary
) -> Array:
	var access_tiles := []

	if city_world == null:
		return access_tiles

	if city_object.is_empty():
		return access_tiles

	var footprint_tiles := CityObjectSystem.get_city_object_footprint_tiles(
		city_object
	)
	var object_id := int(city_object.get("id", -1))
	var footprint_hash_value := int(hash(footprint_tiles))

	if object_id > 0:
		var raw_cache_entry = city_object_access_tile_cache.get(
			object_id,
			{}
		)

		if raw_cache_entry is Dictionary:
			var cache_entry: Dictionary = raw_cache_entry

			if (
				int(cache_entry.get("world_instance_id", -1))
				== int(city_world.get_instance_id())
				and int(cache_entry.get("tile_data_version", -1))
				== city_world.tile_data_version
				and int(cache_entry.get("city_object_version", -1))
				== CityObjectSystem.get_city_object_version()
				and int(cache_entry.get("footprint_hash", -1))
				== footprint_hash_value
			):
				var raw_cached_tiles = cache_entry.get(
					"access_tiles",
					[]
				)

				if raw_cached_tiles is Array:
					return raw_cached_tiles.duplicate()

	var footprint_lookup: Dictionary = {}

	for raw_footprint_tile in footprint_tiles:
		if not raw_footprint_tile is Vector2i:
			continue

		var footprint_tile: Vector2i = (
			raw_footprint_tile
		)

		footprint_lookup[footprint_tile] = true

	var access_tile_lookup: Dictionary = {}

	for raw_footprint_tile in footprint_tiles:
		if not raw_footprint_tile is Vector2i:
			continue

		var footprint_tile: Vector2i = (
			raw_footprint_tile
		)

		for offset in CITY_CARDINAL_TILE_OFFSETS:
			var candidate_tile: Vector2i = (
				footprint_tile + offset
			)

			if footprint_lookup.has(candidate_tile):
				continue

			if access_tile_lookup.has(candidate_tile):
				continue

			if not is_city_tile_walkable_for_citizen(
				city_world,
				candidate_tile
			):
				continue

			access_tile_lookup[candidate_tile] = true
			access_tiles.append(candidate_tile)

	access_tiles.sort_custom(
		_sort_city_tiles_y_then_x
	)

	if object_id > 0:
		city_object_access_tile_cache[object_id] = {
			"world_instance_id": int(
				city_world.get_instance_id()
			),
			"tile_data_version": city_world.tile_data_version,
			"city_object_version": CityObjectSystem.get_city_object_version(),
			"footprint_hash": footprint_hash_value,
			"access_tiles": access_tiles.duplicate(),
		}

	return access_tiles


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

		return get_city_object_access_tiles(
			city_world,
			city_object
		)

	return []


#endregion

#region Citizen Resource Withdrawal and Transfers


static func get_city_object_definition_from_object(city_object: Dictionary) -> Dictionary:
	if city_object.is_empty():
		return {}

	return get_city_object_definition(str(city_object.get("type", "")))


static func city_citizen_can_directly_withdraw_resource(
	citizen_id: int,
	city_object: Dictionary,
	resource: String,
	withdrawal_purpose: String
) -> bool:
	var citizen := get_city_citizen_by_id(citizen_id)

	if (
		citizen.is_empty()
		or not bool(citizen.get("alive", false))
		or city_object.is_empty()
		or not CityResourceContainerSystem.can_city_object_store_resource(city_object, resource)
		or not CityResourceContainerSystem.city_object_allows_direct_resource_withdrawal(
			city_object,
			withdrawal_purpose
		)
	):
		return false

	if (
		withdrawal_purpose
		== CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_PERSONAL_FOOD
		and WorldData.get_city_food_hunger_restore(resource) <= 0
	):
		return false

	match CityResourceContainerSystem.get_city_object_container_type(city_object):
		CONTAINER_TYPE_PRIVATE_HOME_STORAGE:
			return (
				int(citizen.get("home_object_id", -1))
				== int(city_object.get("id", -1))
				and get_city_object_resident_ids(city_object).has(citizen_id)
			)

		CONTAINER_TYPE_PUBLIC_CITY_STORAGE:
			return CityResourceContainerSystem.city_object_container_is_publicly_usable(city_object)

		CONTAINER_TYPE_WORKPLACE_STORAGE:
			return (
				withdrawal_purpose
				== CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_PERSONAL_FOOD
				and city_object_is_workplace(city_object)
				and get_city_object_output_resources(city_object).has(resource)
			)

	return false


static func get_city_citizen_direct_withdrawal_target_tiles(
	citizen_id: int,
	city_object: Dictionary,
	withdrawal_purpose: String
) -> Array:
	var target_tiles: Array = []
	var citizen := get_city_citizen_by_id(citizen_id)

	if (
		citizen.is_empty()
		or not bool(citizen.get("alive", false))
		or city_object.is_empty()
		or not CityResourceContainerSystem.city_object_allows_direct_resource_withdrawal(
			city_object,
			withdrawal_purpose
		)
	):
		return target_tiles

	match CityResourceContainerSystem.get_city_object_container_type(city_object):
		CONTAINER_TYPE_PRIVATE_HOME_STORAGE:
			if (
				int(citizen.get("home_object_id", -1))
				== int(city_object.get("id", -1))
				and get_city_object_resident_ids(city_object).has(citizen_id)
			):
				return CityObjectSystem.get_city_object_footprint_tiles(city_object)

		CONTAINER_TYPE_PUBLIC_CITY_STORAGE:
			if CityResourceContainerSystem.city_object_container_is_publicly_usable(city_object):
				return get_city_object_access_tiles(
					official_city_world,
					city_object
				)

		CONTAINER_TYPE_WORKPLACE_STORAGE:
			if (
				withdrawal_purpose
				== CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_PERSONAL_FOOD
				and city_object_is_workplace(city_object)
			):
				return get_city_object_access_tiles(
					official_city_world,
					city_object
				)

	return target_tiles


static func city_citizen_can_withdraw_food_from_endpoint(
	citizen_id: int,
	endpoint: Dictionary,
	resource: String
) -> bool:
	if WorldData.get_city_food_hunger_restore(resource) <= 0:
		return false

	var endpoint_kind := str(
		endpoint.get("kind", CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE)
	)
	var endpoint_id := int(endpoint.get("id", -1))

	match endpoint_kind:
		CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER:
			return city_citizen_can_directly_withdraw_resource(
				citizen_id,
				CityObjectSystem.get_city_object_by_id(endpoint_id),
				resource,
				CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_PERSONAL_FOOD
			)

		CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE:
			var citizen := get_city_citizen_by_id(citizen_id)
			var ground_pile := CityLogisticsSystem.get_city_ground_pile_by_id(endpoint_id)
			return (
				not citizen.is_empty()
				and bool(citizen.get("alive", false))
				and not ground_pile.is_empty()
				and not CityLogisticsSystem.city_ground_pile_is_construction_reserved(ground_pile)
				and CityLogisticsSystem.get_city_ground_pile_resource_amount(
					ground_pile,
					resource
				) > 0
			)

	return false


static func get_city_citizen_food_endpoint_target_tiles(
	citizen_id: int,
	endpoint: Dictionary
) -> Array:
	match str(
		endpoint.get("kind", CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE)
	):
		CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER:
			return get_city_citizen_direct_withdrawal_target_tiles(
				citizen_id,
				CityObjectSystem.get_city_object_by_id(int(endpoint.get("id", -1))),
				CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_PERSONAL_FOOD
			)

		CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE:
			var ground_pile := CityLogisticsSystem.get_city_ground_pile_by_id(
				int(endpoint.get("id", -1))
			)
			var raw_tile = ground_pile.get(
				"tile_position",
				INVALID_CITY_TILE_POSITION
			)

			if (
				not CityLogisticsSystem.city_ground_pile_is_construction_reserved(ground_pile)
				and raw_tile is Vector2i
				and is_city_tile_walkable_for_citizen(
					official_city_world,
					raw_tile,
					citizen_id
				)
			):
				return [raw_tile]

	return []


static func get_city_food_endpoint_unreserved_amount(
	citizen_id: int,
	endpoint: Dictionary,
	resource: String,
	excluding_citizen_id: int = -1
) -> int:
	if not city_citizen_can_withdraw_food_from_endpoint(
		citizen_id,
		endpoint,
		resource
	):
		return 0

	return CityLogisticsSystem.get_city_haul_endpoint_unreserved_resource_amount(
		endpoint,
		resource,
		INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID,
		excluding_citizen_id
	)


static func transfer_city_food_endpoint_to_citizen_inventory(
	citizen_id: int,
	endpoint: Dictionary,
	resource: String,
	requested_amount: int
) -> int:
	if (
		requested_amount <= 0
		or not city_citizen_can_withdraw_food_from_endpoint(
			citizen_id,
			endpoint,
			resource
		)
	):
		return 0

	var transfer_amount := mini(
		requested_amount,
		mini(
			CityLogisticsSystem.get_city_haul_endpoint_unreserved_resource_amount(
				endpoint,
				resource,
				INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID,
				citizen_id
			),
			get_city_citizen_inventory_free_space(citizen_id)
		)
	)

	if transfer_amount <= 0:
		return 0

	var endpoint_kind := str(
		endpoint.get("kind", CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE)
	)
	var endpoint_id := int(endpoint.get("id", -1))
	var removed_amount := 0
	var original_ground_tile := INVALID_CITY_TILE_POSITION

	if endpoint_kind == CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE:
		var original_ground_pile := CityLogisticsSystem.get_city_ground_pile_by_id(endpoint_id)
		var raw_original_ground_tile = original_ground_pile.get(
			"tile_position",
			INVALID_CITY_TILE_POSITION
		)

		if raw_original_ground_tile is Vector2i:
			original_ground_tile = raw_original_ground_tile

	match endpoint_kind:
		CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER:
			removed_amount = CityResourceContainerSystem.remove_resource_from_city_object_storage(
				endpoint_id,
				resource,
				transfer_amount
			)

		CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE:
			removed_amount = CityLogisticsSystem.remove_resource_from_city_ground_pile(
				endpoint_id,
				resource,
				transfer_amount
			)

	if removed_amount <= 0:
		return 0

	var accepted_amount := add_resource_to_city_citizen_inventory(
		citizen_id,
		resource,
		removed_amount
	)

	if accepted_amount == removed_amount:
		return accepted_amount

	if accepted_amount > 0:
		remove_resource_from_city_citizen_inventory(
			citizen_id,
			resource,
			accepted_amount
		)

	var rollback_amount := 0

	match endpoint_kind:
		CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER:
			rollback_amount = CityResourceContainerSystem.add_resource_to_city_object_storage(
				endpoint_id,
				resource,
				removed_amount
			)

		CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE:
			if original_ground_tile != INVALID_CITY_TILE_POSITION:
				rollback_amount = int(
					CityLogisticsSystem.add_resource_to_city_ground_piles_with_result({
						"tile_position": original_ground_tile,
						"resource": resource,
						"amount_delta": removed_amount,
					}).get("added_amount", 0)
				)

	if rollback_amount != removed_amount:
		push_error(
			"Atomic food-endpoint transfer rollback failed for "
			+ resource
			+ "."
		)

	return 0


static func transfer_city_object_resource_to_citizen_inventory(
	values: Dictionary
) -> int:
	var citizen_id := int(values.get("citizen_id", -1))
	var object_id := int(values.get("object_id", -1))
	var resource := str(values.get("resource", RESOURCE_NONE))
	var requested_amount := int(values.get("requested_amount", 0))
	var withdrawal_purpose := str(
		values.get("withdrawal_purpose", CONTAINER_HAUL_PURPOSE_NONE)
	)
	var excluding_food_task_citizen_id := int(
		values.get("excluding_food_task_citizen_id", -1)
	)
	if requested_amount <= 0:
		return 0

	var city_object := CityObjectSystem.get_city_object_by_id(object_id)

	if not city_citizen_can_directly_withdraw_resource(
		citizen_id,
		city_object,
		resource,
		withdrawal_purpose
	):
		return 0

	var source_endpoint := CityLogisticsSystem.make_city_citizen_haul_endpoint(object_id)
	var available_amount := CityLogisticsSystem.get_city_haul_endpoint_unreserved_resource_amount(
		source_endpoint,
		resource,
		INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID,
		excluding_food_task_citizen_id
	)
	var transfer_amount := mini(
		requested_amount,
		mini(
			available_amount,
			get_city_citizen_inventory_free_space(citizen_id)
		)
	)

	if transfer_amount <= 0:
		return 0

	var removed_amount := CityResourceContainerSystem.remove_resource_from_city_object_storage(
		object_id,
		resource,
		transfer_amount
	)

	if removed_amount <= 0:
		return 0

	var accepted_amount := add_resource_to_city_citizen_inventory(
		citizen_id,
		resource,
		removed_amount
	)

	if accepted_amount == removed_amount:
		return accepted_amount

	if accepted_amount > 0:
		remove_resource_from_city_citizen_inventory(
			citizen_id,
			resource,
			accepted_amount
		)

	var rollback_amount := CityResourceContainerSystem.add_resource_to_city_object_storage(
		object_id,
		resource,
		removed_amount
	)

	if rollback_amount != removed_amount:
		push_error(
			"Atomic personal-inventory transfer rollback failed for "
			+ resource
			+ "."
		)

	return 0

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

#region Citizen Assignment Mutation

static func get_city_object_worker_names(city_object: Dictionary) -> Array:
	var worker_names := []
	var worker_ids := get_city_object_worker_ids(city_object)

	for worker_id in worker_ids:
		worker_names.append(get_city_citizen_display_name(int(worker_id)))

	return worker_names

static func _get_clean_city_object_assignment_ids(
	city_object: Dictionary,
	object_id: int,
	object_id_list_field: String,
	citizen_object_id_field: String
) -> Array:
	var clean_assignment_ids: Array = []

	if city_object.is_empty():
		return clean_assignment_ids

	var raw_assignment_ids = city_object.get(
		object_id_list_field,
		[]
	)

	if not raw_assignment_ids is Array:
		return clean_assignment_ids

	for raw_citizen_id in raw_assignment_ids:
		var citizen_id := int(raw_citizen_id)

		if citizen_id < 0:
			continue

		if clean_assignment_ids.has(citizen_id):
			continue

		var citizen_index := get_city_citizen_index_by_id(
			citizen_id
		)

		if citizen_index < 0:
			continue

		var raw_citizen = city_citizens[citizen_index]

		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if not bool(citizen.get("alive", true)):
			continue

		if (
			int(citizen.get(citizen_object_id_field, -1))
			!= object_id
		):
			continue

		clean_assignment_ids.append(citizen_id)

	return clean_assignment_ids


static func _write_city_object_assignment_ids(
	object_index: int,
	object_id_list_field: String,
	assignment_ids: Array
) -> bool:
	if object_index < 0 or object_index >= CityObjectSystem.get_city_objects().size():
		return false

	var raw_city_object = CityObjectSystem.get_city_objects()[object_index]

	if not raw_city_object is Dictionary:
		return false

	var city_object: Dictionary = raw_city_object
	var existing_assignment_ids = city_object.get(
		object_id_list_field,
		[]
	)

	if (
		existing_assignment_ids is Array
		and existing_assignment_ids == assignment_ids
	):
		return false

	city_object[object_id_list_field] = assignment_ids.duplicate()
	return CityObjectSystem.write_city_object_at_index(
		object_index,
		city_object
	)


static func _remove_citizen_from_city_object_assignment(
	object_id: int,
	citizen_id: int,
	object_id_list_field: String,
	citizen_object_id_field: String
) -> bool:
	var object_index := CityObjectSystem.get_city_object_index_by_id(object_id)

	if object_index < 0:
		return false

	var raw_city_object = CityObjectSystem.get_city_objects()[object_index]

	if not raw_city_object is Dictionary:
		return false

	var city_object: Dictionary = raw_city_object
	var assignment_ids := _get_clean_city_object_assignment_ids(
		city_object,
		object_id,
		object_id_list_field,
		citizen_object_id_field
	)

	var removed_citizen := false

	while assignment_ids.has(citizen_id):
		assignment_ids.erase(citizen_id)
		removed_citizen = true

	var assignment_list_changed := (
		_write_city_object_assignment_ids(
			object_index,
			object_id_list_field,
			assignment_ids
		)
	)

	return removed_citizen or assignment_list_changed

static func assign_city_citizen_home(
	citizen_id: int,
	house_id: int
) -> bool:

	var citizen_index := get_city_citizen_index_by_id(citizen_id)

	if citizen_index < 0:
		return false

	var raw_citizen = city_citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return false

	var citizen: Dictionary = raw_citizen

	if not bool(citizen.get("alive", true)):
		return false

	var house_index := CityObjectSystem.get_city_object_index_by_id(house_id)

	if house_index < 0:
		return false

	var raw_house = CityObjectSystem.get_city_objects()[house_index]

	if not raw_house is Dictionary:
		return false

	var house: Dictionary = raw_house
	var resident_capacity := get_city_object_resident_capacity(
		house
	)

	if resident_capacity <= 0:
		return false

	var resident_ids := _get_clean_city_object_assignment_ids(
		house,
		house_id,
		"resident_ids",
		"home_object_id"
	)

	var current_home_id := int(
		citizen.get("home_object_id", -1)
	)

	if current_home_id == house_id:
		var assignment_changed := false

		if not resident_ids.has(citizen_id):
			if resident_ids.size() >= resident_capacity:
				push_error(
					"Citizen "
					+ str(citizen_id)
					+ " points to full House "
					+ str(house_id)
					+ " but is missing from its resident list."
				)

				return false

			resident_ids.append(citizen_id)
			assignment_changed = true

		if _write_city_object_assignment_ids(
			house_index,
			"resident_ids",
			resident_ids
		):
			assignment_changed = true

		if assignment_changed:
			_mark_city_assignments_changed()

		return true

	if resident_ids.size() >= resident_capacity:
		return false

	var assignment_changed := false

	if current_home_id >= 0:
		if _remove_citizen_from_city_object_assignment(
			current_home_id,
			citizen_id,
			"resident_ids",
			"home_object_id"
		):
			assignment_changed = true

	citizen["home_object_id"] = house_id
	city_citizens[citizen_index] = citizen
	assignment_changed = true
	_clear_city_citizen_return_home_task_after_home_change(
		citizen_id
	)

	resident_ids.append(citizen_id)

	if _write_city_object_assignment_ids(
		house_index,
		"resident_ids",
		resident_ids
	):
		assignment_changed = true

	if assignment_changed:
		_mark_city_assignments_changed()

	return true


static func remove_city_citizen_home(citizen_id: int) -> bool:
	var citizen_index := get_city_citizen_index_by_id(citizen_id)

	if citizen_index < 0:
		return false

	var raw_citizen = city_citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return false

	var citizen: Dictionary = raw_citizen
	var current_home_id := int(
		citizen.get("home_object_id", -1)
	)

	if current_home_id < 0:
		return false

	_remove_citizen_from_city_object_assignment(
		current_home_id,
		citizen_id,
		"resident_ids",
		"home_object_id"
	)

	citizen["home_object_id"] = -1
	city_citizens[citizen_index] = citizen
	_clear_city_citizen_return_home_task_after_home_change(
		citizen_id
	)

	_mark_city_assignments_changed()

	return true


static func _clear_city_citizen_return_home_task_after_home_change(
	citizen_id: int
) -> void:
	var current_task := get_city_citizen_current_task(
		citizen_id
	)

	if (
		str(current_task.get("kind", ""))
		!= CITY_CITIZEN_TASK_KIND_RETURN_HOME
	):
		return

	clear_city_citizen_task(
		citizen_id,
		CITY_CITIZEN_TASK_SOURCE_PLAYER
	)
	cancel_city_citizen_movement(citizen_id)


static func _clear_city_citizen_work_task_after_job_change(
	citizen_id: int
) -> void:
	var current_task := get_city_citizen_current_task(
		citizen_id
	)

	if (
		str(current_task.get("kind", ""))
		!= CITY_CITIZEN_TASK_KIND_WORK
	):
		return

	clear_city_citizen_task(
		citizen_id,
		CITY_CITIZEN_TASK_SOURCE_PLAYER
	)
	cancel_city_citizen_movement(citizen_id)

static func assign_city_citizen_job(
	citizen_id: int,
	workplace_id: int
) -> bool:

	var citizen_index := get_city_citizen_index_by_id(citizen_id)

	if citizen_index < 0:
		return false

	var raw_citizen = city_citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return false

	var citizen: Dictionary = raw_citizen

	if not bool(citizen.get("alive", true)):
		return false

	var workplace_index := CityObjectSystem.get_city_object_index_by_id(
		workplace_id
	)

	if workplace_index < 0:
		return false

	var raw_workplace = CityObjectSystem.get_city_objects()[workplace_index]

	if not raw_workplace is Dictionary:
		return false

	var workplace: Dictionary = raw_workplace

	if not city_object_is_workplace(workplace):
		return false

	var worker_capacity := get_city_object_worker_capacity(
		workplace
	)

	if worker_capacity <= 0:
		return false

	var worker_ids := _get_clean_city_object_assignment_ids(
		workplace,
		workplace_id,
		"assigned_worker_ids",
		"job_object_id"
	)

	var current_job_id := int(
		citizen.get("job_object_id", -1)
	)

	if current_job_id == workplace_id:
		var assignment_changed := false

		if not worker_ids.has(citizen_id):
			if worker_ids.size() >= worker_capacity:
				push_error(
					"Citizen "
					+ str(citizen_id)
					+ " points to full workplace "
					+ str(workplace_id)
					+ " but is missing from its worker list."
				)

				return false

			worker_ids.append(citizen_id)
			assignment_changed = true

		if _write_city_object_assignment_ids(
			workplace_index,
			"assigned_worker_ids",
			worker_ids
		):
			assignment_changed = true

		if assignment_changed:
			_mark_city_assignments_changed()
			_clear_city_citizen_work_task_after_job_change(
				citizen_id
			)

		return true

	if worker_ids.size() >= worker_capacity:
		return false

	# Validate the requested workplace before interrupting an unemployed
	# citizen's autonomous action. A rejected full-workplace assignment must
	# not make them drop cargo or abandon a valid haul.
	if (
		current_job_id < 0
		and not (
			CitizenTaskSystem
			.prepare_unemployed_citizen_for_priority_interrupt(citizen_id)
		)
	):
		return false

	if current_job_id < 0:
		citizen = get_city_citizen_by_id(citizen_id)

		if citizen.is_empty():
			return false

	var assignment_changed := false

	if current_job_id >= 0:
		if _remove_citizen_from_city_object_assignment(
			current_job_id,
			citizen_id,
			"assigned_worker_ids",
			"job_object_id"
		):
			assignment_changed = true

	citizen["job_object_id"] = workplace_id
	city_citizens[citizen_index] = citizen
	assignment_changed = true

	worker_ids.append(citizen_id)

	if _write_city_object_assignment_ids(
		workplace_index,
		"assigned_worker_ids",
		worker_ids
	):
		assignment_changed = true

	if assignment_changed:
		_mark_city_assignments_changed()

	return true


static func remove_city_citizen_job(citizen_id: int) -> bool:
	var citizen_index := get_city_citizen_index_by_id(citizen_id)

	if citizen_index < 0:
		return false

	var raw_citizen = city_citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return false

	var citizen: Dictionary = raw_citizen
	var current_job_id := int(
		citizen.get("job_object_id", -1)
	)

	if current_job_id < 0:
		return false

	_remove_citizen_from_city_object_assignment(
		current_job_id,
		citizen_id,
		"assigned_worker_ids",
		"job_object_id"
	)

	citizen["job_object_id"] = -1
	city_citizens[citizen_index] = citizen

	_mark_city_assignments_changed()
	_clear_city_citizen_work_task_after_job_change(
		citizen_id
	)

	return true

#endregion
