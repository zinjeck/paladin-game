extends Node

var failure_count: int = 0


func _ready() -> void:
	_test_explicit_city_runtime_storage()
	_test_failed_bootstrap_is_atomic_and_retryable()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error("City workspace removal test failed: " + str(failure_count))
		get_tree().quit(1)
		return

	print("City workspace removal test passed.")
	get_tree().quit(0)


func _test_explicit_city_runtime_storage() -> void:
	WorldData.reset_runtime_session_state()
	var fixture := _make_two_city_fixture("Explicit Storage")
	if fixture.is_empty():
		_expect(false, "The explicit storage fixture must be created.")
		return

	var city_a_id: int = fixture["city_a_id"]
	var city_b_id: int = fixture["city_b_id"]
	var state_a: CitySettlementSimulationState = fixture["state_a"]
	var state_b: CitySettlementSimulationState = fixture["state_b"]
	var world_a := _make_world(6, 6, 12_001)
	var world_b := _make_world(7, 7, 12_002)
	state_a.city_runtime_data = {"marker": "A"}
	state_b.city_runtime_data = {"marker": "B"}

	_expect(
		WorldData.store_city_world_for_settlement(city_a_id, world_a, 12_001)
		and WorldData.store_city_world_for_settlement(
			city_b_id,
			world_b,
			12_002
		)
		and WorldPoliticalState.set_active_settlement(city_b_id),
		"Both worlds must be stored through exact settlement IDs."
	)
	var b_runtime_owner: Dictionary = state_b.city_runtime_data
	var b_object_owner: CityObjectState = state_b.object_state
	state_a.city_runtime_data["local_only"] = 1
	_expect(
		WorldPoliticalState.active_settlement_id == city_b_id
		and is_same(state_a.city_world, world_a)
		and state_a.city_seed == 12_001
		and state_a.city_runtime_data.get("local_only") == 1
		and is_same(state_b.city_world, world_b)
		and state_b.city_seed == 12_002
		and is_same(state_b.city_runtime_data, b_runtime_owner)
		and not state_b.city_runtime_data.has("local_only")
		and is_same(state_b.object_state, b_object_owner),
		"Explicit City A storage and mutation must preserve presented City B."
	)


func _test_failed_bootstrap_is_atomic_and_retryable() -> void:
	WorldData.reset_runtime_session_state()
	var fixture := _make_two_city_fixture("Bootstrap Retry")
	if fixture.is_empty():
		_expect(false, "The bootstrap retry fixture must be created.")
		return

	var city_a_id: int = fixture["city_a_id"]
	var city_b_id: int = fixture["city_b_id"]
	var context_a: SettlementSimulationContext = fixture["context_a"]
	var state_a: CitySettlementSimulationState = fixture["state_a"]
	var state_b: CitySettlementSimulationState = fixture["state_b"]
	var culture_id: int = fixture["culture_id"]
	var world_a := _make_world(8, 8, 13_001)
	var world_b := _make_world(8, 8, 13_002)
	state_a.city_world = world_a
	state_a.city_seed = 13_003
	state_a.city_runtime_data = {
		"id": city_a_id,
		"name": "Bootstrap Retry A",
		"primary_culture_id": culture_id,
		"founded": false,
		"can_build": false,
	}
	state_b.city_world = world_b
	state_b.city_seed = 13_002
	state_b.city_runtime_data = {
		"id": city_b_id,
		"name": "Bootstrap Retry B",
		"primary_culture_id": culture_id,
		"founded": false,
		"can_build": false,
	}
	WorldPoliticalState.set_active_settlement(city_b_id)

	var a_identities := _capture_owner_identities(state_a)
	var a_values := _capture_owner_values(state_a)
	var b_identities := _capture_owner_identities(state_b)
	var b_values := _capture_owner_values(state_b)
	var failed_result := CitySettlementRuntimeBootstrap.ensure_ready(context_a)
	_expect(
		not bool(failed_result.get("success", false))
		and str(failed_result.get("failure_code", ""))
		== CitySettlementRuntimeBootstrap.FAILURE_CITY_SEED_MISMATCH,
		"A mismatched explicit City seed must fail before bootstrap mutation."
	)
	_expect(
		_owner_identities_match(state_a, a_identities)
		and _capture_owner_values(state_a) == a_values
		and _owner_identities_match(state_b, b_identities)
		and _capture_owner_values(state_b) == b_values
		and WorldPoliticalState.active_settlement_id == city_b_id,
		"Failed bootstrap must preserve both owners and presentation selection."
	)

	state_a.city_seed = 13_001
	var retry_result := CitySettlementRuntimeBootstrap.ensure_ready(context_a)
	_expect(
		bool(retry_result.get("success", false))
		and WorldPoliticalState.is_registered_settlement_context(context_a)
		and WorldPoliticalState.active_settlement_id == city_b_id
		and _owner_identities_match(state_b, b_identities)
		and _capture_owner_values(state_b) == b_values,
		"Correcting the explicit owner must make retry succeed without touching B."
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
		"culture_id": culture_id,
		"city_a_id": city_a_id,
		"city_b_id": city_b_id,
		"context_a": context_a,
		"context_b": context_b,
		"state_a": context_a.get_city_simulation_state(),
		"state_b": context_b.get_city_simulation_state(),
	}


func _create_city(name: String, polity_id: int, center: Vector2i) -> Dictionary:
	return WorldPoliticalState.create_settlement({
		"name": name,
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": polity_id,
		"world_region_top_left": center,
		"world_region_center": center,
		"world_region_size": 1,
		"simulation_backend_kind": (
			SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
		),
	})


func _capture_owner_identities(
	state: CitySettlementSimulationState
) -> Dictionary:
	return {
		"runtime": state.city_runtime_data,
		"objects": state.object_state,
		"citizens": state.citizen_registry_state,
		"spatial": state.citizen_spatial_state,
		"assignments": state.assignment_state,
		"workplaces": state.workplace_state,
		"work": state.work_state,
		"logistics": state.logistics_state,
		"construction": state.construction_state,
		"navigation": state.navigation_state,
	}


func _owner_identities_match(
	state: CitySettlementSimulationState,
	identities: Dictionary
) -> bool:
	return (
		is_same(state.city_runtime_data, identities["runtime"])
		and is_same(state.object_state, identities["objects"])
		and is_same(state.citizen_registry_state, identities["citizens"])
		and is_same(state.citizen_spatial_state, identities["spatial"])
		and is_same(state.assignment_state, identities["assignments"])
		and is_same(state.workplace_state, identities["workplaces"])
		and is_same(state.work_state, identities["work"])
		and is_same(state.logistics_state, identities["logistics"])
		and is_same(state.construction_state, identities["construction"])
		and is_same(state.navigation_state, identities["navigation"])
	)


func _capture_owner_values(state: CitySettlementSimulationState) -> Dictionary:
	return {
		"runtime": state.city_runtime_data.duplicate(true),
		"object_version": state.object_state.object_version,
		"citizen_version": state.citizen_registry_state.citizen_version,
		"spatial_version": state.citizen_spatial_state.citizen_spatial_version,
		"assignment_version": state.assignment_state.assignment_version,
		"workplace_version": state.workplace_state.workplace_version,
		"work_order_version": state.work_state.work_order_version,
		"ground_pile_version": state.logistics_state.ground_pile_version,
		"construction_version": state.construction_state.construction_version,
	}


func _make_world(width: int, height: int, seed_value: int) -> WorldData:
	var world := WorldData.new()
	world.setup(width, height, seed_value)
	return world


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error("City workspace removal test: " + message)
