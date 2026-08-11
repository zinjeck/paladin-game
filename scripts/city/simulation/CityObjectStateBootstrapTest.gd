extends Node

const TEST_CITY_NAME := "Object Bootstrap City"
const TEST_CULTURE_NAME := "Object Bootstrap Culture"

var failure_count: int = 0


func _ready() -> void:
	_test_state_defaults()
	_test_founding_adopts_pre_context_state()
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
	CityObjectSystem.get_current_state().objects = objects
	CityObjectSystem.get_current_state().object_index_by_id = object_index_by_id
	CityObjectSystem.get_current_state().occupied_tiles = occupied_tiles
	CityObjectSystem.get_current_state().next_object_id = 18
	CityObjectSystem.get_current_state().object_version = 5

	var bootstrap_state := CityObjectSystem.get_current_state()
	_expect(
		bootstrap_state is CityObjectState,
		"Pre-context objects must live in the unbound CityObjectState."
	)
	_expect(
		is_same(CityObjectSystem.get_current_state().objects, bootstrap_state.objects)
		and is_same(
			CityObjectSystem.get_current_state().object_index_by_id,
			bootstrap_state.object_index_by_id
		)
		and is_same(
			CityObjectSystem.get_current_state().occupied_tiles,
			bootstrap_state.occupied_tiles
		),
		"CityObjectSystem collections must preserve exact state identity."
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
			CityObjectSystem.get_current_state(),
			bootstrap_state
		)
		and is_same(CityObjectSystem.get_current_state().objects, bootstrap_state.objects)
		and CityObjectSystem.get_current_state().next_object_id == 18
		and CityObjectSystem.get_current_state().object_version == 5,
		"Context and CityObjectSystem access must resolve the adopted state."
	)

	_expect(
		WorldPoliticalState.synchronize_foundation_with_world_data()
		and is_same(
			CityObjectSystem.get_current_state(),
			bootstrap_state
		)
		and CityObjectSystem.get_current_state().objects.size() == 1,
		"Repeated founding synchronization must not replace or duplicate object state."
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
