extends Node

var failure_count: int = 0


func _ready() -> void:
	_test_explicit_city_simulation_is_independent_of_visual_selection()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"Explicit settlement simulation context test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("Explicit settlement simulation context test passed.")
	get_tree().quit(0)


func _test_explicit_city_simulation_is_independent_of_visual_selection() -> void:
	WorldData.reset_runtime_session_state()
	var culture := WorldData.create_culture("Explicit Context Culture")
	var culture_id := int(culture.get("id", -1))
	var polity := WorldPoliticalState.create_polity({
		"name": "Explicit Context Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var polity_id := int(polity.get("id", -1))
	var city_a := _create_city("Explicit Context A", polity_id, Vector2i(1, 1))
	var city_b := _create_city("Explicit Context B", polity_id, Vector2i(2, 2))
	var city_a_id := int(city_a.get("id", -1))
	var city_b_id := int(city_b.get("id", -1))

	if (
		culture_id <= 0
		or city_a_id <= 0
		or city_b_id <= 0
		or not _seed_city(city_a_id, culture_id, 41_001)
		or not _seed_city(city_b_id, culture_id, 41_001)
	):
		_expect(false, "The two-city explicit context fixture must be created.")
		return

	var context_a = WorldPoliticalState.get_settlement_context(city_a_id)
	var context_b = WorldPoliticalState.get_settlement_context(city_b_id)
	var state_a: CitySettlementSimulationState = context_a.get_city_simulation_state()
	var state_b: CitySettlementSimulationState = context_b.get_city_simulation_state()

	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id),
		"City B must remain the visual/player-selected settlement."
	)
	WorldData.player_city_founded = false

	var state_b_before := _capture_city_projection(state_b)
	var state_b_identities := _capture_city_identities(state_b)
	var a_observations: Array = []
	SimulationCoordinator.run_settlement_simulation_systems(
		context_a,
		17,
		36,
		Callable(self, "_record_presentation_observation").bind(
			city_b_id,
			state_b,
			a_observations
		)
	)

	_expect(
		WorldPoliticalState.active_settlement_id == city_b_id
		and is_same(WorldPoliticalState.get_current_city_simulation_state(), state_b),
		"Simulating A must never switch the visual/current settlement away from B."
	)
	_expect(
		a_observations.size() == 6 and not a_observations.has(false),
		"Every simulation boundary must leave the visual City B selection intact."
	)
	_expect(
		_capture_city_projection(state_b) == state_b_before
		and _city_identities_match(state_b, state_b_identities),
		"Explicitly simulating A must not mutate City B or replace any B owner collection."
	)
	_expect(
		_city_reached_expected_projection(state_a, 17),
		"Explicit City A must advance its own needs, decisions, and movement runtime."
	)

	var state_a_after := _capture_city_projection(state_a)
	var state_a_identities := _capture_city_identities(state_a)
	var b_observations: Array = []
	SimulationCoordinator.run_settlement_simulation_systems(
		context_b,
		17,
		36,
		Callable(self, "_record_presentation_observation").bind(
			city_b_id,
			state_b,
			b_observations
		)
	)

	_expect(
		_capture_city_projection(state_a) == state_a_after
		and _city_identities_match(state_a, state_a_identities),
		"Simulating B after A must leave A exactly at its completed tick state."
	)
	_expect(
		_city_reached_expected_projection(state_b, 17)
		and _deterministic_projection(state_a) == _deterministic_projection(state_b),
		"Equivalent A and B fixtures must reach the same deterministic result regardless of visual selection."
	)
	_expect(
		b_observations.size() == 6
		and not b_observations.has(false)
		and WorldPoliticalState.active_settlement_id == city_b_id,
		"Sequential A then B execution must not use or leak a hidden global simulation target."
	)


func _record_presentation_observation(
	_system_key: String,
	_duration_usec: int,
	expected_active_id: int,
	expected_visual_state: CitySettlementSimulationState,
	observations: Array
) -> void:
	observations.append(
		WorldPoliticalState.active_settlement_id == expected_active_id
		and is_same(
			WorldPoliticalState.get_current_city_simulation_state(),
			expected_visual_state
		)
		and is_same(
			CityObjectSystem.get_current_state(),
			expected_visual_state.object_state
		)
	)


