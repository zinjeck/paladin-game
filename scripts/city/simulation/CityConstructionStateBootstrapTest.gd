extends Node

const TEST_CITY_NAME := "Construction Bootstrap City"
const TEST_CULTURE_NAME := "Construction Bootstrap Culture"

var failure_count: int = 0


func _ready() -> void:
	_run_bootstrap_test()
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City construction-state bootstrap test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City construction-state bootstrap test passed.")
	get_tree().quit(0)


func _run_bootstrap_test() -> void:
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()

	var world := _make_world(8, 8, 85_021)
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

	WorldData.city_construction_sites = [
		{
			"id": 17,
			"test_owner": "bootstrap",
		},
	]
	WorldData.city_construction_site_index_by_id = {17: 0}
	WorldData.city_construction_site_id_by_tile = {Vector2i(3, 3): 17}
	WorldData.next_city_construction_site_id = 18
	WorldData.city_construction_version = 5

	var bootstrap_state = WorldPoliticalState.get_current_city_construction_state()
	_expect(
		bootstrap_state is CityConstructionState,
		"Pre-context construction must live in the unbound CityConstructionState."
	)

	_expect(
		WorldPoliticalState.synchronize_foundation_with_world_data(),
		"Founding must establish a city settlement context."
	)

	var capital_state = WorldPoliticalState.get_active_city_simulation_state()
	_expect(
		capital_state is CitySettlementSimulationState,
		"Founding capital must own city simulation state."
	)
	if capital_state == null:
		return

	_expect(
		capital_state.construction_state == bootstrap_state,
		"Founding City must adopt the exact pre-context construction-state object."
	)
	_expect(
		str(capital_state.construction_state.construction_sites[0].get("test_owner", ""))
		== "bootstrap"
		and capital_state.construction_state.next_construction_site_id == 18
		and capital_state.construction_state.construction_version == 5,
		"Bootstrap construction state must survive context establishment."
	)
	_expect(
		WorldData.city_construction_sites == capital_state.construction_state.construction_sites
		and WorldData.next_city_construction_site_id == 18
		and WorldData.city_construction_version == 5,
		"WorldData compatibility properties must resolve to the active City's construction state."
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
	push_error("City construction-state bootstrap test: " + message)
