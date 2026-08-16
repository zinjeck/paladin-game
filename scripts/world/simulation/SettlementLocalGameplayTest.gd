extends Node

const CityCitizenStateValidatorScript := preload(
	"res://scripts/city/simulation/validators/CityCitizenStateValidator.gd"
)

var failure_count: int = 0


func _ready() -> void:
	_test_two_founded_settlements_resolve_local_culture()
	_test_founded_state_controls_needs_decisions_and_builds()
	_test_production_uses_target_foundation_state()
	_test_foundation_bootstrap_is_local_and_exactly_once()
	_test_player_capital_bridge_uses_exact_local_state()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"Settlement-local gameplay test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("Settlement-local gameplay test passed.")
	get_tree().quit(0)


func _test_two_founded_settlements_resolve_local_culture() -> void:
	var fixture := _make_two_city_fixture(true, true, 51_001)
	if fixture.is_empty():
		return

	var state_a: CitySettlementSimulationState = fixture["state_a"]
	var state_b: CitySettlementSimulationState = fixture["state_b"]
	var culture_a_id: int = fixture["culture_a_id"]
	var culture_b_id: int = fixture["culture_b_id"]
	var city_a_id: int = fixture["city_a_id"]

	_expect(
		WorldPoliticalState.set_active_settlement(city_a_id),
		"City A must remain the presentation/player-selected settlement."
	)
	WorldData.player_city_founded = false

	var citizen_b := (
		CityCitizenRegistrySystem.add_city_citizen_for_city_state(
			state_b,
			"",
			Vector2i(4, 4),
			CityCitizens.CITY_CITIZEN_SEX_FEMALE
		)
	)

	WorldData.player_city_founded = true
	var citizen_a := (
		CityCitizenRegistrySystem.add_city_citizen_for_city_state(
			state_a,
			"",
			Vector2i(4, 4),
			CityCitizens.CITY_CITIZEN_SEX_MALE
		)
	)

	_expect(
		state_a.is_city_founded()
		and state_b.is_city_founded()
		and state_a.can_build_city_objects()
		and state_b.can_build_city_objects()
		and state_a.get_primary_culture_id() == culture_a_id
		and state_b.get_primary_culture_id() == culture_b_id,
		"Each founded settlement must expose its own local gameplay facts."
	)
	_expect(
		int(citizen_a.get("culture_id", -1)) == culture_a_id
		and int(citizen_b.get("culture_id", -1)) == culture_b_id,
		"Default citizen creation must use the target settlement culture."
	)
	var city_b_id: int = int(fixture["city_b_id"])
	var npc_validation_errors: Array[String] = []
	var npc_validation_target := {
		"settlement_context": (
			WorldPoliticalState.get_settlement_context(city_b_id)
		),
		"settlement_id": city_b_id,
		"city_state": state_b,
	}
	CityCitizenStateValidatorScript._validate_city_citizen_culture_state(
		npc_validation_target,
		npc_validation_errors,
		state_b.citizen_registry_state.citizen_index_by_id
	)
	_expect(
		npc_validation_errors.is_empty()
		and WorldPoliticalState.active_settlement_id == city_a_id,
		"A founded NPC city must validate against its local culture without changing the selected City."
	)

	WorldData.player_city_founded = false
	_expect(
		(
			CityCitizenRegistrySystem
			.resolve_city_citizen_culture_id_for_city_state(state_a)
			== culture_a_id
		)
		and (
			CityCitizenRegistrySystem
			.resolve_city_citizen_culture_id_for_city_state(state_b)
			== culture_b_id
		),
		"Changing the player-capital flag must not change local culture resolution."
	)


