extends Node

const TEST_CITY_NAME := "Spatial Bootstrap"
const TEST_CULTURE_NAME := "Spatial Culture"

var failure_count: int = 0


func _ready() -> void:
	_test_state_defaults()
	_test_pre_context_state_adoption()
	_test_real_founding_spatial_bootstrap()
	_test_legacy_backend_conversion_adopts_state()
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
	WorldData.reset_runtime_session_state()
	var world := _make_world(8, 8, 98_001)
	if not _lock_founding_world(world, "Pre-context"):
		return

	var bootstrap_index: Dictionary = {
		Vector2i(3, 3): [17, 18],
	}
	var bootstrap_state := (
		CityCitizenSpatialSystem.get_current_state()
	)
	bootstrap_state.citizen_ids_by_tile = bootstrap_index
	bootstrap_state.citizen_spatial_version = 5

	_expect(
		WorldPoliticalState.synchronize_foundation_with_world_data(),
		"Founding must establish a City settlement context."
	)
	var capital_state = WorldPoliticalState.get_active_city_simulation_state()
	var context = WorldPoliticalState.get_active_settlement_context()
	_expect(
		capital_state is CitySettlementSimulationState
		and is_same(capital_state.citizen_spatial_state, bootstrap_state)
		and is_same(
			capital_state.citizen_spatial_state.citizen_ids_by_tile,
			bootstrap_index
		),
		"The founding City must adopt the exact pre-context spatial owner."
	)
	_expect(
		context != null
		and is_same(
			context.get_city_citizen_spatial_state(),
			bootstrap_state
		)
		and is_same(CityCitizenSpatialSystem.get_current_state().citizen_ids_by_tile, bootstrap_index)
		and CityCitizenSpatialSystem.get_current_state().citizen_spatial_version == 5,
		"Context and compatibility access must resolve one spatial owner."
	)
	_expect(
		WorldPoliticalState.synchronize_foundation_with_world_data()
		and is_same(
			CityCitizenSpatialSystem.get_current_state(),
			bootstrap_state
		),
		"Repeated synchronization must not replace the spatial owner."
	)


func _test_real_founding_spatial_bootstrap() -> void:
	WorldData.reset_runtime_session_state()
	var world := _make_world(8, 8, 98_101)
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

	var spatial_state: CityCitizenSpatialState = (
		capital_state.citizen_spatial_state
	)
	var spatial_index: Dictionary = spatial_state.citizen_ids_by_tile
	var city_world := _make_world(20, 20, 98_102)
	WorldData.store_city_world_save(city_world, 98_102)
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
		"city_world_seed": 98_102,
		"city_map_size": Vector2i(city_world.width, city_world.height),
		"foundation_top_left": keep.get("top_left", Vector2i(-1, -1)),
		"foundation_size": keep.get("size", Vector2i.ZERO),
	})

	_expect(
		WorldData.has_player_city()
		and CityCitizenRegistrySystem.get_current_state().citizens.size() == WorldData.STARTING_CITY_POPULATION
		and spatial_state.citizen_spatial_version
		== WorldData.STARTING_CITY_POPULATION
		and _spatial_index_matches_registry(spatial_index),
		"Founding must index all eight citizens and publish eight spatial changes."
	)
	_expect(
		is_same(CityCitizenSpatialSystem.get_current_state().citizen_ids_by_tile, spatial_index)
		and is_same(
			WorldPoliticalState
			.get_active_settlement_context()
			.get_city_citizen_spatial_state(),
			spatial_state
		),
		"The founders must land directly in the capital's spatial owner."
	)

	var version_before_repeat := spatial_state.citizen_spatial_version
	var repeated_count := WorldData.initialize_starting_city_population()
	_expect(
		repeated_count == 0
		and spatial_state.citizen_spatial_version == version_before_repeat
		and _spatial_index_matches_registry(spatial_index),
		"Repeated founding initialization must not duplicate or invalidate space."
	)

	var legacy_citizen: Dictionary = CityCitizenRegistrySystem.get_current_state().citizens[0]
	legacy_citizen.erase("city_tile_position")
	CityCitizenRegistrySystem.get_current_state().citizens[0] = legacy_citizen
	var version_before_legacy_repair := spatial_state.citizen_spatial_version
	_expect(
		CityCitizenSpatialSystem.ensure_city_citizen_spatial_state(city_world) == 1
		and CityCitizenRegistrySystem.get_current_state().citizens[0].get("city_tile_position") is Vector2i
		and spatial_state.citizen_spatial_version
		== version_before_legacy_repair + 1
		and _spatial_index_matches_registry(spatial_index),
		"Legacy position repair must rebuild membership and invalidate once."
	)
	var version_before_clean_ensure := spatial_state.citizen_spatial_version
	_expect(
		CityCitizenSpatialSystem.ensure_city_citizen_spatial_state(city_world) == 0
		and spatial_state.citizen_spatial_version
		== version_before_clean_ensure,
		"A clean spatial ensure must not publish a false change."
	)


