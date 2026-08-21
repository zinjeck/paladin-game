extends Node

var failure_count: int = 0


func _ready() -> void:
	_test_registered_city_backend_contract()
	_test_stale_context_rejects_without_mutation()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error("Legacy city backend removal test failed: " + str(failure_count))
		get_tree().quit(1)
		return

	print("Legacy city backend removal test passed.")
	get_tree().quit(0)


func _test_registered_city_backend_contract() -> void:
	WorldData.reset_runtime_session_state()
	var fixture := _make_two_city_fixture("Registered Backend")
	if fixture.is_empty():
		_expect(false, "Two registered City contexts must be created.")
		return

	var city_a_id: int = fixture["city_a_id"]
	var city_b_id: int = fixture["city_b_id"]
	var context_a: SettlementSimulationContext = fixture["context_a"]
	var context_b: SettlementSimulationContext = fixture["context_b"]
	var state_a: CitySettlementSimulationState = context_a.get_city_simulation_state()
	var state_b: CitySettlementSimulationState = context_b.get_city_simulation_state()
	state_a.city_runtime_data["marker"] = "A"
	state_b.city_runtime_data["marker"] = "B"

	_expect(
		WorldPoliticalState.is_registered_settlement_context(context_a)
		and WorldPoliticalState.is_registered_settlement_context(context_b)
		and not is_same(context_a, context_b)
		and not is_same(state_a, state_b),
		"Every City must have a distinct registered context and state owner."
	)
	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id),
		"City B must be selectable for presentation."
	)
	_expect(
		WorldPoliticalState.active_settlement_id == city_b_id
		and WorldPoliticalState.get_city_simulation_state(city_a_id) == state_a
		and WorldPoliticalState.get_city_simulation_state(city_b_id) == state_b
		and state_a.city_runtime_data.get("marker") == "A"
		and state_b.city_runtime_data.get("marker") == "B",
		"Presentation selection must not choose or copy either gameplay owner."
	)

	state_a.city_runtime_data["local_only"] = 1
	_expect(
		WorldPoliticalState.active_settlement_id == city_b_id
		and not state_b.city_runtime_data.has("local_only"),
		"Mutating explicit City A must not touch presented City B."
	)
	_expect(
		WorldPoliticalState.set_active_settlement(city_a_id)
		and WorldPoliticalState.set_active_settlement(city_b_id)
		and state_a.city_runtime_data.get("local_only") == 1
		and state_b.city_runtime_data.get("marker") == "B",
		"A/B presentation changes must preserve both explicit owners."
	)


func _test_stale_context_rejects_without_mutation() -> void:
	WorldData.reset_runtime_session_state()
	var fixture := _make_two_city_fixture("Stale Context")
	if fixture.is_empty():
		_expect(false, "The stale-context fixture must be created.")
		return

	var stale_context: SettlementSimulationContext = fixture["context_a"]
	var stale_state: CitySettlementSimulationState = (
		stale_context.get_city_simulation_state()
	)
	stale_state.city_runtime_data["marker"] = "must_survive"
	var owner_identities := _capture_owner_identities(stale_state)
	var values_before := _capture_all_state_values(stale_state)

	WorldData.reset_runtime_session_state()
	var result := CitySettlementRuntimeBootstrap.ensure_ready(stale_context)
	SimulationCoordinator.run_settlement_simulation_systems(
		stale_context,
		1,
		15
	)
	_expect(
		not WorldPoliticalState.is_registered_settlement_context(stale_context)
		and not bool(result.get("success", false))
		and str(result.get("failure_code", ""))
		== CitySettlementRuntimeBootstrap.FAILURE_UNREGISTERED_CONTEXT,
		"A context captured before registry reset must be rejected as stale."
	)
	_expect(
		_owner_identities_match(stale_state, owner_identities)
		and _capture_all_state_values(stale_state) == values_before,
		"Bootstrap and simulation boundaries must reject a stale context without mutating its detached gameplay owners."
	)


