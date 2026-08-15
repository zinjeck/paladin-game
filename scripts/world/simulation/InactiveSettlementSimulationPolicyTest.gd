extends Node

var failure_count: int = 0


func _ready() -> void:
	_test_inactive_settlement_simulation_policy()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"Inactive settlement simulation policy test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("Inactive settlement simulation policy test passed.")
	get_tree().quit(0)


func _test_inactive_settlement_simulation_policy() -> void:
	WorldData.reset_runtime_session_state()
	var culture := WorldData.create_culture("Inactive Policy Culture")
	var culture_id := int(culture.get("id", -1))
	var polity := WorldPoliticalState.create_polity({
		"name": "Inactive Policy Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var polity_id := int(polity.get("id", -1))
	var city_a := _create_city("Policy A", polity_id, Vector2i(2, 2))
	var city_b := _create_city("Policy B", polity_id, Vector2i(4, 4))
	var city_a_id := int(city_a.get("id", -1))
	var city_b_id := int(city_b.get("id", -1))

	if (
		culture_id <= 0
		or city_a_id <= 0
		or city_b_id <= 0
		or not _seed_city(city_a_id, culture_id, 71_001)
		or not _seed_city(city_b_id, culture_id, 72_002)
	):
		_expect(false, "The two-city policy fixture must be created.")
		return

	var state_a: CitySettlementSimulationState = (
		WorldPoliticalState.get_city_simulation_state(city_a_id)
	)
	var state_b: CitySettlementSimulationState = (
		WorldPoliticalState.get_city_simulation_state(city_b_id)
	)
	var state_a_identities := _capture_identities(state_a)
	var state_b_identities := _capture_identities(state_b)

	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id)
		and SimulationCoordinator.select_detailed_simulation_settlement(
			city_a_id
		),
		"City B must remain presented while City A is selected explicitly for full simulation."
	)
	var b_before_a_tick := _capture_gameplay(state_b)
	SimulationCoordinator.run_simulation_systems(1, 10)

	_expect(
		WorldPoliticalState.active_settlement_id == city_b_id
		and SimulationCoordinator.get_detailed_simulation_settlement_id()
		== city_a_id
		and _city_was_simulated(state_a, 1)
		and _capture_gameplay(state_b) == b_before_a_tick,
		"Only explicitly selected City A may receive the first full-detail tick while B is presented."
	)
	_expect(
		SimulationCoordinator.get_settlement_simulation_tier(city_a_id)
		== SimulationCoordinator.SETTLEMENT_SIMULATION_TIER_FULL_DETAIL
		and SimulationCoordinator.get_settlement_simulation_tier(city_b_id)
		== SimulationCoordinator.SETTLEMENT_SIMULATION_TIER_INACTIVE_RETAINED
		and SimulationCoordinator.get_pending_inactive_minutes(city_a_id) == 0
		and SimulationCoordinator.get_pending_inactive_minutes(city_b_id) == 10,
		"The policy ledger must explicitly classify A as detailed and retain ten inactive minutes for B."
	)

	var a_before_view_changes := _capture_gameplay(state_a)
	var b_before_view_changes := _capture_gameplay(state_b)
	_expect(
		WorldPoliticalState.set_active_settlement(city_a_id)
		and WorldPoliticalState.set_active_settlement(city_b_id)
		and _capture_gameplay(state_a) == a_before_view_changes
		and _capture_gameplay(state_b) == b_before_view_changes,
		"Changing presentation selection alone must not mutate either city's gameplay."
	)
	SimulationCoordinator.run_simulation_systems(2, 6)
	_expect(
		_city_was_simulated(state_a, 2)
		and _capture_gameplay(state_b) == b_before_view_changes
		and SimulationCoordinator.get_pending_inactive_minutes(city_b_id) == 16,
		"A second tick must still target explicit A rather than the active presentation pointer."
	)

	var a_before_b_selection := _capture_gameplay(state_a)
	var b_before_b_selection := _capture_gameplay(state_b)
	_expect(
		SimulationCoordinator.select_detailed_simulation_settlement(city_b_id)
		and _capture_gameplay(state_a) == a_before_b_selection
		and _capture_gameplay(state_b) == b_before_b_selection,
		"Selecting a new detailed target must itself remain a gameplay no-op."
	)
	_expect(
		WorldPoliticalState.set_active_settlement(city_a_id),
		"City A must be presented while explicit City B runs."
	)
	SimulationCoordinator.run_simulation_systems(3, 4)
	_expect(
		_capture_gameplay(state_a) == a_before_b_selection
		and _city_was_simulated(state_b, 3)
		and WorldPoliticalState.active_settlement_id == city_a_id,
		"Explicit City B must tick without switching or mutating inactive presented City A."
	)
	_expect(
		SimulationCoordinator.get_pending_inactive_minutes(city_a_id) == 4
		and SimulationCoordinator.get_pending_inactive_minutes(city_b_id) == 16,
		"Switching the detailed target must start A's inactive ledger and preserve B's prior debt without implicit catch-up."
	)

	_expect(
		SimulationCoordinator.consume_pending_inactive_minutes(city_b_id, 7) == 7
		and SimulationCoordinator.get_pending_inactive_minutes(city_b_id) == 9,
		"The bounded future catch-up hook must consume only explicitly requested inactive minutes."
	)
	var a_before_no_target := _capture_gameplay(state_a)
	var b_before_no_target := _capture_gameplay(state_b)
	SimulationCoordinator.clear_detailed_simulation_settlement()
	SimulationCoordinator.run_simulation_systems(4, 3)
	_expect(
		_capture_gameplay(state_a) == a_before_no_target
		and _capture_gameplay(state_b) == b_before_no_target
		and SimulationCoordinator.get_pending_inactive_minutes(city_a_id) == 7
		and SimulationCoordinator.get_pending_inactive_minutes(city_b_id) == 12,
		"With no detailed target, every city must stay frozen while elapsed inactive time remains explicit."
	)
	_expect(
		not SimulationCoordinator.select_detailed_simulation_settlement(999_999)
		and SimulationCoordinator.get_detailed_simulation_settlement_id()
		== SettlementData.INVALID_SETTLEMENT_ID,
		"An invalid target must be rejected without creating an implicit active-settlement fallback."
	)
	_expect(
		_identities_match(state_a, state_a_identities)
		and _identities_match(state_b, state_b_identities),
		"Policy execution must retain every settlement gameplay owner identity."
	)

	WorldPoliticalState.reset_state()
	_expect(
		SimulationCoordinator.get_detailed_simulation_settlement_id()
		== SettlementData.INVALID_SETTLEMENT_ID
		and SimulationCoordinator.pending_inactive_minutes_by_settlement_id.is_empty()
		and SimulationCoordinator.full_detail_minutes_by_settlement_id.is_empty(),
		"Resetting the settlement registry must atomically clear the execution policy and elapsed ledger."
	)