func _test_founded_state_controls_needs_decisions_and_builds() -> void:
	var fixture := _make_two_city_fixture(true, false, 51_101)
	if fixture.is_empty():
		return

	var state_a: CitySettlementSimulationState = fixture["state_a"]
	var state_b: CitySettlementSimulationState = fixture["state_b"]
	var culture_a_id: int = fixture["culture_a_id"]
	var culture_b_id: int = fixture["culture_b_id"]

	var citizen_a := _add_explicit_citizen(
		state_a,
		culture_a_id,
		Vector2i(5, 5),
		CityCitizens.CITY_CITIZEN_SEX_MALE
	)
	var citizen_b := _add_explicit_citizen(
		state_b,
		culture_b_id,
		Vector2i(5, 5),
		CityCitizens.CITY_CITIZEN_SEX_FEMALE
	)
	var citizen_a_id := int(citizen_a.get("id", -1))
	var citizen_b_id := int(citizen_b.get("id", -1))

	if citizen_a_id <= 0 or citizen_b_id <= 0:
		_expect(false, "The local-needs fixture must create both citizens.")
		return

	CitizenNeedsSystem.set_city_citizen_hunger_state_for_city_state(
		state_a,
		citizen_a_id,
		100,
		0
	)
	CitizenNeedsSystem.set_city_citizen_hunger_state_for_city_state(
		state_b,
		citizen_b_id,
		100,
		0
	)

	WorldData.player_city_founded = false
	CitizenNeedsSystem.run_tick_for_city_state(state_a, 7, 36)
	CitizenDecisionSystem.run_tick_for_city_state(state_a, 7, 1)

	WorldData.player_city_founded = true
	CitizenNeedsSystem.run_tick_for_city_state(state_b, 7, 36)
	CitizenDecisionSystem.run_tick_for_city_state(state_b, 7, 1)

	_expect(
		CitizenNeedsSystem.get_city_citizen_hunger_for_city_state(
			state_a,
			citizen_a_id
		) == 99
		and CitizenNeedsSystem.get_city_citizen_hunger_for_city_state(
			state_b,
			citizen_b_id
		) == 100,
		"Needs must advance for founded A and remain stopped for unfounded B."
	)
	_expect(
		state_a.citizen_decision_runtime_state.runtime_initialized
		and not state_b.citizen_decision_runtime_state.runtime_initialized,
		"Decision runtime must use the target settlement's founded state."
	)

	WorldData.player_city_founded = false
	var eligibility_with_global_false := _local_build_eligibility_matches(
		state_a,
		state_b
	)
	WorldData.player_city_founded = true
	var eligibility_with_global_true := _local_build_eligibility_matches(
		state_a,
		state_b
	)
	_expect(
		eligibility_with_global_false and eligibility_with_global_true,
		"Build eligibility must be local and invariant under player-capital changes."
	)


func _test_production_uses_target_foundation_state() -> void:
	var fixture := _make_two_city_fixture(true, false, 51_201, true)
	if fixture.is_empty():
		return

	var state_a: CitySettlementSimulationState = fixture["state_a"]
	var state_b: CitySettlementSimulationState = fixture["state_b"]
	var culture_a_id: int = fixture["culture_a_id"]
	var culture_b_id: int = fixture["culture_b_id"]

	var fishery_a := _prepare_attended_fishery(state_a, culture_a_id, 1)
	# Seed B's completed-workplace fixture through the ordinary local eligibility
	# gate, then return B to unfounded before either production tick runs.
	state_b.city_runtime_data["founded"] = true
	state_b.city_runtime_data["can_build"] = true
	var fishery_b := _prepare_attended_fishery(state_b, culture_b_id, 2)
	state_b.city_runtime_data["founded"] = false
	state_b.city_runtime_data["can_build"] = false
	if fishery_a.is_empty() or fishery_b.is_empty():
		_expect(false, "The local-production fixture must prepare both fisheries.")
		return

	WorkplaceProductionSystem.clear_resource_source_evaluation_cache()
	WorldData.player_city_founded = false
	WorkplaceProductionSystem.run_tick_for_city_state(state_a, 11, 120)

	WorldData.player_city_founded = true
	WorkplaceProductionSystem.run_tick_for_city_state(state_b, 11, 120)

	_expect(
		(
			CityResourceAccountingSystem
			.get_total_physical_city_resource_amount_for_city_state(
				state_a,
				CityResourceCatalog.RESOURCE_FISH
			) == 1
		)
		and (
			CityResourceAccountingSystem
			.get_total_physical_city_resource_amount_for_city_state(
				state_b,
				CityResourceCatalog.RESOURCE_FISH
			) == 0
		),
		"Founded NPC production must run without the player flag, while unfounded production must not run with it."
	)