func _make_two_city_fixture(label: String) -> Dictionary:
	var culture := WorldData.create_culture(label + " Culture")
	var culture_id := int(culture.get("id", -1))
	var polity := WorldPoliticalState.create_polity({
		"name": label + " Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var polity_id := int(polity.get("id", -1))
	var city_a := _create_city(label + " A", polity_id, Vector2i(1, 1))
	var city_b := _create_city(label + " B", polity_id, Vector2i(2, 2))
	var city_a_id := int(city_a.get("id", -1))
	var city_b_id := int(city_b.get("id", -1))
	var context_a: SettlementSimulationContext = (
		WorldPoliticalState.get_settlement_context(city_a_id)
	)
	var context_b: SettlementSimulationContext = (
		WorldPoliticalState.get_settlement_context(city_b_id)
	)
	if (
		culture_id <= 0
		or polity_id <= 0
		or context_a == null
		or context_b == null
	):
		return {}
	return {
		"city_a_id": city_a_id,
		"city_b_id": city_b_id,
		"context_a": context_a,
		"context_b": context_b,
	}


func _create_city(name: String, polity_id: int, tile: Vector2i) -> Dictionary:
	return WorldPoliticalState.create_settlement({
		"name": name,
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": polity_id,
		"world_region_top_left": tile,
		"world_region_center": tile,
		"world_region_size": 1,
		"simulation_backend_kind": (
			SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
		),
	})


func _get_owner_map(state: CitySettlementSimulationState) -> Dictionary:
	return {
		"object_state": state.object_state,
		"resource_accounting_state": state.resource_accounting_state,
		"citizen_registry_state": state.citizen_registry_state,
		"assignment_state": state.assignment_state,
		"workplace_state": state.workplace_state,
		"citizen_spatial_state": state.citizen_spatial_state,
		"citizen_movement_runtime_state": (
			state.citizen_movement_runtime_state
		),
		"citizen_task_runtime_state": state.citizen_task_runtime_state,
		"citizen_decision_runtime_state": (
			state.citizen_decision_runtime_state
		),
		"work_state": state.work_state,
		"logistics_state": state.logistics_state,
		"construction_state": state.construction_state,
		"navigation_state": state.navigation_state,
	}


func _capture_owner_identities(
	state: CitySettlementSimulationState
) -> Dictionary:
	var identities := {
		"world": state.city_world,
		"runtime": state.city_runtime_data,
	}
	identities.merge(_get_owner_map(state))
	return identities


func _owner_identities_match(
	state: CitySettlementSimulationState,
	identities: Dictionary
) -> bool:
	if (
		not is_same(state.city_world, identities.get("world"))
		or not is_same(state.city_runtime_data, identities.get("runtime"))
	):
		return false
	var owners := _get_owner_map(state)
	for owner_key in owners.keys():
		if not is_same(
			owners[owner_key],
			identities.get(owner_key)
		):
			return false
	return true


func _capture_all_state_values(
	state: CitySettlementSimulationState
) -> Dictionary:
	var owner_values := {}
	var owners := _get_owner_map(state)
	for owner_key in owners.keys():
		owner_values[owner_key] = _capture_script_variable_values(
			owners[owner_key]
		)
	return {
		"city_seed": state.city_seed,
		"runtime": state.city_runtime_data.duplicate(true),
		"world": _capture_script_variable_values(state.city_world),
		"owners": owner_values,
	}


func _capture_script_variable_values(owner) -> Dictionary:
	if owner == null or not owner.has_method("get_property_list"):
		return {}
	var values := {}
	for property in owner.get_property_list():
		var usage := int(property.get("usage", 0))
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var property_name := str(property.get("name", ""))
		if property_name.is_empty():
			continue
		var value = owner.get(property_name)
		if value is Dictionary:
			values[property_name] = value.duplicate(true)
		elif value is Array:
			values[property_name] = value.duplicate(true)
		else:
			values[property_name] = value
	return values


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error("Legacy city backend removal test: " + message)
