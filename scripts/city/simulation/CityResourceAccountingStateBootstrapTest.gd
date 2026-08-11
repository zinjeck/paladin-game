extends Node

const TEST_CITY_NAME := "Resource Bootstrap City"
const TEST_CULTURE_NAME := "Resource Bootstrap Culture"

var failure_count: int = 0


func _ready() -> void:
	_test_state_defaults()
	_test_founding_adopts_pre_context_state()
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City resource-accounting bootstrap test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City resource-accounting bootstrap test passed.")
	get_tree().quit(0)


func _test_state_defaults() -> void:
	var state := CityResourceAccountingState.new()
	_expect(
		state.owned_resource_amount_cache.is_empty()
		and state.owned_resource_amount_cache_container_version == -1
		and state.container_version == 0
		and state.public_storage_version == 0,
		"A new accounting state must have clean cache and version defaults."
	)


func _test_founding_adopts_pre_context_state() -> void:
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()

	var world := _make_world(8, 8, 94_001)
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

	var bootstrap_cache: Dictionary = {
		WorldData.RESOURCE_FISH: 12,
		WorldData.RESOURCE_LUMBER: 4,
	}
	var bootstrap_state := (
		CityResourceAccountingSystem.get_current_state()
	)
	bootstrap_state.owned_resource_amount_cache = bootstrap_cache
	bootstrap_state.owned_resource_amount_cache_container_version = 7
	bootstrap_state.container_version = 7
	bootstrap_state.public_storage_version = 5
	_expect(
		bootstrap_state is CityResourceAccountingState
		and is_same(
			bootstrap_state.owned_resource_amount_cache,
			bootstrap_cache
		)
		and is_same(
			CityResourceAccountingSystem.get_current_state().owned_resource_amount_cache,
			bootstrap_cache
		),
		"Pre-context accounting values must live in one exact unbound state."
	)

	_expect(
		WorldPoliticalState.synchronize_foundation_with_world_data(),
		"Founding must establish a City settlement context."
	)
	var capital_state = WorldPoliticalState.get_active_city_simulation_state()
	var context = WorldPoliticalState.get_active_settlement_context()
	_expect(
		capital_state is CitySettlementSimulationState
		and is_same(
			capital_state.resource_accounting_state,
			bootstrap_state
		)
		and is_same(
			capital_state.resource_accounting_state.owned_resource_amount_cache,
			bootstrap_cache
		),
		"The founding City must adopt the exact pre-context accounting owner."
	)
	_expect(
		context != null
		and is_same(
			context.get_city_resource_accounting_state(),
			bootstrap_state
		)
		and is_same(
			CityResourceAccountingSystem.get_current_state(),
			bootstrap_state
		)
		and CityResourceAccountingSystem.get_current_state().owned_resource_amount_cache_container_version == 7
		and CityResourceAccountingSystem.get_city_container_version() == 7
		and CityResourceAccountingSystem.get_city_public_storage_version() == 5,
		"Context and system access must resolve the adopted accounting state."
	)

	_expect(
		WorldPoliticalState.synchronize_foundation_with_world_data()
		and is_same(
			CityResourceAccountingSystem.get_current_state(),
			bootstrap_state
		)
		and is_same(
			CityResourceAccountingSystem.get_current_state().owned_resource_amount_cache,
			bootstrap_cache
		),
		"Repeated founding synchronization must not replace accounting state."
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
	push_error("City resource-accounting bootstrap test: " + message)
