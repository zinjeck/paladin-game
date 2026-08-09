extends Node

const TEST_CITY_NAME := "Object Bootstrap City"
const TEST_CULTURE_NAME := "Object Bootstrap Culture"

var failure_count: int = 0


func _ready() -> void:
	_test_state_defaults()
	_test_founding_adopts_pre_context_state()
	_test_legacy_backend_conversion_adopts_state()
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City object-state bootstrap test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City object-state bootstrap test passed.")
	get_tree().quit(0)


func _test_state_defaults() -> void:
	var state := CityObjectState.new()
	_expect(
		state.objects.is_empty()
		and state.object_index_by_id.is_empty()
		and state.occupied_tiles.is_empty()
		and state.next_object_id == 1
		and state.object_version == 0,
		"A new CityObjectState must have clean registry defaults."
	)


func _test_founding_adopts_pre_context_state() -> void:
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()

	var world := _make_world(8, 8, 87_001)
	var locked := WorldData.lock_world_save({
		"source_world": world,
		"region_top_left": Vector2i(1, 1),
		"region_center": Vector2i(2, 2),
		"region_size": 3,
		"world_scene_path": "res://scenes/GameSession.tscn",
		"city_scene_path": "res://scenes/CityScreen.tscn",
		"city_name": TEST_CITY_NAME,
		"culture_name": TEST_CULTURE_NAME,
	})
	_expect(locked, "Fixture must lock a founding world.")
	if not locked:
		return

	var tile := Vector2i(3, 3)
	var objects: Array = [{
		"id": 17,
		"type": WorldData.CITY_OBJECT_ROAD,
		"tiles": [tile],
		"owner": "bootstrap",
	}]
	var object_index_by_id: Dictionary = {17: 0}
	var occupied_tiles: Dictionary = {tile: 17}
	WorldData.city_objects = objects
	WorldData.city_object_index_by_id = object_index_by_id
	WorldData.city_occupied_tiles = occupied_tiles
	WorldData.next_city_object_id = 18
	WorldData.city_object_version = 5

	var bootstrap_state = WorldPoliticalState.get_current_city_object_state()
	_expect(
		bootstrap_state is CityObjectState,
		"Pre-context objects must live in the unbound CityObjectState."
	)
	_expect(
		is_same(WorldData.city_objects, bootstrap_state.objects)
		and is_same(
			WorldData.city_object_index_by_id,
			bootstrap_state.object_index_by_id
		)
		and is_same(
			WorldData.city_occupied_tiles,
			bootstrap_state.occupied_tiles
		),
		"WorldData compatibility collections must preserve exact identity."
	)

	_expect(
		WorldPoliticalState.synchronize_foundation_with_world_data(),
		"Founding must establish a city settlement context."
	)
	var capital_state = WorldPoliticalState.get_active_city_simulation_state()
	var context = WorldPoliticalState.get_active_settlement_context()
	_expect(
		capital_state is CitySettlementSimulationState
		and is_same(capital_state.object_state, bootstrap_state),
		"The founding City must adopt the exact pre-context object state."
	)
	_expect(
		context != null
		and is_same(context.get_city_object_state(), bootstrap_state)
		and is_same(
			WorldPoliticalState.get_current_city_object_state(),
			bootstrap_state
		)
		and is_same(WorldData.city_objects, bootstrap_state.objects)
		and WorldData.next_city_object_id == 18
		and WorldData.city_object_version == 5,
		"Context and compatibility access must resolve the adopted state."
	)

	_expect(
		WorldPoliticalState.synchronize_foundation_with_world_data()
		and is_same(
			WorldPoliticalState.get_current_city_object_state(),
			bootstrap_state
		)
		and WorldData.city_objects.size() == 1,
		"Repeated founding synchronization must not replace or duplicate object state."
	)