func _test_foundation_bootstrap_is_local_and_exactly_once() -> void:
	var fixture := _make_two_city_fixture(
		false,
		false,
		51_301,
		false,
		true
	)
	if fixture.is_empty():
		return

	var state_a: CitySettlementSimulationState = fixture["state_a"]
	var state_b: CitySettlementSimulationState = fixture["state_b"]
	var culture_a_id: int = fixture["culture_a_id"]
	var culture_b_id: int = fixture["culture_b_id"]
	var city_a_id: int = fixture["city_a_id"]
	var city_b_id: int = fixture["city_b_id"]
	_expect(
		int(fixture["polity_a_id"]) == int(fixture["polity_b_id"])
		and culture_a_id != culture_b_id,
		"The local-foundation regression must use two cultures in one polity."
	)

	var keep_a := _add_city_keep(state_a, Vector2i(6, 6))
	var keep_b := _add_city_keep(state_b, Vector2i(6, 6))
	if keep_a.is_empty() or keep_b.is_empty():
		_expect(false, "The local-foundation fixture must place both Keeps.")
		return

	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id),
		"City B must remain active while City A is founded explicitly."
	)
	WorldData.player_city_founded = false
	var foundation_a := _make_foundation_values(state_a, keep_a)
	var foundation_b := _make_foundation_values(state_b, keep_b)
	var founded_a := WorldPoliticalState.found_city_settlement(
		city_a_id,
		foundation_a
	)

	_expect(
		founded_a
		and WorldPoliticalState.active_settlement_id == city_b_id
		and state_a.is_city_founded()
		and state_a.citizen_registry_state.citizens.size()
		== CityCitizenRegistrySystem.STARTING_CITY_POPULATION
		and _has_exact_local_starting_population(state_a, culture_a_id)
		and int(state_a.city_runtime_data.get("foundation_object_id", -1))
		== int(keep_a.get("id", -1))
		and str(state_a.city_runtime_data.get("foundation_object_owner", ""))
		== str(keep_a.get("owner", ""))
		and state_b.citizen_registry_state.citizens.is_empty(),
		"Founding A while B is active must record its exact Keep and bootstrap exactly eight local culture-A citizens only in A."
	)

	var a_citizens: Array = state_a.citizen_registry_state.citizens
	var a_index: Dictionary = state_a.citizen_registry_state.citizen_index_by_id
	var a_spatial: Dictionary = (
		state_a.citizen_spatial_state.citizen_ids_by_tile
	)
	var a_runtime: Dictionary = state_a.city_runtime_data
	var a_runtime_snapshot := state_a.city_runtime_data.duplicate(true)
	var a_citizen_version := state_a.citizen_registry_state.citizen_version
	var a_spatial_version := (
		state_a.citizen_spatial_state.citizen_spatial_version
	)
	var a_next_id := state_a.citizen_registry_state.next_citizen_id

	WorldPoliticalState.found_city_settlement(city_a_id, foundation_a)
	var repeated_a_count := (
		CityCitizenRegistrySystem
		.initialize_starting_city_population_for_city_state(state_a)
	)
	_expect(
		repeated_a_count == 0
		and is_same(state_a.citizen_registry_state.citizens, a_citizens)
		and is_same(state_a.citizen_registry_state.citizen_index_by_id, a_index)
		and is_same(state_a.citizen_spatial_state.citizen_ids_by_tile, a_spatial)
		and is_same(state_a.city_runtime_data, a_runtime)
		and state_a.city_runtime_data == a_runtime_snapshot
		and state_a.citizen_registry_state.citizen_version == a_citizen_version
		and state_a.citizen_spatial_state.citizen_spatial_version
		== a_spatial_version
		and state_a.citizen_registry_state.next_citizen_id == a_next_id,
		"Repeated A foundation/bootstrap must preserve exact owners, versions, IDs, and population."
	)

	_expect(
		not state_b.is_city_founded()
		and state_b.citizen_registry_state.citizens.is_empty(),
		"Founding and repeatedly bootstrapping A must leave unfounded B empty."
	)

	WorldData.player_city_founded = true
	var founded_b := WorldPoliticalState.found_city_settlement(
		city_b_id,
		foundation_b
	)
	_expect(
		founded_b
		and state_b.is_city_founded()
		and state_b.citizen_registry_state.citizens.size()
		== CityCitizenRegistrySystem.STARTING_CITY_POPULATION
		and _has_exact_local_starting_population(state_b, culture_b_id)
		and int(state_b.city_runtime_data.get("foundation_object_id", -1))
		== int(keep_b.get("id", -1))
		and str(state_b.city_runtime_data.get("foundation_object_owner", ""))
		== str(keep_b.get("owner", ""))
		and is_same(state_a.citizen_registry_state.citizens, a_citizens)
		and state_a.citizen_registry_state.citizen_version == a_citizen_version,
		"Same-polity founding B must retain B's local culture and exact Keep without mutating A."
	)

	var b_citizens: Array = state_b.citizen_registry_state.citizens
	var b_index: Dictionary = state_b.citizen_registry_state.citizen_index_by_id
	var b_runtime: Dictionary = state_b.city_runtime_data
	var b_runtime_snapshot := state_b.city_runtime_data.duplicate(true)
	var b_version := state_b.citizen_registry_state.citizen_version
	var b_next_id := state_b.citizen_registry_state.next_citizen_id
	WorldPoliticalState.found_city_settlement(city_b_id, foundation_b)
	var repeated_b_count := (
		CityCitizenRegistrySystem
		.initialize_starting_city_population_for_city_state(state_b)
	)
	_expect(
		repeated_b_count == 0
		and is_same(state_b.citizen_registry_state.citizens, b_citizens)
		and is_same(state_b.citizen_registry_state.citizen_index_by_id, b_index)
		and is_same(state_b.city_runtime_data, b_runtime)
		and state_b.city_runtime_data == b_runtime_snapshot
		and state_b.citizen_registry_state.citizen_version == b_version
		and state_b.citizen_registry_state.next_citizen_id == b_next_id,
		"Repeated B foundation/bootstrap must be an exact identity-preserving no-op."
	)