func _city_was_simulated(
	state: CitySettlementSimulationState,
	expected_tick_index: int
) -> bool:
	if state.citizen_registry_state.citizens.size() != 1:
		return false
	var citizen: Dictionary = state.citizen_registry_state.citizens[0]
	return (
		citizen.has("hunger")
		and state.citizen_decision_runtime_state.runtime_initialized
		and state.citizen_movement_runtime_state.citizen_movement_visual_tick_index
		== expected_tick_index
	)


func _seed_city(settlement_id: int, culture_id: int, seed_value: int) -> bool:
	var state = WorldPoliticalState.get_city_simulation_state(settlement_id)
	if not state is CitySettlementSimulationState:
		return false
	state.city_world = _make_world(12, 12, seed_value)
	state.city_seed = seed_value
	state.city_runtime_data = {
		"name": "Policy City " + str(settlement_id),
		"primary_culture_id": culture_id,
		"founded": true,
		"can_build": true,
	}
	var citizen := CityCitizenRegistrySystem.add_city_citizen_for_city_state(
		state,
		"",
		Vector2i(5, 5),
		CityCitizens.CITY_CITIZEN_SEX_FEMALE,
		culture_id
	)
	if citizen.is_empty():
		return false
	var citizen_record: Dictionary = state.citizen_registry_state.citizens[0]
	for field in [
		"carry_capacity",
		"inventory",
		"haul_cargo",
		"hunger",
		"hunger_decay_remainder",
		"happiness",
	]:
		citizen_record.erase(field)
	state.citizen_registry_state.citizens[0] = citizen_record
	return true


