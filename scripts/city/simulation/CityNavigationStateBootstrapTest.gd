extends Node

const TEST_CITY_NAME := "Navigation Bootstrap"
const TEST_CULTURE_NAME := "Navigation Culture"

var failure_count: int = 0


func _ready() -> void:
	_test_state_defaults()
	_test_pre_context_state_adoption()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City navigation state bootstrap test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City navigation state bootstrap test passed.")
	get_tree().quit(0)


func _test_state_defaults() -> void:
	var state_a := CityNavigationState.new()
	var state_b := CityNavigationState.new()
	_expect(
		state_a.object_access_tile_cache.is_empty(),
		"A new navigation owner must start with an empty access cache."
	)
	_expect(
		not is_same(state_a, state_b)
		and not is_same(
			state_a.object_access_tile_cache,
			state_b.object_access_tile_cache
		),
		"Separate navigation owners must never share cache dictionaries."
	)


func _test_pre_context_state_adoption() -> void:
	WorldData.reset_runtime_session_state()
	var world := _make_world(8, 8, 72_001)
	if not _lock_founding_world(world, "Pre-context"):
		return

	var bootstrap_state := CityNavigationSystem.get_current_state()
	bootstrap_state.object_access_tile_cache[77] = {
		"world_instance_id": 123,
		"access_tiles": [Vector2i(1, 2)],
	}

	_expect(
		WorldPoliticalState.synchronize_foundation_with_world_data(),
		"Founding must establish a City settlement context."
	)
	var capital_state = WorldPoliticalState.get_active_city_simulation_state()
	_expect(
		capital_state is CitySettlementSimulationState
		and is_same(capital_state.navigation_state, bootstrap_state)
		and is_same(CityNavigationSystem.get_current_state(), bootstrap_state)
		and bootstrap_state.object_access_tile_cache.has(77),
		"The founding City must adopt the exact pre-context navigation owner."
	)
	_expect(
		WorldPoliticalState.synchronize_foundation_with_world_data()
		and is_same(CityNavigationSystem.get_current_state(), bootstrap_state),
		"Repeated synchronization must not replace the navigation owner."
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
	push_error("City navigation state bootstrap test: " + message)