func _test_player_capital_bridge_uses_exact_local_state() -> void:
	WorldData.reset_runtime_session_state()
	var founding_world := _make_world(12, 12, 51_401)
	var locked := WorldData.lock_world_save({
		"source_world": founding_world,
		"region_top_left": Vector2i(1, 1),
		"region_center": Vector2i(2, 2),
		"region_size": 3,
		"world_scene_path": "res://scenes/GameSession.tscn",
		"city_scene_path": "res://scenes/CityScreen.tscn",
		"city_name": "Exact Capital",
		"culture_name": "Exact Capital Culture",
	})
	_expect(locked, "The player-capital bridge fixture must lock its world.")
	if not locked:
		return

	_expect(
		WorldPoliticalState.synchronize_foundation_with_world_data(),
		"The player-capital bridge fixture must create its exact capital."
	)
	var capital_id := WorldPoliticalState.get_player_capital_settlement_id()
	var capital_state = (
		WorldPoliticalState.get_player_capital_city_simulation_state()
	)
	if not capital_state is CitySettlementSimulationState:
		_expect(false, "The player capital must own a City state.")
		return

	capital_state.city_world = _make_world(24, 24, 51_402)
	capital_state.city_seed = 51_402
	var capital_world = capital_state.city_world
	var capital_keep := _add_city_keep(capital_state, Vector2i(6, 6))
	if capital_keep.is_empty():
		_expect(false, "The player-capital bridge fixture must place its Keep.")
		return

	# A stale true mirror must not short-circuit founding an unfounded local
	# capital. The bridge must inspect that exact local state first.
	WorldData.player_city_founded = true
	WorldData.player_city_foundation_top_left = Vector2i(1, 1)
	WorldData.player_city_foundation_size = Vector2i.ONE
	var capital_foundation := _make_foundation_values(
		capital_state,
		capital_keep
	)
	WorldData.found_player_city(capital_foundation)
	_expect(
		capital_state.is_city_founded()
		and capital_state.has_city_foundation_footprint()
		and int(capital_state.city_runtime_data.get(
			"foundation_object_id",
			-1
		)) == int(capital_keep.get("id", -1))
		and str(capital_state.city_runtime_data.get(
			"foundation_object_owner",
			""
		)) == str(capital_keep.get("owner", "")),
		"Player founding must ignore a stale mirror and commit the exact capital Keep."
	)

	var npc_culture := WorldData.create_culture("Exact NPC Culture")
	var npc_culture_id := int(npc_culture.get("id", -1))
	var npc_polity := _create_polity("Exact NPC Realm", npc_culture_id)
	var npc_polity_id := int(npc_polity.get("id", -1))
	var npc_city := _create_city(
		"Exact NPC City",
		npc_polity_id,
		Vector2i(8, 8)
	)
	var npc_city_id := int(npc_city.get("id", -1))
	var npc_state = WorldPoliticalState.get_city_simulation_state(npc_city_id)
	if (
		npc_culture_id <= 0
		or npc_polity_id <= 0
		or npc_city_id <= 0
		or not npc_state is CitySettlementSimulationState
	):
		_expect(false, "The player-capital bridge fixture must create an NPC city.")
		return

	npc_state.city_world = _make_world(24, 24, 51_403)
	npc_state.city_seed = 51_403
	npc_state.city_runtime_data = _make_city_runtime_data(
		npc_city_id,
		"Exact NPC City",
		npc_culture_id,
		npc_state.city_world,
		false
	)
	WorldPoliticalState.set_polity_capital(npc_polity_id, npc_city_id)
	var npc_keep := _add_city_keep(npc_state, Vector2i(7, 7), "npc")
	if npc_keep.is_empty():
		_expect(false, "The player-capital bridge fixture must place the NPC Keep.")
		return

	_expect(
		WorldPoliticalState.set_active_settlement(npc_city_id)
		and not WorldData.can_build_in_city(),
		"Build compatibility must read the active unfounded NPC rather than the founded player capital."
	)
	_expect(
		WorldPoliticalState.found_city_settlement(
			npc_city_id,
			_make_foundation_values(npc_state, npc_keep)
		),
		"The NPC fixture must found independently."
	)

	# False/invalid mirrors are repaired from the exact capital, not from the
	# active NPC city.
	WorldData.player_city_founded = false
	WorldData.player_city_foundation_top_left = Vector2i(-1, -1)
	WorldData.player_city_foundation_size = Vector2i.ZERO
	_expect(
		WorldData.has_player_city()
		and WorldData.has_player_city_foundation()
		and WorldData.can_build_in_city()
		and WorldData.player_city_founded
		and WorldData.player_city_foundation_top_left
		== capital_keep.get("top_left")
		and WorldData.player_city_foundation_size == capital_keep.get("size"),
		"Player-city mirrors and guards must derive from the exact capital while the NPC is active."
	)

	var npc_runtime: Dictionary = npc_state.city_runtime_data
	var npc_runtime_snapshot := npc_runtime.duplicate(true)
	var npc_object_state = npc_state.object_state
	var npc_registry_state = npc_state.citizen_registry_state
	var npc_objects: Array = npc_object_state.objects
	var npc_citizens: Array = npc_registry_state.citizens
	var npc_world = npc_state.city_world
	var npc_seed: int = npc_state.city_seed
	WorldData.reset_player_city_state()
	_expect(
		WorldPoliticalState.active_settlement_id == npc_city_id
		and is_same(capital_state.city_world, capital_world)
		and capital_state.city_seed == 51_402
		and capital_state.city_runtime_data.is_empty()
		and capital_state.object_state.objects.is_empty()
		and capital_state.citizen_registry_state.citizens.is_empty()
		and is_same(npc_state.city_runtime_data, npc_runtime)
		and npc_state.city_runtime_data == npc_runtime_snapshot
		and is_same(npc_state.object_state, npc_object_state)
		and is_same(npc_state.citizen_registry_state, npc_registry_state)
		and is_same(npc_state.object_state.objects, npc_objects)
		and is_same(npc_state.citizen_registry_state.citizens, npc_citizens)
		and is_same(npc_state.city_world, npc_world)
		and npc_state.city_seed == npc_seed,
		"Resetting the player city must reset only the exact capital without switching or mutating the active NPC."
	)

	WorldData.player_city_founded = true
	WorldData.player_city_foundation_top_left = Vector2i(2, 2)
	WorldData.player_city_foundation_size = Vector2i.ONE
	_expect(
		not WorldData.has_player_city()
		and not WorldData.has_player_city_foundation()
		and WorldData.can_build_in_city()
		and not WorldData.player_city_founded
		and WorldData.player_city_foundation_top_left == Vector2i(-1, -1)
		and WorldData.player_city_foundation_size == Vector2i.ZERO,
		"Stale true mirrors must not make the reset capital inherit active-NPC facts or disable active-NPC builds."
	)


