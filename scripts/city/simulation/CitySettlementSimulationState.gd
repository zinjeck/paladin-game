extends RefCounted
class_name CitySettlementSimulationState

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
var work_state: CityWorkState = CityWorkState.new()
var logistics_state: CityLogisticsState = CityLogisticsState.new()
var construction_state: CityConstructionState = CityConstructionState.new()
var navigation_state: CityNavigationState = CityNavigationState.new()


