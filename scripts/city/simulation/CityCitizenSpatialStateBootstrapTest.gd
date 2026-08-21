extends Node

const CitySettlementTestFixtureScript = preload(
	"res://scripts/city/simulation/test_support/CitySettlementTestFixture.gd"
)
const TEST_CITY_NAME := "Spatial Bootstrap"
const TEST_CULTURE_NAME := "Spatial Culture"

var failure_count: int = 0


func _ready() -> void:
	_test_state_defaults()
	_test_pre_context_state_adoption()
	_test_real_founding_spatial_bootstrap()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City citizen-spatial bootstrap test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City citizen-spatial bootstrap test passed.")
	get_tree().quit(0)


func _test_state_defaults() -> void:
	var state_a := CityCitizenSpatialState.new()
	var state_b := CityCitizenSpatialState.new()
	_expect(
		state_a.citizen_ids_by_tile.is_empty()
		and state_a.citizen_spatial_version == 0,
		"A new spatial owner must have clean index and version defaults."
	)
	_expect(
		not is_same(state_a, state_b)
		and not is_same(
			state_a.citizen_ids_by_tile,
			state_b.citizen_ids_by_tile
		),
		"Separate spatial owners must never share their mutable index."
	)


func _test_pre_context_state_adoption() -> void:
	var fixture = CitySettlementTestFixtureScript.create({
		"label": "Citizen Spatial Bootstrap",
	})
	_expect(fixture != null, "The spatial fixture must be created.")
	if fixture == null:
		return

	var bootstrap_index: Dictionary = {
		Vector2i(3, 3): [17, 18],
	}
	var bootstrap_state: CityCitizenSpatialState = (
		fixture.city_state.citizen_spatial_state
	)
	bootstrap_state.citizen_ids_by_tile = bootstrap_index
	bootstrap_state.citizen_spatial_version = 5

	_expect(
		is_same(fixture.city_state.citizen_spatial_state, bootstrap_state)
		and is_same(
			fixture.city_state.citizen_spatial_state.citizen_ids_by_tile,
			bootstrap_index
		),
		"The registered City must retain the exact spatial owner."
	)
	_expect(
		fixture.settlement_context != null
		and is_same(
			fixture.settlement_context.get_city_citizen_spatial_state(),
			bootstrap_state
		)
		and bootstrap_state.citizen_spatial_version == 5,
		"The context must expose the explicit spatial owner."
	)
	fixture.cleanup()


func _test_real_founding_spatial_bootstrap() -> void:
	WorldData.reset_runtime_session_state()
	var world := _make_world(8, 8, 98_101)
	if not _lock_founding_world(world, "Actual founding"):
		return
	_expect(
		WorldPoliticalState.synchronize_foundation_with_world_data(),
		"The live flow must establish the capital before Keep placement."
	)
	var capital_settlement_id := (
		WorldPoliticalState.get_player_capital_settlement_id()
	)
	var capital_state = WorldPoliticalState.get_city_simulation_state(
		capital_settlement_id
	)
	if not capital_state is CitySettlementSimulationState:
		_expect(false, "The live founding fixture requires a City state.")
		return

	var spatial_state: CityCitizenSpatialState = (
		capital_state.citizen_spatial_state
	)
	var spatial_index: Dictionary = spatial_state.citizen_ids_by_tile
	var city_world := _make_world(20, 20, 98_102)
	WorldData.store_city_world_for_state(
		capital_state, city_world, 98_102
	)
	var keep_size := CityObjectCatalog.get_city_object_size_for_type(
		CityObjectCatalog.CITY_OBJECT_CITY_CENTER
	)
	var keep := CityObjectSystem.add_city_object_for_city_state(capital_state, {
		"object_type": CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
		"top_left": Vector2i(6, 6),
		"size_tiles": keep_size,
		"object_owner": "player",
		"city_world": city_world,
	})
	_expect(not keep.is_empty(), "The founding fixture must place a City Keep.")
	if keep.is_empty():
		return

	WorldData.found_player_city({
		"city_world_seed": 98_102,
		"city_map_size": Vector2i(city_world.width, city_world.height),
		"foundation_top_left": keep.get("top_left", Vector2i(-1, -1)),
		"foundation_size": keep.get("size", Vector2i.ZERO),
	})

	_expect(
		WorldData.has_player_city()
		and capital_state.citizen_registry_state.citizens.size()
		== CityCitizenRegistrySystem.STARTING_CITY_POPULATION
		and spatial_state.citizen_spatial_version
		== CityCitizenRegistrySystem.STARTING_CITY_POPULATION
		and _spatial_index_matches_registry(capital_state, spatial_index),
		"Founding must index all eight citizens and publish eight spatial changes."
	)
	_expect(
		is_same(capital_state.citizen_spatial_state.citizen_ids_by_tile, spatial_index)
		and is_same(
			WorldPoliticalState
			.get_settlement_context(capital_settlement_id)
			.get_city_citizen_spatial_state(),
			spatial_state
		),
		"The founders must land directly in the capital's spatial owner."
	)

	var version_before_repeat := spatial_state.citizen_spatial_version
	var repeated_count := (
		CityCitizenRegistrySystem.initialize_starting_city_population_for_city_state(
			capital_state
		)
	)
	_expect(
		repeated_count == 0
		and spatial_state.citizen_spatial_version == version_before_repeat
		and _spatial_index_matches_registry(capital_state, spatial_index),
		"Repeated founding initialization must not duplicate or invalidate space."
	)

	var legacy_citizen: Dictionary = capital_state.citizen_registry_state.citizens[0]
	legacy_citizen.erase("city_tile_position")
	capital_state.citizen_registry_state.citizens[0] = legacy_citizen
	var version_before_legacy_repair := spatial_state.citizen_spatial_version
	_expect(
		CityCitizenSpatialSystem.ensure_city_citizen_spatial_state_for_city_state(
			capital_state,
			city_world
		) == 1
		and capital_state.citizen_registry_state.citizens[0].get(
			"city_tile_position"
		) is Vector2i
		and spatial_state.citizen_spatial_version
		== version_before_legacy_repair + 1
		and _spatial_index_matches_registry(capital_state, spatial_index),
		"Legacy position repair must rebuild membership and invalidate once."
	)
	var version_before_clean_ensure := spatial_state.citizen_spatial_version
	_expect(
		CityCitizenSpatialSystem.ensure_city_citizen_spatial_state_for_city_state(
			capital_state,
			city_world
		) == 0
		and spatial_state.citizen_spatial_version
		== version_before_clean_ensure,
		"A clean spatial ensure must not publish a false change."
	)



func _spatial_index_matches_registry(
	city_state: CitySettlementSimulationState,
	spatial_index: Dictionary
) -> bool:
	var expected_by_tile: Dictionary = {}
	for raw_citizen in city_state.citizen_registry_state.citizens:
		if not raw_citizen is Dictionary:
			return false
		var citizen: Dictionary = raw_citizen
		var citizen_id := int(citizen.get("id", -1))
		var raw_tile = citizen.get(
			"city_tile_position",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)
		if citizen_id <= 0 or not raw_tile is Vector2i:
			return false
		var tile: Vector2i = raw_tile
		var expected_ids: Array = expected_by_tile.get(tile, [])
		expected_ids.append(citizen_id)
		expected_ids.sort()
		expected_by_tile[tile] = expected_ids
	return expected_by_tile == spatial_index


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
	push_error("City citizen-spatial bootstrap test: " + message)