func _make_two_city_fixture(
	founded_a: bool,
	founded_b: bool,
	seed_base: int,
	fish_tiles: bool = false,
	same_polity: bool = false
) -> Dictionary:
	WorldData.reset_runtime_session_state()
	var culture_a := WorldData.create_culture("Settlement Local Culture A")
	var culture_b := WorldData.create_culture("Settlement Local Culture B")
	var culture_a_id := int(culture_a.get("id", -1))
	var culture_b_id := int(culture_b.get("id", -1))
	var polity_a := _create_polity("Settlement Local Realm A", culture_a_id)
	var polity_b: Dictionary = (
		polity_a
		if same_polity
		else _create_polity("Settlement Local Realm B", culture_b_id)
	)
	var polity_a_id := int(polity_a.get("id", -1))
	var polity_b_id := int(polity_b.get("id", -1))
	var city_a := _create_city(
		"Settlement Local City A",
		polity_a_id,
		Vector2i(1, 1)
	)
	var city_b := _create_city(
		"Settlement Local City B",
		polity_b_id,
		Vector2i(2, 2)
	)
	var city_a_id := int(city_a.get("id", -1))
	var city_b_id := int(city_b.get("id", -1))

	if (
		culture_a_id <= 0
		or culture_b_id <= 0
		or polity_a_id <= 0
		or polity_b_id <= 0
		or city_a_id <= 0
		or city_b_id <= 0
	):
		_expect(false, "The two-settlement fixture must create valid identities.")
		return {}

	var state_a = WorldPoliticalState.get_city_simulation_state(city_a_id)
	var state_b = WorldPoliticalState.get_city_simulation_state(city_b_id)
	if (
		not state_a is CitySettlementSimulationState
		or not state_b is CitySettlementSimulationState
	):
		_expect(false, "Both CITY settlements must own local simulation state.")
		return {}

	state_a.city_world = _make_world(24, 24, seed_base, fish_tiles)
	state_b.city_world = _make_world(24, 24, seed_base + 1, fish_tiles)
	state_a.city_seed = seed_base
	state_b.city_seed = seed_base + 1
	state_a.city_runtime_data = _make_city_runtime_data(
		city_a_id,
		"Settlement Local City A",
		culture_a_id,
		state_a.city_world,
		founded_a
	)
	state_b.city_runtime_data = _make_city_runtime_data(
		city_b_id,
		"Settlement Local City B",
		culture_b_id,
		state_b.city_world,
		founded_b
	)

	WorldPoliticalState.set_polity_capital(polity_a_id, city_a_id)
	if not same_polity:
		WorldPoliticalState.set_polity_capital(polity_b_id, city_b_id)
	WorldPoliticalState.player_polity_id = polity_a_id
	WorldPoliticalState.set_active_settlement(city_a_id)

	return {
		"culture_a_id": culture_a_id,
		"culture_b_id": culture_b_id,
		"polity_a_id": polity_a_id,
		"polity_b_id": polity_b_id,
		"city_a_id": city_a_id,
		"city_b_id": city_b_id,
		"state_a": state_a,
		"state_b": state_b,
	}


