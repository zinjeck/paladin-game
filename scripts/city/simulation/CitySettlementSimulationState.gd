extends RefCounted
class_name CitySettlementSimulationState

const CityCitizenDecisionRuntimeStateScript = preload(
	"res://scripts/city/simulation/CityCitizenDecisionRuntimeState.gd"
)

# Instance-owned mutable state for one CITY settlement.
#
# City runtime identity and mutable simulation state live directly on this
# settlement owner. No state is copied through WorldData when settlements switch.
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
var citizen_decision_runtime_state: CityCitizenDecisionRuntimeStateScript = (
	CityCitizenDecisionRuntimeStateScript.new()
)
var work_state: CityWorkState = CityWorkState.new()
var logistics_state: CityLogisticsState = CityLogisticsState.new()
var construction_state: CityConstructionState = CityConstructionState.new()
var navigation_state: CityNavigationState = CityNavigationState.new()


# Settlement-local gameplay facts remain in the existing runtime record so
# founding has one authority. These typed readers keep simulation and
# presentation code from falling back to the global player-capital mirrors.
func is_city_founded() -> bool:
	return bool(city_runtime_data.get("founded", false))


func can_build_city_objects() -> bool:
	return (
		is_city_founded()
		and bool(city_runtime_data.get("can_build", false))
	)


func get_primary_culture_id() -> int:
	var raw_culture_id = city_runtime_data.get("primary_culture_id", -1)
	return int(raw_culture_id) if raw_culture_id is int else -1


func has_city_foundation_footprint() -> bool:
	var top_left = city_runtime_data.get(
		"foundation_top_left",
		Vector2i(-1, -1)
	)
	var size_tiles = city_runtime_data.get(
		"foundation_size",
		Vector2i.ZERO
	)
	return (
		is_city_founded()
		and top_left is Vector2i
		and size_tiles is Vector2i
		and top_left.x >= 0
		and top_left.y >= 0
		and size_tiles.x > 0
		and size_tiles.y > 0
	)
