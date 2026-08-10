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
var assignment_state: CityAssignmentState = CityAssignmentState.new()
var workplace_state: CityWorkplaceState = CityWorkplaceState.new()
var citizen_spatial_state: CityCitizenSpatialState = (
	CityCitizenSpatialState.new()
)
var citizen_movement_runtime_state: CityCitizenMovementRuntimeState = (
	CityCitizenMovementRuntimeState.new()
)
var citizen_task_runtime_state: CityCitizenTaskRuntimeState = (
	CityCitizenTaskRuntimeState.new()
)
var work_state: CityWorkState = CityWorkState.new()
var logistics_state: CityLogisticsState = CityLogisticsState.new()
var construction_state: CityConstructionState = CityConstructionState.new()

var object_access_tile_cache: Dictionary = {}


func capture_from_world_data() -> void:
	city_world = WorldData.official_city_world
	city_seed = WorldData.official_city_seed
	city_runtime_data = WorldData.player_city_data

	object_access_tile_cache = WorldData.city_object_access_tile_cache



func apply_to_world_data() -> void:
	WorldData.official_city_world = city_world
	WorldData.official_city_seed = city_seed
	WorldData.player_city_data = city_runtime_data

	WorldData.city_object_access_tile_cache = object_access_tile_cache



func is_bound_to_world_data_workspace() -> bool:
	return is_same(
		WorldData.player_city_data,
		city_runtime_data
	)
