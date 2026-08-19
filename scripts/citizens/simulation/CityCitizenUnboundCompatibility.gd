extends RefCounted
class_name CityCitizenUnboundCompatibility

# Legacy bootstrap and low-level test compatibility only. Production citizen
# simulation receives a real CitySettlementSimulationState or one of its exact
# subordinate owners from an explicit settlement context.
#
# This view never resolves the active/presented settlement. It only re-exposes
# WorldPoliticalState's pre-registry unbound owners until PR 9 retires that
# compatibility backend altogether. A fresh aggregate is built on every call
# because reset_state() replaces the unbound owner objects.


static func get_city_state() -> CitySettlementSimulationState:
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