func _test_legacy_backend_conversion_adopts_state() -> void:
	WorldData.reset_runtime_session_state()
	var culture := WorldData.create_culture("Citizen Spatial Legacy Culture")
	var culture_id := int(culture.get("id", -1))
	var polity := WorldPoliticalState.create_polity({
		"name": "Citizen Spatial Legacy Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var legacy_city := _create_city(
		"Citizen Spatial Legacy City",
		int(polity.get("id", -1)),
		Vector2i(2, 2),
		SettlementSimulationContext.BACKEND_LEGACY_CITY_WORLD_DATA
	)
	_expect(
		not legacy_city.is_empty()
		and WorldPoliticalState.set_active_settlement(
			int(legacy_city.get("id", -1))
		),
		"The fixture must activate a legacy-backed City."
	)
	if legacy_city.is_empty():
		return

	WorldData.add_city_citizen(
		"",
		Vector2i(3, 3),
		WorldData.CITY_CITIZEN_SEX_MALE,
		culture_id
	)
	WorldData.add_city_citizen(
		"",
		Vector2i(3, 3),
		WorldData.CITY_CITIZEN_SEX_FEMALE,
		culture_id
	)
	var legacy_state := (
		CityCitizenSpatialSystem.get_current_state()
	)
	var legacy_index: Dictionary = legacy_state.citizen_ids_by_tile
	var legacy_city_id := int(legacy_city["id"])
	_expect(
		WorldPoliticalState.set_settlement_simulation_backend(
			legacy_city_id,
			SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
		),
		"Legacy spatial data must exist before backend conversion."
	)
	var converted_state = WorldPoliticalState.get_city_simulation_state(
		legacy_city_id
	)
	_expect(
		converted_state is CitySettlementSimulationState
		and is_same(converted_state.citizen_spatial_state, legacy_state)
		and is_same(
			converted_state.citizen_spatial_state.citizen_ids_by_tile,
			legacy_index
		)
		and legacy_index.get(Vector2i(3, 3), []) == [1, 2]
		and legacy_state.citizen_spatial_version == 2,
		"Legacy conversion must transfer the exact two-field spatial owner."
	)

	var fallback_city := _create_city(
		"Second Citizen Spatial Legacy City",
		int(polity.get("id", -1)),
		Vector2i(6, 6),
		SettlementSimulationContext.BACKEND_LEGACY_CITY_WORLD_DATA
	)
	_expect(
		not fallback_city.is_empty()
		and WorldPoliticalState.set_active_settlement(
			int(fallback_city.get("id", -1))
		),
		"A second legacy-backed City must use the rotated fallback."
	)
	var rotated_fallback := (
		CityCitizenSpatialSystem.get_current_state()
	)
	_expect(
		not is_same(rotated_fallback, legacy_state)
		and rotated_fallback.citizen_ids_by_tile.is_empty()
		and rotated_fallback.citizen_spatial_version == 0,
		"Conversion must rotate a fresh pre-context spatial fallback."
	)
	_expect(
		WorldPoliticalState.set_active_settlement(legacy_city_id)
		and is_same(
			CityCitizenSpatialSystem.get_current_state(),
			legacy_state
		)
		and is_same(CityCitizenSpatialSystem.get_current_state().citizen_ids_by_tile, legacy_index),
		"The converted City must retain its exact spatial owner after switching."
	)

	WorldData.reset_runtime_session_state()
	var reset_state := (
		CityCitizenSpatialSystem.get_current_state()
	)
	_expect(
		WorldPoliticalState.settlement_city_state_by_id.is_empty()
		and not is_same(reset_state, legacy_state)
		and reset_state.citizen_ids_by_tile.is_empty()
		and reset_state.citizen_spatial_version == 0,
		"A runtime reset must discard every settlement spatial owner."
	)


func _spatial_index_matches_registry(spatial_index: Dictionary) -> bool:
	var expected_by_tile: Dictionary = {}
	for raw_citizen in CityCitizenRegistrySystem.get_current_state().citizens:
		if not raw_citizen is Dictionary:
			return false
		var citizen: Dictionary = raw_citizen
		var citizen_id := int(citizen.get("id", -1))
		var raw_tile = citizen.get(
			"city_tile_position",
			WorldData.INVALID_CITY_TILE_POSITION
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
