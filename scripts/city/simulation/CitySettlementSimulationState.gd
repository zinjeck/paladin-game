extends RefCounted
class_name CitySettlementSimulationState

# Instance-owned mutable state for one CITY settlement.
#
# WorldData still exposes historical compatibility fields while the remaining
# city systems are migrated, but extracted subsystems are not captured into or
# restored from that workspace anymore.
#
# Do not add world/polity identity here. SettlementData and PolityData own that
# information. This class is only local city-simulation state.

var city_world = null
var city_seed: int = 0
var city_runtime_data: Dictionary = {}

# Physically extracted settlement-local subsystems. Their state is selected by
# settlement identity rather than copied through the legacy WorldData workspace.
var object_state: CityObjectState = CityObjectState.new()
var resource_accounting_state: CityResourceAccountingState = (
	CityResourceAccountingState.new()
)
var citizen_registry_state: CityCitizenRegistryState = (
	CityCitizenRegistryState.new()
)
var work_state: CityWorkState = CityWorkState.new()
var logistics_state: CityLogisticsState = CityLogisticsState.new()
var construction_state: CityConstructionState = CityConstructionState.new()

var citizen_ids_by_tile: Dictionary = {}
var active_mover_ids: Array[int] = []
var active_mover_id_lookup: Dictionary = {}
var citizen_movement_visual_events: Array = []
var citizen_movement_visual_tick_index: int = -1
var active_task_ids: Array[int] = []
var active_task_id_lookup: Dictionary = {}
var object_access_tile_cache: Dictionary = {}

var citizen_spatial_version: int = 0
var citizen_movement_version: int = 0
var citizen_task_version: int = 0
var assignment_version: int = 0
var workplace_version: int = 0


func capture_from_world_data() -> void:
	city_world = WorldData.official_city_world
	city_seed = WorldData.official_city_seed
	city_runtime_data = WorldData.player_city_data

	citizen_ids_by_tile = WorldData.city_citizen_ids_by_tile
	active_mover_ids = WorldData.city_active_mover_ids
	active_mover_id_lookup = WorldData.city_active_mover_id_lookup
	citizen_movement_visual_events = WorldData.city_citizen_movement_visual_events
	citizen_movement_visual_tick_index = (
		WorldData.city_citizen_movement_visual_tick_index
	)
	active_task_ids = WorldData.city_active_task_ids
	active_task_id_lookup = WorldData.city_active_task_id_lookup
	object_access_tile_cache = WorldData.city_object_access_tile_cache

	citizen_spatial_version = WorldData.city_citizen_spatial_version
	citizen_movement_version = WorldData.city_citizen_movement_version
	citizen_task_version = WorldData.city_citizen_task_version
	assignment_version = WorldData.city_assignment_version
	workplace_version = WorldData.city_workplace_version


func apply_to_world_data() -> void:
	WorldData.official_city_world = city_world
	WorldData.official_city_seed = city_seed
	WorldData.player_city_data = city_runtime_data

	WorldData.city_citizen_ids_by_tile = citizen_ids_by_tile
	WorldData.city_active_mover_ids = active_mover_ids
	WorldData.city_active_mover_id_lookup = active_mover_id_lookup
	WorldData.city_citizen_movement_visual_events = citizen_movement_visual_events
	WorldData.city_citizen_movement_visual_tick_index = (
		citizen_movement_visual_tick_index
	)
	WorldData.city_active_task_ids = active_task_ids
	WorldData.city_active_task_id_lookup = active_task_id_lookup
	WorldData.city_object_access_tile_cache = object_access_tile_cache

	WorldData.city_citizen_spatial_version = citizen_spatial_version
	WorldData.city_citizen_movement_version = citizen_movement_version
	WorldData.city_citizen_task_version = citizen_task_version
	WorldData.city_assignment_version = assignment_version
	WorldData.city_workplace_version = workplace_version


func is_bound_to_world_data_workspace() -> bool:
	return is_same(
		WorldData.city_citizen_ids_by_tile,
		citizen_ids_by_tile
	)