func _test_legacy_backend_conversion_adopts_state() -> void:
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()

	var culture := WorldData.create_culture("Object Legacy Culture")
	var polity := WorldPoliticalState.create_polity({
		"name": "Object Legacy Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": int(culture.get("id", -1)),
	})
	var legacy_city := WorldPoliticalState.create_settlement({
		"name": "Object Legacy City",
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": int(polity.get("id", -1)),
		"world_region_top_left": Vector2i(2, 2),
		"world_region_center": Vector2i(2, 2),
		"world_region_size": 1,
		"simulation_backend_kind": (
			SettlementSimulationContext.BACKEND_LEGACY_CITY_WORLD_DATA
		),
	})
	_expect(
		not legacy_city.is_empty()
		and WorldPoliticalState.set_active_settlement(int(legacy_city.get("id", -1))),
		"Fixture must activate a legacy-backed City."
	)
	if legacy_city.is_empty():
		return

	var tile := Vector2i(4, 4)
	WorldData.city_objects = [{
		"id": 29,
		"type": WorldData.CITY_OBJECT_ROAD,
		"tiles": [tile],
		"owner": "legacy",
	}]
	WorldData.city_object_index_by_id = {29: 0}
	WorldData.city_occupied_tiles = {tile: 29}
	WorldData.next_city_object_id = 30
	WorldData.city_object_version = 8
	var legacy_object_state = WorldPoliticalState.get_current_city_object_state()
	var legacy_objects: Array = WorldData.city_objects
	var legacy_index: Dictionary = WorldData.city_object_index_by_id
	var legacy_occupancy: Dictionary = WorldData.city_occupied_tiles

	var city_id := int(legacy_city["id"])
	_expect(
		WorldPoliticalState.set_settlement_simulation_backend(
			city_id,
			SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
		),
		"The active legacy City must convert to instance-owned state."
	)
	var converted_state = WorldPoliticalState.get_city_simulation_state(city_id)
	_expect(
		converted_state is CitySettlementSimulationState
		and is_same(converted_state.object_state, legacy_object_state),
		"Legacy conversion must adopt the exact unbound object state."
	)
	_expect(
		is_same(WorldData.city_objects, legacy_objects)
		and is_same(WorldData.city_object_index_by_id, legacy_index)
		and is_same(WorldData.city_occupied_tiles, legacy_occupancy)
		and WorldData.next_city_object_id == 30
		and WorldData.city_object_version == 8,
		"Legacy conversion must preserve all five object-state values."
	)
	var fallback_city := WorldPoliticalState.create_settlement({
		"name": "Second Object Legacy City",
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": int(polity.get("id", -1)),
		"world_region_top_left": Vector2i(6, 6),
		"world_region_center": Vector2i(6, 6),
		"world_region_size": 1,
		"simulation_backend_kind": (
			SettlementSimulationContext.BACKEND_LEGACY_CITY_WORLD_DATA
		),
	})
	_expect(
		not fallback_city.is_empty()
		and WorldPoliticalState.set_active_settlement(
			int(fallback_city.get("id", -1))
		),
		"Fixture must activate a second legacy-backed City."
	)
	var rotated_fallback = WorldPoliticalState.get_current_city_object_state()
	_expect(
		not is_same(rotated_fallback, legacy_object_state)
		and rotated_fallback.objects.is_empty()
		and rotated_fallback.object_index_by_id.is_empty()
		and rotated_fallback.occupied_tiles.is_empty()
		and rotated_fallback.next_object_id == 1
		and rotated_fallback.object_version == 0,
		"Legacy conversion must rotate to a fresh pre-context fallback state."
	)
	_expect(
		WorldPoliticalState.set_active_settlement(city_id)
		and is_same(
			WorldPoliticalState.get_current_city_object_state(),
			legacy_object_state
		)
		and WorldData.city_objects.size() == 1,
		"The converted City must retain its adopted state after fallback use."
	)

	WorldData.reset_runtime_session_state()
	var reset_state = WorldPoliticalState.get_current_city_object_state()
	_expect(
		WorldPoliticalState.settlement_city_state_by_id.is_empty()
		and not is_same(reset_state, legacy_object_state)
		and reset_state.objects.is_empty()
		and reset_state.object_index_by_id.is_empty()
		and reset_state.occupied_tiles.is_empty()
		and reset_state.next_object_id == 1
		and reset_state.object_version == 0,
		"A global runtime reset must discard every settlement-owned object state."
	)


func _make_world(width: int, height: int, seed: int) -> WorldData:
	var world := WorldData.new()
	world.setup(width, height, seed)
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
	push_error("City object-state bootstrap test: " + message)