func _seed_city(settlement_id: int, culture_id: int, seed_value: int) -> bool:
	var state = WorldPoliticalState.get_city_simulation_state(settlement_id)
	if not state is CitySettlementSimulationState:
		return false

	state.city_world = _make_world(12, 12, seed_value)
	state.city_seed = seed_value
	state.city_runtime_data = {
		"name": "Explicit Context City",
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
	if citizen.is_empty() or state.citizen_registry_state.citizens.size() != 1:
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


func _city_reached_expected_projection(
	state: CitySettlementSimulationState,
	tick_index: int
) -> bool:
	if state.citizen_registry_state.citizens.size() != 1:
		return false
	var citizen: Dictionary = state.citizen_registry_state.citizens[0]
	return (
		int(citizen.get("hunger", -1)) == 99
		and int(citizen.get("hunger_decay_remainder", -1)) == 0
		and int(citizen.get("carry_capacity", -1)) == CityCitizens.DEFAULT_CITIZEN_CARRY_CAPACITY
		and citizen.get("inventory", {}) is Dictionary
		and citizen.get("haul_cargo", {}) is Dictionary
		and state.citizen_decision_runtime_state.runtime_initialized
		and state.citizen_movement_runtime_state.citizen_movement_visual_tick_index == tick_index
	)


func _deterministic_projection(state: CitySettlementSimulationState) -> Dictionary:
	var citizen: Dictionary = state.citizen_registry_state.citizens[0]
	return {
		"citizen": citizen.duplicate(true),
		"assignment_version": state.assignment_state.assignment_version,
		"workplace_version": state.workplace_state.workplace_version,
		"decision_initialized": state.citizen_decision_runtime_state.runtime_initialized,
		"decision_pending": state.citizen_decision_runtime_state.pending_decision_ids.duplicate(),
		"movement_tick": state.citizen_movement_runtime_state.citizen_movement_visual_tick_index,
		"task_version": state.citizen_task_runtime_state.citizen_task_version,
	}


func _capture_city_projection(state: CitySettlementSimulationState) -> Dictionary:
	return {
		"citizens": state.citizen_registry_state.citizens.duplicate(true),
		"citizen_version": state.citizen_registry_state.citizen_version,
		"assignment_version": state.assignment_state.assignment_version,
		"workplace_version": state.workplace_state.workplace_version,
		"object_version": state.object_state.object_version,
		"construction_version": state.construction_state.construction_version,
		"ground_pile_version": state.logistics_state.ground_pile_version,
		"haul_version": state.logistics_state.haul_reservation_version,
		"movement_tick": state.citizen_movement_runtime_state.citizen_movement_visual_tick_index,
		"movement_version": state.citizen_movement_runtime_state.citizen_movement_version,
		"task_version": state.citizen_task_runtime_state.citizen_task_version,
		"decision_initialized": state.citizen_decision_runtime_state.runtime_initialized,
		"decision_pending": state.citizen_decision_runtime_state.pending_decision_ids.duplicate(),
	}


func _capture_city_identities(state: CitySettlementSimulationState) -> Dictionary:
	return {
		"citizens": state.citizen_registry_state.citizens,
		"objects": state.object_state.objects,
		"piles": state.logistics_state.ground_piles,
		"sites": state.construction_state.construction_sites,
		"movement_events": state.citizen_movement_runtime_state.citizen_movement_visual_events,
		"active_tasks": state.citizen_task_runtime_state.active_task_ids,
		"decision_pending": state.citizen_decision_runtime_state.pending_decision_ids,
	}


func _city_identities_match(
	state: CitySettlementSimulationState,
	identities: Dictionary
) -> bool:
	return (
		is_same(state.citizen_registry_state.citizens, identities["citizens"])
		and is_same(state.object_state.objects, identities["objects"])
		and is_same(state.logistics_state.ground_piles, identities["piles"])
		and is_same(state.construction_state.construction_sites, identities["sites"])
		and is_same(state.citizen_movement_runtime_state.citizen_movement_visual_events, identities["movement_events"])
		and is_same(state.citizen_task_runtime_state.active_task_ids, identities["active_tasks"])
		and is_same(state.citizen_decision_runtime_state.pending_decision_ids, identities["decision_pending"])
	)


func _create_city(city_name: String, polity_id: int, region_center: Vector2i) -> Dictionary:
	return WorldPoliticalState.create_settlement({
		"name": city_name,
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": polity_id,
		"world_region_top_left": region_center,
		"world_region_center": region_center,
		"world_region_size": 1,
		"simulation_backend_kind": SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE,
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


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error("Explicit settlement simulation context test: " + message)
