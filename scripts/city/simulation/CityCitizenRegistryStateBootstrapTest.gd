extends Node

const TEST_CITY_NAME := "Citizen Bootstrap"
const TEST_CULTURE_NAME := "Registry Culture"

var failure_count: int = 0


func _ready() -> void:
	_test_state_defaults()
	_test_pre_context_state_adoption()
	_test_real_founding_population_bootstrap()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City citizen-registry bootstrap test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City citizen-registry bootstrap test passed.")
	get_tree().quit(0)


func _test_state_defaults() -> void:
	var state_a := CityCitizenRegistryState.new()
	var state_b := CityCitizenRegistryState.new()
	_expect(
		state_a.citizens.is_empty()
		and state_a.citizen_index_by_id.is_empty()
		and state_a.next_citizen_id == 1
		and state_a.citizen_version == 0,
		"A new registry must have clean collection, ID, and version defaults."
	)
	_expect(
		not is_same(state_a, state_b)
		and not is_same(state_a.citizens, state_b.citizens)
		and not is_same(
			state_a.citizen_index_by_id,
			state_b.citizen_index_by_id
		),
		"Separate registries must never share their mutable collections."
	)


func _test_pre_context_state_adoption() -> void:
	WorldData.reset_runtime_session_state()
	var world := _make_world(8, 8, 96_001)
	if not _lock_founding_world(world, "Pre-context"):
		return

	var bootstrap_citizens: Array = [{
		"id": 17,
		"name": "Pre-context Citizen",
		"alive": true,
	}]
	var bootstrap_index: Dictionary = {17: 0}
	var bootstrap_state := (
		CityCitizenRegistrySystem.get_current_state()
	)
	bootstrap_state.citizens = bootstrap_citizens
	bootstrap_state.citizen_index_by_id = bootstrap_index
	bootstrap_state.next_citizen_id = 18
	bootstrap_state.citizen_version = 5

	_expect(
		WorldPoliticalState.synchronize_foundation_with_world_data(),
		"Founding must establish a City settlement context."
	)
	var capital_state = WorldPoliticalState.get_active_city_simulation_state()
	var context = WorldPoliticalState.get_active_settlement_context()
	_expect(
		capital_state is CitySettlementSimulationState
		and is_same(
			capital_state.citizen_registry_state,
			bootstrap_state
		)
		and is_same(
			capital_state.citizen_registry_state.citizens,
			bootstrap_citizens
		)
		and is_same(
			capital_state.citizen_registry_state.citizen_index_by_id,
			bootstrap_index
		),
		"The founding City must adopt the exact pre-context registry owner."
	)
	_expect(
		context != null
		and is_same(
			context.get_city_citizen_registry_state(),
			bootstrap_state
		)
		and is_same(CityCitizenRegistrySystem.get_current_state().citizens, bootstrap_citizens)
		and is_same(
			CityCitizenRegistrySystem.get_current_state().citizen_index_by_id,
			bootstrap_index
		)
		and CityCitizenRegistrySystem.get_current_state().next_citizen_id == 18
		and CityCitizenRegistrySystem.get_current_state().citizen_version == 5,
		"Context and compatibility access must resolve one adopted registry."
	)
	_expect(
		WorldPoliticalState.synchronize_foundation_with_world_data()
		and is_same(
			CityCitizenRegistrySystem.get_current_state(),
			bootstrap_state
		)
		and CityCitizenRegistrySystem.get_current_state().citizens.size() == 1,
		"Repeated synchronization must not replace or duplicate the registry."
	)