func _make_city_runtime_data(
	city_id: int,
	city_name: String,
	culture_id: int,
	city_world: WorldData,
	founded: bool
) -> Dictionary:
	return {
		"id": city_id,
		"name": city_name,
		"primary_culture_id": culture_id,
		"city_world_seed": city_world.seed,
		"city_map_size": Vector2i(city_world.width, city_world.height),
		"foundation_top_left": Vector2i(-1, -1),
		"foundation_size": Vector2i.ZERO,
		"can_build": founded,
		"founded": founded,
	}


func _create_polity(polity_name: String, culture_id: int) -> Dictionary:
	return WorldPoliticalState.create_polity({
		"name": polity_name,
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})


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


func _add_explicit_citizen(
	state: CitySettlementSimulationState,
	culture_id: int,
	tile_position: Vector2i,
	citizen_sex: String
) -> Dictionary:
	return CityCitizenRegistrySystem.add_city_citizen_for_city_state(
		state,
		"",
		tile_position,
		citizen_sex,
		culture_id
	)


func _local_build_eligibility_matches(
	state_a: CitySettlementSimulationState,
	state_b: CitySettlementSimulationState
) -> bool:
	return (
		CityObjectSystem.can_use_city_object_definition_for_city_state(
			state_a,
			CityObjectCatalog.CITY_OBJECT_HOUSE
		)
		and not CityObjectSystem.can_use_city_object_definition_for_city_state(
			state_a,
			CityObjectCatalog.CITY_OBJECT_CITY_CENTER
		)
		and not CityObjectSystem.can_use_city_object_definition_for_city_state(
			state_b,
			CityObjectCatalog.CITY_OBJECT_HOUSE
		)
		and CityObjectSystem.can_use_city_object_definition_for_city_state(
			state_b,
			CityObjectCatalog.CITY_OBJECT_CITY_CENTER
		)
	)