func _create_city(
	city_name: String,
	polity_id: int,
	region_center: Vector2i
) -> Dictionary:
	return WorldPoliticalState.create_settlement({
		"name": city_name,
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": polity_id,
		"world_region_top_left": region_center,
		"world_region_center": region_center,
		"world_region_size": 1,
		"simulation_backend_kind": (
			SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
		),
	})


func _make_world(width: int, height: int, seed_value: int) -> WorldData:
	var world := WorldData.new()
	world.setup(width, height, seed_value)
	for y in range(height):
		for x in range(width):
			world.tiles[y][x] = {
				"fertility": 50.0,
				"elevation": 0.2,
				"temperature": 0.5,
				"precipitation": 0.5,
				"terrain": WorldData.TERRAIN_LAND,
				"biome": WorldData.BIOME_PLAIN,
				"resource": WorldData.RESOURCE_NONE,
				"is_land": true,
			}
	world.mark_tile_data_changed()
	return world


func _capture_gameplay(state: CitySettlementSimulationState) -> Dictionary:
	return {
		"citizens": state.citizen_registry_state.citizens.duplicate(true),
		"citizen_version": state.citizen_registry_state.citizen_version,
		"assignment_version": state.assignment_state.assignment_version,
		"workplace_version": state.workplace_state.workplace_version,
		"movement_tick": state.citizen_movement_runtime_state.citizen_movement_visual_tick_index,
		"movement_version": state.citizen_movement_runtime_state.citizen_movement_version,
		"task_version": state.citizen_task_runtime_state.citizen_task_version,
		"decision_initialized": state.citizen_decision_runtime_state.runtime_initialized,
		"decision_pending": state.citizen_decision_runtime_state.pending_decision_ids.duplicate(),
		"object_version": state.object_state.object_version,
		"ground_pile_version": state.logistics_state.ground_pile_version,
		"construction_version": state.construction_state.construction_version,
	}


func _capture_identities(state: CitySettlementSimulationState) -> Dictionary:
	return {
		"world": state.city_world,
		"citizens": state.citizen_registry_state.citizens,
		"objects": state.object_state.objects,
		"spatial": state.citizen_spatial_state.citizen_ids_by_tile,
		"tasks": state.citizen_task_runtime_state.active_task_ids,
		"movement": state.citizen_movement_runtime_state.active_mover_ids,
		"decision": state.citizen_decision_runtime_state.pending_decision_ids,
		"piles": state.logistics_state.ground_piles,
		"sites": state.construction_state.construction_sites,
	}


func _identities_match(
	state: CitySettlementSimulationState,
	identities: Dictionary
) -> bool:
	return (
		is_same(state.city_world, identities["world"])
		and is_same(state.citizen_registry_state.citizens, identities["citizens"])
		and is_same(state.object_state.objects, identities["objects"])
		and is_same(state.citizen_spatial_state.citizen_ids_by_tile, identities["spatial"])
		and is_same(state.citizen_task_runtime_state.active_task_ids, identities["tasks"])
		and is_same(state.citizen_movement_runtime_state.active_mover_ids, identities["movement"])
		and is_same(state.citizen_decision_runtime_state.pending_decision_ids, identities["decision"])
		and is_same(state.logistics_state.ground_piles, identities["piles"])
		and is_same(state.construction_state.construction_sites, identities["sites"])
	)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error("Inactive settlement simulation policy test: " + message)