func _test_real_founding_population_bootstrap() -> void:
	WorldData.reset_runtime_session_state()
	var world := _make_world(8, 8, 96_101)
	if not _lock_founding_world(world, "Actual founding"):
		return
	_expect(
		WorldPoliticalState.synchronize_foundation_with_world_data(),
		"The live flow must establish the capital before Keep placement."
	)
	var capital_state = WorldPoliticalState.get_active_city_simulation_state()
	if not capital_state is CitySettlementSimulationState:
		_expect(false, "The live founding fixture requires a City state.")
		return

	var registry_state: CityCitizenRegistryState = (
		capital_state.citizen_registry_state
	)
	var registry_array: Array = registry_state.citizens
	var registry_index: Dictionary = registry_state.citizen_index_by_id
	var city_world := _make_world(20, 20, 96_102)
	WorldData.store_city_world_save(city_world, 96_102)
	var keep_size := WorldData.get_city_object_size_for_type(
		WorldData.CITY_OBJECT_CITY_CENTER
	)
	var keep := CityObjectSystem.add_city_object({
		"object_type": WorldData.CITY_OBJECT_CITY_CENTER,
		"top_left": Vector2i(6, 6),
		"size_tiles": keep_size,
		"object_owner": "player",
		"city_world": city_world,
	})
	_expect(not keep.is_empty(), "The founding fixture must place a City Keep.")
	if keep.is_empty():
		return

	WorldData.found_player_city({
		"city_world_seed": 96_102,
		"city_map_size": Vector2i(city_world.width, city_world.height),
		"foundation_top_left": keep.get("top_left", Vector2i(-1, -1)),
		"foundation_size": keep.get("size", Vector2i.ZERO),
	})

	var exact_index := true
	for citizen_index in range(WorldData.STARTING_CITY_POPULATION):
		var expected_id := citizen_index + 1
		var raw_citizen = registry_array[citizen_index]
		if (
			not raw_citizen is Dictionary
			or int(raw_citizen.get("id", -1)) != expected_id
			or int(registry_index.get(expected_id, -1)) != citizen_index
		):
			exact_index = false
			break

	_expect(
		WorldData.has_player_city()
		and registry_array.size() == WorldData.STARTING_CITY_POPULATION
		and registry_index.size() == WorldData.STARTING_CITY_POPULATION
		and registry_state.next_citizen_id
		== WorldData.STARTING_CITY_POPULATION + 1
		and registry_state.citizen_version
		== WorldData.STARTING_CITY_POPULATION
		and exact_index,
		"Founding must create IDs 1-8, exact indexes, next ID 9, and version 8."
	)
	_expect(
		is_same(CityCitizenRegistrySystem.get_current_state().citizens, registry_array)
		and is_same(CityCitizenRegistrySystem.get_current_state().citizen_index_by_id, registry_index)
		and is_same(
			WorldPoliticalState
			.get_active_settlement_context()
			.get_city_citizen_registry_state(),
			registry_state
		),
		"The eight founders must land directly in the capital registry."
	)

	var repeated_count := WorldData.initialize_starting_city_population()
	WorldData.found_player_city({
		"city_world_seed": 96_102,
		"city_map_size": Vector2i(city_world.width, city_world.height),
	})
	_expect(
		repeated_count == 0
		and registry_array.size() == WorldData.STARTING_CITY_POPULATION
		and registry_state.next_citizen_id
		== WorldData.STARTING_CITY_POPULATION + 1
		and registry_state.citizen_version
		== WorldData.STARTING_CITY_POPULATION,
		"Repeated founding initialization must not duplicate citizens."
	)



func _lock_founding_world(world: WorldData, label: String) -> bool:
	var locked := WorldData.lock_world_save({
		"source_world": world,
		"region_top_left": Vector2i(1, 1),
		"region_center": Vector2i(2, 2),
		"region_size": 3,
		"world_scene_path": "res://scenes/GameSession.tscn",
		"city_scene_path": "res://scenes/CityScreen.tscn",
		"city_name": TEST_CITY_NAME + " " + label,
		"culture_name": TEST_CULTURE_NAME + " " + label,
	})
	_expect(locked, label + " fixture must lock its founding world.")
	return locked


func _create_city(
	city_name: String,
	polity_id: int,
	region_center: Vector2i,
	backend_kind: String
) -> Dictionary:
	return WorldPoliticalState.create_settlement({
		"name": city_name,
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": polity_id,
		"world_region_top_left": region_center,
		"world_region_center": region_center,
		"world_region_size": 1,
		"simulation_backend_kind": backend_kind,
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
	push_error("City citizen-registry bootstrap test: " + message)