func _prepare_attended_fishery(
	state: CitySettlementSimulationState,
	culture_id: int,
	tile_offset: int
) -> Dictionary:
	var fishery := CityObjectSystem.register_completed_city_object_for_city_state(
		state,
		{
			"object_type": CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS,
			"top_left": Vector2i(8 + tile_offset, 8),
			"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
				CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS
			),
			"object_owner": "player",
		}
	)
	var fishery_id := int(fishery.get("id", -1))
	if fishery_id <= 0:
		return {}

	var access_tiles := CityNavigationSystem.get_city_object_access_tiles_for_city_state(
		state,
		state.city_world,
		fishery
	)
	if access_tiles.is_empty():
		return {}

	var worker := _add_explicit_citizen(
		state,
		culture_id,
		access_tiles[0],
		CityCitizens.CITY_CITIZEN_SEX_MALE
	)
	var worker_id := int(worker.get("id", -1))
	var work_task := {
		"kind": CityCitizens.CITY_CITIZEN_TASK_KIND_WORK,
		"source": CityCitizens.CITY_CITIZEN_TASK_SOURCE_SCHEDULE,
		"priority": 50,
		"target_object_id": fishery_id,
	}
	if (
		worker_id <= 0
		or not CityAssignmentSystem.assign_city_citizen_job_for_city_state(
			state,
			worker_id,
			fishery_id
		)
		or not CityCitizenTaskRuntimeSystem.assign_city_citizen_task_for_city_state(
			state,
			worker_id,
			work_task
		)
		or not CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase_for_city_state(
			state,
			worker_id,
			CityCitizens.CITY_CITIZEN_TASK_PHASE_PERFORMING
		)
	):
		return {}

	return fishery


