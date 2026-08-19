extends RefCounted
class_name CityCitizenUnboundCompatibility

# Transitional bootstrap and low-level compatibility only. Production citizen
# simulation receives a real CitySettlementSimulationState or one of its exact
# subordinate owners from an explicit settlement context.
#
# This view never resolves the active/presented settlement. Before the political
# registry exists it exposes the pre-registry unbound owners. After foundation
# it targets the fixed player-capital owner. A legacy one-city fixture may also
# use its sole registered city because that owner is unambiguous and cannot be
# redirected by presentation selection. Multi-city legacy tests may bind one
# exact CitySettlementSimulationState explicitly; presentation selection still
# has no authority over citizen gameplay state. PR 9 will retire this
# compatibility backend altogether.

static var _explicit_legacy_fixture_state: CitySettlementSimulationState = null


static func bind_legacy_fixture_state(
	city_state: CitySettlementSimulationState
) -> void:
	_explicit_legacy_fixture_state = city_state


static func clear_legacy_fixture_state() -> void:
	_explicit_legacy_fixture_state = null


static func get_city_state() -> CitySettlementSimulationState:
	if _explicit_legacy_fixture_state != null:
		return _explicit_legacy_fixture_state

	var capital_state = WorldPoliticalState.get_player_capital_city_simulation_state()
	if capital_state is CitySettlementSimulationState:
		return capital_state

	var only_registered_state := _get_only_registered_city_state()
	if only_registered_state != null:
		return only_registered_state

	var city_state := CitySettlementSimulationState.new()
	city_state.city_world = WorldPoliticalState._unbound_city_world
	city_state.city_seed = WorldPoliticalState._unbound_city_seed
	city_state.city_runtime_data = WorldPoliticalState._unbound_city_runtime_data
	city_state.object_state = WorldPoliticalState._unbound_city_object_state
	city_state.resource_accounting_state = (
		WorldPoliticalState._unbound_city_resource_accounting_state
	)
	city_state.citizen_registry_state = (
		WorldPoliticalState._unbound_city_citizen_registry_state
	)
	city_state.assignment_state = WorldPoliticalState._unbound_city_assignment_state
	city_state.workplace_state = WorldPoliticalState._unbound_city_workplace_state
	city_state.citizen_spatial_state = (
		WorldPoliticalState._unbound_city_citizen_spatial_state
	)
	city_state.citizen_movement_runtime_state = (
		WorldPoliticalState._unbound_city_citizen_movement_runtime_state
	)
	city_state.citizen_task_runtime_state = (
		WorldPoliticalState._unbound_city_citizen_task_runtime_state
	)
	city_state.citizen_decision_runtime_state = (
		WorldPoliticalState._unbound_city_citizen_decision_runtime_state
	)
	city_state.work_state = WorldPoliticalState._unbound_city_work_state
	city_state.logistics_state = WorldPoliticalState._unbound_city_logistics_state
	city_state.construction_state = (
		WorldPoliticalState._unbound_city_construction_state
	)
	city_state.navigation_state = WorldPoliticalState._unbound_city_navigation_state
	return city_state


static func _get_only_registered_city_state() -> CitySettlementSimulationState:
	var only_state: CitySettlementSimulationState = null
	for raw_state in WorldPoliticalState.settlement_city_state_by_id.values():
		if not raw_state is CitySettlementSimulationState:
			continue
		if only_state != null:
			return null
		only_state = raw_state
	return only_state