func _add_city_keep(
	state: CitySettlementSimulationState,
	top_left: Vector2i,
	object_owner: String = "player"
) -> Dictionary:
	return CityObjectSystem.register_completed_city_object_for_city_state(
		state,
		{
			"object_type": CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
			"top_left": top_left,
			"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
				CityObjectCatalog.CITY_OBJECT_CITY_CENTER
			),
			"object_owner": object_owner,
		}
	)


func _make_foundation_values(
	state: CitySettlementSimulationState,
	city_keep: Dictionary
) -> Dictionary:
	return {
		"city_world_seed": state.city_seed,
		"city_map_size": Vector2i(
			state.city_world.width,
			state.city_world.height
		),
		"foundation_top_left": city_keep.get(
			"top_left",
			Vector2i(-1, -1)
		),
		"foundation_size": city_keep.get("size", Vector2i.ZERO),
	}


func _has_exact_local_starting_population(
	state: CitySettlementSimulationState,
	culture_id: int
) -> bool:
	if (
		state.citizen_registry_state.citizens.size()
		!= CityCitizenRegistrySystem.STARTING_CITY_POPULATION
		or state.citizen_registry_state.citizen_index_by_id.size()
		!= CityCitizenRegistrySystem.STARTING_CITY_POPULATION
		or state.citizen_registry_state.next_citizen_id
		!= CityCitizenRegistrySystem.STARTING_CITY_POPULATION + 1
		or not state.citizen_registry_state.starting_population_initialized
	):
		return false

	for citizen_index in range(
		CityCitizenRegistrySystem.STARTING_CITY_POPULATION
	):
		var raw_citizen = state.citizen_registry_state.citizens[citizen_index]
		var expected_id := citizen_index + 1
		if (
			not raw_citizen is Dictionary
			or int(raw_citizen.get("id", -1)) != expected_id
			or int(raw_citizen.get("culture_id", -1)) != culture_id
			or int(
				state.citizen_registry_state.citizen_index_by_id.get(
					expected_id,
					-1
				)
			) != citizen_index
		):
			return false

	return true


func _make_world(
	width: int,
	height: int,
	seed_value: int,
	fish_tiles: bool = false
) -> WorldData:
	var world := WorldData.new()
	world.setup(width, height, seed_value)
	var tile_resource := (
		CityResourceCatalog.RESOURCE_FISH
		if fish_tiles
		else WorldData.RESOURCE_NONE
	)

	for y in range(height):
		for x in range(width):
			world.tiles[y][x] = {
				"fertility": 50.0,
				"elevation": 0.2,
				"temperature": 0.5,
				"precipitation": 0.5,
				"terrain": WorldData.TERRAIN_LAND,
				"biome": WorldData.BIOME_PLAIN,
				"resource": tile_resource,
				"is_land": true,
			}

	world.mark_tile_data_changed()
	return world


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error("Settlement-local gameplay test: " + message)
